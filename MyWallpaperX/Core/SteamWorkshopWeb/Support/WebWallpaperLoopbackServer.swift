//
//  WebWallpaperLoopbackServer.swift
//  MyWallpaperX
//

import Foundation
import Network

final class WebWallpaperLoopbackServer {
    /// listener 只负责 accept；连接读写各自在自己的串行队列（＋Connection）。
    private let listenerQueue = DispatchQueue(label: "com.songziqiang.MyWallpaperX.web-loopback", qos: .userInitiated)
    /// 启动期生成的 128-bit token：只有拿到入口 URL 的页面能用前缀访问受控资源。
    let accessToken: String
    let schemeHandler: WebWallpaperLocalSchemeHandler
    private var listener: NWListener?
    /// 同一次启动尝试的完成回调统一在这里排队；重入 `start()` 只会追加，不再覆盖。
    private var pendingStartCompletions: [(Result<URL, Error>) -> Void] = []
    private var startupTimeoutWorkItem: DispatchWorkItem?
    private(set) var port: UInt16?
    var diagnosticHandler: ((String, WebRuntimeDiagnosticEvent.Severity, String, URL?) -> Void)?

    init(schemeHandler: WebWallpaperLocalSchemeHandler) {
        self.schemeHandler = schemeHandler
        self.accessToken = Self.makeAccessToken()
    }

    /// 请求路径的强制前缀；入口 URL 与页面内相对路径都从它派生。
    var accessPathPrefix: String {
        "/mwx-\(accessToken)/"
    }

    /// 会话标记 cookie 名：入口 HTML 响应以 `Set-Cookie` 下发，页面在 origin 下
    /// 以 `/` 开头的绝对路径（`<img src="/x">`、`fetch('/x')`、`new URL('/x', origin)`）
    /// 因此仍可访问受控资源。
    static let accessCookieName = "mwx-access"

    /// 会话 cookie 的 `Set-Cookie` 文本。`SameSite=Strict` 是第二因子的关键：
    /// 跨站页面发起的请求不会携带它，未持有 token 的本机进程也拿不到，两者保持
    /// 无前缀 403；代价是跨源子 frame 仍拿不到无前缀资源（与既有 token 模型一致）。
    var accessCookieHeader: String {
        "\(Self.accessCookieName)=\(accessToken); Path=/; SameSite=Strict"
    }

