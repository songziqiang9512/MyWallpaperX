import AppKit
import Combine
import Foundation
import ImageIO
import SQLite3

@MainActor final class PlaybackCommandMultiplexer {
    enum Command { case setPerformanceProfile(maxFPS: Int) }
    static let shared = PlaybackCommandMultiplexer()
    var frames: [Int] = []
    func dispatch(_ command: Command) { if case let .setPerformanceProfile(fps) = command { frames.append(fps) } }
}

// PRODUCTION_IMAGE_MODEL

@MainActor final class SILService {
    static var defersMissingFileCleanupForPersonalSettingsRecovery = false
    private var metadataLoadGeneration: UInt64 = 0
    var wallpapers: [SILWallpaper] = []
    var selectedIDs = Set<String>()
    var selectedID: String?, inspectedWallpaperID: String?
    var missingAlerts = 0
    let persistenceURL: URL
    init(_ url: URL) { persistenceURL = url }
    func scheduleInitialMissingFilesAlert(for removed: [SILWallpaper], attempt: Int) { missingAlerts += 1 }
    func reconcileForAudit() { reconcileMissingFilesOnLaunch() }
    // PRODUCTION_IMAGE_SAVE
}

@MainActor final class PlaybackPolicyController {
    static let shared = PlaybackPolicyController()
    var updates = 0
    func updateSettings(_ settings: WallpaperSettings) { updates += 1 }
}
final class ProfileDefaults: UserDefaults {
    var failSynchronization = false
    override func synchronize() -> Bool { failSynchronization ? false : super.synchronize() }
}
@MainActor final class WallpaperManager {
    var didFinishInitialIndexLoad = true
    var initialIndexInternalPublication = false
    @Published var wallpapers: [VideoWallpaper] = []
    var settings = WallpaperSettings()
    let defaults: ProfileDefaults
    let wallpapersKey = "Wallpapers", settingsKey = "WallpaperSettings"
    var wallpaperIndexSaveRevision: UInt64 = 0, wallpaperIndexSaveEpoch: UInt64 = 0
    var pendingWallpaperIndexSave: WallpaperIndexSaveSnapshot?
    var wallpaperIndexSaveInFlight: WallpaperIndexSaveSnapshot?
    var wallpapersAutoSaveWorkItem: DispatchWorkItem?, settingsAutoSaveWorkItem: DispatchWorkItem?
    var missingIndexedSourceScanWorkItem: DispatchWorkItem?
    var recentlyUsedWallpapers: [VideoWallpaper] = []
    var selectedWallpaperId: String?
    var selectedWallpaperIds = Set<String>()
    var missingAlerts = 0
    var recentWrites = 0, timerRefreshes = 0, loginChanges = 0
    var subscription: AnyCancellable?
    init() {
        defaults = ProfileDefaults(suiteName: ProcessInfo.processInfo.environment["MWX_PROFILE_TEST_DOMAIN"]!)!
        subscription = $wallpapers.dropFirst().sink { [weak self] _ in self?.scheduleWallpapersAutoPersist() }
    }
    func normalizedPath(_ path: String) -> String { URL(fileURLWithPath: path).resolvingSymlinksInPath().standardizedFileURL.path }
    func persistInitialIndexChanges() {}
    func retryInitialIndexLoadIfNeeded() {}
    func clearInitialIndexRecoveryAfterSave() {}
    func saveCodableValue<T: Encodable>(_ value: T, forKey key: String) { defaults.set(try? JSONEncoder().encode(value), forKey: key) }
    func constrainRecentWallpapersToLibrary() { recentWrites += 1 }
    func saveRecentWallpapers() { recentWrites += 1 }
    func refreshAutoSwitchTimerIfNeeded() { timerRefreshes += 1 }
    func updateLoginItemStatus() { loginChanges += 1 }
    nonisolated func normalizedSourcePathExists(_ path: String) -> Bool { FileManager.default.fileExists(atPath: path) }
    func removeDerivedAssets(for record: RemovalRecord) {}
    func resolveNextSelectionID(removedIDs: Set<String>) -> String? { nil }
    func presentAutoRemovedMissingIndexedFilesAlert(titles: [String]) { missingAlerts += 1 }
    // PRODUCTION_VIDEO_STATE
    // PRODUCTION_VIDEO_SAVE
    // PRODUCTION_VIDEO_REMOVAL
}
extension Notification.Name {
    static let wallpaperManagerDidImportPersonalSettings = Notification.Name("ProfileImported")
}

