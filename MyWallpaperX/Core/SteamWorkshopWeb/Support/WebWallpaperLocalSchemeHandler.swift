//
//  WebWallpaperLocalSchemeHandler.swift
//  MyWallpaperX
//

import Foundation
import WebKit
import UniformTypeIdentifiers

final class WebWallpaperLocalSchemeHandler: NSObject, WKURLSchemeHandler {
    /// 只承载「路径身份 + 受控读取判定」：size/mtime 属于交付时刻的事实，
    /// 由 `FileStat` 每次现取，不从 resolve 缓存里带出来。
    struct ResolvedResource {
        let fileURL: URL
        let didTraverseSymlink: Bool
        let matchedRootPath: String
    }

    /// resolve 结果：`resource` 与 `denial` 必有其一。
    /// 拒绝原因随返回值传递，不再按 requestURL 记账。
    struct ResolveOutcome {
        let resource: ResolvedResource?
        let denial: AccessDenied?

        static func resolved(_ resource: ResolvedResource) -> ResolveOutcome {
            ResolveOutcome(resource: resource, denial: nil)
        }

        static func denied(_ denial: AccessDenied) -> ResolveOutcome {
            ResolveOutcome(resource: nil, denial: denial)
        }
    }

    enum AccessDenyReason: String {
        case invalidURL
        case outsideAllowedRoots
        case outsideRootAfterSymlink
        case symlinkRejected
        case missing
        case directoryWithoutIndex
        case notRegularFile
    }

    struct AccessDenied: LocalizedError {
        let reason: AccessDenyReason
        let requestURL: URL
        let candidateURL: URL?
        let resolvedURL: URL?

        var errorDescription: String? {
            "local_scheme_denied_\(reason.rawValue)"
        }
    }

    /// `stop` 与在途交付共享的取消身份：一旦置位，交付不得再对 task 回调。
    final class RequestCancellation {
        private let lock = NSLock()
        private var cancelled = false

        func cancel() {
            lock.lock()
            cancelled = true
            lock.unlock()
        }

        var isCancelled: Bool {
            lock.lock()
            defer { lock.unlock() }
            return cancelled
        }
    }

    /// 单次 didReceive 的读块上限：不超过该值的文件与原先单次整读等价。
    static let deliveryChunkSize = 1 << 20
    /// resolve 缓存 TTL（秒）与条目上限。TTL 只覆盖同一次页面装载的并发爆发，
    /// 让路径/符号链接判定与受控根判定的过期窗口保持在交付窗口量级。
    static let resolveCacheTTL: TimeInterval = 0.25
    static let resolveCacheCapacity = 512
    /// 已交付 CSS 诊断去重集合的条目上限：满时清空重录，
    /// 未信任页面循环制造唯一 query 键也无法无界累积。
    static let servedDiagnosticURLsCapacity = 512

    /// 不可变，供 +Resolve 复用。
    let rootURL: URL
    let strictSymlinkPolicy: Bool
    /// 以下共享状态只在 stateLock 内读写；stat/读文件等 IO 一律在锁外。
    /// `additionalReadableRoots` 只经 `updateAdditionalReadableRoots` 变更。
    let stateLock = NSLock()
    var additionalReadableRoots: [URL] = []
    var readableRootsGeneration: UInt64 = 0
    var resolveCache: [String: CachedResolution] = [:]
    var diagnosticHandler: ((String, WebRuntimeDiagnosticEvent.Severity, String, URL?) -> Void)?
    /// resolve 与交付在 IO 队列、回调在主线程。
    let ioQueue = DispatchQueue(
        label: "com.songziqiang.MyWallpaperX.local-scheme-io",
        qos: .userInitiated
    )
    /// 只在主线程访问（交付回调与诊断都收敛在主线程）。
    private var servedDiagnosticURLs: Set<String> = []
    /// 同样受 stateLock 保护：`stop` 可能在任意回调线程到达。
    private var activeCancellations: [ObjectIdentifier: RequestCancellation] = [:]

