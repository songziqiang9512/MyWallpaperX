#!/usr/bin/env python3
"""Owner gate for opaque graph-target alpha-weighted loop averages."""

from __future__ import annotations

import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

from script.tests import test_scene_generic_shader_program_artifact as shared
from script.tests import test_scene_resolved_material_program_finalizer as finalizer


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
PROFILE = "source-proven-graph-target-opaque-alpha-weighted-loop-average"
FRAGMENT = """
varying vec2 v_TexCoord[4];
uniform sampler2D g_Texture0;
void main() {
    float weight = 0.0;
    vec3 result = CAST3(0.0);
    vec4 sample;
    for (int i = 0; i < 4; ++i) {
        sample = texSample2D(g_Texture0, v_TexCoord[i]);
        result += sample.rgb * sample.a;
        weight += sample.a;
    }
    gl_FragColor = vec4(result.rgb / max(0.001, weight), 1.0);
}
"""
EXPANDED_FRAGMENT = """
varying vec2 v_TexCoord[4];
uniform sampler2D g_Texture0;
void main() {
    float weight = 0.0;
    vec3 result = CAST3(0.0);
    vec4 sample;
    {
        sample = texSample2D(g_Texture0, v_TexCoord[0]);
        result += sample.rgb * sample.a;
        weight += sample.a;
    }
    {
        sample = texSample2D(g_Texture0, v_TexCoord[1]);
        result += sample.rgb * sample.a;
        weight += sample.a;
    }
    {
        sample = texSample2D(g_Texture0, v_TexCoord[2]);
        result += sample.rgb * sample.a;
        weight += sample.a;
    }
    {
        sample = texSample2D(g_Texture0, v_TexCoord[3]);
        result += sample.rgb * sample.a;
        weight += sample.a;
    }
    gl_FragColor = vec4(result.rgb / max(0.001, weight), 1.0);
}
"""
UNSEEN_FRAGMENT = """
varying float2 probes[3];
uniform sampler2D g_Texture3;
void main() {
    float totalAlpha = 0.0;
    float3 gathered = float3(0.0);
    float4 texel;
    for (int probe = 0; probe < 3; probe++) {
        texel = texture2D(g_Texture3, probes[probe]);
        gathered += texel.xyz * texel.w;
        totalAlpha += texel.w;
    }
    gl_FragColor = float4(
        gathered.xyz / max(0.0001, totalAlpha),
        1.0
    );
}
"""

