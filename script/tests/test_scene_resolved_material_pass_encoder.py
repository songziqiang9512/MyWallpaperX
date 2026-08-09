#!/usr/bin/env python3

"""R4 atomic material Program preflight, pipeline cache and Metal encoding gate."""

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
SWIFT_SOURCES = [
    SCENE_ROOT / "Format/SceneJSONValue.swift",
    SCENE_ROOT / "RenderGraph/SceneShaderSourceGraph.swift",
    SCENE_ROOT / "RenderGraph/SceneShaderContract.swift",
    SCENE_ROOT / "RenderGraph/SceneShaderVariantEnvironment.swift",
    SCENE_ROOT / "RenderGraph/SceneShaderVariantEnvironment+HostFacts.swift",
    SCENE_ROOT / "RenderGraph/SceneAuthoredEffectRenderPlan.swift",
    SCENE_ROOT / "RenderGraph/SceneMaterialRenderState.swift",
    SCENE_ROOT / "RenderGraph/SceneAuthoredShaderFrontendModel.swift",
    SCENE_ROOT / "RenderGraph/SceneAuthoredShaderLexer.swift",
    SCENE_ROOT / "RenderGraph/SceneAuthoredShaderBoundedLoopAdmission.swift",
    SCENE_ROOT / "RenderGraph/SceneAuthoredShaderStaticLoopAdmission.swift",
    SCENE_ROOT / "RenderGraph/SceneAuthoredShaderLoopAnalyzer.swift",
    SCENE_ROOT / "RenderGraph/SceneAuthoredShaderSyntax.swift",
    SCENE_ROOT / "RenderGraph/SceneAuthoredShaderDeadBindingAnalyzer.swift",
    SCENE_ROOT / "RenderGraph/SceneAuthoredShaderMetalSource.swift",
    SCENE_ROOT / "RenderGraph/SceneAuthoredShaderVectorConversion.swift",
    SCENE_ROOT / "RenderGraph/SceneAuthoredShaderFunctionSemantics.swift",
    SCENE_ROOT / "RenderGraph/SceneAuthoredShaderVaryingArrayEmitter.swift",
    SCENE_ROOT / "RenderGraph/SceneAuthoredShaderMetalEmitter.swift",
    SCENE_ROOT / "RenderGraph/SceneAuthoredShaderMetalEmitter+Translation.swift",
    SCENE_ROOT / "RenderGraph/SceneAuthoredShaderColorTransferAnalyzer.swift",
    SCENE_ROOT / "RenderGraph/SceneAuthoredShaderSameSlotMixAnalyzer.swift",
    SCENE_ROOT / "RenderGraph/SceneAuthoredShaderSameSlotMixGraphAnalyzer.swift",
    SCENE_ROOT / "RenderGraph/SceneAuthoredShaderOpaqueInputAlphaAnalyzer.swift",
    SCENE_ROOT / "RenderGraph/SceneAuthoredShaderIndependentAlphaAnalyzer.swift",
    SCENE_ROOT / "RenderGraph/SceneAuthoredShaderPremultipliedOutputAnalyzer.swift",
    SCENE_ROOT / "RenderGraph/SceneAuthoredShaderFrontend.swift",
    SCENE_ROOT / "Resources/SceneTextureSampling.swift",
    SCENE_ROOT / "Resources/SceneTextureUVTransform.swift",
    SCENE_ROOT / "Resources/SceneTextureCandidate.swift",
    SCENE_ROOT / "Resources/SceneTextureSlotBinding.swift",
    SCENE_ROOT / "Resources/SceneTextureProviderPublication.swift",
    SCENE_ROOT / "RenderGraph/SceneResolvedMaterialProgram.swift",
    SCENE_ROOT / "RenderGraph/SceneResolvedMaterialHostUniformSchema.swift",
    SCENE_ROOT / "RenderGraph/SceneResolvedMaterialProgramIdentity.swift",
    SCENE_ROOT / "RenderGraph/SceneResolvedMaterialProgramIdentity+ExactTexture.swift",
    SCENE_ROOT / "RenderGraph/SceneResolvedMaterialProgram+Derivation.swift",
    SCENE_ROOT / "RenderGraph/SceneResolvedMaterialProgram+ColorDerivation.swift",
    SCENE_ROOT
    / "RenderGraph/EffectExecution/SceneResolvedMaterialPassEncoder.swift",
]


