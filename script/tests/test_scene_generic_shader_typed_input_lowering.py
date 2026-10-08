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
                    sourceColorTransfer: .straightAlphaPreserving(textureSlot: 0)
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
