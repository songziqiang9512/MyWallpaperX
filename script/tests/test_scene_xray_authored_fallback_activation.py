#!/usr/bin/env python3
"""Executable downstream activation proof for X-Ray authored size fallback."""

from __future__ import annotations

import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
SCENE_ROOT = REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene"
CAPABILITY_STAGES_SOURCE = (
    SCENE_ROOT
    / "RenderGraph/EffectExecution/SceneResolvedMaterialExecutionCapability+Stages.swift"
)
SNAPSHOT_SOURCE = SCENE_ROOT / "Properties/SceneDynamicSnapshot.swift"
ACTIVATION_SOURCE = (
    SCENE_ROOT
    / "RenderGraph/EffectExecution/SceneResolvedMaterialStageActivation.swift"
)


def product_activation_functions() -> str:
    source = CAPABILITY_STAGES_SOURCE.read_text(encoding="utf-8")
    start = source.index(
        "    static func stageActivationPolicy("
    )
    end = source.index("    struct CompiledStages", start)
    return source[start:end]


SUPPORT = r'''
import Foundation

struct SceneAuthoredEffectRenderPlan {
    struct EffectKey: Hashable {
        let layerID: Int
        let effectIndex: Int
    }

    struct Effect {
        let key: EffectKey
        let output: String
    }

    enum NodeKind {
        case material
    }

    struct Node {
        let kind: NodeKind
        let effect: EffectKey
        let target: String
        let compose: Int?
        let conditions: Int?
    }

    let effects: [Effect]
    let nodes: [Node]
    let renderTargets: [Int]
}

struct SceneGraphAdmissionProduct {
    struct ClearFunctions {
        let functions: [Int]
    }

    let graph: SceneAuthoredEffectRenderPlan
    let clearFunctions: ClearFunctions
}

enum SceneResolvedMaterialDependencyOwnership {
    case none
    case external
}

struct SceneLayerFullFramePairPlan {
    struct EffectStep {}
}

struct SceneResolvedMaterialTemplate {
    enum DynamicUniformSource: Hashable {
        case userProperty(String)
        case timeline
        case sceneScript
    }

    enum DynamicUniformScriptAttachment: Hashable {
        case unproven
    }

    struct StaticUniformValue {
        let valueKind: String
        let componentBitPatterns: [UInt64]
        let authoredBindingKeys: [String]
    }

    struct DynamicUniform {
        let target: SceneDynamicTarget
        let valueContributors: [DynamicUniformSource]
        let scriptAttachments: [DynamicUniformScriptAttachment]
        let authoredFallback: StaticUniformValue?
        let authoredBindingKeys: [String]
    }

    enum UniformValue {
        case staticExact(StaticUniformValue)
        case dynamic(DynamicUniform)
    }

    struct UniformDeclaration {
        let name: String
        let value: UniformValue
    }

    let uniformDeclarations: [UniformDeclaration]
}

enum SceneResolvedMaterialExecutionCapabilityCatalog {
    typealias Graph = SceneAuthoredEffectRenderPlan
    typealias Template = SceneResolvedMaterialTemplate
    typealias MaterialKey = String

    struct MaterialVariants {
        let launchEnvelopeProvesSpatialWeightedPointerProvider: Bool
    }

    struct MaterialCapability {
        let template: Template
        let variants: MaterialVariants
    }

    struct DynamicProducerCatalog {
        let userProperties: Set<SceneDynamicUserPropertyProducer>
        let authoredFallbackTargets: Set<SceneDynamicTarget>
    }

    static func visualFailureFramebufferTopologyMayPassthrough(
        _ graph: Graph,
        effect: Graph.Effect,
        pairStep: SceneLayerFullFramePairPlan.EffectStep
    ) -> Bool {
        false
    }
}
'''