    /// 异步启动：端口就绪或失败经 completion（主队列）回报，超时 1 秒回退。
    /// 同一启动尝试内的多个 completion 共享同一结果。
    func start(completion: @escaping (Result<URL, Error>) -> Void) {
        if let port,
           let url = Self.loopbackURL(port: port, accessPathPrefix: accessPathPrefix) {
            completion(.success(url))
            return
        }

        let createdListener: Bool
        if listener == nil {
            let listener: NWListener
            do {
                listener = try Self.makeListener()
            } catch {
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
                return
            }
            listener.stateUpdateHandler = { [weak self, weak listener] state in
                guard let listener else { return }
                self?.handleListenerState(state, from: listener)
            }
            listener.newConnectionHandler = { [weak self] connection in
                self?.handle(connection)
            }
            listener.start(queue: listenerQueue)
            self.listener = listener
            createdListener = true
        } else {
            createdListener = false
        }

        pendingStartCompletions.append { result in
            DispatchQueue.main.async {
                completion(result)
            }
        }
        // 只有新建 listener 的那次调用武装超时看门狗；后续重入沿用同一窗口。
        guard createdListener else { return }
        let timeoutWorkItem = DispatchWorkItem { [weak self] in
            self?.handleStartupTimeout()
        }
        startupTimeoutWorkItem = timeoutWorkItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: timeoutWorkItem)
    }

    /// NWListener 回调在自建 queue 上；启动状态涉及的 completion/超时/端口
    /// 状态统一回主线程处理，与 start()/stop() 的调用线程保持一致。
    private func handleListenerState(_ state: NWListener.State, from listener: NWListener) {
        DispatchQueue.main.async { [weak self] in
            self?.applyListenerState(state, from: listener)
        }
    }

    private func applyListenerState(_ state: NWListener.State, from listener: NWListener) {
        // 被 cancel/替换的 listener 的迟到回调不得影响当前启动。
        guard listener === self.listener else { return }
        switch state {
        case .ready:
            guard let port = listener.port?.rawValue,
                  let url = Self.loopbackURL(port: port, accessPathPrefix: accessPathPrefix) else {
                listener.cancel()
                self.listener = nil
                diagnosticHandler?("loopback.failed", .error, "loopback_port_unavailable", nil)
                finishStartup(.failure(NSError(
                    domain: "WebWallpaperLoopbackServer",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "loopback_port_unavailable"]
                )))
                return
            }
            self.port = port
            diagnosticHandler?("loopback.ready", .info, "port=\(port)", nil)
            finishStartup(.success(url))
        case let .failed(error):
            diagnosticHandler?("loopback.failed", .error, error.localizedDescription, nil)
            listener.cancel()
            self.listener = nil
            finishStartup(.failure(error))
        case let .waiting(error):
            diagnosticHandler?("loopback.waiting", .warning, error.localizedDescription, nil)
        default:
            break
        }
    }

    private func handleStartupTimeout() {
        guard pendingStartCompletions.isEmpty == false else { return }
        diagnosticHandler?("loopback.start.timeout", .error, "listener did not become ready", nil)
        listener?.cancel()
        listener = nil
        finishStartup(.failure(NSError(
            domain: "WebWallpaperLoopbackServer",
            code: 3,
            userInfo: [NSLocalizedDescriptionKey: "loopback_start_timeout"]
        )))
    }

    private func finishStartup(_ result: Result<URL, Error>) {
        guard pendingStartCompletions.isEmpty == false else { return }
        let completions = pendingStartCompletions
        pendingStartCompletions.removeAll()
        startupTimeoutWorkItem?.cancel()
        startupTimeoutWorkItem = nil
        for completion in completions {
            completion(result)
        }
    }

    func stop() {
        startupTimeoutWorkItem?.cancel()
        startupTimeoutWorkItem = nil
        pendingStartCompletions.removeAll()
        listener?.cancel()
        listener = nil
        port = nil
    }

    /// 请求目标只有在带 `/mwx-<token>/` 前缀、或携带本服务器的会话标记 cookie 时
    /// 才放行，返回剥离前缀（无前缀时即 Web 根相对路径）后的路径（含 query）。
    /// absolute-form 也按其中的路径判定，避免绕过前缀检查。
    ///
    /// 无前缀放行只服务「loopback 页面 origin 下以 `/` 开头的绝对路径」这一类请求：
    /// 页面 origin 是 `http://127.0.0.1:<port>`（不含 token 前缀），资源改写层只把
    /// 绝对文件路径改写成 `mwx-local://…`，Web 根绝对路径原样下发。放行要求携带入口
    /// HTML 响应下发的 `SameSite=Strict` 会话 cookie（`accessCookieHeader`）：跨站
    /// 页面无法携带它，不持有 token 的本机进程也拿不到，两者仍按无前缀 403 拒绝。
    func authorizedRequestPath(_ rawTarget: String, cookieHeader: String?) -> String? {
        let rawPath: String
        let rawQuery: String?
        if let absoluteURL = URL(string: rawTarget),
           absoluteURL.scheme?.hasPrefix("http") == true,
           let components = URLComponents(url: absoluteURL, resolvingAgainstBaseURL: false) {
            rawPath = components.percentEncodedPath.isEmpty ? "/" : components.percentEncodedPath
            rawQuery = components.percentEncodedQuery
        } else {
            let parts = rawTarget.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)
            rawPath = parts.first.map(String.init) ?? ""
            rawQuery = parts.count > 1 ? String(parts[1]) : nil
        }

        let prefix = accessPathPrefix
        if rawPath.hasPrefix(prefix) {
            var requestPath = "/" + rawPath.dropFirst(prefix.count)
            if let rawQuery {
                requestPath += "?\(rawQuery)"
            }
            return requestPath
        }
        guard Self.hasAccessCookie(cookieHeader, token: accessToken) else { return nil }
        var requestPath = rawPath.hasPrefix("/") ? rawPath : "/" + rawPath
        if let rawQuery {
            requestPath += "?\(rawQuery)"
        }
        return requestPath
    }

    /// 会话 cookie 匹配：按 `;` 分段做名字（大小写不敏感）与值（大小写敏感）比较，
    /// 只认本服务器的 token。
    private static func hasAccessCookie(_ cookieHeader: String?, token: String) -> Bool {
        guard let cookieHeader else { return false }
        for field in cookieHeader.split(separator: ";") {
            let parts = field.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2,
                  parts[0].trimmingCharacters(in: .whitespaces).caseInsensitiveCompare(accessCookieName) == .orderedSame else {
                continue
            }
            return parts[1].trimmingCharacters(in: .whitespaces) == token
        }
        return false
    }

    /// HTTP 文本助手：请求头取值与状态行文案（＋Connection 复用）。
    func headerValue(named name: String, in requestText: String) -> String? {
        let prefix = "\(name):"
        for line in requestText.components(separatedBy: "\r\n") {
            if line.range(of: prefix, options: [.caseInsensitive, .anchored]) != nil {
                return String(line.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return nil
    }

    func statusText(_ statusCode: Int) -> String {
        switch statusCode {
        case 200: "OK"
        case 206: "Partial Content"
        case 304: "Not Modified"
        case 400: "Bad Request"
        case 403: "Forbidden"
        case 404: "Not Found"
        case 405: "Method Not Allowed"
        default: "Error"
        }
    }

    private static func makeAccessToken() -> String {
        var bytes = [UInt8](repeating: 0, count: 16)
        for index in bytes.indices {
            bytes[index] = UInt8.random(in: .min ... .max)
        }
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    private static func makeListener() throws -> NWListener {
        let parameters = NWParameters.tcp
        parameters.acceptLocalOnly = true
        parameters.requiredLocalEndpoint = .hostPort(
            host: NWEndpoint.Host("127.0.0.1"),
            port: .any
        )
        return try NWListener(using: parameters, on: .any)
    }

    private static func loopbackURL(port: UInt16, accessPathPrefix: String) -> URL? {
        URL(string: "http://127.0.0.1:\(port)\(accessPathPrefix)")
    }
}
