#!/usr/bin/env python3
"""Shared Puppet controls preserve cadence, fractional pose, alpha and owner isolation."""

from __future__ import annotations

import json
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

from script.tests.test_scene_puppet_playback import SCENE_ROOT, SWIFT_SOURCES


HARNESS = r'''
import Foundation
import simd

enum SceneDynamicTarget: Hashable {
    case scriptInstanceProperty(layerID: Int, path: [String])
}
enum SceneDynamicValue { case bool(Bool), number(Double) }
struct SceneDynamicResolvedValue { let value: SceneDynamicValue }
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
               alpha: [[Float]]? = nil) -> SceneMdlPuppetAnimation {
    .init(id: id, name: "track", mode: mode, framesPerSecond: fps, frameCount: 4,
        transformsByBone: [(0...4).map { frame in
            .init(translation: SIMD3(Float(frame), 0, 0), rotation: .zero,
                scale: SIMD3(repeating: 1))
        }], alphaByBone: alpha)
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
    ["parent": snapshot.identity.layerID, "index": snapshot.identity.animationLayerIndex,
     "id": snapshot.identity.animationLayerID as Any, "animationID": snapshot.animationID,
     "name": snapshot.name, "fps": snapshot.framesPerSecond, "count": snapshot.frameCount,
     "duration": snapshot.duration, "frame": snapshot.currentFrame, "playing": snapshot.isPlaying,
     "rate": snapshot.rate, "blend": snapshot.blend, "visible": snapshot.visible,
     "ended": snapshot.endedSequence, "supportsEnded": snapshot.supportsEndedCallbacks,
     "endedFailure": snapshot.endedFailure?.rawValue ?? ""]
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
                layerID: 42, animationLayerID: 10): .init(value: .number(1))]))
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

        print(String(decoding: try JSONSerialization.data(withJSONObject: output,
            options: [.sortedKeys]), as: UTF8.self))
    }
}
'''


class PuppetAnimationPlaybackRuntimeTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        if not shutil.which("swiftc"):
            raise unittest.SkipTest("Swift toolchain unavailable")
        with tempfile.TemporaryDirectory(prefix="mwx-puppet-playback-runtime-") as directory:
            root = Path(directory)
            source, binary = root / "runtime.swift", root / "runtime"
            source.write_text(HARNESS, encoding="utf-8")
            command = ["swiftc", *map(str, SWIFT_SOURCES),
                       str(SCENE_ROOT / "Systems/Puppet/ScenePuppetAnimationControl.swift"),
                       str(SCENE_ROOT / "Systems/Puppet/ScenePuppetAnimationPlaybackRuntime.swift"),
                       str(SCENE_ROOT / "Systems/Properties/ScenePuppetAnimationPropertyTarget.swift"),
                       str(source), "-o", str(binary)]
            run = subprocess.run(command, capture_output=True, text=True, timeout=120)
            if run.returncode:
                raise RuntimeError(run.stdout + run.stderr)
            run = subprocess.run([str(binary)], capture_output=True, text=True, check=True, timeout=30)
            cls.result = json.loads(run.stdout)

    def test_hidden_position_freezes_and_resumes_current_cadence_only(self) -> None:
        result = self.result["hiddenResume"]
        self.assertEqual(result["first"], [[1, 2, 0]])
        self.assertEqual(result["beforeHide"], [[2, 3, 0]])
        self.assertEqual(result["hidden"], [[]])
        self.assertEqual(result["resumed"], [[2, 3, 0.5]])

    def test_initially_hidden_clip_starts_at_zero_before_resume(self) -> None:
        self.assertEqual(self.result["initialHiddenResume"], [[0, 1, 0.5]])

    def test_same_cadence_multi_consumer_and_stale_request_reuse_snapshot(self) -> None:
        result = self.result["hiddenResume"]
        self.assertEqual(result["duplicate"], result["resumed"])
        self.assertEqual(result["stale"], result["resumed"])
        self.assertEqual(result["duplicateSceneTime"], 10.25)
        self.assertTrue(result["visibilityReadOnce"])
        self.assertTrue(result["oldSnapshotRetained"])

    def test_rebuild_registration_keeps_position_and_conflicts_preserve_definition(self) -> None:
        result = self.result["registration"]
        self.assertTrue(result["same"])
        self.assertEqual(result["afterRebuild"], [[3, 4, 0]])
        self.assertFalse(result["conflictAccepted"])
        self.assertFalse(result["alphaConflictAccepted"])
        self.assertEqual(result["afterConflict"], [[3, 4, 0.5]])

    def test_single_loop_mirror_and_rates_preserve_natural_fractional_sampler(self) -> None:
        self.assertEqual(len(self.result["naturalSamples"]), 9)
        self.assertTrue(all(self.result["naturalSamples"].values()))

    def test_parent_layer_identity_prevents_visibility_cross_talk(self) -> None:
        self.assertEqual(self.result["parentIdentity"], {"hidden": [[]], "visible": [[0, 1, 0.5]]})

    def test_authored_position_is_part_of_immutable_registration(self) -> None:
        self.assertFalse(self.result["authoredPositionConflictAccepted"])

    def test_missing_or_wrong_visibility_stays_hidden_and_preserves_zero_position(self) -> None:
        self.assertEqual(self.result["invalidVisibility"],
                         {"missing": [[]], "wrong": [[]], "restored": [[0, 1, 0.5]]})

    def test_paused_cadence_late_registration_fills_only_missing_parent(self) -> None:
        empty = self.result["pausedEmptyRegistration"]
        self.assertTrue(empty["oldFrameStaysEmpty"])
        self.assertEqual(empty["filled"], [[1, 2, 0]])
        self.assertEqual(empty["sceneTime"], 2.5)
        result = self.result["pausedLateRegistration"]
        for name in ("oldParent", "retainedParent", "newParent", "repeatedParent"):
            with self.subTest(frame=name):
                self.assertEqual(result[name], [[1, 2, 0]])
        self.assertEqual(result["sceneTime"], 2.5)
        self.assertTrue(result["onlyNewVisibilityRead"])
        self.assertTrue(result["repeatReadsNoVisibility"])
        self.assertTrue(result["oldSnapshotMissingNewParent"])
        self.assertEqual(result["nextOldParent"], [[1, 2, 0.5]])
        self.assertEqual(result["nextNewParent"], [[1, 2, 0.5]])

    def test_ordered_init_play_seek_preserves_cadence_and_fractional_pose_alpha(self) -> None:
        self.assertTrue(self.result["controlAdmissionPure"])
        result = self.result["controlInit"]
        metadata = result["metadata"]
        self.assertEqual({key: metadata[key] for key in ("parent", "index", "id", "animationID",
                                                       "name", "fps", "count", "duration")},
                         {"parent": 42, "index": 1, "id": 10, "animationID": 1,
                          "name": "track", "fps": 2, "count": 4, "duration": 2})
        self.assertTrue(result["committed"]["playing"])
        self.assertAlmostEqual(result["committed"]["frame"], 3.72, places=6)
        self.assertEqual(result["sameCadence"], [[0, 1, 0]])
        self.assertEqual(result["oldPose"], [0, 1])
        next_frame = self.result["seekNext"]
        self.assertAlmostEqual(next_frame["frame"]["frame"], 3.74, places=6)
        self.assertAlmostEqual(next_frame["poseAlpha"][0], 3.74, places=6)
        self.assertAlmostEqual(next_frame["poseAlpha"][1], 0.065, places=6)

    def test_pause_stop_play_and_rate_changes_preserve_position(self) -> None:
        result = self.result["playbackControls"]
        self.assertAlmostEqual(result["rate"]["frame"], 0.74, places=6)
        self.assertEqual(result["rate"]["rate"], 2)
        self.assertEqual(result["paused"]["frame"], result["rate"]["frame"])
        self.assertFalse(result["paused"]["playing"])
        self.assertEqual(result["stopped"]["frame"], 0)
        self.assertFalse(result["stopped"]["playing"])
        self.assertEqual(result["restarted"]["frame"], 0.5)
        self.assertTrue(result["restarted"]["playing"])

    def test_explicit_seek_keeps_raw_value_and_clamps_only_effective_pose(self) -> None:
        for result, raw in zip(self.result["explicitSeeks"], [-1, 4, 4.5, 8.5, 0.5, 1]):
            with self.subTest(raw=raw):
                self.assertEqual(result["raw"], raw)
                bounded = max(0, min(4, raw))
                self.assertEqual(result["poseAlpha"], [bounded, 1 - bounded / 4])
                self.assertEqual(result["ended"], 1)
        self.assertEqual(self.result["explicitSeeks"][0]["samples"], [[0, 1, 0]])
        self.assertEqual(self.result["explicitSeeks"][1]["samples"], [[3, 4, 1]])

    def test_controlled_blend_updates_pose_and_alpha_at_next_cadence(self) -> None:
        result = self.result["controlledBlend"]
        self.assertEqual(result["old"], [1, 0.75])
        self.assertEqual(result["next"], [0.5, 0.875])
        self.assertEqual(result["sameCadence"], result["old"])
        self.assertEqual(result["blend"], [0.5])
        self.assertTrue(result["sameRegistration"])

    def test_script_visibility_bool_replaces_setter_mirror_and_hidden_position_freezes(self) -> None:
        result = self.result["scriptVisibility"]
        self.assertTrue(result["setterImmediate"])
        self.assertFalse(result["hidden"]["visible"])
        self.assertTrue(result["hidden"]["playing"])
        self.assertEqual(result["hidden"]["frame"], 0.5)
        self.assertEqual(result["hiddenSamples"], [[]])
        self.assertEqual(result["restored"]["frame"], 1)
        self.assertEqual(result["restoreSamples"], [[1, 2, 0]])

    def test_unadmitted_script_presence_retains_authored_visible_fallback(self) -> None:
        self.assertEqual(self.result["unadmittedScriptFallbacks"], [True, True])

    def test_zero_rate_and_static_visibility_setter_preserve_frozen_position(self) -> None:
        result = self.result["zeroRateStaticVisible"]
        self.assertEqual(result["zero"]["frame"], 1)
        self.assertTrue(result["zero"]["playing"])
        self.assertEqual(result["hidden"]["frame"], 1)
        self.assertFalse(result["hidden"]["visible"])
        self.assertEqual(result["hiddenSamples"], [[]])
        self.assertEqual(result["restored"]["frame"], 1.5)

    def test_late_registration_preserves_frozen_samples_metadata_and_pending_controls(self) -> None:
        result = self.result["controlledLateRegistration"]
        self.assertTrue(result["frozenStateRetained"])
        self.assertTrue(result["frozenPoseRetained"])
        self.assertEqual(result["frozenBlend"], [1])
        self.assertEqual(result["newParent"], [[1, 2, 0]])
        self.assertEqual(result["sceneTime"], 0.5)
        self.assertEqual(result["next"]["frame"], 3)
        self.assertFalse(result["next"]["playing"])
        self.assertEqual(result["nextPoseAlpha"], [1.5, 0.625])

    def test_invalid_control_bundle_is_atomic_local_and_cadence_bound(self) -> None:
        result = self.result["controlFailures"]
        for key in ("allRejected", "invalidCadence", "invalidBudget", "unchanged", "replayAccepted",
                    "conflictingReplay", "stale"):
            with self.subTest(check=key):
                self.assertTrue(result[key])
        self.assertEqual(result["controlled"], [[1, 2, 0.5]])
        self.assertEqual(result["other"], [[0, 1, 0.5]])

    def test_command_budget_aggregates_consumed_cadence_and_resets_on_next_cadence(self) -> None:
        self.assertEqual(self.result["aggregateBudget"],
                         {"overflowRejected": True, "stateRetained": True,
                          "nextCadenceAccepted": True, "frame": 3})

    def test_ended_sequence_is_natural_once_per_cadence_and_unknown_profiles_are_typed(self) -> None:
        result = self.result["ended"]
        self.assertEqual(result["crossing"]["frame"], 0.5)
        self.assertEqual(result["crossing"]["ended"], 1)
        self.assertEqual(result["repeated"], result["crossing"])
        self.assertEqual(result["pausedEndpoint"]["frame"], 4)
        self.assertEqual(result["pausedEndpoint"]["ended"], 1)
        self.assertEqual(result["second"]["frame"], 0.5)
        self.assertEqual(result["second"]["ended"], 2)
        self.assertEqual(result["multiple"]["ended"], 2)
        self.assertEqual(result["multiple"]["endedFailure"], "multipleLoopsCrossed")
        self.assertFalse(result["multiple"]["supportsEnded"])
        self.assertEqual(result["multipleSamples"], [[0, 1, 0.5]])
        self.assertTrue(all(self.result["endedUnsupportedModes"]))


if __name__ == "__main__":
    unittest.main()
