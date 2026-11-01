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
}
