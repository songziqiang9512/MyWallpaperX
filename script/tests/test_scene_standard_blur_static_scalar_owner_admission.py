#!/usr/bin/env python3
"""Executable whole-stage owner proof for Standard Blur static scalar input."""

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
BLUR_STOCK_ROOT = STOCK_ROOT / "effects/blur"
SUPPORT_SOURCE = Path(__file__).with_name("fixtures") / (
    "SceneStandardBlurStaticScalarOwnerAdmissionSupport.swift"
)
DEDICATED_COMPILERS_SOURCE = SCENE_ROOT / (
    "RenderGraph/EffectCompilation/SceneEffectStageDedicatedCompilers.swift"
)
FINALIZER_FIXTURE = runpy.run_path(
    str(
        REPOSITORY_ROOT
        / "script/tests/test_scene_resolved_material_program_finalizer.py"
    )
)


def unique_sources(paths: list[Path]) -> list[Path]:
    return list(dict.fromkeys(paths))


SWIFT_SOURCES = unique_sources([
    *FINALIZER_FIXTURE["SWIFT_SOURCES"],
    SCENE_ROOT / "Format/SceneDocument+ShaderValue.swift",
    SCENE_ROOT / "RenderGraph/SceneEffectTextureInput.swift",
    SCENE_ROOT / "RenderGraph/SceneAuthoredMaterialResolver.swift",
    SCENE_ROOT
    / "RenderGraph/MaterialProgram/SceneResolvedMaterialScriptBindingClassifier.swift",
    SCENE_ROOT
    / "RenderGraph/MaterialProgram/SceneResolvedMaterialTemplateCompiler.swift",
    SCENE_ROOT
    / "RenderGraph/EffectCompilation/SceneEffectStageCompileModel.swift",
    SCENE_ROOT
    / "RenderGraph/EffectCompilation/SceneEffectStageExecutionPlan.swift",
    SCENE_ROOT / "RenderGraph/SceneAuthoredStandardBlurPlanner.swift",
    SCENE_ROOT
    / "RenderGraph/SceneResolvedMaterialUnitPreviousBlurredCompositeGraphAdmission.swift",
    SCENE_ROOT
    / "RenderGraph/SceneResolvedMaterialUnitPreviousBlurredCompositeOwnerAdmission.swift",
    SCENE_ROOT / "Resources/SceneResourceIndex.swift",
    SCENE_ROOT / "Resources/SceneResourceView.swift",
    SCENE_ROOT / "Resources/SceneShaderSourceResolver.swift",
    SCENE_ROOT / "Resources/SceneShaderSourceGraphBuilder.swift",
    SCENE_ROOT
    / "RenderGraph/ShaderContract/SceneShaderContractLoader.swift",
    SCENE_ROOT
    / "RenderGraph/ShaderContract/SceneShaderContractLoader+SourceGraph.swift",
])


