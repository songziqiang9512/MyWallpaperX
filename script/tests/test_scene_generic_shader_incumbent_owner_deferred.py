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

private func owner(
    transfer: SceneShaderColorTransfer,
    alphaSlot: Int? = nil,
    composite: (Int, Int)? = nil
) -> String {
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
    ).validatedRollbackOwner.rawValue
}

@main
private struct Harness {
    static func main() throws {
        let mode = CommandLine.arguments[1]
        let resolution = SceneResolvedMaterialGenericShaderArtifactCache.resolve(
            vertexSource: vertex,
            fragmentSource: mode == "alpha" ? alpha : interpolated,
            graphInputTextureSlots: mode == "alpha" ? [0] : [0, 1],
            hasOnlyGraphInputSampler: mode == "alpha"
        )
        let common = (
            alpha: owner(transfer: .straightAlpha(textureSlot: 0), alphaSlot: 0),
            composite: owner(transfer: .premultipliedAlpha, composite: (3, 5))
        )
        let output: Output
        switch resolution {
        case let .ownerDeferred(code, requestKey, decision):
            output = .init(
                status: "owner-deferred", code: code, requestKey: requestKey,
                permitsBoundedFrontend: nil,
                profile: decision.profile, state: decision.state,
                fallbackOwner: decision.fallbackOwner,
                alphaOwner: common.alpha, compositeOwner: common.composite
            )
        case let .unavailable(code, requestKey, permits, decision):
            output = .init(
                status: "unavailable", code: code, requestKey: requestKey,
                permitsBoundedFrontend: permits,
                profile: decision.profile, state: decision.state,
                fallbackOwner: decision.fallbackOwner,
                alphaOwner: common.alpha, compositeOwner: common.composite
            )
        case let .accepted(_, requestKey, decision):
            output = .init(
                status: "accepted", code: nil, requestKey: requestKey,
                permitsBoundedFrontend: nil,
                profile: decision.profile, state: decision.state,
                fallbackOwner: decision.fallbackOwner,
                alphaOwner: common.alpha, compositeOwner: common.composite
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

    def test_observe_only_and_overrides_preserve_typed_owner_authority(self) -> None:
        profile = "source-proven-graph-input-alpha-weighted-sample-average"
        with tempfile.TemporaryDirectory(prefix="mwx-observed-owner-") as directory:
            root = Path(directory)
            observed, observed_log, requests, cache = self.run_route(root, "alpha")
            self.assertEqual(observed, {
                "status": "owner-deferred",
                "code": "route-observe-only",
                "requestKey": observed["requestKey"],
                "profile": profile,
                "state": "observe-only",
                "fallbackOwner": "program-first-incumbent",
                "alphaOwner": "program-first-incumbent",
                "compositeOwner": "program-first-incumbent",
            })
            self.assertIn(
                f"state=observe-only profile={profile} outcome=observed "
                "reason=route-observe-only",
                observed_log,
            )
            self.assertEqual(len(list(requests.glob("*.json"))), 1)
            self.assertEqual(list(cache.iterdir()), [])
            self.assertNotIn("compiler lifecycle", observed_log)
            self.assertNotIn("generic shader execution", observed_log)

            disabled, disabled_log, _, _ = self.run_route(
                root, "alpha", f"{profile}=disable-generic"
            )
            self.assertEqual(disabled["status"], "owner-deferred")
            self.assertEqual(disabled["code"], "route-disabled")
            self.assertEqual(disabled["fallbackOwner"], "program-first-incumbent")
            self.assertIn("outcome=fallback reason=route-disabled", disabled_log)

            invalid, invalid_log, _, _ = self.run_route(
                root, "alpha", f"{profile}=generic-only"
            )
            self.assertEqual(invalid["status"], "owner-deferred")
            self.assertEqual(invalid["code"], "route-invalid")
            self.assertEqual(invalid["state"], "route-invalid")
            self.assertNotIn("outcome=accepted", invalid_log)

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
        self.assertIn("case .sourceProvenGraphInputAlphaWeightedSampleAverage", route)
        self.assertIn(".sourceProvenUnitPreviousBlurredComposite", route)


if __name__ == "__main__":
    unittest.main()
