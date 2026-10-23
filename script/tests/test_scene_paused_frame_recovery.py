"""Run production frozen-frame scheduling with controlled transport completion.

The existing method-extraction scaffold executes the driver, text-publication
callback, invalidation, surface submission, cohort and PreparedFrame owners.
Only the normal simulation branch is replaced by a trap. Timer, dispatch,
raster readiness and Metal completion are hand-controlled transport boundaries;
no scheduler or publication policy is reproduced.
"""
from pathlib import Path
import subprocess
import tempfile
import unittest

from script.tests.test_steam_library_interactions import method

ROOT = Path(__file__).resolve().parents[2]
SCENE = ROOT / "MyWallpaperX/Core/SteamWorkshopScene"
SESSION = SCENE / "Runtime/Session"


STUBS = r'''
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
enum Counter {
    case frameAttempts, cpuFrameMicros, framesRendered, framesBusy, framesDropped, framesInactive
}
enum Phase { case firstVisibleFrame }
struct ScenePerformanceCounterHub {
    static let shared = ScenePerformanceCounterHub()
    func bump(_ counter: Counter) {}
    func add(_ counter: Counter, _ value: UInt64) {}
    func recordLaunchPhase(_ phase: Phase, uptimeMicros: UInt64) {}
    static func nowUptimeMicros() -> UInt64 { 0 }
    static func micros(since: TimeInterval) -> UInt64 { 0 }
}
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
    func discardPreparedFrame() {}
    func pause(sceneTime: Double, hostTime: Double) {}
    func resume(sceneTime: Double, hostTime: Double) {}
    func commitPreparedFrame() {}
}
final class SoundProviders { func pause() {}; func resume() {} }
// Shortcut delivery/scopes are outside the controlled frame transport. Keep
// their teardown leaves available without replacing the production teardown.
final class UserShortcutInput { func revoke() {} }
final class SceneDynamicTextTextureStore {
    var generation = 0
}

final class SceneMetalView {
    // INVALIDATION_TYPE
    enum Plan { case prepared, synchronousDrop, deferred, cancelled }
    var onRenderInvalidated: ((RenderInvalidation) -> Void)?
    var dynamicTextTextures: SceneDynamicTextTextureStore? = .init()
    var textPublication: ((SceneDynamicTextTextureStore) -> Void)?
    let hasSimulationFrame = true
    let simulationFrameIndex: UInt64 = 7
    var plan: Plan = .prepared
    var draws = 0, commits = 0, cancels = 0
    var publicationCommits = 0, publicationDiscards = 0
    var drawnTextGenerations: [Int] = []
    var buffers: [MTLCommandBuffer] = []
    // Retain superseded candidates so identity tests do not pass merely because
    // a weak capture has already become nil.
    var candidates: [SceneMetalRenderer.PreparedFrame] = []
    init() {
        // TEXT_PUBLICATION
    }
    func publishText(_ generation: Int) {
        dynamicTextTextures!.generation = generation
        textPublication?(dynamicTextTextures!)
    }
    func renderFrame(collectsInitialVideoReadiness: Bool,
                     performanceTelemetry: Int?) -> SceneMetalRenderer.FrameOutcome {
        draws += 1
        if plan == .synchronousDrop { return .dropped(reasonCode: "controlled-sync-failure") }
        if plan == .deferred { return .deferred(reasonCode: "controlled-in-flight") }
        let buffer = MTLCommandBuffer()
        let candidate = SceneMetalRenderer.PreparedFrame(commandBuffer: buffer,
            initialVideoPresentation: collectsInitialVideoReadiness ? .init() : nil,
            submit: { [self] in commits += 1; buffer.commit() },
            cancel: { [self] in cancels += 1 })
        drawnTextGenerations.append(dynamicTextTextures!.generation)
        buffers.append(buffer)
        candidates.append(candidate)
        if plan == .cancelled { candidate.cancel() }
        return .prepared(candidate)
    }
    func commitPreparedMaterialAssetFrame() { publicationCommits += 1 }
    func commitPreparedFrameTexturePublication() {}
    func commitPreparedMediaThumbnailUpdate() {}
    func commitPreparedDynamicTextUpdate() {}
    func discardPreparedMaterialAssetFrame() { publicationDiscards += 1 }
    func discardPreparedFrameTexturePublication() {}
    func discardPreparedMediaThumbnailUpdate() {}
    func discardPreparedDynamicTextUpdate() {}
    func invalidateResolvedMaterialRuntime(reason: SceneGraphExecutionResetReason) {}
    func teardownParticlePlayback(reason: SceneGraphExecutionResetReason) {}
}

final class SceneDesktopWallpaperSession {
    final class Surface {
        let window = Window()
        let metalView = SceneMetalView()
        var didSubmitSimulationFrame = false
        var pendingPausedFrame: SceneMetalRenderer.PreparedFrame?
    }
    var sceneClock = SceneClock(hostTime: 0)
    var launchContext: Int? = 1
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
    var initialUserVideoPreparation: WorkItem?
    var performanceProfile = PlaybackPerformanceProfile()
    var screenReconciliationWorkItem: WorkItem?
    var screenTopology: [Int] = [], rebuiltTopology: [Int] = []
    var drainStarted = false
    var retiredSurfaces = 0
    func cancelPendingUserTextureUpdates() {}
    func removePointerEventMonitors() {}
    func releaseUserShortcutScopes() {}
    func retireSurface(_ surface: Surface) { retiredSurfaces += 1 }
    // No new media input. The production driver still chooses its frozen path.
    func refreshPausedMediaPublications() -> Bool { false }
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
'''


