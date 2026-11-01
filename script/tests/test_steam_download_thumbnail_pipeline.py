"""Real video extraction, dark-frame preference, cache returns and held invalidation cases."""
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
INVALIDATION_CHECKS = {'completedFailureStillDeduplicatesBeforeInvalidation',
    'explicitInvalidationLetsSameKeyGenerateRealFrame', 'newResultStillWarmsMemory',
    'invalidationLeavesDiskDeletionWithService', 'serviceDiskRemovalCannotLeaveWarmMemory',
    'inflightSuccessKeepsBothCallbacksOnce', 'inflightSuccessCannotRefillDisk',
    'inflightSuccessCannotRefillMemory', 'newSuccessJobCachesNormally',
    'inflightFailureStillCompletesOnce', 'inflightFailureCannotRefillNegativeCache',
    'newFailureRecoveryCachesNormally', 'invalidationKeepsCapturedIdentityCounts',
    'invalidationGenerationsStaySerialAndOffMain', 'allInvalidationCompletionsOnceOnMain'}
DARK_CHECKS = {'blackVideoKeepsDecodedFrame', 'nearBlackVideoKeepsDecodedFrame',
    'laterBrightCandidateStillWins', 'darkFallbackKeepsFirstDecodedFrame',
    'darkCandidatesKeepOriginalOrder', 'mixedCandidatesReallyStartDarkThenBright',
    'smallVideoStillFails', 'smallVideoFailureStaysNegativeCached',
    'darkMemoryHitsKeepImages', 'darkFramesPersistAsJPEG',
    'darkIdentityReadsStayFresh', 'darkGenerationsStaySerialAndOffMain', 'darkCompletionsOnceOnMain'}
DARK_DISK_CHECKS = {'darkDiskHitsKeepDecodedFrames', 'darkDiskHitsSkipAVGeneration',
    'darkDiskThenMemoryKeepsImage', 'darkDiskIdentityReadsStayFresh', 'darkDiskCompletionsOnceOnMain'}
REPAIR_CHECKS = {'invalidCacheBytesRegenerate', 'truncatedCacheFollowsActualDecode',
    'smallCacheRegenerates', 'repairKeepsSourceIdentity', 'repairOutputsDecode',
    'repairGenerationsStaySerialAndOffMain', 'repairCompletionsOnceOnMain'}