HARNESS = r'''
import Foundation

private typealias Catalog = SceneResolvedMaterialExecutionCapabilityCatalog
private typealias Template = SceneResolvedMaterialTemplate

private let effect = SceneAuthoredEffectRenderPlan.EffectKey(
    layerID: 42,
    effectIndex: 3
)
private let sizeTarget = SceneDynamicTarget.effectConstant(
    layerID: 42,
    effectIndex: 3,
    passIndex: 0,
    name: "size"
)

private func product(nodeTarget: String = "effect-output") -> SceneGraphAdmissionProduct {
    let key = SceneAuthoredEffectRenderPlan.EffectKey(
        layerID: 42,
        effectIndex: 3
    )
    return .init(
        graph: .init(
            effects: [.init(key: key, output: "effect-output")],
            nodes: [.init(
                kind: .material,
                effect: key,
                target: nodeTarget,
                compose: nil,
                conditions: nil
            )],
            renderTargets: []
        ),
        clearFunctions: .init(functions: [])
    )
}

private func activationPolicy(
    material: Catalog.MaterialCapability?,
    dynamicProducers: Catalog.DynamicProducerCatalog,
    graphProduct: SceneGraphAdmissionProduct = product(),
    dependencyOwnership: SceneResolvedMaterialDependencyOwnership = .none
) -> SceneResolvedMaterialStageActivationPolicy? {
    Catalog.stageActivationPolicy(
        product: graphProduct,
        materials: material.map { ["xray": $0] } ?? [:],
        dynamicProducers: dynamicProducers,
        dependencyOwnership: dependencyOwnership,
        pairStep: nil
    )
}

private func fallback(_ value: Double) -> Template.StaticUniformValue {
    .init(
        valueKind: "binding",
        componentBitPatterns: [value.bitPattern],
        authoredBindingKeys: ["user", "value"]
    )
}

private func dynamicMaterial(
    propertyKey: String = "xraySize",
    value: Double = 0.25,
    componentCount: Int = 1,
    provesPointer: Bool = true
) -> Catalog.MaterialCapability {
    let bits = Array(repeating: value.bitPattern, count: componentCount)
    return .init(
        template: .init(uniformDeclarations: [.init(
            name: "size",
            value: .dynamic(.init(
                target: sizeTarget,
                valueContributors: [.userProperty(propertyKey)],
                scriptAttachments: [],
                authoredFallback: .init(
                    valueKind: "binding",
                    componentBitPatterns: bits,
                    authoredBindingKeys: ["user", "value"]
                ),
                authoredBindingKeys: ["user", "value"]
            ))
        )]),
        variants: .init(
            launchEnvelopeProvesSpatialWeightedPointerProvider: provesPointer
        )
    )
}

private func staticMaterial(_ value: Double) -> Catalog.MaterialCapability {
    .init(
        template: .init(uniformDeclarations: [.init(
            name: "size",
            value: .staticExact(.init(
                valueKind: "number",
                componentBitPatterns: [value.bitPattern],
                authoredBindingKeys: []
            ))
        )]),
        variants: .init(
            launchEnvelopeProvesSpatialWeightedPointerProvider: true
        )
    )
}

private func producer(
    _ propertyKey: String,
    target: SceneDynamicTarget = sizeTarget,
    type: SceneDynamicValueType = .scalar
) -> SceneDynamicUserPropertyProducer {
    .init(propertyKey: propertyKey, target: target, valueType: type)
}

private func producerCatalog(
    producers: Set<SceneDynamicUserPropertyProducer> = [],
    fallbackTargets: Set<SceneDynamicTarget> = []
) -> Catalog.DynamicProducerCatalog {
    .init(
        userProperties: producers,
        authoredFallbackTargets: fallbackTargets
    )
}

private func snapshot(_ value: Double) -> SceneDynamicSnapshot {
    SceneDynamicSnapshotResolver().resolve(
        frameIndex: 7,
        generation: 9,
        definitions: [.init(
            target: sizeTarget,
            valueType: .scalar,
            authoredValue: .scalar(value)
        )]
    ).snapshot
}

private func label(
    _ decision: SceneResolvedMaterialStageActivationPolicy.Decision
) -> String {
    switch decision {
    case .active: "active"
    case let .inactive(reason): "inactive:\(reason)"
    case let .rejected(reason): "rejected:\(reason)"
    }
}

@main
enum Harness {
    static func main() throws {
        let fallbackPolicy = activationPolicy(
            material: dynamicMaterial(),
            dynamicProducers: producerCatalog(fallbackTargets: [sizeTarget])
        )
        let lowFallbackPolicy = activationPolicy(
            material: dynamicMaterial(value: 0),
            dynamicProducers: producerCatalog(fallbackTargets: [sizeTarget])
        )
        let livePolicy = activationPolicy(
            material: dynamicMaterial(),
            dynamicProducers: producerCatalog(producers: [
                producer("xraySize"),
            ])
        )
        let sharedKeyOtherTarget = SceneDynamicTarget.effectConstant(
            layerID: 42,
            effectIndex: 3,
            passIndex: 0,
            name: "multiply"
        )
        let sharedKeyLivePolicy = activationPolicy(
            material: dynamicMaterial(propertyKey: "xrayShared"),
            dynamicProducers: producerCatalog(producers: [
                producer("xrayShared"),
                producer("xrayShared", target: sharedKeyOtherTarget),
            ])
        )
        let payload: [String: Any] = [
            "fallbackPolicy": fallbackPolicy != nil,
            "fallbackTargetPreserved": fallbackPolicy?.scalarMinimum?.target
                == sizeTarget,
            "fallbackRequiresPointer":
                fallbackPolicy?.requiresPointerPositionProvider == true,
            "fallbackPointerOutside": fallbackPolicy.map {
                label($0.evaluate(
                    dynamicValues: snapshot(0.25),
                    pointerIsInside: false
                ))
            } ?? "missing",
            "fallbackValid": fallbackPolicy.map {
                label($0.evaluate(
                    dynamicValues: snapshot(0.25),
                    pointerIsInside: true
                ))
            } ?? "missing",
            "fallbackBelowMinimum": lowFallbackPolicy.map {
                label($0.evaluate(
                    dynamicValues: snapshot(0),
                    pointerIsInside: true
                ))
            } ?? "missing",
            "missingDefinitionTargetRejected": activationPolicy(
                material: dynamicMaterial(),
                dynamicProducers: producerCatalog()
            ) == nil,
            "sameKeyWrongTargetRejected": activationPolicy(
                material: dynamicMaterial(),
                dynamicProducers: producerCatalog(
                    producers: [producer("xraySize", target: sharedKeyOtherTarget)],
                    fallbackTargets: [sizeTarget]
                )
            ) == nil,
            "sameTargetWrongKeyRejected": activationPolicy(
                material: dynamicMaterial(),
                dynamicProducers: producerCatalog(
                    producers: [producer("wrongSize")],
                    fallbackTargets: [sizeTarget]
                )
            ) == nil,
            "wrongTypeRejected": activationPolicy(
                material: dynamicMaterial(),
                dynamicProducers: producerCatalog(producers: [
                    producer("xraySize", type: .vector2),
                ])
            ) == nil,
            "multiComponentFallbackRejected": activationPolicy(
                material: dynamicMaterial(componentCount: 2),
                dynamicProducers: producerCatalog(fallbackTargets: [sizeTarget])
            ) == nil,
            "nonfiniteFallbackRejected": activationPolicy(
                material: dynamicMaterial(value: .nan),
                dynamicProducers: producerCatalog(fallbackTargets: [sizeTarget])
            ) == nil,
            "launchEnvelopeRequired": activationPolicy(
                material: dynamicMaterial(provesPointer: false),
                dynamicProducers: producerCatalog(fallbackTargets: [sizeTarget])
            ) == nil,
            "pairLeafTopologyRequired": activationPolicy(
                material: dynamicMaterial(),
                dynamicProducers: producerCatalog(fallbackTargets: [sizeTarget]),
                graphProduct: product(nodeTarget: "wrong-output")
            ) == nil,
            "dependencyOwnershipRequired": activationPolicy(
                material: dynamicMaterial(),
                dynamicProducers: producerCatalog(fallbackTargets: [sizeTarget]),
                dependencyOwnership: .external
            ) == nil,
            "liveTargetPreserved": livePolicy?.scalarMinimum?.target == sizeTarget,
            "sharedKeyLiveFanoutPreserved": sharedKeyLivePolicy != nil,
            "staticPolicyPreserved": activationPolicy(
                material: staticMaterial(0.25),
                dynamicProducers: producerCatalog()
            ) != nil,
        ]
        let data = try JSONSerialization.data(
            withJSONObject: payload,
            options: [.sortedKeys]
        )
        print(String(decoding: data, as: UTF8.self))
    }
}
'''


