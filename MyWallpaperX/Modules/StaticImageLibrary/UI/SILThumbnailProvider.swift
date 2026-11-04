// The mixed library cell adapter's single SIL thumbnail provider.
// Demand belongs to each viewport; decoded images remain in SILThumbnailStore.
import AppKit
import ImageIO

enum SILThumbnailLoadResult {
    case image(NSImage)
    case missingFile
    case unavailable
}

nonisolated func silGridThumbnailFailureSignature(atPath path: String) -> String? {
    guard let attrs = try? FileManager.default.attributesOfItem(atPath: path) else { return nil }
    let size = (attrs[.size] as? NSNumber)?.int64Value ?? -1
    let modified = (attrs[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
    return "\(path)|\(size)|\(modified)"
}

/// 解码失败签名的跨队列载体：失败回调写入、主线程 completion 读取
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
    /// Source identity only. The shared cache owns whether a failure still
    /// exists; clearing it must also make an unchanged source retryable.
    private var failureSourceSignatures: [String: String] = [:]

    init(cache: ThumbnailCache = SILThumbnailStore.sharedCache) { self.cache = cache }

    func load(path: String, request: ThumbnailRequest? = nil, priority: ThumbnailCacheRequestPriority = .visible,
              cancellation: ThumbnailCacheRequestCancellation,
              completion: @escaping (SILThumbnailLoadResult) -> Void) {
        // 内存快路径：命中直接同步完成，零文件系统调用、零队列跳转
        if let cached = self.cache.cachedImage(forKey: path, request: request) {
            completion(.image(cached))
            return
        }
        // 未命中：文件存在性与失败签名 stat 在后台执行，避免逐 cell 主线程文件系统 IO
        let checksFailureSignature = cache.hasCachedFailure(forKey: path)
        if !checksFailureSignature { failureSourceSignatures.removeValue(forKey: path) }
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
                if self.cache.hasCachedFailure(forKey: path),
                   signature == nil || self.failureSourceSignatures[path] != signature {
                    // Another producer may have failed without this provider's
                    // source identity. Do not guess that it describes this file.
                    self.cache.remove(forKey: path)
                }
                // 新失败的源身份只由实际解码在失败处带回；加入其他
                // producer 的 completion 不猜签名，也不在主线程 stat。
                let decodeFailureSignature = SILDecodeFailureSignature()
                self.cache.load(forKey: path, request: request, priority: priority, cancellation: cancellation,
                    input: .sourceFile(URL(filePath: path, directoryHint: .notDirectory), onFailure: {
                        if let signature = silGridThumbnailFailureSignature(atPath: path) {
                            decodeFailureSignature.store(signature)
                        }
                    }), completion: { [weak self] image in
                    guard let self else {
                        completion(image.map(SILThumbnailLoadResult.image) ?? .unavailable)
                        return
                    }
                    if image != nil || !self.cache.hasCachedFailure(forKey: path) {
                        self.failureSourceSignatures.removeValue(forKey: path)
                    } else if let failureSignature = decodeFailureSignature.stored {
                        // Only this decode can identify its failed source. A
                        // joined producer's nil must not acquire a guessed memo.
                        self.failureSourceSignatures[path] = failureSignature
                    }
                    completion(image.map(SILThumbnailLoadResult.image) ?? .unavailable)
                })
            }
        }
    }
}
