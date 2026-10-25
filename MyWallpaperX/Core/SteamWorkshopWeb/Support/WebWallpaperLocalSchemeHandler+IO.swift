import Foundation
import WebKit
import Darwin

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
            guard !cancellation.isCancelled else {
                DispatchQueue.main.async { self.finishRequest(urlSchemeTask) }
                return
            }
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
        guard var resolved = outcome.resource else {
            return .failure(outcome.denial ?? AccessDenied(
                reason: .invalidURL, requestURL: requestURL, candidateURL: nil, resolvedURL: nil))
        }
        do {
            let transformsResponse = WebWallpaperResponseTransformer.supportsTransformation(for: resolved.fileURL)
            let hasCondition = request.value(forHTTPHeaderField: "If-None-Match") != nil
                || request.value(forHTTPHeaderField: "If-Modified-Since") != nil
            if (isHeadRequest && !transformsResponse) || (!isHeadRequest && hasCondition) {
                // HEAD and an immediately reusable 304 need no open FD.
                if let current = revalidatedResource(resolved) {
                    resolved = current
                } else {
                    let refreshed = resolveResource(for: requestURL, allowsDirectoryIndexFallback: true,
                        refreshCachedResolution: true)
                    guard let current = refreshed.resource else {
                        throw refreshed.denial ?? AccessDenied(reason: .invalidURL, requestURL: requestURL,
                            candidateURL: nil, resolvedURL: nil)
                    }
                    resolved = current
                }
                let resource = resolved
                guard let stat = Self.fileStat(for: resource.fileURL) else {
                    throw LocalSchemeError.unreadableFileSize
                }
                let validators = Self.responseValidators(for: stat)
                if !isHeadRequest, Self.isNotModified(request: request, validators: validators) {
                    return .ready(PreparedResponse(
                        response: try Self.makeNotModifiedResponse(for: requestURL, validators: validators),
                        resource: resource, body: nil, streamedHandle: nil, streamedLength: 0, cssServedDiagnostic: nil))
                }
                if isHeadRequest && !WebWallpaperResponseTransformer.supportsTransformation(for: resource.fileURL) {
                    let range = try Self.byteRange(for: request, totalSize: stat.fileSize)
                    let length = range.map { $0.upperBound - $0.lowerBound + 1 } ?? stat.fileSize
                    return .ready(PreparedResponse(response: try Self.makeResponse(for: requestURL,
                        mimeType: Self.mimeType(for: resource.fileURL), totalSize: stat.fileSize,
                        range: range, deliveredLength: Int(length), validators: validators),
                        resource: resource, body: nil, streamedHandle: nil, streamedLength: 0, cssServedDiagnostic: nil))
                }
            }
            let opened = try openResponseStream(from: resolved, request: request)
            var transferredHandle = false
            defer { if !transferredHandle { try? opened.handle.close() } }
            let resource = opened.resource
            let stat = opened.stat
            let range = opened.range
            let transformsOpenedResponse = WebWallpaperResponseTransformer.supportsTransformation(for: resource.fileURL)
            let mimeType = Self.mimeType(for: resource.fileURL)
            let validators = Self.responseValidators(for: stat)
            if !isHeadRequest, Self.isNotModified(request: request, validators: validators) {
                return .ready(PreparedResponse(
                    response: try Self.makeNotModifiedResponse(for: requestURL, validators: validators),
                    resource: resource, body: nil, streamedHandle: nil, streamedLength: 0, cssServedDiagnostic: nil))
            }
            let body: Data?
            let responseSize: Int64
            let deliveredLength: Int
            if !transformsOpenedResponse {
                body = nil
                responseSize = stat.fileSize
                deliveredLength = Int(opened.length)
            } else {
                let data = try Self.readResponseData(from: opened.handle, fileURL: resource.fileURL, range: nil)
                body = isHeadRequest ? nil : data
                responseSize = Int64(data.count)
                deliveredLength = data.count
            }
            let prepared = PreparedResponse(response: try Self.makeResponse(for: requestURL,
                mimeType: mimeType, totalSize: responseSize,
                range: range, deliveredLength: deliveredLength, acceptsRanges: !transformsOpenedResponse,
                validators: validators), resource: resource, body: body,
                streamedHandle: transformsOpenedResponse || isHeadRequest ? nil : opened.handle,
                streamedLength: transformsOpenedResponse || isHeadRequest ? 0 : opened.length,
                cssServedDiagnostic: Self.cssServedDiagnostic(fileURL: resource.fileURL, fileSize: stat.fileSize,
                    mimeType: mimeType, deliveredLength: deliveredLength, range: range))
            transferredHandle = prepared.streamedHandle != nil
#if DEBUG
            if resource.didTraverseSymlink {
                diagnosticHandler?("local-resource-symlink", .warning,
                    "symlink_inside_allowed_root matchedRoot=\(resource.matchedRootPath) resolved=\(resource.fileURL.path)", requestURL)
            }
#endif
            return .ready(prepared)
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

    /// Bind the actual opened file once, then keep this handle through body
    /// transformation or streaming. A grant revision does not detect a path
    /// replaced by a symlink; FD pathname and regular-file facts do.
    func openResponseStream(
        from resource: ResolvedResource, request: URLRequest
    ) throws -> (resource: ResolvedResource, handle: FileHandle, stat: FileStat,
                 range: ClosedRange<Int64>?, length: Int64) {
        var resource = resource
        var descriptor = Darwin.open(resource.fileURL.path, O_RDONLY | O_NONBLOCK | O_CLOEXEC)
        if descriptor < 0 {
            let openError = errno
            guard (openError == ENOENT || openError == ENOTDIR), let requestURL = request.url else {
                throw NSError(domain: NSPOSIXErrorDomain, code: Int(openError))
            }
            // A cached location can disappear while a current spelling or
            // compatibility candidate exists. Retry the original resolver once
            // only after a real missing-path open; authorization failures below
            // never enter this branch or search for another candidate.
            let refreshed = resolveResource(for: requestURL, allowsDirectoryIndexFallback: true,
                refreshCachedResolution: true)
            guard let current = refreshed.resource else {
                throw refreshed.denial ?? AccessDenied(reason: .invalidURL, requestURL: requestURL,
                    candidateURL: nil, resolvedURL: nil)
            }
            resource = current
            descriptor = Darwin.open(resource.fileURL.path, O_RDONLY | O_NONBLOCK | O_CLOEXEC)
            guard descriptor >= 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
        }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        do {
            var facts = stat()
            guard fstat(descriptor, &facts) == 0, facts.st_size >= 0 else {
                throw LocalSchemeError.unreadableFileSize
            }
            guard facts.st_mode & S_IFMT == S_IFREG else {
                throw AccessDenied(reason: .notRegularFile, requestURL: request.url ?? resource.fileURL,
                    candidateURL: resource.fileURL, resolvedURL: resource.fileURL)
            }
            var path = [CChar](repeating: 0, count: Int(MAXPATHLEN))
            guard fcntl(descriptor, F_GETPATH, &path) == 0 else { throw LocalSchemeError.unreadableFileSize }
            let actualURL = URL(fileURLWithPath: String(
                decoding: path.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)).standardizedFileURL
            let (grants, generation) = readableRootsSnapshot()
            guard let matchedRootPath = matchedReadableRootPath(for: actualURL, roots: grants) else {
                throw AccessDenied(reason: .outsideAllowedRoots, requestURL: request.url ?? resource.fileURL,
                    candidateURL: resource.fileURL, resolvedURL: actualURL)
            }
            let didTraverseSymlink = resource.didTraverseSymlink
                || Self.isMaterialPathRewrite(from: resource.fileURL.path, to: actualURL.path)
            guard !strictSymlinkPolicy || !didTraverseSymlink else {
                throw AccessDenied(reason: .symlinkRejected, requestURL: request.url ?? resource.fileURL,
                    candidateURL: resource.fileURL, resolvedURL: actualURL)
            }
            let current = ResolvedResource(fileURL: actualURL, didTraverseSymlink: didTraverseSymlink,
                matchedRootPath: matchedRootPath, authorizationGeneration: generation)
            let fileStat = FileStat(fileSize: Int64(facts.st_size), modificationDate: Date(
                timeIntervalSince1970: Double(facts.st_mtimespec.tv_sec)
                    + Double(facts.st_mtimespec.tv_nsec) / 1_000_000_000))
            let range = WebWallpaperResponseTransformer.supportsTransformation(for: actualURL)
                ? nil : try Self.byteRange(for: request, totalSize: fileStat.fileSize)
            if let range { try handle.seek(toOffset: UInt64(range.lowerBound)) }
            return (current, handle, fileStat, range, range.map { $0.upperBound - $0.lowerBound + 1 } ?? fileStat.fileSize)
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

    static func readResponseData(from fileHandle: FileHandle, fileURL: URL, range: ClosedRange<Int64>?) throws -> Data {
        let data: Data
        if let range {
            let length = Int(range.upperBound - range.lowerBound + 1)
            data = try fileHandle.read(upToCount: length) ?? Data()
        } else {
            data = try fileHandle.readToEnd() ?? Data()
        }
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
