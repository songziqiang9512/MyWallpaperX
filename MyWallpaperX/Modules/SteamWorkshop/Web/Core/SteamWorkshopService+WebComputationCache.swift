import Foundation

/// The same author-only value backs the property UI and playback preparation.
/// Current overrides, bookmark authority and playback payload are never cached.
nonisolated struct CachedWebProjectDescriptor: Codable, Equatable, Sendable {
    let identity: WebAuthorCacheIdentity
    let fileRevisions: [WebAuthorFileRevision]
    let dependencyReferences: [WebAuthorDependencyReference]
    let product: SteamWorkshopService.WebProjectDescriptorParseProduct
    let isReusable: Bool

    func matches(_ inputs: SteamWorkshopService.WebRuntimeCacheManifestInputs) -> Bool {
        isReusable && identity == inputs.cacheIdentity
            && fileRevisions.allSatisfy(\.isCurrent) && dependencyReferences.allSatisfy(\.isCurrent)
    }
}

extension SteamWorkshopService {
    func invalidateCachedWebRuntime(for recordID: String) {
        webProjectDescriptorCache.removeValue(forKey: recordID)
        let analysis = Self.webRuntimeCacheDirectoryURL()
            .appendingPathComponent("\(Self.webRuntimeCacheFileStem(for: recordID))-analysis.json")
        SteamWorkshopWebRuntimeCachePublication.shared.invalidate(key: analysis.path)
    }

    func invalidateAllCachedWebRuntime() {
        webProjectDescriptorCache.removeAll()
        SteamWorkshopWebRuntimeCachePublication.shared.invalidateAll()
    }
}
