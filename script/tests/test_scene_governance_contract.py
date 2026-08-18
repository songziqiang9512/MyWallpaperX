#!/usr/bin/env python3

from __future__ import annotations

import json
import re
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
AGENT_RULES = ROOT / "AGENTS.md"
GITIGNORE = ROOT / ".gitignore"
ROADMAP = ROOT / "docs/scene/scene-compatibility-roadmap.md"
RUNTIME_ARCHITECTURE = ROOT / "docs/scene/runtime-architecture.md"
SCENE_README = ROOT / "docs/scene/README.md"
SOURCE_INDEX = ROOT / "docs/scene/semantics/source-index.md"
COVERAGE_LEDGER = ROOT / "docs/scene/semantics/coverage-ledger.md"
RUNTIME_EVIDENCE = ROOT / "docs/scene/semantics/runtime-evidence-index.md"
RENDER_GRAPH_COVERAGE = (
    ROOT / "docs/scene/semantics/render-graph-shader-coverage.md"
)
RESEARCH_WORKFLOW = (
    ROOT
    / "docs/scene/semantics/official-client-behavior-research-workflow.md"
)
FAST_SUITE = ROOT / "script/scene_fast_suite.json"
MIRAGE_REFERENCE = (
    ROOT / "docs/scene/semantics/miragewallpaper-rendering-reference.md"
)

SOURCE_CLASSES = {
    "official-public-contract",
    "official-client-dynamic-golden",
    "official-client-static-observation",
    "authored-corpus-observation",
    "third-party-reference-pattern",
    "MyWallpaperX-current-evidence",
    "MyWallpaperX-strategy",
}
RESEARCH_ONLY_DOCUMENTS = (
    ROOT / "docs/scene/semantics/client-changelog-forensics.md",
    ROOT / "docs/scene/semantics/client-runtime-static-forensics.md",
    ROOT / "docs/scene/semantics/editor-string-table-forensics.md",
    ROOT / "docs/scene/semantics/scenescript-binding-target-forensics.md",
    ROOT / "docs/scene/semantics/scenescript-runtime-implementation-contract.md",
    ROOT / "docs/scene/semantics/shader-prelude-and-backend-abstraction.md",
)

