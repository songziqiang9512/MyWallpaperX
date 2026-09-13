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
    var peer = SceneRenderDescriptor.Layer(
        id: 8, layerIndex: 1, name: "peer", visible: true,
        originXYZ: [0, 0, 0], scaleXYZ: [1, 1, 1],
        scaleHasScript: nil, alpha: 1, effects: []
    )
    peer.contentKind = "text"
    peer.text = "authored"
    peer.textStyle = .init(
        fontPath: nil, colorRGB: [1, 1, 1], pointSize: 32
    )
    return SceneRenderDescriptor(
        layers: [
            .init(
                id: 7, layerIndex: 0, name: "bars", visible: true,
                originXYZ: [0, 0, 0], scaleXYZ: [1, 1, 1],
                scaleHasScript: nil, alpha: 1, effects: [],
                contentKind: "container"
            ),
            peer,
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
        let statefulParented = SceneScriptVectorProgram.project(
            descriptor: descriptor(parentID: 99, contentKind: "container"),
            scriptBindings: [binding(source: """
                export function update(value) {
                    shared.enabled = true;
                    return value;
                }
                """)]
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
        let escapedStatefulProgram = SceneScriptVectorProgram.compile(
            domain: try SceneScriptQuickJSDomain(),
            descriptor: descriptor(),
            scriptBindings: [binding(source: #"""
                const identity = Function("value", "return value");
                const escaped = "\x6f\x6b";
                export function update(value) {
                    shared[escaped] = true;
                    return identity(value);
                }
                """#)],
            userPropertyDefinitions: [],
            generation: 22
        )
        let escapedStateful = escapedStatefulProgram.evaluate(
            inputs: [target: .bool(false)],
            effectivePropertyValues: [:],
            frame: frame(runtime: 2)
        )
        let selfDestroyProgram = SceneScriptVectorProgram.compile(
            domain: try SceneScriptQuickJSDomain(),
            descriptor: descriptor(),
            scriptBindings: [binding(source: """
                export function update(value) {
                    thisScene.destroyLayer('leaf');
                    return true;
                }
                """)],
            userPropertyDefinitions: [],
            generation: 23
        )
        let selfDestroy = selfDestroyProgram.evaluate(
            inputs: [target: .bool(false)],
            effectivePropertyValues: [:],
            frame: frame(runtime: 2)
        )
        let logoDefinition = SceneUserPropertyDefinition(
            key: "logo", title: "Opening logo", kind: .bool,
            runtimeType: "bool", order: 0, index: nil,
            minimumValue: nil, maximumValue: nil, stepValue: nil,
            allowsFractionalValues: false, fractionalPrecision: nil,
            displayCondition: nil, defaultValue: .bool(true), options: []
        )
        let propertyDestroyProgram = SceneScriptVectorProgram.compile(
            domain: try SceneScriptQuickJSDomain(),
            descriptor: descriptor(),
            scriptBindings: [binding(source: """
                export function update(value) { return value; }
                export function applyUserProperties(properties) {
                    if (properties.hasOwnProperty('logo') && !properties.logo) {
                        thisScene.destroyLayer('leaf');
                    }
                }
                """)],
            userPropertyDefinitions: [logoDefinition],
            generation: 24
        )
        let propertyDestroy = propertyDestroyProgram.evaluate(
            inputs: [target: .bool(true)],
            effectivePropertyValues: ["logo": .bool(false)],
            frame: frame(runtime: 2),
            propertyRevision: 1
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
        let statefulCursorProgram = SceneScriptVectorProgram.compile(
            domain: try SceneScriptQuickJSDomain(),
            descriptor: descriptor(),
            scriptBindings: [binding(source: """
                export function cursorDown() { shared.dragging = true; }
                export function cursorUp() { shared.dragging = false; }
                export function update(value) {
                    shared.angle = (shared.angle || 0) + 1;
                    return value;
                }
                """)],
            userPropertyDefinitions: [],
            generation: 13
        )
        let statefulCursor = statefulCursorProgram.evaluate(
            inputs: [target: .bool(false)],
            effectivePropertyValues: [:],
            frame: frame(runtime: 2)
        )
        let boneProgram = SceneScriptVectorProgram.compile(
            domain: try SceneScriptQuickJSDomain(),
            descriptor: descriptor(),
            scriptBindings: [binding(source: """
                let bone;
                export function init() { bone = thisLayer.getBoneIndex('tip'); }
                export function update(value) {
                    const pose = thisLayer.getLocalBoneTransform(bone);
                    thisLayer.setLocalBoneTransform(bone, pose.translation(new Vec3(12, 3, 0)));
                    return bone === 1;
                }
                export function cursorDown() { thisLayer.getBoneTransform(bone); }
                export function cursorUp() {}
                """)],
            userPropertyDefinitions: [], generation: 21
        )
        let identity: [Double] = [1,0,0,0, 0,1,0,0, 0,0,1,0, 0,0,0,1]
        _ = try boneProgram.configurePuppetBones(
            layerID: 7, worldMatrices: identity + identity,
            localMatrices: identity + identity, names: ["root", "tip"]
        )
        let boneResult = boneProgram.evaluate(
            inputs: [target: .bool(false)], effectivePropertyValues: [:],
            frame: frame(runtime: 2)
        )
        let dynamicSource = """
            export let __workshopId = '2727665642';
            const audio = engine.registerAudioBuffers(16);
            const bars = [];
            export function init() {
                const index = thisScene.getLayerIndex(thisLayer);
                for (let i = 0; i < 2; ++i) {
                    const bar = thisScene.createLayer({
                        image: 'models/bar.json',
                        origin: new Vec3(i * 10, 0, 0),
                        scale: new Vec3(1, 2, 1),
                        color: new Vec3(0.2, 0.4, 0.6),
                        alpha: 0.5,
                        visible: false
                    });
                    thisScene.sortLayer(bar, index);
                    bars.push(bar);
                }
            }
            export function update(value) {
                thisLayer.scale = new Vec3(2, 3, 1);
                const peer = thisScene.getLayer('peer');
                peer.scale = new Vec3(4, 5, 1);
                peer.visible = false;
                peer.alpha = 0.25;
                peer.color = new Vec3(0.2, 0.4, 0.6);
                if (peer.alpha !== 0.25 || peer.color.y !== 0.4) {
                    throw new Error('authored style read-your-writes lost');
                }
                peer.text = 'changed';
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
        let sharedTransactionDomain = try SceneScriptQuickJSDomain()
        let failedStyleProgram = SceneScriptVectorProgram.compile(
            domain: try SceneScriptQuickJSDomain(), descriptor: dynamicImageDescriptor(),
            scriptBindings: [binding(source: """
                export function update(value) {
                    thisScene.getLayer('peer').alpha = 0.2;
                    shared.styleAttempt = true;
                    if (value) throw new Error('local failure after style write');
                    return value;
                }
                """, authored: true)],
            userPropertyDefinitions: [], generation: 17
        )
        let failedStyle = failedStyleProgram.evaluate(inputs: [target: .bool(true)],
            effectivePropertyValues: [:], frame: frame(runtime: 2))
        let sharedTransactionProgram = SceneScriptVectorProgram.compile(
            domain: sharedTransactionDomain,
            descriptor: descriptor(),
            scriptBindings: [binding(source: """
                export function update(value) {
                    shared.counter = (shared.counter || 0) + 1;
                    return shared.counter === 1;
                }
                """)],
            userPropertyDefinitions: [],
            generation: 12
        )
        let sharedTransactionBeginFailure =
            sharedTransactionDomain.beginSharedFrameTransaction()
        let sharedTransactionFirst = sharedTransactionProgram.evaluate(
            inputs: [target: .bool(false)], effectivePropertyValues: [:],
            frame: frame(runtime: 3)
        )
        let sharedTransactionDiscardFailure =
            sharedTransactionDomain.discardSharedFrameTransaction()
        let sharedTransactionRetryBeginFailure =
            sharedTransactionDomain.beginSharedFrameTransaction()
        let sharedTransactionRetry = sharedTransactionProgram.evaluate(
            inputs: [target: .bool(false)], effectivePropertyValues: [:],
            frame: frame(runtime: 3)
        )
        sharedTransactionDomain.commitSharedFrameTransaction()
        let sharedTransactionCommitted = sharedTransactionProgram.evaluate(
            inputs: [target: .bool(false)], effectivePropertyValues: [:],
            frame: frame(runtime: 4)
        )
        let teardown = program.teardown(
            frame: frame(runtime: 3),
            effectivePropertyValues: [:],
            userPropertiesJSON: "{}"
        ).first
        let payload: [String: Any] = [
            "boneDefinitions": boneProgram.definitions.count,
            "boneValue": boolValue(boneResult, target: target) as Any,
            "boneFailure": String(describing: boneResult.failures),
            "boneMutationCount": boneResult.ownerEffects.first?.puppetBoneMutations.count ?? 0,
            "boneTranslation": boneResult.ownerEffects.first?.puppetBoneMutations.first?.matrix[12] ?? -1,
            "boneCursorOwners": boneProgram.cursorOwnerRegistrations.count,
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
            "statefulParentedProjected": statefulParented.targets.count,
            "handleUpdateProjected": handleUpdate.targets.count,
            "dynamicGlobalWriteProjected": dynamicGlobalWrite.targets.count,
            "escapedStatefulDefinitions": escapedStatefulProgram.definitions.count,
            "escapedStatefulValue": boolValue(
                escapedStateful, target: target
            ) as Any,
            "selfDestroyValue": boolValue(selfDestroy, target: target) as Any,
            "selfDestroyMutation": selfDestroy.layerMutations.contains {
                $0.kind == .destroy && !$0.isDynamic && $0.layerID == 7
                    && $0.fields.isEmpty
            },
            "propertyDestroyValue": boolValue(
                propertyDestroy, target: target
            ) as Any,
            "propertyDestroyMutation": propertyDestroy.layerMutations.contains {
                $0.kind == .destroy && !$0.isDynamic && $0.layerID == 7
                    && $0.fields.isEmpty
            },
            "eventfulDefinitions": eventfulProgram.definitions.count,
            "statefulCursorDefinitions":
                statefulCursorProgram.definitions.count,
            "statefulCursorValue":
                boolValue(statefulCursor, target: target) as Any,
            "statefulCursorRegistrationCount":
                statefulCursorProgram.cursorOwnerRegistrations.count,
            "statefulCursorEvents": statefulCursorProgram
                .cursorOwnerRegistrations.first?.owner.exportedCursorEvents
                .map(\.callbackName).sorted() ?? [],
            "dynamicDefinitions": dynamicProgram.definitions.count,
            "dynamicHasAudio": dynamicProgram.hasAudioConsumers,
            "dynamicValue": boolValue(dynamic, target: target) as Any,
            "dynamicLayerCount": dynamic.layerMutations.count,
            "authoredStyleAlpha": dynamic.layerMutations.first(where: { !$0.isDynamic && $0.fields.contains(.alpha) })?.alpha ?? -1,
            "authoredStyleColorY": dynamic.layerMutations.first(where: { !$0.isDynamic && $0.fields.contains(.color) })?.color.y ?? -1,
            "failedStyleDiscarded": failedStyle.values.isEmpty && failedStyle.layerMutations.isEmpty && !failedStyle.failures.isEmpty,
            "dynamicOwnerEffectsCount": dynamic.ownerEffects.count,
            "dynamicOwnerEffectsTarget": dynamic.ownerEffects.first?
                .ownerTarget == target,
            "dynamicOwnerEffectsLayerCount": dynamic.ownerEffects.first?
                .layerMutations.count ?? -1,
            "sharedTransactionRequired":
                sharedTransactionProgram.requiresSharedFrameTransaction,
            "sharedTransactionBeginCode":
                sharedTransactionBeginFailure?.code as Any,
            "sharedTransactionFirst":
                boolValue(sharedTransactionFirst, target: target) as Any,
            "sharedTransactionDiscardCode":
                sharedTransactionDiscardFailure?.code as Any,
            "sharedTransactionRetryBeginCode":
                sharedTransactionRetryBeginFailure?.code as Any,
            "sharedTransactionRetry":
                boolValue(sharedTransactionRetry, target: target) as Any,
            "sharedTransactionCommitted":
                boolValue(sharedTransactionCommitted, target: target) as Any,
            "dynamicModelPaths": dynamic.layerMutations.compactMap(\.assetPath),
            "dynamicPeerMutation": dynamic.layerMutations.contains {
                $0.layerID == 8 && $0.fields == [.scale, .visibility, .text, .alpha, .color]
                    && $0.scale == .init(4, 5, 1)
                    && !$0.visible && $0.text == "changed"
            },
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

    def test_outer_user_and_parented_layer_use_the_same_typed_owner(self) -> None:
        self.assertEqual(self.value["parentedProjected"], 1)
        self.assertEqual(self.value["userWrappedProjected"], 1)

    def test_ordinary_text_leaf_uses_the_value_only_boolean_owner(self) -> None:
        self.assertEqual(self.value["textLeafProjected"], 1)

    def test_effect_bearing_leaf_uses_the_same_value_only_owner(self) -> None:
        self.assertEqual(self.value["effectBearingDefinitions"], 1)
        self.assertTrue(self.value["effectBearingValue"])

    def test_named_graph_participants_keep_independent_visibility_owners(self) -> None:
        self.assertEqual(self.value["namedConsumerProjected"], 1)
        self.assertEqual(self.value["namedProviderProjected"], 1)
        self.assertEqual(self.value["shadowedNamedConsumerProjected"], 1)

    def test_shared_state_owner_is_admitted_without_dynamic_code(self) -> None:
        self.assertEqual(self.value["cursorOnlyProjected"], 1)
        self.assertEqual(self.value["sharedUpdateProjected"], 1)
        self.assertEqual(self.value["statefulParentedProjected"], 1)
        self.assertEqual(self.value["handleUpdateProjected"], 1)
        self.assertEqual(self.value["dynamicGlobalWriteProjected"], 1)
        self.assertEqual(self.value["eventfulDefinitions"], 1)
        self.assertEqual(self.value["statefulCursorDefinitions"], 1)
        self.assertFalse(self.value["statefulCursorValue"])
        self.assertEqual(self.value["statefulCursorRegistrationCount"], 1)
        self.assertEqual(
            self.value["statefulCursorEvents"],
            ["cursorDown", "cursorUp"],
        )

    def test_source_spelling_does_not_select_visibility_owner_admission(self) -> None:
        self.assertEqual(self.value["escapedStatefulDefinitions"], 1)
        self.assertFalse(self.value["escapedStatefulValue"])

    def test_authored_self_destroy_overrides_return_and_property_event(self) -> None:
        self.assertFalse(self.value["selfDestroyValue"])
        self.assertTrue(self.value["selfDestroyMutation"])
        self.assertFalse(self.value["propertyDestroyValue"])
        self.assertTrue(self.value["propertyDestroyMutation"])

    def test_layer_bone_visibility_uses_effectful_owner_and_publishes_matrix(self) -> None:
        self.assertEqual(self.value["boneDefinitions"], 1)
        self.assertTrue(self.value["boneValue"], self.value["boneFailure"])
        self.assertEqual(self.value["boneMutationCount"], 1)
        self.assertEqual(self.value["boneTranslation"], 12)
        self.assertEqual(self.value["boneCursorOwners"], 1)

    def test_shared_state_rolls_back_with_the_frame(self) -> None:
        self.assertTrue(self.value["sharedTransactionRequired"])
        self.assertIsNone(self.value["sharedTransactionBeginCode"])
        self.assertTrue(self.value["sharedTransactionFirst"])
        self.assertIsNone(self.value["sharedTransactionDiscardCode"])
        self.assertIsNone(self.value["sharedTransactionRetryBeginCode"])
        self.assertTrue(self.value["sharedTransactionRetry"])
        self.assertFalse(self.value["sharedTransactionCommitted"])

    def test_effectful_boolean_owner_publishes_prepared_dynamic_image_layers(self) -> None:
        self.assertEqual(self.value["authoredStyleAlpha"], 0.25)
        self.assertEqual(self.value["authoredStyleColorY"], 0.4)
        self.assertTrue(self.value["failedStyleDiscarded"])
        self.assertEqual(self.value["dynamicDefinitions"], 1)
        self.assertTrue(self.value["dynamicHasAudio"])
        self.assertTrue(self.value["dynamicValue"])
        self.assertEqual(self.value["dynamicLayerCount"], 4)
        self.assertEqual(self.value["dynamicOwnerEffectsCount"], 1)
        self.assertTrue(self.value["dynamicOwnerEffectsTarget"])
        self.assertEqual(self.value["dynamicOwnerEffectsLayerCount"], 4)
        self.assertTrue(self.value["dynamicPeerMutation"])
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
        self.assertEqual(self.value["audioDefinitions"], 1)
        self.assertEqual(self.value["destroyDefinitions"], 0)
        self.assertFalse(self.value["teardownDestroyInvoked"])
        self.assertTrue(self.value["teardownQuiescent"])
        self.assertFalse(self.value["teardownFailed"])


if __name__ == "__main__":
    unittest.main()
