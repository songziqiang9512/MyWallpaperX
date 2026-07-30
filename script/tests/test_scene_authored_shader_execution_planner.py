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
    SCENE_ROOT / "RenderGraph/SceneMaterialRenderState.swift",
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
    SCENE_ROOT / "RenderGraph/SceneAuthoredShaderPipelineCache.swift",
    SCENE_ROOT / "RenderGraph/SceneAuthoredShaderRenderer.swift",
]


HARNESS = r'''
import Foundation
import Metal
import simd

final class Counter {
    private let lock = NSLock()
    private var value = 0

    func increment() {
        lock.lock()
        value += 1
        lock.unlock()
    }

    func read() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}

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
        var alphaWriting: String?
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
            alphaWriting: options.alphaWriting
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

    static func render(
        _ plan: SceneAuthoredShaderExecutionPlan,
        dimension: Int,
        device: MTLDevice
    ) -> [String: Any]? {
        guard dimension > 0,
              let queue = device.makeCommandQueue(),
              let pipelineCache = SceneAuthoredShaderPipelineCache(device: device) else {
            return nil
        }
        let sourceDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: dimension,
            height: dimension,
            mipmapped: false
        )
        sourceDescriptor.storageMode = .shared
        sourceDescriptor.usage = [.shaderRead, .renderTarget]
        let targetDescriptor = sourceDescriptor.copy() as! MTLTextureDescriptor
        guard let source = device.makeTexture(descriptor: sourceDescriptor),
              let target = device.makeTexture(descriptor: targetDescriptor),
              let commandBuffer = queue.makeCommandBuffer() else {
            return nil
        }
        let inputBytes = [UInt8](
            repeating: 255,
            count: dimension * dimension * 4
        )
        inputBytes.withUnsafeBytes { bytes in
            guard let baseAddress = bytes.baseAddress else { return }
            source.replace(
                region: MTLRegionMake2D(0, 0, dimension, dimension),
                mipmapLevel: 0,
                withBytes: baseAddress,
                bytesPerRow: dimension * 4
            )
        }
        let size = CGSize(width: dimension, height: dimension)
        let mvp = simd_float4x4(columns: (
            SIMD4(2 / Float(dimension), 0, 0, 0),
            SIMD4(0, 2 / Float(dimension), 0, 0),
            SIMD4(0, 0, 1, 0),
            SIMD4(0, 0, 0, 1)
        ))
        let inputs = SceneAuthoredShaderUniformInputs(
            renderSize: size,
            screenSize: CGSize(width: 1920, height: 1080),
            modelViewProjection: mvp,
            sceneTime: 1,
            dayTime: 0.5,
            frameTime: 1.0 / 60.0,
            pointerCurrentNDC: .zero,
            pointerPreviousNDC: .zero,
            texturePhysicalSizes: Dictionary(
                uniqueKeysWithValues: plan.framebufferTextureSlots.map { ($0, size) }
            )
        )
        guard SceneAuthoredShaderRenderer.encode(
            plan: plan,
            source: source,
            target: target,
            inputs: inputs,
            pipelineCache: pipelineCache,
            commandBuffer: commandBuffer
        ) else {
            return nil
        }
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        guard commandBuffer.status == .completed else { return nil }

        var output = [UInt8](repeating: 0, count: dimension * dimension * 4)
        target.getBytes(
            &output,
            bytesPerRow: dimension * 4,
            from: MTLRegionMake2D(0, 0, dimension, dimension),
            mipmapLevel: 0
        )
        let rgb = output.enumerated().compactMap { index, value in
            index % 4 == 3 ? nil : Int(value)
        }
        return [
            "minimumRGB": rgb.min() ?? 0,
            "maximumRGB": rgb.max() ?? 0,
            "distinctRGB": Set(rgb).count,
            "averageRGB": rgb.reduce(0, +) / max(1, rgb.count),
            "alphaMinimum": output.enumerated().compactMap {
                $0.offset % 4 == 3 ? Int($0.element) : nil
            }.min() ?? 0,
            "compilationAttempts": pipelineCache.compilationAttemptCount,
        ]
    }

    static func failureIsCached(
        _ plan: SceneAuthoredShaderExecutionPlan,
        device: MTLDevice
    ) -> Bool {
        guard let cache = SceneAuthoredShaderPipelineCache(device: device) else {
            return false
        }
        let original = plan.program
        let invalidProgram = SceneAuthoredShaderProgram(
            metalSource: "this is not metal source",
            vertexFunctionName: original.vertexFunctionName,
            fragmentFunctionName: original.fragmentFunctionName,
            uniformLayout: original.uniformLayout,
            textureBindings: original.textureBindings,
            staticLoopWork: original.staticLoopWork
        )
        let invalid = SceneAuthoredShaderExecutionPlan(
            cacheKey: plan.cacheKey,
            program: invalidProgram,
            renderState: plan.renderState,
            mappedSize: plan.mappedSize,
            framebufferTextureSlots: plan.framebufferTextureSlots,
            uniformBindings: plan.uniformBindings
        )
        return cache.pipeline(for: invalid) == nil
            && cache.pipeline(for: invalid) == nil
            && cache.entryCount == 1
            && cache.failedEntryCount == 1
            && cache.compilationAttemptCount == 1
    }

    static func concurrentCacheIsSingleAttempt(
        _ plan: SceneAuthoredShaderExecutionPlan,
        device: MTLDevice
    ) -> Bool {
        guard let cache = SceneAuthoredShaderPipelineCache(device: device) else {
            return false
        }
        let lock = NSLock()
        var states: [ObjectIdentifier] = []
        DispatchQueue.concurrentPerform(iterations: 64) { _ in
            if let pipeline = cache.pipeline(for: plan) {
                lock.lock()
                states.append(ObjectIdentifier(pipeline.state))
                lock.unlock()
            }
        }
        return states.count == 64
            && Set(states).count == 1
            && cache.entryCount == 1
            && cache.failedEntryCount == 0
            && cache.compilationAttemptCount == 1
    }

    static func concurrentFailureIsSingleAttempt(
        _ plan: SceneAuthoredShaderExecutionPlan,
        device: MTLDevice
    ) -> Bool {
        guard let cache = SceneAuthoredShaderPipelineCache(device: device) else {
            return false
        }
        let original = plan.program
        let invalid = SceneAuthoredShaderExecutionPlan(
            cacheKey: plan.cacheKey,
            program: SceneAuthoredShaderProgram(
                metalSource: "this is not metal source",
                vertexFunctionName: original.vertexFunctionName,
                fragmentFunctionName: original.fragmentFunctionName,
                uniformLayout: original.uniformLayout,
                textureBindings: original.textureBindings,
                staticLoopWork: original.staticLoopWork
            ),
            renderState: plan.renderState,
            mappedSize: plan.mappedSize,
            framebufferTextureSlots: plan.framebufferTextureSlots,
            uniformBindings: plan.uniformBindings
        )
        let successes = Counter()
        DispatchQueue.concurrentPerform(iterations: 64) { _ in
            if cache.pipeline(for: invalid) != nil {
                successes.increment()
            }
        }
        return successes.read() == 0
            && cache.entryCount == 1
            && cache.failedEntryCount == 1
            && cache.compilationAttemptCount == 1
    }

    static func unsupportedStateDoesNotAlias(
        _ plan: SceneAuthoredShaderExecutionPlan,
        device: MTLDevice
    ) -> Bool {
        guard let unsupportedState = SceneMaterialRenderState.compile(
                  blending: "additive",
                  depthTest: "disabled",
                  depthWrite: "disabled",
                  cullMode: "nocull",
                  alphaWriting: nil
              ),
              let cache = SceneAuthoredShaderPipelineCache(device: device),
              let supported = cache.pipeline(for: plan) else {
            return false
        }
        let unsupported = SceneAuthoredShaderExecutionPlan(
            cacheKey: plan.cacheKey,
            program: plan.program,
            renderState: unsupportedState,
            mappedSize: plan.mappedSize,
            framebufferTextureSlots: plan.framebufferTextureSlots,
            uniformBindings: plan.uniformBindings
        )
        guard cache.pipeline(for: unsupported) == nil,
              let repeated = cache.pipeline(for: plan) else {
            return false
        }
        return ObjectIdentifier(repeated.state) == ObjectIdentifier(supported.state)
            && cache.entryCount == 2
            && cache.failedEntryCount == 1
            && cache.compilationAttemptCount == 2
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
        var alphaWriting = Options(); alphaWriting.alphaWriting = "enabled"
        var alphaWritingDefault = Options(); alphaWritingDefault.alphaWriting = "default"
        var alphaWritingUnknown = Options(); alphaWritingUnknown.alphaWriting = "unknown"
        var blending = Options(); blending.blending = "additive"
        var translucent = Options(); translucent.blending = "translucent"
        var missingSize = Options(); missingSize.size = nil
        var video = Options(); video.contentKind = "video"

        let rejectedOptions = [
            external, combo, bound, userShader, alphaWriting, alphaWritingDefault,
            alphaWritingUnknown, blending, translucent, missingSize, video,
        ]
        let device = MTLCreateSystemDefaultDevice()
        let genericPixels = generic.flatMap { plan in
            device.flatMap { render(plan, dimension: 4, device: $0) }
        }
        let realPixels = real.flatMap { plan in
            device.flatMap { render(plan, dimension: 32, device: $0) }
        }
        let result: [String: Any] = [
            "genericAccepted": generic != nil,
            "genericContractPreserved": generic.map {
                $0.framebufferTextureSlots == [0]
                    && $0.mappedSize == CGSize(width: 128, height: 128)
                    && $0.uniformBindings.contains { $0.field.name == "g_Strength" }
                    && $0.uniformBindings.contains { $0.field.name == "g_Daytime" }
                    && $0.uniformBindings.contains { $0.field.name == "g_Frametime" }
                    && $0.uniformBindings.contains { $0.field.name == "g_PointerPositionLast" }
                    && $0.uniformBindings.contains { $0.field.name == "g_Screen" }
                    && $0.renderState.matchesFullscreenOverwrite(
                        alphaWriting: .unspecified
                    )
                    && $0.renderState.rawValues.alphaWriting == nil
            } ?? false,
            "realAccepted": real != nil,
            "realContractPreserved": real.map {
                $0.framebufferTextureSlots == [0]
                    && $0.mappedSize == CGSize(width: 128, height: 128)
                    && $0.offscreenSize(for: CGSize(width: 128, height: 128)) != nil
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
            "genericPixels": genericPixels ?? NSNull(),
            "realPixels": realPixels ?? NSNull(),
            "compileFailureCached": generic.map {
                guard let device else { return false }
                return failureIsCached($0, device: device)
            } ?? false,
            "concurrentCacheSingleAttempt": generic.map {
                guard let device else { return false }
                return concurrentCacheIsSingleAttempt($0, device: device)
            } ?? false,
            "concurrentFailureSingleAttempt": generic.map {
                guard let device else { return false }
                return concurrentFailureIsSingleAttempt($0, device: device)
            } ?? false,
            "unsupportedStateDoesNotAlias": generic.map {
                guard let device else { return false }
                return unsupportedStateDoesNotAlias($0, device: device)
            } ?? false,
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
        boolean_contracts = {
            key: value for key, value in result.items()
            if key not in {"genericPixels", "realPixels"}
        }
        self.assertTrue(all(boolean_contracts.values()), result)
        generic_pixels = result["genericPixels"]
        self.assertIsInstance(generic_pixels, dict, result)
        self.assertEqual(generic_pixels["minimumRGB"], 191, result)
        self.assertEqual(generic_pixels["maximumRGB"], 191, result)
        self.assertEqual(generic_pixels["alphaMinimum"], 255, result)
        self.assertEqual(generic_pixels["compilationAttempts"], 1, result)
        real_pixels = result["realPixels"]
        self.assertIsInstance(real_pixels, dict, result)
        self.assertGreater(real_pixels["maximumRGB"], 0, result)
        self.assertGreater(real_pixels["distinctRGB"], 1, result)
        self.assertLess(real_pixels["averageRGB"], 250, result)
        self.assertEqual(real_pixels["alphaMinimum"], 255, result)
        self.assertEqual(real_pixels["compilationAttempts"], 1, result)


if __name__ == "__main__":
    unittest.main()