HARNESS = r'''
import Foundation

private typealias Graph = SceneAuthoredEffectRenderPlan

private let layerID = 530
private let effectKey = Graph.EffectKey(
    layerID: layerID,
    effectIndex: 0,
    descriptorID: "530#effect#0"
)

private func texture(
    _ kind: Graph.TextureKind,
    effect: Graph.EffectKey? = nil,
    name: String? = nil
) -> Graph.TextureIdentity {
    .init(kind: kind, layerID: layerID, effect: effect, name: name)
}

private let source = texture(.layerSource)
private let output = texture(.effectOutput, effect: effectKey)
private let quarterA = texture(
    .framebuffer,
    effect: effectKey,
    name: "_rt_QuarterCompoBuffer1"
)
private let quarterB = texture(
    .framebuffer,
    effect: effectKey,
    name: "_rt_QuarterCompoBuffer2"
)

private func binding(
    slot: Int,
    name: String,
    texture: Graph.TextureIdentity
) -> Graph.Binding {
    .init(
        slot: slot,
        authoredName: name,
        texture: texture,
        conditions: nil
    )
}

private func graph() -> Graph {
    let materialPaths = [
        "materials/effects/blur_downsample4.json",
        "materials/effects/blur_gaussian_x.json",
        "materials/effects/blur_gaussian_y.json",
        "materials/effects/blur_combine.json",
    ]
    let targets = [quarterA, quarterB, quarterA, output]
    let bindings: [[Graph.Binding]] = [
        [binding(slot: 0, name: "previous", texture: source)],
        [binding(
            slot: 0,
            name: "_rt_QuarterCompoBuffer1",
            texture: quarterA
        )],
        [binding(
            slot: 0,
            name: "_rt_QuarterCompoBuffer2",
            texture: quarterB
        )],
        [
            binding(
                slot: 0,
                name: "_rt_QuarterCompoBuffer1",
                texture: quarterA
            ),
            binding(slot: 2, name: "previous", texture: source),
        ],
    ]
    let nodes = materialPaths.indices.map { ordinal in
        Graph.Node(
            nodeIndex: ordinal,
            effect: effectKey,
            definitionPassIndex: ordinal,
            materialOrdinal: ordinal,
            instancePassIndex: ordinal,
            kind: .material,
            materialPath: materialPaths[ordinal],
            materialPassID: "\(materialPaths[ordinal])#0",
            target: targets[ordinal],
            bindings: bindings[ordinal],
            commandSource: nil,
            commandTarget: nil,
            compose: nil,
            conditions: nil
        )
    }
    return .init(
        layerID: layerID,
        effects: [.init(
            key: effectKey,
            definitionPath: "effects/blur/effect.json",
            input: source,
            output: output,
            nodeIndices: nodes.map(\.nodeIndex)
        )],
        renderTargets: [quarterA, quarterB].map {
            .init(
                texture: $0,
                extent: .init(kind: .scale, first: 4, second: nil),
                format: "rgba_backbuffer",
                declaredUnique: false,
                clear: nil,
                uvs: nil,
                conditions: nil
            )
        },
        nodes: nodes,
        finalOutput: output,
        blockers: []
    )
}

private func scalar(
    raw: String = "0.19",
    kind: String
) -> SceneDocument.ShaderValue {
    .init(
        rawValue: raw,
        valueKind: kind,
        userBinding: nil,
        components: [0.19]
    )
}

private func vector(_ x: Double, _ y: Double) -> SceneDocument.ShaderValue {
    .init(
        rawValue: "\(x) \(y)",
        valueKind: "vector",
        userBinding: nil,
        components: [x, y]
    )
}

private func timelineScalar() -> SceneDocument.ShaderValue {
    .init(
        rawValue: "0.19",
        valueKind: "binding",
        userBinding: nil,
        components: [0.19],
        timeline: .init(),
        bindingKeys: ["animation", "value"]
    )
}

private func sceneScriptScalar() -> SceneDocument.ShaderValue {
    .init(
        rawValue: "0.19",
        valueKind: "binding",
        userBinding: nil,
        components: [0.19],
        scriptSource: "return 0.19;",
        bindingKeys: ["script", "value"]
    )
}

private func userScalar() -> SceneDocument.ShaderValue {
    .init(
        rawValue: "0.19 0.19",
        valueKind: "binding",
        userBinding: "blurScale",
        userValueKind: .string,
        components: [0.19, 0.19],
        bindingKeys: ["user", "value"]
    )
}

private func pass(
    _ passIndex: Int,
    scale: SceneDocument.ShaderValue? = nil,
    combos: [String: Int] = [:]
) -> SceneRenderDescriptor.EffectDescriptor.PassDescriptor {
    .init(
        passIndex: passIndex,
        texturePaths: [],
        textureSlots: [],
        userTextureInputs: [],
        combos: combos,
        constantShaderValues: scale.map { ["scale": $0] } ?? [:]
    )
}

private func material(
    name: String,
    shader: String,
    passIndex: Int,
    combos: [String: Int] = [:]
) -> SceneRenderDescriptor.MaterialPassDescriptor {
    let path = "materials/effects/\(name).json"
    return .init(
        id: "\(path)#0",
        materialPath: path,
        passIndex: passIndex,
        shaderPath: shader,
        texturePaths: [],
        textureSlots: [],
        userTextureInputs: [],
        combos: combos,
        constantShaderValues: [:],
        userShaderValues: [:],
        blending: "normal",
        depthTest: "disabled",
        depthWrite: "disabled",
        cullMode: "nocull",
        alphaWriting: nil
    )
}

private func descriptor(
    horizontal: SceneDocument.ShaderValue,
    vertical: SceneDocument.ShaderValue? = nil
) -> SceneRenderDescriptor {
    let verticalScale = vertical ?? horizontal
    return .init(
        layers: [.init(
            id: layerID,
            contentKind: "image",
            effects: [.init(
                id: effectKey.descriptorID,
                file: "effects/blur/effect.json",
                visible: true,
                passes: [
                    pass(0),
                    pass(1, scale: horizontal),
                    pass(2, scale: verticalScale, combos: ["VERTICAL": 1]),
                    pass(3),
                ]
            )]
        )],
        materialPasses: [
            material(
                name: "blur_downsample4",
                shader: "effects/blur_downsample4",
                passIndex: 0
            ),
            material(
                name: "blur_gaussian_x",
                shader: "effects/blur_gaussian",
                passIndex: 0
            ),
            material(
                name: "blur_gaussian_y",
                shader: "effects/blur_gaussian",
                passIndex: 0,
                combos: ["VERTICAL": 1]
            ),
            material(
                name: "blur_combine",
                shader: "effects/blur_combine",
                passIndex: 0
            ),
        ]
    )
}

private func contracts(_ root: URL) -> [SceneShaderContract] {
    let values = SceneShaderContractLoader().load(
        shaderReferences: [
            "effects/blur_downsample4",
            "effects/blur_gaussian",
            "effects/blur_combine",
        ],
        rootURL: root
    )
    precondition(values.count == 3)
    return values
}

private func producers() -> Set<SceneDynamicUserPropertyProducer> {
    Set([1, 2].map { passIndex in
        SceneDynamicUserPropertyProducer(
            propertyKey: "blurScale",
            target: .effectConstant(
                layerID: layerID,
                effectIndex: 0,
                passIndex: passIndex,
                name: "scale"
            ),
            valueType: .scalar
        )
    })
}

private func admits(
    root: URL,
    horizontal: SceneDocument.ShaderValue,
    vertical: SceneDocument.ShaderValue? = nil,
    userPropertyProducers: Set<SceneDynamicUserPropertyProducer> = []
) -> Bool {
    SceneResolvedMaterialUnitPreviousBlurredCompositeOwnerAdmission
        .acceptsDedicatedRevocation(
            key: .init(effect: effectKey, nodeIndex: 3),
            graph: graph(),
            descriptor: descriptor(
                horizontal: horizontal,
                vertical: vertical
            ),
            inputRole: .layerSource,
            shaderContracts: contracts(root),
            userPropertyProducers: userPropertyProducers
        )
}

private func productCompileOutcome(
    root: URL,
    horizontal: SceneDocument.ShaderValue,
    vertical: SceneDocument.ShaderValue? = nil
) -> String {
    let input = SceneEffectStageCompileInput(
        stageGraph: graph(),
        inputRole: .layerSource,
        descriptor: descriptor(horizontal: horizontal, vertical: vertical),
        shaderContracts: contracts(root)
    )
    switch SceneAuthoredStandardBlurPlanner.compile(input) {
    case .notApplicable: return "not-applicable"
    case .accepted: return "accepted"
    case let .rejected(failure):
        return ["rejected", failure.code.rawValue, failure.details.first ?? ""]
            .joined(separator: ":")
    }
}

@main
enum Harness {
    static func main() throws {
        let roots = CommandLine.arguments.dropFirst().map {
            URL(fileURLWithPath: $0, isDirectory: true)
        }
        precondition(roots.count == 10)
        let stock = roots[0]
        let malformed = scalar(raw: "0.19 trailing", kind: "string")
        let user = userScalar()
        var result: [String: Any] = [
            "stringScalar": admits(
                root: stock,
                horizontal: scalar(kind: "string")
            ),
            "numberScalar": admits(
                root: stock,
                horizontal: scalar(kind: "number")
            ),
            "oldPlannerStringScalar": SceneAuthoredStandardBlurPlanner.plan(
                graph: graph(),
                descriptor: descriptor(horizontal: scalar(kind: "string")),
                inputRole: .layerSource
            ) != nil,
            "productStringScalar": productCompileOutcome(
                root: stock,
                horizontal: scalar(kind: "string")
            ),
            "malformedHorizontal": admits(
                root: stock,
                horizontal: malformed,
                vertical: scalar(kind: "string")
            ),
            "malformedVertical": admits(
                root: stock,
                horizontal: scalar(kind: "string"),
                vertical: malformed
            ),
            "productMalformedHorizontal": productCompileOutcome(
                root: stock,
                horizontal: malformed,
                vertical: scalar(kind: "string")
            ),
            "productMalformedVertical": productCompileOutcome(
                root: stock,
                horizontal: scalar(kind: "string"),
                vertical: malformed
            ),
            "mismatchedScalarValues": admits(
                root: stock,
                horizontal: scalar(kind: "string"),
                vertical: .init(
                    rawValue: "0.31",
                    valueKind: "string",
                    userBinding: nil,
                    components: [0.31]
                )
            ),
            "scalarHorizontalVectorVertical": admits(
                root: stock,
                horizontal: scalar(kind: "string"),
                vertical: vector(0.19, 0.19)
            ),
            "vectorHorizontalScalarVertical": admits(
                root: stock,
                horizontal: vector(0.19, 0.19),
                vertical: scalar(kind: "string")
            ),
            "equalFloat2": admits(
                root: stock,
                horizontal: vector(0.19, 0.19)
            ),
            "unequalFloat2": admits(
                root: stock,
                horizontal: vector(0.19, 0.31)
            ),
            "timelineScalar": admits(
                root: stock,
                horizontal: timelineScalar()
            ),
            "sceneScriptScalar": admits(
                root: stock,
                horizontal: sceneScriptScalar()
            ),
            "userWithoutProducers": admits(
                root: stock,
                horizontal: user
            ),
            "userWithSoleProducers": admits(
                root: stock,
                horizontal: user,
                userPropertyProducers: producers()
            ),
            "conditionalStock": admits(
                root: roots[1],
                horizontal: scalar(kind: "string")
            ),
        ]
        let consumerFailureKeys = [
            "unequalDefaultHorizontal", "unequalDefaultVertical",
            "missingDefaultHorizontal", "missingDefaultVertical",
            "float3ABIHorizontal", "float3ABIVertical",
            "arrayABIHorizontal", "arrayABIVertical",
        ]
        for (key, root) in zip(consumerFailureKeys, roots.dropFirst(2)) {
            result[key] = admits(
                root: root,
                horizontal: scalar(kind: "string")
            )
            result["product\(key)"] = productCompileOutcome(
                root: root,
                horizontal: scalar(kind: "string")
            )
        }
        let data = try JSONSerialization.data(
            withJSONObject: result,
            options: [.sortedKeys]
        )
        print(String(decoding: data, as: UTF8.self))
    }
}
'''


