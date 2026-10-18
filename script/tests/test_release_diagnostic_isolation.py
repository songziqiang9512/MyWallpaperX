"""Compile the real diagnostic owners in both configurations, then execute them.

This checks the exclusion boundary rather than assuming an optimized Debug App
represents distribution. Full App playback/IPC still requires runtime evidence.
"""
from pathlib import Path
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]
SCENE = ROOT / "MyWallpaperX/Core/SteamWorkshopScene"
SOURCES = [
    SCENE / "Diagnostics/ScenePerformanceCounterHub.swift",
    SCENE / "Diagnostics/SceneGPUCensus.swift",
    SCENE / "Diagnostics/SceneSignposts.swift",
    SCENE / "Diagnostics/SceneGPUCompletionTelemetry.swift",
    SCENE / "Compilation/Material/SceneResolvedMaterialExecutionCapabilityVariant+CompileProfile.swift",
    ROOT / "WallpaperDaemonSources/Daemon/Core/DaemonLogging.swift",
]
HARNESS = r'''
import Foundation
@main enum Probe {
    static func main() {
        var evaluated = false
        daemonLog({ evaluated = true; return "diagnostic payload" }())
        let observation = SceneGPUCompletionTelemetry(phase: "test")
        observation.recordFailure(layerID: 1)
#if DEBUG
        precondition(evaluated)
        let counters = ScenePerformanceCounterHub.shared
        counters.bump(.frameAttempts)
        precondition(counters.snapshot()[.frameAttempts] == 1)
        SceneResolvedMaterialVariantCompileProfile.reset()
        print("debug-observation-pass")
#else
        precondition(!evaluated, "Release must not evaluate a log payload")
        precondition(MemoryLayout<SceneGPUCompletionTelemetry>.size == 0,
                     "Release must not allocate GPU observation state")
        print("release-exclusion-pass")
#endif
    }
}
'''


