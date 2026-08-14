#!/usr/bin/env python3

from __future__ import annotations

import json
import re
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
SOURCE_ROOT = REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene"
AUTHORED_XRAY_PLANNER_SOURCE = (
    SOURCE_ROOT / "RenderGraph/SceneAuthoredXRayPlanner.swift"
)
AUTHORED_XRAY_STOCK_IDENTITY_SOURCE = (
    SOURCE_ROOT / "RenderGraph/SceneAuthoredXRayPlanner+StockIdentity.swift"
)
LAUNCH_SOURCE = SOURCE_ROOT / "Runtime/SceneDesktopWallpaperHost+Launch.swift"
SWIFT_SOURCES = [
    SOURCE_ROOT / "Properties/SceneDynamicSnapshot.swift",
    SOURCE_ROOT / "RenderGraph/SceneEffectTextureInput.swift",
    SOURCE_ROOT / "Effects/SceneXRayRuntimePlan.swift",
]
IDENTITY_SWIFT_SOURCES = [
    SOURCE_ROOT / "Format/SceneJSONValue.swift",
    SOURCE_ROOT / "RenderGraph/SceneEffectDefinition.swift",
    SOURCE_ROOT / "RenderGraph/AuthoredGraph/SceneAuthoredEffectRenderPlan.swift",
    SOURCE_ROOT / "RenderGraph/ShaderContract/SceneShaderSourceGraph.swift",
    SOURCE_ROOT / "RenderGraph/ShaderContract/SceneShaderContract.swift",
    AUTHORED_XRAY_STOCK_IDENTITY_SOURCE,
]

