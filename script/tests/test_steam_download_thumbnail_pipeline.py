"""Real video extraction, coalescing, request-local identity and disk/memory/failure returns."""
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
IMAGE_SUPPORT = CORE / 'SteamWorkshopPreviewImageSupport.swift'
SOURCES = [SHARED / 'DecodedThumbnailMemoryCache.swift', SHARED / 'GridThumbnailDecoder.swift',
           SHARED / 'ThumbnailCache.swift', CORE / 'SteamWorkshopPreviewRequestCoordinator.swift', IMAGE_SUPPORT]
CHECKS = {'startsWithoutDiskCache', 'coldRequestsComplete', 'coldVideosProduceRealFrames',
          'sameKeySharesOneGeneration', 'differentKeyGeneratesIndependently',
          'memoryWarmReturnsWithoutGeneration', 'badMediaCompletesWithFailure',
          'negativeCacheAvoidsAnotherGeneration', 'missingMediaCompletesWithoutGeneration',
          'generationStaysSerialAndOffMain', 'allCompletionsOnceOnMain', 'realJPEGsPersisted',
          'coldSaveUsesCapturedKeys', 'oneFreshIdentityPerPresentRequest', 'missingSkipsIdentityRead',
          'knownColorSeedRejectsUniformFrames'}
DISK_CHECKS = {'diskHitProducesRealFramesWithoutGeneration', 'diskHitUsesCapturedKeys',
               'diskThenMemoryUsesSameImage', 'diskRequestsEachReadOneFreshIdentity',
               'allDiskCompletionsOnceOnMain'}
MUTATION_CHECKS = {'generationUsesCapturedKeyAfterMetadataChange', 'coldSaveRetainsCapturedKey',
                   'nextMtimeRequestUsesFreshIdentity', 'sameSizeMtimeReplacementUsesFreshInode',
                   'sameInodeMtimeSizeChangeUsesFreshIdentity', 'everyRevisionPersistsRealJPEG',
                   'mutationRequestsEachReadOneFreshIdentity', 'allMutationCompletionsOnceOnMain'}


def observed_pipeline(source):
    """Observe actual owner entries in a task copy; algorithms remain unchanged."""
    transforms = {
        '    private func createThumbnail(for videoURL: URL) -> NSImage? {':
            '        GenerationProbe.shared.begin(videoURL)\n        defer { GenerationProbe.shared.end() }',
        '    private func cacheKey(for videoURL: URL) -> String {':
            '        CacheKeyProbe.shared.keyCall(videoURL)',
        '        let key = cacheKey(for: videoURL)':
            '        CacheKeyProbe.shared.capture(key, for: videoURL)',
    }
    for entry, observation in transforms.items():
        if source.count(entry) != 1:
            raise ValueError('actual pipeline observation entry must be unique: ' + entry)
        source = source.replace(entry, entry + '\n' + observation, 1)
    return source