LAUNCH_GATE_HARNESS = (
    finalizer.HARNESS.split("@main\nprivate enum Harness", 1)[0]
    + r'''
private enum Harness {
    static func float(_ data: Data, at offset: Int) -> Float {
        data.withUnsafeBytes {
            $0.loadUnaligned(fromByteOffset: offset, as: Float.self)
        }
    }
}

private func launchGateVariant(
    _ base: SceneResolvedMaterialCompiledVariant
) -> SceneResolvedMaterialCompiledVariant {
    let frontend = SceneAuthoredShaderProgram(
        metalSource: base.frontendProgram.metalSource,
        vertexFunctionName: base.frontendProgram.vertexFunctionName,
        fragmentFunctionName: base.frontendProgram.fragmentFunctionName,
        uniformBufferIndex: base.frontendProgram.uniformBufferIndex,
        uniformLayout: base.frontendProgram.uniformLayout,
        textureBindings: base.frontendProgram.textureBindings,
        staticLoopWork: base.frontendProgram.staticLoopWork,
        colorTransfer: .opaque,
        fragmentOutputChannelUse:
            base.frontendProgram.fragmentOutputChannelUse,
        backend: base.frontendProgram.backend
    )
    return .init(
        readinessMask: base.readinessMask,
        textureFormats: base.textureFormats,
        preparedShader: base.preparedShader,
        frontendProgram: frontend,
        routeDecision: base.routeDecision,
        runtimeLoopBounds: base.runtimeLoopBounds,
        activeSamplers: base.activeSamplers,
        graphInputSourceSlotFacts: base.graphInputSourceSlotFacts,
        preservedAlphaRGBColorSlots: base.preservedAlphaRGBColorSlots,
        sourceProvenOpaqueColorSlots: [0],
        conditionalGeneratedRGBInputContract:
            base.conditionalGeneratedRGBInputContract,
        sameAlphaReconstructedRGBInputContract:
            base.sameAlphaReconstructedRGBInputContract,
        activeUniforms: base.activeUniforms,
        neutralTextureResolution: base.neutralTextureResolution
    )
}

private func launchGateToken(
    template: SceneResolvedMaterialTemplate,
    variant: SceneResolvedMaterialCompiledVariant,
    input: SceneAuthoredEffectRenderPlan.TextureIdentity,
    internalTarget: SceneAuthoredEffectRenderPlan.TextureIdentity,
    content: SceneTextureContent?
) -> String {
    let facts = content.map { [internalTarget: $0] } ?? [:]
    guard let failure = SceneResolvedMaterialTextureResolver.launchProgramFailure(
        template: template,
        variants: [variant],
        readinessMask: variant.readinessMask,
        formatSlots: [],
        outputStorage: .color,
        implicitFramebufferIdentity: input,
        graphTextureContentFacts: facts,
        assetStates: [:]
    ) else { return "success" }
    return ([failure.phase.rawValue, failure.code.rawValue]
        + failure.boundedDetails).joined(separator: "/")
}

@main
private enum LaunchGateHarness {
    static func main() throws {
        let input = graphTexture()
        let internalTarget = framebufferTexture()
        let shader = contract(
            revision: "opaque-internal-graph-launch-gate",
            uniformMetadata: nil,
            semanticProbes: false,
            fragmentSourceOverride: """
            varying vec2 v_TexCoord;
            uniform sampler2D g_Texture0;
            void main() {
                vec4 sample = texSample2D(g_Texture0, v_TexCoord);
                gl_FragColor = vec4(sample.rgb, 1.0);
            }
            """
        )
        let material = template(
            shader,
            primaryReference: .graph(internalTarget),
            primaryGraphTextureRole: .framebuffer
        )
        guard case let .success(cache) =
                SceneResolvedMaterialVariantCache.launchValidated(
            template: material,
            maximumVariantCount: 8
        ), case .success = cache.precompileLaunchEnvelope(
            implicitFramebufferIdentity: input
        ), let base = cache.launchEnvelopeCapabilitySnapshot().variants.first(
            where: { variant in
                variant.frontendProgram.textureBindings.contains {
                    $0.slot == 0
                }
            }
        ) else {
            fatalError("launch gate fixture did not compile")
        }
        let variant = launchGateVariant(base)
        let result = [
            "opaque": launchGateToken(
                template: material,
                variant: variant,
                input: input,
                internalTarget: internalTarget,
                content: .color(.resolved(.opaque))
            ),
            "premultiplied": launchGateToken(
                template: material,
                variant: variant,
                input: input,
                internalTarget: internalTarget,
                content: .color(.resolved(.premultipliedAlpha))
            ),
            "data": launchGateToken(
                template: material,
                variant: variant,
                input: input,
                internalTarget: internalTarget,
                content: .data
            ),
            "unresolved": launchGateToken(
                template: material,
                variant: variant,
                input: input,
                internalTarget: internalTarget,
                content: .color(.unresolved)
            ),
            "missing": launchGateToken(
                template: material,
                variant: variant,
                input: input,
                internalTarget: internalTarget,
                content: nil
            ),
        ]
        let data = try JSONSerialization.data(
            withJSONObject: result,
            options: [.sortedKeys]
        )
        FileHandle.standardOutput.write(data)
    }
}
'''
)


