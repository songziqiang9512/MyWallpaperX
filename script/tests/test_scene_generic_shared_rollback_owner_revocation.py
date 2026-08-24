#!/usr/bin/env python3

"""Program-first owner safety after a migrated shared rollback fails."""

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
CAPABILITY_FIXTURE = runpy.run_path(
    str(
        REPOSITORY_ROOT
        / "script/tests/test_scene_resolved_material_execution_capability.py"
    )
)
ENVELOPE_SWIFT_SOURCES = CAPABILITY_FIXTURE["ENVELOPE_SWIFT_SOURCES"]

_PAIR_PLAN_STORAGE = """\
    let baseCaptureIdentity: SceneAuthoredEffectRenderPlan.TextureIdentity
    let effects: [EffectStep] = []
"""
_PAIR_PLAN_INITIALIZER = """\
    let baseCaptureIdentity: SceneAuthoredEffectRenderPlan.TextureIdentity
    let effects: [EffectStep]

    init(
        baseCaptureIdentity: SceneAuthoredEffectRenderPlan.TextureIdentity,
        effects: [EffectStep] = []
    ) {
        self.baseCaptureIdentity = baseCaptureIdentity
        self.effects = effects
    }
"""
ENVELOPE_SUPPORT = CAPABILITY_FIXTURE["ENVELOPE_SUPPORT"].replace(
    _PAIR_PLAN_STORAGE,
    _PAIR_PLAN_INITIALIZER,
)
if ENVELOPE_SUPPORT == CAPABILITY_FIXTURE["ENVELOPE_SUPPORT"]:
    raise AssertionError("pair-plan fixture storage contract changed")

_BASE_HARNESS = CAPABILITY_FIXTURE["ENVELOPE_HARNESS"]
_HELPERS = _BASE_HARNESS.split("@main", 1)[0]
HARNESS = _HELPERS + r'''
private func migratedAlphaRollbackContract(
    _ revision: String
) -> SceneShaderContract {
    func stage(
        _ kind: SceneShaderContract.StageKind,
        path: String,
        source: String
    ) -> SceneShaderContract.Stage {
        let parsed = SceneShaderContractSourceParser().parse(
            source,
            stageRelativePath: path
        )
        return .init(
            kind: kind,
            relativePath: path,
            source: source,
            rawSHA256: SceneShaderStableDigest.hash(Data(source.utf8)),
            includes: parsed.includes,
            annotations: parsed.annotations,
            declarations: parsed.declarations
        )
    }
    let fragment = """
    varying vec3 v_TexCoord;
    uniform sampler2D g_Texture0;
    void main() {
        float weight = 0.0;
        vec4 result = CAST4(0.0), sample;
        { sample = texSample2D(g_Texture0, v_TexCoord); result += sample * sample.a; weight += sample.a; }
        { sample = texSample2D(g_Texture0, v_TexCoord + vec3(1.0)); result += sample * sample.a; weight += sample.a; }
        gl_FragColor.rgb = result.rgb / max(0.001, weight);
        gl_FragColor.a = result.a / 2.0;
    }
    """
    let stages = [
        stage(
            .vertex,
            path: "\(revision)/root.vert",
            source: vertexSource()
        ),
        stage(
            .fragment,
            path: "\(revision)/root.frag",
            source: fragment
        ),
    ]
    return .init(
        identity: "fixture/\(revision)",
        sourceKind: .authoredSource,
        stages: stages,
        diagnostics: [],
        canonicalSHA256: "fixture-contract-\(revision)",
        sourceGraph: .init(
            roots: [
                .init(label: "vertex", virtualPath: "\(revision)/root.vert"),
                .init(label: "fragment", virtualPath: "\(revision)/root.frag"),
            ],
            nodes: stages.map {
                .init(
                    virtualPath: $0.relativePath,
                    provenance: .package,
                    source: $0.source,
                    rawSHA256: $0.rawSHA256,
                    byteCount: $0.source.utf8.count
                )
            },
            edges: [],
            diagnostics: [],
            dependencySHA256: "fixture-dependency-\(revision)"
        )
    )
}

private func catalogWithDedicatedCandidate(
    graph: Graph,
    template: Template
) -> Catalog {
    let node = graph.nodes[0]
    let pairNode = SceneLayerFullFramePairPlan.NodeStep(
        nodeIndex: node.nodeIndex,
        definitionPassIndex: node.definitionPassIndex,
        kind: .material
    )
    let pairStep = SceneLayerFullFramePairPlan.EffectStep(
        effect: effectKey,
        composeTransitionCount: 0,
        fullFrameOutputWriteCount: 1,
        inputMember: 0,
        outputMember: 1,
        nodes: [pairNode]
    )
    let admitted = SceneResolvedMaterialAdmittedLayer(
        layerID: layerID,
        products: [.init(graph: graph)],
        pairPlan: .init(
            baseCaptureIdentity: graph.effects[0].input,
            effects: [pairStep]
        ),
        dependencyOwnership: .none,
        sourceRoute: .capturedLayerTexture
    )
    let program = SceneEffectStageProgram(
        effectKey: effectKey,
        stageGraph: graph,
        executionPlan: .init(logicalRenderTargetCount: 0)
    )
    let key = SceneResolvedMaterialRuntimeCatalog.Key(
        effect: effectKey,
        nodeIndex: node.nodeIndex
    )
    return .init(
        admissionCandidates: [.init(
            layerID: layerID,
            result: .success(admitted),
            dedicatedStagePrograms: [program]
        )],
        materialCatalog: .init(
            entries: [key: .template(template)],
            resourceDemandIssues: []
        ),
        dedicatedStageFamilies: [effectKey: "fixture-dedicated"],
        dedicatedLeafKeys: [effectKey]
    )
}

private func outcome(_ catalog: Catalog) -> [String: Any] {
    guard let claim = catalog.claim(layerID: layerID),
          let capability = catalog.resolve(claim.token) else {
        return [
            "claimed": false,
            "rejection": rejection(catalog),
        ]
    }
    return [
        "claimed": true,
        "families": capability.stages.compactMap { $0.subject?.family },
        "visualFailureReasons": capability.stages.compactMap(
            \.visualFailureReasonCode
        ),
    ]
}

@main
private enum SharedRollbackOwnerHarness {
    static func main() throws {
        guard let mode = CommandLine.arguments.dropFirst().first else {
            fatalError("mode required")
        }
        let migratedProfile = mode != "ordinary-unclaimed"
        let candidateGraph = graph(withPrimaryBinding: true)
        let template = materialTemplate(
            graph: candidateGraph,
            shader: migratedProfile
                ? migratedAlphaRollbackContract("owner-\(mode)")
                : contract("owner-\(mode)", frontendInvalid: true),
            slots: slots(primary: graphCandidate())
        )
        let result = outcome(catalogWithDedicatedCandidate(
            graph: candidateGraph,
            template: template
        ))
        let data = try JSONSerialization.data(
            withJSONObject: result,
            options: [.sortedKeys]
        )
        print(String(decoding: data, as: UTF8.self))
    }
}
'''