    init(rootURL: URL, strictSymlinkPolicy: Bool = false) {
        self.rootURL = rootURL.resolvingSymlinksInPath().standardizedFileURL
        self.strictSymlinkPolicy = strictSymlinkPolicy
    }

    /// 根集合每次变更都推进代际并丢弃缓存：受控读取判定以 roots 为准，
    /// 缓存不得跨代际复用。
    func updateAdditionalReadableRoots(_ urls: [URL]) {
        let normalizedRoots = Array(
            Set(
                urls.map { $0.resolvingSymlinksInPath().standardizedFileURL }
            )
        ).sorted { $0.path < $1.path }
        stateLock.lock()
        additionalReadableRoots = normalizedRoots
        readableRootsGeneration &+= 1
        resolveCache.removeAll(keepingCapacity: true)
        stateLock.unlock()
    }

    func webView(_ webView: WKWebView, start urlSchemeTask: any WKURLSchemeTask) {
        let request = urlSchemeTask.request
        guard let requestURL = request.url else {
            let error = AccessDenied(reason: .invalidURL, requestURL: URL(fileURLWithPath: "/"), candidateURL: nil, resolvedURL: nil)
            recordDeny(error)
            urlSchemeTask.didFailWithError(error)
            return
        }
        let cancellation = RequestCancellation()
        registerCancellation(cancellation, for: urlSchemeTask)
        startDelivery(
            for: request,
            requestURL: requestURL,
            isHeadRequest: request.httpMethod?.caseInsensitiveCompare("HEAD") == .orderedSame,
            to: urlSchemeTask,
            cancellation: cancellation,
            webView: webView
        )
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: any WKURLSchemeTask) {
        cancellation(for: urlSchemeTask)?.cancel()
    }

    func registerCancellation(_ cancellation: RequestCancellation, for urlSchemeTask: any WKURLSchemeTask) {
        let key = ObjectIdentifier(urlSchemeTask as AnyObject)
        stateLock.lock()
        activeCancellations[key] = cancellation
        stateLock.unlock()
    }

    func cancellation(for urlSchemeTask: any WKURLSchemeTask) -> RequestCancellation? {
        let key = ObjectIdentifier(urlSchemeTask as AnyObject)
        stateLock.lock()
        defer { stateLock.unlock() }
        return activeCancellations[key]
    }

    func finishRequest(_ urlSchemeTask: any WKURLSchemeTask) {
        let key = ObjectIdentifier(urlSchemeTask as AnyObject)
        stateLock.lock()
        activeCancellations.removeValue(forKey: key)
        stateLock.unlock()
    }

    /// 本方法可能在 IO/scheme 回调线程进入；`evaluateJavaScript` 只在主线程执行。
    func silenceFailedMediaRequestIfNeeded(requestURL: URL, in webView: WKWebView) {
        let normalizedPath = requestURL.path.lowercased()
        let isMediaCandidate =
            normalizedPath.hasSuffix(".ogg") ||
            normalizedPath.hasSuffix(".mp3") ||
            normalizedPath.hasSuffix(".wav") ||
            normalizedPath.hasSuffix(".m4a") ||
            normalizedPath.hasSuffix(".aac") ||
            normalizedPath.hasSuffix(".webm") ||
            normalizedPath.hasSuffix(".mp4") ||
            normalizedPath.hasSuffix("/null")
        guard isMediaCandidate else { return }

        let escapedRequestURL = requestURL.absoluteString
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let script = """
        (() => {
          const failedURL = "\(escapedRequestURL)";
          const mediaNodes = Array.from(document.querySelectorAll('audio,video'));
          mediaNodes.forEach((node) => {
            const currentSrc = String(node.currentSrc || node.src || '').trim();
            if (!currentSrc || currentSrc !== failedURL) return;
            try { node.__mwxMissingSource = failedURL; } catch (_) {}
            try { node.pause(); } catch (_) {}
            try { node.removeAttribute('src'); } catch (_) {}
            try {
              const sourceNodes = Array.from(node.querySelectorAll('source'));
              sourceNodes.forEach((sourceNode) => {
                const sourceValue = String(sourceNode.currentSrc || sourceNode.src || sourceNode.getAttribute('src') || '').trim();
                if (sourceValue === failedURL || !sourceValue || sourceValue.toLowerCase().endsWith('/null')) {
                  try { sourceNode.__mwxMissingSource = failedURL; } catch (_) {}
                  try { sourceNode.removeAttribute('src'); } catch (_) {}
                  try { sourceNode.src = ''; } catch (_) {}
                }
              });
            } catch (_) {}
            try { node.load(); } catch (_) {}
          });
        })();
        """
        DispatchQueue.main.async {
            webView.evaluateJavaScript(script, completionHandler: nil)
        }
    }

