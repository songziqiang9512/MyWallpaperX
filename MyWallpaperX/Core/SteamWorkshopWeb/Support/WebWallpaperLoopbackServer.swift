//
//  WebWallpaperLoopbackServer.swift
//  MyWallpaperX
//

import Foundation
import Network

final class WebWallpaperLoopbackServer {
    private let queue = DispatchQueue(label: "com.songziqiang.MyWallpaperX.web-loopback", qos: .userInitiated)
    private let schemeHandler: WebWallpaperLocalSchemeHandler
    private var listener: NWListener?
    private var pendingStartCompletion: ((Result<URL, Error>) -> Void)?
    private var startupTimeoutWorkItem: DispatchWorkItem?
    private(set) var port: UInt16?
    var diagnosticHandler: ((String, WebRuntimeDiagnosticEvent.Severity, String, URL?) -> Void)?

    init(schemeHandler: WebWallpaperLocalSchemeHandler) {
        self.schemeHandler = schemeHandler
    }

    /// 异步启动：端口就绪或失败经 completion（主队列）回报，超时 1 秒回退
    /// 语义与旧同步等待一致，但不再阻塞调用线程。端口已就绪时同步完成。
    func start(completion: @escaping (Result<URL, Error>) -> Void) {
        if let port,
           let url = URL(string: "http://127.0.0.1:\(port)/") {
            completion(.success(url))
            return
        }

        if listener == nil {
            let parameters = NWParameters.tcp
            parameters.acceptLocalOnly = true
            parameters.requiredLocalEndpoint = .hostPort(
                host: NWEndpoint.Host("127.0.0.1"),
                port: .any
            )
            do {
                let listener = try NWListener(using: parameters, on: .any)
                listener.stateUpdateHandler = { [weak self] state in
                    self?.handleListenerState(state)
                }
                listener.newConnectionHandler = { [weak self] connection in
                    self?.handle(connection)
                }
                listener.start(queue: queue)
                self.listener = listener
            } catch {
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
                return
            }
        }

        pendingStartCompletion = { result in
            DispatchQueue.main.async {
                completion(result)
            }
        }
        let timeoutWorkItem = DispatchWorkItem { [weak self] in
            guard let self,
                  let pendingCompletion = self.pendingStartCompletion else { return }
            self.pendingStartCompletion = nil
            self.startupTimeoutWorkItem = nil
            self.diagnosticHandler?("loopback.start.timeout", .error, "listener did not become ready", nil)
            self.listener?.cancel()
            self.listener = nil
            pendingCompletion(.failure(NSError(
                domain: "WebWallpaperLoopbackServer",
                code: 3,
                userInfo: [NSLocalizedDescriptionKey: "loopback_start_timeout"]
            )))
        }
        startupTimeoutWorkItem = timeoutWorkItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: timeoutWorkItem)
    }

    /// NWListener 回调在自建 queue 上；启动状态涉及的 completion/超时/端口
    /// 状态统一回主线程处理，与 start()/stop() 的调用线程保持一致。
    private func handleListenerState(_ state: NWListener.State) {
        DispatchQueue.main.async { [weak self] in
            self?.applyListenerState(state)
        }
    }

    private func applyListenerState(_ state: NWListener.State) {
        switch state {
        case .ready:
            port = listener?.port?.rawValue
            diagnosticHandler?("loopback.ready", .info, "port=\(port ?? 0)", nil)
            if let port,
               let url = URL(string: "http://127.0.0.1:\(port)/") {
                finishStartup(.success(url))
            } else {
                listener?.cancel()
                listener = nil
                finishStartup(.failure(NSError(
                    domain: "WebWallpaperLoopbackServer",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "loopback_port_unavailable"]
                )))
            }
        case let .failed(error):
            diagnosticHandler?("loopback.failed", .error, error.localizedDescription, nil)
            listener?.cancel()
            listener = nil
            finishStartup(.failure(error))
        case let .waiting(error):
            diagnosticHandler?("loopback.waiting", .warning, error.localizedDescription, nil)
        default:
            break
        }
    }

    private func finishStartup(_ result: Result<URL, Error>) {
        guard let pendingCompletion = pendingStartCompletion else { return }
        pendingStartCompletion = nil
        startupTimeoutWorkItem?.cancel()
        startupTimeoutWorkItem = nil
        pendingCompletion(result)
    }

    func stop() {
        startupTimeoutWorkItem?.cancel()
        startupTimeoutWorkItem = nil
        pendingStartCompletion = nil
        listener?.cancel()
        listener = nil
        port = nil
    }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: queue)
        receiveRequest(on: connection, buffer: Data())
    }

    private func receiveRequest(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 32 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            var nextBuffer = buffer
            if let data {
                nextBuffer.append(data)
            }
            if let error {
                self.sendError(500, message: error.localizedDescription, on: connection)
                return
            }
            if nextBuffer.range(of: Data("\r\n\r\n".utf8)) != nil || isComplete {
                self.respond(to: nextBuffer, on: connection)
                return
            }
            self.receiveRequest(on: connection, buffer: nextBuffer)
        }
    }

    private func respond(to requestData: Data, on connection: NWConnection) {
        guard let requestText = String(data: requestData, encoding: .utf8),
              let firstLine = requestText.components(separatedBy: "\r\n").first else {
            sendError(400, message: "bad_request", on: connection)
            return
        }

        let lineParts = firstLine.split(separator: " ", maxSplits: 2).map(String.init)
        guard lineParts.count >= 2 else {
            sendError(400, message: "bad_request", on: connection)
            return
        }
        let method = lineParts[0].uppercased()
        guard method == "GET" || method == "HEAD" else {
            sendError(405, message: "method_not_allowed", on: connection)
            return
        }

        let rawPath = normalizedRequestPath(lineParts[1])
        guard let requestURL = URL(string: "mwx-local://wallpaper\(rawPath)") else {
            sendError(400, message: "bad_url", on: connection)
            return
        }

        do {
            let fileURL = try schemeHandler.resolvedFileURL(for: requestURL, allowsDirectoryIndexFallback: true)
            let fileSize = try WebWallpaperLocalSchemeHandler.fileSize(for: fileURL)
            let rangeHeader = headerValue(named: "Range", in: requestText)
            var urlRequest = URLRequest(url: requestURL)
            if let rangeHeader {
                urlRequest.setValue(rangeHeader, forHTTPHeaderField: "Range")
            }
            let transformsResponse = WebWallpaperResponseTransformer.supportsTransformation(for: fileURL)
            let range = transformsResponse ? nil : try WebWallpaperLocalSchemeHandler.byteRange(for: urlRequest, totalSize: fileSize)
            let data: Data
            let responseSize: Int64
            let contentLength: Int64
            if method == "HEAD", !transformsResponse {
                data = Data()
                responseSize = fileSize
                contentLength = range.map { $0.upperBound - $0.lowerBound + 1 } ?? fileSize
            } else {
                let responseData = try WebWallpaperLocalSchemeHandler.readResponseData(from: fileURL, range: range)
                data = method == "HEAD" ? Data() : responseData
                responseSize = range == nil ? Int64(responseData.count) : fileSize
                contentLength = Int64(responseData.count)
            }
            let mimeType = WebWallpaperLocalSchemeHandler.mimeType(for: fileURL)
            sendHTTPResponse(
                statusCode: range == nil ? 200 : 206,
                mimeType: mimeType,
                totalSize: responseSize,
                range: range,
                body: data,
                contentLength: contentLength,
                acceptsRanges: !transformsResponse,
                on: connection
            )
        } catch {
            if schemeHandler.isOptionalMissingMediaRequest(requestURL) {
                diagnosticHandler?("loopback.resource.optional", .info, error.localizedDescription, requestURL)
            } else {
                diagnosticHandler?("loopback.resource.error", .warning, error.localizedDescription, requestURL)
            }
            sendError(404, message: error.localizedDescription, on: connection)
        }
    }

    private func normalizedRequestPath(_ rawTarget: String) -> String {
        if let absoluteURL = URL(string: rawTarget),
           absoluteURL.scheme?.hasPrefix("http") == true,
           let absoluteComponents = URLComponents(url: absoluteURL, resolvingAgainstBaseURL: false) {
            var components = URLComponents()
            components.percentEncodedPath = absoluteComponents.percentEncodedPath.isEmpty ? "/" : absoluteComponents.percentEncodedPath
            components.percentEncodedQuery = absoluteComponents.percentEncodedQuery
            return components.string ?? components.percentEncodedPath
        }
        return rawTarget.hasPrefix("/") ? rawTarget : "/\(rawTarget)"
    }

    private func sendHTTPResponse(
        statusCode: Int,
        mimeType: String,
        totalSize: Int64,
        range: ClosedRange<Int64>?,
        body: Data,
        contentLength: Int64,
        acceptsRanges: Bool,
        on connection: NWConnection
    ) {
        var headers = [
            "HTTP/1.1 \(statusCode) \(statusText(statusCode))",
            "Content-Type: \(mimeType)",
            "Content-Length: \(contentLength)",
            "Cache-Control: no-cache",
            "Access-Control-Allow-Origin: *",
            "Connection: close"
        ]
        if acceptsRanges {
            headers.append("Accept-Ranges: bytes")
        }
        if let range {
            headers.append("Content-Range: bytes \(range.lowerBound)-\(range.upperBound)/\(totalSize)")
        }
        send(Data((headers.joined(separator: "\r\n") + "\r\n\r\n").utf8) + body, on: connection)
    }

    private func sendError(_ statusCode: Int, message: String, on connection: NWConnection) {
        let body = Data(message.utf8)
        let headers = [
            "HTTP/1.1 \(statusCode) \(statusText(statusCode))",
            "Content-Type: text/plain; charset=utf-8",
            "Content-Length: \(body.count)",
            "Connection: close"
        ]
        send(Data((headers.joined(separator: "\r\n") + "\r\n\r\n").utf8) + body, on: connection)
    }

    private func send(_ data: Data, on connection: NWConnection) {
        connection.send(content: data, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private func headerValue(named name: String, in requestText: String) -> String? {
        let prefix = "\(name):"
        for line in requestText.components(separatedBy: "\r\n") {
            if line.range(of: prefix, options: [.caseInsensitive, .anchored]) != nil {
                return String(line.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return nil
    }

    private func statusText(_ statusCode: Int) -> String {
        switch statusCode {
        case 200: "OK"
        case 206: "Partial Content"
        case 400: "Bad Request"
        case 404: "Not Found"
        case 405: "Method Not Allowed"
        default: "Error"
        }
    }

}
