import Foundation

// Control-plane fixture only. Loader, Session transaction and live state are
// production methods. File IO, publication/Metal envelopes and Registry/Source
// are scripted boundaries; they do not prove decoder, prime or GPU behavior.
nonisolated final class MTLTexture {
    let name: String
    let width = 9
    let height = 5
    init(_ name: String) { self.name = name }
}
nonisolated final class MTLDevice { let registryID: UInt64; init(_ id: UInt64 = 1) { registryID = id } }
nonisolated final class SceneTextureUploadCommandQueue {}
nonisolated final class SceneTextureDecodeCacheBudget { init(maximumBytes: Int = 0) {} }
nonisolated enum SceneTextureLoadPurpose: String, Hashable {
    case premultipliedColor, straightAlbedo, preservedChannels, mask, normal, flow
    var reportToken: String { rawValue }
}
nonisolated struct SceneUserPropertyTextureIdentity: Hashable {
    let propertyKey: String
    let purpose: SceneTextureLoadPurpose
    init?(propertyKey: String, purpose: SceneTextureLoadPurpose) {
        guard !propertyKey.isEmpty else { return nil }
        self.propertyKey = propertyKey; self.purpose = purpose
    }
}
nonisolated enum SceneFrameTextureIdentity: Equatable { case materialUserProperty(SceneUserPropertyTextureIdentity) }
nonisolated struct SceneTextureCandidate { let texture: MTLTexture; let purpose: SceneTextureLoadPurpose }
nonisolated struct SceneTextureProviderPublication {
    let requestIdentity: SceneFrameTextureIdentity
    let candidate: SceneTextureCandidate
    let contentGeneration: UInt64
    var texture: MTLTexture { candidate.texture }
    var isComplete: Bool { !texture.name.contains("incomplete") }
    var generationIsCurrent: Bool { contentGeneration > 0 }
}
nonisolated enum SceneTextureProviderState { case ready(SceneTextureProviderPublication), absent, pending, unavailable }
nonisolated enum SceneTextureLoadOutcome {
    case loaded(MTLTexture), unsupportedFormat, unsupportedTexFormat, texNoEmbeddedImage, texContainsVideoPayload
    case resourceReadFailed(any Error)
    case decodeFailed(String), textureAllocationFailed(width: Int, height: Int)
}
nonisolated enum SceneTextureCandidateLoadOutcome { case loaded(SceneTextureCandidate), failed(SceneTextureLoadOutcome) }
nonisolated final class SceneTextureLoader {
    struct SourceKey: Hashable { let path: String }
    let uploadCommandQueue: SceneTextureUploadCommandQueue
    let decodeCacheBudget: SceneTextureDecodeCacheBudget
    private static let lock = NSLock()
    private static var calls = 0
    private static var mainCalls = 0
    init(uploadCommandQueue: SceneTextureUploadCommandQueue = .init(), decodeCacheBudget: SceneTextureDecodeCacheBudget = .init()) {
        self.uploadCommandQueue = uploadCommandQueue; self.decodeCacheBudget = decodeCacheBudget
    }
    static func counts() -> (Int, Int) { lock.lock(); defer { lock.unlock() }; return (calls, mainCalls) }
    static func currentSourceKey(for url: URL) -> SourceKey? { .init(path: url.path) }
    static func currentSourceKey(for input: SceneResourceView.FileInput) throws -> SourceKey? {
        .init(path: input.diagnosticPath)
    }
    func sourceKey(for input: SceneResourceView.FileInput,
                   checkCancellation: (() throws -> Void)? = nil) throws -> SourceKey? {
        try checkCancellation?()
        return try Self.currentSourceKey(for: input)
    }
    func loadDirectImageCandidates(from input: SceneResourceView.FileInput, purposes: Set<SceneTextureLoadPurpose>, device: MTLDevice,
                                   isCancelled: () -> Bool, checkCancellation: (() throws -> Void)? = nil) throws -> [SceneTextureLoadPurpose: SceneTextureCandidateLoadOutcome] {
        try checkCancellation?()
        let url = URL(fileURLWithPath: input.diagnosticPath)
        Self.lock.lock(); Self.calls += 1; if Thread.isMainThread { Self.mainCalls += 1 }; Self.lock.unlock()
        if url.lastPathComponent.hasPrefix("slow") { Thread.sleep(forTimeInterval: 0.05) }
        return Dictionary(uniqueKeysWithValues: purposes.map { purpose in
            let outcome: SceneTextureCandidateLoadOutcome
            if url.lastPathComponent == "broken.png" || (url.lastPathComponent == "partial.png" && purpose == .normal) {
                outcome = .failed(.decodeFailed("injected"))
            } else {
                outcome = .loaded(.init(texture: MTLTexture(url.lastPathComponent + ":" + purpose.rawValue), purpose: purpose))
            }
            return (purpose, outcome)
        })
    }
}
nonisolated final class SceneVideoOwnedFile {
    let url: URL
    init(_ url: URL) { self.url = url }
    static func snapshot(
        from url: URL, cacheDirectory: URL, maximumBytes: Int = 1_073_741_824,
        isCancelled: () -> Bool = { false }, isSourceCurrent: () throws -> Bool
    ) throws -> SceneVideoOwnedFile {
        guard !isCancelled(), try isSourceCurrent(),
              !url.lastPathComponent.contains("snapshot-fail") else { throw CancellationError() }
        // No real file is read or written. The original name controls only
        // this fixture's scripted asynchronous boundary.
        return .init(cacheDirectory.appendingPathComponent(UUID().uuidString + "-" + url.lastPathComponent))
    }
}
nonisolated enum SceneVideoPayloadPreparation {
    static func supportsLocalVideo(url: URL) -> Bool {
        ["mp4", "mov", "m4v"].contains(url.pathExtension.lowercased())
    }
}
nonisolated final class VideoStopState: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    func stop() { lock.lock(); defer { lock.unlock() }; if count == 0 { count = 1 } }
    var stops: Int { lock.lock(); defer { lock.unlock() }; return count }
}
final class SceneVideoTextureSource {
    let identity: SceneUserPropertyTextureIdentity
    let filename: String
    private let stopState = VideoStopState()
    var releasePrime = false
    var primeStarted = false
    var primeCancelled = false
    var primed = false
    var activated = false
    var activationSceneTime: Double?
    var activationPaused: Bool?
    init(_ declaration: SceneUserPropertyVideoDeclaration) {
        identity = declaration.identity
        filename = declaration.file.url.lastPathComponent
    }
    nonisolated func stop() { stopState.stop() }
    var stopCount: Int { stopState.stops }
    func primeInitialFrame(isCancelled: @escaping () -> Bool = { false }) async -> Bool {
        primeStarted = true
        repeat {
            if isCancelled() || Task.isCancelled || stopCount != 0 {
                primeCancelled = true
                return false
            }
            if !filename.contains("manual-prime") || releasePrime { break }
            do { try await Task.sleep(for: .milliseconds(5)) }
            catch { primeCancelled = true; return false }
        } while true
        guard !filename.contains("bad-prime") else { return false }
        primed = true
        return true
    }
    func hasCompletePrimedPublication(for property: SceneUserPropertyTextureIdentity) -> Bool {
        primed && stopCount == 0 && identity == property
    }
    func activatePrimed(sceneTime: Double, hostTime: Double, isPaused: Bool) -> Bool {
        guard hasCompletePrimedPublication(for: identity), !activated else { return false }
        activated = true
        activationSceneTime = sceneTime
        activationPaused = isPaused
        return true
    }
}
final class SceneVideoTextureSourceRegistry {
    final class UserPropertyCandidate {
        let source: SceneVideoTextureSource
        let declaration: SceneUserPropertyVideoDeclaration
        var transferred = false
        init(_ declaration: SceneUserPropertyVideoDeclaration) {
            self.declaration = declaration
            source = SceneVideoTextureSource(declaration)
        }
        deinit { if !transferred { source.stop() } }
    }
    var issuedSources: [SceneVideoTextureSource] = []
    var active: [SceneUserPropertyTextureIdentity: SceneVideoTextureSource] = [:]
    var retiredKeys: [Set<String>] = []
    var allowAdoption = true
    func makeUserPropertyCandidate(
        declaration: SceneUserPropertyVideoDeclaration, device: MTLDevice
    ) -> UserPropertyCandidate? {
        guard !declaration.file.url.lastPathComponent.contains("factory-fail") else { return nil }
        let candidate = UserPropertyCandidate(declaration)
        issuedSources.append(candidate.source)
        return candidate
    }
    func canAdoptUserPropertyCandidate(_ candidate: UserPropertyCandidate) -> Bool {
        allowAdoption && candidate.source.hasCompletePrimedPublication(for: candidate.declaration.identity)
    }
    func adoptUserPropertyCandidate(
        _ candidate: UserPropertyCandidate, sceneTime: Double, hostTime: Double, isPaused: Bool
    ) -> Bool {
        guard canAdoptUserPropertyCandidate(candidate),
              candidate.source.activatePrimed(sceneTime: sceneTime, hostTime: hostTime, isPaused: isPaused)
            else { return false }
        active.updateValue(candidate.source, forKey: candidate.declaration.identity)?.stop()
        candidate.transferred = true
        return true
    }
    func retireUserPropertySources(propertyKeys: Set<String>) {
        retiredKeys.append(propertyKeys)
        for identity in active.keys.filter({ propertyKeys.contains($0.propertyKey) }) {
            active.removeValue(forKey: identity)?.stop()
        }
    }
    func userPropertySources(
        declarations: [String: SceneUserPropertyVideoDeclaration], device: MTLDevice
    ) -> [SceneUserPropertyTextureIdentity: SceneVideoTextureSource] {
        active.filter { declarations[$0.key.propertyKey]?.identity == $0.key }
    }
}
nonisolated struct ScenePlaybackTextureReference { let url: URL; let bookmarkData: Data? = nil }
nonisolated struct ScenePlaybackTextureUpdate {
    let references: [String: ScenePlaybackTextureReference]
    let resetKeys: Set<String>
    let values: [String: SceneUserPropertyValue]
    let revision: UInt64
    let recordID: String
}
nonisolated enum ScenePlaybackTextureUpdateOutcome: Equatable { case applied, failed(String), superseded, unavailable }
nonisolated final class SceneWallpaperLaunchCancellation: @unchecked Sendable {
    private let lock = NSLock(); private var cancelled = false
    func cancel() { lock.lock(); cancelled = true; lock.unlock() }
    func check() throws { lock.lock(); defer { lock.unlock() }; if cancelled { throw CancellationError() } }
}
struct DemandCatalog { let userPropertyDemands: Set<SceneUserPropertyTextureIdentity> }
struct RenderDescriptor { let texturePropertyKeys: [String] }
struct RuntimeInput { let renderDescriptor: RenderDescriptor }
struct BaseImages { let textureLoader = SceneTextureLoader() }
struct DeviceResources { var device = MTLDevice(); let baseImages = BaseImages() }
struct ScriptProgram { var generation: UInt64 = 42 }
struct SceneDesktopWallpaperLaunchContext {
    let recordID: String? = "record"
    var userPropertyTextureLoad: SceneUserPropertyTextureLoadResult = .empty
    var liveState: ScenePropertyLiveUpdateState
    let resolvedMaterialCatalog: DemandCatalog
    let baseMaterialProviderBindings: DemandCatalog
    let runtimeInput = RuntimeInput(renderDescriptor: .init(texturePropertyKeys: ["photo", "other"]))
    var preparedDeviceResources = DeviceResources()
    var propertyVectorScriptProgram = ScriptProgram()
    let cacheDirectory = URL(fileURLWithPath: "/fixture/cache")
    let privateMediaCacheDirectory = URL(fileURLWithPath: "/fixture/private-media")
}
class SceneMetalView {
    var snapshot: SceneUserPropertyTextureLoadResult = .empty
    var videoSources: [SceneUserPropertyTextureIdentity: SceneVideoTextureSource] = [:]
    func adoptUserPropertyTextures(_ snapshot: SceneUserPropertyTextureLoadResult,
        videoSources: [SceneUserPropertyTextureIdentity: SceneVideoTextureSource] = [:]) {
        self.snapshot = snapshot
        self.videoSources = videoSources
    }
}
final class SceneDesktopWallpaperSession {
    struct Clock {
        var isPaused = true
        func currentSceneTime(hostTime: Double) -> Double { 12 }
    }
    class Surface { let metalView = SceneMetalView(); var didSubmitSimulationFrame = true }
    var launchContext: SceneDesktopWallpaperLaunchContext?
    var userPropertyTextureLoad: SceneUserPropertyTextureLoadResult = .empty
    var pendingUserTextureUpdates: [UInt64: PendingUserTextureUpdate] = [:]
    var latestUserTextureRevisions: [String: UInt64] = [:]
    var nextUserTextureGeneration: UInt64 = 1
    var sceneClock = Clock()
    var videoTextureSourceRegistry: SceneVideoTextureSourceRegistry? = .init()
    var initialUserVideoPreparation: Task<Void, Never>?
    let retiringSurfaceDrain = DispatchGroup()
    var drainStarted = false
    var onFirstFrameCompletion: ((UInt64, Bool) -> Void)?
    var staticFrameRequests = 0
    func startFrameDriver() { staticFrameRequests += 1 }
    let userTexturePreparationQueue = DispatchQueue(label: "fixture.resource.worker")
    var surfaces: [UInt64: Surface] = [1: .init(), 2: .init()]
    func unavailableLiveConsumerTargets(in context: SceneDesktopWallpaperLaunchContext) -> Set<SceneDynamicTarget> { [] }
    // This fixture has no authored script callback hosts to retire.
    func retiredPropertyCallbackTargets(in context: SceneDesktopWallpaperLaunchContext,
        propertyKeys: Set<String>) -> Set<SceneDynamicTarget> { [] }
    init() {
        let identities: Set<SceneUserPropertyTextureIdentity> = [.init(propertyKey: "photo", purpose: .preservedChannels)!,
            .init(propertyKey: "photo", purpose: .mask)!, .init(propertyKey: "photo", purpose: .normal)!]
        launchContext = .init(liveState: .init(program: .init(definitions: [], instructions: []),
            effectiveValues: ["photo": .string(""), "other": .string("")], activeConsumerTargets: []),
            resolvedMaterialCatalog: .init(userPropertyDemands: identities),
            baseMaterialProviderBindings: .init(userPropertyDemands: [.init(propertyKey: "photo", purpose: .premultipliedColor)!]))
    }
}

