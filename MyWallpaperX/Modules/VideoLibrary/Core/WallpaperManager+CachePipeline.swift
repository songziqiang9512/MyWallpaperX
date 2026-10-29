//
//  WallpaperManager+CachePipeline.swift
//  MyWallpaperX
//

import Foundation
import AVFoundation
import AppKit
import CryptoKit
import Darwin

extension WallpaperManager {
    func currentCacheGeneration() -> UInt64 {
        cacheGenerationLock.lock()
        defer { cacheGenerationLock.unlock() }
        return cacheGeneration
    }

    func cachedThumbnailPath(for key: String) -> String? {
        thumbnailCacheLock.lock()
        defer { thumbnailCacheLock.unlock() }
        return thumbnailCache[key]
    }

    func setCachedThumbnailPath(_ path: String?, for key: String) {
        thumbnailCacheLock.lock()
        defer { thumbnailCacheLock.unlock() }
        if let path {
            thumbnailCache[key] = path
        } else {
            thumbnailCache.removeValue(forKey: key)
        }
    }

    func enqueueThumbnailCompletion(_ completion: @escaping (String?) -> Void, for normalizedPath: String) -> Bool {
        thumbnailInFlightLock.lock()
        defer { thumbnailInFlightLock.unlock() }
        if thumbnailInFlightHandlers[normalizedPath] != nil {
            thumbnailInFlightHandlers[normalizedPath]?.append(completion)
            return true
        }
        thumbnailInFlightHandlers[normalizedPath] = [completion]
        return false
    }

    func completeThumbnailGeneration(for normalizedPath: String, with outputPath: String?, generation: UInt64) {
        // 统一从主线程回调，卡片刷新和索引回写都依赖这一点。
        cacheGenerationLock.lock()
        guard cacheGeneration == generation else { cacheGenerationLock.unlock(); return }
        thumbnailInFlightLock.lock()
        let handlers = thumbnailInFlightHandlers.removeValue(forKey: normalizedPath) ?? []
        thumbnailInFlightLock.unlock()
        cacheGenerationLock.unlock()

        DispatchQueue.main.async {
            let currentPath = self.currentCacheGeneration() == generation ? outputPath : nil
            for handler in handlers {
                handler(currentPath)
            }
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
        DispatchQueue.main.async { handlers.forEach { $0(nil) } }
    }

    func clearThumbnailMemoryCache() {
        thumbnailCacheLock.lock()
        thumbnailCache.removeAll()
        thumbnailCacheLock.unlock()
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

        let sourceURL = URL(fileURLWithPath: wallpaper.path)
        let key = cacheKey(forNormalizedPath: normalizedPath(sourceURL.path))
        if let memoryPath = cachedThumbnailPath(for: key),
           pathExists(memoryPath) {
            return memoryPath
        }

        let path = thumbnailOutputURL(forKey: key).path
        return pathExists(path) ? path : nil
    }

    func generateThumbnail(for url: URL, completion: @escaping (String?) -> Void) {
        let capturedGeneration = currentCacheGeneration()
        let normalized = normalizedPath(url.path)
        let cacheKey = cacheKey(forNormalizedPath: normalized)

        // 检查缓存
        if let cachedPath = cachedThumbnailPath(for: cacheKey) {
            if pathExists(cachedPath) {
                clearThumbnailGenerationFailure(for: normalized)
                completion(cachedPath)
                return
            } else {
                setCachedThumbnailPath(nil, for: cacheKey)
            }
        }

        // 检查磁盘缓存（跨重启仍可命中），避免重复解码生成缩略图。
        let outputURL = thumbnailOutputURL(forKey: cacheKey)
        let diskCachedPath = outputURL.path
        if pathExists(diskCachedPath) {
            setCachedThumbnailPath(diskCachedPath, for: cacheKey)
            clearThumbnailGenerationFailure(for: normalized)
            completion(diskCachedPath)
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
        let alreadyInFlight = enqueueThumbnailCompletion(completion, for: normalized)
        cacheGenerationLock.unlock()
        if alreadyInFlight { return }

        // 使用后台限并发队列生成缩略图，避免导入大量文件时瞬时抢占资源。
        thumbnailQueue.async {
            guard self.currentCacheGeneration() == capturedGeneration else { return }
            self.thumbnailGenerationLimiter.wait()
            defer { self.thumbnailGenerationLimiter.signal() }

            autoreleasepool {
                guard self.currentCacheGeneration() == capturedGeneration else { return }
                let asset = AVURLAsset(url: url)
                let imageGenerator = AVAssetImageGenerator(asset: asset)
                imageGenerator.appliesPreferredTrackTransform = true
                imageGenerator.maximumSize = CGSize(width: 400, height: 400)
                var outputPath: String?

                let candidateTimes = [
                    CMTime(seconds: 1, preferredTimescale: 600),
                    CMTime(seconds: 0.2, preferredTimescale: 600),
                    CMTime(seconds: 2, preferredTimescale: 600),
                    CMTime(seconds: 3, preferredTimescale: 600),
                    CMTime.zero
                ]

                for time in candidateTimes {
                    guard self.currentCacheGeneration() == capturedGeneration else {
                        break
                    }
                    if let cgImage = self.generateCGImage(using: imageGenerator, at: time) {
                        let rep = NSBitmapImageRep(cgImage: cgImage)
                        if let data = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.7]) {
                            do {
                                let staged = outputURL.deletingLastPathComponent()
                                    .appendingPathComponent(".thumbnail-" + UUID().uuidString + ".pending")
                                defer { try? FileManager.default.removeItem(at: staged) }
                                try data.write(to: staged)
                                self.cacheGenerationLock.lock()
                                let published = self.cacheGeneration == capturedGeneration && rename(staged.path, outputURL.path) == 0
                                if published {
                                    self.setCachedThumbnailPath(outputURL.path, for: cacheKey)
                                    self.clearThumbnailGenerationFailure(for: normalized)
                                    outputPath = outputURL.path
                                }
                                self.cacheGenerationLock.unlock()
                                if published { break }
                            } catch {
                            }
                        }
                    }
                }
                self.cacheGenerationLock.lock()
                if outputPath == nil, self.cacheGeneration == capturedGeneration {
                    self.markThumbnailGenerationFailure(for: normalized)
                }
                self.cacheGenerationLock.unlock()
                self.completeThumbnailGeneration(for: normalized, with: outputPath, generation: capturedGeneration)
            }
        }
    }

    func generateCGImage(using generator: AVAssetImageGenerator, at time: CMTime) -> CGImage? {
        VideoStillFrame.image(using: generator, at: time)
    }

}
