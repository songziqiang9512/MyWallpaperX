import Foundation
import WebKit

/// scheme task 的交付：resolve 与读文件在 IO 队列，didReceive/didFinish 回主线程。
extension WebWallpaperLocalSchemeHandler {
    private enum PreparedDelivery {
        case ready(PreparedResponse)
        case failure(Error)

        /// 取消发生在交付之前时，已打开的句柄必须显式关闭。
        func closeStreamedHandle() {
            guard case let .ready(prepared) = self, let streamedHandle = prepared.streamedHandle else { return }
            try? streamedHandle.close()
        }
    }

    private struct PreparedResponse {
        let response: HTTPURLResponse
        var resource: ResolvedResource
        let body: Data?
        /// 分块交付的已打开句柄；打开失败在 prepare 阶段就转为失败，不会先回 200。
        let streamedHandle: FileHandle?
        let streamedLength: Int64
        let cssServedDiagnostic: String?
    }

    /// `stop` 后不再回调：取消身份在交付链路每一步前复查。
    func startDelivery(
        for request: URLRequest,
        requestURL: URL,
        isHeadRequest: Bool,
        to urlSchemeTask: any WKURLSchemeTask,
        cancellation: RequestCancellation,
        webView: WKWebView
    ) {
        // 诊断出口在调用线程取一次，后台 prepare 不再读同一属性。
        let diagnosticHandler: WebRuntimeDiagnosticHandler? = self.diagnosticHandler
        ioQueue.async { [weak self] in
            guard let self else { return }
            let delivery = self.prepareDelivery(
                for: request,
                requestURL: requestURL,
                isHeadRequest: isHeadRequest,
                diagnosticHandler: diagnosticHandler
            )
            DispatchQueue.main.async {
                guard cancellation.isCancelled == false else {
                    // 被 stop 的请求不再交付，但拒绝原因仍要记账（改前 resolve 期即记账）。
                    if case let .failure(error) = delivery, let denied = error as? AccessDenied {

#if DEBUG
self.recordDeny(denied)
#endif

                    }
                    delivery.closeStreamedHandle()
                    self.finishRequest(urlSchemeTask)
                    return
                }
                self.deliver(
                    delivery,
                    requestURL: requestURL,
                    to: urlSchemeTask,
                    cancellation: cancellation,
                    webView: webView
                )
            }
        }
    }

