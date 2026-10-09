import Foundation

extension SteamWorkshopService {
    nonisolated func loadDecodedWebProject(for record: SteamWorkshopDownloadRecord) -> SteamWorkshopProject? {
        Self.loadWorkshopProject(from: record.projectFileURL)
    }

    enum WebFallbackResourceSemantic {
        case file(fileType: String?)
        case directory
    }

    static let webResourcePathPrefixes = [
        "files/",
        "directories/",
        "images/",
        "image/",
        "img/",
        "background/",
        "backgrounds/",
        "bg/",
        "audio/",
        "video/"
    ]

    static let webFallbackDirectoryKeyAliases: Set<String> = [
        "customdirectory",
        "directory",
        "folder"
    ]

    static let webFallbackVideoKeyAliases: Set<String> = [
        "bgvideo",
        "customvideo",
        "selectvideo",
        "video"
    ]

    static let webFallbackImageKeyAliases: Set<String> = [
        "image",
        "background_image",
        "foreground_image",
        "backgroundimage",
        "backgroundimageb",
        "customimagebackgroundimg",
        "bgimage"
    ]

    nonisolated static func fallbackResourceSemantic(forKey key: String, rawPath: String) -> WebFallbackResourceSemantic? {
        let normalizedKey = key.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let normalizedPath = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\", with: "/")
            .lowercased()
        let pathExtension = URL(fileURLWithPath: normalizedPath).pathExtension.lowercased()

        if normalizedKey.contains("color") || normalizedKey.contains("colour") {
            return nil
        }
        if parseWebColorComponents(from: normalizedPath) != nil {
            return nil
        }

        if normalizedPath.hasPrefix("directories/")
            || webFallbackDirectoryKeyAliases.contains(normalizedKey)
            || normalizedKey.contains("directory")
            || normalizedKey.contains("folder") {
            return .directory
        }

        let looksLikeResourcePath = webResourcePathPrefixes.contains(where: { normalizedPath.hasPrefix($0) })
        let imageExtensions = Set(["jpg", "jpeg", "png", "pnga", "bmp", "gif", "svg", "webp"])
        let videoExtensions = Set(["webm", "ogv", "mp4", "mov", "m4v"])
        let audioExtensions = Set(["mp3", "wav", "flac", "m4a", "aac"])
        let prefersVideo = webFallbackVideoKeyAliases.contains(normalizedKey)
            || normalizedKey.contains("video")
            || normalizedKey.contains("movie")
        let prefersAudio = normalizedKey.contains("audio")
            || normalizedKey.contains("music")
            || normalizedKey.contains("sound")
        let prefersImage = webFallbackImageKeyAliases.contains(normalizedKey)
            || normalizedKey.contains("image")
            || normalizedKey.contains("img")
            || normalizedKey.contains("background")
            || normalizedKey.contains("bg")
        let hasResourcePathShape = looksLikeResourcePath
            || normalizedPath.contains("/")
            || pathExtension.isEmpty == false

        guard hasResourcePathShape, looksLikeResourcePath || prefersVideo || prefersAudio || prefersImage else {
            return nil
        }

        if imageExtensions.contains(pathExtension) {
            return .file(fileType: "image")
        }
        if videoExtensions.contains(pathExtension) {
            return .file(fileType: "video")
        }
        if audioExtensions.contains(pathExtension) {
            return .file(fileType: "audio")
        }
        if pathExtension == "ogg" {
            return .file(fileType: prefersAudio ? "audio" : "video")
        }
        if prefersImage {
            return .file(fileType: "image")
        }
        if prefersAudio {
            return .file(fileType: "audio")
        }
        if prefersVideo {
            return .file(fileType: "video")
        }
        return .file(fileType: nil)
    }
}

extension SteamWorkshopService {
    enum WebResourceReference {
        case local(String)
        case external(String)
    }

    nonisolated func loadWebProjectRoot(for record: SteamWorkshopDownloadRecord) -> [String: Any]? {
        Self.loadWebProjectRootStatic(for: record)
    }

    nonisolated static func loadWebProjectRootStatic(for record: SteamWorkshopDownloadRecord) -> [String: Any]? {
        guard let projectFileURL = record.projectFileURL,
              let data = try? Data(contentsOf: projectFileURL),
              let object = try? JSONSerialization.jsonObject(with: data),
              let root = object as? [String: Any] else {
            return nil
        }
        return root
    }

    nonisolated func declaredWebEntryRelativePath(for record: SteamWorkshopDownloadRecord) -> String? {
        let declaredEntry = loadDecodedWebProject(for: record)?.file?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let declaredEntry,
              declaredEntry.isEmpty == false else {
            return nil
        }
        return declaredEntry.replacingOccurrences(of: "\\", with: "/")
    }

