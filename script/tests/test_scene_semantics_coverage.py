#!/usr/bin/env python3

from __future__ import annotations

import re
import unittest
from collections import Counter
from pathlib import Path
from urllib.parse import unquote, urlsplit


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
SEMANTICS_ROOT = REPOSITORY_ROOT / "docs/scene/semantics"
CATALOG_PATH = SEMANTICS_ROOT / "official-page-catalog.md"
CROSSWALK_PATH = SEMANTICS_ROOT / "official-page-crosswalk.md"
LEDGER_PATH = SEMANTICS_ROOT / "coverage-ledger.md"
OFFICIAL_PAGE_MAP_PATH = SEMANTICS_ROOT / "official-page-map.md"
EFFECT_COVERAGE_PATH = SEMANTICS_ROOT / "effect-execution-coverage.md"
RENDER_GRAPH_COVERAGE_PATH = SEMANTICS_ROOT / "render-graph-shader-coverage.md"
DEPENDENCY_MAP_PATH = SEMANTICS_ROOT / "capability-dependency-map.md"
RUNTIME_EVIDENCE_PATH = SEMANTICS_ROOT / "runtime-evidence-index.md"
RUNTIME_INPUT_COVERAGE_PATH = SEMANTICS_ROOT / "runtime-input-property-coverage.md"
SCENE_FORMAT_PATH = SEMANTICS_ROOT / "scene-format-and-render-graph.md"
DEVELOPMENT_PLAN_PATH = (
    REPOSITORY_ROOT / "docs/scene/scene-capability-development-plan-2026-07-22.md"
)
ROADMAP_PATH = (
    REPOSITORY_ROOT / "docs/reviews/web-scene-current-state-roadmap-2026-07-19.md"
)
SAMPLE_ASSESSMENT_PATH = (
    REPOSITORY_ROOT / "docs/scene/scene-sample-assessment-2026-07-22.md"
)
COMPATIBILITY_PATH = REPOSITORY_ROOT / "docs/scene/wallpaper_engine_scene_compatibility.md"
RUNTIME_DESIGN_PATH = REPOSITORY_ROOT / "docs/scene/scene-runtime-design-2026-05-15.md"
EFFECTS_REFERENCE_PATH = SEMANTICS_ROOT / "effects-reference.md"
RUNTIME_SYSTEMS_REFERENCE_PATH = SEMANTICS_ROOT / "runtime-systems-reference.md"
SCENESCRIPT_COVERAGE_PATH = SEMANTICS_ROOT / "scenescript-api-coverage.md"
SOURCE_INDEX_PATH = SEMANTICS_ROOT / "source-index.md"
ADVANCED_OBJECT_COVERAGE_PATH = SEMANTICS_ROOT / "advanced-object-coverage.md"
PARTICLE_COMPONENT_COVERAGE_PATH = SEMANTICS_ROOT / "particle-component-coverage.md"

SPECIALIZED_COVERAGE_TABLES = {
    "advanced-object-coverage.md",
    "effect-execution-coverage.md",
    "particle-component-coverage.md",
    "render-graph-shader-coverage.md",
    "runtime-input-property-coverage.md",
    "scenescript-api-coverage.md",
}
REQUIRED_LEDGER_TARGETS = SPECIALIZED_COVERAGE_TABLES | {
    "official-page-crosswalk.md",
    "official-page-map.md",
}

CATALOG_SECTION_PATTERN = re.compile(
    r"^##\s+(\d+)\.\s+.+?（\s*(\d+)(?:\s*\+\s*1\s+declaration)?\s*）\s*$",
    re.MULTILINE,
)
INLINE_LINK_PATTERN = re.compile(r"!?\[[^\]]*\]\(([^)\n]+)\)")
RANGE_LEVEL_PATTERN = re.compile(
    r"(?<![A-Za-z0-9])L[0-4]\s*(?:-|–|—|~|～|/|至|到)\s*L[0-4](?![A-Za-z0-9])"
)
LEVEL_CELL_PATTERN = re.compile(r"`?(L[0-4])`?")
OFFICIAL_SCENE_PREFIX = "https://docs.wallpaperengine.io/en/scene/"
OFFICIAL_PAGE_CLASSIFICATIONS = {
    "runtime-required",
    "ingest-required",
    "editor-only",
    "platform-decision",
    "research-boundary",
}