    private func prepareDelivery(
        for request: URLRequest,
        requestURL: URL,
        isHeadRequest: Bool,
        diagnosticHandler: WebRuntimeDiagnosticHandler?
    ) -> PreparedDelivery {
        let outcome = resolveResource(for: requestURL, allowsDirectoryIndexFallback: true)
        guard let resolved = outcome.resource else {
            return .failure(outcome.denial ?? AccessDenied(
                reason: .invalidURL,
                requestURL: requestURL,
                candidateURL: nil,
                resolvedURL: nil
            ))
        }
        guard let resource = revalidatedResource(resolved) else {
            return .failure(AccessDenied(reason: .outsideAllowedRoots, requestURL: requestURL,
                candidateURL: resolved.fileURL, resolvedURL: resolved.fileURL))
        }
        if resource.didTraverseSymlink {
#if DEBUG
            diagnosticHandler?(
                "local-resource-symlink",
                .warning,
                "symlink_inside_allowed_root matchedRoot=\(resource.matchedRootPath) resolved=\(resource.fileURL.path)",
                requestURL
            )
#endif
        }

        let transformsResponse = WebWallpaperResponseTransformer.supportsTransformation(for: resource.fileURL)
        let mimeType = Self.mimeType(for: resource.fileURL)
        do {
            // 声明长度与验证器都以交付时刻的现取 stat 为准。
            guard let fileStat = Self.fileStat(for: resource.fileURL) else {
                return .failure(LocalSchemeError.unreadableFileSize)
            }
            let validators = Self.responseValidators(for: fileStat)
            var range = transformsResponse ? nil : try Self.byteRange(for: request, totalSize: fileStat.fileSize)
            if !isHeadRequest, Self.isNotModified(request: request, validators: validators) {
                return .ready(PreparedResponse(
                    response: try Self.makeNotModifiedResponse(for: requestURL, validators: validators),
                    resource: resource,
                    body: nil,
                    streamedHandle: nil,
                    streamedLength: 0,
                    cssServedDiagnostic: nil
                ))
            }
            let body: Data?
            let responseSize: Int64
            let deliveredLength: Int
            var streamedHandle: FileHandle?
            var streamedLength: Int64 = 0
            if !transformsResponse, !isHeadRequest {
                // 完整与 Range 响应共用同一有界交付链；范围和声明长度
                // 均取自已打开句柄，seek 后只交付选定窗口。
                let stream = try Self.openResponseStream(from: resource.fileURL, request: request)
                streamedHandle = stream.handle
                streamedLength = stream.length
                range = stream.range
                body = nil
                responseSize = stream.totalSize
                deliveredLength = Int(stream.length)
            } else if isHeadRequest, !transformsResponse {
                body = nil
                responseSize = fileStat.fileSize
                deliveredLength = range.map { Int($0.upperBound - $0.lowerBound + 1) } ?? Int(fileStat.fileSize)
            } else {
                let responseData = try Self.readResponseData(from: resource.fileURL, range: range)
                body = isHeadRequest ? nil : responseData
                responseSize = range == nil ? Int64(responseData.count) : fileStat.fileSize
                deliveredLength = responseData.count
            }
            return .ready(PreparedResponse(
                response: try Self.makeResponse(
                    for: requestURL,
                    mimeType: mimeType,
                    totalSize: responseSize,
                    range: range,
                    deliveredLength: deliveredLength,
                    acceptsRanges: !transformsResponse,
                    validators: validators
                ),
                resource: resource,
                body: body,
                streamedHandle: streamedHandle,
                streamedLength: streamedLength,
                cssServedDiagnostic: Self.cssServedDiagnostic(
                    fileURL: resource.fileURL,
                    fileSize: fileStat.fileSize,
                    mimeType: mimeType,
                    deliveredLength: deliveredLength,
                    range: range
                )
            ))
        } catch {
            return .failure(error)
        }
    }