    func webPropertyDefinitionSourceRecord(for record: SteamWorkshopDownloadRecord) -> SteamWorkshopDownloadRecord? {
        guard record.contentType == .web else { return nil }
        guard record.isDependencyBackedWeb else { return record }
        guard case let .available(itemID) = record.dependencyStatus else { return record }
        let dependencyRecord = latestDownloadRecord(for: itemID)
            ?? buildInstalledRecord(at: webLibraryRootURL.appendingPathComponent(itemID, isDirectory: true))
            ?? buildInstalledRecord(at: sceneLibraryRootURL.appendingPathComponent(itemID, isDirectory: true))
        guard let dependencyRecord,
              dependencyRecord.contentType == .web,
              dependencyRecord.webEntryURL != nil else {
            return record
        }
        return dependencyRecord
    }

    func webSampleStructure(for record: SteamWorkshopDownloadRecord) -> SteamWorkshopWebSampleStructure {
        Self.webSampleStructure(
            record: record,
            sourceRecord: webPropertyDefinitionSourceRecord(for: record) ?? record
        )
    }

    /// 解析核：sourceRecord 由主线程快照后传入，可在任意线程执行。
    nonisolated static func webSampleStructure(
        record: SteamWorkshopDownloadRecord,
        sourceRecord: SteamWorkshopDownloadRecord
    ) -> SteamWorkshopWebSampleStructure {
        if record.isDependencyBackedWeb { return .dependencyBackedShell }
        let root = Self.loadWebProjectRootStatic(for: sourceRecord)
        let propertyCount = ((root?["general"] as? [String: Any])?["properties"] as? [String: Any])?.count ?? 0
        let fileNames = Set((try? FileManager.default.contentsOfDirectory(atPath: sourceRecord.folderURL.path)) ?? [])
        if fileNames.contains("spine-player.js") || fileNames.contains("spine-player4.1.js") { return .spineWebCharacter }
        if fileNames.contains("shaders") { return .shaderOrCanvasWeb }
        if propertyCount > 150 { return .megaConfigDashboardWeb }
        if fileNames.contains("audio") || fileNames.contains("video") { return .multimediaDashboardWeb }
        if propertyCount > 0 { return .propertyDrivenHTMLWeb }
        return .basicHTMLWeb
    }

    func webPresetValues(for record: SteamWorkshopDownloadRecord) -> [String: SteamWorkshopWebPropertyValue] {
        Self.webPresetValues(for: record)
    }

    nonisolated static func webPresetValues(for record: SteamWorkshopDownloadRecord) -> [String: SteamWorkshopWebPropertyValue] {
        guard record.contentType == .web,
              let root = Self.loadWebProjectRootStatic(for: record),
              let preset = root["preset"] as? [String: Any] else {
            return [:]
        }

        var values: [String: SteamWorkshopWebPropertyValue] = [:]
        for (key, rawValue) in preset {
            guard let value = Self.webPropertyValue(from: rawValue) else {
                continue
            }
            values[key] = value
        }
        return values
    }

    /// 纯 URL/record 推导，无 actor 状态：运行时缓存的签名扫描在后台线程
    /// 复用（nonisolated），不要往这里加任何 self 可变状态访问。
    nonisolated func effectiveWebRootURL(for record: SteamWorkshopDownloadRecord, entryURL: URL) -> URL {
        let standardizedEntryDirectory = entryURL
            .resolvingSymlinksInPath()
            .standardizedFileURL
            .deletingLastPathComponent()

        if let hostRoot = record.webHostRootURL {
            let standardizedHostRoot = hostRoot.resolvingSymlinksInPath().standardizedFileURL
            if standardizedEntryDirectory.path == standardizedHostRoot.path
                || standardizedEntryDirectory.path.hasPrefix(standardizedHostRoot.path + "/") {
                return standardizedHostRoot
            }
        }

        if let projectFileURL = record.projectFileURL {
            let projectRootURL = projectFileURL
                .deletingLastPathComponent()
                .resolvingSymlinksInPath()
                .standardizedFileURL
            if standardizedEntryDirectory.path == projectRootURL.path
                || standardizedEntryDirectory.path.hasPrefix(projectRootURL.path + "/") {
                return projectRootURL
            }
        }

        let standardizedRecordFolder = record.folderURL.resolvingSymlinksInPath().standardizedFileURL
        if standardizedEntryDirectory.path == standardizedRecordFolder.path
            || standardizedEntryDirectory.path.hasPrefix(standardizedRecordFolder.path + "/") {
            return standardizedRecordFolder
        }

        return standardizedEntryDirectory
    }