def markdown_without_fenced_code(text: str) -> str:
    visible_lines: list[str] = []
    fence: str | None = None
    for line in text.splitlines():
        match = re.match(r"^\s*(```|~~~)", line)
        if match:
            marker = match.group(1)
            if fence is None:
                fence = marker
            elif marker == fence:
                fence = None
            continue
        if fence is None:
            visible_lines.append(line)
    return "\n".join(visible_lines)


def markdown_link_targets(text: str) -> list[str]:
    targets: list[str] = []
    for raw_target in INLINE_LINK_PATTERN.findall(markdown_without_fenced_code(text)):
        target = raw_target.strip()
        if target.startswith("<") and ">" in target:
            target = target[1 : target.index(">")]
        else:
            target = target.split(maxsplit=1)[0]
        targets.append(target)
    return targets


def markdown_table_cells(line: str) -> list[str] | None:
    stripped = line.strip()
    if not stripped.startswith("|") or not stripped.endswith("|"):
        return None
    return [
        cell.strip().replace(r"\|", "|")
        for cell in re.split(r"(?<!\\)\|", stripped[1:-1])
    ]


def official_scene_urls(text: str) -> list[str]:
    return [
        target
        for target in markdown_link_targets(text)
        if target.startswith(OFFICIAL_SCENE_PREFIX)
    ]


def table_level(cell: str) -> str | None:
    match = LEVEL_CELL_PATTERN.fullmatch(cell.strip())
    return match.group(1) if match else None


