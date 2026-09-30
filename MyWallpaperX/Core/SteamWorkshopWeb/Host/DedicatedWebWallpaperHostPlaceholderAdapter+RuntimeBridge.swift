//
//  DedicatedWebWallpaperHostPlaceholderAdapter+RuntimeBridge.swift
//  MyWallpaperX
//

import Foundation
import AppKit
import WebKit
import CoreGraphics
import Darwin

private enum WebNetworkBridgeFailure: Error, Equatable {
    case destinationNotAllowed
    case responseTooLarge
    case invalidResponse
    case transport(String)

    var message: String {
        switch self {
        case .destinationNotAllowed:
            return "destination_not_allowed"
        case .responseTooLarge:
            return "response_too_large"
        case .invalidResponse:
            return "invalid_response"
        case let .transport(message):
            return message
        }
    }
}

private struct WebNetworkBridgeResponse {
    let response: HTTPURLResponse
    let body: Data
    /// 作者可见的最终 URL（重定向后为最后一跳）：http 的地址锁定只影响连接，
    /// 不把内部已校验 IP 泄漏回页面。
    let visibleURL: URL
}

/// http 请求的连接地址锁定：连接必须落在已校验的 `address`，对外仍是作者
/// 主机名（Host 头与页面可见 URL 都用 `host`）。
private struct WebNetworkBridgeAddressLock: Equatable {
    let host: String
    let address: String
}

/// 一次网络桥接目标的授权结果。
private struct WebNetworkBridgeAuthorization {
    /// 实际交给 URLSession 的请求：http 已重写为「已校验 IP + 手动 Host 头」。
    let request: URLRequest
    /// 回给页面的作者可见 URL。
    let visibleURL: URL
    /// http 的地址锁定；https 为 nil（无法覆写 SNI，见 handleNetworkRequestMessage）。
    let lock: WebNetworkBridgeAddressLock?
}

/// 每「屏 + frame」的在飞网络桥接请求计数（host-lifecycle-5）：页面可以在单帧内
/// 高频 postMessage，没有配额时会无界累积 URLSession/task。准入与释放都发生在
/// 主线程（postMessage 入口与 `Task { @MainActor }` 完成回调），无需跨线程同步。
///
/// 配额按 frame 分桶：`frameInfo` 由 WebKit 填充、页面无法伪造，因此子 frame
/// （含跨源）只能耗尽自己的桶，不能把主 frame 的代理配额挤到 too_many_requests。
///
/// 配额按 surface 世代隔离：条目记录准入时的 webView（弱引用，不扣留 surface）。
/// 换壁纸 / 换 entry 会 teardown 后按同一 screenID 重建 surface，新 surface 的首次
/// 准入发现 owner 不是自己即整桶重置；旧 surface 在飞请求的迟到 release 因 owner
/// 不匹配成为 no-op——旧请求既不阻塞新壁纸的首屏代理请求，也不会误减新世代计数。
@MainActor
private final class WebNetworkBridgeInflightRegistry {
    private struct BucketKey: Hashable {
        let screenID: CGDirectDisplayID
        let frameKey: String
    }

    private struct Entry {
        weak var owner: WKWebView?
        var count: Int
    }

    static let shared = WebNetworkBridgeInflightRegistry()

    private var entriesByBucket: [BucketKey: Entry] = [:]

    func admit(_ screenID: CGDirectDisplayID, frameKey: String, owner: WKWebView, limit: Int) -> Bool {
        let key = BucketKey(screenID: screenID, frameKey: frameKey)
        if let entry = entriesByBucket[key], entry.owner !== owner {
            // 旧世代（surface 已重建）或 owner 已释放：整桶作废。
            entriesByBucket[key] = nil
        }
        let count = entriesByBucket[key]?.count ?? 0
        guard count < limit else { return false }
        entriesByBucket[key] = Entry(owner: owner, count: count + 1)
        return true
    }

    /// 每条已准入请求恰好释放一次；即使 surface 已拆除也必须调用。`owner` 是准入
    /// 时的 webView（调用方弱捕获传入，可为 nil=已释放）：与条目世代不符时不误减。
    func release(_ screenID: CGDirectDisplayID, frameKey: String, owner: WKWebView?) {
        let key = BucketKey(screenID: screenID, frameKey: frameKey)
        guard let entry = entriesByBucket[key], entry.owner === owner else { return }
        entriesByBucket[key] = entry.count > 1
            ? Entry(owner: entry.owner, count: entry.count - 1)
            : nil
    }
}

private final class WebNetworkBridgeRequest: NSObject, URLSessionDataDelegate, URLSessionTaskDelegate {
    private let request: URLRequest
    private let maximumBodyBytes: Int
    private let authorizeRedirect: (URLRequest, WebNetworkBridgeAddressLock?) -> WebNetworkBridgeAuthorization?
    private let completion: (Result<WebNetworkBridgeResponse, WebNetworkBridgeFailure>) -> Void
    private var session: URLSession?
    private var response: HTTPURLResponse?
    private var body = Data()
    private var failure: WebNetworkBridgeFailure?
    private var completed = false
    private var lock: WebNetworkBridgeAddressLock?
    private var visibleURL: URL

