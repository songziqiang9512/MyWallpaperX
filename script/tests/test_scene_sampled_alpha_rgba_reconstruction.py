#!/usr/bin/env python3

"""Same-slot sampled-alpha RGBA reconstruction stays on one shared path."""

from __future__ import annotations

import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
SCENE_ROOT = REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene"
sys.path.insert(0, str(REPOSITORY_ROOT / "script"))

from scene_swift_source_sets import scene_swift_sources  # noqa: E402


SWIFT_SOURCES = [
    *scene_swift_sources("authored_shader_frontend_core"),
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Compilation/Material/SceneResolvedMaterialGenericShaderProgramArtifact.swift",
    *scene_swift_sources("generic_shader_compiler_preparation_implementation"),
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Compilation/Material/SceneResolvedMaterialGenericShaderRouteProfile.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Compilation/Material/SceneResolvedMaterialGenericShaderRouteAuthority.swift",
]

CONSTRUCTOR_SOURCE = """uniform sampler2D g_Texture0;
uniform sampler2D g_Texture1;
varying vec4 v_Coordinate;
vec2 bend(vec2 uv, float amount) {
    vec2 shifted = uv;
    return uv + vec2(amount * shifted.y * shifted.y, 0.0);
}
void main() {
    float red = texSample2D(g_Texture0, bend(v_Coordinate.xy, 0.4)).r;
    float green = texSample2D(g_Texture0, bend(v_Coordinate.xy, 0.0)).g;
    float blue = texSample2D(g_Texture0, bend(v_Coordinate.xy, -0.4)).b;
    float alpha = texSample2D(g_Texture0, bend(v_Coordinate.xy, 0.2)).a;
    float mask = texSample2D(g_Texture1, v_Coordinate.xy).r;
    gl_FragColor = lerp(texSample2D(g_Texture0, v_Coordinate.xy), vec4(red, green, blue, alpha), mask);
}
"""

# Captured from a real Workshop effect that the previous analyzer left on the
# unresolved color contract: a helper that writes its `uv` parameter and
# reassigns `uv` before returning, plus a chromatic-aberration offset spread
# across the four scalar lanes. The scalar vector broadcast in the captured
# source is written as an explicit constructor because the strict offline
# glslang invocation does not run the app's compatibility prelude.
CHROMATIC_ABERRATION_SOURCE = """uniform sampler2D g_Texture0;
uniform sampler2D g_Texture1;
uniform float u_aberration;
varying vec4 v_TexCoord;
vec2 computeUV(vec2 uv, float amount){
    uv = (uv - 0.5) * 2.0;
    vec2 radial = vec2(0.0);
    float focusLength = 1.0 / max(length(uv), 0.0001);
    radial += uv * (1.0 + amount * pow(length(uv), 2.0)) * focusLength;
    return (radial / 2.0) + 0.5;
}
void main() {
    float offset = u_aberration * 0.1;
    float red = texSample2D(g_Texture0, computeUV(v_TexCoord.xy, offset)).r;
    float green = texSample2D(g_Texture0, computeUV(v_TexCoord.xy, 0.0)).g;
    float blue = texSample2D(g_Texture0, computeUV(v_TexCoord.xy, -offset)).b;
    float alpha = texSample2D(g_Texture0, computeUV(v_TexCoord.xy, 0.0)).a;
    float mask = texSample2D(g_Texture1, v_TexCoord.xy).r;
    gl_FragColor = lerp(texSample2D(g_Texture0, v_TexCoord.xy), vec4(red, green, blue, alpha), mask);
}
"""


