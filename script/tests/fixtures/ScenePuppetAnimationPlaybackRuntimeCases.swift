import Foundation
import simd

enum SceneDynamicTarget: Hashable {
    case scriptInstanceProperty(layerID: Int, path: [String])
}
enum SceneDynamicValue { case bool(Bool), scalar(Double) }
enum SceneDynamicSource { case authored, userProperty, timeline, sceneScript }
struct SceneDynamicResolvedValue {
    let value: SceneDynamicValue
    var source: SceneDynamicSource = .authored
}
enum Observation { static var visibilityReads = 0 }
struct SceneDynamicSnapshot {
    let values: [SceneDynamicTarget: SceneDynamicResolvedValue]
    subscript(target: SceneDynamicTarget) -> SceneDynamicResolvedValue? {
        Observation.visibilityReads += 1
        return values[target]
    }
}
func layer(id: Int = 10, animationID: Int = 1, rate: Double = 1,
           visible: Bool = true, binding: String? = "enabled", script: Bool = false) -> ScenePuppetAnimationLayer {
    .init(id: id, animationID: animationID, name: "track", additive: true,
        blend: 1, blendIn: false, blendOut: false, blendTime: 0,
        rate: rate, visible: visible, visibilityBinding: binding, hasVisibilityScript: script ? true : nil)
}
func animation(id: Int = 1, mode: String = "loop", fps: Float = 2,
               alpha: [[Float]]? = nil,
               events: [SceneMdlPuppetAnimation.Event] = []) -> SceneMdlPuppetAnimation {
    .init(id: id, name: "track", mode: mode, framesPerSecond: fps, frameCount: 4,
        transformsByBone: [(0...4).map { frame in
            .init(translation: SIMD3(Float(frame), 0, 0), rotation: .zero,
                scale: SIMD3(repeating: 1))
        }], alphaByBone: alpha, events: events)
}
func selection(_ layer: ScenePuppetAnimationLayer,
               _ animation: SceneMdlPuppetAnimation) -> ScenePuppetAnimationSelection {
    .init(clips: [.init(layer: layer, animation: animation)], composition: .layered)
}
func visible(_ entries: [Int: Bool]) -> SceneDynamicSnapshot {
    .init(values: Dictionary(uniqueKeysWithValues: entries.map { parent, value in
        (ScenePuppetAnimationPropertyTarget.visibility(layerID: parent, animationLayerID: 10),
         .init(value: .bool(value)))
    }))
}
func report(_ frame: ScenePuppetAnimationPlaybackRuntime.FrameSnapshot, layerID: Int = 42)
    -> [[Double]] {
    frame[layerID]!.samples.map { sample in
        sample.map { [Double($0.frameA), Double($0.frameB), Double($0.fraction)] } ?? []
    }
}
func registration(_ result: Result<Void, ScenePuppetAnimationPlaybackRuntime.Failure>) -> Bool {
    if case .success = result { return true }
    return false
}

