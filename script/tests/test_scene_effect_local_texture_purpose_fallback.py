#!/usr/bin/env python3

"""Effect-local launch fallback for an unproven texture purpose."""

from __future__ import annotations

import json
import os
from pathlib import Path
import runpy
import shutil
import subprocess
import tempfile
import unittest


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
SCENE_ROOT = REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene"
FIXTURE = runpy.run_path(
    str(Path(__file__).with_name("test_scene_resolved_material_execution_capability.py"))
)
PROGRAM_FIRST_SOURCE = (
    SCENE_ROOT
    / "RenderGraph/EffectExecution/SceneResolvedMaterialExecutionCapability+ProgramFirstStages.swift"
)
EXECUTOR_SOURCE = (
    SCENE_ROOT
    / "RenderGraph/EffectExecution/SceneResolvedMaterialGraphExecutor+VisualFailurePassthrough.swift"
)


PAIR_STUB = """    let baseCaptureIdentity: SceneAuthoredEffectRenderPlan.TextureIdentity
    let effects: [EffectStep] = []
"""
PAIR_FIXTURE = """    let baseCaptureIdentity: SceneAuthoredEffectRenderPlan.TextureIdentity
    let effects: [EffectStep]

    init(
        baseCaptureIdentity: SceneAuthoredEffectRenderPlan.TextureIdentity,
        effects: [EffectStep] = []
    ) {
        self.baseCaptureIdentity = baseCaptureIdentity
        self.effects = effects
    }
"""


HARNESS_MAIN = r'''
@main
private enum TexturePurposeFallbackHarness {
    private static func pairStep(
        graph: Graph,
        fullFrameWrites: Int,
        inputMember: Int,
        outputMember: Int
    ) -> SceneLayerFullFramePairPlan.EffectStep {
        .init(
            effect: effectKey,
            composeTransitionCount: 0,
            fullFrameOutputWriteCount: fullFrameWrites,
            inputMember: inputMember,
            outputMember: outputMember,
            nodes: graph.nodes.map {
                .init(
                    nodeIndex: $0.nodeIndex,
                    definitionPassIndex: $0.definitionPassIndex,
                    kind: .material
                )
            }
        )
    }

    private static func catalog(
        graph: Graph,
        template: Template,
        pairStep: SceneLayerFullFramePairPlan.EffectStep,
        functionCount: Int = 0,
        issueCode: SceneResolvedMaterialRuntimeCatalog.ResourceDemandIssue.Code =
            .purposeUnproven
    ) -> Catalog {
        let key = SceneResolvedMaterialRuntimeCatalog.Key(
            effect: effectKey,
            nodeIndex: graph.nodes[0].nodeIndex
        )
        let admitted = SceneResolvedMaterialAdmittedLayer(
            layerID: layerID,
            products: [.init(graph: graph, functionCount: functionCount)],
            pairPlan: .init(
                baseCaptureIdentity: graph.effects[0].input,
                effects: [pairStep]
            ),
            dependencyOwnership: .none,
            sourceRoute: .capturedLayerTexture
        )
        return .init(
            admissionCandidates: [.init(
                layerID: layerID,
                result: .success(admitted)
            )],
            materialCatalog: .init(
                entries: [key: .template(template)],
                resourceDemandIssues: [.init(
                    key: key,
                    slot: 1,
                    code: issueCode
                )]
            ),
            assetStates: [:],
            maximumVariantsPerMaterial: 16
        )
    }

    private static func reason(_ catalog: Catalog) -> String? {
        catalog.claim(layerID: layerID)
            .flatMap { catalog.resolve($0.token) }?
            .stages.first?.visualFailureReasonCode
    }

    static func main() throws {
        let safeGraph = graph(withPrimaryBinding: true)
        let safeTemplate = materialTemplate(
            graph: safeGraph,
            shader: contract(
                "safe-purpose-failure",
                secondMetadata: "{}",
                observesSecond: true
            ),
            slots: slots(
                primary: graphCandidate(),
                second: assetCandidate("textures/unproven.tex")
            )
        )
        let safe = catalog(
            graph: safeGraph,
            template: safeTemplate,
            pairStep: pairStep(
                graph: safeGraph,
                fullFrameWrites: 1,
                inputMember: 0,
                outputMember: 1
            )
        )
        let functionOwned = catalog(
            graph: safeGraph,
            template: safeTemplate,
            pairStep: pairStep(
                graph: safeGraph,
                fullFrameWrites: 1,
                inputMember: 0,
                outputMember: 1
            ),
            functionCount: 1
        )
        let samplerSchema = catalog(
            graph: safeGraph,
            template: safeTemplate,
            pairStep: pairStep(
                graph: safeGraph,
                fullFrameWrites: 1,
                inputMember: 0,
                outputMember: 1
            ),
            issueCode: .samplerSchemaUnavailable
        )

        let framebuffer = Graph.TextureIdentity(
            kind: .framebuffer,
            layerID: layerID,
            effect: effectKey,
            name: "unsafe"
        )
        let unsafeGraph = graph(
            withPrimaryBinding: true,
            nodeTarget: framebuffer
        )
        let unsafeTemplate = materialTemplate(
            graph: unsafeGraph,
            shader: contract(
                "unsafe-purpose-failure",
                secondMetadata: "{}",
                observesSecond: true
            ),
            slots: slots(
                primary: graphCandidate(),
                second: assetCandidate("textures/unproven.tex")
            ),
            nodeTarget: .framebuffer
        )
        let unsafe = catalog(
            graph: unsafeGraph,
            template: unsafeTemplate,
            pairStep: pairStep(
                graph: unsafeGraph,
                fullFrameWrites: 0,
                inputMember: 0,
                outputMember: 0
            )
        )

        let payload: [String: Any] = [
            "safeReason": reason(safe) ?? "",
            "safeClaim": safe.claim(layerID: layerID) != nil,
            "samplerSchemaReason": reason(samplerSchema) ?? "",
            "functionOwnedClaim": functionOwned.claim(layerID: layerID) != nil,
            "unsafeFramebufferClaim": unsafe.claim(layerID: layerID) != nil,
            "unsafeFramebufferReason": unsafe.reportLines.first(where: {
                $0.contains("material-variant-envelope-texture-purpose")
            }) ?? "",
        ]
        let data = try JSONSerialization.data(withJSONObject: payload)
        FileHandle.standardOutput.write(data)
    }
}
'''