def observed_pipeline(source):
    """Observe original entries; only invalidation mode opts into a nil generation leaf."""
    transforms = {
        '    private func createThumbnail(for videoURL: URL) -> NSImage? {':
            '        GenerationProbe.shared.begin(videoURL)\n        defer { GenerationProbe.shared.end() }\n'
            '        if GenerationProbe.shared.shouldFail(videoURL) { return nil }',
        '    private func cacheKey(for videoURL: URL) -> String {':
            '        CacheKeyProbe.shared.keyCall(videoURL)',
        '        let key = cacheKey(for: videoURL)':
            '        CacheKeyProbe.shared.capture(key, for: videoURL)',
        '        return result\n':
            '        GenerationProbe.shared.frame(CMTimeGetSeconds(time), image: result)\n',
    }
    for entry, observation in transforms.items():
        if source.count(entry) != 1:
            raise ValueError('actual pipeline observation entry must be unique: ' + entry)
        if entry == '        return result\n':
            source = source.replace(entry, observation + entry, 1)
        else:
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
            for name, seed in (
                ('black.mp4', 'color=c=black:s=512x288:r=4:d=2'),
                ('near-black.mp4', "color=c=0x020202:s=512x288:r=4:d=2,drawbox=color=0x060606:t=fill:enable='gte(t,0.5)'"),
                ('mixed.mp4', "testsrc2=size=512x288:rate=4:duration=2,drawbox=color=black:t=fill:enable='gte(t,0.5)'"),
                ('small.mp4', 'color=c=white:s=2x2:r=4:d=2'),
            ):
                generated = subprocess.run(['ffmpeg', '-nostdin', '-v', 'error', '-f', 'lavfi',
                    '-i', seed, '-c:v', 'libx264', '-pix_fmt', 'yuv420p', '-crf', '18', '-preset', 'fast',
                    '-g', '1', '-keyint_min', '1', '-sc_threshold', '0', '-threads', '1', str(work / name)],
                    capture_output=True, text=True, timeout=15)
                save(name + '-ffmpeg.log', generated.stdout + generated.stderr)
                self.assertEqual(generated.returncode, 0, generated.stdout + generated.stderr)
            shutil.copyfile(clip, work / 'second.mp4')
            shutil.copyfile(clip, work / 'changing.mp4')
            for name in ('clear-failure.mp4', 'clear-flight-success.mp4', 'clear-flight-failure.mp4'):
                shutil.copyfile(clip, work / name)
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
                               'capture actual generateThumbnail request key after its original computation',
                               'invalidation mode alone can hold the generation leaf or return nil before real AV; recovery uses real AV',
                               'observe requested candidate time and the real returned CGImage without changing AV timing'],
                'scope': __doc__}, indent=2) + '\n')
            compilation_sources = [support if path == IMAGE_SUPPORT else path for path in SOURCES]
            build = subprocess.run(['xcrun', 'swiftc', *SWIFT_ISOLATION_FLAGS, '-warnings-as-errors', '-parse-as-library',
                *map(str, compilation_sources), str(source), str(harness),
                '-module-cache-path', str(work / 'modules'), '-o', str(binary)],
                capture_output=True, text=True, timeout=150, env=environment)
            save('compile.log', build.stdout + build.stderr)
            self.assertEqual(build.returncode, 0, build.stdout + build.stderr)
            self.assertEqual(inputs, fingerprints())
            for mode, checks in [('cold', CHECKS), ('disk', DISK_CHECKS), ('mutation', MUTATION_CHECKS),
                                 ('invalidation', INVALIDATION_CHECKS), ('dark', DARK_CHECKS),
                                 ('dark-disk', DARK_DISK_CHECKS), ('repair', REPAIR_CHECKS)]:
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

nonisolated final class GenerationHold: @unchecked Sendable {
    private let lock = NSLock()
    private let gate = DispatchSemaphore(value: 0)
    private var started = false
    var entered: Bool { lock.lock(); defer { lock.unlock() }; return started }
    func wait() {
        lock.lock(); started = true; lock.unlock()
        precondition(gate.wait(timeout: .now() + 15) == .success, "invalidation gate timed out")
    }
    func release() { gate.signal() }
}

