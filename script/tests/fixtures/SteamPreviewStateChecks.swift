import AppKit

/// Controlled completions exercise source identity and temporal counterexamples,
/// while the companion AppKit harness uses real encoded images and cache IO.
@MainActor func steamPreviewStateChecks(still: NSImage, animation: NSImage, localVersionURL: URL) throws -> [String: Bool] {
    let a = URL(string: "https://example.invalid/renamed-a.gif")!
    let b = URL(string: "https://example.invalid/renamed-b.gif")!
    var images: [(URL, (NSImage?) -> Void)] = []
    var animations: [(NSImage?) -> Void] = []
    var videos: [(NSImage?) -> Void] = []
    var invalidations = 0
    let state = SteamWorkshopPreviewState(loaders: .init(
        image: { url, _, _, done in images.append((url, done)) }, animation: { _, _, done in animations.append(done) },
        video: { _, done in videos.append(done) }, retryDelay: { _ in nil }, invalidate: { _ in invalidations += 1 }))
    var checks: [String: Bool] = [:]
    var pendingVisibility: [(SteamWorkshopPreviewLoadCancellation, (NSImage?) -> Void)] = []
    let visibility = SteamWorkshopPreviewState(loaders: .init(
        image: { _, _, cancellation, done in pendingVisibility.append((cancellation, done)) },
        animation: { _, _, done in done(nil) }, video: { _, done in done(nil) }, retryDelay: { _ in nil }, invalidate: { _ in }))
    visibility.configure(previewURL: a, fallbackVideoURL: nil)
    visibility.setImageDemandActive(false)
    checks["offscreenPendingStillReleasesOnlyItsConsumer"] = pendingVisibility.count == 1 && pendingVisibility[0].0.cancelled
    visibility.configure(previewURL: b, fallbackVideoURL: nil)
    checks["hiddenConfigurationStoresIdentityWithoutStartingWork"] = pendingVisibility.count == 1
    pendingVisibility[0].1(animation)
    visibility.setImageDemandActive(true)
    checks["reshowResumesLatestUnfinishedIdentity"] = pendingVisibility.count == 2 && visibility.image == nil
    pendingVisibility[1].1(still)
    visibility.setImageDemandActive(false)
    visibility.setImageDemandActive(true)
    checks["readyStillSurvivesHideWithoutReload"] = pendingVisibility.count == 2 && visibility.image === still
    visibility.configure(previewURL: a, fallbackVideoURL: nil)
    pendingVisibility.last!.1(nil)
    let afterTerminalFailure = pendingVisibility.count
    visibility.setImageDemandActive(false)
    visibility.setImageDemandActive(true)
    checks["terminalFailureDoesNotRestartOnEveryVisibilityChange"] = pendingVisibility.count == afterTerminalFailure
        && visibility.placeholder == .unavailable

    state.setAnimationActive(true)
    state.configure(previewURL: a, fallbackVideoURL: nil)
    for _ in 0..<50 { state.configure(previewURL: a, fallbackVideoURL: nil); state.setAnimationActive(true) }
    checks["sameSourceCoalescesBeforeReady"] = images.count == 1 && animations.isEmpty
    images[0].1(still)
    for _ in 0..<50 { state.configure(previewURL: a, fallbackVideoURL: nil); state.setAnimationActive(true) }
    checks["sameSourceCoalescesWhileAnimationPending"] = images.count == 1 && animations.count == 1
    state.setAnimationActive(false)
    state.setAnimationActive(true)
    animations[0](animation)
    checks["oldHoverCannotOverwriteNewHover"] = state.image === still && !state.isAnimating
    animations[1](animation)
    checks["newHoverAcceptsOwnAnimation"] = state.image === animation && state.isAnimating
    state.setAnimationActive(false)
    checks["hoverExitImmediatelyRestoresHeldStill"] = state.image === still && state.placeholder == .hidden
    state.setAnimationActive(true)
    animations[2](nil)
    checks["animationFailureKeepsReadyStill"] = state.image === still && state.placeholder == .hidden
    state.reload()
    images.last!.1(nil)
    checks["failedExplicitRefreshKeepsStill"] = state.image === still && state.placeholder == .hidden && invalidations == 1
    let afterReload = images.count
    state.configure(previewURL: a, fallbackVideoURL: nil)
    checks["ordinaryConfigurationAfterReloadIsNoOp"] = images.count == afterReload
    state.configure(previewURL: b, fallbackVideoURL: nil)
    let staleB = images.last!.1
    checks["differentResourceClearsOldImage"] = state.image == nil && state.placeholder == .loading
    state.configure(previewURL: a, fallbackVideoURL: nil)
    staleB(animation)
    checks["previousResourceCannotPublish"] = state.image == nil
    let pendingA = images.last!.1
    state.reset()
    state.configure(previewURL: a, fallbackVideoURL: nil)
    pendingA(animation)
    checks["sameURLAfterReuseRejectsOldGeneration"] = state.image == nil
    images.last!.1(still)
    let video = URL(fileURLWithPath: "/fixture/renamed-video.mov")
    state.configure(previewURL: nil, fallbackVideoURL: video)
    state.configure(previewURL: b, fallbackVideoURL: nil)
    videos[0](animation)
    checks["lateVideoFallbackCannotPublishToNewResource"] = state.image == nil
    images.last!.1(nil)
    checks["noImageFailureShowsUnavailable"] = state.placeholder == .unavailable
    state.setAnimationActive(true)
    state.configure(previewURL: a, fallbackVideoURL: nil)
    images.last!.1(still)
    weak var releasedAnimation: NSImage?
    do {
        let temporary = NSImage(size: NSSize(width: 48, height: 48))
        releasedAnimation = temporary
        animations.last!(temporary)
    }
    checks["activeStateOwnsTemporaryAnimation"] = releasedAnimation != nil
    state.setAnimationActive(false)
    checks["hoverExitReleasesTemporaryAnimation"] = releasedAnimation == nil
    state.configure(previewURL: a, fallbackVideoURL: nil, refreshToken: 1)
    images.last!.1(nil)
    checks["refreshTokenFailureKeepsStill"] = state.image === still && state.placeholder == .hidden
    state.reset()
    checks["resetReleasesAllPresentationImages"] = state.image == nil && !state.isAnimating
    var retryImages: [(NSImage?) -> Void] = []
    let retry = SteamWorkshopPreviewState(loaders: .init(
        image: { _, _, _, done in retryImages.append(done) }, animation: { _, _, done in done(nil) },
        video: { _, done in done(nil) }, retryDelay: { _ in 0 }, invalidate: { _ in }))
    retry.configure(previewURL: a, fallbackVideoURL: nil)
    retryImages[0](nil)
    checks["transientFailureSchedulesBoundedRetry"] = retry.placeholder == .retrying
    let retryWait = Date().addingTimeInterval(1.5)
    while retryImages.count < 2, Date() < retryWait {
        RunLoop.main.run(until: Date().addingTimeInterval(0.01))
    }
    checks["scheduledRetryLoadsAgain"] = retryImages.count == 2
    if retryImages.count == 2 { retryImages[1](still) }
    checks["scheduledRetryCanRecover"] = retry.image === still && retry.placeholder == .hidden
    retry.reload()
    retryImages.last!(nil)
    retry.configure(previewURL: b, fallbackVideoURL: nil)
    let countAfterSwitch = retryImages.count
    RunLoop.main.run(until: Date().addingTimeInterval(0.7))
    checks["sourceSwitchCancelsScheduledRetry"] = retryImages.count == countAfterSwitch
    let exhausted = SteamWorkshopPreviewState(loaders: .init(
        image: { _, _, _, done in done(nil) }, animation: { _, _, done in done(nil) },
        video: { _, done in done(nil) }, retryDelay: { _ in 120 }, invalidate: { _ in }))
    exhausted.configure(previewURL: a, fallbackVideoURL: nil)
    checks["retryBeyondBudgetEndsWithoutSpinner"] = exhausted.placeholder == .unavailable
    var candidates: [(URL, SteamWorkshopPreviewLoadCancellation, (NSImage?) -> Void)] = []
    var candidateAnimations: [URL] = []
    var fallbackImages: [(URL, (NSImage?) -> Void)] = []
    let candidateState = SteamWorkshopPreviewState(loaders: .init(
        image: { url, _, token, done in candidates.append((url, token, done)) },
        animation: { url, _, done in candidateAnimations.append(url); done(animation) },
        video: { url, done in fallbackImages.append((url, done)) }, retryDelay: { _ in nil }, invalidate: { _ in }))
    candidateState.setAnimationActive(true)
    candidateState.configure(previewURL: localVersionURL, fallbackImageURL: a, fallbackVideoURL: nil)
    candidates.last!.2(nil)
    checks["badLocalPreviewTriesRemoteBeforeVideo"] = candidates.map(\.0) == [localVersionURL, a] && fallbackImages.isEmpty
    candidates.last!.2(still)
    checks["remoteFallbackUsesItsOwnAnimation"] = candidateState.image === animation && candidateAnimations == [a]
    candidateState.setAnimationActive(false)
    checks["remoteFallbackKeepsStillAfterHover"] = candidateState.image === still && candidateState.placeholder == .hidden
    candidateState.reset()
    candidateState.configure(previewURL: localVersionURL, fallbackImageURL: a, fallbackVideoURL: nil)
    candidates.last!.2(nil)
    let staleRemote = candidates.last!
    candidateState.configure(previewURL: b, fallbackVideoURL: nil)
    staleRemote.2(still)
    checks["oldFallbackAfterItemSwitchCannotPublish"] = staleRemote.1.cancelled && candidateState.image == nil
    candidates.last!.2(nil)
    candidateState.configure(previewURL: localVersionURL, fallbackImageURL: a, fallbackVideoURL: nil)
    candidates.last!.2(nil); candidates.last!.2(nil)
    checks["badLocalAndRemoteWithoutVideoEndsUnavailable"] = candidateState.image == nil && candidateState.placeholder == .unavailable
    candidateState.configure(previewURL: localVersionURL, fallbackImageURL: a, fallbackVideoURL: video)
    candidates.last!.2(nil); candidates.last!.2(nil)
    checks["videoRunsOnlyAfterBothImagesFail"] = fallbackImages.last?.0 == video
    fallbackImages.last!.1(still)
    let otherVideo = URL(fileURLWithPath: "/fixture/other-video.mov")
    candidateState.configure(previewURL: localVersionURL, fallbackImageURL: a, fallbackVideoURL: otherVideo)
    checks["replacingSuccessfulVideoClearsItsStill"] = candidateState.image == nil
    candidates.last!.2(nil); candidates.last!.2(nil)
    let staleVideo = fallbackImages.last!.1
    candidateState.configure(previewURL: a, fallbackVideoURL: nil)
    staleVideo(animation)
    checks["oldVideoAfterFallbackReplacementCannotPublish"] = candidateState.image == nil
    candidates.last!.2(still)
    let readyLoads = candidates.count
    candidateState.configure(previewURL: a, fallbackVideoURL: video)
    checks["addingVideoDoesNotReloadReadyPrimary"] = candidateState.image === still && candidates.count == readyLoads
    candidateState.configure(previewURL: a, fallbackVideoURL: nil)
    checks["removingVideoDoesNotReloadReadyPrimary"] = candidateState.image === still && candidates.count == readyLoads

    try Data("version-one".utf8).write(to: localVersionURL, options: .atomic)
    let attributes = try FileManager.default.attributesOfItem(atPath: localVersionURL.path)
    let modification = attributes[.modificationDate] as! Date
    let firstKey = steamWorkshopLocalPreviewCacheKey(for: localVersionURL)
    candidateState.configure(previewURL: localVersionURL, fallbackVideoURL: nil)
    let staleLocal = candidates.last!
    try Data("version-two".utf8).write(to: localVersionURL, options: .atomic)
    try FileManager.default.setAttributes([.modificationDate: modification], ofItemAtPath: localVersionURL.path)
    checks["atomicSameSizeSameDateReplacementChangesKey"] = firstKey != steamWorkshopLocalPreviewCacheKey(for: localVersionURL)
    candidateState.configure(previewURL: localVersionURL, fallbackVideoURL: nil)
    staleLocal.2(animation)
    checks["sameURLNewVersionRejectsOldCallback"] = staleLocal.1.cancelled && candidateState.image == nil
    candidates.last!.2(still)
    let versionLoads = candidates.count
    candidateState.configure(previewURL: localVersionURL, fallbackVideoURL: nil)
    checks["sameLocalVersionConfigurationDoesNotReload"] = candidateState.image === still && candidates.count == versionLoads
    return checks
}