HARNESS = r'''
import Foundation
import Metal

private struct Output: Codable {
    let transfer: String
    let sourceSlot: Int?
    let auxiliarySlots: [Int]?
    let preservesSnapshotAlpha: Bool?
    let totalSamples: Int?
    let renamedAccepted: Bool
    let loweringAccepted: Bool
    let artifactTransfer: String?
    let sourceUnpremultipliedCount: Int
    let dataUnpremultipliedCount: Int
    let outputPremultiplied: Bool
    let routeProfile: String
    let routeState: String
    let rollbackOwner: String
    let defaultPermitsBoundedFrontend: Bool
    let defaultFallbackOutcome: String
    let disablePermitsBoundedFrontend: Bool
    let disableFallbackOutcome: String
    let wrongSlotRejected: Bool
    let wrongProjectionRejected: Bool
    let alphaOverwriteRejected: Bool
    let hiddenSourceRejected: Bool
    let endpointDriftRejected: Bool
    let compilerAlphaLaneDriftRejected: Bool
    let compilerProjectionDriftRejected: Bool
    let compilerTemporaryEscapeRejected: Bool
    let compilerHiddenSourceRejected: Bool
    let compilerEndpointDriftRejected: Bool
    let realCompilerLoweringAccepted: Bool
    let realCompilerSourceUnpremultipliedCount: Int
    let renamedCompilerAccepted: Bool
    let renamedCompilerDriftRejected: Bool
    let snapshotAlphaWithAuxiliaryRGAccepted: Bool
    let constructorChecks: [String: Bool]
    let constructorSourceUnpremultipliedCount: Int
    let constructorOutputPremultiplied: Bool
    let constructorPixels: [[Float]]
    let chromaticChecks: [String: Bool]
}

private func constructorPixels(_ source: String?) throws -> [[Float]] {
    guard let source else { return [] }
    guard let device = MTLCreateSystemDefaultDevice(),
          let queue = device.makeCommandQueue() else {
        throw NSError(domain: "ConstructorGPU", code: 1)
    }
    let vertex = """
    struct ConstructorProbeVertexOutput {
        float4 position [[position]];
        float4 coordinate [[user(locn0)]];
    };
    vertex ConstructorProbeVertexOutput constructorProbeVertex(uint id [[vertex_id]]) {
        float2 positions[3] = {float2(-1.0, -1.0), float2(3.0, -1.0), float2(-1.0, 3.0)};
        ConstructorProbeVertexOutput out;
        out.position = float4(positions[id], 0.0, 1.0);
        out.coordinate = float4(0.5, 0.5, 0.0, 0.0);
        return out;
    }
    """
    let library = try device.makeLibrary(source: source + "\n" + vertex, options: nil)
    let pipelineDescriptor = MTLRenderPipelineDescriptor()
    pipelineDescriptor.vertexFunction = library.makeFunction(name: "constructorProbeVertex")
    pipelineDescriptor.fragmentFunction = library.makeFunction(name: "mwxGenericFragment")
    pipelineDescriptor.colorAttachments[0].pixelFormat = .rgba32Float
    let pipeline = try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
    func texture(width: Int) throws -> MTLTexture {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba32Float, width: width, height: 1, mipmapped: false
        )
        descriptor.storageMode = .shared
        descriptor.usage = [.shaderRead, .renderTarget]
        guard let texture = device.makeTexture(descriptor: descriptor) else {
            throw NSError(domain: "ConstructorGPU", code: 2)
        }
        return texture
    }
    let color = try texture(width: 64)
    let mask = try texture(width: 1)
    let output = try texture(width: 1)
    let samplerDescriptor = MTLSamplerDescriptor()
    samplerDescriptor.minFilter = .nearest
    samplerDescriptor.magFilter = .nearest
    samplerDescriptor.sAddressMode = .clampToEdge
    samplerDescriptor.tAddressMode = .clampToEdge
    guard let sampler = device.makeSamplerState(descriptor: samplerDescriptor) else {
        throw NSError(domain: "ConstructorGPU", code: 3)
    }
    var colors = Array(repeating: Float(0), count: 64 * 4)
    func setColor(_ index: Int, _ rgba: [Float]) {
        colors.replaceSubrange(index * 4..<(index + 1) * 4, with: rgba)
    }
    setColor(32, [0.05, 0.3, 0.1, 0.5])
    setColor(38, [0.2, 0.1, 0.05, 0.25])
    setColor(25, [0.3, 0.15, 0.675, 0.75])
    setColor(35, [0.06, 0.02, 0.12, 0.2])
    var pixels: [[Float]] = []
    for (index, weight) in [Float(0), 0.5, 1, 1, 1].enumerated() {
        if index == 3 { setColor(38, [0, 0, 0, 0]) }
        if index == 4 { setColor(35, [0, 0, 0, 0]) }
        colors.withUnsafeBytes {
            color.replace(region: MTLRegionMake2D(0, 0, 64, 1), mipmapLevel: 0,
                          withBytes: $0.baseAddress!, bytesPerRow: 64 * 16)
        }
        [weight, Float(0), 0, 0.1].withUnsafeBytes {
            mask.replace(region: MTLRegionMake2D(0, 0, 1, 1), mipmapLevel: 0,
                         withBytes: $0.baseAddress!, bytesPerRow: 16)
        }
        guard let command = queue.makeCommandBuffer() else {
            throw NSError(domain: "ConstructorGPU", code: 4)
        }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = output
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        guard let encoder = command.makeRenderCommandEncoder(descriptor: pass) else {
            throw NSError(domain: "ConstructorGPU", code: 5)
        }
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentTexture(color, index: 0)
        encoder.setFragmentTexture(mask, index: 1)
        encoder.setFragmentSamplerState(sampler, index: 0)
        encoder.setFragmentSamplerState(sampler, index: 1)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
        command.commit()
        command.waitUntilCompleted()
        guard command.status == .completed, command.error == nil else {
            throw command.error ?? NSError(domain: "ConstructorGPU", code: 6)
        }
        var pixel = Array(repeating: Float(0), count: 4)
        pixel.withUnsafeMutableBytes {
            output.getBytes($0.baseAddress!, bytesPerRow: 16,
                            from: MTLRegionMake2D(0, 0, 1, 1), mipmapLevel: 0)
        }
        pixels.append(pixel)
    }
    return pixels
}

@main
private enum SampledAlphaRGBAReconstructionHarness {
    static func main() throws {
        let authored = [
            "uniform sampler2D g_Texture0;",
            "uniform sampler2D g_Texture1;",
            "uniform sampler2D g_Texture2;",
            "varying vec4 v_Coordinate;",
            "void main() {",
            "    vec4 reconstructed;",
            "    float mask = texSample2D(g_Texture2, v_Coordinate.zw).r;",
            "    vec4 snapshot = texSample2D(g_Texture0, v_Coordinate.xy);",
            "    reconstructed.ga = texSample2D(g_Texture0, v_Coordinate.zw).ga;",
            "    reconstructed.r = texSample2D(g_Texture0, v_Coordinate.xy + 0.01).r;",
            "    reconstructed.b = texSample2D(g_Texture0, v_Coordinate.xy - 0.01).b;",
            "    vec3 field = texSample2D(g_Texture1, v_Coordinate.xy).gbr;",
            "    reconstructed.rgb = mix(reconstructed.rgb, field, 0.1);",
            "    gl_FragColor = mix(snapshot, reconstructed, mask);",
            "}",
        ].joined(separator: "\n")
        let msl = [
            "#include <metal_stdlib>",
            "using namespace metal;",
            "fragment void f() {",
            "    float mask = g_Texture2.sample(g_Texture2Smplr, in.v_Coordinate.zw).x;",
            "    float4 snapshot = g_Texture0.sample(g_Texture0Smplr, in.v_Coordinate.xy);",
            "    float4 reconstructed;",
            "    float2 sampledGA = g_Texture0.sample(g_Texture0Smplr, in.v_Coordinate.zw).yw;",
            "    reconstructed.y = sampledGA.x;",
            "    reconstructed.w = sampledGA.y;",
            "    reconstructed.x = g_Texture0.sample(g_Texture0Smplr, in.v_Coordinate.xy + 0.01).x;",
            "    reconstructed.z = g_Texture0.sample(g_Texture0Smplr, in.v_Coordinate.xy - 0.01).z;",
            "    float3 field = g_Texture1.sample(g_Texture1Smplr, in.v_Coordinate.xy).yzx;",
            "    float3 filtered = mix(reconstructed.xyz, field, float3(0.1));",
            "    reconstructed.x = filtered.x;",
            "    reconstructed.y = filtered.y;",
            "    reconstructed.z = filtered.z;",
            "    out.mwxFragColor = mix(snapshot, reconstructed, float4(mask));",
            "    return out;",
            "}",
        ].joined(separator: "\n")

        func fact(
            _ source: String
        ) -> SceneAuthoredShaderSameAlphaReconstructedRGBFilterFact? {
            SceneAuthoredShaderSameAlphaReconstructedRGBFilterAnalyzer.analyze(
                fragmentSource: source
            )
        }

        func routeProfile() -> SceneGenericShaderCapabilityProfile {
            SceneGenericShaderCapabilityProfile(
                colorTransfer: .straightAlpha(textureSlot: 0),
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
                sameAlphaReconstructedRGBFilterSourceSlot: 0,
                sameAlphaReconstructedRGBFilterAuxiliarySlots: [1, 2],
                typedStaticDataAuxiliarySlots: [1, 2],
                previousBlurredCompositeBlurredSlot: nil,
                previousBlurredCompositePreviousSlot: nil,
                hasExternalProviderTexture: false,
                producesScalarRedOutput: false,
                isSourceIndependentPremultipliedOutput: false,
                graphTextureSlots: [],
                graphInputTextureSlots: [0],
                r8TextureSlots: [],
                hasDefaultedOpacityMaskSampler: false,
                hasStageScopedUniformBindings: false,
                hasStereoAudioSpectrumArrays: false
            )
        }

        let analyzed = fact(authored)
        let transfer = SceneAuthoredShaderColorTransferAnalyzer.analyze(
            fragmentSource: authored
        )
        let lowered = try? SceneGenericShaderArtifactBuilder.prepareColorTransfer(
            msl: msl,
            authoredSource: authored
        )
        let loweredMSL = lowered?.msl ?? ""
        let realCompilerMSL = CommandLine.arguments.count >= 2
            ? (try? String(
                contentsOfFile: CommandLine.arguments[1],
                encoding: .utf8
            )) ?? ""
            : ""
        let realCompilerLowered = try?
            SceneGenericShaderArtifactBuilder.prepareColorTransfer(
                msl: realCompilerMSL,
                authoredSource: authored
            )
        let realCompilerLoweredMSL = realCompilerLowered?.msl ?? ""
        let profile = routeProfile()
        let renamed = authored
            .replacingOccurrences(of: "reconstructed", with: "colorCarrier")
            .replacingOccurrences(of: "snapshot", with: "entryColor")
            .replacingOccurrences(of: "field", with: "proceduralValue")

        func renamedCompiler(_ text: String) -> String {
            text.replacingOccurrences(of: "reconstructed", with: "colorCarrier")
                .replacingOccurrences(of: "snapshot", with: "entryColor")
                .replacingOccurrences(of: "sampledGA", with: "coveragePair")
                .replacingOccurrences(of: "field", with: "proceduralValue")
        }
        // Same public reconstruction contract with snapshot alpha and a
        // separate two-channel data input; identifier spelling is irrelevant.
        let preservingSource = authored
            .replacingOccurrences(
                of: "reconstructed.ga = texSample2D(g_Texture0, v_Coordinate.zw).ga;",
                with: "reconstructed.ga = snapshot.ga;"
            )
            .replacingOccurrences(of: "vec3 field", with: "vec2 field")
            .replacingOccurrences(of: ").gbr;", with: ").rg;")
            .replacingOccurrences(of: "reconstructed.rgb, field,", with: "reconstructed.rgb, vec3(field, 0.0),")
        let preservingMSL = renamedCompiler(msl
            .replacingOccurrences(
                of: "float2 sampledGA = g_Texture0.sample(g_Texture0Smplr, in.v_Coordinate.zw).yw;\n    reconstructed.y = sampledGA.x;\n    reconstructed.w = sampledGA.y;",
                with: "reconstructed.y = snapshot.y;\n    reconstructed.w = snapshot.w;"
            )
            .replacingOccurrences(of: "float3 field", with: "float2 field")
            .replacingOccurrences(of: ").yzx;", with: ").xy;")
            .replacingOccurrences(of: "reconstructed.xyz, field,", with: "reconstructed.xyz, float3(field, 0.0),"))

        let constructorSource = try String(contentsOfFile: CommandLine.arguments[2], encoding: .utf8)
        let constructorMSL = try String(contentsOfFile: CommandLine.arguments[3], encoding: .utf8)
        let constructorFact = fact(constructorSource)
        let constructorLowered = try? SceneGenericShaderArtifactBuilder.prepareColorTransfer(
            msl: constructorMSL, authoredSource: constructorSource
        )
        let constructorRenamed = constructorSource
            .replacingOccurrences(of: "red", with: "firstLane")
            .replacingOccurrences(of: "green", with: "secondLane")
            .replacingOccurrences(of: "blue", with: "thirdLane")
            .replacingOccurrences(of: "alpha", with: "lastLane")
            .replacingOccurrences(of: "bend", with: "coordinateWarp")
        var constructorChecks: [String: Bool] = [
            "sourceAccepted": constructorFact?.sourceSlot == 0
                && constructorFact?.auxiliarySlots == [1]
                && constructorFact?.preservesSnapshotAlpha == false
                && constructorFact?.sourceSampleCallCounts == [
                    .fullVector: 1, .red: 1, .green: 1, .blue: 1, .alpha: 1
                ] && constructorFact?.dataSampleCallCounts == [1: [.red: 1]],
            "renamedAccepted": fact(constructorRenamed) == constructorFact
                && constructorFact != nil,
            "realCompilerAccepted": constructorLowered?.transfer.kind == "straight-alpha",
            "realCompilerRenamedAccepted": (try? SceneGenericShaderArtifactBuilder.prepareColorTransfer(
                msl: constructorMSL
                    .replacingOccurrences(of: "red", with: "firstLane")
                    .replacingOccurrences(of: "green", with: "secondLane")
                    .replacingOccurrences(of: "blue", with: "thirdLane")
                    .replacingOccurrences(of: "alpha", with: "lastLane")
                    .replacingOccurrences(of: "bend", with: "coordinateWarp"),
                authoredSource: constructorRenamed
            ))?.transfer.kind == "straight-alpha",
        ]
        let constructorLoweredMSL = constructorLowered?.msl ?? ""
        let chromaticAuthored = try String(
            contentsOfFile: CommandLine.arguments[4], encoding: .utf8
        )
        let chromaticMSL = try String(
            contentsOfFile: CommandLine.arguments[5], encoding: .utf8
        )
        let chromaticFact = fact(chromaticAuthored)
        let chromaticLowered = try? SceneGenericShaderArtifactBuilder
            .prepareColorTransfer(
                msl: chromaticMSL, authoredSource: chromaticAuthored
            )
        let chromaticLoweredMSL = chromaticLowered?.msl ?? ""
        var chromaticChecks: [String: Bool] = [
            // The real effect's helper writes its `uv` parameter, assigns a
            // local through a call argument and reassigns `uv` before
            // returning; the four scalar lanes spread one uniform offset.
            "sourceAccepted": chromaticFact?.sourceSlot == 0
                && chromaticFact?.auxiliarySlots == [1]
                && chromaticFact?.preservesSnapshotAlpha == false
                && chromaticFact?.sourceSampleCallCounts == [
                    .fullVector: 1, .red: 1, .green: 1, .blue: 1, .alpha: 1
                ] && chromaticFact?.dataSampleCallCounts == [1: [.red: 1]],
            "realCompilerAccepted":
                chromaticLowered?.transfer.kind == "straight-alpha",
            "boundaryCounts": chromaticLoweredMSL.components(
                separatedBy: "mwxGenericUnpremultiply(g_Texture0.sample("
            ).count - 1 == 5
                && chromaticLoweredMSL.contains(
                    "out.mwxFragColor = mwxGenericPremultiply("
                ),
        ]
        let chromaticSourceDrifts: [String: String] = [
            "wrongLane": chromaticAuthored.replacingOccurrences(
                of: "    float blue = texSample2D(g_Texture0,"
                    + " computeUV(v_TexCoord.xy, -offset)).b;",
                with: "    float blue = texSample2D(g_Texture0,"
                    + " computeUV(v_TexCoord.xy, -offset)).g;"
            ),
            "helperExtraSample": chromaticAuthored.replacingOccurrences(
                of: "    vec2 radial = vec2(0.0);",
                with: "    vec2 radial = texSample2D(g_Texture0, uv).rg;"
            ),
        ]
        for (name, source) in chromaticSourceDrifts {
            chromaticChecks["sourceChanged-" + name] = source != chromaticAuthored
            chromaticChecks["sourceRejected-" + name] = fact(source) == nil
        }
        // Reading the helper's own parameter is not side-effect authority: the
        // closure proof only denies writes and texture reads, so this stays
        // accepted.
        chromaticChecks["helperParameterReadAccepted"] = fact(
            chromaticAuthored.replacingOccurrences(
                of: "    return (radial / 2.0) + 0.5;",
                with: "    return radial + uv;"
            )
        ) != nil
        for (name, source) in [
            "wrongLane": chromaticMSL.replacingOccurrences(
                of: ").w;", with: ").y;"
            ),
            "paramAlias": chromaticMSL.replacingOccurrences(
                of: "    float mask = g_Texture1.sample",
                with: "    float red = 0.0;\n    float mask = g_Texture1.sample"
            ),
        ] {
            chromaticChecks["compilerChanged-" + name] = source != chromaticMSL
            chromaticChecks["compilerRejected-" + name] = (try? SceneGenericShaderArtifactBuilder
                .prepareColorTransfer(
                    msl: source, authoredSource: chromaticAuthored
                )) == nil
        }

        let constructorTerminal = "gl_FragColor = lerp("
        let sourceDrifts: [String: String] = [
            "wrongLane": constructorSource.replacingOccurrences(of: "0.2)).a;", with: "0.2)).g;"),
            "wrongSlot": constructorSource.replacingOccurrences(of: "float alpha = texSample2D(g_Texture0", with: "float alpha = texSample2D(g_Texture1"),
            "laneOrder": constructorSource.replacingOccurrences(of: "vec4(red, green, blue, alpha)", with: "vec4(blue, green, red, alpha)"),
            "laterWrite": constructorSource.replacingOccurrences(of: constructorTerminal, with: "alpha = mask;\n    " + constructorTerminal),
            "increment": constructorSource.replacingOccurrences(of: constructorTerminal, with: "++alpha;\n    " + constructorTerminal),
            "extraSample": constructorSource.replacingOccurrences(of: constructorTerminal, with: "float hidden = texSample2D(g_Texture0, v_Coordinate.xy).r;\n    " + constructorTerminal),
            "escape": constructorSource.replacingOccurrences(of: constructorTerminal, with: "float hidden = alpha;\n    " + constructorTerminal),
            "inout": constructorSource.replacingOccurrences(of: "bend(vec2 uv", with: "bend(inout vec2 uv"),
            "scalarInout": ("void mutate(inout float lane) { lane = 0.0; }\n" + constructorSource).replacingOccurrences(of: constructorTerminal, with: "mutate(alpha);\n    " + constructorTerminal),
            "builtinInout": ("vec2 floor(inout vec2 uv) { uv += vec2(0.1); return uv; }\n" + constructorSource)
                .replacingOccurrences(of: "float red =", with: "vec2 address = v_Coordinate.xy;\n    float red =")
                .replacingOccurrences(of: "bend(v_Coordinate.xy, 0.4)", with: "floor(address)"),
            "fakeSampler": "vec4 texSample2D(sampler2D image, vec2 uv) { return vec4(1.0); }\n" + constructorSource,
            "fakeMix": "vec4 lerp(vec4 a, vec4 b, float weight) { return b; }\n" + constructorSource,
            "endpoint": constructorSource.replacingOccurrences(of: "lerp(texSample2D(g_Texture0, v_Coordinate.xy), vec4(red, green, blue, alpha), mask)", with: "lerp(vec4(red, green, blue, alpha), texSample2D(g_Texture0, v_Coordinate.xy), mask)"),
        ]
        for (name, source) in sourceDrifts {
            constructorChecks["sourceRejected-" + name] = fact(source) == nil
        }
        let compilerDrifts: [String: String] = [
            "wrongLane": constructorMSL.replacingOccurrences(of: ").w;", with: ").y;"),
            "wrongSlot": constructorMSL.replacingOccurrences(of: "float alpha = g_Texture0.sample", with: "float alpha = g_Texture1.sample"),
            "laneOrder": constructorMSL.replacingOccurrences(of: "float4(red, green, blue, alpha)", with: "float4(blue, green, red, alpha)"),
            "laterWrite": constructorMSL.replacingOccurrences(of: "    out.mwxFragColor =", with: "    alpha = mask;\n    out.mwxFragColor ="),
            "increment": constructorMSL.replacingOccurrences(of: "    out.mwxFragColor =", with: "    ++alpha;\n    out.mwxFragColor ="),
            "extraSample": constructorMSL.replacingOccurrences(of: "    out.mwxFragColor =", with: "    float hidden = g_Texture0.sample(g_Texture0Smplr, in.v_Coordinate.xy).x;\n    out.mwxFragColor ="),
            "escape": constructorMSL.replacingOccurrences(of: "    out.mwxFragColor =", with: "    float hidden = alpha;\n    out.mwxFragColor ="),
            "inout": ("void mutate(thread float& lane) { lane = 0.0; }\n" + constructorMSL).replacingOccurrences(of: "    out.mwxFragColor =", with: "    mutate(alpha);\n    out.mwxFragColor ="),
            "fakeMix": constructorMSL.replacingOccurrences(
                of: "using namespace metal;",
                with: "using namespace metal;\nfloat4 mix(float4 a, float4 b, float4 weight) { return b; }"
            ),
            "commentClosedBody": constructorMSL.replacingOccurrences(
                of: "float4(mask)", with: "float4(mask /* } */)"
            ),
            "endpoint": constructorMSL.replacingOccurrences(of: "float4(red, green, blue, alpha)", with: "float4(red, green, blue, mask)"),
        ]
        for (name, source) in compilerDrifts {
            constructorChecks["compilerChanged-" + name] = source != constructorMSL
            constructorChecks["compilerRejected-" + name] = (try? SceneGenericShaderArtifactBuilder.prepareColorTransfer(
                msl: source, authoredSource: constructorSource
            )) == nil
        }

        let output = Output(
            transfer: {
                if case .straightAlpha(textureSlot: 0) = transfer {
                    return "straight-alpha-0"
                }
                return "unexpected"
            }(),
            sourceSlot: analyzed?.sourceSlot,
            auxiliarySlots: analyzed?.auxiliarySlots.sorted(),
            preservesSnapshotAlpha: analyzed?.preservesSnapshotAlpha,
            totalSamples: analyzed?.totalSampleCallCount,
            renamedAccepted: fact(renamed) != nil,
            loweringAccepted: lowered != nil,
            artifactTransfer: lowered?.transfer.kind,
            sourceUnpremultipliedCount: loweredMSL.components(
                separatedBy: "mwxGenericUnpremultiply(g_Texture0.sample("
            ).count - 1,
            dataUnpremultipliedCount: [1, 2].reduce(0) { count, slot in
                count + loweredMSL.components(
                    separatedBy:
                        "mwxGenericUnpremultiply(g_Texture\(slot).sample("
                ).count - 1
            },
            outputPremultiplied: loweredMSL.contains(
                "out.mwxFragColor = mwxGenericPremultiply("
                    + "mix(snapshot, reconstructed, float4(mask)));"
            ),
            routeProfile: profile.rawValue,
            routeState: profile.defaultRouteState.rawValue,
            rollbackOwner: profile.validatedRollbackOwner.rawValue,
            defaultPermitsBoundedFrontend:
                profile.permitsBoundedFrontendAfterArtifactFailure(
                    routeState: profile.defaultRouteState
                ),
            defaultFallbackOutcome: profile.artifactFallbackOutcome(
                routeState: profile.defaultRouteState
            ),
            disablePermitsBoundedFrontend:
                profile.permitsBoundedFrontendAfterArtifactFailure(
                    routeState: .disableGeneric
                ),
            disableFallbackOutcome: profile.artifactFallbackOutcome(
                routeState: .disableGeneric
            ),
            wrongSlotRejected: fact(authored.replacingOccurrences(
                of: "texSample2D(g_Texture0, v_Coordinate.zw).ga",
                with: "texSample2D(g_Texture1, v_Coordinate.zw).ga"
            )) == nil,
            wrongProjectionRejected: fact(authored.replacingOccurrences(
                of: "v_Coordinate.zw).ga;",
                with: "v_Coordinate.zw).rg;"
            )) == nil,
            alphaOverwriteRejected: fact(authored.replacingOccurrences(
                of: "    gl_FragColor = mix(snapshot, reconstructed, mask);",
                with: "    reconstructed.a = mask;\n"
                    + "    gl_FragColor = mix(snapshot, reconstructed, mask);"
            )) == nil,
            hiddenSourceRejected: fact(authored.replacingOccurrences(
                of: "    gl_FragColor = mix(snapshot, reconstructed, mask);",
                with: "    float hidden = texSample2D(g_Texture0, v_Coordinate.xy).r;\n"
                    + "    gl_FragColor = mix(snapshot, reconstructed, mask);"
            )) == nil,
            endpointDriftRejected: fact(authored.replacingOccurrences(
                of: "mix(snapshot, reconstructed, mask)",
                with: "mix(reconstructed, snapshot, mask)"
            )) == nil,
            compilerAlphaLaneDriftRejected:
                (try? SceneGenericShaderArtifactBuilder.prepareColorTransfer(
                    msl: msl.replacingOccurrences(
                        of: "reconstructed.w = sampledGA.y;",
                        with: "reconstructed.w = sampledGA.x;"
                    ),
                    authoredSource: authored
                )) == nil,
            compilerProjectionDriftRejected:
                (try? SceneGenericShaderArtifactBuilder.prepareColorTransfer(
                    msl: msl.replacingOccurrences(
                        of: ").yw;",
                        with: ").xy;"
                    ),
                    authoredSource: authored
                )) == nil,
            compilerTemporaryEscapeRejected:
                (try? SceneGenericShaderArtifactBuilder.prepareColorTransfer(
                    msl: msl.replacingOccurrences(
                        of: "    reconstructed.y = sampledGA.x;",
                        with: "    reconstructed.y = sampledGA.x;\n"
                            + "    float escapedGA = sampledGA.x;"
                    ),
                    authoredSource: authored
                )) == nil,
            compilerHiddenSourceRejected:
                (try? SceneGenericShaderArtifactBuilder.prepareColorTransfer(
                    msl: msl.replacingOccurrences(
                        of: "    out.mwxFragColor = mix(snapshot, reconstructed, float4(mask));",
                        with: "    float hidden = g_Texture0.sample("
                            + "g_Texture0Smplr, in.v_Coordinate.xy).x;\n"
                            + "    out.mwxFragColor = mix(snapshot, reconstructed, float4(mask));"
                    ),
                    authoredSource: authored
                )) == nil,
            compilerEndpointDriftRejected:
                (try? SceneGenericShaderArtifactBuilder.prepareColorTransfer(
                    msl: msl.replacingOccurrences(
                        of: "mix(snapshot, reconstructed, float4(mask))",
                        with: "mix(reconstructed, snapshot, float4(mask))"
                    ),
                    authoredSource: authored
                )) == nil,
            realCompilerLoweringAccepted: realCompilerLowered != nil,
            realCompilerSourceUnpremultipliedCount:
                realCompilerLoweredMSL.components(
                    separatedBy:
                        "mwxGenericUnpremultiply(g_Texture0.sample("
                ).count - 1,
            renamedCompilerAccepted: (try? SceneGenericShaderArtifactBuilder.prepareColorTransfer(
                msl: renamedCompiler(msl), authoredSource: renamed
            ))?.transfer.kind == "straight-alpha",
            renamedCompilerDriftRejected: (try? SceneGenericShaderArtifactBuilder.prepareColorTransfer(
                msl: renamedCompiler(msl).replacingOccurrences(
                    of: "colorCarrier.w = coveragePair.y;", with: "colorCarrier.w = coveragePair.x;"
                ), authoredSource: renamed
            )) == nil,
            snapshotAlphaWithAuxiliaryRGAccepted: (try? SceneGenericShaderArtifactBuilder.prepareColorTransfer(
                msl: preservingMSL, authoredSource: preservingSource
            ))?.transfer.kind == "straight-alpha-preserving",
            constructorChecks: constructorChecks,
            constructorSourceUnpremultipliedCount: constructorLoweredMSL.components(
                separatedBy: "mwxGenericUnpremultiply(g_Texture0.sample("
            ).count - 1,
            constructorOutputPremultiplied: constructorLoweredMSL.contains(
                "out.mwxFragColor = mwxGenericPremultiply("
            ),
            constructorPixels: try constructorPixels(constructorLowered?.msl),
            chromaticChecks: chromaticChecks
        )
        FileHandle.standardOutput.write(try JSONEncoder().encode(output))
    }
}
'''


class SceneSampledAlphaRGBAReconstructionTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        swiftc = shutil.which("swiftc")
        if swiftc is None:
            raise unittest.SkipTest("swiftc is unavailable")
        cls.build_directory = tempfile.TemporaryDirectory(
            prefix="mwx-sampled-alpha-rgba-"
        )
        root = Path(cls.build_directory.name)
        harness = root / "SampledAlphaRGBAReconstructionHarness.swift"
        harness.write_text(HARNESS, encoding="utf-8")
        compiler_source = root / "sampled-alpha.frag"
        compiler_source.write_text(
            """#version 450
layout(location=0) in vec4 v_Coordinate;
layout(location=0) out vec4 mwxFragColor;
layout(binding=0) uniform sampler2D g_Texture0;
layout(binding=1) uniform sampler2D g_Texture1;
layout(binding=2) uniform sampler2D g_Texture2;
void main() {
    vec4 reconstructed;
    float mask = texture(g_Texture2, v_Coordinate.zw).r;
    vec4 snapshot = texture(g_Texture0, v_Coordinate.xy);
    reconstructed.ga = texture(g_Texture0, v_Coordinate.zw).ga;
    reconstructed.r = texture(g_Texture0, v_Coordinate.xy + 0.01).r;
    reconstructed.b = texture(g_Texture0, v_Coordinate.xy - 0.01).b;
    vec3 field = texture(g_Texture1, v_Coordinate.xy).gbr;
    reconstructed.rgb = mix(reconstructed.rgb, field, 0.1);
    mwxFragColor = mix(snapshot, reconstructed, mask);
}
""",
            encoding="utf-8",
        )
        spirv = root / "sampled-alpha.spv"
        actual_msl = root / "sampled-alpha.metal"
        glslang = (
            REPOSITORY_ROOT
            / "MyWallpaperX/Resources/SceneShaderCompilerTools/glslang"
        )
        spirv_cross = (
            REPOSITORY_ROOT
            / "MyWallpaperX/Resources/SceneShaderCompilerTools/spirv-cross"
        )
        compiler = subprocess.run(
            [
                str(glslang), "-V", "--auto-map-bindings",
                "--auto-map-locations", "-S", "frag", "-e", "main",
                "-o", str(spirv), str(compiler_source),
            ],
            cwd=REPOSITORY_ROOT,
            capture_output=True,
            text=True,
        )
        if compiler.returncode != 0:
            raise RuntimeError(compiler.stderr or compiler.stdout)
        cross = subprocess.run(
            [
                str(spirv_cross), str(spirv), "--msl", "--msl-version",
                "20000", "--msl-decoration-binding", "--rename-entry-point",
                "main", "mwxGenericFragment", "frag", "--output",
                str(actual_msl),
            ],
            cwd=REPOSITORY_ROOT,
            capture_output=True,
            text=True,
        )
        if cross.returncode != 0:
            raise RuntimeError(cross.stderr or cross.stdout)
        constructor_authored = root / "constructor-authored.frag"
        constructor_authored.write_text(CONSTRUCTOR_SOURCE, encoding="utf-8")
        constructor_glsl = root / "constructor.frag"
        constructor_glsl.write_text(
            "#version 450\nlayout(location=0) out vec4 mwxFragColor;\n"
            + CONSTRUCTOR_SOURCE.replace(
                "uniform sampler2D g_Texture0;",
                "layout(binding=0) uniform sampler2D g_Texture0;",
            ).replace(
                "uniform sampler2D g_Texture1;",
                "layout(binding=1) uniform sampler2D g_Texture1;",
            ).replace(
                "varying vec4 v_Coordinate;",
                "layout(location=0) in vec4 v_Coordinate;",
            ).replace("texSample2D(", "texture(")
            .replace("gl_FragColor", "mwxFragColor")
            .replace("lerp(", "mix("),
            encoding="utf-8",
        )
        constructor_spirv = root / "constructor.spv"
        constructor_msl = root / "constructor.metal"
        for command in (
            [str(glslang), "-V", "--auto-map-bindings", "--auto-map-locations",
             "-S", "frag", "-e", "main", "-o", str(constructor_spirv),
             str(constructor_glsl)],
            [str(spirv_cross), str(constructor_spirv), "--msl", "--msl-version",
             "20000", "--msl-decoration-binding", "--rename-entry-point",
             "main", "mwxGenericFragment", "frag", "--output",
             str(constructor_msl)],
        ):
            completed = subprocess.run(
                command, cwd=REPOSITORY_ROOT, capture_output=True, text=True
            )
            if completed.returncode != 0:
                raise RuntimeError(completed.stderr or completed.stdout)
        chromatic_authored = root / "chromatic-authored.frag"
        chromatic_authored.write_text(
            CHROMATIC_ABERRATION_SOURCE, encoding="utf-8"
        )
        chromatic_glsl = root / "chromatic.frag"
        chromatic_glsl.write_text(
            "#version 450\nlayout(location=0) out vec4 mwxFragColor;\n"
            + CHROMATIC_ABERRATION_SOURCE.replace(
                "uniform sampler2D g_Texture0;",
                "layout(binding=0) uniform sampler2D g_Texture0;",
            ).replace(
                "uniform sampler2D g_Texture1;",
                "layout(binding=1) uniform sampler2D g_Texture1;",
            ).replace(
                "uniform float u_aberration;",
                "layout(std140, binding=4) uniform AberrationUniforms"
                " { float u_aberration; };",
            ).replace(
                "varying vec4 v_TexCoord;",
                "layout(location=0) in vec4 v_TexCoord;",
            ).replace("texSample2D(", "texture(")
            .replace("gl_FragColor", "mwxFragColor")
            .replace("lerp(", "mix("),
            encoding="utf-8",
        )
        chromatic_spirv = root / "chromatic.spv"
        chromatic_msl = root / "chromatic.metal"
        for command in (
            [str(glslang), "-V", "--auto-map-bindings", "--auto-map-locations",
             "-S", "frag", "-e", "main", "-o", str(chromatic_spirv),
             str(chromatic_glsl)],
            [str(spirv_cross), str(chromatic_spirv), "--msl", "--msl-version",
             "20000", "--msl-decoration-binding", "--rename-entry-point",
             "main", "mwxGenericFragment", "frag", "--output",
             str(chromatic_msl)],
        ):
            completed = subprocess.run(
                command, cwd=REPOSITORY_ROOT, capture_output=True, text=True
            )
            if completed.returncode != 0:
                raise RuntimeError(completed.stderr or completed.stdout)
        cls.binary = root / "sampled-alpha-rgba"
        environment = os.environ.copy()
        environment["CLANG_MODULE_CACHE_PATH"] = str(root / "clang-cache")
        environment["SWIFT_MODULECACHE_PATH"] = str(root / "swift-cache")
        completed = subprocess.run(
            [
                swiftc,
                "-parse-as-library",
                *(str(path) for path in SWIFT_SOURCES),
                str(harness),
                "-framework", "Security",
                "-o", str(cls.binary),
            ],
            cwd=REPOSITORY_ROOT,
            env=environment,
            capture_output=True,
            text=True,
        )
        if completed.returncode != 0:
            raise RuntimeError(completed.stderr)
        result = subprocess.run(
            [str(cls.binary), str(actual_msl), str(constructor_authored),
             str(constructor_msl), str(chromatic_authored),
             str(chromatic_msl)],
            cwd=REPOSITORY_ROOT,
            env=environment,
            capture_output=True,
            text=True,
        )
        if result.returncode != 0:
            raise RuntimeError(result.stderr or result.stdout)
        cls.result = json.loads(result.stdout)

    @classmethod
    def tearDownClass(cls) -> None:
        cls.build_directory.cleanup()

    def test_shared_color_boundary_and_route(self) -> None:
        self.assertEqual(self.result["transfer"], "straight-alpha-0")
        self.assertEqual(self.result["sourceSlot"], 0)
        self.assertEqual(self.result["auxiliarySlots"], [1, 2])
        self.assertFalse(self.result["preservesSnapshotAlpha"])
        self.assertEqual(self.result["totalSamples"], 6)
        self.assertTrue(self.result["renamedAccepted"])
        self.assertTrue(self.result["renamedCompilerAccepted"])
        self.assertTrue(self.result["snapshotAlphaWithAuxiliaryRGAccepted"])
        self.assertTrue(self.result["loweringAccepted"])
        self.assertEqual(self.result["artifactTransfer"], "straight-alpha")
        self.assertEqual(self.result["sourceUnpremultipliedCount"], 4)
        self.assertEqual(self.result["dataUnpremultipliedCount"], 0)
        self.assertTrue(self.result["outputPremultiplied"])
        self.assertEqual(
            self.result["routeProfile"],
            "source-proven-graph-input-sampled-alpha-reconstructed-rgba-data-filter",
        )
        self.assertEqual(self.result["routeState"], "generic-only")
        self.assertEqual(self.result["rollbackOwner"], "none")
        self.assertFalse(self.result["defaultPermitsBoundedFrontend"])
        self.assertEqual(
            self.result["defaultFallbackOutcome"], "rejected"
        )
        self.assertFalse(self.result["disablePermitsBoundedFrontend"])
        self.assertEqual(self.result["disableFallbackOutcome"], "fallback")
        self.assertTrue(self.result["realCompilerLoweringAccepted"])
        self.assertEqual(
            self.result["realCompilerSourceUnpremultipliedCount"], 4
        )

    def test_source_and_compiler_drift_fail_closed(self) -> None:
        for key in (
            "wrongSlotRejected",
            "wrongProjectionRejected",
            "alphaOverwriteRejected",
            "hiddenSourceRejected",
            "endpointDriftRejected",
            "compilerAlphaLaneDriftRejected",
            "compilerProjectionDriftRejected",
            "compilerTemporaryEscapeRejected",
            "compilerHiddenSourceRejected",
            "compilerEndpointDriftRejected",
            "renamedCompilerDriftRejected",
        ):
            self.assertTrue(self.result[key], (key, self.result))

    def test_constructor_locals_share_the_sampled_alpha_contract(self) -> None:
        checks = self.result["constructorChecks"]
        for key in (
            "sourceAccepted", "renamedAccepted", "realCompilerAccepted",
            "realCompilerRenamedAccepted",
        ):
            self.assertTrue(checks[key], (key, checks))
        # Five same-slot reads cross the straight-color boundary exactly once
        # each; the terminal returns to premultiplied storage exactly once.
        self.assertEqual(self.result["constructorSourceUnpremultipliedCount"], 5)
        self.assertTrue(self.result["constructorOutputPremultiplied"])

    def test_constructor_source_and_real_compiler_drift_fail_closed(self) -> None:
        checks = self.result["constructorChecks"]
        for key, value in checks.items():
            if "Rejected-" in key or "Changed-" in key:
                self.assertTrue(value, (key, checks))

    def test_constructor_real_compiler_pixels_preserve_straight_rgba_and_data_mask(self) -> None:
        expected = (
            (0.05, 0.3, 0.1, 0.5),
            (0.1575, 0.21, 0.1925, 0.35),
            (0.16, 0.12, 0.18, 0.2),
            (0.0, 0.12, 0.18, 0.2),
            (0.0, 0.0, 0.0, 0.0),
        )
        self.assertEqual(len(self.result["constructorPixels"]), len(expected))
        for actual, target in zip(self.result["constructorPixels"], expected):
            for value, wanted in zip(actual, target):
                self.assertAlmostEqual(value, wanted, delta=0.00001)

    def test_captured_workshop_effect_reaches_the_shared_reconstruction_owner(
        self,
    ) -> None:
        checks = self.result["chromaticChecks"]
        for key in (
            "sourceAccepted", "realCompilerAccepted", "boundaryCounts",
            "helperParameterReadAccepted",
        ):
            self.assertTrue(checks[key], (key, checks))

    def test_captured_workshop_effect_drift_fails_closed(self) -> None:
        checks = self.result["chromaticChecks"]
        for key in (
            "sourceChanged-wrongLane", "sourceRejected-wrongLane",
            "sourceChanged-helperExtraSample",
            "sourceRejected-helperExtraSample",
            "compilerChanged-wrongLane", "compilerRejected-wrongLane",
            "compilerChanged-paramAlias", "compilerRejected-paramAlias",
        ):
            self.assertTrue(checks[key], (key, checks))


if __name__ == "__main__":
    unittest.main()