def observed_image_support(source):
    entry = 'nonisolated func steamWorkshopLocalPreviewCacheKey(for url: URL) -> String {'
    if source.count(entry) != 1:
        raise ValueError('actual metadata-key entry must be unique')
    return source.replace(entry, entry + '\n    CacheKeyProbe.shared.metadataCall(url)', 1)


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
                '-i', 'testsrc2=size=512x288:rate=2', '-t', '2', '-c:v', 'libx264',
                '-pix_fmt', 'yuv420p', '-crf', '20', '-preset', 'fast', '-threads', '1', str(clip)],
                capture_output=True, text=True, timeout=15)
            save('ffmpeg.log', generate.stdout + generate.stderr)
            self.assertEqual(generate.returncode, 0, generate.stdout + generate.stderr)
            shutil.copyfile(clip, work / 'second.mp4')
            shutil.copyfile(clip, work / 'changing.mp4')
            (work / 'bad.mp4').write_bytes(b'owned invalid movie fixture')
            home = work / 'home'
            home.mkdir()
            (work / 'tmp').mkdir()
            environment = dict(os.environ, HOME=str(home), CFFIXED_USER_HOME=str(home),
                               TMPDIR=str(work / 'tmp') + '/')
            source = work / PIPELINE.name
            source.write_text(observed_pipeline(PIPELINE.read_text()))
            support = work / IMAGE_SUPPORT.name
            support.write_text(observed_image_support(IMAGE_SUPPORT.read_text()))
            harness = work / 'Harness.swift'
            harness.write_text(HARNESS)
            binary = work / 'steam-video'
            save('ObservedPipeline.swift', source.read_text())
            save('ObservedImageSupport.swift', support.read_text())
            save('Harness.swift', HARNESS)
            save('inputs.json', json.dumps({'inputs': inputs,
                'clipSHA256': hashlib.sha256(clip.read_bytes()).hexdigest(),
                'transforms': ['actual generation leaf begin/defer end', 'actual key and metadata API counts',
                               'capture actual generateThumbnail request key after its original computation'],
                'scope': __doc__}, indent=2) + '\n')
            compilation_sources = [support if path == IMAGE_SUPPORT else path for path in SOURCES]
            build = subprocess.run(['xcrun', 'swiftc', *SWIFT_ISOLATION_FLAGS, '-warnings-as-errors', '-parse-as-library',
                *map(str, compilation_sources), str(source), str(harness),
                '-module-cache-path', str(work / 'modules'), '-o', str(binary)],
                capture_output=True, text=True, timeout=150, env=environment)
            save('compile.log', build.stdout + build.stderr)
            self.assertEqual(build.returncode, 0, build.stdout + build.stderr)
            self.assertEqual(inputs, fingerprints())
            for mode, checks in [('cold', CHECKS), ('disk', DISK_CHECKS), ('mutation', MUTATION_CHECKS)]:
                result = subprocess.run([str(binary), str(work), mode], env=environment,
                    capture_output=True, text=True, timeout=45)
                prefix = '' if mode == 'cold' else mode + '-'
                save(prefix + 'stdout.log', result.stdout)
                save(prefix + 'stderr.log', result.stderr)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                facts = json.loads(result.stdout)
                save(prefix + 'results.json', json.dumps(facts, indent=2) + '\n')
                self.assertEqual(set(facts['checks']), checks)
                for name, passed in facts['checks'].items():
                    with self.subTest(mode=mode, name=name):
                        self.assertTrue(passed, facts)
                self.assertEqual(inputs, fingerprints())