HARNESS_SOURCE = r'''
import Foundation
import simd

struct SceneDocument {
    struct ShaderValue {
        let valueKind: String
        let userBinding: String?
        let components: [Double]?
    }
}

struct SceneRenderDescriptor {
    struct EffectDescriptor {
        struct PassDescriptor {
            let passIndex: Int
            let texturePaths: [String]
            let textureSlots: [String?]
            let userTextureInputs: [SceneEffectTextureInput?]
            let combos: [String: Int]
            let constantShaderValues: [String: SceneDocument.ShaderValue]
        }

        let id: String
        let file: String
        let visible: Bool?
        let passes: [PassDescriptor]
    }

    struct Layer {
        let id: Int
        let effects: [EffectDescriptor]
    }
}

struct SceneXRayEffectTextures {
    let effectID: String
    let blendTexturePath: String
    let haloTexturePath: String?
    let opacityMaskPath: String?
    let blendPropertyKey: String?
    let haloPropertyKey: String?
    let blendUVScale: SIMD2<Float>
    let opacityUVScale: SIMD2<Float>

    func matches(_ declaration: SceneXRayRuntimePlanner.Declaration) -> Bool {
        effectID == declaration.effectID
            && blendTexturePath == declaration.blendTexturePath
            && haloTexturePath == declaration.haloTexturePath
            && opacityMaskPath == declaration.opacityMaskPath
            && blendPropertyKey == declaration.blendPropertyKey
            && haloPropertyKey == declaration.haloPropertyKey
    }
}

@main
enum Harness {
    static let visibilityTarget = SceneDynamicTarget.effectVisibility(
        layerID: 42,
        effectIndex: 0
    )
    static let sizeTarget = SceneDynamicTarget.effectConstant(
        layerID: 42,
        effectIndex: 0,
        passIndex: 0,
        name: "size"
    )
    static let multiplyTarget = SceneDynamicTarget.effectConstant(
        layerID: 42,
        effectIndex: 0,
        passIndex: 0,
        name: "multiply"
    )

    static func value(
        _ components: [Double],
        kind: String = "number",
        binding: String? = nil
    ) -> SceneDocument.ShaderValue {
        .init(valueKind: kind, userBinding: binding, components: components)
    }

    static func effect(
        id: String = "42#effect#7",
        file: String = "effects/xray/effect.json",
        visible: Bool? = true,
        combos: [String: Int] = ["BLENDMODE": 0, "OPACITYMASK": 1],
        textureSlots: [String?] = [nil, "blend.tex", "halo.tex", "mask.tex"],
        texturePaths: [String] = ["blend.tex", "halo.tex", "mask.tex"],
        userTextureInputs: [SceneEffectTextureInput?] = [
            nil,
            SceneEffectTextureInput(kind: .property, value: "bottom"),
            SceneEffectTextureInput(kind: .property, value: "xraystyle"),
        ],
        values: [String: SceneDocument.ShaderValue] = [
            "size": value([0.4], kind: "binding", binding: "user.size"),
            "multiply": value([1.25], kind: "binding", binding: "user.multiply"),
        ]
    ) -> SceneRenderDescriptor.EffectDescriptor {
        .init(
            id: id,
            file: file,
            visible: visible,
            passes: [
                .init(
                    passIndex: 0,
                    texturePaths: texturePaths,
                    textureSlots: textureSlots,
                    userTextureInputs: userTextureInputs,
                    combos: combos,
                    constantShaderValues: values
                )
            ]
        )
    }

    static func layer(
        effects: [SceneRenderDescriptor.EffectDescriptor] = [effect()]
    ) -> SceneRenderDescriptor.Layer {
        .init(id: 42, effects: effects)
    }

    static func snapshot(
        visible: Bool = true,
        size: Double = 0.4,
        multiply: Double = 1.25
    ) -> SceneDynamicSnapshot {
        let definitions = [
            SceneDynamicTargetDefinition(
                target: visibilityTarget,
                valueType: .bool,
                authoredValue: .bool(true)
            ),
            SceneDynamicTargetDefinition(
                target: sizeTarget,
                valueType: .scalar,
                authoredValue: .scalar(0.4)
            ),
            SceneDynamicTargetDefinition(
                target: multiplyTarget,
                valueType: .scalar,
                authoredValue: .scalar(1.25)
            ),
        ]
        return SceneDynamicSnapshotResolver().resolve(
            frameIndex: 1,
            generation: 1,
            definitions: definitions,
            userValues: [
                visibilityTarget: .bool(visible),
                sizeTarget: .scalar(size),
                multiplyTarget: .scalar(multiply),
            ]
        ).snapshot
    }

    static func resources(
        effectID: String = "42#effect#7"
    ) -> SceneXRayEffectTextures {
        .init(
            effectID: effectID,
            blendTexturePath: "blend.tex",
            haloTexturePath: "halo.tex",
            opacityMaskPath: "mask.tex",
            blendPropertyKey: "bottom",
            haloPropertyKey: "xraystyle",
            blendUVScale: SIMD2(0.5, 0.75),
            opacityUVScale: SIMD2(0.25, 0.5)
        )
    }

    static func main() throws {
        let authoredLayer = layer()
        let declaration = SceneXRayRuntimePlanner.declaration(for: authoredLayer)
        let plan = SceneXRayRuntimePlanner.plan(
            for: authoredLayer,
            resources: resources(),
            snapshot: snapshot(size: 0.25, multiply: 2.5),
            pointerIsInside: true
        )
        let fallbackPlan = SceneXRayRuntimePlanner.plan(
            for: authoredLayer,
            resources: resources(),
            snapshot: snapshot(size: 2),
            pointerIsInside: true
        )
        let result: [String: Any] = [
            "declaration": declaration != nil,
            "blendPath": declaration?.blendTexturePath ?? "",
            "haloPath": declaration?.haloTexturePath ?? "",
            "opacityPath": declaration?.opacityMaskPath ?? "",
            "blendProperty": declaration?.blendPropertyKey ?? "",
            "haloProperty": declaration?.haloPropertyKey ?? "",
            "fallbackSize": declaration?.fallbackSize ?? -1,
            "fallbackMultiply": declaration?.fallbackMultiply ?? -1,
            "consumerCount": SceneXRayRuntimePlanner.liveConsumerTargets(
                for: authoredLayer
            ).count,
            "dynamicSize": plan?.size ?? -1,
            "dynamicMultiply": plan?.multiply ?? -1,
            "fallbackDynamicSize": fallbackPlan?.size ?? -1,
            "blendScale": [plan?.blendUVScale.x ?? -1, plan?.blendUVScale.y ?? -1],
            "outsideRejected": SceneXRayRuntimePlanner.plan(
                for: authoredLayer,
                resources: resources(),
                snapshot: snapshot(),
                pointerIsInside: false
            ) == nil,
            "hiddenRejected": SceneXRayRuntimePlanner.plan(
                for: authoredLayer,
                resources: resources(),
                snapshot: snapshot(visible: false),
                pointerIsInside: true
            ) == nil,
            "resourceMismatchRejected": SceneXRayRuntimePlanner.plan(
                for: authoredLayer,
                resources: resources(effectID: "other"),
                snapshot: snapshot(),
                pointerIsInside: true
            ) == nil,
            "unknownComboRejected": SceneXRayRuntimePlanner.declaration(
                for: layer(effects: [effect(combos: ["UNSUPPORTED": 1])])
            ) == nil,
            "duplicateRejected": SceneXRayRuntimePlanner.declaration(
                for: layer(effects: [effect(), effect(id: "duplicate")])
            ) == nil,
            "shapeRejected": SceneXRayRuntimePlanner.declaration(
                for: layer(effects: [
                    effect(
                        textureSlots: [nil, "blend.tex", nil],
                        texturePaths: ["blend.tex"],
                        userTextureInputs: [
                            nil,
                            nil,
                            SceneEffectTextureInput(
                                kind: .property,
                                value: "xraystyle"
                            ),
                        ]
                    )
                ])
            ) == nil,
            "boundMultiplyAccepted": SceneXRayRuntimePlanner.declaration(
                for: layer(effects: [
                    effect(values: [
                        "size": value([0.4]),
                        "multiply": value(
                            [1],
                            kind: "binding",
                            binding: "user.multiply"
                        ),
                    ])
                ])
            ) != nil,
        ]
        let data = try JSONSerialization.data(
            withJSONObject: result,
            options: [.sortedKeys]
        )
        print(String(decoding: data, as: UTF8.self))
    }
}
'''