    nonisolated func webRelativePath(for fileURL: URL, under rootURL: URL) -> String {
        let normalizedRoot = rootURL.resolvingSymlinksInPath().standardizedFileURL.path
        let normalizedFile = fileURL.resolvingSymlinksInPath().standardizedFileURL.path
        guard Self.isWebPath(normalizedFile, insideRootPath: normalizedRoot) else {
            return fileURL.lastPathComponent
        }
        let relativeURL = fileURL.resolvingSymlinksInPath().standardizedFileURL
            .path.replacingOccurrences(of: normalizedRoot, with: "", options: [.anchored])
        let relative = relativeURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return relative.isEmpty ? fileURL.lastPathComponent : relative
    }

    nonisolated static func extractLocalWebResourceReferences(from content: String, fileExtension _: String) -> [WebResourceReference] {
        let pattern = #"(?:^|[\s<])(?:src|href)\s*=\s*(?:\"([^\"]+)\"|'([^']+)'|([^\s\"'=<>`]+))|url\(\s*['\"]?([^'\")]+)['\"]?\s*\)|import\s+[\"']([^\"']+)[\"']"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return []
        }
        let nsRange = NSRange(content.startIndex..<content.endIndex, in: content)
        var references: [WebResourceReference] = regex.matches(in: content, options: [], range: nsRange).compactMap { match -> WebResourceReference? in
            for index in 1..<match.numberOfRanges {
                let range = match.range(at: index)
                guard range.location != NSNotFound,
                      let swiftRange = Range(range, in: content) else {
                    continue
                }
                let rawValue = String(content[swiftRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                guard !rawValue.isEmpty else { continue }
                let lowered = rawValue.lowercased()
                if lowered.hasPrefix("http://")
                    || lowered.hasPrefix("https://")
                    || lowered.hasPrefix("//")
                    || lowered.hasPrefix("data:")
                    || lowered.hasPrefix("javascript:")
                    || lowered.hasPrefix("about:") {
                    return .external(rawValue)
                }
                if rawValue.hasPrefix("#") { return nil }
                return .local(rawValue)
            }
            return nil
        }

        let externalURLPattern = #"\bhttps?://[^\s"'`<>\\]+"#
        if let externalURLRegex = try? NSRegularExpression(pattern: externalURLPattern, options: [.caseInsensitive]) {
            references += externalURLRegex.matches(in: content, options: [], range: nsRange).compactMap { match -> WebResourceReference? in
                guard let range = Range(match.range, in: content) else { return nil }
                let rawURL = String(content[range])
                    .trimmingCharacters(in: CharacterSet(charactersIn: ".,;:!?)]}"))
                return rawURL.isEmpty ? nil : .external(rawURL)
            }
        }
        return references
    }

    nonisolated static func resolveWebResourceURL(_ path: String, relativeTo fileURL: URL, rootURL: URL) -> URL? {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        var normalized = trimmed.replacingOccurrences(of: "\\", with: "/")
        if let fragmentIndex = normalized.firstIndex(of: "#") {
            normalized = String(normalized[..<fragmentIndex])
        }
        if let queryIndex = normalized.firstIndex(of: "?") {
            normalized = String(normalized[..<queryIndex])
        }
        normalized = normalized.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.isEmpty == false else { return nil }
        let candidate: URL
        if normalized.hasPrefix("/") {
            candidate = rootURL.appendingPathComponent(String(normalized.dropFirst()))
        } else {
            candidate = fileURL.deletingLastPathComponent().appendingPathComponent(normalized)
        }
        let resolved = candidate.resolvingSymlinksInPath().standardizedFileURL
        let rootPath = rootURL.resolvingSymlinksInPath().standardizedFileURL.path
        guard isWebPath(resolved.path, insideRootPath: rootPath) else { return nil }
        return resolved
    }

    nonisolated static func shouldScanWebDependencyFile(named fileName: String) -> Bool {
        let ext = URL(fileURLWithPath: fileName).pathExtension.lowercased()
        return ["html", "htm", "css", "js", "json"].contains(ext)
    }

    private nonisolated static func isWebPath(_ path: String, insideRootPath rootPath: String) -> Bool {
        let normalizedRoot = rootPath.hasSuffix("/") ? String(rootPath.dropLast()) : rootPath
        guard path == normalizedRoot || path.hasPrefix(normalizedRoot + "/") else {
            return false
        }
        return true
    }
}
