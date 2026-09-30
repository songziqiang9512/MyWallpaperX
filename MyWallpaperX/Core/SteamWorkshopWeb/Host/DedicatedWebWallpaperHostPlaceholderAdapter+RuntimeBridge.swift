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
}

private final class WebNetworkBridgeRequest: NSObject, URLSessionDataDelegate, URLSessionTaskDelegate {
    private let request: URLRequest
    private let maximumBodyBytes: Int
    private let allowsURL: (URL) -> Bool
    private let completion: (Result<WebNetworkBridgeResponse, WebNetworkBridgeFailure>) -> Void
    private var session: URLSession?
    private var response: HTTPURLResponse?
    private var body = Data()
    private var failure: WebNetworkBridgeFailure?
    private var completed = false

    init(
        request: URLRequest,
        maximumBodyBytes: Int,
        allowsURL: @escaping (URL) -> Bool,
        completion: @escaping (Result<WebNetworkBridgeResponse, WebNetworkBridgeFailure>) -> Void
    ) {
        self.request = request
        self.maximumBodyBytes = maximumBodyBytes
        self.allowsURL = allowsURL
        self.completion = completion
    }

    func start() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
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
        task: URLSessionTask,
        willPerformHTTPRedirection _: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        guard let destinationURL = request.url, allowsURL(destinationURL) else {
            failure = .destinationNotAllowed
            completionHandler(nil)
            return
        }
        completionHandler(request)
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
        finish(.success(WebNetworkBridgeResponse(response: response, body: body)))
    }

    private func finish(_ result: Result<WebNetworkBridgeResponse, WebNetworkBridgeFailure>) {
        guard completed == false else { return }
        completed = true
        completion(result)
    }
}

extension DedicatedWebWallpaperHostPlaceholderAdapter {
    private static let networkBridgeMaxBodyBytes = 2 * 1024 * 1024

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

    func handleNetworkRequestMessage(_ body: [String: Any], webView: WKWebView) {
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

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 10
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
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
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard Self.allowsNetworkBridgeURL(url, allowedHosts: allowedHosts) else {
                Task { @MainActor in
                    guard let self else { return }
                    self.resolveNetworkRequest(
                        requestID: requestID,
                        payload: ["ok": false, "error": WebNetworkBridgeFailure.destinationNotAllowed.message],
                        webView: webView
                    )
                    self.recordDiagnostic(
                        type: "network.proxy.denied",
                        severity: .warning,
                        message: "\(method) \(rawURLString)",
                        screenID: self.screenID(for: webView),
                        url: webView.url?.absoluteString
                    )
                }
                return
            }

            let bridgeRequest = WebNetworkBridgeRequest(
                request: request,
                maximumBodyBytes: Self.networkBridgeMaxBodyBytes,
                allowsURL: { Self.allowsNetworkBridgeURL($0, allowedHosts: allowedHosts) }
            ) { [weak self] result in
                Task { @MainActor in
                    guard let self else { return }
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
                                "bodyIsBase64": true
                            ],
                            webView: webView
                        )
                        self.recordDiagnostic(
                            type: "network.proxy",
                            severity: .info,
                            message: "\(method) \(rawURLString) status=\(result.response.statusCode) bytes=\(result.body.count)",
                            screenID: self.screenID(for: webView),
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
                            screenID: self.screenID(for: webView),
                            url: webView.url?.absoluteString
                        )
                    }
                }
            }
            bridgeRequest.start()
        }
    }

    private func allowedNetworkBridgeHosts() -> Set<String> {
        guard let recordID = currentRequest?.recordID else {
            return []
        }
        return allowedNetworkBridgeHostsResolver?(recordID) ?? []
    }

    private static func allowsNetworkBridgeURL(_ url: URL, allowedHosts: Set<String>) -> Bool {
        guard url.user == nil,
              url.password == nil,
              let host = normalizedNetworkBridgeHost(url.host),
              allowedHosts.contains(host) else {
            return false
        }
        return resolvesToPublicNetworkAddresses(host: host)
    }

    static func normalizedNetworkBridgeHost(_ rawHost: String?) -> String? {
        guard let rawHost else { return nil }
        let host = rawHost.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard host.isEmpty == false else { return nil }
        return host.hasSuffix(".") ? String(host.dropLast()) : host
    }

    private static func resolvesToPublicNetworkAddresses(host: String) -> Bool {
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
            return false
        }
        defer { freeaddrinfo(firstResult) }

        var foundAddress = false
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
                if isNonPublicIPv4Address(UInt32(bigEndian: ipv4.s_addr)) {
                    return false
                }
                foundAddress = true
            case AF_INET6:
                let ipv6 = address.withMemoryRebound(to: sockaddr_in6.self, capacity: 1) { $0.pointee.sin6_addr }
                let bytes = withUnsafeBytes(of: ipv6) { Array($0) }
                if isNonPublicIPv6Address(bytes) {
                    return false
                }
                foundAddress = true
            default:
                break
            }
            currentResult = info.ai_next
        }
        return foundAddress
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
