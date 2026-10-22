import AppKit
import Combine
import Foundation

extension SteamWorkshopService {
    /// Product launch admission checks entry availability only; dependency
    /// analysis belongs to asynchronous runtime preparation.
    func webLaunchEntryIsValid(for record: SteamWorkshopDownloadRecord) -> Bool {
        let signature = webProjectDescriptorSignature(for: record)
        if let cached = webLaunchEligibilityCache[record.id], cached.signature == signature {
            return cached.isValid
        }
        let isValid = computeWebLaunchEntryIsValid(for: record)
        webLaunchEligibilityCache[record.id] = .init(signature: signature, isValid: isValid)
        return isValid
    }

    private func computeWebLaunchEntryIsValid(for record: SteamWorkshopDownloadRecord) -> Bool {
        // A missing dependency is handled by the existing launchability guard;
        // it was a nonfatal precondition in the development report as well.
        if case .missing = record.dependencyStatus,
           record.isDependencyBackedWeb, !record.hasPlayableDependencyWebHost { return true }
        // Admission needs the entry only. Resolving a descriptor here would
        // synchronously parse the project and scan dependencies before the
        // asynchronous launch preparation gets a chance to run.
        guard let entryURL = record.webEntryURL else { return false }
        if !record.isDependencyBackedWeb,
           let declared = declaredWebEntryRelativePath(for: record) {
            let declaredURL = record.folderURL.appendingPathComponent(declared)
                .resolvingSymlinksInPath().standardizedFileURL
            guard FileManager.default.fileExists(atPath: declaredURL.path) else { return false }
        }
        return FileManager.default.fileExists(
            atPath: entryURL.resolvingSymlinksInPath().standardizedFileURL.path
        )
    }


    func webPlaybackFailureMessage(for record: SteamWorkshopDownloadRecord) -> String? {
        if let failureRecordID = lastWebPlaybackFailureRecordID {
            guard failureRecordID == record.id else { return nil }
            return lastWebPlaybackFailureMessage
        }

        guard let entryURL = record.webEntryURL,
              let failurePath = lastWebPlaybackFailurePath else {
            return nil
        }
        let entryPath = entryURL.resolvingSymlinksInPath().standardizedFileURL.path
        guard failurePath == entryPath else { return nil }
        return lastWebPlaybackFailureMessage
    }
}