class ReleaseDiagnosticIsolationTests(unittest.TestCase):
    def compile_and_run(self, debug: bool) -> tuple[str, str]:
        with tempfile.TemporaryDirectory(prefix="mwx-diagnostic-exclusion-") as raw:
            directory = Path(raw)
            harness = directory / "Harness.swift"
            harness.write_text(HARNESS)
            binary = directory / "probe"
            command = ["xcrun", "swiftc", "-O", "-whole-module-optimization"]
            if debug:
                command += ["-D", "DEBUG"]
            command += ["-module-cache-path", str(directory / "modules")]
            command += [str(path) for path in SOURCES]
            if not debug:
                command += [str(SCENE / "Diagnostics" / name) for name in [
                    "SceneFramePerformanceTelemetry.swift", "SceneEffectExecutionFrameTrace.swift",
                    "SceneEffectExecutionTelemetry.swift", "SceneGraphExecutionTelemetry.swift",
                    "SceneDiagnostics.swift",
                ]]
            command += [str(harness), "-o", str(binary)]
            compiled = subprocess.run(command, capture_output=True, text=True)
            self.assertEqual(compiled.returncode, 0, compiled.stderr)
            executed = subprocess.run([str(binary)], capture_output=True, text=True)
            self.assertEqual(executed.returncode, 0, executed.stdout + executed.stderr)
            symbols = subprocess.run(
                ["nm", str(binary)], capture_output=True, text=True, check=True
            ).stdout
            return executed.stdout + executed.stderr, symbols

    def test_release_excludes_counter_signpost_and_gpu_observation_work(self):
        output, symbols = self.compile_and_run(False)
        self.assertIn("release-exclusion-pass", output)
        self.assertNotIn("diagnostic payload", output)
        for owner in ["ScenePerformanceCounterHub", "SceneGPUCensus", "SceneSignpost",
                      "SceneResolvedMaterialVariantCompileProfile", "SceneDiagnosticsBuilder",
                      "recordRouteTransition", "recordParticleSubmission"]:
            self.assertNotIn(owner, symbols, owner)
        self.assertNotIn("NSLock", symbols)
        self.assertNotIn("os_signpost", symbols)

    def test_debug_keeps_real_counters_and_lazy_log_delivery(self):
        output, _ = self.compile_and_run(True)
        self.assertIn("debug-observation-pass", output)
        self.assertIn("diagnostic payload", output)

    def test_web_release_rejects_development_commands(self):
        source = (ROOT / "MyWallpaperX/Core/SteamWorkshopWeb/Process/WebDaemonProtocol.swift").read_text()
        def declaration(signature):
            start = source.index(signature)
            opening = source.index("{", start)
            depth, end = 1, opening + 1
            while depth:
                depth += (source[end] == "{") - (source[end] == "}")
                end += 1
            return source[start:end]
        command = declaration("nonisolated enum WebDaemonCommand:")
        stubs = """
        import Foundation
        struct WebDaemonLaunch: Codable {}
        struct WebDaemonMediaSnapshot: Codable {}
        struct WebDaemonActivationRequest: Codable {}
        struct WebDaemonActivationIdentity: Codable {}
        enum WallpaperEngine {
            enum WebWallpaperRuntimeCommand: Codable { case pushAudioSpectrum([Double]) }
        }
        """
        harness = r'''
        @main enum Check {
            static func main() throws {
                let decoder = JSONDecoder()
                let inspect = Data(#"{"inspect":{}}"#.utf8)
                let developmentAccepted = (try? decoder.decode(WebDaemonCommand.self, from: inspect)) != nil
        #if DEBUG
                precondition(developmentAccepted)
        #else
                precondition(!developmentAccepted)
        #endif
                guard case .shutdown = try decoder.decode(WebDaemonCommand.self,
                    from: Data(#"{"shutdown":{}}"#.utf8)) else { fatalError("product command lost") }
                print("protocol-isolation-pass")
            }
        }
        '''
        for debug in [False, True]:
            with self.subTest(debug=debug), tempfile.TemporaryDirectory(prefix="mwx-web-protocol-") as raw:
                directory = Path(raw)
                swift = directory / "Harness.swift"
                swift.write_text(stubs + command + harness)
                binary = directory / "probe"
                flags = ["-D", "DEBUG"] if debug else []
                compiled = subprocess.run(
                    ["xcrun", "swiftc", "-parse-as-library", "-O", *flags, str(swift), "-o", str(binary)],
                    capture_output=True, text=True,
                )
                self.assertEqual(compiled.returncode, 0, compiled.stderr)
                executed = subprocess.run([str(binary)], capture_output=True, text=True)
                self.assertEqual(executed.returncode, 0, executed.stderr)
                self.assertIn("protocol-isolation-pass", executed.stdout)


    def test_release_web_admission_keeps_entry_checks_without_sample_scan(self):
        # Compile the real Release service owner. The leaf doubles supply only
        # record/descriptor facts; local file existence and caching are real.
        harness = r'''
        import Foundation
        enum Dependency { case none, missing(String) }
        struct SteamWorkshopDownloadRecord {
            var id = "wallpaper"
            var dependencyStatus = Dependency.none
            var isDependencyBackedWeb = false
            var hasPlayableDependencyWebHost = false
            var webEntryURL: URL?
            var folderURL: URL
        }
        struct Descriptor { let resolvedEntryURL: URL }
        struct Eligibility { let signature: String; let isValid: Bool }
        final class SteamWorkshopService {
            var webLaunchEligibilityCache: [String: Eligibility] = [:]
            var generation = 0
            var descriptorCalls = 0
            var declared: String?
            var lastWebPlaybackFailureRecordID: String?
            var lastWebPlaybackFailureMessage: String?
            var lastWebPlaybackFailurePath: String?
            func webProjectDescriptorSignature(for record: SteamWorkshopDownloadRecord) -> String {
                String(generation)
            }
            func resolvedWebProjectDescriptor(for record: SteamWorkshopDownloadRecord) -> Descriptor? {
                descriptorCalls += 1
                return record.webEntryURL.map(Descriptor.init)
            }
            func declaredWebEntryRelativePath(for record: SteamWorkshopDownloadRecord) -> String? { declared }
        }
        @main enum Check {
            static func main() throws {
                let folder = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
                let entry = folder.appendingPathComponent("index.html")
                try Data("<html></html>".utf8).write(to: entry)
                var record = SteamWorkshopDownloadRecord(webEntryURL: entry, folderURL: folder)
                let service = SteamWorkshopService()
                precondition(service.webLaunchEntryIsValid(for: record))
                let calls = service.descriptorCalls
                precondition(service.webLaunchEntryIsValid(for: record) && service.descriptorCalls == calls)
                service.declared = "missing.html"; service.generation += 1
                precondition(!service.webLaunchEntryIsValid(for: record), "missing declared entry admitted")
                record.isDependencyBackedWeb = true; service.generation += 1
                precondition(service.webLaunchEntryIsValid(for: record), "dependency-host fallback rejected")
                record.isDependencyBackedWeb = false; service.declared = nil
                record.webEntryURL = nil; service.generation += 1
                precondition(!service.webLaunchEntryIsValid(for: record), "missing resolved entry admitted")
                record.webEntryURL = entry; try FileManager.default.removeItem(at: entry)
                service.generation += 1
                precondition(!service.webLaunchEntryIsValid(for: record), "deleted file admitted")
                record.isDependencyBackedWeb = true; record.dependencyStatus = .missing("host")
                service.generation += 1
                precondition(service.webLaunchEntryIsValid(for: record), "dependency precondition became a fatal issue")
                service.lastWebPlaybackFailureRecordID = record.id
                service.lastWebPlaybackFailureMessage = "playback error"
                precondition(service.webPlaybackFailureMessage(for: record) == "playback error")
                print("release-web-admission-pass")
            }
        }
        '''
        with tempfile.TemporaryDirectory(prefix="mwx-release-web-admission-") as raw:
            directory = Path(raw)
            main = directory / "Harness.swift"; main.write_text(harness)
            binary = directory / "check"
            source = ROOT / "MyWallpaperX/Modules/SteamWorkshop/Web/Core/SteamWorkshopService+WebValidation.swift"
            compiled = subprocess.run(["xcrun", "swiftc", "-parse-as-library", str(source), str(main),
                                       "-module-cache-path", str(directory / "modules"), "-o", str(binary)],
                                      capture_output=True, text=True)
            self.assertEqual(compiled.returncode, 0, compiled.stderr)
            run = subprocess.run([str(binary), str(directory)], capture_output=True, text=True)
            self.assertEqual(run.returncode, 0, run.stdout + run.stderr)
            self.assertIn("release-web-admission-pass", run.stdout)
            symbols = subprocess.run(["nm", str(binary)], capture_output=True, text=True, check=True).stdout
            self.assertNotIn("webValidationReport", symbols)


if __name__ == "__main__":
    unittest.main()