func control(_ identity: ScenePuppetAnimationIdentity, _ action: ScenePuppetAnimationCommand.Action,
             _ epoch: UInt64, _ ordinal: UInt32 = 0) -> ScenePuppetAnimationCommand {
    .init(identity: identity, action: action, callbackEpoch: epoch, ordinal: ordinal)
}
func state(_ snapshot: ScenePuppetAnimationSnapshot) -> [String: Any] {
    ["parent": snapshot.identity.layerID, "index": snapshot.identity.animationLayerIndex as Any,
     "id": snapshot.identity.animationLayerID as Any, "animationID": snapshot.animationID,
     "name": snapshot.name, "fps": snapshot.framesPerSecond, "count": snapshot.frameCount,
     "duration": snapshot.duration, "frame": snapshot.currentFrame, "playing": snapshot.isPlaying,
     "rate": snapshot.rate, "blend": snapshot.blend, "visible": snapshot.visible,
     "ended": snapshot.endedSequence, "supportsEnded": snapshot.supportsEndedCallbacks,
     "endedFailure": snapshot.endedFailure?.rawValue ?? ""]
}
func event(_ name: String, _ frame: Int) -> SceneMdlPuppetAnimation.Event {
    .init(name: name, frame: frame, recordedTime: 17.25)
}
func events(_ frame: ScenePuppetAnimationPlaybackRuntime.FrameSnapshot) -> [[String: Any]] {
    frame.animationEvents.map { ["parent": $0.identity.layerID,
        "clip": $0.identity.animationLayerIndex as Any, "sequence": $0.sequence,
        "name": $0.name, "frame": $0.frame] }
}
func eventRuntime(_ candidate: ScenePuppetAnimationSelection, parent: Int = 42)
    throws -> ScenePuppetAnimationPlaybackRuntime {
    let runtime = ScenePuppetAnimationPlaybackRuntime()
    try runtime.register(layerID: parent, selection: candidate,
        authoredLayers: candidate.clips.map(\.layer)).get()
    return runtime
}
func step(_ runtime: ScenePuppetAnimationPlaybackRuntime, _ frame: UInt64, _ time: Double,
          visible value: Bool = true) -> ScenePuppetAnimationPlaybackRuntime.FrameSnapshot {
    runtime.advance(frameIndex: frame, sceneTime: time, dynamicValues: visible([42: value]))
}
func animationEventReport() throws -> [String: Any] {
    var output: [String: Any] = [:]
    let definition = selection(layer(binding: nil),
        animation(events: [event("renamed-early", 1), event("late", 3)]))
    let runtime = try eventRuntime(definition)
    let initial = step(runtime, 0, 0)
    let before = step(runtime, 1, 0.49)
    let exact = step(runtime, 2, 0.5)
    let late = step(runtime, 3, 1.5)
    let wrapped = step(runtime, 4, 2.5)
    let duplicate = step(runtime, 4, 99)
    let stale = step(runtime, 3, 99)
    try runtime.register(layerID: 77, selection: definition,
        authoredLayers: definition.clips.map(\.layer)).get()
    let lateParent = step(runtime, 4, 99)
    let noCrossing = step(runtime, 5, 2.75)
    output["crossing"] = ["initial": events(initial), "before": events(before),
        "exact": events(exact), "late": events(late), "wrapped": events(wrapped),
        "same": duplicate.animationEvents == wrapped.animationEvents
            && stale.animationEvents == wrapped.animationEvents
            && lateParent.animationEvents == wrapped.animationEvents,
        "lateParentPrepared": lateParent[77] != nil, "next": events(noCrossing)]
    let changed = selection(definition.clips[0].layer,
        animation(events: [event("different-source", 1), event("late", 3)]))
    output["eventDefinitionConflict"] = !registration(runtime.register(layerID: 42,
        selection: changed, authoredLayers: changed.clips.map(\.layer)))

    let ordering = ScenePuppetAnimationSelection(clips: [
        .init(layer: layer(binding: nil), animation: animation(events: [
            event("authored-first", 1), event("authored-second", 1)])),
        .init(layer: layer(id: 11, animationID: 2, binding: nil),
            animation: animation(id: 2, fps: 4, events: [event("fast-first", 1), event("fast-tie", 2)]))
    ], composition: .layered)
    let ordered = try eventRuntime(ordering)
    _ = step(ordered, 0, 0)
    output["ordering"] = events(step(ordered, 1, 0.5))
    let acrossBoundary = try eventRuntime(definition)
    _ = step(acrossBoundary, 0, 1.25)
    output["wrapOrder"] = events(step(acrossBoundary, 1, 2.75))

    let controlled = try eventRuntime(definition)
    _ = step(controlled, 0, 0)
    let id = controlled.snapshots()[0].identity
    try controlled.apply([control(id, .setFrame(3), 1)], frameIndex: 0).get()
    let seek = step(controlled, 1, 0.1)
    try controlled.apply([control(id, .stop, 2)], frameIndex: 1).get()
    let stopped = step(controlled, 2, 10)
    try controlled.apply([control(id, .play, 3)], frameIndex: 2).get()
    let resumed = step(controlled, 3, 10.25)
    try controlled.apply([control(id, .setRate(0), 4)], frameIndex: 3).get()
    let zero = step(controlled, 4, 20)
    try controlled.apply([control(id, .setRate(1), 5), control(id, .pause, 5, 1)], frameIndex: 4).get()
    let paused = step(controlled, 5, 30)
    try controlled.apply([control(id, .play, 6)], frameIndex: 5).get()
    let played = step(controlled, 6, 30.3)
    try controlled.apply([control(id, .stop, 7)], frameIndex: 6).get()
    let frozen = step(controlled, 6, 100)
    output["controls"] = ["quiet": [seek, stopped, resumed, zero, paused].allSatisfy {
            $0.animationEvents.isEmpty && $0.eventFailures.isEmpty },
        "play": events(played), "frozen": frozen.animationEvents == played.animationEvents]

    let dynamic = try eventRuntime(selection(layer(), definition.clips[0].animation))
    _ = step(dynamic, 0, 0)
    _ = step(dynamic, 1, 0.25)
    let hidden = step(dynamic, 2, 10, visible: false)
    let restored = step(dynamic, 3, 10.25)
    let stationary = step(dynamic, 4, 10.25)
    output["visibility"] = ["hidden": events(hidden), "restored": events(restored),
        "stationary": events(stationary)]

    let tooMany = (0..<33).map { event("entry-\($0)", 1) }
    let overBudget = ScenePuppetAnimationSelection(clips: [
        .init(layer: layer(binding: nil), animation: animation(events: tooMany)),
        .init(layer: layer(id: 11, animationID: 2, binding: nil),
            animation: animation(id: 2, events: tooMany))
    ], composition: .layered)
    let failing = try eventRuntime(overBudget)
    try failing.register(layerID: 77, selection: definition,
        authoredLayers: definition.clips.map(\.layer)).get()
    _ = step(failing, 0, 0)
    let budget = step(failing, 1, 0.5)
    let retained = step(failing, 2, 0.75)
    output["budget"] = ["events": events(budget), "failureCount": budget.eventFailures.count,
        "failures": budget.eventFailures.values.map(\.rawValue).sorted(),
        "healthyPose": budget[42]!.samples.allSatisfy { $0 != nil },
        "retainedFailures": retained.eventFailures == budget.eventFailures]
    let sourceOverflowDefinition = ScenePuppetAnimationSelection(clips: [
        .init(layer: layer(binding: nil), animation: animation(events:
            (0...ScenePuppetAnimationPlaybackRuntime.eventBudget).map { event("overflow-\($0)", 1) })),
        .init(layer: layer(id: 11, animationID: 2, binding: nil),
            animation: animation(id: 2, events: [event("healthy-sibling", 1)]))
    ], composition: .layered)
    let sourceOverflow = try eventRuntime(sourceOverflowDefinition)
    _ = step(sourceOverflow, 0, 0)
    let rejectedParent = step(sourceOverflow, 1, 0.5)
    output["sourceBudget"] = rejectedParent.animationEvents.isEmpty
        && rejectedParent.eventFailures.count == 2
        && rejectedParent.eventFailures.values.allSatisfy { $0 == .eventBudgetExceeded }
    let full = try eventRuntime(selection(layer(binding: nil), animation(
        events: (0..<ScenePuppetAnimationPlaybackRuntime.eventBudget).map { event("at-limit-\($0)", 1) })))
    _ = step(full, 0, 0)
    let fullFrame = step(full, 1, 0.5)
    output["atBudget"] = fullFrame.animationEvents.count == 64 && fullFrame.eventFailures.isEmpty

    let multi = try eventRuntime(definition)
    _ = step(multi, 0, 0)
    let multiple = step(multi, 1, 5)
    let overflow = try eventRuntime(selection(layer(binding: nil),
        animation(fps: .greatestFiniteMagnitude, events: [event("finite-metadata", 1)])))
    _ = step(overflow, 0, 0)
    let nonFinite = step(overflow, 1, .greatestFiniteMagnitude)
    var invalid: [String] = []
    for candidate in [animation(mode: "mirror", events: [event("mode", 1)]),
                      animation(events: [event("boundary", 0)])] {
        let owner = try eventRuntime(selection(layer(binding: nil), candidate))
        invalid.append(contentsOf: step(owner, 0, 0).eventFailures.values.map(\.rawValue))
    }
    let noEvents = try eventRuntime(selection(layer(binding: nil), animation()))
    _ = step(noEvents, 0, 0)
    let noEventProfile = step(noEvents, 1, 100)
    output["failures"] = ["multiple": multiple.eventFailures.values.map(\.rawValue),
        "multipleEvents": events(multiple), "multiplePose": multiple[42]!.samples[0] != nil,
        "nonFinite": nonFinite.eventFailures.values.map(\.rawValue), "invalid": invalid,
        "noEventProfile": noEventProfile.eventFailures.isEmpty && noEventProfile.animationEvents.isEmpty]

    let retirement = try eventRuntime(definition)
    try retirement.register(layerID: -1, selection: definition,
        authoredLayers: definition.clips.map(\.layer)).get()
    let badDefinition = selection(layer(binding: nil), animation(mode: "single", events: [event("mode", 1)]))
    try retirement.register(layerID: -2, selection: badDefinition,
        authoredLayers: badDefinition.clips.map(\.layer)).get()
    _ = step(retirement, 0, 0)
    let beforeRetire = step(retirement, 1, 0.5)
    retirement.synchronizeDynamicLayers(topologyRevision: 1, liveLayerIDs: [])
    let retired = step(retirement, 1, 99)
    output["retirement"] = ["beforeEvents": beforeRetire.animationEvents.count,
        "beforeFailures": beforeRetire.eventFailures.count, "events": events(retired),
        "failures": retired.eventFailures.count, "removedPose": retired[-1] == nil && retired[-2] == nil]
    return output
}
func evaluate(_ frame: ScenePuppetAnimationPlaybackRuntime.FrameSnapshot,
              selection: ScenePuppetAnimationSelection) throws -> [Double] {
    let mesh = SceneMdlPuppetMesh(version: "fixture", vertexStride: 52, meshBlockOffset: 0,
        vertices: [.init(x: 0, y: 0, z: 0, u: 0, v: 0)], indices: [])
    let rig = SceneMdlPuppetRig(bones: [.init(parentIndex: -1,
        bindLocalMatrixColumnMajor: [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1])],
        vertexWeights: [.init(boneIndices: SIMD4(0, 0, 0, 0), boneWeights: SIMD4(1, 0, 0, 0))])
    let evaluator = try ScenePuppetAnimationEvaluator(mesh: mesh, rig: rig,
        additiveAnimations: selection.clips.map(\.animation))
    let animationFrame = frame[42]!
    var matrices = [matrix_identity_float4x4]
    try evaluator.writeLocalMatrices(selection: selection, frameSamples: animationFrame.samples,
        blends: animationFrame.blends, into: &matrices)
    var coverage: [Float] = [0], scratch: [Float] = [0]
    try evaluator.writeVertexCoverages(selection: selection, frameSamples: animationFrame.samples,
        blends: animationFrame.blends, into: &coverage, boneScratch: &scratch)
    return [Double(matrices[0].columns.3.x), Double(coverage[0])]
}

