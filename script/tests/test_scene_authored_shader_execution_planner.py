#!/usr/bin/env python3

from __future__ import annotations

import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import textwrap
import unittest


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
SCENE_ROOT = REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene"
sys.path.insert(0, str(REPOSITORY_ROOT / "script"))

from scene_real_test_fixtures import sample_cache_root


SWIFT_SOURCES = [
    SCENE_ROOT / "Format/SceneJSONValue.swift",
    SCENE_ROOT / "RenderGraph/SceneAuthoredEffectRenderPlan.swift",
    SCENE_ROOT / "RenderGraph/SceneAuthoredMaterialResolver.swift",
    SCENE_ROOT / "RenderGraph/SceneShaderContract.swift",
    SCENE_ROOT / "RenderGraph/SceneShaderContractLoader.swift",
    SCENE_ROOT / "RenderGraph/SceneAuthoredShaderFrontendModel.swift",
    SCENE_ROOT / "RenderGraph/SceneAuthoredShaderLexer.swift",
    SCENE_ROOT / "RenderGraph/SceneAuthoredShaderLoopAnalyzer.swift",
    SCENE_ROOT / "RenderGraph/SceneAuthoredShaderSyntax.swift",
    SCENE_ROOT / "RenderGraph/SceneAuthoredShaderMetalSource.swift",
    SCENE_ROOT / "RenderGraph/SceneAuthoredShaderMetalEmitter.swift",
    SCENE_ROOT / "RenderGraph/SceneAuthoredShaderFrontend.swift",
    SCENE_ROOT / "RenderGraph/SceneAuthoredShaderExecutionPlan.swift",
    SCENE_ROOT / "RenderGraph/SceneAuthoredShaderUniformBinder.swift",
    SCENE_ROOT / "RenderGraph/SceneAuthoredShaderExecutionPlanner.swift",
]