class SceneOpaqueAlphaWeightedLoopAverageOwnerTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        shared.SceneGenericShaderProgramArtifactTests.setUpClass()
        cls.binary = shared.SceneGenericShaderProgramArtifactTests.binary

    @classmethod
    def tearDownClass(cls) -> None:
        shared.SceneGenericShaderProgramArtifactTests.tearDownClass()

    def run_harness(self, root: Path, **kwargs):
        return shared.SceneGenericShaderProgramArtifactTests.run_harness(
            self, root, **kwargs
        )

    def artifact(self, key: str) -> dict:
        return shared.SceneGenericShaderProgramArtifactTests.artifact(
            self, key, color_transfer="opaque"
        )

    @staticmethod
    def facts(slot: int = 0) -> dict:
        return {
            "graph_slots": (slot,),
            "graph_input_slots": (slot,),
            "active_slots": (slot,),
            "has_only_graph_input_sampler": True,
        }

    def publish_artifact(
        self, root: Path, fragment: str = EXPANDED_FRAGMENT
    ) -> str:
        observed, _, cache, _ = self.run_harness(
            root,
            route="observe-only",
            fragment=fragment,
            **self.facts(),
        )
        artifact = self.artifact(observed["requestKey"])
        (cache / f"{observed['requestKey']}.json").write_text(
            json.dumps(artifact), encoding="utf-8"
        )
        return observed["requestKey"]

    def test_default_failure_rollback_recovery_and_legacy_route(self) -> None:
        with tempfile.TemporaryDirectory(
            prefix="mwx-opaque-alpha-weighted-loop-owner-"
        ) as directory:
            root = Path(directory)
            request_key = self.publish_artifact(root)

            accepted, _, cache, log = self.run_harness(
                root, route=None, fragment=EXPANDED_FRAGMENT, **self.facts()
            )
            self.assertEqual(accepted["status"], "accepted")
            self.assertEqual(accepted["backend"], "genericCompilerArtifact")
            self.assertEqual(accepted["routeState"], "generic-only")
            self.assertEqual(accepted["routeProfile"], PROFILE)
            self.assertIn(
                f"state=generic-only profile={PROFILE} outcome=accepted", log
            )

            legacy, _, _, _ = self.run_harness(
                root,
                route="disable-generic",
                fragment=EXPANDED_FRAGMENT,
                **self.facts(),
            )
            self.assertEqual(legacy["status"], "accepted")
            self.assertEqual(legacy["routeState"], "generic-only")

            artifact_path = cache / f"{request_key}.json"
            artifact = json.loads(artifact_path.read_text(encoding="utf-8"))
            artifact["program"]["metalSourceSHA256"] = "0" * 64
            artifact_path.write_text(json.dumps(artifact), encoding="utf-8")
            rejected, _, _, rejected_log = self.run_harness(
                root, route=None, fragment=EXPANDED_FRAGMENT, **self.facts()
            )
            self.assertEqual(rejected["code"], "artifact-contract-rejected")
            self.assertFalse(rejected["permitsBoundedFrontend"])
            self.assertIn(
                f"state=generic-only profile={PROFILE} outcome=rejected",
                rejected_log,
            )

            rolled_back, _, _, rollback_log = self.run_harness(
                root,
                route=None,
                profile_routes=f"{PROFILE}=disable-generic",
                fragment=EXPANDED_FRAGMENT,
                **self.facts(),
            )
            self.assertEqual(rolled_back["code"], "route-disabled")
            self.assertTrue(rolled_back["permitsBoundedFrontend"])
            self.assertIn(
                f"state=disable-generic profile={PROFILE} outcome=fallback",
                rollback_log,
            )

            artifact_path.write_text(
                json.dumps(self.artifact(request_key)), encoding="utf-8"
            )
            recovered, _, _, _ = self.run_harness(
                root, route=None, fragment=EXPANDED_FRAGMENT, **self.facts()
            )
            self.assertEqual(recovered["status"], "accepted")
            self.assertEqual(recovered["routeProfile"], PROFILE)

    def test_unseen_names_slot_and_loop_count_are_admitted(self) -> None:
        with tempfile.TemporaryDirectory(
            prefix="mwx-opaque-alpha-weighted-loop-unseen-"
        ) as directory:
            observed, _, _, _ = self.run_harness(
                Path(directory),
                route="observe-only",
                fragment=UNSEEN_FRAGMENT,
                **self.facts(3),
            )
            self.assertEqual(observed["routeProfile"], PROFILE)
            self.assertEqual(observed["routeState"], "generic-only")

        with tempfile.TemporaryDirectory(
            prefix="mwx-opaque-alpha-weighted-expanded-"
        ) as directory:
            observed, _, _, _ = self.run_harness(
                Path(directory),
                route="observe-only",
                fragment=EXPANDED_FRAGMENT,
                **self.facts(),
            )
            self.assertEqual(observed["routeProfile"], PROFILE)
            self.assertEqual(observed["routeState"], "generic-only")

    def test_source_drift_keeps_the_incumbent(self) -> None:
        cases = [
            EXPANDED_FRAGMENT.replace("v_TexCoord[2]", "v_TexCoord[1]"),
            EXPANDED_FRAGMENT.replace(
                "weight += sample.a", "weight += sample.r", 1
            ),
            EXPANDED_FRAGMENT.replace(
                "g_Texture0, v_TexCoord[2]",
                "g_Texture1, v_TexCoord[2]",
            ),
            FRAGMENT.replace("sample.rgb * sample.a", "sample.rgb"),
            FRAGMENT.replace("weight += sample.a", "weight += 1.0"),
            FRAGMENT.replace("max(0.001, weight)", "max(0.001, 1.0)"),
            FRAGMENT.replace("max(0.001, weight)", "max(0.0, weight)"),
            FRAGMENT.replace("vec4(result.rgb / max(0.001, weight), 1.0)",
                             "vec4(result.rgb / max(0.001, weight), 0.5)"),
            FRAGMENT.replace("i < 4", "i <= 4"),
            FRAGMENT.replace("v_TexCoord[4]", "v_TexCoord[5]"),
            FRAGMENT.replace("g_Texture0, v_TexCoord[i]",
                             "g_Texture1, v_TexCoord[i]"),
            FRAGMENT.replace("texSample2D", "texture"),
            FRAGMENT.replace(
                "v_TexCoord[i]",
                "v_TexCoord[int(texture2DLod(g_Texture0, v_TexCoord[0], 0.0).x)]",
            ),
            FRAGMENT.replace(
                "    gl_FragColor =",
                "    result *= 0.5;\n    gl_FragColor =",
            ),
            FRAGMENT.replace(
                "    float weight =",
                "    if (v_TexCoord[0].x > 0.0) { return; }\n    float weight =",
            ),
            FRAGMENT.replace(
                "    gl_FragColor =",
                "    gl_FragColor = vec4(0.0);\n    gl_FragColor =",
            ),
        ]
        for fragment in cases:
            with self.subTest(fragment=fragment[-200:]), tempfile.TemporaryDirectory(
                prefix="mwx-opaque-alpha-weighted-loop-source-reject-"
            ) as directory:
                observed, _, _, log = self.run_harness(
                    Path(directory),
                    route="observe-only",
                    fragment=fragment,
                    **self.facts(),
                )
                self.assertNotEqual(observed["routeProfile"], PROFILE)
                self.assertNotIn(f"profile={PROFILE}", log)

    def test_resource_and_target_drift_keep_the_incumbent(self) -> None:
        cases = [
            {},
            {"graph_slots": (0,), "active_slots": (0,)},
            {
                "graph_slots": (0,),
                "graph_input_slots": (0,),
                "active_slots": (0, 1),
                "has_only_graph_input_sampler": True,
            },
            {**self.facts(), "has_external_provider": True},
            {**self.facts(), "has_only_graph_input_sampler": False},
            {**self.facts(), "produces_scalar_output": True},
            {**self.facts(), "produces_red_green_unorm_output": True},
            {**self.facts(), "preserved_rgba_output": True},
        ]
        for facts in cases:
            with self.subTest(facts=facts), tempfile.TemporaryDirectory(
                prefix="mwx-opaque-alpha-weighted-loop-contract-reject-"
            ) as directory:
                observed, _, _, _ = self.run_harness(
                    Path(directory),
                    route="observe-only",
                    fragment=FRAGMENT,
                    **facts,
                )
                self.assertNotEqual(observed["routeProfile"], PROFILE)

    def test_typed_opaque_input_contract_reaches_frame_finalization(self) -> None:
        compilation = (
            REPOSITORY_ROOT
            / "MyWallpaperX/Core/SteamWorkshopScene/RenderGraph/MaterialProgram"
            / "SceneResolvedMaterialExecutionCapabilityVariant+Compilation.swift"
        ).read_text(encoding="utf-8")
        finalizer = (
            REPOSITORY_ROOT
            / "MyWallpaperX/Core/SteamWorkshopScene/RenderGraph/MaterialProgram"
            / "SceneResolvedMaterialProgramFinalizer+ColorInputs.swift"
        ).read_text(encoding="utf-8")
        launch = (
            REPOSITORY_ROOT
            / "MyWallpaperX/Core/SteamWorkshopScene/RenderGraph/MaterialProgram"
            / "SceneResolvedMaterialTextureResolver+LaunchColor.swift"
        ).read_text(encoding="utf-8")

        self.assertIn(
            ".sourceProvenGraphTargetOpaqueAlphaWeightedLoopAverage.rawValue",
            compilation,
        )
        self.assertIn(
            "sourceProvenOpaqueColorSlots = [fact.sourceSlot]", compilation
        )
        for source in (finalizer, launch):
            self.assertIn(
                "hasResolvedOpaqueColorSampleContract(", source
            )
            self.assertIn("variant.sourceProvenOpaqueColorSlots", source)

    @unittest.skipUnless(shutil.which("swiftc"), "swiftc is required")
    def test_launch_gate_executes_internal_graph_typed_content_contract(self) -> None:
        with tempfile.TemporaryDirectory(
            prefix="mwx-opaque-internal-graph-launch-gate-"
        ) as directory:
            root = Path(directory)
            support = root / "Support.swift"
            harness = root / "LaunchGateHarness.swift"
            binary = root / "launch-gate-test"
            support.write_text(finalizer.SUPPORT, encoding="utf-8")
            harness.write_text(LAUNCH_GATE_HARNESS, encoding="utf-8")
            environment = os.environ.copy()
            environment["MWX_SCENE_GENERIC_SHADER_ROUTE"] = "disable-generic"
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
                    *(str(path) for path in finalizer.SWIFT_SOURCES),
                    str(harness),
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
        self.assertEqual(payload["opaque"], "success", payload)
        expected = "color/colorContractUnproven/source-proven-opaque-color-slots"
        for key in ("premultiplied", "data", "unresolved", "missing"):
            self.assertEqual(payload[key], expected, payload)


if __name__ == "__main__":
    unittest.main()
