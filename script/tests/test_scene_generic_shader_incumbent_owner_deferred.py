#!/usr/bin/env python3

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
from script.tests.scene_generic_shader_test_support import (
    generic_color_program_artifact,
)


SWIFT_SOURCES = [
    *scene_swift_sources("authored_shader_frontend_core"),
    MATERIAL_PROGRAM_ROOT
    / "SceneResolvedMaterialGenericShaderProgramArtifact.swift",
    *scene_swift_sources("generic_shader_compiler_preparation_implementation"),
    MATERIAL_PROGRAM_ROOT / "SceneResolvedMaterialGenericShaderRouteProfile.swift",
    MATERIAL_PROGRAM_ROOT / "SceneResolvedMaterialGenericShaderRouteAuthority.swift",
    MATERIAL_PROGRAM_ROOT / "SceneResolvedMaterialGenericShaderArtifactCache.swift",
    MATERIAL_PROGRAM_ROOT
    / "SceneResolvedMaterialGenericShaderPreparationCoordination.swift",
    MATERIAL_PROGRAM_ROOT / "SceneResolvedMaterialGenericShaderRequest.swift",
    MATERIAL_PROGRAM_ROOT
    / "SceneResolvedMaterialGenericShaderOwnerDeferral.swift",
]

ROUTE_SOURCE = MATERIAL_PROGRAM_ROOT / "SceneResolvedMaterialGenericShaderRouteProfile.swift"
ROUTE_AUTHORITY_SOURCE = MATERIAL_PROGRAM_ROOT / (
    "SceneResolvedMaterialGenericShaderRouteAuthority.swift"
)
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
LAUNCH_SOURCE = SCENE_ROOT / "Runtime/SceneDesktopWallpaperHost+Launch.swift"
FINALIZER_SOURCE = MATERIAL_PROGRAM_ROOT / "SceneResolvedMaterialProgramFinalizer.swift"
SHADER_SCHEMA_SOURCE = MATERIAL_PROGRAM_ROOT / "SceneResolvedMaterialShaderSchema.swift"


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
        hasStereoAudioSpectrumArrays: false
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

    artifact = staticmethod(generic_color_program_artifact)

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


    def test_dedicated_incumbent_runtime_is_retired(self) -> None:
        product = "\n".join(
            path.read_text(encoding="utf-8")
            for path in SCENE_ROOT.rglob("*.swift")
        )
        for symbol in (
            "SceneEffectStageProgram",
            "SceneEffectStageExecutionPlan",
            "SceneEffectStageRenderer",
            "dedicatedStagePrograms",
            "DedicatedFrameInputs",
        ):
            self.assertNotIn(symbol, product)
        program_first = PROGRAM_FIRST_SOURCE.read_text(encoding="utf-8")
        self.assertIn("case let .failure(programFailure):", program_first)
        self.assertIn("visualFailurePassthrough", program_first)


if __name__ == "__main__":
    unittest.main()
