import Foundation

/// Stable author/source roles and language, independent of current user
/// overrides and bookmarks. Resource revisions are stored beside this key.
nonisolated struct WebAuthorCacheIdentity: Codable, Equatable, Sendable {
    let fields: [String]
    let languageKeys: [String]
    let roots: [SteamWorkshopService.WebAuthorBindingContext.Root]
}

extension SteamWorkshopService {
    nonisolated struct WebRuntimeCacheManifestInputs: Equatable, Sendable {
        let recordID: String
        let language: String
        let authorLanguageKeys: [String]
        let propertySource: SteamWorkshopWebPropertyDefinitionSource?
        let ownFolderURL: URL
        let ownProjectURL: URL?
        let dependencyEntryURL: URL?
        let dependencyFolderURL: URL?
        let candidateRoots: [WebAuthorBindingContext.Root]
        let dependencyRole: String
        let dependencyItemID: String?
        let entryURL: URL?
        let rootURL: URL?
        let analysisFileURL: URL
        let authorSourceAvailable: Bool

        var cacheIdentity: WebAuthorCacheIdentity {
            .init(fields: [recordID, language, ownFolderURL.path, ownProjectURL?.path ?? "",
                propertySource?.id ?? "", propertySource?.folderURL.path ?? "",
                propertySource?.projectFileURL?.path ?? "", dependencyRole, dependencyItemID ?? "",
                dependencyEntryURL?.path ?? "", dependencyFolderURL?.path ?? "",
                entryURL?.path ?? "", rootURL?.path ?? ""],
                languageKeys: authorLanguageKeys, roots: candidateRoots)
        }
    }
}
