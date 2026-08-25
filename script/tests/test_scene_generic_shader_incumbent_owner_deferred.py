#!/usr/bin/env python3

import hashlib
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
MATERIAL_PROGRAM_ROOT = SCENE_ROOT / "RenderGraph/MaterialProgram"
EFFECT_EXECUTION_ROOT = SCENE_ROOT / "RenderGraph/EffectExecution"
sys.path.insert(0, str(REPOSITORY_ROOT / "script"))

from scene_swift_source_sets import scene_swift_sources


SWIFT_SOURCES = [
    *scene_swift_sources("authored_shader_frontend_core"),
    MATERIAL_PROGRAM_ROOT
    / "SceneResolvedMaterialGenericShaderProgramArtifact.swift",
    *scene_swift_sources("generic_shader_compiler_preparation_implementation"),
    MATERIAL_PROGRAM_ROOT / "SceneResolvedMaterialGenericShaderRouteProfile.swift",
    MATERIAL_PROGRAM_ROOT / "SceneResolvedMaterialGenericShaderArtifactCache.swift",
    MATERIAL_PROGRAM_ROOT
    / "SceneResolvedMaterialGenericShaderOwnerDeferral.swift",
]

ROUTE_SOURCE = MATERIAL_PROGRAM_ROOT / "SceneResolvedMaterialGenericShaderRouteProfile.swift"
CACHE_SOURCE = MATERIAL_PROGRAM_ROOT / "SceneResolvedMaterialGenericShaderArtifactCache.swift"
VARIANT_SOURCE = MATERIAL_PROGRAM_ROOT / (
    "SceneResolvedMaterialExecutionCapabilityVariant+Compilation.swift"
)
FAILURE_SOURCE = MATERIAL_PROGRAM_ROOT / "SceneResolvedMaterialProgram.swift"
STAGES_SOURCE = EFFECT_EXECUTION_ROOT / (
    "SceneResolvedMaterialExecutionCapability+Stages.swift"
)
PROGRAM_FIRST_SOURCE = EFFECT_EXECUTION_ROOT / (
    "SceneResolvedMaterialExecutionCapability+ProgramFirstStages.swift"
)
CAPABILITY_SOURCE = EFFECT_EXECUTION_ROOT / (
    "SceneResolvedMaterialExecutionCapability.swift"
)
OWNER_ADMISSION_SOURCE = SCENE_ROOT / "RenderGraph" / (
    "SceneResolvedMaterialUnitPreviousBlurredCompositeOwnerAdmission.swift"
)
STANDARD_BLUR_SOURCE = SCENE_ROOT / "RenderGraph/SceneAuthoredStandardBlurPlanner.swift"
DEDICATED_COMPILERS_SOURCE = SCENE_ROOT / (
    "RenderGraph/EffectCompilation/SceneEffectStageDedicatedCompilers.swift"
)
STAGE_COMPILE_MODEL_SOURCE = SCENE_ROOT / (
    "RenderGraph/EffectCompilation/SceneEffectStageCompileModel.swift"
)
DEDICATED_STAGES_SOURCE = SCENE_ROOT / (
    "RenderGraph/EffectCompilation/SceneEffectProgramCompiler+DedicatedStages.swift"
)
LAUNCH_SOURCE = SCENE_ROOT / "Runtime/SceneDesktopWallpaperHost+Launch.swift"
FINALIZER_SOURCE = MATERIAL_PROGRAM_ROOT / "SceneResolvedMaterialProgramFinalizer.swift"


