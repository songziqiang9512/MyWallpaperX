import Foundation

enum SceneDeferredBaseImageStatus: Equatable {
    case notDeferred, pending, loading, ready
    case failed(String)
}

final class FixtureResources {
    let deferredLayerIDs: Set<Int>
    var statuses: [Int: SceneDeferredBaseImageStatus]
    var requests: [(layerID: Int, generation: UInt64)] = []

    init(deferredLayerIDs: Set<Int> = [11, 22]) {
        self.deferredLayerIDs = deferredLayerIDs
        self.statuses = Dictionary(uniqueKeysWithValues: deferredLayerIDs.map { ($0, .pending) })
    }

    @discardableResult
    func requestDeferredBaseImage(layerID: Int, requestGeneration: UInt64)
        -> SceneDeferredBaseImageStatus {
        requests.append((layerID, requestGeneration))
        return deferredStatus(for: layerID)
    }
    func deferredStatus(for layerID: Int) -> SceneDeferredBaseImageStatus {
        statuses[layerID] ?? .notDeferred
    }
}

final class FixtureAdoption {
    var successfulCalls = 0
    var failAfterSuccessfulCalls: Int?

    func accept() -> Bool {
        if let limit = failAfterSuccessfulCalls, successfulCalls >= limit { return false }
        successfulCalls += 1
        return true
    }
}

final class FixtureView {
    let adoption: FixtureAdoption
    var preparedParticleLayerIDs: Set<Int> = []
    var staged: Set<Int> = []
    var committed: Set<Int> = []
    var attempts = 0
    var discards = 0
    var commits = 0

    init(_ adoption: FixtureAdoption) { self.adoption = adoption }
    func adoptPreparedDeferredBaseImage(layerID: Int) -> Bool {
        attempts += 1
        guard adoption.accept() else { return false }
        staged.insert(layerID)
        return true
    }
    func discardPreparedDeferredBaseImages(layerIDs: Set<Int>) {
        discards += 1
        staged.subtract(layerIDs)
    }
    func commitPreparedDeferredBaseImages(layerIDs: Set<Int>) {
        commits += 1
        committed.formUnion(layerIDs)
        staged.subtract(layerIDs)
    }
}

final class FixtureSound {
    var accepts = true
    var applies = 0
    func canApply(userValues: [SceneDynamicTarget: SceneDynamicValue]) -> Bool { accepts }
    func apply(userValues: [SceneDynamicTarget: SceneDynamicValue]) { applies += 1 }
}

struct FixtureRuntimeInput { let propertyBindingProgram: ScenePropertyBindingProgram }
struct FixtureDeviceResources { let baseImages: FixtureResources }
struct FixtureScriptProgram { var generation: UInt64 = 1 }
struct SceneDesktopWallpaperLaunchContext {
    let recordID: String?
    var liveState: ScenePropertyLiveUpdateState
    let runtimeInput: FixtureRuntimeInput
    let preparedDeviceResources: FixtureDeviceResources
    var particleLayerIDs: Set<Int> = []
    var particleVisibilityRequirements: [Int: Set<Int>] = [:]
    var preparedParticleVisibilityLayerIDs: Set<Int> {
        Set(particleVisibilityRequirements.values.joined())
    }
    var propertyVectorScriptProgram = FixtureScriptProgram()
    var unavailable: Set<SceneDynamicTarget> = []
}

enum SceneDesktopWallpaperHost {
    static let usesDebugEvidenceWindow = false
    static func unavailableLiveScriptPropertyTargets(
        in context: SceneDesktopWallpaperLaunchContext
    ) -> Set<SceneDynamicTarget> { context.unavailable }
}

final class SceneDesktopWallpaperSession {
    struct Surface {
        let metalView: FixtureView
        var scriptGeneration: UInt64 = 1
    }
    var launchContext: SceneDesktopWallpaperLaunchContext?
    var surfaces: [Int: Surface] = [:]
    var preparedSurfaceIDs: Set<Int> = []
    var soundPlaybackRegistry: FixtureSound? = FixtureSound()
    var nextDeferredPropertyGeneration: UInt64 = 0
    var pendingDeferredLayerVisibilityUpdate: PendingDeferredLayerVisibilityUpdate?
    init(_ context: SceneDesktopWallpaperLaunchContext) { launchContext = context }

    // PRODUCT_PENDING_DECLARATION
}
