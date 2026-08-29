#!/usr/bin/env python3

"""Five-color media events, generation admission, and previous-current rollback."""

from __future__ import annotations

import json
from pathlib import Path
import subprocess
import tempfile
import unittest

try:
    from .scene_vector_vm_test_support import compile_vector_harness
except ImportError:
    from scene_vector_vm_test_support import compile_vector_harness


HARNESS = r'''
@main
enum Harness {
    static func main() throws {
        let descriptor = SceneRenderDescriptor(layers: [
            .init(
                id: 10,
                layerIndex: 0,
                name: "media",
                visible: true,
                originXYZ: [20, 2250, 0],
                scaleXYZ: [1, 1, 1],
                scaleHasScript: true,
                alpha: nil,
                effects: [.init(
                    name: "history",
                    effectID: 100,
                    passes: [.init(
                        passIndex: 0,
                        id: 200,
                        constantShaderValues: [
                            "mediaColor": .init(
                                scriptSource: mediaColorSource,
                                components: [0.2, 0.4, 0.6]
                            ),
                            "mediaRollback": .init(
                                scriptSource: mediaRollbackSource,
                                components: [0.3, 0.4, 0.5]
                            ),
                            "mediaRollbackPeer": .init(
                                scriptSource: mediaRollbackPeerSource,
                                components: [1, 2, 3]
                            ),
                        ]
                    )]
                )]
            )
        ])
        let mediaFrame = SceneScriptFrameInput(
            timing: .init(
                wallDate: Date(timeIntervalSince1970: 0),
                simulationFrameTime: 0.5,
                sceneTime: 2
            ),
            timeZone: TimeZone(secondsFromGMT: 0)!
        )
        let mediaTarget = passTarget("mediaColor")
        let mediaInput = [
            mediaTarget: SceneDynamicValue.vector3(0.2, 0.4, 0.6)
        ]
        let mediaProgram = SceneScriptVectorProgram.compile(
            domain: try SceneScriptQuickJSDomain(),
            descriptor: descriptor,
            scriptBindings: [passBinding(
                key: "mediaColor",
                source: mediaColorSource,
                value: "0.2 0.4 0.6",
                wrapperKeys: ["script", "scriptproperties", "value"],
                properties: [
                    "topColor": .object([
                        "user": .string("fixtureAccent"),
                        "value": .string("0.2 0.4 0.6"),
                    ])
                ]
            )],
            userPropertyDefinitions: [],
            generation: 25
        )
        let blueEvent = SceneScriptMediaThumbnailEventInput(
            hasThumbnail: true,
            primaryColor: .init(0.9, 0.1, 0.2),
            secondaryColor: .init(0.1, 0.3, 1),
            tertiaryColor: .init(0.2, 0.5, 0.8),
            textColor: .init(1, 1, 1),
            highContrastColor: .init(0, 0, 0),
            generation: 1
        )
        let blueStart = mediaProgram.evaluate(
            inputs: mediaInput,
            effectivePropertyValues: [:],
            frame: mediaFrame,
            mediaThumbnailEvent: blueEvent,
            mediaPlaybackEvent: .init(state: 1, generation: 1)
        )
        let blueMidpoint = mediaProgram.evaluate(
            inputs: mediaInput,
            effectivePropertyValues: [:],
            frame: mediaFrame,
            mediaThumbnailEvent: blueEvent,
            mediaPlaybackEvent: .init(state: 1, generation: 1)
        )
        let blueComplete = mediaProgram.evaluate(
            inputs: mediaInput,
            effectivePropertyValues: [:],
            frame: mediaFrame,
            mediaThumbnailEvent: blueEvent,
            mediaPlaybackEvent: .init(state: 1, generation: 1)
        )
        let missingPalette = mediaProgram.evaluate(
            inputs: mediaInput,
            effectivePropertyValues: [
                "fixtureAccent": .string("0.4 0.5 0.6")
            ],
            frame: mediaFrame,
            mediaThumbnailEvent: .init(
                hasThumbnail: true,
                secondaryColor: .zero,
                generation: 2
            ),
            mediaPlaybackEvent: .init(state: 1, generation: 1)
        )

        let retryProgram = SceneScriptVectorProgram.compile(
            domain: try SceneScriptQuickJSDomain(),
            descriptor: descriptor,
            scriptBindings: [passBinding(
                key: "mediaColor",
                source: mediaColorSource,
                value: "0.2 0.4 0.6",
                wrapperKeys: ["script", "scriptproperties", "value"],
                properties: [
                    "topColor": .object([
                        "user": .string("fixtureAccent"),
                        "value": .string("0.2 0.4 0.6"),
                    ])
                ]
            )],
            userPropertyDefinitions: [],
            generation: 28
        )
        let retryBlue = SceneScriptMediaThumbnailEventInput(
            hasThumbnail: true,
            secondaryColor: .init(0.1, 0.3, 1),
            generation: 7
        )
        let retryRed = SceneScriptMediaThumbnailEventInput(
            hasThumbnail: true,
            secondaryColor: .init(1, 0.1, 0.1),
            generation: 7
        )
        let missingInput = retryProgram.evaluate(
            inputs: [:],
            effectivePropertyValues: [:],
            frame: mediaFrame,
            mediaThumbnailEvent: retryBlue,
            mediaPlaybackEvent: .init(state: 1, generation: 7)
        )
        let retryStart = retryProgram.evaluate(
            inputs: mediaInput,
            effectivePropertyValues: [:],
            frame: mediaFrame,
            mediaThumbnailEvent: retryBlue,
            mediaPlaybackEvent: .init(state: 1, generation: 7)
        )
        let retryMidpoint = retryProgram.evaluate(
            inputs: mediaInput,
            effectivePropertyValues: [:],
            frame: mediaFrame,
            mediaThumbnailEvent: retryBlue,
            mediaPlaybackEvent: .init(state: 1, generation: 7)
        )
        let stale = retryProgram.evaluate(
            inputs: mediaInput,
            effectivePropertyValues: [:],
            frame: mediaFrame,
            mediaThumbnailEvent: .init(
                hasThumbnail: true,
                secondaryColor: retryRed.secondaryColor,
                generation: 6
            ),
            mediaPlaybackEvent: .init(state: 1, generation: 6)
        )
        let conflict = retryProgram.evaluate(
            inputs: mediaInput,
            effectivePropertyValues: [:],
            frame: mediaFrame,
            mediaThumbnailEvent: retryRed,
            mediaPlaybackEvent: .init(state: 0, generation: 7)
        )
        let zeroGeneration = retryProgram.evaluate(
            inputs: mediaInput,
            effectivePropertyValues: [:],
            frame: mediaFrame,
            mediaThumbnailEvent: .init(
                hasThumbnail: true,
                secondaryColor: retryRed.secondaryColor,
                generation: 0
            ),
            mediaPlaybackEvent: .init(state: 0, generation: 0)
        )

        let rollbackTarget = passTarget("mediaRollback")
        let rollbackPeerTarget = passTarget("mediaRollbackPeer")
        let rollbackProgram = SceneScriptVectorProgram.compile(
            domain: try SceneScriptQuickJSDomain(),
            descriptor: descriptor,
            scriptBindings: [
                passBinding(
                    key: "mediaRollback",
                    source: mediaRollbackSource,
                    value: "0.3 0.4 0.5"
                ),
                passBinding(
                    key: "mediaRollbackPeer",
                    source: mediaRollbackPeerSource,
                    value: "1 2 3"
                ),
            ],
            userPropertyDefinitions: [],
            generation: 30
        )
        let rollbackBaselineInputs = [
            rollbackTarget: SceneDynamicValue.vector3(0.3, 0.4, 0.5),
            rollbackPeerTarget: SceneDynamicValue.vector3(1, 2, 3),
        ]
        let rollbackBaseline = rollbackProgram.evaluate(
            inputs: rollbackBaselineInputs,
            effectivePropertyValues: [:],
            frame: mediaFrame
        )
        let rollbackFailureLower = SceneDynamicValue.vector3(0.7, 0.8, 0.9)
        let rollbackFailureInputs = [
            rollbackTarget: rollbackFailureLower,
            rollbackPeerTarget: SceneDynamicValue.vector3(1, 2, 3),
        ]
        let rollbackFailure = rollbackProgram.evaluate(
            inputs: rollbackFailureInputs,
            effectivePropertyValues: [:],
            frame: mediaFrame,
            mediaThumbnailEvent: .init(
                hasThumbnail: true,
                secondaryColor: .init(0.1, 0.3, 1),
                generation: 9
            )
        )
        let rollbackFailureSnapshot = SceneDynamicSnapshotResolver().resolve(
            frameIndex: 2,
            generation: 2,
            definitions: rollbackProgram.definitions,
            timelineValues: [rollbackTarget: rollbackFailureLower],
            sceneScriptValues: rollbackFailure.values
        ).snapshot
        let rollbackDisabledLower = SceneDynamicValue.vector3(0.9, 0.7, 0.5)
        let rollbackDisabledInputs = [
            rollbackTarget: rollbackDisabledLower,
            rollbackPeerTarget: SceneDynamicValue.vector3(1, 2, 3),
        ]
        let rollbackDisabled = rollbackProgram.evaluate(
            inputs: rollbackDisabledInputs,
            effectivePropertyValues: [:],
            frame: mediaFrame
        )
        let rollbackDisabledSnapshot = SceneDynamicSnapshotResolver().resolve(
            frameIndex: 3,
            generation: 2,
            definitions: rollbackProgram.definitions,
            timelineValues: [rollbackTarget: rollbackDisabledLower],
            sceneScriptValues: rollbackDisabled.values
        ).snapshot

        let routeBindings = [
                passBinding(
                    key: "mediaColor",
                    source: mediaColorSource,
                    value: "0.2 0.4 0.6",
                    wrapperKeys: ["script", "scriptproperties", "value"],
                    properties: [
                        "topColor": .string("0.2 0.4 0.6")
                    ]
                ),
                passBinding(
                    key: "mediaRollbackPeer",
                    source: mediaRollbackPeerSource,
                    value: "1 2 3"
                ),
            ]
        let routeProjection = SceneScriptVectorProgram.project(
            descriptor: descriptor,
            scriptBindings: routeBindings
        )
        let routeDiscoveryProgram = SceneScriptVectorProgram.compile(
            domain: try SceneScriptQuickJSDomain(),
            descriptor: descriptor,
            scriptBindings: routeBindings,
            userPropertyDefinitions: [],
            generation: 31
        )
        let routeMediaTargets = routeDiscoveryProgram.mediaThumbnailTargets
            .intersection([mediaTarget, rollbackPeerTarget])
        let routeInputs = SceneScriptVectorMediaRouteState.disableGeneric
            .admittedVectorInputs([
                mediaTarget: .vector3(0.2, 0.4, 0.6),
                rollbackPeerTarget: .vector3(1, 2, 3),
            ], mediaOwnerTargets: routeMediaTargets)
        let routePassTargets = SceneScriptVectorMediaRouteState.disableGeneric
            .admittedVectorPassTargets(
                [mediaTarget, rollbackPeerTarget],
                mediaOwnerTargets: routeMediaTargets
            )
        let routeProgram = SceneScriptVectorProgram.compileNonPass(
            domain: try SceneScriptQuickJSDomain(),
            descriptor: descriptor,
            projection: routeProjection,
            userPropertyDefinitions: [],
            generation: 32
        )
        _ = routeProgram.instantiatePassOwners(
            projection: routeProjection,
            admittedTargets: routePassTargets
        )
        let routeFallbackDefinitions =
            SceneScriptVectorMediaRouteState.disableGeneric
                .authoredFallbackDefinitions(
                    routeProjection.uniqueCandidates.map(\.definition),
                    mediaOwnerTargets: routeMediaTargets
                )
        let routeDisabled = routeProgram.evaluate(
            inputs: routeInputs,
            effectivePropertyValues: [:],
            frame: mediaFrame,
            mediaThumbnailEvent: blueEvent,
            mediaPlaybackEvent: .init(state: 1, generation: 1)
        )
        let routeDisabledLower = SceneDynamicValue.vector3(0.8, 0.7, 0.6)
        let routeDisabledSnapshot = SceneDynamicSnapshotResolver().resolve(
            frameIndex: 4,
            generation: 2,
            definitions: routeProgram.definitions + routeFallbackDefinitions,
            timelineValues: [mediaTarget: routeDisabledLower],
            sceneScriptValues: routeDisabled.values
        ).snapshot
        let routeAuthoredFallbackSnapshot = SceneDynamicSnapshotResolver().resolve(
            frameIndex: 5,
            generation: 2,
            definitions: routeProgram.definitions + routeFallbackDefinitions,
            sceneScriptValues: routeDisabled.values
        ).snapshot
        let routeFallbackTargets = Set(
            routeFallbackDefinitions.map(\.target)
        )
        let routeCommittedTargets = Set(routeProgram.definitions.map(\.target))

        let propertyTarget = SceneDynamicTarget.layer(
            layerID: 10,
            field: .origin
        )
        let propertyProgram = SceneScriptVectorProgram.compile(
            domain: try SceneScriptQuickJSDomain(),
            descriptor: descriptor,
            scriptBindings: [objectBinding(
                source: propertyEventSource,
                properties: ["step": .number(3)]
            )],
            userPropertyDefinitions: [],
            generation: 29
        )
        _ = propertyProgram.evaluate(
            inputs: [:],
            effectivePropertyValues: ["mode": .number(4)],
            frame: mediaFrame
        )
        let propertyRecovered = propertyProgram.evaluate(
            inputs: [propertyTarget: .vector3(20, 2250, 0)],
            effectivePropertyValues: ["mode": .number(4)],
            frame: mediaFrame
        )

        let payload: [String: Any] = [
            "bindings": mediaProgram.bindings.count,
            "start": vector(blueStart.values[mediaTarget]),
            "midpoint": vector(blueMidpoint.values[mediaTarget]),
            "complete": vector(blueComplete.values[mediaTarget]),
            "missingPalette": vector(missingPalette.values[mediaTarget]),
            "mediaFailures": blueStart.failures.count
                + blueMidpoint.failures.count
                + blueComplete.failures.count
                + missingPalette.failures.count,
            "missingInputPublished": !missingInput.values.isEmpty,
            "retryStart": vector(retryStart.values[mediaTarget]),
            "retryMidpoint": vector(retryMidpoint.values[mediaTarget]),
            "stale": vector(stale.values[mediaTarget]),
            "conflict": vector(conflict.values[mediaTarget]),
            "zeroGeneration": vector(zeroGeneration.values[mediaTarget]),
            "retryFailures": missingInput.failures.count
                + retryStart.failures.count
                + retryMidpoint.failures.count
                + stale.failures.count
                + conflict.failures.count
                + zeroGeneration.failures.count,
            "rollbackBaseline": vector(
                rollbackBaseline.values[rollbackTarget]
            ),
            "rollbackFailurePublished":
                rollbackFailure.values[rollbackTarget] != nil,
            "rollbackFailureSnapshot": vector(
                rollbackFailureSnapshot[rollbackTarget]?.value
            ),
            "rollbackFailureSnapshotSource":
                rollbackFailureSnapshot[rollbackTarget]?.source.rawValue ?? "",
            "rollbackDisabledPublished":
                rollbackDisabled.values[rollbackTarget] != nil,
            "rollbackDisabledSnapshot": vector(
                rollbackDisabledSnapshot[rollbackTarget]?.value
            ),
            "rollbackDisabledSnapshotSource":
                rollbackDisabledSnapshot[rollbackTarget]?.source.rawValue ?? "",
            "rollbackFailureMutations":
                rollbackFailure.materialFunctionMutations.count,
            "rollbackDisabledMutations":
                rollbackDisabled.materialFunctionMutations.count,
            "rollbackCode": rollbackFailure.failures[rollbackTarget]?.code ?? "",
            "rollbackDetail": rollbackFailure.failures[rollbackTarget].map {
                String(describing: $0)
            } ?? "",
            "rollbackFailurePeer": vector(
                rollbackFailureSnapshot[rollbackPeerTarget]?.value
            ),
            "rollbackFailurePeerSource":
                rollbackFailureSnapshot[
                    rollbackPeerTarget
                ]?.source.rawValue ?? "",
            "rollbackFailurePeerFailed":
                rollbackFailure.failures[rollbackPeerTarget] != nil,
            "rollbackDisabledPeer": vector(
                rollbackDisabledSnapshot[rollbackPeerTarget]?.value
            ),
            "rollbackDisabledPeerSource":
                rollbackDisabledSnapshot[
                    rollbackPeerTarget
                ]?.source.rawValue ?? "",
            "rollbackDisabledPeerFailed":
                rollbackDisabled.failures[rollbackPeerTarget] != nil,
            "routeMediaTargetCount": routeMediaTargets.count,
            "routeCommittedMediaTargetCount":
                routeProgram.mediaThumbnailTargets.count,
            "routeFallbackDefinitionCount": routeFallbackDefinitions.count,
            "routeFallbackTargetsMatch": routeFallbackTargets == routeMediaTargets,
            "routeFallbackOverlap":
                !routeFallbackTargets.isDisjoint(with: routeCommittedTargets),
            "routeInputCount": routeInputs.count,
            "routePassTargetCount": routePassTargets.count,
            "routePassHasMedia": routePassTargets.contains(mediaTarget),
            "routePassHasPeer": routePassTargets.contains(rollbackPeerTarget),
            "routeDisabledMediaPublished":
                routeDisabled.values[mediaTarget] != nil,
            "routeDisabledPeer": vector(
                routeDisabled.values[rollbackPeerTarget]
            ),
            "routeDisabledMutationCount":
                routeDisabled.materialFunctionMutations.count
                + routeDisabled.animationMutations.count
                + routeDisabled.layerMutations.count,
            "routeDisabledSnapshot": vector(
                routeDisabledSnapshot[mediaTarget]?.value
            ),
            "routeDisabledSnapshotSource":
                routeDisabledSnapshot[mediaTarget]?.source.rawValue ?? "",
            "routeAuthoredFallbackSnapshot": vector(
                routeAuthoredFallbackSnapshot[mediaTarget]?.value
            ),
            "routeAuthoredFallbackSource":
                routeAuthoredFallbackSnapshot[mediaTarget]?.source.rawValue ?? "",
            "propertyRecovered": vector(
                propertyRecovered.values[propertyTarget]
            ),
        ]
        let data = try JSONSerialization.data(
            withJSONObject: payload,
            options: [.sortedKeys]
        )
        print(String(decoding: data, as: UTF8.self))
    }

    static func passTarget(_ name: String) -> SceneDynamicTarget {
        .effectConstant(
            layerID: 10,
            effectIndex: 0,
            passIndex: 0,
            name: name
        )
    }

    static func passBinding(
        key: String,
        source: String,
        value: String,
        wrapperKeys: [String] = ["script", "value"],
        properties: [String: SceneJSONValue] = [:]
    ) -> SceneScriptBindingIR {
        .init(
            source: source,
            owner: .init(
                kind: .pass,
                objectIndex: 0,
                objectID: 10,
                effectIndex: 0,
                effectID: 100,
                passIndex: 0,
                passID: 200
            ),
            targetPath: [
                .key("objects"),
                .index(0),
                .key("effects"),
                .index(0),
                .key("passes"),
                .index(0),
                .key("constantshadervalues"),
                .key(key),
            ],
            properties: properties,
            authoredValue: .string(value),
            valueType: .string,
            wrapperKeys: wrapperKeys
        )
    }

    static func objectBinding(
        source: String,
        properties: [String: SceneJSONValue]
    ) -> SceneScriptBindingIR {
        .init(
            source: source,
            owner: .init(
                kind: .object,
                objectIndex: 0,
                objectID: 10,
                effectIndex: nil,
                effectID: nil,
                passIndex: nil,
                passID: nil
            ),
            targetPath: [
                .key("objects"),
                .index(0),
                .key("origin"),
            ],
            properties: properties,
            authoredValue: .string("20 2250 0"),
            valueType: .string,
            wrapperKeys: ["script", "scriptproperties", "value"]
        )
    }

    static func vector(_ value: SceneDynamicValue?) -> [Double] {
        guard case let .vector3(x, y, z)? = value else { return [] }
        return [x, y, z]
    }

    static let mediaColorSource = """
    "use strict"
    export var scriptProperties = createScriptProperties()
      .addColor({name:"topColor",value:new Vec3(0.2,0.4,0.6)}).finish()
    const blendSeconds = 1
    var playbackStatus = 0
    let incomingTint = scriptProperties.topColor
    let outgoingTint = scriptProperties.topColor
    let elapsedSeconds = blendSeconds
    export function mediaThumbnailChanged(event) {
      elapsedSeconds = 0
      outgoingTint = incomingTint
      incomingTint = event.secondaryColor
    }
    export function mediaPlaybackChanged(event) { playbackStatus = event.state }
    export function update() {
      var resultTint = incomingTint
      if (elapsedSeconds < blendSeconds) {
        resultTint = incomingTint.subtract(outgoingTint)
          .multiply(elapsedSeconds / blendSeconds).add(outgoingTint)
        elapsedSeconds += engine.frametime
      }
      if (incomingTint == "0 0 0" || playbackStatus == 0) {
        resultTint = scriptProperties.topColor
      }
      return resultTint
    }
    """

    static let mediaRollbackSource = """
    let failNextUpdate = false
    export function mediaThumbnailChanged(event) {
      thisLayer.getEffect("history").executeMaterialFunction("clearHistory")
      failNextUpdate = event.hasThumbnail
    }
    export function update(value) {
      if (failNextUpdate) {
        throw new Error("rollback update failure")
      }
      return value.multiply(2)
    }
    """

    static let mediaRollbackPeerSource = """
    export function update(value) { return value.multiply(2) }
    """

    static let propertyEventSource = """
    export var scriptProperties = createScriptProperties()
      .addSlider({name:'step',value:1}).finish();
    let applied = 0;
    export function applyUserProperties(changed) {
      if (changed.hasOwnProperty('mode')) {
        applied = scriptProperties.step + engine.userProperties.mode;
      }
    }
    export function update(value) {
      value.x = applied;
      return value;
    }
    """
}
'''


class SceneVectorMediaEventTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.temporary_directory = tempfile.TemporaryDirectory(
            prefix="mwx-scene-vector-media-"
        )
        cls.binary = compile_vector_harness(
            Path(cls.temporary_directory.name),
            HARNESS,
            "vector-media-events",
        )
        completed = subprocess.run(
            [str(cls.binary)],
            check=True,
            capture_output=True,
            text=True,
        )
        cls.value = json.loads(completed.stdout)

    @classmethod
    def tearDownClass(cls) -> None:
        cls.temporary_directory.cleanup()

    def test_five_color_event_runs_before_generic_vec3_update(self) -> None:
        value = self.value
        self.assertEqual(value["bindings"], 1)
        self.assertEqual(value["start"], [0.2, 0.4, 0.6])
        for actual, expected in zip(
            value["midpoint"],
            [0.15, 0.35, 0.8],
            strict=True,
        ):
            self.assertAlmostEqual(actual, expected)
        self.assertEqual(value["complete"], [0.1, 0.3, 1])
        self.assertEqual(value["missingPalette"], [0.4, 0.5, 0.6])
        self.assertEqual(value["mediaFailures"], 0)

    def test_generation_rejection_does_not_consume_retry_or_replace_current(
        self,
    ) -> None:
        value = self.value
        self.assertFalse(value["missingInputPublished"])
        self.assertEqual(value["retryStart"], [0.2, 0.4, 0.6])
        for actual, expected in zip(
            value["retryMidpoint"],
            [0.15, 0.35, 0.8],
            strict=True,
        ):
            self.assertAlmostEqual(actual, expected)
        for key in ("stale", "conflict", "zeroGeneration"):
            self.assertEqual(value[key], [0.1, 0.3, 1])
        self.assertEqual(value["retryFailures"], 0)
        self.assertEqual(value["propertyRecovered"], [7, 2250, 0])

    def test_failure_and_disabled_frames_follow_lower_priority_current(
        self,
    ) -> None:
        value = self.value
        self.assertEqual(value["rollbackBaseline"], [0.6, 0.8, 1.0])
        self.assertFalse(value["rollbackFailurePublished"])
        self.assertEqual(value["rollbackFailureSnapshot"], [0.7, 0.8, 0.9])
        self.assertEqual(value["rollbackFailureSnapshotSource"], "timeline")
        self.assertFalse(value["rollbackDisabledPublished"])
        self.assertEqual(value["rollbackDisabledSnapshot"], [0.9, 0.7, 0.5])
        self.assertEqual(value["rollbackDisabledSnapshotSource"], "timeline")
        self.assertEqual(value["rollbackFailureMutations"], 0)
        self.assertEqual(value["rollbackDisabledMutations"], 0)
        self.assertEqual(value["rollbackCode"], "exception")
        self.assertIn("rollback update failure", value["rollbackDetail"])
        self.assertEqual(value["rollbackFailurePeer"], [2, 4, 6])
        self.assertEqual(value["rollbackFailurePeerSource"], "sceneScript")
        self.assertFalse(value["rollbackFailurePeerFailed"])
        self.assertEqual(value["rollbackDisabledPeer"], [2, 4, 6])
        self.assertEqual(value["rollbackDisabledPeerSource"], "sceneScript")
        self.assertFalse(value["rollbackDisabledPeerFailed"])

    def test_disable_route_suppresses_media_owner_but_keeps_vector_peer(
        self,
    ) -> None:
        value = self.value
        self.assertEqual(value["routeMediaTargetCount"], 1)
        self.assertEqual(value["routeCommittedMediaTargetCount"], 0)
        self.assertEqual(value["routeFallbackDefinitionCount"], 1)
        self.assertTrue(value["routeFallbackTargetsMatch"])
        self.assertFalse(value["routeFallbackOverlap"])
        self.assertEqual(value["routeInputCount"], 1)
        self.assertEqual(value["routePassTargetCount"], 1)
        self.assertFalse(value["routePassHasMedia"])
        self.assertTrue(value["routePassHasPeer"])
        self.assertFalse(value["routeDisabledMediaPublished"])
        self.assertEqual(value["routeDisabledPeer"], [2, 4, 6])
        self.assertEqual(value["routeDisabledMutationCount"], 0)
        self.assertEqual(value["routeDisabledSnapshot"], [0.8, 0.7, 0.6])
        self.assertEqual(value["routeDisabledSnapshotSource"], "timeline")
        self.assertEqual(value["routeAuthoredFallbackSnapshot"], [0.2, 0.4, 0.6])
        self.assertEqual(value["routeAuthoredFallbackSource"], "authored")


if __name__ == "__main__":
    unittest.main()
