// PRODUCTION_FRAME_PREFIX

import Foundation
import CoreFoundation
typealias CGDirectDisplayID = UInt32

enum TransportTime {
    static var now: TimeInterval = 100
}
func CACurrentMediaTime() -> CFTimeInterval { TransportTime.now }

// Deliver production async closures only when the scenario requests it.
final class DispatchQueue {
    static let main = DispatchQueue()
    private var callbacks: [() -> Void] = []
    func async(execute callback: @escaping () -> Void) { callbacks.append(callback) }
    func drain() {
        var deliveries = 0
        while !callbacks.isEmpty {
            deliveries += 1
            precondition(deliveries < 100, "unbounded transport dispatch")
            callbacks.removeFirst()()
        }
    }
}

final class Timer {
    let fireTime: TimeInterval
    private let callback: (Timer) -> Void
    private(set) var isValid = true
    init(timeInterval: TimeInterval, repeats: Bool, block: @escaping (Timer) -> Void) {
        precondition(!repeats)
        fireTime = TransportTime.now + timeInterval
        callback = block
    }
    func invalidate() { isValid = false }
    func fire() {
        precondition(isValid)
        isValid = false
        callback(self)
    }
}

final class RunLoop {
    enum Mode { case common }
    static let main = RunLoop()
    private var timers: [Timer] = []
    func add(_ timer: Timer, forMode: Mode) { timers.append(timer) }
    var activeCount: Int { timers.filter(\.isValid).count }
    @discardableResult func fireNext() -> Bool {
        timers.removeAll { !$0.isValid }
        guard let index = timers.indices.min(by: { timers[$0].fireTime < timers[$1].fireTime }) else {
            return false
        }
        let timer = timers.remove(at: index)
        TransportTime.now = max(TransportTime.now, timer.fireTime)
        timer.fire()
        DispatchQueue.main.drain()
        return true
    }
}

final class MTLCommandBuffer {
    enum Status { case notEnqueued, committed, completed, error }
    var status: Status = .notEnqueued
    var error: Error?
    private var callbacks: [(MTLCommandBuffer) -> Void] = []
    func addCompletedHandler(_ callback: @escaping (MTLCommandBuffer) -> Void) {
        precondition(status == .notEnqueued)
        callbacks.append(callback)
    }
    func commit() {
        precondition(status == .notEnqueued)
        status = .committed
    }
    func complete(_ succeeded: Bool) {
        precondition(status == .committed)
        status = succeeded ? .completed : .error
        if !succeeded { error = NSError(domain: "controlled-metal-completion", code: 1) }
        let deliveries = callbacks
        callbacks.removeAll()
        deliveries.forEach { $0(self) }
    }
}

struct SceneMetalRenderer {}
struct SceneResolvedMaterialFrameTargetPlan {}
struct SceneResolvedMaterialRuntimeBridge { struct FramePreparationRequest {} }
struct SceneResolvedMaterialFrameResourceBundle {}
enum SceneDesktopWallpaperHost { static let usesDebugEvidenceWindow = false }
enum SceneFramePerformanceTelemetry { static let debugEvidence: Int? = nil }
struct PlaybackPerformanceProfile { var maxFPS = 60 }
enum SceneGraphExecutionResetReason { case testTeardown }
final class WorkItem { func cancel() {} }
final class Window {
    var closes = 0
    func orderOut(_ sender: Any?) {}
    func close() { closes += 1 }
}
final class VideoProviders {
    var identities: [Int: UUID] = [:]
    var commits = 0, discards = 0
    func sourceIncarnations(for layerIDs: Set<Int>, deviceRegistryID: UInt64) -> Set<UUID> {
        Set(layerIDs.compactMap { identities[$0] })
    }
    func discardPreparedFrame() { discards += 1 }
    func pause(sceneTime: Double, hostTime: Double) {}
    func resume(sceneTime: Double, hostTime: Double) {}
    func commitPreparedFrame() { commits += 1 }
}
final class SoundProviders { func pause() {}; func resume() {} }
// Shortcut delivery/scopes are outside the controlled frame transport. Keep
// their teardown leaves available without replacing the production teardown.
final class UserShortcutInput { func revoke() {} }
final class SceneDynamicTextTextureStore {
    struct Snapshot { let generation: Int }
    var generation = 0, snapshotReads = 0
    var updates: [Int] = []
    var updatedLayers: [Int] = [], updatedFields: [Int: Set<Int>] = [:]
    var retiredAuthoredLayerIDs: Set<Int> = []
    func snapshot() -> Snapshot { snapshotReads += 1; return .init(generation: generation) }
    func update(from snapshot: Int, dynamicLayers: [Int], destroyedAuthoredLayerIDs: Set<Int>,
                dynamicTextFieldsByLayerID: [Int: Set<Int>]) {
        updates.append(snapshot)
        updatedLayers = dynamicLayers; updatedFields = dynamicTextFieldsByLayerID
        retiredAuthoredLayerIDs = destroyedAuthoredLayerIDs
    }
}

enum SceneMediaThumbnailInbox { struct Snapshot { let generation: UInt64 } }
final class SceneMediaThumbnailTextureStore {
    struct Snapshot { var generation: UInt64 = 0; var pendingGeneration: UInt64? }
    var publication = Snapshot(), updates: [UInt64] = []
    var onUpdate: (() -> Void)?
    func snapshot() -> Snapshot { publication }
    func update(from input: SceneMediaThumbnailInbox.Snapshot) {
        updates.append(input.generation); onUpdate?()
    }
}