    func shouldRecordServedDiagnostic(for requestURL: URL) -> Bool {
        let key = requestURL.absoluteString
        guard servedDiagnosticURLs.contains(key) == false else {
            return false
        }
        // 未信任页面可以持续制造唯一 query 键，集合必须有硬上限。
        if servedDiagnosticURLs.count >= Self.servedDiagnosticURLsCapacity {
            servedDiagnosticURLs.removeAll()
        }
        servedDiagnosticURLs.insert(key)
        return true
    }

    func isOptionalMissingMediaRequest(_ requestURL: URL) -> Bool {
        optionalMissingMediaDiagnostic(for: requestURL) != nil
    }

    private func optionalMissingMediaDiagnostic(for requestURL: URL) -> (type: String, message: String)? {
        let normalizedPath = requestURL.path.removingPercentEncoding?.lowercased() ?? requestURL.path.lowercased()
        let components = normalizedPath.split(separator: "/").map(String.init)
        let fileName = components.last ?? ""
        let directoryNames = Set(components.dropLast())
        if Self.isPlaceholderMediaPath(normalizedPath, fileName: fileName) {
            return ("local-resource.placeholder", "placeholder_media_source")
        }
        if fileName == "performance.layout.user.js" {
            return ("local-resource.optional-user-layout", "optional_performance_layout_user")
        }
        guard Self.isAudioPath(normalizedPath) else {
            return nil
        }
        if fileName.hasPrefix("0-") || fileName.hasPrefix("00-") {
            return ("local-resource.optional-audio", "optional_audio_none_placeholder")
        }
        if directoryNames.contains("sound") || directoryNames.contains("sounds") {
            return ("local-resource.optional-audio", "optional_audio_missing")
        }
        return nil
    }

    private static func isPlaceholderMediaPath(_ normalizedPath: String, fileName: String) -> Bool {
        if fileName == "null" || fileName == "undefined" || fileName == "(null)" || fileName == "about:blank" {
            return true
        }
        return normalizedPath.hasSuffix("/null") ||
            normalizedPath.hasSuffix("/undefined") ||
            normalizedPath.hasSuffix("/(null)") ||
            normalizedPath.hasSuffix("/about:blank")
    }

    private static func isAudioPath(_ normalizedPath: String) -> Bool {
        normalizedPath.hasSuffix(".ogg") ||
            normalizedPath.hasSuffix(".mp3") ||
            normalizedPath.hasSuffix(".wav") ||
            normalizedPath.hasSuffix(".m4a") ||
            normalizedPath.hasSuffix(".aac") ||
            normalizedPath.hasSuffix(".flac")
    }

    /// 已打开句柄的实际长度：流式交付的声明长度以此为准（seek 到末尾取偏移后回到起点）。
    static func streamedLength(of fileHandle: FileHandle) -> Int64? {
        guard let endOffset = try? fileHandle.seekToEnd(),
              (try? fileHandle.seek(toOffset: 0)) != nil else {
            return nil
        }
        return Int64(endOffset)
    }

