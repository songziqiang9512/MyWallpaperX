import Foundation

extension SteamWorkshopDownloadRecord {
    var webEntryURL: URL? {
        guard let entryHTMLURL,
              FileManager.default.fileExists(atPath: entryHTMLURL.path) else {
            return nil
        }
        return entryHTMLURL
    }

    var webHostRootURL: URL? {
        guard let resolvedWebRootURL,
              FileManager.default.fileExists(atPath: resolvedWebRootURL.path) else {
            return nil
        }
        return resolvedWebRootURL
    }

    var webShellRootURL: URL {
        folderURL.resolvingSymlinksInPath().standardizedFileURL
    }

    var webOwnEntryURL: URL? {
        guard let ownEntryHTMLURL,
              FileManager.default.fileExists(atPath: ownEntryHTMLURL.path) else {
            return nil
        }
        return ownEntryHTMLURL
    }

    var webDependencyHostEntryURL: URL? {
        guard let dependencyHostEntryHTMLURL,
              FileManager.default.fileExists(atPath: dependencyHostEntryHTMLURL.path) else {
            return nil
        }
        return dependencyHostEntryHTMLURL
    }

    var isWebPlayable: Bool {
        status == .ready && webEntryURL != nil
    }

#if DEBUG
    var webValidationFailureSeverity: SteamWorkshopWebValidationSeverity? {
        webValidationFailureLevel?.severity
    }

    var webValidationFailureLevel: SteamWorkshopWebValidationLevel? {
        guard contentType == .web else { return nil }
        if webEntryURL == nil {
            return dependencyItemID != nil ? .preconditionUnmet : .fatal
        }
        if case .missing = dependencyStatus {
            return .preconditionUnmet
        }
        return nil
    }

#endif

    var isDependencyBackedWeb: Bool {
        contentType == .web && dependencyItemID != nil
    }

    var isStandaloneWebPlayable: Bool {
        status == .ready && webEntryURL != nil && dependencyItemID == nil
    }

    var hasPlayableDependencyWebHost: Bool {
        if case .available = dependencyStatus {
            return true
        }
        return false
    }

    var isWebPlayableOrLaunchable: Bool {
        isPlayable
            || isStandaloneWebPlayable
            || (isDependencyBackedWeb && hasPlayableDependencyWebHost && webEntryURL != nil)
    }
}
