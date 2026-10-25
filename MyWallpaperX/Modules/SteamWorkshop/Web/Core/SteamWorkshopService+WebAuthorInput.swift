import Foundation
import Darwin

/// One cold interpretation owns its actual reads. Warm cache checks use the
/// recorded revisions and never repeat the dependency scan or hash author bytes.
nonisolated final class WebAuthorFileReader {
    struct Observation {
        let content: String
        let isTruncated: Bool
        let containsServiceWorker: Bool
    }
    private var projects: [URL: Data] = [:]
    private var attemptedProjects = Set<URL>()
    private var revisions: [URL: WebAuthorFileRevision] = [:]
    private var references: [WebAuthorDependencyReference] = []
    private(set) var unstable = false

    private func key(_ url: URL) -> URL { url.resolvingSymlinksInPath().standardizedFileURL }

    private func observe(_ url: URL) -> WebAuthorFileRevision {
        let value = WebAuthorFileRevision(url)
        if let previous = revisions[url], previous != value { unstable = true }
        else { revisions[url] = value }
        return value
    }

    func project(_ supplied: URL?) -> Data? {
        guard let supplied else { return nil }
        let url = key(supplied)
        if let data = projects[url] { return data }
        guard attemptedProjects.insert(url).inserted else { return nil }
        guard let data = read(url) else { return nil }
        projects[url] = data
        return data
    }

    func summaryDependencyExists(_ url: URL) -> Bool {
        observe(url).state != nil
    }

    func recordDependency(_ path: String, source: URL, root: URL, resolved: URL?) {
        references.append(.init(path: path, sourceURL: source, rootURL: root, resolvedURL: resolved))
    }

    private func openRegular(_ url: URL) -> (FileHandle, stat)? {
        // O_NONBLOCK is needed before fstat: a FIFO must never block a canceled
        // preparation's join or keep its resource lifetime indefinitely.
        let fd = open(url.path, O_RDONLY | O_CLOEXEC | O_NONBLOCK)
        guard fd >= 0 else { return nil }
        var before = stat()
        guard fstat(fd, &before) == 0, before.st_mode & S_IFMT == S_IFREG,
              before.st_size >= 0, before.st_size < Int.max else { _ = close(fd); return nil }
        return (FileHandle(fileDescriptor: fd, closeOnDealloc: true), before)
    }

    func summary(_ supplied: URL) -> Observation? {
        let url = key(supplied)
        let revision = observe(url)
        guard !Task.isCancelled, let (handle, before) = openRegular(url) else { return nil }
        defer { try? handle.close() }
        let size = Int(before.st_size)
        let maximum = SteamWorkshopService.webStaticAnalysisMaximumFileBytes
        let data: Data
        var extraServiceWorker = false
        do {
            if size <= 1024 * 1024 {
                data = try handle.read(upToCount: size + 1) ?? Data()
                guard data.count == size else { unstable = true; return nil }
                extraServiceWorker = size > maximum && WebStaticFileSignalScanner.containsServiceWorkerRegistration(data: data)
            } else {
                let half = maximum / 2
                let prefix = try handle.read(upToCount: half) ?? Data()
                guard !Task.isCancelled else { return nil }
                try handle.seek(toOffset: UInt64(size - half))
                let suffix = try handle.read(upToCount: half) ?? Data()
                guard prefix.count == half, suffix.count == half else { unstable = true; return nil }
                data = prefix + suffix
            }
        } catch { return nil }
        if !revision.isCurrent { unstable = true }
        let scan: (content: String, isTruncated: Bool)?
        if size > 1024 * 1024 {
            let half = maximum / 2
            scan = (String(decoding: data.prefix(half), as: UTF8.self)
                + "\n/* static analysis truncated */\n"
                + String(decoding: data.suffix(half), as: UTF8.self), true)
        } else { scan = SteamWorkshopService.webStaticAnalysisContent(data: data) }
        return scan.map { Observation(content: $0.content, isTruncated: $0.isTruncated,
            containsServiceWorker: extraServiceWorker) }
    }

    private func read(_ url: URL) -> Data? {
        let revision = observe(url)
        guard !Task.isCancelled, let (handle, before) = openRegular(url) else { return nil }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: Int(before.st_size) + 1),
              data.count == before.st_size else { unstable = true; return nil }
        if !revision.isCurrent { unstable = true }
        return data
    }

    func directoryNames(_ supplied: URL) -> [String]? {
        let url = key(supplied)
        let revision = observe(url)
        guard !Task.isCancelled,
              let result = try? FileManager.default.contentsOfDirectory(atPath: url.path) else { return nil }
        if !revision.isCurrent { unstable = true }
        return result
    }

    func cachedProduct(_ product: SteamWorkshopService.WebProjectDescriptorParseProduct,
        inputs: SteamWorkshopService.WebRuntimeCacheManifestInputs) -> CachedWebProjectDescriptor {
        CachedWebProjectDescriptor(identity: inputs.cacheIdentity,
            fileRevisions: revisions.values.sorted { $0.url.path < $1.url.path },
            dependencyReferences: references, product: product, isReusable: !unstable)
    }
}