@main struct PersonalSettingsImportHarness {
    static func ref(_ id: String, _ provider: WallpaperProvider = .videoLibrary) -> WallpaperReference {
        .init(provider: provider, sourceID: id)
    }
    static func sql(_ url: URL, _ statement: String) throws {
        var db: OpaquePointer?
        precondition(sqlite3_open(url.path, &db) == SQLITE_OK)
        defer { sqlite3_close(db) }
        precondition(sqlite3_exec(db, statement, nil, nil, nil) == SQLITE_OK)
    }
    static func write(_ payload: PersonalSettingsPayload, to url: URL) throws {
        try LibraryPersonalSettings.encode(payload).write(to: url)
    }
    static func stage(_ url: URL, _ value: Int) throws {
        var object = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
        object["stage"] = value
        try JSONSerialization.data(withJSONObject: object).write(to: url, options: .atomic)
    }
    static func source(_ id: String, _ path: String, _ title: String, _ provider: WallpaperProvider = .videoLibrary,
                       firstIndexedAt: Date? = nil) -> PersonalSettingsLocalSource {
        .init(reference: ref(id, provider), path: path, title: title, firstIndexedAt: firstIndexedAt)
    }
    @MainActor static func main() async throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[1])
        let manager = WallpaperManager()
        defer { manager.defaults.removePersistentDomain(forName: ProcessInfo.processInfo.environment["MWX_PROFILE_TEST_DOMAIN"]!) }
        var checks: [String: Bool] = [:]
        var nativeBackground = WallpaperSettings()
        nativeBackground.libraryBackgroundStyle = .macOSNative
        nativeBackground.volume = 73
        let restoredBackground = try JSONDecoder().decode(WallpaperSettings.self, from: JSONEncoder().encode(nativeBackground))
        checks["BackgroundStylePersistsWithoutChangingOtherSettings"] = restoredBackground == nativeBackground
        for value in ["{}", "{\"libraryBackgroundStyle\":\"future-style\",\"volume\":31}", "{\"libraryBackgroundStyle\":42,\"volume\":31}"] {
            let decoded = try JSONDecoder().decode(WallpaperSettings.self, from: Data(value.utf8))
            checks["MissingOrUnknownBackgroundStyleDefaultsLocally-\(value)"] = decoded.libraryBackgroundStyle == .listCoverTint
                && decoded.volume == (value == "{}" ? 50 : 31)
        }
        let partialPreferences = try JSONDecoder().decode(PersonalSettingsPreferences.self, from: Data("{}".utf8))
        checks["CurrentPartialProfilePreservesLocalBackgroundStyle"] = partialPreferences.applying(to: nativeBackground).libraryBackgroundStyle == .macOSNative
        let exportedBackground = try JSONDecoder().decode(PersonalSettingsPreferences.self,
            from: JSONEncoder().encode(PersonalSettingsPreferences(from: nativeBackground)))
        checks["ProfileRoundTripRestoresExplicitBackgroundStyle"] = exportedBackground.applying(to: WallpaperSettings()).libraryBackgroundStyle == .macOSNative
        let futurePreferences = try JSONDecoder().decode(PersonalSettingsPreferences.self,
            from: Data("{\"libraryBackgroundStyle\":\"future-style\",\"volume\":19}".utf8))
        let futureApplied = futurePreferences.applying(to: nativeBackground)
        checks["UnknownProfileBackgroundStylePreservesLocalStyleAndOtherChanges"] = futureApplied.libraryBackgroundStyle == .macOSNative && futureApplied.volume == 19
        let originalDate = Date(timeIntervalSince1970: 30)
        var clickSettings = WallpaperSettings()
        checks["FreshSettingsKeepListTintAndSelectionOnly"] = clickSettings.libraryBackgroundStyle == .listCoverTint
            && LibraryBackgroundStyle.macOSNative.rawValue == "macOSNative" && clickSettings.libraryCardClickAction == .selectOnly
        clickSettings.libraryBackgroundStyle = .listCoverTint; clickSettings.libraryCardClickAction = .openDetails
        let decodedClicks = try JSONDecoder().decode(WallpaperSettings.self, from: JSONEncoder().encode(clickSettings))
        checks["ExplicitBackgroundAndCardClickChoicesRoundTripWithoutOtherSettingLoss"] = decodedClicks == clickSettings
        for raw in ["{}", "{\"libraryCardClickAction\":\"future-action\",\"volume\":31}", "{\"libraryCardClickAction\":42,\"volume\":31}"] {
            let decoded = try JSONDecoder().decode(WallpaperSettings.self, from: Data(raw.utf8))
            checks["MissingOrUnknownCardClickActionDefaultsLocally-\(raw)"] = decoded.libraryCardClickAction == .selectOnly
                && decoded.volume == (raw == "{}" ? 50 : 31)
        }
        let clickProfile = try JSONDecoder().decode(PersonalSettingsPreferences.self,
            from: JSONEncoder().encode(PersonalSettingsPreferences(from: clickSettings)))
        checks["ProfileRestoresExplicitCardClickChoice"] = clickProfile.applying(to: WallpaperSettings()).libraryCardClickAction == .openDetails
        var laterClickSettings = clickSettings; laterClickSettings.libraryCardClickAction = .selectOnly
        checks["ExplicitCardClickRecoverySnapshotStillRejectsLaterLocalEdit"] = clickProfile != .init(from: laterClickSettings)
        var incompleteClickSnapshot = clickProfile; incompleteClickSnapshot.libraryCardClickAction = nil
        checks["IncompleteRecoverySnapshotDoesNotBorrowTheCurrentCardClickField"] = incompleteClickSnapshot != .init(from: laterClickSettings)
        checks["CurrentPartialProfilePreservesLocalCardClickChoice"] = partialPreferences.applying(to: clickSettings).libraryCardClickAction == .openDetails
        var shortcutSettings = clickSettings
        shortcutSettings.systemHotkeysEnabled = true
        shortcutSettings.previousWallpaperHotkey = .f2; shortcutSettings.nextWallpaperHotkey = .f4
        shortcutSettings.togglePlaybackHotkey = .f6; shortcutSettings.toggleMuteHotkey = .f8
        let shortcutProfile = try JSONDecoder().decode(PersonalSettingsPreferences.self,
            from: JSONEncoder().encode(PersonalSettingsPreferences(from: shortcutSettings)))
        let shortcutRestored = shortcutProfile.applying(to: WallpaperSettings())
        checks["PortableShortcutEnableAndBindingsRoundTripThroughTheOriginalPreferences"] = shortcutRestored.systemHotkeysEnabled
            && shortcutRestored.previousWallpaperHotkey == .f2 && shortcutRestored.nextWallpaperHotkey == .f4
            && shortcutRestored.togglePlaybackHotkey == .f6 && shortcutRestored.toggleMuteHotkey == .f8
        checks["CurrentPartialProfilesDoNotClaimExistingShortcutPreferences"] = partialPreferences.applying(to: shortcutSettings).previousWallpaperHotkey == .f2
            && partialPreferences.applying(to: shortcutSettings).systemHotkeysEnabled
        var incompleteShortcutSnapshot = shortcutProfile; incompleteShortcutSnapshot.toggleMuteHotkey = nil
        checks["IncompleteRecoverySnapshotCannotMatchACompleteCurrentPreferenceSnapshot"] = incompleteShortcutSnapshot != .init(from: shortcutSettings)
        let unknownClickProfile = try JSONDecoder().decode(PersonalSettingsPreferences.self,
            from: Data("{\"libraryCardClickAction\":\"future-action\",\"volume\":19}".utf8))
        let unknownApplied = unknownClickProfile.applying(to: clickSettings)
        checks["UnknownProfileCardClickChoicePreservesLocalAndOtherChanges"] = unknownApplied.libraryCardClickAction == .openDetails
            && unknownApplied.libraryBackgroundStyle == .listCoverTint && unknownApplied.volume == 19
        let a = VideoWallpaper(id: "A", title: "Original", path: root.appendingPathComponent("missing-A.mp4").path,
            thumbnailPath: "/derived/thumbnail", isFavorite: true, lastUsed: originalDate, tags: ["retired"], duration: 50,
            firstIndexedAt: Date(timeIntervalSinceReferenceDate: 800_000_000.0000001))
        manager.initialIndexInternalPublication = true; manager.wallpapers = [a]; manager.initialIndexInternalPublication = false
        try WallpaperIndexStore.shared.saveWallpapers(manager.wallpapers)
        let imageURL = root.appendingPathComponent("images.json")
        let images = SILService(imageURL)
        let storeURL = root.appendingPathComponent("relations.sqlite3")
        let store = UserCollectionsStore(url: storeURL)
        let initial = try await store.snapshot()
        checks.merge(try screenSaverPreferenceChecks(state: initial)) { _, next in next }
        let controller = UserCollectionsController(store: store, snapshot: initial)
        let presentation = WallpaperLibraryPresentation(collections: controller, defaults: manager.defaults)
        _ = presentation.update(catalog: .init(), relationships: controller.snapshot)
        func makeCoordinator(_ recoveryURL: URL) -> PersonalSettingsImportCoordinator {
            PersonalSettingsImportCoordinator(manager: manager, images: images, collections: controller, recoveryURL: recoveryURL,
                readVideoSort: { try presentation.videoSortPreference() },
                validateVideoSort: { try presentation.validateVideoSortPatch($0, resetEpoch: $1) },
                applyVideoSort: { try presentation.applyVideoSortPatch($0, resetEpoch: $1) })
        }
        if CommandLine.arguments.dropFirst(2).contains("video-sort") {
            try await runVideoSortProfileChecks(root: root, manager: manager, images: images, controller: controller,
                presentation: presentation)
            return
        }
        if CommandLine.arguments.dropFirst(2).contains("source-persistence") {
            let sourceChecks = try await runSourcePersistenceChecks(root: root, manager: manager, images: images,
                controller: controller, presentation: presentation)
            print(String(data: try JSONEncoder().encode(sourceChecks), encoding: .utf8)!)
            return
        }
        if CommandLine.arguments.dropFirst(2).contains("path-reuse") {
            let firstDirectory = root.appendingPathComponent("first", isDirectory: true)
            let secondDirectory = root.appendingPathComponent("second", isDirectory: true)
            for directory in [firstDirectory, secondDirectory] {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
                try Data("local media".utf8).write(to: directory.appendingPathComponent("movie.mp4"))
            }
            let alias = root.appendingPathComponent("alias", isDirectory: true)
            try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: firstDirectory)
            let aliasPath = alias.appendingPathComponent("movie.mp4").path
            let firstPath = firstDirectory.appendingPathComponent("movie.mp4").resolvingSymlinksInPath().standardizedFileURL.path
            let secondPath = secondDirectory.appendingPathComponent("movie.mp4").resolvingSymlinksInPath().standardizedFileURL.path
            let recovery = root.appendingPathComponent("path-recovery.json"), profile = root.appendingPathComponent("path-profile.json")
            let importer = makeCoordinator(recovery)
            let declared = source("duplicate-path", aliasPath, "First resolution")
            var incoming = LibraryCollectionsPersonalSettingsImport()
            incoming.locators = [.init(reference: declared.reference, locator: .init(path: aliasPath))]
            try write(.init(exportedAt: originalDate, preferences: .init(from: manager.settings),
                sources: [declared, declared, source("direct-alias", firstPath, "First resolution")], collections: incoming), to: profile)
            let firstSummary = try await importer.importPersonalSettings(from: profile)
            let firstRows = try WallpaperIndexStore.shared.loadWallpapers()
            checks["RepeatedAndAliasPathsMergeToOriginalFirstReference"] = firstRows == manager.wallpapers
                && firstRows.count == 2 && firstRows[1].id == declared.reference.sourceID && firstRows[1].path == firstPath
                && firstSummary.createdWallpaperCount == 1 && firstSummary.missingPathCount == 0
            try FileManager.default.removeItem(at: alias)
            try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: secondDirectory)
            let next = source("next-import", aliasPath, "Fresh resolution")
            incoming.locators = [.init(reference: next.reference, locator: .init(path: aliasPath))]
            try write(.init(exportedAt: originalDate, preferences: .init(from: manager.settings),
                sources: [next, next], collections: incoming), to: profile)
            let secondSummary = try await importer.importPersonalSettings(from: profile)
            let secondRows = try WallpaperIndexStore.shared.loadWallpapers()
            checks["NextImportResolvesRetargetedAliasAgain"] = secondRows == manager.wallpapers && secondRows.count == 3
                && secondRows[1] == firstRows[1] && secondRows[2].id == next.reference.sourceID && secondRows[2].path == secondPath
                && secondSummary.createdWallpaperCount == 1 && secondSummary.missingPathCount == 0
            checks["DeclaredLocatorsKeepBothCurrentSourceIdentities"] = controller.snapshot.locators.contains { $0.reference == declared.reference && $0.locator.path == aliasPath }
                && controller.snapshot.locators.contains { $0.reference == next.reference && $0.locator.path == aliasPath }
            checks["SuccessfulRepeatedImportsLeaveNoRecoveryOrPlaybackSideEffects"] = importer.allowsEditing
                && !FileManager.default.fileExists(atPath: recovery.path) && manager.recentWrites == 0 && manager.timerRefreshes == 0
            func object<T: Encodable>(_ value: T) throws -> Any { try JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) }
            let result: [String: Any] = ["checks": checks, "projection": ["firstRows": try object(firstRows),
                "secondRows": try object(secondRows), "firstSummary": try object(firstSummary), "secondSummary": try object(secondSummary),
                "locators": try object(controller.snapshot.locators)]]
            print(String(decoding: try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys]), as: UTF8.self))
            return
        }
        let existing = WallpaperPlaylist(name: "Same name", createdAt: originalDate, sidebarRank: 0)
        let local = WallpaperOrganizationItem(reference: ref("A"), locator: .init(path: a.path), isPublishedLocally: true, isAvailable: true)
        let other = WallpaperOrganizationItem(reference: ref("keep"), locator: .init(), isPublishedLocally: true, isAvailable: true)
        _ = try await controller.perform([.createPlaylist(existing), .addMembers(existing.id, [local], originalDate),
            .setFavorite(local, true, originalDate), .setFavorite(other, true, originalDate),
            .rememberLocator(.init(reference: ref("plain", .pixabay), locator: .init(titleHint: "Plain")))])
        controller.recordSuccessfulUse(ref("A"), locator: nil, sequence: 1, at: originalDate); _ = await controller.flush()
        let history = controller.snapshot.recent
        let patchSources = (0..<300).map { source("patch-\($0)", "/offline/patch-\($0).mp4", "Patch \($0)") }
            + [source("\u{e9}", "/offline/nfc.mp4", "NFC"), source("e\u{301}", "/offline/nfd.mp4", "NFD")]
        let declaredLocator = WallpaperReferenceLocator(reference: patchSources[0].reference,
            locator: .init(path: "/explicit/keep.mp4", titleHint: "Keep declared locator", mediaKind: .video))
        let patchPayload = PersonalSettingsPayload(exportedAt: originalDate, preferences: .init(from: manager.settings),
            sources: patchSources + [source("same-path-new-id", patchSources[0].path, "Merged source")],
            collections: .init(locators: [declaredLocator]))
        let patchPlan = try LibraryPersonalSettings.plan(patchPayload, sources: [],
            beforePreferences: .init(from: manager.settings), targetPreferences: .init(from: manager.settings),
            state: initial, normalizedPaths: [:], missingPathCount: patchSources.count)
        checks["SourcePatchLocatorMembershipPreservesDeclaredValuesAndAppendOrder"] = patchPlan.collections.locators.first == declaredLocator
            && patchPlan.collections.locators.map(\.reference) == patchSources.map(\.reference)
            && patchPlan.sourcePatches.map { $0.target.reference } == patchSources.map(\.reference)
        checks["SourcePatchLocatorMembershipDeduplicatesRemappedPathsWithoutCollapsingOpaqueIDs"] = patchPlan.collections.locators.count == 302
            && patchPlan.collections.locators.suffix(2).map(\.reference) == patchSources.suffix(2).map(\.reference)
        let onlineRefs = [ref("Ab001", .wallhaven), ref("001234:p0", .pixiv), ref("001234:p2", .pixiv)]
        let onlineList = WallpaperPlaylist(name: "Offline online images", sidebarRank: 0)
        let onlineMembers = onlineRefs.enumerated().map {
            WallpaperPlaylistMember(playlistID: onlineList.id, reference: $0.element, position: $0.offset, addedAt: originalDate)
        }
        let onlineLocators = onlineRefs.map { WallpaperReferenceLocator(reference: $0,
            locator: .init(path: "/offline/" + $0.storageKey, titleHint: "Saved image", mediaKind: .image)) }
        let onlineState = UserCollectionsSnapshot(revision: 1, resetEpoch: UUID(), playlists: [onlineList], members: onlineMembers,
            favorites: onlineRefs.map { .init(reference: $0, favoritedAt: originalDate) }, recent: [], aliases: [], locators: onlineLocators)
        let onlinePayload = try LibraryPersonalSettings.export(sources: [], preferences: .init(from: manager.settings), state: onlineState)
        let onlineBytes = try LibraryPersonalSettings.encode(onlinePayload)
        let onlineDecoded = try LibraryPersonalSettings.decode(onlineBytes)
        let onlinePlan = try LibraryPersonalSettings.plan(onlineDecoded, sources: [],
            beforePreferences: .init(from: manager.settings), targetPreferences: .init(from: manager.settings),
            state: initial, normalizedPaths: [:], missingPathCount: onlineRefs.count)
        checks["SchemaEightPreservesOpaqueOnlineImagePageRelationsWithoutCreatingSILSources"] = onlineDecoded.schemaVersion == 8
            && onlinePlan.sourcePatches.isEmpty && onlinePlan.collections.members == onlineMembers
            && onlinePlan.collections.favoriteStates.map(\.reference) == onlineRefs && onlinePlan.collections.locators == onlineLocators
        var credentialObject = try JSONSerialization.jsonObject(with: onlineBytes) as! [String: Any]
        credentialObject["pixivCookie"] = "fixture-cookie-must-not-export"
        credentialObject["wallhavenAPIKey"] = "fixture-key-must-not-export"
        let withoutCredentials = try LibraryPersonalSettings.encode(LibraryPersonalSettings.decode(JSONSerialization.data(withJSONObject: credentialObject)))
        checks["OnlineCredentialsHaveNoPersonalSettingsRepresentation"] = !String(decoding: withoutCredentials, as: UTF8.self).contains("fixture-cookie-must-not-export")
            && !String(decoding: withoutCredentials, as: UTF8.self).contains("fixture-key-must-not-export")
        credentialObject["schemaVersion"] = 9
        do {
            _ = try LibraryPersonalSettings.decode(JSONSerialization.data(withJSONObject: credentialObject))
            checks["NextPersonalSettingsSchemaIsRejected"] = false
        } catch PersonalSettingsError.unsupportedSchema(9) { checks["NextPersonalSettingsSchemaIsRejected"] = true }
        manager.settings.systemHotkeysEnabled = true; manager.settings.previousWallpaperHotkey = .f3
        manager.settings.restorePlaybackOnLaunch = false
        let partialPayload = PersonalSettingsPayload(exportedAt: originalDate,
            preferences: try JSONDecoder().decode(PersonalSettingsPreferences.self, from: Data("{\"volume\":17}".utf8)),
            sources: [], collections: .init())
        let partialBytes = try LibraryPersonalSettings.encode(partialPayload)
        let partial = try LibraryPersonalSettings.decode(partialBytes).preferences.applying(to: manager.settings)
        checks["CurrentPartialPreferencesPreserveUnselectedValues"] = partial.volume == 17
            && !partial.restorePlaybackOnLaunch && partial.systemHotkeysEnabled && partial.previousWallpaperHotkey == .f3
        for version in 1...7 {
            var old = try JSONSerialization.jsonObject(with: partialBytes) as! [String: Any]
            old["schemaVersion"] = version
            let bytes = try JSONSerialization.data(withJSONObject: old), file = root.appendingPathComponent("unsupported-\(version).json")
            try bytes.write(to: file)
            let sourceBefore = manager.wallpapers, organizationBefore = controller.snapshot, settingsBefore = manager.settings
            do { _ = try await makeCoordinator(root.appendingPathComponent("unsupported-recovery.json")).importPersonalSettings(from: file); checks["Schema\(version)RejectsWithoutMutation"] = false }
            catch PersonalSettingsError.unsupportedSchema(let found) {
                checks["Schema\(version)RejectsWithoutMutation"] = try Data(contentsOf: file) == bytes
                    && found == version && manager.wallpapers == sourceBefore && controller.snapshot == organizationBefore && manager.settings == settingsBefore
            }
        }
        let extreme = try JSONDecoder().decode(PersonalSettingsPreferences.self, from: Data("""
            {"idleTimeoutMinutes":-9223372036854775808,"systemAudioSpectrumBarCount":9223372036854775807,
            "volume":900,"playbackRate":99,"systemAudioSpectrumOffsetX":9,"systemAudioSpectrumOffsetY":-9}
            """.utf8)).applying(to: manager.settings)
        checks["ExternalPreferenceBoundsHaveNoIntegerOverflow"] = extreme.idleTimeoutMinutes == 5 && extreme.systemAudioSpectrumBarCount == 48
            && extreme.volume == 100 && extreme.playbackRate == 2 && extreme.systemAudioSpectrumOffsetX == 0.3 && extreme.systemAudioSpectrumOffsetY == -0.2
        let exportURL = root.appendingPathComponent("export.json")
        let recoveryURL = root.appendingPathComponent("pending.json")
        let coordinator = makeCoordinator(recoveryURL)
        _ = try await coordinator.exportPersonalSettings(to: exportURL)
        let exported = try LibraryPersonalSettings.decode(Data(contentsOf: exportURL))
        let object = try JSONSerialization.jsonObject(with: Data(contentsOf: exportURL)) as! [String: Any]
        let exportedPreferences = object["preferences"] as? [String: Any]
        let exportedJSON = String(decoding: try Data(contentsOf: exportURL), as: UTF8.self)
        checks["SchemaEightExportExcludesRuntimeHistoryCredentialsAndWallpaperMedia"] = exported.schemaVersion == 8
            && object["recent"] == nil && object["currentWallpaper"] == nil && object["session"] == nil
            && (exportedPreferences?["systemHotkeysEnabled"] as? Bool) == manager.settings.systemHotkeysEnabled
            && object["pixivCookie"] == nil && object["wallhavenAPIKey"] == nil
            && !exportedJSON.contains("/derived/thumbnail")
        checks["ExportIncludesExplicitFalseForUnfavoritedReferences"] = exported.collections.favoriteStates.contains { $0.reference == ref("plain", .pixabay) && !$0.isFavorite } == true
        checks["SourceAdmissionExportsSeparatelyFromPlaybackHistory"] = exported.sources.first?.firstIndexedAt == a.firstIndexedAt
            && exported.sources.first?.firstIndexedAt != a.lastUsed
            && ((object["sources"] as? [[String: Any]])?.first?["firstIndexedAtReferenceDate"] as? Double) == a.firstIndexedAt?.timeIntervalSinceReferenceDate
        let exactSource = manager.personalSettingsSources[0]
        checks["SourceRecoveryCodecPreservesOddReferenceDateULP"] = try JSONDecoder().decode(PersonalSettingsLocalSource.self,
            from: JSONEncoder().encode(exactSource)) == exactSource
        let second = WallpaperPlaylist(name: existing.name, createdAt: originalDate, sidebarRank: 1)
        var incoming = LibraryCollectionsPersonalSettingsImport()
        incoming.playlists = [second]
        incoming.members = [.init(playlistID: second.id, reference: ref("video:offline-scene", .steamWorkshop), position: 0, addedAt: originalDate),
            .init(playlistID: second.id, reference: ref("77", .pixabay), position: 1, addedAt: originalDate)]
        incoming.favoriteStates = [.init(reference: ref("A"), isFavorite: false)]
        incoming.locators = [.init(reference: ref("video:offline-scene", .steamWorkshop), locator: .init(path: "/offline/scene", mediaKind: .scene))]
        var prefs = PersonalSettingsPreferences(from: manager.settings)
        prefs.volume = 71; prefs.randomPlayback = true; prefs.autoSwitchEnabled = true
        let incomingImage = source("image-I", root.appendingPathComponent("offline.png").path, "Offline image", .staticImageLibrary)
        let payload = PersonalSettingsPayload(exportedAt: originalDate, preferences: prefs,
            sources: [source("A", a.path, "Imported"), incomingImage], collections: incoming)
        let profile = root.appendingPathComponent("profile.json"); try write(payload, to: profile)
        let profileBytes = try Data(contentsOf: profile)
        let unwritableRecoveryParent = root.appendingPathComponent("unwritable-recovery", isDirectory: true)
        try FileManager.default.createDirectory(at: unwritableRecoveryParent, withIntermediateDirectories: false)
        let unwritableRecovery = makeCoordinator(unwritableRecoveryParent.appendingPathComponent("prepared.json"))
        let sourcesBeforeFailedPreparation = manager.wallpapers
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: unwritableRecoveryParent.path)
        do {
            _ = try await unwritableRecovery.importPersonalSettings(from: profile)
            checks["FailedRecoveryPreparationDoesNotClaimAnImportOrMutateOwners"] = false
        } catch {
            checks["FailedRecoveryPreparationDoesNotClaimAnImportOrMutateOwners"] = unwritableRecovery.allowsEditing
                && unwritableRecovery.recoveryMessage == nil && manager.wallpapers == sourcesBeforeFailedPreparation
                && !FileManager.default.fileExists(atPath: unwritableRecoveryParent.appendingPathComponent("prepared.json").path)
        }
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: unwritableRecoveryParent.path)
        let hdrBefore = SceneHDRDisplayPreference.isEnabled, mediaBefore = SceneMediaSourcePreference.isEnabled
        let frameBudgetBefore = PlaybackPerformanceProfile.current
        var completePreferences = prefs
        completePreferences.sceneHDRDisplayEnabled = !hdrBefore
        completePreferences.sceneMediaInfoEnabled = !mediaBefore
        completePreferences.playbackPerformanceProfile = frameBudgetBefore == .standard ? 30 : 60
        let completeProfile = root.appendingPathComponent("all-portable-preferences.json")
        try write(.init(exportedAt: originalDate, preferences: completePreferences, sources: [], collections: .init()), to: completeProfile)
        _ = try await coordinator.importPersonalSettings(from: completeProfile)
        checks["ExternalPortablePreferencesApplyThroughTheirOriginalOwnersWithoutPlayback"] = SceneHDRDisplayPreference.isEnabled == !hdrBefore
            && SceneMediaSourcePreference.isEnabled == !mediaBefore
            && PlaybackPerformanceProfile.current.rawValue == completePreferences.playbackPerformanceProfile
            && PlaybackCommandMultiplexer.shared.frames.last == PlaybackPerformanceProfile.current.maxFPS && manager.recentWrites == 0
        let portableBackup = root.appendingPathComponent("all-portable-backup.json")
        _ = try await coordinator.exportPersonalSettings(to: portableBackup)
        let portableExport = try LibraryPersonalSettings.decode(Data(contentsOf: portableBackup)).preferences
        checks["ExternalPortablePreferencesAreIncludedInTheOriginalProfileExport"] = portableExport.sceneHDRDisplayEnabled == !hdrBefore
            && portableExport.sceneMediaInfoEnabled == !mediaBefore && portableExport.playbackPerformanceProfile == PlaybackPerformanceProfile.current.rawValue
        let result = try await coordinator.importPersonalSettings(from: profile)
        checks["CurrentPartialProfilesLeaveUnselectedExternalPreferencesWithTheirOwners"] = SceneHDRDisplayPreference.isEnabled == !hdrBefore
            && SceneMediaSourcePreference.isEnabled == !mediaBefore && PlaybackPerformanceProfile.current.rawValue == completePreferences.playbackPerformanceProfile
        checks["SameNameDifferentUUIDAndMixedOfflineMembersSurvive"] = controller.snapshot.playlists.count == 2
            && controller.snapshot.members.filter { $0.playlistID == second.id }.map(\.reference) == [ref("video:offline-scene", .steamWorkshop), ref("77", .pixabay)]
        checks["ExplicitFalseOnlyClearsItsCanonicalFavorite"] = !controller.snapshot.favorites.contains { $0.reference == ref("A") }
            && controller.snapshot.favorites.contains { $0.reference == ref("keep") }
        checks["OriginalSourcePersistenceReceivesMetadataNotRetiredRelationships"] = try WallpaperIndexStore.shared.loadWallpapers().first?.title == "Imported"
            && manager.wallpapers[0].isFavorite && manager.wallpapers[0].tags == ["retired"] && manager.wallpapers[0].lastUsed == originalDate
            && manager.wallpapers[0].duration == 50
        checks["MissingProfileAdmissionDoesNotClearKnownSourceTime"] = try manager.wallpapers[0].firstIndexedAt == a.firstIndexedAt
            && WallpaperIndexStore.shared.loadWallpapers().first?.firstIndexedAt == a.firstIndexedAt
        let writtenImages = try JSONDecoder().decode([SILWallpaper].self, from: Data(contentsOf: imageURL))
        checks["OfflineImageRestoresWithoutMediaProbeOrPlaybackHistory"] = writtenImages.first?.id == "image-I"
            && writtenImages.first?.pixelWidth == nil && writtenImages.first?.fileSize == nil && writtenImages.first?.lastUsed == .distantPast
            && controller.snapshot.recent == history && manager.recentWrites == 0 && manager.timerRefreshes == 0
        let afterProfileBytes = try Data(contentsOf: profile)
        checks["ImportCompletesAllOwnersBeforeSummaryAndNeverRewritesBackup"] = result.createdWallpaperCount == 1 && result.mergedWallpaperCount == 1
            && result.missingPathCount == 3 && manager.settings.volume == 71 && manager.settings.previousWallpaperHotkey == .f3
            && coordinator.allowsEditing && !FileManager.default.fileExists(atPath: recoveryURL.path)
            && afterProfileBytes == profileBytes
        let count = manager.wallpapers.count
        _ = try await coordinator.importPersonalSettings(from: profile)
        checks["RepeatedSchemaEightImportDoesNotDuplicateSourcePlaylistOrMembers"] = manager.wallpapers.count == count
            && images.wallpapers.count == 1 && controller.snapshot.playlists.count == 2 && controller.snapshot.members.count == 3
        let beforeUnknown = manager.wallpapers
        let future = root.appendingPathComponent("future.json")
        let futureBytes = Data("{\"schemaVersion\":99,\"unreadableFuture\":\"retained\"}".utf8); try futureBytes.write(to: future)
        do { _ = try await coordinator.importPersonalSettings(from: future); checks["FutureSchemaRejectedBeforeAnyOwnerWrite"] = false }
        catch PersonalSettingsError.unsupportedSchema(99) {
            let afterFutureBytes = try Data(contentsOf: future)
            checks["FutureSchemaRejectedBeforeAnyOwnerWrite"] = manager.wallpapers == beforeUnknown
                && afterFutureBytes == futureBytes && !FileManager.default.fileExists(atPath: recoveryURL.path)
        }
        manager.didFinishInitialIndexLoad = false
        do { _ = try await coordinator.importPersonalSettings(from: root.appendingPathComponent("does-not-exist")); checks["PendingCurrentIndexDeniesBeforeReadingProfile"] = false }
        catch PersonalSettingsError.indexLoading { checks["PendingCurrentIndexDeniesBeforeReadingProfile"] = true }
        manager.didFinishInitialIndexLoad = true

        // Real original IndexStore fails; the source array is not published and
        // the prepared recovery remains retryable, with no fallback fake commit.
        var changed = payload.sources; changed[0] = source("A", a.path, "After failure")
        let failingPayload = PersonalSettingsPayload(exportedAt: originalDate, preferences: prefs, sources: changed, collections: incoming)
        try write(failingPayload, to: profile)
        try WallpaperIndexStore.shared.profileQueryOnly(true)
        do { _ = try await coordinator.importPersonalSettings(from: profile); checks["RealVideoWriteFailureLeavesOldMemoryAndRecovery"] = false }
        catch { checks["RealVideoWriteFailureLeavesOldMemoryAndRecovery"] = manager.wallpapers[0].title == "Imported"
            && FileManager.default.fileExists(atPath: recoveryURL.path) && !coordinator.allowsEditing }
        try WallpaperIndexStore.shared.profileQueryOnly(false)
        _ = try await coordinator.resumeIfNeeded()
        checks["RealVideoFailureResumesThroughOriginalOwner"] = manager.wallpapers[0].title == "After failure" && coordinator.allowsEditing
            && manager.wallpapers[0].firstIndexedAt == a.firstIndexedAt

        // The original image writer fails at its real filesystem leaf, after
        // Video committed. Recreate the path and restart the App coordinator.
        try FileManager.default.removeItem(at: imageURL); try FileManager.default.createDirectory(at: imageURL, withIntermediateDirectories: false)
        changed[0] = source("A", a.path, "Before image recovery")
        try write(.init(exportedAt: originalDate, preferences: prefs, sources: changed, collections: incoming), to: profile)
        do { _ = try await coordinator.importPersonalSettings(from: profile); checks["RealImageWriteFailureRetainsPreviousOwnerAndStage"] = false }
        catch { checks["RealImageWriteFailureRetainsPreviousOwnerAndStage"] = manager.wallpapers[0].title == "Before image recovery"
            && !coordinator.allowsEditing && FileManager.default.fileExists(atPath: recoveryURL.path) }
        try FileManager.default.removeItem(at: imageURL)
        // Emulate durable Video commit followed by a crash before its stage
        // acknowledgement. A new source owner loads the real SQLite value,
        // then recovery retries the exact before/target admission precondition.
        try stage(recoveryURL, 0)
        manager.initialIndexInternalPublication = true
        manager.wallpapers = try WallpaperIndexStore.shared.loadWallpapers()
        manager.initialIndexInternalPublication = false
        let restarted = makeCoordinator(recoveryURL)
        checks["StartupPendingRecoveryBlocksNewEditing"] = !restarted.allowsEditing
        _ = try await restarted.resumeIfNeeded()
        checks["RestartResumesHalfImportAndPreservesRelationshipHistory"] = restarted.allowsEditing
            && controller.snapshot.recent == history && images.wallpapers.count == 1
        checks["SQLiteReloadAndPreAckStageReplayKeepOddSourceTimeULP"] = try manager.wallpapers[0].firstIndexedAt == a.firstIndexedAt
            && WallpaperIndexStore.shared.loadWallpapers()[0].firstIndexedAt == a.firstIndexedAt

        let beforeFailedRelationship = controller.snapshot.organizationState
        try sql(storeURL, "CREATE TRIGGER reject_profile BEFORE INSERT ON playlists BEGIN SELECT RAISE(ABORT,'profile fixture');END;")
        changed[0] = source("A", a.path, "Before relationship recovery")
        try write(.init(exportedAt: originalDate, preferences: prefs, sources: changed, collections: incoming), to: profile)
        do { _ = try await restarted.importPersonalSettings(from: profile); checks["RealRelationshipFailureRetainsRecoveryAfterSourceCommit"] = false }
        catch { checks["RealRelationshipFailureRetainsRecoveryAfterSourceCommit"] = manager.wallpapers[0].title == "Before relationship recovery"
            && controller.snapshot.organizationState == beforeFailedRelationship && !restarted.allowsEditing }
        try sql(storeURL, "DROP TRIGGER reject_profile")
        _ = try await restarted.resumeIfNeeded()
        checks["RealRelationshipFailureResumesWithoutSourceDuplication"] = restarted.allowsEditing
            && manager.wallpapers.count == 1 && images.wallpapers.count == 1 && controller.snapshot.members.count == 3

        // A failed preference acknowledgement happens after a real SQLite
        // commit; emulate a crash before that commit's stage record persisted.
        manager.defaults.failSynchronization = true
        var newPrefs = prefs; newPrefs.volume = 23
        try write(.init(exportedAt: originalDate, preferences: newPrefs, sources: changed, collections: incoming), to: profile)
        do { _ = try await restarted.importPersonalSettings(from: profile); checks["PreferenceDurabilityFailureDoesNotReportSuccess"] = false }
        catch { checks["PreferenceDurabilityFailureDoesNotReportSuccess"] = manager.settings.volume == 71 && !restarted.allowsEditing }
        manager.defaults.failSynchronization = false
        try stage(recoveryURL, 2)
        let laterMetadata = controller.snapshot.playlists.first { $0.id == second.id }!.metadata
        var laterReplacement = laterMetadata; laterReplacement.name = "Later edit"
        _ = try await controller.perform(.editPlaylistMetadata(id: second.id, expected: laterMetadata,
            replacement: laterReplacement, coverAsset: nil, at: Date()))
        _ = try await restarted.resumeIfNeeded()
        checks["CommittedCommandMarkerPreservesLaterOrganizationEditsOnReplay"] = controller.snapshot.playlists.contains { $0.id == second.id && $0.name == "Later edit" }
            && manager.settings.volume == 23 && restarted.allowsEditing

        // Conflict evidence remains byte-for-byte, never rolling back a later
        // title or preferences edit merely to finish an old command.
        manager.defaults.failSynchronization = true
        newPrefs.volume = 35
        try write(.init(exportedAt: originalDate, preferences: newPrefs, sources: changed, collections: incoming), to: profile)
        do { _ = try await restarted.importPersonalSettings(from: profile) } catch {}
        manager.defaults.failSynchronization = false
        let recoveryBytes = try Data(contentsOf: recoveryURL)
        manager.settings.volume = 88
        do { _ = try await restarted.resumeIfNeeded(); checks["LaterPreferencesEditRejectsResumeWithoutOverwrite"] = false }
        catch PersonalSettingsError.preferencesChanged {
            let afterRecoveryBytes = try Data(contentsOf: recoveryURL)
            checks["LaterPreferencesEditRejectsResumeWithoutOverwrite"] = manager.settings.volume == 88 && afterRecoveryBytes == recoveryBytes
        }
        restarted.cancelForReset()
        try await controller.reset()
        try restarted.clearRecoveryAfterReset()
        checks["ResetEpochRetiresOldRecoveryWithoutReimport"] = restarted.allowsEditing
            && !FileManager.default.fileExists(atPath: recoveryURL.path) && controller.snapshot.playlists.isEmpty

        // Current recovery owns complete per-owner snapshots. A missing field
        // is corruption, not permission to borrow a later local preference.
        do {
            let originalSettings = manager.settings
            defer { manager.settings = originalSettings; manager.defaults.failSynchronization = false }
            let journalURL = root.appendingPathComponent("background-recovery.json")
            let inputURL = root.appendingPathComponent("background-profile.json")
            manager.settings.libraryBackgroundStyle = .macOSNative
            let beforeStyleEdit = PersonalSettingsPreferences(from: manager.settings)
            let importer = makeCoordinator(journalURL)
            var target = beforeStyleEdit; target.volume = 25
            try write(.init(exportedAt: originalDate, preferences: target, sources: [], collections: .init()), to: inputURL)
            manager.defaults.failSynchronization = true
            do { _ = try await importer.importPersonalSettings(from: inputURL) } catch {}
            manager.defaults.failSynchronization = false
            let intact = try Data(contentsOf: journalURL)
            var object = try JSONSerialization.jsonObject(with: intact) as! [String: Any]
            var plan = object["plan"] as! [String: Any]
            for key in ["beforePreferences", "targetPreferences"] {
                var preferences = plan[key] as! [String: Any]
                preferences.removeValue(forKey: "libraryBackgroundStyle")
                preferences.removeValue(forKey: "libraryCardClickAction")
                plan[key] = preferences
            }
            object["plan"] = plan
            let incomplete = try JSONSerialization.data(withJSONObject: object)
            try incomplete.write(to: journalURL)
            let incompleteOwner = makeCoordinator(journalURL)
            do { _ = try await incompleteOwner.resumeIfNeeded(); checks["IncompleteCurrentJournalCannotBorrowMissingFields"] = false }
            catch PersonalSettingsError.preferencesChanged {
                checks["IncompleteCurrentJournalCannotBorrowMissingFields"] = try Data(contentsOf: journalURL) == incomplete
                    && manager.settings.volume == originalSettings.volume && !incompleteOwner.allowsEditing
            }
            try intact.write(to: journalURL)
            manager.settings.libraryBackgroundStyle = .listCoverTint
            let explicitOwner = makeCoordinator(journalURL)
            do { _ = try await explicitOwner.resumeIfNeeded(); checks["ExplicitJournalRejectsLaterBackgroundEditWithoutChangingRecovery"] = false }
            catch PersonalSettingsError.preferencesChanged {
                checks["ExplicitJournalRejectsLaterBackgroundEditWithoutChangingRecovery"] = try Data(contentsOf: journalURL) == intact
                    && manager.settings.volume == originalSettings.volume && !explicitOwner.allowsEditing
            }
            do { try manager.applyPersonalSettingsPreferences(expected: beforeStyleEdit, target: target); checks["DirectPreferenceOwnerAlsoRejectsExplicitLaterBackgroundEdit"] = false }
            catch PersonalSettingsError.preferencesChanged { checks["DirectPreferenceOwnerAlsoRejectsExplicitLaterBackgroundEdit"] = manager.settings.libraryBackgroundStyle == .listCoverTint }
            manager.settings.libraryBackgroundStyle = .macOSNative
            _ = try await explicitOwner.resumeIfNeeded()
            checks["CurrentJournalResumesAfterItsExactBackgroundChoiceIsRestored"] = explicitOwner.allowsEditing
                && manager.settings.libraryBackgroundStyle == .macOSNative && manager.settings.volume == 25
        }

        let fresh = makeCoordinator(recoveryURL)
        var retainedRelations = incoming
        retainedRelations.playlists.insert(existing, at: 0)
        retainedRelations.members.insert(.init(playlistID: existing.id, reference: ref("A"), position: 0, addedAt: originalDate), at: 0)
        let retainedProfile = root.appendingPathComponent("retained-current-relations.json")
        try write(.init(exportedAt: originalDate, preferences: .init(from: manager.settings), sources: [], collections: retainedRelations), to: retainedProfile)
        _ = try await fresh.importPersonalSettings(from: retainedProfile)
        let firstIDs = controller.snapshot.playlists.map(\.id)
        _ = try await fresh.importPersonalSettings(from: retainedProfile)
        checks["RepeatedCurrentRelationImportPreservesUUIDsAndMemberCount"] = controller.snapshot.playlists.map(\.id) == firstIDs
            && controller.snapshot.members.count == 3
        let nfc = source("é", "/opaque/NFC.mp4", "First"), nfd = source("é", "/opaque/NFD.mp4", "Second")
        let emptyCollections = LibraryCollectionsPersonalSettingsImport()
        let opaquePlan = try LibraryPersonalSettings.plan(
            .init(exportedAt: originalDate, preferences: prefs, sources: [nfc, nfd], collections: emptyCollections),
            sources: [], beforePreferences: prefs, targetPreferences: prefs, state: controller.snapshot,
            normalizedPaths: [:], missingPathCount: 2)
        checks["OpaqueNFCAndNFDSourceIDsRemainDistinct"] = opaquePlan.sourcePatches.count == 2
            && opaquePlan.sourcePatches[0].target.reference != opaquePlan.sourcePatches[1].target.reference
            && opaquePlan.sourcePatches.allSatisfy { $0.before == nil }
        do {
            _ = try LibraryPersonalSettings.plan(.init(exportedAt: originalDate, preferences: prefs,
                sources: [nfc, source("é", "/different.mp4", "Conflict")], collections: emptyCollections),
                sources: [], beforePreferences: prefs, targetPreferences: prefs, state: controller.snapshot,
                normalizedPaths: [:], missingPathCount: 0)
            checks["ConflictingSourceDeclarationsRejectBeforeOwnerApplication"] = false
        } catch { checks["ConflictingSourceDeclarationsRejectBeforeOwnerApplication"] = true }

        let alias = WallpaperReferenceAlias(alias: ref("alias", .steamWorkshop), canonical: ref("canonical", .pixabay), proof: .publishedDownload)
        _ = try await controller.perform(.linkAlias(alias, Date()))
        var conflicting = LibraryCollectionsPersonalSettingsImport()
        conflicting.aliases = [.init(alias: alias.canonical, canonical: ref("redirect", .steamWorkshop), proof: .restoredSourceRecord)]
        try write(.init(exportedAt: originalDate, preferences: prefs, sources: [source("A", a.path, "Must not apply")],
                        collections: conflicting), to: profile)
        let beforeInvalidAlias = manager.wallpapers
        do { _ = try await fresh.importPersonalSettings(from: profile); checks["OldBackupCannotRedirectEstablishedAliasBeforeSourceWrites"] = false }
        catch { checks["OldBackupCannotRedirectEstablishedAliasBeforeSourceWrites"] = manager.wallpapers == beforeInvalidAlias
            && !FileManager.default.fileExists(atPath: recoveryURL.path) }

        // Exercise the original bounded save owner with an old request in
        // flight and a second stale pending slot, then a synchronous import.
        let entered = DispatchSemaphore(value: 0), release = DispatchSemaphore(value: 0)
        WallpaperIndexStore.shared.profileHold(entered: entered, release: release)
        precondition(entered.wait(timeout: .now() + 3) == .success)
        manager.saveWallpapers()
        manager.wallpaperIndexSaveRevision &+= 1
        manager.pendingWallpaperIndexSave = .init(wallpapers: [a], revision: manager.wallpaperIndexSaveRevision, epoch: manager.wallpaperIndexSaveEpoch)
        DispatchQueue.global().async { release.signal() }
        let before = manager.personalSettingsSources[0]
        try manager.applyPersonalSettingsSources([.init(before: before, target: source("A", a.path, "After old completions"))])
        try await Task.sleep(nanoseconds: 80_000_000)
        checks["OldAsyncCompletionCannotResubmitStaleSnapshotAfterImport"] = try WallpaperIndexStore.shared.loadWallpapers()[0].title == "After old completions"
            && manager.pendingWallpaperIndexSave == nil && manager.wallpaperIndexSaveInFlight == nil
            && manager.recentWrites == 0 && manager.timerRefreshes == 0

        // Profiles supply source metadata, never a new admission event. A
        // restored unknown remains unknown; explicit metadata can fill it once.
        let unknown = source("restored-unknown", "/offline/restored-unknown.mp4", "Unknown")
        let dated = source("restored-dated", "/offline/restored-dated.mp4", "Dated", firstIndexedAt: Date(timeIntervalSince1970: 80.375))
        let currentPreferences = PersonalSettingsPreferences(from: manager.settings)
        let sourceOnly = root.appendingPathComponent("source-times.json")
        try write(.init(exportedAt: originalDate, preferences: currentPreferences,
            sources: [unknown, dated, source("A", a.path, "After old completions", firstIndexedAt: Date(timeIntervalSince1970: 999))],
            collections: .init()), to: sourceOnly)
        _ = try await fresh.importPersonalSettings(from: sourceOnly)
        checks["RestoredSourcesKeepProvidedOrUnknownAdmissionWithoutUsingNow"] = manager.wallpapers.first { $0.id == unknown.reference.sourceID }?.firstIndexedAt == nil
            && manager.wallpapers.first { $0.id == dated.reference.sourceID }?.firstIndexedAt == dated.firstIndexedAt
            && manager.wallpapers.first { $0.id == "A" }?.firstIndexedAt == a.firstIndexedAt
        let filled = source(unknown.reference.sourceID, unknown.path, unknown.title, firstIndexedAt: Date(timeIntervalSince1970: 70))
        try write(.init(exportedAt: originalDate, preferences: currentPreferences,
            sources: [filled, source(dated.reference.sourceID, dated.path, dated.title)], collections: .init()), to: sourceOnly)
        _ = try await fresh.importPersonalSettings(from: sourceOnly)
        _ = try await fresh.importPersonalSettings(from: sourceOnly)
        let persistedTimes = try WallpaperIndexStore.shared.loadWallpapers()
        checks["ExplicitProfileAdmissionFillsUnknownOnceAndPersistsIdempotently"] = persistedTimes.first { $0.id == filled.reference.sourceID }?.firstIndexedAt == filled.firstIndexedAt
            && persistedTimes.first { $0.id == dated.reference.sourceID }?.firstIndexedAt == dated.firstIndexedAt
            && persistedTimes.count == 3
        let staleBefore = manager.personalSettingsSources.first { $0.reference == filled.reference }!
        let staleTarget = source(filled.reference.sourceID, filled.path, "Stale pending metadata", firstIndexedAt: filled.firstIndexedAt)
        let laterIndex = manager.wallpapers.firstIndex { $0.id == filled.reference.sourceID }!
        manager.initialIndexInternalPublication = true
        manager.wallpapers[laterIndex].firstIndexedAt = Date(timeIntervalSince1970: 71)
        manager.initialIndexInternalPublication = false
        try manager.persistWallpaperIndexNow(manager.wallpapers)
        let laterTimes = try WallpaperIndexStore.shared.loadWallpapers()
        do {
            try manager.applyPersonalSettingsSources([.init(before: staleBefore, target: staleTarget)])
            checks["LaterSourceTimeEditRejectsStaleProfilePatchWithoutOverwrite"] = false
        } catch PersonalSettingsError.sourceChanged {
            checks["LaterSourceTimeEditRejectsStaleProfilePatchWithoutOverwrite"] = try WallpaperIndexStore.shared.loadWallpapers() == laterTimes
                && manager.wallpapers[laterIndex].title == filled.title
        }

        WallpaperManager.defersMissingFileCleanupForPersonalSettingsRecovery = true
        SILService.defersMissingFileCleanupForPersonalSettingsRecovery = true
        let beforeDeferredVideo = try WallpaperIndexStore.shared.loadWallpapers()
        let beforeDeferredImages = try Data(contentsOf: imageURL)
        try Data("broken-recovery".utf8).write(to: recoveryURL)
        let broken = makeCoordinator(recoveryURL)
        do { _ = try await broken.resumeIfNeeded(); checks["CorruptRecoveryNeverBecomesFakeEmptySuccess"] = false }
        catch { checks["CorruptRecoveryNeverBecomesFakeEmptySuccess"] = !broken.allowsEditing
            && (try? Data(contentsOf: recoveryURL)) == Data("broken-recovery".utf8) }
        manager.scheduleMissingIndexedSourceFilesScan(); images.reconcileForAudit()
        try await Task.sleep(nanoseconds: 350_000_000)
        let deferredVideo = try WallpaperIndexStore.shared.loadWallpapers()
        let deferredImages = try Data(contentsOf: imageURL)
        checks["PendingFailedProfileDefersOriginalMissingSourceCleanup"] = manager.wallpapers == beforeDeferredVideo
            && deferredVideo == beforeDeferredVideo && deferredImages == beforeDeferredImages
            && images.wallpapers.count == 1 && manager.missingAlerts == 0 && images.missingAlerts == 0
        try FileManager.default.removeItem(at: recoveryURL)
        _ = try await broken.resumeIfNeeded()
        manager.resumeMissingFileCleanupAfterSettingsRecovery(); images.resumeMissingFileCleanupAfterSettingsRecovery()
        try await Task.sleep(nanoseconds: 450_000_000)
        checks["SuccessfulRecoveryReleasesOriginalCleanupExactlyOnce"] = manager.wallpapers.isEmpty && images.wallpapers.isEmpty
            && manager.missingAlerts == 1 && images.missingAlerts == 1
            && !WallpaperManager.defersMissingFileCleanupForPersonalSettingsRecovery
            && !SILService.defersMissingFileCleanupForPersonalSettingsRecovery
        checks["SourceCleanupDoesNotReimportOrDeleteRelationshipRecords"] = controller.snapshot.playlists.map(\.id) == firstIDs
            && controller.snapshot.members.count == 3

        // Hold the actual relationship database while import awaits its FIFO
        // turn. Reset revokes the same command before it may apply preferences.
        let latePlaylist = WallpaperPlaylist(name: "Must be reset", sidebarRank: 0)
        var lateCollections = LibraryCollectionsPersonalSettingsImport()
        lateCollections.playlists = [latePlaylist]
        var latePreferences = PersonalSettingsPreferences(from: manager.settings); latePreferences.volume = 12
        try write(.init(exportedAt: originalDate, preferences: latePreferences,
            sources: [source("late", "/offline/late.mp4", "Late import")], collections: lateCollections), to: profile)
        let cancellation = makeCoordinator(recoveryURL)
        let oldVolume = manager.settings.volume
        var lock: OpaquePointer?
        precondition(sqlite3_open(storeURL.path, &lock) == SQLITE_OK)
        precondition(sqlite3_exec(lock, "BEGIN IMMEDIATE", nil, nil, nil) == SQLITE_OK)
        let importing = Task { try await cancellation.importPersonalSettings(from: profile) }
        for _ in 0..<100 {
            if let data = try? Data(contentsOf: recoveryURL),
               let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               object["stage"] as? Int == 2 { break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        cancellation.cancelForReset()
        let resetting = Task { try await controller.reset {
            manager.initialIndexInternalPublication = true
            manager.wallpapers = []; manager.initialIndexInternalPublication = false
            images.wallpapers = []
            try? manager.persistWallpaperIndexNow([])
            try? images.persistWallpaperMetadata([])
        } }
        await Task.yield()
        precondition(sqlite3_exec(lock, "COMMIT", nil, nil, nil) == SQLITE_OK)
        sqlite3_close(lock)
        try await resetting.value
        do { _ = try await importing.value; checks["ResetRevokesImportAwaitingRealRelationshipTransaction"] = false }
        catch UserCollectionsError.staleResetEpoch {
            checks["ResetRevokesImportAwaitingRealRelationshipTransaction"] = manager.wallpapers.isEmpty && images.wallpapers.isEmpty
                && controller.snapshot.playlists.isEmpty && manager.settings.volume == oldVolume
        }
        try cancellation.clearRecoveryAfterReset()
        checks["ResetCleanupDoesNotResumeCurrentPartialProfileOrRetainPendingMarker"] = cancellation.allowsEditing
            && !FileManager.default.fileExists(atPath: recoveryURL.path)

        WallpaperManager.defersMissingFileCleanupForPersonalSettingsRecovery = true
        SILService.defersMissingFileCleanupForPersonalSettingsRecovery = true
        try write(.init(exportedAt: originalDate, preferences: latePreferences,
            sources: [source("termination", "/offline/termination.mp4", "Interrupted by exit")], collections: lateCollections), to: profile)
        let termination = makeCoordinator(recoveryURL)
        var exitLock: OpaquePointer?
        precondition(sqlite3_open(storeURL.path, &exitLock) == SQLITE_OK)
        precondition(sqlite3_exec(exitLock, "BEGIN IMMEDIATE", nil, nil, nil) == SQLITE_OK)
        let atExit = Task { try await termination.importPersonalSettings(from: profile) }
        for _ in 0..<100 {
            if let data = try? Data(contentsOf: recoveryURL),
               let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               object["stage"] as? Int == 2 { break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        termination.prepareForTermination()
        precondition(sqlite3_exec(exitLock, "COMMIT", nil, nil, nil) == SQLITE_OK)
        sqlite3_close(exitLock)
        _ = await controller.flush()
        do { _ = try await atExit.value; checks["TerminationRevokesLatePreferencesButKeepsRecoveryBarrier"] = false }
        catch UserCollectionsError.staleResetEpoch {
            checks["TerminationRevokesLatePreferencesButKeepsRecoveryBarrier"] = manager.settings.volume == oldVolume
                && FileManager.default.fileExists(atPath: recoveryURL.path)
                && WallpaperManager.defersMissingFileCleanupForPersonalSettingsRecovery
                && SILService.defersMissingFileCleanupForPersonalSettingsRecovery
        }
        let nextLaunch = makeCoordinator(recoveryURL)
        _ = try await nextLaunch.resumeIfNeeded()
        checks["NextLaunchCanResumeSameEpochImportAfterTermination"] = nextLaunch.allowsEditing
            && manager.settings.volume == 12 && controller.snapshot.playlists.contains { $0.id == latePlaylist.id }
        try await runPlaylistMetadataChecks(root: root, manager: manager, images: images, checks: &checks)
        print(String(data: try JSONEncoder().encode(checks), encoding: .utf8)!)
    }

    @MainActor static func runPlaylistMetadataChecks(root: URL, manager: WallpaperManager, images: SILService,
                                                     checks: inout [String: Bool]) async throws {
        // The earlier source/termination assertions are complete. Start this
        // independent metadata section with an explicitly durable empty source,
        // rather than racing its previously scheduled missing-file cleanup.
        manager.wallpapersAutoSaveWorkItem?.cancel(); manager.missingIndexedSourceScanWorkItem?.cancel()
        manager.initialIndexInternalPublication = true; manager.wallpapers = []; manager.initialIndexInternalPublication = false
        try manager.persistWallpaperIndexNow([])
        images.wallpapers = []; try images.persistWallpaperMetadata([])
        let url = root.appendingPathComponent("cover-profile.sqlite")
        let store = UserCollectionsStore(url: url)
        let initial = try await store.snapshot()
        let controller = UserCollectionsController(store: store, snapshot: initial)
        let recovery = root.appendingPathComponent("cover-recovery.json")
        let importer = PersonalSettingsImportCoordinator(manager: manager, images: images, collections: controller, recoveryURL: recovery,
            readVideoSort: { .init(mode: .name, ascending: true) }, validateVideoSort: { _, _ in }, applyVideoSort: { _, _ in })
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2, bitsPerSample: 8,
            samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 8, bitsPerPixel: 32)!
        for x in 0..<2 { for y in 0..<2 {
            bitmap.setColor(NSColor(srgbRed: 0.3, green: 0.5, blue: 0.7, alpha: 1), atX: x, y: y)
        } }
        let asset = WallpaperPlaylistCoverAsset(imageData: bitmap.representation(using: .png, properties: [:])!, pixelWidth: 2, pixelHeight: 2)
        let fractionalDate = Date(timeIntervalSince1970: 1234.375)
        let id = try await controller.createPlaylist(metadata: .init(name: "Portable cover", descriptionText: "A description", customCoverAssetID: asset.id),
            coverAsset: asset, at: fractionalDate)
        let hidden = ref("hidden", .videoLibrary)
        let member = WallpaperOrganizationItem(reference: hidden, locator: .init(), isPublishedLocally: true, isAvailable: true)
        _ = try await controller.perform([.addMembers(id, [member], fractionalDate), .setFavorite(member, true, fractionalDate), .setLibraryExcluded([hidden], true)])
        let profile = root.appendingPathComponent("cover-profile.json")
        _ = try await importer.exportPersonalSettings(to: profile)
        let portableBytes = try Data(contentsOf: profile)
        let portable = try LibraryPersonalSettings.decode(portableBytes)
        checks["SchemaEightExportsOnlyReferencedControlledCoverCopiesAndExplicitHideStates"] = portable.schemaVersion == 8
            && portable.collections.coverAssets == [asset] && portable.collections.playlists.first?.descriptionText == "A description"
            && portable.collections.libraryExclusionStates.contains { $0.reference == hidden && $0.isExcluded } == true
            && portable.collections.expectedLibraryExclusions == nil
        let downloads = [WallpaperProvider.steamWorkshop, .pixabay, .wallhaven, .pixiv].map { ref($0 == .pixiv ? "123:p0" : "old-download-hide", $0) }
        _ = try await controller.perform(.setLibraryExcluded(downloads, true))
        let exported = try LibraryPersonalSettings.export(sources: [], preferences: portable.preferences, state: controller.snapshot, coverAssets: [asset])
        checks["DownloadProviderHidesAreNotExportedButLocalSourceHideRemainsPortable"] = exported.collections.libraryExclusionStates.contains { downloads.contains($0.reference) } == false
            && exported.collections.libraryExclusionStates.contains { $0.reference == hidden && $0.isExcluded } == true
        var collectionsWithDownloadHides = portable.collections
        collectionsWithDownloadHides.libraryExclusionStates = downloads.map { .init(reference: $0, isExcluded: true) }
            + [.init(reference: hidden, isExcluded: true)]
        for provider in [WallpaperProvider.steamWorkshop, .pixabay, .wallhaven, .pixiv] {
            let backing = ref("aliased-download-hide", provider == .pixiv ? .staticImageLibrary : .videoLibrary)
            var aliased = collectionsWithDownloadHides
            aliased.aliases = [.init(alias: backing, canonical: downloads.first { $0.provider == provider }!, proof: .restoredSourceRecord)]
            aliased.libraryExclusionStates.append(.init(reference: backing, isExcluded: true))
            let object = try JSONSerialization.jsonObject(with: LibraryPersonalSettings.encode(.init(exportedAt: Date(), preferences: portable.preferences, sources: [], collections: aliased))) as! [String: Any]
            let input = try LibraryPersonalSettings.decode(JSONSerialization.data(withJSONObject: object))
            let mapped = try LibraryPersonalSettings.plan(input, sources: [], beforePreferences: portable.preferences,
                targetPreferences: portable.preferences, state: controller.snapshot, normalizedPaths: [:], missingPathCount: 0)
            checks["SchemaEightRejectsAliased\(provider.rawValue)DownloadHideButKeepsLocalSource"] = mapped.collections.libraryExclusionStates.map(\.reference) == [hidden]
        }
        _ = try await controller.perform(.setLibraryExcluded(downloads, false))
        func transparentPNG(width: Int, height: Int) -> Data {
            let copy = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8,
                samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                bytesPerRow: width * 4, bitsPerPixel: 32)!
            copy.bitmapData!.initialize(repeating: 0, count: copy.bytesPerRow * height)
            copy.setColor(NSColor(srgbRed: 0.2, green: 0.4, blue: 0.6, alpha: 0.5), atX: width - 1, y: height - 1)
            return copy.representation(using: .png, properties: [:])!
        }
        for (label, width, height) in [("Boundary512x256", 512, 256), ("TransparentTinyPNG", 2, 2)] {
            let copy = WallpaperPlaylistCoverAsset(imageData: transparentPNG(width: width, height: height), pixelWidth: width, pixelHeight: height)
            var incoming = portable.collections
            incoming.playlists[0].customCoverAssetID = copy.id; incoming.coverAssets = [copy]
            try write(.init(exportedAt: Date(), preferences: .init(from: manager.settings), sources: [], collections: incoming), to: profile)
            _ = try await importer.importPersonalSettings(from: profile)
            let persisted = try await controller.playlistCoverAsset(id: copy.id, expectedEpoch: controller.snapshot.resetEpoch)
            let pixels = persisted.flatMap { NSBitmapImageRep(data: $0.imageData) }
            checks["SchemaEightImports" + label + "ThroughRealCoverValidation"] = persisted == copy
                && controller.snapshot.playlists.first { $0.id == id }?.customCoverAssetID == copy.id
                && pixels?.pixelsWide == width && pixels?.pixelsHigh == height && pixels?.colorAt(x: 0, y: 0)?.alphaComponent == 0
        }
        // Fractional dates must survive the actual recovery snapshot exactly.
        _ = try await controller.editPlaylistMetadata(id: id, expected: controller.snapshot.playlists[0].metadata,
            replacement: .init(name: "Portable cover", descriptionText: "A description", customCoverAssetID: asset.id),
            at: fractionalDate, expectedEpoch: controller.snapshot.resetEpoch)
        let automatic = WallpaperPlaylist(id: id, name: "Automatic", createdAt: Date(timeIntervalSince1970: 10), sidebarRank: 0)
        let clearPayload = PersonalSettingsPayload(exportedAt: Date(timeIntervalSince1970: 20), preferences: .init(from: manager.settings),
            sources: [], collections: .init(playlists: [automatic], libraryExclusionStates: [.init(reference: hidden, isExcluded: false)]))
        try write(clearPayload, to: profile)
        _ = try await importer.importPersonalSettings(from: profile)
        checks["SchemaEightExplicitAutomaticAndFalseHideAreAppliedByOriginalImportChain"] = controller.snapshot.playlists.first { $0.id == id }?.customCoverAssetID == nil
            && controller.snapshot.playlists.first { $0.id == id }?.descriptionText == nil && controller.snapshot.excludedLibraryReferences.isEmpty
        _ = try await controller.editPlaylistMetadata(id: id, expected: controller.snapshot.playlists[0].metadata,
            replacement: .init(name: "Automatic fractional"), at: fractionalDate, expectedEpoch: controller.snapshot.resetEpoch)
        let beforeBad = controller.snapshot
        let exactEncoder = JSONEncoder(); exactEncoder.dateEncodingStrategy = .iso8601
        let exactDecoder = JSONDecoder(); exactDecoder.dateDecodingStrategy = .iso8601
        checks["ExpectedOrganizationRecoveryCodecPreservesActualFractionalPlaylistMemberAndFavoriteDates"] =
            try exactDecoder.decode(LibraryCollectionsOrganizationState.self, from: exactEncoder.encode(beforeBad.organizationState)) == beforeBad.organizationState
                && beforeBad.playlists[0].modifiedAt == fractionalDate && beforeBad.members[0].addedAt == fractionalDate
                && beforeBad.favorites[0].favoritedAt == fractionalDate
        var badCollections = portable.collections
        badCollections.coverAssets = [.init(id: asset.id, imageData: Data("not-an-image".utf8), pixelWidth: 2, pixelHeight: 2)]
        try write(.init(exportedAt: Date(), preferences: .init(from: manager.settings), sources: [], collections: badCollections), to: profile)
        do {
            _ = try await importer.importPersonalSettings(from: profile)
            checks["UndecodableCoverCopyIsRejectedBeforeRecoveryOrRelationshipWrites"] = false
        } catch PersonalSettingsError.invalidPayload(_) {
            checks["UndecodableCoverCopyIsRejectedBeforeRecoveryOrRelationshipWrites"] = controller.snapshot == beforeBad
                && !FileManager.default.fileExists(atPath: recovery.path)
        }
        for (label, invalid) in [
            ("OversizedDeclaration", WallpaperPlaylistCoverAsset(id: asset.id, imageData: asset.imageData, pixelWidth: 8192, pixelHeight: 8192)),
            ("OversizedActualPixels", WallpaperPlaylistCoverAsset(id: asset.id, imageData: transparentPNG(width: 513, height: 2), pixelWidth: 2, pixelHeight: 2)),
            ("OversizedEncodedBytes", WallpaperPlaylistCoverAsset(id: asset.id,
                imageData: Data(repeating: 0, count: WallpaperPlaylistCoverAsset.maxEncodedBytes + 1), pixelWidth: 2, pixelHeight: 2))
        ] {
            badCollections.coverAssets = [invalid]
            try write(.init(exportedAt: Date(), preferences: .init(from: manager.settings), sources: [], collections: badCollections), to: profile)
            do {
                _ = try await importer.importPersonalSettings(from: profile)
                checks["SchemaEightRejects" + label + "BeforeRecoveryOrRelationshipWrites"] = false
            } catch PersonalSettingsError.invalidPayload(_) {
                checks["SchemaEightRejects" + label + "BeforeRecoveryOrRelationshipWrites"] = controller.snapshot == beforeBad
                    && !FileManager.default.fileExists(atPath: recovery.path) && importer.allowsEditing
            }
        }
        try portableBytes.write(to: profile)
        try sql(url, "CREATE TRIGGER cover_profile_fail BEFORE INSERT ON playlists BEGIN SELECT RAISE(ABORT,'controlled cover profile failure'); END")
        do {
            _ = try await importer.importPersonalSettings(from: profile)
            checks["CoverProfileFailureRetainsOriginalMetadataAndDurableRecovery"] = false
        } catch {
            checks["CoverProfileFailureRetainsOriginalMetadataAndDurableRecovery"] = controller.snapshot == beforeBad
                && FileManager.default.fileExists(atPath: recovery.path) && !importer.allowsEditing
        }
        try sql(url, "DROP TRIGGER cover_profile_fail")
        let resumed = PersonalSettingsImportCoordinator(manager: manager, images: images, collections: controller, recoveryURL: recovery,
            readVideoSort: { .init(mode: .name, ascending: true) }, validateVideoSort: { _, _ in }, applyVideoSort: { _, _ in })
        _ = try await resumed.resumeIfNeeded()
        let restoredAsset = try await controller.playlistCoverAsset(id: asset.id, expectedEpoch: controller.snapshot.resetEpoch)
        checks["RestartedOriginalRecoveryReplaysCoverBytesDescriptionAndHiddenStateExactlyOnce"] = resumed.allowsEditing
            && restoredAsset == asset && controller.snapshot.playlists.first { $0.id == id }?.descriptionText == "A description"
            && controller.snapshot.excludedLibraryReferences.contains { $0.reference == hidden }
        let reopened = UserCollectionsStore(url: url, allowCreate: false)
        let disk = try await reopened.snapshot()
        checks["PortableMetadataProfileReopensWithSameIdsAndNoMediaSourceSubstitution"] = disk == controller.snapshot
            && disk.playlists.count == 1 && disk.playlists[0].id == id
    }
}
