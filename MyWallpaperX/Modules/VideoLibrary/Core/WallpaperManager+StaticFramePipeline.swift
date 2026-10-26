//
//  WallpaperManager+StaticFramePipeline.swift
//  MyWallpaperX
//

import Foundation
import AVFoundation
import AppKit

extension WallpaperManager {
    func staticFrameOutputURL(forKey key: String) -> URL {
        // 静帧路径和缩略图路径分开，避免不同派生资产互相覆盖。
        staticFrameCacheDirectory.appendingPathComponent("\(key)_frame.jpg")
    }

    func existingStaticFramePath(for url: URL) -> String? {
        // 先命中磁盘缓存再决定是否进入后台提取，减少重复解码。
        let key = cacheKey(forNormalizedPath: normalizedPath(url.path))
        let path = staticFrameOutputURL(forKey: key).path
        return pathExists(path) ? path : nil
    }

    func scheduleStaticFrameGeneration(for url: URL) {
        // 静帧生成走延迟调度，优先让缩略图先出来，避免导入后卡住主线程感知。
        guard pathExists(url.path) else { return }
        let capturedGeneration = currentCacheGeneration()
        let normalized = normalizedPath(url.path)
        let outputPath = staticFrameOutputURL(forKey: cacheKey(forNormalizedPath: normalized)).path

        if pathExists(outputPath) {
            DispatchQueue.main.async { [weak self] in
                guard let self, self.currentCacheGeneration() == capturedGeneration else { return }
                self.updateWallpaperAssetPaths(forPath: url.path, staticFramePath: outputPath)
            }
            return
        }

        guard beginStaticFrameSchedule(for: normalized) else { return }

        staticFrameQueue.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            guard let self else { return }
            let outputPath: String?
            if self.currentCacheGeneration() == capturedGeneration {
                outputPath = self.generateStaticFrame(for: url)
            } else {
                outputPath = nil
            }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.finishStaticFrameSchedule(for: normalized)
                guard self.currentCacheGeneration() == capturedGeneration,
                      let outputPath else { return }
                self.updateWallpaperAssetPaths(forPath: url.path, staticFramePath: outputPath)
            }
        }
    }

    func generateStaticFrameIfNeeded(for url: URL, completion: @escaping (String?) -> Void) {
        // 按需生成接口用于补齐单个条目，不会阻塞完整队列。
        let capturedGeneration = currentCacheGeneration()
        if let cachedPath = existingStaticFramePath(for: url) {
            updateWallpaperAssetPaths(forPath: url.path, staticFramePath: cachedPath)
            completion(cachedPath)
            return
        }

        staticFrameQueue.async { [weak self] in
            guard let self else { return }
            guard self.currentCacheGeneration() == capturedGeneration else {
                DispatchQueue.main.async { completion(nil) }
                return
            }
            let outputPath = self.generateStaticFrame(for: url)
            DispatchQueue.main.async {
                guard self.currentCacheGeneration() == capturedGeneration else {
                    completion(nil)
                    return
                }
                if let outputPath {
                    self.updateWallpaperAssetPaths(forPath: url.path, staticFramePath: outputPath)
                }
                completion(outputPath)
            }
        }
    }

    func generateStaticFrame(for url: URL) -> String? {
        // 真正的帧抽取只在后台队列执行，并且只生成首帧，目的是同步系统壁纸和列表预览。
        guard pathExists(url.path) else {
            return nil
        }

        let key = cacheKey(forNormalizedPath: normalizedPath(url.path))
        let outputURL = staticFrameOutputURL(forKey: key)
        if pathExists(outputURL.path) {
            return outputURL.path
        }

        return autoreleasepool {
            let asset = AVURLAsset(url: url)
            let imageGenerator = AVAssetImageGenerator(asset: asset)
            imageGenerator.appliesPreferredTrackTransform = true
            imageGenerator.maximumSize = CGSize(width: 4096, height: 4096)
            imageGenerator.requestedTimeToleranceBefore = .zero
            imageGenerator.requestedTimeToleranceAfter = .zero
            guard let cgImage = generateCGImage(using: imageGenerator, at: .zero) else {
                return nil
            }

            let rep = NSBitmapImageRep(cgImage: cgImage)
            guard let data = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.9]) else {
                return nil
            }

            do {
                try data.write(to: outputURL)
                return outputURL.path
            } catch {
                return nil
            }
        }
    }
}