HARNESS = r'''
import Foundation

private struct Output: Codable {
    let status: String
    let code: String?
    let requestKey: String
    let permitsBoundedFrontend: Bool?
    let profile: String
    let state: String
    let fallbackOwner: String
    let alphaOwner: String
    let compositeOwner: String
    let alphaState: String
    let compositeState: String
    let boundedFrontendAccepted: Bool?
}

private let vertex = """
attribute vec3 a_Position;
attribute vec2 a_TexCoord;
varying vec2 v_TexCoord;
void main() {
    gl_Position = vec4(a_Position, 1.0);
    v_TexCoord = a_TexCoord;
}
"""

private let alpha = """
uniform sampler2D g_Texture0;
void main() {
    float weight = 0.0;
    vec4 result = CAST4(0.0), sample;
    { sample = texSample2D(g_Texture0, vec2(0.0)); result += sample * sample.a; weight += sample.a; }
    { sample = texSample2D(g_Texture0, vec2(1.0)); result += sample * sample.a; weight += sample.a; }
    gl_FragColor.rgb = result.rgb / max(0.001, weight);
    gl_FragColor.a = result.a / 2.0;
}
"""

private let interpolated = """
uniform sampler2D g_Texture0;
uniform sampler2D g_Texture1;
uniform float g_Blend;
varying vec2 v_TexCoord;
void main() {
    vec4 recent = texSample2D(g_Texture0, v_TexCoord);
    vec4 retained = texSample2D(g_Texture1, v_TexCoord);
    gl_FragColor = mix(retained, recent, g_Blend);
}
"""

private let preserved = """
uniform sampler2D g_Texture0;
uniform sampler2D g_Texture2;
varying vec2 v_TexCoord;
void main() {
    vec4 filtered = texSample2D(g_Texture0, v_TexCoord);
    vec2 control = texSample2D(g_Texture2, v_TexCoord).rg;
    if (control.x > 0.01) {
        filtered.rgb += texSample2D(
            g_Texture0, v_TexCoord + vec2(control.y)
        ).rgb;
    }
    gl_FragColor = filtered;
}
"""

private let spatialWeighted = """
uniform sampler2D g_Texture0;
uniform sampler2D g_Texture1;
uniform sampler2D g_Texture2;
uniform float g_Opacity;
varying vec2 v_TexCoord;
vec3 ApplyBlending(
    const int mode,
    in vec3 base,
    in vec3 blend,
    in float opacity
) {
    return mix(base, blend, opacity);
}
void main() {
    vec4 carrier = texSample2D(g_Texture0, v_TexCoord);
    vec4 replacement = texSample2D(g_Texture1, v_TexCoord);
    float weight = replacement.a * g_Opacity;
    vec2 point = v_TexCoord;
    vec2 falloff = texSample2D(g_Texture2, point).ra;
    weight *= falloff.x * falloff.y;
    carrier.rgb = ApplyBlending(
        0, carrier.rgb, replacement.rgb, weight
    );
    gl_FragColor = carrier;
}
"""

private let composite = """
uniform sampler2D g_Texture3;
uniform sampler2D g_Texture5;
uniform vec3 g_CompositeColor;
varying vec2 v_TexCoord;
vec4 identityComposite(vec4 oldColor, vec4 effectColor) {
    return effectColor;
}
vec4 compositeCarrier(vec4 oldColor, vec4 effectColor) {
    effectColor.rgb *= g_CompositeColor;
    return identityComposite(oldColor, effectColor);
}
void main() {
    vec4 blurred = texSample2D(g_Texture3, v_TexCoord);
    vec4 previous = texSample2D(g_Texture5, v_TexCoord.xy);
    float mask = 1.0;
    float divisor = mix(blurred.a, 1, step(blurred.a, 0));
    blurred = compositeCarrier(
        previous, vec4(blurred.rgb / divisor, blurred.a)
    );
    blurred = mix(previous, blurred, mask);
    gl_FragColor = blurred;
}
"""

private func profile(
    transfer: SceneShaderColorTransfer,
    alphaSlot: Int? = nil,
    composite: (Int, Int)? = nil
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
        alphaWeightedSampleAverageSourceSlot: alphaSlot,
        preservedAlphaRGBFilterSourceSlot: nil,
        preservedAlphaRGBFilterTextureSlots: [],
        unitCompositeBlurredSlot: composite?.0,
        unitCompositePreviousSlot: composite?.1,
        hasExternalProviderTexture: false,
        producesScalarRedOutput: false,
        isSourceIndependentPremultipliedOutput: false,
        graphTextureSlots: composite.map { Set([$0.0]) } ?? [],
        graphInputTextureSlots: composite.map { Set([$0.0, $0.1]) }
            ?? alphaSlot.map { Set([$0]) } ?? [],
        r8TextureSlots: [],
        hasDefaultedOpacityMaskSampler: false,
        hasOnlyGraphInputSampler: alphaSlot != nil,
        hasStageScopedUniformBindings: false,
        hasStereoAudioSpectrumArrays: false,
        hasLocalizedMutableFragmentVarying: false
    )
}

@main
private struct Harness {
    static func main() throws {
        let mode = CommandLine.arguments[1]
        let isAlpha = mode == "alpha"
        let isPreserved = mode == "preserved"
        let isSpatialWeighted = mode == "spatial-weighted"
        let isComposite = mode.hasPrefix("composite")
        let isCompositeOwned = mode == "composite"
        let fragment = isAlpha ? alpha
            : isPreserved ? preserved
            : isSpatialWeighted ? spatialWeighted
            : isComposite ? composite : interpolated
        let resolution = SceneResolvedMaterialGenericShaderArtifactCache.resolve(
            vertexSource: vertex,
            fragmentSource: fragment,
            unitCompositeBlurredSlot: isCompositeOwned ? 3 : nil,
            unitCompositePreviousSlot: isCompositeOwned ? 5 : nil,
            graphTextureSlots: isComposite ? [3] : isPreserved ? [2] : [],
            graphInputTextureSlots:
                isAlpha ? [0] : isPreserved ? [0, 2]
                    : isSpatialWeighted ? [0]
                    : isComposite ? [3, 5] : [0, 1],
            spatialWeightedColorBlendSourceSlot: isSpatialWeighted ? 0 : nil,
            spatialWeightedColorBlendActiveSlots: isSpatialWeighted
                ? [0, 1, 2] : [],
            spatialWeightedColorBlendTypedAuxiliarySlots: isSpatialWeighted
                ? [1, 2] : [],
            hasOnlyGraphInputSampler: isAlpha
        )
        let alphaProfile = profile(
            transfer: .straightAlpha(textureSlot: 0), alphaSlot: 0
        )
        let compositeProfile = profile(
            transfer: .straightAlphaPreserving(textureSlot: 3),
            composite: (3, 5)
        )
        let common = (
            alphaOwner: alphaProfile.validatedRollbackOwner.rawValue,
            compositeOwner: compositeProfile.validatedRollbackOwner.rawValue,
            alphaState: alphaProfile.defaultRouteState.rawValue,
            compositeState: compositeProfile.defaultRouteState.rawValue
        )
        let output: Output
        switch resolution {
        case let .ownerDeferred(code, requestKey, decision):
            output = .init(
                status: "owner-deferred", code: code, requestKey: requestKey,
                permitsBoundedFrontend: nil,
                profile: decision.profile, state: decision.state,
                fallbackOwner: decision.fallbackOwner,
                alphaOwner: common.alphaOwner,
                compositeOwner: common.compositeOwner,
                alphaState: common.alphaState,
                compositeState: common.compositeState,
                boundedFrontendAccepted: nil
            )
        case let .unavailable(code, requestKey, permits, decision):
            let boundedAccepted = permits
                ? SceneAuthoredShaderFrontend.compile(
                    vertexSource: vertex,
                    fragmentSource: fragment
                ).program != nil
                : false
            output = .init(
                status: "unavailable", code: code, requestKey: requestKey,
                permitsBoundedFrontend: permits,
                profile: decision.profile, state: decision.state,
                fallbackOwner: decision.fallbackOwner,
                alphaOwner: common.alphaOwner,
                compositeOwner: common.compositeOwner,
                alphaState: common.alphaState,
                compositeState: common.compositeState,
                boundedFrontendAccepted: boundedAccepted
            )
        case let .accepted(_, requestKey, decision):
            output = .init(
                status: "accepted", code: nil, requestKey: requestKey,
                permitsBoundedFrontend: nil,
                profile: decision.profile, state: decision.state,
                fallbackOwner: decision.fallbackOwner,
                alphaOwner: common.alphaOwner,
                compositeOwner: common.compositeOwner,
                alphaState: common.alphaState,
                compositeState: common.compositeState,
                boundedFrontendAccepted: nil
            )
        }
        print(String(decoding: try JSONEncoder().encode(output), as: UTF8.self))
    }
}
'''


