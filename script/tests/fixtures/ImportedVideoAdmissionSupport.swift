// Native process/asset/cache/persistence leaves only. Product transaction,
// admission, notification, import preparation/application and Stop bodies are
// inserted by the Python harness from the current source files.
extension VideoWallpaper {
    init(path: String) { self.init(title: path, path: path) }
}

@MainActor enum PlaybackVolumeState {
    static let shared = PlaybackVolumeStateOwner()
}
@MainActor final class PlaybackVolumeStateOwner { func setNormalizedVolume(_ value: Float) {} }
extension PlaybackCommandMultiplexer {
    enum Command { case setVolume(Float) }
    func dispatch(_ command: Command) {}
}
extension WallpaperEngine { func stopPlayback() { activeVideoPlayback = nil; activeVideoExecution = nil } }
extension SceneDaemonClient { func stop() {} }
extension Notification.Name {
    static let onlineVideoReadyToPlay = Self("AdmissionOnlineReady")
    static let onlineDownloadsPlaybackPathDidChange = Self("AdmissionOnlinePath")
}

struct OnlineLibraryVideoItem { let id: Int }
@MainActor final class OnlineLibraryService {
    static var downloadDirectory = URL(fileURLWithPath: "/invalid-test-path")
    var downloadedIDs: Set<Int> = []
    var downloadedContent = OnlineLibraryDownloadedContentSnapshot(revision: 0, entries: [], status: .initial)
    func refreshDownloadedContent() {}
    var requestLibraryPlayback: ((WallpaperReference) -> Void)?
    var prepareVideoPlaybackIntent: ((WallpaperReference, WallpaperPlaybackSequence.Pending?) -> ImportedVideoPlaybackAdmission?)?
    var downloadError: String?
    var downloadStarts = 0
    func startDownload(item: OnlineLibraryVideoItem) { downloadStarts += 1 }
    // ONLINE_METHODS
}

extension WallpaperManager {
    var allowsLibraryMutation: Bool { migrationRecoveryMessage == nil }
    var preservesLegacyMigrationInputs: Bool { migrationRecoveryMessage != nil }
    var defaults: UserDefaults { UserDefaults(suiteName: ProcessInfo.processInfo.environment["MWX_IMPORT_ADMISSION_DOMAIN"]!)! }
    var wallpapersKey: String { "Wallpapers" }
    var initialIndexChangesKey: String { "WallpaperIndexStartupChangesV1" }
    func reportMigrationReadOnly(in window: NSWindow? = nil) { migrationWarnings += 1 }
    func pathExists(_ path: String) -> Bool { FileManager.default.fileExists(atPath: path) }
    func isReadablePath(_ path: String) -> Bool { FileManager.default.isReadableFile(atPath: path) }
    // IMPORT_CACHE_METHODS
    func recordInitialIndexExplicitEdit(_ value: VideoWallpaper, fields: Set<WallpaperIndexStartupChanges.Field>, addedTags: [String] = []) {}
    func recordPlaybackHistoryIfNeeded(current: VideoWallpaper?, targetNormalizedPath: String, enabled: Bool) { if enabled { historyRequests += 1 } }
    func updateRecentWallpapers(_ value: VideoWallpaper) { recentRequests += 1 }
    func applySystemAudioSpectrumToEngine() {}
    func handleMissingWallpaperDuringSwitch(_ value: VideoWallpaper, userInitiated: Bool) { unexpectedMissingFallbacks += 1 }
    func presentImportSummary(_ value: ImportSummary, in window: NSWindow?) { importSummaryCount += 1; onImportSummary?() }
    func scheduleImportedAssetsProcessing(_ urls: [URL]) { importedAssetRequests.append(contentsOf: urls) }
    func navigateLibraryPlayback(_ direction: ManualNavigationDirection,
                                 policy: WallpaperPlaybackSequence.NavigationPolicy = .adjacent) {
        manualNavigationExecutions += 1
        manualNavigationDirections.append(direction)
        manualNavigationPolicies.append(policy)
    }
    // IMPORT_AND_APPLY_METHODS
}
