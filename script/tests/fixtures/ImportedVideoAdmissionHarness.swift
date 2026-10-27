@main enum ImportedVideoAdmissionChecks {
    @MainActor static func main() async throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true).resolvingSymlinksInPath().standardizedFileURL
        OnlineLibraryService.downloadDirectory = root
        let firstURL = root.appendingPathComponent("online_1.mp4")
        let secondURL = root.appendingPathComponent("online_2.mp4")
        let oldURL = root.appendingPathComponent("old.mp4")
        for url in [firstURL, secondURL, oldURL] { try Data([1,2,3]).write(to: url) }
        var checks: [String: Bool] = [:]
        let preferencesDomain = ProcessInfo.processInfo.environment["MWX_IMPORT_ADMISSION_DOMAIN"]!
        defer { UserDefaults(suiteName: preferencesDomain)!.removePersistentDomain(forName: preferencesDomain) }

        func setup() -> (WallpaperManager, OnlineLibraryService, NSObjectProtocol) {
            let manager = WallpaperManager()
            let old = VideoWallpaper(id: "old", title: "Old", path: oldURL.path)
            manager.wallpapers = [old]
            let current = candidate(manager, .video, path: oldURL.path)
            current.show(manager)
            manager.libraryBackingPublished = { [weak manager] in manager?.backingPublications.append($0) }
            let service = OnlineLibraryService()
            service.downloadedIDs = [1, 2]
            service.prepareVideoPlaybackIntent = { manager.admitImportedVideoPlayback(reference: $0, libraryPending: $1) }
            service.requestLibraryPlayback = { reference in
                let snapshot = try! WallpaperPlaybackSequence.Snapshot(source: .single(reference), revision: 1,
                    entries: [.init(reference: reference, runtime: .video, isPlayable: true)])
                manager.libraryPlaybackDispatcher = { pending in
                    service.setLocalFileAsWallpaper(id: Int(pending.proposal.entry.reference.sourceID)!, libraryPending: pending)
                }
                _ = manager.requestLibraryPlayback(reference: reference, from: snapshot)
            }
            let observer = ImportedVideoPlaybackObserver.make(name: .onlineVideoReadyToPlay,
                context: .onlinePlayback, wallpaperManager: manager)
            return (manager, service, observer)
        }
        func hold(_ manager: WallpaperManager) -> DispatchSemaphore {
            let entered = DispatchSemaphore(value: 0), release = DispatchSemaphore(value: 0)
            manager.importPreparationQueue.async { entered.signal(); release.wait() }
            precondition(entered.wait(timeout: .now() + 3) == .success)
            return release
        }
        func wait(_ condition: @escaping () -> Bool, line: UInt = #line) async {
            let deadline = Date().addingTimeInterval(3)
            while !condition() {
                precondition(Date() < deadline, "Import never reached its expected product state at line \(line)")
                try? await Task.sleep(for: .milliseconds(5))
            }
        }

        do {
            let (manager, service, observer) = setup()
            defer { NotificationCenter.default.removeObserver(observer); manager.stopAutoSwitchTimer() }
            let epoch = manager.playbackIntentEpoch
            for directory in [manager.thumbnailCacheDirectory, manager.staticFrameCacheDirectory] {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            }
            let cacheKey = manager.cacheKey(forNormalizedPath: manager.normalizedPath(firstURL.path))
            let thumbnail = manager.thumbnailOutputURL(forKey: cacheKey), frame = manager.staticFrameOutputURL(forKey: cacheKey)
            try Data("owned cached thumbnail".utf8).write(to: thumbnail)
            try Data("owned cached static frame".utf8).write(to: frame)
            service.downloadedIDs = []
            service.downloadAndSet(item: .init(id: 999))
            checks["downloadOnlyDoesNotAdmitOrPlay"] = service.downloadStarts == 1 && manager.playbackIntentEpoch == epoch
                && manager.playbackSwitch.pending == nil
            service.downloadedIDs = [1]
            let release = hold(manager)
            let preparations = WallpaperEngine.shared.videoPreparations
            service.downloadAndSet(item: .init(id: 1))
            let ticket = manager.playbackSwitch.pending!.selection.ticket
            checks["clickAdmitsOriginalVideoTicketBeforeAsyncImport"] = ticket.runtime == .video
                && ticket.epoch == epoch + 1 && WallpaperEngine.shared.videoPreparations == preparations
                && manager.currentWallpaper?.path == oldURL.path
                && manager.backingPublications.isEmpty
            release.signal()
            await wait { WallpaperEngine.shared.videoPreparations == preparations + 1 }
            checks["readyObserverImportAndPrepareKeepSameTicket"] = WallpaperEngine.shared.lastPreparedVideoTicket == ticket
                && manager.playbackIntentEpoch == ticket.epoch && manager.playbackSwitch.pending?.selection.ticket == ticket
                && manager.wallpapers.contains(where: { $0.path == firstURL.path }) && manager.importSummaryCount == 0
            checks["successfulImportPublishesExactBackingReceipt"] = manager.backingPublications == [
                WallpaperContentBackingPublication(backingVideoID: manager.pendingWallpaper!.id,
                    publishedReference: .init(provider: .pixabay, sourceID: "1"), proof: .publishedDownload)
            ]
            let imported = manager.wallpapers.first { $0.path == firstURL.path }
            checks["actualCacheLookupReachesImportedAndPreparedWallpaper"] = imported?.thumbnailPath == thumbnail.path
                && imported?.staticFramePath == frame.path && manager.pendingWallpaper?.thumbnailPath == thumbnail.path
                && manager.pendingWallpaper?.staticFramePath == frame.path && WallpaperEngine.shared.lastPreparedVideoTicket == ticket
        }
        do {
            let (manager, service, observer) = setup()
            defer { NotificationCenter.default.removeObserver(observer); manager.stopAutoSwitchTimer() }
            let release = hold(manager)
            let preparations = WallpaperEngine.shared.videoPreparations
            service.setLocalFileAsWallpaper(id: 1)
            manager.stopCurrentPlayback()
            let stoppedEpoch = manager.playbackIntentEpoch
            release.signal()
            await wait { manager.wallpapers.contains(where: { $0.path == firstURL.path }) }
            checks["stopKeepsSilentImportButNeverResurrectsPlayback"] = WallpaperEngine.shared.videoPreparations == preparations
                && manager.playbackSwitch.pending == nil && manager.currentWallpaper == nil
                && manager.playbackIntentEpoch == stoppedEpoch && !manager.isPlaying && manager.importSummaryCount == 0
            checks["stopDoesNotDiscardSuccessfulDownloadProvenance"] = manager.backingPublications.count == 1
                && manager.backingPublications[0].backingVideoID == manager.wallpapers.first(where: { $0.path == firstURL.path })?.id
        }
        do {
            let (manager, service, observer) = setup()
            defer { NotificationCenter.default.removeObserver(observer); manager.stopAutoSwitchTimer() }
            let release = hold(manager)
            let preparations = WallpaperEngine.shared.videoPreparations
            service.setLocalFileAsWallpaper(id: 1)
            _ = manager.beginPlaybackIntent(runtime: .web)
            let newer = manager.playbackSwitch.pending!.selection.ticket
            release.signal()
            await wait { manager.wallpapers.contains(where: { $0.path == firstURL.path }) }
            checks["lateImportCannotCancelOrReplaceNewerWeb"] = WallpaperEngine.shared.videoPreparations == preparations
                && manager.playbackSwitch.pending?.selection.ticket == newer && manager.playbackIntentEpoch == newer.epoch
                && manager.currentWallpaper?.path == oldURL.path
        }
        do {
            let (manager, service, observer) = setup()
            defer { NotificationCenter.default.removeObserver(observer); manager.stopAutoSwitchTimer() }
            let release = hold(manager)
            let preparations = WallpaperEngine.shared.videoPreparations
            service.setLocalFileAsWallpaper(id: 1)
            try FileManager.default.removeItem(at: firstURL)
            release.signal()
            await wait { manager.playbackSwitch.pending == nil }
            checks["failedImportReturnsPendingAndRetainsHealthyOutput"] = manager.currentWallpaper?.path == oldURL.path
                && manager.playbackSwitch.committed?.ticket.runtime == .video
                && WallpaperEngine.shared.videoPreparations == preparations && manager.unexpectedMissingFallbacks == 0
            try Data([1,2,3]).write(to: firstURL)
        }
        do {
            let (manager, service, observer) = setup()
            defer { NotificationCenter.default.removeObserver(observer); manager.stopAutoSwitchTimer() }
            let existing = VideoWallpaper(id: "canonical-backing", title: "Original title", path: firstURL.path,
                                           isFavorite: true, lastUsed: .distantPast, tags: ["Original tag"])
            manager.wallpapers.append(existing)
            let preparations = WallpaperEngine.shared.videoPreparations
            service.setLocalFileAsWallpaper(id: 1)
            let ticket = manager.playbackSwitch.pending!.selection.ticket
            await wait { WallpaperEngine.shared.videoPreparations == preparations + 1 }
            checks["existingBackingKeepsIdentityFavoriteTagsAndSameTicket"] = manager.wallpapers == [manager.wallpapers[0], existing]
                && manager.pendingWallpaper?.id == existing.id && WallpaperEngine.shared.lastPreparedVideoTicket == ticket
                && manager.playbackIntentEpoch == ticket.epoch
        }
        do {
            let (manager, service, observer) = setup()
            defer { NotificationCenter.default.removeObserver(observer); manager.stopAutoSwitchTimer() }
            let release = hold(manager)
            let preparations = WallpaperEngine.shared.videoPreparations
            service.setLocalFileAsWallpaper(id: 1)
            service.setLocalFileAsWallpaper(id: 2)
            let latest = manager.playbackSwitch.pending!.selection.ticket
            release.signal()
            await wait { manager.wallpapers.count == 3 && WallpaperEngine.shared.videoPreparations == preparations + 1 }
            checks["twoQueuedImportsOnlyPrepareLatestOriginalTicket"] = WallpaperEngine.shared.lastPreparedVideoTicket == latest
                && manager.pendingWallpaper?.path == secondURL.path && manager.playbackIntentEpoch == latest.epoch
            checks["uncachedLatestSourceDoesNotBorrowPreviousAssetPaths"] = manager.pendingWallpaper?.thumbnailPath == nil
                && manager.pendingWallpaper?.staticFramePath == nil
        }
        do {
            let (manager, _, observer) = setup()
            defer { NotificationCenter.default.removeObserver(observer); manager.stopAutoSwitchTimer() }
            manager.lastManualNavigationAt = CACurrentMediaTime()
            manager.navigateWallpaperManually(.next)
            let queued = manager.pendingManualNavigationWorkItem!
            manager.stopCurrentPlayback()
            let epoch = manager.playbackIntentEpoch
            queued.perform()
            try await Task.sleep(for: .milliseconds(250))
            checks["stopRevokesQueuedDirectionFlagsAndWorkItem"] = manager.pendingManualNavigationWorkItem == nil
                && manager.pendingManualNavigationDirection == nil
                && manager.manualNavigationExecutions == 0 && manager.playbackIntentEpoch == epoch
                && manager.playbackSwitch.pending == nil
        }
        do {
            let (manager, _, observer) = setup()
            defer { NotificationCenter.default.removeObserver(observer); manager.stopCurrentPlayback() }
            manager.navigateWallpaperManually(.next)
            checks["manualNavigationFirstRequestDispatchesImmediatelyThroughRandomHistory"] =
                manager.manualNavigationExecutions == 1 && manager.manualNavigationDirections == [.next]
                && manager.manualNavigationPolicies == [.randomHistory]
                && manager.pendingManualNavigationWorkItem == nil && manager.pendingManualNavigationDirection == nil
            manager.navigateWallpaperManually(.next)
            let replaced = manager.pendingManualNavigationWorkItem
            manager.navigateWallpaperManually(.previous)
            checks["manualNavigationDebounceKeepsOnlyTheLastDirection"] = manager.manualNavigationMinInterval == 0.18
                && replaced?.isCancelled == true && manager.pendingManualNavigationWorkItem !== replaced
                && manager.pendingManualNavigationDirection == .previous && manager.manualNavigationExecutions == 1
            try await Task.sleep(for: .milliseconds(250))
            checks["manualNavigationDelayedDispatchRunsExactlyOnceAndClearsItsReceipt"] =
                manager.manualNavigationExecutions == 2 && manager.manualNavigationDirections == [.next, .previous]
                && manager.manualNavigationPolicies == [.randomHistory, .randomHistory]
                && manager.pendingManualNavigationDirection == nil && manager.pendingManualNavigationWorkItem == nil
        }
        do {
            let (manager, _, observer) = setup()
            defer { NotificationCenter.default.removeObserver(observer); manager.stopCurrentPlayback() }
            manager.lastManualNavigationAt = CACurrentMediaTime()
            manager.navigateWallpaperManually(.next)
            let queued = manager.pendingManualNavigationWorkItem!
            let generation = manager.libraryPlaybackSequence.rotationGeneration
            let reference = WallpaperReference(provider: .videoLibrary, sourceID: "new-navigation-source")
            let snapshot = try WallpaperPlaybackSequence.Snapshot(source: .single(reference), revision: 1,
                entries: [.init(reference: reference, runtime: .video, isPlayable: true)])
            let proposal = manager.libraryPlaybackSequence.proposeSelection(reference, from: snapshot)
            precondition(proposal != nil && manager.libraryPlaybackSequence.rotationGeneration != generation)
            queued.perform()
            try await Task.sleep(for: .milliseconds(250))
            checks["manualNavigationOldGenerationCannotDispatchItsQueuedDirection"] = manager.manualNavigationExecutions == 0
                && manager.manualNavigationDirections.isEmpty && manager.manualNavigationPolicies.isEmpty
        }
        do {
            let (manager, _, observer) = setup()
            defer { NotificationCenter.default.removeObserver(observer); manager.stopAutoSwitchTimer() }
            let oldCandidate = candidate(manager, .scene)
            var newer: ImportedVideoPlaybackAdmission?
            var newerDeadline: DispatchWorkItem?
            oldCandidate.onCancel = {
                newer = manager.admitImportedVideoPlayback(reference: WallpaperReference(provider: .pixabay, sourceID: "newer"))
                newerDeadline = manager.switchDeadline
                manager.pendingWallpaper = VideoWallpaper(path: secondURL.path)
            }
            let obsolete = manager.admitImportedVideoPlayback(reference: WallpaperReference(provider: .steamWorkshop, sourceID: "outer"))
            checks["reentrantCancellationCannotStealTicketOrRevokeNewClaim"] = obsolete == nil && newer != nil
                && manager.playbackSwitch.pending?.selection.ticket == newer?.ticket
                && ImportedVideoAutoplayGate.shared.isCurrent(newer!.autoplayToken)
                && manager.switchDeadline === newerDeadline && manager.switchDeadline?.isCancelled == false
                && manager.pendingWallpaper?.path == secondURL.path
        }
        do {
            let (manager, _, observer) = setup()
            defer { NotificationCenter.default.removeObserver(observer); manager.stopAutoSwitchTimer() }
            let oldCandidate = candidate(manager, .scene)
            var newer: ImportedVideoPlaybackAdmission?
            var newerDeadline: DispatchWorkItem?
            oldCandidate.onCancel = {
                newer = manager.admitImportedVideoPlayback(reference: WallpaperReference(provider: .pixabay, sourceID: "after-stop"))
                newerDeadline = manager.switchDeadline
                manager.pendingWallpaper = VideoWallpaper(path: secondURL.path)
            }
            manager.stopCurrentPlayback()
            checks["reentrantNewIntentSurvivesOuterStopMirrorsAndDeadline"] = newer != nil
                && manager.playbackSwitch.pending?.selection.ticket == newer?.ticket
                && ImportedVideoAutoplayGate.shared.isCurrent(newer!.autoplayToken)
                && manager.switchDeadline === newerDeadline && manager.switchDeadline?.isCancelled == false
                && manager.pendingWallpaper?.path == secondURL.path
        }
        do {
            let (manager, _, observer) = setup()
            defer { NotificationCenter.default.removeObserver(observer); manager.stopAutoSwitchTimer() }
            let oldCandidate = candidate(manager, .scene)
            var newer: ImportedVideoPlaybackAdmission?
            var newerDeadline: DispatchWorkItem?
            oldCandidate.onCancel = {
                newer = manager.admitImportedVideoPlayback(reference: WallpaperReference(provider: .pixabay, sourceID: "after-web"))
                newerDeadline = manager.switchDeadline
                manager.pendingWallpaper = VideoWallpaper(path: secondURL.path)
            }
            let obsoleteEpoch = manager.beginPlaybackIntent(runtime: .web)
            checks["outerWebCannotClearNewerVideoPendingOrDeadline"] = newer != nil && newer!.ticket.epoch > obsoleteEpoch
                && manager.playbackSwitch.pending?.selection.ticket == newer?.ticket
                && ImportedVideoAutoplayGate.shared.isCurrent(newer!.autoplayToken)
                && manager.pendingWallpaper?.path == secondURL.path
                && manager.switchDeadline === newerDeadline && manager.switchDeadline?.isCancelled == false
        }
        do {
            let (manager, _, observer) = setup()
            defer { NotificationCenter.default.removeObserver(observer); manager.stopAutoSwitchTimer() }
            let oldCandidate = candidate(manager, .scene)
            var newer: ImportedVideoPlaybackAdmission?
            oldCandidate.onCancel = {
                newer = manager.admitImportedVideoPlayback(reference: WallpaperReference(provider: .pixabay, sourceID: "after-direct-video"))
            }
            let preparations = WallpaperEngine.shared.videoPreparations
            let reference = WallpaperReference(provider:.videoLibrary,sourceID:"outer-direct-video")
            let source = try WallpaperPlaybackSequence.Snapshot(source:.single(reference),revision:1,
                entries:[.init(reference:reference,runtime:.video,isPlayable:true)])
            manager.libraryPlaybackDispatcher = { pending in
                manager.prepareVideoSwitch(VideoWallpaper(path:firstURL.path),libraryPending:pending)
                return true
            }
            let outer = manager.requestLibraryPlayback(reference:reference,from:source)
            checks["directVideoPreparationCannotBorrowReentrantTicket"] = outer == nil && newer != nil
                && manager.playbackSwitch.pending?.selection.ticket == newer?.ticket
                && ImportedVideoAutoplayGate.shared.isCurrent(newer!.autoplayToken)
                && WallpaperEngine.shared.videoPreparations == preparations
        }
        do {
            let (manager, _, observer) = setup()
            defer { NotificationCenter.default.removeObserver(observer); manager.stopAutoSwitchTimer() }
            let failing = manager.admitImportedVideoPlayback(reference: WallpaperReference(provider: .steamWorkshop, sourceID: "fails"))!
            var newer: ImportedVideoPlaybackAdmission?
            var newerDeadline: DispatchWorkItem?
            var cancellations = 0
            WallpaperEngine.shared.cancellation = { ticket in
                guard ticket == failing.ticket else { return }
                cancellations += 1
                newer = manager.admitImportedVideoPlayback(reference: WallpaperReference(provider: .pixabay, sourceID: "after-failure"))
                newerDeadline = manager.switchDeadline
                manager.pendingWallpaper = VideoWallpaper(path: secondURL.path)
            }
            manager.failImportedVideoPlayback(failing, reason: "Import failed")
            WallpaperEngine.shared.cancellation = nil
            checks["failedEffectCompletesCancelWithoutClearingNewVideoMirrors"] = cancellations == 1 && newer != nil
                && manager.playbackSwitch.cancellations.isEmpty
                && manager.playbackSwitch.pending?.selection.ticket == newer?.ticket
                && manager.pendingWallpaper?.path == secondURL.path
                && manager.switchDeadline === newerDeadline && manager.switchDeadline?.isCancelled == false
                && ImportedVideoAutoplayGate.shared.isCurrent(newer!.autoplayToken)
        }
        do {
            let (manager, _, observer) = setup()
            defer { NotificationCenter.default.removeObserver(observer); manager.stopAutoSwitchTimer() }
            let committedTicket = manager.playbackSwitch.committed!.ticket
            let newerSelection = candidate(manager, .scene)
            manager.switchFailed(newerSelection.ticket, reason: "New Scene could not prepare")
            let recovery = NativeEndpoint(committedTicket)
            manager.switchPrepared(committedTicket, endpoint: recovery.endpoint)
            let isOlderRecovery = manager.playbackSwitch.pending?.recovery == true
                && committedTicket.epoch < manager.playbackIntentEpoch
            var failures = 0
            let token = NotificationCenter.default.addObserver(forName: .wallpaperSwitchDidFail, object: nil, queue: nil) { _ in failures += 1 }
            manager.switchFailed(committedTicket, reason: "Native recovery confirmation failed")
            NotificationCenter.default.removeObserver(token)
            checks["olderCommittedTicketRecoveryStillReportsLegitimateFailure"] = isOlderRecovery && failures == 1
                && manager.playbackSwitch.pending == nil && manager.playbackSwitch.committed?.ticket == committedTicket
                && manager.currentWallpaper?.path == oldURL.path
        }
        do {
            let (manager, _, observer) = setup()
            defer { NotificationCenter.default.removeObserver(observer); manager.stopAutoSwitchTimer() }
            let failing = manager.admitImportedVideoPlayback(reference: WallpaperReference(provider: .steamWorkshop, sourceID: "notifies"))!
            var newer: ImportedVideoPlaybackAdmission?
            var refreshesAfterCallback = -1
            let token = NotificationCenter.default.addObserver(forName: .wallpaperSwitchDidFail, object: nil, queue: nil) { _ in
                newer = manager.admitImportedVideoPlayback(reference: WallpaperReference(provider: .pixabay, sourceID: "notification-reentry"))
                refreshesAfterCallback = manager.timerRefreshAudit
            }
            manager.failImportedVideoPlayback(failing, reason: "Notify before timer policy")
            NotificationCenter.default.removeObserver(token)
            checks["failureNotificationReentryDoesNotApplyOldTimerMirror"] = newer != nil
                && manager.playbackSwitch.pending?.selection.ticket == newer?.ticket
                && refreshesAfterCallback >= 0 && manager.timerRefreshAudit == refreshesAfterCallback
                && manager.switchDeadline?.isCancelled == false
        }
        do {
            let (manager, service, observer) = setup()
            defer { NotificationCenter.default.removeObserver(observer); manager.stopAutoSwitchTimer() }
            manager.migrationRecoveryMessage = "Saved migration input needs recovery"
            let original = manager.wallpapers
            let preparations = WallpaperEngine.shared.videoPreparations
            var failureMessage: String?
            let failureToken = NotificationCenter.default.addObserver(forName: .wallpaperSwitchDidFail, object: nil, queue: .main) {
                failureMessage = $0.userInfo?["message"] as? String
            }
            service.setLocalFileAsWallpaper(id: 1)
            NotificationCenter.default.removeObserver(failureToken)
            checks["readOnlyMigrationRejectsImportAndReturnsPendingWithVisibleReason"] = manager.wallpapers == original
                && manager.playbackSwitch.pending == nil && manager.currentWallpaper?.path == oldURL.path
                && WallpaperEngine.shared.videoPreparations == preparations && manager.migrationWarnings == 1
                && manager.importSummaryCount == 0 && failureMessage == "需要先恢复资料库再导入播放。"
        }
        do {
            let (manager, service, observer) = setup()
            defer { NotificationCenter.default.removeObserver(observer); manager.stopAutoSwitchTimer() }
            let existing = VideoWallpaper(id: "indexed-download", title: "Stored title", path: root.path + "/./online_1.mp4",
                isFavorite: true, lastUsed: .distantPast, tags: ["Keep"])
            manager.wallpapers.append(existing)
            manager.migrationRecoveryMessage = "Saved migration input needs recovery"
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let originalIndex = try encoder.encode(manager.wallpapers)
            let mediaBytes = try Data(contentsOf: firstURL)
            let keys = [manager.wallpapersKey, "WallpaperTags", "RecentWallpapers", manager.initialIndexChangesKey]
            let frozen = Dictionary(uniqueKeysWithValues: keys.map { ($0, Data(("original-" + $0).utf8)) })
            for (key, bytes) in frozen { manager.defaults.set(bytes, forKey: key) }
            var admitted: ImportedVideoPlaybackAdmission?
            service.prepareVideoPlaybackIntent = { reference, pending in
                let admission = manager.admitImportedVideoPlayback(reference: reference, libraryPending: pending)
                admitted = admission
                return admission
            }
            let epoch = manager.playbackIntentEpoch, preparations = WallpaperEngine.shared.videoPreparations
            service.setLocalFileAsWallpaper(id: 1)
            checks["readOnlyIndexedDownloadPlaysThroughOriginalTicketWithoutNewClaim"] = admitted != nil
                && WallpaperEngine.shared.videoPreparations == preparations + 1
                && WallpaperEngine.shared.lastPreparedVideoTicket == admitted?.ticket
                && manager.playbackIntentEpoch == epoch + 1 && manager.playbackIntentEpoch == admitted?.ticket.epoch
                && manager.pendingWallpaper?.id == existing.id && manager.playbackSwitch.pending?.selection.ticket == admitted?.ticket
                && ImportedVideoAutoplayGate.shared.isCurrent(admitted!.autoplayToken)
            // Exercise the two current index persistence inputs. Retired
            // relationship keys have no writer; their original bytes must
            // still survive the actual playback chain below.
            for key in [manager.wallpapersKey, manager.initialIndexChangesKey] {
                manager.saveCodableValue([existing], forKey: key)
            }
            checks["readOnlyIndexedPlaybackPreservesFrozenInputAndMediaBytes"] = try encoder.encode(manager.wallpapers) == originalIndex
                && keys.allSatisfy { manager.defaults.data(forKey: $0) == frozen[$0] }
                && Data(contentsOf: firstURL) == mediaBytes && manager.historyRequests == 0 && manager.recentRequests == 0
                && manager.importedAssetRequests.isEmpty && manager.importSummaryCount == 0 && manager.migrationWarnings == 0
        }
        do {
            let (manager, _, observer) = setup()
            defer { NotificationCenter.default.removeObserver(observer); manager.stopAutoSwitchTimer() }
            let existing = VideoWallpaper(id: "indexed-steam", title: "Stored Steam", path: firstURL.path)
            manager.wallpapers.append(existing)
            manager.migrationRecoveryMessage = "Recovery required"
            let admission = manager.admitImportedVideoPlayback(reference: .init(provider: .steamWorkshop, sourceID: "42"))!
            let preparations = WallpaperEngine.shared.videoPreparations
            manager.processImportedVideos(from: [firstURL], presentingIn: nil, context: .steamPlayback, admission: admission)
            checks["readOnlySteamAdmissionAlsoReusesOnlyExistingIndexedTarget"] = WallpaperEngine.shared.videoPreparations == preparations + 1
                && WallpaperEngine.shared.lastPreparedVideoTicket == admission.ticket && manager.pendingWallpaper?.id == existing.id
                && manager.wallpapers.count == 2 && manager.recentRequests == 0 && manager.importedAssetRequests.isEmpty
        }
        do {
            let (manager, _, observer) = setup()
            defer { NotificationCenter.default.removeObserver(observer); manager.stopAutoSwitchTimer() }
            manager.wallpapers.append(VideoWallpaper(id: "indexed", title: "Indexed", path: firstURL.path))
            manager.migrationRecoveryMessage = "Recovery required"
            let obsolete = manager.admitImportedVideoPlayback(reference: .init(provider: .pixabay, sourceID: "1"))!
            let newer = manager.admitImportedVideoPlayback(reference: .init(provider: .steamWorkshop, sourceID: "newer"))!
            let deadline = manager.switchDeadline, preparations = WallpaperEngine.shared.videoPreparations
            manager.processImportedVideos(from: [firstURL], presentingIn: nil, context: .onlinePlayback, admission: obsolete)
            checks["readOnlyLateAdmissionCannotPrepareOrCancelNewerTicket"] = WallpaperEngine.shared.videoPreparations == preparations
                && manager.playbackSwitch.pending?.selection.ticket == newer.ticket && manager.playbackIntentEpoch == newer.ticket.epoch
                && manager.switchDeadline === deadline && ImportedVideoAutoplayGate.shared.isCurrent(newer.autoplayToken)
                && manager.migrationWarnings == 0
        }
        do {
            let (manager, _, observer) = setup()
            defer { NotificationCenter.default.removeObserver(observer); manager.stopAutoSwitchTimer() }
            manager.wallpapers.append(VideoWallpaper(id: "indexed", title: "Indexed", path: firstURL.path))
            manager.migrationRecoveryMessage = "Recovery required"
            let admission = manager.admitImportedVideoPlayback(reference: .init(provider: .pixabay, sourceID: "1"))!
            let preparations = WallpaperEngine.shared.videoPreparations
            manager.processImportedVideos(from: [firstURL], presentingIn: nil, context: .steamPlayback, admission: admission)
            checks["readOnlyMismatchedSourceAdmissionCannotBypassImportProtection"] = WallpaperEngine.shared.videoPreparations == preparations
                && manager.playbackSwitch.pending == nil && manager.wallpapers.count == 2 && manager.migrationWarnings == 1
        }
        for admitted in [false, true] {
            let (manager, service, observer) = setup()
            defer { NotificationCenter.default.removeObserver(observer); manager.stopAutoSwitchTimer() }
            let release = hold(manager)
            let preparations = WallpaperEngine.shared.videoPreparations
            if admitted { service.setLocalFileAsWallpaper(id: 1) }
            else { manager.processImportedVideos(from: [firstURL], presentingIn: nil, context: .library) }
            // The real reset owner invalidates this existing index epoch before
            // clearing media. A blocked worker must not cross that boundary.
            manager.wallpaperIndexSaveEpoch &+= 1
            manager.wallpapers.removeAll()
            manager.stopCurrentPlayback()
            let epoch = manager.playbackIntentEpoch
            release.signal()
            await withCheckedContinuation { continuation in
                manager.importPreparationQueue.async { continuation.resume() }
            }
            await drainMainQueue()
            checks[admitted ? "resetRejectsLateAdmittedImportAndReceipt" : "resetRejectsLateNormalImport"] = manager.wallpapers.isEmpty
                && manager.backingPublications.isEmpty && manager.importedAssetRequests.isEmpty
                && manager.importSummaryCount == 0 && manager.playbackIntentEpoch == epoch
                && WallpaperEngine.shared.videoPreparations == preparations && manager.playbackSwitch.pending == nil
        }
        do {
            let (manager, _, observer) = setup()
            defer { NotificationCenter.default.removeObserver(observer); manager.stopAutoSwitchTimer() }
            manager.onImportSummary = {
                manager.wallpaperIndexSaveEpoch &+= 1
                manager.wallpapers.removeAll()
            }
            manager.processImportedVideos(from: [firstURL], presentingIn: nil, context: .library)
            await wait { manager.importSummaryCount == 1 }
            checks["resetReentryFromSummaryCannotAppendOldPreparedRows"] = manager.wallpapers.isEmpty
                && manager.backingPublications.isEmpty && manager.importedAssetRequests.isEmpty
        }
        do {
            let (manager, _, observer) = setup()
            defer { NotificationCenter.default.removeObserver(observer); manager.stopAutoSwitchTimer() }
            var receipt: WallpaperSourceImportResult?
            let preparations = WallpaperEngine.shared.videoPreparations
            let missing = root.appendingPathComponent("missing-import.mp4")
            manager.processImportedVideos(from: [secondURL, oldURL, missing, secondURL], presentingIn: nil, context: .library,
                presentsSummary: false) { receipt = $0 }
            await wait { receipt != nil }
            checks["explicitImportReceiptPreservesEachInputOutcomeAndStableReference"] = receipt?.items.map(\.disposition) == [.added, .existing, .failed, .existing]
                && receipt?.items[0].organizationItem?.reference == receipt?.items[3].organizationItem?.reference
                && receipt?.items[1].organizationItem?.reference.sourceID == "old"
                && receipt?.items[2].failureMessage == "文件不存在"
                && receipt?.organizationItems.count == 2 && manager.importSummaryCount == 0
                && WallpaperEngine.shared.videoPreparations == preparations
        }
        do {
            let (manager, _, observer) = setup()
            defer { NotificationCenter.default.removeObserver(observer); manager.stopAutoSwitchTimer() }
            let release = hold(manager)
            var a: WallpaperSourceImportResult?, b: WallpaperSourceImportResult?
            manager.processImportedVideos(from: [firstURL], presentingIn: nil, context: .library,
                presentsSummary: false) { a = $0 }
            manager.processImportedVideos(from: [secondURL], presentingIn: nil, context: .library,
                presentsSummary: false) { b = $0 }
            release.signal()
            await wait { a != nil && b != nil }
            checks["independentExplicitImportCommandsBothFinishInOriginalSerialQueue"] = a?.organizationItems.first?.locator.path == firstURL.path
                && b?.organizationItems.first?.locator.path == secondURL.path && manager.wallpapers.count == 3
                && manager.importSummaryCount == 0 && manager.backingPublications.isEmpty
        }
        print(String(decoding: try JSONEncoder().encode(checks), as: UTF8.self))
    }
}
