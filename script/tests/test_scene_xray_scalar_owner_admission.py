#!/usr/bin/env python3
"""Controlled executable owner partition for current-stock X-Ray scalars."""

from __future__ import annotations

import json
import os
from pathlib import Path
import runpy
import shutil
import subprocess
import tempfile
import unittest


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
SCENE_ROOT = REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene"
STOCK_ROOT = (
    REPOSITORY_ROOT
    / "MyWallpaperX/Resources/SceneStockAssets.bundle/assets"
)
FINALIZER_FIXTURE = runpy.run_path(
    str(REPOSITORY_ROOT / "script/tests/test_scene_resolved_material_program_finalizer.py")
)
DEDICATED_COMPILERS_SOURCE = (
    SCENE_ROOT
    / "RenderGraph/EffectCompilation/SceneEffectStageDedicatedCompilers.swift"
)
X_RAY_SUPPORT_SOURCE = (
    Path(__file__).with_name("fixtures")
    / "SceneXRayScalarOwnerAdmissionSupport.swift"
)


def unique_sources(paths: list[Path]) -> list[Path]:
    return list(dict.fromkeys(paths))


def product_xray_compiler_source() -> str:
    """Compile the exact production protocols and X-Ray compiler extension."""
    source = DEDICATED_COMPILERS_SOURCE.read_text(encoding="utf-8")
    standard_blur = source.index("extension SceneAuthoredStandardBlurPlanner")
    xray = source.index("extension SceneAuthoredXRayPlanner")
    pulse = source.index("extension SceneAuthoredPulsePlanner")
    return source[:standard_blur] + source[xray:pulse]


SWIFT_SOURCES = unique_sources([
    *FINALIZER_FIXTURE["SWIFT_SOURCES"],
    SCENE_ROOT / "Format/SceneDocument+ShaderValue.swift",
    SCENE_ROOT / "RenderGraph/SceneEffectTextureInput.swift",
    SCENE_ROOT / "RenderGraph/SceneAuthoredMaterialResolver.swift",
    SCENE_ROOT / "RenderGraph/MaterialProgram/SceneResolvedMaterialScriptBindingClassifier.swift",
    SCENE_ROOT / "RenderGraph/MaterialProgram/SceneResolvedMaterialTemplateCompiler.swift",
    SCENE_ROOT / "RenderGraph/EffectCompilation/SceneEffectStageCompileModel.swift",
    SCENE_ROOT / "RenderGraph/EffectCompilation/SceneEffectStageAuthoredFallbackOwnerPartition.swift",
    SCENE_ROOT
    / "RenderGraph/EffectCompilation/SceneEffectStageXRayScalarOwnerAdmission.swift",
    SCENE_ROOT / "Rendering/SceneLayerVisibility.swift",
    SCENE_ROOT
    / "RenderGraph/LayerDependencies/SceneImageLayerBlendDependencyContract.swift",
    SCENE_ROOT
    / "RenderGraph/LayerDependencies/SceneDependencyGraphAnalysis.swift",
    SCENE_ROOT
    / "RenderGraph/LayerDependencies/SceneDependencyRenderPlan.swift",
    SCENE_ROOT / "Effects/SceneXRayRuntimePlan.swift",
    SCENE_ROOT / "RenderGraph/SceneAuthoredXRayPlanner.swift",
    SCENE_ROOT / "Resources/SceneResourceIndex.swift",
    SCENE_ROOT / "Resources/SceneResourceView.swift",
    SCENE_ROOT / "Resources/SceneShaderSourceResolver.swift",
    SCENE_ROOT / "Resources/SceneShaderSourceGraphBuilder.swift",
    SCENE_ROOT / "RenderGraph/ShaderContract/SceneShaderContractLoader.swift",
    SCENE_ROOT / "RenderGraph/ShaderContract/SceneShaderContractLoader+SourceGraph.swift",
])


