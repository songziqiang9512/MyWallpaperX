//
//  WebWallpaperLoopbackServer+Connection.swift
//  MyWallpaperX
//

import Foundation
import Network

extension WebWallpaperLoopbackServer {
    /// 单个连接的全部可变状态；只在 `queue` 上访问，因此不同连接互不阻塞。
    final class ConnectionContext {
        let connection: NWConnection
        let queue: DispatchQueue
        var bufferedRequestData = Data()
        var servedRequestCount = 0
        var idleTimeoutWorkItem: DispatchWorkItem?
        /// 当前请求头阶段已扫描过的起始偏移：收据只追加，终结符搜索从上一轮
        /// 尾部回退 3 字节继续，避免对整个增长缓冲反复全扫（O(n²)）。
        var headerScanStartIndex: Int = 0
        /// 当前请求头阶段是否已武装空闲超时；每阶段只武装一次，收集期间
        /// 不再按收据重挂（滴流字节不能无限续命）。
        var headerTimeoutArmed = false

        init(connection: NWConnection, queue: DispatchQueue) {
            self.connection = connection
            self.queue = queue
        }
    }

    /// 超过该长度的无 Range 请求改流式发送，避免整读进内存。
    static let streamingThreshold: Int64 = 64 * 1024 * 1024
    static let connectionChunkSize = 1 << 20
    static let maxRequestsPerConnection = 64
    static let idleConnectionTimeout: TimeInterval = 5
    static let headerTerminator = Data("\r\n\r\n".utf8)
    /// 未完成请求头的累积上限：授权检查发生在头收集完成之后，未认证的
    /// 本机连接不得在等待 `\r\n\r\n` 期间无限占内存。
    static let maxRequestHeaderBytes = 64 * 1024

    /// 名额归还的一次性闸：NWConnection 终态在个别 teardown 路径可能
    /// `.failed` 后再派发 `.cancelled`，同一连接只允许归还一次名额。
    /// 不持有 connection，无环。
    final class ConnectionSlotReleaseGuard {
        var released = false
    }

