//
//  WallpaperManager+CachePipeline.swift
//  MyWallpaperX
//

import Foundation
import AVFoundation
import AppKit
import CryptoKit
import Darwin
import ImageIO

nonisolated struct VideoThumbnailAsset: Sendable {
    let path: String
    let nativeSize: CGSize?
}

extension WallpaperManager {
    func currentCacheGeneration() -> UInt64 {
        cacheGenerationLock.lock()
        defer { cacheGenerationLock.unlock() }
        return cacheGeneration
    }

    func enqueueThumbnailCompletion(_ completion: @escaping (VideoThumbnailAsset?) -> Void, for normalizedPath: String, request: ThumbnailRequest? = nil) -> Bool {
        thumbnailInFlightLock.lock()
        defer { thumbnailInFlightLock.unlock() }
        if thumbnailInFlightHandlers[normalizedPath] != nil {
            thumbnailInFlightHandlers[normalizedPath]?.append((request, completion))
            return true
        }
        thumbnailInFlightHandlers[normalizedPath] = [(request, completion)]
        return false
    }

    @discardableResult
    func completeThumbnailGeneration(for normalizedPath: String, with asset: VideoThumbnailAsset?, generation: UInt64,
                                     pixels: CGSize = .zero) -> ThumbnailRequest? {
        // Keep larger requests pending until the same producer covers their actual pixels.
        cacheGenerationLock.lock()
        guard cacheGeneration == generation else { cacheGenerationLock.unlock(); return nil }
        thumbnailInFlightLock.lock()
        let consumers = thumbnailInFlightHandlers[normalizedPath] ?? []
        var handlers: [(request: ThumbnailRequest?, completion: (VideoThumbnailAsset?) -> Void)] = []
        var remaining: [(request: ThumbnailRequest?, completion: (VideoThumbnailAsset?) -> Void)] = []
        for consumer in consumers {
            if asset == nil || (consumer.request?.isCovered(by: pixels, nativeSize: asset?.nativeSize) ?? true) {
                handlers.append(consumer)
            } else { remaining.append(consumer) }
        }
        if remaining.isEmpty { thumbnailInFlightHandlers.removeValue(forKey: normalizedPath) }
        else { thumbnailInFlightHandlers[normalizedPath] = remaining }
        thumbnailInFlightLock.unlock()
        cacheGenerationLock.unlock()

        let completions = handlers
        DispatchQueue.main.async {
            let currentAsset = self.currentCacheGeneration() == generation ? asset : nil
            for handler in completions { handler.completion(currentAsset) }
        }
        return remaining.compactMap { $0.request }.max {
            $0.scale(for: asset?.nativeSize ?? pixels) < $1.scale(for: asset?.nativeSize ?? pixels)
        }
    }

    func removeThumbnailInFlight(for normalizedPath: String) {
        thumbnailInFlightLock.lock()
        thumbnailInFlightHandlers.removeValue(forKey: normalizedPath)
        thumbnailInFlightLock.unlock()
    }

    func clearThumbnailInFlight() {
        thumbnailInFlightLock.lock()
        let handlers = thumbnailInFlightHandlers.values.flatMap { $0 }
        thumbnailInFlightHandlers.removeAll()
        thumbnailInFlightLock.unlock()
        // Import's original serial pipeline waits for these completions; a
        // cache clear releases each existing consumer without publishing a path.
        DispatchQueue.main.async { handlers.forEach { $0.completion(nil) } }
    }

    func markThumbnailGenerationFailure(for normalizedPath: String) {
        thumbnailGenerationFailureLock.lock()
        thumbnailGenerationFailures[normalizedPath] = Date()
        thumbnailGenerationFailureLock.unlock()
    }

    func clearThumbnailGenerationFailure(for normalizedPath: String) {
        thumbnailGenerationFailureLock.lock()
        thumbnailGenerationFailures.removeValue(forKey: normalizedPath)
        thumbnailGenerationFailureLock.unlock()
    }

    func recentThumbnailGenerationFailureDate(for normalizedPath: String) -> Date? {
        thumbnailGenerationFailureLock.lock()
        defer { thumbnailGenerationFailureLock.unlock() }
        return thumbnailGenerationFailures[normalizedPath]
    }

    func hasRecentThumbnailGenerationFailure(for normalizedPath: String) -> Bool {
        guard let failureDate = recentThumbnailGenerationFailureDate(for: normalizedPath) else { return false }
        return Date().timeIntervalSince(failureDate) < thumbnailFailureRetryCooldown
    }

    func shouldRetryThumbnailGeneration(for normalizedPath: String) -> Bool {
        !hasRecentThumbnailGenerationFailure(for: normalizedPath)
    }