SHADER_FILES = (
    "blur_downsample4.vert",
    "blur_downsample4.frag",
    "blur_gaussian.vert",
    "blur_gaussian.frag",
    "blur_combine.vert",
    "blur_combine.frag",
)
COMMON_FILES = ("common.h", "common_blending.h", "common_composite.h")
STOCK_SCALE_UNIFORM = (
    'uniform vec2 g_Scale; // {"material":"scale",'
    '"label":"ui_editor_properties_scale","default":"1 1",'
    '"linked":true,"range":[0.01, 2.0]}'
)


def replace_once(path: Path, old: str, new: str) -> None:
    source = path.read_text(encoding="utf-8")
    if source.count(old) != 1:
        raise AssertionError(f"expected one {old!r} in {path}")
    path.write_text(source.replace(old, new), encoding="utf-8")


def isolate_consumer_failure(path: Path, bad: str, vertical: bool) -> None:
    horizontal_uniform = STOCK_SCALE_UNIFORM if vertical else bad
    vertical_uniform = bad if vertical else STOCK_SCALE_UNIFORM
    replace_once(
        path,
        STOCK_SCALE_UNIFORM,
        "\n".join((
            "#if VERTICAL",
            vertical_uniform,
            "#else",
            horizontal_uniform,
            "#endif",
        )),
    )