@unittest.skipUnless(shutil.which("swiftc"), "swiftc is required")
class SceneGenericShaderIncumbentOwnerDeferredTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.build_directory = tempfile.TemporaryDirectory(
            prefix="mwx-generic-incumbent-owner-"
        )
        root = Path(cls.build_directory.name)
        harness = root / "Harness.swift"
        harness.write_text(HARNESS, encoding="utf-8")
        cls.binary = root / "generic-incumbent-owner-harness"
        environment = os.environ.copy()
        environment["CLANG_MODULE_CACHE_PATH"] = str(root / "clang-cache")
        environment["SWIFT_MODULECACHE_PATH"] = str(root / "swift-cache")
        completed = subprocess.run(
            [
                "swiftc", "-parse-as-library",
                *(str(path) for path in SWIFT_SOURCES),
                str(harness), "-framework", "Security", "-o", str(cls.binary),
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

    def run_route(
        self,
        root: Path,
        mode: str,
        profile_routes: str | None = None,
    ) -> tuple[dict, str, Path, Path]:
        requests = root / "requests"
        cache = root / "cache"
        requests.mkdir(exist_ok=True)
        cache.mkdir(exist_ok=True)
        environment = os.environ.copy()
        environment.update({
            "MWX_SCENE_GENERIC_SHADER_REQUESTS": str(requests),
            "MWX_SCENE_GENERIC_SHADER_CACHE": str(cache),
        })
        if profile_routes is None:
            environment.pop("MWX_SCENE_GENERIC_SHADER_PROFILE_ROUTES", None)
        else:
            environment["MWX_SCENE_GENERIC_SHADER_PROFILE_ROUTES"] = profile_routes
        environment.pop("MWX_SCENE_GENERIC_SHADER_ROUTE", None)
        completed = subprocess.run(
            [str(self.binary), mode],
            cwd=REPOSITORY_ROOT,
            env=environment,
            capture_output=True,
            text=True,
        )
        self.assertEqual(completed.returncode, 0, completed.stderr)
        return json.loads(completed.stdout), completed.stderr, requests, cache

    @staticmethod
    def artifact(
        key: str,
        slot: int = 0,
        transfer: str = "straight-alpha",
        auxiliary_channel_uses: dict[int, str] | None = None,
        output_channel_use: str = "unproven",
    ) -> dict:
        auxiliary_channel_uses = auxiliary_channel_uses or {}
        slots = [slot, *sorted(auxiliary_channel_uses)]
        transforms = " ".join(
            f"float4 mwxTexture{texture_slot}Transform{component};"
            for texture_slot in slots for component in range(2)
        )
        metal = """
#include <metal_stdlib>
using namespace metal;
struct Uniforms {
    float2 mwxRenderSize;
    TRANSFORMS
};
vertex float4 mwxGenericVertex(
    uint vertexID [[vertex_id]], constant Uniforms& u [[buffer(8)]]) {
    return float4(0.0);
}
fragment float4 mwxGenericFragment(
    texture2d<float> g_TextureSLOT [[texture(SLOT)]],
    constant Uniforms& u [[buffer(8)]]) {
    return g_TextureSLOT.sample(
        sampler(),
        u.mwxTextureSLOTTransform0.xy
            + u.mwxTextureSLOTTransform0.zw * 0.5
            + u.mwxTextureSLOTTransform1.xy * 0.5
    );
}
""".replace("TRANSFORMS", transforms).replace("SLOT", str(slot)).strip() + "\n"
        return {
            "schemaVersion": 6,
            "kind": "scene-generic-shader-program-artifact",
            "backendID": "glslang-spirv-cross-msl-v2",
            "requestKey": key,
            "outputSemantics": "color",
            "program": {
                "metalSource": metal,
                "metalSourceSHA256": hashlib.sha256(metal.encode()).hexdigest(),
                "vertexFunctionName": "mwxGenericVertex",
                "fragmentFunctionName": "mwxGenericFragment",
                "uniformBufferIndex": 8,
                "uniformLayout": {
                    "fields": [
                        {
                            "name": "mwxRenderSize",
                            "authoredName": "mwxRenderSize",
                            "type": "float2",
                            "offset": 0,
                        },
                    ] + [
                        {
                            "name": f"mwxTexture{texture_slot}Transform{component}",
                            "authoredName":
                                f"mwxTexture{texture_slot}Transform{component}",
                            "type": "float4",
                            "offset": 16 + index * 32 + component * 16,
                        }
                        for index, texture_slot in enumerate(slots)
                        for component in range(2)
                    ],
                    "byteSize": 16 + len(slots) * 32,
                },
                "textureBindings": [
                    {
                        "name": f"g_Texture{texture_slot}",
                        "slot": texture_slot,
                        "channelUse": (
                            "unproven" if texture_slot == slot
                            else auxiliary_channel_uses[texture_slot]
                        ),
                    }
                    for texture_slot in slots
                ],
                "staticLoopWork": 0,
                "fragmentOutputChannelUse": output_channel_use,
                "colorTransfer": {"kind": transfer, "slot": slot},
            },
        }

    def test_shared_alpha_is_generic_only_with_explicit_bounded_rollback(
        self,
    ) -> None:
        profile = "source-proven-graph-input-alpha-weighted-sample-average"
        with tempfile.TemporaryDirectory(prefix="mwx-shared-alpha-owner-") as directory:
            root = Path(directory)
            missing, missing_log, requests, cache = self.run_route(root, "alpha")
            self.assertEqual(missing["status"], "unavailable")
            self.assertEqual(missing["profile"], profile)
            self.assertEqual(missing["state"], "generic-only")
            self.assertEqual(missing["fallbackOwner"], "bounded-frontend")
            self.assertFalse(missing["permitsBoundedFrontend"])
            self.assertFalse(missing["boundedFrontendAccepted"])
            self.assertEqual(missing["alphaOwner"], "bounded-frontend")
            self.assertEqual(missing["alphaState"], "generic-only")
            self.assertEqual(missing["compositeOwner"], "none")
            self.assertEqual(missing["compositeState"], "generic-only")
            self.assertIn(
                f"state=generic-only profile={profile} outcome=rejected",
                missing_log,
            )
            self.assertEqual(len(list(requests.glob("*.json"))), 1)
            artifact_path = cache / f"{missing['requestKey']}.json"
            artifact = self.artifact(missing["requestKey"])
            artifact_path.write_text(json.dumps(artifact), encoding="utf-8")

            accepted, accepted_log, _, _ = self.run_route(root, "alpha")
            self.assertEqual(accepted["status"], "accepted")
            self.assertEqual(accepted["state"], "generic-only")
            self.assertEqual(accepted["fallbackOwner"], "bounded-frontend")
            self.assertIn("outcome=accepted reason=-", accepted_log)

            artifact["program"]["metalSourceSHA256"] = "0" * 64
            artifact_path.write_text(json.dumps(artifact), encoding="utf-8")
            bad, bad_log, _, _ = self.run_route(root, "alpha")
            self.assertEqual(bad["status"], "unavailable")
            self.assertEqual(bad["code"], "artifact-contract-rejected")
            self.assertFalse(bad["permitsBoundedFrontend"])
            self.assertFalse(bad["boundedFrontendAccepted"])
            self.assertIn(
                "outcome=rejected reason=artifact-contract-rejected", bad_log
            )

            disabled, disabled_log, _, _ = self.run_route(
                root, "alpha", f"{profile}=disable-generic"
            )
            self.assertEqual(disabled["status"], "unavailable")
            self.assertEqual(disabled["code"], "route-disabled")
            self.assertEqual(disabled["fallbackOwner"], "bounded-frontend")
            self.assertTrue(disabled["boundedFrontendAccepted"])
            self.assertIn("outcome=fallback reason=route-disabled", disabled_log)

    def test_spatial_weighted_owner_rejects_bad_artifact_and_rolls_back_shared(
        self,
    ) -> None:
        profile = "source-proven-graph-input-spatial-weighted-color-blend"
        with tempfile.TemporaryDirectory(
            prefix="mwx-spatial-weighted-owner-"
        ) as directory:
            root = Path(directory)
            missing, missing_log, requests, cache = self.run_route(
                root, "spatial-weighted"
            )
            self.assertEqual(missing["status"], "unavailable")
            self.assertEqual(missing["profile"], profile)
            self.assertEqual(missing["state"], "generic-only")
            self.assertEqual(missing["fallbackOwner"], "bounded-frontend")
            self.assertFalse(missing["permitsBoundedFrontend"])
            self.assertFalse(missing["boundedFrontendAccepted"])
            self.assertEqual(len(list(requests.glob("*.json"))), 1)
            self.assertIn(
                f"state=generic-only profile={profile} outcome=rejected",
                missing_log,
            )

            artifact_path = cache / f"{missing['requestKey']}.json"
            artifact = self.artifact(
                missing["requestKey"],
                transfer="straight-alpha-preserving",
                auxiliary_channel_uses={1: "wholeVector", 2: "wholeVector"},
                output_channel_use="redDefined",
            )
            artifact_path.write_text(json.dumps(artifact), encoding="utf-8")
            accepted, accepted_log, _, _ = self.run_route(
                root, "spatial-weighted"
            )
            self.assertEqual(accepted["status"], "accepted")
            self.assertEqual(accepted["state"], "generic-only")
            self.assertIn("outcome=accepted reason=-", accepted_log)

            artifact["program"]["metalSourceSHA256"] = "0" * 64
            artifact_path.write_text(json.dumps(artifact), encoding="utf-8")
            rejected, rejected_log, _, _ = self.run_route(
                root, "spatial-weighted"
            )
            self.assertEqual(rejected["status"], "unavailable")
            self.assertEqual(rejected["code"], "artifact-contract-rejected")
            self.assertFalse(rejected["permitsBoundedFrontend"])
            self.assertFalse(rejected["boundedFrontendAccepted"])
            self.assertIn(
                "outcome=rejected reason=artifact-contract-rejected",
                rejected_log,
            )

            disabled, disabled_log, _, _ = self.run_route(
                root,
                "spatial-weighted",
                f"{profile}=disable-generic",
            )
            self.assertEqual(disabled["status"], "unavailable")
            self.assertEqual(disabled["code"], "route-disabled")
            self.assertTrue(disabled["permitsBoundedFrontend"])
            self.assertTrue(disabled["boundedFrontendAccepted"])
            self.assertIn("outcome=fallback reason=route-disabled", disabled_log)

    def test_preserved_alpha_rgb_filter_is_generic_only_without_secondary_owner(
        self,
    ) -> None:
        profile = "source-proven-graph-input-preserved-alpha-rgb-filter"
        with tempfile.TemporaryDirectory(prefix="mwx-preserved-rgb-owner-") as directory:
            root = Path(directory)
            missing, missing_log, requests, cache = self.run_route(root, "preserved")
            self.assertEqual(missing["status"], "unavailable")
            self.assertEqual(missing["profile"], profile)
            self.assertEqual(missing["state"], "generic-only")
            self.assertEqual(missing["fallbackOwner"], "none")
            self.assertFalse(missing["permitsBoundedFrontend"])
            self.assertFalse(missing["boundedFrontendAccepted"])
            self.assertEqual(len(list(requests.glob("*.json"))), 1)
            self.assertEqual(list(cache.iterdir()), [])
            self.assertIn(
                f"state=generic-only profile={profile} outcome=rejected",
                missing_log,
            )

            (cache / f"{missing['requestKey']}.json").write_text(
                "{invalid-json", encoding="utf-8"
            )
            rejected, rejected_log, _, _ = self.run_route(root, "preserved")
            self.assertEqual(rejected["code"], "artifact-invalid-json")
            self.assertFalse(rejected["permitsBoundedFrontend"])
            self.assertFalse(rejected["boundedFrontendAccepted"])
            self.assertIn(
                "outcome=rejected reason=artifact-invalid-json", rejected_log
            )

            disabled, disabled_log, _, _ = self.run_route(
                root, "preserved", f"{profile}=disable-generic"
            )
            self.assertEqual(disabled["code"], "route-disabled")
            self.assertEqual(disabled["fallbackOwner"], "none")
            self.assertFalse(disabled["permitsBoundedFrontend"])
            self.assertFalse(disabled["boundedFrontendAccepted"])
            self.assertIn("outcome=fallback reason=route-disabled", disabled_log)

    def test_unit_composite_generic_only_rejects_to_previous_current_without_secondary_owner(
        self,
    ) -> None:
        profile = "source-proven-unit-previous-blurred-composite"
        with tempfile.TemporaryDirectory(prefix="mwx-unit-composite-owner-") as directory:
            root = Path(directory)
            missing, missing_log, requests, cache = self.run_route(root, "composite")
            self.assertEqual(missing["status"], "unavailable")
            self.assertTrue(missing["code"].startswith("compiler-configuration-"))
            self.assertEqual(missing["profile"], profile)
            self.assertEqual(missing["state"], "generic-only")
            self.assertEqual(missing["fallbackOwner"], "none")
            self.assertFalse(missing["permitsBoundedFrontend"])
            self.assertEqual(list(cache.iterdir()), [])
            self.assertEqual(len(list(requests.glob("*.json"))), 1)
            self.assertIn("compiler lifecycle", missing_log)

            artifact_path = cache / f"{missing['requestKey']}.json"
            artifact = self.artifact(
                missing["requestKey"], slot=3,
                transfer="straight-alpha-preserving",
            )
            artifact_path.write_text(json.dumps(artifact), encoding="utf-8")
            accepted, accepted_log, _, _ = self.run_route(root, "composite")
            self.assertEqual(accepted["status"], "accepted")
            self.assertEqual(accepted["state"], "generic-only")
            self.assertIn("outcome=accepted reason=-", accepted_log)

            artifact["program"]["metalSourceSHA256"] = "0" * 64
            artifact_path.write_text(json.dumps(artifact), encoding="utf-8")
            rejected, rejected_log, _, _ = self.run_route(root, "composite")
            self.assertEqual(rejected["status"], "unavailable")
            self.assertEqual(rejected["code"], "artifact-contract-rejected")
            self.assertFalse(rejected["permitsBoundedFrontend"])
            self.assertIn(
                "outcome=rejected reason=artifact-contract-rejected",
                rejected_log,
            )

            disabled, disabled_log, _, _ = self.run_route(
                root, "composite", f"{profile}=disable-generic"
            )
            self.assertEqual(disabled["status"], "unavailable")
            self.assertEqual(disabled["code"], "route-disabled")
            self.assertEqual(disabled["fallbackOwner"], "none")
            self.assertFalse(disabled["permitsBoundedFrontend"])
            self.assertFalse(disabled["boundedFrontendAccepted"])
            self.assertIn("outcome=fallback reason=route-disabled", disabled_log)

    def test_source_proven_composite_without_whole_stage_owner_is_quarantined(
        self,
    ) -> None:
        profile = "source-proven-unit-previous-blurred-composite-unowned"
        with tempfile.TemporaryDirectory(prefix="mwx-unit-composite-unowned-") as directory:
            result, log, requests, cache = self.run_route(
                Path(directory), "composite-unowned"
            )
            self.assertEqual(result["status"], "owner-deferred")
            self.assertEqual(result["code"], "route-observe-only")
            self.assertEqual(result["profile"], profile)
            self.assertEqual(result["state"], "observe-only")
            self.assertEqual(result["fallbackOwner"], "program-first-incumbent")
            self.assertEqual(len(list(requests.glob("*.json"))), 1)
            self.assertEqual(list(cache.iterdir()), [])
            self.assertIn("outcome=observed reason=route-observe-only", log)

    def test_generic_only_rollback_and_owner_revocation_remain_distinct(self) -> None:
        profile = "source-proven-scalar-color-interpolation"
        with tempfile.TemporaryDirectory(prefix="mwx-generic-only-owner-") as directory:
            root = Path(directory)
            observed, _, _, cache = self.run_route(
                root, "interpolated", f"{profile}=observe-only"
            )
            self.assertEqual(observed["status"], "unavailable")
            self.assertEqual(observed["fallbackOwner"], "bounded-frontend")
            (cache / f"{observed['requestKey']}.json").write_text(
                "{invalid-json", encoding="utf-8"
            )
            rejected, rejected_log, _, _ = self.run_route(root, "interpolated")
            self.assertEqual(rejected["status"], "unavailable")
            self.assertEqual(rejected["code"], "artifact-invalid-json")
            self.assertFalse(rejected["permitsBoundedFrontend"])
            self.assertIn("outcome=rejected reason=artifact-invalid-json", rejected_log)

            disabled, _, _, _ = self.run_route(
                root, "interpolated", f"{profile}=disable-generic"
            )
            self.assertEqual(disabled["status"], "unavailable")
            self.assertEqual(disabled["code"], "route-disabled")
            self.assertTrue(disabled["permitsBoundedFrontend"])

    def test_typed_deferred_failure_reaches_only_validated_incumbent_flow(self) -> None:
        variant = VARIANT_SOURCE.read_text(encoding="utf-8")
        failure = FAILURE_SOURCE.read_text(encoding="utf-8")
        stages = STAGES_SOURCE.read_text(encoding="utf-8")
        program_first = PROGRAM_FIRST_SOURCE.read_text(encoding="utf-8")
        cache = CACHE_SOURCE.read_text(encoding="utf-8")
        route = ROUTE_SOURCE.read_text(encoding="utf-8")
        owner_admission = OWNER_ADMISSION_SOURCE.read_text(encoding="utf-8")
        standard_blur = STANDARD_BLUR_SOURCE.read_text(encoding="utf-8")
        dedicated_compilers = DEDICATED_COMPILERS_SOURCE.read_text(encoding="utf-8")

        self.assertIn("case ownerDeferred(", cache)
        self.assertIn("case genericProductOwnerDeferred", failure)
        deferred = variant.index("case let .ownerDeferred")
        bounded = variant.index("case let .unavailable", deferred)
        self.assertIn(".genericProductOwnerDeferred", variant[deferred:bounded])
        self.assertNotIn("onBoundedFrontendCompilation()", variant[deferred:bounded])
        self.assertIn("materialFailure.code == .genericProductOwnerDeferred", stages)
        self.assertIn("material-generic-incumbent-owner-deferred", stages)

        self.assertNotIn(
            'programFailure.code == "material-generic-incumbent-owner-deferred"',
            program_first,
        )
        passthrough = program_first[program_first.index(
            "private static func visualFailureMayPassthrough("
        ):]
        self.assertNotIn("material-generic-incumbent-owner-deferred", passthrough)
        for incumbent_gate in (
            "guard let program = programsByKey[effect.key]?.first else",
            "let pairLeaf = dedicatedLeafKeys.contains(effect.key)",
            "let logicalTargetStage = dedicatedGraphStageKeys.contains(effect.key)",
            "let identityMatches = program.effectKey == effect.key",
            "let dynamicTargetsExecutable = dedicatedDynamicTargetsAreExecutable(",
            "let sourceRouteExecutable =",
            "guard pairLeaf || logicalTargetStage,",
            "stages.append(.dedicated(",
        ):
            self.assertIn(incumbent_gate, program_first)
        no_incumbent = program_first.index(
            "guard let program = programsByKey[effect.key]?.first else"
        )
        incumbent = program_first.index("let pairLeaf =", no_incumbent)
        self.assertIn("return .failure(programFailure)", program_first[
            no_incumbent:incumbent
        ])
        self.assertIn("case programFirstIncumbent", route)
        default_routes = route[route.index("var defaultRouteState"):]
        prefer_generic_cases, generic_only_tail = default_routes.split(
            ".preferGeneric", 1
        )
        generic_only_cases = generic_only_tail.split(".genericOnly", 1)[0]
        self.assertNotIn(
            ".sourceProvenUnitPreviousBlurredComposite,",
            prefer_generic_cases,
        )
        self.assertNotIn(
            ".sourceProvenGraphInputAlphaWeightedSampleAverage,",
            prefer_generic_cases,
        )
        self.assertNotIn(
            ".sourceProvenGraphInputPreservedAlphaRGBFilter,",
            prefer_generic_cases,
        )
        self.assertIn(
            ".sourceProvenGraphInputAlphaWeightedSampleAverage,",
            generic_only_cases,
        )
        self.assertIn(
            ".sourceProvenGraphInputPreservedAlphaRGBFilter,",
            generic_only_cases,
        )
        self.assertIn(
            ".sourceProvenUnitPreviousBlurredComposite,",
            generic_only_cases,
        )
        self.assertIn(
            ".sourceProvenGraphInputStageUniformPassthrough:",
            generic_only_cases,
        )
        rollback = route[route.index("var validatedRollbackOwner"):]
        incumbent_cases = rollback.split(".programFirstIncumbent", 1)[0]
        self.assertIn(
            ".sourceProvenGraphInputPreservedAlphaRGBFilter,",
            rollback,
        )
        self.assertIn(
            ".sourceProvenUnitPreviousBlurredComposite:", rollback
        )
        self.assertIn(".none", rollback)
        self.assertIn(
            ".sourceProvenUnitPreviousBlurredCompositeUnowned",
            incumbent_cases,
        )
        owner_gate = owner_admission[owner_admission.index("static func accepts("):]
        self.assertIn("SceneAuthoredStandardBlurPlanner.plan(", owner_gate)
        self.assertIn("let source = sourceCohort(layer)", owner_gate)
        for captured_main_boundary in (
            "case (false, false): .capturedMain",
            "case (true, true): .copyPassthroughCapturedMain",
            "case (false, true), (true, false): nil",
            "layer.childLayerIDs.isEmpty",
            "layer.dependencyLayerIDs.isEmpty",
            "layer.authoredDependencies.isEmpty",
        ):
            self.assertIn(captured_main_boundary, owner_gate)
        self.assertIn("blur.maskTexturePath == nil", owner_gate)
        self.assertIn("SceneAuthoredEffectInputValidator.role(", owner_gate)
        self.assertIn(
            "source == .copyPassthroughCapturedMain",
            owner_gate,
        )
        self.assertIn(".userPropertyScalarSplat", owner_gate)
        self.assertIn('scale.bindingKeys == ["user", "value"]', owner_gate)
        self.assertIn("components.count == 1 || components.count == 2", owner_gate)
        self.assertIn("components.count == 1 || components[0] == components[1]", owner_gate)
        self.assertIn(
            '"typed-user-scalar-splat-owner-revoked-to-material-program"',
            owner_gate,
        )
        self.assertIn(
            '"captured-main-copy-passthrough-static-owner-revoked-to-material-program"',
            owner_gate,
        )
        self.assertIn(
            '"captured-main-copy-passthrough-typed-user-scalar-splat-'
            'owner-revoked-to-material-program"',
            owner_gate,
        )
        revocation_gate = owner_admission[
            owner_admission.index("static func acceptsDedicatedRevocation("):
        ]
        self.assertIn("shaderContracts: [SceneShaderContract]", revocation_gate)
        self.assertIn("SceneResolvedMaterialTemplateCompiler.compile(", revocation_gate)
        self.assertIn("SceneAuthoredShaderPreparation.prepareShaderStages(", revocation_gate)
        self.assertIn("template.textureSlots.indices.contains(slot)", revocation_gate)
        self.assertIn("template.textureSlots[slot] != nil", revocation_gate)
        self.assertNotIn("($0, true)", revocation_gate)
        self.assertIn("userPropertyScalarSplatConsumersAdmit(", revocation_gate)
        self.assertIn("[1, 2].allSatisfy", revocation_gate)
        self.assertIn(
            "dynamic.valueContributors == [.userProperty(propertyKey)]",
            revocation_gate,
        )
        self.assertIn('dynamic.authoredBindingKeys == ["user", "value"]', revocation_gate)
        self.assertIn('materialKey: "scale"', revocation_gate)
        self.assertIn("type: .float2", revocation_gate)
        self.assertIn("stage: .vertex", revocation_gate)
        self.assertIn("defaultComponents.count == 2", revocation_gate)
        self.assertIn(
            "defaultComponents[0] == defaultComponents[1]", revocation_gate
        )
        self.assertIn(
            "SceneResolvedMaterialUnitPreviousBlurredCompositeEligibility.slots(",
            revocation_gate,
        )
        self.assertIn(
            "SceneAuthoredShaderColorTransferAnalyzer.analyze(", revocation_gate
        )
        self.assertIn('combos["KERNEL", default: 0] == 0', standard_blur)
        standard_compiler = dedicated_compilers[
            dedicated_compilers.index("extension SceneAuthoredStandardBlurPlanner"):
            dedicated_compilers.index(
                "extension SceneAuthoredXRayPlanner"
            )
        ]
        self.assertNotIn("SceneAuthoredWaterWavesPlanner", dedicated_compilers)
        self.assertNotIn(".waterWaves", dedicated_compilers)
        self.assertIn(
            "acceptsDedicatedRevocation(",
            standard_compiler,
        )
        self.assertIn("dedicatedRevocationDetail(", standard_compiler)
        self.assertNotIn(".accepts(\n", standard_compiler)
        self.assertIn("details: [revocationDetail]", standard_compiler)

        pulse_compiler = dedicated_compilers[
            dedicated_compilers.index("extension SceneAuthoredPulsePlanner"):
        ]
        self.assertIn("colorOnlyRGBProgramOwnerIsProven(", pulse_compiler)
        self.assertIn("staticAlphaOnlyProgramOwnerIsProven(", pulse_compiler)
        for static_profile in (
            ".stock2842",
            ".directPhaseSaturateV1",
            ".directPhaseMaxClampV1",
        ):
            self.assertIn(static_profile, pulse_compiler)
        self.assertIn(
            "supportedProfiles.contains(plan.shaderProfile)", pulse_compiler
        )
        for static_guard in (
            "plan.audio == nil || plan.shaderProfile == .stock2842",
            "plan.pulseColor",
            "!plan.pulseAlpha",
        ):
            self.assertIn(static_guard, pulse_compiler)
        self.assertIn("directColorBindingCohortIsProven(plan)", pulse_compiler)
        self.assertIn("exactUserPropertyProducersAreProven(", pulse_compiler)
        for fragment_constant in (
            ".noiseSpeed", ".noiseAmount", ".power", ".tintLow", ".tintHigh",
        ):
            self.assertIn(fragment_constant, pulse_compiler)
        self.assertIn("propertyKey: binding.propertyKey", pulse_compiler)
        self.assertIn("target: binding.dynamicTarget", pulse_compiler)
        self.assertIn("valueType: constant.valueType", pulse_compiler)
        self.assertIn("exactUserPropertyBindingsAreProven(", pulse_compiler)
        self.assertIn("activeUserPropertyConsumersAreProven(", pulse_compiler)
        self.assertIn("uniform.authoredRange == constant.range", pulse_compiler)
        self.assertIn(
            "SceneAuthoredShaderTypedDataRGBFilterAnalyzer.analyze(",
            pulse_compiler,
        )
        self.assertIn(
            ".straightRGBScalarAlphaFact(",
            pulse_compiler,
        )
        for alpha_guard in (
            "plan.audio == nil || plan.shaderProfile == .stock2842",
            "plan.bindings.isEmpty",
            "!plan.pulseColor",
            "plan.pulseAlpha",
            "plan.maskTexturePath == nil",
            "auxiliaryShapeIsProven",
            "plan.shaderProfile == .stock2842",
            "fact.auxiliarySlots.isEmpty",
            "Set(samplers.keys)",
            "graphTargetSlots.isEmpty",
            ".sourceProvenGraphInputStraightRGBScalarAlpha",
        ):
            self.assertIn(alpha_guard, pulse_compiler)
        alpha_owner = pulse_compiler[
            pulse_compiler.index(
                "private nonisolated static func "
                "staticAlphaOnlyProgramOwnerIsProven("
            ):
        ]
        self.assertIn(
            "if plan.audio == nil {\n"
            "                auxiliaryShapeIsProven = "
            "!fact.auxiliarySlots.isEmpty",
            alpha_owner,
        )
        self.assertIn(
            "plan.shaderProfile == .stock2842\n"
            "                    && fact.auxiliarySlots.isEmpty",
            alpha_owner,
        )
        self.assertNotIn(
            "graphTargetSlots.isEmpty,\n"
            "                  !fact.auxiliarySlots.isEmpty,",
            alpha_owner,
        )
        self.assertIn("typedStaticDataAuxiliarySlots(", pulse_compiler)
        self.assertIn("typedAuxiliary == fact.auxiliarySlots", pulse_compiler)
        self.assertIn("exactGenericParametersAreProven(", pulse_compiler)
        self.assertIn(
            "material.combos.keys.allSatisfy(comboNames.contains)",
            pulse_compiler,
        )
        self.assertIn(
            "material.constants.keys.allSatisfy(constantNames.contains)",
            pulse_compiler,
        )
        self.assertIn("template.comboValues == material.combos", pulse_compiler)
        self.assertIn("audioParameters(", pulse_compiler)
        self.assertIn("audio.parameters == plan.audio", pulse_compiler)
        self.assertIn(
            "constantNames.formUnion(SceneAudioResponseAdmission.constantKeys)",
            pulse_compiler,
        )
        self.assertIn(".defaultRouteState == .genericOnly", pulse_compiler)
        self.assertIn(".validatedRollbackOwner == .none", pulse_compiler)
        for revocation_detail in (
            "static-rgb-preserving", "audio-color-only-rgb",
            "typed-user-property-rgb",
            "static-alpha-only", "audio-alpha-only",
        ):
            self.assertIn(
                f'"{revocation_detail}-owner-revoked-to-material-program"',
                pulse_compiler,
            )
        finalizer = FINALIZER_SOURCE.read_text(encoding="utf-8")
        self.assertIn("directUserPropertyRangedValue(", finalizer)
        self.assertIn("guard let liveEncoded else { return nil }", finalizer)
        self.assertIn("[.float, .float2, .float3].contains(field.type)", finalizer)

        compile_model = STAGE_COMPILE_MODEL_SOURCE.read_text(encoding="utf-8")
        dedicated_stages = DEDICATED_STAGES_SOURCE.read_text(encoding="utf-8")
        launch = LAUNCH_SOURCE.read_text(encoding="utf-8")
        self.assertIn(
            "userPropertyProducers: Set<SceneDynamicUserPropertyProducer>",
            compile_model,
        )
        self.assertIn(
            "userPropertyProducers: Set<SceneDynamicUserPropertyProducer> = []",
            dedicated_stages,
        )
        self.assertIn("valueType: $0.valueType", launch)
        self.assertIn("userPropertyProducers: userPropertyProducers", launch)

        capability = CAPABILITY_SOURCE.read_text(encoding="utf-8")
        self.assertIn("userPropertyValueTypeMatches(", capability)
        self.assertIn(
            'dynamic.authoredBindingKeys == ["user", "value"]', capability
        )
        for typed_component_count in (
            "case 1: expected = .scalar",
            "case 2: expected = .vector2",
            "case 3: expected = .vector3",
            "case 4: expected = .vector4",
        ):
            self.assertIn(typed_component_count, capability)


if __name__ == "__main__":
    unittest.main()