    func isThumbnailGenerationInFlight(for normalizedPath: String) -> Bool {
        thumbnailInFlightLock.lock()
        defer { thumbnailInFlightLock.unlock() }
        return thumbnailInFlightHandlers[normalizedPath] != nil
    }

    func beginStaticFrameSchedule(for normalizedPath: String) -> Bool {
        staticFrameScheduleLock.lock()
        defer { staticFrameScheduleLock.unlock() }
        if scheduledStaticFramePaths.contains(normalizedPath) {
            return false
        }
        scheduledStaticFramePaths.insert(normalizedPath)
        return true
    }

    func finishStaticFrameSchedule(for normalizedPath: String) {
        staticFrameScheduleLock.lock()
        scheduledStaticFramePaths.remove(normalizedPath)
        staticFrameScheduleLock.unlock()
    }

    func clearStaticFrameSchedule() {
        staticFrameScheduleLock.lock()
        scheduledStaticFramePaths.removeAll()
        staticFrameScheduleLock.unlock()
    }

    func cacheKey(forNormalizedPath normalized: String) -> String {
        let digest = SHA256.hash(data: Data(normalized.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    func thumbnailOutputURL(forKey key: String) -> URL {
        thumbnailCacheDirectory.appendingPathComponent("\(key)_thumb.jpg")
    }

    func existingThumbnailPath(for url: URL) -> String? {
        let key = cacheKey(forNormalizedPath: normalizedPath(url.path))
        let path = thumbnailOutputURL(forKey: key).path
        return pathExists(path) ? path : nil
    }

    func resolvedThumbnailPath(for wallpaper: VideoWallpaper) -> String? {
        if let configuredPath = wallpaper.thumbnailPath,
           pathExists(configuredPath) {
            return configuredPath
        }

        return existingThumbnailPath(for: URL(fileURLWithPath: wallpaper.path))
    }

    func generateThumbnail(for url: URL, request: ThumbnailRequest? = nil, completion: @escaping (VideoThumbnailAsset?) -> Void) {
        let capturedGeneration = currentCacheGeneration()
        let normalized = normalizedPath(url.path)
        let cacheKey = cacheKey(forNormalizedPath: normalized)

        // 检查磁盘缓存（跨重启仍可命中），避免重复解码生成缩略图。
        let outputURL = thumbnailOutputURL(forKey: cacheKey)
        let diskCachedPath = outputURL.path
        if request == nil, pathExists(diskCachedPath) {
            clearThumbnailGenerationFailure(for: normalized)
            completion(VideoThumbnailAsset(path: diskCachedPath, nativeSize: nil))
            return
        }

        // 检查文件是否存在
        guard pathExists(url.path) else {
            markThumbnailGenerationFailure(for: normalized)
            completion(nil)
            return
        }

        cacheGenerationLock.lock()
        guard cacheGeneration == capturedGeneration else {
            cacheGenerationLock.unlock()
            DispatchQueue.main.async { completion(nil) }
            return
        }
        let alreadyInFlight = enqueueThumbnailCompletion(completion, for: normalized, request: request)
        cacheGenerationLock.unlock()
        if alreadyInFlight { return }

        thumbnailQueue.async {
            guard self.currentCacheGeneration() == capturedGeneration else { return }
            self.generateThumbnailAsset(ThumbnailGeneration(asset: AVURLAsset(url: url), normalizedPath: normalized,
                outputURL: outputURL, generation: capturedGeneration), request: request)
        }
    }

    private struct ThumbnailGeneration {
        let asset: AVURLAsset
        let normalizedPath: String
        let outputURL: URL
        let generation: UInt64
    }

    func thumbnailPixelSize(at path: String) -> CGSize? {
        guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL,
            [kCGImageSourceShouldCache: false] as CFDictionary),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
              let height = properties[kCGImagePropertyPixelHeight] as? NSNumber else { return nil }
        return CGSize(width: width.doubleValue, height: height.doubleValue)
    }

    private func generateThumbnailAsset(_ source: ThumbnailGeneration, request: ThumbnailRequest?, nativeSize: CGSize? = nil) {
        thumbnailQueue.async {
            guard self.currentCacheGeneration() == source.generation else { return }
            if let request, let stored = self.thumbnailPixelSize(at: source.outputURL.path),
               request.isCovered(by: stored, nativeSize: nativeSize) {
                self.clearThumbnailGenerationFailure(for: source.normalizedPath)
                self.finishThumbnailAsset(source, outputPath: source.outputURL.path, nativeSize: nativeSize, pixels: stored)
                return
            }
            if request != nil, nativeSize == nil {
                self.thumbnailGenerationLimiter.wait()
                guard self.currentCacheGeneration() == source.generation else {
                    self.thumbnailGenerationLimiter.signal()
                    return
                }
                Task {
                    defer { self.thumbnailGenerationLimiter.signal() }
                    let native = await self.thumbnailNativeSize(for: source.asset)
                    self.thumbnailQueue.async {
                        guard self.currentCacheGeneration() == source.generation else { return }
                        guard let native else {
                            self.cacheGenerationLock.lock()
                            if self.cacheGeneration == source.generation { self.markThumbnailGenerationFailure(for: source.normalizedPath) }
                            self.cacheGenerationLock.unlock()
                            self.completeThumbnailGeneration(for: source.normalizedPath, with: nil, generation: source.generation)
                            return
                        }
                        self.generateThumbnailAsset(source, request: request, nativeSize: native)
                    }
                }
                return
            }
            self.thumbnailGenerationLimiter.wait()
            defer { self.thumbnailGenerationLimiter.signal() }
            autoreleasepool {
                guard self.currentCacheGeneration() == source.generation else { return }
                let imageGenerator = AVAssetImageGenerator(asset: source.asset)
                imageGenerator.appliesPreferredTrackTransform = true
                if let request, let nativeSize {
                    // The uncropped master also serves default Inspector/Status consumers.
                    imageGenerator.maximumSize = request.decodedSize(for: nativeSize, minimumLongestSide: 400)
                } else {
                    imageGenerator.maximumSize = CGSize(width: 400, height: 400)
                }
                var outputPath: String?
                var pixels = CGSize.zero

                let candidateTimes = [
                    CMTime(seconds: 1, preferredTimescale: 600),
                    CMTime(seconds: 0.2, preferredTimescale: 600),
                    CMTime(seconds: 2, preferredTimescale: 600),
                    CMTime(seconds: 3, preferredTimescale: 600),
                    CMTime.zero
                ]

                for time in candidateTimes {
                    guard self.currentCacheGeneration() == source.generation else {
                        break
                    }
                    if let cgImage = self.generateCGImage(using: imageGenerator, at: time) {
                        let rep = NSBitmapImageRep(cgImage: cgImage)
                        if let data = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.7]) {
                            do {
                                let staged = source.outputURL.deletingLastPathComponent()
                                    .appendingPathComponent(".thumbnail-" + UUID().uuidString + ".pending")
                                defer { try? FileManager.default.removeItem(at: staged) }
                                try data.write(to: staged)
                                self.cacheGenerationLock.lock()
                                let published = self.cacheGeneration == source.generation && rename(staged.path, source.outputURL.path) == 0
                                if published {
                                    self.clearThumbnailGenerationFailure(for: source.normalizedPath)
                                    outputPath = source.outputURL.path
                                    pixels = CGSize(width: cgImage.width, height: cgImage.height)
                                }
                                self.cacheGenerationLock.unlock()
                                break
                            } catch {
                                break
                            }
                        }
                    }
                }
                self.cacheGenerationLock.lock()
                if outputPath == nil, self.cacheGeneration == source.generation {
                    self.markThumbnailGenerationFailure(for: source.normalizedPath)
                }
                self.cacheGenerationLock.unlock()
                self.finishThumbnailAsset(source, outputPath: outputPath, nativeSize: nativeSize, pixels: pixels)
            }
        }
    }

    private func thumbnailNativeSize(for asset: AVAsset) async -> CGSize? {
        guard let tracks = try? await asset.loadTracks(withMediaType: .video), let track = tracks.first,
              let size = try? await track.load(.naturalSize),
              let transform = try? await track.load(.preferredTransform) else { return nil }
        let transformed = CGRect(origin: .zero, size: size).applying(transform).size
        let native = CGSize(width: abs(transformed.width), height: abs(transformed.height))
        return native.width.isFinite && native.height.isFinite && native.width > 0 && native.height > 0 ? native : nil
    }

    private func finishThumbnailAsset(_ source: ThumbnailGeneration, outputPath: String?, nativeSize: CGSize?, pixels: CGSize) {
        let asset = outputPath.map { VideoThumbnailAsset(path: $0, nativeSize: nativeSize) }
        if let next = completeThumbnailGeneration(for: source.normalizedPath, with: asset,
            generation: source.generation, pixels: pixels) {
            generateThumbnailAsset(source, request: next, nativeSize: nativeSize)
        }
    }

    func generateCGImage(using generator: AVAssetImageGenerator, at time: CMTime) -> CGImage? {
        VideoStillFrame.image(using: generator, at: time)
    }

}
