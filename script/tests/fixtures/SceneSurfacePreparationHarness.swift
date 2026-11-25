import AppKit

// The platform and expensive preparation leaves are controlled; coordination,
// cancellation, membership publication and worker/main handoff are production.
final class TestScreen {
    static var screens: [TestScreen] { [] }
    let frame: CGRect
    let backingScaleFactor: CGFloat = 1
    var deviceDescription: [NSDeviceDescriptionKey: Any] { [:] }
    init(_ frame: CGRect) { self.frame = frame }
}
typealias NSScreen = TestScreen
enum SceneDesktopWallpaperHostLaunchError: Error { case cancelled, preparationFailed }
// PRODUCTION_CANCELLATION

// PREPARATION_LEAVES_BEGIN
final class TestTrace: @unchecked Sendable {
    private let lock = NSLock()
    private var events: [String] = []
    func record(_ event: String) { lock.lock(); events.append(event); lock.unlock() }
    var values: [String] { lock.lock(); defer { lock.unlock() }; return events }
}
final class TestPreparationStep: @unchecked Sendable {
    let entered = DispatchSemaphore(value: 0), release = DispatchSemaphore(value: 0)
    let held: Bool, fails: Bool
    let installedDisplayIDs: [CGDirectDisplayID]?
    private let lock = NSLock()
    private var products: [SceneParticlePlaybackState] = []
    init(held: Bool = false, fails: Bool = false, installing: [CGDirectDisplayID]? = nil) {
        self.held = held; self.fails = fails; installedDisplayIDs = installing
    }
    func save(_ values: [SceneParticlePlaybackState]) { lock.lock(); products = values; lock.unlock() }
    var prepared: [SceneParticlePlaybackState] { lock.lock(); defer { lock.unlock() }; return products }
}
final class TestTextureLoader: @unchecked Sendable {
    let trace: TestTrace
    private var evictions = 0
    init(_ trace: TestTrace) { self.trace = trace }
    func evictDecodedCaches() {
        precondition(Thread.isMainThread, "loader evicted before main consumed its products")
        evictions += 1; trace.record("evict-\(evictions)")
    }
}
struct TestBaseImages { let textureLoader: TestTextureLoader }
struct SceneDynamicSnapshot: Equatable { let frameIndex: UInt64; let generation: UInt64 }
struct SceneParticleAudioInput: Equatable { let left: [Float]; let right: [Float]; let generation: UInt64 }
final class SceneAudioSpectrumInbox {
    static let shared = SceneAudioSpectrumInbox()
    var snapshot = SceneParticleAudioInput(left: [0.25], right: [0.5], generation: 7)
    func prepareFrame() -> (snapshot: SceneParticleAudioInput, unused: Bool) { (snapshot, false) }
}
struct TestTopology {
    var particlePlayback: [Int: Int] = [42: 1]
    var destroyedAuthoredLayerIDs: Set<Int> = []
}
final class TestDynamicLayers {
    var value = TestTopology()
    func snapshot() -> TestTopology { value }
}
final class TestCursorProgram {
    var retired: [Set<CGDirectDisplayID>] = []
    func retireSurfaceInputs(_ ids: Set<CGDirectDisplayID>) { retired.append(ids) }
}
final class TestStorageDomain {
    var identities: [String?] = []
    func setStorageScreenIdentity(_ value: String?) throws { identities.append(value) }
}
struct TestVectorProgram { let domain: TestStorageDomain? = TestStorageDomain() }
final class SceneParticlePlaybackState: @unchecked Sendable {
    var hasAudioConsumer = true
    var teardownReasons: [String] = []
    func teardown(reason: String) -> Bool { teardownReasons.append(reason); return true }
}
final class SceneResolvedMaterialRuntimeBridge: @unchecked Sendable {}
struct SceneSurfacePreparationInput {
    let baseImages: TestBaseImages
    let dynamicValues: SceneDynamicSnapshot
    let particlePlayback: [Int: Int]
    let destroyedLayerIDs: Set<Int>
    let audioInput: SceneParticleAudioInput
    let step: TestPreparationStep
    let number: Int
    func prepare(displayIDs: [CGDirectDisplayID], cancellation: SceneWallpaperLaunchCancellation?)
        throws -> [SceneDesktopWallpaperSession.PreparedSurface] {
        precondition(!Thread.isMainThread, "expensive preparation ran on main")
        let trace = baseImages.textureLoader.trace
        trace.record("worker-\(number)")
        try cancellation?.check()
        step.entered.signal()
        if step.held {
            precondition(step.release.wait(timeout: .now() + 5) == .success, "worker release timed out")
        }
        try cancellation?.check()
        if step.fails { throw SceneDesktopWallpaperHostLaunchError.preparationFailed }
        let prepared = displayIDs.map { SceneDesktopWallpaperSession.PreparedSurface(
            displayID: $0, playback: SceneParticlePlaybackState(), materialRuntime: SceneResolvedMaterialRuntimeBridge()) }
        step.save(prepared.map(\.playback))
        trace.record("produced-\(number)")
        return prepared
    }
}
final class SceneDesktopWallpaperLaunchContext {
    let sceneScriptCursorProgram = TestCursorProgram()
    let sceneScriptDynamicLayerRuntime = TestDynamicLayers()
    let propertyVectorScriptProgram = TestVectorProgram()
    let baseImages: TestBaseImages
    let steps: [TestPreparationStep]
    var inputs: [SceneSurfacePreparationInput] = []
#if SCENE_SHUTDOWN_PREPARATION
    var preparedDeviceResources = TestPreparedResources(baseImages: ControlledFontWorker(held: false))
#endif
    init(_ steps: [TestPreparationStep], trace: TestTrace) {
        self.steps = steps; baseImages = TestBaseImages(textureLoader: TestTextureLoader(trace))
    }
#if SCENE_SHUTDOWN_PREPARATION
    init(preparedDeviceResources: TestPreparedResources) {
        self.preparedDeviceResources = preparedDeviceResources
        steps = []; baseImages = TestBaseImages(textureLoader: TestTextureLoader(TestTrace()))
    }
#endif
    func makeSurfacePreparationInput(dynamicValues: SceneDynamicSnapshot, topology: TestTopology,
        audioInput: SceneParticleAudioInput, sceneTime: Double = 0) -> SceneSurfacePreparationInput {
        precondition(Thread.isMainThread && inputs.count < steps.count, "unexpected preparation/retry")
        let number = inputs.count + 1
        let input = SceneSurfacePreparationInput(baseImages: baseImages, dynamicValues: dynamicValues,
            particlePlayback: topology.particlePlayback, destroyedLayerIDs: topology.destroyedAuthoredLayerIDs,
            audioInput: audioInput, step: steps[number - 1], number: number)
        inputs.append(input); baseImages.textureLoader.trace.record("input-\(number)")
        return input
    }
}
struct TestEvaluationTransaction { var committedSnapshot: SceneDynamicSnapshot? = .init(frameIndex: 32, generation: 5) }
struct TestClock {
    var isPaused = false
    func currentSceneTime(hostTime: TimeInterval) -> TimeInterval { 0 }
}
// PREPARATION_LEAVES_END
final class TestWindow {
    var frame: CGRect
    var frameUpdates = 0
    init(_ frame: CGRect) { self.frame = frame }
    func setFrame(_ frame: CGRect, display: Bool, animate: Bool) { self.frame = frame; frameUpdates += 1 }
}
final class TestView {
    var drawableUpdates = 0, outputUpdates = 0
    func updateDrawableSize() { drawableUpdates += 1 }
    func refreshDisplayOutput() { outputUpdates += 1 }
}
enum SceneGraphExecutionResetReason { case surfaceStop }
struct TestInstallationBoundary {
    let preparedIDs: Set<CGDirectDisplayID>, screenIDs: Set<CGDirectDisplayID>
}
@MainActor final class SceneDesktopWallpaperSession {
    final class Surface {
        let window: TestWindow, metalView = TestView()
        var particlePlayback: SceneParticlePlaybackState?
        let materialRuntime: SceneResolvedMaterialRuntimeBridge
        init(_ frame: CGRect, playback: SceneParticlePlaybackState = .init(),
             material: SceneResolvedMaterialRuntimeBridge = .init()) {
            window = TestWindow(frame); particlePlayback = playback; materialRuntime = material
        }
    }
    // PRODUCTION_PREPARATION_TYPES
    static var resolved: [(TestScreen, CGDirectDisplayID)] = []
    static var resolutions = 0
    static var resolvedTopologies: [[SceneScreenTopology]] = []
    var launchContext: SceneDesktopWallpaperLaunchContext?
    var screenTopology: [SceneScreenTopology] = []
    var preparedSurfaceIDs: Set<CGDirectDisplayID> = []
    var surfaces: [CGDirectDisplayID: Surface] = [:]
    var retired: [Surface] = []
    var debugSurfaceReferenceFrames: [CGDirectDisplayID: CGRect] = [:]
    var screenReconciliationWorkItem: DispatchWorkItem?
    var pendingSurfacePreparation: PendingSurfacePreparation?
    var evaluationTransaction = TestEvaluationTransaction(), sceneClock = TestClock()
    var frameTimer: Timer?
    let surfacePreparationQueue = DispatchQueue(label: "test.surface-preparation")
    let retiringSurfaceDrain = DispatchGroup()
    var audioInputs: [Bool?] = [], installedValues: [SceneDynamicSnapshot?] = []
    var installationBoundaries: [TestInstallationBoundary] = []
    var visibilityUpdates = 0, stops = 0, driverStarts = 0
    static func surfaceScreens(topology: [SceneScreenTopology]) -> [(TestScreen, CGDirectDisplayID)] {
        resolutions += 1; resolvedTopologies.append(topology); return resolved
    }
    func updateAudioSpectrumDemand(_ context: SceneDesktopWallpaperLaunchContext, hasParticleAudioConsumer: Bool?) {
        audioInputs.append(hasParticleAudioConsumer)
    }
    nonisolated static func sceneScriptStorageScreenIdentity(_ id: CGDirectDisplayID) -> String? { "screen-\(id)" }
    func teardownSurface(_ surface: Surface, reason: SceneGraphExecutionResetReason) {
        precondition(!surfaces.values.contains { $0 === surface }, "retired owner was still active")
        retired.append(surface)
    }
    func reassertSurfaceVisibility() { visibilityUpdates += 1 }
    func startFrameDriver() { driverStarts += 1 }
    func stop() { stops += 1; launchContext = nil; surfaces.removeAll() }
    private func installPreparedSurfaces(_ prepared: [PreparedSurface], screens: [(TestScreen, CGDirectDisplayID)],
        context: SceneDesktopWallpaperLaunchContext, dynamicValues: SceneDynamicSnapshot?) -> Int {
        precondition(Thread.isMainThread, "installation ran before main consumption")
        installedValues.append(dynamicValues)
        installationBoundaries.append(.init(preparedIDs: Set(prepared.map(\.displayID)), screenIDs: Set(screens.map(\.1))))
        context.baseImages.textureLoader.trace.record("consume-\(context.inputs.count)")
        // The actual App and particle handoff gates exercise installation and
        // command adoption. This leaf returns the scripted installation result;
        // it does not implement the product's obsolete-candidate disposal rule.
        let wanted = Dictionary(uniqueKeysWithValues: screens.map { ($0.1, $0.0) })
        let products = Dictionary(uniqueKeysWithValues: prepared.map { ($0.displayID, $0) })
        let installed = context.steps[context.inputs.count - 1].installedDisplayIDs ?? prepared.map(\.displayID)
        for id in installed {
            let value = products[id]!, screen = wanted[id]!
            surfaces[id] = Surface(screen.frame, playback: value.playback, material: value.materialRuntime)
        }
        return installed.count
    }
    // PRODUCTION_DISPLAY_METHODS
}

