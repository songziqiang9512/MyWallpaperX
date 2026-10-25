import Foundation
import Darwin

nonisolated struct SteamWorkshopWebAnalysisCacheManifest: Codable {
    static let currentVersion = 22
    let version: Int
    let author: CachedWebProjectDescriptor
}

/// The existing cache owner fences deletion against late derived-cache writes.
nonisolated final class SteamWorkshopWebRuntimeCachePublication: @unchecked Sendable {
    static let shared = SteamWorkshopWebRuntimeCachePublication()

    final class Slot: @unchecked Sendable {
        let lock = NSLock()
        var generation = UUID()
    }

    struct Ticket: Sendable {
        let slot: Slot
        let generation: UUID
    }

    private final class WeakSlot {
        weak var value: Slot?
        init(_ value: Slot) { self.value = value }
    }

    private let registryLock = NSLock()
    private var slots: [String: WeakSlot] = [:]

    private func slot(for key: String) -> Slot {
        registryLock.withLock {
            // Only active tickets retain slots. Reap dead keys on every entry,
            // so importing/deleting successive records does not grow history.
            slots = slots.filter { $0.value.value != nil }
            if let slot = slots[key]?.value { return slot }
            let slot = Slot()
            slots[key] = WeakSlot(slot)
            return slot
        }
    }

    func begin(key: String) -> Ticket {
        let slot = slot(for: key)
        return slot.lock.withLock {
            slot.generation = UUID()
            return Ticket(slot: slot, generation: slot.generation)
        }
    }

    func isCurrent(_ ticket: Ticket) -> Bool {
        ticket.slot.lock.withLock { ticket.slot.generation == ticket.generation }
    }

    func invalidate(key: String, removing files: [URL] = []) {
        let slot = slot(for: key)
        slot.lock.withLock {
            slot.generation = UUID()
            for file in files { _ = unlink(file.path) }
        }
    }

    func invalidateAll() {
        let currentSlots = registryLock.withLock { slots.values.compactMap(\.value) }
        for slot in currentSlots {
            slot.lock.withLock { slot.generation = UUID() }
        }
    }

    func remove(_ files: [URL], ticket: Ticket) {
        ticket.slot.lock.withLock {
            guard ticket.slot.generation == ticket.generation else { return }
            for file in files { _ = unlink(file.path) }
        }
    }

    @discardableResult
    func publish(_ data: Data, to fileURL: URL, ticket: Ticket) -> Bool {
        let staging = fileURL.deletingLastPathComponent()
            .appendingPathComponent(".\(fileURL.lastPathComponent).\(UUID().uuidString).pending")
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        } catch { return false }
        let fd = open(staging.path, O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC, 0o600)
        guard fd >= 0 else { return false }
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        defer {
            try? handle.close()
            _ = unlink(staging.path) // Only this invocation created this O_EXCL file.
        }
        do {
            try handle.write(contentsOf: data)
            try handle.close()
        } catch { return false }
        return ticket.slot.lock.withLock {
            guard ticket.slot.generation == ticket.generation, !Task.isCancelled else { return false }
            return rename(staging.path, fileURL.path) == 0
        }
    }
}


extension SteamWorkshopService {
    func webRuntimeCacheManifestInputs(for record: SteamWorkshopDownloadRecord,
        source: SteamWorkshopWebPropertyDefinitionSource?) -> WebRuntimeCacheManifestInputs {
        let entry = record.webEntryURL?.resolvingSymlinksInPath().standardizedFileURL
        return WebRuntimeCacheManifestInputs(recordID: record.id,
            language: Self.resolvedWebWallpaperLanguage(), authorLanguageKeys: WorkshopPropertyDisplayResolver.languageVersion,
            propertySource: source, ownFolderURL: record.folderURL.resolvingSymlinksInPath().standardizedFileURL,
            ownProjectURL: record.projectFileURL?.resolvingSymlinksInPath().standardizedFileURL,
            dependencyEntryURL: record.webDependencyHostEntryURL?.resolvingSymlinksInPath().standardizedFileURL,
            dependencyFolderURL: record.dependencyHostFolderURL?.resolvingSymlinksInPath().standardizedFileURL,
            candidateRoots: webResourceCandidateRoots(for: record).map { .init(source: $0.0, url: $0.1) },
            dependencyRole: (record.isDependencyBackedWeb ? "dependency:" : "own:") + String(describing: record.dependencyStatus),
            dependencyItemID: record.dependencyItemID, entryURL: entry,
            rootURL: entry.map { effectiveWebRootURL(for: record, entryURL: $0) },
            analysisFileURL: webAnalysisCacheFileURL(for: record),
            authorSourceAvailable: !record.isDependencyBackedWeb || record.dependencyHostFolderURL == nil || source != nil)
    }

    func removeWebRuntimeCaches(for recordID: String) {
        invalidateCachedWebRuntime(for: recordID)
        let stem = Self.webRuntimeCacheFileStem(for: recordID)
        let directory = Self.webRuntimeCacheDirectoryURL()
        let analysis = directory.appendingPathComponent("\(stem)-analysis.json")
        // Remove the retired execution-payload cache when this record is deleted.
        SteamWorkshopWebRuntimeCachePublication.shared.invalidate(key: analysis.path, removing: [
            analysis, directory.appendingPathComponent("\(stem)-runtime.json")
        ])
    }

    nonisolated static func webRuntimeCacheDirectoryURL() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Caches/MyWallpaperX/SteamWorkshop/WebRuntime", isDirectory: true)
    }

    nonisolated static func webRuntimeCacheFileStem(for recordID: String) -> String {
        Data(recordID.utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    func webAnalysisCacheFileURL(for record: SteamWorkshopDownloadRecord) -> URL {
        Self.webRuntimeCacheDirectoryURL()
            .appendingPathComponent("\(Self.webRuntimeCacheFileStem(for: record.id))-analysis.json")
    }

    nonisolated static func loadCachedAnalysisDescriptor(
        inputs: WebRuntimeCacheManifestInputs
    ) -> CachedWebProjectDescriptor? {
        guard !Task.isCancelled, let data = try? Data(contentsOf: inputs.analysisFileURL),
              let manifest = try? JSONDecoder().decode(SteamWorkshopWebAnalysisCacheManifest.self, from: data),
              manifest.version == SteamWorkshopWebAnalysisCacheManifest.currentVersion,
              manifest.author.matches(inputs) else { return nil }
        return manifest.author
    }

    /// The bounded writer consumes captured values only. Playback never awaits
    /// encoding or disk publication; a stale/deleted source simply skips saving.
    nonisolated static func saveWebAnalysisCache(_ author: CachedWebProjectDescriptor,
        inputs: WebRuntimeCacheManifestInputs, publication: SteamWorkshopWebRuntimeCachePublication.Ticket) {
        guard author.isReusable else { return }
        Task.detached(priority: .utility) {
            guard author.matches(inputs),
                  let data = try? JSONEncoder().encode(SteamWorkshopWebAnalysisCacheManifest(
                    version: SteamWorkshopWebAnalysisCacheManifest.currentVersion, author: author)) else { return }
            SteamWorkshopWebRuntimeCachePublication.shared.publish(data, to: inputs.analysisFileURL, ticket: publication)
        }
    }
}