@unittest.skipUnless(shutil.which("swiftc"), "swiftc is required")
class SceneStandardBlurStaticScalarOwnerAdmissionTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.temporary_directory = tempfile.TemporaryDirectory(
            prefix="mwx-standard-blur-static-scalar-owner-"
        )
        root = Path(cls.temporary_directory.name)
        harness = root / "Harness.swift"
        harness.write_text(HARNESS, encoding="utf-8")

        bad_uniforms = {
            "unequal-default": STOCK_SCALE_UNIFORM.replace(
                '"default":"1 1"', '"default":"1 0.5"'
            ),
            "missing-default": STOCK_SCALE_UNIFORM.replace(
                '"default":"1 1",', ""
            ),
            "float3-abi": STOCK_SCALE_UNIFORM.replace(
                "uniform vec2", "uniform vec3"
            ).replace('"default":"1 1"', '"default":"1 1 1"'),
            "array-abi": STOCK_SCALE_UNIFORM.replace(
                "uniform vec2 g_Scale;", "uniform vec2 g_Scale[1];"
            ),
        }
        failure_specs = [
            (f"{name}-{axis}", uniform, axis == "vertical")
            for name, uniform in bad_uniforms.items()
            for axis in ("horizontal", "vertical")
        ]
        cls.roots = [root / "stock", root / "conditional-stock", *(
            root / name for name, _, _ in failure_specs
        )]
        for fixture in cls.roots:
            (fixture / "shaders/effects").mkdir(parents=True)
            for name in SHADER_FILES:
                shutil.copy2(
                    BLUR_STOCK_ROOT / "shaders/effects" / name,
                    fixture / "shaders/effects" / name,
                )
            for name in COMMON_FILES:
                shutil.copy2(
                    STOCK_ROOT / "shaders" / name,
                    fixture / "shaders" / name,
                )

        isolate_consumer_failure(
            cls.roots[1] / "shaders/effects/blur_gaussian.vert",
            STOCK_SCALE_UNIFORM,
            False,
        )
        for fixture, (_, bad, vertical) in zip(
            cls.roots[2:], failure_specs
        ):
            isolate_consumer_failure(
                fixture / "shaders/effects/blur_gaussian.vert",
                bad,
                vertical,
            )

        binary = root / "standard-blur-static-scalar-owner"
        product_compiler = root / "ProductStandardBlurCompiler.swift"
        source = DEDICATED_COMPILERS_SOURCE.read_text(encoding="utf-8")
        product_compiler.write_text(source[
            source.index("extension SceneAuthoredStandardBlurPlanner"):
            source.index("extension SceneAuthoredXRayPlanner")
        ], encoding="utf-8")
        environment = os.environ.copy()
        environment["CLANG_MODULE_CACHE_PATH"] = str(root / "clang-cache")
        environment["SWIFT_MODULECACHE_PATH"] = str(root / "swift-cache")
        compilation = subprocess.run(
            [
                "xcrun",
                "--sdk",
                "macosx",
                "swiftc",
                "-parse-as-library",
                str(SUPPORT_SOURCE),
                *(str(path) for path in SWIFT_SOURCES),
                str(product_compiler),
                str(harness),
                "-framework",
                "Metal",
                "-framework",
                "CoreGraphics",
                "-framework",
                "ImageIO",
                "-module-cache-path",
                str(root / "module-cache"),
                "-o",
                str(binary),
            ],
            cwd=REPOSITORY_ROOT,
            env=environment,
            capture_output=True,
            text=True,
        )
        if compilation.returncode != 0:
            raise RuntimeError(compilation.stderr)
        completed = subprocess.run(
            [str(binary), *(str(path) for path in cls.roots)],
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

    def test_string_and_number_scalars_revoke_the_incumbent(self) -> None:
        self.assertTrue(self.result["stringScalar"])
        self.assertTrue(self.result["numberScalar"])
        self.assertTrue(self.result["oldPlannerStringScalar"])
        self.assertEqual(
            self.result["productStringScalar"],
            "rejected:dedicated-profile-rejected:"
            "static-scalar-owner-revoked-to-material-program",
        )

    def test_scalar_projection_requires_exact_authored_token_provenance(self) -> None:
        self.assertFalse(self.result["malformedHorizontal"])
        self.assertFalse(self.result["malformedVertical"])
        self.assertFalse(self.result["mismatchedScalarValues"])
        self.assertFalse(self.result["scalarHorizontalVectorVertical"])
        self.assertFalse(self.result["vectorHorizontalScalarVertical"])
        self.assertEqual(self.result["productMalformedHorizontal"], "accepted")
        self.assertEqual(self.result["productMalformedVertical"], "accepted")

    def test_each_unproven_float2_consumer_contract_retains_the_incumbent(
        self,
    ) -> None:
        self.assertTrue(self.result["conditionalStock"])
        for failure in ("unequalDefault", "missingDefault", "float3ABI", "arrayABI"):
            for consumer in ("Horizontal", "Vertical"):
                key = failure + consumer
                with self.subTest(key=key):
                    self.assertFalse(self.result[key])
                    self.assertEqual(self.result["product" + key], "accepted")

    def test_existing_static_float2_values_still_revoke_the_incumbent(self) -> None:
        self.assertTrue(self.result["equalFloat2"])
        self.assertTrue(self.result["unequalFloat2"])

    def test_dynamic_shapes_do_not_enter_through_the_static_cohort(self) -> None:
        self.assertFalse(self.result["timelineScalar"])
        self.assertFalse(self.result["sceneScriptScalar"])
        self.assertFalse(self.result["userWithoutProducers"])
        self.assertTrue(self.result["userWithSoleProducers"])


if __name__ == "__main__":
    unittest.main()