IDENTITY_HARNESS_SOURCE = r'''
import CryptoKit
import Foundation

enum SceneAuthoredXRayPlanner {
    typealias Graph = SceneAuthoredEffectRenderPlan
}

extension SceneAuthoredXRayPlanner {
    nonisolated static let currentStockIdentityProfile: StockIdentityProfile = {
        let synthetic = IdentityHarness.profile(
            flavor: "current",
            version: 1,
            replacementKey: "xray",
            group: "interactive"
        )
        return .init(
            version: synthetic.version,
            replacementKey: synthetic.replacementKey,
            group: synthetic.group,
            materialSemanticSHA256: synthetic.materialSemanticSHA256,
            shaderCanonicalSHA256: synthetic.shaderCanonicalSHA256,
            shaderDependencySHA256: synthetic.shaderDependencySHA256
        )
    }()
    nonisolated static let stockIdentityProfiles = [currentStockIdentityProfile]
}

struct SceneRenderDescriptor {
    struct EffectDescriptor {
        let id: String
        let file: String
        let visible: Bool?
    }

    struct Layer {
        let id: Int
        let effects: [EffectDescriptor]
    }

    struct MaterialPassDescriptor {
        let id: String
        let materialPath: String
        let materialRawSHA256: String
        let shaderPathIndependentSHA256: String
        let passIndex: Int
        let shaderPath: String?
        let texturePaths: [String]
        let textureSlots: [String?]
        let userTextureInputs: [String?]
        let combos: [String: Int]
        let constantShaderValues: [String: Double]
        let userShaderValues: [String: String]
        let blending: String?
        let depthTest: String?
        let depthWrite: String?
        let cullMode: String?
        let alphaWriting: String?
    }

    let layers: [Layer]
    let materialPasses: [MaterialPassDescriptor]
    let effectDefinitions: [SceneEffectDefinition]
}

@main
enum IdentityHarness {
    typealias Profile = SceneAuthoredXRayPlanner.SyntheticStockIdentityProfile
    typealias Contract = SceneShaderContract

    struct Fixture {
        let flavor: String
        let profile: Profile
        let descriptor: SceneRenderDescriptor
        let contract: Contract
    }

    struct CanonicalShaderPayload: Encodable {
        let identity: String
        let sourceKind: Contract.SourceKind
        let stages: [Contract.Stage]
        let diagnostics: [Contract.Diagnostic]
    }

    static func sha256(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    static func stages(
        flavor: String,
        vertexSourceSuffix: String = "",
        vertexRawOverride: String? = nil
    ) -> [Contract.Stage] {
        let vertexSource = "mwx-synthetic-\(flavor)-vertex\(vertexSourceSuffix)"
        let fragmentSource = "mwx-synthetic-\(flavor)-fragment"
        return [
            .init(
                kind: .vertex,
                relativePath: "shaders/effects/xray.vert",
                source: vertexSource,
                rawSHA256: vertexRawOverride ?? sha256(vertexSource),
                includes: [],
                annotations: [],
                declarations: []
            ),
            .init(
                kind: .fragment,
                relativePath: "shaders/effects/xray.frag",
                source: fragmentSource,
                rawSHA256: sha256(fragmentSource),
                includes: [],
                annotations: [],
                declarations: []
            ),
        ]
    }

    static func canonicalHash(
        stages: [Contract.Stage],
        diagnostics: [Contract.Diagnostic] = []
    ) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let payload = CanonicalShaderPayload(
            identity: "effects/xray",
            sourceKind: .authoredSource,
            stages: stages,
            diagnostics: diagnostics
        )
        return (try? encoder.encode(payload)).map {
            SHA256.hash(data: $0)
                .map { String(format: "%02x", $0) }
                .joined()
        } ?? ""
    }

    static func profile(
        flavor: String,
        version: Int?,
        replacementKey: String?,
        group: String
    ) -> Profile {
        let stockStages = stages(flavor: flavor)
        return .init(
            version: version,
            replacementKey: replacementKey,
            group: group,
            materialSemanticSHA256: sha256(
                "mwx-synthetic-shared-material-semantics"
            ),
            shaderCanonicalSHA256: canonicalHash(stages: stockStages),
            shaderDependencySHA256: SceneShaderSourceGraph.dependencySHA256(
                nodes: graphNodes(flavor: flavor),
                edges: []
            )
        )
    }

    static func graphNodes(
        flavor: String,
        includeSourceSuffix: String = "",
        includeRawOverride: String? = nil,
        includePathOverride: String? = nil,
        includeProvenance: SceneShaderSourceGraph.Provenance = .stock,
        otherNodeSourceSuffix: String = "",
        otherNodeRawTracksSource: Bool = false,
        otherNodeByteCountDelta: Int = 0
    ) -> [SceneShaderSourceGraph.Node] {
        let baseIncludeSource = "mwx-synthetic-\(flavor)-common-blending"
        let includeSource = baseIncludeSource + includeSourceSuffix
        let baseOtherSource = "mwx-synthetic-\(flavor)-other-node"
        let otherSource = baseOtherSource + otherNodeSourceSuffix
        return [
            .init(
                virtualPath: includePathOverride
                    ?? "shaders/common_blending.h",
                provenance: includeProvenance,
                source: includeSource,
                rawSHA256: includeRawOverride ?? sha256(baseIncludeSource),
                byteCount: includeSource.utf8.count
            ),
            .init(
                virtualPath: "shaders/synthetic_other.h",
                provenance: .stock,
                source: otherSource,
                rawSHA256: otherNodeRawTracksSource
                    ? sha256(otherSource) : sha256(baseOtherSource),
                byteCount: otherSource.utf8.count + otherNodeByteCountDelta
            ),
        ]
    }

    static func definition(
        profile: Profile,
        rawOverride: String? = nil,
        groupOverride: String? = nil
    ) -> SceneEffectDefinition {
        .init(
            relativePath: "effects/xray/effect.json",
            version: profile.version,
            replacementKey: profile.replacementKey,
            name: "ui_editor_effect_xray_title",
            description: "ui_editor_effect_xray_description",
            group: groupOverride ?? profile.group,
            performance: nil,
            previewPath: "preview/project.json",
            editable: nil,
            passes: [.init(
                passIndex: 0,
                materialPath: "materials/effects/xray.json",
                target: nil,
                bindings: [],
                compose: nil,
                command: nil,
                source: nil,
                conditions: nil,
                extraFields: [:]
            )],
            framebuffers: [],
            dependencies: [
                "materials/effects/xray.json",
                "shaders/effects/xray.frag",
                "shaders/effects/xray.vert",
            ],
            functions: nil,
            gizmos: nil,
            extraFields: [:],
            unknownFieldPaths: [],
            rawSHA256: rawOverride
                ?? sha256("mwx-synthetic-definition-\(profile.group)")
        )
    }

    static func descriptor(
        profile: Profile,
        definitionGroupOverride: String? = nil,
        materialBlending: String = "normal",
        materialSemanticSHA256Override: String? = nil,
        extraMaterialPass: Bool = false,
        primaryVisible: Bool = true,
        primaryPath: String = "effects/xray/effect.json"
    ) -> SceneRenderDescriptor {
        let leadingEffects = (0 ..< 10).map { index in
            SceneRenderDescriptor.EffectDescriptor(
                id: "195#local#\(index)",
                file: "effects/tint/effect.json",
                visible: true
            )
        }
        let effects = leadingEffects + [
            .init(
                id: "195#effect#xray",
                file: primaryPath,
                visible: primaryVisible
            ),
            .init(
                id: "195#effect#hidden-xray",
                file: "effects/xray/effect.json",
                visible: false
            ),
            .init(
                id: "195#effect#lookalike",
                file: "effects/workshop/xray/effect.json",
                visible: true
            ),
        ]
        let material = SceneRenderDescriptor.MaterialPassDescriptor(
            id: "materials/effects/xray.json#0",
            materialPath: "materials/effects/xray.json",
            materialRawSHA256: sha256("mwx-synthetic-material"),
            shaderPathIndependentSHA256: materialSemanticSHA256Override
                ?? profile.materialSemanticSHA256,
            passIndex: 0,
            shaderPath: "effects/xray",
            texturePaths: [],
            textureSlots: [],
            userTextureInputs: [],
            combos: [:],
            constantShaderValues: [:],
            userShaderValues: [:],
            blending: materialBlending,
            depthTest: "disabled",
            depthWrite: "disabled",
            cullMode: "nocull",
            alphaWriting: nil
        )
        let materials = extraMaterialPass ? [
            material,
            .init(
                id: "materials/effects/xray.json#1",
                materialPath: "materials/effects/xray.json",
                materialRawSHA256: sha256("mwx-synthetic-material-pass-1"),
                shaderPathIndependentSHA256: profile.materialSemanticSHA256,
                passIndex: 1,
                shaderPath: "effects/xray",
                texturePaths: [],
                textureSlots: [],
                userTextureInputs: [],
                combos: [:],
                constantShaderValues: [:],
                userShaderValues: [:],
                blending: "normal",
                depthTest: "disabled",
                depthWrite: "disabled",
                cullMode: "nocull",
                alphaWriting: nil
            ),
        ] : [material]
        return .init(
            layers: [.init(id: 195, effects: effects)],
            materialPasses: materials,
            effectDefinitions: [definition(
                profile: profile,
                groupOverride: definitionGroupOverride
            )]
        )
    }

    static func contract(
        flavor: String,
        profile: Profile,
        vertexSourceSuffix: String = "",
        vertexRawOverride: String? = nil,
        canonicalOverride: String? = nil,
        dependencyOverride: String? = nil,
        includeSourceSuffix: String = "",
        includeRawOverride: String? = nil,
        includePathOverride: String? = nil,
        includeProvenance: SceneShaderSourceGraph.Provenance = .stock,
        otherNodeSourceSuffix: String = "",
        otherNodeRawTracksSource: Bool = false,
        otherNodeByteCountDelta: Int = 0,
        wrongRootOrder: Bool = false,
        contractDiagnostic: Bool = false,
        graphDiagnostic: Bool = false
    ) -> Contract {
        let authoredStages = stages(
            flavor: flavor,
            vertexSourceSuffix: vertexSourceSuffix,
            vertexRawOverride: vertexRawOverride
        )
        let contractDiagnostics: [Contract.Diagnostic] = contractDiagnostic ? [
            .init(
                code: .unreadableSource,
                message: "synthetic diagnostic",
                relativePath: "shaders/effects/xray.vert",
                line: nil
            ),
        ] : []
        let graphDiagnostics: [SceneShaderSourceGraph.Diagnostic] =
            graphDiagnostic ? [
                .init(
                    code: .missing,
                    parentVirtualPath: "shaders/effects/xray.frag",
                    line: 1,
                    request: "common_blending.h",
                    candidateVirtualPath: nil
                ),
            ] : []
        let sourceGraph = SceneShaderSourceGraph(
            roots: wrongRootOrder ? [
                .init(label: "vertex", virtualPath: "shaders/effects/xray.vert"),
                .init(label: "fragment", virtualPath: "shaders/effects/xray.frag"),
            ] : [
                .init(label: "fragment", virtualPath: "shaders/effects/xray.frag"),
                .init(label: "vertex", virtualPath: "shaders/effects/xray.vert"),
            ],
            nodes: graphNodes(
                flavor: flavor,
                includeSourceSuffix: includeSourceSuffix,
                includeRawOverride: includeRawOverride,
                includePathOverride: includePathOverride,
                includeProvenance: includeProvenance,
                otherNodeSourceSuffix: otherNodeSourceSuffix,
                otherNodeRawTracksSource: otherNodeRawTracksSource,
                otherNodeByteCountDelta: otherNodeByteCountDelta
            ),
            edges: [],
            diagnostics: graphDiagnostics,
            dependencySHA256: dependencyOverride
                ?? profile.shaderDependencySHA256
        )
        return .init(
            identity: "effects/xray",
            sourceKind: .authoredSource,
            stages: authoredStages,
            diagnostics: contractDiagnostics,
            canonicalSHA256: canonicalOverride
                ?? profile.shaderCanonicalSHA256,
            sourceGraph: sourceGraph
        )
    }

    static func fixture(
        flavor: String,
        version: Int?,
        replacementKey: String?,
        group: String
    ) -> Fixture {
        let identity = profile(
            flavor: flavor,
            version: version,
            replacementKey: replacementKey,
            group: group
        )
        return .init(
            flavor: flavor,
            profile: identity,
            descriptor: descriptor(profile: identity),
            contract: contract(flavor: flavor, profile: identity)
        )
    }

    static func keys(
        descriptor: SceneRenderDescriptor,
        contracts: [Contract],
        profiles: [Profile]
    ) -> [String] {
        SceneAuthoredXRayPlanner.verifiedStockIdentityEffectKeysForTesting(
            descriptor: descriptor,
            shaderContracts: contracts,
            syntheticProfiles: profiles
        ).map {
            "\($0.layerID):\($0.effectIndex):\($0.descriptorID)"
        }.sorted()
    }

    static func main() throws {
        let current = fixture(
            flavor: "current",
            version: 1,
            replacementKey: "xray",
            group: "interactive"
        )
        let legacy = fixture(
            flavor: "legacy",
            version: nil,
            replacementKey: nil,
            group: "colorize"
        )
        let expected = ["195:10:195#effect#xray"]
        let currentExact = keys(
            descriptor: current.descriptor,
            contracts: [current.contract],
            profiles: [current.profile]
        )
        let legacyExact = keys(
            descriptor: legacy.descriptor,
            contracts: [legacy.contract],
            profiles: [legacy.profile]
        )
        let mismatchedMaterialSemanticSHA256 = String(
            repeating: "0",
            count: 64
        )
        let currentMaterialSemanticMismatch = descriptor(
            profile: current.profile,
            materialSemanticSHA256Override: mismatchedMaterialSemanticSHA256
        )
        let legacyMaterialSemanticMismatch = descriptor(
            profile: legacy.profile,
            materialSemanticSHA256Override: mismatchedMaterialSemanticSHA256
        )
        let result: [String: Any] = [
            "currentExact": currentExact,
            "legacyExact": legacyExact,
            "effectIndexIsExact": currentExact == expected && legacyExact == expected,
            "currentExecutionHelperExact": SceneAuthoredXRayPlanner
                .currentStockShaderContractMatches([current.contract]),
            "currentExecutionHelperDependencyRejected": !SceneAuthoredXRayPlanner
                .currentStockShaderContractMatches([contract(
                    flavor: current.flavor,
                    profile: current.profile,
                    dependencyOverride: String(repeating: "0", count: 64)
                )]),
            "currentExecutionHelperIncludeRejected": !SceneAuthoredXRayPlanner
                .currentStockShaderContractMatches([contract(
                    flavor: current.flavor,
                    profile: current.profile,
                    includeSourceSuffix: "-mutated"
                )]),
            "currentExecutionHelperLegacyRejected": !SceneAuthoredXRayPlanner
                .currentStockShaderContractMatches([legacy.contract]),
            "currentExecutionMaterialHelperDigestRejected":
                !SceneAuthoredXRayPlanner.currentStockMaterialMatches(
                    descriptor: currentMaterialSemanticMismatch
                ),
            "wrongDefinitionMetadataRejected": keys(
                descriptor: descriptor(
                    profile: current.profile,
                    definitionGroupOverride: "other"
                ),
                contracts: [current.contract],
                profiles: [current.profile]
            ).isEmpty,
            "wrongMaterialRejected": keys(
                descriptor: descriptor(
                    profile: current.profile,
                    materialBlending: "additive"
                ),
                contracts: [current.contract],
                profiles: [current.profile]
            ).isEmpty,
            "wrongCurrentMaterialSemanticDigestRejected": keys(
                descriptor: currentMaterialSemanticMismatch,
                contracts: [current.contract],
                profiles: [current.profile]
            ).isEmpty,
            "wrongLegacyMaterialSemanticDigestRejected": keys(
                descriptor: legacyMaterialSemanticMismatch,
                contracts: [legacy.contract],
                profiles: [legacy.profile]
            ).isEmpty,
            "extraMaterialPassRejected": keys(
                descriptor: descriptor(
                    profile: current.profile,
                    extraMaterialPass: true
                ),
                contracts: [current.contract],
                profiles: [current.profile]
            ).isEmpty,
            "wrongStageSourceRejected": keys(
                descriptor: current.descriptor,
                contracts: [contract(
                    flavor: current.flavor,
                    profile: current.profile,
                    vertexSourceSuffix: "-mutated"
                )],
                profiles: [current.profile]
            ).isEmpty,
            "wrongStageRawRejected": keys(
                descriptor: current.descriptor,
                contracts: [contract(
                    flavor: current.flavor,
                    profile: current.profile,
                    vertexRawOverride: String(repeating: "0", count: 64)
                )],
                profiles: [current.profile]
            ).isEmpty,
            "wrongCanonicalRejected": keys(
                descriptor: current.descriptor,
                contracts: [contract(
                    flavor: current.flavor,
                    profile: current.profile,
                    canonicalOverride: String(repeating: "0", count: 64)
                )],
                profiles: [current.profile]
            ).isEmpty,
            "wrongDependencyRejected": keys(
                descriptor: current.descriptor,
                contracts: [contract(
                    flavor: current.flavor,
                    profile: current.profile,
                    dependencyOverride: String(repeating: "0", count: 64)
                )],
                profiles: [current.profile]
            ).isEmpty,
            "wrongRootOrderRejected": keys(
                descriptor: current.descriptor,
                contracts: [contract(
                    flavor: current.flavor,
                    profile: current.profile,
                    wrongRootOrder: true
                )],
                profiles: [current.profile]
            ).isEmpty,
            "wrongIncludeSourceRejected": keys(
                descriptor: current.descriptor,
                contracts: [contract(
                    flavor: current.flavor,
                    profile: current.profile,
                    includeSourceSuffix: "-mutated"
                )],
                profiles: [current.profile]
            ).isEmpty,
            "wrongIncludeRawRejected": keys(
                descriptor: current.descriptor,
                contracts: [contract(
                    flavor: current.flavor,
                    profile: current.profile,
                    includeRawOverride: String(repeating: "0", count: 64)
                )],
                profiles: [current.profile]
            ).isEmpty,
            "wrongIncludePathRejected": keys(
                descriptor: current.descriptor,
                contracts: [contract(
                    flavor: current.flavor,
                    profile: current.profile,
                    includePathOverride: "shaders/other.h"
                )],
                profiles: [current.profile]
            ).isEmpty,
            "wrongIncludeProvenanceRejected": keys(
                descriptor: current.descriptor,
                contracts: [contract(
                    flavor: current.flavor,
                    profile: current.profile,
                    includeProvenance: .package
                )],
                profiles: [current.profile]
            ).isEmpty,
            "wrongOtherNodeSourceRejected": keys(
                descriptor: current.descriptor,
                contracts: [contract(
                    flavor: current.flavor,
                    profile: current.profile,
                    otherNodeSourceSuffix: "-mutated"
                )],
                profiles: [current.profile]
            ).isEmpty,
            "selfConsistentOtherNodeWithoutDependencyUpdateRejected": keys(
                descriptor: current.descriptor,
                contracts: [contract(
                    flavor: current.flavor,
                    profile: current.profile,
                    otherNodeSourceSuffix: "-mutated",
                    otherNodeRawTracksSource: true
                )],
                profiles: [current.profile]
            ).isEmpty,
            "wrongOtherNodeByteCountRejected": keys(
                descriptor: current.descriptor,
                contracts: [contract(
                    flavor: current.flavor,
                    profile: current.profile,
                    otherNodeByteCountDelta: 1
                )],
                profiles: [current.profile]
            ).isEmpty,
            "contractDiagnosticRejected": keys(
                descriptor: current.descriptor,
                contracts: [contract(
                    flavor: current.flavor,
                    profile: current.profile,
                    contractDiagnostic: true
                )],
                profiles: [current.profile]
            ).isEmpty,
            "graphDiagnosticRejected": keys(
                descriptor: current.descriptor,
                contracts: [contract(
                    flavor: current.flavor,
                    profile: current.profile,
                    graphDiagnostic: true
                )],
                profiles: [current.profile]
            ).isEmpty,
            "hybridRejected": keys(
                descriptor: current.descriptor,
                contracts: [legacy.contract],
                profiles: [current.profile, legacy.profile]
            ).isEmpty,
            "hiddenRejected": keys(
                descriptor: descriptor(
                    profile: current.profile,
                    primaryVisible: false
                ),
                contracts: [current.contract],
                profiles: [current.profile]
            ).isEmpty,
            "unknownPathRejected": keys(
                descriptor: descriptor(
                    profile: current.profile,
                    primaryPath: "effects/workshop/xray/effect.json"
                ),
                contracts: [current.contract],
                profiles: [current.profile]
            ).isEmpty,
        ]
        let data = try JSONSerialization.data(
            withJSONObject: result,
            options: [.sortedKeys]
        )
        print(String(decoding: data, as: UTF8.self))
    }
}
'''