final class SceneMetalView {
    enum Plan { case prepared, synchronousDrop, deferred, cancelled }
    var onRenderInvalidated: (() -> Void)?
    var preparedTextSnapshot: SceneDynamicTextTextureStore.Snapshot?
    var submittedTextSnapshot: SceneDynamicTextTextureStore.Snapshot?
    var onRender: (() -> Void)?
    struct SimulationFrame {
        struct Timing { var frameIndex: UInt64 = 7 }
        var timing = Timing()
        var mediaInputGeneration: UInt64 = 0
        var mediaThumbnail = SceneMediaThumbnailTextureStore.Snapshot()
    }
    struct Device { let registryID: UInt64 = 1 }
    let metalDevice = Device()
    var videoPresentation: SceneMetalRenderer.InitialVideoPresentation?
    var presentationFlags: [Bool] = []
    var plan: Plan = .prepared
    var draws = 0, commits = 0, cancels = 0
    var publicationCommits = 0, publicationDiscards = 0
    var drawnTextGenerations: [Int] = []
    var drawnFrameIndices: [UInt64] = []
    var drawnMediaGenerations: [UInt64] = []
    var buffers: [MTLCommandBuffer] = []
    // Retain superseded candidates so identity tests do not pass merely because
    // a weak capture has already become nil.
    var candidates: [SceneMetalRenderer.PreparedFrame] = []
    func renderFrame(simulationFrame: SimulationFrame?, dynamicTextSnapshot: SceneDynamicTextTextureStore.Snapshot?,
                     collectsInitialVideoReadiness: Bool,
                     performanceTelemetry: Int?) -> SceneMetalRenderer.FrameOutcome {
        draws += 1
        drawnFrameIndices.append(simulationFrame!.timing.frameIndex)
        drawnMediaGenerations.append(simulationFrame!.mediaThumbnail.generation)
        preparedTextSnapshot = dynamicTextSnapshot
        drawnTextGenerations.append(dynamicTextSnapshot?.generation ?? -1)
        onRender?()
        if plan == .synchronousDrop { return .dropped(reasonCode: "controlled-sync-failure") }
        if plan == .deferred { return .deferred(reasonCode: "controlled-in-flight") }
        let buffer = MTLCommandBuffer()
        let candidate = SceneMetalRenderer.PreparedFrame(commandBuffer: buffer,
            initialVideoPresentation: collectsInitialVideoReadiness ? (videoPresentation ?? .init()) : nil,
            submit: { [self] present in commits += 1; presentationFlags.append(present); buffer.commit() },
            cancel: { [self] in cancels += 1 })
        buffers.append(buffer)
        candidates.append(candidate)
        if plan == .cancelled { candidate.cancel() }
        return .prepared(candidate)
    }
    func commitPreparedMaterialAssetFrame() { publicationCommits += 1 }
    func commitPreparedFrameTexturePublication() {}
    func discardPreparedMaterialAssetFrame() { publicationDiscards += 1 }
    func discardPreparedFrameTexturePublication() {}
    // TEXT_FRAME_METHODS
    func invalidateResolvedMaterialRuntime(reason: SceneGraphExecutionResetReason) {}
}

final class SceneDesktopWallpaperSession {
    final class Surface {
        let window = Window()
        let metalView = SceneMetalView()
        // The frozen scheduler only observes owner retirement, not pose work.
        var puppetPlaybackStates: [Int: Int] = [17: 1]
        var simulationFrame: SceneMetalView.SimulationFrame? = .init()
        var didSubmitSimulationFrame = false
        var pendingPausedFrame: SceneMetalRenderer.PreparedFrame?
        var lastSubmittedPresentationSources: Set<UUID> = []
        var videoSwitchDeadline: TimeInterval?
        func teardownParticlePlayback(reason: SceneGraphExecutionResetReason) {}
    }
    var sceneClock = SceneClock(hostTime: 0)
    var launchContext: Int? = 1
    var dynamicTextTextures: SceneDynamicTextTextureStore? = .init()
    var mediaThumbnailTextures: SceneMediaThumbnailTextureStore? = .init()
    var pendingProviderUpdate: (dynamicValues: Int, dynamicLayers: [Int],
        destroyedAuthoredLayerIDs: Set<Int>, dynamicTextFieldsByLayerID: [Int: Set<Int>],
        mediaInput: SceneMediaThumbnailInbox.Snapshot)?
    struct ProviderTopology { let dynamicLayers: [Int]; let destroyedAuthoredLayerIDs: Set<Int> }
    struct ProviderLaunchContext {
        struct FrameSchema { let dynamicTextFieldsByLayerID: [Int: Set<Int>] }
        let frameSchema: FrameSchema
    }
    func adoptProviderInput(dynamicValues: Int, layerTopology: ProviderTopology,
                            launchContext: ProviderLaunchContext, mediaInput: SceneMediaThumbnailInbox.Snapshot) {
// PROVIDER_INPUT_ADOPTION
    }
    var surfaces: [CGDirectDisplayID: Surface] = [:]
    var preparedSurfaceIDs: Set<CGDirectDisplayID> = []
    var initialPresentationCohort = SceneInitialPresentationCohort()
    var frameTimer: Timer?
    var frameDriverDeadline: CFTimeInterval?
    var pausedFrameRetryDeadline: CFTimeInterval?
    var onFirstFrameCompletion: ((CGDirectDisplayID, Bool) -> Void)?
    var videoTextureSourceRegistry: VideoProviders?
    var soundPlaybackRegistry: SoundProviders?
    let userShortcutInput = UserShortcutInput()
    var isVisible = true
    var isOutputActive = true
    var initialVideoPreparation: WorkItem?
    var performanceProfile = PlaybackPerformanceProfile()
    var screenReconciliationWorkItem: WorkItem?
    var screenTopology: [Int] = [], rebuiltTopology: [Int] = []
    var drainStarted = false
    var retiredSurfaces = 0
    func cancelPendingUserTextureUpdates() {}
    func removePointerEventMonitors() {}
    func releaseUserShortcutScopes() {}
    func retireSurface(_ surface: Surface) { retiredSurfaces += 1 }
    func publishText(_ generation: Int) {
        dynamicTextTextures!.generation = generation
        textTexturePublicationDidChange(dynamicTextTextures!)
    }
    func attach(_ screenID: CGDirectDisplayID = 1) -> Surface {
        let surface = Surface()
        let metalView = surface.metalView
        surfaces[screenID] = surface
        preparedSurfaceIDs = Set(surfaces.keys)
        // INVALIDATION
        return surface
    }
    // METHODS
}

