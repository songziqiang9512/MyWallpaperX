#!/usr/bin/env python3

"""Exact ordered signal/color composition across shared shader owners."""

from __future__ import annotations

import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
SCENE_ROOT = REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene"
sys.path.insert(0, str(REPOSITORY_ROOT / "script"))

from scene_shader_compiler_artifact import request_cache_key  # noqa: E402
from scene_shader_compiler_color_transfer_contract import (  # noqa: E402
    IndependentSignalContractFailure,
    parse_expected_transfer,
    prepare_independent_signal_contract,
)
from scene_swift_source_sets import scene_swift_sources  # noqa: E402
from script.tests import test_scene_shader_compiler_harness as compiler_support  # noqa: E402


SWIFT_SOURCES = [
    *scene_swift_sources("authored_shader_frontend_core"),
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Compilation/Material/SceneResolvedMaterialGenericShaderProgramArtifact.swift",
    *scene_swift_sources("generic_shader_compiler_preparation_implementation"),
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Compilation/Material/SceneResolvedMaterialGenericShaderRouteProfile.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Compilation/Material/SceneResolvedMaterialGenericShaderRouteAuthority.swift",
]


HARNESS = r'''
import CryptoKit
import Foundation

private struct Output: Codable {
    let renamedPositive: Bool
    let unseenPositive: Bool
    let implicitSampleRejected: Bool
    let reversedRolesRejected: Bool
    let wrongAlphaRejected: Bool
    let wrongFactorRejected: Bool
    let extraOutputRejected: Bool
    let controlFlowRejected: Bool
    let extraSampleRejected: Bool
    let sameSlotRejected: Bool
    let builderAccepted: Bool
    let colorBoundaryInserted: Bool
    let signalLeftRaw: Bool
    let outputBoundaryInserted: Bool
    let compilerImplicitSampleRejected: Bool
    let compilerReversedCarrierRejected: Bool
    let compilerExtraOutputRejected: Bool
    let compilerControlFlowRejected: Bool
    let decoderAccepted: Bool
    let decoderReversedOrderRejected: Bool
    let decoderWrongExpectedRejected: Bool
    let expectedEncodingOrdered: Bool
    let profile: String
    let route: String
    let rollback: String
    let externalProviderRejected: Bool
    let scalarOutputRejected: Bool
    let wrongGraphRoleRejected: Bool
    let twoGraphTargetsAccepted: Bool
    let extraSamplerRejected: Bool
}

private func source(
    signalSlot: Int = 6,
    colorSlot: Int = 2,
    mode: Int = 7,
    signalName: String = "pulseValue",
    colorName: String = "canvasValue",
    blendSignal: String? = nil,
    alpha: String? = nil,
    factor: String? = nil,
    output: String? = nil,
    prefix: String = "",
    suffix: String = ""
) -> String {
    let blendSignal = blendSignal ?? signalName
    let alpha = alpha ?? "\(colorName).a = saturate(\(colorName).a + \(signalName).a);"
    let factor = factor ?? "\(signalName).a"
    let output = output ?? "gl_FragColor = \(colorName);"
    return """
uniform sampler2D g_Texture\(signalSlot);
uniform sampler2D g_Texture\(colorSlot);
varying vec2 v_TexCoord;
void main() {
    \(prefix)
    vec4 \(signalName) = texSample2D(g_Texture\(signalSlot), v_TexCoord);
    vec4 \(colorName) = texSample2D(g_Texture\(colorSlot), v_TexCoord);
    \(colorName).rgb = ApplyBlending(\(mode), \(colorName).rgb, \(blendSignal).rgb, \(factor));
    \(alpha)
    \(output)
    \(suffix)
}
"""
}

private func transfer(_ source: String) -> SceneShaderColorTransfer {
    SceneAuthoredShaderColorTransferAnalyzer.analyze(fragmentSource: source)
}

private let authored = source()
private let msl = """
#include <metal_stdlib>
using namespace metal;
struct Output { float4 mwxFragColor [[color(0)]]; };
fragment Output mwxGenericFragment() {
    Output out = {};
    float4 translatedPulse = g_Texture6.sample(g_Texture6Smplr, uv);
    float4 translatedCanvas = g_Texture2.sample(g_Texture2Smplr, uv);
    translatedCanvas.xyz = translatedCanvas.xyz + translatedPulse.xyz * translatedPulse.w;
    translatedCanvas.w = clamp(translatedCanvas.w + translatedPulse.w, 0.0, 1.0);
    out.mwxFragColor = translatedCanvas;
    return out;
}
"""

private func prepared(_ metal: String) -> (
    msl: String,
    transfer: SceneGenericShaderProgramArtifact.Program.ColorTransfer
)? {
    try? SceneGenericShaderArtifactBuilder.prepareColorTransfer(
        msl: metal,
        authoredSource: authored
    )
}

private func artifact(
    source: String,
    slots: [Int]
) -> SceneGenericShaderProgramArtifact {
    SceneGenericShaderProgramArtifact(
        backendID: "glslang-spirv-cross-msl-v2",
        requestKey: String(repeating: "b", count: 64),
        program: .init(
            metalSource: source,
            metalSourceSHA256: SHA256.hash(data: Data(source.utf8))
                .map { String(format: "%02x", $0) }.joined(),
            vertexFunctionName: "mwxGenericVertex",
            fragmentFunctionName: "mwxGenericFragment",
            uniformBufferIndex: 8,
            uniformLayout: .init(fields: [
                .init(name: "mwxRenderSize", authoredName: "mwxRenderSize",
                      type: "float2", offset: 0),
                .init(name: "mwxTexture2Transform0",
                      authoredName: "mwxTexture2Transform0",
                      type: "float4", offset: 16),
                .init(name: "mwxTexture2Transform1",
                      authoredName: "mwxTexture2Transform1",
                      type: "float4", offset: 32),
                .init(name: "mwxTexture6Transform0",
                      authoredName: "mwxTexture6Transform0",
                      type: "float4", offset: 48),
                .init(name: "mwxTexture6Transform1",
                      authoredName: "mwxTexture6Transform1",
                      type: "float4", offset: 64),
            ], byteSize: 80),
            textureBindings: [
                .init(name: "g_Texture2", slot: 2, channelUse: "wholeVector"),
                .init(name: "g_Texture6", slot: 6, channelUse: "wholeVector"),
            ],
            staticLoopWork: 0,
            premultipliedColorInputSlots: [],
            colorTransfer: .init(
                kind: "independent-alpha-signal-compositing",
                slot: nil,
                slots: slots
            ),
            fragmentOutputChannelUse: "unproven"
        )
    )
}

private func decoded(
    _ artifact: SceneGenericShaderProgramArtifact,
    expected: SceneShaderColorTransfer
) -> SceneAuthoredShaderProgram? {
    artifact.makeProgram(
        expectedKey: String(repeating: "b", count: 64),
        expectedColorTransfer: expected,
        expectedFragmentOutputChannelUse: .unproven
    )
}

private func profile(
    transfer: SceneShaderColorTransfer = .independentAlphaSignalCompositing(
        signalSlot: 6, colorSlot: 2
    ),
    external: Bool = false,
    scalarOutput: Bool = false,
    graphTextureSlots: Set<Int> = [6],
    hasOnlyGraphInputSampler: Bool = true
) -> SceneGenericShaderCapabilityProfile {
    SceneGenericShaderCapabilityProfile(
        colorTransfer: transfer,
        alphaAttenuationSourceSlot: nil,
        colorBlendSourceSlot: nil,
        conditionalStraightUnionSourceSlot: nil,
        singleSamplerAlphaMutationSourceSlot: nil,
        sameSlotChannelReconstructionSourceSlot: nil,
        auxiliaryRGBMixSourceSlot: nil,
        normalizedSampleSumSourceSlot: nil,
        alphaWeightedSampleAverageSourceSlot: nil,
        preservedAlphaRGBFilterSourceSlot: nil,
        preservedAlphaRGBFilterTextureSlots: [],
        previousBlurredCompositeBlurredSlot: nil,
        previousBlurredCompositePreviousSlot: nil,
        hasExternalProviderTexture: external,
        producesScalarRedOutput: scalarOutput,
        isSourceIndependentPremultipliedOutput: false,
        graphTextureSlots: graphTextureSlots,
        graphInputTextureSlots: [6, 2],
        r8TextureSlots: [],
        hasDefaultedOpacityMaskSampler: false,
        hasOnlyGraphInputSampler: hasOnlyGraphInputSampler,
        hasStageScopedUniformBindings: false,
        hasStereoAudioSpectrumArrays: false
    )
}

@main
private enum Harness {
    static func main() throws {
        let built = prepared(msl)
        let accepted = built.map { artifact(source: $0.msl, slots: [6, 2]) }
        let reversed = built.map { artifact(source: $0.msl, slots: [2, 6]) }
        let selected = profile()
        let expected = SceneGenericShaderExpectedColorTransfer(
            .independentAlphaSignalCompositing(signalSlot: 6, colorSlot: 2)
        )!
        let encoded = try JSONSerialization.jsonObject(
            with: JSONEncoder().encode(expected)
        ) as! [String: Any]

        let implicitMetal = msl.replacingOccurrences(
            of: "float4 translatedPulse = g_Texture6.sample(g_Texture6Smplr, uv);",
            with: "float4 translatedPulse = float4(g_Texture6.sample(g_Texture6Smplr, uv));"
        )
        let reversedCarrier = msl.replacingOccurrences(
            of: "out.mwxFragColor = translatedCanvas;",
            with: "out.mwxFragColor = translatedPulse;"
        )
        let extraOutput = msl.replacingOccurrences(
            of: "out.mwxFragColor = translatedCanvas;",
            with: "out.mwxFragColor = translatedCanvas;\n    out.mwxFragColor.w = 1.0;"
        )
        let controlled = msl.replacingOccurrences(
            of: "translatedCanvas.xyz =",
            with: "if (translatedPulse.w > 0.0) translatedCanvas.xyz ="
        )

        let output = Output(
            renamedPositive: transfer(authored) == .independentAlphaSignalCompositing(
                signalSlot: 6, colorSlot: 2
            ),
            unseenPositive: transfer(source(
                signalSlot: 1, colorSlot: 5, mode: 32,
                signalName: "quietCarrier", colorName: "surfaceCarrier"
            )) == .independentAlphaSignalCompositing(signalSlot: 1, colorSlot: 5),
            implicitSampleRejected: transfer(source(prefix:
                "vec4 hiddenValue = vec4(0.0);"
            )) == .unresolved,
            reversedRolesRejected: transfer(source(
                blendSignal: "canvasValue"
            )) == .unresolved,
            wrongAlphaRejected: transfer(source(alpha:
                "canvasValue.a = saturate(canvasValue.a - pulseValue.a);"
            )) == .unresolved,
            wrongFactorRejected: transfer(source(factor:
                "canvasValue.a"
            )) == .unresolved,
            extraOutputRejected: transfer(source(suffix:
                "gl_FragColor = pulseValue;"
            )) == .unresolved,
            controlFlowRejected: transfer(source(prefix:
                "if (v_TexCoord.x < 0.0) { discard; }"
            )) == .unresolved,
            extraSampleRejected: transfer(source(prefix:
                "vec4 extraValue = texSample2D(g_Texture6, v_TexCoord * 0.5);"
            )) == .unresolved,
            sameSlotRejected: transfer(source(
                signalSlot: 2, colorSlot: 2
            )) == .unresolved,
            builderAccepted: built?.transfer.kind
                == "independent-alpha-signal-compositing"
                && built?.transfer.slots == [6, 2],
            colorBoundaryInserted: built?.msl.contains(
                "mwxGenericSignalCompositeUnpremultiply(g_Texture2.sample"
            ) == true,
            signalLeftRaw: built?.msl.contains(
                "translatedPulse = g_Texture6.sample"
            ) == true,
            outputBoundaryInserted: built?.msl.contains(
                "out.mwxFragColor = mwxGenericSignalCompositePremultiply(translatedCanvas);"
            ) == true,
            compilerImplicitSampleRejected: prepared(implicitMetal) == nil,
            compilerReversedCarrierRejected: prepared(reversedCarrier) == nil,
            compilerExtraOutputRejected: prepared(extraOutput) == nil,
            compilerControlFlowRejected: prepared(controlled) == nil,
            decoderAccepted: accepted.flatMap {
                decoded($0, expected: .independentAlphaSignalCompositing(
                    signalSlot: 6, colorSlot: 2
                ))
            } != nil,
            decoderReversedOrderRejected: reversed.flatMap {
                decoded($0, expected: .independentAlphaSignalCompositing(
                    signalSlot: 6, colorSlot: 2
                ))
            } == nil,
            decoderWrongExpectedRejected: accepted.flatMap {
                decoded($0, expected: .independentAlphaSignalCompositing(
                    signalSlot: 2, colorSlot: 6
                ))
            } == nil,
            expectedEncodingOrdered: encoded["kind"] as? String
                == "independent-alpha-signal-compositing"
                && encoded["slots"] as? [Int] == [6, 2]
                && encoded["slot"] == nil,
            profile: selected.rawValue,
            route: selected.defaultRouteState.rawValue,
            rollback: selected.validatedRollbackOwner.rawValue,
            externalProviderRejected: profile(external: true) != selected,
            scalarOutputRejected: profile(scalarOutput: true) != selected,
            wrongGraphRoleRejected: profile(graphTextureSlots: [2]) != selected,
            twoGraphTargetsAccepted:
                profile(graphTextureSlots: [6, 2]) == selected,
            extraSamplerRejected:
                profile(hasOnlyGraphInputSampler: false) != selected
        )
        print(String(data: try JSONEncoder().encode(output), encoding: .utf8)!)
    }
}
'''


