"""Real cold-video extraction, coalescing, serial generation and cache/failure returns."""
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

from script.tests.test_thumbnail_return_reuse import SWIFT_ISOLATION_FLAGS

ROOT = Path(__file__).resolve().parents[2]
CORE = ROOT / 'MyWallpaperX/Modules/SteamWorkshop/Core'
SHARED = ROOT / 'MyWallpaperX/Shared/UI'
PIPELINE = CORE / 'SteamWorkshopDownloadThumbnailPipeline.swift'
SOURCES = [SHARED / 'DecodedThumbnailMemoryCache.swift', SHARED / 'GridThumbnailDecoder.swift',
           SHARED / 'ThumbnailCache.swift', CORE / 'SteamWorkshopPreviewRequestCoordinator.swift',
           CORE / 'SteamWorkshopPreviewImageSupport.swift']
CHECKS = {'startsWithoutDiskCache', 'coldRequestsComplete', 'coldVideosProduceRealFrames',
          'sameKeySharesOneGeneration', 'differentKeyGeneratesIndependently',
          'memoryWarmReturnsWithoutGeneration', 'badMediaCompletesWithFailure',
          'negativeCacheAvoidsAnotherGeneration', 'missingMediaCompletesWithoutGeneration',
          'generationStaysSerialAndOffMain', 'allCompletionsOnceOnMain', 'realJPEGsPersisted'}


@unittest.skipUnless(sys.platform == 'darwin' and shutil.which('ffmpeg'),
                     'macOS and ffmpeg fixture generator required')
class SteamDownloadThumbnailPipelineTests(unittest.TestCase):
    def test_real_cold_generation_coalescing_cache_and_failure(self):
        with tempfile.TemporaryDirectory(prefix='mwx-steam-video-', dir='/private/tmp') as directory:
            work = Path(directory)
            proof = os.environ.get('MWX_STEAM_DOWNLOAD_THUMBNAIL_PROOF_DIR')
            if proof:
                proof = Path(proof)
                proof.mkdir(parents=True, exist_ok=True)

            def save(name, text):
                if proof:
                    (proof / name).write_text(text)

            def fingerprints():
                return {str(path): hashlib.sha256(path.read_bytes()).hexdigest()
                        for path in [PIPELINE, *SOURCES, Path(__file__)]}

            inputs = fingerprints()
            clip = work / 'first.mp4'
            generate = subprocess.run(['ffmpeg', '-nostdin', '-v', 'error', '-f', 'lavfi',
                '-i', 'testsrc2=size=512x288:rate=2', '-t', '2', '-c:v', 'mpeg4',
                '-q:v', '3', '-threads', '1', str(clip)], capture_output=True, text=True, timeout=15)
            save('ffmpeg.log', generate.stdout + generate.stderr)
            self.assertEqual(generate.returncode, 0, generate.stdout + generate.stderr)
            shutil.copyfile(clip, work / 'second.mp4')
            (work / 'bad.mp4').write_bytes(b'owned invalid movie fixture')
            home = work / 'home'
            home.mkdir()
            original = PIPELINE.read_text()
            entry = '    private func createThumbnail(for videoURL: URL) -> NSImage? {'
            self.assertEqual(original.count(entry), 1)
            # Only observe/gate the entry; the complete queue, AVFoundation,
            # cache, locking, persistence and completion algorithms stay real.
            observed = original.replace(entry, entry + '\n'
                '        GenerationProbe.shared.begin(videoURL)\n'
                '        defer { GenerationProbe.shared.end() }', 1)
            source = work / PIPELINE.name
            source.write_text(observed)
            harness = work / 'Harness.swift'
            harness.write_text(HARNESS)
            binary = work / 'steam-video'
            save('inputs.json', json.dumps({'inputs': inputs,
                'clipSHA256': hashlib.sha256(clip.read_bytes()).hexdigest(),
                'transforms': ['createThumbnail entry begin/defer end observation; first-entry leaf gate'],
                'scope': __doc__}, indent=2) + '\n')
            build = subprocess.run(['xcrun', 'swiftc', *SWIFT_ISOLATION_FLAGS, '-warnings-as-errors', '-parse-as-library',
                *map(str, SOURCES), str(source), str(harness),
                '-module-cache-path', str(work / 'modules'), '-o', str(binary)],
                capture_output=True, text=True, timeout=150)
            save('compile.log', build.stdout + build.stderr)
            self.assertEqual(build.returncode, 0, build.stdout + build.stderr)
            self.assertEqual(inputs, fingerprints())
            result = subprocess.run([str(binary), str(work)],
                env=dict(os.environ, HOME=str(home), CFFIXED_USER_HOME=str(home)),
                capture_output=True, text=True, timeout=45)
            save('stdout.log', result.stdout)
            save('stderr.log', result.stderr)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            facts = json.loads(result.stdout)
            save('results.json', json.dumps(facts, indent=2) + '\n')
            self.assertEqual(set(facts['checks']), CHECKS)
            for name, passed in facts['checks'].items():
                with self.subTest(name=name):
                    self.assertTrue(passed, facts)
            self.assertEqual(inputs, fingerprints())