@unittest.skipUnless(shutil.which("swiftc"), "swiftc is required")
class SceneXRayPlannerTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.temporary_directory = tempfile.TemporaryDirectory(prefix="mwx-xray-planner-")
        root = Path(cls.temporary_directory.name)
        harness = root / "Harness.swift"
        harness.write_text(HARNESS_SOURCE, encoding="utf-8")
        cls.binary = root / "xray-planner"
        compilation = subprocess.run(
            [
                "xcrun",
                "--sdk",
                "macosx",
                "swiftc",
                *(str(path) for path in SWIFT_SOURCES),
                str(harness),
                "-o",
                str(cls.binary),
            ],
            capture_output=True,
            text=True,
        )
        if compilation.returncode != 0:
            raise RuntimeError(compilation.stderr)
        completed = subprocess.run(
            [str(cls.binary)],
            check=True,
            capture_output=True,
            text=True,
        )
        cls.result = json.loads(completed.stdout)

    @classmethod
    def tearDownClass(cls) -> None:
        cls.temporary_directory.cleanup()

    def test_exact_declaration_and_dynamic_size_are_planned(self) -> None:
        self.assertTrue(self.result["declaration"])
        self.assertEqual(self.result["blendPath"], "blend.tex")
        self.assertEqual(self.result["haloPath"], "halo.tex")
        self.assertEqual(self.result["opacityPath"], "mask.tex")
        self.assertEqual(self.result["blendProperty"], "bottom")
        self.assertEqual(self.result["haloProperty"], "xraystyle")
        self.assertAlmostEqual(self.result["fallbackSize"], 0.4)
        self.assertAlmostEqual(self.result["fallbackMultiply"], 1.25)
        self.assertEqual(self.result["consumerCount"], 3)
        self.assertAlmostEqual(self.result["dynamicSize"], 0.25)
        self.assertAlmostEqual(self.result["dynamicMultiply"], 2.5)
        self.assertEqual(self.result["blendScale"], [0.5, 0.75])

    def test_out_of_range_dynamic_size_falls_back_to_authored_value(self) -> None:
        self.assertAlmostEqual(self.result["fallbackDynamicSize"], 0.4)

    def test_pointer_visibility_and_resource_identity_gate_execution(self) -> None:
        self.assertTrue(self.result["outsideRejected"])
        self.assertTrue(self.result["hiddenRejected"])
        self.assertTrue(self.result["resourceMismatchRejected"])

    def test_unknown_or_ambiguous_shapes_fail_closed(self) -> None:
        self.assertTrue(self.result["unknownComboRejected"])
        self.assertTrue(self.result["duplicateRejected"])
        self.assertTrue(self.result["shapeRejected"])
        self.assertTrue(self.result["boundMultiplyAccepted"])


