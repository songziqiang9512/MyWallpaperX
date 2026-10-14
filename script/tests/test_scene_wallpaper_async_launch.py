#!/usr/bin/env python3

from __future__ import annotations

from script.tests.source_family import read_source_family
import json
import subprocess
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
LAUNCH = (
    ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Runtime/Session/SceneDesktopWallpaperHost+Launch.swift"
)
HOST = (
    ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Runtime/Session/SceneDesktopWallpaperHost.swift"
)
FRAME_DRIVER = (
    ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Runtime/Session/SceneDesktopWallpaperSession+FrameDriver.swift"
)
SURFACE_TEARDOWN = (
    ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Runtime/Session/SceneDesktopWallpaperSession+SurfaceTeardown.swift"
)
COORDINATOR = ROOT / "MyWallpaperX" / "App" / "MainWindowCoordinator+PlaybackRouting.swift"
DEBUG_RUNNER = ROOT / "MyWallpaperX" / "App" / "Debug" / "DebugScenePlaybackRunner.swift"
INSPECTION = (
    ROOT
    / "MyWallpaperX"
    / "Modules"
    / "SteamWorkshop"
    / "UI"
    / "SteamWorkshopSceneInspectionController.swift"
)
SPOT_LIGHT_RUNTIME = (
    ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Lighting/SceneSpotLightRuntime.swift"
)
PREPARED_DEVICE_RESOURCES = (
    ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Runtime/Session/ScenePreparedDeviceResources.swift"
)
METAL_VIEW = (
    ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Frame/SceneMetalView.swift"
)
METAL_RENDERER = (
    ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Frame/SceneMetalRenderer.swift"
)
RENDERER_DIAGNOSTICS = (
    ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Frame/SceneMetalRenderer+Diagnostics.swift"
)
RENDERER_EXECUTION_EVIDENCE = (
    ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Frame/SceneMetalRenderer+ExecutionEvidence.swift"
)
TEXT_LOADER = (
    ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Text/SceneTextTextureLoader.swift"
)
DEFERRED_BASE_IMAGES = (
    ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Runtime/Session/SceneDesktopWallpaperHost+DeferredBaseImages.swift"
)
SHADER_REACHABILITY = (
    ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Compilation/Material/SceneResolvedMaterialShaderSchema+Reachability.swift"
)
VARIANT_CACHE = (
    ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Compilation/Material/SceneResolvedMaterialExecutionCapabilityVariant.swift"
)
def function_body(source: str, signature: str) -> str:
    start = source.index(signature)
    opening = source.index("{", start)
    depth = 0
    for index in range(opening, len(source)):
        if source[index] == "{":
            depth += 1
        elif source[index] == "}":
            depth -= 1
            if depth == 0:
                return source[opening : index + 1]
    raise AssertionError(f"unterminated function: {signature}")


class SceneWallpaperAsyncLaunchTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.launch = LAUNCH.read_text(encoding="utf-8")
        cls.host = HOST.read_text(encoding="utf-8")
        cls.frame_driver = (
            FRAME_DRIVER.read_text(encoding="utf-8")
            + "\n"
            + SURFACE_TEARDOWN.read_text(encoding="utf-8")
        )
        cls.coordinator = COORDINATOR.read_text(encoding="utf-8")
        cls.debug_runner = DEBUG_RUNNER.read_text(encoding="utf-8")
        cls.inspection = INSPECTION.read_text(encoding="utf-8")
        cls.spot_light_runtime = SPOT_LIGHT_RUNTIME.read_text(encoding="utf-8")
        cls.prepared_device_resources = PREPARED_DEVICE_RESOURCES.read_text(
            encoding="utf-8"
        )
        cls.metal_view = METAL_VIEW.read_text(encoding="utf-8")
        cls.metal_renderer = read_source_family(METAL_RENDERER)
        cls.renderer_diagnostics = RENDERER_DIAGNOSTICS.read_text(encoding="utf-8")
        cls.text_loader = TEXT_LOADER.read_text(encoding="utf-8")
        cls.deferred_base_images = DEFERRED_BASE_IMAGES.read_text(
            encoding="utf-8"
        )
        cls.shader_reachability = SHADER_REACHABILITY.read_text(encoding="utf-8")
        cls.variant_cache = VARIANT_CACHE.read_text(encoding="utf-8")

    def test_product_request_uses_daemon_command_and_switches_on_launch_event(self) -> None:
        observer = function_body(
            self.coordinator,
            "private static func observeSteamWorkshopSceneReadyToRender()",
        )
        self.assertIn("PlaybackCommandMultiplexer.shared.dispatch(", observer)
        self.assertIn(".loadScene(.init(", observer)
        self.assertIn("to: .scene", observer)
        self.assertNotIn("SceneDesktopWallpaperHost.shared", observer)
        state_observer = function_body(
            self.coordinator,
            "private static func observeSceneWallpaperLaunchState()",
        )
        launched = state_observer[state_observer.index("case .launched:") :]
        self.assertIn("postWallpaperRuntimeWillSwitch", launched)
        self.assertIn("WallpaperEngine.shared.stopPlayback()", launched)

    def test_main_window_projects_central_launch_state(self) -> None:
        configure = function_body(self.coordinator, "static func configure(")
        observer = function_body(
            self.coordinator,
            "private static func observeSceneWallpaperLaunchState()",
        )
        self.assertIn("observeSceneWallpaperLaunchState()", configure)
        self.assertIn("sceneWallpaperLaunchStateDidChange", observer)
        self.assertIn("SteamWorkshopService.shared.statusMessage", observer)
        self.assertIn("当前壁纸会继续播放", observer)
        self.assertIn("正在等待首帧显示", observer)



    def test_progress_uses_truthful_indeterminate_stages(self) -> None:
        prepare = function_body(self.launch, "private static func prepareLaunch(")
        self.assertIn(".preparingModel", prepare)
        self.assertIn("SceneRuntimeModelBuilder().build", prepare)
        self.assertNotIn("SceneDiagnosticsBuilder", prepare)
        self.assertNotIn("model.diagnostics", prepare)
        self.assertIn(".preparingPrograms", prepare)
        self.assertIn(".preparingResources", prepare)
        self.assertNotIn("percent", prepare.lower())

    def test_launch_envelope_projects_only_relevant_availability_masks(self) -> None:
        """The envelope must share the bounded mask projection with reachability."""
        self.assertIn(
            ".launchAvailabilityMasks(template)",
            self.variant_cache,
        )
        self.assertNotIn(
            "for rawAvailability in UInt16(0) ... UInt16(UInt8.max)",
            self.variant_cache,
        )
        self.assertIn("readinessComboSlotMask(template)", self.shader_reachability)
        self.assertIn("Array(UInt8.min ... UInt8.max)", self.shader_reachability)

    def test_launch_availability_projection_preserves_fail_closed_fallback(self) -> None:
        """Unknown or out-of-range schema metadata keeps exhaustive rejection semantics."""
        projection = function_body(
            self.shader_reachability,
            "nonisolated static func launchAvailabilityMasks(",
        )
        self.assertIn("guard let readinessSlots = readinessComboSlotMask(template)", projection)
        self.assertIn("guard (0 ..< 8).contains(slot.index)", projection)
        self.assertGreaterEqual(projection.count("Array(UInt8.min ... UInt8.max)"), 2)
        self.assertIn("availability & ~relevantSlots == 0", projection)



    def test_first_surface_runtime_warmup_overlaps_program_compilation(self) -> None:
        prepare = function_body(self.launch, "private static func prepareLaunch(")
        make_runtime = function_body(
            self.launch, "func makeResolvedMaterialRuntime()"
        )
        self.assertIn("ScenePreparedFirstSurfaceRuntimeTask(", prepare)
        self.assertIn("firstSurfaceRuntimePreparation.start()", prepare)
        self.assertIn("firstSurfaceRuntimePreparation.value()", prepare)
        self.assertLess(
            prepare.index("firstSurfaceRuntimePreparation.start()"),
            prepare.index("SceneScriptQuickJSProgramCandidate.compile("),
        )
        self.assertIn("preparedFirstSurfaceRuntime.take() ??", make_runtime)
        self.assertIn(
            "final class ScenePreparedFirstSurfaceRuntime",
            self.prepared_device_resources,
        )
        self.assertIn("private let lock = NSLock()", self.prepared_device_resources)
        self.assertIn("runtime = nil", self.prepared_device_resources)

    def test_optional_spot_light_pipeline_is_not_built_without_authored_plans(self) -> None:
        self.assertIn(
            "pipeline: @autoclosure () -> SceneSpotLightPipeline?",
            self.spot_light_runtime,
        )
        self.assertIn(
            "self.pipeline = plansByLayerID.isEmpty ? nil : pipeline()",
            self.spot_light_runtime,
        )

    def test_product_launch_does_not_construct_startup_diagnostics(self) -> None:
        load = function_body(self.metal_view, "func loadImageLayers(")
        install = function_body(
            RENDERER_EXECUTION_EVIDENCE.read_text(encoding="utf-8"),
            "func installResolvedMaterialExecutionEvidence()",
        )
        runtime_report = function_body(
            self.renderer_diagnostics,
            "func runtimeReportLines()",
        )

        self.assertIn(
            "SceneStartupReportBuffer(enabled: logURL != nil)",
            load,
        )
        self.assertIn("@autoclosure () -> String", self.metal_view)
        self.assertIn("@autoclosure () -> [String]", self.metal_view)
        self.assertIn("if report.isEnabled", load)
        self.assertIn("recordsDiagnostics: report.isEnabled", load)
        self.assertGreaterEqual(self.text_loader.count("if recordsDiagnostics"), 2)
        self.assertIn("renderer.installResolvedMaterialExecutionEvidence()", load)
        self.assertIn("installExecutionEvidence(", install)
        self.assertNotIn("installExecutionEvidence(", runtime_report)


    def test_detail_projects_progress_and_user_cancellation(self) -> None:
        self.assertIn("sceneWallpaperLaunchStateDidChange", self.inspection)
        self.assertIn("launchState.isInProgress", self.inspection)
        self.assertIn("当前壁纸会继续播放", self.inspection)
        self.assertIn(".cancelSceneLaunch(recordID: record.id)", self.inspection)
        self.assertIn("to: .scene", self.inspection)

    def test_host_stop_cancels_pending_preparation(self) -> None:
        stop = function_body(self.host, "func stop()")
        self.assertIn("cancelPendingLaunch()", stop)

    def test_surface_teardown_reports_after_surfaces_are_cleared(self) -> None:
        teardown = function_body(self.frame_driver, "func teardownSurfaces(")
        clear_index = teardown.index("surfaces.removeAll()")
        log_index = teardown.index('phase=surface-teardown')
        self.assertGreater(
            log_index,
            clear_index,
            "teardown evidence must report the post-close surface count",
        )
        self.assertIn("surfaces.count", teardown[log_index:])

    def test_debug_smoke_exercises_the_async_product_entrypoint(self) -> None:
        self.assertIn("--mwx-debug-scene-async-launch-smoke", self.debug_runner)
        self.assertIn("runtimeHost.requestLaunch(", self.debug_runner)
        self.assertIn("phase=async-launch-request-returned", self.debug_runner)
        self.assertIn("phase=async-launch-ready", self.debug_runner)

    def test_property_edit_restarts_pending_full_intent_before_active_commit(self) -> None:
        source = property_launch_harness(self.host)
        with tempfile.TemporaryDirectory(prefix="mwx-property-launch-") as directory:
            path = Path(directory)
            harness = path / "Harness.swift"
            harness.write_text(source)
            binary = path / "harness"
            compilation = subprocess.run([
                "xcrun", "swiftc", "-swift-version", "5", "-parse-as-library",
                str(LAUNCH.with_name("SceneDesktopWallpaperLaunchModels.swift")),
                str(harness), "-o", str(binary),
            ], capture_output=True, text=True, timeout=60)
            self.assertEqual(compilation.returncode, 0, compilation.stderr)
            result = subprocess.run([str(binary)], capture_output=True, text=True, timeout=15)
            self.assertEqual(result.returncode, 0, result.stderr)
            output = json.loads(result.stdout)
            print(result.stdout, end="")
            for name, passed in output["facts"].items():
                with self.subTest(name=name, trace=output["trace"]):
                    self.assertTrue(passed)


