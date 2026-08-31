#!/usr/bin/env python3

"""Strict Boolean publication with read-only scene lookup visibility."""

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
import Foundation

private func descriptor(
    parentID: Int? = nil,
    effects: [SceneRenderDescriptor.EffectDescriptor] = [],
    effectFiles: [String] = [],
    contentKind: String = "image"
) -> SceneRenderDescriptor {
    SceneRenderDescriptor(layers: [
        .init(
            id: 7,
            layerIndex: 0,
            name: "leaf",
            visible: false,
            originXYZ: [0, 0, 0],
            scaleXYZ: [1, 1, 1],
            scaleHasScript: nil,
            alpha: 1,
            effects: effects,
            contentKind: contentKind,
            parentID: parentID,
            effectFiles: effectFiles
        ),
    ])
}

private func namedReferenceDescriptor(
    targetIsConsumer: Bool,
    userTextureShadowsReference: Bool = false
) -> SceneRenderDescriptor {
    let providerLayerID = targetIsConsumer ? 8 : 7
    let pass = SceneRenderDescriptor.EffectDescriptor.PassDescriptor(
        passIndex: 0,
        id: nil,
        constantShaderValues: [:],
        textureSlots: ["_rt_imageLayerComposite_\(providerLayerID)_a"],
        userTextureInputs: userTextureShadowsReference ? [true] : []
    )
    let referenceEffect = SceneRenderDescriptor.EffectDescriptor(
        name: "named-reference",
        passes: [pass],
        id: "named-reference"
    )
    let genericEffect = SceneRenderDescriptor.EffectDescriptor(
        name: "generic-effect"
    )
    return SceneRenderDescriptor(layers: [
        .init(
            id: 7,
            layerIndex: 0,
            name: "leaf",
            visible: false,
            originXYZ: [0, 0, 0],
            scaleXYZ: [1, 1, 1],
            scaleHasScript: nil,
            alpha: 1,
            effects: targetIsConsumer ? [referenceEffect] : [genericEffect]
        ),
        .init(
            id: 8,
            layerIndex: 1,
            name: "peer",
            visible: true,
            originXYZ: [0, 0, 0],
            scaleXYZ: [1, 1, 1],
            scaleHasScript: nil,
            alpha: 1,
            effects: targetIsConsumer ? [] : [referenceEffect]
        ),
    ])
}

private func dynamicImageDescriptor() -> SceneRenderDescriptor {
    SceneRenderDescriptor(
        layers: [
            .init(
                id: 7, layerIndex: 0, name: "bars", visible: true,
                originXYZ: [0, 0, 0], scaleXYZ: [1, 1, 1],
                scaleHasScript: nil, alpha: 1, effects: []
            ),
        ],
        modelMaterialLinks: [
            .init(modelPath: "models/workshop/2727665642/bar.json"),
        ]
    )
}

private func binding(
    source: String,
    wrapperKeys: [String] = ["script", "value"],
    authored: Bool = false
) -> SceneScriptBindingIR {
    .init(
        source: source,
        owner: .init(
            kind: .object,
            objectIndex: 0,
            objectID: 7,
            effectIndex: nil,
            effectID: nil,
            passIndex: nil,
            passID: nil
        ),
        targetPath: [.key("objects"), .index(0), .key("visible")],
        properties: [:],
        authoredValue: .bool(authored),
        valueType: .boolean,
        wrapperKeys: wrapperKeys
    )
}

private func frame(runtime: TimeInterval) -> SceneScriptFrameInput {
    .init(timing: .init(
        wallDate: Date(timeIntervalSince1970: 0),
        simulationFrameTime: 1.0 / 60.0,
        sceneTime: runtime
    ))
}

private func boolValue(
    _ result: SceneScriptVectorFrameResult,
    target: SceneDynamicTarget
) -> Bool? {
    guard case let .bool(value)? = result.values[target] else { return nil }
    return value
}

private func evaluateValueOnlyOwner(
    source: String,
    target: SceneDynamicTarget,
    generation: UInt64
) throws -> Result<SceneScriptVectorEvaluation, SceneScriptScalarRuntimeFailure> {
    let domain = try SceneScriptQuickJSDomain()
    try domain.configureLayerCatalog(descriptor())
    let owner = try SceneScriptVectorOwner(
        domain: domain,
        source: source,
        target: target,
        valueType: .bool,
        effectNames: [],
        generation: generation,
        budget: .default
    )
    return owner.evaluate(
        input: .bool(false),
        frame: frame(runtime: 2),
        scriptPropertiesJSON: "",
        userPropertiesJSON: "{}",
        expectedGeneration: generation,
        interruptBudget: nil
    )
}