@unittest.skipUnless(shutil.which("swiftc"), "swiftc is required")
class SceneXRayAuthoredFallbackActivationTests(unittest.TestCase):
    def test_definition_only_size_preserves_pointer_and_minimum_activation(
        self,
    ) -> None:
        with tempfile.TemporaryDirectory(
            prefix="mwx-xray-authored-fallback-activation-"
        ) as directory:
            root = Path(directory)
            product = root / "ProductFunctions.swift"
            support = root / "Support.swift"
            harness = root / "Harness.swift"
            binary = root / "xray-authored-fallback-activation"
            support.write_text(SUPPORT, encoding="utf-8")
            product.write_text(
                "extension SceneResolvedMaterialExecutionCapabilityCatalog {\n"
                + product_activation_functions()
                + "}\n",
                encoding="utf-8",
            )
            harness.write_text(HARNESS, encoding="utf-8")
            environment = os.environ.copy()
            environment["CLANG_MODULE_CACHE_PATH"] = str(root / "clang-cache")
            environment["SWIFT_MODULECACHE_PATH"] = str(root / "swift-cache")
            compilation = subprocess.run(
                [
                    "xcrun", "--sdk", "macosx", "swiftc", "-parse-as-library",
                    str(SNAPSHOT_SOURCE),
                    str(ACTIVATION_SOURCE),
                    str(support),
                    str(product),
                    str(harness),
                    "-module-cache-path", str(root / "module-cache"),
                    "-o", str(binary),
                ],
                cwd=REPOSITORY_ROOT,
                env=environment,
                capture_output=True,
                text=True,
            )
            self.assertEqual(compilation.returncode, 0, compilation.stderr)
            completed = subprocess.run(
                [str(binary)],
                cwd=REPOSITORY_ROOT,
                env=environment,
                capture_output=True,
                text=True,
            )
            self.assertEqual(completed.returncode, 0, completed.stderr)

        result = json.loads(completed.stdout)
        self.assertTrue(
            all(
                value is True
                for key, value in result.items()
                if not key.startswith("fallback")
            ),
            result,
        )
        self.assertTrue(result["fallbackPolicy"], result)
        self.assertTrue(result["fallbackTargetPreserved"], result)
        self.assertTrue(result["fallbackRequiresPointer"], result)
        self.assertEqual(
            result["fallbackPointerOutside"],
            "inactive:effect-activation-pointer-provider-unavailable",
        )
        self.assertEqual(result["fallbackValid"], "active")
        self.assertEqual(
            result["fallbackBelowMinimum"],
            "inactive:effect-activation-scalar-below-minimum",
        )


if __name__ == "__main__":
    unittest.main()