HARNESS = r'''
import Foundation

struct SceneDocument {
    struct ShaderValue {
        let userBinding: String?
        let components: [Double]?
        let timeline: String?
        let timelineDiagnostics: [String]
    }
}

struct SceneEffectTextureInput { let name: String }

struct SceneRenderDescriptor {
    struct EffectDescriptor {
        struct PassDescriptor {
            let passIndex: Int
            let textureSlots: [String?]
            let userTextureInputs: [SceneEffectTextureInput?]
            let combos: [String: Int]
            let constantShaderValues: [String: SceneDocument.ShaderValue]
        }
        let id: String
        let visible: Bool?
        let passes: [PassDescriptor]
    }

    struct Layer {
        let id: Int
        let contentKind: String
        let sizeWH: [Float]?
        let effects: [EffectDescriptor]
    }

    struct MaterialPassDescriptor {
        let id: String
        let materialPath: String
        let shaderPath: String?
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
    let materialPasses: [MaterialPassDescriptor]
}

@main
enum Harness {
    typealias Graph = SceneAuthoredEffectRenderPlan
    static let layerID = 20
    static let descriptorID = "20#effect#0"
    static let materialPath = "materials/effects/test.json"
    static let materialPassID = "materials/effects/test.json#0"

    struct Options {
        var contentKind = "solid"
        var size: [Float]? = [128, 128]
        var visible: Bool? = true
        var externalTexture = false
        var combo = false
        var userBinding = false
        var userShaderValue = false
        var alphaWriting = false
        var blending = "normal"
    }

    static func value(_ component: Double, bound: Bool = false) -> SceneDocument.ShaderValue {
        .init(
            userBinding: bound ? "property" : nil,
            components: [component],
            timeline: nil,
            timelineDiagnostics: []
        )
    }

    static func descriptor(
        identity: String,
        options: Options = .init()
    ) -> SceneRenderDescriptor {
        let textureSlots: [String?] = options.externalTexture ? ["external.png"] : []
        let constants = identity == "effects/generic"
            ? ["g_Strength": value(0.75, bound: options.userBinding)]
            : [:]
        let pass = SceneRenderDescriptor.EffectDescriptor.PassDescriptor(
            passIndex: 0,
            textureSlots: textureSlots,
            userTextureInputs: [],
            combos: options.combo ? ["OPTION": 1] : [:],
            constantShaderValues: constants
        )
        let effect = SceneRenderDescriptor.EffectDescriptor(
            id: descriptorID,
            visible: options.visible,
            passes: [pass]
        )
        let material = SceneRenderDescriptor.MaterialPassDescriptor(
            id: materialPassID,
            materialPath: materialPath,
            shaderPath: identity,
            textureSlots: [],
            userTextureInputs: [],
            combos: [:],
            constantShaderValues: [:],
            userShaderValues: options.userShaderValue ? ["g_Strength": "property"] : [:],
            blending: options.blending,
            depthTest: "disabled",
            depthWrite: "disabled",
            cullMode: "nocull",
            alphaWriting: options.alphaWriting ? "enabled" : nil
        )
        return .init(
            layers: [.init(
                id: layerID,
                contentKind: options.contentKind,
                sizeWH: options.size,
                effects: [effect]
            )],
            materialPasses: [material]
        )
    }

    static func graph(priorInput: Bool = false, blocker: Bool = false) -> Graph {
        let key = Graph.EffectKey(
            layerID: layerID,
            effectIndex: 0,
            descriptorID: descriptorID
        )
        let priorKey = Graph.EffectKey(
            layerID: layerID,
            effectIndex: 0,
            descriptorID: "prior"
        )
        let input = Graph.TextureIdentity(
            kind: priorInput ? .effectOutput : .layerSource,
            layerID: layerID,
            effect: priorInput ? priorKey : nil,
            name: nil
        )
        let output = Graph.TextureIdentity(
            kind: .effectOutput,
            layerID: layerID,
            effect: key,
            name: nil
        )
        return .init(
            layerID: layerID,
            effects: [.init(
                key: key,
                definitionPath: "effects/test/effect.json",
                input: input,
                output: output,
                nodeIndices: [0]
            )],
            renderTargets: [],
            nodes: [.init(
                nodeIndex: 0,
                effect: key,
                definitionPassIndex: 0,
                materialOrdinal: 0,
                instancePassIndex: 0,
                kind: .material,
                materialPath: materialPath,
                materialPassID: materialPassID,
                target: output,
                bindings: [],
                commandSource: nil,
                commandTarget: nil,
                compose: nil,
                conditions: nil
            )],
            finalOutput: output,
            blockers: blocker ? [.init(
                effect: key,
                definitionPassIndex: 0,
                reason: .unsupportedCondition,
                detail: "fixture"
            )] : []
        )
    }

    static func contracts(_ identity: String, root: URL) -> [SceneShaderContract] {
        SceneShaderContractLoader().load(shaderReferences: [identity], rootURL: root)
    }

    static func plan(
        identity: String,
        root: URL,
        options: Options = .init(),
        priorInput: Bool = false,
        role: SceneAuthoredEffectInputRole = .layerSource,
        blocker: Bool = false
    ) -> SceneAuthoredShaderExecutionPlan? {
        SceneAuthoredShaderExecutionPlanner.plan(
            graph: graph(priorInput: priorInput, blocker: blocker),
            descriptor: descriptor(identity: identity, options: options),
            shaderContracts: contracts(identity, root: root),
            inputRole: role
        )
    }

    static func main() throws {
        let realRoot = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let syntheticRoot = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
        let generic = plan(identity: "effects/generic", root: syntheticRoot)
        let real = plan(identity: "effects/myfirstshader", root: realRoot)

        var external = Options(); external.externalTexture = true
        var combo = Options(); combo.combo = true
        var bound = Options(); bound.userBinding = true
        var userShader = Options(); userShader.userShaderValue = true
        var alphaWriting = Options(); alphaWriting.alphaWriting = true
        var blending = Options(); blending.blending = "additive"
        var missingSize = Options(); missingSize.size = nil
        var video = Options(); video.contentKind = "video"

        let rejectedOptions = [
            external, combo, bound, userShader, alphaWriting, blending, missingSize, video,
        ]
        let result: [String: Bool] = [
            "genericAccepted": generic != nil,
            "genericContractPreserved": generic.map {
                $0.framebufferTextureSlots == [0]
                    && $0.mappedSize == CGSize(width: 128, height: 128)
                    && $0.uniformBindings.contains { $0.field.name == "g_Strength" }
                    && $0.uniformBindings.contains { $0.field.name == "g_Daytime" }
                    && $0.uniformBindings.contains { $0.field.name == "g_Frametime" }
                    && $0.uniformBindings.contains { $0.field.name == "g_PointerPositionLast" }
                    && $0.uniformBindings.contains { $0.field.name == "g_Screen" }
            } ?? false,
            "realAccepted": real != nil,
            "realContractPreserved": real.map {
                $0.framebufferTextureSlots == [0]
                    && $0.mappedSize == CGSize(width: 128, height: 128)
                    && $0.offscreenSize != nil
                    && $0.uniformBindings.contains { $0.field.name == "g_Time" }
                    && $0.uniformBindings.contains { $0.field.name == "g_Texture0Resolution" }
            } ?? false,
            "priorAccepted": plan(
                identity: "effects/generic",
                root: syntheticRoot,
                priorInput: true,
                role: .priorEffectOutput
            ) != nil,
            "wrongRoleRejected": plan(
                identity: "effects/generic",
                root: syntheticRoot,
                priorInput: true,
                role: .layerSource
            ) == nil,
            "unsupportedContractsRejected": ["noannotation", "unknown", "included"].allSatisfy {
                plan(identity: "effects/\($0)", root: syntheticRoot) == nil
            },
            "unsupportedMaterialRejected": rejectedOptions.allSatisfy {
                plan(identity: "effects/generic", root: syntheticRoot, options: $0) == nil
            },
            "blockedGraphRejected": plan(
                identity: "effects/generic",
                root: syntheticRoot,
                blocker: true
            ) == nil,
        ]
        let data = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }
}
'''


