import AppKit
import QuartzCore
import Combine
import Foundation

@main struct SteamDetailInvalidationHarness {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        let service = SteamWorkshopService.shared
        let item = makeItem()
        service.record = makeRecord()
        service.selectedDownloadDetailItem = item
        service.selectedDownloadInspectorItem = item
        SceneDaemonClient.shared.activeRecordID = item.id
        let detail = AppKitSteamWorkshopItemDetailView(item: item)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 760), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = detail
        detail.frame = NSRect(x: 0, y: 0, width: 400, height: 760)
        settle(detail)
        var checks: [String: Bool] = [:]
        func same(_ old: [NSView], _ new: [NSView]) -> Bool {
            old.count == new.count && zip(old, new).allSatisfy { $0 === $1 }
        }
        func pulse() { service.objectWillChange.send(); settle(detail) }
        func changes(_ mutation: () -> Void) -> Bool {
            let before = roots(detail)
            mutation(); pulse()
            return !same(before, roots(detail))
        }
        func qualify() {
            service.record = makeRecord()
            service.selectedDownloadDetailItem = item
            service.selectedDownloadInspectorItem = item
            SceneDaemonClient.shared.activeRecordID = item.id
            service.downloading = false
            service.downloadingIDs = []; service.queuedIDs = []
            detail.configure(item: item); settle(detail)
        }
        let definition = SceneUserPropertyDefinition(key: "renamedScalar", title: "Scalar", kind: .slider, runtimeType: "slider", order: 0, index: 0,
            minimumValue: 0, maximumValue: 100, stepValue: 1, allowsFractionalValues: false, fractionalPrecision: nil,
            displayCondition: nil, defaultValue: .number(0), options: [])
        let originalRoots = roots(detail), originalFooter = footer(detail).subviews
        let initialConstraints = constraints(detail)
        let initialScroll = views(detail).compactMap { $0 as? NSScrollView }.first!
        let firstContentRect = originalRoots[0].convert(originalRoots[0].bounds, to: initialScroll.documentView!)
        let visibleContentRect = initialScroll.documentVisibleRect
        checks["initialTopContentIsFullyVisible"] = firstContentRect.minY >= visibleContentRect.minY - 1
            && firstContentRect.maxY <= visibleContentRect.maxY + 1
        let initialFadeColors = (initialScroll.layer?.mask as? CAGradientLayer)?.colors as? [CGColor]
        checks["steamUsesSharedTopInsetWithoutFadingTheInitialPreview"] = initialScroll is InspectorFadingScrollView
            && initialScroll.documentView?.isFlipped == true && abs(firstContentRect.minY - visibleContentRect.minY - 8) <= 1
            && initialFadeColors?.first?.alpha == 1
        checks["detailScrollbarsStayAbsent"] = !initialScroll.hasVerticalScroller && !initialScroll.hasHorizontalScroller
        checks["downloadDetailPrefersLocalOverRemoteMetadata"] = FixturePreview.localLoads == [URL(fileURLWithPath: "/fixture/local-preview.gif")]
        let initialPreviewState = previewState(detail)
        let initialHeightConstraint = previewHeightConstraints(detail).first
        var pulses = 0
        let observer = service.objectWillChange.sink { pulses += 1 }
        service.accessorReads = [:]
        var allValuesSaved = true
        for value in 1...20 {
            service.updateScenePropertyValue(.number(Double(value)), definition: definition, record: service.record!)
            settle(detail)
            allValuesSaved = allValuesSaved && service.scenePropertyOverrides(for: service.record!)[definition.key] == .number(Double(value))
        }
        checks["twentyIndependentUpdatesSaveAndDispatch"] = allValuesSaved
            && service.scenePropertyCommandRevision == 20 && PlaybackCommandMultiplexer.shared.propertyDispatches == 20
        checks["allOriginalPropertyPulsesPreserved"] = pulses == 20
        checks["eligibleContentAndFooterRetainIdentity"] = same(originalRoots, roots(detail)) && same(originalFooter, footer(detail).subviews)
        checks["eligibleNotificationsAvoidIOBearingGetters"] = service.accessorReads.values.allSatisfy { $0 == 0 }
        checks["ordinaryUpdatesDoNotGrowConstraints"] = constraints(detail) == initialConstraints
        observer.cancel()

        let beforeBurst = roots(detail)
        service.previewReloadToken += 1; service.objectWillChange.send()
        service.previewReloadToken -= 1; service.objectWillChange.send()
        settle(detail)
        checks["pendingPulsesCompareFinalStateNotEarlyRenderedState"] = same(beforeBurst, roots(detail)) && !detail.isRebuildScheduled
        var metadataRebuilt = true
        let requiredConstraintCount = constraints(detail)
        for index in 1...10 {
            metadataRebuilt = changes { service.selectedDownloadDetailItem = makeItem(title: "Metadata \(index)") } && metadataRebuilt
        }
        checks["metadataChangesRebuildActualLabels"] = metadataRebuilt && labels(detail).contains("Metadata 10")
        checks["requiredRebuildsKeepOnePreviewHeight"] = previewHeights(detail) == 1 && constraints(detail) == requiredConstraintCount
            && previewHeightConstraints(detail).first === initialHeightConstraint && previewHeight(detail) == 156
        checks["metadataRebuildDoesNotReloadPreview"] = FixturePreview.localLoads.count == 1 && FixturePreview.animationLoads == 1
        let rebuiltPreviewState = previewState(detail)
        let beforeConfigure = roots(detail)
        detail.configure(item: service.selectedDownloadDetailItem!); settle(detail)
        checks["explicitConfigureStillForcesRebuild"] = !same(beforeConfigure, roots(detail))
        checks["forceRefreshAlsoKeepsOnePreviewHeight"] = previewHeights(detail) == 1
            && previewHeightConstraints(detail).first === initialHeightConstraint && previewHeight(detail) == 156
        let originalContentSize = window.contentView!.bounds.size
        window.setContentSize(NSSize(width: 400, height: 380)); settle(detail)
        let sourcePreview = views(detail).first { $0 is SteamWorkshopPreviewImageContainerView }!
        let scroll = views(detail).compactMap { $0 as? NSScrollView }.first!
        let maxOffset = max(0, (scroll.documentView?.bounds.height ?? 0) - scroll.contentView.bounds.height)
        checks["realSteamSameTurnScrollProbeHasANonzeroScrollableDocument"] = maxOffset >= 37
        let offset = NSPoint(x: 0, y: min(maxOffset, 37))
        scroll.contentView.scroll(to: offset); scroll.reflectScrolledClipView(scroll.contentView)
        let scrolledFadeColors = (scroll.layer?.mask as? CAGradientLayer)?.colors as? [CGColor]
        detail.configure(item: service.selectedDownloadDetailItem!)
        let immediateFrame = sourcePreview.convert(sourcePreview.bounds, to: detail)
        let immediateOffset = scroll.contentView.bounds.origin
        settle(detail)
        checks["realSteamPreviewHasFinalGeometryBeforeTheNextRunLoop"] = immediateFrame == sourcePreview.convert(sourcePreview.bounds, to: detail)
            && immediateFrame.width > 0 && immediateFrame.height == 156
        checks["realSteamScrollRestoresWithinTheSameRebuild"] = immediateOffset == offset && scroll.contentView.bounds.origin == offset
        scroll.contentView.scroll(to: .zero); scroll.reflectScrolledClipView(scroll.contentView)
        let topFadeColors = (scroll.layer?.mask as? CAGradientLayer)?.colors as? [CGColor]
        let restoredFirst = roots(detail)[0].convert(roots(detail)[0].bounds, to: scroll.documentView!)
        checks["steamSharedFadeTracksNativeScrollAndReturnToTop"] = scrolledFadeColors?.first?.alpha == 0
            && topFadeColors?.first?.alpha == 1 && abs(restoredFirst.minY - scroll.documentVisibleRect.minY - 8) <= 1
        window.setContentSize(originalContentSize); settle(detail)

        checks["rawReadyRecordSizeInvalidates"] = changes { service.record = makeRecord(size: "9 MB") } && labels(detail).contains("9 MB")
        qualify()
        checks["rawDependencyRecordInvalidates"] = changes { service.record = makeRecord(dependency: .missing(itemID: "dependency-probe")) }
            && labels(detail).contains { $0.contains("dependency-probe") }
        checks["missingDependencyRunningTaskInvalidates"] = changes { service.downloadingIDs.insert("dependency-probe") }
        let beforeEquivalentTask = roots(detail)
        service.downloadingIDs = []; service.queuedIDs.insert("dependency-probe"); pulse()
        checks["missingDependencyRunningAndQueuedHaveEquivalentDisplay"] = same(beforeEquivalentTask, roots(detail))
        checks["missingDependencyTaskCompletionInvalidates"] = changes { service.queuedIDs = [] }
        checks["missingDependencyQueuedTaskInvalidates"] = changes { service.queuedIDs.insert("dependency-probe") }
        checks["refreshStateInvalidates"] = changes { service.isRefreshingSelectedDownloadDetailItem = true }
            && labels(detail).contains { $0.contains("正在补全") }
        checks["detailErrorInvalidates"] = changes { service.selectedDownloadDetailError = "Fixture detail error" }
            && labels(detail).contains("Fixture detail error")
        checks["previewReloadTokenInvalidates"] = changes { service.previewReloadToken += 1 }
        checks["localAuthorRouteInvalidates"] = changes { service.selectedDownloadInspectorItem = nil; service.selectedBrowserItem = service.selectedDownloadDetailItem }
        checks["onlineStateInvalidates"] = changes { service.steamAuth.isOnline = true }
        checks["subscriptionStateInvalidates"] = changes { service.steamSubscriptions.value = .known(true) }
            && labels(detail).contains("已订阅")
        checks["unconfirmedSubscriptionStateInvalidates"] = changes { service.steamSubscriptions.value = .unconfirmed("fixture confirmation") }
            && labels(detail).contains("待确认")
        checks["subscriptionHintInvalidates"] = changes { detail.subscriptionHint = "Fixture hint" } && labels(detail).contains("Fixture hint")
        checks["pendingLaunchMemoryStateInvalidates"] = changes { service.pendingLaunch = true }
        checks["mainItemTaskInvalidates"] = changes { service.downloadingIDs.insert(item.id) }
        checks["mainItemQueueInvalidates"] = changes { service.queuedIDs.insert(item.id) }
        service.pendingLaunch = false

        qualify()
        service.steamSubscriptions.onRead = {
            service.steamSubscriptions.onRead = nil
            service.selectedDownloadDetailItem = makeItem(title: "Reentrant final metadata")
            service.objectWillChange.send()
        }
        checks["reentrantPulseKeepsLatestMetadata"] = changes { service.selectedDownloadDetailItem = makeItem(title: "Intermediate metadata") }
            && labels(detail).contains("Reentrant final metadata")
        let afterReentry = roots(detail); pulse()
        checks["renderedStateCatchesUpAfterReentry"] = same(afterReentry, roots(detail))

        qualify()
        checks["inactiveSceneNeverSuppressed"] = changes { SceneDaemonClient.shared.activeRecordID = nil }
            && changes {}
        qualify()
        checks["differentActiveRecordNeverSuppressed"] = changes { SceneDaemonClient.shared.activeRecordID = "other-record" }
            && changes {}
        qualify()
        checks["nonReadySceneNeverSuppressed"] = changes { service.record = makeRecord(status: .failed("fixture failure")) }
            && changes {}
        qualify()
        checks["sourceVideoFallbackNeverSuppressed"] = changes { service.record = makeRecord(source: URL(fileURLWithPath: "/fixture/missing-source.mp4")) }
            && changes {}
        qualify()
        checks["exportedVideoFallbackNeverSuppressed"] = changes { service.record = makeRecord(exported: URL(fileURLWithPath: "/fixture/missing-export.mp4")) }
            && changes {}
        for kind in [SteamWorkshopDownloadContentType.web, .video, .unknown] {
            qualify()
            checks["nonSceneNeverSuppressed-\(kind.rawValue)"] = changes { service.record = makeRecord(kind: kind) } && changes {}
        }
        qualify()
        let switched = makeItem(id: "other-detail", title: "Other item")
        service.record = makeRecord(id: switched.id)
        service.selectedDownloadDetailItem = switched
        let beforeSwitch = roots(detail)
        detail.configure(item: switched); settle(detail)
        checks["explicitItemSwitchForcesActualNewMetadata"] = !same(beforeSwitch, roots(detail)) && labels(detail).contains(switched.title)
        checks["newInactiveItemDoesNotReusePriorSnapshot"] = changes {}

        // The original progress owner updates title/fill in place even outside
        // the eligible branch; a service notification there still rebuilds.
        qualify(); SceneDaemonClient.shared.activeRecordID = nil; service.downloading = true
        service.downloadProgressStore.begin(itemID: item.id, jobKey: "job", attempt: 1); pulse()
        let beforePhase = roots(detail)
        _ = service.downloadProgressStore.receiveHelperEvent(itemID: item.id, jobKey: "job", attempt: 1,
            sequence: 1, stage: "chunks", totalBytes: 100, verifiedBytes: 10)
        settle(detail)
        checks["progressPhaseChangesStillRebuild"] = !same(beforePhase, roots(detail)) && labels(footer(detail)).contains("10%")
        let beforePercent = roots(detail), percentFooter = footer(detail).subviews
        _ = service.downloadProgressStore.receiveHelperEvent(itemID: item.id, jobKey: "job", attempt: 1,
            sequence: 2, stage: "chunks", totalBytes: 100, verifiedBytes: 40)
        settle(detail)
        checks["samePhasePercentUsesOriginalInPlaceOwner"] = same(beforePercent, roots(detail)) && same(percentFooter, footer(detail).subviews)
            && labels(footer(detail)).contains("40%")
        let beforeClear = roots(detail)
        service.downloadProgressStore.clear(itemID: item.id, jobKey: "job"); settle(detail)
        checks["progressPresenceChangesStillRebuild"] = !same(beforeClear, roots(detail))

        qualify()
        detail.subscriptionHint = nil
        service.steamAuth.isOnline = true
        service.steamSubscriptions.value = .unknown
        detail.configure(item: item); settle(detail)
        _ = drainUntil(detail) { service.steamSubscriptions.refreshCalls > 0 }
        let initialUnknownRefreshes = service.steamSubscriptions.refreshCalls
        checks["actualUnknownSubscriptionButtonStartsRefreshTask"] = initialUnknownRefreshes > 0
            && labels(detail).contains("查询中…")
        let beforeAccountChange = roots(detail)
        // The loading pulse from account A need not render before account B
        // returns to online/unknown. The real auth/subscription observers must
        // still rebuild the unknown button and schedule its refresh Task.
        service.objectWillChange.send()
        service.steamSubscriptions.value = .loading
        service.steamSubscriptions.objectWillChange.send()
        service.steamSubscriptions.value = .unknown
        service.steamAuth.objectWillChange.send()
        checks["accountResetToSameUnknownStillRefreshes"] = drainUntil(detail) {
            !same(beforeAccountChange, roots(detail)) && service.steamSubscriptions.refreshCalls > initialUnknownRefreshes
                && !detail.isRebuildScheduled && !detail.isForcedRebuildScheduled
        }
        let forceSources: [(String, () -> Void)] = [
            ("wallpaper", { WallpaperManager.shared.objectWillChange.send() }),
            ("scene-launch", { NotificationCenter.default.post(name: .sceneWallpaperLaunchStateDidChange, object: nil) }),
            ("auth", { service.steamAuth.objectWillChange.send() }),
            ("subscriptions", { service.steamSubscriptions.objectWillChange.send() }),
        ]
        for (name, force) in forceSources {
            let before = roots(detail)
            let refreshes = service.steamSubscriptions.refreshCalls
            let previewLoads = FixturePreview.localLoads.count
            let animationLoads = FixturePreview.animationLoads
            service.objectWillChange.send()
            force()
            checks["pendingServiceCannotSwallowForce-\(name)"] = drainUntil(detail) {
                !same(before, roots(detail)) && service.steamSubscriptions.refreshCalls > refreshes
                    && !detail.isRebuildScheduled && !detail.isForcedRebuildScheduled
            }
            let preview = views(detail).first { $0 is SteamWorkshopPreviewImageContainerView } as! SteamWorkshopPreviewImageContainerView
            checks["forceKeepsReadyPreview-\(name)"] = preview.previewState.image === FixturePreview.image
                && preview.previewState.placeholder == .hidden && FixturePreview.localLoads.count == previewLoads
                && FixturePreview.animationLoads == animationLoads
        }
        let afterForced = roots(detail)
        let afterForcedRefreshes = service.steamSubscriptions.refreshCalls
        pulse()
        checks["serviceOnlyReturnsToFilteringAfterForce"] = same(afterForced, roots(detail))
            && service.steamSubscriptions.refreshCalls == afterForcedRefreshes
            && !detail.isRebuildScheduled && !detail.isForcedRebuildScheduled
        let beforeReentrantForce = service.steamSubscriptions.refreshCalls
        service.steamSubscriptions.onRead = {
            service.steamSubscriptions.onRead = nil
            WallpaperManager.shared.objectWillChange.send()
        }
        service.objectWillChange.send()
        WallpaperManager.shared.objectWillChange.send()
        checks["forceDuringRebuildSchedulesNextTurn"] = drainUntil(detail) {
            service.steamSubscriptions.refreshCalls >= beforeReentrantForce + 2
                && !detail.isRebuildScheduled && !detail.isForcedRebuildScheduled
        }
        checks["allRequiredRebuildsKeepPreviewConstraintBounded"] = previewHeights(detail) == 1
            && previewHeightConstraints(detail).first === initialHeightConstraint && previewHeight(detail) == 156
        qualify()
        FixturePreview.failLocal = true
        FixturePreview.animateRemote = true
        let badLocalDetail = AppKitSteamWorkshopItemDetailView(item: item)
        settle(badLocalDetail)
        let fallbackPreview = views(badLocalDetail).first { $0 is SteamWorkshopPreviewImageContainerView } as! SteamWorkshopPreviewImageContainerView
        checks["actualDetailBadLocalUsesRemoteWithoutVideo"] = fallbackPreview.previewState.image === FixturePreview.remoteAnimation
            && fallbackPreview.previewState.placeholder == .hidden
            && FixturePreview.remoteKeys.last == item.previewImageURL?.absoluteString
            && FixturePreview.animationURLs.last == item.previewImageURL
        fallbackPreview.previewState.setAnimationActive(false)
        checks["actualDetailRemoteFallbackKeepsStatic"] = fallbackPreview.previewState.image === FixturePreview.remoteImage
        service.record = makeRecord(browserItem: item)
        let projected = service.record!.displayItemForToolbar
        service.selectedDownloadDetailItem = projected
        service.selectedDownloadInspectorItem = projected
        let projectedDetail = AppKitSteamWorkshopItemDetailView(item: projected)
        settle(projectedDetail)
        let projectedPreview = views(projectedDetail).first { $0 is SteamWorkshopPreviewImageContainerView } as! SteamWorkshopPreviewImageContainerView
        checks["downloadProjectionRetainsRecordsRemoteFallback"] = projected.previewImageURL?.isFileURL == true
            && projectedPreview.previewState.image === FixturePreview.remoteAnimation
            && FixturePreview.animationURLs.last == item.previewImageURL
        FixturePreview.failRemote = true
        let bothBadDetail = AppKitSteamWorkshopItemDetailView(item: item)
        settle(bothBadDetail)
        let bothBad = views(bothBadDetail).first { $0 is SteamWorkshopPreviewImageContainerView } as! SteamWorkshopPreviewImageContainerView
        checks["actualDetailBothCandidatesFailWithoutVideo"] = bothBad.previewState.image == nil && bothBad.previewState.placeholder == .unavailable
        var injectedPrimary = 0
        service.record = makeRecord()
        service.downloading = false; service.downloadingIDs = []; service.queuedIDs = []; service.pendingLaunch = false
        SceneDaemonClient.shared.activeRecordID = nil
        func libraryActions(playing: Bool = false, canPlay: Bool = true) -> WallpaperInspectorActions {
            .init(state: .init(isPlaying: playing, isFavorite: false, canPerformPrimary: canPlay, canFavorite: false, canOrganize: false, playlistNames: []),
                onPrimary: { injectedPrimary += 1 }, onToggleFavorite: {}, onChoosePlaylist: { _ in })
        }
        let injectedDetail = AppKitSteamWorkshopItemDetailView(item: item, service: service, libraryActions: libraryActions())
        let injectedPlay = views(injectedDetail).compactMap { $0 as? InspectorFooterButton }.first { $0.action == NSSelectorFromString("setAsWallpaper") }!
        _ = injectedPlay.accessibilityPerformPress()
        checks["injectedSteamPrimaryDoesNotBypassCanonicalPlaybackOwner"] = injectedPrimary == 1 && service.wallpaperRequests == 0
        injectedDetail.updateLibraryActions(libraryActions(canPlay: false))
        let disabledPlay = views(injectedDetail).compactMap { $0 as? InspectorFooterButton }.first { $0.action == NSSelectorFromString("setAsWallpaper") }!
        checks["injectedUnavailableSteamPrimaryRefusesNativePress"] = !disabledPlay.isEnabled && !disabledPlay.accessibilityPerformPress() && injectedPrimary == 1
        injectedDetail.updateLibraryActions(libraryActions(playing: true))
        let injectedStop = views(injectedDetail).compactMap { $0 as? InspectorFooterButton }.first { $0.action == NSSelectorFromString("stopCurrentWallpaper") }!
        checks["injectedSteamStopRemainsOnFixedCanonicalAction"] = injectedStop.accessibilityPerformPress() && injectedPrimary == 2 && service.wallpaperRequests == 0
        injectedDetail.updateLibraryActions(libraryActions(playing: true, canPlay: false))
        let disabledStop = views(injectedDetail).compactMap { $0 as? InspectorFooterButton }.first { $0.action == NSSelectorFromString("stopCurrentWallpaper") }!
        checks["absentPinnedPrimaryCannotExposeAnEnabledSteamStop"] = !disabledStop.isEnabled && !disabledStop.accessibilityPerformPress() && injectedPrimary == 2
        injectedDetail.updateLibraryActions(nil)
        checks["clearingRemoteInspectorFactoryRevokesOldPinnedAction"] = !views(injectedDetail).compactMap { $0 as? InspectorFooterButton }.contains { $0.action == NSSelectorFromString("stopCurrentWallpaper") }
            && injectedPrimary == 2
        service.steamAuth.isOnline = false
        let accountDetail = AppKitSteamWorkshopItemDetailView(item: item, service: service)
        let offlineSubscribe = views(accountDetail).compactMap { $0 as? InspectorFooterButton }.first { $0.action == NSSelectorFromString("toggleSubscriptionClicked:") }!
        let offlineIcon = views(offlineSubscribe).compactMap { $0 as? NSImageView }.first!.image
        let bookmark = NSImage(systemSymbolName: "bookmark", accessibilityDescription: nil)!.withSymbolConfiguration(.init(pointSize: 14, weight: .semibold))!
        checks["sourceInspectorSubscriptionUsesNativeBookmarkWithoutOrganizationFactory"] = offlineIcon?.size == bookmark.size
            && offlineSubscribe.accessibilityLabel() == "订阅"
        service.steamAuth.isOnline = true; service.steamSubscriptions.value = .known(true)
        let subscribedDetail = AppKitSteamWorkshopItemDetailView(item: item, service: service)
        let subscribedButton = views(subscribedDetail).compactMap { $0 as? InspectorFooterButton }.first { $0.action == NSSelectorFromString("toggleSubscriptionClicked:") }!
        let subscribedIcon = views(subscribedButton).compactMap { $0 as? NSImageView }.first!.image
        let filledBookmark = NSImage(systemSymbolName: "bookmark.fill", accessibilityDescription: nil)!.withSymbolConfiguration(.init(pointSize: 14, weight: .semibold))!
        checks["subscribedSourceInspectorUsesFilledBookmarkAndRetainsAccountLabel"] = subscribedIcon?.size == filledBookmark.size && subscribedButton.accessibilityLabel() == "已订阅"
        let output: [String: Any] = ["checks": checks, "ordinaryUpdates": 20, "propertyPulses": pulses,
            "propertyDispatches": PlaybackCommandMultiplexer.shared.propertyDispatches,
            "previewInitial": initialPreviewState, "previewAfterMetadata": rebuiltPreviewState,
            "scope": "actual ordinary store/update leaf, detail observation/rebuild and AppKit views; external service/account/playback/inspection leaves"]
        FileHandle.standardOutput.write(try JSONSerialization.data(withJSONObject: output, options: [.sortedKeys]))
        window.close()
    }
    @MainActor static func views(_ root: NSView) -> [NSView] { [root] + root.subviews.flatMap(views) }
    @MainActor static func labels(_ root: NSView) -> [String] { views(root).compactMap { ($0 as? NSTextField)?.stringValue } }
    @MainActor static func footer(_ root: NSView) -> SteamWorkshopDetailFooterView { views(root).first { $0 is SteamWorkshopDetailFooterView } as! SteamWorkshopDetailFooterView }
    @MainActor static func roots(_ root: NSView) -> [NSView] {
        let scrolls = views(root).compactMap { $0 as? NSScrollView }.filter {
            $0.documentView?.subviews.first is NSStackView
        }
        precondition(scrolls.count == 1, "detail must have one content scroll owner")
        return (scrolls[0].documentView!.subviews.first as! NSStackView).arrangedSubviews
    }
    @MainActor static func constraints(_ root: NSView) -> Int { views(root).reduce(0) { $0 + $1.constraints.count } }
    @MainActor static func previewHeights(_ root: NSView) -> Int {
        previewHeightConstraints(root).count
    }
    @MainActor static func previewHeightConstraints(_ root: NSView) -> [NSLayoutConstraint] {
        let preview = views(root).first { $0 is SteamWorkshopPreviewImageContainerView }!
        return preview.constraints.filter { $0.isActive && ($0.firstItem as? NSView) === preview
            && $0.firstAttribute == .height && $0.secondItem == nil && $0.constant == 156 }
    }
    @MainActor static func previewHeight(_ root: NSView) -> CGFloat { views(root).first { $0 is SteamWorkshopPreviewImageContainerView }!.bounds.height }
    @MainActor static func previewState(_ root: NSView) -> [String: Any] {
        let preview = views(root).first { $0 is SteamWorkshopPreviewImageContainerView }!
        let heights = views(root).flatMap(\.constraints).filter { ($0.firstItem as? NSView) === preview && $0.firstAttribute == .height }
        return ["height": preview.bounds.height,
            "treeHeightConstraints": heights.map { ["identity": String(describing: ObjectIdentifier($0)), "active": $0.isActive, "constant": $0.constant] as [String: Any] }]
    }
    @MainActor static func settle(_ detail: NSView) {
        var delivered = false
        DispatchQueue.main.async {
            DispatchQueue.main.async {
                DispatchQueue.main.async { delivered = true }
            }
        }
        precondition(drainUntil(detail) { delivered }, "main-queue delivery did not complete")
        detail.layoutSubtreeIfNeeded()
    }
    @MainActor static func drainUntil(_ detail: NSView, condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(1)
        while !condition(), Date() < deadline {
            _ = RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.01))
            detail.layoutSubtreeIfNeeded()
        }
        return condition()
    }
    static func makeItem(id: String = "detail-probe", title: String = "Synthetic Scene detail") -> SteamWorkshopBrowserItem {
        SteamWorkshopBrowserItem(id: id, title: title, author: "Author", authorProfileURL: nil,
            authorWorkshopURL: URL(string: "https://example.invalid/author"), hasAdultContent: false,
            summary: "Synthetic detail fixture", descriptionText: "Fixed wrapping description. 固定中文描述检查实际布局。",
            tags: ["Scene", "Customizable", "Audio responsive"], workshopTypeText: "Scene", ageRatingText: "Everyone", genreText: "Fantasy",
            categoryText: "Scene", dependencyIDs: [], previewImageURL: URL(string: "https://example.invalid/remote-metadata.gif"), previewVideoURL: nil, previewAssetKind: .stillImage,
            fileSizeText: "2 MB", resolutionText: "1920 x 1080", postedText: "2026-01-01", updatedText: "2026-10-15",
            favoritesText: "200", subscriptionsText: "1000", scoreText: "浏览 3000", lifetimeFavoritesText: "400", lifetimeSubscriptionsText: "5000",
            visibilityText: "Public", moderationText: "Approved", detailFields: [], detailURL: URL(string: "https://example.invalid/detail")!)
    }
    static func makeRecord(id: String = "detail-probe", kind: SteamWorkshopDownloadContentType = .scene,
        status: SteamWorkshopDownloadRecord.Status = .ready, size: String = "2 MB", source: URL? = nil,
        exported: URL? = nil, dependency: SteamWorkshopWebDependencyStatus = .none, browserItem: SteamWorkshopBrowserItem? = nil) -> SteamWorkshopDownloadRecord {
        SteamWorkshopDownloadRecord(id: id, title: "Scene", description: "fixture", tags: [],
            folderURL: URL(fileURLWithPath: "/fixture"), projectFileURL: nil, ownEntryHTMLURL: nil, dependencyHostEntryHTMLURL: nil,
            dependencyHostFolderURL: nil, entryHTMLURL: nil, resolvedWebRootURL: nil, previewURL: URL(fileURLWithPath: "/fixture/local-preview.gif"), sourceVideoURL: source,
            exportedVideoURL: exported, updatedAt: Date(timeIntervalSince1970: 0), sizeText: size, status: status,
            browserItem: browserItem, contentType: kind, dependencyItemID: nil, dependencyStatus: dependency)
    }
}
