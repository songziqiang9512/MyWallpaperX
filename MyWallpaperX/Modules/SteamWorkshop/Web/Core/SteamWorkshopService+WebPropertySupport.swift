import Foundation

extension SteamWorkshopService {
    private func existingWebResourceURL(for candidateURL: URL) -> URL? {
        let standardizedCandidateURL = candidateURL.resolvingSymlinksInPath().standardizedFileURL
        if FileManager.default.fileExists(atPath: standardizedCandidateURL.path) {
            return standardizedCandidateURL
        }

        let parentURL = standardizedCandidateURL.deletingLastPathComponent()
        guard FileManager.default.fileExists(atPath: parentURL.path) else {
            return nil
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

    func effectiveWebPropertyValues(
        for record: SteamWorkshopDownloadRecord,
        descriptor: ResolvedWebProjectDescriptor
    ) -> [String: SteamWorkshopWebPropertyValue] {
        var values = descriptor.defaultValueMap
        for (key, value) in webPropertyOverrides(for: record) {
            values[key] = value
        }
        return values
    }

    func effectiveWebPropertyValues(
        for record: SteamWorkshopDownloadRecord,
        definitions: [SteamWorkshopWebPropertyDefinition]
    ) -> [String: SteamWorkshopWebPropertyValue] {
        var values = webPropertyBaselineValues(for: record, definitions: definitions)
        for (key, value) in webPropertyOverrides(for: record) {
            values[key] = value
        }
        return values
    }

    nonisolated func webPropertyBaselineValues(
        for record: SteamWorkshopDownloadRecord,
        definitions: [SteamWorkshopWebPropertyDefinition]
    ) -> [String: SteamWorkshopWebPropertyValue] {
        var values = Dictionary(uniqueKeysWithValues: definitions.map { ($0.key, $0.defaultValue) })
        for (key, value) in Self.webPresetValues(for: record) {
            values[key] = value
        }
        return values
    }

    func resolvedWebResourceBinding(
        forKey key: String,
        definition: SteamWorkshopWebPropertyDefinition?,
        rawValue: SteamWorkshopWebPropertyValue,
        record: SteamWorkshopDownloadRecord,
        usesBookmarks: Bool = true
    ) -> ResolvedWebResourceBinding? {
        guard let rawPath = rawValue.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
              !rawPath.isEmpty else {
            return nil
        }

        let normalized = rawPath.replacingOccurrences(of: "\\", with: "/")
        let normalizedKey = key.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let isDirectoryDefinition = definition?.kind == .directory
        let isFileDefinition = definition?.kind == .file
        let looksLikePathPreset = webShellResourcePathLikeKeys(for: record).contains(normalizedKey)
        let origin: ResolvedWebResourceBindingOrigin = definition == nil ? .presetFallback : .propertyDefinition
        let kind: ResolvedWebResourceBindingKind
        if isDirectoryDefinition {
            kind = .directory
        } else if isFileDefinition {
            kind = .file
        } else if looksLikePathPreset {
            kind = .pathlikePreset
        } else {
            return nil
        }

        let candidateRoots = webResourceCandidateRoots(for: record)

        if usesBookmarks,
           kind != .pathlikePreset,
           let bookmarkURL = resolvedBookmarkedWebPropertyURL(forKey: key, record: record) {
            return ResolvedWebResourceBinding(
                key: key,
                rawValue: rawPath,
                kind: kind,
                fileType: definition?.fileType,
                resolvedURL: bookmarkURL,
                source: .bookmarkedOverride,
                origin: origin
            )
        }

        if normalized.hasPrefix("/") {
            let candidateURL = URL(fileURLWithPath: normalized).resolvingSymlinksInPath().standardizedFileURL
            let resolvedCandidateURL = existingWebResourceURL(for: candidateURL)
            let bundledRoot = resolvedCandidateURL.flatMap { candidateURL in
                candidateRoots.first { isWebResource(candidateURL, containedIn: $0.1) }
            }
            return ResolvedWebResourceBinding(
                key: key,
                rawValue: rawPath,
                kind: kind,
                fileType: definition?.fileType,
                resolvedURL: bundledRoot == nil && usesBookmarks ? nil : resolvedCandidateURL,
                source: bundledRoot?.0 ?? (resolvedCandidateURL != nil && !usesBookmarks ? .absolutePath : .unresolved),
                origin: origin
            )
        }

        for (source, rootURL) in candidateRoots {
            let candidateURL = rootURL.appendingPathComponent(normalized).resolvingSymlinksInPath().standardizedFileURL
            guard isWebResource(candidateURL, containedIn: rootURL) else {
                continue
            }
            if let resolvedCandidateURL = existingWebResourceURL(for: candidateURL) {
                return ResolvedWebResourceBinding(
                    key: key,
                    rawValue: rawPath,
                    kind: kind,
                    fileType: definition?.fileType,
                    resolvedURL: resolvedCandidateURL,
                    source: source,
                    origin: origin
                )
            }
        }

        return ResolvedWebResourceBinding(
            key: key,
            rawValue: rawPath,
            kind: kind,
            fileType: definition?.fileType,
            resolvedURL: nil,
            source: .unresolved,
            origin: origin
        )
    }

    private func webResourceCandidateRoots(for record: SteamWorkshopDownloadRecord) -> [(ResolvedWebResourceBindingSource, URL)] {
        var candidateRoots: [(ResolvedWebResourceBindingSource, URL)] = []
        if record.isDependencyBackedWeb {
            // Dependency-backed presets commonly point at files owned by the shell sample,
            // while scripts and property definitions come from the dependency host.
            candidateRoots.append((.shellRoot, record.webShellRootURL))
        }
        if let rootURL = record.webHostRootURL ?? record.resolvedWebRootURL {
            let standardizedRootURL = rootURL.resolvingSymlinksInPath().standardizedFileURL
            if candidateRoots.contains(where: { $0.1.path == standardizedRootURL.path }) == false {
                candidateRoots.append((.hostRoot, standardizedRootURL))
            }
        }
        let standardizedFolderURL = record.folderURL.resolvingSymlinksInPath().standardizedFileURL
        if candidateRoots.contains(where: { $0.1.path == standardizedFolderURL.path }) == false {
            candidateRoots.append((.recordFolder, standardizedFolderURL))
        }
        return candidateRoots
    }

    private func isWebResource(_ candidateURL: URL, containedIn rootURL: URL) -> Bool {
        let candidatePath = candidateURL.resolvingSymlinksInPath().standardizedFileURL.path
        let rootPath = rootURL.resolvingSymlinksInPath().standardizedFileURL.path
        return candidatePath == rootPath || candidatePath.hasPrefix(rootPath + "/")
    }

    func resolvedWebRuntimeAssetURL(
        forKey key: String,
        definition: SteamWorkshopWebPropertyDefinition,
        rawValue: SteamWorkshopWebPropertyValue,
        record: SteamWorkshopDownloadRecord
    ) -> URL? {
        guard let resolvedURL = resolvedWebResourceBinding(
            forKey: key,
            definition: definition,
            rawValue: rawValue,
            record: record
        )?.resolvedURL else {
            return nil
        }
        guard definition.kind != .file || Self.webFileURL(resolvedURL, matches: definition.fileType) else {
            return nil
        }
        return resolvedURL
    }

    func resolvedWebRuntimeValue(
        forKey key: String,
        definition: SteamWorkshopWebPropertyDefinition,
        rawValue: SteamWorkshopWebPropertyValue,
        record: SteamWorkshopDownloadRecord
    ) -> SteamWorkshopWebPropertyValue {
        if definition.kind == .color,
           case let .string(rawString) = rawValue,
           let normalizedColor = Self.normalizedWebColorRuntimeString(from: rawString) {
            return .string(normalizedColor)
        }

        if let binding = resolvedWebResourceBinding(
            forKey: key,
            definition: definition,
            rawValue: rawValue,
            record: record
        ), let resolvedURL = binding.resolvedURL {
            guard definition.kind != .file || Self.webFileURL(resolvedURL, matches: definition.fileType) else {
                return .string("")
            }
            return .string(resolvedURL.path)
        }

        guard definition.kind == .file || definition.kind == .directory else {
            return rawValue
        }
        return rawValue
    }

}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