EXPECTED_CASES = {
    "v0-ordinary-one-pass": "V0",
    "v0-ordinary-optional-texture-combo": "V0",
    "v1-ordered-multipass-fbo": "V1",
    "v1-copy-swap-history": "V1",
    "v1-cross-layer-named-provider": "V1",
    "v2-scenescript-property-event": "V2",
    "v3-particle-component-stream": "V3",
}
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
    def setUp(self) -> None:
        self.manifest = json.loads(FAST_SUITE.read_text(encoding="utf-8"))

    def test_fast_suite_manifest_is_complete_but_honest_about_readiness(self) -> None:
        self.assertEqual(self.manifest.get("schemaVersion"), 1)
        self.assertEqual(self.manifest.get("status"), "selection-required")
        self.assertEqual(
            set(self.manifest.get("allowedSelectionStates", [])),
            {"selection-required", "approved", "retired"},
        )
        self.assertEqual(set(self.manifest.get("requiredEvidence", [])), REQUIRED_EVIDENCE)
        self.assertEqual(set(self.manifest.get("checkpointMetrics", [])), REQUIRED_METRICS)

        cases = self.manifest.get("cases")
        self.assertIsInstance(cases, list)
        indexed = {case.get("id"): case for case in cases}
        self.assertEqual(set(indexed), set(EXPECTED_CASES))
        self.assertEqual(len(indexed), len(cases), "Fast Suite case IDs must be unique")

        for case_id, lane in EXPECTED_CASES.items():
            with self.subTest(case=case_id):
                case = indexed[case_id]
                self.assertEqual(case.get("lane"), lane)
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

    def test_roadmap_does_not_duplicate_current_capability_truth(self) -> None:
        roadmap = ROADMAP.read_text(encoding="utf-8")
        self.assertIn("## 4. AI 主动纠偏合同", roadmap)
        self.assertIn("## 8. 当前 V1 选择协议", roadmap)
        self.assertIn("当前代码、旧测试、旧类型层级和历史 matrix", roadmap)
        self.assertIn("readiness 的唯一事实入口", roadmap)
        self.assertIn("任何 `selection-required` 成员都不能执行或计为", roadmap)
        self.assertIn("本节不复述 current capability", roadmap)
        self.assertIn("semantics/coverage-ledger.md#1-口径", roadmap)
        self.assertIn("semantics/runtime-evidence-index.md#1-当前证据快照", roadmap)
        self.assertNotIn("当前 Swift/Metal 底座已经拥有", roadmap)
        self.assertNotIn("当前七类成员", roadmap)
        self.assertNotIn("目前还不是可运行门", roadmap)
        scene_readme = SCENE_README.read_text(encoding="utf-8")
        self.assertIn("readiness 的唯一事实入口", scene_readme)
        self.assertNotIn("当前 `selection-required`", scene_readme)
        self.assertNotIn("current capability truth", roadmap)
        self.assertNotIn("## 4. 全能力状态与归属", roadmap)
        self.assertNotIn("`S5 parity-ready`", roadmap)
        self.assertNotIn("## 8. 下一批精确断点", roadmap)
        self.assertNotIn("该包冻结时的下一", roadmap)
        self.assertNotIn("该阶段仍在 V0", roadmap)
        self.assertNotRegex(
            roadmap,
            r"(?<![0-9-])\d{9,10}(?![0-9-])",
            "active roadmap must not retain sample or fixture identities",
        )

    def test_rules_require_active_drift_correction_and_typed_migration_routes(self) -> None:
        combined = "\n".join(
            (
                AGENT_RULES.read_text(encoding="utf-8"),
                RUNTIME_ARCHITECTURE.read_text(encoding="utf-8"),
                ROADMAP.read_text(encoding="utf-8"),
            )
        )
        for phrase in (
            "目标合同",
            "当前事实",
            "偏差债务",
            "observe-only",
            "prefer-generic",
            "generic-only",
            "disable-generic",
            "slice-visible",
            "owner-migration",
            "parity-release",
        ):
            with self.subTest(phrase=phrase):
                self.assertIn(phrase, combined)

        roadmap = ROADMAP.read_text(encoding="utf-8")
        for deviation_class in (
            "aligned",
            "missing",
            "contradictory",
            "duplicate-owner",
            "over-specialized",
            "stale-document",
            "unknown",
        ):
            with self.subTest(deviationClass=deviation_class):
                self.assertIn(f"`{deviation_class}`", roadmap)
        for correction_field in (
            "target_contract:",
            "current_observation_and_evidence:",
            "deviation_class:",
            "first_breakpoint:",
            "correctness_atom:",
            "route_state_before:",
            "route_state_after:",
            "remaining_deviation_and_exit_condition:",
        ):
            with self.subTest(correctionField=correction_field):
                self.assertIn(correction_field, roadmap)

    def test_scene_evidence_is_a_local_ignored_cache(self) -> None:
        rules = AGENT_RULES.read_text(encoding="utf-8")
        evidence = RUNTIME_EVIDENCE.read_text(encoding="utf-8")
        ignored = GITIGNORE.read_text(encoding="utf-8").splitlines()
        self.assertIn("docs/scene/evidence/", ignored)
        self.assertIn("仓库忽略的本机证据缓存", rules)
        self.assertIn("仓库忽略的本机证据缓存", evidence)
        self.assertNotIn("](../evidence/", evidence)

    def test_named_source_taxonomy_is_single_and_complete(self) -> None:
        rules = AGENT_RULES.read_text(encoding="utf-8")
        source_index = SOURCE_INDEX.read_text(encoding="utf-8")
        self.assertIn("named source taxonomy 的唯一分类入口", source_index)
        self.assertNotIn("必须区分五种来源", rules)
        for source_class in SOURCE_CLASSES:
            with self.subTest(sourceClass=source_class):
                self.assertIn(f"`{source_class}`", source_index)
                self.assertIn(f"`{source_class}`", rules)

        for path in (ROOT / "docs/scene").rglob("*.md"):
            if "history" in path.parts:
                continue
            with self.subTest(noLegacyDGrade=path.relative_to(ROOT).as_posix()):
                text = path.read_text(encoding="utf-8")
                self.assertNotRegex(text, r"(?<![A-Za-z0-9])D\s*级")
                self.assertNotRegex(text, r"等级[：:\s]*`?D`?")

    def test_capability_and_evidence_scales_have_separate_authorities(self) -> None:
        ledger = COVERAGE_LEDGER.read_text(encoding="utf-8")
        evidence = RUNTIME_EVIDENCE.read_text(encoding="utf-8")
        render_graph = RENDER_GRAPH_COVERAGE.read_text(encoding="utf-8")
        self.assertIn("current capability 的唯一摘要入口", ledger)
        self.assertIn("`S0-S5` 只由[运行证据索引]", ledger)
        self.assertIn("本页采用唯一的运行证据深度口径", evidence)
        self.assertNotIn("- `S1 preserved`：", render_graph)

        defined_levels = {
            level
            for level in re.findall(
                r"`(S\d) (?:missing/unknown|preserved|wired|executed|visible|parity-ready)`",
                evidence,
            )
        }
        self.assertEqual(defined_levels, {"S0", "S1", "S2", "S3", "S4", "S5"})

        used_levels: set[str] = set()
        for path in (ROOT / "docs/scene").rglob("*.md"):
            if "history" in path.parts:
                continue
            used_levels.update(re.findall(r"\bS\d+\b", path.read_text(encoding="utf-8")))
        self.assertLessEqual(used_levels, defined_levels)

    def test_static_forensics_remain_research_only(self) -> None:
        forbidden_product_directives = (
            r"MyWallpaperX\s+(?:应|必须|不得)",
            r"MyWallpaperX 的 [^，。；\n]{0,60}(?:应|必须|不得)",
            r"项目(?:公共 API| fixture)?\s*(?:应|必须|不得)",
            r"实现规格",
            r"这些结果证明项目",
            r"实现时(?:不能|应|必须|不得)",
            r"足以约束项目[^。\n]{0,80}实现",
            r"(?:允许|支持)项目建立",
            r"跨平台应",
            r"纳入项目 typed declaration",
        )
        for path in RESEARCH_ONLY_DOCUMENTS:
            with self.subTest(path=path.relative_to(ROOT).as_posix()):
                text = path.read_text(encoding="utf-8")
                self.assertIn("research-context-only", text)
                self.assertRegex(text, r"implementation agent|fresh context|实现代理")
                for pattern in forbidden_product_directives:
                    self.assertNotRegex(text, pattern)

    def test_static_research_requires_a_fresh_implementation_context(self) -> None:
        workflow = RESEARCH_WORKFLOW.read_text(encoding="utf-8")
        for phrase in (
            "静态研究任务不得修改产品代码",
            "fresh_implementation_task_or_context_id",
            "did-not-receive-raw-static-output",
            "新任务或新上下文",
            "完整继承研究对话",
            "不得宽泛检索或预读标为 `research-context-only`",
            "当前上下文必须停止产品写入",
        ):
            with self.subTest(phrase=phrase):
                self.assertIn(phrase, workflow)


if __name__ == "__main__":
    unittest.main()
