#!/usr/bin/env python3
"""Typed color inputs lower only the exact bound provider slot."""

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

from scene_swift_source_sets import scene_swift_sources


SWIFT_SOURCES = [
    *scene_swift_sources("authored_shader_frontend_core"),
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Compilation/Material/SceneResolvedMaterialGenericShaderProgramArtifact.swift",
    *scene_swift_sources("generic_shader_compiler_preparation_implementation"),
    *(SCENE_ROOT / "Compilation/Material" / name for name in [
        "SceneResolvedMaterialGenericShaderRouteProfile.swift",
        "SceneResolvedMaterialGenericShaderRouteAuthority.swift",
        "ScenePersistentCacheSupport.swift",
        "SceneResolvedMaterialGenericShaderArtifactCache.swift",
        "SceneResolvedMaterialGenericShaderArtifactCache+Diagnostics.swift",
        "SceneResolvedMaterialGenericShaderPreparationCoordination.swift",
        "SceneResolvedMaterialGenericShaderRequest.swift",
        "SceneResolvedMaterialGenericShaderOwnerDeferral.swift",
        "SceneResolvedMaterialExecutionCapabilityVariant+Frontend.swift",
    ]),
]


HARNESS = r'''
import Foundation
import Metal

// Only the surrounding resource/diagnostic types are fixtures. The complete
// product analysis, frontend selection and lowering implementations compile
// below; these stubs neither classify profiles nor select the input ABI.
struct TemplateFixture { let backgroundSlots: Set<Int> }
enum SceneResolvedMaterialShaderSchema {
    enum DefaultTexture { case internalTarget }
    struct Sampler { let defaultTexture: DefaultTexture? }
}
enum SceneResolvedMaterialTextureResolver {
    static func sceneBackgroundColorSlots(
        template: TemplateFixture,
        samplers: [Int: SceneResolvedMaterialShaderSchema.Sampler]
    ) -> Set<Int> { template.backgroundSlots.intersection(samplers.keys) }
    static func sceneEnvironmentReference(
        template: TemplateFixture,
        sampler: SceneResolvedMaterialShaderSchema.Sampler,
        slot: Int
    ) -> Int? { nil }
}
enum SceneResolvedMaterialVariantCompileProfile {
    static func add(artifact: Double) {}
}
enum SceneResolvedMaterialExecutionCapabilityDiagnostics {
    static func frontendFailure(
        template: TemplateFixture, output: SceneAuthoredShaderFrontendOutput
    ) -> [String] { [] }
}
enum SceneResolvedMaterialVariantCache {
    typealias Template = TemplateFixture
    enum Failure: Error { case fixture }
    enum Code { case shaderFrontendFailed, genericProductOwnerDeferred }
    enum Phase { case frontend }
    enum OwnerFailure { case productOwnerRevoked }
    static func failure(
        _ code: Code, phase: Phase,
        genericOwnerFailure: OwnerFailure? = nil, details: [String] = []
    ) -> Failure { .fixture }
    static func genericOwnerFailure(
        _ decision: SceneGenericShaderRouteDecision
    ) -> OwnerFailure? { nil }
}

private struct Result: Codable {
    let boundedAccepted: Bool
    let boundedWrapsOnlySlotOne: Bool
    let boundedUntypedCacheEntryStaysRaw: Bool
    let boundedMissingSlotRejected: Bool
    let genericWrapsOnlySlotOne: Bool
    let genericMissingSlotRejected: Bool
    let boundaryThenPremultipliedSubsetAccepted: Bool
    let boundaryThenPremultipliedNoDoubleWrap: Bool
    let ordinaryProfiles: [String]
    let ordinaryAnalysisABI: [[Int]]
    let preservedAnalysisABI: [[Int]]
    let ordinaryFrontendABI: [Int]
    let preservedFrontendABI: [Int]
    let ordinaryBackgroundUnionABI: [Int]
    let preservedOutputAnalysisABI: [Int]
    let redGreenOutputAnalysisABI: [Int]
    let preservedOutputBuilt: Bool
    let preservedOutputUnchanged: Bool
    let nonColorFrontendABI: [[Int]]
    let nonColorBackgroundFrontendABI: [Int]
    let acceptedMixedABI: [Int]
    let acceptedEmptyABI: [Int]
    let boundedMixedABI: [Int]
}

@main
private enum Harness {
    static func main() throws {
        if let flag = CommandLine.arguments.firstIndex(where: {
            $0 == "--compiled-request" || $0 == "--vertex-sampling-gpu" || $0 == "--signal-passthrough-gpu"
        }) {
            struct Input: Decodable {
                struct Expected: Decodable { let kind: String }
                struct Stage: Decodable {
                    let name: String
                    let source: String
                    let authoredSource: String
                    let msl: String
                    let reflection: String
                }
                let requestKey: String
                let colorBoundary: SceneShaderColorBoundary
                let defaultBoundaryColorSlots: [Int]?
                let premultipliedColorInputSlots: [Int]?
                let expectedColorTransfer: Expected?
                let stages: [Stage]
            }
            let input = try JSONDecoder().decode(Input.self, from: Data(contentsOf:
                URL(fileURLWithPath: CommandLine.arguments[flag + 1])))
            guard input.expectedColorTransfer == nil else { throw SceneResolvedMaterialVariantCache.Failure.fixture }
            let result = SceneGenericShaderArtifactBuilder.build(requestKey: input.requestKey,
                backendID: "glslang-spirv-cross-msl-v2",
                premultipliedColorInputSlots: Set(input.premultipliedColorInputSlots ?? []),
                defaultBoundaryColorSlots: Set(input.defaultBoundaryColorSlots ?? input.colorBoundary.colorInputSlots),
                colorBoundary: input.colorBoundary, stages: input.stages.map {
                    .init(name: $0.name, source: $0.source, authoredSource: $0.authoredSource,
                          msl: $0.msl, reflection: Data($0.reflection.utf8))
                }, maximumArtifactBytes: 4_194_304)
            switch result {
            case let .success(artifact):
                if input.colorBoundary.signalPassthroughSlot != nil {
                    func accepted(_ value: SceneGenericShaderProgramArtifact) -> Bool {
                        value.makeProgram(expectedKey: input.requestKey, expectedColorBoundary: input.colorBoundary,
                            expectedColorTransfer: .unresolved, expectedFragmentOutputChannelUse: .unproven) != nil
                    }
                    guard accepted(artifact) else { throw SceneResolvedMaterialVariantCache.Failure.fixture }
                    var packet = try JSONSerialization.jsonObject(with: JSONEncoder().encode(artifact)) as! [String: Any]
                    var program = packet["program"] as! [String: Any]
                    program["colorTransfer"] = ["kind": "opaque"]
                    packet["program"] = program
                    let tampered = try JSONDecoder().decode(SceneGenericShaderProgramArtifact.self,
                        from: JSONSerialization.data(withJSONObject: packet))
                    guard !accepted(tampered) else { throw SceneResolvedMaterialVariantCache.Failure.fixture }
                }
                if CommandLine.arguments[flag] != "--compiled-request" {
                    let bounded = SceneAuthoredShaderFrontend.compile(
                        vertexSource: input.stages.first(where: { $0.name == "vertex" })!.authoredSource,
                        fragmentSource: input.stages.first(where: { $0.name == "fragment" })!.authoredSource,
                        colorBoundary: input.colorBoundary)
                    guard let bounded = bounded.program else { throw SceneResolvedMaterialVariantCache.Failure.fixture }
                    let payload = try vertexSamplingGPU(bounded: bounded, generic: artifact.program,
                        signalPassthrough: input.colorBoundary.signalPassthroughSlot != nil)
                    FileHandle.standardOutput.write(try JSONSerialization.data(withJSONObject: payload))
                } else {
                    FileHandle.standardOutput.write(try JSONEncoder().encode(artifact))
                }
            case let .failure(failure):
                throw failure
            }
            return
        }
        let vertex = """
        attribute vec3 a_Position;
        attribute vec2 a_TexCoord;
        varying vec2 v_TexCoord;
        void main() {
            gl_Position = vec4(a_Position, 1.0);
            v_TexCoord = a_TexCoord;
        }
        """
        let fragment = """
        uniform sampler2D g_Texture0;
        uniform sampler2D g_Texture1;
        uniform sampler2D g_Texture2;
        varying vec2 v_TexCoord;
        void main() {
            vec4 base = texSample2D(g_Texture0, v_TexCoord);
            vec4 provider = texSample2D(g_Texture1, v_TexCoord);
            float data = texSample2D(g_Texture2, v_TexCoord).r;
            gl_FragColor = vec4(
                mix(base.rgb, provider.rgb, data),
                base.a
            );
        }
        """
        if CommandLine.arguments.contains("--ordinary") {
            let contract = SceneShaderColorBoundary(colorInputSlots: [0, 1],
                outputRepresentation: .straightAlpha)
            let ordinary = SceneAuthoredShaderFrontend.compile(vertexSource: vertex,
                fragmentSource: fragment, colorBoundary: contract)
            let source = ordinary.program?.metalSource ?? ""
            let msl = """
            #include <metal_stdlib>
            using namespace metal;
            struct MWXUniforms { float2 mwxRenderSize; };
            struct Output { float4 mwxFragColor [[color(0)]]; };
            inline float4 readColor(texture2d<float> g_Texture0, sampler s,
                constant MWXUniforms& helperUniforms) {
                return g_Texture0.sample(s, float2(0.5));
            }
            fragment Output mwxGenericFragment(
                texture2d<float> g_Texture0 [[texture(0)]],
                texture2d<float> g_Texture1 [[texture(1)]],
                texture2d<float> g_Texture2 [[texture(2)]],
                sampler s [[sampler(0)]],
                constant MWXUniforms& frameUniforms [[buffer(8)]]) {
                Output out = {};
                float4 base = readColor(g_Texture0, s, frameUniforms);
                float4 provider = g_Texture1.sample(s, float2(0.5));
                float data = g_Texture2.sample(s, float2(0.5)).r;
                out.mwxFragColor = float4(mix(base.rgb, provider.rgb, data), base.a);
                return out;
            }
            """
            let generic = SceneGenericShaderDefaultStraightColorBoundaryLowering
                .lowerOrdinary(msl, boundary: contract) ?? ""
            let contextDrift = msl.replacingOccurrences(of:
                "constant MWXUniforms& helperUniforms", with: "float mwxColorUniforms")
            let omittedContext = """
            #include <metal_stdlib>
            using namespace metal;
            struct MWXUniforms { float2 mwxRenderSize; };
            struct Output { float4 mwxFragColor [[color(0)]]; };
            inline float4 sampleColor(texture2d<float> g_Texture0, sampler s) {
                return g_Texture0.sample(s, float2(0.5));
            }
            inline float4 readColor(texture2d<float> g_Texture0, sampler s) {
                return sampleColor(g_Texture0, s);
            }
            fragment Output mwxGenericFragment(texture2d<float> g_Texture0 [[texture(0)]],
                sampler s [[sampler(0)]]) {
                Output out = {};
                out.mwxFragColor = readColor(g_Texture0, s);
                out.mwxFragColor.w = 0.5;
                return out;
            }
            """
            let threaded = SceneGenericShaderDefaultStraightColorBoundaryLowering
                .lowerOrdinary(omittedContext, boundary: .init(colorInputSlots: [0],
                    outputRepresentation: .straightAlpha)) ?? ""
            let mismatch = SceneAuthoredShaderFrontend.compile(vertexSource: vertex,
                fragmentSource: fragment, colorBoundary: .init(colorInputSlots: [7],
                    outputRepresentation: .straightAlpha))
            let generated = SceneAuthoredShaderFrontend.compile(vertexSource: vertex,
                fragmentSource: "void main() { gl_FragColor = vec4(0.6, 0.4, 1.25, 0.0); }",
                colorBoundary: .init(colorInputSlots: [], outputRepresentation: .straightAlpha))
            let passthroughBoundary = SceneShaderColorBoundary(colorInputSlots: [0],
                outputRepresentation: .straightAlpha, signalPassthroughSlot: 0)
            let passthroughSource = "uniform sampler2D g_Texture0; void main() { gl_FragColor=texSample2D(g_Texture0,vec2(0.5)); }"
            let passthrough = SceneAuthoredShaderFrontend.compile(vertexSource: vertex,
                fragmentSource: passthroughSource, colorBoundary: passthroughBoundary)
            let proofDrift = SceneAuthoredShaderFrontend.compile(vertexSource: vertex,
                fragmentSource: "uniform sampler2D g_Texture0; void main() { vec4 c=texSample2D(g_Texture0,vec2(0.5)); gl_FragColor=vec4(c.rgb,0.5); }",
                provenColorTransfer: .passthrough(textureSlot: 0), colorBoundary: passthroughBoundary)
            func key(_ boundary: SceneShaderColorBoundary?) -> String {
                SceneResolvedMaterialGenericShaderRequest.key(vertexSource: vertex,
                    fragmentSource: fragment, outputSemantics: .color,
                    expectedColorTransfer: nil, premultipliedColorInputSlots: [],
                    colorBoundary: boundary)
            }
            let result: [String: Bool] = [
                "boundedAccepted": ordinary.program?.colorBoundary == contract,
                "signalPassthroughProven": passthrough.program?.colorBoundary == passthroughBoundary
                    && proofDrift.program == nil,
                "signalPassthroughCacheIdentity": key(passthroughBoundary) != key(.init(
                    colorInputSlots: [0], outputRepresentation: .straightAlpha)),
                "uintMask": ordinary.program?.uniformLayout.fields.contains(where: {
                    $0.name == SceneShaderColorBoundary.uniformName && $0.type == .uint
                }) == true,
                "boundedColorOnly": source.contains("mwxStraightColorInput(mwxTexture0.sample(")
                    && source.contains("mwxStraightColorInput(mwxTexture1.sample(")
                    && !source.contains("mwxStraightColorInput(mwxTexture2.sample("),
                "generatedZeroAlpha": generated.program?.colorBoundary?.outputRepresentation == .straightAlpha
                    && (generated.program?.metalSource.contains("return mwxStraightColorOutput(mwxFragColor)") == true),
                "coveragePreservesRGB": source.contains("return float4(color.xyz, clamp(color.w, 0.0, 1.0))")
                    && !source.contains("return mwxPremultiply(mwxFragColor)"),
                "genericHelperContext": generic.contains("helperUniforms.mwxPremultipliedColorInputMask, 0u")
                    && generic.contains("frameUniforms.mwxPremultipliedColorInputMask, 1u"),
                "genericDataRaw": generic.contains("float data = g_Texture2.sample(s, float2(0.5)).r;"),
                "genericMathPreserved": generic.contains("out.mwxFragColor = float4(mix(base.rgb, provider.rgb, data), base.a);"),
                "genericCoverage": generic.contains("out.mwxFragColor = mwxStraightColorOutput(out.mwxFragColor)"),
                "omittedContextThreaded": threaded.contains("constant MWXUniforms& mwxColorUniforms [[buffer(8)]]")
                    && threaded.contains("sampleColor(mwxColorUniforms, g_Texture0, s)")
                    && threaded.contains("readColor(mwxColorUniforms, g_Texture0, s)")
                    && threaded.contains("mwxColorUniforms.mwxPremultipliedColorInputMask, 0u"),
                "helperContextDriftRejected": SceneGenericShaderDefaultStraightColorBoundaryLowering
                    .lowerOrdinary(contextDrift, boundary: contract) == nil,
                "missingColorSlotRejected": mismatch.program == nil,
                "cacheBoundaryIdentity": key(contract) != key(nil)
                    && key(contract) != key(.init(colorInputSlots: [0], outputRepresentation: .straightAlpha))
                    && key(contract) != key(.init(colorInputSlots: [0, 1], outputRepresentation: .premultipliedAlpha)),
            ]
            FileHandle.standardOutput.write(try JSONSerialization.data(withJSONObject: result))
            return
        }
        let bounded = SceneAuthoredShaderFrontend.compile(
            vertexSource: vertex,
            fragmentSource: fragment,
            provenColorTransfer: .premultipliedAlpha,
            premultipliedColorInputSlots: [1]
        )
        let boundedSource = bounded.program?.metalSource ?? ""
        let boundedCompact = boundedSource.replacingOccurrences(
            of: " ",
            with: ""
        )
        let untyped = SceneAuthoredShaderFrontend.compile(
            vertexSource: vertex,
            fragmentSource: fragment,
            provenColorTransfer: .premultipliedAlpha
        )
        let untypedCompact = (untyped.program?.metalSource ?? "")
            .replacingOccurrences(of: " ", with: "")
        let missing = SceneAuthoredShaderFrontend.compile(
            vertexSource: vertex,
            fragmentSource: fragment,
            provenColorTransfer: .premultipliedAlpha,
            premultipliedColorInputSlots: [3]
        )

        let genericMSL = """
        #include <metal_stdlib>
        using namespace metal;
        inline float4 mwxGenericUnpremultiply(float4 color) {
            return color;
        }
        fragment float4 mwxGenericFragment(
            texture2d<float> g_Texture0 [[texture(0)]],
            texture2d<float> g_Texture1 [[texture(1)]],
            texture2d<float> g_Texture2 [[texture(2)]],
            sampler linearSampler [[sampler(0)]]
        ) {
            float4 base = g_Texture0.sample(linearSampler, float2(0.5));
            float4 provider = g_Texture1.sample(linearSampler, float2(0.5));
            float data = g_Texture2.sample(linearSampler, float2(0.5)).r;
            return float4(mix(base.rgb, provider.rgb, data), base.a);
        }
        """
        let boundarySource = """
        #include <metal_stdlib>
        using namespace metal;
        fragment float4 mwxGenericFragment(
            texture2d<float> g_Texture0 [[texture(0)]],
            sampler linearSampler [[sampler(0)]]
        ) {
            out.mwxFragColor = g_Texture0.sample(linearSampler, float2(0.5));
            return out;
        }
        """
        let boundary = SceneGenericShaderDefaultStraightColorBoundaryLowering
            .lower(boundarySource, colorSlots: [0])
        let boundaryThenPremultiplied = boundary.flatMap { lowered in
            SceneGenericShaderArtifactBuilder
                .lowerPremultipliedColorInputs(lowered.msl, slots: [0])
        }
        let generic = SceneGenericShaderArtifactBuilder
            .lowerPremultipliedColorInputs(genericMSL, slots: [1]) ?? ""
        let genericCompact = generic.replacingOccurrences(of: " ", with: "")
        let missingGeneric = SceneGenericShaderArtifactBuilder
            .lowerPremultipliedColorInputs(genericMSL, slots: [3])

        func analysis(
            premultiplied: Bool, transfer: SceneShaderColorTransfer,
            output: SceneGenericShaderOutputSemantics = .color
        ) -> SceneGenericShaderAnalysis {
            SceneResolvedMaterialGenericShaderArtifactCache.computeAnalysis(
                input: .init(
                    vertexSource: vertex, fragmentSource: fragment,
                    alphaAttenuationSourceSlot: nil, colorBlendSourceSlot: nil,
                    previousBlurredCompositeBlurredSlot: nil,
                    previousBlurredCompositePreviousSlot: nil,
                    previousBlurredCompositeMaskSlot: nil,
                    hasExternalProviderTexture: true,
                    producesScalarRedOutput: false,
                    producesRedGreenUnormOutput: output == .redGreenUnorm,
                    hasOnlyScalarDataInputs: false,
                    isSourceIndependentPremultipliedOutput: false,
                    graphTextureSlots: [], graphInputTextureSlots: [0],
                    graphDataTextureSlots: [],
                    activeTextureSlots: [0, 1, 2], activeOpacityMaskSlots: [2],
                    typedStaticDataAuxiliarySlots: [2],
                    preservedChannelsExternalProviderTextureSlots:
                        premultiplied ? [] : [1],
                    premultipliedColorAuxiliarySlots:
                        premultiplied ? [1] : [],
                    sceneBackgroundColorSlots: [],
                    spatialWeightedColorBlendSourceSlot: nil,
                    spatialWeightedColorBlendActiveSlots: [],
                    spatialWeightedColorBlendTypedAuxiliarySlots: [],
                    spatialWeightedColorBlendExternalColorSlot: nil,
                    r8TextureSlots: [], hasDefaultedOpacityMaskSampler: false,
                    hasOnlyTypedOpacityMaskAuxiliary: false,
                    hasOnlyGraphInputSampler: false, outputIsRGBA8Unorm: true,
                    sourceColorTransfer: transfer, outputSemantics: output,
                    runtimeLoopBounds: .none
                )
            )
        }
        let namedAnalyses = [
            analysis(premultiplied: true, transfer: .unresolved),
            analysis(premultiplied: true,
                     transfer: .straightAlphaPreserving(textureSlot: 0)),
        ]
        let preservedAnalyses = [
            analysis(premultiplied: false, transfer: .unresolved),
            analysis(premultiplied: false,
                     transfer: .straightAlphaPreserving(textureSlot: 0)),
        ]
        let preservedOutputAnalysis = analysis(
            premultiplied: true, transfer: .unresolved,
            output: .preservedRGBAUnorm
        )
        let redGreenOutputAnalysis = analysis(
            premultiplied: true, transfer: .unresolved,
            output: .redGreenUnorm
        )
        let dataSource = """
        uniform sampler2D g_Texture1;
        void main() {
            gl_FragColor = texSample2D(g_Texture1, vec2(0.5));
        }
        """
        let dataMSL = """
        #include <metal_stdlib>
        using namespace metal;
        struct MWXUniforms {};
        struct Output { float4 mwxFragColor [[color(0)]]; };
        fragment Output mwxGenericFragment(
            texture2d<float> g_Texture1 [[texture(1)]],
            sampler linearSampler [[sampler(0)]]
        ) {
            Output out = {};
            out.mwxFragColor = g_Texture1.sample(linearSampler, float2(0.5));
            return out;
        }
        """
        let dataReflection = Data(#"{"types":{"_1":{"members":[]}},"ubos":[{"type":"_1","block_size":0,"set":0,"binding":8}],"textures":[{"name":"g_Texture1","binding":1}]}"#.utf8)
        let dataArtifact = SceneGenericShaderArtifactBuilder.build(
            requestKey: "fixture", backendID: "fixture",
            outputSemantics: .preservedRGBAUnorm,
            premultipliedColorInputSlots:
                preservedOutputAnalysis.premultipliedColorInputSlots,
            stages: [
                .init(name: "vertex", source: "void main() {}",
                      authoredSource: "void main() {}",
                      msl: "struct MWXUniforms {};", reflection: dataReflection),
                .init(name: "fragment", source: dataSource,
                      authoredSource: dataSource, msl: dataMSL,
                      reflection: dataReflection),
            ],
            maximumArtifactBytes: 1_024_000
        )
        let dataProgram: SceneGenericShaderProgramArtifact.Program?
        switch dataArtifact {
        case let .success(artifact): dataProgram = artifact.program
        case .failure: dataProgram = nil
        }
        func frontendABI(
            auxiliary: Set<Int>, background: Set<Int> = [],
            output: SceneGenericShaderOutputSemantics = .color,
            acceptedABI: Set<Int>? = nil, mixed: Set<Int> = []
        ) throws -> [Int] {
            guard let program = bounded.program else {
                throw SceneResolvedMaterialVariantCache.Failure.fixture
            }
            let decision = SceneGenericShaderRouteDecision(
                profile: "ordinary-shader", state: "generic-only",
                fallbackOwner: "bounded-frontend"
            )
            let artifact: SceneResolvedMaterialGenericShaderArtifactCache.Resolution
            if let acceptedABI {
                artifact = .accepted(
                    program: program, premultipliedColorInputSlots: acceptedABI,
                    requestKey: "fixture", routeDecision: decision
                )
            } else {
                artifact = .unavailable(
                    code: "fixture", requestKey: "fixture",
                    permitsBoundedFrontend: true, routeDecision: decision
                )
            }
            let selected = try SceneResolvedMaterialVariantCache
                .resolveVariantFrontend(
                    template: .init(backgroundSlots: background),
                    sourceActiveSamplers: background.isEmpty ? [:]
                        : [0: .init(defaultTexture: .internalTarget)],
                    spatialWeightedColorBlendExternalColorSlot: nil,
                    premultipliedColorAuxiliarySlots: auxiliary,
                    mixedProviderSlots: mixed,
                    outputSemantics: output,
                    artifactStart: 0,
                    artifactResolution: artifact,
                    compatibilityTargetAdmissionPending: false,
                    onBoundedFrontendCompilation: {},
                    compilerSources: .init(vertex: vertex, fragment: fragment),
                    runtimeLoopBounds: .none,
                    sourceColorTransfer: .straightAlphaPreserving(textureSlot: 0),
                    colorBoundary: nil
                )
            return selected.premultipliedColorInputSlots.sorted()
        }

        let result = Result(
            boundedAccepted:
                bounded.diagnostics.isEmpty && bounded.program != nil,
            boundedWrapsOnlySlotOne:
                boundedCompact.contains(
                    "mwxUnpremultiply(mwxTexture1.sample("
                )
                && !boundedCompact.contains(
                    "mwxUnpremultiply(mwxTexture0.sample("
                )
                && !boundedCompact.contains(
                    "mwxUnpremultiply(mwxTexture2.sample("
                ),
            boundedUntypedCacheEntryStaysRaw:
                untyped.program != nil
                && !untypedCompact.contains(
                    "mwxUnpremultiply(mwxTexture1.sample("
                ),
            boundedMissingSlotRejected:
                missing.program == nil
                && missing.diagnostics.contains(where: {
                    $0.code == .unsupportedSampler
                }),
            genericWrapsOnlySlotOne:
                genericCompact.contains(
                    "mwxGenericUnpremultiply(g_Texture1.sample("
                )
                && !genericCompact.contains(
                    "mwxGenericUnpremultiply(g_Texture0.sample("
                )
                && !genericCompact.contains(
                    "mwxGenericUnpremultiply(g_Texture2.sample("
                ),
            genericMissingSlotRejected: missingGeneric == nil,
            // The archived production failure: the default straight-color
            // boundary already unpremultiplied a boundary slot; the
            // premultiplied-input lowering on that same slot must treat the
            // wrapped call as done instead of failing the artifact.
            boundaryThenPremultipliedSubsetAccepted:
                boundary != nil && boundaryThenPremultiplied != nil,
            boundaryThenPremultipliedNoDoubleWrap:
                boundaryThenPremultiplied.map { lowered in
                    lowered.components(
                        separatedBy: "mwxGenericUnpremultiply(g_Texture0.sample("
                    ).count == 2
                        && !lowered.contains(
                            "mwxGenericUnpremultiply(mwxGenericUnpremultiply("
                        )
                } ?? false,
            ordinaryProfiles: namedAnalyses.map { $0.profile.rawValue },
            ordinaryAnalysisABI: namedAnalyses.map {
                $0.premultipliedColorInputSlots.sorted()
            },
            preservedAnalysisABI: preservedAnalyses.map {
                $0.premultipliedColorInputSlots.sorted()
            },
            ordinaryFrontendABI: try frontendABI(auxiliary: [1]),
            preservedFrontendABI: try frontendABI(auxiliary: []),
            ordinaryBackgroundUnionABI:
                try frontendABI(auxiliary: [1], background: [0]),
            preservedOutputAnalysisABI:
                preservedOutputAnalysis.premultipliedColorInputSlots.sorted(),
            redGreenOutputAnalysisABI:
                redGreenOutputAnalysis.premultipliedColorInputSlots.sorted(),
            preservedOutputBuilt: dataProgram != nil,
            preservedOutputUnchanged:
                dataProgram?.colorTransfer.kind == "preserved-rgba-data"
                    && dataProgram?.premultipliedColorInputSlots == []
                    && dataProgram?.metalSource.contains(
                        "out.mwxFragColor = g_Texture1.sample("
                    ) == true
                    && dataProgram?.metalSource.contains(
                        "mwxGenericUnpremultiply"
                    ) == false,
            nonColorFrontendABI: try [
                frontendABI(auxiliary: [1], output: .preservedRGBAUnorm),
                frontendABI(auxiliary: [1], output: .redGreenUnorm),
            ],
            nonColorBackgroundFrontendABI: try frontendABI(
                auxiliary: [1], background: [0], output: .preservedRGBAUnorm
            ),
            acceptedMixedABI: try frontendABI(
                auxiliary: [], background: [0], acceptedABI: [1], mixed: [1]
            ),
            acceptedEmptyABI: try frontendABI(
                auxiliary: [1], background: [0], acceptedABI: [], mixed: [1]
            ),
            boundedMixedABI: try frontendABI(auxiliary: [1], mixed: [1])
        )
        FileHandle.standardOutput.write(try JSONEncoder().encode(result))
    }

    private static func vertexSamplingGPU(
        bounded: SceneAuthoredShaderProgram,
        generic: SceneGenericShaderProgramArtifact.Program,
        signalPassthrough: Bool = false
    ) throws -> [String: Any] {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else {
            return ["metalAvailable": false]
        }
        func texture(_ value: [Float]) -> MTLTexture {
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba16Float,
                width: 1, height: 1, mipmapped: false)
            descriptor.storageMode = .shared
            descriptor.usage = [.shaderRead, .renderTarget]
            let result = device.makeTexture(descriptor: descriptor)!
            var bytes = value.map(Float16.init)
            bytes.withUnsafeMutableBytes { result.replace(region: MTLRegionMake2D(0, 0, 1, 1),
                mipmapLevel: 0, withBytes: $0.baseAddress!, bytesPerRow: 8) }
            return result
        }
        var cases: [[String: Any]] = []
        for isGeneric in [false, true] {
            let source = isGeneric ? generic.metalSource : bounded.metalSource
            let library = try device.makeLibrary(source: source, options: nil)
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexFunction = library.makeFunction(name:
                isGeneric ? generic.vertexFunctionName : bounded.vertexFunctionName)
            descriptor.fragmentFunction = library.makeFunction(name:
                isGeneric ? generic.fragmentFunctionName : bounded.fragmentFunctionName)
            descriptor.colorAttachments[0].pixelFormat = .rgba16Float
            if isGeneric {
                let vertex = MTLVertexDescriptor()
                vertex.attributes[0].format = .float3
                vertex.attributes[0].offset = 0
                vertex.attributes[0].bufferIndex = 16
                vertex.attributes[1].format = .float2
                vertex.attributes[1].offset = 12
                vertex.attributes[1].bufferIndex = 16
                vertex.layouts[16].stride = 20
                descriptor.vertexDescriptor = vertex
            }
            let pipeline = try device.makeRenderPipelineState(descriptor: descriptor)
            let uniformIndex = isGeneric ? generic.uniformBufferIndex : bounded.uniformBufferIndex
            let byteSize = isGeneric ? generic.uniformLayout.byteSize : bounded.uniformLayout.byteSize
            let maskOffset = isGeneric
                ? generic.uniformLayout.fields.first(where: { $0.name == SceneShaderColorBoundary.uniformName })!.offset
                : bounded.uniformLayout.fields.first(where: { $0.name == SceneShaderColorBoundary.uniformName })!.offset
            let probes: [(UInt32, [Float], [Float])] = signalPassthrough ? [
                (0, [2, 0.6, 0.25, 0.5], [2, 0.6, 0.25, 0.5]),
                (1, [1, 0.3, 0.125, 0.5], [2, 0.6, 0.25, 0.5]),
                (0, [2, 0.6, 0.25, 0], [2, 0.6, 0.25, 0]),
                (1, [0, 0, 0, 0], [0, 0, 0, 0]),
                (256, [2, 0.6, 0.25, 2.5], [2, 0.6, 0.25, 2.5]),
                (256, [2, 0.6, 0.25, -0.25], [2, 0.6, 0.25, -0.25]),
                (512, [2, 0.6, 0.25, 2.5], [2, 0.6, 0.25, 1]),
            ] : [
                (UInt32(2), [Float(2), 0.6, 0.25, 0.5], [Float(1), 0.3, 0.125, 0.5]),
                (UInt32(3), [Float(1), 0.3, 0.125, 0.5], [Float(1), 0.3, 0.125, 0.5]),
                (UInt32(2), [Float(2), 0.6, 0.25, 0], [Float(1), 0.3, 0.125, 0.5]),
                (UInt32(3), [Float(0), 0, 0, 0], [Float(0), 0, 0, 0.5])
            ]
            // Reuse each pipeline while switching only typed frame bytes.
            for (mask, value, authoredExpected) in probes {
                let pmaOutput = bounded.colorBoundary?.outputRepresentation == .premultipliedAlpha
                let expected = signalPassthrough && pmaOutput && mask != 256
                    ? [authoredExpected[0] * authoredExpected[3], authoredExpected[1] * authoredExpected[3],
                       authoredExpected[2] * authoredExpected[3], authoredExpected[3]] : authoredExpected
                let input = texture(value)
                let data = texture([0.5, 0, 0, 0.25])
                let output = texture([0, 0, 0, 0])
                var bytes = [UInt8](repeating: 0, count: byteSize)
                withUnsafeBytes(of: mask) { bytes.replaceSubrange(maskOffset..<(maskOffset + 4), with: $0) }
                let command = queue.makeCommandBuffer()!
                let pass = MTLRenderPassDescriptor()
                pass.colorAttachments[0].texture = output
                pass.colorAttachments[0].loadAction = .clear
                pass.colorAttachments[0].storeAction = .store
                let encoder = command.makeRenderCommandEncoder(descriptor: pass)!
                encoder.setRenderPipelineState(pipeline)
                bytes.withUnsafeBytes {
                    encoder.setVertexBytes($0.baseAddress!, length: $0.count, index: uniformIndex)
                    encoder.setFragmentBytes($0.baseAddress!, length: $0.count, index: uniformIndex)
                }
                var positions: [Float] = [-1, -1, 0, 0.5, 0.5, 1, -1, 0, 0.5, 0.5,
                                         -1, 1, 0, 0.5, 0.5, 1, 1, 0, 0.5, 0.5]
                if isGeneric { encoder.setVertexBytes(&positions, length: positions.count * 4, index: 16) }
                let sampler = device.makeSamplerState(descriptor: MTLSamplerDescriptor())!
                for (slot, sourceTexture) in [input, data].enumerated() {
                    encoder.setVertexTexture(sourceTexture, index: slot)
                    encoder.setVertexSamplerState(sampler, index: slot)
                    encoder.setFragmentTexture(sourceTexture, index: slot)
                    encoder.setFragmentSamplerState(sampler, index: slot)
                }
                encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
                encoder.endEncoding()
                command.commit()
                command.waitUntilCompleted()
                var pixel = [Float16](repeating: 0, count: 4)
                pixel.withUnsafeMutableBytes { output.getBytes($0.baseAddress!, bytesPerRow: 8,
                    from: MTLRegionMake2D(0, 0, 1, 1), mipmapLevel: 0) }
                cases.append(["generic": isGeneric, "mask": mask, "uniformIndex": uniformIndex,
                    "completed": command.status == .completed, "actual": pixel.map(Float.init),
                    "expected": expected])
            }
        }
        return ["metalAvailable": true, "cases": cases]
    }
}
'''


class SceneGenericShaderTypedInputLoweringTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        swiftc = shutil.which("swiftc")
        if swiftc is None:
            raise unittest.SkipTest("swiftc is unavailable")
        cls.build_directory = tempfile.TemporaryDirectory(
            prefix="mwx-typed-input-lowering-test-"
        )
        build_root = Path(cls.build_directory.name)
        harness = build_root / "Harness.swift"
        harness.write_text(HARNESS, encoding="utf-8")
        cls.binary = build_root / "typed-input-lowering-harness"
        environment = os.environ.copy()
        environment["CLANG_MODULE_CACHE_PATH"] = str(
            build_root / "clang-module-cache"
        )
        environment["SWIFT_MODULECACHE_PATH"] = str(
            build_root / "swift-module-cache"
        )
        completed = subprocess.run(
            [
                swiftc,
                "-parse-as-library",
                *(str(path) for path in SWIFT_SOURCES),
                str(harness),
                "-framework", "Security",
                "-framework", "Metal",
                "-o",
                str(cls.binary),
            ],
            cwd=REPOSITORY_ROOT,
            env=environment,
            capture_output=True,
            text=True,
        )
        if completed.returncode != 0:
            raise AssertionError(completed.stderr)

    @classmethod
    def tearDownClass(cls) -> None:
        cls.build_directory.cleanup()

    def test_ordinary_color_abi_preserves_math_and_validates_helper_scope(self) -> None:
        result = json.loads(subprocess.check_output(
            [str(self.binary), "--ordinary"], cwd=REPOSITORY_ROOT, text=True
        ))
        self.assertTrue(result, result)
        self.assertTrue(all(result.values()), result)

    def compile_authored_stages(self, authored: list[dict], root: Path) -> list[dict]:
        from scene_shader_compiler_harness import normalize_wallpaper_engine_pair

        tools = REPOSITORY_ROOT / "MyWallpaperX/Resources/SceneShaderCompilerTools"
        if not (tools / "glslang").is_file():
            self.skipTest("bundled shader compiler is unavailable")
        normalized, _ = normalize_wallpaper_engine_pair(authored, {})
        compiled = []
        for stage in normalized:
            name = stage["stage"]
            source = root / f"{name}.{'vert' if name == 'vertex' else 'frag'}"
            source.write_text(stage["source"], encoding="utf-8")
            spirv, msl, reflection = (root / f"{name}.{suffix}" for suffix in ("spv", "metal", "json"))
            commands = [
                [str(tools / "glslang"), "-V", "--auto-map-bindings", "--auto-map-locations",
                 "-S", "vert" if name == "vertex" else "frag", "-e", "main", "-o", str(spirv), str(source)],
                [str(tools / "spirv-cross"), str(spirv), "--msl", "--msl-version", "20000",
                 "--msl-decoration-binding", "--rename-entry-point", "main",
                 "mwxGenericVertex" if name == "vertex" else "mwxGenericFragment",
                 "vert" if name == "vertex" else "frag", "--output", str(msl)],
                [str(tools / "spirv-cross"), str(spirv), "--reflect", "--output", str(reflection)],
            ]
            for command in commands:
                result = subprocess.run(command, capture_output=True, text=True)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            compiled.append({"name": name, "source": stage["source"],
                             "authoredSource": next(s["source"] for s in authored if s["stage"] == name),
                             "msl": msl.read_text(encoding="utf-8"),
                             "reflection": reflection.read_text(encoding="utf-8")})
        return compiled

    def test_real_compiler_texture_only_alpha_override_restores_uniform_context(self) -> None:
        from scene_shader_compiler_harness import normalize_wallpaper_engine_pair

        tools = REPOSITORY_ROOT / "MyWallpaperX/Resources/SceneShaderCompilerTools"
        if not (tools / "glslang").is_file() or shutil.which("xcrun") is None:
            self.skipTest("bundled compiler or Metal toolchain is unavailable")
        metal = subprocess.run(["xcrun", "--find", "metal"], capture_output=True, text=True)
        if metal.returncode != 0:
            self.skipTest("Metal toolchain is unavailable")
        authored = [
            {"stage": "vertex", "entryPoint": "main", "source":
             "uniform mat4 g_ModelViewProjectionMatrix;\nattribute vec3 a_Position;\n"
             "attribute vec2 a_TexCoord;\nvarying vec2 v_TexCoord;\n"
             "void main() { gl_Position=mul(vec4(a_Position,1.0),g_ModelViewProjectionMatrix); "
             "v_TexCoord=a_TexCoord; }\n"},
            {"stage": "fragment", "entryPoint": "main", "source":
             "varying vec2 v_TexCoord;\nuniform sampler2D g_Texture0;\n"
             "void main() { vec4 sampled=texSample2D(g_Texture0,v_TexCoord); "
             "sampled.a=0.5; gl_FragColor=sampled; }\n"},
        ]
        with tempfile.TemporaryDirectory(prefix="mwx-color-uniform-context-") as directory:
            root = Path(directory)
            compiled = self.compile_authored_stages(authored, root)
            raw_fragment = next(s["msl"] for s in compiled if s["name"] == "fragment")
            self.assertNotIn("constant MWXUniforms&", raw_fragment)
            request = root / "input.json"
            request.write_text(json.dumps({"requestKey": "c" * 64, "stages": compiled,
                                          "colorBoundary": {"colorInputSlots": [0],
                                                            "outputRepresentation": "straight-alpha"}}), encoding="utf-8")
            built = subprocess.run([str(self.binary), "--compiled-request", str(request)],
                                   capture_output=True, text=True)
            self.assertEqual(built.returncode, 0, built.stderr)
            program = json.loads(built.stdout)["program"]
            self.assertIn("constant MWXFragmentUniforms& mwxColorUniforms [[buffer(8)]]", program["metalSource"])
            self.assertIn("sampled.w = 0.5;", program["metalSource"])
            self.assertEqual(program["metalSource"].count("mwxStraightColorInput(g_Texture0.sample"), 1)
            self.assertIn("out.mwxFragColor = mwxStraightColorOutput(out.mwxFragColor);", program["metalSource"])
            combined = root / "program.metal"
            combined.write_text(program["metalSource"], encoding="utf-8")
            accepted = subprocess.run([metal.stdout.strip(), "-x", "metal", "-std=macos-metal2.4",
                                       "-c", str(combined), "-o", str(root / "program.air")],
                                      capture_output=True, text=True)
            self.assertEqual(accepted.returncode, 0, accepted.stdout + accepted.stderr)
            request.write_text(json.dumps({"requestKey": "c" * 64, "stages": compiled,
                "colorBoundary": {"colorInputSlots": [0], "outputRepresentation": "straight-alpha",
                                  "signalPassthroughSlot": 0}}), encoding="utf-8")
            drift = subprocess.run([str(self.binary), "--compiled-request", str(request)], capture_output=True, text=True)
            self.assertNotEqual(drift.returncode, 0)
            self.assertIn("colorTransfer", drift.stderr)

    def test_exact_provider_slot_is_lowered_and_other_slots_remain_raw(self) -> None:
        completed = subprocess.run(
            [str(self.binary)],
            cwd=REPOSITORY_ROOT,
            check=True,
            capture_output=True,
            text=True,
        )
        result = json.loads(completed.stdout)
        self.assertEqual(
            {key: value for key, value in result.items()
             if isinstance(value, bool) and not key.startswith("preservedOutput")},
            {
                "boundedAccepted": True,
                "boundedWrapsOnlySlotOne": True,
                "boundedUntypedCacheEntryStaysRaw": True,
                "boundedMissingSlotRejected": True,
                "genericWrapsOnlySlotOne": True,
                "genericMissingSlotRejected": True,
                "boundaryThenPremultipliedSubsetAccepted": True,
                "boundaryThenPremultipliedNoDoubleWrap": True,
            },
        )

    def test_vertex_color_mask_switch_reaches_fragment_through_varying_on_gpu(self) -> None:
        authored = [
            {"stage": "vertex", "entryPoint": "main", "source":
             "attribute vec3 a_Position;\nattribute vec2 a_TexCoord;\nuniform sampler2D g_Texture0;\n"
             "uniform sampler2D g_Texture1;\nvarying vec4 v_Color;\n"
             "vec4 readColor(vec2 uv) { return texSample2D(g_Texture0,uv); }\n"
             "void main() { vec4 sampled=readColor(a_TexCoord); "
             "float data=texSample2D(g_Texture1,a_TexCoord).r; "
             "v_Color=vec4(sampled.rgb*data,sampled.a); gl_Position=vec4(a_Position,1.0); }\n"},
            {"stage": "fragment", "entryPoint": "main", "source":
             "varying vec4 v_Color;\nvoid main() { gl_FragColor=vec4(v_Color.rgb,0.5); }\n"},
        ]
        with tempfile.TemporaryDirectory(prefix="mwx-vertex-color-boundary-gpu-") as directory:
            root = Path(directory)
            compiled = self.compile_authored_stages(authored, root)
            self.assertNotIn("constant MWXUniforms&", next(s["msl"] for s in compiled if s["name"] == "vertex"))
            request = root / "input.json"
            request.write_text(json.dumps({"requestKey": "d" * 64, "stages": compiled,
                                          "colorBoundary": {"colorInputSlots": [0],
                                                            "outputRepresentation": "straight-alpha"}}), encoding="utf-8")
            executed = subprocess.run([str(self.binary), "--vertex-sampling-gpu", str(request)],
                                      capture_output=True, text=True)
            self.assertEqual(executed.returncode, 0, executed.stderr)
            result = json.loads(executed.stdout)
        if not result["metalAvailable"]:
            self.skipTest("Metal is unavailable")
        self.assertEqual(len(result["cases"]), 8, result)
        self.assertEqual({case["uniformIndex"] for case in result["cases"]}, {0, 8})
        for case in result["cases"]:
            self.assertTrue(case["completed"], case)
            for actual, expected in zip(case["actual"], case["expected"], strict=True):
                self.assertAlmostEqual(actual, expected, delta=0.002, msg=case)

    def test_signal_passthrough_switches_actual_representation_on_one_pipeline(self) -> None:
        authored = [
            {"stage": "vertex", "entryPoint": "main", "source":
             "attribute vec3 a_Position;\nattribute vec2 a_TexCoord;\nvarying vec2 v_TexCoord;\n"
             "void main() { v_TexCoord=a_TexCoord; gl_Position=vec4(a_Position,1.0); }\n"},
            {"stage": "fragment", "entryPoint": "main", "source":
             "varying vec2 v_TexCoord;\nuniform sampler2D g_Texture0;\n"
             "void main() { gl_FragColor=texSample2D(g_Texture0,v_TexCoord); }\n"},
        ]
        with tempfile.TemporaryDirectory(prefix="mwx-signal-passthrough-gpu-") as directory:
            root = Path(directory)
            compiled = self.compile_authored_stages(authored, root)
            for representation in ["straight-alpha", "premultiplied-alpha"]:
                boundary = {"colorInputSlots": [0], "outputRepresentation": representation,
                            "signalPassthroughSlot": 0}
                request = root / "input.json"
                request.write_text(json.dumps({"requestKey": "e" * 64, "stages": compiled,
                                              "colorBoundary": boundary}), encoding="utf-8")
                executed = subprocess.run([str(self.binary), "--signal-passthrough-gpu", str(request)],
                                          capture_output=True, text=True)
                self.assertEqual(executed.returncode, 0, executed.stderr)
                result = json.loads(executed.stdout)
                if not result["metalAvailable"]:
                    self.skipTest("Metal is unavailable")
                self.assertEqual(len(result["cases"]), 14, result)
                self.assertEqual({case["uniformIndex"] for case in result["cases"]}, {0, 8})
                for case in result["cases"]:
                    self.assertTrue(case["completed"], case)
                    for actual, expected in zip(case["actual"], case["expected"], strict=True):
                        self.assertAlmostEqual(actual, expected, delta=0.002, msg=case)

    def test_ordinary_profile_conserves_both_typed_provider_abis(self) -> None:
        result = json.loads(subprocess.check_output(
            [str(self.binary)], cwd=REPOSITORY_ROOT, text=True
        ))
        self.assertEqual(result["ordinaryProfiles"], ["ordinary-shader"] * 2)
        self.assertEqual(result["ordinaryAnalysisABI"], [[1], [1]], result)
        self.assertEqual(result["preservedAnalysisABI"], [[], []], result)
        self.assertEqual(result["ordinaryFrontendABI"], [1], result)
        self.assertEqual(result["preservedFrontendABI"], [], result)

    def test_ordinary_profile_keeps_existing_background_boundary(self) -> None:
        result = json.loads(subprocess.check_output(
            [str(self.binary)], cwd=REPOSITORY_ROOT, text=True
        ))
        self.assertEqual(result["ordinaryBackgroundUnionABI"], [0, 1], result)

    def test_accepted_compiler_abi_is_not_reclassified_by_bounded_rules(self) -> None:
        result = json.loads(subprocess.check_output(
            [str(self.binary)], cwd=REPOSITORY_ROOT, text=True
        ))
        self.assertEqual(result["acceptedMixedABI"], [1], result)
        self.assertEqual(result["acceptedEmptyABI"], [], result)
        self.assertEqual(result["boundedMixedABI"], [], result)

    def test_non_color_output_keeps_data_channels_and_no_color_input_abi(self) -> None:
        result = json.loads(subprocess.check_output(
            [str(self.binary)], cwd=REPOSITORY_ROOT, text=True
        ))
        self.assertEqual(result["preservedOutputAnalysisABI"], [], result)
        self.assertEqual(result["redGreenOutputAnalysisABI"], [], result)
        self.assertTrue(result["preservedOutputBuilt"], result)
        self.assertTrue(result["preservedOutputUnchanged"], result)
        self.assertEqual(result["nonColorFrontendABI"], [[], []], result)
        self.assertEqual(result["nonColorBackgroundFrontendABI"], [0], result)


if __name__ == "__main__":
    unittest.main()
