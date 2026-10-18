#!/usr/bin/env python3
"""inline alpha 第二级显示权释放的行为级 builder fixture（d86e9013 checkpoint 欠账）。

真编译 harness（test_scene_solid_layers.py 形态）：磁盘 fixture（project.json +
scene.json）经 SceneProjectLoader/SceneDocumentLoader/SceneAssetCatalogLoader/
SceneRenderDescriptorBuilder 真链进入 SceneRuntimeModelBuilder.build，断言
build 后 renderDescriptor 上的 displayScriptOwnership 与 SceneLayerVisibility
可见集，钉死三层行为：

1. value:null 的 inline alpha wrapper 无任何发布路径认领 → 第二 tier
   （SceneScriptScalarDisplayProjection.applyUnclaimedFallback）把
   displayScriptOwnership.alpha 释放为 false，层回到 authored alpha 显示。
2. 被发布路径认领的 alpha 目标不被第二 tier 释放：timeline-only 认领的层
   （claimed 集合是 shared ∪ scalar-projected ∪ timeline 的并集）保持
   alpha == true；scalar/shared 认领的层由各自的第一 tier 投影更早释放，
   同样以 alpha == false 落地（admit 桶既有语义，本 fixture 一并钉死终态）。
3. 无脚本的层 ownership 为空（visible:false, alpha:false）——文档对象上
   ownership 是非可选解析产物（SceneDocumentObject.swift），descriptor 原样
   携带；消费端把 nil 与 empty 同等对待（SceneLayerVisibility.isEmpty）。

Harness 只编译真实链路文件；stub 仅限链路之外的叶子（QuickJS VM 运行时、
launch 图 planner/路由准入、MDL 读取、粒子文本叶子），stub 形状沿用
test_scene_solid_layers.py 与 test_scene_script_binding_parser.py 的既有
先例。不构建 App。
"""

from __future__ import annotations