private func failureCode(
    _ result: Result<SceneScriptVectorEvaluation, SceneScriptScalarRuntimeFailure>
) -> String? {
    guard case let .failure(failure) = result else { return nil }
    return failure.code
}

@main
enum Harness {
    static func main() throws {
        let target = SceneDynamicTarget.layer(layerID: 7, field: .visibility)
        let source = "export function update(value) { return engine.runtime >= 1; }"
        let authoredBinding = binding(source: source)
        let program = SceneScriptVectorProgram.compile(
            domain: try SceneScriptQuickJSDomain(),
            descriptor: descriptor(),
            scriptBindings: [authoredBinding],
            userPropertyDefinitions: [],
            generation: 1
        )
        let first = program.evaluate(
            inputs: [target: .bool(false)],
            effectivePropertyValues: [:],
            frame: frame(runtime: 0)
        )
        let second = program.evaluate(
            inputs: [target: .bool(false)],
            effectivePropertyValues: [:],
            frame: frame(runtime: 2)
        )

        let badProgram = SceneScriptVectorProgram.compile(
            domain: try SceneScriptQuickJSDomain(),
            descriptor: descriptor(),
            scriptBindings: [binding(
                source: "export function update(value) { return 1; }"
            )],
            userPropertyDefinitions: [],
            generation: 2
        )
        let bad = badProgram.evaluate(
            inputs: [target: .bool(false)],
            effectivePropertyValues: [:],
            frame: frame(runtime: 2)
        )
        let badAgain = badProgram.evaluate(
            inputs: [target: .bool(false)],
            effectivePropertyValues: [:],
            frame: frame(runtime: 3)
        )

        let undefinedProgram = SceneScriptVectorProgram.compile(
            domain: try SceneScriptQuickJSDomain(),
            descriptor: descriptor(),
            scriptBindings: [binding(
                source: "export function update(value) { return undefined; }"
            )],
            userPropertyDefinitions: [],
            generation: 3
        )
        let undefinedResult = undefinedProgram.evaluate(
            inputs: [target: .bool(true)],
            effectivePropertyValues: [:],
            frame: frame(runtime: 2)
        )

        let hiddenShared = try evaluateValueOnlyOwner(
            source: "export function update(value) { return shared.enabled; }",
            target: target,
            generation: 4
        )
        let hiddenHandle = try evaluateValueOnlyOwner(
            source: "export function update(value) { return thisScene.getLayerCount() > 0; }",
            target: target,
            generation: 5
        )
        let timer = try evaluateValueOnlyOwner(
            source: """
                export function update(value) {
                    engine.setTimeout(() => {}, 0);
                    return value;
                }
                """,
            target: target,
            generation: 6
        )

        let audioProgram = SceneScriptVectorProgram.compile(
            domain: try SceneScriptQuickJSDomain(),
            descriptor: descriptor(),
            scriptBindings: [binding(source: """
                const spectrum = engine["register" + "AudioBuffers"]();
                export function update(value) { return value; }
                """)],
            userPropertyDefinitions: [],
            generation: 7
        )
        let destroyProgram = SceneScriptVectorProgram.compile(
            domain: try SceneScriptQuickJSDomain(),
            descriptor: descriptor(),
            scriptBindings: [binding(source: """
                export function update(value) { return value; }
                export function destroy() {}
                """)],
            userPropertyDefinitions: [],
            generation: 8
        )

        let parented = SceneScriptVectorProgram.project(
            descriptor: descriptor(parentID: 99),
            scriptBindings: [authoredBinding]
        )
        let userWrapped = SceneScriptVectorProgram.project(
            descriptor: descriptor(),
            scriptBindings: [binding(
                source: source,
                wrapperKeys: ["script", "user", "value"]
            )]
        )
        let textLeaf = SceneScriptVectorProgram.project(
            descriptor: descriptor(contentKind: "text"),
            scriptBindings: [authoredBinding]
        )
        let effectBearingProgram = SceneScriptVectorProgram.compile(
            domain: try SceneScriptQuickJSDomain(),
            descriptor: descriptor(
                effects: [.init(name: "generic-effect")],
                effectFiles: ["effects/generic-effect.json"]
            ),
            scriptBindings: [authoredBinding],
            userPropertyDefinitions: [],
            generation: 10
        )
        let effectBearing = effectBearingProgram.evaluate(
            inputs: [target: .bool(false)],
            effectivePropertyValues: [:],
            frame: frame(runtime: 2)
        )
        let namedConsumer = SceneScriptVectorProgram.project(
            descriptor: namedReferenceDescriptor(targetIsConsumer: true),
            scriptBindings: [authoredBinding]
        )
        let namedProvider = SceneScriptVectorProgram.project(
            descriptor: namedReferenceDescriptor(targetIsConsumer: false),
            scriptBindings: [authoredBinding]
        )
        let shadowedNamedConsumer = SceneScriptVectorProgram.project(
            descriptor: namedReferenceDescriptor(
                targetIsConsumer: true,
                userTextureShadowsReference: true
            ),
            scriptBindings: [authoredBinding]
        )
        let cursorOnly = SceneScriptVectorProgram.project(
            descriptor: descriptor(),
            scriptBindings: [binding(
                source: "export function cursorClick() {}"
            )]
        )
        let sharedUpdate = SceneScriptVectorProgram.project(
            descriptor: descriptor(),
            scriptBindings: [binding(
                source: "export function update(value) { return shared.enabled; }"
            )]
        )
        let handleUpdate = SceneScriptVectorProgram.project(
            descriptor: descriptor(),
            scriptBindings: [binding(
                source: "export function update(value) { return thisScene.visible; }"
            )]
        )
        let dynamicGlobalWrite = SceneScriptVectorProgram.project(
            descriptor: descriptor(),
            scriptBindings: [binding(source: """
                const root = [].filter.constructor("return this")();
                root.__mwxBoolPoison = true;
                export function update(value) { return value; }
                """)]
        )
        let eventfulProgram = SceneScriptVectorProgram.compile(
            domain: try SceneScriptQuickJSDomain(),
            descriptor: descriptor(),
            scriptBindings: [binding(source: """
                export function update(value) { return value; }
                export function cursorClick() {}
                """)],
            userPropertyDefinitions: [],
            generation: 9
        )
        let dynamicSource = """
            export let __workshopId = '2727665642';
            const audio = engine.registerAudioBuffers(16);
            const bars = [];
            export function init() {
                const index = thisScene.getLayerIndex(thisLayer);
                for (let i = 0; i < 2; ++i) {
                    const bar = thisScene.createLayer('models/bar.json');
                    thisScene.sortLayer(bar, index);
                    bars.push(bar);
                }
            }
            export function update(value) {
                thisLayer.scale = new Vec3(2, 3, 1);
                for (let i = 0; i < bars.length; ++i) {
                    bars[i].origin = new Vec3(i * 10, 0, 0);
                    bars[i].scale = new Vec3(1, audio.average[i] * 10, 1);
                }
                return value;
            }
            """
        let dynamicProgram = SceneScriptVectorProgram.compile(
            domain: try SceneScriptQuickJSDomain(),
            descriptor: dynamicImageDescriptor(),
            scriptBindings: [binding(source: dynamicSource, authored: true)],
            userPropertyDefinitions: [],
            generation: 11
        )
        let dynamic = dynamicProgram.evaluate(
            inputs: [target: .bool(true)],
            effectivePropertyValues: [:],
            frame: frame(runtime: 2)
        )
        let teardown = program.teardown(
            frame: frame(runtime: 3),
            effectivePropertyValues: [:],
            userPropertiesJSON: "{}"
        ).first
        let payload: [String: Any] = [
            "definitions": program.definitions.count,
            "first": boolValue(first, target: target) as Any,
            "second": boolValue(second, target: target) as Any,
            "badPublished": bad.values[target] != nil,
            "badCode": bad.failures[target]?.code as Any,
            "badAgainPublished": badAgain.values[target] != nil,
            "badAgainFailed": badAgain.failures[target] != nil,
            "undefinedValue": boolValue(undefinedResult, target: target) as Any,
            "hiddenSharedCode": failureCode(hiddenShared) as Any,
            "hiddenHandleCode": failureCode(hiddenHandle) as Any,
            "timerCode": failureCode(timer) as Any,
            "audioDefinitions": audioProgram.definitions.count,
            "destroyDefinitions": destroyProgram.definitions.count,
            "parentedProjected": parented.targets.count,
            "userWrappedProjected": userWrapped.targets.count,
            "textLeafProjected": textLeaf.targets.count,
            "effectBearingDefinitions": effectBearingProgram.definitions.count,
            "effectBearingValue": boolValue(effectBearing, target: target) as Any,
            "namedConsumerProjected": namedConsumer.targets.count,
            "namedProviderProjected": namedProvider.targets.count,
            "shadowedNamedConsumerProjected": shadowedNamedConsumer.targets.count,
            "cursorOnlyProjected": cursorOnly.targets.count,
            "sharedUpdateProjected": sharedUpdate.targets.count,
            "handleUpdateProjected": handleUpdate.targets.count,
            "dynamicGlobalWriteProjected": dynamicGlobalWrite.targets.count,
            "eventfulDefinitions": eventfulProgram.definitions.count,
            "dynamicDefinitions": dynamicProgram.definitions.count,
            "dynamicHasAudio": dynamicProgram.hasAudioConsumers,
            "dynamicValue": boolValue(dynamic, target: target) as Any,
            "dynamicLayerCount": dynamic.layerMutations.count,
            "dynamicModelPaths": dynamic.layerMutations.compactMap(\.assetPath),
            "teardownDestroyInvoked": teardown?.destroyCallbackInvoked as Any,
            "teardownQuiescent": teardown?.snapshot.isQuiescent as Any,
            "teardownFailed": teardown?.failure != nil,
        ]
        let data = try JSONSerialization.data(
            withJSONObject: payload,
            options: [.sortedKeys]
        )
        print(String(decoding: data, as: UTF8.self))
    }
}
'''


class SceneScriptBooleanVisibilityTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.temporary_directory = tempfile.TemporaryDirectory(
            prefix="mwx-scene-bool-visible-"
        )
        cls.binary = compile_vector_harness(
            Path(cls.temporary_directory.name),
            HARNESS,
            "scene-bool-visible",
        )
        result = subprocess.run(
            [str(cls.binary)], check=True, capture_output=True, text=True
        )
        cls.value = json.loads(result.stdout)

    @classmethod
    def tearDownClass(cls) -> None:
        cls.temporary_directory.cleanup()

    def test_boolean_input_and_return_are_published_without_coercion(self) -> None:
        self.assertEqual(self.value["definitions"], 1)
        self.assertFalse(self.value["first"])
        self.assertTrue(self.value["second"])

    def test_non_boolean_return_fails_only_the_owner(self) -> None:
        self.assertFalse(self.value["badPublished"])
        self.assertEqual(self.value["badCode"], "bad-return")
        self.assertFalse(self.value["badAgainPublished"])
        self.assertFalse(self.value["badAgainFailed"])

    def test_undefined_preserves_the_boolean_input(self) -> None:
        self.assertTrue(self.value["undefinedValue"])

    def test_topology_and_outer_user_sources_remain_outside_the_cohort(self) -> None:
        self.assertEqual(self.value["parentedProjected"], 0)
        self.assertEqual(self.value["userWrappedProjected"], 0)

    def test_ordinary_text_leaf_uses_the_value_only_boolean_owner(self) -> None:
        self.assertEqual(self.value["textLeafProjected"], 1)

    def test_effect_bearing_leaf_uses_the_same_value_only_owner(self) -> None:
        self.assertEqual(self.value["effectBearingDefinitions"], 1)
        self.assertTrue(self.value["effectBearingValue"])

    def test_named_graph_participants_keep_independent_visibility_owners(self) -> None:
        self.assertEqual(self.value["namedConsumerProjected"], 1)
        self.assertEqual(self.value["namedProviderProjected"], 1)
        self.assertEqual(self.value["shadowedNamedConsumerProjected"], 1)

    def test_shared_mutable_and_event_only_owners_remain_outside(self) -> None:
        self.assertEqual(self.value["cursorOnlyProjected"], 0)
        self.assertEqual(self.value["sharedUpdateProjected"], 0)
        self.assertEqual(self.value["handleUpdateProjected"], 1)
        self.assertEqual(self.value["dynamicGlobalWriteProjected"], 0)
        self.assertEqual(self.value["eventfulDefinitions"], 0)

    def test_effectful_boolean_owner_publishes_prepared_dynamic_image_layers(self) -> None:
        self.assertEqual(self.value["dynamicDefinitions"], 1)
        self.assertTrue(self.value["dynamicHasAudio"])
        self.assertTrue(self.value["dynamicValue"])
        self.assertEqual(self.value["dynamicLayerCount"], 3)
        self.assertEqual(
            self.value["dynamicModelPaths"],
            [
                "models/workshop/2727665642/bar.json",
                "models/workshop/2727665642/bar.json",
            ],
        )

    def test_value_only_host_allows_read_only_scene_lookup_only(self) -> None:
        self.assertEqual(self.value["hiddenSharedCode"], "exception")
        self.assertIsNone(self.value["hiddenHandleCode"])
        self.assertEqual(self.value["timerCode"], "exception")
        self.assertEqual(self.value["audioDefinitions"], 0)
        self.assertEqual(self.value["destroyDefinitions"], 0)
        self.assertFalse(self.value["teardownDestroyInvoked"])
        self.assertTrue(self.value["teardownQuiescent"])
        self.assertFalse(self.value["teardownFailed"])


if __name__ == "__main__":
    unittest.main()