    init(
        authorization: WebNetworkBridgeAuthorization,
        maximumBodyBytes: Int,
        authorizeRedirect: @escaping (URLRequest, WebNetworkBridgeAddressLock?) -> WebNetworkBridgeAuthorization?,
        completion: @escaping (Result<WebNetworkBridgeResponse, WebNetworkBridgeFailure>) -> Void
    ) {
        self.request = authorization.request
        self.maximumBodyBytes = maximumBodyBytes
        self.authorizeRedirect = authorizeRedirect
        self.lock = authorization.lock
        self.visibleURL = authorization.visibleURL
        self.completion = completion
    }

    func start() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        // request.timeoutInterval（构造请求时设 10s）只是「两次数据到达之间」的空闲
        // 超时，ephemeral 会话的资源总时限默认宽松得多；不设总时限时，慢速滴流端可把
        // 一次在飞请求挂住并长期占用该屏配额。总时限 10s 与仓库既有双时限写法一致
        // （OnlineLibraryThumbnailPipeline.swift:48-49、
        // SteamWorkshopPreviewRequestCoordinator.swift:71-72），并刻意小于页面侧 15s
        // 桥接超时（JS hostNetworkRequest），保证原生先失败回包。
        configuration.timeoutIntervalForResource = 10
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        self.session = session
        session.dataTask(with: request).resume()
    }

    func urlSession(
        _: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        guard let httpResponse = response as? HTTPURLResponse else {
            failure = .invalidResponse
            dataTask.cancel()
            completionHandler(.cancel)
            return
        }
        self.response = httpResponse
        if response.expectedContentLength > Int64(maximumBodyBytes) {
            failure = .responseTooLarge
            dataTask.cancel()
            completionHandler(.cancel)
            return
        }
        completionHandler(.allow)
    }

    func urlSession(_: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard failure == nil else { return }
        guard body.count <= maximumBodyBytes - data.count else {
            failure = .responseTooLarge
            dataTask.cancel()
            return
        }
        body.append(data)
    }

    func urlSession(
        _: URLSession,
        task _: URLSessionTask,
        willPerformHTTPRedirection _: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        // 重定向目标走与首跳相同的授权：白名单 + 公网地址校验，http 重新锁定
        // 到新一跳的已校验地址（相对 Location 由 URLSession 按当前锁定基址解析，
        // 这类目标的主机就是已校验地址本身，复用锁定）。
        guard let authorization = authorizeRedirect(request, lock) else {
            failure = .destinationNotAllowed
            completionHandler(nil)
            return
        }
        lock = authorization.lock
        visibleURL = authorization.visibleURL
        completionHandler(authorization.request)
    }

    func urlSession(_: URLSession, task _: URLSessionTask, didCompleteWithError error: Error?) {
        defer {
            session?.finishTasksAndInvalidate()
            session = nil
        }
        if let failure {
            finish(.failure(failure))
            return
        }
        if let error {
            finish(.failure(.transport(error.localizedDescription)))
            return
        }
        guard let response else {
            finish(.failure(.invalidResponse))
            return
        }
        finish(.success(WebNetworkBridgeResponse(response: response, body: body, visibleURL: visibleURL)))
    }

    private func finish(_ result: Result<WebNetworkBridgeResponse, WebNetworkBridgeFailure>) {
        guard completed == false else { return }
        completed = true
        completion(result)
    }
}

extension DedicatedWebWallpaperHostPlaceholderAdapter {
    private static let networkBridgeMaxBodyBytes = 2 * 1024 * 1024
    /// 每个 surface 世代的在飞网络桥接请求上限：页面每帧高频 postMessage 时按屏
    /// 限流，超限走既有失败回包通道（JS 侧对 ok !== true 一律 reject）。单条请求的
    /// 存活窗口 = 空闲 10s 与资源总时限 10s 的较小者（WebNetworkBridgeRequest.start()）。
    private static let networkBridgeMaxInflightRequestsPerScreen = 8

    var currentGeneralProperties: [String: Any] {
        currentGeneralProperties(for: nil, screenID: nil)
    }

    func currentGeneralProperties(for screen: NSScreen?, screenID: CGDirectDisplayID?) -> [String: Any] {
        let targetScreen = screen ?? NSScreen.main
        let frame = targetScreen?.frame ?? .zero
        return [
            "fps": resolvedGeneralFPSValue(for: targetScreen),
            "language": currentRequest?.language ?? "en-us",
            "paused": ["value": paused],
            "volume": ["value": currentVolume],
            "display": [
                "value": screenID.map { "Monitor\($0)" } ?? "Monitor0",
                "width": Int(frame.width),
                "height": Int(frame.height),
                "scale": targetScreen?.backingScaleFactor ?? 1
            ]
        ]
    }

    var resolvedGeneralFPSValue: Int {
        resolvedGeneralFPSValue(for: NSScreen.main)
    }

