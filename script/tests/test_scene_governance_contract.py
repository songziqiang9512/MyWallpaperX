#!/usr/bin/env python3

from __future__ import annotations

import json
import re
import subprocess
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
AGENT_RULES = ROOT / "AGENTS.md"
GITIGNORE = ROOT / ".gitignore"
DOCS_README = ROOT / "docs/README.md"
ROADMAP = ROOT / "docs/scene/README.md"
SCENE_README = ROOT / "docs/scene/README.md"
WEB_README = ROOT / "docs/web/README.md"
SCENE_EVIDENCE = ROOT / ".artifacts/scene-evidence/runs"
SOURCE_INDEX = ROOT / "docs/scene/development/source-index.md"
COVERAGE_LEDGER = ROOT / "docs/scene/capabilities/README.md"
RUNTIME_EVIDENCE = ROOT / "docs/scene/capabilities/runtime-evidence-current.md"
RENDER_GRAPH_COVERAGE = (
    ROOT / "docs/scene/capabilities/render-graph-shader-coverage.md"
)
RESEARCH_WORKFLOW = (
    ROOT
    / "docs/scene/development/official-client-behavior-research-workflow.md"
)
FAST_SUITE = ROOT / "script/scene_fast_suite.json"

SOURCE_CLASSES = {
    "official-public-contract",
    "official-client-dynamic-golden",
    "official-client-static-observation",
    "authored-corpus-observation",
    "third-party-reference-pattern",
    "MyWallpaperX-current-evidence",
    "MyWallpaperX-strategy",
}

ALLOWED_FAST_SUITE_LANES = {"V0", "V1", "V2", "V3"}
REQUIRED_EVIDENCE = {
    "actual-route-identity",
    "execution-completion",
    "publication-identity",
    "terminal-compositor-consumption",
    "next-frame",
    "predeclared-visible-or-event-oracle",
    "localized-failure-negative",
}
REQUIRED_METRICS = {
    "eligibleAuthoredUnits",
    "compileOrPlanSuccesses",
    "actualExecutions",
    "gpuEncodedEffectPasses",
    "visibleNonBaseScenes",
    "localizedFallbacks",
    "wholeLayerOrSceneRejections",
    "fallbackReasons",
    "firstCompileMilliseconds",
    "firstEffectFrameMilliseconds",
    "cpuFrameMilliseconds",
    "gpuFrameMilliseconds",
    "memoryBytes",
    "changedExecutionPrimitives",
    "newlyExecutedAuthoredUnits",
}