import json
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
SOURCE_ROOT = REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene"
SWIFT_SOURCES = [
    REPOSITORY_ROOT / "script/tests/fixtures/SceneProgramResourcePlanningUnavailableStub.swift",
    REPOSITORY_ROOT / "script/tests/fixtures/SceneStaticModelMaterialBindingUnavailableStub.swift",
    SOURCE_ROOT / "Runtime/Frame/SceneStaticModelMaterialBindings.swift",
    Path(__file__).resolve().parents[2] / "MyWallpaperX/Core/SteamWorkshopScene/Resources/Textures/SceneResourceBudget.swift",
    SOURCE_ROOT / "Diagnostics/ScenePerformanceCounterHub.swift",
    SOURCE_ROOT / "Format/SceneCompatibilityContext.swift",
    SOURCE_ROOT / "Rendering/Composition/SceneBloomPostProcess.swift",
    SOURCE_ROOT / "Systems/Properties/SceneDynamicSnapshot.swift",
    SOURCE_ROOT / "Format/SceneDocument.swift",
    SOURCE_ROOT / "Format/SceneDocument+General.swift",
    SOURCE_ROOT / "Format/SceneDocument+ShaderValue.swift",
    SOURCE_ROOT / "Format/SceneDocument+Timeline.swift",
    SOURCE_ROOT / "Format/SceneDocumentObject.swift",
    SOURCE_ROOT / "Format/SceneObjectDependency.swift",
    SOURCE_ROOT / "Format/SceneDirectionalLightDefinition.swift",
    SOURCE_ROOT / "Format/ScenePointLightDefinition.swift",
    SOURCE_ROOT / "Format/SceneSpotLightDefinition.swift",
    SOURCE_ROOT / "Format/SceneTimelineAnimation.swift",
    SOURCE_ROOT / "Format/SceneDocument+NumericParsing.swift",
    SOURCE_ROOT / "Format/ScenePuppetAnimationLayer.swift",
    SOURCE_ROOT / "Format/SceneJSONValue.swift",
    SOURCE_ROOT / "Format/SceneScriptBindingDefinition.swift",
    SOURCE_ROOT / "Systems/Properties/SceneScriptDynamicProviderHostContract.swift",
    SOURCE_ROOT / "Format/SceneScriptSourceEvidence.swift",
    SOURCE_ROOT / "Compilation/Material/SceneEffectDefinition.swift",
    SOURCE_ROOT / "Compilation/Material/SceneEffectTextureInput.swift",
    SOURCE_ROOT / "Rendering/Composition/SceneUtilityLayer.swift",
    SOURCE_ROOT / "Compilation/Material/SceneRenderTargetVocabulary.swift",
    SOURCE_ROOT / "Resources/Assets/SceneModelResourceIdentity.swift",
    SOURCE_ROOT / "Runtime/Frame/SceneRenderDescriptor.swift",
    SOURCE_ROOT / "Runtime/Frame/SceneRenderDescriptor+Layer.swift",
    SOURCE_ROOT / "Runtime/Frame/SceneRenderDescriptor+AuthoredAssets.swift",
    SOURCE_ROOT / "Systems/Input/SceneLayerParallax.swift",
    SOURCE_ROOT / "Rendering/Geometry/SceneMatrix.swift",
    SOURCE_ROOT / "Systems/Puppet/ScenePuppetAttachmentFrameSnapshot.swift",
    SOURCE_ROOT / "Rendering/Geometry/SceneLayerWorldFrameResolver.swift",
    SOURCE_ROOT / "Rendering/Geometry/SceneLayerDynamicWorldFrameResolver.swift",
    SOURCE_ROOT / "Systems/Particles/SceneParticleWorldSpacePlan.swift",
    SOURCE_ROOT / "Systems/Particles/SceneParticleWorldSpacePlan+Descriptor.swift",
    SOURCE_ROOT / "Rendering/Metal/SceneMetalPipeline.swift",
    SOURCE_ROOT / "Resources/Textures/SceneSolidLayerTexture.swift",
    Path(__file__).resolve().parents[2] / "MyWallpaperX/Shared/WorkshopPropertyDisplayResolver.swift",
    SOURCE_ROOT / "Format/SceneProject.swift",
    SOURCE_ROOT / "Format/ScenePkgExtractionReport.swift",
    SOURCE_ROOT / "Resources/Assets/SceneResourceIndex.swift",
    SOURCE_ROOT / "Resources/Assets/SceneResourceView.swift",
    SOURCE_ROOT / "Resources/Assets/SceneAssetCatalog.swift",
    SOURCE_ROOT / "Resources/Assets/SceneResourceReferenceIndex.swift",
    SOURCE_ROOT / "Runtime/Frame/SceneCapabilityProfile.swift",
    SOURCE_ROOT / "Runtime/Frame/SceneRuntimeSourceFacts.swift",
    SOURCE_ROOT / "Runtime/Frame/SceneRuntimeModel.swift",
    SOURCE_ROOT / "Runtime/Frame/SceneRuntimeInput.swift",
    SOURCE_ROOT / "Runtime/Frame/SceneInitialMediaEffectVisibilityProjection.swift",
    SOURCE_ROOT / "Systems/Properties/SceneUserProperty.swift",
    SOURCE_ROOT / "Systems/Properties/SceneUserPropertyBindings.swift",
    SOURCE_ROOT / "Systems/Properties/ScenePuppetAnimationPropertyTarget.swift",
    SOURCE_ROOT / "Systems/Properties/SceneDefault2DCameraInputProfile.swift",
    SOURCE_ROOT / "Systems/Properties/ScenePropertyBindingProgram.swift",
    SOURCE_ROOT / "Systems/Properties/ScenePropertyBindingCompiler+TargetMapping.swift",
    SOURCE_ROOT / "Systems/Properties/ScenePropertyBindingProgramValidator.swift",
    SOURCE_ROOT / "Systems/Properties/SceneMaterialPropertyBindingCompiler.swift",
    SOURCE_ROOT / "Systems/Properties/SceneSharedLayerAlphaCompiler.swift",
    SOURCE_ROOT / "Systems/Properties/SceneSharedLayerAlphaProgram.swift",
    SOURCE_ROOT / "Systems/Properties/SceneSharedLayerAlphaSyntax.swift",
    SOURCE_ROOT / "Systems/Properties/SceneIdentityDisplayScriptProjection.swift",
    SOURCE_ROOT / "Systems/Properties/SceneLaunchOriginTransitionCompiler+SyntaxLexer.swift",
    SOURCE_ROOT / "Systems/Script/SceneScriptScalarProgram+Projection.swift",
    SOURCE_ROOT / "Systems/Script/SceneScriptScalarDisplayProjection.swift",
    SOURCE_ROOT / "Systems/Script/SceneScriptPropertyInput.swift",
    SOURCE_ROOT / "Systems/Script/SceneScriptVectorCandidateModels.swift",
    SOURCE_ROOT / "Systems/Puppet/ScenePuppetAnimationControl.swift",
    SOURCE_ROOT / "Systems/Script/SceneScriptParticleProjection.swift",
    SOURCE_ROOT / "Systems/Script/SceneScriptLayerTopologyProjection.swift",
    SOURCE_ROOT / "Systems/Script/SceneScriptCursorHitAdmission.swift",
    SOURCE_ROOT / "Systems/Timeline/SceneTimelineTargetCompiler.swift",
    SOURCE_ROOT / "Systems/Timeline/SceneTimelineTargetCompiler+Camera.swift",
    SOURCE_ROOT / "Rendering/Geometry/SceneLayerVisibility.swift",
    SOURCE_ROOT / "Systems/Properties/SceneUserPropertyDefinitionParser.swift",
    SOURCE_ROOT / "Systems/Properties/SceneUserPropertyResolver.swift",
    SOURCE_ROOT / "Format/ScenePkgReader.swift",
    SOURCE_ROOT / "Format/SceneMdlPuppetAttachmentReader.swift",
    SOURCE_ROOT / "Compilation/ShaderContract/SceneShaderSourceGraph.swift",
    SOURCE_ROOT / "Compilation/ShaderContract/SceneShaderLegacyAnnotationJSON.swift",
    SOURCE_ROOT / "Compilation/ShaderContract/SceneShaderContract.swift",
    SOURCE_ROOT / "Resources/Assets/SceneShaderSourceGraphBuilder.swift",
    SOURCE_ROOT / "Resources/Assets/SceneShaderSourceResolver.swift",
    SOURCE_ROOT / "Compilation/ShaderContract/SceneShaderContractLoader.swift",
    SOURCE_ROOT / "Compilation/ShaderContract/SceneBuiltinShaderIdentity.swift",
    SOURCE_ROOT / "Compilation/ShaderContract/SceneShaderContractLoader+SourceGraph.swift",
    SOURCE_ROOT / "Format/ScenePkgCacheExtractor.swift",
    SOURCE_ROOT / "Resources/Textures/SceneNamedTextureReference.swift",
    SOURCE_ROOT / "Systems/Script/SceneScriptVectorCandidateCatalog.swift",
    SOURCE_ROOT / "Systems/Script/SceneScriptDynamicImageReferenceAnalysis.swift",
    SOURCE_ROOT / "Systems/Script/SceneScriptVectorProgramModels.swift",
    SOURCE_ROOT / "Systems/Properties/SceneScriptValueOwnership.swift",
    SOURCE_ROOT / "Systems/Text/SceneTextDescriptor.swift",
    SOURCE_ROOT / "Systems/Text/SceneTextScriptDefinition.swift",
    SOURCE_ROOT / "Systems/Script/SceneScriptLayerTopologyModels.swift",
    SOURCE_ROOT / "Systems/Particles/SceneParticlePlaybackModels.swift",
    SOURCE_ROOT / "Systems/Particles/SceneParticleDefinition.swift",
    SOURCE_ROOT / "Systems/Particles/SceneParticleInitializer.swift",
    SOURCE_ROOT / "Systems/Particles/SceneParticleVortex.swift",
    SOURCE_ROOT / "Systems/Particles/SceneParticleRemapValue.swift",
    SOURCE_ROOT / "Systems/Particles/SceneParticleReduceMovement.swift",
    SOURCE_ROOT / "Systems/Particles/SceneParticleCollisionPlane.swift",
    SOURCE_ROOT / "Systems/Particles/SceneParticlePositionAroundControlPoint.swift",
    SOURCE_ROOT / "Systems/Particles/SceneParticleDefinitionParser.swift",
    SOURCE_ROOT / "Systems/Particles/SceneParticleDefinitionParser+Operator.swift",
    SOURCE_ROOT / "Systems/Particles/SceneParticleDefinitionParser+InstanceOverride.swift",
    SOURCE_ROOT / "Rendering/Dependencies/SceneNamedTextureDependencyReferenceAnalysis.swift",
]