    func resolvedGeneralFPSValue(for screen: NSScreen?) -> Int {
        guard let screen else { return 60 }
        return max(1, min(60, screen.maximumFramesPerSecond))
    }

    var currentGeneralPropertiesJSON: String {
        guard JSONSerialization.isValidJSONObject(currentGeneralProperties),
              let data = try? JSONSerialization.data(withJSONObject: currentGeneralProperties),
              let json = String(data: data, encoding: .utf8) else {
            return #"{"fps":30,"language":"en-us"}"#
        }
        return json
    }

    func currentGeneralPropertiesJSON(for screen: NSScreen?, screenID: CGDirectDisplayID?) -> String {
        let properties = currentGeneralProperties(for: screen, screenID: screenID)
        guard JSONSerialization.isValidJSONObject(properties),
              let data = try? JSONSerialization.data(withJSONObject: properties),
              let json = String(data: data, encoding: .utf8) else {
            return #"{"fps":60,"language":"en-us"}"#
        }
        return json
    }

    func refreshReadableResourceRoots(using propertiesJSON: String?) {
        let accessibleURLs = accessibleResourceURLs(from: propertiesJSON)
        for surface in surfaces.values {
            surface.schemeHandler.updateAdditionalReadableRoots(accessibleURLs)
        }
        refreshRandomFileSnapshots(using: propertiesJSON)
    }

    func accessibleResourceURLs(from propertiesJSON: String?) -> [URL] {
        guard let propertiesJSON,
              let data = propertiesJSON.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return []
        }