SCENARIOS = r'''
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
        surface.metalView.onRenderInvalidated?(.surface)
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
        surface.metalView.onRenderInvalidated?(.surface)
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
            view.onRenderInvalidated?(.surface)
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
        old.metalView.onRenderInvalidated?(.surface)
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
        complete(surface.metalView, 0, false)
        surface.metalView.onRenderInvalidated?(.surface)
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
        surface.metalView.onRenderInvalidated?(.surface)
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
            submit: { submissions += 1; buffer.commit() }, cancel: { cancellations += 1 })
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
        for surface in surfaces {
            // Execute MetalView's real asynchronous text publication callback,
            // including its store identity check, then Session's real callback.
            surface.metalView.publishText(2)
            surface.metalView.publishText(3)
            surface.metalView.onRenderInvalidated?(.mediaPublication)
        }
        DispatchQueue.main.drain()
        precondition(surfaces.allSatisfy { $0.metalView.draws == 1 },
                     "unadopted publication replaced the qualified candidate")
        precondition(owner.initialPresentationCohort.isHeld && callbacks.isEmpty)
        stopped(owner)
        for (index, surface) in surfaces.enumerated() {
            complete(surface.metalView, 0, true)
            if index < screens - 1 {
                precondition(callbacks.isEmpty, "partial GPU cohort reached Host")
                surface.metalView.publishText(4)
                DispatchQueue.main.drain()
            }
        }
        precondition(callbacks == (1...screens).map { "\($0):true" })
        precondition(owner.initialPresentationCohort.hasDelivered)
        // Parent may delay promotion. More ready data cannot silently replace
        // its delivered drawable or turn publication into a Host failure.
        for surface in surfaces {
            surface.metalView.publishText(5)
            surface.metalView.onRenderInvalidated?(.mediaPublication)
        }
        DispatchQueue.main.drain()
        precondition(callbacks.count == screens)
        precondition(owner.initialPresentationCohort.isHeld)
        precondition(surfaces.allSatisfy { $0.metalView.draws == 1 })
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
        b.onRenderInvalidated?(.surface)
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
        a.onRenderInvalidated?(.surface)
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
            view.onRenderInvalidated?(.surface)
            DispatchQueue.main.drain()
            precondition(view.draws == 2)
            complete(view, 1, true)
            precondition(callbacks == [true] && owner.initialPresentationCohort.hasDelivered)
        }
        view.publishText(1)
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
        view.publishText(8)
        DispatchQueue.main.drain()
        precondition(view.draws == 2 && view.drawnTextGenerations == [0, 8],
                     "active paused text was routed into media-only refresh or never adopted")
        complete(view, 1, true)
        // A retired raster store must not invalidate the live view.
        view.textPublication?(SceneDynamicTextTextureStore())
        DispatchQueue.main.drain()
        precondition(view.draws == 2)
        stopped(owner)
        frozen(owner, before)
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
        default: fatalError("unknown scenario")
        }
        print("paused-frame-recovery-pass: \(scenario)")
    }
}
'''