def _keyframe(frame: int, value: float) -> dict:
    return {
        "back": {"enabled": True, "x": -1, "y": 0},
        "frame": frame,
        "front": {"enabled": True, "x": 1, "y": 0},
        "lockangle": True,
        "locklength": True,
        "value": value,
    }


def _loop_animation() -> dict:
    return {
        "c0": [_keyframe(0, 0), _keyframe(30, 1)],
        "options": {"fps": 30, "length": 60, "mode": "loop", "wraploop": True},
    }


SCENE_FIXTURE = {
    "version": 3,
    "objects": [
        {
            # a) inline 脚本写 alpha 但 wrapper value 为 null：无有限种子 ⇒
            # scalar 准入拒绝；非 shared 形态；无 Timeline ⇒ 任何发布路径都
            # 不认领 .layer(10,.alpha)，第二 tier 释放。
            "id": 10,
            "name": "Null-valued inline alpha wrapper",
            "image": "models/util/solidlayer.json",
            "size": "100 100",
            "alpha": {"script": "export function update() {}", "value": None},
        },
        {
            # b) B 形 inline alpha wrapper（number 种子，[script,value]）：
            # scalar owner 认领（第一 tier admitted target），终态 alpha
            # 所有权为 false，authored alpha 0.5 原样保留。
            "id": 20,
            "name": "Scalar-admitted inline alpha wrapper",
            "image": "models/util/solidlayer.json",
            "size": "100 100",
            "alpha": {
                "script": "export function update(value) { return value; }",
                "value": 0.5,
            },
        },
        {
            # c) 无脚本的 authored alpha 层：ownership 为空壳（非 nil）。
            "id": 30,
            "name": "Authored alpha without script",
            "image": "models/util/solidlayer.json",
            "size": "100 100",
            "alpha": 0.25,
        },
        {
            # A 形 wrapper（[animation,script,value]）且 Timeline 编译出该
            # alpha target：走 scalar 准入的 timeline 分支，第一 tier 释放。
            "id": 40,
            "name": "Timeline alpha wrapper with inline script",
            "image": "models/util/solidlayer.json",
            "size": "100 100",
            "alpha": {
                "script": "export function update(value) { return value; }",
                "value": 0.75,
                "animation": _loop_animation(),
            },
        },
        {
            # Timeline 认领（[animation,script,scriptproperties,value] 形态
            # 不满足 scalar 准入的 wrapper 白名单）但 scalar/shared 不认领：
            # claimed 并集里的 timeline 成员让第二 tier 保持 alpha == true
            # ——构建后唯一以 alpha == true 落地的认领形态。
            "id": 50,
            "name": "Timeline-only claimed alpha wrapper",
            "image": "models/util/solidlayer.json",
            "size": "100 100",
            "alpha": {
                "script": "export function update(value) { return value + step; }",
                "value": 0.6,
                "scriptproperties": {"step": 0.1},
                "animation": _loop_animation(),
            },
        },
    ],
}

PROJECT_FIXTURE = {"type": "scene", "file": "scene.json"}


