#!/usr/bin/env python3

from __future__ import annotations

import fnmatch
import json
import re
import subprocess
import tempfile
import unittest
from collections import defaultdict
from pathlib import Path
from urllib.parse import unquote, urlsplit


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
SEMANTICS_ROOT = REPOSITORY_ROOT / "docs/scene/semantics"
SCENE_SOURCE_ROOT = REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene"
SCENE_LAYOUT_PATH = REPOSITORY_ROOT / "script/scene_source_layout.json"
INLINE_LINK_PATTERN = re.compile(r"!?\[[^\]]*\]\(([^)\n]+)\)")


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


def swift_without_comments(text: str) -> str:
    output: list[str] = []
    index = 0
    block_depth = 0
    state = "code"
    while index < len(text):
        if state == "line-comment":
            if text[index] == "\n":
                output.append("\n")
                state = "code"
            else:
                output.append(" ")
            index += 1
            continue
        if state == "block-comment":
            if text.startswith("/*", index):
                output.extend("  ")
                block_depth += 1
                index += 2
            elif text.startswith("*/", index):
                output.extend("  ")
                block_depth -= 1
                index += 2
                if block_depth == 0:
                    state = "code"
            else:
                output.append("\n" if text[index] == "\n" else " ")
                index += 1
            continue
        if state == "string":
            output.append(text[index])
            if text[index] == "\\" and index + 1 < len(text):
                output.append(text[index + 1])
                index += 2
            else:
                if text[index] == '"':
                    state = "code"
                index += 1
            continue
        if state == "multiline-string":
            if text.startswith('"""', index):
                output.extend('"""')
                index += 3
                state = "code"
            else:
                output.append(text[index])
                index += 1
            continue
        if text.startswith("//", index):
            output.extend("  ")
            index += 2
            state = "line-comment"
        elif text.startswith("/*", index):
            output.extend("  ")
            index += 2
            block_depth = 1
            state = "block-comment"
        elif text.startswith('"""', index):
            output.extend('"""')
            index += 3
            state = "multiline-string"
        elif text[index] == '"':
            output.append('"')
            index += 1
            state = "string"
        else:
            output.append(text[index])
            index += 1
    return "".join(output)


def render_chain_authority_violations(
    source_root: Path,
    rules: list[dict[str, object]],
    repository_root: Path | None = None,
) -> list[str]:
    violations: list[str] = []
    all_sources = sorted(source_root.rglob("*.swift"))
    for rule in rules:
        rule_id = str(rule["id"])
        pattern = re.compile(str(rule["pattern"]), re.MULTILINE)
        allowed_files = [str(value) for value in rule["allowed_files"]]
        scope_files = [str(value) for value in rule.get("scope_files", [])]
        rule_source_root = source_root
        scan_root = rule.get("scan_root")
        if scan_root is not None:
            if repository_root is None:
                violations.append(
                    f"{rule_id}: scan_root requires an explicit repository root"
                )
                continue
            rule_source_root = repository_root / str(scan_root)
        sources = (
            [rule_source_root / relative for relative in scope_files]
            if scope_files
            else (
                sorted(rule_source_root.rglob("*.swift"))
                if scan_root is not None
                else all_sources
            )
        )
        matches_by_file: dict[str, int] = {}
        for source in sources:
            if not source.is_file():
                violations.append(f"{rule_id}: scope file is missing: {source}")
                continue
            relative = source.relative_to(rule_source_root).as_posix()
            searchable = swift_without_comments(source.read_text(encoding="utf-8"))
            start_marker = rule.get("start_marker")
            end_marker = rule.get("end_marker")
            if start_marker is not None:
                start = searchable.find(str(start_marker))
                if start < 0:
                    violations.append(
                        f"{rule_id}: start marker missing in {relative}"
                    )
                    continue
                searchable = searchable[start:]
            if end_marker is not None:
                end = searchable.find(str(end_marker))
                if end < 0:
                    violations.append(f"{rule_id}: end marker missing in {relative}")
                    continue
                searchable = searchable[:end]
            count = len(pattern.findall(searchable))
            if count:
                matches_by_file[relative] = count

        actual_files = sorted(matches_by_file)
        actual_occurrences = sum(matches_by_file.values())
        baseline_occurrences = int(rule["baseline_occurrences"])
        if actual_files != allowed_files:
            violations.append(
                f"{rule_id}: files {actual_files} != baseline {allowed_files}"
            )
        if actual_occurrences != baseline_occurrences:
            violations.append(
                f"{rule_id}: occurrences {actual_occurrences} != baseline "
                f"{baseline_occurrences}; ratchet the manifest when authority shrinks"
            )
    return violations