        var urls: [URL] = []
        for rawPayload in root.values {
            guard let payload = rawPayload as? [String: Any],
                  let payloadType = payload["type"] as? String,
                  ["file", "directory"].contains(payloadType.lowercased()),
                  let rawValue = payload["value"] as? String else {
                continue
            }

            let trimmedValue = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmedValue.hasPrefix("/") else { continue }

            let candidateURL = URL(fileURLWithPath: trimmedValue)
                .resolvingSymlinksInPath()
                .standardizedFileURL
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: candidateURL.path, isDirectory: &isDirectory) else {
                continue
            }
            urls.append(isDirectory.boolValue ? candidateURL : candidateURL.deletingLastPathComponent())
        }
        return urls
    }

    func resolveRandomFilePath(forPropertyNamed propertyName: String) -> String? {
        guard let propertiesJSON = currentRequest?.propertiesJSON,
              let data = propertiesJSON.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let propertyPayload = root[propertyName] as? [String: Any],
              let payloadType = propertyPayload["type"] as? String,
              ["file", "directory"].contains(payloadType.lowercased()),
              let rawValue = propertyPayload["value"] as? String,
              rawValue.isEmpty == false else {
            return nil
        }

        let candidateURL = URL(fileURLWithPath: rawValue)
            var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: candidateURL.path, isDirectory: &isDirectory) else {
            return nil
        }

        let normalizedPayloadType = payloadType.lowercased()
        if normalizedPayloadType == "directory", isDirectory.boolValue == false {
            return nil
        }
        if normalizedPayloadType == "file", isDirectory.boolValue {
            return nil
        }

        let resolvedURL: URL?
        if isDirectory.boolValue {
            resolvedURL = randomFileURL(in: candidateURL)
        } else {
            resolvedURL = candidateURL
        }
        guard let resolvedURL else { return nil }
        return absoluteLocalSchemeURL(for: resolvedURL)
    }

    /// 主线程只从后台枚举出的目录快照里取随机值：目录树遍历一律在
    /// directorySyncQueue 上进行（复用 fetchall 目录同步的枚举实现
    /// directorySyncStatus(forPath:)），不再随每次随机请求阻塞主线程。
    func randomFileURL(in directoryURL: URL) -> URL? {
        let cacheKey = randomFileCacheKey(for: directoryURL)
        guard let snapshot = randomFileSnapshotsByDirectoryPath[cacheKey] else {
            // 快照未就绪：触发后台补枚举，本轮让页面拿到空结果（与属性缺失
            // 同一条 fail-soft 路径），绝不在主线程同步遍历目录树。
            scheduleRandomFileSnapshotRefresh(for: directoryURL)
            return nil
        }
        scheduleRandomFileSnapshotRefresh(for: directoryURL)
        return snapshot.filesByPath.keys.randomElement()
            .map { URL(fileURLWithPath: $0).standardizedFileURL }
    }

    func resetRandomFileSnapshots() {
        randomFileSnapshotsByDirectoryPath.removeAll()
        randomFileSnapshotRefreshedAtByDirectoryPath.removeAll()
        randomFileEnumeratingDirectoryPaths.removeAll()
    }

    func refreshRandomFileSnapshots(using propertiesJSON: String?) {
        guard let propertiesJSON,
              let data = propertiesJSON.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return
        }
        for rawPayload in root.values {
            guard let payload = rawPayload as? [String: Any],
                  let payloadType = payload["type"] as? String,
                  payloadType.lowercased() == "directory",
                  let rawValue = payload["value"] as? String,
                  rawValue.isEmpty == false else {
                continue
            }
            scheduleRandomFileSnapshotRefresh(for: URL(fileURLWithPath: rawValue))
        }
    }

    private func randomFileCacheKey(for directoryURL: URL) -> String {
        directoryURL.resolvingSymlinksInPath().standardizedFileURL.path
    }

    private func scheduleRandomFileSnapshotRefresh(for directoryURL: URL) {
        let cacheKey = randomFileCacheKey(for: directoryURL)
        guard randomFileEnumeratingDirectoryPaths.contains(cacheKey) == false else { return }
        if let refreshedAt = randomFileSnapshotRefreshedAtByDirectoryPath[cacheKey],
           ProcessInfo.processInfo.systemUptime - refreshedAt < Self.randomFileSnapshotRefreshInterval {
            return
        }
        randomFileEnumeratingDirectoryPaths.insert(cacheKey)
        let requestID = currentRequest?.id
        let directoryPath = directoryURL.path
        directorySyncQueue.async { [weak self] in
            guard let self else { return }
            let status = self.directorySyncStatus(forPath: directoryPath)
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.randomFileEnumeratingDirectoryPaths.remove(cacheKey)
                // 请求已切换的旧枚举结果不落回快照，避免跨请求写入。
                guard self.currentRequest?.id == requestID else { return }
                self.randomFileSnapshotsByDirectoryPath[cacheKey] = status.snapshot
                self.randomFileSnapshotRefreshedAtByDirectoryPath[cacheKey] = ProcessInfo.processInfo.systemUptime
            }
        }
    }

    func absoluteLocalSchemeURL(for fileURL: URL) -> String {
        let normalizedURL = fileURL.resolvingSymlinksInPath().standardizedFileURL
        let segments = normalizedURL.path
            .split(separator: "/")
            .map { String($0).addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? String($0) }
            .joined(separator: "/")
        return "\(WebWallpaperHostSupport.localScheme)://wallpaper/__absolute__/\(segments)"
    }

    func applyCompatibilityState(to webView: WKWebView, deferDirectorySync _: Bool) {
        let propertiesJSON = currentRequest?.propertiesJSON ?? "{}"
        let screenID = screenID(for: webView)
        let screen = screenID.flatMap { targetID in
            NSScreen.screens.first { Self.screenID(for: $0) == targetID }
        }
        let generalPropertiesJSON = currentGeneralPropertiesJSON(for: screen, screenID: screenID)
        refreshReadableResourceRoots(using: propertiesJSON)
        syncFetchAllDirectoryProperties(using: propertiesJSON)
        let escapedProperties = WebWallpaperHostSupport.javaScriptQuotedString(propertiesJSON)
        let escapedGeneralProperties = WebWallpaperHostSupport.javaScriptQuotedString(generalPropertiesJSON)
        let volumeLiteral = String(format: "%.6f", currentVolume)
        let playbackRateLiteral = String(format: "%.6f", currentPlaybackRate)
        let pausedLiteral = paused ? "true" : "false"
        let spectrumLiteral: String
        if let levels = currentSpectrumLevels {
            let joinedLevels = levels.map { String(format: "%.6f", $0) }.joined(separator: ",")
            spectrumLiteral = "[\(joinedLevels)]"
        } else {
            spectrumLiteral = "null"
        }
        webView.evaluateJavaScript(
            """
            (() => {
              const properties = JSON.parse(\(escapedProperties));
              const generalProperties = JSON.parse(\(escapedGeneralProperties));
              window.__myWallpaperNotifyPluginLoaded('led');
              window.__myWallpaperNotifyPluginLoaded('rgb');
              if (typeof window.__myWallpaperApplyProperties === 'function') {
                window.__myWallpaperApplyProperties(properties);
              } else if (typeof window.__myWallpaperNormalizePropertyBag === 'function') {
                window.__myWallpaperLastUserProperties = window.__myWallpaperNormalizePropertyBag(properties);
              } else {
                window.__myWallpaperLastUserProperties = properties;
              }
              window.__myWallpaperApplyGeneralProperties(generalProperties);
              window.__myWallpaperSetGlobalVolume(\(volumeLiteral));
              window.__myWallpaperSetPlaybackRate(\(playbackRateLiteral));
              if (typeof window.__myWallpaperApplyInitialPausedState === 'function') {
                window.__myWallpaperApplyInitialPausedState(\(pausedLiteral));
              } else {
                window.__myWallpaperSetPaused(\(pausedLiteral));
              }
              const spectrum = \(spectrumLiteral);
              if (Array.isArray(spectrum)) {
                window.__myWallpaperPushAudioSpectrum(spectrum);
              }
            })();
            """,
            completionHandler: nil
        )
    }

    func applyPausedState(_ paused: Bool, to webView: WKWebView) {
        webView.setAllMediaPlaybackSuspended(paused, completionHandler: nil)
        let pausedLiteral = paused ? "true" : "false"
        webView.evaluateJavaScript(
            "window.__myWallpaperSetPaused(\(pausedLiteral));",
            completionHandler: nil
        )
        applyGeneralProperties(to: webView)
    }

    func applyProperties(_ propertiesJSON: String, to webView: WKWebView) {
        let escapedProperties = WebWallpaperHostSupport.javaScriptQuotedString(propertiesJSON)
        webView.evaluateJavaScript(
            """
            (() => {
              const properties = JSON.parse(\(escapedProperties));
              if (typeof window.__myWallpaperApplyProperties === 'function') {
                window.__myWallpaperApplyProperties(properties);
              }
            })();
            """,
            completionHandler: nil
        )
        applyGeneralProperties(to: webView)
    }

    func applyGeneralProperties(to webView: WKWebView) {
        let screenID = screenID(for: webView)
        let screen = screenID.flatMap { targetID in
            NSScreen.screens.first { Self.screenID(for: $0) == targetID }
        }
        let escapedGeneralProperties = WebWallpaperHostSupport.javaScriptQuotedString(currentGeneralPropertiesJSON(for: screen, screenID: screenID))
        webView.evaluateJavaScript(
            """
            (() => {
              const properties = JSON.parse(\(escapedGeneralProperties));
              if (typeof window.__myWallpaperApplyGeneralProperties === 'function') {
                window.__myWallpaperApplyGeneralProperties(properties);
              }
            })();
            """,
            completionHandler: nil
        )
    }

    func applyVolume(_ volume: Float, to webView: WKWebView) {
        let volumeLiteral = String(format: "%.6f", volume)
        webView.evaluateJavaScript(
            """
            if (typeof window.__myWallpaperSetGlobalVolume === 'function') {
              window.__myWallpaperSetGlobalVolume(\(volumeLiteral));
            }
            """,
            completionHandler: nil
        )
        applyGeneralProperties(to: webView)
    }

    func applyPlaybackRate(_ playbackRate: Float, to webView: WKWebView) {
        let playbackRateLiteral = String(format: "%.6f", playbackRate)
        webView.evaluateJavaScript(
            """
            if (typeof window.__myWallpaperSetPlaybackRate === 'function') {
              window.__myWallpaperSetPlaybackRate(\(playbackRateLiteral));
            }
            """,
            completionHandler: nil
        )
    }

    func pushAudioSpectrum(_ levels: [Float], to webView: WKWebView) {
        let levelLiterals = levels.map { String(format: "%.6f", $0) }.joined(separator: ",")
        webView.evaluateJavaScript(
            "window.__myWallpaperPushAudioSpectrum([\(levelLiterals)]);",
            completionHandler: nil
        )
    }

    /// 网络桥接配额桶的 frame 键：主 frame 固定 `main`，子 frame 用其文档源
    /// （`scheme://host:port`，同源子 frame 共桶）。键来自 WebKit 填充的
    /// `frameInfo`，页面无法把自己伪装成主 frame 去占用顶层配额。
    func networkBridgeFrameKey(for frameInfo: WKFrameInfo) -> String {
        guard frameInfo.isMainFrame == false else { return "main" }
        if let url = frameInfo.request.url, url.host?.isEmpty == false {
            return "frame:\(url.scheme ?? "")://\(url.host ?? ""):\(url.port ?? 0)"
        }
        return "frame:unknown"
    }

    /// 处理页面 postMessage 的网络桥接请求：白名单校验 → 连接 → 回包。
    ///
    /// 安全模型（DNS rebinding TOCTOU）：校验用 getaddrinfo 解析主机名并确认
    /// 全部地址为公网；如果连接阶段再由 URLSession 按主机名二次解析，短 TTL
    /// 域名可以先公网过检、连接时切到内网地址。这里对 http 把 URL 主机重写为
    /// 已校验 IP 并手动设置 Host 头，连接强制落在已校验地址上
    /// （`/private/tmp` 一次性探针实测：URLSession 尊重手动 Host 头，相对
    /// Location 按锁定 IP 基址解析并在重定向后保留 Host 头）。
    /// https 无法覆写 SNI/证书校验使用的主机名，仍按主机名连接——「校验后
    /// 重绑定」在 https 上是已知残余面，本批不消除，也不假装覆盖。
    ///
    /// 并发与生命周期（host-lifecycle-5）：每屏每 frame 的在飞请求受
    /// `networkBridgeMaxInflightRequestsPerScreen` 限制（配额按 frame 与 surface
    /// 世代隔离，见 WebNetworkBridgeInflightRegistry），超限走既有失败回包；单条请求
    /// 的窗口由空闲 10s（request.timeoutInterval）与资源总时限 10s
    /// （configuration.timeoutIntervalForResource，见 start()）共同封顶。完成回调按
    /// screenID 现查 surface，不再强持有 webView，surface 拆除后查 nil 即丢弃回包。
    /// `frameKey` 由调用方从 `WKScriptMessage.frameInfo` 派生（主 frame 与各子 frame
    /// 各自成桶）。
    func handleNetworkRequestMessage(_ body: [String: Any], webView: WKWebView, frameKey: String) {
        guard let requestID = body["requestID"] as? String,
              let rawURLString = body["url"] as? String,
              let url = URL(string: rawURLString),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme) else {
            resolveNetworkRequest(
                requestID: body["requestID"] as? String ?? "",
                payload: ["ok": false, "error": "invalid_url"],
                webView: webView
            )
            return
        }

        let method = ((body["method"] as? String) ?? "GET").uppercased()
        guard method == "GET" || method == "HEAD" else {
            resolveNetworkRequest(
                requestID: requestID,
                payload: ["ok": false, "error": "unsupported_method"],
                webView: webView
            )
            return
        }

        // 后续只按 screenID 现查 surface：WebKit 在主线程异步投递脚本消息，页面在
        // `removeSurface`（+Surface.swift）移除 surface 之后仍可能投递一条已排队的
        // 消息，此时该 webView 已无配额归属与可信回包目标，直接丢弃。
        guard let screenID = screenID(for: webView) else { return }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 10
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        // 与页面侧 `normalizedProxiedRequestHeaders` 的放行名单一致。
        // Authorization 等鉴权头本批不放行（显式产品决策，owner：网络桥接；
        // 退役条件：出现官方行为证据要求跨域携带凭据时单独立项）。
        if let headers = body["headers"] as? [String: String] {
            for (name, value) in headers {
                let loweredName = name.lowercased()
                guard ["accept", "accept-language", "content-type"].contains(loweredName) else {
                    continue
                }
                request.setValue(value, forHTTPHeaderField: name)
            }
        }
        if request.value(forHTTPHeaderField: "User-Agent") == nil {
            request.setValue(
                "Mozilla/5.0 (Macintosh; Intel Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) MyWallpaperX",
                forHTTPHeaderField: "User-Agent"
            )
        }

        let allowedHosts = allowedNetworkBridgeHosts()
        guard WebNetworkBridgeInflightRegistry.shared.admit(
            screenID,
            frameKey: frameKey,
            owner: webView,
            limit: Self.networkBridgeMaxInflightRequestsPerScreen
        ) else {
            resolveNetworkRequest(
                requestID: requestID,
                payload: ["ok": false, "error": "too_many_requests"],
                webView: webView
            )
            recordDiagnostic(
                type: "network.proxy.overloaded",
                severity: .warning,
                message: "\(method) \(rawURLString) too_many_requests",
                screenID: screenID,
                url: surfaces[screenID]?.webView.url?.absoluteString
            )
            return
        }

        // ownedWebView 只用于配额归属：弱捕获（实测内层闭包不扣留对象），不阻止
        // surface 拆除后 webView 释放，也不把 webView 带进任何强持有链。
        DispatchQueue.global(qos: .utility).async { [weak self, weak ownedWebView = webView] in
            guard let authorization = Self.authorizedNetworkBridgeRequest(
                request,
                allowedHosts: allowedHosts,
                reusing: nil
            ) else {
                Task { @MainActor in
                    WebNetworkBridgeInflightRegistry.shared.release(screenID, frameKey: frameKey, owner: ownedWebView)
                    guard let self, let webView = self.surfaces[screenID]?.webView else { return }
                    self.resolveNetworkRequest(
                        requestID: requestID,
                        payload: ["ok": false, "error": WebNetworkBridgeFailure.destinationNotAllowed.message],
                        webView: webView
                    )
                    self.recordDiagnostic(
                        type: "network.proxy.denied",
                        severity: .warning,
                        message: "\(method) \(rawURLString)",
                        screenID: screenID,
                        url: webView.url?.absoluteString
                    )
                }
                return
            }

            let bridgeRequest = WebNetworkBridgeRequest(
                authorization: authorization,
                maximumBodyBytes: Self.networkBridgeMaxBodyBytes,
                authorizeRedirect: { candidate, lock in
                    Self.authorizedNetworkBridgeRequest(
                        candidate,
                        allowedHosts: allowedHosts,
                        reusing: lock
                    )
                }
            ) { [weak self] result in
                Task { @MainActor in
                    WebNetworkBridgeInflightRegistry.shared.release(screenID, frameKey: frameKey, owner: ownedWebView)
                    guard let self, let webView = self.surfaces[screenID]?.webView else { return }
                    switch result {
                    case let .success(result):
                        var headerFields: [String: String] = [:]
                        for (key, value) in result.response.allHeaderFields {
                            guard let key = key as? String else { continue }
                            headerFields[key] = String(describing: value)
                        }
                        // 响应体统一 base64 回传并固定携带编码标志：按 UTF-8
                        // 可解码性二选一的旧编码没有标志，页面只能把响应体当
                        // 文本消费，非 UTF-8 二进制（图片/字体/音频）静默损坏。
                        // 统一编码后无二义性，页面侧按 bodyIsBase64 还原字节。
                        self.resolveNetworkRequest(
                            requestID: requestID,
                            payload: [
                                "ok": true,
                                "status": result.response.statusCode,
                                "headers": headerFields,
                                "body": result.body.base64EncodedString(),
                                "bodyIsBase64": true,
                                "responseURL": result.visibleURL.absoluteString
                            ],
                            webView: webView
                        )
                        self.recordDiagnostic(
                            type: "network.proxy",
                            severity: .info,
                            message: "\(method) \(rawURLString) status=\(result.response.statusCode) bytes=\(result.body.count)",
                            screenID: screenID,
                            url: webView.url?.absoluteString
                        )
                    case let .failure(failure):
                        self.resolveNetworkRequest(
                            requestID: requestID,
                            payload: ["ok": false, "error": failure.message],
                            webView: webView
                        )
                        self.recordDiagnostic(
                            type: failure == .responseTooLarge ? "network.proxy.too-large" : "network.proxy.error",
                            severity: .warning,
                            message: "\(method) \(rawURLString) \(failure.message)",
                            screenID: screenID,
                            url: webView.url?.absoluteString
                        )
                    }
                }
            }
            bridgeRequest.start()
        }
    }

    /// 校验网络桥接目标并生成实际连接请求；拒绝返回 nil。
    ///
    /// `reusing` 是当前连接正在使用的地址锁定：URLSession 把相对 Location 按
    /// 锁定基址解析（探针实测 `http://<已校验IP>/landing`），这类重定向的 URL
    /// 主机就是已校验地址本身，直接复用锁定，而不是拿 IP 去比对主机名白名单。
    private static func authorizedNetworkBridgeRequest(
        _ candidate: URLRequest,
        allowedHosts: Set<String>,
        reusing existingLock: WebNetworkBridgeAddressLock?
    ) -> WebNetworkBridgeAuthorization? {
        guard let url = candidate.url,
              url.user == nil,
              url.password == nil,
              let scheme = url.scheme?.lowercased(),
              let host = normalizedNetworkBridgeHost(url.host),
              scheme == "http" || scheme == "https" else {
            return nil
        }

        guard scheme == "http" else {
            // https：SNI 与证书校验绑定 URL 主机名，无法像 http 一样把连接锁到
            // 已校验 IP；保持主机名连接 + 全地址公网校验，TOCTOU 残余面登记在
            // handleNetworkRequestMessage 的函数头注释。
            guard allowedHosts.contains(host),
                  resolvesToPublicNetworkAddresses(host: host) else {
                return nil
            }
            return WebNetworkBridgeAuthorization(request: candidate, visibleURL: url, lock: nil)
        }

        let lock: WebNetworkBridgeAddressLock
        if let existingLock, host == existingLock.address {
            lock = existingLock
        } else {
            guard allowedHosts.contains(host),
                  let address = publicNetworkBridgeAddress(for: host) else {
                return nil
            }
            lock = WebNetworkBridgeAddressLock(host: host, address: address)
        }

        guard let visibleURL = replacingNetworkBridgeHost(in: url, with: lock.host, port: url.port),
              let pinnedURL = replacingNetworkBridgeHost(in: url, with: lock.address, port: url.port),
              let hostHeader = networkBridgeHostHeader(for: visibleURL) else {
            return nil
        }
        var request = candidate
        request.url = pinnedURL
        request.setValue(hostHeader, forHTTPHeaderField: "Host")
        return WebNetworkBridgeAuthorization(request: request, visibleURL: visibleURL, lock: lock)
    }

    /// 只替换 URL 的主机（端口不变），路径与查询保持原始百分号编码。
    /// IPv6 字面量需自行加方括号（URLComponents 不识别裸地址形式）。
    private static func replacingNetworkBridgeHost(in url: URL, with host: String, port: Int?) -> URL? {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }
        components.host = host.contains(":") ? "[\(host)]" : host
        components.port = port
        return components.url
    }

    /// Host 头的值：作者可见 URL 的 authority（主机名 + 显式端口）。
    private static func networkBridgeHostHeader(for url: URL) -> String? {
        guard let host = url.host else { return nil }
        guard let port = url.port else { return host }
        return "\(host):\(port)"
    }

    private func allowedNetworkBridgeHosts() -> Set<String> {
        guard let recordID = currentRequest?.recordID else {
            return []
        }
        return allowedNetworkBridgeHostsResolver?(recordID) ?? []
    }

    static func normalizedNetworkBridgeHost(_ rawHost: String?) -> String? {
        guard let rawHost else { return nil }
        let host = rawHost.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard host.isEmpty == false else { return nil }
        return host.hasSuffix(".") ? String(host.dropLast()) : host
    }

    private static func resolvesToPublicNetworkAddresses(host: String) -> Bool {
        publicNetworkBridgeAddress(for: host) != nil
    }

    /// getaddrinfo 解析主机名并返回可用的公网连接地址（IPv4 优先）；
    /// 任一解析结果落在非公网段、或没有任何地址时返回 nil。
    private static func publicNetworkBridgeAddress(for host: String) -> String? {
        var hints = addrinfo(
            ai_flags: AI_ADDRCONFIG,
            ai_family: AF_UNSPEC,
            ai_socktype: SOCK_STREAM,
            ai_protocol: 0,
            ai_addrlen: 0,
            ai_canonname: nil,
            ai_addr: nil,
            ai_next: nil
        )
        var results: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(host, nil, &hints, &results) == 0,
              let firstResult = results else {
            return nil
        }
        defer { freeaddrinfo(firstResult) }

        var ipv4Address: String?
        var ipv6Address: String?
        var currentResult: UnsafeMutablePointer<addrinfo>? = firstResult
        while let result = currentResult {
            let info = result.pointee
            guard let address = info.ai_addr else {
                currentResult = info.ai_next
                continue
            }
            switch info.ai_family {
            case AF_INET:
                let ipv4 = address.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee.sin_addr }
                let value = UInt32(bigEndian: ipv4.s_addr)
                guard isNonPublicIPv4Address(value) == false else { return nil }
                if ipv4Address == nil {
                    ipv4Address = dottedIPv4Address(value)
                }
            case AF_INET6:
                let ipv6 = address.withMemoryRebound(to: sockaddr_in6.self, capacity: 1) { $0.pointee.sin6_addr }
                let bytes = withUnsafeBytes(of: ipv6) { Array($0) }
                guard isNonPublicIPv6Address(bytes) == false else { return nil }
                if ipv6Address == nil {
                    ipv6Address = textualIPv6Address(bytes)
                }
            default:
                break
            }
            currentResult = info.ai_next
        }
        return ipv4Address ?? ipv6Address
    }

    private static func dottedIPv4Address(_ value: UInt32) -> String {
        "\((value >> 24) & 0xff).\((value >> 16) & 0xff).\((value >> 8) & 0xff).\(value & 0xff)"
    }

    private static func textualIPv6Address(_ bytes: [UInt8]) -> String? {
        guard bytes.count == MemoryLayout<in6_addr>.size else { return nil }
        var value = in6_addr()
        withUnsafeMutableBytes(of: &value) { destination in
            bytes.withUnsafeBytes { source in
                destination.copyBytes(from: source)
            }
        }
        var buffer = [CChar](repeating: 0, count: Int(INET6_ADDRSTRLEN))
        let text: UnsafePointer<CChar>? = withUnsafePointer(to: &value) { pointer in
            pointer.withMemoryRebound(to: UInt8.self, capacity: MemoryLayout<in6_addr>.size) { rawPointer in
                inet_ntop(AF_INET6, rawPointer, &buffer, socklen_t(buffer.count))
            }
        }
        guard let text else { return nil }
        return String(cString: text)
    }

    private static func isNonPublicIPv4Address(_ address: UInt32) -> Bool {
        let first = UInt8((address >> 24) & 0xff)
        let second = UInt8((address >> 16) & 0xff)
        let third = UInt8((address >> 8) & 0xff)
        if first == 0 || first == 10 || first == 127 || first >= 224 {
            return true
        }
        if first == 100, (64...127).contains(second) {
            return true
        }
        if first == 169, second == 254 {
            return true
        }
        if first == 172, (16...31).contains(second) {
            return true
        }
        if first == 192, second == 0, third == 0 {
            return true
        }
        if first == 192, second == 0, third == 2 {
            return true
        }
        if first == 192, second == 88, third == 99 {
            return true
        }
        if first == 192, second == 168 {
            return true
        }
        if first == 198, second == 18 || second == 19 || second == 51 {
            return true
        }
        return first == 203 && second == 0 && third == 113
    }

    private static func isNonPublicIPv6Address(_ bytes: [UInt8]) -> Bool {
        guard bytes.count == 16 else { return true }
        if bytes.allSatisfy({ $0 == 0 }) || (bytes.dropLast().allSatisfy({ $0 == 0 }) && bytes.last == 1) {
            return true
        }
        if bytes[0] & 0xfe == 0xfc || bytes[0] == 0xff || (bytes[0] == 0xfe && bytes[1] & 0xc0 == 0x80) {
            return true
        }
        if bytes[0] == 0x20, bytes[1] == 0x01, bytes[2] == 0x0d, bytes[3] == 0xb8 {
            return true
        }
        let isIPv4Mapped = bytes.prefix(10).allSatisfy { $0 == 0 } && bytes[10] == 0xff && bytes[11] == 0xff
        let isIPv4Compatible = bytes.prefix(12).allSatisfy { $0 == 0 }
        if isIPv4Mapped || isIPv4Compatible {
            let ipv4 = UInt32(bytes[12]) << 24 | UInt32(bytes[13]) << 16 | UInt32(bytes[14]) << 8 | UInt32(bytes[15])
            return isNonPublicIPv4Address(ipv4)
        }
        return false
    }

    private func resolveNetworkRequest(requestID: String, payload: [String: Any], webView: WKWebView) {
        guard requestID.isEmpty == false else { return }
        var responsePayload = payload
        responsePayload["requestID"] = requestID
        guard JSONSerialization.isValidJSONObject(responsePayload),
              let data = try? JSONSerialization.data(withJSONObject: responsePayload),
              let json = String(data: data, encoding: .utf8) else {
            return
        }
        webView.evaluateJavaScript(
            "window.__myWallpaperResolveNetworkRequest(\(json));",
            completionHandler: nil
        )
    }
}