@unittest.skipUnless(shutil.which("swiftc"), "swiftc is required")
class SceneEffectLocalTexturePurposeFallbackTests(unittest.TestCase):
    def test_safe_effect_isolated_but_unsafe_topologies_remain_hard(self) -> None:
        support = FIXTURE["ENVELOPE_SUPPORT"]
        self.assertIn(PAIR_STUB, support)
        support = support.replace(PAIR_STUB, PAIR_FIXTURE, 1)
        harness = FIXTURE["ENVELOPE_HARNESS"]
        harness = harness[: harness.index("@main")] + HARNESS_MAIN

        with tempfile.TemporaryDirectory(
            prefix="mwx-texture-purpose-effect-fallback-"
        ) as directory:
            root = Path(directory)
            support_path = root / "Support.swift"
            harness_path = root / "Harness.swift"
            binary = root / "texture-purpose-effect-fallback-test"
            support_path.write_text(support, encoding="utf-8")
            harness_path.write_text(harness, encoding="utf-8")
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
                    str(support_path),
                    *(str(path) for path in FIXTURE["ENVELOPE_SWIFT_SOURCES"]),
                    str(harness_path),
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
        self.assertTrue(payload["safeClaim"], payload)
        self.assertEqual(
            payload["safeReason"],
            "material-variant-envelope-texture-purpose",
            payload,
        )
        self.assertFalse(payload["functionOwnedClaim"], payload)
        self.assertEqual(
            payload["samplerSchemaReason"],
            "material-variant-envelope-sampler-schema",
            payload,
        )
        self.assertFalse(payload["unsafeFramebufferClaim"], payload)
        self.assertIn(
            "material-variant-envelope-texture-purpose",
            payload["unsafeFramebufferReason"],
            payload,
        )

    def test_only_the_typed_purpose_failure_joins_existing_visual_gate(self) -> None:
        for path in (PROGRAM_FIRST_SOURCE, EXECUTOR_SOURCE):
            source = path.read_text(encoding="utf-8")
            self.assertIn(
                '"material-variant-envelope-texture-purpose"',
                source,
                path,
            )
            for hard_failure in (
                "material-variant-envelope-texture-binding",
                "material-variant-envelope-capacity",
                "material-target-storage-unproven",
            ):
                self.assertNotIn(f'"{hard_failure}"', source, path)


if __name__ == "__main__":
    unittest.main()