func denseStateRuntimeReport() throws -> [[String: Any]] {
    var output: [[String: Any]] = []
    for (id, tag) in [(1, "held"), (917, "renamed-σ")] {
        func held(_ state: SceneMdlPuppetAnimation.TransformTrackState?) -> SceneMdlPuppetAnimation {
            .init(id: id, name: tag, mode: "loop", framesPerSecond: 2, frameCount: 4,
                transformsByBone: [Array(repeating: .init(translation: .zero, rotation: .zero,
                    scale: SIMD3(repeating: 1)), count: 5)],
                transformTrackStates: state.map { [$0] }, alphaByBone: [[1,0.75,0.5,0.25,1]],
                events: [event("\(tag)-cue", 1)])
        }
        let ownerLayer = layer(animationID: id)
        let definition = selection(ownerLayer, held(.referenceCandidate))
        let runtime = try eventRuntime(definition)
        _ = step(runtime, 0, 0)
        let first = step(runtime, 1, 0.5)
        let same = registration(runtime.register(layerID: 42, selection: definition,
            authoredLayers: [ownerLayer]))
        let changed = selection(ownerLayer, held(.sampled))
        let result = runtime.register(layerID: 42, selection: changed, authoredLayers: [ownerLayer])
        let conflict: Bool
        if case let .failure(failure) = result { conflict = failure == .conflictingDefinition(layerID: 42) }
        else { conflict = false }
        let next = step(runtime, 2, 1)
        let hidden = step(runtime, 3, 1.5, visible: false)
        let resumed = step(runtime, 4, 1.75)
        let defaultRuntime = try eventRuntime(selection(ownerLayer, held(nil)))
        let defaultEquivalent = registration(defaultRuntime.register(layerID: 42,
            selection: changed, authoredLayers: [ownerLayer]))
        output.append(["same": same, "stateOnlyConflict": conflict,
            "defaultEquivalent": defaultEquivalent, "firstSamples": report(first),
            "firstPoseAlpha": try evaluate(first, selection: definition),
            "firstEvents": events(first).map { $0["name"] as! String },
            "nextSamples": report(next), "nextPoseAlpha": try evaluate(next, selection: definition),
            "hidden": report(hidden), "resumed": report(resumed),
            "resumedPoseAlpha": try evaluate(resumed, selection: definition)])
    }
    return output
}