SUPPORT = r'''
import Foundation
import Metal

nonisolated enum SceneTextureLoadPurpose: Hashable, Sendable {
    case premultipliedColor, straightAlbedo, preservedChannels, mask, noise
    case flow, phase, normal, depth, lookupTable
    var requiresVolumeTexture: Bool { self == .lookupTable }
}

nonisolated struct SceneResolvedMaterialNode {
    enum TextureProvenance: String, Hashable {
        case material, instance, userTexture, explicitBinding
    }
}

nonisolated enum SceneDynamicTarget: Hashable {
    case effectConstant(layerID: Int, effectIndex: Int, passIndex: Int, name: String)
}

nonisolated enum SceneDynamicSource: Hashable {
    case authored, userProperty, timeline, sceneScript
}

nonisolated enum SceneFrameTextureIdentity: Hashable {
    case layerSource(Int)
    case namedLayerTarget(String)
    case graph(SceneAuthoredEffectRenderPlan.TextureIdentity)
    case asset(SceneAssetTextureIdentity)
    case userProperty(String)
    case materialUserProperty(SceneUserPropertyTextureIdentity)
    case system(String)
}
'''


HARNESS = r'''
import CoreGraphics
import Foundation
import Metal
import simd

private typealias Program = SceneResolvedMaterialProgram
private typealias Template = SceneResolvedMaterialTemplate
private typealias Graph = SceneAuthoredEffectRenderPlan

private let vertexSource = """
attribute vec3 a_Position;
attribute vec2 a_TexCoord;
varying vec2 v_TexCoord;
void main() {
    v_TexCoord = a_TexCoord;
    gl_Position = vec4(a_Position, 1.0);
}
"""

private func fragment(
    outputSlot: Int,
    uniformName: String = "g_Gain",
    unresolved: Bool = false
) -> String {
    let output = if unresolved {
        "gl_FragColor = texSample2D(g_Texture0, v_TexCoord) * g_Gain;"
    } else if outputSlot == 3 {
        """
        vec4 color = texSample2D(g_Texture0, v_TexCoord);
        float mask = texSample2D(g_Texture3, v_TexCoord).r;
        color.a *= mask;
        gl_FragColor = color;
        """
    } else {
        "gl_FragColor = texSample2D(g_Texture0, v_TexCoord);"
    }
    return """
    varying vec2 v_TexCoord;
    uniform sampler2D g_Texture0;
    uniform sampler2D g_Texture3;
    uniform float \(uniformName);
    void main() {
        \(output)
    }
    """
}

private let straightAlphaFragment = """
varying vec2 v_TexCoord;
uniform sampler2D g_Texture0;
uniform sampler2D g_Texture3;
uniform float g_Gain;
void main() {
    vec4 color = texSample2D(g_Texture0, v_TexCoord);
    gl_FragColor = vec4(color.rgb, color.a * g_Gain);
}
"""

private let maskedAlphaFragment = """
varying vec2 v_TexCoord;
uniform sampler2D g_Texture0;
uniform sampler2D g_Texture3;
uniform float g_Gain;
void main() {
    vec4 color = texSample2D(g_Texture0, v_TexCoord);
    float mask = texSample2D(g_Texture3, v_TexCoord).r;
    color.a *= mask * g_Gain;
    gl_FragColor = color;
}
"""

private func prepared(
    marker: String,
    fragmentSource: String
) -> SceneShaderPreparedProgram {
    func stage(
        _ kind: SceneShaderContract.StageKind,
        source: String
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
        vertex: stage(.vertex, source: vertexSource),
        fragment: stage(.fragment, source: fragmentSource),
        colorContract: .unresolvedAuthoredPass,
        cacheKey: "cache-\(marker)"
    )
}

private func state() -> SceneMaterialRenderState {
    SceneMaterialRenderState.compile(
        blending: "normal",
        depthTest: "disabled",
        depthWrite: "disabled",
        cullMode: "nocull",
        alphaWriting: nil
    )!
}

private func graphIdentity(_ marker: Int = 1) -> Graph.TextureIdentity {
    let effect = Graph.EffectKey(
        layerID: marker,
        effectIndex: marker,
        descriptorID: "descriptor-\(marker)"
    )
    return .init(
        kind: .framebuffer,
        layerID: marker,
        effect: effect,
        name: "framebuffer-\(marker)"
    )
}

private func texture(
    device: MTLDevice,
    format: MTLPixelFormat = .rgba8Unorm,
    width: Int = 2,
    height: Int = 2,
    usage: MTLTextureUsage = .shaderRead,
    fill: [UInt8]? = nil
) -> MTLTexture {
    let descriptor = MTLTextureDescriptor.texture2DDescriptor(
        pixelFormat: format,
        width: width,
        height: height,
        mipmapped: false
    )
    descriptor.storageMode = .shared
    descriptor.usage = usage
    let result = device.makeTexture(descriptor: descriptor)!
    if let fill {
        result.replace(
            region: MTLRegionMake2D(0, 0, width, height),
            mipmapLevel: 0,
            withBytes: fill,
            bytesPerRow: width * 4
        )
    }
    return result
}

private func target(
    device: MTLDevice,
    format: MTLPixelFormat = .rgba8Unorm,
    width: Int = 2,
    height: Int = 2,
    usage: MTLTextureUsage = [.renderTarget, .shaderRead]
) -> MTLTexture {
    texture(
        device: device,
        format: format,
        width: width,
        height: height,
        usage: usage
    )
}

private func slot(
    device: MTLDevice,
    index: Int,
    texture: MTLTexture,
    content: SceneTextureContent,
    purpose: SceneTextureLoadPurpose,
    sampling: SceneTextureSampling,
    marker: Int = 1
) -> Program.TextureSlot {
    let reference: Template.TextureReference
    let registry: SceneFrameTextureIdentity
    if index == 0 {
        let identity = graphIdentity(marker)
        reference = .graph(identity)
        registry = .graph(identity)
    } else {
        let path = SceneVFSAssetPath("assets/slot\(index)-\(marker).tex")!
        reference = .asset(path)
        registry = .asset(.init(path: path, purpose: purpose))
    }
    let generation = UInt64(marker)
    let publication = SceneTextureProviderPublication(
        requestIdentity: registry,
        candidate: .init(
            texture: texture,
            identity: .provider(.video(layerID: marker, lifecycleEpoch: 1)),
            generation: .provider(contentGeneration: generation),
            purpose: purpose,
            content: content,
            physicalSize: CGSize(width: texture.width, height: texture.height),
            mappedSize: CGSize(width: texture.width, height: texture.height),
            uvTransform: .identity,
            sampling: sampling
        ),
        contentGeneration: generation
    )
    return .init(
        index: index,
        reference: reference,
        registryIdentity: registry,
        diagnosticSelectionProvenance: .authored(.explicitBinding),
        expectedPurpose: purpose,
        resource: .init(publication: publication, resourceGeneration: generation)
    )
}

private func slots(_ values: Program.TextureSlot...) -> [Program.TextureSlot?] {
    var result = Array<Program.TextureSlot?>(repeating: nil, count: 8)
    for value in values { result[value.index] = value }
    return result
}

private func bytes<T>(_ value: T) -> Data {
    var copy = value
    return withUnsafeBytes(of: &copy) { Data($0) }
}

private func uniforms(
    shader: SceneShaderPreparedProgram,
    gain: Float = 0.5,
    malformed: Bool = false
) -> [Program.ResolvedUniform] {
    let frontend = SceneAuthoredShaderFrontend.compile(
        vertexSource: shader.vertex.source,
        fragmentSource: shader.fragment.source
    ).program!
    return frontend.uniformLayout.fields.map { field in
        let value: Data
        if field.name == "mwxRenderSize" {
            value = bytes(SIMD2<Float>(2, 2))
        } else if malformed {
            value = bytes(SIMD2<Float>(0.5, 0.5))
        } else {
            value = bytes(gain)
        }
        let source: Program.ResolvedUniform.Source = field.name == "mwxRenderSize"
            ? .host(.renderSize)
            : .staticValue
        return .init(field: field, source: source, encodedValue: value)
    }
}

private func program(
    device: MTLDevice,
    marker: Int,
    outputSlot: Int,
    slot0Texture: MTLTexture? = nil,
    slot0Content: SceneTextureContent = .color(.resolved(.premultipliedAlpha)),
    slot0Purpose: SceneTextureLoadPurpose = .premultipliedColor,
    slot3Texture: MTLTexture? = nil,
    slot3Content: SceneTextureContent = .data,
    slot3Purpose: SceneTextureLoadPurpose = .mask,
    slot3Sampling: SceneTextureSampling = .init(texFlags: 1),
    uniformName: String = "g_Gain",
    unresolved: Bool = false,
    fragmentSource: String? = nil,
    gain: Float = 0.5,
    malformedUniform: Bool = false
) -> Program? {
    let shader = prepared(
        marker: "program-\(marker)",
        fragmentSource: fragmentSource ?? fragment(
            outputSlot: outputSlot,
            uniformName: uniformName,
            unresolved: unresolved
        )
    )
    let first = slot(
        device: device,
        index: 0,
        texture: slot0Texture ?? texture(device: device),
        content: slot0Content,
        purpose: slot0Purpose,
        sampling: .directImageFallback,
        marker: marker
    )
    let third = slot(
        device: device,
        index: 3,
        texture: slot3Texture ?? texture(device: device),
        content: slot3Content,
        purpose: slot3Purpose,
        sampling: slot3Sampling,
        marker: marker + 100
    )
    let frontend = SceneAuthoredShaderFrontend.compile(
        vertexSource: shader.vertex.source,
        fragmentSource: shader.fragment.source
    ).program!
    let activeSlots = Set(frontend.textureBindings.map(\.slot))
    var resolvedSlots = Array<Program.TextureSlot?>(repeating: nil, count: 8)
    if activeSlots.contains(0) { resolvedSlots[0] = first }
    if activeSlots.contains(3) { resolvedSlots[3] = third }
    return Program.assemble(.init(
        preparedShader: shader,
        textureSlots: resolvedSlots,
        resolvedUniforms: uniforms(
            shader: shader,
            gain: gain,
            malformed: malformedUniform
        ),
        renderState: state(),
        graphRole: .init(
            effectInput: .layerSource,
            effectOutput: .effectOutput,
            nodeTarget: .framebuffer,
            bindings: activeSlots.contains(0)
                ? [.init(slot: 0, texture: .framebuffer)]
                : []
        )
    ))
}

private func pixels(_ texture: MTLTexture) -> [UInt8] {
    var result = [UInt8](repeating: 0, count: texture.width * texture.height * 4)
    texture.getBytes(
        &result,
        bytesPerRow: texture.width * 4,
        from: MTLRegionMake2D(0, 0, texture.width, texture.height),
        mipmapLevel: 0
    )
    return result
}

@main
private enum Harness {
    static func main() throws {
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue(),
              let encoder = SceneResolvedMaterialPassEncoder(device: device) else {
            print("{\"metalAvailable\":false}")
            return
        }

        // Four distinct quadrants keep a vertically mirrored pass from
        // satisfying a set-of-colors assertion.
        let color: [UInt8] = [
            255, 0, 0, 255, 0, 255, 0, 255,
            0, 0, 255, 255, 255, 255, 0, 255,
        ]
        let authoredTexture = texture(device: device, fill: color)
        let whiteMask = texture(
            device: device,
            fill: [UInt8](repeating: 255, count: 16)
        )
        let baseline = program(
            device: device,
            marker: 1,
            outputSlot: 3,
            slot0Texture: authoredTexture,
            slot3Texture: whiteMask
        )!
        let rgbaTarget = target(device: device)
        let first = encoder.prepare(program: baseline, target: rgbaTarget)
        let attemptsAfterFirst = encoder.pipelineCompilationAttemptCount
        let second = encoder.prepare(program: baseline, target: rgbaTarget)
        let pipelineCacheReused = second != nil
            && encoder.pipelineCompilationAttemptCount == attemptsAfterFirst

        let changedSampling = program(
            device: device,
            marker: 2,
            outputSlot: 3,
            slot3Sampling: .init(texFlags: 3)
        )!
        let samplingVariant = encoder.prepare(
            program: changedSampling,
            target: rgbaTarget
        )
        let cacheReusedAcrossResources = encoder.pipelineCompilationAttemptCount == 1

        var encoded = false
        var gpuCompleted = false
        var outputMatches = false
        var committedBufferRejected = false
        if let first, let command = queue.makeCommandBuffer() {
            encoded = encoder.encode(first, commandBuffer: command)
            command.commit()
            command.waitUntilCompleted()
            gpuCompleted = command.status == .completed && command.error == nil
            committedBufferRejected = !encoder.encode(
                first,
                commandBuffer: command
            )
            outputMatches = pixels(rgbaTarget) == color
        }

        let bgraTarget = target(device: device, format: .bgra8Unorm)
        let bgraPrepared = encoder.prepare(program: baseline, target: bgraTarget)
        let separateFormatPipeline = bgraPrepared != nil
            && encoder.pipelineCompilationAttemptCount == 2

        let straight = program(
            device: device,
            marker: 3,
            outputSlot: 0,
            slot0Content: .color(.resolved(.straightAlpha)),
            slot0Purpose: .straightAlbedo
        )!
        let attemptsBeforeColorGate = encoder.pipelineCompilationAttemptCount
        let straightRejected = encoder.prepare(
            program: straight,
            target: rgbaTarget
        ) == nil && encoder.pipelineCompilationAttemptCount == attemptsBeforeColorGate
        let unresolvedRejectedUpstream = program(
            device: device,
            marker: 4,
            outputSlot: 0,
            unresolved: true
        ) == nil

        let aliasTexture = target(device: device)
        let aliasProgram = program(
            device: device,
            marker: 5,
            outputSlot: 0,
            slot0Texture: aliasTexture
        )!
        let aliasRejected = encoder.prepare(
            program: aliasProgram,
            target: aliasTexture
        ) == nil

        let shortGraphTexture = texture(
            device: device,
            width: 1,
            height: 1,
            fill: [32, 64, 96, 128]
        )
        let shortGraph = program(
            device: device,
            marker: 6,
            outputSlot: 0,
            slot0Texture: shortGraphTexture
        )!
        let crossExtentTarget = target(device: device)
        let crossExtentPrepared = encoder.prepare(
            program: shortGraph,
            target: crossExtentTarget
        )
        var crossExtentEncoded = false
        var crossExtentGPUCompleted = false
        var crossExtentOutputMatches = false
        if let crossExtentPrepared, let command = queue.makeCommandBuffer() {
            crossExtentEncoded = encoder.encode(
                crossExtentPrepared,
                commandBuffer: command
            )
            command.commit()
            command.waitUntilCompleted()
            crossExtentGPUCompleted = command.status == .completed
                && command.error == nil
            let output = pixels(crossExtentTarget)
            crossExtentOutputMatches = stride(from: 0, to: 16, by: 4)
                .allSatisfy { Array(output[$0 ..< $0 + 4]) == [32, 64, 96, 128] }
        }

        let premultipliedPixel = texture(
            device: device,
            width: 1,
            height: 1,
            fill: [64, 32, 16, 128]
        )
        let straightCases: [(Float, [UInt8])] = [
            (0.0, [0, 0, 0, 0]),
            (0.5, [32, 16, 8, 64]),
            (1.0, [64, 32, 16, 128]),
        ]
        var straightBoundaryPrepared = true
        var straightBoundaryGPUCompleted = true
        var straightBoundaryPixelsMatch = true
        var straightBoundaryPremultiplied = true
        for (index, testCase) in straightCases.enumerated() {
            let straightProgram = program(
                device: device,
                marker: 20 + index,
                outputSlot: 0,
                slot0Texture: premultipliedPixel,
                slot3Content: .data,
                slot3Purpose: .mask,
                fragmentSource: straightAlphaFragment,
                gain: testCase.0
            )!
            let output = target(device: device, width: 1, height: 1)
            guard let prepared = encoder.prepare(program: straightProgram, target: output),
                  prepared.fragmentOutput == .premultipliedAlpha,
                  let command = queue.makeCommandBuffer() else {
                straightBoundaryPrepared = false
                continue
            }
            guard encoder.encode(prepared, commandBuffer: command) else {
                straightBoundaryPrepared = false
                continue
            }
            command.commit()
            command.waitUntilCompleted()
            straightBoundaryGPUCompleted = straightBoundaryGPUCompleted
                && command.status == .completed
                && command.error == nil
            let actual = pixels(output)
            straightBoundaryPixelsMatch = straightBoundaryPixelsMatch
                && zip(actual, testCase.1).allSatisfy {
                    abs(Int($0.0) - Int($0.1)) <= 1
                }
            straightBoundaryPremultiplied = straightBoundaryPremultiplied
                && actual[0] <= actual[3]
                && actual[1] <= actual[3]
                && actual[2] <= actual[3]
        }

        let maskPixel = texture(
            device: device,
            width: 1,
            height: 1,
            fill: [128, 0, 0, 255]
        )
        let maskedProgram = program(
            device: device,
            marker: 30,
            outputSlot: 0,
            slot0Texture: premultipliedPixel,
            slot3Texture: maskPixel,
            slot3Content: .data,
            slot3Purpose: .mask,
            fragmentSource: maskedAlphaFragment,
            gain: 0.5
        )
        let secondColorRejected = program(
            device: device,
            marker: 31,
            outputSlot: 0,
            slot0Texture: premultipliedPixel,
            slot3Texture: maskPixel,
            slot3Content: .color(.resolved(.straightAlpha)),
            slot3Purpose: .straightAlbedo,
            fragmentSource: maskedAlphaFragment,
            gain: 0.5
        ) == nil
        var maskedBoundaryPrepared = false
        var maskedBoundaryGPUCompleted = false
        var maskedBoundaryPixelsMatch = false
        let maskedTarget = target(device: device, width: 1, height: 1)
        if let maskedProgram,
           let prepared = encoder.prepare(program: maskedProgram, target: maskedTarget),
           let command = queue.makeCommandBuffer() {
            maskedBoundaryPrepared = prepared.fragmentOutput == .premultipliedAlpha
            if encoder.encode(prepared, commandBuffer: command) {
                command.commit()
                command.waitUntilCompleted()
                maskedBoundaryGPUCompleted = command.status == .completed
                    && command.error == nil
                maskedBoundaryPixelsMatch = zip(
                    pixels(maskedTarget), [UInt8(16), 8, 4, 32]
                ).allSatisfy { abs(Int($0.0) - Int($0.1)) <= 1 }
            }
        }

        let r8Target = target(device: device, format: .r8Unorm)
        let formatRejected = encoder.prepare(
            program: baseline,
            target: r8Target
        ) == nil
        let readOnlyTarget = target(device: device, usage: .shaderRead)
        let missingRenderTargetRejected = encoder.prepare(
            program: baseline,
            target: readOnlyTarget
        ) == nil
        let writeOnlyTarget = target(device: device, usage: .renderTarget)
        let missingShaderReadRejected = encoder.prepare(
            program: baseline,
            target: writeOnlyTarget
        ) == nil

        let noReadTexture = texture(device: device, usage: .renderTarget)
        let inputUsageRejectedUpstream = program(
            device: device,
            marker: 7,
            outputSlot: 0,
            slot0Texture: noReadTexture
        ) == nil
        let malformedUniformRejectedUpstream = program(
            device: device,
            marker: 8,
            outputSlot: 0,
            malformedUniform: true
        ) == nil

        let invalidMetal = program(
            device: device,
            marker: 9,
            outputSlot: 0,
            uniformName: "operator"
        )!
        let attemptsBeforeFailure = encoder.pipelineCompilationAttemptCount
        let firstFailure = encoder.prepare(
            program: invalidMetal,
            target: rgbaTarget
        ) == nil
        let attemptsAfterFailure = encoder.pipelineCompilationAttemptCount
        let secondFailure = encoder.prepare(
            program: invalidMetal,
            target: rgbaTarget
        ) == nil
        let failureNegativeCached = firstFailure
            && secondFailure
            && attemptsAfterFailure == attemptsBeforeFailure + 1
            && encoder.pipelineCompilationAttemptCount == attemptsAfterFailure
            && encoder.failedPipelineCount == 1

        let preparedBeforeReset = second
        encoder.reset()
        let resetClearedCache = encoder.cachedPipelineCount == 0
            && encoder.pipelineCompilationAttemptCount == 0
            && encoder.failedPipelineCount == 0
        var stalePreparedRejected = false
        if let preparedBeforeReset, let staleCommand = queue.makeCommandBuffer() {
            stalePreparedRejected = !encoder.encode(
                preparedBeforeReset,
                commandBuffer: staleCommand
            )
        }
        let preparedAfterReset = encoder.prepare(
            program: baseline,
            target: rgbaTarget
        )

        var crossDeviceExercised = false
        var crossDeviceRejected = true
        if let other = MTLCopyAllDevices().first(where: {
            $0.registryID != device.registryID
        }) {
            crossDeviceExercised = true
            let otherTarget = target(device: other)
            crossDeviceRejected = encoder.prepare(
                program: baseline,
                target: otherTarget
            ) == nil
        }

        let results: [String: Bool] = [
            "metalAvailable": true,
            "prepared": first != nil,
            "pipelineCompiledOnce": attemptsAfterFirst == 1,
            "pipelineCacheReused": pipelineCacheReused,
            "cacheReusedAcrossResources": cacheReusedAcrossResources,
            "authoredSlotsPreserved": first?.bindingSlots == [0, 3],
            "typedSamplersPreserved": first?.bindingSamplings
                == [.directImageFallback, .init(texFlags: 1)],
            "uniformLayoutPreserved": first?.uniformByteCount
                == baseline.frontendProgram.uniformLayout.byteSize,
            "baselineOutputPremultiplied": first?.fragmentOutput
                == .premultipliedAlpha,
            "premultipliedOutputPublished": crossExtentPrepared?.fragmentOutput
                == .premultipliedAlpha,
            "commandsEncoded": encoded,
            "gpuCompleted": gpuCompleted,
            "committedCommandBufferRejected": committedBufferRejected,
            "outputMatches": outputMatches,
            "rgbaAndBgraSupported": separateFormatPipeline,
            "straightOutputRejectedBeforeCompile": straightRejected,
            "unresolvedOutputRejectedUpstream": unresolvedRejectedUpstream,
            "inputTargetAliasRejected": aliasRejected,
            "crossExtentGraphPrepared": crossExtentPrepared != nil,
            "crossExtentGraphEncoded": crossExtentEncoded,
            "crossExtentGraphGPUCompleted": crossExtentGPUCompleted,
            "crossExtentGraphOutputMatches": crossExtentOutputMatches,
            "straightBoundaryPrepared": straightBoundaryPrepared,
            "straightBoundaryGPUCompleted": straightBoundaryGPUCompleted,
            "straightBoundaryPixelsMatch": straightBoundaryPixelsMatch,
            "straightBoundaryPremultiplied": straightBoundaryPremultiplied,
            "maskedBoundaryPrepared": maskedBoundaryPrepared,
            "maskedBoundaryGPUCompleted": maskedBoundaryGPUCompleted,
            "maskedBoundaryPixelsMatch": maskedBoundaryPixelsMatch,
            "secondColorRejected": secondColorRejected,
            "targetFormatRejected": formatRejected,
            "missingRenderTargetRejected": missingRenderTargetRejected,
            "missingShaderReadRejected": missingShaderReadRejected,
            "inputUsageRejectedUpstream": inputUsageRejectedUpstream,
            "uniformMismatchRejectedUpstream": malformedUniformRejectedUpstream,
            "pipelineFailureNegativeCached": failureNegativeCached,
            "resetClearsCache": resetClearedCache,
            "resetInvalidatesPreparedPass": stalePreparedRejected,
            "prepareAfterReset": preparedAfterReset != nil,
            "crossDeviceRejectedWhenAvailable": crossDeviceRejected,
        ]
        let payload: [String: Any] = [
            "results": results,
            "crossDeviceExercised": crossDeviceExercised,
        ]
        let data = try JSONSerialization.data(
            withJSONObject: payload,
            options: [.sortedKeys]
        )
        FileHandle.standardOutput.write(data)
    }
}
'''