@main enum Harness {
    static let live = CGRect(x: 80, y: 40, width: 640, height: 360)
    static func check(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else { fatalError(message) }
    }
    static func wait(_ signal: DispatchSemaphore) async {
        await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                check(signal.wait(timeout: .now() + 5) == .success, "controlled boundary timed out")
                continuation.resume()
            }
        }
    }
    @MainActor static func drain(_ session: SceneDesktopWallpaperSession) async {
        await withCheckedContinuation { continuation in
            session.retiringSurfaceDrain.notify(queue: .main) { continuation.resume() }
        }
    }
    @MainActor static func target(_ ids: [CGDirectDisplayID], _ session: SceneDesktopWallpaperSession,
                                  debounce: Bool = false) {
        SceneDesktopWallpaperSession.resolved = ids.map { (TestScreen(live.offsetBy(dx: CGFloat($0) * 50, dy: 0)), $0) }
        let typed = ids.map { SceneScreenTopology(displayID: $0, frame: .zero, backingScaleFactor: 3) }
        if debounce { session.applyDisplayConfiguration(typed) }
        else {
            session.screenTopology = typed
            _ = session.reconcileSurfaceScreens(SceneDesktopWallpaperSession.resolved, context: session.launchContext!)
        }
    }
    @MainActor static func make(_ ids: [CGDirectDisplayID], steps: [TestPreparationStep] = [])
        -> (SceneDesktopWallpaperSession, SceneDesktopWallpaperLaunchContext, TestTrace) {
        let session = SceneDesktopWallpaperSession(), trace = TestTrace()
        let context = SceneDesktopWallpaperLaunchContext(steps, trace: trace)
        session.launchContext = context
        for id in ids { session.surfaces[id] = .init(live.offsetBy(dx: CGFloat(id) * 50, dy: 0)) }
        session.preparedSurfaceIDs = Set(ids)
        SceneDesktopWallpaperSession.resolutions = 0; SceneDesktopWallpaperSession.resolvedTopologies = []
        return (session, context, trace)
    }
    @MainActor static func geometryAndRemoval() async throws {
        let (session, _, _) = make([1])
        let original = session.surfaces[1]!
        original.window.frame = .zero
        target([1], session, debounce: true)
        check(session.screenTopology.first!.frame == .zero, "typed topology did not publish before debounce")
        try await Task.sleep(nanoseconds: 300_000_000)
        check(SceneDesktopWallpaperSession.resolutions == 1 && session.surfaces[1] === original,
              "stable geometry resolved more than once or replaced its owner")
        check(original.window.frame == live.offsetBy(dx: 50, dy: 0) && original.window.frameUpdates == 1
              && original.metalView.drawableUpdates == 1 && original.metalView.outputUpdates == 1,
              "retained geometry failed to reach existing window/view with the live frame")
        target([1], session, debounce: true); try await Task.sleep(nanoseconds: 300_000_000)
        check(original.window.frameUpdates == 1 && session.audioInputs.isEmpty,
              "same live geometry set a duplicate frame or republished membership")
        session.applyDisplayConfiguration(session.screenTopology + [.init(displayID: 2, frame: .zero, backingScaleFactor: 1)])
        try await Task.sleep(nanoseconds: 300_000_000)
        check(session.surfaces.count == 1 && session.pendingSurfacePreparation == nil,
              "unresolved requested display affected actual stable membership")
        let (shrinking, context, _) = make([1, 2, 3])
        let keeper = shrinking.surfaces[1]!, removed = [shrinking.surfaces[2]!, shrinking.surfaces[3]!]
        shrinking.debugSurfaceReferenceFrames = [1: live, 2: live, 3: live]
        target([1], shrinking, debounce: true); try await Task.sleep(nanoseconds: 300_000_000)
        check(SceneDesktopWallpaperSession.resolutions == 1 && shrinking.surfaces[1] === keeper
              && Set(shrinking.retired.map(ObjectIdentifier.init)) == Set(removed.map(ObjectIdentifier.init)),
              "removed-only changed a survivor or retired another owner")
        check(shrinking.preparedSurfaceIDs == [1] && shrinking.audioInputs.count == 1
              && context.propertyVectorScriptProgram.domain!.identities == ["screen-1"]
              && context.sceneScriptCursorProgram.retired == [Set([2, 3])]
              && Set(shrinking.debugSurfaceReferenceFrames.keys) == [1], "removed consumers were not published once")
    }
    @MainActor static func membershipChanges() async throws {
        let changes: [([CGDirectDisplayID], [CGDirectDisplayID])] = [([1], [1, 2]), ([1, 2], [2, 3]), ([1], [2])]
        for (original, wanted) in changes {
            let step = TestPreparationStep(held: true)
            let (session, context, _) = make(original, steps: [step])
            let owners = session.surfaces
            target(wanted, session, debounce: true)
            await wait(step.entered)
            let removed = Set(owners.keys).subtracting(wanted)
            check(Set(session.retired.map(ObjectIdentifier.init)) == Set(removed.map { ObjectIdentifier(owners[$0]!) }),
                  "incremental membership retired more than its removed difference")
            for id in Set(owners.keys).intersection(wanted) {
                check(session.surfaces[id] === owners[id], "incremental change rebuilt a retained owner")
            }
            if original == [1] && wanted == [2] {
                check(session.surfaces.isEmpty && session.stops == 0 && session.pendingSurfacePreparation != nil,
                      "disjoint preparation revoked the temporarily empty active session")
            }
            let frozen = context.inputs[0]
            check(frozen.dynamicValues == .init(frameIndex: 32, generation: 5)
                  && frozen.particlePlayback == [42: 1] && frozen.destroyedLayerIDs.isEmpty
                  && frozen.audioInput.generation == 7, "job-start typed inputs changed at worker boundary")
            session.evaluationTransaction.committedSnapshot = .init(frameIndex: 48, generation: 9)
            step.release.signal(); await drain(session)
            check(Set(session.surfaces.keys) == Set(wanted) && session.stops == 0,
                  "worker products did not reach exact current membership")
            check(SceneDesktopWallpaperSession.resolutions == 2, "debounce or main consume resolved its input more than once")
            check(session.installedValues == [.init(frameIndex: 48, generation: 9)]
                  && session.preparedSurfaceIDs == Set(session.surfaces.keys), "main did not use the latest committed values")
            check(session.pendingSurfacePreparation == nil && session.driverStarts == 1, "prepared job retained its tail")
            for id in Set(owners.keys).intersection(wanted) {
                check(session.surfaces[id] === owners[id], "main consumption replaced a retained owner")
            }
        }
    }
    @MainActor static func cancellation(at boundary: String) async {
        let first = TestPreparationStep(held: boundary != "before-start"), second = TestPreparationStep()
        let (session, context, trace) = make([1], steps: [first, second])
        let keeper = session.surfaces[1]!
        let queued = DispatchSemaphore(value: 0), releaseQueue = DispatchSemaphore(value: 0)
        if boundary == "before-start" {
            session.surfacePreparationQueue.async { queued.signal(); releaseQueue.wait() }
            await wait(queued)
        }
        target([1, 2], session)
        let pending = session.pendingSurfacePreparation!
        check(session.retiringSurfaceDrain.wait(timeout: .now()) == .timedOut, "queued work was absent from the existing drain")
        if boundary != "before-start" { await wait(first.entered) }
        if boundary == "main-tail" {
            let returned = DispatchSemaphore(value: 0)
            session.surfacePreparationQueue.async { returned.signal() }
            first.release.signal()
            // Main stays here until production queued its finish callback.
            check(returned.wait(timeout: .now() + 5) == .success, "worker tail did not return")
            check(first.prepared.count == 1, "main-tail case did not produce a real candidate")
        }
        if boundary == "in-worker" {
            // The Host's new launch entry cancels this actual token and places
            // its candidate on the existing serial queue before old main retry.
            pending.cancellation.cancel()
            session.surfacePreparationQueue.async { trace.record("candidate-launch") }
        }
        session.evaluationTransaction.committedSnapshot = .init(frameIndex: 64, generation: 12)
        context.sceneScriptDynamicLayerRuntime.value = .init(particlePlayback: [42: 2], destroyedAuthoredLayerIDs: [7])
        target([1, 3], session)
        check(pending.cancellation.isCancelled && session.pendingSurfacePreparation === pending,
              "replacement did not cancel the old job, or released it before main consumption")
        check(context.inputs.count == 1, "next job reused the loader before old main consumption")
        if boundary == "before-start" { releaseQueue.signal() }
        else if boundary == "in-worker" { first.release.signal() }
        await wait(second.entered); await drain(session)
        check(Set(session.surfaces.keys) == [1, 3] && session.surfaces[1] === keeper && session.retired.isEmpty,
              "cancelled job replaced the retained owner or adopted its obsolete display")
        check(context.inputs.count == 2 && context.inputs[1].dynamicValues == .init(frameIndex: 64, generation: 12)
              && context.inputs[1].particlePlayback == [42: 2] && context.inputs[1].destroyedLayerIDs == [7],
              "replacement job did not capture current typed state after old main consumption")
        let events = trace.values
        check(events.firstIndex(of: "evict-1")! < events.firstIndex(of: "input-2")!
              && events.firstIndex(of: "input-2")! < events.firstIndex(of: "worker-2")!
              && events.firstIndex(of: "consume-2")! < events.firstIndex(of: "evict-2")!,
              "shared loader crossed worker/main/next ownership boundaries")
        if boundary == "in-worker" {
            check(events.firstIndex(of: "candidate-launch")! < events.firstIndex(of: "worker-2")!,
                  "active-session retry overtook the candidate launch on the shared serial queue")
        }
        if boundary == "main-tail" {
            check(first.prepared[0].teardownReasons == ["preparationCancelled"], "late cancelled candidate was not retired exactly once")
        } else { check(first.prepared.isEmpty, "cancelled worker produced an adoptable candidate") }
    }
    @MainActor static func finishUsesCurrentMembership() async {
        let step = TestPreparationStep(held: true)
        let (session, context, _) = make([1, 2], steps: [step])
        let removed = session.surfaces[1]!, keeper = session.surfaces[2]!
        target([1, 2, 3], session); await wait(step.entered)
        let returned = DispatchSemaphore(value: 0)
        session.surfacePreparationQueue.async { returned.signal() }
        step.release.signal()
        check(returned.wait(timeout: .now() + 5) == .success, "merged membership worker did not return")
        target([2, 3], session, debounce: true)
        await drain(session)
        check(session.surfaces[2] === keeper && Set(session.surfaces.keys) == [2, 3]
              && session.retired.count == 1 && session.retired[0] === removed,
              "completion did not retire/install its one current resolved membership")
        check(session.audioInputs == [true] && session.preparedSurfaceIDs == [2, 3]
              && context.propertyVectorScriptProgram.domain!.identities == [nil]
              && context.sceneScriptCursorProgram.retired == [Set([1])],
              "completion published an intermediate removed-only audio/storage/membership state")
    }
    @MainActor static func partiallyOverlappingPreparation() async {
        let first = TestPreparationStep(held: true, installing: [3]), second = TestPreparationStep(held: true)
        let (session, context, trace) = make([1], steps: [first, second])
        let keeper = session.surfaces[1]!
        target([1, 2, 3], session); await wait(first.entered)
        let original = session.pendingSurfacePreparation!
        target([1, 3, 4], session)
        check(!original.cancellation.isCancelled && session.pendingSurfacePreparation === original,
              "partial overlap cancelled work still needed by the current topology")
        first.release.signal(); await wait(second.entered)
        check(session.pendingSurfacePreparation!.displayIDs == [4]
              && session.installationBoundaries[0].preparedIDs == [2, 3]
              && session.installationBoundaries[0].screenIDs == [3, 4]
              && first.prepared.count == 2
              && session.surfaces[3]?.particlePlayback === first.prepared[1],
              "partial main consumption lost its current installer boundary or scheduled a covered display")
        let events = trace.values
        check(events.firstIndex(of: "consume-1")! < events.firstIndex(of: "evict-1")!
              && events.firstIndex(of: "evict-1")! < events.firstIndex(of: "input-2")!,
              "partial completion reused its loader before main consumption and eviction")
        second.release.signal(); await drain(session)
        check(session.surfaces[1] === keeper && Set(session.surfaces.keys) == [1, 3, 4]
              && session.retired.isEmpty && context.inputs.count == 2 && session.stops == 0,
              "partial completion replaced a retained owner or prepared a covered display twice")
    }
    @MainActor static func failuresAndDepartedTail() async throws {
        let (failed, context, _) = make([1], steps: [TestPreparationStep(fails: true)])
        let original = failed.surfaces[1]!
        target([1, 2], failed); await drain(failed)
        check(context.inputs.count == 1 && failed.surfaces[1] === original && failed.pendingSurfacePreparation == nil
              && failed.audioInputs.isEmpty && failed.stops == 0, "failed added work retried itself or affected its live peer")
        let (disjoint, disjointContext, _) = make([1], steps: [TestPreparationStep(fails: true)])
        let removed = disjoint.surfaces[1]!
        target([2], disjoint); await drain(disjoint)
        check(disjoint.stops == 1 && disjoint.launchContext == nil && disjoint.surfaces.isEmpty
              && disjointContext.inputs.count == 1 && disjoint.pendingSurfacePreparation == nil
              && disjoint.retired.count == 1 && disjoint.retired[0] === removed,
              "failed all-new preparation retained an empty session or retried its failed target")
        let emptyStep = TestPreparationStep(held: true)
        let (becameEmpty, _, _) = make([1], steps: [emptyStep])
        target([1, 2], becameEmpty); await wait(emptyStep.entered)
        SceneDesktopWallpaperSession.resolved = []
        emptyStep.release.signal(); await drain(becameEmpty)
        check(becameEmpty.stops == 1 && becameEmpty.launchContext == nil && becameEmpty.surfaces.isEmpty
              && becameEmpty.installedValues.isEmpty && becameEmpty.pendingSurfacePreparation == nil
              && SceneDesktopWallpaperSession.resolutions == 1
              && emptyStep.prepared[0].teardownReasons == ["preparationCancelled"],
              "completion with empty live resolution adopted stale surfaces or required another configuration event")
        let step = TestPreparationStep(held: true)
        let (departed, departedContext, _) = make([1], steps: [step])
        target([1, 2], departed); await wait(step.entered)
        departed.pendingSurfacePreparation!.cancellation.cancel()
        departed.launchContext = nil
        check(departed.retiringSurfaceDrain.wait(timeout: .now()) == .timedOut,
              "departed context released a worker before its main tail")
        step.release.signal(); await drain(departed)
        check(departedContext.inputs.count == 1 && departed.pendingSurfacePreparation == nil
              && departed.installedValues.isEmpty && SceneDesktopWallpaperSession.resolutions == 0,
              "departed callback resolved, installed, or started another preparation")
        let (empty, _, _) = make([1])
        target([], empty)
        check(empty.stops == 1 && empty.launchContext == nil && empty.pendingSurfacePreparation == nil,
              "empty actual resolution failed to revoke the session")
        let (queued, _, _) = make([1])
        let untouched = queued.surfaces[1]!
        target([1], queued, debounce: true); queued.launchContext = nil
        try await Task.sleep(nanoseconds: 300_000_000)
        check(SceneDesktopWallpaperSession.resolutions == 0 && untouched.metalView.drawableUpdates == 0,
              "queued debounce touched a departed context")
    }
    @MainActor static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        Task { @MainActor in
            do {
                try await geometryAndRemoval(); try await membershipChanges()
                for boundary in ["before-start", "in-worker", "main-tail"] { await cancellation(at: boundary) }
                await finishUsesCurrentMembership(); await partiallyOverlappingPreparation()
                try await failuresAndDepartedTail()
                print("PASS: production display coordinator, added/mixed/disjoint worker/main/cancellation and loader release order")
                exit(0)
            } catch { fatalError(String(describing: error)) }
        }
        app.run()
    }
}