def render_chain_completion_violations(
    source_root: Path,
    layout: dict[str, object],
    repository_root: Path | None = None,
) -> list[str]:
    contract = layout["render_chain_authority_ratchet"]
    assert isinstance(contract, dict)
    rules = contract["rules"]
    states = contract["completion_state"]
    assert isinstance(rules, list)
    assert isinstance(states, dict)

    violations = render_chain_authority_violations(
        source_root,
        rules,
        repository_root,
    )
    r4_state = str(states.get("r4"))
    r5_state = str(states.get("r5"))
    if r5_state in {"partial", "complete"} and r4_state != "complete":
        violations.append("r5: cannot start before r4 is complete")

    completed_phases: set[str] = set()
    if r4_state == "complete":
        completed_phases.add("r4")
    if r5_state == "complete":
        completed_phases.update({"r4", "r5"})
    for rule in rules:
        if rule.get("role") != "retirement":
            continue
        phase = str(rule["completion_phase"])
        if phase not in completed_phases:
            continue
        baseline = int(rule["baseline_occurrences"])
        target = int(rule["completion_target_occurrences"])
        if baseline != target:
            violations.append(
                f"{rule['id']}: {phase} completion requires {target} "
                f"occurrences, found {baseline}"
            )
        if target == 0 and rule["allowed_files"]:
            violations.append(
                f"{rule['id']}: completed zero target must have no allowed files"
            )
    return violations


def committed_scene_layout() -> dict[str, object] | None:
    result = subprocess.run(
        ["git", "show", "HEAD:script/scene_source_layout.json"],
        cwd=REPOSITORY_ROOT,
        capture_output=True,
        text=True,
        check=False,
    )
    if result.returncode != 0:
        return None
    try:
        return json.loads(result.stdout)
    except json.JSONDecodeError:
        return None