SIGNAL_BRIDGE_HARNESS = r'''
private func bridgePublication(
    _ texture: MTLTexture, identity: Graph.TextureIdentity,
    content: SceneTextureContent, generation: UInt64
) -> SceneFrameTextureResource {
    let purpose: SceneTextureLoadPurpose = content.isColorContent
        ? (content == .color(.resolved(.straightAlpha)) ? .straightAlbedo : .premultipliedColor)
        : .preservedChannels
    let publication = SceneTextureProviderPublication(requestIdentity: .graph(identity),
        candidate: .init(texture: texture,
            identity: .provider(.graph(allocationGeneration: generation, physicalToken: "bridge-\(identity.name ?? "color")")),
            generation: .provider(contentGeneration: generation), purpose: purpose, content: content,
            physicalSize: CGSize(width: extent.width, height: extent.height),
            mappedSize: CGSize(width: extent.width, height: extent.height),
            uvTransform: .identity, sampling: .directImageFallback), contentGeneration: generation)
    return .init(publication: publication, resourceGeneration: generation)
}

private func bridgeTemplate(_ name: String) -> Template {
    let fragment: String
    let isDataPrevious = name == "dataPrevious"
    let previous = isDataPrevious ? "// {\"material\":\"previous\",\"mode\":\"rgbmask\"}" : ""
    if name == "producer" { fragment = """
    varying vec2 v_TexCoord;
    uniform sampler2D g_Texture0;
    void main() {
        vec4 carrier = texSample2D(g_Texture0, v_TexCoord);
        carrier.rgb *= carrier.a;
        carrier.a = 1.0;
        gl_FragColor = carrier;
        gl_FragColor.a *= 0.25;
    }
    """ } else if name == "raw" { fragment = """
    varying vec2 v_TexCoord;
    uniform sampler2D g_Texture0;
    void main() { gl_FragColor = texSample2D(g_Texture0, v_TexCoord); }
    """ } else if name == "composer" { fragment = """
    varying vec2 v_TexCoord;
    uniform sampler2D g_Texture0;
    uniform sampler2D g_Texture1;
    vec3 ApplyBlending(const int mode, in vec3 base, in vec3 blend, in float opacity) {
        return base + blend * opacity;
    }
    void main() {
        vec4 impulse = texSample2D(g_Texture0, v_TexCoord);
        vec4 canvas = texSample2D(g_Texture1, v_TexCoord);
        canvas.rgb = ApplyBlending(7, canvas.rgb, impulse.rgb, impulse.a);
        canvas.a = saturate(canvas.a + impulse.a);
        gl_FragColor = canvas;
    }
    """ } else { fragment = """
    varying vec2 v_TexCoord;
    uniform sampler2D g_Texture0; \(previous)
    void main() {
        float scalar = texSample2D(g_Texture0, v_TexCoord).r;
        gl_FragColor = vec4(scalar, scalar, scalar, 1.0);
    }
    """ }
    let contract = shaderContract(nodeIndex: 41, pass: false, fragmentOverride: fragment)
    var slots = Array<Template.TextureSlot?>(repeating: nil, count: 8)
    if !isDataPrevious {
        slots[0] = .init(index: 0, candidates: [.init(reference: .graph(first), provenance: .explicitBinding)])
    }
    if name == "composer" {
        slots[1] = .init(index: 1, candidates: [.init(reference: .graph(second), provenance: .explicitBinding)])
    }
    return Template.validated(textureSlots: slots, combos: [], uniformDeclarations: [],
        renderState: SceneMaterialRenderState.compile(blending: "normal", depthTest: "disabled",
            depthWrite: "disabled", cullMode: "nocull", alphaWriting: nil)!,
        graphRole: .init(effectInput: isDataPrevious ? .effectOutput : .framebuffer,
            effectOutput: .effectOutput, nodeTarget: .effectOutput,
            bindings: name == "composer" ? [.init(slot: 0, texture: .framebuffer), .init(slot: 1, texture: .framebuffer)]
                : isDataPrevious ? [] : [.init(slot: 0, texture: .framebuffer)]),
        effectContext: .init(key: isDataPrevious ? chainedSecondEffect : effect,
            input: isDataPrevious ? chainedFirstOutput : first), shaderContract: contract,
        diagnosticProvenance: .init(nodeIndex: 41, authoredShaderPath: contract.identity,
            contractIdentity: contract.identity, contractCanonicalSHA256: contract.canonicalSHA256,
            textureSources: [], uniformSources: []))!
}

private func runSignalBridge(_ name: String, device: MTLDevice, queue: MTLCommandQueue) -> [String: Any] {
    let template = bridgeTemplate(name)
    let isScalar = name.hasPrefix("scalar")
    let isDataPrevious = name == "dataPrevious"
    let rawData = isScalar || isDataPrevious
    let ingress = isDataPrevious ? chainedFirstOutput : first
    guard case let .success(cache) = SceneResolvedMaterialVariantCache.launchValidated(template: template,
        maximumVariantCount: 16), let encoder = SceneResolvedMaterialPassEncoder(device: device) else {
        return ["failure": "bridge-setup"]
    }
    let initialContent: SceneTextureContent = isScalar ? .scalarRedUnorm : isDataPrevious ? .data
        : name == "composer" || name == "raw" ? .color(.resolved(.independentAlphaSignal))
        : .color(.resolved(.premultipliedAlpha))
    let formats: [Graph.TextureIdentity: SceneShaderTextureFormat] = isScalar ? [first: .r8] : [:]
    let contents: [Graph.TextureIdentity: SceneTextureContent] = name == "composer"
        ? [ingress: initialContent, second: .color(.resolved(.premultipliedAlpha))] : [ingress: initialContent]
    let launch = cache.precompileLaunchEnvelope(implicitFramebufferIdentity: ingress,
        outputIsRGBA8Unorm: true, graphTextureFormatFacts: formats, graphTextureContentFacts: contents)
    guard case .success = launch else {
        return ["failure": "bridge-precompile", "diagnostic": String(describing: launch)]
    }
    var rows: [[String: Any]] = [], key: String?, compilationCount = 0, libraryCount = 0
    let representations: [SceneShaderColorRepresentation] = rawData ? [.opaque]
        : name == "raw" ? [.independentAlphaSignal, .straightAlpha, .premultipliedAlpha]
        : [.straightAlpha, .premultipliedAlpha]
    for (offset, representation) in representations.enumerated() {
        let index = UInt64(offset + 1)
        let source: MTLTexture
        if isScalar {
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .r8Unorm,
                width: extent.width, height: extent.height, mipmapped: false)
            descriptor.storageMode = .shared; descriptor.usage = [.shaderRead, .renderTarget]
            source = device.makeTexture(descriptor: descriptor)!
            [UInt8](repeating: 64, count: extent.width * extent.height).withUnsafeBytes {
                source.replace(region: MTLRegionMake2D(0, 0, extent.width, extent.height), mipmapLevel: 0,
                    withBytes: $0.baseAddress!, bytesPerRow: extent.width)
            }
        } else {
            let color: [UInt8] = name == "raw"
                ? (representation == .straightAlpha ? [51, 102, 204, 0]
                    : representation == .independentAlphaSignal ? [26, 51, 102, 64] : [26, 51, 102, 128])
                : isDataPrevious ? [26, 51, 102, 0] : name == "composer" ? [26, 51, 204, 64]
                : representation == .straightAlpha ? [51, 102, 204, 128] : [26, 51, 102, 128]
            source = makeSource(device, width: extent.width, height: extent.height,
                usage: [.shaderRead, .renderTarget], bgra: color)
        }
        var resources = [ingress: bridgePublication(source, identity: ingress,
            content: name == "producer" || name == "raw" ? .color(.resolved(representation)) : initialContent,
            generation: index)]
        if name == "composer" {
            let color = makeSource(device, width: extent.width, height: extent.height,
                usage: [.shaderRead, .renderTarget],
                bgra: representation == .straightAlpha ? [26, 51, 102, 128] : [13, 26, 51, 128])
            resources[second] = bridgePublication(color, identity: second,
                content: .color(.resolved(representation)), generation: index)
        }
        guard let snapshot = frame(index).overlayingGraphResources(resources) else {
            return ["failure": "bridge-publication", "frames": rows]
        }
        let result = SceneResolvedMaterialProgramFinalizer.finalize(snapshot.finalizationInput(
            template: template, layerID: layerID, renderSize: CGSize(width: extent.width, height: extent.height),
            modelViewProjection: matrix_identity_float4x4, layerModelMatrix: matrix_identity_float4x4,
            effectOutputModelViewProjection: matrix_identity_float4x4,
            effectTextureProjectionMatrixInverse: matrix_identity_float4x4,
            implicitFramebufferIdentity: ingress), variantCache: cache)
        guard case let .success(program) = result else {
            return ["failure": "bridge-finalize", "diagnostic": String(describing: result), "frames": rows]
        }
        let target = makeSource(device, width: extent.width, height: extent.height,
            usage: [.shaderRead, .renderTarget], bgra: [0, 0, 0, 0])
        guard let prepared = encoder.prepare(program: program, target: target),
              let command = queue.makeCommandBuffer(), encoder.encode(prepared, commandBuffer: command),
              let read = appendReadback(target, commandBuffer: command) else {
            return ["failure": "bridge-encode", "frames": rows]
        }
        command.commit(); command.waitUntilCompleted()
        let mask = program.resolvedUniforms.first { $0.field.name == "mwxPremultipliedColorInputMask" }
            .map { $0.encodedValue.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) } } ?? 0
        if offset == 0 {
            key = program.preparedShader.cacheKey
            compilationCount = cache.counters.frontendCompilationCount
            libraryCount = encoder.metalLibraryCompilationAttemptCount
        }
        let colorSlot = name == "composer" ? 1 : 0
        let expectedMask: UInt32 = (rawData || representation == .straightAlpha
            || representation == .independentAlphaSignal ? 0 : 1 << UInt32(colorSlot))
            | (name == "composer" || representation == .independentAlphaSignal ? 256 : 0)
        let expectedPixel: [UInt8] = name == "raw"
            ? (representation == .straightAlpha ? [51, 102, 204, 0]
                : representation == .independentAlphaSignal ? [26, 51, 102, 64] : [52, 102, 203, 128])
            : name == "producer" ? [26, 51, 102, 64]
            : name == "composer" ? [24, 48, 115, 192]
            : isDataPrevious ? [102, 102, 102, 255] : [64, 64, 64, 255]
        let expectedRepresentation: SceneShaderColorRepresentation = name == "raw"
            ? (representation == .independentAlphaSignal ? .independentAlphaSignal : .straightAlpha)
            : name == "producer" ? .independentAlphaSignal
            : name == "composer" ? .premultipliedAlpha : .opaque
        let actualRepresentation: SceneShaderColorRepresentation? = switch program.outputContract {
        case let .color(contract): SceneResolvedMaterialAttachmentStorage.acceptedColorOutput(contract.fragmentOutput)
        default: nil
        }
        rows.append(["completed": command.status == .completed && command.error == nil,
            "maskUsesOnlyActualColor": mask == expectedMask,
            "exactColorRole": program.frontendProgram.colorBoundary?.colorInputSlots == (rawData ? [] : [colorSlot]),
            "actualOutputRepresentation": actualRepresentation == expectedRepresentation,
            "samePreparedProgram": key == program.preparedShader.cacheKey,
            "noRepresentationRecompile": compilationCount == cache.counters.frontendCompilationCount
                && libraryCount == encoder.metalLibraryCompilationAttemptCount,
            "dynamicSignalPassthroughRetained": name != "raw" || (
                program.frontendProgram.colorBoundary?.signalPassthroughSlot == 0
                && program.frontendProgram.colorTransfer == .passthrough(textureSlot: 0)
                && program.resolvedUniforms.contains { $0.field.name == "mwxPremultipliedColorInputMask" }),
            "authoredMathPreserved": matches(read.firstPixel, expectedPixel) && matches(read.lastPixel, expectedPixel),
            "pixel": read.firstPixel, "mask": mask])
    }
    return ["frames": rows]
}

@main private enum SignalBridgeHarness {
    static func main() throws {
        setenv("MWX_SCENE_GENERIC_SHADER_ROUTE", "disable-generic", 1)
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else {
            print("{\"metalAvailable\":false}"); return
        }
        var bridges: [String: Any] = [:]
        for name in ["producer", "composer", "scalar", "dataPrevious", "raw"] {
            bridges[name] = runSignalBridge(name, device: device, queue: queue)
        }
        print(String(decoding: try JSONSerialization.data(withJSONObject:
            ["metalAvailable": true, "bridges": bridges], options: [.sortedKeys]), as: UTF8.self))
    }
}
'''