func singleInstanceReport() throws -> [[String: Any]] {
    try [(739, "track"), (891, "renamed-resource")].map { id, name in
        let base = animation(id: id, mode: "single")
        let source = SceneMdlPuppetAnimation(id: id, name: name, mode: base.mode,
            framesPerSecond: base.framesPerSecond, frameCount: base.frameCount,
            transformsByBone: base.transformsByBone)
        let runtime = ScenePuppetAnimationPlaybackRuntime()
        let empty = ScenePuppetAnimationSelection(clips: [], composition: .layered)
        try runtime.register(layerID: 42, selection: empty, authoredLayers: [],
            availableSingleAnimations: [source]).get()
        let peer = selection(layer(binding: nil), animation())
        try runtime.register(layerID: 77, selection: peer, authoredLayers: peer.clips.map(\.layer)).get()
        let original = step(runtime, 0, 200)
        let birth = ScenePuppetAnimationIdentity(layerID: 42, creationEpoch: 1, creationOrdinal: 0)
        let create = control(birth, .createSingle(animationID: id), 1)
        let atomic = !registration(runtime.validate([create,
            control(birth, .setRate(.nan), 1, 1)], frameIndex: 0))
            && !runtime.snapshots().contains { $0.identity.layerID == 42 }
        let metadata = runtime.singleAnimationSource(layerID: 42, name: name)
        try runtime.apply([create], frameIndex: 0).get()
        let born = runtime.snapshots().first { $0.identity == birth }!
        let frozen = step(runtime, 0, 999)
        let moving = step(runtime, 1, 200.25)
        try runtime.apply([control(birth, .pause, 2),
            control(birth, .setFrame(1.5), 2, 1)], frameIndex: 1).get()
        let paused = step(runtime, 2, 201)
        try runtime.register(layerID: 42, selection: empty, authoredLayers: [],
            availableSingleAnimations: [source]).get()
        let rebuilt = runtime.snapshots().first { $0.identity == birth }!
        try runtime.apply([control(birth, .play, 3)], frameIndex: 2).get()
        let resumed = step(runtime, 3, 201.25)
        try runtime.apply([control(birth, .stop, 4)], frameIndex: 3).get()
        let stopped = step(runtime, 4, 300)
        try runtime.apply([control(birth, .setFrame(4), 5)], frameIndex: 4).get()
        let terminalPause = step(runtime, 5, 400)
        try runtime.apply([control(birth, .play, 6)], frameIndex: 5).get()
        let still = step(runtime, 6, 400)
        let ended = step(runtime, 7, 500)
        let same = step(runtime, 7, 900)
        let expired = !registration(runtime.validate([control(birth, .pause, 7)], frameIndex: 7))
        try runtime.register(layerID: 42, selection: empty, authoredLayers: [],
            availableSingleAnimations: [source]).get()
        let noRevive = !runtime.snapshots().contains { $0.identity == birth }
        runtime.synchronizeDynamicLayers(topologyRevision: 1, liveLayerIDs: [], destroyedAuthoredLayerIDs: [42])
        return ["sourceID": id, "sourceLookup": metadata?.animationID == id
                && runtime.singleAnimationSource(layerID: 77, name: name) == nil,
            "atomicRollback": atomic, "bornFrame": born.currentFrame,
            "createdIdentity": birth.animationLayerIndex == nil && birth.animationLayerID == nil,
            "frozenEmpty": frozen[42]!.samples.isEmpty && original[42]!.samples.isEmpty,
            "lateFrame": moving.animationSnapshots.first { $0.identity == birth }!.currentFrame,
            "pausedFrame": paused.animationSnapshots.first { $0.identity == birth }!.currentFrame,
            "pausedSample": report(paused), "rebuiltFrame": rebuilt.currentFrame,
            "resumedFrame": resumed.animationSnapshots.first { $0.identity == birth }!.currentFrame,
            "stoppedFrame": stopped.animationSnapshots.first { $0.identity == birth }!.currentFrame,
            "terminalPause": terminalPause.animationSnapshots.contains { $0.identity == birth }
                && still.animationSnapshots.contains { $0.identity == birth },
            "removed": ended[42]!.samples.isEmpty && ended[42]!.selection!.clips.isEmpty
                && !ended.animationSnapshots.contains { $0.identity == birth },
            "retirementRevision": ended[42]!.membershipRevision,
            "sameFrozen": same[42]!.membershipRevision == ended[42]!.membershipRevision
                && same[42]!.samples.isEmpty,
            "quietSingle": ended.animationEvents.isEmpty && !born.supportsEndedCallbacks,
            "expiredRejected": expired, "noRevive": noRevive,
            "peerAlive": ended[77] != nil && ended.animationSnapshots.contains { $0.identity.layerID == 77 },
            "retiredSource": runtime.singleAnimationSource(layerID: 42, name: name) == nil]
    }
}