@unittest.skipUnless(shutil.which("swiftc"), "swiftc is required")
class SceneResolvedMaterialPassEncoderTests(unittest.TestCase):
    def test_program_is_prepared_and_encoded_atomically(self) -> None:
        with tempfile.TemporaryDirectory(
            prefix="mwx-resolved-material-pass-"
        ) as directory:
            root = Path(directory)
            support = root / "Support.swift"
            harness = root / "Harness.swift"
            binary = root / "resolved-material-pass-test"
            support.write_text(SUPPORT, encoding="utf-8")
            harness.write_text(HARNESS, encoding="utf-8")
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
                    str(support),
                    *(str(path) for path in SWIFT_SOURCES),
                    str(harness),
                    "-framework",
                    "Metal",
                    "-framework",
                    "CoreGraphics",
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
            self.assertEqual(compilation.returncode, 0, compilation.stderr)
            completed = subprocess.run(
                [str(binary)],
                cwd=REPOSITORY_ROOT,
                env=environment,
                capture_output=True,
                text=True,
            )
            self.assertEqual(completed.returncode, 0, completed.stderr)
        payload = json.loads(completed.stdout)
        results = payload["results"]
        if not results["metalAvailable"]:
            self.skipTest("Metal is unavailable")
        self.assertEqual(
            [name for name, passed in results.items() if not passed],
            [],
            payload,
        )


if __name__ == "__main__":
    unittest.main()