class SceneIndependentSignalColorCarrierCompositingTests(unittest.TestCase):
    def test_prepared_signal_bridge_uses_actual_color_representation(self) -> None:
        from script.tests import test_scene_resolved_material_graph_executor as graph_gate

        harness = graph_gate.HARNESS.split("@main\nprivate enum Harness", 1)[0] + SIGNAL_BRIDGE_HARNESS
        compilation, completed = graph_gate.compile_lit_harness(graph_gate.SUPPORT, harness)
        self.assertEqual(compilation.returncode, 0, compilation.stderr)
        self.assertIsNotNone(completed)
        assert completed is not None
        self.assertEqual(completed.returncode, 0, completed.stderr)
        payload = json.loads(completed.stdout)
        if not payload["metalAvailable"]:
            self.skipTest("Metal is unavailable")
        self.assertEqual(set(payload["bridges"]), {"producer", "composer", "scalar", "dataPrevious", "raw"})
        for name, report in payload["bridges"].items():
            self.assertNotIn("failure", report, (name, report))
            self.assertEqual(len(report["frames"]), 1 if name in {"scalar", "dataPrevious"}
                else 3 if name == "raw" else 2, report)
            for row in report["frames"]:
                for assertion, passed in row.items():
                    if isinstance(passed, bool):
                        self.assertTrue(passed, (name, assertion, row))

    def test_swift_frontend_artifact_and_route_contract(self) -> None:
        with tempfile.TemporaryDirectory(
            prefix="mwx-signal-color-compositing-"
        ) as directory:
            executable = Path(directory) / "harness"
            harness = Path(directory) / "Harness.swift"
            harness.write_text(HARNESS, encoding="utf-8")
            completed = subprocess.run(
                [
                    "xcrun", "swiftc", "-O", "-o", str(executable),
                    *(str(path) for path in SWIFT_SOURCES), str(harness),
                ],
                cwd=REPOSITORY_ROOT,
                text=True,
                capture_output=True,
                check=False,
            )
            self.assertEqual(completed.returncode, 0, completed.stderr)
            run = subprocess.run(
                [str(executable)], cwd=REPOSITORY_ROOT,
                text=True, capture_output=True, check=False,
            )
            self.assertEqual(run.returncode, 0, run.stderr)
            result = json.loads(run.stdout)

        expected_true = {
            key for key, value in result.items() if isinstance(value, bool)
        }
        self.assertTrue(expected_true)
        for key in expected_true:
            self.assertTrue(result[key], key)
        self.assertEqual(
            result["profile"],
            "source-proven-graph-input-independent-signal-compositing",
        )
        self.assertEqual(result["route"], "generic-only")
        self.assertEqual(result["rollback"], "bounded-frontend")

    def test_external_contract_preserves_order_and_rejects_drift(self) -> None:
        expected = {
            "kind": "independent-alpha-signal-compositing", "slots": [6, 2],
        }
        self.assertEqual(parse_expected_transfer(expected), expected)
        bindings = [
            {"name": "g_Texture2", "slot": 2},
            {"name": "g_Texture6", "slot": 6},
        ]
        source = """
#include <metal_stdlib>
using namespace metal;
struct Output { float4 mwxFragColor [[color(0)]]; };
fragment Output mwxGenericFragment() {
    Output out = {};
    float4 firstCarrier = g_Texture6.sample(sampler(), uv);
    float4 secondCarrier = g_Texture2.sample(sampler(), uv);
    secondCarrier.xyz += firstCarrier.xyz * firstCarrier.w;
    secondCarrier.w = clamp(secondCarrier.w + firstCarrier.w, 0.0, 1.0);
    out.mwxFragColor = secondCarrier;
    return out;
}
"""
        prepared, transfer = prepare_independent_signal_contract(
            source, expected, bindings,
        )
        self.assertEqual(transfer, expected)
        self.assertIn(
            "mwxSignalCompositeUnpremultiply(g_Texture2.sample", prepared
        )
        self.assertIn("firstCarrier = g_Texture6.sample", prepared)
        self.assertIn(
            "out.mwxFragColor = mwxSignalCompositePremultiply(secondCarrier);",
            prepared,
        )

        reflection = {
            "types": {"_1": {"members": [
                {"name": "mwxRenderSize", "type": "vec2", "offset": 0},
            ]}},
            "ubos": [{
                "type": "_1", "block_size": 8, "set": 0, "binding": 8,
            }],
            "textures": [
                {"name": "g_Texture2", "binding": 2},
                {"name": "g_Texture6", "binding": 6},
            ],
        }
        uniform = "struct MWXUniforms { float2 mwxRenderSize; };"
        vertex_msl = "\n".join([
            "#include <metal_stdlib>", "using namespace metal;", uniform,
            "vertex float4 mwxGenericVertex(constant MWXUniforms& uniforms "
            "[[buffer(8)]]) { return float4(uniforms.mwxRenderSize, 0.0, 1.0); }",
        ])
        fragment_msl = source.replace(
            "struct Output", uniform + "\nstruct Output"
        ).replace(
            "fragment Output mwxGenericFragment()",
            "fragment Output mwxGenericFragment(constant MWXUniforms& uniforms "
            "[[buffer(8)]])",
        )
        arguments = compiler_support.artifact_arguments(
            reflection, vertex_msl, fragment_msl, "c"
        )
        arguments["expected_color_transfer"] = expected
        artifact = compiler_support.build_program_artifact(**arguments)
        self.assertEqual(artifact["program"]["colorTransfer"], expected)
        self.assertIn(
            "mwxSignalCompositeUnpremultiply(g_Texture2.sample",
            artifact["program"]["metalSource"],
        )

        reverse = {**expected, "slots": [2, 6]}
        request = {
            "schemaVersion": 6,
            "outputSemantics": "color",
            "premultipliedColorInputSlots": [],
            "stages": [
                {"stage": "vertex", "source": "void main() {}"},
                {"stage": "fragment", "source": "void main() {}"},
            ],
            "expectedColorTransfer": expected,
        }
        reverse_request = {**request, "expectedColorTransfer": reverse}
        self.assertNotEqual(
            request_cache_key(request), request_cache_key(reverse_request)
        )

        malformed = [
            {"kind": expected["kind"], "slots": [6, 6]},
            {"kind": expected["kind"], "slots": [6]},
            {"kind": expected["kind"], "slots": [6, 2], "slot": 6},
            {"kind": "unknown", "slots": [6, 2]},
        ]
        for value in malformed:
            with self.subTest(value=value):
                with self.assertRaises(IndependentSignalContractFailure):
                    parse_expected_transfer(value)

        drift = {
            "implicit-sample": source.replace(
                "float4 firstCarrier = g_Texture6.sample(sampler(), uv);",
                "float4 firstCarrier = float4(g_Texture6.sample(sampler(), uv));",
            ),
            "reversed-carrier": source.replace(
                "out.mwxFragColor = secondCarrier;",
                "out.mwxFragColor = firstCarrier;",
            ),
            "extra-output": source.replace(
                "out.mwxFragColor = secondCarrier;",
                "out.mwxFragColor = secondCarrier;\n    out.mwxFragColor.w = 1.0;",
            ),
            "control-flow": source.replace(
                "secondCarrier.xyz +=",
                "if (firstCarrier.w > 0.0) secondCarrier.xyz +=",
            ),
            "extra-sample": source.replace(
                "secondCarrier.xyz +=",
                "float4 extraCarrier = g_Texture6.sample(sampler(), uv);\n"
                "    secondCarrier.xyz +=",
            ),
        }
        for name, value in drift.items():
            with self.subTest(name=name):
                with self.assertRaises(IndependentSignalContractFailure):
                    prepare_independent_signal_contract(value, expected, bindings)
        with self.assertRaises(IndependentSignalContractFailure):
            prepare_independent_signal_contract(source, reverse, bindings)


if __name__ == "__main__":
    unittest.main()
