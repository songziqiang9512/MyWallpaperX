#!/usr/bin/env python3

"""Shared material texture-transform ABI and real Metal consumption gate."""

from __future__ import annotations

import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

from script.tests.test_scene_resolved_material_pass_encoder import (
    REPOSITORY_ROOT,
    SCENE_ROOT,
    SUPPORT as PASS_ENCODER_SUPPORT,
    SWIFT_SOURCES as PASS_ENCODER_SOURCES,
)


SUPPORT = PASS_ENCODER_SUPPORT.replace(
    """nonisolated enum SceneDynamicTarget: Hashable {
    case effectConstant(layerID: Int, effectIndex: Int, passIndex: Int, name: String)
}

nonisolated enum SceneDynamicSource: Hashable {
    case authored, userProperty, timeline, sceneScript
}

""",
    "",
)

EXTRA_SOURCES = [
    SCENE_ROOT / "Properties/SceneDynamicSnapshot.swift",
    SCENE_ROOT / "RenderGraph/SceneAuthoredShaderFrameInputs.swift",
    SCENE_ROOT
    / "RenderGraph/MaterialProgram/SceneResolvedMaterialHostUniformSchema.swift",
    SCENE_ROOT
    / "RenderGraph/MaterialProgram/SceneResolvedMaterialUniformEncoder.swift",
    SCENE_ROOT
    / "RenderGraph/MaterialProgram/SceneResolvedMaterialGenericShaderProgramArtifact.swift",
    SCENE_ROOT
    / "RenderGraph/ShaderPreparation/SceneGenericShaderMutableFragmentVaryingNormalizer.swift",
    SCENE_ROOT
    / "RenderGraph/ShaderPreparation/SceneGenericShaderBooleanScalarArithmeticNormalizer.swift",
    SCENE_ROOT
    / "RenderGraph/ShaderPreparation/SceneGenericShaderTextureSamplingNormalizer.swift",
    SCENE_ROOT
    / "RenderGraph/ShaderPreparation/SceneGenericShaderVaryingNormalizer.swift",
    SCENE_ROOT / "RenderGraph/ShaderPreparation/SceneGenericShaderSourceNormalizer.swift",
    SCENE_ROOT / "RenderGraph/ShaderPreparation/SceneGenericShaderArtifactBuilder.swift",
    SCENE_ROOT
    / "RenderGraph/ShaderPreparation/SceneGenericShaderArtifactBuilder+ColorTransfer.swift",
    SCENE_ROOT
    / "RenderGraph/ShaderPreparation/SceneGenericShaderIndependentSignalLowering.swift",
    SCENE_ROOT
    / "RenderGraph/ShaderPreparation/SceneGenericShaderIndependentSignalCompositingLowering.swift",
    SCENE_ROOT
    / "RenderGraph/ShaderPreparation/SceneGenericShaderArtifactBuilder+StageUniforms.swift",
    SCENE_ROOT
    / "RenderGraph/ShaderPreparation/SceneGenericShaderStraightAlphaPreservingLowering.swift",
    SCENE_ROOT
    / "RenderGraph/ShaderPreparation/SceneGenericShaderOpaqueFromStraightColorLowering.swift",
    SCENE_ROOT
    / "RenderGraph/ShaderPreparation/SceneGenericShaderStraightAlphaWholeOutputUnionLowering.swift",
    SCENE_ROOT
    / "RenderGraph/ShaderPreparation/SceneGenericShaderTypedDataRGBFilterLowering.swift",
    SCENE_ROOT
    / "RenderGraph/ShaderPreparation/SceneGenericShaderConditionalGeneratedRGBLowering.swift",
    SCENE_ROOT
    / "RenderGraph/ShaderPreparation/SceneGenericShaderSameAlphaReconstructedRGBFilterLowering.swift",
    SCENE_ROOT
    / "RenderGraph/ShaderPreparation/SceneGenericShaderUnitPreviousBlurredCompositeLowering.swift",
    SCENE_ROOT
    / "RenderGraph/ShaderPreparation/SceneGenericShaderAlphaWeightedSampleAverageCanonicalShape.swift",
    SCENE_ROOT / "RenderGraph/ShaderPreparation/SceneGenericShaderBoundedLoopWork.swift",
]
SWIFT_SOURCES = list(dict.fromkeys([*PASS_ENCODER_SOURCES, *EXTRA_SOURCES]))