// PRODUCTION_FRAME_TYPES

@main enum Harness {
    static func fixture() -> (SceneDesktopWallpaperSession,
                              SceneDesktopWallpaperSession.Surface, SceneClock.State) {
        let owner = SceneDesktopWallpaperSession()
        let surface = owner.attach()
        owner.setPlaybackPaused(true)
        return (owner, surface, owner.sceneClock.snapshot())
    }
    static func frozen(_ owner: SceneDesktopWallpaperSession, _ before: SceneClock.State) {
        precondition(owner.sceneClock.snapshot() == before, "paused recovery advanced SceneClock")
        for surface in owner.surfaces.values {
            precondition(surface.metalView.drawnFrameIndices.allSatisfy { $0 == surface.simulationFrame?.timing.frameIndex })
        }
    }
    static func complete(_ view: SceneMetalView, _ index: Int, _ succeeded: Bool) {
        view.buffers[index].complete(succeeded)
        DispatchQueue.main.drain()
    }
    static func stopped(_ owner: SceneDesktopWallpaperSession) {
        precondition(owner.frameTimer == nil && owner.frameDriverDeadline == nil)
        precondition(RunLoop.main.activeCount == 0)
    }
    static func success() {
        let (owner, surface, before) = fixture()
        owner.startFrameDriver()
        precondition(surface.metalView.draws == 1 && surface.didSubmitSimulationFrame)
        precondition(surface.pendingPausedFrame === surface.metalView.candidates[0])
        complete(surface.metalView, 0, true)
        precondition(surface.pendingPausedFrame == nil)
        precondition(surface.metalView.publicationCommits == 1)
        stopped(owner)
        TransportTime.now += 5
        precondition(!RunLoop.main.fireNext() && surface.metalView.draws == 1)
        // A real surface invalidation requests exactly one new frozen image.
        surface.metalView.onRenderInvalidated?()
        DispatchQueue.main.drain()
        precondition(surface.metalView.draws == 2)
        complete(surface.metalView, 1, true)
        stopped(owner)
        precondition(!RunLoop.main.fireNext())
        frozen(owner, before)
    }
    static func failOnce() {
        let (owner, surface, before) = fixture()
        var callbacks: [Bool] = []
        owner.onFirstFrameCompletion = { _, succeeded in
            precondition(surface.didSubmitSimulationFrame,
                         "original first-frame callback must run before failed admission is revoked")
            callbacks.append(succeeded)
        }
        owner.startFrameDriver()
        let deadline = owner.pausedFrameRetryDeadline
        complete(surface.metalView, 0, false)
        precondition(!surface.didSubmitSimulationFrame && surface.pendingPausedFrame == nil)
        precondition(owner.frameTimer?.isValid == true)
        precondition(owner.pausedFrameRetryDeadline == deadline)
        precondition(RunLoop.main.fireNext())
        precondition(surface.metalView.draws == 2 && surface.didSubmitSimulationFrame)
        complete(surface.metalView, 1, true)
        // An already-visible session retries its paused transport locally;
        // candidate-only Host delivery is exercised separately below.
        precondition(callbacks.isEmpty)
        stopped(owner)
        precondition(!RunLoop.main.fireNext())
        frozen(owner, before)
    }
    static func asynchronousExpiry() {
        let (owner, surface, before) = fixture()
        owner.startFrameDriver()
        let deadline = owner.pausedFrameRetryDeadline!
        var attempts = 0
        repeat {
            attempts += 1
            precondition(attempts < 100, "async failure renewed the paused retry window")
            // Each GPU result arrives later than submission; this also catches
            // deriving a fresh deadline from each completion time.
            TransportTime.now += 0.04
            complete(surface.metalView, surface.metalView.buffers.count - 1, false)
            precondition(owner.pausedFrameRetryDeadline == deadline)
            frozen(owner, before)
        } while RunLoop.main.fireNext()
        precondition(attempts > 1 && TransportTime.now >= deadline)
        precondition(!surface.didSubmitSimulationFrame && surface.pendingPausedFrame == nil)
        stopped(owner)
        let draws = surface.metalView.draws
        TransportTime.now += 2
        precondition(!RunLoop.main.fireNext() && surface.metalView.draws == draws)
    }
    static func synchronousExpiry(_ plan: SceneMetalView.Plan) {
        let (owner, surface, before) = fixture()
        surface.metalView.plan = plan
        owner.startFrameDriver()
        let deadline = owner.pausedFrameRetryDeadline!
        var fired = 0
        while RunLoop.main.fireNext() {
            fired += 1
            precondition(fired < 600, "sync failure renewed the paused retry window")
            precondition(owner.pausedFrameRetryDeadline == deadline)
            frozen(owner, before)
        }
        precondition(fired > 1 && TransportTime.now >= deadline)
        precondition(!surface.didSubmitSimulationFrame && surface.pendingPausedFrame == nil)
        precondition(surface.metalView.commits == 0)
        precondition(surface.metalView.publicationDiscards == surface.metalView.draws)
        stopped(owner)
        frozen(owner, before)
    }
    static func oldCandidate() {
        let (owner, surface, before) = fixture()
        owner.startFrameDriver()
        let old = surface.metalView.candidates[0]
        surface.metalView.onRenderInvalidated?()
        DispatchQueue.main.drain()
        let current = surface.metalView.candidates[1]
        precondition(old !== current && surface.pendingPausedFrame === current)
        complete(surface.metalView, 1, true)
        complete(surface.metalView, 0, false)
        precondition(surface.didSubmitSimulationFrame && surface.pendingPausedFrame == nil)
        precondition(surface.metalView.draws == 2)
        stopped(owner)
        frozen(owner, before)

        // A fresh invalidation can encounter busy admission before it has a
        // replacement candidate. The previous completion then arrives while
        // the existing timer is waiting to draw the newest frozen input.
        func completionDuringBusy(_ oldSucceeded: Bool) {
            let (busyOwner, busySurface, busyBefore) = fixture()
            let view = busySurface.metalView
            busyOwner.startFrameDriver()
            let previous = view.candidates[0]
            let previousDeadline = busyOwner.pausedFrameRetryDeadline!
            TransportTime.now += 0.3
            view.plan = .deferred
            view.onRenderInvalidated?()
            DispatchQueue.main.drain()
            let currentDeadline = busyOwner.pausedFrameRetryDeadline!
            precondition(currentDeadline > previousDeadline)
            precondition(view.draws == 2 && !busySurface.didSubmitSimulationFrame)
            precondition(busySurface.pendingPausedFrame === previous)
            precondition(busyOwner.frameTimer?.isValid == true)
            let waitingTimer = busyOwner.frameTimer
            TransportTime.now += 0.4
            complete(view, 0, oldSucceeded)
            precondition(!busySurface.didSubmitSimulationFrame,
                         "old success suppressed the newest frozen image")
            precondition(busySurface.pendingPausedFrame == nil)
            precondition(busyOwner.pausedFrameRetryDeadline == currentDeadline,
                         "old failure extended the new invalidation's retry window")
            precondition(busyOwner.frameTimer?.isValid == true)
            if oldSucceeded {
                precondition(busyOwner.frameTimer === waitingTimer,
                             "old success replaced the latest input's retry")
            }
            view.plan = .prepared
            precondition(RunLoop.main.fireNext())
            precondition(view.draws == 3 && view.commits == 2)
            precondition(busySurface.pendingPausedFrame === view.candidates[1])
            complete(view, 1, true)
            precondition(busySurface.didSubmitSimulationFrame)
            stopped(busyOwner)
            frozen(busyOwner, busyBefore)
        }
        completionDuringBusy(true)
        completionDuringBusy(false)
    }
    static func replacedSurface() {
        let (owner, old, before) = fixture()
        var deliveries = 0
        owner.onFirstFrameCompletion = { _, _ in deliveries += 1 }
        owner.startFrameDriver()
        let current = owner.attach()
        owner.startFrameDriver()
        complete(current.metalView, 0, true)
        complete(old.metalView, 0, false)
        old.metalView.onRenderInvalidated?()
        DispatchQueue.main.drain()
        precondition(deliveries == 0 && current.didSubmitSimulationFrame)
        precondition(current.pendingPausedFrame == nil && current.metalView.draws == 1)
        stopped(owner)
        frozen(owner, before)
    }
    static func teardown() {
        let (owner, surface, before) = fixture()
        var deliveries = 0
        owner.onFirstFrameCompletion = { _, _ in deliveries += 1 }
        owner.startFrameDriver()
        owner.teardownSurfaces(clearContext: false, reason: .testTeardown)
        precondition(owner.surfaces.isEmpty && owner.pausedFrameRetryDeadline == nil)
        precondition(owner.retiredSurfaces == 1 && surface.window.closes == 1)
        precondition(surface.puppetPlaybackStates.isEmpty, "teardown retained CPU Puppet owners")
        complete(surface.metalView, 0, false)
        surface.metalView.onRenderInvalidated?()
        DispatchQueue.main.drain()
        precondition(deliveries == 0 && surface.metalView.draws == 1)
        stopped(owner)
        frozen(owner, before)
    }
    static func callbackTeardown() {
        let (owner, surface, before) = fixture()
        owner.isVisible = false
        var deliveries = 0
        owner.onFirstFrameCompletion = { _, succeeded in
            precondition(!succeeded && surface.didSubmitSimulationFrame)
            deliveries += 1
            owner.teardownSurfaces(clearContext: false, reason: .testTeardown)
        }
        owner.startFrameDriver()
        complete(surface.metalView, 0, false)
        precondition(deliveries == 1 && owner.surfaces.isEmpty)
        precondition(owner.pausedFrameRetryDeadline == nil)
        // Revalidate after the original callback: a retired surface must not
        // be marked failed or cause a driver to restart.
        precondition(surface.didSubmitSimulationFrame)
        stopped(owner)
        frozen(owner, before)
    }
    static func multipleSurfaces() {
        let (owner, healthy, before) = fixture()
        let failed = owner.attach(2)
        owner.startFrameDriver()
        complete(healthy.metalView, 0, true)
        complete(failed.metalView, 0, false)
        precondition(healthy.didSubmitSimulationFrame && !failed.didSubmitSimulationFrame)
        precondition(RunLoop.main.fireNext())
        precondition(healthy.metalView.draws == 1 && failed.metalView.draws == 2)
        complete(failed.metalView, 1, true)
        precondition(owner.surfaces.values.allSatisfy(\.didSubmitSimulationFrame))
        stopped(owner)
        frozen(owner, before)
    }
    static func resumePause() {
        let (owner, surface, _) = fixture()
        owner.startFrameDriver()
        let old = surface.metalView.candidates[0]
        // Resume uses the real pause transition but has no live launch to drive
        // the intentionally trapped normal simulation branch.
        owner.launchContext = nil
        TransportTime.now += 0.1
        owner.setPlaybackPaused(false)
        precondition(surface.pendingPausedFrame == nil && owner.pausedFrameRetryDeadline == nil)
        TransportTime.now += 0.1
        owner.setPlaybackPaused(true)
        let before = owner.sceneClock.snapshot()
        owner.launchContext = 1
        surface.metalView.onRenderInvalidated?()
        DispatchQueue.main.drain()
        precondition(surface.pendingPausedFrame !== old)
        complete(surface.metalView, 1, true)
        complete(surface.metalView, 0, false)
        precondition(surface.didSubmitSimulationFrame && surface.pendingPausedFrame == nil)
        stopped(owner)
        frozen(owner, before)
    }
    static func cancellation() {
        let buffer = MTLCommandBuffer()
        var completions = 0, submissions = 0, cancellations = 0
        let candidate = SceneMetalRenderer.PreparedFrame(commandBuffer: buffer,
            submit: { _ in submissions += 1; buffer.commit() }, cancel: { cancellations += 1 })
        candidate.whenCompleted { _ in completions += 1 }
        candidate.cancel()
        candidate.cancel()
        let outcome = SceneMetalRenderer.submitPreparedFrame(.prepared(candidate))
        precondition(!outcome.isSubmitted && !candidate.isReady)
        precondition(buffer.status == .notEnqueued)
        DispatchQueue.main.drain()
        precondition(submissions == 0 && cancellations == 1 && completions == 0)
        synchronousExpiry(.cancelled)
    }
    static func candidate(_ screens: Int = 1) ->
        (SceneDesktopWallpaperSession, [SceneDesktopWallpaperSession.Surface], SceneClock.State) {
        let owner = SceneDesktopWallpaperSession()
        owner.isVisible = false
        let surfaces = (0..<screens).map { owner.attach(CGDirectDisplayID($0 + 1)) }
        owner.setPlaybackPaused(true)
        return (owner, surfaces, owner.sceneClock.snapshot())
    }
    static func heldPublications(_ screens: Int) {
        let (owner, surfaces, before) = candidate(screens)
        var callbacks: [String] = []
        owner.onFirstFrameCompletion = { callbacks.append("\($0):\($1)") }
        owner.startFrameDriver()
        precondition(owner.initialPresentationCohort.isHeld)
        precondition(!owner.initialPresentationCohort.hasDelivered)
        owner.pendingProviderUpdate = (77, [], [19], [19: [4]], .init(generation: 77))
        for surface in surfaces { surface.simulationFrame?.mediaThumbnail.pendingGeneration = 0 }
        owner.publishText(2)
        owner.publishText(3)
        owner.enqueueMediaThumbnailPublication(owner.mediaThumbnailTextures!)
        DispatchQueue.main.drain()
        precondition(surfaces.allSatisfy { $0.metalView.draws == 1 },
                     "unadopted publication replaced the qualified candidate")
        precondition(owner.initialPresentationCohort.isHeld && callbacks.isEmpty)
        precondition(owner.dynamicTextTextures!.updates.isEmpty && owner.pendingProviderUpdate?.destroyedAuthoredLayerIDs == [19],
                     "held output consumed a newer topology's pending text retirement")
        precondition(surfaces.allSatisfy(\.didSubmitSimulationFrame))
        stopped(owner)
        for (index, surface) in surfaces.enumerated() {
            complete(surface.metalView, 0, true)
            if index < screens - 1 {
                precondition(callbacks.isEmpty, "partial GPU cohort reached Host")
                owner.publishText(4)
                DispatchQueue.main.drain()
            }
        }
        precondition(callbacks == (1...screens).map { "\($0):true" })
        precondition(owner.initialPresentationCohort.hasDelivered)
        // Parent may delay promotion. More ready data cannot silently replace
        // its delivered drawable or turn publication into a Host failure.
        owner.publishText(5)
        owner.enqueueMediaThumbnailPublication(owner.mediaThumbnailTextures!)
        DispatchQueue.main.drain()
        precondition(callbacks.count == screens)
        precondition(owner.initialPresentationCohort.isHeld)
        precondition(surfaces.allSatisfy { $0.metalView.draws == 1 })
        precondition(surfaces.allSatisfy { $0.metalView.submittedTextSnapshot?.generation == 0 })
        precondition(owner.dynamicTextTextures!.updates.isEmpty && owner.pendingProviderUpdate?.destroyedAuthoredLayerIDs == [19])
        frozen(owner, before)
        stopped(owner)
    }
    static func realInvalidation() {
        let (owner, surfaces, before) = candidate(2)
        let a = surfaces[0].metalView, b = surfaces[1].metalView
        var callbacks: [String] = []
        owner.onFirstFrameCompletion = { callbacks.append("\($0):\($1)") }
        owner.startFrameDriver()
        complete(a, 0, true)
        precondition(callbacks.isEmpty)
        b.onRenderInvalidated?()
        DispatchQueue.main.drain()
        precondition(a.draws == 2 && b.draws == 2)
        precondition(owner.initialPresentationCohort.isHeld)
        // A-old success cannot combine with B-new, even on the same frameIndex.
        complete(b, 0, true)
        complete(b, 1, true)
        precondition(callbacks.isEmpty)
        complete(a, 1, true)
        precondition(callbacks == ["1:true", "2:true"])
        precondition(owner.initialPresentationCohort.hasDelivered)
        a.onRenderInvalidated?()
        DispatchQueue.main.drain()
        precondition(callbacks == ["1:true", "2:true", "1:false"],
                     "real invalidation after delivery must reach original Host failure")
        precondition(!owner.initialPresentationCohort.isHeld)
        precondition(!owner.initialPresentationCohort.hasDelivered)
        precondition(a.draws == 2 && b.draws == 2)
        stopped(owner)
        frozen(owner, before)
    }
    static func candidateGPUFailure(_ stale: Bool) {
        let (owner, surfaces, before) = candidate()
        let view = surfaces[0].metalView
        var callbacks: [Bool] = []
        owner.onFirstFrameCompletion = { _, succeeded in
            callbacks.append(succeeded)
            if !succeeded { owner.teardownSurfaces(clearContext: false, reason: .testTeardown) }
        }
        owner.startFrameDriver()
        if stale {
            view.onRenderInvalidated?()
            DispatchQueue.main.drain()
            precondition(view.draws == 2)
            complete(view, 1, true)
            precondition(callbacks == [true] && owner.initialPresentationCohort.hasDelivered)
        }
        owner.publishText(1)
        DispatchQueue.main.drain()
        precondition(callbacks == (stale ? [true] : []) && !owner.surfaces.isEmpty,
                     "publication reached Host before actual GPU failure")
        precondition(view.draws == (stale ? 2 : 1),
                     "publication replaced candidate before GPU failure")
        complete(view, 0, false)
        precondition(callbacks == (stale ? [true, false] : [false]),
                     "publication or stale success token swallowed actual GPU failure")
        precondition(owner.surfaces.isEmpty && !owner.initialPresentationCohort.isHeld)
        stopped(owner)
        frozen(owner, before)
    }
    static func activePausedText() {
        let (owner, surface, before) = fixture()
        let view = surface.metalView
        owner.startFrameDriver()
        complete(view, 0, true)
        stopped(owner)
        owner.publishText(8)
        DispatchQueue.main.drain()
        precondition(view.draws == 2 && view.drawnTextGenerations == [0, 8],
                     "active paused text was routed into media-only refresh or never adopted")
        complete(view, 1, true)
        precondition(view.submittedTextSnapshot?.generation == 8)
        // A previously active store may deliver after the Session replaced it.
        let retiredStore = owner.dynamicTextTextures!
        owner.dynamicTextTextures = .init()
        owner.textTexturePublicationDidChange(retiredStore)
        DispatchQueue.main.drain()
        precondition(view.draws == 2)
        owner.publishText(9)
        precondition(view.drawnTextGenerations == [0, 8, 9])
        complete(view, 2, true)
        let retiredMedia = owner.mediaThumbnailTextures!
        surface.simulationFrame?.mediaInputGeneration = 9
        retiredMedia.publication = .init(generation: 9)
        owner.enqueueMediaThumbnailPublication(retiredMedia)
        owner.mediaThumbnailTextures = .init()
        DispatchQueue.main.drain()
        precondition(view.draws == 3)
        stopped(owner)
        frozen(owner, before)
    }
    static func textPending() {
        for plan: SceneMetalView.Plan in [.deferred, .synchronousDrop, .cancelled] {
            let (owner, surface, before) = fixture(), view = surface.metalView
            let store = owner.dynamicTextTextures!
            owner.adoptProviderInput(dynamicValues: 17,
                layerTopology: .init(dynamicLayers: [23], destroyedAuthoredLayerIDs: [19, 21]),
                launchContext: .init(frameSchema: .init(dynamicTextFieldsByLayerID: [23: [4]])),
                mediaInput: .init(generation: 17))
            view.plan = plan; owner.startFrameDriver()
            precondition(owner.pendingProviderUpdate?.dynamicValues == 17 && store.updates.isEmpty)
            precondition(owner.pendingProviderUpdate?.destroyedAuthoredLayerIDs == [19, 21]
                         && store.retiredAuthoredLayerIDs.isEmpty)
            precondition(owner.mediaThumbnailTextures!.updates.isEmpty)
            precondition(!owner.refreshPausedMediaPublications(.init(generation: 17)))
            precondition(!owner.refreshPausedMediaPublications(.init(generation: 0, pendingGeneration: 1)))
            view.plan = .prepared
            precondition(RunLoop.main.fireNext())
            precondition(owner.pendingProviderUpdate == nil && store.updates == [17])
            precondition(store.updatedLayers == [23] && store.updatedFields == [23: [4]])
            precondition(store.retiredAuthoredLayerIDs == [19, 21])
            complete(view, view.buffers.count - 1, true)
            _ = owner.renderSurfaces()
            precondition(store.updates == [17] && owner.mediaThumbnailTextures!.updates == [17])
            stopped(owner); frozen(owner, before)
        }
        for rejected: SceneMetalView.Plan in [.deferred, .synchronousDrop] {
            let (owner, a, before) = fixture(), b = owner.attach(2)
            let store = owner.dynamicTextTextures!
            b.metalView.plan = rejected
            owner.adoptProviderInput(dynamicValues: 29,
                layerTopology: .init(dynamicLayers: [31], destroyedAuthoredLayerIDs: [27]),
                launchContext: .init(frameSchema: .init(dynamicTextFieldsByLayerID: [31: [5]])),
                mediaInput: .init(generation: 29))
            let media = owner.mediaThumbnailTextures!
            media.publication = .init(generation: 29)
            media.onUpdate = { owner.enqueueMediaThumbnailPublication(media) }
            for surface in [a, b] {
                surface.simulationFrame?.mediaInputGeneration = 29
                surface.metalView.onRender = { store.generation += 1 }
            }
            let result = owner.renderSurfaces()
            if case .busy = result { precondition(rejected == .deferred) }
            else if case .dropped = result { precondition(rejected == .synchronousDrop) }
            else { preconditionFailure("partial paused attempt hid its failed surface") }
            precondition(store.snapshotReads == 1 && store.generation == 2)
            precondition([a, b].allSatisfy { $0.metalView.drawnTextGenerations == [0] },
                         "worker readiness changed the frozen attempt between surfaces")
            precondition(store.updates == [29] && owner.pendingProviderUpdate == nil,
                         "a submitted surface must consume pending input despite busy/dropped return")
            precondition(store.retiredAuthoredLayerIDs == [27])
            precondition(a.metalView.submittedTextSnapshot?.generation == 0 && a.metalView.preparedTextSnapshot == nil)
            precondition(b.metalView.submittedTextSnapshot == nil && b.metalView.preparedTextSnapshot == nil)
            precondition(media.updates == [29] && a.metalView.draws == 1 && b.metalView.draws == 1,
                         "synchronous producer notification reentered the post-submit attempt")
            b.metalView.plan = .prepared
            complete(a.metalView, 0, true)
            precondition(media.updates == [29] && [a, b].allSatisfy(\.didSubmitSimulationFrame))
            stopped(owner); frozen(owner, before)
        }
    }
    static func frozenFrameCohort() {
        for rejection in ["missing-frame", "mixed-frame", "generation", "members", "pending"] {
            let (owner, a, before) = fixture(), b = owner.attach(2)
            for surface in [a, b] {
                surface.simulationFrame?.mediaInputGeneration = 31
                surface.simulationFrame?.mediaThumbnail.pendingGeneration = 31
                surface.didSubmitSimulationFrame = true
            }
            let second = b.simulationFrame
            switch rejection {
            case "missing-frame": b.simulationFrame = nil
            case "mixed-frame": b.simulationFrame?.timing.frameIndex = 8
            case "generation": b.simulationFrame?.mediaInputGeneration = 32
            case "members": owner.preparedSurfaceIDs = [1]
            default: break
            }
            let publication = SceneMediaThumbnailTextureStore.Snapshot(generation: 31,
                pendingGeneration: rejection == "pending" ? 32 : nil)
            precondition(!owner.refreshPausedMediaPublications(publication))
            precondition(a.simulationFrame?.mediaThumbnail.generation == 0
                && a.simulationFrame?.mediaThumbnail.pendingGeneration == 31
                && [a, b].allSatisfy(\.didSubmitSimulationFrame), "partial frozen cohort was published")
            b.simulationFrame = second
            owner.preparedSurfaceIDs = [1, 2]
            precondition(owner.refreshPausedMediaPublications(.init(generation: 31)))
            owner.startFrameDriver()
            precondition([a, b].allSatisfy {
                $0.metalView.drawnFrameIndices == [7] && $0.metalView.drawnMediaGenerations == [31]
            }, "View did not consume the accepted frozen frame")
            for surface in [a, b] { complete(surface.metalView, 0, true) }
            stopped(owner); frozen(owner, before)
        }
    }
    static let videoA = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    static let videoB = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
    static let videoC = UUID(uuidString: "00000000-0000-0000-0000-000000000003")!
    static func seededVideo() -> (SceneDesktopWallpaperSession, SceneDesktopWallpaperSession.Surface, SceneClock.State, VideoProviders) {
        let (owner, surface, before) = fixture()
        let providers = VideoProviders()
        providers.identities = [1: videoA, 2: videoB, 3: videoC]
        owner.videoTextureSourceRegistry = providers
        surface.metalView.videoPresentation = .init(readyLayerIDs: [1])
        owner.startFrameDriver()
        precondition(surface.lastSubmittedPresentationSources == [videoA])
        complete(surface.metalView, 0, true)
        stopped(owner)
        return (owner, surface, before, providers)
    }
    static func videoSwitchRecovery() {
        let (owner, surface, before, providers) = seededVideo()
        let view = surface.metalView, healthy = owner.attach(2)
        healthy.metalView.videoPresentation = .init(readyLayerIDs: [1])
        view.videoPresentation = .init(pendingLayerIDs: [2], pendingSurfaceLayerIDs: [2])
        view.onRenderInvalidated?(); DispatchQueue.main.drain()
        let deadline = surface.videoSwitchDeadline!
        precondition(view.presentationFlags == [true, false] && !surface.didSubmitSimulationFrame)
        precondition(view.commits == 2 && view.publicationCommits == 2 && providers.commits == 2)
        precondition(surface.lastSubmittedPresentationSources == [videoA] && view.publicationDiscards == 0)
        complete(view, 1, true); complete(healthy.metalView, 0, true)
        TransportTime.now = deadline - 0.05; view.plan = .deferred
        precondition(RunLoop.main.fireNext() && surface.videoSwitchDeadline == deadline)
        precondition(providers.discards == 1 && healthy.metalView.draws == 1)
        TransportTime.now = deadline - 0.04; view.plan = .prepared
        view.videoPresentation = .init(pendingLayerIDs: [3], pendingSurfaceLayerIDs: [3])
        precondition(RunLoop.main.fireNext() && surface.videoSwitchDeadline == deadline)
        precondition(view.presentationFlags.last == false && !surface.didSubmitSimulationFrame)
        complete(view, 2, true)
        view.videoPresentation = .init(readyLayerIDs: [3])
        precondition(RunLoop.main.fireNext() && view.presentationFlags.last == true)
        precondition(surface.lastSubmittedPresentationSources == [videoC] && surface.videoSwitchDeadline == nil)
        complete(view, 3, true)
        precondition(healthy.metalView.draws == 1 && providers.commits == 4)
        stopped(owner); frozen(owner, before)
    }
    static func videoSwitchExpiry() {
        let (owner, surface, before, _) = seededVideo()
        let view = surface.metalView
        view.videoPresentation = .init(pendingLayerIDs: [2], pendingSurfaceLayerIDs: [2])
        view.onRenderInvalidated?(); DispatchQueue.main.drain()
        let deadline = surface.videoSwitchDeadline!
        complete(view, 1, true)
        TransportTime.now = deadline
        precondition(RunLoop.main.fireNext() && view.presentationFlags.last == true)
        precondition(!surface.didSubmitSimulationFrame && owner.frameTimer != nil,
                     "spent presentation wait stopped paused resource retry")
        complete(view, 2, true)
        view.videoPresentation = .init(readyLayerIDs: [2])
        precondition(RunLoop.main.fireNext())
        complete(view, 3, true)
        precondition(surface.didSubmitSimulationFrame && surface.lastSubmittedPresentationSources == [videoB])
        stopped(owner); frozen(owner, before)
    }
    static func videoSwitchRejected(_ kind: String) {
        let (owner, surface, before, _) = seededVideo()
        let view = surface.metalView
        view.videoPresentation = .init(pendingLayerIDs: [2], pendingSurfaceLayerIDs: [2])
        view.onRenderInvalidated?(); DispatchQueue.main.drain()
        let deadline = surface.videoSwitchDeadline!
        TransportTime.now = deadline - 0.05
        if kind == "gpu" { complete(view, 1, false) }
        else {
            complete(view, 1, true)
            view.plan = kind == "cancel" ? .cancelled : .synchronousDrop
            precondition(RunLoop.main.fireNext())
        }
        precondition(surface.videoSwitchDeadline.map { $0 <= TransportTime.now } == true)
        view.plan = .prepared
        view.videoPresentation = .init(pendingLayerIDs: [3], pendingSurfaceLayerIDs: [3])
        precondition(RunLoop.main.fireNext() && view.presentationFlags.last == true)
        precondition(!surface.didSubmitSimulationFrame && owner.frameTimer != nil)
        complete(view, view.buffers.count - 1, true)
        view.videoPresentation = .init(readyLayerIDs: [3])
        precondition(RunLoop.main.fireNext())
        complete(view, view.buffers.count - 1, true)
        stopped(owner); frozen(owner, before)
    }
    static func submittedVideoSet() {
        let (owner, surface, before, _) = seededVideo()
        let view = surface.metalView
        for ids: Set<Int> in [[1, 2], [1]] {
            view.videoPresentation = .init(readyLayerIDs: ids)
            view.onRenderInvalidated?(); DispatchQueue.main.drain()
            precondition(surface.lastSubmittedPresentationSources == (ids.count == 2 ? [videoA, videoB] : [videoA]))
        }
        // Older GPU callbacks have not run; optional C cannot revive retired B.
        view.videoPresentation = .init(readyLayerIDs: [1], pendingLayerIDs: [3], pendingSurfaceLayerIDs: [3])
        view.onRenderInvalidated?(); DispatchQueue.main.drain()
        precondition(view.presentationFlags.allSatisfy { $0 } && surface.videoSwitchDeadline == nil)
        precondition(!surface.didSubmitSimulationFrame && owner.frameTimer != nil)
        complete(view, 1, true); complete(view, 2, true); complete(view, 3, true)
        precondition(surface.lastSubmittedPresentationSources == [videoA])
        view.videoPresentation = .init(readyLayerIDs: [1], pendingLayerIDs: [3])
        precondition(RunLoop.main.fireNext())
        precondition(surface.didSubmitSimulationFrame && surface.videoSwitchDeadline == nil,
                     "startup-only pending escaped into surface switch scope")
        complete(view, 4, true)
        stopped(owner); frozen(owner, before)
    }
    static func main() {
        let scenario = CommandLine.arguments[1]
        switch scenario {
        case "success": success()
        case "failOnce": failOnce()
        case "asyncExpiry": asynchronousExpiry()
        case "syncExpiry": synchronousExpiry(.synchronousDrop)
        case "busyExpiry": synchronousExpiry(.deferred)
        case "oldCandidate": oldCandidate()
        case "replacedSurface": replacedSurface()
        case "teardown": teardown()
        case "callbackTeardown": callbackTeardown()
        case "multipleSurfaces": multipleSurfaces()
        case "resumePause": resumePause()
        case "cancellation": cancellation()
        case "heldText": heldPublications(1)
        case "heldTextTwoSurfaces": heldPublications(2)
        case "realInvalidation": realInvalidation()
        case "candidateGPUFailure": candidateGPUFailure(false)
        case "staleGPUFailureAfterDelivery": candidateGPUFailure(true)
        case "activePausedText": activePausedText()
        case "textPending": textPending()
        case "frozenFrameCohort": frozenFrameCohort()
        case "videoSwitchRecovery": videoSwitchRecovery()
        case "videoSwitchExpiry": videoSwitchExpiry()
        case "videoSwitchGPUFailure": videoSwitchRejected("gpu")
        case "videoSwitchCancel": videoSwitchRejected("cancel")
        case "videoSwitchDrop": videoSwitchRejected("drop")
        case "submittedVideoSet": submittedVideoSet()
        default: fatalError("unknown scenario")
        }
        print("paused-frame-recovery-pass: \(scenario)")
    }
}
