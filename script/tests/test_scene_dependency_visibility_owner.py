#!/usr/bin/env python3

"""Dependency-bearing visibility executes in the real value-only VM owner."""

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
        let descriptor = makeDescriptor()
        let target = SceneDynamicTarget.layer(
            layerID: 22, field: .visibility
        )
        let positiveBinding = binding(source: positiveSource)
        let positiveProjection = SceneScriptVectorProgram.project(
            descriptor: descriptor,
            scriptBindings: [positiveBinding]
        )
        let positiveCandidate = try SceneScriptQuickJSProgramCandidate.compile(
            authoredDescriptor: descriptor,
            runtimeDescriptor: descriptor,
            scriptBindings: [positiveBinding],
            vectorProjection: positiveProjection,
            userPropertyDefinitions: [],
            timelineTargets: [],
            scalarExcludedTargets: [],
            stringExcludedTargets: [],
            admittedVectorPassTargets: [],
            generation: 51
        )
        try publishLayerSnapshot(
            positiveCandidate, descriptor: descriptor, generation: 1
        )
        let positive = positiveCandidate.vectorProgram.evaluate(
            inputs: [target: .bool(true)],
            effectivePropertyValues: [:],
            frame: frame
        )

        let mutatingBinding = binding(source: callbackMutationSource)
        let mutatingProjection = SceneScriptVectorProgram.project(
            descriptor: descriptor,
            scriptBindings: [mutatingBinding]
        )
        let mutatingCandidate = try SceneScriptQuickJSProgramCandidate.compile(
            authoredDescriptor: descriptor,
            runtimeDescriptor: descriptor,
            scriptBindings: [mutatingBinding],
            vectorProjection: mutatingProjection,
            userPropertyDefinitions: [],
            timelineTargets: [],
            scalarExcludedTargets: [],
            stringExcludedTargets: [],
            admittedVectorPassTargets: [],
            generation: 52
        )
        try publishLayerSnapshot(
            mutatingCandidate, descriptor: descriptor, generation: 2
        )
        let rejected = mutatingCandidate.vectorProgram.evaluate(
            inputs: [target: .bool(true)],
            effectivePropertyValues: [:],
            frame: frame
        )
        let disabled = mutatingCandidate.vectorProgram.evaluate(
            inputs: [target: .bool(true)],
            effectivePropertyValues: [:],
            frame: frame
        )

        let mutableHandleProjection = SceneScriptVectorProgram.project(
            descriptor: descriptor,
            scriptBindings: [binding(source: mutableHandleSource)]
        )
        let payload: [String: Any] = [
            "dependencyProjectionCount": positiveProjection.targets.count,
            "positiveInstantiated": positiveCandidate.constructionReport
                .instantiatedVectorTargets.contains(target),
            "positiveValue": bool(positive.values[target]),
            "positiveFailures": positive.failures.count,
            "positiveFailure": String(describing: positive.failures[target]),
            "positiveMutations": positive.materialFunctionMutations.count
                + positive.animationMutations.count
                + positive.layerMutations.count,
            "positiveVideoCommands": positive.videoCommands.count,
            "positiveVideoLayers": Array(Set(
                positive.videoCommands.map(\.layerID)
            )).sorted(),
            "callbackFailureCode": rejected.failures[target]?.code ?? "",
            "callbackFailure": String(describing: rejected.failures[target]),
            "callbackFailureMessage": failureMessage(rejected.failures[target]),
            "callbackValuePublished": rejected.values[target] != nil,
            "callbackMutationsPublished": rejected.materialFunctionMutations.count
                + rejected.animationMutations.count
                + rejected.layerMutations.count,
            "disabledValuePublished": disabled.values[target] != nil,
            "disabledFailures": disabled.failures.count,
            "mutableHandleProjected": mutableHandleProjection.targets.contains(target),
        ]
        let data = try JSONSerialization.data(
            withJSONObject: payload,
            options: [.sortedKeys]
        )
        print(String(decoding: data, as: UTF8.self))
    }

    static func makeDescriptor() -> SceneRenderDescriptor {
        .init(layers: [
            .init(
                id: 21,
                layerIndex: 0,
                name: "provider-video",
                visible: false,
                originXYZ: [0, 0, 0],
                scaleXYZ: [1, 1, 1],
                scaleHasScript: false,
                alpha: 1,
                effects: []
            ),
            .init(
                id: 22,
                layerIndex: 1,
                name: "front-video",
                visible: true,
                originXYZ: [0, 0, 0],
                scaleXYZ: [1, 1, 1],
                scaleHasScript: false,
                alpha: 1,
                effects: [.init(
                    name: "dependency-consumer",
                    effectID: 23,
                    passes: [.init(
                        passIndex: 0,
                        id: 24,
                        constantShaderValues: [:],
                        textureSlots: [nil, "_rt_imageLayerComposite_21_a"]
                    )]
                )],
                dependencyLayerIDs: [21],
                authoredDependencies: [21]
            ),
        ])
    }

    static func binding(source: String) -> SceneScriptBindingIR {
        .init(
            source: source,
            owner: .init(
                kind: .object,
                objectIndex: 1,
                objectID: 22,
                effectIndex: nil,
                effectID: nil,
                passIndex: nil,
                passID: nil
            ),
            targetPath: [
                .key("objects"), .index(1), .key("visible"),
            ],
            properties: [:],
            authoredValue: .bool(true),
            valueType: .boolean,
            wrapperKeys: ["script", "value"]
        )
    }

    static func publishLayerSnapshot(
        _ candidate: SceneScriptQuickJSProgramCandidate,
        descriptor: SceneRenderDescriptor,
        generation: UInt64
    ) throws {
        let resolution = SceneDynamicSnapshotResolver().resolve(
            frameIndex: generation,
            generation: generation,
            definitions: candidate.vectorProgram.definitions
        )
        try candidate.domain?.publishLayerSnapshot(
            resolution.snapshot,
            descriptor: descriptor,
            videoSnapshots: [
                21: .init(
                    layerID: 21, duration: 12, rate: 1, loop: true,
                    currentTime: 2, isPlaying: true, endedGeneration: 0
                ),
                22: .init(
                    layerID: 22, duration: 10, rate: 1, loop: true,
                    currentTime: 2, isPlaying: true, endedGeneration: 0
                ),
            ]
        )
    }

    static func bool(_ value: SceneDynamicValue?) -> Bool {
        guard case let .bool(result)? = value else { return false }
        return result
    }

    static func failureMessage(
        _ failure: SceneScriptScalarRuntimeFailure?
    ) -> String {
        guard case let .invalidArgument(message)? = failure else { return "" }
        return message
    }

    static let frame = SceneScriptFrameInput(
        timing: .init(
            wallDate: Date(timeIntervalSince1970: 0),
            simulationFrameTime: 1.0 / 60.0,
            sceneTime: 2
        ),
        timeZone: TimeZone(secondsFromGMT: 0)!
    )

    static let positiveSource = """
    function getLayerByName(name) {
      const count = thisScene.getLayerCount()
      for (let index = 0; index < count; index++) {
        const layer = thisScene.getLayer(index)
        if (layer && layer.name === name) return layer
      }
      return null
    }
    function showPair() {
      const front = getLayerByName('front-video')
      const back = getLayerByName('provider-video')
      const frontVideo = front?.getVideoTexture?.()
      const backVideo = back?.getVideoTexture?.()
      if (!front || !back || !frontVideo || !backVideo) {
        if (!Object.isFrozen(console)) throw new Error('mutable console')
        if (console.log('optional video API unavailable') !== undefined) {
          throw new Error('console result')
        }
        return
      }
      if (frontVideo.duration !== 10 || backVideo.duration !== 12) {
        throw new Error('duration snapshot')
      }
      frontVideo.loop = false
      backVideo.loop = false
      frontVideo.setCurrentTime(0)
      backVideo.setCurrentTime(0)
      frontVideo.pause()
      backVideo.pause()
      frontVideo.play()
      backVideo.play()
      frontVideo.addEndedCallback(() => {})
      front.visible = true
    }
    export function init() {
      const properties = engine.userProperties || {}
      if (Object.keys(properties).length !== 0) throw new Error('properties')
      showPair()
    }
    export function applyUserProperties(changed) {
      Object.assign({}, engine.userProperties || {}, changed || {})
      showPair()
    }
    export function update(value) { return value }
    """

    static let callbackMutationSource = """
    export function applyUserProperties(changed) {
      thisScene.getLayer('front-video').visible = false
    }
    export function update(value) { return value }
    """

    static let mutableHandleSource = """
    export function update(value) {
      thisLayer.visible = false
      return value
    }
    """
}
'''


class SceneDependencyVisibilityOwnerTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.temporary_directory = tempfile.TemporaryDirectory(
            prefix="mwx-scene-dependency-visibility-"
        )
        cls.binary = compile_vector_harness(
            Path(cls.temporary_directory.name),
            HARNESS,
            "dependency-visibility-owner",
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

    def test_dependency_owner_executes_optional_missing_api_path(self) -> None:
        self.assertEqual(self.value["dependencyProjectionCount"], 1)
        self.assertTrue(self.value["positiveInstantiated"])
        self.assertTrue(self.value["positiveValue"])
        self.assertEqual(self.value["positiveFailures"], 0)
        self.assertEqual(self.value["positiveMutations"], 0)
        self.assertGreaterEqual(self.value["positiveVideoCommands"], 8)
        self.assertEqual(self.value["positiveVideoLayers"], [21, 22])

    def test_callback_mutation_is_rejected_before_value_publication(self) -> None:
        self.assertEqual(self.value["callbackFailureCode"], "invalid-argument")
        self.assertIn("conflicting target visibility", self.value["callbackFailure"])
        self.assertFalse(self.value["callbackValuePublished"])
        self.assertEqual(self.value["callbackMutationsPublished"], 0)
        self.assertFalse(self.value["disabledValuePublished"])
        self.assertEqual(self.value["disabledFailures"], 0)

    def test_direct_mutable_owner_handles_remain_outside_profile(self) -> None:
        self.assertFalse(self.value["mutableHandleProjected"])

    def test_typed_visibility_owner_reaches_program_admission_and_frame_gate(
        self,
    ) -> None:
        root = Path(__file__).resolve().parents[2]
        launch = (
            root
            / "MyWallpaperX/Core/SteamWorkshopScene/Runtime"
            / "SceneDesktopWallpaperHost+Launch.swift"
        ).read_text()
        admission = (
            root
            / "MyWallpaperX/Core/SteamWorkshopScene/RenderGraph"
            / "EffectExecution"
            / "SceneResolvedMaterialExecutionCapabilityAdmission.swift"
        ).read_text()
        preflight = (
            root
            / "MyWallpaperX/Core/SteamWorkshopScene/Rendering"
            / "SceneResolvedMaterialFramePreflight.swift"
        ).read_text()
        self.assertIn(
            "let dynamicLayerVisibilityOwnerTargets = propertyVectorScriptTargets\n"
            "            .union(propertyLayerVisibilityTargets)",
            launch,
        )
        self.assertIn(
            "dynamicLayerVisibilityOwnerTargets:\n"
            "                    dynamicLayerVisibilityOwnerTargets",
            launch,
        )
        self.assertIn(
            "case let .layer(layerID, .visibility) = target",
            admission,
        )
        self.assertIn(
            "resolvedMaterialExecutionLayerIDs(",
            preflight,
        )
        self.assertIn(
            "!activeExecutionLayerIDs.contains(layer.id)",
            preflight,
        )
        self.assertIn(
            "imageTextures.isLayerSourcePending(binding.providerLayerID)",
            preflight,
        )


if __name__ == "__main__":
    unittest.main()
