import Foundation

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
    case decodeFailed(String), textureAllocationFailed(width: Int, height: Int)
}
nonisolated enum SceneTextureCandidateLoadOutcome { case loaded(SceneTextureCandidate), failed(SceneTextureLoadOutcome) }
nonisolated final class SceneTextureLoader {
    let uploadCommandQueue: SceneTextureUploadCommandQueue
    let decodeCacheBudget: SceneTextureDecodeCacheBudget
    private static let lock = NSLock()
    private static var calls = 0
    private static var mainCalls = 0
    init(uploadCommandQueue: SceneTextureUploadCommandQueue = .init(), decodeCacheBudget: SceneTextureDecodeCacheBudget = .init()) {
        self.uploadCommandQueue = uploadCommandQueue; self.decodeCacheBudget = decodeCacheBudget
    }
    static func counts() -> (Int, Int) { lock.lock(); defer { lock.unlock() }; return (calls, mainCalls) }
    func loadDirectImageCandidates(from url: URL, purposes: Set<SceneTextureLoadPurpose>, device: MTLDevice,
                                   isCancelled: () -> Bool) -> [SceneTextureLoadPurpose: SceneTextureCandidateLoadOutcome] {
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
}
class SceneMetalView {
    var snapshot: SceneUserPropertyTextureLoadResult = .empty
    func adoptUserPropertyTextures(_ snapshot: SceneUserPropertyTextureLoadResult) { self.snapshot = snapshot }
}
final class SceneDesktopWallpaperSession {
    struct Clock { var isPaused = true }
    class Surface { let metalView = SceneMetalView(); var didSubmitSimulationFrame = true }
    var launchContext: SceneDesktopWallpaperLaunchContext?
    var userPropertyTextureLoad: SceneUserPropertyTextureLoadResult = .empty
    var pendingUserTextureUpdates: [UInt64: PendingUserTextureUpdate] = [:]
    var latestUserTextureRevisions: [String: UInt64] = [:]
    var nextUserTextureGeneration: UInt64 = 1
    var sceneClock = Clock()
    var staticFrameRequests = 0
    func startFrameDriver() { staticFrameRequests += 1 }
    let userTexturePreparationQueue = DispatchQueue(label: "fixture.resource.worker")
    var surfaces: [UInt64: Surface] = [1: .init(), 2: .init()]
    func unavailableLiveConsumerTargets(in context: SceneDesktopWallpaperLaunchContext) -> Set<SceneDynamicTarget> { [] }
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
        let encoded = try! JSONSerialization.data(withJSONObject: results, options: [.sortedKeys])
        print(String(data: encoded, encoding: .utf8)!)
        precondition(results.values.allSatisfy { $0 }, "failed checks")
    }
}