    private func deliver(
        _ delivery: PreparedDelivery,
        requestURL: URL,
        to urlSchemeTask: any WKURLSchemeTask,
        cancellation: RequestCancellation,
        webView: WKWebView
    ) {
        guard !cancellation.isCancelled else {
            delivery.closeStreamedHandle()
            finishRequest(urlSchemeTask)
            return
        }
        switch delivery {
        case let .failure(error):
            // 416 先行：不可满足的 Range 是可恢复协议响应，不走
            // didFailWithError——那会触发媒体源摘除（pause+摘 src），
            // 把"seek 越界可重验证"变成资源永久死亡。
            if case let LocalSchemeError.rangeNotSatisfiable(totalSize) = error,
               let notSatisfiableResponse = try? Self.makeRangeNotSatisfiableResponse(
                   for: requestURL,
                   totalSize: totalSize
               ) {
                urlSchemeTask.didReceive(notSatisfiableResponse)
                guard !cancellation.isCancelled else { finishRequest(urlSchemeTask); return }
                finishRequest(urlSchemeTask)
                urlSchemeTask.didFinish()
#if DEBUG
                diagnosticHandler?("local-resource.range-not-satisfiable", .info, "totalSize=\(totalSize)", requestURL)
#endif
                return
            }
            if let denied = error as? AccessDenied {

#if DEBUG
recordDeny(denied)
#endif

            } else {
#if DEBUG
                diagnosticHandler?("local-resource-error", .warning, error.localizedDescription, requestURL)
#endif
            }
            silenceFailedMediaRequestIfNeeded(requestURL: requestURL, in: webView)
            finishRequest(urlSchemeTask)
            urlSchemeTask.didFailWithError(error)
        case let .ready(prepared):
            if readableRootsSnapshot().generation != prepared.resource.authorizationGeneration {
                ioQueue.async {
                    let resource = self.revalidatedResource(prepared.resource)
                    DispatchQueue.main.async {
                        guard let resource else {
                            delivery.closeStreamedHandle()
                            self.deliver(.failure(AccessDenied(reason: .outsideAllowedRoots, requestURL: requestURL,
                                candidateURL: prepared.resource.fileURL, resolvedURL: prepared.resource.fileURL)),
                                requestURL: requestURL, to: urlSchemeTask, cancellation: cancellation, webView: webView)
                            return
                        }
                        var refreshed = prepared
                        refreshed.resource = resource
                        self.deliver(.ready(refreshed), requestURL: requestURL, to: urlSchemeTask,
                            cancellation: cancellation, webView: webView)
                    }
                }
                return
            }
#if DEBUG
            if let message = prepared.cssServedDiagnostic, shouldRecordServedDiagnostic(for: requestURL) {
                diagnosticHandler?("local-resource.served", .info, message, requestURL)
            }
#endif
            urlSchemeTask.didReceive(prepared.response)
            guard !cancellation.isCancelled else {
                delivery.closeStreamedHandle()
                finishRequest(urlSchemeTask)
                return
            }
            if let streamedHandle = prepared.streamedHandle {
                streamNextChunk(
                    from: streamedHandle,
                    remaining: prepared.streamedLength,
                    to: urlSchemeTask,
                    cancellation: cancellation, resource: prepared.resource
                )
                return
            }
            if let body = prepared.body, body.isEmpty == false {
                urlSchemeTask.didReceive(body)
            }
            guard !cancellation.isCancelled else { finishRequest(urlSchemeTask); return }
            finishRequest(urlSchemeTask)
            urlSchemeTask.didFinish()
        }
    }

    /// Read on IO, publish on main. A changed grant set revalidates only this
    /// pinned resource; unrelated property resources do not interrupt its stream.
    private func streamNextChunk(
        from fileHandle: FileHandle,
        remaining: Int64,
        to urlSchemeTask: any WKURLSchemeTask,
        cancellation: RequestCancellation, resource: ResolvedResource
    ) {
        guard !cancellation.isCancelled else {
            try? fileHandle.close()
            finishRequest(urlSchemeTask)
            return
        }
        guard remaining > 0 else {
            try? fileHandle.close()
            finishRequest(urlSchemeTask)
            urlSchemeTask.didFinish()
            return
        }
        ioQueue.async { [weak self] in
            guard let self else { try? fileHandle.close(); return }
            guard !cancellation.isCancelled else {
                try? fileHandle.close()
                DispatchQueue.main.async { self.finishRequest(urlSchemeTask) }
                return
            }
            let current = self.readableRootsSnapshot().generation == resource.authorizationGeneration
                ? resource : self.revalidatedResource(resource)
            guard let current else {
                try? fileHandle.close()
                DispatchQueue.main.async {
                    self.finishRequest(urlSchemeTask)
                    if !cancellation.isCancelled {
                        urlSchemeTask.didFailWithError(AccessDenied(reason: .outsideAllowedRoots,
                            requestURL: urlSchemeTask.request.url ?? resource.fileURL,
                            candidateURL: resource.fileURL, resolvedURL: resource.fileURL))
                    }
                }
                return
            }
            let chunk = try? fileHandle.read(upToCount: Int(min(Int64(Self.deliveryChunkSize), remaining)))
            DispatchQueue.main.async {
                self.deliverStreamChunk(chunk, from: fileHandle, remaining: remaining, to: urlSchemeTask,
                    cancellation: cancellation, resource: current)
            }
        }
    }