@main enum Checks {
    static func main() {
        let session = SceneDesktopWallpaperSession()
        var results: [String: Bool] = [:]
        var events: [String: ScenePlaybackTextureUpdateOutcome] = [:]
        func select(_ name: String, _ key: String, _ filename: String, _ revision: UInt64) {
            let url = URL(fileURLWithPath: "/fixture/" + filename)
            let update = ScenePlaybackTextureUpdate(references: [key: .init(url: url)], resetKeys: [],
                values: [key: .string(url.path)], revision: revision, recordID: "record")
            session.applyUserTextureUpdate(update, resolvedURLs: [key: url]) { events[name] = $0 }
        }
        func reset(_ name: String, _ key: String, _ revision: UInt64) {
            session.applyUserTextureUpdate(.init(references: [:], resetKeys: [key], values: [key: .string("")],
                revision: revision, recordID: "record"), resolvedURLs: [:]) { events[name] = $0 }
        }
        func wait(_ name: String) {
            let deadline = Date().addingTimeInterval(2)
            while events[name] == nil && Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.005)) }
            precondition(events[name] != nil, "completion timed out: " + name)
        }
        func texture(_ key: String) -> MTLTexture? { session.userPropertyTextureLoad.textures[key] }
        select("first", "photo", "first.png", 1); wait("first")
        let first = texture("photo")!
        let firstRevision = session.launchContext!.liveState.revision
        results["pureTextureAccepted"] = events["first"] == .applied && firstRevision == 1
        results["pausedUpdateRequestsStaticFrame"] = session.staticFrameRequests == 1 && session.sceneClock.isPaused
        results["allPurposesPublished"] = session.userPropertyTextureLoad.providerStates.count == 4
            && session.userPropertyTextureLoad.providerStates.keys.contains(.init(propertyKey: "photo", purpose: .normal)!)
        let photoDemands = session.launchContext!.resolvedMaterialCatalog.userPropertyDemands
        results["requiredLaunchAcceptsCompleteSelection"] = session.userPropertyTextureLoad.satisfiesRequiredProperties(
            ["photo"], selectedKeys: ["photo"], demands: photoDemands)
        results["requiredLaunchRejectsUndeclaredSelection"] = !session.userPropertyTextureLoad.satisfiesRequiredProperties(
            ["missing"], selectedKeys: ["missing"], demands: photoDemands)
        results["requiredLaunchRejectsUnreadySelection"] = !SceneUserPropertyTextureLoadResult.empty.satisfiesRequiredProperties(
            ["photo"], selectedKeys: ["photo"], demands: photoDemands)
        results["surfacesShareAtom"] = session.surfaces.values.allSatisfy { $0.metalView.snapshot.textures["photo"] === first }
        select("broken", "photo", "broken.png", 2); wait("broken")
        results["decodeFailurePreservesOld"] = events["broken"] == .failed("texture-update-resource-unavailable")
            && texture("photo") === first && session.launchContext!.liveState.revision == firstRevision
        select("partial", "photo", "partial.png", 3); wait("partial")
        results["onePurposeFailurePreservesWholeKey"] = events["partial"] == .failed("texture-update-resource-unavailable")
            && texture("photo") === first && session.launchContext!.liveState.revision == firstRevision
        select("a", "photo", "slow-a.png", 4)
        select("b", "other", "b.png", 5)
        reset("reset", "photo", 6)
        wait("reset"); wait("a"); wait("b")
        results["latestSameKeyWins"] = events["a"] == .superseded && events["reset"] == .applied
        results["independentKeySurvives"] = events["b"] == .applied && texture("other")?.name == "b.png:premultipliedColor"
        results["resetRemovesBareAndEveryPurpose"] = texture("photo") == nil
            && session.userPropertyTextureLoad.textureCandidates["photo"] == nil
            && session.userPropertyTextureLoad.providerStates.filter { $0.key.propertyKey == "photo" }.count == 4
            && session.userPropertyTextureLoad.providerStates.filter { $0.key.propertyKey == "photo" }.values.allSatisfy {
                if case .absent = $0 { return true }; return false
            } && session.launchContext!.liveState.effectiveValues["photo"] == .string("")
        results["requiredLaunchAcceptsExplicitReset"] = session.userPropertyTextureLoad.satisfiesRequiredProperties(
            ["photo"], selectedKeys: [], demands: photoDemands)
        select("second", "photo", "second.png", 7); wait("second")
        let second = texture("photo")!
        let publication = session.userPropertyTextureLoad.publications[.init(propertyKey: "photo", purpose: .normal)!]!
        results["monotonicContentGeneration"] = publication.contentGeneration > 2
        results["contextConsumesCurrentSnapshot"] = session.launchContext!.userPropertyTextureLoad.textures["photo"] === second
        results["newSurfaceConsumesCurrent"] = {
            let surface = SceneDesktopWallpaperSession.Surface(); surface.metalView.adoptUserPropertyTextures(session.userPropertyTextureLoad)
            return surface.metalView.snapshot.textures["photo"] === second
        }()
        select("stale", "photo", "late.png", 6); wait("stale")
        results["staleRevisionRejected"] = events["stale"] == .superseded && texture("photo") === second
        select("device", "photo", "slow-device.png", 8)
        session.launchContext!.preparedDeviceResources.device = MTLDevice(2); wait("device")
        results["deviceChangeRejectsReady"] = events["device"] == .superseded && texture("photo") === second
        select("stop", "photo", "slow-stop.png", 9)
        session.cancelPendingUserTextureUpdates(); session.launchContext = nil; wait("stop")
        results["stopEndsCompletion"] = events["stop"] == .superseded && session.pendingUserTextureUpdates.isEmpty
        let counts = SceneTextureLoader.counts()
        results["workerNeverRunsOnMain"] = counts.1 == 0
        results["snapshotDidNotMutateOldAtom"] = first.name == "first.png:premultipliedColor"
        let releaseSession = SceneDesktopWallpaperSession()
        weak var retired: MTLTexture?
        do {
            let initial = MTLTexture("initial")
            retired = initial
            let snapshot = SceneUserPropertyTextureLoadResult(textures: ["photo": initial],
                textureCandidates: [:], providerStates: [:], reportLines: [])
            releaseSession.userPropertyTextureLoad = snapshot
            releaseSession.launchContext!.userPropertyTextureLoad = snapshot
            releaseSession.surfaces.values.forEach { $0.metalView.adoptUserPropertyTextures(snapshot) }
        }
        var releaseOutcome: ScenePlaybackTextureUpdateOutcome?
        releaseSession.applyUserTextureUpdate(.init(references: [:], resetKeys: ["photo"],
            values: ["photo": .string("")], revision: 1, recordID: "record"), resolvedURLs: [:]) { releaseOutcome = $0 }
        while releaseOutcome == nil { RunLoop.main.run(until: Date().addingTimeInterval(0.005)) }
        results["initialSnapshotRetiredFromContextAndSurfaces"] = releaseOutcome == .applied && retired == nil
        results.merge(videoChecks()) { _, new in new }
        let blocked = SceneDesktopWallpaperSession()
        let entered = DispatchSemaphore(value: 0), release = DispatchSemaphore(value: 0)
        blocked.userTexturePreparationQueue.async { entered.signal(); release.wait() }
        precondition(entered.wait(timeout: .now() + 2) == .success)
        let blockedURL = URL(fileURLWithPath: "/fixture/blocked.png")
        var blockedOutcome: ScenePlaybackTextureUpdateOutcome?
        blocked.applyUserTextureUpdate(.init(references: ["other": .init(url: blockedURL)], resetKeys: [],
            values: ["other": .string(blockedURL.path)], revision: 1, recordID: "record"),
            resolvedURLs: ["other": blockedURL]) { blockedOutcome = $0 }
        results["admittedUserWorkerEntersOriginalRetirementGroup"] =
            blocked.retiringSurfaceDrain.wait(timeout: .now()) == .timedOut
        blocked.cancelPendingUserTextureUpdates(); blocked.launchContext = nil
        results["cancelDoesNotPretendBlockedUserWorkerJoined"] = blockedOutcome == nil
            && blocked.retiringSurfaceDrain.wait(timeout: .now()) == .timedOut
        release.signal()
        let deadline = Date().addingTimeInterval(2)
        while blockedOutcome == nil && Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.005))
        }
        results["cancelledUserChainLeavesGroupAfterRealTerminal"] = blockedOutcome == .superseded
            && blocked.pendingUserTextureUpdates.isEmpty
            && blocked.retiringSurfaceDrain.wait(timeout: .now()) == .success
        let closed = SceneDesktopWallpaperSession(); closed.drainStarted = true
        var closedOutcome: ScenePlaybackTextureUpdateOutcome?
        closed.applyUserTextureUpdate(.init(references: ["other": .init(url: blockedURL)], resetKeys: [],
            values: ["other": .string(blockedURL.path)], revision: 1, recordID: "record"),
            resolvedURLs: ["other": blockedURL]) { closedOutcome = $0 }
        results["retiringSessionRejectsNewUserTextureAdmission"] = closedOutcome == .unavailable
            && closed.pendingUserTextureUpdates.isEmpty
            && closed.retiringSurfaceDrain.wait(timeout: .now()) == .success
        let encoded = try! JSONSerialization.data(withJSONObject: results, options: [.sortedKeys])
        print(String(data: encoded, encoding: .utf8)!)
        precondition(results.values.allSatisfy { $0 }, "failed checks")
    }

    static func videoChecks() -> [String: Bool] {
        let session = SceneDesktopWallpaperSession()
        let registry = session.videoTextureSourceRegistry!
        let identity = SceneUserPropertyTextureIdentity(propertyKey: "other", purpose: .premultipliedColor)!
        var results: [String: Bool] = [:]
        var events: [String: ScenePlaybackTextureUpdateOutcome] = [:]
        func until(_ label: String, _ condition: () -> Bool) {
            let deadline = Date().addingTimeInterval(2)
            while !condition() && Date() < deadline {
                RunLoop.main.run(until: Date().addingTimeInterval(0.005))
            }
            precondition(condition(), "video boundary timed out: " + label)
        }
        func select(_ name: String, _ key: String = "other", _ file: String, _ revision: UInt64) {
            let url = URL(fileURLWithPath: "/fixture/" + file)
            session.applyUserTextureUpdate(.init(references: [key: .init(url: url)], resetKeys: [],
                values: [key: .string(url.path)], revision: revision, recordID: "record"),
                resolvedURLs: [key: url]) { events[name] = $0 }
        }
        func reset(_ name: String, _ revision: UInt64) {
            session.applyUserTextureUpdate(.init(references: [:], resetKeys: ["other"],
                values: ["other": .string("")], revision: revision, recordID: "record"),
                resolvedURLs: [:]) { events[name] = $0 }
        }
        func wait(_ name: String) { until(name) { events[name] != nil } }
        func nextPrime(_ previousCount: Int) -> SceneVideoTextureSource {
            until("prime started") {
                registry.issuedSources.count > previousCount && registry.issuedSources.last!.primeStarted
            }
            return registry.issuedSources.last!
        }
        select("peer", "photo", "peer.png", 1); wait("peer")
        select("old", "other", "old-other.png", 1); wait("old")
        let peer = session.userPropertyTextureLoad.textures["photo"]!
        let old = session.userPropertyTextureLoad.textures["other"]!
        let oldRevision = session.launchContext!.liveState.revision
        select("video", "other", "manual-prime-first.mp4", 2)
        let first = nextPrime(0)
        results["pendingVideoPrimeKeepsOriginalRetirementGroupEntered"] =
            session.retiringSurfaceDrain.wait(timeout: .now()) == .timedOut
        results["videoPendingPrimePreservesValueResourceRevision"] = events["video"] == nil
            && registry.active.isEmpty
            && session.userPropertyTextureLoad.textures["other"] === old
            && session.launchContext!.liveState.revision == oldRevision
            && session.launchContext!.liveState.effectiveValues["other"] == .string("/fixture/old-other.png")
        results["videoPendingPrimeIsNotSurfaceBinding"] = session.surfaces.values.allSatisfy {
            $0.metalView.videoSources.isEmpty && $0.metalView.snapshot.textures["other"] === old
        }
        first.releasePrime = true
        wait("video")
        let adoptedRevision = session.launchContext!.liveState.revision
        results["videoValueAndBindingAdoptTogetherAcrossSurfaces"] = events["video"] == .applied
            && adoptedRevision == oldRevision + 1 && registry.active[identity] === first
            && session.launchContext!.liveState.effectiveValues["other"] == .string("/fixture/manual-prime-first.mp4")
            && session.surfaces.values.allSatisfy {
                $0.metalView.videoSources[identity] === first && !$0.didSubmitSimulationFrame
                    && $0.metalView.snapshot.textures["other"] == nil
                    && $0.metalView.snapshot.videoDeclarations["other"]?.file
                        === session.userPropertyTextureLoad.videoDeclarations["other"]?.file
            }
        results["videoActivationUsesCurrentPausedSceneClock"] = first.activated
            && first.activationSceneTime == 12 && first.activationPaused == true && session.sceneClock.isPaused
        let prepared = session.userPropertyTextureLoad
        let videoOutputDirectory = prepared.videoDeclarations["other"]?.file.url.deletingLastPathComponent().path
        results["videoWorkerUsesPrivateOutputDomain"] =
            videoOutputDirectory == session.launchContext!.privateMediaCacheDirectory.path
            && videoOutputDirectory != session.launchContext!.cacheDirectory.path
        results["videoDeclarationPreparedNeverReadyPublication"] = prepared.hasPreparedResources(for: [identity])
            && prepared.satisfiesPreparedProperties(["other"], selectedKeys: ["other"], demands: [identity])
            && !prepared.hasCompletePublications(for: [identity])
            && !prepared.satisfiesRequiredProperties(["other"], selectedKeys: ["other"], demands: [identity])
            && prepared.textures["other"] == nil && prepared.publications[identity] == nil
        results["videoPreservesOtherKeyEveryPurpose"] = session.userPropertyTextureLoad.textures["photo"] === peer
            && session.userPropertyTextureLoad.providerStates.filter { $0.key.propertyKey == "photo" }.count == 4
        let issued = registry.issuedSources.count
        select("purpose", "photo", "not-a-data-map.mov", 2); wait("purpose")
        results["videoNonColorDemandRejectsWholeKeyBeforeFactory"] =
            events["purpose"] == .failed("texture-update-resource-unavailable")
            && registry.issuedSources.count == issued
            && session.userPropertyTextureLoad.textures["photo"] === peer
            && registry.active[identity] === first
        select("bad-prime", "other", "bad-prime.mp4", 3); wait("bad-prime")
        let failed = registry.issuedSources.last!
        results["videoFailedPrimeKeepsOldAtomAndStopsCandidate"] =
            events["bad-prime"] == .failed("texture-update-video-unavailable")
            && failed.stopCount == 1 && registry.active[identity] === first && first.stopCount == 0
            && session.launchContext!.liveState.revision == adoptedRevision
        let beforeA = registry.issuedSources.count
        select("a", "other", "manual-prime-a.mp4", 4)
        let a = nextPrime(beforeA)
        select("b", "other", "renamed-equivalent.MOV", 5)
        wait("b"); wait("a")
        let b = registry.active[identity]!
        results["videoSupersededPrimeCannotAdoptOrChangeValue"] = events["a"] == .superseded
            && a.primeCancelled && a.stopCount == 1 && events["b"] == .applied
            && b !== a && b !== first
            && session.launchContext!.liveState.effectiveValues["other"] == .string("/fixture/renamed-equivalent.MOV")
        results["videoReplacementCallsAdoptionBoundaryAndRetiresOldStub"] =
            first.stopCount == 1 && b.stopCount == 0 && session.surfaces.values.allSatisfy {
                $0.metalView.videoSources[identity] === b
            }
        select("image", "other", "back-to-image.png", 6); wait("image")
        results["videoToImageRequestsRetirementAndClearsDeclarations"] = events["image"] == .applied
            && b.stopCount == 1 && registry.active.isEmpty
            && registry.retiredKeys.contains(["other"])
            && session.userPropertyTextureLoad.videoDeclarations.isEmpty
            && session.surfaces.values.allSatisfy {
                $0.metalView.videoSources.isEmpty
                    && $0.metalView.snapshot.textures["other"]?.name == "back-to-image.png:premultipliedColor"
            }
        let beforeResetCandidate = registry.issuedSources.count
        select("reset-candidate", "other", "manual-prime-reset.m4v", 7)
        let resetCandidate = nextPrime(beforeResetCandidate)
        reset("reset-video", 8)
        wait("reset-video"); wait("reset-candidate")
        results["videoResetCancelsPendingAndRemovesWholeKey"] = events["reset-video"] == .applied
            && events["reset-candidate"] == .superseded && resetCandidate.primeCancelled
            && resetCandidate.stopCount == 1 && session.userPropertyTextureLoad.videoDeclarations.isEmpty
            && session.launchContext!.liveState.effectiveValues["other"] == .string("")
            && session.surfaces.values.allSatisfy { $0.metalView.videoSources.isEmpty }
        results["videoExtensionOwnerAcceptsBoundedFormats"] = ["clip.mp4", "clip.MOV", "clip.m4v"].allSatisfy {
            SceneUserPropertyTextureLoader.isVideo(url: URL(fileURLWithPath: $0))
        } && !SceneUserPropertyTextureLoader.supports(url: URL(fileURLWithPath: "clip.webm"))
        func staleBoundary(_ label: String, mutate: (SceneDesktopWallpaperSession) -> Void,
                           expected: ScenePlaybackTextureUpdateOutcome = .superseded) -> Bool {
            let isolated = SceneDesktopWallpaperSession()
            let initialRegistry = isolated.videoTextureSourceRegistry!
            let url = URL(fileURLWithPath: "/fixture/manual-prime-" + label + ".mp4")
            var outcome: ScenePlaybackTextureUpdateOutcome?
            isolated.applyUserTextureUpdate(.init(references: ["other": .init(url: url)], resetKeys: [],
                values: ["other": .string(url.path)], revision: 1, recordID: "record"),
                resolvedURLs: ["other": url]) { outcome = $0 }
            until(label + " pending") { initialRegistry.issuedSources.first?.primeStarted == true }
            let source = initialRegistry.issuedSources.first!
            mutate(isolated)
            source.releasePrime = true
            until(label + " completes") { outcome != nil }
            return outcome == expected && source.stopCount == 1 && initialRegistry.active.isEmpty
                && isolated.launchContext?.liveState.revision == 0
                && isolated.launchContext?.liveState.effectiveValues["other"] == .string("")
        }
        results["videoRegistryReplacementRejectsLatePrime"] = staleBoundary("registry") {
            $0.videoTextureSourceRegistry = SceneVideoTextureSourceRegistry()
        }
        results["videoDeviceChangeRejectsLatePrime"] = staleBoundary("device") {
            $0.launchContext!.preparedDeviceResources.device = MTLDevice(2)
        }
        results["videoProgramGenerationChangeRejectsLatePrime"] = staleBoundary("program") {
            $0.launchContext!.propertyVectorScriptProgram.generation += 1
        }
        results["videoSurfaceRemovalRejectsLatePrime"] = staleBoundary("surfaces") { $0.surfaces.removeAll() }
        results["videoAdoptionDenialPreservesLiveState"] = staleBoundary("admission", mutate: {
            $0.videoTextureSourceRegistry!.allowAdoption = false
        }, expected: .failed("texture-update-consumer-unavailable"))
        results["videoIntentCancellationStopsDeferredPrime"] = staleBoundary("intent") {
            $0.cancelPendingUserTextureUpdates()
        }
        func initial(_ filename: String) -> SceneDesktopWallpaperSession {
            let target = SceneDesktopWallpaperSession()
            let file = SceneVideoOwnedFile(URL(fileURLWithPath: "/fixture/" + filename))
            let declaration = SceneUserPropertyVideoDeclaration(identity: identity, file: file,
                source: SceneTextureLoader.currentSourceKey(for: file.url)!)
            target.userPropertyTextureLoad = .init(textures: [:], textureCandidates: [:],
                providerStates: [identity: .unavailable], videoDeclarations: ["other": declaration], reportLines: [])
            target.launchContext!.userPropertyTextureLoad = target.userPropertyTextureLoad
            return target
        }
        let startup = initial("manual-prime-startup.mp4")
        let startupRegistry = startup.videoTextureSourceRegistry!
        startup.prepareInitialUserPropertyVideos()
        until("startup prime") { startupRegistry.issuedSources.first?.primeStarted == true }
        results["initialVideoPrimeEntersOriginalRetirementGroup"] =
            startup.retiringSurfaceDrain.wait(timeout: .now()) == .timedOut
        let startupSource = startupRegistry.issuedSources.first!
        results["videoStartupDoesNotBindDeclarationBeforePrime"] = startupRegistry.active.isEmpty
            && startup.surfaces.values.allSatisfy { $0.metalView.videoSources.isEmpty }
            && !startup.userPropertyTextureLoad.hasCompletePublications(for: [identity])
        startupSource.releasePrime = true
        until("startup adopted") { startup.initialUserVideoPreparation == nil }
        results["initialVideoPrimeSuccessLeavesRetirementGroup"] =
            startup.retiringSurfaceDrain.wait(timeout: .now()) == .success
        results["videoStartupUsesSameSourceForEverySurfaceAfterPrime"] =
            startupRegistry.active[identity] === startupSource
            && startup.surfaces.values.allSatisfy { $0.metalView.videoSources[identity] === startupSource }
            && !startup.userPropertyTextureLoad.hasCompletePublications(for: [identity])
        let badStartup = initial("bad-prime-startup.mp4")
        var firstFrameFailure: Bool?
        badStartup.onFirstFrameCompletion = { _, succeeded in firstFrameFailure = succeeded }
        badStartup.prepareInitialUserPropertyVideos()
        until("startup failed") { firstFrameFailure != nil }
        results["initialVideoPrimeFailureLeavesRetirementGroup"] =
            badStartup.retiringSurfaceDrain.wait(timeout: .now()) == .success
        let cancelledStartup = initial("manual-prime-cancelled-startup.mp4")
        cancelledStartup.prepareInitialUserPropertyVideos()
        until("cancelled startup prime") {
            cancelledStartup.videoTextureSourceRegistry!.issuedSources.first?.primeStarted == true
        }
        cancelledStartup.initialUserVideoPreparation?.cancel()
        results["initialPrimeCancelIsNotImmediateJoin"] =
            cancelledStartup.retiringSurfaceDrain.wait(timeout: .now()) == .timedOut
        until("cancelled startup terminal") {
            cancelledStartup.retiringSurfaceDrain.wait(timeout: .now()) == .success
        }
        results["initialPrimeCancelledWorkerLeavesOriginalGroup"] =
            cancelledStartup.videoTextureSourceRegistry!.issuedSources.first?.primeCancelled == true
        results["videoStartupPrimeFailureReportsNotReady"] = firstFrameFailure == false
            && badStartup.videoTextureSourceRegistry!.active.isEmpty
            && badStartup.videoTextureSourceRegistry!.issuedSources.first?.stopCount == 1
            && badStartup.surfaces.values.allSatisfy { $0.metalView.videoSources.isEmpty }
        return results
    }
}