HARNESS_SOURCE = r'''
// Probe shell: run the real SceneRuntimeModelBuilder disk chain and dump the
// post-build display-ownership state. Stubs below stand in for leaves outside
// the asserted chain (QuickJS VM runtime, launch-graph planner/route
// admission, MDL reading, base-material modulation); their shapes follow the
// committed harness precedents in test_scene_solid_layers.py and
// test_scene_script_binding_parser.py.
enum SceneGraphRenderTargetPlan { enum TextureFormat { case rgba16f, rgbaBackbuffer } }
import Foundation
import Metal

// This builder/factory gate does not prepare native FOV consumers.
enum SceneParticleCameraFrame {
    static func acceptsNativePerspectiveProjection(camera: SceneRenderDescriptor.CameraDescriptor) -> Bool { false }
}

enum SceneMdlStaticModelReader {
    static func readMaterialPathMetadata(data rawData: Data) throws -> String { "" }
    static func readMaterialPathsMetadata(data: Data) throws -> [String] { [] }
}

nonisolated struct SceneScriptScalarProgram {}

nonisolated final class SceneScriptVectorProgram: @unchecked Sendable {}

final class SceneScriptValueOwner: @unchecked Sendable {
    static func acceptsScalar(_ value: Double, for target: SceneDynamicTarget) -> Bool {
        guard value.isFinite else { return false }
        if case .layer(_, .intensity) = target {
            return value >= 0 && value <= Double(Float.greatestFiniteMagnitude)
        }
        return true
    }
}

struct SceneScriptScalarBudget: Sendable {}

final class SceneScriptQuickJSDomain: @unchecked Sendable {
    init(budget: SceneScriptScalarBudget) throws {}
    func configureLayerCatalog(_ descriptor: SceneRenderDescriptor) throws {}
}

struct SceneScriptMaterialFunctionMutation: Equatable, Sendable {}
struct SceneTimelinePlaybackMutation: Equatable, Sendable {}
struct SceneTextureAnimationCommand: Equatable, Sendable {}
enum SceneScriptScalarRuntimeFailure: Error, Equatable, Sendable { case unavailable }

struct SceneScriptLayerMutation: Equatable, Sendable {
    enum Kind: Equatable, Sendable { case upsert, destroy }

    struct Fields: OptionSet, Equatable, Sendable {
        let rawValue: UInt32
        static let origin = Self(rawValue: 1 << 0)
        static let scale = Self(rawValue: 1 << 1)
        static let angles = Self(rawValue: 1 << 2)
        static let visibility = Self(rawValue: 1 << 3)
        static let solid = Self(rawValue: 1 << 4)
        static let text = Self(rawValue: 1 << 5)
        static let font = Self(rawValue: 1 << 6)
        static let alpha = Self(rawValue: 1 << 7)
        static let color = Self(rawValue: 1 << 8)
        static let effectVisibility = Self(rawValue: 1 << 9)
        static let authoredFields: Self = [
            .origin, .scale, .angles, .visibility, .solid, .text, .font,
            .alpha, .color, .effectVisibility,
        ]
    }

    let kind: Kind
    let isDynamic: Bool
    let fields: Fields
    let layerID: Int
    let orderIndex: Int
    let visible: Bool
    let solid: Bool
    let size: SIMD2<Double>?
    let perspective: Bool?
    let alpha: Double
    let origin: SIMD3<Double>
    let scale: SIMD3<Double>
    let angles: SIMD3<Double>
    let color: SIMD3<Double>
    let pointSize: Double
    let text: String
    let font: String
    let assetPath: String?
    let ownerTarget: SceneDynamicTarget?
    let effectVisibilities: [Int: Bool]

    init(
        kind: Kind, isDynamic: Bool, fields: Fields, layerID: Int,
        orderIndex: Int, visible: Bool, solid: Bool, alpha: Double,
        origin: SIMD3<Double>, scale: SIMD3<Double>, angles: SIMD3<Double>,
        color: SIMD3<Double>, pointSize: Double, text: String, font: String,
        assetPath: String?, ownerTarget: SceneDynamicTarget? = nil,
        effectVisibilities: [Int: Bool] = [:], size: SIMD2<Double>? = nil,
        perspective: Bool? = nil
    ) {
        self.kind = kind
        self.isDynamic = isDynamic
        self.fields = fields
        self.layerID = layerID
        self.orderIndex = orderIndex
        self.visible = visible
        self.solid = solid
        self.size = size
        self.perspective = perspective
        self.alpha = alpha
        self.origin = origin
        self.scale = scale
        self.angles = angles
        self.color = color
        self.pointSize = pointSize
        self.text = text
        self.font = font
        self.assetPath = assetPath
        self.ownerTarget = ownerTarget
        self.effectVisibilities = effectVisibilities
    }
}

struct SceneScriptPuppetBoneMutation: Equatable, Sendable {}
struct SceneScriptMediaPlaybackCommand: Equatable, Sendable {}
struct SceneScriptParticlePlaybackCommand: Equatable, Sendable {}

struct SceneScriptOwnerEffects: Equatable, Sendable {
    var materialFunctionMutations: [SceneScriptMaterialFunctionMutation] = []
    var animationMutations: [SceneTimelinePlaybackMutation] = []
    var layerMutations: [SceneScriptLayerMutation] = []
    var puppetBoneMutations: [SceneScriptPuppetBoneMutation] = []
    var mediaPlaybackCommands: [SceneScriptMediaPlaybackCommand] = []
    var textureAnimationCommands: [SceneTextureAnimationCommand] = []
    var particlePlaybackCommands: [SceneScriptParticlePlaybackCommand] = []
    var puppetAnimationCommands: [ScenePuppetAnimationCommand] = []
    var puppetAnimationCallbackRegistrations = 0
    var layerTopologyOwnerIdentity: UInt64? = nil
}

struct SceneScriptMediaEventMutations: Equatable, Sendable {
    var materialFunctions: [SceneScriptMaterialFunctionMutation] = []
    var animations: [SceneTimelinePlaybackMutation] = []
    var layers: [SceneScriptLayerMutation] = []
    var puppetBones: [SceneScriptPuppetBoneMutation] = []
    var mediaPlaybackCommands: [SceneScriptMediaPlaybackCommand] = []
    var textureAnimationCommands: [SceneTextureAnimationCommand] = []
    var particlePlaybackCommands: [SceneScriptParticlePlaybackCommand] = []
    var puppetAnimationCommands: [ScenePuppetAnimationCommand] = []
    var puppetAnimationCallbackRegistrations = 0
}

enum SceneBaseMaterialColorModulationCompiler {
    struct Binding {
        let scriptSource: String?
        let scriptProperties: [String: SceneJSONValue]
        let sourceLayerID: Int
        let materialPath: String
        let colorKey: String
        let authoredColor: SIMD3<Double>
        let modelPath: String
        var alphaKey: String? = nil
        var authoredAlpha: Float = 1
        var alphaUserPropertyKey: String? = nil
        var alphaPropertyTarget: SceneDynamicTarget? {
            guard alphaUserPropertyKey != nil, let alphaKey else { return nil }
            return .materialConstant(layerID: sourceLayerID, passIndex: 0,
                name: alphaKey, materialPath: materialPath)
        }
        var colorUserPropertyKey: String? = nil
        var colorPropertyTarget: SceneDynamicTarget? {
            guard colorUserPropertyKey != nil else { return nil }
            return .materialConstant(layerID: sourceLayerID, passIndex: 0,
                name: colorKey, materialPath: materialPath)
        }
        var colorBindingPath: [SceneUserPropertyPathComponent] {
            [.key("materials"), .key(materialPath), .key("passes"), .index(0),
             .key("constantshadervalues"), .key(colorKey)]
        }
    }

    static func compile(
        descriptor: SceneRenderDescriptor,
        shaderContracts: [SceneShaderContract],
        dynamicImageModelPaths: Set<String>,
        admittedLayerColorConsumerIDs: Set<Int>
    ) -> [Binding] {
        []
    }
}

// This builder fixture has no authored shader proof (the link stub above
// returns no facts). Admission's real behavior is covered by the provider gate.
enum SceneBaseMaterialProviderBindingCompiler {
    static func admittedSourceMaterials(
        _ bindings: [SceneBaseMaterialColorModulationCompiler.Binding],
        descriptor: SceneRenderDescriptor,
        materialInstancesByLayerID: [Int: SceneDocument.SceneLayerMaterialInstance],
        propertyProgram: ScenePropertyBindingProgram,
        namedLayerIDs: Set<Int>
    ) -> [SceneBaseMaterialColorModulationCompiler.Binding] {
        precondition(bindings.isEmpty)
        return []
    }
}

enum SceneAuthoredEffectRenderPlanner {
    static func plans(
        for descriptor: SceneRenderDescriptor,
        startupInactiveEffectVisibilityTargets: Set<SceneDynamicTarget> = [],
        shaderContracts: [SceneShaderContract] = []
    ) -> [SceneAuthoredEffectRenderPlan] {
        []
    }
}

struct SceneAuthoredEffectRenderPlan: Codable, Equatable {}

enum SceneDirectBoolEffectVisibilityRouteAdmission {
    static func startupInactiveTargets(
        in descriptor: SceneRenderDescriptor,
        candidates: Set<SceneDynamicTarget>,
        dynamicLayerVisibilityOwnerTargets: Set<SceneDynamicTarget> = [],
        scriptOwnedCandidates: Set<SceneDynamicTarget> = []
    ) -> Set<SceneDynamicTarget> {
        candidates
    }
}

enum SceneTextGeometry {
    static func expandedSize(authoredSize: [Float]?, padding: Float) -> [Float]? {
        authoredSize
    }
}

@main
enum Harness {
    static func creationGeometry() -> [String: Any] {
        let template = SceneScriptPreparedResourceLayerTemplate(
            modelPath: "models/renamed-resource.json", renderSizeWH: [4, 4])
        func mutation(_ size: SIMD2<Double>?, path: String = "models/renamed-resource.json") -> SceneScriptLayerMutation {
            .init(kind: .upsert, isDynamic: true, fields: [], layerID: -1,
                orderIndex: 0, visible: true, solid: true, alpha: 1,
                origin: .init(10, 20, 30), scale: .init(2, 3, 4),
                angles: .init(0, 0.6, 0), color: .init(1, 1, 1),
                pointSize: 32, text: "", font: "", assetPath: path,
                size: size, perspective: true)
        }
        let created = SceneRenderDescriptor.Layer.preparedResourceLayer(mutation(.init(200, 100)), template: template)
        let fallback = SceneRenderDescriptor.Layer.preparedResourceLayer(mutation(nil), template: template)
        return ["explicitSize": created?.renderSizeWH ?? [],
            "preparedFallbackSize": fallback?.renderSizeWH ?? [],
            "usesPerspective": created?.usesPerspective == true,
            "anglesRemainRadians": created?.anglesXYZ == [0, 0.6, 0],
            "invalidSizeRejected": SceneRenderDescriptor.Layer.preparedResourceLayer(mutation(.init(0, 100)), template: template) == nil &&
                SceneRenderDescriptor.Layer.preparedResourceLayer(mutation(.init(.infinity, 100)), template: template) == nil,
            "unmatchedResourceRejected": SceneRenderDescriptor.Layer.preparedResourceLayer(mutation(.init(200, 100), path: "models/neighbor.json"), template: template) == nil]
    }

    static func compositionGeometry() -> [String: Any] {
        let template = SceneScriptPreparedResourceLayerTemplate(
            modelPath: "models/own-container.json", renderSizeWH: [640,480], kind: .composition)
        func mutation(_ id: Int, _ perspective: Bool?) -> SceneScriptLayerMutation {
            .init(kind: .upsert, isDynamic: true, fields: [], layerID: id,
                orderIndex: 1, visible: true, solid: false, alpha: 0.75,
                origin: .init(Double(id),20,30), scale: .init(2,3,4),
                angles: .init(0,0.6,0), color: .init(0.2,0.4,0.6),
                pointSize: 32, text: "", font: "", assetPath: template.modelPath,
                size: .init(18,9), perspective: perspective)
        }
        let layers = [nil, false, true].enumerated().compactMap {
            SceneRenderDescriptor.Layer.preparedResourceLayer(mutation(-1-$0.offset,$0.element), template: template)
        }
        var bad = template; bad.autosize = true
        var mesh = template; mesh.puppetMeshPath = "meshes/unrelated.mdl"
        return ["count":layers.count,
            "perspective":layers.map { $0.usesPerspective.map { $0 ? 1 : 0 } ?? -1 },
            "sizes":layers.map { $0.renderSizeWH ?? [] },
            "independent":Set(layers.map(\.id)).count == 3 && layers.map { $0.originXYZ?[0] ?? 0 } == [-1,-2,-3],
            "emptyOnly":layers.allSatisfy { $0.contentKind == "composition" && $0.utilityLayer?.kind == .composition
                && $0.utilityLayer?.copyBackground == true && $0.utilityLayer?.passthrough == false
                && $0.parentID == nil && $0.childLayerIDs.isEmpty && $0.dependencyLayerIDs.isEmpty
                && $0.authoredDependencies.isEmpty && $0.effects.isEmpty && $0.effectFiles.isEmpty
                && $0.scriptBindings == nil && !$0.hasInlineScript && $0.texturePaths.isEmpty
                && $0.puppetMeshPath == nil && $0.hasPerspectiveGeometryConsumer },
            "invalidTemplateRejected":SceneRenderDescriptor.Layer.preparedResourceLayer(mutation(-1,true),template:bad) == nil
                && SceneRenderDescriptor.Layer.preparedResourceLayer(mutation(-1,true),template:mesh) == nil]
    }

    static func main() throws {
        guard CommandLine.arguments.count == 2 else {
            throw HarnessError.missingFixture
        }
        let rootURL = URL(fileURLWithPath: CommandLine.arguments[1])
        let model = try SceneRuntimeModelBuilder().build(rootURL: rootURL)
        let layers: [[String: Any]] = model.renderDescriptor.layers.map { layer in
            [
                "id": layer.id,
                "contentKind": layer.contentKind,
                "alpha": layer.alpha.map { NSNumber(value: $0) } ?? NSNull(),
                "visible": layer.visible.map { NSNumber(value: $0) } ?? NSNull(),
                "ownership": [
                    "present": NSNumber(value: layer.displayScriptOwnership != nil),
                    "visible": NSNumber(
                        value: layer.displayScriptOwnership?.visible ?? false
                    ),
                    "alpha": NSNumber(
                        value: layer.displayScriptOwnership?.alpha ?? false
                    ),
                ],
            ]
        }
        let preparedSizes: [Int: [Float]] = [10: [200,100], 20: [1,1]]
        let preparedInput = model.runtimeInput.applyingPreparedImageGeometry(preparedSizes)
        let preparedAuthored = model.authoredRenderDescriptor.applyingPreparedImageGeometry(preparedSizes)
        let preparedLayers = preparedInput.renderDescriptor.layers
        let naturalLayer = preparedLayers.first { $0.id == 10 }!
        let defaultLayer = preparedLayers.first { $0.id == 20 }!
        let preparedGeometry: [String: Any] = [
            "naturalSize": naturalLayer.renderSizeWH ?? [], "defaultSize": defaultLayer.sizeWH ?? [],
            "naturalCursorAccepted": SceneScriptCursorHitAdmission.accepts(naturalLayer),
            "defaultCursorAccepted": SceneScriptCursorHitAdmission.accepts(defaultLayer),
            "sameAuthoredSize": preparedAuthored.layers.first { $0.id == 10 }?.sizeWH == naturalLayer.sizeWH,
            "configurationRetained": preparedLayers.map(\.initialConfiguration) == model.renderDescriptor.layers.map(\.initialConfiguration),
            "authorSizeRetained": naturalLayer.size == model.renderDescriptor.layers.first { $0.id == 10 }?.size,
            "peerUntouched": preparedLayers.first { $0.id == 30 }?.sizeWH == model.renderDescriptor.layers.first { $0.id == 30 }?.sizeWH,
            "originalDescriptorUnchanged": model.renderDescriptor.layers.first { $0.id == 10 }?.sizeWH == [100,100]
        ]
        let catalogDimensions: [String: [String: Any]] = Dictionary(uniqueKeysWithValues:
            model.assetCatalog.models.filter { $0.relativePath.hasPrefix("models/field-presence-") }.map {
                ($0.relativePath, ["present": $0.hasDeclaredSizeFields, "parsed": $0.declaredSizeWH ?? []])
            })
        let rawSizePresence: [String: [String: Any]] = Dictionary(uniqueKeysWithValues:
            model.renderDescriptor.layers.filter { $0.id >= 101 }.map { layer in
                var present = false
                if case let .object(authored)? = layer.initialConfiguration { present = authored["size"] != nil }
                return (String(layer.id), ["present": present, "size": layer.sizeWH ?? []])
            })
        let payload: [String: Any] = [
            "releaseHasNoDiagnosticPayload": !Mirror(reflecting: model).children.contains {
                ["resourceReferences", "capabilityProfile", "resourceIndex"].contains($0.label ?? "")
            } && !Mirror(reflecting: model.renderDescriptor).children.contains {
                ["firstStageRendererGaps", "effectDefinitionDiagnostics", "missingResources"].contains($0.label ?? "")
            },
            "rawSizePresence": rawSizePresence,
            "catalogDimensions": catalogDimensions,
            "preparedGeometry": preparedGeometry,
            "creationGeometry": creationGeometry(),
            "compositionGeometry": compositionGeometry(),
            "layers": layers,
            "visibleLayerIDs": SceneLayerVisibility.visibleLayerIDs(
                in: model.renderDescriptor
            ).sorted(),
            "sharedAlphaTargets": model.sharedLayerAlphaProgram.definitions.map {
                "\($0.target)"
            },
        ]
        let data = try JSONSerialization.data(
            withJSONObject: payload,
            options: [.sortedKeys]
        )
        print(String(decoding: data, as: UTF8.self))
    }

    enum HarnessError: Error {
        case missingFixture
    }
}
'''