HARNESS = r'''
import AppKit
import Foundation
import Darwin

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

nonisolated final class CacheKeyProbe: @unchecked Sendable {
    static let shared = CacheKeyProbe()
    private let lock = NSLock()
    private var keys: [String: Int] = [:], metadata: [String: Int] = [:]
    private var admitted: [String: [String]] = [:]
    func keyCall(_ url: URL) { lock.lock(); defer { lock.unlock() }; keys[url.path, default: 0] += 1 }
    func metadataCall(_ url: URL) { lock.lock(); defer { lock.unlock() }; metadata[url.path, default: 0] += 1 }
    func capture(_ key: String, for url: URL) {
        lock.lock(); defer { lock.unlock() }; admitted[url.path, default: []].append(key)
    }
    func captures(_ url: URL) -> [String] { lock.lock(); defer { lock.unlock() }; return admitted[url.path] ?? [] }
    func hasQueries(_ expected: Int, for url: URL) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return keys[url.path, default: 0] == expected && metadata[url.path, default: 0] == expected
            && admitted[url.path, default: []].count == expected
    }
    var metrics: [String: Any] {
        lock.lock(); defer { lock.unlock() }
        return ["keyAPICalls": keys, "metadataAPICalls": metadata, "capturedKeys": admitted]
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
    func allOnceOnMain(expectedCount: Int) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return counts.count == expectedCount && counts.values.allSatisfy { $0 == 1 } && allMain
    }
}

@main struct SteamDownloadThumbnailChecks {
    @MainActor static func main() throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[1])
        let mode = CommandLine.arguments[2]
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
        let keys = CacheKeyProbe.shared
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
            guard let image, let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
                  cg.width == 512, cg.height == 288,
                  !steamWorkshopPreviewImageLooksSuspicious(image) else { return false }
            // This is the known colorful testsrc2 seed, not a rule for authored wallpapers.
            // A decoder-produced uniform green bitmap has the right dimensions and is not near-black.
            var pixels = [UInt8](repeating: 0, count: 16 * 9 * 4)
            return pixels.withUnsafeMutableBytes { bytes in
                guard let context = CGContext(data: bytes.baseAddress, width: 16, height: 9,
                    bitsPerComponent: 8, bytesPerRow: 16 * 4, space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue)
                    else { return false }
                context.draw(cg, in: CGRect(x: 0, y: 0, width: 16, height: 9))
                let values = bytes.bindMemory(to: UInt8.self)
                return [0, 2].allSatisfy { channel in
                    let samples = stride(from: channel, to: values.count, by: 4).map { Int(values[$0]) }
                    return (samples.max() ?? 0) - (samples.min() ?? 0) > 40
                }
            }
        }
        func uniformFrame(_ color: CGColor) -> NSImage {
            let context = CGContext(data: nil, width: 512, height: 288, bitsPerComponent: 8,
                bytesPerRow: 512 * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.setFillColor(color)
            context.fill(CGRect(x: 0, y: 0, width: 512, height: 288))
            return NSImage(cgImage: context.makeImage()!, size: NSSize(width: 512, height: 288))
        }
        func outputURL(_ key: String) -> URL { disk.appendingPathComponent(key).appendingPathExtension("jpg") }
        func emit() throws {
            print(String(data: try JSONSerialization.data(withJSONObject: ["checks": checks,
                "mode": mode, "generation": generations.metrics, "identity": keys.metrics], options: [.sortedKeys]), encoding: .utf8)!)
        }
        if mode == "disk" {
            // A new process has no in-memory entries; use the previous cold run's
            // real JPEGs and leave any unexpected AV generation free to finish.
            generations.firstEntryGate.signal()
            request("disk-first", first)
            request("disk-second", second)
            checks["diskHitProducesRealFramesWithoutGeneration"] = pump {
                completions.count("disk-first") == 1 && completions.count("disk-second") == 1
            } && realFrame(completions.image("disk-first")) && realFrame(completions.image("disk-second"))
                && generations.metrics["totalStarts"] == 0
            let firstKey = keys.captures(first).first ?? ""
            let secondKey = keys.captures(second).first ?? ""
            checks["diskHitUsesCapturedKeys"] = !firstKey.isEmpty && !secondKey.isEmpty
                && realFrame(NSImage(contentsOf: outputURL(firstKey))) && realFrame(NSImage(contentsOf: outputURL(secondKey)))
            request("disk-memory", first)
            checks["diskThenMemoryUsesSameImage"] = pump { completions.count("disk-memory") == 1 }
                && completions.image("disk-first") != nil
                && completions.image("disk-first") === completions.image("disk-memory")
                && generations.metrics["totalStarts"] == 0
            checks["diskRequestsEachReadOneFreshIdentity"] = keys.hasQueries(2, for: first) && keys.hasQueries(1, for: second)
            checks["allDiskCompletionsOnceOnMain"] = completions.allOnceOnMain(expectedCount: 3)
            try emit()
            return
        }
        if mode == "mutation" {
            let changing = root.appendingPathComponent("changing.mp4")
            request("captured", changing)
            let entered = pump { generations.count(changing) == 1 }
            let captured = keys.captures(changing).first ?? ""
            let original = try FileManager.default.attributesOfItem(atPath: changing.path)
            let changedDate = (original[.modificationDate] as! Date).addingTimeInterval(120)
            try FileManager.default.setAttributes([.modificationDate: changedDate], ofItemAtPath: changing.path)
            generations.firstEntryGate.signal()
            checks["generationUsesCapturedKeyAfterMetadataChange"] = entered
                && pump { completions.count("captured") == 1 } && realFrame(completions.image("captured"))
                && keys.hasQueries(1, for: changing)
            checks["coldSaveRetainsCapturedKey"] = !captured.isEmpty && realFrame(NSImage(contentsOf: outputURL(captured)))

            request("mtime", changing)
            checks["nextMtimeRequestUsesFreshIdentity"] = pump { completions.count("mtime") == 1 }
                && realFrame(completions.image("mtime")) && keys.captures(changing).count == 2
                && keys.captures(changing).last != captured && generations.count(changing) == 2

            let beforeReplacement = try FileManager.default.attributesOfItem(atPath: changing.path)
            let sameDate = beforeReplacement[.modificationDate] as! Date
            let replacement = root.appendingPathComponent("replacement-\(UUID().uuidString).mp4")
            defer { try? FileManager.default.removeItem(at: replacement) }
            try FileManager.default.copyItem(at: changing, to: replacement)
            try FileManager.default.setAttributes([.modificationDate: sameDate], ofItemAtPath: replacement.path)
            precondition(rename(replacement.path, changing.path) == 0, "owned replacement rename failed")
            let replaced = try FileManager.default.attributesOfItem(atPath: changing.path)
            request("inode", changing)
            checks["sameSizeMtimeReplacementUsesFreshInode"] = pump { completions.count("inode") == 1 }
                && realFrame(completions.image("inode")) && keys.captures(changing).count == 3
                && Set(keys.captures(changing)).count == 3 && generations.count(changing) == 3
                && (beforeReplacement[.size] as! NSNumber) == (replaced[.size] as! NSNumber)
                && (beforeReplacement[.modificationDate] as! Date) == (replaced[.modificationDate] as! Date)
                && (beforeReplacement[.systemFileNumber] as! NSNumber) != (replaced[.systemFileNumber] as! NSNumber)

            let handle = try FileHandle(forWritingTo: changing)
            _ = try handle.seekToEnd()
            // A valid ISO BMFF free box changes size while retaining a decodable movie.
            try handle.write(contentsOf: Data([0, 0, 0, 16, 102, 114, 101, 101, 0, 0, 0, 0, 0, 0, 0, 0]))
            try handle.close()
            try FileManager.default.setAttributes([.modificationDate: sameDate], ofItemAtPath: changing.path)
            let resized = try FileManager.default.attributesOfItem(atPath: changing.path)
            request("size", changing)
            checks["sameInodeMtimeSizeChangeUsesFreshIdentity"] = pump { completions.count("size") == 1 }
                && realFrame(completions.image("size")) && keys.captures(changing).count == 4
                && Set(keys.captures(changing)).count == 4 && generations.count(changing) == 4
                && (resized[.size] as! NSNumber).uint64Value == (replaced[.size] as! NSNumber).uint64Value + 16
                && (resized[.systemFileNumber] as! NSNumber) == (replaced[.systemFileNumber] as! NSNumber)
                && (resized[.modificationDate] as! Date) == (replaced[.modificationDate] as! Date)
            checks["everyRevisionPersistsRealJPEG"] = keys.captures(changing).count == 4
                && keys.captures(changing).allSatisfy { realFrame(NSImage(contentsOf: outputURL($0))) }
            checks["mutationRequestsEachReadOneFreshIdentity"] = keys.hasQueries(4, for: changing)
            checks["allMutationCompletionsOnceOnMain"] = completions.allOnceOnMain(expectedCount: 4)
            try emit()
            return
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
        checks["knownColorSeedRejectsUniformFrames"] = !realFrame(uniformFrame(CGColor(red: 0, green: 1, blue: 0, alpha: 1)))
            && !realFrame(uniformFrame(CGColor(gray: 0.5, alpha: 1)))
        checks["sameKeySharesOneGeneration"] = generations.count(first) == 1
            && completions.image("first") != nil && completions.image("first") === completions.image("same-key")
        checks["differentKeyGeneratesIndependently"] = generations.count(second) == 1
            && completions.image("second") != nil && completions.image("second") !== completions.image("first")
        request("warm", first)
        checks["memoryWarmReturnsWithoutGeneration"] = pump { completions.count("warm") == 1 }
            && generations.count(first) == 1 && completions.image("first") != nil
            && completions.image("first") === completions.image("warm")
        request("bad", bad)
        checks["badMediaCompletesWithFailure"] = pump { completions.count("bad") == 1 }
            && completions.image("bad") == nil && generations.count(bad) == 1
        request("negative-cache", bad)
        checks["negativeCacheAvoidsAnotherGeneration"] = pump { completions.count("negative-cache") == 1 }
            && completions.image("negative-cache") == nil && generations.count(bad) == 1
        request("missing", missing)
        checks["missingMediaCompletesWithoutGeneration"] = pump { completions.count("missing") == 1 }
            && completions.image("missing") == nil && generations.count(missing) == 0
        var drained = false
        DispatchQueue.main.async { drained = true }
        _ = pump { drained }
        checks["generationStaysSerialAndOffMain"] = generations.serialAndOffMain
            && generations.metrics["totalStarts"] == 3
        checks["allCompletionsOnceOnMain"] = completions.allOnceOnMain(expectedCount: 7)
        let persisted = try FileManager.default.contentsOfDirectory(at: disk, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "jpg" }
        checks["realJPEGsPersisted"] = persisted.count == 2
            && persisted.allSatisfy { realFrame(NSImage(contentsOf: $0)) }
        let firstKeys = keys.captures(first), secondKeys = keys.captures(second)
        checks["coldSaveUsesCapturedKeys"] = firstKeys.count == 3 && secondKeys.count == 1
            && firstKeys.first == firstKeys.last
            && realFrame(NSImage(contentsOf: outputURL(firstKeys.first ?? "")))
            && realFrame(NSImage(contentsOf: outputURL(secondKeys.first ?? "")))
        checks["oneFreshIdentityPerPresentRequest"] = keys.hasQueries(3, for: first)
            && keys.hasQueries(1, for: second) && keys.hasQueries(2, for: bad)
        checks["missingSkipsIdentityRead"] = keys.hasQueries(0, for: missing)
        try emit()
    }
}
'''


if __name__ == '__main__':
    unittest.main()