def property_launch_harness(host_source: str) -> str:
    """Execute real Host arbitration/epochs and Client merge/ack, with leaf doubles.

    Preparation deliberately finishes after cancellation. No parser, renderer,
    transport process or GPU is created; session acceptance is a controlled leaf.
    """
    launch = LAUNCH.read_text()
    ipc = ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Runtime/IPC"

    def method(source: str, signature: str) -> str:
        start = source.index(signature)
        opening = source.index("{", start)
        return source[start:opening] + function_body(source, signature)

    host_methods = "\n".join([
        method(host_source, "func applyUserPropertyValues("),
        method(launch, "func requestLaunch("),
        method(launch, "func cancelPendingLaunch("),
    ])
    client = (ipc / "SceneDaemonClient.swift").read_text()
    events = (ipc / "SceneDaemonClient+Events.swift").read_text()
    client_methods = "\n".join([
        method(client, "func requestLaunch("),
        method(client, "private func applyPropertyValues("),
        method(events, "private func handlePropertyUpdateResult("),
        method(events, "private func handleLaunchState("),
    ])
    return PROPERTY_LAUNCH_SUPPORT.replace("__HOST_METHODS__", host_methods).replace(
        "__CLIENT_METHODS__", client_methods
    )


PROPERTY_LAUNCH_SUPPORT = r'''
import Foundation

enum SceneUserPropertyValue: Equatable {
    case number(Double)
    var foundationValue: Any { if case let .number(v) = self { return v }; return 0 }
}
struct SceneRuntimeModel { let values: [String: SceneUserPropertyValue] }
struct SceneDesktopWallpaperLaunchContext {
    let values: [String: SceneUserPropertyValue]
    let generation: UInt64
}
struct SceneFirstFramePresentationRegistration { let requestID: UUID; let recordID: String? }
struct ScenePlaybackLoadRequest {
    let rootURL: URL
    var propertyOverrides: [String: SceneUserPropertyValue]
    let recordID: String?
}
enum ScenePlaybackTextureUpdateOutcome { case superseded, failed(String) }
enum SceneDaemonProtocol { static let version = 1 }

final class PreparationControl: @unchecked Sendable {
    let entered = DispatchSemaphore(value: 0), release = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var first = true
    func prepare() {
        lock.lock(); let wait = first; first = false; lock.unlock()
        if wait { entered.signal(); release.wait() }
    }
}
struct SceneTextureDecodeCacheBudget: Sendable { let control: PreparationControl }
@MainActor final class SceneDesktopWallpaperSession {
    var values: [String: SceneUserPropertyValue]
    var calls = 0
    let acceptsJ: Bool
    init(_ values: [String: SceneUserPropertyValue], acceptsJ: Bool = true) {
        self.values = values; self.acceptsJ = acceptsJ
    }
    func applyUserPropertyValues(_ replacements: [String: SceneUserPropertyValue],
        changedPropertyKeys: Set<String>, recordID: String?) -> Bool {
        calls += 1
        guard recordID == "record" else { return false }
        if changedPropertyKeys.contains("K"), replacements["K"] != values["K"] { return false }
        if changedPropertyKeys.contains("J"), !acceptsJ { return false }
        for key in changedPropertyKeys { values[key] = replacements[key] }
        return true
    }
}
@MainActor final class SceneDesktopWallpaperHost {
    struct PreparedLaunch { let context: SceneDesktopWallpaperLaunchContext; let model: SceneRuntimeModel }
    let launchPreparationQueue = DispatchQueue(label: "self-authored-launch-boundary")
    let textureDecodeCacheBudget: SceneTextureDecodeCacheBudget
    var nextLaunchRequestGeneration: UInt64 = 0, nextSceneScriptGeneration: UInt64 = 0
    var pendingLaunchCompletion: (@MainActor (Result<SceneRuntimeModel, Error>) -> Void)?
    var launchCancellation: SceneWallpaperLaunchCancellation?
    var launchState: SceneWallpaperLaunchState?
    var activeSession: SceneDesktopWallpaperSession?
    var onState: ((SceneWallpaperLaunchState) -> Void)?
    var began: [UInt64] = [], trace: [String] = []
    init(_ control: PreparationControl) { textureDecodeCacheBudget = .init(control: control) }
    nonisolated static func prepareLaunch(rootURL: URL,
        propertyOverrides: [String: SceneUserPropertyValue], userPropertyTextureURLs: [String: URL],
        requiredUserTextureKeys: Set<String>, logURL: URL?, recordID: String?,
        sceneScriptGeneration: UInt64, textureDecodeCacheBudget: SceneTextureDecodeCacheBudget,
        cancellation: SceneWallpaperLaunchCancellation?,
        progress: ((SceneWallpaperLaunchState.Phase, String) -> Void)?) throws -> PreparedLaunch {
        textureDecodeCacheBudget.control.prepare()
        // A noncooperative leaf probes the production generation guards too.
        progress?(.preparingPrograms, "controlled late preparation")
        return .init(context: .init(values: propertyOverrides, generation: sceneScriptGeneration),
                     model: .init(values: propertyOverrides))
    }
    func publishLaunchState(_ state: SceneWallpaperLaunchState) {
        launchState = state
        trace.append("\(state.phase.rawValue):\(nextLaunchRequestGeneration)")
        onState?(state)
    }
    func discardCandidate() { trace.append("discard:\(nextLaunchRequestGeneration)") }
    func beginCandidate(_ context: SceneDesktopWallpaperLaunchContext,
        firstPresentation: SceneFirstFramePresentationRegistration,
        completion: @escaping (Result<Void, Error>) -> Void) throws {
        began.append(context.generation)
        activeSession = .init(context.values)
        completion(.success(()))
    }
    func finishLaunchFailure(_ error: Error, requestID: UUID, recordID: String?,
        completion: @MainActor (Result<SceneRuntimeModel, Error>) -> Void) {
        publishLaunchState(.init(requestID: requestID, recordID: recordID,
            phase: .failed, message: error.localizedDescription))
        completion(.failure(error))
    }
    __HOST_METHODS__
}

@MainActor final class SceneDaemonClient {
    struct Lifetime { let rootURL: URL; let recordID: String? }
    let host: SceneDesktopWallpaperHost
    var activeIntent: ScenePlaybackLoadRequest?, pendingIntent: ScenePlaybackLoadRequest?
    var activeResourceLifetime: Lifetime?, pendingResourceLifetime: Lifetime?
    var activeRecordID: String?, activeRequestID: UUID?, pendingRequestID: UUID?
    var launchState: SceneWallpaperLaunchState?
    var pendingPropertyRevisions: [UInt64: String] = [:], latestTextureRevisions: [String: UInt64] = [:]
    var lastPropertyRevision: UInt64 = 0
    var warmSessionPending = false, endpointReady = true
    var restartWorkItem: DispatchWorkItem?
    var replayed: [ScenePlaybackLoadRequest] = [], completions: [Bool] = []
    init(_ host: SceneDesktopWallpaperHost) { self.host = host }
    func edit(_ values: [String: SceneUserPropertyValue], revision: UInt64) -> Bool {
        applyPropertyValues(values, revision: revision, recordID: "record")
    }
    func receive(_ state: SceneWallpaperLaunchState) {
        handleLaunchState(["phase": state.phase.rawValue, "requestID": state.requestID.uuidString,
                           "message": state.message, "recordID": state.recordID ?? ""])
    }
    func send(_ payload: [String: Any]) {
        let values = (payload["values"] as! [String: Any]).mapValues {
            SceneUserPropertyValue.number($0 as! Double)
        }
        let accepted = host.applyUserPropertyValues(values, changedPropertyKeys: Set(values.keys),
            recordID: payload["recordID"] as? String)
        handlePropertyUpdateResult(["revision": payload["revision"]!,
            "recordID": payload["recordID"]!, "accepted": accepted])
    }
    func ensureSession() -> Bool { true }
    func replayPendingIntent() {
        guard let request = pendingIntent else { return }
        replayed.append(request)
        host.requestLaunch(rootURL: request.rootURL, propertyOverrides: request.propertyOverrides,
            recordID: request.recordID) { [weak self] outcome in
            if case .success = outcome { self?.completions.append(true) }
            else { self?.completions.append(false) }
        }
    }
    func finishPendingTextureUpdates(_ outcome: ScenePlaybackTextureUpdateOutcome) {}
    func bindDeferredTextureUpdates(recordID: String?, requestID: UUID) {}
    func fallbackReplayIntent(requestID: UUID) -> ScenePlaybackLoadRequest? { nil }
    func finishTextureReload(recordID: String?, outcome: ScenePlaybackTextureUpdateOutcome) {}
    func publishFailure(code: String, message: String) { preconditionFailure(message) }
    static func unsignedInteger(_ value: Any?) -> UInt64? { value as? UInt64 }
    __CLIENT_METHODS__
}

@main enum Harness {
    @MainActor static func queueDrained(_ queue: DispatchQueue) async {
        await withCheckedContinuation { done in
            queue.async { DispatchQueue.main.async { done.resume() } }
        }
    }
    @MainActor static func main() async throws {
        var facts: [String: Bool] = [:], traces: [String: [String]] = [:]
        let initial: [String: SceneUserPropertyValue] = ["K": .number(0), "J": .number(0)]
        for kind in ["same", "hot", "structural"] {
            let control = PreparationControl()
            // Each scenario uses one serial preparation queue and one controlled first leaf.
            let runtime = SceneDesktopWallpaperHost(control)
            let session = SceneDesktopWallpaperSession(initial, acceptsJ: kind != "structural")
            runtime.activeSession = session
            let client = SceneDaemonClient(runtime)
            client.activeIntent = .init(rootURL: URL(fileURLWithPath: "/self-authored"),
                propertyOverrides: initial, recordID: "record")
            runtime.onState = { [weak client] in client?.receive($0) }
            facts[kind + "-initialDispatched"] = client.edit(["K": .number(1)], revision: 1)
            let entered = await Task.detached { control.entered.wait(timeout: .now() + 5) == .success }.value
            guard entered else { fatalError("preparation leaf not entered") }
            let oldGeneration = runtime.nextLaunchRequestGeneration
            let oldCancellation = runtime.launchCancellation!
            let oldCalls = session.calls
            let next: SceneUserPropertyValue = .number(kind == "same" ? 0 : 3)
            facts[kind + "-secondDispatched"] = client.edit(["J": next], revision: 2)
            facts[kind + "-activeNotDelegated"] = session.calls == oldCalls && session.values == initial
            facts[kind + "-fullIntentReplayed"] = client.replayed.count == 2
                && client.replayed.last?.propertyOverrides == ["K": .number(1), "J": next]
            facts[kind + "-generationCancelledAndReplaced"] = runtime.nextLaunchRequestGeneration == oldGeneration + 2
            do { try oldCancellation.check(); facts[kind + "-cancelToken"] = false }
            catch { facts[kind + "-cancelToken"] = true }
            control.release.signal()
            await queueDrained(runtime.launchPreparationQueue)
            facts[kind + "-oldCompletionCannotPublish"] = !runtime.began.contains(1)
                && !runtime.trace.contains("preparingPrograms:\(oldGeneration)")
            facts[kind + "-replacementCompletesOnce"] = runtime.began == [2]
                && client.completions == [false, true]
            facts[kind + "-latestActivated"] = runtime.activeSession?.values == ["K": .number(1), "J": next]
                && client.activeIntent?.propertyOverrides == runtime.activeSession?.values
                && client.pendingIntent == nil && runtime.launchState?.phase == .launched
            traces[kind] = runtime.trace
        }
        for phase in [SceneWallpaperLaunchState.Phase.launched, .cancelled, .failed, .stopped] {
            let host = SceneDesktopWallpaperHost(PreparationControl())
            let session = SceneDesktopWallpaperSession(initial)
            host.activeSession = session
            host.launchState = .init(requestID: UUID(), recordID: "record", phase: phase, message: "fixture")
            facts["terminal-" + phase.rawValue] = host.applyUserPropertyValues(["J": .number(0)],
                changedPropertyKeys: ["J"], recordID: "record") && session.calls == 1
                && host.nextLaunchRequestGeneration == 0
        }
        for kind in ["no-pending", "different-record", "empty"] {
            let host = SceneDesktopWallpaperHost(PreparationControl())
            let session = SceneDesktopWallpaperSession(initial)
            host.activeSession = session
            if kind != "no-pending" {
                host.launchState = .init(requestID: UUID(),
                    recordID: kind == "different-record" ? "other" : "record",
                    phase: .preparingPrograms, message: "fixture")
            }
            facts[kind + "-delegates"] = host.applyUserPropertyValues(
                kind == "empty" ? [:] : ["J": .number(3)],
                changedPropertyKeys: kind == "empty" ? [] : ["J"], recordID: "record")
                && session.calls == 1 && host.nextLaunchRequestGeneration == 0
            facts[kind + "-pendingPreserved"] = kind == "no-pending" || host.launchState?.isInProgress == true
        }
        print(String(decoding: try JSONSerialization.data(withJSONObject:
            ["facts": facts, "trace": traces], options: [.sortedKeys]), as: UTF8.self))
    }
}
'''


if __name__ == "__main__":
    unittest.main()
