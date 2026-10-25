import AppKit
import Combine
import Foundation

extension SteamWorkshopService {
    /// Synchronous product admission samples the already-selected entry only.
    /// Author declarations and fallback selection belong to capture's original
    /// resolver; this front door never discovers a source or reads project JSON.
    nonisolated func webLaunchEntryIsValid(for record: SteamWorkshopDownloadRecord) -> Bool {
        let entry = record.webEntryURL?.resolvingSymlinksInPath().standardizedFileURL
        return entry.flatMap { try? $0.resourceValues(forKeys: [.isRegularFileKey]) }?.isRegularFile == true
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