    /// listener 的 accept 队列在这里交棒：连接后续读写都在自己的串行队列上。
    func handle(_ connection: NWConnection) {
        // 连接数上限：WKWebView 对单 host 的并发远低于该值，超限连接只可能
        // 来自本机进程的可用性攻击面（每连接一个串行队列与 FD），直接拒绝。
        guard claimActiveConnectionSlot() else {
            connection.cancel()
            return
        }
        let queue = DispatchQueue(
            label: "com.songziqiang.MyWallpaperX.web-loopback.connection",
            qos: .userInitiated
        )
        let context = ConnectionContext(connection: connection, queue: queue)
        let slotReleaseGuard = ConnectionSlotReleaseGuard()
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .cancelled, .failed:
                guard slotReleaseGuard.released == false else { return }
                slotReleaseGuard.released = true
                self?.releaseActiveConnectionSlot()
            default:
                break
            }
        }
        connection.start(queue: queue)
        receiveRequest(on: context)
    }

    private func receiveRequest(on context: ConnectionContext, isComplete: Bool = false) {
        // keep-alive 下同一连接的后续请求（含已到达的 pipelined 字节）直接处理。
        let scanStart = max(0, context.headerScanStartIndex)
        if let headerRange = context.bufferedRequestData.range(
            of: Self.headerTerminator,
            options: [],
            in: scanStart..<context.bufferedRequestData.count
        ) {
            respondToRequestHeader(in: context, headerRange: headerRange)
            return
        }
        // 终结符可能跨收据分界：下一轮从回退一个终结符长度的位置继续扫。
        context.headerScanStartIndex = max(0, context.bufferedRequestData.count - (Self.headerTerminator.count - 1))
        if isComplete {
            sendError(400, message: "bad_request", on: context)
            return
        }
        if context.headerTimeoutArmed == false {
            context.headerTimeoutArmed = true
            scheduleIdleTimeout(for: context)
        }
        context.connection.receive(minimumIncompleteLength: 1, maximumLength: 32 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let data {
                context.bufferedRequestData.append(data)
            }
            guard error == nil else {
                self.sendError(500, message: error?.localizedDescription ?? "receive_failed", on: context)
                return
            }
            guard context.bufferedRequestData.count <= Self.maxRequestHeaderBytes else {
                self.sendError(431, message: "header_too_large", on: context)
                return
            }
            self.receiveRequest(on: context, isComplete: isComplete)
        }
    }

    private func respondToRequestHeader(in context: ConnectionContext, headerRange: Range<Data.Index>) {
        context.idleTimeoutWorkItem?.cancel()
        context.idleTimeoutWorkItem = nil
        let headerData = Data(context.bufferedRequestData[0..<headerRange.lowerBound])
        let leftover = Data(context.bufferedRequestData[headerRange.upperBound...])
        context.bufferedRequestData = Data()
        // 下一请求头阶段重新武装扫描与超时（pipelined leftover 也按新阶段起算）。
        context.headerScanStartIndex = 0
        context.headerTimeoutArmed = false
        guard let requestText = String(data: headerData, encoding: .utf8) else {
            sendError(400, message: "bad_request", on: context)
            return
        }
        respond(to: requestText, leftover: leftover, on: context)
    }

    private func respond(to requestText: String, leftover: Data, on context: ConnectionContext) {
        guard let firstLine = requestText.components(separatedBy: "\r\n").first else {
            sendError(400, message: "bad_request", on: context)
            return
        }
        let lineParts = firstLine.split(separator: " ", maxSplits: 2).map(String.init)
        guard lineParts.count >= 2 else {
            sendError(400, message: "bad_request", on: context)
            return
        }
        let method = lineParts[0].uppercased()
        guard method == "GET" || method == "HEAD" else {
            sendError(405, message: "method_not_allowed", on: context)
            return
        }
        let cookieHeader = headerValue(named: "Cookie", in: requestText)
        guard let requestPath = authorizedRequestPath(lineParts[1], cookieHeader: cookieHeader) else {
            diagnosticHandler?("loopback.request.rejected", .warning, "reason=missing_access_token", nil)
            sendError(403, message: "forbidden", on: context)
            return
        }
        guard let requestURL = URL(string: "mwx-local://wallpaper\(requestPath)") else {
            sendError(400, message: "bad_url", on: context)
            return
        }

        let outcome = schemeHandler.resolveResource(for: requestURL, allowsDirectoryIndexFallback: true)
        guard let resource = outcome.resource else {
            let denial = outcome.denial ?? WebWallpaperLocalSchemeHandler.AccessDenied(
                reason: .invalidURL,
                requestURL: requestURL,
                candidateURL: nil,
                resolvedURL: nil
            )
            schemeHandler.recordDeny(denial)
            respondWithResourceFailure(denial, requestURL: requestURL, on: context)
            return
        }

        do {
            // keep-alive 到量关闭：本连接第 maxRequestsPerConnection 个请求的响应
            // 必须显式声明 `Connection: close`，否则客户端会继续复用随后被关闭的
            // 连接（第 65 个请求以连接错误告终）。
            let keepAlive = shouldKeepConnectionAlive(requestText: requestText, firstLine: firstLine)
                && context.servedRequestCount + 1 < Self.maxRequestsPerConnection
            try sendResourceResponse(
                resource,
                method: method,
                requestText: requestText,
                requestURL: requestURL,
                keepAlive: keepAlive,
                leftover: leftover,
                on: context
            )
        } catch {
            respondWithResourceFailure(error, requestURL: requestURL, on: context)
        }
    }

    private func sendResourceResponse(
        _ resource: WebWallpaperLocalSchemeHandler.ResolvedResource,
        method: String,
        requestText: String,
        requestURL: URL,
        keepAlive: Bool,
        leftover: Data,
        on context: ConnectionContext
    ) throws {
        let isHeadRequest = method == "HEAD"
        let transformsResponse = WebWallpaperResponseTransformer.supportsTransformation(for: resource.fileURL)
        var urlRequest = URLRequest(url: requestURL)
        if let rangeHeader = headerValue(named: "Range", in: requestText) {
            urlRequest.setValue(rangeHeader, forHTTPHeaderField: "Range")
        }
        // 声明长度与验证器都以交付时刻的现取 stat 为准。
        guard let fileStat = WebWallpaperLocalSchemeHandler.fileStat(for: resource.fileURL) else {
            throw WebWallpaperLocalSchemeHandler.LocalSchemeError.unreadableFileSize
        }
        let range = transformsResponse
            ? nil
            : try WebWallpaperLocalSchemeHandler.byteRange(for: urlRequest, totalSize: fileStat.fileSize)
        let mimeType = WebWallpaperLocalSchemeHandler.mimeType(for: resource.fileURL)
        let validators = WebWallpaperLocalSchemeHandler.responseValidators(for: fileStat)

        if !isHeadRequest, WebWallpaperLocalSchemeHandler.isNotModified(
            ifNoneMatch: headerValue(named: "If-None-Match", in: requestText),
            ifModifiedSince: headerValue(named: "If-Modified-Since", in: requestText),
            validators: validators
        ) {
            sendNotModifiedResponse(validators: validators, keepAlive: keepAlive, on: context) { [weak self] in
                self?.continueAfterResponse(on: context, leftover: leftover, keepAlive: keepAlive)
            }
            return
        }

        if range == nil, !transformsResponse, !isHeadRequest, fileStat.fileSize > Self.streamingThreshold {
            streamFile(resource.fileURL, mimeType: mimeType, validators: validators, requestURL: requestURL, on: context)
            return
        }

        let body: Data
        let responseSize: Int64
        let contentLength: Int64
        if isHeadRequest, !transformsResponse {
            body = Data()
            responseSize = fileStat.fileSize
            contentLength = range.map { $0.upperBound - $0.lowerBound + 1 } ?? fileStat.fileSize
        } else {
            let responseData = try WebWallpaperLocalSchemeHandler.readResponseData(from: resource.fileURL, range: range)
            body = isHeadRequest ? Data() : responseData
            responseSize = range == nil ? Int64(responseData.count) : fileStat.fileSize
            contentLength = Int64(responseData.count)
        }
        // 会话标记只在 HTML 文档响应上下发：拿到入口文档的客户端才有资格用
        // 无前缀的 Web 根绝对路径访问受控资源（见 authorizedRequestPath）。
        let sessionCookie = mimeType.hasPrefix("text/html") ? accessCookieHeader : nil
        sendHTTPResponse(
            statusCode: range == nil ? 200 : 206,
            mimeType: mimeType,
            totalSize: responseSize,
            range: range,
            body: body,
            contentLength: contentLength,
            acceptsRanges: !transformsResponse,
            validators: validators,
            keepAlive: keepAlive,
            sessionCookie: sessionCookie,
            on: context
        ) { [weak self] in
            self?.continueAfterResponse(on: context, leftover: leftover, keepAlive: keepAlive)
        }
    }

    private func continueAfterResponse(on context: ConnectionContext, leftover: Data, keepAlive: Bool) {
        context.servedRequestCount += 1
        guard keepAlive, context.servedRequestCount < Self.maxRequestsPerConnection else {
            context.connection.cancel()
            return
        }
        context.bufferedRequestData = leftover
        receiveRequest(on: context)
    }

    /// HTTP/1.1 且未声明 `Connection: close`、无非零请求体时才复用连接。
    /// 请求体不做解析，带体的请求响应后即关闭，避免把请求体当作下一个请求。
    private func shouldKeepConnectionAlive(requestText: String, firstLine: String) -> Bool {
        guard firstLine.hasSuffix("HTTP/1.1") else { return false }
        if let connectionHeader = headerValue(named: "Connection", in: requestText),
           connectionHeader.lowercased().contains("close") {
            return false
        }
        if let contentLength = headerValue(named: "Content-Length", in: requestText),
           let length = Int(contentLength),
           length > 0 {
            return false
        }
        return true
    }

    private func respondWithResourceFailure(_ error: Error, requestURL: URL, on context: ConnectionContext) {
        if schemeHandler.isOptionalMissingMediaRequest(requestURL) {
            diagnosticHandler?("loopback.resource.optional", .info, error.localizedDescription, requestURL)
        } else {
            diagnosticHandler?("loopback.resource.error", .warning, error.localizedDescription, requestURL)
        }
        sendError(404, message: error.localizedDescription, on: context)
    }

    /// 流式分支同样以句柄实际长度为声明长度，保证 Content-Length 与实际发送一致。
    private func streamFile(
        _ fileURL: URL,
        mimeType: String,
        validators: WebWallpaperLocalSchemeHandler.ResponseValidators,
        requestURL: URL,
        on context: ConnectionContext
    ) {
        guard let fileHandle = try? FileHandle(forReadingFrom: fileURL),
              let streamedLength = WebWallpaperLocalSchemeHandler.streamedLength(of: fileHandle) else {
            sendError(404, message: "unreadable_local_resource", on: context)
            return
        }
        var headers = [
            "HTTP/1.1 200 OK",
            "Content-Type: \(mimeType)",
            "Content-Length: \(streamedLength)",
            "Cache-Control: no-cache",
            "ETag: \(validators.entityTag)"
        ]
        if let lastModified = validators.lastModified {
            headers.append("Last-Modified: \(lastModified)")
        }
        headers.append("Accept-Ranges: bytes")
        headers.append("Connection: close")
        send(Data((headers.joined(separator: "\r\n") + "\r\n\r\n").utf8), on: context) { [weak self] in
            self?.streamNextChunk(from: fileHandle, remaining: streamedLength, requestURL: requestURL, on: context)
        }
    }

    /// 读一块→发一块链式推进；send 完成才读下一块，天然限流不堆积内存。
    private func streamNextChunk(
        from fileHandle: FileHandle,
        remaining: Int64,
        requestURL: URL,
        on context: ConnectionContext
    ) {
        let chunk = try? fileHandle.read(upToCount: Int(min(Int64(Self.connectionChunkSize), remaining)))
        guard let chunk, chunk.isEmpty == false else {
            try? fileHandle.close()
            // 声明长度尚未读满就 EOF（文件在交付中被改写/截断）：与自定义 scheme
            // 路径的 truncatedDuringDelivery 同语义的失败。响应头已发出、无法再改
            // 状态码，只能留诊断并关闭连接，绝不把截断体当正常结束静默交付。
            if remaining > 0 {
                diagnosticHandler?(
                    "loopback.stream.truncated",
                    .warning,
                    "truncated_during_delivery remaining=\(remaining)",
                    requestURL
                )
                context.connection.cancel()
                return
            }
            finishStream(on: context)
            return
        }
        context.connection.send(content: chunk, completion: .contentProcessed { [weak self] error in
            guard let self else { return }
            guard error == nil else {
                try? fileHandle.close()
                context.connection.cancel()
                return
            }
            let nextRemaining = remaining - Int64(chunk.count)
            guard nextRemaining > 0 else {
                try? fileHandle.close()
                self.finishStream(on: context)
                return
            }
            self.streamNextChunk(from: fileHandle, remaining: nextRemaining, requestURL: requestURL, on: context)
        })
    }

    /// 末块后显式 final-message（FIN）再关闭，保持 200 + Content-Length 语义。
    private func finishStream(on context: ConnectionContext) {
        context.connection.send(
            content: nil,
            contentContext: .finalMessage,
            isComplete: true,
            completion: .contentProcessed { _ in
                context.connection.cancel()
            }
        )
    }

    private func sendHTTPResponse(
        statusCode: Int,
        mimeType: String,
        totalSize: Int64,
        range: ClosedRange<Int64>?,
        body: Data,
        contentLength: Int64,
        acceptsRanges: Bool,
        validators: WebWallpaperLocalSchemeHandler.ResponseValidators,
        keepAlive: Bool,
        sessionCookie: String?,
        on context: ConnectionContext,
        completion: @escaping () -> Void
    ) {
        var headers = [
            "HTTP/1.1 \(statusCode) \(statusText(statusCode))",
            "Content-Type: \(mimeType)",
            "Content-Length: \(contentLength)",
            "Cache-Control: no-cache",
            "ETag: \(validators.entityTag)"
        ]
        if let lastModified = validators.lastModified {
            headers.append("Last-Modified: \(lastModified)")
        }
        if let sessionCookie {
            headers.append("Set-Cookie: \(sessionCookie)")
        }
        if keepAlive == false {
            headers.append("Connection: close")
        }
        if acceptsRanges {
            headers.append("Accept-Ranges: bytes")
        }
        if let range {
            headers.append("Content-Range: bytes \(range.lowerBound)-\(range.upperBound)/\(totalSize)")
        }
        send(Data((headers.joined(separator: "\r\n") + "\r\n\r\n").utf8) + body, on: context, completion: completion)
    }

    /// 304 不带正文与 Content-Length；同源页面无需 CORS 头。
    private func sendNotModifiedResponse(
        validators: WebWallpaperLocalSchemeHandler.ResponseValidators,
        keepAlive: Bool,
        on context: ConnectionContext,
        completion: @escaping () -> Void
    ) {
        var headers = [
            "HTTP/1.1 304 Not Modified",
            "Cache-Control: no-cache",
            "ETag: \(validators.entityTag)"
        ]
        if let lastModified = validators.lastModified {
            headers.append("Last-Modified: \(lastModified)")
        }
        if keepAlive == false {
            headers.append("Connection: close")
        }
        send(Data((headers.joined(separator: "\r\n") + "\r\n\r\n").utf8), on: context, completion: completion)
    }

    private func sendError(_ statusCode: Int, message: String, on context: ConnectionContext) {
        let body = Data(message.utf8)
        let headers = [
            "HTTP/1.1 \(statusCode) \(statusText(statusCode))",
            "Content-Type: text/plain; charset=utf-8",
            "Content-Length: \(body.count)",
            "Connection: close"
        ]
        send(Data((headers.joined(separator: "\r\n") + "\r\n\r\n").utf8) + body, on: context) {
            context.connection.cancel()
        }
    }

    private func send(_ data: Data, on context: ConnectionContext, completion: @escaping () -> Void) {
        context.connection.send(content: data, completion: .contentProcessed { _ in
            completion()
        })
    }

    private func scheduleIdleTimeout(for context: ConnectionContext) {
        context.idleTimeoutWorkItem?.cancel()
        let workItem = DispatchWorkItem {
            context.connection.cancel()
        }
        context.idleTimeoutWorkItem = workItem
        context.queue.asyncAfter(deadline: .now() + Self.idleConnectionTimeout, execute: workItem)
    }

}