    /// css 交付诊断文案（`local-resource.served` 的唯一产生点）。
    static func cssServedDiagnostic(
        fileURL: URL,
        fileSize: Int64,
        mimeType: String,
        deliveredLength: Int,
        range: ClosedRange<Int64>?
    ) -> String? {
        guard fileURL.pathExtension.lowercased() == "css" else { return nil }
        let rangeDescription = range.map { "\($0.lowerBound)-\($0.upperBound)" } ?? "full"
        return "mime=\(mimeType) size=\(fileSize) delivered=\(deliveredLength) range=\(rangeDescription) file=\(fileURL.path)"
    }

    static func mimeType(for fileURL: URL) -> String {
        if let type = UTType(filenameExtension: fileURL.pathExtension),
           let mimeType = type.preferredMIMEType {
            return mimeType
        }
        switch fileURL.pathExtension.lowercased() {
        case "skel":
            return "application/octet-stream"
        case "atlas", "txt":
            return "text/plain"
        case "js":
            return "text/javascript"
        case "css":
            return "text/css"
        case "html", "htm":
            return "text/html"
        case "json":
            return "application/json"
        case "svg":
            return "image/svg+xml"
        case "wasm", "unityweb":
            return "application/wasm"
        case "png":
            return "image/png"
        case "jpg", "jpeg":
            return "image/jpeg"
        case "gif":
            return "image/gif"
        case "webp":
            return "image/webp"
        case "webm":
            return "video/webm"
        case "mp4", "m4v":
            return "video/mp4"
        case "mp3":
            return "audio/mpeg"
        case "ogg":
            return "audio/ogg"
        case "wav":
            return "audio/wav"
        case "m4a", "aac":
            return "audio/mp4"
        case "woff":
            return "font/woff"
        case "woff2":
            return "font/woff2"
        case "ttf":
            return "font/ttf"
        case "otf":
            return "font/otf"
        default:
            return "application/octet-stream"
        }
    }

    enum LocalSchemeError: LocalizedError {
        case invalidURL
        case unreadableFileSize
        case invalidRangeHeader
        case unsupportedMultipartRange
        case rangeNotSatisfiable(totalSize: Int64)
        case invalidResponse
        case truncatedDuringDelivery

        var errorDescription: String? {
            switch self {
            case .invalidURL:
                return "invalid_local_scheme_url"
            case .unreadableFileSize:
                return "local_scheme_unreadable_file_size"
            case .truncatedDuringDelivery:
                return "local_scheme_truncated_during_delivery"
            case .invalidRangeHeader:
                return "local_scheme_invalid_range_header"
            case .unsupportedMultipartRange:
                return "local_scheme_unsupported_multipart_range"
            case let .rangeNotSatisfiable(totalSize):
                return "local_scheme_range_not_satisfiable_\(totalSize)"
            case .invalidResponse:
                return "local_scheme_invalid_response"
            }
        }
    }

    /// 记录拒绝原因（诊断唯一出口）；调用方负责把同一 denial 交回请求方。
    func recordDeny(_ denial: AccessDenied) {
        let candidate = denial.candidateURL?.path ?? ""
        let resolved = denial.resolvedURL?.path ?? ""
        let message = [
            "reason=\(denial.reason.rawValue)",
            candidate.isEmpty ? nil : "candidate=\(candidate)",
            resolved.isEmpty ? nil : "resolved=\(resolved)"
        ]
        .compactMap { $0 }
        .joined(separator: " ")
        if denial.reason == .missing,
           let diagnostic = optionalMissingMediaDiagnostic(for: denial.requestURL) {
            diagnosticHandler?(diagnostic.type, .info, "\(diagnostic.message) \(message)", denial.requestURL)
            return
        }
        diagnosticHandler?("local-resource-deny", .warning, message, denial.requestURL)
    }
}