HARNESS = r'''
import AppKit
import Foundation

nonisolated final class GenerationProbe: @unchecked Sendable {
    static let shared = GenerationProbe()
    let firstEntryGate = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var starts: [String: Int] = [:]
    private var active = 0
    private var maximum = 0
    private var allOffMain = true
    func begin(_ url: URL) {
        lock.lock()
        let first = starts.isEmpty
        starts[url.path, default: 0] += 1
        active += 1; maximum = max(maximum, active)
        allOffMain = allOffMain && !Thread.isMainThread
        lock.unlock()
        if first { precondition(firstEntryGate.wait(timeout: .now() + 15) == .success, "entry gate timed out") }
    }
    func end() { lock.lock(); active -= 1; lock.unlock() }
    func count(_ url: URL) -> Int { lock.lock(); defer { lock.unlock() }; return starts[url.path, default: 0] }
    var serialAndOffMain: Bool {
        lock.lock(); defer { lock.unlock() }
        return active == 0 && maximum == 1 && allOffMain
    }
    var metrics: [String: Int] {
        lock.lock(); defer { lock.unlock() }
        return ["active": active, "maximumActive": maximum, "totalStarts": starts.values.reduce(0, +)]
    }
}

nonisolated final class CompletionProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var counts: [String: Int] = [:]
    private var images: [String: NSImage] = [:]
    private var allMain = true
    func record(_ name: String, _ image: NSImage?) {
        lock.lock(); defer { lock.unlock() }
        counts[name, default: 0] += 1
        images[name] = image
        allMain = allMain && Thread.isMainThread
    }
    func count(_ name: String) -> Int { lock.lock(); defer { lock.unlock() }; return counts[name, default: 0] }
    func image(_ name: String) -> NSImage? { lock.lock(); defer { lock.unlock() }; return images[name] }
    var allOnceOnMain: Bool {
        lock.lock(); defer { lock.unlock() }
        return counts.count == 7 && counts.values.allSatisfy { $0 == 1 } && allMain
    }
}

@main struct SteamDownloadThumbnailChecks {
    @MainActor static func main() throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[1])
        let home = root.appendingPathComponent("home", isDirectory: true)
        precondition(FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL.path == home.standardizedFileURL.path,
                     "fixture HOME must isolate the real disk cache")
        let first = root.appendingPathComponent("first.mp4")
        let second = root.appendingPathComponent("second.mp4")
        let bad = root.appendingPathComponent("bad.mp4")
        let missing = root.appendingPathComponent("missing.mp4")
        let disk = home.appendingPathComponent("Library/Caches/MyWallpaperX/SteamWorkshop/GeneratedDownloadThumbnails")
        let pipeline = SteamWorkshopDownloadThumbnailPipeline.shared
        let generations = GenerationProbe.shared
        let completions = CompletionProbe()
        var checks: [String: Bool] = [:]
        func pump(_ condition: () -> Bool) -> Bool {
            let deadline = Date().addingTimeInterval(10)
            while !condition(), Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.005)) }
            return condition()
        }
        func request(_ name: String, _ url: URL) {
            pipeline.generateThumbnail(for: url) { completions.record(name, $0) }
        }
        func realFrame(_ image: NSImage?) -> Bool {
            guard let image, let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return false }
            return cg.width == 512 && cg.height == 288 && !steamWorkshopPreviewImageLooksSuspicious(image)
        }
        checks["startsWithoutDiskCache"] = !FileManager.default.fileExists(atPath: disk.path)
        request("first", first)
        // Hold real extraction at its leaf until the same-key consumer and a
        // different-key request have both entered the real inFlight/queue path.
        let entered = pump { generations.count(first) == 1 }
        request("same-key", first)
        request("second", second)
        generations.firstEntryGate.signal()
        checks["coldRequestsComplete"] = entered && pump {
            completions.count("first") == 1 && completions.count("same-key") == 1 && completions.count("second") == 1
        }
        checks["coldVideosProduceRealFrames"] = realFrame(completions.image("first")) && realFrame(completions.image("second"))
        checks["sameKeySharesOneGeneration"] = generations.count(first) == 1
            && completions.image("first") != nil && completions.image("first") === completions.image("same-key")
        checks["differentKeyGeneratesIndependently"] = generations.count(second) == 1
            && completions.image("second") != nil && completions.image("second") !== completions.image("first")
        let cached = pipeline.cachedThumbnail(for: first)
        request("warm", first)
        checks["memoryWarmReturnsWithoutGeneration"] = pump { completions.count("warm") == 1 }
            && generations.count(first) == 1 && cached != nil
            && cached === completions.image("first") && cached === completions.image("warm")
        request("bad", bad)
        checks["badMediaCompletesWithFailure"] = pump { completions.count("bad") == 1 }
            && completions.image("bad") == nil && generations.count(bad) == 1
        request("negative-cache", bad)
        checks["negativeCacheAvoidsAnotherGeneration"] = pump { completions.count("negative-cache") == 1 }
            && completions.image("negative-cache") == nil && generations.count(bad) == 1
            && pipeline.cachedThumbnail(for: bad) == nil
        request("missing", missing)
        checks["missingMediaCompletesWithoutGeneration"] = pump { completions.count("missing") == 1 }
            && completions.image("missing") == nil && generations.count(missing) == 0
        var drained = false
        DispatchQueue.main.async { drained = true }
        _ = pump { drained }
        checks["generationStaysSerialAndOffMain"] = generations.serialAndOffMain
            && generations.metrics["totalStarts"] == 3
        checks["allCompletionsOnceOnMain"] = completions.allOnceOnMain
        let persisted = try FileManager.default.contentsOfDirectory(at: disk, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "jpg" }
        checks["realJPEGsPersisted"] = persisted.count == 2
            && persisted.allSatisfy { realFrame(NSImage(contentsOf: $0)) }
        print(String(data: try JSONSerialization.data(withJSONObject: ["checks": checks,
            "generation": generations.metrics], options: [.sortedKeys]), encoding: .utf8)!)
    }
}
'''


if __name__ == '__main__':
    unittest.main()