class SceneSemanticsCoverageTests(unittest.TestCase):
    def test_official_catalog_has_16_sections_totalling_179_pages(self) -> None:
        text = CATALOG_PATH.read_text(encoding="utf-8")
        sections = [
            (int(number), int(count))
            for number, count in CATALOG_SECTION_PATTERN.findall(text)
            if int(number) <= 16
        ]

        self.assertEqual([number for number, _ in sections], list(range(1, 17)))
        self.assertEqual(sum(count for _, count in sections), 179)

    def test_official_catalog_and_exact_map_cover_the_same_179_urls(self) -> None:
        catalog_urls = official_scene_urls(CATALOG_PATH.read_text(encoding="utf-8"))
        mapped_urls = official_scene_urls(
            OFFICIAL_PAGE_MAP_PATH.read_text(encoding="utf-8")
        )

        self.assertEqual(len(set(catalog_urls)), 179)
        self.assertEqual(len(set(mapped_urls)), 179)
        self.assertEqual(set(mapped_urls), set(catalog_urls))

    def test_official_page_map_has_one_complete_row_per_url(self) -> None:
        text = OFFICIAL_PAGE_MAP_PATH.read_text(encoding="utf-8")
        expected_urls = set(official_scene_urls(CATALOG_PATH.read_text(encoding="utf-8")))
        url_rows: dict[str, list[int]] = {}
        page_ids: list[str] = []
        violations: list[str] = []

        for line_number, line in enumerate(text.splitlines(), start=1):
            urls = official_scene_urls(line)
            if not urls:
                continue
            if len(urls) != 1:
                violations.append(
                    f"line {line_number}: expected one official URL, found {len(urls)}"
                )
                continue

            url = urls[0]
            url_rows.setdefault(url, []).append(line_number)
            cells = markdown_table_cells(line)
            if cells is None or len(cells) != 5:
                violations.append(
                    f"line {line_number}: official URL must be in a five-column table row"
                )
                continue

            page_id, _, classification, local_contract, decision = cells
            if not page_id:
                violations.append(f"line {line_number}: Page ID is empty")
            else:
                page_ids.append(page_id)

            classification_tokens = set(re.findall(r"`([^`]+)`", classification))
            if not classification_tokens:
                violations.append(f"line {line_number}: classification is empty")
            unknown_classifications = (
                classification_tokens - OFFICIAL_PAGE_CLASSIFICATIONS
            )
            if unknown_classifications:
                violations.append(
                    f"line {line_number}: unknown classification(s) "
                    f"{sorted(unknown_classifications)}"
                )

            contract_targets = markdown_link_targets(local_contract)
            local_targets = [
                target
                for target in contract_targets
                if not urlsplit(target).scheme and bool(urlsplit(target).path)
            ]
            if not local_targets:
                violations.append(
                    f"line {line_number}: local contract must contain a relative link"
                )
            if not decision:
                violations.append(f"line {line_number}: player decision is empty")

        duplicate_urls = {
            url: lines for url, lines in url_rows.items() if len(lines) != 1
        }
        self.assertEqual(duplicate_urls, {}, "Official URLs must each appear on one row")
        self.assertEqual(set(url_rows), expected_urls)
        self.assertEqual(len(page_ids), len(set(page_ids)), "Page IDs must be unique")
        self.assertEqual(
            violations,
            [],
            "Incomplete official page map rows:\n" + "\n".join(violations),
        )

    def test_crosswalk_declares_179_mapped_and_zero_unmapped_pages(self) -> None:
        text = CROSSWALK_PATH.read_text(encoding="utf-8")
        self.assertEqual(self.table_count(text, "已路由页面"), 179)
        self.assertEqual(self.table_count(text, "未路由页面"), 0)

    def test_coverage_ledger_links_all_specialized_tables_and_crosswalk(self) -> None:
        text = LEDGER_PATH.read_text(encoding="utf-8")
        linked_filenames = {
            Path(urlsplit(target).path).name
            for target in markdown_link_targets(text)
        }
        self.assertEqual(REQUIRED_LEDGER_TARGETS - linked_filenames, set())

    def test_relative_markdown_links_in_semantics_directory_exist(self) -> None:
        missing: list[str] = []
        for document in sorted(SEMANTICS_ROOT.glob("*.md")):
            text = document.read_text(encoding="utf-8")
            for target in markdown_link_targets(text):
                parsed = urlsplit(target)
                if parsed.scheme or target.startswith(("#", "/", "//")):
                    continue
                relative_path = unquote(parsed.path)
                if not relative_path:
                    continue
                resolved = (document.parent / relative_path).resolve()
                if not resolved.exists():
                    missing.append(
                        f"{document.relative_to(REPOSITORY_ROOT)} -> {target}"
                    )

        self.assertEqual(missing, [], "Missing relative Markdown links:\n" + "\n".join(missing))

    def test_coverage_table_rows_use_single_levels_not_ranges(self) -> None:
        coverage_paths = sorted(SEMANTICS_ROOT.glob("*coverage*.md"))
        coverage_names = {path.name for path in coverage_paths}
        self.assertEqual(SPECIALIZED_COVERAGE_TABLES - coverage_names, set())

        violations: list[str] = []
        for path in coverage_paths:
            for line_number, line in enumerate(
                path.read_text(encoding="utf-8").splitlines(), start=1
            ):
                if not line.lstrip().startswith("|"):
                    continue
                match = RANGE_LEVEL_PATTERN.search(line)
                if match:
                    violations.append(
                        f"{path.relative_to(REPOSITORY_ROOT)}:{line_number}: {match.group(0)}"
                    )

        self.assertEqual(
            violations,
            [],
            "Coverage table rows must use one L0-L4 value:\n" + "\n".join(violations),
        )

    def test_official_effect_table_has_exact_45_item_level_distribution(self) -> None:
        text = EFFECT_COVERAGE_PATH.read_text(encoding="utf-8")
        start = text.index("## 2.")
        end = text.index("## 8.", start)
        levels: Counter[str] = Counter()
        asset_ids: list[str] = []

        for line in text[start:end].splitlines():
            cells = markdown_table_cells(line)
            if cells is None or len(cells) < 2:
                continue
            level = table_level(cells[1])
            if level is None:
                continue
            asset_id_matches = re.findall(r"`([^`]+)`", cells[0])
            self.assertEqual(
                len(asset_id_matches),
                1,
                f"Effect row must contain one asset ID: {cells[0]}",
            )
            asset_ids.append(asset_id_matches[0])
            levels[level] += 1

        self.assertEqual(len(asset_ids), 45)
        self.assertEqual(len(set(asset_ids)), 45, "Effect asset IDs must be unique")
        self.assertEqual(
            {level: levels[level] for level in ("L0", "L1", "L2", "L3", "L4")},
            {"L0": 0, "L1": 28, "L2": 5, "L3": 12, "L4": 0},
        )

    def test_generic_graph_primitives_remain_l2(self) -> None:
        expected_primitives = {
            "`EffectDefinition`",
            "ordered pass / material ordinal",
            "`Material`",
            "FBO declaration",
            "`target`",
            "`previous`",
            "`bind`",
            "extent (`scale`/`fit`/absolute/input)",
            "`format`",
            "`combo` / permutation",
            "uniform / `constantshadervalues`",
            "render state (blend/depth/write/cull)",
        }
        text = RENDER_GRAPH_COVERAGE_PATH.read_text(encoding="utf-8")
        primitive_levels: dict[str, list[str]] = {
            primitive: [] for primitive in expected_primitives
        }

        for line in text.splitlines():
            cells = markdown_table_cells(line)
            if cells is None or len(cells) < 2 or cells[0] not in primitive_levels:
                continue
            level = table_level(cells[1])
            if level is not None:
                primitive_levels[cells[0]].append(level)

        self.assertEqual(
            primitive_levels,
            {primitive: ["L2"] for primitive in expected_primitives},
            "Strict profiles and scheduler must not promote generic graph/shader primitives",
        )

    def test_current_effect_chain_state_is_linked_across_active_documents(self) -> None:
        implementation_documents = (
            LEDGER_PATH,
            EFFECT_COVERAGE_PATH,
            RENDER_GRAPH_COVERAGE_PATH,
            RUNTIME_EVIDENCE_PATH,
            RUNTIME_INPUT_COVERAGE_PATH,
            SCENE_FORMAT_PATH,
            DEVELOPMENT_PLAN_PATH,
            ROADMAP_PATH,
            SAMPLE_ASSESSMENT_PATH,
            COMPATIBILITY_PATH,
            RUNTIME_DESIGN_PATH,
            EFFECTS_REFERENCE_PATH,
            RUNTIME_SYSTEMS_REFERENCE_PATH,
            SCENESCRIPT_COVERAGE_PATH,
            SOURCE_INDEX_PATH,
            ADVANCED_OBJECT_COVERAGE_PATH,
            PARTICLE_COMPONENT_COVERAGE_PATH,
        )
        document_text = {
            path: path.read_text(encoding="utf-8") for path in implementation_documents
        }

        for path, text in document_text.items():
            self.assertIn(
                "`b541867`",
                text,
                f"Current Scene document is missing the effect-chain baseline: {path}",
            )

        report_path = ".codex/scene-effect-chain-gated-final13-20260723/report.json"
        for path in (
            LEDGER_PATH,
            EFFECT_COVERAGE_PATH,
            RENDER_GRAPH_COVERAGE_PATH,
            RUNTIME_EVIDENCE_PATH,
            DEVELOPMENT_PLAN_PATH,
            ROADMAP_PATH,
            SAMPLE_ASSESSMENT_PATH,
            COMPATIBILITY_PATH,
            RUNTIME_DESIGN_PATH,
            EFFECTS_REFERENCE_PATH,
            RUNTIME_SYSTEMS_REFERENCE_PATH,
            SCENESCRIPT_COVERAGE_PATH,
            SOURCE_INDEX_PATH,
            ADVANCED_OBJECT_COVERAGE_PATH,
            PARTICLE_COMPONENT_COVERAGE_PATH,
        ):
            self.assertIn(
                report_path,
                document_text[path],
                f"Current Scene document is missing the final effect-chain report: {path}",
            )

        evidence = document_text[RUNTIME_EVIDENCE_PATH]
        self.assertIn("### E-EFFECT-CHAIN: ordered strict effect-chain scheduler", evidence)
        self.assertIn("Scene tests 251 total / 250 pass / 1 skip", evidence)
        self.assertIn(
            "ordered strict effect-chain",
            DEPENDENCY_MAP_PATH.read_text(encoding="utf-8"),
        )
        for path, text in document_text.items():
            self.assertIn(
                "exact Workshop single-pass shadow profile",
                text,
                f"Current Scene document is missing the next strict-chain gate: {path}",
            )

        stale_current_routes = (
            "Generic graph scheduler（当前主线）",
            "下一步先建 generic scheduler",
            "先做 B2 generic scheduler",
            "先推进 B2 generic scheduler",
            "下一步 generic effect-chain/read-write scheduler",
        )
        for path, text in document_text.items():
            for stale_route in stale_current_routes:
                self.assertNotIn(
                    stale_route,
                    text,
                    f"Stale Scene route remains in current document: {path}",
                )

    def table_count(self, text: str, label: str) -> int:
        pattern = re.compile(
            rf"^\|\s*{re.escape(label)}\s*\|\s*(\d+)\s*\|",
            re.MULTILINE,
        )
        matches = pattern.findall(text)
        self.assertEqual(len(matches), 1, f"Expected one '{label}' completeness row")
        return int(matches[0])


if __name__ == "__main__":
    unittest.main()