def layer_result(payload: dict, layer_id: int) -> dict:
    matches = [l for l in payload["layers"] if l["id"] == layer_id]
    assert len(matches) == 1, f"layer {layer_id} missing from harness payload"
    return matches[0]


class SceneAlphaDisplayBuilderFixtureTests(unittest.TestCase):
    def test_prepared_geometry_is_shared_by_actual_descriptor_input_and_cursor_consumers(self) -> None:
        geometry = self.result["preparedGeometry"]
        self.assertEqual(geometry["naturalSize"], [200, 100])
        self.assertEqual(geometry["defaultSize"], [1, 1])
        for key in ("naturalCursorAccepted", "defaultCursorAccepted", "sameAuthoredSize",
                    "configurationRetained", "authorSizeRetained", "peerUntouched", "originalDescriptorUnchanged"):
            self.assertTrue(geometry[key], key)

    def test_actual_model_parser_preserves_dimension_field_presence(self) -> None:
        facts = self.result["catalogDimensions"]
        absent = facts["models/field-presence-absent.json"]
        self.assertFalse(absent["present"])
        self.assertEqual(absent["parsed"], [])
        for name in ("width", "height", "invalid"):
            case = facts[f"models/field-presence-{name}.json"]
            self.assertTrue(case["present"], name)
            self.assertEqual(case["parsed"], [], name)
        self.assertEqual(facts["models/field-presence-pair.json"], {"present": True, "parsed": [80, 40]})

    def test_actual_layer_parser_distinguishes_size_key_absence_from_unsupported_values(self) -> None:
        facts = self.result["rawSizePresence"]
        for layer_id in (101, 102, 103, 104):
            self.assertTrue(facts[str(layer_id)]["present"], layer_id)
            self.assertEqual(facts[str(layer_id)]["size"], [0, 0])
        self.assertEqual(facts["105"], {"present": False, "size": [0, 0]})

    def test_dynamic_creation_projection_preserves_geometry_and_rejects_neighbors(self) -> None:
        geometry = self.result["creationGeometry"]
        self.assertEqual(geometry["explicitSize"], [200, 100])
        self.assertEqual(geometry["preparedFallbackSize"], [1, 1])
        for key in ("usesPerspective", "anglesRemainRadians", "invalidSizeRejected", "unmatchedResourceRejected"):
            self.assertIs(geometry[key], True, key)

    @classmethod
    def setUpClass(cls) -> None:
        swiftc = shutil.which("swiftc")
        if swiftc is None:
            raise unittest.SkipTest("swiftc is unavailable")
        missing_sources = [path for path in SWIFT_SOURCES if not path.is_file()]
        if missing_sources:
            raise RuntimeError(
                "Scene alpha display builder fixture is missing real sources: "
                + ", ".join(path.name for path in missing_sources)
            )

        cls.temporary_directory = tempfile.TemporaryDirectory(
            prefix="mwx-scene-alpha-display-builder-"
        )
        directory = Path(cls.temporary_directory.name)
        scene_root = directory / "fixture-scene"
        scene_root.mkdir()
        scene_fixture = json.loads(json.dumps(SCENE_FIXTURE))
        for layer_id, raw in [(101, None), (102, []), (103, {"value": 0}), (104, {"value": "0 0"}), (105, "absent")]:
            item = {"id": layer_id, "image": "models/field-presence-absent.json", "visible": False}
            if raw != "absent":
                item["size"] = raw
            scene_fixture["objects"].append(item)
        (scene_root / "scene.json").write_text(json.dumps(scene_fixture), encoding="utf-8")
        (scene_root / "project.json").write_text(
            json.dumps(PROJECT_FIXTURE), encoding="utf-8"
        )
        (scene_root / "models").mkdir()
        (scene_root / "materials").mkdir()
        (scene_root / "materials/field-presence.json").write_text(json.dumps({"passes": [
            {"shader": "genericimage2", "textures": ["materials/field-presence.png"], "combos": {"VERSION": 2}}
        ]}))
        import base64
        (scene_root / "materials/field-presence.png").write_bytes(base64.b64decode(
            "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jWZkAAAAASUVORK5CYII="))
        for name, fields in {"absent": {}, "width": {"width": 80}, "height": {"height": 40},
                             "invalid": {"width": "invalid", "height": 40},
                             "pair": {"width": 80, "height": 40}}.items():
            (scene_root / "models" / f"field-presence-{name}.json").write_text(json.dumps({"material": "materials/field-presence.json", **fields}))
        harness = directory / "Harness.swift"
        # Link the actual data-only particle environment leaf; this solid/text
        # builder fixture does not execute particle simulation.
        force = (SOURCE_ROOT / "Systems/Particles/SceneParticleControlPointForce.swift").read_text()
        start = force.index("nonisolated struct SceneParticleControlPointForceEnvironment:")
        environment = force[start:force.index("\n}", start) + 2]
        harness.write_text(environment + "\n" + HARNESS_SOURCE, encoding="utf-8")
        cls.binary = directory / "scene-alpha-display-builder"
        compilation = subprocess.run(
            [
                "xcrun",
                "--sdk",
                "macosx",
                "swiftc",
                *(str(path) for path in SWIFT_SOURCES),
                str(harness),
                "-framework",
                "Metal",
                "-o",
                str(cls.binary),
            ],
            capture_output=True,
            text=True,
            shell=False,
        )
        if compilation.returncode != 0:
            raise RuntimeError(compilation.stderr)
        completed = subprocess.run(
            ["/usr/bin/env", str(cls.binary), str(scene_root)],
            check=True,
            capture_output=True,
            text=True,
            shell=False,
        )
        cls.result = json.loads(completed.stdout)

    @classmethod
    def tearDownClass(cls) -> None:
        if hasattr(cls, "temporary_directory"):
            cls.temporary_directory.cleanup()

    def test_empty_composition_factory_preserves_tristate_and_independent_geometry(self) -> None:
        value = self.result["compositionGeometry"]
        self.assertEqual(value["count"], 3)
        self.assertEqual(value["perspective"], [-1, 0, 1])
        self.assertEqual(value["sizes"], [[18, 9]] * 3)
        for key in ("independent", "emptyOnly", "invalidTemplateRejected"):
            with self.subTest(key=key):
                self.assertIs(value[key], True)

    def test_release_model_keeps_playback_without_sample_diagnostic_payload(self) -> None:
        self.assertTrue(self.result["releaseHasNoDiagnosticPayload"])

    def test_fixture_loads_all_authored_layers(self) -> None:
        self.assertEqual(
            [l["id"] for l in self.result["layers"]], [10, 20, 30, 40, 50, 101, 102, 103, 104, 105]
        )
        # 本 fixture 无 shared-alpha 形态：shared 发布路径认领为零。
        self.assertEqual(self.result["sharedAlphaTargets"], [])

    def test_null_valued_inline_alpha_wrapper_releases_to_authored_display(
        self,
    ) -> None:
        # a) value:null 的 inline alpha wrapper 无任何发布路径认领：
        # 第二 tier applyUnclaimedFallback 把 ownership.alpha 释放为 false。
        layer = layer_result(self.result, 10)
        self.assertEqual(
            layer["ownership"],
            {"present": True, "visible": False, "alpha": False},
        )
        # visible 位与 authored alpha 原样保留（wrapper 无 authored 数值 ⇒
        # descriptor alpha 保持 nil，由下游默认值接管）。
        self.assertIsNone(layer["alpha"])
        self.assertIsNone(layer["visible"])

    def test_scalar_admitted_alpha_wrapper_lands_released_with_authored_alpha(
        self,
    ) -> None:
        # b) scalar owner 认领的 alpha 脚本层：admitted target 由既有第一
        # tier（SceneScriptScalarDisplayProjection.apply）释放，构建后
        # ownership.alpha 落地为 false；wrapper 的 authored alpha 0.5 原样
        # 保留。第二 tier 的 claimed 守护不重复触碰已释放的层。
        layer = layer_result(self.result, 20)
        self.assertEqual(
            layer["ownership"],
            {"present": True, "visible": False, "alpha": False},
        )
        self.assertAlmostEqual(layer["alpha"], 0.5, places=6)

    def test_layer_without_script_keeps_empty_not_nil_ownership(self) -> None:
        # c) 无脚本层：ownership 是解析产物（非可选），落地为空壳
        # （visible:false, alpha:false）而不是 nil；authored alpha 0.25
        # 原样保留。消费端把 nil 与 empty 同等对待（SceneLayerVisibility
        # 的 isEmpty 门）。
        layer = layer_result(self.result, 30)
        self.assertEqual(
            layer["ownership"],
            {"present": True, "visible": False, "alpha": False},
        )
        self.assertAlmostEqual(layer["alpha"], 0.25, places=6)

    def test_timeline_admitted_alpha_wrapper_keeps_first_tier_release(
        self,
    ) -> None:
        # A 形 wrapper（[animation,script,value]）且 Timeline 编译出该
        # alpha target：scalar 准入的 timeline 分支认领，第一 tier 释放，
        # authored alpha 0.75 原样保留。
        layer = layer_result(self.result, 40)
        self.assertEqual(
            layer["ownership"],
            {"present": True, "visible": False, "alpha": False},
        )
        self.assertAlmostEqual(layer["alpha"], 0.75, places=6)

    def test_timeline_only_claimed_alpha_target_is_not_released(self) -> None:
        # claimed 并集的负控制：层 50 的 .layer(50,.alpha) 只被 timeline
        # 认领（wrapper 带 scriptproperties，不在 scalar 准入白名单），
        # applyUnclaimedFallback 不得释放它——构建后唯一以 alpha == true
        # 落地的认领形态。
        layer = layer_result(self.result, 50)
        self.assertEqual(
            layer["ownership"],
            {"present": True, "visible": False, "alpha": True},
        )
        self.assertAlmostEqual(layer["alpha"], 0.6, places=6)

    def test_release_keeps_released_layers_in_the_visible_set(self) -> None:
        # 释放贯通到合成可见集：释放/无压制的层（10/20/30/40）全部可见；
        # 唯一保持 alpha 所有权的目标（50，timeline-only 认领）留在
        # SceneLayerVisibility 未释放的抑制分支上——该分支按设计原样保留，
        # 作为未来形态的回滚面。
        self.assertEqual(self.result["visibleLayerIDs"], [10, 20, 30, 40])


if __name__ == "__main__":
    unittest.main()