class SceneGovernanceContractTests(unittest.TestCase):
    def test_scene_top_level_contains_only_entrypoint_and_active_plans(self) -> None:
        index = json.loads((ROOT / "docs/document-role-index.json").read_text())
        roles = {entry["path"]: entry["role"] for entry in index["documents"]}
        for path in (ROOT / "docs/scene").glob("*.md"):
            if path.name == "README.md":
                continue
            with self.subTest(path=path.name):
                self.assertEqual(roles.get(path.relative_to(ROOT).as_posix()), "active-plan")

    def setUp(self) -> None:
        self.manifest = json.loads(FAST_SUITE.read_text(encoding="utf-8"))

    def test_fast_suite_manifest_is_complete_but_honest_about_readiness(self) -> None:
        self.assertEqual(self.manifest.get("schemaVersion"), 1)
        self.assertEqual(
            set(self.manifest.get("allowedSelectionStates", [])),
            {"selection-required", "approved", "retired"},
        )
        self.assertEqual(set(self.manifest.get("requiredEvidence", [])), REQUIRED_EVIDENCE)
        self.assertEqual(set(self.manifest.get("checkpointMetrics", [])), REQUIRED_METRICS)

        cases = self.manifest.get("cases")
        self.assertIsInstance(cases, list)
        self.assertTrue(cases)
        indexed = {case.get("id"): case for case in cases}
        self.assertNotIn(None, indexed)
        self.assertEqual(len(indexed), len(cases), "Fast Suite case IDs must be unique")
        states = {case.get("selectionState") for case in cases}
        self.assertIn(self.manifest.get("status"), self.manifest["allowedSelectionStates"])
        if "selection-required" in states:
            self.assertEqual(self.manifest.get("status"), "selection-required")

        for case_id, case in indexed.items():
            with self.subTest(case=case_id):
                self.assertIsInstance(case_id, str)
                self.assertTrue(case_id)
                self.assertIn(case.get("lane"), ALLOWED_FAST_SUITE_LANES)
                state = case.get("selectionState")
                self.assertIn(state, self.manifest["allowedSelectionStates"])
                for field in (
                    "authoredShape",
                    "expectedRoute",
                    "firstBreakpoint",
                    "positiveOracle",
                    "negativeOracle",
                    "failureRadius",
                ):
                    self.assertTrue(case.get(field), f"{case_id} is missing {field}")
                if state == "approved":
                    self.assertTrue(case.get("fixtureIdentity"))
                    self.assertTrue(case.get("contentDigest"))
                    self.assertNotIn("must be recorded", case["firstBreakpoint"])
                elif state == "selection-required":
                    self.assertIsNone(case.get("fixtureIdentity"))
                    self.assertIsNone(case.get("contentDigest"))

    def test_scene_navigation_does_not_duplicate_current_capability_truth(self) -> None:
        roadmap = ROADMAP.read_text(encoding="utf-8")
        self.assertNotRegex(
            roadmap,
            r"(?<![0-9-])\d{9,10}(?![0-9-])",
            "active roadmap must not retain sample or fixture identities",
        )
        self.assertNotRegex(
            roadmap,
            r"(?<![0-9a-f])[0-9a-f]{40,64}(?![0-9a-f])",
            "active roadmap must not retain build or artifact hashes",
        )
        self.assertNotRegex(
            roadmap,
            r"\b\d+\s*个\s*(?:generic-only|prefer-generic|observe-only)",
            "active roadmap must not retain moving route census values",
        )
        for local_artifact_reference in (
            ".codex/",
            "/private/tmp/",
            "report.json",
            "manifest.json",
        ):
            with self.subTest(localArtifactReference=local_artifact_reference):
                self.assertNotIn(local_artifact_reference, roadmap)

    def test_navigation_documents_do_not_copy_moving_state(self) -> None:
        for path in (DOCS_README, SCENE_README, WEB_README):
            with self.subTest(document=path.relative_to(ROOT).as_posix()):
                text = path.read_text(encoding="utf-8")
                self.assertNotRegex(text, r"当前(?:主线|阶段|段位)\s*[:：]?\s*V\d")
                self.assertNotRegex(text, r"(?<![0-9-])\d{9,10}(?![0-9-])")
                self.assertNotRegex(
                    text,
                    r"(?<![0-9a-f])[0-9a-f]{40,64}(?![0-9a-f])",
                )
                self.assertNotRegex(
                    text,
                    r"\b\d+\s*个\s*(?:generic-only|prefer-generic|observe-only)",
                )
                self.assertNotIn(".codex/", text)
                self.assertNotIn("/private/tmp/", text)
                self.assertNotIn("report.json", text)
                self.assertNotIn("manifest.json", text)

    def test_scene_evidence_is_a_local_ignored_cache(self) -> None:
        evidence = RUNTIME_EVIDENCE.read_text(encoding="utf-8")
        ignored = GITIGNORE.read_text(encoding="utf-8").splitlines()
        self.assertIn(".artifacts/", ignored)
        self.assertNotIn("](../evidence/", evidence)

        relative = SCENE_EVIDENCE.relative_to(ROOT).as_posix()
        ignored_path = subprocess.run(
            ["git", "check-ignore", "--no-index", relative + "/proof.json"],
            cwd=ROOT, capture_output=True, text=True,
        )
        self.assertEqual(ignored_path.returncode, 0, ignored_path.stderr)
        tracked = subprocess.check_output(
            ["git", "ls-files", "--", ".artifacts/scene-evidence"], cwd=ROOT, text=True,
        )
        self.assertEqual(tracked.strip(), "", "local evidence must not become tracked payload")

    def test_named_source_taxonomy_is_single_and_complete(self) -> None:
        rules = AGENT_RULES.read_text(encoding="utf-8")
        source_index = SOURCE_INDEX.read_text(encoding="utf-8")
        for source_class in SOURCE_CLASSES:
            with self.subTest(sourceClass=source_class):
                self.assertIn(f"`{source_class}`", source_index)
                self.assertNotIn(f"`{source_class}`", rules)

        for path in (ROOT / "docs/scene").rglob("*.md"):
            if "history" in path.parts:
                continue
            with self.subTest(noLegacyDGrade=path.relative_to(ROOT).as_posix()):
                text = path.read_text(encoding="utf-8")
                self.assertNotRegex(text, r"(?<![A-Za-z0-9])D\s*级")
                self.assertNotRegex(text, r"等级[：:\s]*`?D`?")



if __name__ == "__main__":
    unittest.main()