@unittest.skipUnless(shutil.which("swiftc"), "swiftc is required")
class SceneGenericSharedRollbackOwnerRevocationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.build_directory = tempfile.TemporaryDirectory(
            prefix="mwx-shared-rollback-owner-"
        )
        root = Path(cls.build_directory.name)
        support = root / "Support.swift"
        harness = root / "SharedRollbackOwnerHarness.swift"
        support.write_text(ENVELOPE_SUPPORT, encoding="utf-8")
        harness.write_text(HARNESS, encoding="utf-8")
        cls.binary = root / "shared-rollback-owner-test"
        environment = os.environ.copy()
        environment["CLANG_MODULE_CACHE_PATH"] = str(root / "clang-cache")
        environment["SWIFT_MODULECACHE_PATH"] = str(root / "swift-cache")
        completed = subprocess.run(
            [
                "xcrun",
                "--sdk",
                "macosx",
                "swiftc",
                "-parse-as-library",
                str(support),
                *(str(path) for path in ENVELOPE_SWIFT_SOURCES),
                str(harness),
                "-module-cache-path",
                str(root / "module-cache"),
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

    def run_case(
        self,
        mode: str,
        profile_routes: str | None,
        cache_is_directory: bool = True,
    ) -> dict:
        with tempfile.TemporaryDirectory(
            prefix=f"mwx-shared-rollback-{mode}-"
        ) as directory:
            root = Path(directory)
            cache = root / "cache"
            if cache_is_directory:
                cache.mkdir()
            else:
                cache.write_text("not-a-directory", encoding="utf-8")
            requests = root / "requests"
            requests.mkdir()
            environment = os.environ.copy()
            environment.update({
                "HOME": str(root / "home"),
                "MWX_SCENE_GENERIC_SHADER_CACHE": str(cache),
                "MWX_SCENE_GENERIC_SHADER_REQUESTS": str(requests),
            })
            environment.pop("MWX_SCENE_GENERIC_SHADER_ROUTE", None)
            if profile_routes is None:
                environment.pop(
                    "MWX_SCENE_GENERIC_SHADER_PROFILE_ROUTES", None
                )
            else:
                environment[
                    "MWX_SCENE_GENERIC_SHADER_PROFILE_ROUTES"
                ] = profile_routes
            completed = subprocess.run(
                [str(self.binary), mode],
                cwd=REPOSITORY_ROOT,
                env=environment,
                capture_output=True,
                text=True,
            )
            self.assertEqual(completed.returncode, 0, completed.stderr)
            return json.loads(completed.stdout)

    def test_migrated_disable_generic_exhaustion_never_revives_dedicated(
        self,
    ) -> None:
        profile = "source-proven-graph-input-alpha-weighted-sample-average"
        result = self.run_case(
            "migrated-disable",
            f"{profile}=disable-generic",
        )
        self.assertTrue(result["claimed"], result)
        self.assertEqual(result["families"], ["visual-failure-passthrough"])
        self.assertEqual(
            result["visualFailureReasons"],
            ["material-generic-owner-revoked"],
        )
        self.assertNotIn("fixture-dedicated", result["families"])

    def test_ordinary_unclaimed_failure_may_still_select_dedicated(self) -> None:
        result = self.run_case(
            "ordinary-unclaimed",
            "ordinary-shader=disable-generic",
        )
        self.assertTrue(result["claimed"], result)
        self.assertEqual(result["families"], ["fixture-dedicated"])
        self.assertEqual(result["visualFailureReasons"], [])

    def test_generic_only_artifact_failure_remains_local_passthrough(self) -> None:
        result = self.run_case(
            "generic-only-revoked",
            None,
            cache_is_directory=False,
        )
        self.assertTrue(result["claimed"], result)
        self.assertEqual(result["families"], ["visual-failure-passthrough"])
        self.assertEqual(
            result["visualFailureReasons"],
            ["material-generic-owner-revoked"],
        )
        self.assertNotIn("fixture-dedicated", result["families"])


if __name__ == "__main__":
    unittest.main()