@unittest.skipUnless(shutil.which("swiftc"), "swiftc is required")
class SceneXRayStockIdentityTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.temporary_directory = tempfile.TemporaryDirectory(
            prefix="mwx-xray-stock-identity-"
        )
        root = Path(cls.temporary_directory.name)
        harness = root / "IdentityHarness.swift"
        harness.write_text(IDENTITY_HARNESS_SOURCE, encoding="utf-8")
        cls.binary = root / "xray-stock-identity"
        compilation = subprocess.run(
            [
                "xcrun",
                "--sdk",
                "macosx",
                "swiftc",
                "-D",
                "SCENE_XRAY_STOCK_IDENTITY_TESTING",
                *(str(path) for path in IDENTITY_SWIFT_SOURCES),
                str(harness),
                "-o",
                str(cls.binary),
            ],
            capture_output=True,
            text=True,
        )
        if compilation.returncode != 0:
            raise RuntimeError(compilation.stderr)
        completed = subprocess.run(
            [str(cls.binary)],
            check=True,
            capture_output=True,
            text=True,
        )
        cls.result = json.loads(completed.stdout)

    @classmethod
    def tearDownClass(cls) -> None:
        cls.temporary_directory.cleanup()

    def test_current_and_legacy_profiles_publish_only_the_exact_visible_key(
        self,
    ) -> None:
        expected = ["195:10:195#effect#xray"]
        self.assertEqual(self.result["currentExact"], expected)
        self.assertEqual(self.result["legacyExact"], expected)
        self.assertTrue(self.result["effectIndexIsExact"])
        self.assertTrue(self.result["hiddenRejected"])
        self.assertTrue(self.result["unknownPathRejected"])

    def test_definition_material_and_root_shader_identity_fail_closed(self) -> None:
        for key in (
            "wrongDefinitionMetadataRejected",
            "wrongMaterialRejected",
            "wrongCurrentMaterialSemanticDigestRejected",
            "wrongLegacyMaterialSemanticDigestRejected",
            "extraMaterialPassRejected",
            "wrongStageSourceRejected",
            "wrongStageRawRejected",
            "wrongCanonicalRejected",
            "contractDiagnosticRejected",
            "hybridRejected",
        ):
            self.assertTrue(self.result[key], key)

    def test_source_graph_dependency_and_include_identity_fail_closed(self) -> None:
        for key in (
            "wrongDependencyRejected",
            "wrongRootOrderRejected",
            "wrongIncludeSourceRejected",
            "wrongIncludeRawRejected",
            "wrongIncludePathRejected",
            "wrongIncludeProvenanceRejected",
            "wrongOtherNodeSourceRejected",
            "selfConsistentOtherNodeWithoutDependencyUpdateRejected",
            "wrongOtherNodeByteCountRejected",
            "graphDiagnosticRejected",
        ):
            self.assertTrue(self.result[key], key)

    def test_current_execution_helper_requires_current_source_graph_identity(
        self,
    ) -> None:
        for key in (
            "currentExecutionHelperExact",
            "currentExecutionHelperDependencyRejected",
            "currentExecutionHelperIncludeRejected",
            "currentExecutionHelperLegacyRejected",
            "currentExecutionMaterialHelperDigestRejected",
        ):
            self.assertTrue(self.result[key], key)

    def test_production_profiles_keep_exact_current_and_legacy_pairings(self) -> None:
        source = AUTHORED_XRAY_PLANNER_SOURCE.read_text(encoding="utf-8")
        current = source.split("currentStockIdentityProfile =", 1)[1].split(
            "legacyStockIdentityProfile =", 1
        )[0]
        legacy = source.split("legacyStockIdentityProfile =", 1)[1].split(
            "stockIdentityProfiles =", 1
        )[0]

        current_hashes = re.findall(r'"([0-9a-f]{64})"', current)
        self.assertEqual(len(current_hashes), 2)
        self.assertIn("version: 1", current)
        self.assertIn('replacementKey: "xray"', current)
        self.assertIn('group: "interactive"', current)
        self.assertIn(
            "materialSemanticSHA256: stockMaterialSemanticSHA256",
            current,
        )

        legacy_hashes = re.findall(r'"([0-9a-f]{64})"', legacy)
        self.assertEqual(len(legacy_hashes), 2)
        self.assertTrue(set(current_hashes).isdisjoint(legacy_hashes))
        self.assertIn("version: nil", legacy)
        self.assertIn("replacementKey: nil", legacy)
        self.assertIn('group: "colorize"', legacy)
        self.assertIn(
            "materialSemanticSHA256: stockMaterialSemanticSHA256",
            legacy,
        )

        matcher = AUTHORED_XRAY_STOCK_IDENTITY_SOURCE.read_text(encoding="utf-8")
        for call in (
            "definitionMatches(",
            "materialMatches(",
            "semanticSHA256: profile.materialSemanticSHA256",
            "shaderContractMatches(",
        ):
            self.assertIn(call, matcher)

    def test_launch_uses_production_identity_api_not_dedicated_execution_leaf(self) -> None:
        launch = LAUNCH_SOURCE.read_text(encoding="utf-8")
        self.assertIn(
            "SceneAuthoredXRayPlanner.verifiedStockIdentityEffectKeys(",
            launch,
        )
        self.assertNotIn("executionPlan.xRay", launch)


if __name__ == "__main__":
    unittest.main()