class SceneSemanticsCoverageTests(unittest.TestCase):
    def test_scene_sources_follow_the_documented_directory_layout(self) -> None:
        layout = json.loads(SCENE_LAYOUT_PATH.read_text(encoding="utf-8"))
        self.assertEqual(layout["schema_version"], 3)
        self.assertEqual(
            REPOSITORY_ROOT / layout["source_root"],
            SCENE_SOURCE_ROOT,
        )
        self.assertEqual(
            sorted(path.name for path in SCENE_SOURCE_ROOT.glob("*.swift")),
            [],
            "SteamWorkshopScene is a classification root and must not contain Swift files",
        )
        actual_directories = {
            path.relative_to(SCENE_SOURCE_ROOT).parts[0]
            for path in SCENE_SOURCE_ROOT.rglob("*.swift")
        }
        self.assertEqual(
            actual_directories,
            set(layout["top_level_directories"]),
        )

        declared_nested = layout["declared_second_level_directories"]
        misplaced: list[str] = []
        sources_by_name: defaultdict[str, list[Path]] = defaultdict(list)
        for source in sorted(SCENE_SOURCE_ROOT.rglob("*.swift")):
            relative = source.relative_to(SCENE_SOURCE_ROOT)
            sources_by_name[source.name].append(relative)
            if len(relative.parts) == 2:
                continue
            if len(relative.parts) != 3:
                misplaced.append(
                    f"{relative.as_posix()}: Scene Swift depth must be one or two"
                )
                continue
            top_level, second_level, filename = relative.parts
            contract = declared_nested.get(top_level, {}).get(second_level)
            if contract is None:
                misplaced.append(
                    f"{relative.as_posix()}: second-level directory is not declared"
                )
                continue
            if not any(
                fnmatch.fnmatchcase(filename, pattern)
                for pattern in contract["file_globs"]
            ):
                misplaced.append(
                    f"{relative.as_posix()}: filename is outside its directory contract"
                )

        for top_level, second_levels in declared_nested.items():
            for second_level, contract in second_levels.items():
                expected_parent = Path(top_level) / second_level
                for pattern in contract["file_globs"]:
                    matches = [
                        source
                        for source in SCENE_SOURCE_ROOT.rglob(pattern)
                        if source.is_file()
                    ]
                    if not matches:
                        misplaced.append(
                            f"{expected_parent}/{pattern}: layout glob matched no files"
                        )
                    for source in matches:
                        relative = source.relative_to(SCENE_SOURCE_ROOT)
                        if relative.parent != expected_parent:
                            misplaced.append(
                                f"{relative.as_posix()}: belongs in {expected_parent}"
                            )

        duplicate_names = {
            name: paths
            for name, paths in sources_by_name.items()
            if len(paths) > 1
        }
        self.assertEqual(
            duplicate_names,
            {},
            "Scene Swift basenames must stay unique for reliable navigation",
        )
        forbidden_names = set(layout["forbidden_directory_names"])
        forbidden_directories = sorted(
            path.relative_to(SCENE_SOURCE_ROOT).as_posix()
            for path in SCENE_SOURCE_ROOT.rglob("*")
            if path.is_dir() and path.name in forbidden_names
        )
        self.assertEqual(forbidden_directories, [])
        self.assertEqual(
            misplaced,
            [],
            "Scene source layout violations:\n" + "\n".join(misplaced),
        )

    def test_render_chain_authority_matches_the_ratcheted_inventory(self) -> None:
        layout = json.loads(SCENE_LAYOUT_PATH.read_text(encoding="utf-8"))
        contract = layout["render_chain_authority_ratchet"]
        states = contract["completion_state"]
        self.assertEqual(set(states), {"r4", "r5"})
        self.assertIn(states["r4"], {"partial", "complete"})
        self.assertIn(states["r5"], {"not_started", "partial", "complete"})
        rules = contract["rules"]
        ids = [rule["id"] for rule in rules]
        self.assertEqual(len(ids), len(set(ids)))
        rules_by_id = {rule["id"]: rule for rule in rules}
        for rule_id in (
            "legacy-script-source-profile-selector",
            "numeric-workshop-runtime-dispatch",
        ):
            rule = rules_by_id[rule_id]
            self.assertEqual(rule["baseline_occurrences"], 0)
            self.assertEqual(rule["completion_target_occurrences"], 0)
            self.assertEqual(rule["completion_phase"], "r4")
            self.assertEqual(rule["allowed_files"], [])
        for rule in rules:
            self.assertIn(rule["role"], {"required", "inventory", "retirement"})
            self.assertEqual(rule["allowed_files"], sorted(rule["allowed_files"]))
            if "scope_files" in rule:
                self.assertEqual(rule["scope_files"], sorted(rule["scope_files"]))
            if rule["role"] == "required":
                self.assertNotIn("completion_phase", rule)
                self.assertEqual(
                    rule["completion_target_occurrences"],
                    rule["baseline_occurrences"],
                )
            elif rule["role"] == "inventory":
                self.assertNotIn("completion_phase", rule)
                self.assertNotIn("completion_target_occurrences", rule)
            else:
                self.assertIn(rule["completion_phase"], {"r4", "r5"})
                self.assertEqual(rule["completion_target_occurrences"], 0)
        image_blend_rule = rules_by_id["legacy-image-blend-product-owner"]
        self.assertEqual(image_blend_rule.get("scan_root"), "MyWallpaperX")
        self.assertNotIn("scope_files", image_blend_rule)
        for rule_id in (
            "base-layer-inline-effect-authority",
            "heuristic-shared-effect-texture-loading",
            "deprecated-direct-target-allocation",
            "sample-specific-product-dispatch",
        ):
            rule = rules_by_id[rule_id]
            self.assertEqual(rule["baseline_occurrences"], 0)
            self.assertEqual(rule["completion_target_occurrences"], 0)
            self.assertEqual(rule["completion_phase"], "r5")
            self.assertEqual(rule["allowed_files"], [])
            self.assertNotIn("scope_files", rule)
        self.assertNotIn(
            "scan_root", rules_by_id["sample-specific-product-dispatch"]
        )
        r5_retirement_rules = [
            rule for rule in rules
            if rule.get("role") == "retirement"
            and rule.get("completion_phase") == "r5"
        ]
        self.assertTrue(r5_retirement_rules)
        for rule in r5_retirement_rules:
            self.assertEqual(rule["baseline_occurrences"], 0)
            self.assertEqual(rule["completion_target_occurrences"], 0)
            self.assertEqual(rule["completion_phase"], "r5")
            self.assertEqual(rule["allowed_files"], [])
            self.assertNotIn("scope_files", rule)
        self.assertEqual(states, {"r4": "complete", "r5": "complete"})
        violations = render_chain_authority_violations(
            SCENE_SOURCE_ROOT,
            rules,
            REPOSITORY_ROOT,
        )
        self.assertEqual(
            violations,
            [],
            "Render-chain authority ratchet violations:\n" + "\n".join(violations),
        )

    def test_render_chain_declared_completion_state_meets_targets(self) -> None:
        layout = json.loads(SCENE_LAYOUT_PATH.read_text(encoding="utf-8"))
        violations = render_chain_completion_violations(
            SCENE_SOURCE_ROOT,
            layout,
            REPOSITORY_ROOT,
        )
        self.assertEqual(
            violations,
            [],
            "Render-chain completion violations:\n" + "\n".join(violations),
        )

    def test_render_chain_ratchet_cannot_rise_above_committed_baseline(self) -> None:
        committed = committed_scene_layout()
        if committed is None or "render_chain_authority_ratchet" not in committed:
            self.skipTest("the committed checkout predates the R4-0 authority ratchet")
        previous = {
            rule["id"]: rule
            for rule in committed["render_chain_authority_ratchet"]["rules"]
        }
        current = {
            rule["id"]: rule
            for rule in json.loads(SCENE_LAYOUT_PATH.read_text(encoding="utf-8"))[
                "render_chain_authority_ratchet"
            ]["rules"]
        }
        violations: list[str] = []
        old_contract = committed["render_chain_authority_ratchet"]
        new_contract = json.loads(SCENE_LAYOUT_PATH.read_text(encoding="utf-8"))[
            "render_chain_authority_ratchet"
        ]
        rename_output = subprocess.run(
            [
                "git", "diff", "--name-status", "--find-renames=50%",
                "HEAD", "--", "MyWallpaperX/Core/SteamWorkshopScene",
            ],
            cwd=REPOSITORY_ROOT,
            check=True,
            capture_output=True,
            text=True,
        ).stdout
        scene_prefix = "MyWallpaperX/Core/SteamWorkshopScene/"
        renamed_scene_files: dict[str, str] = {}
        for line in rename_output.splitlines():
            fields = line.split("\t")
            if len(fields) == 3 and fields[0].startswith("R"):
                old_path, new_path = fields[1:]
                if old_path.startswith(scene_prefix) and new_path.startswith(scene_prefix):
                    renamed_scene_files[
                        old_path.removeprefix(scene_prefix)
                    ] = new_path.removeprefix(scene_prefix)
        old_states = old_contract.get("completion_state")
        if old_states is not None:
            new_states = new_contract["completion_state"]
            state_orders = {
                "r4": {"partial": 0, "complete": 1},
                "r5": {"not_started": 0, "partial": 1, "complete": 2},
            }
            for phase, order in state_orders.items():
                if order[new_states[phase]] < order[old_states[phase]]:
                    violations.append(f"{phase}: completion state regressed")
        for rule_id, old_rule in previous.items():
            new_rule = current.get(rule_id)
            if new_rule is None:
                violations.append(f"{rule_id}: committed rule was removed")
                continue
            if int(new_rule["baseline_occurrences"]) > int(old_rule["baseline_occurrences"]):
                violations.append(f"{rule_id}: baseline occurrence increased")
            renamed_allowed = {
                renamed_scene_files.get(path, path)
                for path in old_rule["allowed_files"]
            }
            if not set(new_rule["allowed_files"]).issubset(renamed_allowed):
                violations.append(f"{rule_id}: allowed file set increased")
            renamed_scope = {
                renamed_scene_files.get(path, path)
                for path in old_rule.get("scope_files", [])
            }
            if not set(new_rule.get("scope_files", [])).issubset(renamed_scope):
                violations.append(f"{rule_id}: scope file set increased")
            old_role = old_rule.get("role")
            if old_role == "required" and new_rule.get("role") != "required":
                violations.append(f"{rule_id}: required rule was weakened")
            if old_role == "retirement" and new_rule.get("role") != "retirement":
                violations.append(f"{rule_id}: retirement rule was weakened")
            if old_rule.get("completion_phase") is not None:
                if new_rule.get("completion_phase") != old_rule["completion_phase"]:
                    violations.append(f"{rule_id}: completion phase changed")
                if new_rule.get("completion_target_occurrences") is None:
                    violations.append(f"{rule_id}: completion target was removed")
                elif int(new_rule["completion_target_occurrences"]) > int(
                    old_rule["completion_target_occurrences"]
                ):
                    violations.append(f"{rule_id}: completion target increased")
            reaches_retirement_target = (
                old_rule.get("role") == "retirement"
                and int(new_rule["baseline_occurrences"])
                    == int(new_rule["completion_target_occurrences"])
                and not new_rule.get("allowed_files")
                and not new_rule.get("scope_files")
                and int(old_rule["baseline_occurrences"])
                    >= int(new_rule["baseline_occurrences"])
            )
            definition_moved_without_authority_growth = (
                old_rule.get("role") == "inventory"
                and int(new_rule["baseline_occurrences"])
                    == int(old_rule["baseline_occurrences"])
                and set(new_rule["allowed_files"]) == renamed_allowed
                and set(new_rule.get("scope_files", [])) == renamed_scope
            )
            if not reaches_retirement_target and not definition_moved_without_authority_growth:
                for field in ("pattern", "start_marker", "end_marker"):
                    if new_rule.get(field) != old_rule.get(field):
                        violations.append(f"{rule_id}: {field} changed")
        self.assertEqual(violations, [])

    def test_render_chain_ratchet_rejects_new_owner_recovery_and_selector(self) -> None:
        rules = [
            {
                "id": "owner",
                "pattern": r"OWNER\(",
                "baseline_occurrences": 1,
                "allowed_files": ["Owner.swift"],
            },
            {
                "id": "recovery",
                "pattern": r"^    case [A-Za-z]+$",
                "baseline_occurrences": 1,
                "allowed_files": ["Recovery.swift"],
                "scope_files": ["Recovery.swift"],
            },
            {
                "id": "selector",
                "pattern": r"workshop/[0-9]+",
                "baseline_occurrences": 1,
                "allowed_files": ["Selector.swift"],
            },
            {
                "id": "product-wide",
                "pattern": r"RETIRED_OWNER",
                "baseline_occurrences": 0,
                "allowed_files": [],
                "scan_root": "Product",
            },
        ]
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "Product").mkdir()
            (root / "Owner.swift").write_text(
                "OWNER()\n// OWNER() is documentation only.\n",
                encoding="utf-8",
            )
            (root / "Recovery.swift").write_text(
                "enum Recovery {\n    case iris\n}\n",
                encoding="utf-8",
            )
            (root / "Selector.swift").write_text(
                'let path = "workshop/123/effect.json"\n',
                encoding="utf-8",
            )
            self.assertEqual(
                render_chain_authority_violations(root, rules, root),
                [],
            )

            (root / "Unexpected.swift").write_text(
                'OWNER()\nlet path = "workshop/456/effect.json"\n',
                encoding="utf-8",
            )
            (root / "Recovery.swift").write_text(
                "enum Recovery {\n    case iris\n    case shine\n}\n",
                encoding="utf-8",
            )
            (root / "Product/Unexpected.swift").write_text(
                "RETIRED_OWNER\n",
                encoding="utf-8",
            )
            violations = render_chain_authority_violations(root, rules, root)
            self.assertTrue(any(value.startswith("owner:") for value in violations))
            self.assertTrue(any(value.startswith("recovery:") for value in violations))
            self.assertTrue(any(value.startswith("selector:") for value in violations))
            self.assertTrue(
                any(value.startswith("product-wide:") for value in violations)
            )

    def test_render_chain_completion_distinguishes_inventory_from_retirement(self) -> None:
        rules = [
            {
                "id": "inventory",
                "role": "inventory",
                "pattern": r"INVENTORY\(",
                "baseline_occurrences": 1,
                "allowed_files": ["Inventory.swift"],
            },
            {
                "id": "retirement",
                "role": "retirement",
                "pattern": r"OWNER\(",
                "baseline_occurrences": 1,
                "completion_phase": "r4",
                "completion_target_occurrences": 0,
                "allowed_files": ["Owner.swift"],
            },
        ]
        layout = {
            "render_chain_authority_ratchet": {
                "completion_state": {"r4": "partial", "r5": "not_started"},
                "rules": rules,
            }
        }
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "Inventory.swift").write_text("INVENTORY()\n", encoding="utf-8")
            (root / "Owner.swift").write_text("OWNER()\n", encoding="utf-8")
            self.assertEqual(render_chain_completion_violations(root, layout), [])

            layout["render_chain_authority_ratchet"]["completion_state"]["r4"] = (
                "complete"
            )
            violations = render_chain_completion_violations(root, layout)
            self.assertTrue(any(value.startswith("retirement:") for value in violations))

            (root / "Owner.swift").write_text("// retired\n", encoding="utf-8")
            rules[1]["baseline_occurrences"] = 0
            rules[1]["allowed_files"] = []
            self.assertEqual(render_chain_completion_violations(root, layout), [])

            layout["render_chain_authority_ratchet"]["completion_state"] = {
                "r4": "partial",
                "r5": "complete",
            }
            violations = render_chain_completion_violations(root, layout)
            self.assertIn("r5: cannot start before r4 is complete", violations)

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


if __name__ == "__main__":
    unittest.main()