@main enum Harness {
    static func main() throws {
        var output: [String: Any] = [:]
        let definition = selection(layer(), animation())
        let runtime = ScenePuppetAnimationPlaybackRuntime()
        try runtime.register(layerID: 42, selection: definition,
            authoredLayers: definition.clips.map(\.layer)).get()
        let first = runtime.advance(frameIndex: 0, sceneTime: 0.5, dynamicValues: visible([42: true]))
        let beforeHide = runtime.advance(frameIndex: 1, sceneTime: 1, dynamicValues: visible([42: true]))
        let hidden = runtime.advance(frameIndex: 2, sceneTime: 2, dynamicValues: visible([42: false]))
        _ = runtime.advance(frameIndex: 3, sceneTime: 10, dynamicValues: visible([42: false]))
        let resumed = runtime.advance(frameIndex: 4, sceneTime: 10.25, dynamicValues: visible([42: true]))
        let reads = Observation.visibilityReads
        let duplicate = runtime.advance(frameIndex: 4, sceneTime: 100, dynamicValues: visible([42: false]))
        let stale = runtime.advance(frameIndex: 3, sceneTime: 100, dynamicValues: visible([42: false]))
        output["hiddenResume"] = ["first": report(first), "beforeHide": report(beforeHide),
            "hidden": report(hidden), "resumed": report(resumed), "duplicate": report(duplicate),
            "stale": report(stale), "duplicateSceneTime": duplicate.sceneTime,
            "visibilityReadOnce": Observation.visibilityReads == reads,
            "oldSnapshotRetained": report(beforeHide) == [[2, 3, 0]]]

        let sameRegistration = registration(runtime.register(layerID: 42, selection: definition,
            authoredLayers: definition.clips.map(\.layer)))
        let afterRebuild = runtime.advance(frameIndex: 5, sceneTime: 10.5,
            dynamicValues: visible([42: true]))
        let changed = selection(layer(), animation(fps: 4))
        let conflict = registration(runtime.register(layerID: 42, selection: changed,
            authoredLayers: changed.clips.map(\.layer)))
        let changedAlpha = selection(layer(), animation(alpha: [[1, 1, 1, 1, 0.5]]))
        let alphaConflict = registration(runtime.register(layerID: 42, selection: changedAlpha,
            authoredLayers: changedAlpha.clips.map(\.layer)))
        let afterConflict = runtime.advance(frameIndex: 6, sceneTime: 10.75,
            dynamicValues: visible([42: true]))
        output["registration"] = ["same": sameRegistration, "afterRebuild": report(afterRebuild),
            "conflictAccepted": conflict, "alphaConflictAccepted": alphaConflict,
            "afterConflict": report(afterConflict)]

        let initialHidden = ScenePuppetAnimationPlaybackRuntime()
        try initialHidden.register(layerID: 42, selection: definition,
            authoredLayers: definition.clips.map(\.layer)).get()
        _ = initialHidden.advance(frameIndex: 0, sceneTime: 5, dynamicValues: visible([42: false]))
        _ = initialHidden.advance(frameIndex: 1, sceneTime: 8, dynamicValues: visible([42: false]))
        output["initialHiddenResume"] = report(initialHidden.advance(frameIndex: 2,
            sceneTime: 8.25, dynamicValues: visible([42: true])))

        var natural: [String: Bool] = [:]
        for mode in ["single", "loop", "mirror"] {
            for rate in [0.5, 1, 1.5] {
                let clip = selection(layer(rate: rate, binding: nil), animation(mode: mode))
                let owner = ScenePuppetAnimationPlaybackRuntime()
                try owner.register(layerID: 42, selection: clip,
                    authoredLayers: clip.clips.map(\.layer)).get()
                var matches = true
                for (index, time) in [2.75, 3.0, 4.25, 6.5].enumerated() {
                    let frame = owner.advance(frameIndex: UInt64(index), sceneTime: time,
                        dynamicValues: visible([:]))
                    matches = matches && frame[42]!.samples[0] == ScenePuppetAnimationEvaluator.frameSample(
                        sceneTime: time, rate: rate, animation: clip.clips[0].animation)
                }
                natural["\(mode)-\(rate)"] = matches
            }
        }
        output["naturalSamples"] = natural

        let parentOwner = ScenePuppetAnimationPlaybackRuntime()
        try parentOwner.register(layerID: 42, selection: definition,
            authoredLayers: definition.clips.map(\.layer)).get()
        try parentOwner.register(layerID: 77, selection: definition,
            authoredLayers: definition.clips.map(\.layer)).get()
        _ = parentOwner.advance(frameIndex: 0, sceneTime: 0, dynamicValues: visible([42: true, 77: true]))
        let independent = parentOwner.advance(frameIndex: 1, sceneTime: 0.25,
            dynamicValues: visible([42: false, 77: true]))
        output["parentIdentity"] = ["hidden": report(independent), "visible": report(independent, layerID: 77)]

        let authoredOwner = ScenePuppetAnimationPlaybackRuntime()
        let extra = layer(id: 9, visible: false, binding: nil)
        try authoredOwner.register(layerID: 42, selection: definition,
            authoredLayers: [extra, definition.clips[0].layer]).get()
        output["authoredPositionConflictAccepted"] = registration(authoredOwner.register(
            layerID: 42, selection: definition, authoredLayers: [definition.clips[0].layer]))

        let invalidVisibilityOwner = ScenePuppetAnimationPlaybackRuntime()
        try invalidVisibilityOwner.register(layerID: 42, selection: definition,
            authoredLayers: definition.clips.map(\.layer)).get()
        let missing = invalidVisibilityOwner.advance(frameIndex: 0, sceneTime: 5,
            dynamicValues: visible([:]))
        let wrong = invalidVisibilityOwner.advance(frameIndex: 1, sceneTime: 6,
            dynamicValues: .init(values: [ScenePuppetAnimationPropertyTarget.visibility(
                layerID: 42, animationLayerID: 10): .init(value: .scalar(1))]))
        let valid = invalidVisibilityOwner.advance(frameIndex: 2, sceneTime: 6.25,
            dynamicValues: visible([42: true]))
        output["invalidVisibility"] = ["missing": report(missing), "wrong": report(wrong),
            "restored": report(valid)]

        let initiallyEmpty = ScenePuppetAnimationPlaybackRuntime()
        let emptyFrame = initiallyEmpty.advance(frameIndex: 7, sceneTime: 2.5,
            dynamicValues: visible([:]))
        try initiallyEmpty.register(layerID: 42, selection: definition,
            authoredLayers: definition.clips.map(\.layer)).get()
        let filledEmpty = initiallyEmpty.advance(frameIndex: 7, sceneTime: 100,
            dynamicValues: visible([42: true]))
        output["pausedEmptyRegistration"] = ["oldFrameStaysEmpty": emptyFrame[42] == nil,
            "filled": report(filledEmpty), "sceneTime": filledEmpty.sceneTime]

        let lateParent = ScenePuppetAnimationPlaybackRuntime()
        try lateParent.register(layerID: 42, selection: definition,
            authoredLayers: definition.clips.map(\.layer)).get()
        let oldParent = lateParent.advance(frameIndex: 7, sceneTime: 2.5,
            dynamicValues: visible([42: true]))
        try lateParent.register(layerID: 77, selection: definition,
            authoredLayers: definition.clips.map(\.layer)).get()
        let readsBeforeFill = Observation.visibilityReads
        let filled = lateParent.advance(frameIndex: 7, sceneTime: 200,
            dynamicValues: visible([42: false, 77: true]))
        let readsAfterFill = Observation.visibilityReads
        let repeated = lateParent.advance(frameIndex: 7, sceneTime: 300,
            dynamicValues: visible([42: false, 77: false]))
        let readsAfterRepeat = Observation.visibilityReads
        let next = lateParent.advance(frameIndex: 8, sceneTime: 2.75,
            dynamicValues: visible([42: true, 77: true]))
        output["pausedLateRegistration"] = ["oldParent": report(oldParent),
            "retainedParent": report(filled), "newParent": report(filled, layerID: 77),
            "repeatedParent": report(repeated, layerID: 77), "sceneTime": filled.sceneTime,
            "onlyNewVisibilityRead": readsAfterFill - readsBeforeFill == 1,
            "repeatReadsNoVisibility": readsAfterRepeat == readsAfterFill,
            "oldSnapshotMissingNewParent": oldParent[77] == nil,
            "nextOldParent": report(next), "nextNewParent": report(next, layerID: 77)]
        let controlledDefinition = selection(layer(binding: nil),
            animation(alpha: [[1, 0.75, 0.5, 0.25, 0]]))
        let controlled = ScenePuppetAnimationPlaybackRuntime()
        try controlled.register(layerID: 42, selection: controlledDefinition,
            authoredLayers: [extra, controlledDefinition.clips[0].layer]).get()
        let controlFirst = controlled.advance(frameIndex: 0, sceneTime: 0, dynamicValues: visible([:]))
        let identity = controlled.snapshots()[0].identity
        let initCommands = [control(identity, .setFrame(4 * 0.93), 1, 1), control(identity, .play, 1)]
        let beforeValidation = controlled.snapshots()
        try controlled.validate(initCommands, frameIndex: 0).get()
        output["controlAdmissionPure"] = beforeValidation == controlled.snapshots()
        try controlled.apply(initCommands, frameIndex: 0).get()
        output["controlInit"] = ["metadata": state(controlFirst.animationSnapshots[0]),
            "committed": state(controlled.snapshots()[0]),
            "sameCadence": report(controlled.advance(frameIndex: 0, sceneTime: 100,
                dynamicValues: visible([:]))), "oldPose": try evaluate(controlFirst, selection: controlledDefinition)]
        let seekNext = controlled.advance(frameIndex: 1, sceneTime: 0.01, dynamicValues: visible([:]))
        output["seekNext"] = ["frame": state(seekNext.animationSnapshots[0]),
            "poseAlpha": try evaluate(seekNext, selection: controlledDefinition)]
        try controlled.apply([control(identity, .setRate(2), 2)], frameIndex: 1).get()
        let rateNext = controlled.advance(frameIndex: 2, sceneTime: 0.26, dynamicValues: visible([:]))
        try controlled.apply([control(identity, .pause, 3)], frameIndex: 2).get()
        let paused = controlled.advance(frameIndex: 3, sceneTime: 10, dynamicValues: visible([:]))
        try controlled.apply([control(identity, .stop, 4)], frameIndex: 3).get()
        let stopped = controlled.advance(frameIndex: 4, sceneTime: 20, dynamicValues: visible([:]))
        try controlled.apply([control(identity, .play, 5)], frameIndex: 4).get()
        let restarted = controlled.advance(frameIndex: 5, sceneTime: 20.125, dynamicValues: visible([:]))
        output["playbackControls"] = ["rate": state(rateNext.animationSnapshots[0]),
            "paused": state(paused.animationSnapshots[0]), "stopped": state(stopped.animationSnapshots[0]),
            "restarted": state(restarted.animationSnapshots[0])]

        try controlled.apply([control(identity, .pause, 6)], frameIndex: 5).get()
        var seeks: [[String: Any]] = []
        for (index, value) in [-1.0, 4, 4.5, 8.5, 0.5, 1].enumerated() {
            try controlled.apply([control(identity, .setFrame(value), UInt64(index + 7))],
                frameIndex: UInt64(index + 5)).get()
            let frame = controlled.advance(frameIndex: UInt64(index + 6),
                sceneTime: 21 + Double(index), dynamicValues: visible([:]))
            seeks.append(["raw": controlled.snapshots()[0].currentFrame, "samples": report(frame),
                "poseAlpha": try evaluate(frame, selection: controlledDefinition),
                "ended": controlled.snapshots()[0].endedSequence])
        }
        output["explicitSeeks"] = seeks
        let beforeBlend = controlled.advance(frameIndex: 11, sceneTime: 26, dynamicValues: visible([:]))
        try controlled.apply([control(identity, .setBlend(0.5), 13)], frameIndex: 11).get()
        let sameBlendCadence = controlled.advance(frameIndex: 11, sceneTime: 900, dynamicValues: visible([:]))
        let afterBlend = controlled.advance(frameIndex: 12, sceneTime: 27, dynamicValues: visible([:]))
        output["controlledBlend"] = ["old": try evaluate(beforeBlend, selection: controlledDefinition),
            "sameCadence": try evaluate(sameBlendCadence, selection: controlledDefinition),
            "next": try evaluate(afterBlend, selection: controlledDefinition),
            "blend": afterBlend[42]!.blends!,
            "sameRegistration": registration(controlled.register(layerID: 42,
                selection: controlledDefinition, authoredLayers: [extra, controlledDefinition.clips[0].layer]))]

        let hiddenControl = ScenePuppetAnimationPlaybackRuntime()
        let scriptLayer = layer(visible: false, binding: nil, script: true)
        let scriptDefinition = selection(scriptLayer, animation())
        try hiddenControl.register(layerID: 42, selection: scriptDefinition,
            authoredLayers: [scriptLayer]).get()
        _ = hiddenControl.advance(frameIndex: 0, sceneTime: 5, dynamicValues: visible([42: false]))
        let scriptIdentity = hiddenControl.snapshots()[0].identity
        try hiddenControl.apply([control(scriptIdentity, .setFrame(0.5), 1),
            control(scriptIdentity, .setVisible(true), 1, 1)], frameIndex: 0).get()
        let visibleSetter = hiddenControl.snapshots()[0].visible
        let boolReturnHidden = hiddenControl.advance(frameIndex: 1, sceneTime: 10,
            dynamicValues: visible([42: false]))
        let scriptRestore = hiddenControl.advance(frameIndex: 2, sceneTime: 10.25,
            dynamicValues: visible([42: true]))
        output["scriptVisibility"] = ["setterImmediate": visibleSetter,
            "hidden": state(boolReturnHidden.animationSnapshots[0]), "hiddenSamples": report(boolReturnHidden),
            "restored": state(scriptRestore.animationSnapshots[0]), "restoreSamples": report(scriptRestore)]

        var scriptFallbacks: [Bool] = []
        for id in [10, -1] {
            var fallback = layer(binding: nil, script: true)
            if id < 0 {
                fallback = .init(id: nil, animationID: 1, name: "fallback", additive: true,
                    blend: 1, blendIn: false, blendOut: false, blendTime: 0,
                    rate: 1, visible: true, visibilityBinding: nil, hasVisibilityScript: true)
            }
            let owner = ScenePuppetAnimationPlaybackRuntime()
            let candidate = selection(fallback, animation())
            try owner.register(layerID: 42, selection: candidate, authoredLayers: [fallback]).get()
            let frame = owner.advance(frameIndex: 0, sceneTime: 0.25, dynamicValues: visible([:]))
            scriptFallbacks.append(frame[42]!.samples[0] != nil && frame.animationSnapshots[0].visible)
        }
        output["unadmittedScriptFallbacks"] = scriptFallbacks

        let zeroRate = ScenePuppetAnimationPlaybackRuntime()
        try zeroRate.register(layerID: 42, selection: controlledDefinition,
            authoredLayers: [controlledDefinition.clips[0].layer]).get()
        _ = zeroRate.advance(frameIndex: 0, sceneTime: 0.5, dynamicValues: visible([:]))
        let zeroIdentity = zeroRate.snapshots()[0].identity
        try zeroRate.apply([control(zeroIdentity, .setRate(0), 1)], frameIndex: 0).get()
        let noMovement = zeroRate.advance(frameIndex: 1, sceneTime: 10, dynamicValues: visible([:]))
        try zeroRate.apply([control(zeroIdentity, .setRate(1), 2), control(zeroIdentity, .setVisible(false), 2, 1)],
            frameIndex: 1).get()
        let staticHidden = zeroRate.advance(frameIndex: 2, sceneTime: 20, dynamicValues: visible([:]))
        try zeroRate.apply([control(zeroIdentity, .setVisible(true), 3)], frameIndex: 2).get()
        let staticRestored = zeroRate.advance(frameIndex: 3, sceneTime: 20.25, dynamicValues: visible([:]))
        output["zeroRateStaticVisible"] = ["zero": state(noMovement.animationSnapshots[0]),
            "hidden": state(staticHidden.animationSnapshots[0]), "hiddenSamples": report(staticHidden),
            "restored": state(staticRestored.animationSnapshots[0])]

        let lateControlled = ScenePuppetAnimationPlaybackRuntime()
        try lateControlled.register(layerID: 42, selection: controlledDefinition,
            authoredLayers: [controlledDefinition.clips[0].layer]).get()
        let lateFrozen = lateControlled.advance(frameIndex: 7, sceneTime: 0.5, dynamicValues: visible([:]))
        let lateID = lateControlled.snapshots()[0].identity
        try lateControlled.apply([control(lateID, .pause, 1), control(lateID, .setFrame(3), 1, 1),
            control(lateID, .setBlend(0.5), 1, 2)], frameIndex: 7).get()
        try lateControlled.register(layerID: 77, selection: controlledDefinition,
            authoredLayers: [controlledDefinition.clips[0].layer]).get()
        let lateFilled = lateControlled.advance(frameIndex: 7, sceneTime: 200, dynamicValues: visible([:]))
        let lateNext = lateControlled.advance(frameIndex: 8, sceneTime: 0.75, dynamicValues: visible([:]))
        output["controlledLateRegistration"] = ["frozenStateRetained": lateFrozen.animationSnapshots[0]
            == lateFilled.animationSnapshots[0], "frozenPoseRetained": report(lateFrozen) == report(lateFilled),
            "frozenBlend": lateFilled[42]!.blends!, "newParent": report(lateFilled, layerID: 77),
            "sceneTime": lateFilled.sceneTime, "next": state(lateNext.animationSnapshots[0]),
            "nextPoseAlpha": try evaluate(lateNext, selection: controlledDefinition)]

        let isolated = ScenePuppetAnimationPlaybackRuntime()
        for parent in [42, 77] {
            try isolated.register(layerID: parent, selection: controlledDefinition,
                authoredLayers: [controlledDefinition.clips[0].layer]).get()
        }
        _ = isolated.advance(frameIndex: 0, sceneTime: 0, dynamicValues: visible([:]))
        let safeIdentity = isolated.snapshots()[0].identity
        let crossRuntime = ScenePuppetAnimationPlaybackRuntime()
        for parent in [42, 77] {
            try crossRuntime.register(layerID: parent, selection: controlledDefinition,
                authoredLayers: [controlledDefinition.clips[0].layer]).get()
        }
        _ = crossRuntime.advance(frameIndex: 0, sceneTime: 0, dynamicValues: visible([:]))
        let crossIdentity = crossRuntime.snapshots().first { $0.identity.layerID == 77 }!.identity
        let hiddenSeek = [control(crossIdentity, .setVisible(false), 0),
            control(crossIdentity, .setFrame(2.5), 0, 1)]
        let hiddenRejected = !registration(crossRuntime.validate(hiddenSeek,
            sourceLayerID: 42, sourceAnimationLayerID: safeIdentity.animationLayerID!, frameIndex: 0))
        try crossRuntime.apply([control(crossIdentity, .setVisible(false), 0)], frameIndex: 0).get()
        let crossSeek = [control(crossIdentity, .pause, 0, 1), control(crossIdentity, .setFrame(2.5), 0, 2)]
        let crossAccepted = registration(crossRuntime.validate(crossSeek,
            sourceLayerID: 42, sourceAnimationLayerID: safeIdentity.animationLayerID!, frameIndex: 0))
        try crossRuntime.apply(crossSeek, frameIndex: 0).get()
        output["crossParentHiddenSeek"] = [hiddenRejected, crossAccepted,
            crossRuntime.snapshots().first { $0.identity == crossIdentity }?.visible == false,
            crossRuntime.snapshots().first { $0.identity == crossIdentity }?.currentFrame == 2.5,
            crossRuntime.snapshots().first { $0.identity == safeIdentity }?.currentFrame == 0]
        let wrongIdentities = [ScenePuppetAnimationIdentity(layerID: 99, animationLayerIndex: 0, animationLayerID: 10),
            .init(layerID: 42, animationLayerIndex: 1, animationLayerID: 10),
            .init(layerID: 42, animationLayerIndex: 0, animationLayerID: 11)]
        var rejected: [Bool] = []
        for wrongID in wrongIdentities {
            rejected.append(!registration(isolated.apply([control(safeIdentity, .pause, 1),
                control(wrongID, .setFrame(2), 1, 1)], frameIndex: 0)))
        }
        for bad in [Double.nan, .infinity, -Double.infinity, Double.greatestFiniteMagnitude] {
            rejected.append(!registration(isolated.apply([control(safeIdentity, .pause, 1),
                control(safeIdentity, .setFrame(bad), 1, 1)], frameIndex: 0)))
        }
        for action in [ScenePuppetAnimationCommand.Action.setRate(-1), .setBlend(-1), .setRate(.nan),
                       .setBlend(.infinity)] {
            rejected.append(!registration(isolated.apply([control(safeIdentity, .pause, 1),
                control(safeIdentity, action, 1, 1)], frameIndex: 0)))
        }
        let invalidCadence = !registration(isolated.apply([control(safeIdentity, .pause, 1)], frameIndex: 1))
        let budget = (0...ScenePuppetAnimationPlaybackRuntime.commandBudget).map {
            control(safeIdentity, .pause, 1, UInt32($0))
        }
        let invalidBudget = !registration(isolated.apply(budget, frameIndex: 0))
        let unchangedAfterRejection = isolated.snapshots().allSatisfy { $0.currentFrame == 0 && $0.isPlaying }
        let validCommands = [control(safeIdentity, .pause, 2), control(safeIdentity, .setFrame(1.5), 2, 1)]
        try isolated.apply(validCommands, frameIndex: 0).get()
        let replayAccepted = registration(isolated.apply(validCommands, frameIndex: 0))
        let conflictingReplay = !registration(isolated.apply([control(safeIdentity, .stop, 2)], frameIndex: 0))
        let staleCommand = !registration(isolated.apply([control(safeIdentity, .play, 1)], frameIndex: 0))
        let isolatedNext = isolated.advance(frameIndex: 1, sceneTime: 0.25, dynamicValues: visible([:]))
        output["controlFailures"] = ["allRejected": rejected.allSatisfy { $0 }, "invalidCadence": invalidCadence,
            "invalidBudget": invalidBudget, "unchanged": unchangedAfterRejection,
            "replayAccepted": replayAccepted, "conflictingReplay": conflictingReplay,
            "stale": staleCommand, "controlled": report(isolatedNext), "other": report(isolatedNext, layerID: 77)]

        let budgetOwner = ScenePuppetAnimationPlaybackRuntime()
        try budgetOwner.register(layerID: 42, selection: controlledDefinition,
            authoredLayers: [controlledDefinition.clips[0].layer]).get()
        _ = budgetOwner.advance(frameIndex: 0, sceneTime: 0, dynamicValues: visible([:]))
        let budgetID = budgetOwner.snapshots()[0].identity
        let fullBudget = (0..<ScenePuppetAnimationPlaybackRuntime.commandBudget).map {
            control(budgetID, .setFrame(2), 1, UInt32($0))
        }
        try budgetOwner.apply(fullBudget, frameIndex: 0).get()
        let overflowRejected = !registration(budgetOwner.apply([control(budgetID, .setFrame(3), 2)], frameIndex: 0))
        let budgetStateRetained = budgetOwner.snapshots()[0].currentFrame == 2
        _ = budgetOwner.advance(frameIndex: 1, sceneTime: 0, dynamicValues: visible([:]))
        let nextCadenceAccepted = registration(budgetOwner.apply([control(budgetID, .setFrame(3), 2)], frameIndex: 1))
        output["aggregateBudget"] = ["overflowRejected": overflowRejected, "stateRetained": budgetStateRetained,
            "nextCadenceAccepted": nextCadenceAccepted, "frame": budgetOwner.snapshots()[0].currentFrame]

        let ended = ScenePuppetAnimationPlaybackRuntime()
        try ended.register(layerID: 42, selection: controlledDefinition,
            authoredLayers: [controlledDefinition.clips[0].layer]).get()
        _ = ended.advance(frameIndex: 0, sceneTime: 0, dynamicValues: visible([:]))
        _ = ended.advance(frameIndex: 1, sceneTime: 1.75, dynamicValues: visible([:]))
        let crossing = ended.advance(frameIndex: 2, sceneTime: 2.25, dynamicValues: visible([:]))
        let repeatedCrossing = ended.advance(frameIndex: 2, sceneTime: 100, dynamicValues: visible([:]))
        let endedIdentity = ended.snapshots()[0].identity
        try ended.apply([control(endedIdentity, .pause, 1), control(endedIdentity, .setFrame(4), 1, 1)],
            frameIndex: 2).get()
        let pausedEndpoint = ended.advance(frameIndex: 3, sceneTime: 20, dynamicValues: visible([:]))
        try ended.apply([control(endedIdentity, .setFrame(3.5), 2), control(endedIdentity, .play, 2, 1)],
            frameIndex: 3).get()
        let secondCrossing = ended.advance(frameIndex: 4, sceneTime: 20.5, dynamicValues: visible([:]))
        let multiple = ended.advance(frameIndex: 5, sceneTime: 30.5, dynamicValues: visible([:]))
        output["ended"] = ["crossing": state(crossing.animationSnapshots[0]),
            "repeated": state(repeatedCrossing.animationSnapshots[0]),
            "pausedEndpoint": state(pausedEndpoint.animationSnapshots[0]),
            "second": state(secondCrossing.animationSnapshots[0]),
            "multiple": state(multiple.animationSnapshots[0]), "multipleSamples": report(multiple)]
        var unsupportedModes: [Bool] = []
        for mode in ["single", "mirror"] {
            let owner = ScenePuppetAnimationPlaybackRuntime()
            let candidate = selection(layer(binding: nil), animation(mode: mode))
            try owner.register(layerID: 42, selection: candidate, authoredLayers: [candidate.clips[0].layer]).get()
            let frame = owner.advance(frameIndex: 0, sceneTime: 2.75, dynamicValues: visible([:]))
            unsupportedModes.append(!frame.animationSnapshots[0].supportsEndedCallbacks
                && frame.animationSnapshots[0].endedFailure == .unsupportedMode)
        }
        output["endedUnsupportedModes"] = unsupportedModes

        let retirement = ScenePuppetAnimationPlaybackRuntime()
        let liveDefinition = selection(layer(binding: nil), animation())
        for id in [42, 77, -1, -2] {
            try retirement.register(layerID: id, selection: liveDefinition,
                authoredLayers: [liveDefinition.clips[0].layer]).get()
        }
        let beforeRetirement = retirement.advance(frameIndex: 1, sceneTime: 2,
            dynamicValues: visible([:]))
        retirement.synchronizeDynamicLayers(topologyRevision: 2, liveLayerIDs: [-2])
        let sameRetirement = retirement.advance(frameIndex: 1, sceneTime: 90,
            dynamicValues: visible([:]))
        let afterRetirement = retirement.advance(frameIndex: 2, sceneTime: 2.5,
            dynamicValues: visible([:]))
        retirement.synchronizeDynamicLayers(topologyRevision: 3, liveLayerIDs: [])
        let rebuiltWithoutHistory = retirement.advance(frameIndex: 2, sceneTime: 90,
            dynamicValues: visible([:]))
        output["dynamicRetirement"] = [rebuiltWithoutHistory[-2] == nil,
            rebuiltWithoutHistory[42] != nil, sameRetirement[-1] == nil,
            sameRetirement[42] != nil, sameRetirement[-2] != nil,
            report(sameRetirement, layerID: -2) == report(beforeRetirement, layerID: -2),
            afterRetirement[-1] == nil,
            report(afterRetirement, layerID: -2) != report(beforeRetirement, layerID: -2),
            !sameRetirement.animationSnapshots.contains { $0.identity.layerID == -1 }]

        retirement.synchronizeDynamicLayers(topologyRevision: 4, liveLayerIDs: [],
            destroyedAuthoredLayerIDs: [42])
        let authoredRetired = retirement.advance(frameIndex: 2, sceneTime: 90,
            dynamicValues: visible([:]))
        let nextAuthoredRetired = retirement.advance(frameIndex: 3, sceneTime: 3,
            dynamicValues: visible([:]))
        output["authoredRetirement"] = [authoredRetired[42] == nil,
            nextAuthoredRetired[42] == nil, authoredRetired[77] != nil,
            report(authoredRetired, layerID: 77) == report(rebuiltWithoutHistory, layerID: 77),
            !authoredRetired.animationSnapshots.contains { $0.identity.layerID == 42 },
            !authoredRetired.animationEvents.contains { $0.identity.layerID == 42 },
            !authoredRetired.eventFailures.keys.contains { $0.layerID == 42 }]

        output["animationEvents"] = try animationEventReport()
        output["denseState"] = try denseStateRuntimeReport()
        output["singleInstances"] = try singleInstanceReport()
        print(String(decoding: try JSONSerialization.data(withJSONObject: output,
            options: [.sortedKeys]), as: UTF8.self))
    }
}