    private func deliverStreamChunk(
        _ chunk: Data?, from fileHandle: FileHandle, remaining: Int64,
        to urlSchemeTask: any WKURLSchemeTask, cancellation: RequestCancellation,
        resource: ResolvedResource
    ) {
        guard !cancellation.isCancelled else {
            try? fileHandle.close()
            finishRequest(urlSchemeTask)
            return
        }
        if readableRootsSnapshot().generation != resource.authorizationGeneration {
            ioQueue.async {
                let current = self.revalidatedResource(resource)
                DispatchQueue.main.async {
                    guard let current else {
                        try? fileHandle.close()
                        self.finishRequest(urlSchemeTask)
                        if !cancellation.isCancelled {
                            urlSchemeTask.didFailWithError(AccessDenied(reason: .outsideAllowedRoots,
                                requestURL: urlSchemeTask.request.url ?? resource.fileURL,
                                candidateURL: resource.fileURL, resolvedURL: resource.fileURL))
                        }
                        return
                    }
                    self.deliverStreamChunk(chunk, from: fileHandle, remaining: remaining, to: urlSchemeTask,
                        cancellation: cancellation, resource: current)
                }
            }
            return
        }
        guard let chunk, !chunk.isEmpty else {
            try? fileHandle.close()
            finishRequest(urlSchemeTask)
            urlSchemeTask.didFailWithError(LocalSchemeError.truncatedDuringDelivery)
            return
        }
        urlSchemeTask.didReceive(chunk)
        // didReceive 可同步触发 WebKit stop；末块也不能再回调 didFinish。
        guard !cancellation.isCancelled else {
            try? fileHandle.close()
            finishRequest(urlSchemeTask)
            return
        }
        let nextRemaining = remaining - Int64(chunk.count)
        guard nextRemaining > 0 else {
            try? fileHandle.close()
            finishRequest(urlSchemeTask)
            urlSchemeTask.didFinish()
            return
        }
        streamNextChunk(from: fileHandle, remaining: nextRemaining, to: urlSchemeTask,
            cancellation: cancellation, resource: resource)
    }

    /// 打开、定长、解析 Range 与 seek 在同一句柄上完成，失败不泄漏 FD。
    /// 调用者仍负责资源授权；这里不产生新的可读根或缓存。
    static func openResponseStream(
        from fileURL: URL, request: URLRequest
    ) throws -> (handle: FileHandle, totalSize: Int64, range: ClosedRange<Int64>?, length: Int64) {
        let handle = try FileHandle(forReadingFrom: fileURL)
        do {
            guard let totalSize = streamedLength(of: handle) else {
                throw LocalSchemeError.unreadableFileSize
            }
            let range = try byteRange(for: request, totalSize: totalSize)
            if let range { try handle.seek(toOffset: UInt64(range.lowerBound)) }
            return (handle, totalSize, range, range.map { $0.upperBound - $0.lowerBound + 1 } ?? totalSize)
        } catch {
            try? handle.close()
            throw error
        }
    }

    static func byteRange(for request: URLRequest, totalSize: Int64) throws -> ClosedRange<Int64>? {
        guard totalSize > 0 else { return nil }
        guard let headerValue = request.value(forHTTPHeaderField: "Range")?.trimmingCharacters(in: .whitespacesAndNewlines),
              headerValue.isEmpty == false else {
            return nil
        }
        guard headerValue.hasPrefix("bytes=") else {
            throw LocalSchemeError.invalidRangeHeader
        }
        let rawRange = String(headerValue.dropFirst("bytes=".count))
        guard rawRange.contains(",") == false else {
            throw LocalSchemeError.unsupportedMultipartRange
        }
        let components = rawRange.split(separator: "-", omittingEmptySubsequences: false)
        guard components.count == 2 else {
            throw LocalSchemeError.invalidRangeHeader
        }

        let lowerText = String(components[0])
        let upperText = String(components[1])

        if lowerText.isEmpty {
            guard let suffixLength = Int64(upperText), suffixLength > 0 else {
                throw LocalSchemeError.invalidRangeHeader
            }
            let clampedLength = min(suffixLength, totalSize)
            let start = max(0, totalSize - clampedLength)
            return start...(totalSize - 1)
        }

        guard let start = Int64(lowerText), start >= 0, start < totalSize else {
            throw LocalSchemeError.rangeNotSatisfiable(totalSize: totalSize)
        }

        let end: Int64
        if upperText.isEmpty {
            end = totalSize - 1
        } else {
            guard let requestedEnd = Int64(upperText), requestedEnd >= start else {
                throw LocalSchemeError.invalidRangeHeader
            }
            end = min(requestedEnd, totalSize - 1)
        }
        return start...end
    }