extension SteamWorkshopService {
    nonisolated struct WebAuthorBindingContext: Codable, Equatable, Sendable {
        struct Root: Codable, Equatable, Sendable {
            let source: ResolvedWebResourceBindingSource
            let url: URL
        }
        let candidateRoots: [Root]
        let pathlikePresetValues: [String: SteamWorkshopWebPropertyValue]
        var pathlikeKeys: Set<String> { Set(pathlikePresetValues.keys.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }) }

        nonisolated static func make(record: SteamWorkshopDownloadRecord,
            presets: [String: SteamWorkshopWebPropertyValue], roots: [Root]) -> Self {
            Self(candidateRoots: roots, pathlikePresetValues: record.isDependencyBackedWeb ? presets.filter {
                guard let path = $0.value.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines), !path.isEmpty else { return false }
                return SteamWorkshopService.fallbackResourceSemantic(forKey: $0.key, rawPath: path) != nil
            } : [:])
        }
    }

    nonisolated struct WebCapturedAuthorInput: Sendable {
        let ownProjectData: Data?
        let sourceProjectData: Data?
        let declaredEntry: String?
        let entrySource: ResolvedWebProjectDescriptor.EntrySource
        let source: SteamWorkshopWebPropertyDefinitionSource?
        let topLevelNames: Set<String>
        let summary: ResolvedWebStaticContentSummary
        let candidateRoots: [WebAuthorBindingContext.Root]
        let inputs: WebRuntimeCacheManifestInputs
    }

    nonisolated func captureWebAuthorInput(record: SteamWorkshopDownloadRecord,
        source: SteamWorkshopWebPropertyDefinitionSource?, inputs: WebRuntimeCacheManifestInputs,
        reader: WebAuthorFileReader = WebAuthorFileReader()) -> WebCapturedAuthorInput? {
        guard !Task.isCancelled, inputs.authorSourceAvailable,
              let entry = inputs.entryURL, let root = inputs.rootURL else { return nil }
        let ownData = reader.project(inputs.ownProjectURL)
        let sourceData = reader.project(source?.projectFileURL)
        let declared = Self.declaredWebEntryRelativePath(data: ownData)
        // Library discovery already selected this entry. Do not recursively
        // discover HTML again merely to permit a previously selected wallpaper.
        let entrySource: ResolvedWebProjectDescriptor.EntrySource
        if let declared, entry.path == inputs.ownFolderURL.appendingPathComponent(declared).resolvingSymlinksInPath().standardizedFileURL.path {
            entrySource = .declaredProjectEntry
        } else if record.isDependencyBackedWeb, let host = inputs.dependencyEntryURL,
                  host == entry { entrySource = .dependencyHostEntry }
        else { entrySource = .inferredFallbackEntry }
        let fileNames = record.isDependencyBackedWeb ? [] : (reader.directoryNames(source?.folderURL ?? inputs.ownFolderURL) ?? [])
        let summary = resolvedWebStaticContentSummary(for: record, entryURL: entry, rootURL: root,
            propertyDefinitions: [], read: reader.summary, exists: reader.summaryDependencyExists,
            observeReference: { path, sourceURL, resolved in
                reader.recordDependency(path, source: sourceURL, root: root, resolved: resolved)
            })
        guard !Task.isCancelled else { return nil }
        // A changing optional script/directory only makes this result unsuitable
        // for caching. It does not revoke an otherwise playable HTML entry.
        return WebCapturedAuthorInput(ownProjectData: ownData, sourceProjectData: sourceData,
            declaredEntry: declared, entrySource: entrySource, source: source, topLevelNames: Set(fileNames),
            summary: summary, candidateRoots: inputs.candidateRoots, inputs: inputs)
    }
}