VERTEX_SOURCE = r'''
uniform mat4 g_ModelViewProjectionMatrix;
attribute vec3 a_Position;
attribute vec2 a_TexCoord;
varying vec2 v_TexCoord;
void main() {
    gl_Position = mul(vec4(a_Position, 1.0), g_ModelViewProjectionMatrix);
    v_TexCoord = a_TexCoord;
}
'''


def fragment_source(*, annotation: bool = True, unknown: bool = False) -> str:
    sampler_annotation = (
        ' // {"material":"framebuffer","hidden":true}' if annotation else ""
    )
    extra_uniform = "uniform float g_Unsupported;" if unknown else ""
    return f'''
uniform sampler2D g_Texture0;{sampler_annotation}
uniform float g_Strength;
uniform float g_Daytime;
uniform float g_Frametime;
uniform vec2 g_PointerPositionLast;
uniform vec3 g_Screen;
{extra_uniform}
varying vec2 v_TexCoord;
void main() {{
    vec4 color = texture2D(g_Texture0, v_TexCoord);
    gl_FragColor = vec4(color.rgb * g_Strength, color.a);
}}
'''


class SceneAuthoredShaderExecutionPlannerTests(unittest.TestCase):
    def test_generic_and_real_contracts_share_bounded_admission(self) -> None:
        if shutil.which("swiftc") is None:
            self.skipTest("swiftc is unavailable")
        real_root = sample_cache_root("3141421197")
        if not (real_root / "shaders/effects/myfirstshader.frag").is_file():
            self.skipTest("isolated 3141421197 shader fixture is unavailable")

        with tempfile.TemporaryDirectory(prefix="mwx-authored-shader-planner-") as directory:
            root = Path(directory)
            synthetic_root = root / "synthetic"
            shader_root = synthetic_root / "shaders/effects"
            shader_root.mkdir(parents=True)
            for identity, source in {
                "generic": fragment_source(),
                "noannotation": fragment_source(annotation=False),
                "unknown": fragment_source(unknown=True),
                "included": '#include "shared.inc"\n' + fragment_source(),
            }.items():
                (shader_root / f"{identity}.vert").write_text(
                    textwrap.dedent(VERTEX_SOURCE), encoding="utf-8"
                )
                (shader_root / f"{identity}.frag").write_text(
                    textwrap.dedent(source), encoding="utf-8"
                )

            harness = root / "Harness.swift"
            harness.write_text(HARNESS, encoding="utf-8")
            binary = root / "authored-shader-planner"
            environment = os.environ.copy()
            environment["CLANG_MODULE_CACHE_PATH"] = str(root / "clang-module-cache")
            environment["SWIFT_MODULECACHE_PATH"] = str(root / "swift-module-cache")
            compilation = subprocess.run(
                [
                    "xcrun", "--sdk", "macosx", "swiftc", "-parse-as-library",
                    *(str(path) for path in SWIFT_SOURCES),
                    str(harness), "-o", str(binary),
                ],
                cwd=REPOSITORY_ROOT,
                env=environment,
                capture_output=True,
                text=True,
            )
            self.assertEqual(compilation.returncode, 0, compilation.stderr)
            completed = subprocess.run(
                [str(binary), str(real_root), str(synthetic_root)],
                cwd=REPOSITORY_ROOT,
                check=True,
                capture_output=True,
                text=True,
            )

        result = json.loads(completed.stdout)
        self.assertTrue(all(result.values()), result)


if __name__ == "__main__":
    unittest.main()