def production_harness(sources=None):
    """Accept frozen source bytes for causal old/new checks; normal tests use live owners."""
    def read(relative):
        return sources[relative] if sources is not None else (SCENE / relative).read_text()

    driver = read("Runtime/Session/SceneDesktopWallpaperSession+FrameDriver.swift")
    session = read("Runtime/Session/SceneDesktopWallpaperSession.swift")
    submission = read("Runtime/Session/SceneDesktopWallpaperSession+SurfaceSubmission.swift")
    pause = read("Runtime/Session/SceneDesktopWallpaperSession+VideoProviders.swift")
    teardown = read("Runtime/Session/SceneDesktopWallpaperSession+SurfaceTeardown.swift")
    context = read("Runtime/Frame/SceneFrameContext.swift")
    outcome = read("Rendering/Frame/SceneMetalRenderer+FrameOutcome.swift")
    view = read("Rendering/Frame/SceneMetalView.swift")
    # Execute the complete frozen branch. Entering ordinary clock/VM work is a
    # test failure, rather than a fake implementation that could conceal it.
    frame = method(driver, "private func renderFrame()")
    frame = frame[:frame.index("        promotePendingDeferredLayerVisibilityIfReady()")]
    frame += '        fatalError("normal cadence/VM branch entered during paused recovery")\n    }'
    # Surface identity and retry cancellation belong to this production prefix;
    # the later cursor/audio/VM context disposal is outside this transport test.
    retirement = method(teardown, "func teardownSurfaces(")
    marker = "        surfaces.removeAll()"
    retirement = retirement[:retirement.index(marker) + len(marker)] + "\n    }"
    methods = "\n".join([
        method(driver, "private var sceneFrameInterval:").replace("private var", "var"),
        method(driver, "private var sceneBusyFrameRetryInterval:").replace("private var", "var"),
        *(method(driver, signature) for signature in [
            "func startFrameDriver(", "func scheduleFrameDriver(", "private func armFrameDriver(",
        ]),
        *(method(submission, signature) for signature in [
            "func renderSurfaces(", "var awaitsInitialPresentation:",
            "private func observeSurfaceCompletion(", "private func deliverInitialPresentationCohort(",
        ]),
        frame,
        method(pause, "func setPlaybackPaused("),
        retirement,
    ])
    harness = STUBS.replace("// INVALIDATION\n", method(session, "metalView.onRenderInvalidated =") + "\n")
    harness = harness.replace("// INVALIDATION_TYPE", method(view, "enum RenderInvalidation {"))
    text_callback = method(view, "onPublication: { [weak self] store in")
    harness = harness.replace("// TEXT_PUBLICATION", "textPublication =" + text_callback.split(":", 1)[1])
    harness = harness.replace("// METHODS", methods)
    return "\n".join([
        method(driver, "enum SceneFrameDriverAttempt"),
        read("Runtime/Session/SceneInitialPresentationCohort.swift"),
        harness,
        method(context, "nonisolated struct SceneFrameTiming:"),
        method(context, "nonisolated struct SceneClock {"),
        outcome.replace("import Metal\n", ""),
        SCENARIOS,
    ])


class ScenePausedFrameRecoveryTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temporary = tempfile.TemporaryDirectory(prefix="mwx-paused-frame-recovery-")
        cls.addClassCleanup(cls.temporary.cleanup)
        directory = Path(cls.temporary.name)
        source = directory / "Harness.swift"
        source.write_text(production_harness())
        cls.binary = directory / "harness"
        result = subprocess.run([
            "xcrun", "swiftc", "-parse-as-library", "-module-cache-path",
            str(directory / "module-cache"), str(source), "-o", str(cls.binary),
        ], capture_output=True, text=True, timeout=60)
        if result.returncode:
            raise AssertionError(result.stdout + result.stderr)

    def run_scenario(self, name):
        result = subprocess.run([str(self.binary), name], capture_output=True, text=True, timeout=10)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("paused-frame-recovery-pass: " + name, result.stdout)

    def test_success_draws_once_per_invalidation(self):
        self.run_scenario("success")

    def test_one_async_failure_retries_then_stops(self):
        self.run_scenario("failOnce")

    def test_repeated_async_failures_do_not_extend_deadline(self):
        self.run_scenario("asyncExpiry")

    def test_synchronous_failures_expire(self):
        self.run_scenario("syncExpiry")

    def test_busy_admission_expire(self):
        self.run_scenario("busyExpiry")

    def test_old_candidate_failure_preserves_new_success(self):
        self.run_scenario("oldCandidate")

    def test_reused_display_id_ignores_retired_surface(self):
        self.run_scenario("replacedSurface")

    def test_teardown_ignores_late_completion_and_invalidation(self):
        self.run_scenario("teardown")

    def test_first_frame_callback_teardown_precedes_retry_revalidation(self):
        self.run_scenario("callbackTeardown")

    def test_multiple_displays_only_retry_failed_surface(self):
        self.run_scenario("multipleSurfaces")

    def test_resume_pause_ignores_old_failure(self):
        self.run_scenario("resumePause")

    def test_cancelled_candidate_has_no_completion_and_retry_expires(self):
        self.run_scenario("cancellation")

    def test_text_and_media_publications_preserve_qualified_and_delivered_candidate(self):
        self.run_scenario("heldText")

    def test_two_surface_publications_cannot_replace_or_partially_deliver_cohort(self):
        self.run_scenario("heldTextTwoSurfaces")

    def test_real_invalidation_rejects_cross_attempt_success_and_fails_delivered_host(self):
        self.run_scenario("realInvalidation")

    def test_candidate_gpu_failure_survives_text_publication(self):
        self.run_scenario("candidateGPUFailure")

    def test_old_submitted_gpu_failure_still_reaches_host_after_newer_delivery(self):
        self.run_scenario("staleGPUFailureAfterDelivery")

    def test_active_paused_text_adopts_latest_store_without_advancing_simulation(self):
        self.run_scenario("activePausedText")


if __name__ == "__main__":
    unittest.main()