HARNESS = r'''
import CoreGraphics
import Foundation
import Metal
import simd

private typealias Program = SceneResolvedMaterialProgram
private typealias Template = SceneResolvedMaterialTemplate
private typealias Graph = SceneAuthoredEffectRenderPlan

private let vertex = """
attribute vec3 a_Position;
attribute vec2 a_TexCoord;
varying vec2 v_TexCoord;
void main() {
    v_TexCoord = a_TexCoord;
    gl_Position = vec4(a_Position, 1.0);
}
"""
private let fragment = """
varying vec2 v_TexCoord;
uniform sampler2D g_Texture0;
void main() { gl_FragColor = texSample2D(g_Texture0, v_TexCoord); }
"""

private func prepared(_ marker: String) -> SceneShaderPreparedProgram {
    func stage(
        _ kind: SceneShaderContract.StageKind, _ source: String
    ) -> SceneShaderPreparedSource {
        .init(
            frontendSchemaVersion: SceneShaderVariantEnvironment.frontendSchemaVersion,
            sourceDialect: .wallpaperEngineGLSLLike,
            backend: .mwxMetal,
            stage: kind,
            rootRelativePath: "\(marker)/\(kind.rawValue).shader",
            source: source,
            sourceMap: [],
            activeAnnotations: [],
            activeDeclarations: [],
            dependencies: [],
            dependencySHA256: "dependency-\(marker)-\(kind.rawValue)",
            variantSHA256: "variant-\(marker)-\(kind.rawValue)",
            preparedSHA256: "prepared-\(marker)-\(kind.rawValue)"
        )
    }
    return .init(
        vertex: stage(.vertex, vertex),
        fragment: stage(.fragment, fragment),
        colorContract: .unresolvedAuthoredPass,
        cacheKey: "cache-\(marker)"
    )
}

private func texture(_ device: MTLDevice) -> MTLTexture {
    let descriptor = MTLTextureDescriptor.texture2DDescriptor(
        pixelFormat: .rgba8Unorm, width: 4, height: 2, mipmapped: false
    )
    descriptor.storageMode = .shared
    descriptor.usage = .shaderRead
    let value = device.makeTexture(descriptor: descriptor)!
    let row: [UInt8] = [
        255, 0, 0, 255, 255, 0, 0, 255,
        0, 255, 0, 255, 0, 255, 0, 255,
    ]
    value.replace(
        region: MTLRegionMake2D(0, 0, 4, 2), mipmapLevel: 0,
        withBytes: row + row, bytesPerRow: 16
    )
    return value
}

private func target(_ device: MTLDevice) -> MTLTexture {
    let descriptor = MTLTextureDescriptor.texture2DDescriptor(
        pixelFormat: .rgba8Unorm, width: 2, height: 2, mipmapped: false
    )
    descriptor.storageMode = .shared
    descriptor.usage = [.renderTarget, .shaderRead]
    return device.makeTexture(descriptor: descriptor)!
}

private func slot(
    texture: MTLTexture,
    transform: SceneTextureUVTransform,
    contentGeneration: UInt64
) -> Program.TextureSlot {
    let effect = Graph.EffectKey(
        layerID: 42, effectIndex: 1, descriptorID: "synthetic-atlas"
    )
    let identity = Graph.TextureIdentity(
        kind: .framebuffer,
        layerID: 42,
        effect: effect,
        name: "synthetic-atlas"
    )
    let candidate = SceneTextureCandidate(
        texture: texture,
        identity: .provider(.video(layerID: 42, lifecycleEpoch: 1)),
        generation: .provider(contentGeneration: contentGeneration),
        purpose: .premultipliedColor,
        content: .color(.resolved(.premultipliedAlpha)),
        physicalSize: CGSize(width: 4, height: 2),
        mappedSize: CGSize(width: 4, height: 2),
        uvTransform: transform,
        sampling: .init(texFlags: 3)
    )
    let publication = SceneTextureProviderPublication(
        requestIdentity: .graph(identity),
        candidate: candidate,
        contentGeneration: contentGeneration
    )
    return .init(
        index: 0,
        reference: .graph(identity),
        registryIdentity: .graph(identity),
        diagnosticSelectionProvenance: .authored(.explicitBinding),
        expectedPurpose: .premultipliedColor,
        resource: .init(
            publication: publication,
            resourceGeneration: contentGeneration
        )
    )
}

private func slots(_ slot: Program.TextureSlot) -> [Program.TextureSlot?] {
    var result = Array<Program.TextureSlot?>(repeating: nil, count: 8)
    result[0] = slot
    return result
}

private func inputs() -> SceneAuthoredShaderUniformInputs {
    .init(
        frameIndex: 1,
        renderSize: CGSize(width: 2, height: 2),
        screenSize: CGSize(width: 2, height: 2),
        modelViewProjection: matrix_identity_float4x4,
        layerModelMatrix: matrix_identity_float4x4,
        effectTextureProjectionMatrixInverse: matrix_identity_float4x4,
        sceneTime: 0,
        dayTime: 0,
        frameTime: 1 / 60,
        pointerCurrentNDC: .zero,
        pointerPreviousNDC: .zero,
        texturePhysicalSizes: [0: CGSize(width: 4, height: 2)]
    )
}

private func uniforms(
    frontend: SceneAuthoredShaderProgram,
    slots: [Program.TextureSlot?]
) -> [Program.ResolvedUniform]? {
    let values = inputs()
    return frontend.uniformLayout.fields.map { field in
        guard let host = SceneResolvedMaterialUniformEncoder.hostUniform(
            field, slots: slots
        ), let encoded = SceneResolvedMaterialUniformEncoder.encodeHost(
            host, type: field.type, inputs: values, slots: slots
        ) else { return nil }
        return .init(field: field, source: .host(host), encodedValue: encoded)
    }.compactMap { $0 }
}

private func state() -> SceneMaterialRenderState {
    SceneMaterialRenderState.compile(
        blending: "normal", depthTest: "disabled", depthWrite: "disabled",
        cullMode: "nocull", alphaWriting: nil
    )!
}

private func assembly(
    _ prepared: SceneShaderPreparedProgram,
    frontend: SceneAuthoredShaderProgram,
    slot: Program.TextureSlot
) -> Program.AssemblyInput? {
    let textureSlots = slots(slot)
    guard let resolved = uniforms(frontend: frontend, slots: textureSlots),
          resolved.count == frontend.uniformLayout.fields.count else { return nil }
    return .init(
        preparedShader: prepared,
        textureSlots: textureSlots,
        resolvedUniforms: resolved,
        renderState: state(),
        graphRole: .init(
            effectInput: .layerSource,
            effectOutput: .effectOutput,
            nodeTarget: .framebuffer,
            bindings: [.init(slot: 0, texture: .framebuffer)]
        )
    )
}

private func genericFrontend(
    layout: SceneAuthoredShaderUniformLayout
) -> SceneAuthoredShaderProgram? {
    let fields = layout.fields.map {
        SceneGenericShaderProgramArtifact.Program.UniformLayout.Field(
            name: $0.name,
            authoredName: $0.authoredName,
            stage: $0.stage?.rawValue,
            type: $0.type.rawValue,
            offset: $0.offset,
            arrayCount: $0.arrayCount
        )
    }
    let metal = """
    #include <metal_stdlib>
    using namespace metal;
    struct MWXUniforms {
        float2 mwxRenderSize;
        float4 mwxTexture0Transform0;
        float4 mwxTexture0Transform1;
    };
    struct MWXVertexOut { float4 position [[position]]; float2 uv; };
    vertex MWXVertexOut mwxGenericVertex(uint id [[vertex_id]]) {
        const float2 coordinates[4] = {
            float2(0.0, 1.0), float2(1.0, 1.0),
            float2(0.0, 0.0), float2(1.0, 0.0)
        };
        MWXVertexOut out;
        out.uv = coordinates[id];
        out.position = float4(
            coordinates[id].x * 2.0 - 1.0,
            (1.0 - coordinates[id].y) * 2.0 - 1.0,
            0.0, 1.0
        );
        return out;
    }
    fragment float4 mwxGenericFragment(
        MWXVertexOut in [[stage_in]],
        constant MWXUniforms& uniforms [[buffer(8)]],
        texture2d<float> g_Texture0 [[texture(0)]],
        sampler g_Texture0Sampler [[sampler(0)]]) {
        float2 uv = uniforms.mwxTexture0Transform0.xy
            + uniforms.mwxTexture0Transform0.zw * in.uv.x
            + uniforms.mwxTexture0Transform1.xy * in.uv.y;
        return g_Texture0.sample(g_Texture0Sampler, uv);
    }
    """
    let artifact = SceneGenericShaderProgramArtifact(
        backendID: "glslang-spirv-cross-msl-v2",
        requestKey: "synthetic-transform",
        program: .init(
            metalSource: metal,
            metalSourceSHA256: SceneGenericShaderProgramArtifact.sha256(
                Data(metal.utf8)
            ),
            vertexFunctionName: "mwxGenericVertex",
            fragmentFunctionName: "mwxGenericFragment",
            uniformBufferIndex: 8,
            uniformLayout: .init(fields: fields, byteSize: layout.byteSize),
            textureBindings: [.init(
                name: "g_Texture0", slot: 0, channelUse: "unproven"
            )],
            staticLoopWork: 0,
            colorTransfer: .init(kind: "passthrough", slot: 0, slots: nil),
            fragmentOutputChannelUse: "unproven"
        )
    )
    return artifact.makeProgram(
        expectedKey: "synthetic-transform",
        expectedColorTransfer: .passthrough(textureSlot: 0),
        expectedFragmentOutputChannelUse: .redDefined
    )
}

private func render(
    _ program: Program?,
    encoder: SceneResolvedMaterialPassEncoder,
    queue: MTLCommandQueue,
    device: MTLDevice
) -> (completed: Bool, pixels: [UInt8]) {
    let output = target(device)
    guard let program,
          let pass = encoder.prepare(program: program, target: output),
          let command = queue.makeCommandBuffer(),
          encoder.encode(pass, commandBuffer: command) else {
        return (false, [])
    }
    command.commit()
    command.waitUntilCompleted()
    var pixels = [UInt8](repeating: 0, count: 16)
    output.getBytes(
        &pixels, bytesPerRow: 8,
        from: MTLRegionMake2D(0, 0, 2, 2), mipmapLevel: 0
    )
    return (command.status == .completed && command.error == nil, pixels)
}

private func uniformStageFailure(malformed: Bool) -> String {
    let transformType = malformed ? "vec2" : "vec4"
    let members: [[String: Any]] = malformed ? [
        ["name": "mwxRenderSize", "type": "vec2", "offset": 0],
        ["name": "mwxTexture0Transform0", "type": transformType, "offset": 16],
        ["name": "mwxTexture0Transform1", "type": "vec4", "offset": 32],
    ] : [["name": "mwxRenderSize", "type": "vec2", "offset": 0]]
    let reflection: [String: Any] = [
        "types": ["_1": ["members": members]],
        "ubos": [[
            "type": "_1", "block_size": malformed ? 48 : 16,
            "set": 0, "binding": 8,
        ]],
        "textures": [["name": "g_Texture0", "binding": 0]],
    ]
    let data = try! JSONSerialization.data(withJSONObject: reflection)
    let msl = """
    #include <metal_stdlib>
    using namespace metal;
    struct MWXUniforms { float2 mwxRenderSize; };
    fragment float4 main0(texture2d<float> g_Texture0 [[texture(0)]]) {
        return g_Texture0.sample(sampler(), float2(0.5));
    }
    """
    let stages = ["vertex", "fragment"].map { name in
        SceneGenericShaderArtifactBuilder.Stage(
            name: name,
            source: name == "fragment" ? fragment : vertex,
            authoredSource: name == "fragment" ? fragment : vertex,
            msl: msl,
            reflection: data
        )
    }
    switch SceneGenericShaderArtifactBuilder.build(
        requestKey: "negative", backendID: "glslang-spirv-cross-msl-v2",
        stages: stages, maximumArtifactBytes: 100_000
    ) {
    case .success: return "accepted"
    case let .failure(failure): return String(describing: failure)
    }
}

@main
private enum Main {
    static func main() throws {
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue(),
              let encoder = SceneResolvedMaterialPassEncoder(device: device) else {
            print(#"{"metalAvailable":false}"#)
            return
        }
        let source = texture(device)
        let frame0 = SceneTextureUVTransform(
            origin: .zero, xAxis: SIMD2(0.5, 0), yAxis: SIMD2(0, 1)
        )
        let frame1 = SceneTextureUVTransform(
            origin: SIMD2(0.5, 0), xAxis: SIMD2(0.5, 0), yAxis: SIMD2(0, 1)
        )
        let identity = SceneTextureUVTransform.identity
        let invalid = SceneTextureUVTransform(
            origin: SIMD2(0.8, 0), xAxis: SIMD2(0.5, 0), yAxis: SIMD2(0, 1)
        )
        let shader = prepared("bounded")
        let bounded = SceneAuthoredShaderFrontend.compile(
            vertexSource: vertex, fragmentSource: fragment
        ).program!
        let generic = genericFrontend(layout: bounded.uniformLayout)!

        func program(
            frontend: SceneAuthoredShaderProgram,
            transform: SceneTextureUVTransform,
            generation: UInt64,
            genericBackend: Bool
        ) -> Program? {
            let selected = slot(
                texture: source,
                transform: transform,
                contentGeneration: generation
            )
            guard let input = assembly(shader, frontend: frontend, slot: selected) else {
                return nil
            }
            return genericBackend ? Program.assembleCompiled(
                input,
                frontend: frontend,
                routeDecision: .init(
                    profile: "ordinary-shader",
                    state: "prefer-generic",
                    fallbackOwner: "bounded-frontend"
                ),
                conditionalGeneratedRGBInputContract: nil
            ) : Program.assemble(input)
        }

        let bounded0 = program(
            frontend: bounded, transform: frame0, generation: 1,
            genericBackend: false
        )
        let bounded1 = program(
            frontend: bounded, transform: frame1, generation: 2,
            genericBackend: false
        )
        let boundedIdentity = program(
            frontend: bounded, transform: identity, generation: 3,
            genericBackend: false
        )
        let boundedInvalid = program(
            frontend: bounded, transform: invalid, generation: 4,
            genericBackend: false
        )
        let bounded0Pixels = render(
            bounded0, encoder: encoder, queue: queue, device: device
        )
        let attemptsAfterBounded0 = encoder.pipelineCompilationAttemptCount
        let bounded1Pixels = render(
            bounded1, encoder: encoder, queue: queue, device: device
        )
        let attemptsAfterBounded1 = encoder.pipelineCompilationAttemptCount
        let identityPixels = render(
            boundedIdentity, encoder: encoder, queue: queue, device: device
        )

        let generic0 = program(
            frontend: generic, transform: frame0, generation: 1,
            genericBackend: true
        )
        let generic1 = program(
            frontend: generic, transform: frame1, generation: 2,
            genericBackend: true
        )
        let generic0Pixels = render(
            generic0, encoder: encoder, queue: queue, device: device
        )
        let attemptsAfterGeneric0 = encoder.pipelineCompilationAttemptCount
        let generic1Pixels = render(
            generic1, encoder: encoder, queue: queue, device: device
        )
        let attemptsAfterGeneric1 = encoder.pipelineCompilationAttemptCount

        let red = Array(repeating: [UInt8](arrayLiteral: 255, 0, 0, 255), count: 4)
            .flatMap { $0 }
        let green = Array(repeating: [UInt8](arrayLiteral: 0, 255, 0, 255), count: 4)
            .flatMap { $0 }
        let identityExpected: [UInt8] = [
            255, 0, 0, 255, 0, 255, 0, 255,
            255, 0, 0, 255, 0, 255, 0, 255,
        ]
        let reservedFragment = """
        varying vec2 v_TexCoord;
        uniform sampler2D g_Texture0;
        uniform vec4 mwxTexture0Transform0;
        void main() { gl_FragColor = texSample2D(g_Texture0, v_TexCoord); }
        """
        let boundedReserved = SceneAuthoredShaderFrontend.compile(
            vertexSource: vertex, fragmentSource: reservedFragment
        )
        let genericReserved = SceneGenericShaderSourceNormalizer.normalize(
            vertexSource: vertex,
            fragmentSource: reservedFragment,
            maximumStageSourceBytes: 100_000
        )
        let normalized = SceneGenericShaderSourceNormalizer.normalize(
            vertexSource: vertex,
            fragmentSource: fragment,
            maximumStageSourceBytes: 100_000
        )
        let normalizedConsumes: Bool
        if case let .success(pair) = normalized {
            normalizedConsumes = pair.fragment.contains(
                "mwxTexture0Coordinate"
            ) && pair.fragment.contains("#define texSample2D")
                && pair.fragment.contains("#define texture2DLod")
        } else { normalizedConsumes = false }
        let genericReservedRejected: Bool
        if case .failure(.reservedUniform) = genericReserved {
            genericReservedRejected = true
        } else { genericReservedRejected = false }
        let result: [String: Any] = [
            "metalAvailable": true,
            "bounded": [
                "programBuilt": bounded0 != nil && bounded1 != nil,
                "frame0": bounded0Pixels.completed && bounded0Pixels.pixels == red,
                "frame1": bounded1Pixels.completed && bounded1Pixels.pixels == green,
                "mappedStatic": bounded0Pixels.pixels == red,
                "identityStatic": identityPixels.completed
                    && identityPixels.pixels == identityExpected,
                "invalidRejected": boundedInvalid == nil,
                "exactChanges": bounded0?.exactIdentity != bounded1?.exactIdentity,
                "uniformChanges": bounded0?.uniformBytes != bounded1?.uniformBytes,
                "semanticStable": bounded0?.semanticIdentity == bounded1?.semanticIdentity,
                "pipelineStable": attemptsAfterBounded0 == attemptsAfterBounded1,
            ],
            "generic": [
                "programBuilt": generic0 != nil && generic1 != nil,
                "frame0": generic0Pixels.completed && generic0Pixels.pixels == red,
                "frame1": generic1Pixels.completed && generic1Pixels.pixels == green,
                "matchesBounded": generic0Pixels.pixels == bounded0Pixels.pixels
                    && generic1Pixels.pixels == bounded1Pixels.pixels,
                "pipelineStable": attemptsAfterGeneric0 == attemptsAfterGeneric1,
                "normalizerConsumes": normalizedConsumes,
            ],
            "negative": [
                "boundedReserved": boundedReserved.program == nil
                    && boundedReserved.diagnostics.contains {
                        $0.code == .unsupportedDeclaration
                    },
                "genericReserved": genericReservedRejected,
                "missingABI": uniformStageFailure(malformed: false)
                    == "uniformStageMismatch",
                "malformedABI": uniformStageFailure(malformed: true)
                    == "uniformStageMismatch",
            ],
        ]
        let data = try JSONSerialization.data(
            withJSONObject: result, options: [.sortedKeys]
        )
        FileHandle.standardOutput.write(data)
    }
}
'''


class SceneMaterialTextureTransformTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.temporary_directory = tempfile.TemporaryDirectory(
            prefix="mwx-material-texture-transform-"
        )
        root = Path(cls.temporary_directory.name)
        support = root / "Support.swift"
        harness = root / "Harness.swift"
        binary = root / "material-texture-transform"
        support.write_text(SUPPORT, encoding="utf-8")
        harness.write_text(HARNESS, encoding="utf-8")
        environment = os.environ.copy()
        environment["CLANG_MODULE_CACHE_PATH"] = str(root / "clang-cache")
        environment["SWIFT_MODULECACHE_PATH"] = str(root / "swift-cache")
        compilation = subprocess.run(
            [
                "xcrun", "--sdk", "macosx", "swiftc", "-parse-as-library",
                str(support), *(str(path) for path in SWIFT_SOURCES), str(harness),
                "-framework", "Metal", "-framework", "CoreGraphics",
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
            [str(binary)],
            cwd=REPOSITORY_ROOT,
            env=environment,
            capture_output=True,
            text=True,
        )
        if completed.returncode != 0:
            raise RuntimeError(completed.stderr or completed.stdout)
        cls.result = json.loads(completed.stdout)
        if not cls.result["metalAvailable"]:
            raise unittest.SkipTest("Metal is unavailable")

    @classmethod
    def tearDownClass(cls) -> None:
        cls.temporary_directory.cleanup()

    def test_bounded_and_generic_consume_exact_transform_on_gpu(self) -> None:
        self.assertEqual(
            [key for key, value in self.result["bounded"].items() if not value],
            [],
            self.result,
        )
        self.assertEqual(
            [key for key, value in self.result["generic"].items() if not value],
            [],
            self.result,
        )

    def test_reserved_and_malformed_abi_fail_typed(self) -> None:
        self.assertEqual(
            [key for key, value in self.result["negative"].items() if not value],
            [],
            self.result,
        )


if __name__ == "__main__":
    unittest.main()