    static func readFileData(from fileURL: URL, range: ClosedRange<Int64>?) throws -> Data {
        let fileHandle = try FileHandle(forReadingFrom: fileURL)
        defer {
            try? fileHandle.close()
        }
        if let range {
            try fileHandle.seek(toOffset: UInt64(range.lowerBound))
            let length = Int(range.upperBound - range.lowerBound + 1)
            return try fileHandle.read(upToCount: length) ?? Data()
        }
        return try fileHandle.readToEnd() ?? Data()
    }

    static func readResponseData(from fileURL: URL, range: ClosedRange<Int64>?) throws -> Data {
        let data = try readFileData(from: fileURL, range: range)
        guard range == nil else { return data }
        return WebWallpaperResponseTransformer.transform(data, fileURL: fileURL)
    }

    static func makeResponse(
        for requestURL: URL,
        mimeType: String,
        totalSize: Int64,
        range: ClosedRange<Int64>?,
        deliveredLength: Int,
        acceptsRanges: Bool = true,
        validators: ResponseValidators? = nil
    ) throws -> HTTPURLResponse {
        var headers: [String: String] = [
            "Content-Type": mimeType,
            "Cache-Control": "no-cache"
        ]
        if let validators {
            headers["ETag"] = validators.entityTag
            if let lastModified = validators.lastModified {
                headers["Last-Modified"] = lastModified
            }
        }
        if acceptsRanges {
            headers["Accept-Ranges"] = "bytes"
        }
        let statusCode: Int
        if let range {
            statusCode = 206
            headers["Content-Length"] = String(deliveredLength)
            headers["Content-Range"] = "bytes \(range.lowerBound)-\(range.upperBound)/\(totalSize)"
        } else {
            statusCode = 200
            headers["Content-Length"] = String(totalSize)
        }
        guard let response = HTTPURLResponse(
            url: requestURL,
            statusCode: statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: headers
        ) else {
            throw LocalSchemeError.invalidResponse
        }
        return response
    }

    /// 304 只回验证器与缓存指令，不带正文与 Content-Length。
    static func makeNotModifiedResponse(for requestURL: URL, validators: ResponseValidators) throws -> HTTPURLResponse {
        var headers: [String: String] = [
            "Cache-Control": "no-cache",
            "ETag": validators.entityTag
        ]
        if let lastModified = validators.lastModified {
            headers["Last-Modified"] = lastModified
        }
        guard let response = HTTPURLResponse(
            url: requestURL,
            statusCode: 304,
            httpVersion: "HTTP/1.1",
            headerFields: headers
        ) else {
            throw LocalSchemeError.invalidResponse
        }
        return response
    }

    /// 416（RFC 9110 §14.2）：不可满足的 Range 带
    /// `Content-Range: bytes */总长`、零长度正文——媒体 seek 越界（文件在
    /// 会话中被替换短版）是可恢复协议响应，客户端可据此重验证资源尺寸。
    static func makeRangeNotSatisfiableResponse(for requestURL: URL, totalSize: Int64) throws -> HTTPURLResponse {
        guard let response = HTTPURLResponse(
            url: requestURL,
            statusCode: 416,
            httpVersion: "HTTP/1.1",
            headerFields: [
                "Content-Length": "0",
                "Content-Range": "bytes */\(totalSize)"
            ]
        ) else {
            throw LocalSchemeError.invalidResponse
        }
        return response
    }

}
