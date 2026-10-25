// The mixed library cell adapter's single SIL thumbnail provider.
// Demand belongs to each viewport; decoded images remain in SILThumbnailStore.
import AppKit
import ImageIO

enum SILThumbnailLoadResult {
    case image(NSImage)
    case missingFile
    case unavailable
}

/// Both visible and nearby consumers use the same bounded, display-size decode.
nonisolated func silGridThumbnailImage(atPath path: String) -> NSImage? {
    guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL,
        [kCGImageSourceShouldCache: false] as CFDictionary),
        let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceThumbnailMaxPixelSize: 512,
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true
        ] as CFDictionary) else { return nil }
    return NSImage(cgImage: image, size: .zero)
}

nonisolated func silGridThumbnailFailureSignature(atPath path: String) -> String? {
    guard let attrs = try? FileManager.default.attributesOfItem(atPath: path) else { return nil }
    let size = (attrs[.size] as? NSNumber)?.int64Value ?? -1
    let modified = (attrs[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
    return "\(path)|\(size)|\(modified)"
}

/// decodeQueue 解码失败签名的跨队列载体：loader 写入、主线程 completion 读取
private final class SILDecodeFailureSignature: @unchecked Sendable {
    private let lock = NSLock()
    private var value: String?
    func store(_ signature: String) {
        lock.lock(); value = signature; lock.unlock()
    }
    var stored: String? {
        lock.lock(); defer { lock.unlock() }
        return value
    }
}

final class SILThumbnailProvider {
    let cache: ThumbnailCache
    private var failedThumbnailSignatures: Set<String> = []

    init(cache: ThumbnailCache = SILThumbnailStore.sharedCache) { self.cache = cache }

    func load(path: String, priority: ThumbnailCacheRequestPriority = .visible,
              cancellation: ThumbnailCacheRequestCancellation,
              completion: @escaping (SILThumbnailLoadResult) -> Void) {
        // 内存快路径：命中直接同步完成，零文件系统调用、零队列跳转
        if let cached = self.cache.cachedImage(forKey: path) {
            completion(.image(cached))
            return
        }
        // 未命中：文件存在性与失败签名 stat 在后台执行，避免逐 cell 主线程文件系统 IO
        let checksFailureSignature = !self.failedThumbnailSignatures.isEmpty
        DispatchQueue.global(qos: priority == .prefetch ? .utility : .userInitiated).async { [weak self] in
            guard !cancellation.cancelled else { return }
            let exists = FileManager.default.fileExists(atPath: path)
            let signature = exists && checksFailureSignature ? silGridThumbnailFailureSignature(atPath: path) : nil
            DispatchQueue.main.async { [weak self] in
                guard !cancellation.cancelled else { return }
                guard let self else {
                    completion(.unavailable)
                    return
                }
                guard exists else {
                    completion(.missingFile)
                    return
                }
                if let signature, self.failedThumbnailSignatures.contains(signature) {
                    completion(.unavailable)
                    return
                }
                // 签名复用：completion 直接使用闭包捕获的后台签名，失败时由
                // loader 在 decodeQueue 解码失败处重算带回，不再主线程 stat
                let decodeFailureSignature = SILDecodeFailureSignature()
                self.cache.load(forKey: path, priority: priority, cancellation: cancellation, loader: {
                    let decodeFailure: () -> NSImage? = {
                        if let signature = silGridThumbnailFailureSignature(atPath: path) {
                            decodeFailureSignature.store(signature)
                        }
                        return nil
                    }
                    return silGridThumbnailImage(atPath: path) ?? decodeFailure()
                }, completion: { [weak self] image in
                    guard let self else {
                        completion(image.map(SILThumbnailLoadResult.image) ?? .unavailable)
                        return
                    }
                    // 成功 remove 后台预载签名（文件替换窗口内更精确）；
                    // 失败优先 insert decodeQueue 解码时刻重算的签名
                    let failureSignature = decodeFailureSignature.stored ?? signature
                    if let failureSignature {
                        if image != nil {
                            self.failedThumbnailSignatures.remove(failureSignature)
                        } else {
                            self.failedThumbnailSignatures.insert(failureSignature)
                        }
                    }
                    completion(image.map(SILThumbnailLoadResult.image) ?? .unavailable)
                })
            }
        }
    }
}