nonisolated final class GenerationProbe: @unchecked Sendable {
    static let shared = GenerationProbe()
    let firstEntryGate = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var starts: [String: Int] = [:]
    private var active = 0
    private var maximum = 0
    private var allOffMain = true
    private var failures = Set<String>()
    private var holds: [String: GenerationHold] = [:]
    private var currentPath: String?
    private var frames: [String: [(seconds: Double, image: CGImage?)]] = [:]
    func begin(_ url: URL) {
        lock.lock()
        let first = starts.isEmpty
        let hold = holds.removeValue(forKey: url.path)
        starts[url.path, default: 0] += 1
        currentPath = url.path
        active += 1; maximum = max(maximum, active)
        allOffMain = allOffMain && !Thread.isMainThread
        lock.unlock()
        if first { precondition(firstEntryGate.wait(timeout: .now() + 15) == .success, "entry gate timed out") }
        hold?.wait()
    }
    func fail(_ url: URL, enabled: Bool) {
        lock.lock(); defer { lock.unlock() }
        if enabled { failures.insert(url.path) } else { failures.remove(url.path) }
    }
    func shouldFail(_ url: URL) -> Bool { lock.lock(); defer { lock.unlock() }; return failures.contains(url.path) }
    func holdNext(_ url: URL) -> GenerationHold {
        lock.lock(); defer { lock.unlock() }
        let hold = GenerationHold(); holds[url.path] = hold; return hold
    }
    func end() { lock.lock(); active -= 1; currentPath = nil; lock.unlock() }
    func frame(_ seconds: Double, image: CGImage?) {
        lock.lock(); defer { lock.unlock() }
        guard let path = currentPath else { return }
        frames[path, default: []].append((seconds, image))
    }
    func candidates(_ url: URL) -> (times: [Double], images: [CGImage?]) {
        lock.lock(); defer { lock.unlock() }
        let values = frames[url.path] ?? []
        return (values.map(\.seconds), values.map(\.image))
    }
    func count(_ url: URL) -> Int { lock.lock(); defer { lock.unlock() }; return starts[url.path, default: 0] }
    var serialAndOffMain: Bool {
        lock.lock(); defer { lock.unlock() }
        return active == 0 && maximum == 1 && allOffMain
    }
    var metrics: [String: Int] {
        lock.lock(); defer { lock.unlock() }
        return ["active": active, "maximumActive": maximum, "totalStarts": starts.values.reduce(0, +)]
    }
    var frameObservations: [String: [[String: Any]]] {
        lock.lock(); defer { lock.unlock() }
        return frames.mapValues { values in
            values.map { time, image in
                ["requestedSeconds": time, "decoded": image != nil, "width": image?.width ?? 0,
                 "height": image?.height ?? 0, "nearBlack": image.map(steamWorkshopSampledLumaIsSuspicious) ?? false]
            }
        }
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
                  !steamWorkshopSampledLumaIsSuspicious(cg) else { return false }
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
        func decodedFrame(_ image: NSImage?) -> CGImage? {
            guard let cg = image?.cgImage(forProposedRect: nil, context: nil, hints: nil),
                  cg.width == 512, cg.height == 288 else { return nil }
            return cg
        }
        func sampleRGB(_ image: CGImage?) -> [UInt8]? {
            guard let image else { return nil }
            var pixels = [UInt8](repeating: 0, count: 4)
            return pixels.withUnsafeMutableBytes { bytes in
                guard let context = CGContext(data: bytes.baseAddress, width: 1, height: 1, bitsPerComponent: 8,
                    bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
                context.draw(image, in: CGRect(x: 0, y: 0, width: 1, height: 1))
                return Array(bytes.bindMemory(to: UInt8.self).prefix(3))
            }
        }
        func darkFrame(_ image: NSImage?) -> Bool {
            decodedFrame(image).map(steamWorkshopSampledLumaIsSuspicious) ?? false
        }
        func outputURL(_ key: String) -> URL { disk.appendingPathComponent(key).appendingPathExtension("jpg") }
        func emit() throws {
            print(String(data: try JSONSerialization.data(withJSONObject: ["checks": checks,
                "mode": mode, "generation": generations.metrics, "identity": keys.metrics,
                "frameCandidates": generations.frameObservations], options: [.sortedKeys]), encoding: .utf8)!)
        }
        if mode == "dark" || mode == "dark-disk" {
            let black = root.appendingPathComponent("black.mp4")
            let nearBlack = root.appendingPathComponent("near-black.mp4")
            let mixed = root.appendingPathComponent("mixed.mp4")
            generations.firstEntryGate.signal()
            for (name, url) in [("black", black), ("near-black", nearBlack), ("mixed", mixed)] {
                request(name, url)
            }
            let finished = pump { ["black", "near-black", "mixed"].allSatisfy { completions.count($0) == 1 } }
            let blackImage = completions.image("black"), nearImage = completions.image("near-black")
            let mixedImage = completions.image("mixed")
            request("black-warm", black); request("near-warm", nearBlack)
            let warmFinished = pump { completions.count("black-warm") == 1 && completions.count("near-warm") == 1 }
            let memoryMatches = warmFinished && blackImage != nil && nearImage != nil
                && blackImage === completions.image("black-warm") && nearImage === completions.image("near-warm")
            if mode == "dark-disk" {
                checks["darkDiskHitsKeepDecodedFrames"] = finished && darkFrame(blackImage)
                    && darkFrame(nearImage) && realFrame(mixedImage)
                checks["darkDiskHitsSkipAVGeneration"] = generations.metrics["totalStarts"] == 0
                checks["darkDiskThenMemoryKeepsImage"] = memoryMatches
                checks["darkDiskIdentityReadsStayFresh"] = keys.hasQueries(2, for: black)
                    && keys.hasQueries(2, for: nearBlack) && keys.hasQueries(1, for: mixed)
                checks["darkDiskCompletionsOnceOnMain"] = completions.allOnceOnMain(expectedCount: 5)
                try emit()
                return
            }
            let blackPixels = sampleRGB(decodedFrame(blackImage)), nearPixels = sampleRGB(decodedFrame(nearImage))
            checks["blackVideoKeepsDecodedFrame"] = finished && darkFrame(blackImage)
                && (blackPixels?.allSatisfy { $0 <= 1 } ?? false)
            checks["nearBlackVideoKeepsDecodedFrame"] = darkFrame(nearImage)
                && (nearPixels?.allSatisfy { $0 > 0 && $0 < 8 } ?? false)
            checks["laterBrightCandidateStillWins"] = realFrame(mixedImage)
            let blackFrames = generations.candidates(black), nearFrames = generations.candidates(nearBlack)
            let mixedFrames = generations.candidates(mixed)
            checks["darkFallbackKeepsFirstDecodedFrame"] = blackPixels != nil && nearPixels != nil
                && blackPixels == sampleRGB(blackFrames.images.first ?? nil)
                && nearPixels == sampleRGB(nearFrames.images.first ?? nil)
                && nearPixels != sampleRGB(nearFrames.images.last ?? nil)
            checks["darkCandidatesKeepOriginalOrder"] = blackFrames.times == [1, 0.25, 0]
                && nearFrames.times == [1, 0.25, 0]
            checks["mixedCandidatesReallyStartDarkThenBright"] = mixedFrames.times == [1, 0.25]
                && mixedFrames.images.count == 2
                && mixedFrames.images[0].map(steamWorkshopSampledLumaIsSuspicious) == true
                && mixedFrames.images[1].map(steamWorkshopSampledLumaIsSuspicious) == false
            let small = root.appendingPathComponent("small.mp4")
            request("small", small)
            let smallFinished = pump { completions.count("small") == 1 }
            let smallFrames = generations.candidates(small)
            checks["smallVideoStillFails"] = smallFinished
                && completions.image("small") == nil && generations.count(small) == 1
                && smallFrames.times == [1, 0.25, 0]
                && smallFrames.images.allSatisfy { image in image.map { $0.width <= 4 || $0.height <= 4 } ?? true }
            request("small-again", small)
            checks["smallVideoFailureStaysNegativeCached"] = pump { completions.count("small-again") == 1 }
                && completions.image("small-again") == nil && generations.count(small) == 1
            checks["darkMemoryHitsKeepImages"] = memoryMatches && generations.count(black) == 1 && generations.count(nearBlack) == 1
            checks["darkFramesPersistAsJPEG"] = [black, nearBlack].allSatisfy { url in
                let key = keys.captures(url).first ?? ""
                return !key.isEmpty && darkFrame(NSImage(contentsOf: outputURL(key)))
            }
            checks["darkIdentityReadsStayFresh"] = keys.hasQueries(2, for: black) && keys.hasQueries(2, for: nearBlack)
                && keys.hasQueries(1, for: mixed) && keys.hasQueries(2, for: small)
            checks["darkGenerationsStaySerialAndOffMain"] = generations.serialAndOffMain && generations.metrics["totalStarts"] == 4
            checks["darkCompletionsOnceOnMain"] = completions.allOnceOnMain(expectedCount: 7)
            try emit()
            return
        }
        if mode == "repair" {
            generations.firstEntryGate.signal()
            var sameIdentity = true, repairedOutputs = true
            for (kind, url) in [("invalid", first), ("truncated", second), ("small", root.appendingPathComponent("changing.mp4"))] {
                request(kind + "-seed", url)
                let seeded = pump { completions.count(kind + "-seed") == 1 }
                let key = keys.captures(url).first ?? ""
                let output = outputURL(key)
                let original = (try? Data(contentsOf: output)) ?? Data()
                var damaged = Data("owned invalid thumbnail bytes".utf8)
                if kind == "truncated" { damaged = Data(original.prefix(original.count / 2)) }
                if kind == "small" {
                    let context = CGContext(data: nil, width: 2, height: 2, bitsPerComponent: 8, bytesPerRow: 8,
                        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
                    context.setFillColor(CGColor(gray: 1, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
                    damaged = NSBitmapImageRep(cgImage: context.makeImage()!).representation(using: .jpeg, properties: [:])!
                }
                let decodes = decodedFrame(NSImage(data: damaged)) != nil
                let before = generations.count(url)
                pipeline.invalidateCachedResults()
                try damaged.write(to: output)
                request(kind + "-repair", url)
                let finished = pump { completions.count(kind + "-repair") == 1 }
                let result = completions.image(kind + "-repair")
                let regenerated = generations.count(url) == before + 1
                let name = kind == "invalid" ? "invalidCacheBytesRegenerate"
                    : (kind == "small" ? "smallCacheRegenerates" : "truncatedCacheFollowsActualDecode")
                checks[name] = seeded && realFrame(completions.image(kind + "-seed")) && finished
                    && (decodes ? (decodedFrame(result) != nil && generations.count(url) == before)
                                : (realFrame(result) && regenerated))
                sameIdentity = sameIdentity && !key.isEmpty && keys.hasQueries(2, for: url)
                    && Set(keys.captures(url)).count == 1
                repairedOutputs = repairedOutputs && decodedFrame(NSImage(contentsOf: output)) != nil
                    && (decodes || realFrame(NSImage(contentsOf: output)))
            }
            checks["repairKeepsSourceIdentity"] = sameIdentity
            checks["repairOutputsDecode"] = repairedOutputs
            checks["repairGenerationsStaySerialAndOffMain"] = generations.serialAndOffMain
            checks["repairCompletionsOnceOnMain"] = completions.allOnceOnMain(expectedCount: 6)
            try emit()
            return
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
        if mode == "invalidation" {
            let failed = root.appendingPathComponent("clear-failure.mp4")
            let successFlight = root.appendingPathComponent("clear-flight-success.mp4")
            let failureFlight = root.appendingPathComponent("clear-flight-failure.mp4")
            generations.firstEntryGate.signal()
            func removeServiceDiskRoot() throws {
                let cacheRoot = disk.deletingLastPathComponent()
                if FileManager.default.fileExists(atPath: cacheRoot.path) { try FileManager.default.removeItem(at: cacheRoot) }
            }
            generations.fail(failed, enabled: true)
            request("initial-failure", failed)
            precondition(pump { completions.count("initial-failure") == 1 })
            request("negative-before-clear", failed)
            checks["completedFailureStillDeduplicatesBeforeInvalidation"] = pump {
                completions.count("negative-before-clear") == 1
            } && completions.image("initial-failure") == nil && completions.image("negative-before-clear") == nil
                && generations.count(failed) == 1
            pipeline.invalidateCachedResults()
            generations.fail(failed, enabled: false)
            request("same-key-after-clear", failed)
            checks["explicitInvalidationLetsSameKeyGenerateRealFrame"] = pump {
                completions.count("same-key-after-clear") == 1
            } && realFrame(completions.image("same-key-after-clear")) && generations.count(failed) == 2
                && Set(keys.captures(failed)).count == 1
            request("warm-after-clear", failed)
            checks["newResultStillWarmsMemory"] = pump { completions.count("warm-after-clear") == 1 }
                && completions.image("warm-after-clear") === completions.image("same-key-after-clear")
                && generations.count(failed) == 2
            let failedKey = keys.captures(failed).first!
            pipeline.invalidateCachedResults()
            checks["invalidationLeavesDiskDeletionWithService"] = realFrame(NSImage(contentsOf: outputURL(failedKey)))
            try removeServiceDiskRoot()
            request("after-service-disk-clear", failed)
            checks["serviceDiskRemovalCannotLeaveWarmMemory"] = pump {
                completions.count("after-service-disk-clear") == 1
            } && realFrame(completions.image("after-service-disk-clear")) && generations.count(failed) == 3

            let successHold = generations.holdNext(successFlight)
            request("old-success", successFlight)
            precondition(pump { successHold.entered })
            request("joined-old-success", successFlight)
            pipeline.invalidateCachedResults()
            try removeServiceDiskRoot()
            successHold.release()
            checks["inflightSuccessKeepsBothCallbacksOnce"] = pump {
                completions.count("old-success") == 1 && completions.count("joined-old-success") == 1
            } && realFrame(completions.image("old-success"))
                && completions.image("old-success") === completions.image("joined-old-success")
                && generations.count(successFlight) == 1
            let successKey = keys.captures(successFlight).first!
            checks["inflightSuccessCannotRefillDisk"] = !FileManager.default.fileExists(atPath: outputURL(successKey).path)
            request("new-success", successFlight)
            checks["inflightSuccessCannotRefillMemory"] = pump { completions.count("new-success") == 1 }
                && realFrame(completions.image("new-success")) && generations.count(successFlight) == 2
            request("new-success-warm", successFlight)
            checks["newSuccessJobCachesNormally"] = pump { completions.count("new-success-warm") == 1 }
                && completions.image("new-success-warm") === completions.image("new-success")
                && generations.count(successFlight) == 2 && realFrame(NSImage(contentsOf: outputURL(successKey)))

            generations.fail(failureFlight, enabled: true)
            let failureHold = generations.holdNext(failureFlight)
            request("old-failure", failureFlight)
            precondition(pump { failureHold.entered })
            pipeline.invalidateCachedResults()
            try removeServiceDiskRoot()
            failureHold.release()
            checks["inflightFailureStillCompletesOnce"] = pump { completions.count("old-failure") == 1 }
                && completions.image("old-failure") == nil && generations.count(failureFlight) == 1
            generations.fail(failureFlight, enabled: false)
            request("new-after-failure", failureFlight)
            checks["inflightFailureCannotRefillNegativeCache"] = pump { completions.count("new-after-failure") == 1 }
                && realFrame(completions.image("new-after-failure")) && generations.count(failureFlight) == 2
            let failureKey = keys.captures(failureFlight).first!
            checks["newFailureRecoveryCachesNormally"] = realFrame(NSImage(contentsOf: outputURL(failureKey)))
            checks["invalidationKeepsCapturedIdentityCounts"] = keys.hasQueries(5, for: failed)
                && keys.hasQueries(4, for: successFlight) && keys.hasQueries(2, for: failureFlight)
                && Set(keys.captures(failed)).count == 1 && Set(keys.captures(successFlight)).count == 1
                && Set(keys.captures(failureFlight)).count == 1
            checks["invalidationGenerationsStaySerialAndOffMain"] = generations.serialAndOffMain
                && generations.metrics["totalStarts"] == 7
            checks["allInvalidationCompletionsOnceOnMain"] = completions.allOnceOnMain(expectedCount: 11)
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