SUPPORT = r'''
import Foundation
import simd

struct SceneDocument {}
struct SceneTimelineAnimation: Codable {}

struct SceneLayerDisplayScriptOwnership {
    let fields: [String]

    var isEmpty: Bool { fields.isEmpty }
}

struct SceneUtilityLayer {
    enum Kind { case composition, project, fullscreen }

    let kind: Kind
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
        let contentKind: String
        var utilityLayer: SceneUtilityLayer? = nil
        var dependencyLayerIDs: [Int] = []
        var authoredDependencies: [Int] = []
        var parentID: Int? = nil
        var childLayerIDs: [Int] = []
        var visible: Bool? = true
        var displayScriptOwnership: SceneLayerDisplayScriptOwnership? = nil
        let effects: [EffectDescriptor]
    }

    struct MaterialPassDescriptor {
        let id: String
        let materialPath: String
        let passIndex: Int
        let shaderPath: String?
        let texturePaths: [String]
        let textureSlots: [String?]
        let userTextureInputs: [SceneEffectTextureInput?]
        let combos: [String: Int]
        let constantShaderValues: [String: SceneDocument.ShaderValue]
        let userShaderValues: [String: String]
        let blending: String?
        let depthTest: String?
        let depthWrite: String?
        let cullMode: String?
        let alphaWriting: String?
    }

    let layers: [Layer]
    let renderOrderLayerIDs: [Int]
    let materialPasses: [MaterialPassDescriptor]

    init(
        layers: [Layer],
        renderOrderLayerIDs: [Int]? = nil,
        materialPasses: [MaterialPassDescriptor]
    ) {
        self.layers = layers
        self.renderOrderLayerIDs = renderOrderLayerIDs ?? layers.map(\.id)
        self.materialPasses = materialPasses
    }
}

'''


