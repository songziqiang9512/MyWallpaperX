import Foundation

/// The existing product selection and autoplay gate travel together from the
/// download click through asynchronous metadata/import work. This value owns
/// neither an intent counter nor a second playback transaction.
nonisolated struct ImportedVideoPlaybackAdmission: Equatable, Sendable {
    static let notificationUserInfoKey = "importedVideoPlaybackAdmission"
    let ticket: PlaybackSwitchTicket
    let autoplayToken: ImportedVideoAutoplayGate.Token
    let reference: WallpaperReference
    let libraryPending: WallpaperPlaybackSequence.Pending?

    init(ticket: PlaybackSwitchTicket, autoplayToken: ImportedVideoAutoplayGate.Token,
         reference: WallpaperReference, libraryPending: WallpaperPlaybackSequence.Pending? = nil) {
        self.ticket = ticket
        self.autoplayToken = autoplayToken
        self.reference = reference
        self.libraryPending = libraryPending
    }
}
