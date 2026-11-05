import Combine
import Foundation

extension PersonalSettingsImportHarness {
    @MainActor static func runVideoSortProfileChecks(root: URL, manager: WallpaperManager, images: SILService,
        controller: UserCollectionsController, presentation: WallpaperLibraryPresentation) async throws {
        var checks: [String: Bool] = [:]
        let recovery = root.appendingPathComponent("sort-recovery.json")
        let profile = root.appendingPathComponent("sort-profile.json")
        let exportedURL = root.appendingPathComponent("sort-export.json")
        var failViewSave = false, rejectBeforeViewSave = false
        func coordinator(_ view: WallpaperLibraryPresentation, recoveryURL: URL? = nil) -> PersonalSettingsImportCoordinator {
            PersonalSettingsImportCoordinator(manager: manager, images: images, collections: controller,
                recoveryURL: recoveryURL ?? recovery, readVideoSort: { try view.videoSortPreference() },
                validateVideoSort: { try view.validateVideoSortPatch($0, resetEpoch: $1) },
                applyVideoSort: { patch, epoch in
                    if rejectBeforeViewSave { throw WallpaperLibraryVideoSortError.persistenceFailed }
                    manager.defaults.failSynchronization = failViewSave
                    defer { manager.defaults.failSynchronization = false }
                    try view.applyVideoSortPatch(patch, resetEpoch: epoch)
                })
        }
        func catalog() -> WallpaperLibraryCatalog {
            .init(videos: manager.wallpapers.map { value in
                let reference = ref(value.id)
                return WallpaperContentItem(reference: reference, providerReference: reference,
                    locator: .init(path: value.path), title: value.title, kind: .video,
                    publishedAvailability: .unavailable, capabilities: [.inspect],
                    metadata: .init(fileSizeBytes: value.fileSize, createdAt: value.firstIndexedAt),
                    acquisition: .idle, update: .idle, aliases: [])
            })
        }
        func refresh(_ view: WallpaperLibraryPresentation = presentation) {
            _ = view.update(catalog: catalog(), relationships: controller.snapshot)
        }
        func writeCurrentSort(_ preference: WallpaperLibraryVideoSortPreference, sources: [PersonalSettingsLocalSource] = []) throws {
            var prefs = PersonalSettingsPreferences(from: manager.settings)
            prefs.videoLibrarySort = preference
            try write(.init(exportedAt: Date(timeIntervalSince1970: 100), preferences: prefs,
                sources: sources, collections: .init()), to: profile)
        }
        let original = manager.wallpapers[0]
        let b = VideoWallpaper(id: "B", title: "Beta", path: root.appendingPathComponent("B.mp4").path,
            lastUsed: Date(timeIntervalSince1970: 10), fileSize: 20, firstIndexedAt: Date(timeIntervalSince1970: 90))
        let c = VideoWallpaper(id: "C", title: "Charlie", path: root.appendingPathComponent("C.mp4").path,
            lastUsed: Date(timeIntervalSince1970: 50), fileSize: 10, firstIndexedAt: Date(timeIntervalSince1970: 20))
        manager.initialIndexInternalPublication = true
        manager.wallpapers = [original, b, c]
        manager.initialIndexInternalPublication = false
        try WallpaperIndexStore.shared.saveWallpapers(manager.wallpapers)
        refresh()
        let videoQuery = WallpaperLibraryQueryState(search: "Original", providers: [.videoLibrary, .steamWorkshop], kinds: [.video, .scene],
            statuses: [.playable, .unavailable], sort: .fileSize, ascending: false, preferredColumns: 3, scrollAnchor: ref("A"), scrollOffset: -12.5, scrollAtTop: false)
        presentation.setQueryState(videoQuery)
        presentation.switchPage(.images)
        presentation.setQueryState(.init(search: "private image filter", preferredColumns: 6, scrollAnchor: ref("image-view"), scrollOffset: 18, scrollAtTop: true))
        let imageQuery = presentation.queryState
        let initialHistory = controller.snapshot.recent
        var importer = coordinator(presentation)
        var partial = try JSONDecoder().decode(PersonalSettingsPreferences.self, from: Data("{\"volume\":17}".utf8))
        partial.videoLibrarySort = nil
        try write(.init(exportedAt: Date(), preferences: partial, sources: [], collections: .init()), to: profile)
        _ = try await importer.importPersonalSettings(from: profile)
        checks["CurrentPartialImportWithoutSortPreservesTheLiveViewAndOtherPage"] = try presentation.videoSortPreference()
            == .init(mode: .fileSize, ascending: false) && presentation.page == .images && presentation.queryState == imageQuery
        _ = try await importer.exportPersonalSettings(to: exportedURL)
        let exported = try LibraryPersonalSettings.decode(Data(contentsOf: exportedURL))
        let json = try JSONSerialization.jsonObject(with: Data(contentsOf: exportedURL)) as! [String: Any]
        let prefsJSON = json["preferences"] as! [String: Any]
        let sortJSON = prefsJSON["videoLibrarySort"] as! [String: Any]
        checks["ExportReadsVideoSessionRatherThanStaleManagerGlobalOrActiveImagePage"] = exported.preferences.videoLibrarySort
            == .init(mode: .fileSize, ascending: false) && prefsJSON["sortMode"] == nil && prefsJSON["sortAscending"] == nil
        checks["SchemaEightRetainsOnlyVideoSortAndNeverExportsViewNavigationFiltersOrPlayback"] = exported.schemaVersion == 8
            && Set(sortJSON.keys) == ["mode", "ascending"] && json["page"] == nil && json["history"] == nil
            && json["playbackSource"] == nil && prefsJSON["search"] == nil && prefsJSON["zoomOffset"] == nil
            && prefsJSON["preferredColumns"] == nil && prefsJSON["scrollAnchor"] == nil && prefsJSON["scrollOffset"] == nil
            && prefsJSON["scrollAtTop"] == nil && prefsJSON["page"] == nil
            && prefsJSON["providers"] == nil && prefsJSON["kinds"] == nil && prefsJSON["statuses"] == nil

        for mode in [WallpaperLibraryVideoSortPreference.Mode.sourceOrder, .name, .fileSize, .createdAt, .lastUsed] {
            let preference = WallpaperLibraryVideoSortPreference(mode: mode, ascending: false)
            try writeCurrentSort(preference)
            _ = try await importer.importPersonalSettings(from: profile)
            _ = try await importer.exportPersonalSettings(to: exportedURL)
            let roundTrip = try LibraryPersonalSettings.decode(Data(contentsOf: exportedURL)).preferences.videoLibrarySort
            checks["Mode\(mode.rawValue)ImportsAndExportsFromTheSameViewOwner"] = try roundTrip == preference
                && presentation.videoSortPreference() == preference && presentation.page == .images && presentation.queryState == imageQuery
        }
        presentation.switchPage(.videos)
        checks["SortPatchPreservesVideoSearchProviderKindDensityAndScroll"] = presentation.queryState.search == videoQuery.search
            && presentation.queryState.providers == videoQuery.providers && presentation.queryState.kinds == videoQuery.kinds
            && presentation.queryState.statuses == videoQuery.statuses
            && presentation.queryState.preferredColumns == videoQuery.preferredColumns && presentation.queryState.scrollAnchor == videoQuery.scrollAnchor
            && presentation.queryState.scrollOffset == videoQuery.scrollOffset && presentation.queryState.scrollAtTop == videoQuery.scrollAtTop
        checks["CurrentSortNeverWritesHistoryOrSourceDates"] = controller.snapshot.recent == initialHistory
            && manager.wallpapers.first { $0.id == "A" }?.lastUsed == original.lastUsed
            && manager.wallpapers.first { $0.id == "A" }?.firstIndexedAt == original.firstIndexedAt
            && manager.wallpapers.first { $0.id == "B" }?.lastUsed == b.lastUsed
            && manager.recentWrites == 0 && manager.timerRefreshes == 0

        // Fail the actual view-defaults durability acknowledgement after base
        // preferences committed, then rebuild the view and coordinator.
        presentation.setQueryState(.init(sort: .name, ascending: false))
        try writeCurrentSort(.init(mode: .fileSize, ascending: true))
        failViewSave = true
        do { _ = try await importer.importPersonalSettings(from: profile); checks["ViewDurabilityFailureCannotReportComplete"] = false }
        catch WallpaperLibraryVideoSortError.persistenceFailed { checks["ViewDurabilityFailureCannotReportComplete"] = !importer.allowsEditing }
        failViewSave = false
        let record = try JSONSerialization.jsonObject(with: Data(contentsOf: recovery)) as! [String: Any]
        let savedPatch = record["videoSortPatch"] as! [String: Any]
        checks["RecoveryPersistsExactBeforeTargetAndPreferencesBoundary"] = record["schemaVersion"] as? Int == 3
            && record["stage"] as? Int == 4 && (savedPatch["before"] as? [String: Any])?["mode"] as? String == "name"
            && (savedPatch["target"] as? [String: Any])?["mode"] as? String == "fileSize"
        let restartedView = WallpaperLibraryPresentation(collections: controller, defaults: manager.defaults)
        refresh(restartedView)
        let restarted = coordinator(restartedView)
        var publications = 0
        let observation = restartedView.$state.dropFirst().sink { _ in publications += 1 }
        _ = try await restarted.resumeIfNeeded()
        checks["RestartAcceptsAlreadyDurableTargetWithoutReplayingViewChange"] = try restarted.allowsEditing && publications == 0
            && restartedView.videoSortPreference() == .init(mode: .fileSize, ascending: true)
            && !FileManager.default.fileExists(atPath: recovery.path)
        observation.cancel()
        presentation.setQueryState(.init(sort: .name, ascending: false))
        importer = coordinator(presentation)
        try writeCurrentSort(.init(mode: .fileSize, ascending: true))
        rejectBeforeViewSave = true
        do { _ = try await importer.importPersonalSettings(from: profile) } catch {}
        rejectBeforeViewSave = false
        let beforeRestartView = WallpaperLibraryPresentation(collections: controller, defaults: manager.defaults)
        refresh(beforeRestartView)
        let beforeRestart = coordinator(beforeRestartView)
        let actualBefore = try beforeRestartView.videoSortPreference()
        _ = try await beforeRestart.resumeIfNeeded()
        checks["RestartFromBeforeAppliesExactSavedTargetInTheSameEpoch"] = try actualBefore == .init(mode: .name, ascending: false)
            && beforeRestartView.videoSortPreference() == .init(mode: .fileSize, ascending: true)
            && beforeRestart.allowsEditing && !FileManager.default.fileExists(atPath: recovery.path)
        importer = coordinator(presentation)
        try writeCurrentSort(.init(mode: .createdAt, ascending: true))
        failViewSave = true
        do { _ = try await importer.importPersonalSettings(from: profile) } catch {}
        failViewSave = false
        let recoveryBytes = try Data(contentsOf: recovery)
        presentation.setQueryState(.init(sort: .lastUsed, ascending: false))
        do { _ = try await importer.resumeIfNeeded(); checks["LaterVideoSortChoiceRejectsOldImportWithoutOverwrite"] = false }
        catch WallpaperLibraryVideoSortError.changed {
            checks["LaterVideoSortChoiceRejectsOldImportWithoutOverwrite"] = try presentation.videoSortPreference()
                == .init(mode: .lastUsed, ascending: false) && Data(contentsOf: recovery) == recoveryBytes
        }
        let oldEpoch = controller.snapshot.resetEpoch
        let oldPatch = WallpaperLibraryVideoSortPatch(before: try presentation.videoSortPreference(), target: .init(mode: .sourceOrder, ascending: true))
        importer.cancelForReset(); try await controller.reset(); try importer.clearRecoveryAfterReset()
        do { try presentation.applyVideoSortPatch(oldPatch, resetEpoch: oldEpoch); checks["ResetRevokesOldSortPatchWithoutApplyingIt"] = false }
        catch UserCollectionsError.staleResetEpoch { checks["ResetRevokesOldSortPatchWithoutApplyingIt"] = try presentation.videoSortPreference() == oldPatch.before }
        refresh()

        importer = coordinator(presentation)
        try writeCurrentSort(.init(mode: .name, ascending: true))
        failViewSave = true
        do { _ = try await importer.importPersonalSettings(from: profile) } catch {}
        failViewSave = false
        let currentRecord = try JSONSerialization.jsonObject(with: Data(contentsOf: recovery)) as! [String: Any]
        presentation.setQueryState(.init(sort: .lastUsed, ascending: false))
        let retainedSources = manager.wallpapers, retainedSettings = manager.settings, retainedRelations = controller.snapshot
        for version in [1, 2] {
            var oldRecord = currentRecord; oldRecord["schemaVersion"] = version
            if version == 1 { oldRecord.removeValue(forKey: "videoSortPatch") }
            let oldBytes = try JSONSerialization.data(withJSONObject: oldRecord)
            try oldBytes.write(to: recovery)
            let rejectedOwner = coordinator(presentation)
            do { _ = try await rejectedOwner.resumeIfNeeded(); checks["Recovery\(version)RejectsWithoutChangingBytesSourcesOrView"] = false }
            catch PersonalSettingsError.invalidPayload {
                checks["Recovery\(version)RejectsWithoutChangingBytesSourcesOrView"] = try !rejectedOwner.allowsEditing
                    && presentation.videoSortPreference() == .init(mode: .lastUsed, ascending: false) && Data(contentsOf: recovery) == oldBytes
                    && manager.wallpapers == retainedSources && manager.settings == retainedSettings && controller.snapshot == retainedRelations
            }
        }
        try FileManager.default.removeItem(at: recovery)

        let badSuite = "MWX.Profile.BadView." + UUID().uuidString
        let badDefaults = UserDefaults(suiteName: badSuite)!
        defer { badDefaults.removePersistentDomain(forName: badSuite) }
        let unknown = Data("{\"version\":99,\"opaque\":\"keep\"}".utf8)
        badDefaults.set(unknown, forKey: WallpaperLibraryPresentation.settingsKey)
        let badView = WallpaperLibraryPresentation(collections: controller, defaults: badDefaults)
        let blockedRecovery = root.appendingPathComponent("blocked-sort.json")
        let blocked = coordinator(badView, recoveryURL: blockedRecovery)
        try writeCurrentSort(.init(mode: .name, ascending: true), sources: [source("A", original.path, "Must not apply")])
        let sourceBefore = manager.wallpapers
        do { _ = try await blocked.importPersonalSettings(from: profile); checks["UnknownViewPreferencesRejectSortBeforeAnySourceOrRelationshipEdit"] = false }
        catch WallpaperLibraryVideoSortError.readOnly {
            checks["UnknownViewPreferencesRejectSortBeforeAnySourceOrRelationshipEdit"] = manager.wallpapers == sourceBefore
                && badDefaults.data(forKey: WallpaperLibraryPresentation.settingsKey) == unknown
                && !FileManager.default.fileExists(atPath: blockedRecovery.path)
        }
        var malformed = try JSONSerialization.jsonObject(with: Data(contentsOf: profile)) as! [String: Any]
        var malformedPrefs = malformed["preferences"] as! [String: Any]
        malformedPrefs["videoLibrarySort"] = ["mode": "future", "ascending": true]
        malformed["preferences"] = malformedPrefs
        let malformedBytes = try JSONSerialization.data(withJSONObject: malformed)
        try malformedBytes.write(to: profile)
        do { _ = try await coordinator(presentation).importPersonalSettings(from: profile); checks["UnknownNewSortRejectsBeforeMutationAndPreservesBackup"] = false }
        catch {
            checks["UnknownNewSortRejectsBeforeMutationAndPreservesBackup"] = try manager.wallpapers == sourceBefore
                && Data(contentsOf: profile) == malformedBytes && !FileManager.default.fileExists(atPath: recovery.path)
        }
        malformedPrefs["videoLibrarySort"] = ["mode": "legacyTime", "ascending": true]
        malformed["preferences"] = malformedPrefs
        let retiredModeBytes = try JSONSerialization.data(withJSONObject: malformed)
        try retiredModeBytes.write(to: profile)
        do { _ = try await coordinator(presentation).importPersonalSettings(from: profile); checks["RetiredSortModeRejectsBeforeSourceMutation"] = false }
        catch { checks["RetiredSortModeRejectsBeforeSourceMutation"] = try manager.wallpapers == sourceBefore
            && Data(contentsOf: profile) == retiredModeBytes && !FileManager.default.fileExists(atPath: recovery.path) }
        let futureRecovery = root.appendingPathComponent("future-sort-recovery.json")
        var future = currentRecord; future["schemaVersion"] = 99
        let futureBytes = try JSONSerialization.data(withJSONObject: future)
        try futureBytes.write(to: futureRecovery)
        let futureImporter = coordinator(presentation, recoveryURL: futureRecovery)
        let currentSort = try presentation.videoSortPreference()
        do { _ = try await futureImporter.resumeIfNeeded(); checks["FutureRecoveryStaysIntactWithoutGuessingViewOrSourceState"] = false }
        catch {
            checks["FutureRecoveryStaysIntactWithoutGuessingViewOrSourceState"] = try Data(contentsOf: futureRecovery) == futureBytes
                && presentation.videoSortPreference() == currentSort && manager.wallpapers == sourceBefore && !futureImporter.allowsEditing
        }
        do {
            let hotkeyRecovery = root.appendingPathComponent("current-hotkey-sort-recovery.json")
            var beforeHotkeys = manager.settings
            beforeHotkeys.volume = 71; beforeHotkeys.systemHotkeysEnabled = true
            beforeHotkeys.previousWallpaperHotkey = .f1; beforeHotkeys.nextWallpaperHotkey = .f3
            beforeHotkeys.togglePlaybackHotkey = .f5; beforeHotkeys.toggleMuteHotkey = .f7
            manager.settings = beforeHotkeys
            presentation.setQueryState(.init(sort: .name, ascending: false))
            var canonicalRestart = beforeHotkeys
            canonicalRestart.volume = 23
            canonicalRestart.previousWallpaperHotkey = .f2; canonicalRestart.nextWallpaperHotkey = .none
            canonicalRestart.togglePlaybackHotkey = .none; canonicalRestart.toggleMuteHotkey = .none
            var importedPreferences = PersonalSettingsPreferences(from: canonicalRestart)
            importedPreferences.previousWallpaperHotkey = "f2"; importedPreferences.nextWallpaperHotkey = "f2"
            importedPreferences.togglePlaybackHotkey = "f2"; importedPreferences.toggleMuteHotkey = "f2"
            importedPreferences.videoLibrarySort = .init(mode: .fileSize, ascending: true)
            try write(.init(exportedAt: Date(timeIntervalSince1970: 100), preferences: importedPreferences,
                sources: [], collections: .init()), to: profile)
            let historyBeforeHotkeys = controller.snapshot.recent, sourcesBeforeHotkeys = manager.wallpapers
            let recentWritesBeforeHotkeys = manager.recentWrites, timerBeforeHotkeys = manager.timerRefreshes
            let oldWriter = coordinator(presentation, recoveryURL: hotkeyRecovery)
            rejectBeforeViewSave = true
            var stoppedBeforeViewSave = false
            do { _ = try await oldWriter.importPersonalSettings(from: profile) }
            catch WallpaperLibraryVideoSortError.persistenceFailed { stoppedBeforeViewSave = true }
            rejectBeforeViewSave = false
            var hotkeyRecord = try JSONSerialization.jsonObject(with: Data(contentsOf: hotkeyRecovery)) as! [String: Any]
            var hotkeyPlan = hotkeyRecord["plan"] as! [String: Any]
            var journalTarget = hotkeyPlan["targetPreferences"] as! [String: Any]
            let bindingFields = ["previousWallpaperHotkey", "nextWallpaperHotkey", "togglePlaybackHotkey", "toggleMuteHotkey"]
            let durableHotkeys = try JSONDecoder().decode(WallpaperSettings.self,
                from: manager.defaults.data(forKey: manager.settingsKey)!)
            checks["DuplicateImportHotkeysAreCanonicalBeforeViewSaveInPlanDefaultsAndManager"] = stoppedBeforeViewSave
                && hotkeyRecord["stage"] as? Int == 4
                && journalTarget["previousWallpaperHotkey"] as? String == "f2"
                && journalTarget["nextWallpaperHotkey"] as? String == "none"
                && journalTarget["togglePlaybackHotkey"] as? String == "none"
                && journalTarget["toggleMuteHotkey"] as? String == "none"
                && durableHotkeys == canonicalRestart && manager.settings == canonicalRestart
            // A recovery record must already contain the normalized snapshot
            // captured by the current import, not a second import request.
            for field in bindingFields { journalTarget[field] = "f2" }
            hotkeyPlan["targetPreferences"] = journalTarget; hotkeyRecord["plan"] = hotkeyPlan
            let tamperedJournal = try JSONSerialization.data(withJSONObject: hotkeyRecord)
            try tamperedJournal.write(to: hotkeyRecovery, options: .atomic)
            manager.settings = canonicalRestart
            checks["TamperedHotkeyJournalStopsAtStageFourWithOnlyTargetBindingsChanged"] = stoppedBeforeViewSave
                && hotkeyRecord["stage"] as? Int == 4 && journalTarget["volume"] as? Double == 23
                && (hotkeyPlan["beforePreferences"] as? [String: Any])?["volume"] as? Double == 71
                && bindingFields.allSatisfy { journalTarget[$0] as? String == "f2" }
                && manager.settings == canonicalRestart
            let hotkeyView = WallpaperLibraryPresentation(collections: controller, defaults: manager.defaults)
            refresh(hotkeyView)
            let recoveredHotkeys = coordinator(hotkeyView, recoveryURL: hotkeyRecovery)
            var resumedHotkeys = false
            do { _ = try await recoveredHotkeys.resumeIfNeeded(); resumedHotkeys = true } catch {}
            checks["RecoveryRejectsRetamperedDuplicateHotkeysWithoutNormalizingTheJournal"] = try !resumedHotkeys
                && !recoveredHotkeys.allowsEditing && FileManager.default.fileExists(atPath: hotkeyRecovery.path)
                && Data(contentsOf: hotkeyRecovery) == tamperedJournal
                && manager.settings == canonicalRestart && hotkeyView.videoSortPreference() == .init(mode: .name, ascending: false)
            checks["RejectedHotkeyRecoveryPreservesSourcesOtherSettingsAndHistory"] = manager.settings == canonicalRestart
                && manager.wallpapers == sourcesBeforeHotkeys && controller.snapshot.recent == historyBeforeHotkeys
                && manager.recentWrites == recentWritesBeforeHotkeys && manager.timerRefreshes == timerBeforeHotkeys

            var duplicatePreferences = PersonalSettingsPreferences(from: canonicalRestart)
            duplicatePreferences.nextWallpaperHotkey = "f2"; duplicatePreferences.togglePlaybackHotkey = "f2"
            duplicatePreferences.toggleMuteHotkey = "f2"
            var nextPreferences = PersonalSettingsPreferences(from: canonicalRestart); nextPreferences.volume = 24
            manager.settings = canonicalRestart
            var acceptedExpected = false
            do {
                try manager.applyPersonalSettingsPreferences(expected: duplicatePreferences, target: nextPreferences)
                acceptedExpected = true
            } catch {}
            checks["ProfileSettingsRejectsANormalizedButUnequalExpectedSnapshot"] = !acceptedExpected
                && manager.settings == canonicalRestart
            manager.settings = canonicalRestart
            var acceptedTarget = false
            do {
                try manager.applyPersonalSettingsPreferences(expected: .init(from: beforeHotkeys), target: duplicatePreferences)
                acceptedTarget = true
            } catch {}
            checks["ProfileSettingsRejectsANormalizedButUnequalTargetSnapshot"] = !acceptedTarget && manager.settings == canonicalRestart

            var partialPreferences = duplicatePreferences
            partialPreferences.previousWallpaperHotkey = nil; partialPreferences.toggleMuteHotkey = nil
            var changedMissingBindings = canonicalRestart
            changedMissingBindings.previousWallpaperHotkey = .f4; changedMissingBindings.nextWallpaperHotkey = .f2
            changedMissingBindings.toggleMuteHotkey = .f8
            checks["RecoveryRejectsPartialHotkeySnapshotsInsteadOfBorrowingMissingBindings"] = partialPreferences != .init(from: canonicalRestart)
                && partialPreferences != .init(from: changedMissingBindings)
            var distinctBinding = duplicatePreferences; distinctBinding.previousWallpaperHotkey = "f4"
            var unknownBinding = duplicatePreferences; unknownBinding.nextWallpaperHotkey = "future-key"
            var conflictingVolume = duplicatePreferences; conflictingVolume.volume = 22
            for (name, conflicting) in [("ExplicitOtherHotkey", distinctBinding), ("UnknownHotkeyRaw", unknownBinding), ("OtherVolume", conflictingVolume)] {
                manager.settings = canonicalRestart
                let settingsDataBefore = manager.defaults.data(forKey: manager.settingsKey)
                var rejected = false
                do { try manager.applyPersonalSettingsPreferences(expected: conflicting, target: conflicting) }
                catch PersonalSettingsError.preferencesChanged { rejected = true }
                checks["ProfileSettingsRejects\(name)WithoutChangingOrPersistingSettings"] = rejected
                    && manager.settings == canonicalRestart && manager.defaults.data(forKey: manager.settingsKey) == settingsDataBefore
            }
        }
        print(String(data: try JSONEncoder().encode(checks), encoding: .utf8)!)
    }
}