HARNESS = r'''
import Foundation

private typealias Graph = SceneAuthoredEffectRenderPlan

private let layerID = 42
private let effectKey = Graph.EffectKey(
    layerID: layerID,
    effectIndex: 0,
    descriptorID: "42#effect#xray"
)

private func texture(
    _ kind: Graph.TextureKind,
    effect: Graph.EffectKey? = nil
) -> Graph.TextureIdentity {
    .init(kind: kind, layerID: layerID, effect: effect, name: nil)
}

private func graph() -> Graph {
    let input = texture(.layerSource)
    let output = texture(.effectOutput, effect: effectKey)
    return .init(
        layerID: layerID,
        effects: [.init(
            key: effectKey,
            definitionPath: "effects/xray/effect.json",
            input: input,
            output: output,
            nodeIndices: [0]
        )],
        renderTargets: [],
        nodes: [.init(
            nodeIndex: 0,
            effect: effectKey,
            definitionPassIndex: 0,
            materialOrdinal: 0,
            instancePassIndex: 0,
            kind: .material,
            materialPath: "materials/effects/xray.json",
            materialPassID: "materials/effects/xray.json#0",
            target: output,
            bindings: [],
            commandSource: nil,
            commandTarget: nil,
            compose: nil,
            conditions: nil
        )],
        finalOutput: output,
        blockers: []
    )
}

private func value(
    _ fallback: Double,
    propertyKey: String? = nil,
    extraBindingKey: Bool = false,
    script: String? = nil
) -> SceneDocument.ShaderValue {
    let keys = propertyKey == nil
        ? []
        : (extraBindingKey ? ["extra", "user", "value"] : ["user", "value"])
    return .init(
        rawValue: String(fallback),
        valueKind: propertyKey == nil ? "number" : "binding",
        userBinding: propertyKey,
        userValueKind: propertyKey == nil ? nil : .string,
        components: [fallback],
        scriptSource: script,
        bindingKeys: keys
    )
}

private func descriptor(
    effectVisible: Bool? = true,
    sizeProperty: String? = nil,
    multiplyProperty: String? = nil,
    extraSizeBindingKey: Bool = false,
    sizeScript: String? = nil
) -> SceneRenderDescriptor {
    let values = [
        "size": value(
            0.25,
            propertyKey: sizeProperty,
            extraBindingKey: extraSizeBindingKey,
            script: sizeScript
        ),
        "multiply": value(1.5, propertyKey: multiplyProperty),
    ]
    let pass = SceneRenderDescriptor.EffectDescriptor.PassDescriptor(
        passIndex: 0,
        texturePaths: ["textures/blend.jpg", "particle/halo_6"],
        textureSlots: [nil, "textures/blend.jpg", "particle/halo_6"],
        userTextureInputs: [],
        combos: ["BLENDMODE": 0],
        constantShaderValues: values
    )
    return .init(
        layers: [.init(
            id: layerID,
            contentKind: "image",
            effects: [.init(
                id: effectKey.descriptorID,
                file: "effects/xray/effect.json",
                visible: effectVisible,
                passes: [pass]
            )]
        )],
        materialPasses: [.init(
            id: "materials/effects/xray.json#0",
            materialPath: "materials/effects/xray.json",
            passIndex: 0,
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
        )]
    )
}

private func producer(
    _ propertyKey: String,
    name: String,
    type: SceneDynamicValueType = .scalar
) -> SceneDynamicUserPropertyProducer {
    .init(
        propertyKey: propertyKey,
        target: .effectConstant(
            layerID: layerID,
            effectIndex: 0,
            passIndex: 0,
            name: name
        ),
        valueType: type
    )
}

private func contract(_ root: URL) -> SceneShaderContract {
    let contracts = SceneShaderContractLoader().load(
        shaderReferences: ["effects/xray"],
        rootURL: root
    )
    precondition(contracts.count == 1)
    return contracts[0]
}

private func compileInput(
    root: URL,
    effectVisible: Bool? = true,
    sizeProperty: String? = nil,
    multiplyProperty: String? = nil,
    producers: Set<SceneDynamicUserPropertyProducer> = [],
    activeEffectLocalDirectBoolVisibilityTargets: Set<SceneDynamicTarget> = [],
    startupInactiveEffectVisibilityTargets: Set<SceneDynamicTarget> = [],
    frameDrivenVisibilityEffectIndex: Int? = nil,
    extraSizeBindingKey: Bool = false,
    sizeScript: String? = nil
) -> SceneEffectStageCompileInput {
    SceneEffectStageCompileInput(
        stageGraph: graph(),
        effectKey: effectKey,
        definitionPath: "effects/xray/effect.json",
        inputRole: .layerSource,
        descriptor: descriptor(
            effectVisible: effectVisible,
            sizeProperty: sizeProperty,
            multiplyProperty: multiplyProperty,
            extraSizeBindingKey: extraSizeBindingKey,
            sizeScript: sizeScript
        ),
        shaderContracts: [contract(root)],
        userPropertyProducers: producers,
        activeEffectLocalDirectBoolVisibilityTargets:
            activeEffectLocalDirectBoolVisibilityTargets,
        startupInactiveEffectVisibilityTargets:
            startupInactiveEffectVisibilityTargets,
        frameDrivenEffectVisibilityOwners: frameDrivenVisibilityEffectIndex
            .map { [.init(layerID: layerID, effectIndex: $0)] }
            ?? []
    )
}

private func admits(
    root: URL,
    sizeProperty: String? = nil,
    multiplyProperty: String? = nil,
    producers: Set<SceneDynamicUserPropertyProducer> = [],
    activeEffectLocalDirectBoolVisibilityTargets: Set<SceneDynamicTarget> = [],
    frameDrivenVisibilityEffectIndex: Int? = nil,
    extraSizeBindingKey: Bool = false,
    sizeScript: String? = nil
) -> Bool {
    let input = compileInput(
        root: root,
        sizeProperty: sizeProperty,
        multiplyProperty: multiplyProperty,
        producers: producers,
        activeEffectLocalDirectBoolVisibilityTargets:
            activeEffectLocalDirectBoolVisibilityTargets,
        frameDrivenVisibilityEffectIndex: frameDrivenVisibilityEffectIndex,
        extraSizeBindingKey: extraSizeBindingKey,
        sizeScript: sizeScript
    )
    return SceneEffectStageXRayScalarOwnerAdmission
        .acceptsDedicatedRevocation(effectKey: effectKey, input: input)
}

private func productCompilerResult(
    _ input: SceneEffectStageCompileInput
) -> (outcome: String, detail: String, envelope: String) {
    switch SceneAuthoredXRayPlanner.compile(input) {
    case .notApplicable:
        return ("not-applicable", "", "")
    case .accepted:
        return ("accepted", "", "")
    case .rejected(let failure):
        return (
            "rejected",
            failure.details.first ?? "",
            "\(failure.backend.rawValue):\(failure.phase.rawValue):\(failure.code.rawValue)"
        )
    }
}

@main
enum Harness {
    static func main() throws {
        let stock = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let wrongRange = URL(
            fileURLWithPath: CommandLine.arguments[2],
            isDirectory: true
        )
        let nonSpatial = URL(
            fileURLWithPath: CommandLine.arguments[3],
            isDirectory: true
        )
        let size = producer("xraySize", name: "size")
        let multiply = producer("xrayMultiply", name: "multiply")
        let visibility = SceneDynamicUserPropertyProducer(
            propertyKey: "xrayVisible",
            target: .effectVisibility(layerID: layerID, effectIndex: 0),
            valueType: .bool
        )
        let competingVisibility = SceneDynamicUserPropertyProducer(
            propertyKey: "competingVisible",
            target: visibility.target,
            valueType: .bool
        )
        let staticInput = compileInput(root: stock)
        let productStatic = productCompilerResult(staticInput)
        let productMissingProducer = productCompilerResult(compileInput(
            root: stock,
            sizeProperty: "xraySize"
        ))
        let productWrongProducer = productCompilerResult(compileInput(
            root: stock,
            sizeProperty: "xraySize",
            producers: [producer("xraySize", name: "size", type: .vector2)]
        ))
        let productFrameDrivenVisibility = productCompilerResult(compileInput(
            root: stock,
            frameDrivenVisibilityEffectIndex: 0
        ))
        let productWrongRange = productCompilerResult(compileInput(
            root: wrongRange
        ))
        let productNonSpatial = productCompilerResult(compileInput(
            root: nonSpatial
        ))
        let productStartup = productCompilerResult(compileInput(
            root: stock,
            effectVisible: false,
            producers: [visibility],
            startupInactiveEffectVisibilityTargets: [visibility.target]
        ))
        let result: [String: Any] = [
            "plannerStaticAccepted": SceneAuthoredXRayPlanner.plan(
                graph: staticInput.stageGraph,
                descriptor: staticInput.descriptor,
                shaderContracts: staticInput.shaderContracts,
                inputRole: staticInput.inputRole
            ) != nil,
            "productStaticOutcome": productStatic.outcome,
            "productStaticDetail": productStatic.detail,
            "productMissingProducerOutcome": productMissingProducer.outcome,
            "productWrongProducerOutcome": productWrongProducer.outcome,
            "productFrameDrivenVisibilityOutcome":
                productFrameDrivenVisibility.outcome,
            "productWrongRangeOutcome": productWrongRange.outcome,
            "productNonSpatialOutcome": productNonSpatial.outcome,
            "productStartupOutcome": productStartup.outcome,
            "productStartupDetail": productStartup.detail,
            "productStartupEnvelope": productStartup.envelope,
            "productStartupNearMisses": [
                productCompilerResult(compileInput(
                    root: stock, effectVisible: false, producers: [visibility],
                    activeEffectLocalDirectBoolVisibilityTargets: [visibility.target]
                )).outcome,
                productCompilerResult(compileInput(
                    root: stock, effectVisible: false,
                    startupInactiveEffectVisibilityTargets: [visibility.target]
                )).outcome,
                productCompilerResult(compileInput(
                    root: stock, effectVisible: false,
                    producers: [visibility, competingVisibility],
                    startupInactiveEffectVisibilityTargets: [visibility.target]
                )).outcome,
                productCompilerResult(compileInput(
                    root: stock, effectVisible: false, producers: [visibility],
                    startupInactiveEffectVisibilityTargets: [
                        .effectVisibility(layerID: layerID, effectIndex: 1),
                    ]
                )).outcome,
                productCompilerResult(compileInput(
                    root: stock, effectVisible: false, producers: [visibility],
                    startupInactiveEffectVisibilityTargets: [visibility.target],
                    frameDrivenVisibilityEffectIndex: 0
                )).outcome,
                productCompilerResult(compileInput(
                    root: stock, effectVisible: false, producers: [visibility],
                    startupInactiveEffectVisibilityTargets: [visibility.target],
                    frameDrivenVisibilityEffectIndex: 1
                )).outcome,
                productCompilerResult(compileInput(
                    root: stock, effectVisible: false,
                    producers: [.init(
                        propertyKey: "xrayVisible", target: visibility.target,
                        valueType: .vector2
                    )],
                    startupInactiveEffectVisibilityTargets: [visibility.target]
                )).outcome,
                productCompilerResult(compileInput(
                    root: stock, effectVisible: false,
                    producers: [.init(
                        propertyKey: "xrayVisible",
                        target: .effectVisibility(layerID: layerID, effectIndex: 1),
                        valueType: .bool
                    )],
                    startupInactiveEffectVisibilityTargets: [visibility.target]
                )).outcome,
            ],
            "size": admits(
                root: stock,
                sizeProperty: "xraySize",
                producers: [size]
            ),
            "multiply": admits(
                root: stock,
                multiplyProperty: "xrayMultiply",
                producers: [multiply]
            ),
            "both": admits(
                root: stock,
                sizeProperty: "xraySize",
                multiplyProperty: "xrayMultiply",
                producers: [size, multiply]
            ),
            "staticOnly": admits(root: stock),
            "staticDynamicVisibility": admits(
                root: stock,
                producers: [visibility],
                activeEffectLocalDirectBoolVisibilityTargets: [visibility.target]
            ),
            "missingProducer": admits(
                root: stock,
                sizeProperty: "xraySize"
            ),
            "wrongProducerType": admits(
                root: stock,
                sizeProperty: "xraySize",
                producers: [producer("xraySize", name: "size", type: .vector2)]
            ),
            "dynamicVisibility": admits(
                root: stock,
                sizeProperty: "xraySize",
                producers: [size, visibility],
                activeEffectLocalDirectBoolVisibilityTargets: [visibility.target]
            ),
            "unvalidatedVisibility": admits(
                root: stock,
                sizeProperty: "xraySize",
                producers: [size, visibility]
            ),
            "wrongVisibilityType": admits(
                root: stock,
                sizeProperty: "xraySize",
                producers: [
                    size,
                    SceneDynamicUserPropertyProducer(
                        propertyKey: "xrayVisible",
                        target: .effectVisibility(
                            layerID: layerID,
                            effectIndex: 0
                        ),
                        valueType: .vector2
                    ),
                ]
            ),
            "frameDrivenVisibility": admits(
                root: stock,
                sizeProperty: "xraySize",
                producers: [size],
                frameDrivenVisibilityEffectIndex: 0
            ),
            "siblingFrameDrivenVisibility": admits(
                root: stock,
                sizeProperty: "xraySize",
                producers: [size],
                frameDrivenVisibilityEffectIndex: 1
            ),
            "extraWrapperField": admits(
                root: stock,
                sizeProperty: "xraySize",
                producers: [size],
                extraSizeBindingKey: true
            ),
            "scriptAttachment": admits(
                root: stock,
                sizeProperty: "xraySize",
                producers: [size],
                sizeScript: "return 0.5;"
            ),
            "wrongRange": admits(
                root: wrongRange,
                sizeProperty: "xraySize",
                producers: [size]
            ),
            "nonSpatial": admits(
                root: nonSpatial,
                sizeProperty: "xraySize",
                producers: [size]
            ),
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
class SceneXRayScalarOwnerAdmissionTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.temporary_directory = tempfile.TemporaryDirectory(
            prefix="mwx-xray-scalar-owner-"
        )
        root = Path(cls.temporary_directory.name)
        support = root / "Support.swift"
        product_compiler = root / "ProductXRayCompiler.swift"
        harness = root / "Harness.swift"
        support.write_text(SUPPORT, encoding="utf-8")
        product_compiler.write_text(
            product_xray_compiler_source(),
            encoding="utf-8",
        )
        harness.write_text(HARNESS, encoding="utf-8")

        cls.stock = root / "stock"
        cls.wrong_range = root / "wrong-range"
        cls.non_spatial = root / "non-spatial"
        for fixture in (cls.stock, cls.wrong_range, cls.non_spatial):
            (fixture / "shaders/effects").mkdir(parents=True)
            shutil.copy2(
                STOCK_ROOT / "effects/xray/shaders/effects/xray.vert",
                fixture / "shaders/effects/xray.vert",
            )
            shutil.copy2(
                STOCK_ROOT / "effects/xray/shaders/effects/xray.frag",
                fixture / "shaders/effects/xray.frag",
            )
            shutil.copy2(
                STOCK_ROOT / "shaders/common_blending.h",
                fixture / "shaders/common_blending.h",
            )
        vertex = (cls.wrong_range / "shaders/effects/xray.vert").read_text(
            encoding="utf-8"
        )
        (cls.wrong_range / "shaders/effects/xray.vert").write_text(
            vertex.replace('"range":[0.0, 1.0]', '"range":[0.0, 2.0]'),
            encoding="utf-8",
        )
        fragment_path = cls.non_spatial / "shaders/effects/xray.frag"
        fragment = fragment_path.read_text(encoding="utf-8")
        fragment_path.write_text(
            fragment.replace(
                "albedo.rgb = ApplyBlending(BLENDMODE, albedo.rgb, mask.rgb, blend);",
                "albedo.rgb = mask.rgb;",
            ),
            encoding="utf-8",
        )

        binary = root / "xray-scalar-owner"
        environment = os.environ.copy()
        environment.pop("MWX_SCENE_NAMED_PROVIDER_ROUTE", None)
        environment["CLANG_MODULE_CACHE_PATH"] = str(root / "clang-cache")
        environment["SWIFT_MODULECACHE_PATH"] = str(root / "swift-cache")
        compilation = subprocess.run(
            [
                "xcrun", "--sdk", "macosx", "swiftc", "-parse-as-library",
                str(support),
                str(X_RAY_SUPPORT_SOURCE),
                *(str(path) for path in SWIFT_SOURCES),
                str(product_compiler),
                str(harness),
                "-framework", "Metal",
                "-framework", "CoreGraphics",
                "-framework", "ImageIO",
                "-module-cache-path", str(root / "module-cache"),
                "-o", str(binary),
            ],
            cwd=REPOSITORY_ROOT,
            env=environment,
            capture_output=True,
            text=True,
        )
        if compilation.returncode != 0:
            raise RuntimeError(compilation.stderr)
        completed = subprocess.run(
            [
                str(binary),
                str(cls.stock),
                str(cls.wrong_range),
                str(cls.non_spatial),
            ],
            cwd=REPOSITORY_ROOT,
            env=environment,
            capture_output=True,
            text=True,
        )
        if completed.returncode != 0:
            raise RuntimeError(completed.stderr)
        cls.result = json.loads(completed.stdout)

    @classmethod
    def tearDownClass(cls) -> None:
        cls.temporary_directory.cleanup()

    def test_current_stock_scalar_cohort_revokes_the_incumbent(self) -> None:
        self.assertTrue(self.result["staticOnly"])
        self.assertTrue(self.result["staticDynamicVisibility"])
        self.assertTrue(self.result["size"])
        self.assertTrue(self.result["multiply"])
        self.assertTrue(self.result["both"])
        self.assertTrue(self.result["dynamicVisibility"])

    def test_non_cohort_shapes_retain_the_incumbent(self) -> None:
        for key in (
            "missingProducer",
            "wrongProducerType",
            "wrongVisibilityType",
            "unvalidatedVisibility",
            "frameDrivenVisibility",
            "siblingFrameDrivenVisibility",
            "extraWrapperField",
            "scriptAttachment",
            "wrongRange",
            "nonSpatial",
        ):
            with self.subTest(key=key):
                self.assertFalse(self.result[key])
        for key in (
            "productMissingProducerOutcome",
            "productWrongProducerOutcome",
            "productFrameDrivenVisibilityOutcome",
            "productWrongRangeOutcome",
            "productNonSpatialOutcome",
        ):
            with self.subTest(key=key):
                self.assertEqual(self.result[key], "accepted")

    def test_launch_forwards_frame_driven_visibility_to_stage_compilers(
        self,
    ) -> None:
        launch = (
            SCENE_ROOT / "Runtime/SceneDesktopWallpaperHost+Launch.swift"
        ).read_text(encoding="utf-8")
        normalized = "".join(launch.split())
        self.assertIn(
            "letstageCompileEffectVisibilityOwners=Set("
            "frameDrivenEffectVisibilityOwners.map{"
            "SceneEffectStageCompileInput.DynamicEffectVisibilityOwner(",
            normalized,
        )
        self.assertIn(
            "frameDrivenEffectVisibilityOwners:"
            "stageCompileEffectVisibilityOwners",
            normalized,
        )
        self.assertIn(
            "activeEffectLocalDirectBoolVisibilityTargets:"
            "activeEffectLocalDirectBoolVisibilityTargets",
            normalized,
        )

    def test_controlled_stock_identity_partition_reaches_product_compiler(
        self,
    ) -> None:
        self.assertTrue(self.result["plannerStaticAccepted"])
        self.assertEqual(self.result["productStaticOutcome"], "rejected")
        self.assertEqual(
            self.result["productStaticDetail"],
            "current-stock-scalar-owner-revoked-to-material-program",
        )

    def test_startup_inactive_requires_the_exact_direct_bool_route(self) -> None:
        self.assertEqual(self.result["productStartupOutcome"], "rejected")
        self.assertEqual(
            self.result["productStartupDetail"],
            "startup-inactive-direct-bool-current-stock-scalar-"
            "owner-revoked-to-material-program",
        )
        self.assertEqual(
            self.result["productStartupEnvelope"],
            "x-ray:compatibility:dedicated-profile-rejected",
        )
        self.assertEqual(self.result["productStartupNearMisses"], ["accepted"] * 8)


if __name__ == "__main__":
    unittest.main()
