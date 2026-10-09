//
//  WebWallpaperLocalSchemeHandler+Resolve.swift
//  MyWallpaperX
//

import Foundation
import Dispatch

/// resolve 及其派生数据：受控读取判定、resolve 缓存、由 size+mtime 派生的
/// 响应验证器（ETag/Last-Modified/条件请求）。
extension WebWallpaperLocalSchemeHandler {
    /// 交付时刻的现取 stat：声明长度与 ETag/Last-Modified 都基于它，
    /// 缓存里不带 size/mtime（缓存过期不得变成错误长度或陈旧验证器）。
    struct FileStat {
        let fileSize: Int64
        let modificationDate: Date?
    }

    static func fileStat(for fileURL: URL) -> FileStat? {
        guard let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]),
              let fileSize = values.fileSize else {
            return nil
        }
        return FileStat(fileSize: Int64(fileSize), modificationDate: values.contentModificationDate)
    }

    /// resolve 缓存条目：只存路径身份与受控读取判定结果。
    struct CachedResolution {
        let resource: ResolvedResource
        let storedAtUptimeNanoseconds: UInt64

        func isFresh(nowUptimeNanoseconds: UInt64) -> Bool {
            let ttlNanoseconds = UInt64(WebWallpaperLocalSchemeHandler.resolveCacheTTL * 1_000_000_000)
            return nowUptimeNanoseconds &- storedAtUptimeNanoseconds <= ttlNanoseconds
        }
    }

    /// 响应验证器：由 size+mtime 派生，供 ETag/Last-Modified 与条件请求复用。
    struct ResponseValidators {
        let entityTag: String
        let lastModified: String?
        let modificationDate: Date?
    }

    /// 解析请求 URL 到受控文件；拒绝原因随返回值带回，调用方负责 `recordDeny`。
    ///
    /// 缓存键带 `readableRootsGeneration`：受控读取判定完全由
    /// `updateAdditionalReadableRoots` 决定，根集合每次变更都会让旧条目不可达，
    /// 因此缓存命中不会绕过 root 校验。
    func resolveResource(for requestURL: URL, allowsDirectoryIndexFallback: Bool) -> ResolveOutcome {
        let (roots, generation) = readableRootsSnapshot()
        let cacheKey = Self.resolveCacheKey(
            for: requestURL,
            allowsDirectoryIndexFallback: allowsDirectoryIndexFallback,
            generation: generation
        )
        if let cached = cachedResolution(forKey: cacheKey) {
            return ResolveOutcome(resource: cached, denial: nil)
        }
        let outcome = computeResolution(
            for: requestURL,
            allowsDirectoryIndexFallback: allowsDirectoryIndexFallback,
            roots: roots
        )
        if let resource = outcome.resource {
            storeCachedResolution(resource, forKey: cacheKey)
        }
        return outcome
    }

    /// mwx-local 请求路径的解码合同：三条生产路径（入口构造、
    /// randomFile/__absolute__ 逐段编码、页面 encodeURIComponent）都恰好编码
    /// 一次，这里恰好解码一次。不用 `URL.path`——它把段内 `%2F` 解码成路径
    /// 分隔符，也不做第二次整体 `removingPercentEncoding`——那会把字面
    /// `%XX` 文件名解析到错误路径并让缓存键互相碰撞。
    static func decodedRequestPath(for requestURL: URL) -> String {
        guard let components = URLComponents(url: requestURL, resolvingAgainstBaseURL: false) else {
            return requestURL.path
        }
        return components.percentEncodedPath
            .split(separator: "/", omittingEmptySubsequences: false)
            .map { $0.removingPercentEncoding ?? String($0) }
            .joined(separator: "/")
    }

    static func resolveCacheKey(
        for requestURL: URL,
        allowsDirectoryIndexFallback: Bool,
        generation: UInt64
    ) -> String {
        return "\(generation)|\(allowsDirectoryIndexFallback ? 1 : 0)|\(Self.decodedRequestPath(for: requestURL))"
    }

    func readableRootsSnapshot() -> (roots: [URL], generation: UInt64) {
        stateLock.lock()
        defer { stateLock.unlock() }
        return (additionalReadableRoots, readableRootsGeneration)
    }

    func cachedResolution(forKey cacheKey: String) -> ResolvedResource? {
        stateLock.lock()
        defer { stateLock.unlock() }
        guard let cached = resolveCache[cacheKey] else { return nil }
        guard cached.isFresh(nowUptimeNanoseconds: DispatchTime.now().uptimeNanoseconds) else {
            resolveCache.removeValue(forKey: cacheKey)
            return nil
        }
        return cached.resource
    }

    func storeCachedResolution(_ resource: ResolvedResource, forKey cacheKey: String) {
        let storedAt = DispatchTime.now().uptimeNanoseconds
        stateLock.lock()
        defer { stateLock.unlock() }
        // 未信任页面可以持续制造唯一路径，缓存必须有硬上限（条目只在命中过 resolve 后写入）。
        if resolveCache.count >= Self.resolveCacheCapacity {
            resolveCache.removeAll(keepingCapacity: true)
        }
        resolveCache[cacheKey] = CachedResolution(resource: resource, storedAtUptimeNanoseconds: storedAt)
    }

    private func computeResolution(
        for requestURL: URL,
        allowsDirectoryIndexFallback: Bool,
        roots: [URL]
    ) -> ResolveOutcome {
        let decodedPath = Self.decodedRequestPath(for: requestURL)
        let originalURL: URL
        if decodedPath.hasPrefix("/__absolute__/") {
            let absolutePath = "/" + decodedPath.dropFirst("/__absolute__/".count)
            originalURL = URL(fileURLWithPath: absolutePath).standardizedFileURL
        } else if let compatibleAbsoluteURL = allowedAbsoluteCompatibilityURL(for: decodedPath, roots: roots) {
            originalURL = compatibleAbsoluteURL
        } else {
            let relativePath = decodedPath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            originalURL = rootURL
                .appendingPathComponent(relativePath, isDirectory: false)
                .standardizedFileURL
        }
        let requestedURL = originalURL.resolvingSymlinksInPath().standardizedFileURL
        let resolvedRequestedURL = existingFileURL(for: originalURL)
            ?? compatibilityFallbackFileURL(for: originalURL)
            ?? requestedURL
        var isDirectory: ObjCBool = false
        let targetURL: URL
        if FileManager.default.fileExists(atPath: resolvedRequestedURL.path, isDirectory: &isDirectory), isDirectory.boolValue {
            guard allowsDirectoryIndexFallback else {
                return .denied(AccessDenied(
                    reason: .directoryWithoutIndex,
                    requestURL: requestURL,
                    candidateURL: originalURL,
                    resolvedURL: resolvedRequestedURL
                ))
            }
            targetURL = existingFileURL(for: resolvedRequestedURL.appendingPathComponent("index.html", isDirectory: false))
                ?? resolvedRequestedURL.appendingPathComponent("index.html", isDirectory: false)
        } else {
            targetURL = resolvedRequestedURL
        }
        let normalizedTargetURL = targetURL.resolvingSymlinksInPath().standardizedFileURL
        let didTraverseSymlink = Self.isMaterialPathRewrite(from: originalURL.path, to: requestedURL.path) ||
            Self.isMaterialPathRewrite(from: targetURL.standardizedFileURL.path, to: normalizedTargetURL.path)
        if didTraverseSymlink, strictSymlinkPolicy {
            return .denied(AccessDenied(
                reason: .symlinkRejected,
                requestURL: requestURL,
                candidateURL: originalURL,
                resolvedURL: normalizedTargetURL
            ))
        }
        guard let matchedRootPath = matchedReadableRootPath(for: normalizedTargetURL, roots: roots) else {
            let reason: AccessDenyReason = didTraverseSymlink ? .outsideRootAfterSymlink : .outsideAllowedRoots
            return .denied(AccessDenied(
                reason: reason,
                requestURL: requestURL,
                candidateURL: originalURL,
                resolvedURL: normalizedTargetURL
            ))
        }
        var isTargetDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: normalizedTargetURL.path, isDirectory: &isTargetDirectory) else {
            return .denied(AccessDenied(
                reason: .missing,
                requestURL: requestURL,
                candidateURL: originalURL,
                resolvedURL: normalizedTargetURL
            ))
        }
        let resourceValues = try? normalizedTargetURL.resourceValues(forKeys: [.isRegularFileKey])
        guard !isTargetDirectory.boolValue, resourceValues?.isRegularFile == true else {
            return .denied(AccessDenied(
                reason: .notRegularFile,
                requestURL: requestURL,
                candidateURL: originalURL,
                resolvedURL: normalizedTargetURL
            ))
        }
        return .resolved(ResolvedResource(
            fileURL: normalizedTargetURL,
            didTraverseSymlink: didTraverseSymlink,
            matchedRootPath: matchedRootPath
        ))
    }

    /// 大小写/变音符不敏感地逐段求证真实路径；未命中时逐组件查目录。
    func existingFileURL(for candidateURL: URL) -> URL? {
        let standardizedCandidateURL = candidateURL.resolvingSymlinksInPath().standardizedFileURL
        if FileManager.default.fileExists(atPath: standardizedCandidateURL.path) {
            return standardizedCandidateURL
        }

        let pathComponents = standardizedCandidateURL.pathComponents.filter { $0 != "/" }
        guard !pathComponents.isEmpty else {
            return nil
        }

        var resolvedURL = URL(fileURLWithPath: "/", isDirectory: true)
        for component in pathComponents {
            let exactURL = resolvedURL.appendingPathComponent(component, isDirectory: false)
            if FileManager.default.fileExists(atPath: exactURL.path) {
                resolvedURL = exactURL
                continue
            }

            guard let directoryContents = try? FileManager.default.contentsOfDirectory(
                at: resolvedURL,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ) else {
                return nil
            }

            guard let matchedURL = directoryContents.first(where: {
                $0.lastPathComponent.compare(component, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
            }) else {
                return nil
            }
            resolvedURL = matchedURL
        }

        let standardizedResolvedURL = resolvedURL.resolvingSymlinksInPath().standardizedFileURL
        return FileManager.default.fileExists(atPath: standardizedResolvedURL.path) ? standardizedResolvedURL : nil
    }

    private func compatibilityFallbackFileURL(for originalURL: URL) -> URL? {
        let relativePath: String
        let originalPath = originalURL.standardizedFileURL.path
        let rootPath = rootURL.path
        if originalPath == rootPath {
            relativePath = ""
        } else if originalPath.hasPrefix(rootPath + "/") {
            relativePath = String(originalPath.dropFirst(rootPath.count + 1))
        } else {
            return nil
        }

        let lowerRelativePath = relativePath.lowercased()
        let candidateURL: URL?
        switch lowerRelativePath {
        case "background.png":
            candidateURL = rootURL
                .appendingPathComponent("image", isDirectory: true)
                .appendingPathComponent("bg.png", isDirectory: false)
        case "spine-player.js":
            candidateURL = rootURL.appendingPathComponent("spine-player4.1.js", isDirectory: false)
        default:
            if lowerRelativePath.hasPrefix("map/") {
                candidateURL = rootURL
                    .appendingPathComponent("Default Content", isDirectory: true)
                    .appendingPathComponent(relativePath, isDirectory: false)
            } else {
                candidateURL = nil
            }
        }

        guard let candidateURL else { return nil }
        return existingFileURL(for: candidateURL)
    }

    private func allowedAbsoluteCompatibilityURL(for decodedPath: String, roots: [URL]) -> URL? {
        let supportedPrefixes = ["/Users/", "/Volumes/", "/private/", "/tmp/", "/var/"]
        guard supportedPrefixes.contains(where: { decodedPath.hasPrefix($0) }) else {
            return nil
        }

        let candidateURL = URL(fileURLWithPath: decodedPath).standardizedFileURL
        let resolvedCandidateURL = candidateURL.resolvingSymlinksInPath().standardizedFileURL
        guard matchedReadableRootPath(for: resolvedCandidateURL, roots: roots) != nil else {
            return nil
        }
        return candidateURL
    }

    private func matchedReadableRootPath(for targetURL: URL, roots: [URL]) -> String? {
        let targetPath = targetURL.resolvingSymlinksInPath().standardizedFileURL.path
        let rootPath = rootURL.path
        if targetPath == rootPath || targetPath.hasPrefix(rootPath + "/") {
            return rootPath
        }
        for readableRoot in roots {
            let readablePath = readableRoot.path
            if targetPath == readablePath || targetPath.hasPrefix(readablePath + "/") {
                return readablePath
            }
        }
        return nil
    }

    private static func isMaterialPathRewrite(from originalPath: String, to resolvedPath: String) -> Bool {
        guard originalPath != resolvedPath else { return false }
        return originalPath.compare(resolvedPath, options: [.caseInsensitive, .diacriticInsensitive]) != .orderedSame
    }

    static func responseValidators(for stat: FileStat) -> ResponseValidators {
        ResponseValidators(
            entityTag: entityTag(fileSize: stat.fileSize, modificationDate: stat.modificationDate),
            lastModified: stat.modificationDate.map { httpDateString(from: $0) },
            modificationDate: stat.modificationDate
        )
    }

    static func entityTag(fileSize: Int64, modificationDate: Date?) -> String {
        guard let modificationDate else { return "\"\(fileSize)\"" }
        return "\"\(fileSize)-\(Int64(modificationDate.timeIntervalSince1970))\""
    }

    /// `If-None-Match` 优先于 `If-Modified-Since`（RFC 9110 §13.1.3）。
    static func isNotModified(request: URLRequest, validators: ResponseValidators) -> Bool {
        isNotModified(
            ifNoneMatch: request.value(forHTTPHeaderField: "If-None-Match"),
            ifModifiedSince: request.value(forHTTPHeaderField: "If-Modified-Since"),
            validators: validators
        )
    }

    static func isNotModified(
        ifNoneMatch: String?,
        ifModifiedSince: String?,
        validators: ResponseValidators
    ) -> Bool {
        if let ifNoneMatch,
           ifNoneMatch.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            let candidates = ifNoneMatch.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            return candidates.contains("*") || candidates.contains { candidate in
                candidate == validators.entityTag || candidate == "W/\(validators.entityTag)"
            }
        }
        guard let modificationDate = validators.modificationDate,
              let ifModifiedSince,
              let sinceDate = Self.parseHTTPDate(ifModifiedSince) else {
            return false
        }
        return modificationDate.timeIntervalSince1970.rounded(.down) <= sinceDate.timeIntervalSince1970
    }

    static func httpDateString(from date: Date) -> String {
        httpDateLock.lock()
        defer { httpDateLock.unlock() }
        return httpDateFormatter.string(from: date)
    }

    static func parseHTTPDate(_ value: String) -> Date? {
        httpDateLock.lock()
        defer { httpDateLock.unlock() }
        return httpDateFormatter.date(from: value)
    }

    private static let httpDateLock = NSLock()
    private static let httpDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss 'GMT'"
        return formatter
    }()
}
