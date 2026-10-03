#!/usr/bin/env python3

from __future__ import annotations

import copy
import html
import json
import os
import re
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch
from urllib.parse import unquote, urlsplit

from script.document_registry import managed_documents
from script.source_authority import (
    authority_metric_digest,
    authority_relocation_transition_violations,
    classification_transition_violations,
    render_chain_authority_violations,
    render_chain_completion_violations,
    scene_source_layout_violations,
)


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
DOCUMENTATION_ROOT = REPOSITORY_ROOT / "docs"
SEMANTICS_ROOT = REPOSITORY_ROOT / "docs/scene/capabilities"
SCENE_SOURCE_ROOT = REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene"
SCENE_LAYOUT_PATH = REPOSITORY_ROOT / "script/scene_source_layout.json"
INLINE_LINK_PATTERN = re.compile(r"!?\[[^\]]*\]\(([^)\n]+)\)")
EXPLICIT_ANCHOR_PATTERN = re.compile(
    r"<a\s+(?:[^>]*?\s)?id=[\"']([^\"']+)[\"'][^>]*>",
    re.IGNORECASE,
)


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


def github_heading_slug(value: str) -> str:
    """Return the stable ASCII/CJK subset used by our Markdown anchors."""

    value = re.sub(r"<[^>]+>", "", html.unescape(value)).strip().lower()
    value = re.sub(r"[^\w\-\u3400-\u9fff ]", "", value)
    return re.sub(r"[ _]+", "-", value).strip("-")


def markdown_anchors(text: str) -> set[str]:
    anchors = set(EXPLICIT_ANCHOR_PATTERN.findall(text))
    for line in markdown_without_fenced_code(text).splitlines():
        match = re.match(r"^\s{0,3}#{1,6}\s+(.+?)\s*#*\s*$", line)
        if match:
            slug = github_heading_slug(match.group(1))
            if slug:
                anchors.add(slug)
    return anchors


def validation_base() -> str:
    requested = os.environ.get("MWX_VALIDATION_BASE", "HEAD")
    result = subprocess.run(
        ["git", "rev-parse", "--verify", f"{requested}^{{commit}}"],
        cwd=REPOSITORY_ROOT, capture_output=True, text=True, check=True,
    )
    return result.stdout.strip()


def committed_scene_layout(base_ref: str | None = None) -> dict[str, object] | None:
    base_ref = base_ref or validation_base()
    # Only a valid historical tree that predates this file may omit its baseline.
    listing = subprocess.run(
        ["git", "ls-tree", "--name-only", base_ref, "--", "script/scene_source_layout.json"],
        cwd=REPOSITORY_ROOT, capture_output=True, text=True, check=True,
    )
    if not listing.stdout.strip():
        return None
    result = subprocess.run(
        ["git", "show", f"{base_ref}:script/scene_source_layout.json"],
        cwd=REPOSITORY_ROOT, capture_output=True, text=True, check=True,
    )
    return json.loads(result.stdout)


class SceneSemanticsCoverageTests(unittest.TestCase):
    def test_scene_sources_follow_the_documented_directory_layout(self) -> None:
        layout = json.loads(SCENE_LAYOUT_PATH.read_text(encoding="utf-8"))
        self.assertEqual(layout["schema_version"], 3)
        self.assertEqual(REPOSITORY_ROOT / layout["source_root"], SCENE_SOURCE_ROOT)
        violations = scene_source_layout_violations(SCENE_SOURCE_ROOT, layout)
        self.assertEqual(violations, [], "Scene source layout violations:\n" + "\n".join(violations))

    def test_flat_layout_rejects_unregistered_missing_and_relocated_files(self) -> None:
        layout = {
            "top_level_directories": ["Format", "Diagnostics"],
            "declared_second_level_directories": {},
            "declared_flat_directories": {
                "Format": {"files": ["Model.swift"]},
                "Diagnostics": {"files": ["Trace.swift"]},
            },
            "forbidden_directory_names": ["Misc"],
        }
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for relative in ("Format/Model.swift", "Diagnostics/Trace.swift"):
                path = root / relative
                path.parent.mkdir(exist_ok=True)
                path.touch()
            self.assertEqual(scene_source_layout_violations(root, layout), [])
            for relative in ("Format/New.swift", "Diagnostics/New.swift", "Rendering/New.swift",
                             "New.swift", "Format/Deep/New.swift", "Format/Deep/More/New.swift"):
                with self.subTest(relative=relative):
                    path = root / relative
                    path.parent.mkdir(parents=True, exist_ok=True)
                    path.touch()
                    self.assertTrue(any(relative in value for value in
                                        scene_source_layout_violations(root, layout)))
                    path.unlink()
            (root / "Format/Model.swift").rename(root / "Diagnostics/Model.swift")
            self.assertTrue(any("belongs in Format" in value for value in
                                scene_source_layout_violations(root, layout)))
            (root / "Diagnostics/Model.swift").unlink()
            self.assertTrue(any("matched no files" in value for value in
                                scene_source_layout_violations(root, layout)))

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
            if rule.get("classifications"):
                self.assertEqual(rule["role"], "inventory")
                self.assertIn(rule.get("metric"), {"classified-declarations", "local-alias-declarations"})
                for classification in rule["classifications"]:
                    for field in ("owner", "reason", "retirement", "scope", "declaration", "file"):
                        self.assertTrue(classification.get(field), f"missing classification {field}")
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
        base_ref = validation_base()
        committed = committed_scene_layout(base_ref)
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
        from script.source_relocations import unchanged_source_relocations
        scene_prefix = "MyWallpaperX/Core/SteamWorkshopScene/"
        old_paths = {
            scene_prefix + path
            for rule in old_contract["rules"]
            for path in rule["allowed_files"]
        }
        moves = unchanged_source_relocations(
            REPOSITORY_ROOT, base_ref, old_paths,
            (path.relative_to(REPOSITORY_ROOT).as_posix()
             for path in SCENE_SOURCE_ROOT.rglob("*.swift")),
        )
        renamed_scene_files = {
            old.removeprefix(scene_prefix): new.removeprefix(scene_prefix)
            for old, new in moves.items()
        }
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
            violations.extend(classification_transition_violations(old_rule, new_rule))
            if int(new_rule["baseline_occurrences"]) > int(old_rule["baseline_occurrences"]):
                violations.append(f"{rule_id}: baseline occurrence increased")
            renamed_allowed = {
                renamed_scene_files.get(path, path)
                for path in old_rule["allowed_files"]
            }
            relocation_errors = []
            previous_sources, current_sources = {}, {}
            if new_rule.get("owner_relocation") is not None and old_rule.get("owner_relocation") is None:
                listing = subprocess.run(
                    ["git", "grep", "-l", "-E", "--", old_rule["pattern"], base_ref, "--", scene_prefix],
                    cwd=REPOSITORY_ROOT, capture_output=True, text=True, check=False,
                )
                self.assertIn(listing.returncode, (0, 1), listing.stderr)
                for entry in listing.stdout.splitlines():
                    relative = entry.removeprefix(f"{base_ref}:").removeprefix(scene_prefix)
                    previous_sources[relative] = subprocess.run(
                        ["git", "show", f"{base_ref}:{scene_prefix}{relative}"], cwd=REPOSITORY_ROOT,
                        capture_output=True, text=True, check=True,
                    ).stdout
                current_sources = {path.relative_to(SCENE_SOURCE_ROOT).as_posix(): path.read_text()
                                   for path in SCENE_SOURCE_ROOT.rglob("*.swift")}
            relocation_errors = authority_relocation_transition_violations(
                old_rule, new_rule, previous_sources, current_sources)
            violations.extend(relocation_errors)
            exact_owner_relocated = (new_rule.get("owner_relocation") is not None
                                     and old_rule.get("owner_relocation") is None and not relocation_errors)
            new_allowed = set(new_rule["allowed_files"])
            new_only_allowed = new_allowed - renamed_allowed
            old_only_allowed = renamed_allowed - new_allowed
            preexisting_new_allowed = all(
                subprocess.run(
                    [
                        "git", "cat-file", "-e",
                        f"{base_ref}:MyWallpaperX/Core/SteamWorkshopScene/{path}",
                    ],
                    cwd=REPOSITORY_ROOT,
                    check=False,
                    capture_output=True,
                ).returncode == 0
                for path in new_only_allowed
            )
            removed_old_allowed = all(
                not (SCENE_SOURCE_ROOT / path).exists()
                for path in old_only_allowed
            )
            inventory_consolidated_without_growth = (
                old_rule.get("role") == "inventory"
                and int(new_rule["baseline_occurrences"])
                    <= int(old_rule["baseline_occurrences"])
                and len(new_allowed) <= len(renamed_allowed)
                and bool(new_only_allowed)
                and bool(old_only_allowed)
                and preexisting_new_allowed
                and removed_old_allowed
            )
            if (
                not new_allowed.issubset(renamed_allowed)
                and not inventory_consolidated_without_growth
                and not exact_owner_relocated
            ):
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
                and (
                    new_allowed == renamed_allowed
                    or inventory_consolidated_without_growth
                    or exact_owner_relocated
                )
                and set(new_rule.get("scope_files", [])) == renamed_scope
            )
            if not reaches_retirement_target and not definition_moved_without_authority_growth:
                for field in ("pattern", "start_marker", "end_marker"):
                    if new_rule.get(field) != old_rule.get(field):
                        violations.append(f"{rule_id}: {field} changed")
        self.assertEqual(violations, [])

    def test_ci_base_rejects_committed_receipt_tampering_and_invalid_base(self) -> None:
        with tempfile.TemporaryDirectory(prefix="mwx-authority-ci-base-") as temporary:
            root = Path(temporary)
            def git(*arguments: str) -> str:
                return subprocess.run(["git", *arguments], cwd=root, check=True,
                                      capture_output=True, text=True).stdout.strip()
            git("init", "--quiet")
            git("config", "user.name", "Ratchet Fixture")
            git("config", "user.email", "ratchet@example.invalid")
            scene = root / "MyWallpaperX/Core/SteamWorkshopScene"
            scene.mkdir(parents=True)
            (scene / "Owner.swift").write_text("struct Owner {}\n")
            path = root / "script/scene_source_layout.json"
            path.parent.mkdir()
            rule = {"id": "bounded-frontend-product-entry", "role": "inventory",
                    "pattern": r"SceneAuthoredShaderFrontend\.compile\(",
                    "baseline_occurrences": 1, "allowed_files": ["Owner.swift"]}
            prior_rule = {**rule, "allowed_files": ["Origin.swift"]}
            rule["owner_relocation"] = {
                "from_file": "Origin.swift", "to_file": "Owner.swift",
                "from_contract_sha256": authority_metric_digest(prior_rule),
                "to_contract_sha256": authority_metric_digest(rule),
                "design_doc": "docs/scene/roadmap/batch2/frame-admission-retry-design.md",
                "owner": "variant preparation", "reason": "original committed receipt",
                "retirement": "retire only after all calls disappear",
            }
            layout = {"render_chain_authority_ratchet": {"rules": [rule]}}
            path.write_text(json.dumps(layout))
            git("add", "script/scene_source_layout.json", "MyWallpaperX/Core/SteamWorkshopScene/Owner.swift")
            git("commit", "--quiet", "-m", "original receipt")
            original = git("rev-parse", "HEAD")
            rule["owner_relocation"]["reason"] = "rewritten in a later commit"
            path.write_text(json.dumps(layout))
            git("add", "script/scene_source_layout.json")
            git("commit", "--quiet", "-m", "tamper receipt")
            with patch.dict(globals(), REPOSITORY_ROOT=root, SCENE_SOURCE_ROOT=scene,
                            SCENE_LAYOUT_PATH=path):
                with patch.dict(os.environ, MWX_VALIDATION_BASE="HEAD"):
                    self.test_render_chain_ratchet_cannot_rise_above_committed_baseline()
                with patch.dict(os.environ, MWX_VALIDATION_BASE=original):
                    with self.assertRaisesRegex(AssertionError, "committed owner relocation"):
                        self.test_render_chain_ratchet_cannot_rise_above_committed_baseline()
                with patch.dict(os.environ, MWX_VALIDATION_BASE="missing-base-ref"):
                    with self.assertRaises(subprocess.CalledProcessError):
                        committed_scene_layout()

    def test_owner_relocation_preserves_calls_and_refuses_forged_receipts(self) -> None:
        old = {"id": "bounded-frontend-product-entry", "role": "inventory",
               "pattern": r"SceneAuthoredShaderFrontend\.compile\(", "baseline_occurrences": 2,
               "allowed_files": ["Origin.swift", "Stable.swift"]}
        new = {**old, "allowed_files": ["Destination.swift", "Stable.swift"]}
        receipt = {"from_file": "Origin.swift", "to_file": "Destination.swift",
                   "from_contract_sha256": authority_metric_digest(old),
                   "to_contract_sha256": authority_metric_digest(new),
                   "design_doc": "docs/scene/roadmap/batch2/frame-admission-retry-design.md",
                   "owner": "variant preparation", "reason": "whole frontend stage moved",
                   "retirement": "retire only after all calls disappear"}
        new["owner_relocation"] = receipt
        call = 'SceneAuthoredShaderFrontend.compile(vertexSource: "a", fragmentSource: make("b"))'
        previous = {"Origin.swift": call, "Stable.swift": call}
        current = {"Origin.swift": "struct Retained {}", "Destination.swift": call, "Stable.swift": call}
        self.assertEqual(authority_relocation_transition_violations(old, new, previous, current), [])
        altered = copy.deepcopy(current)
        altered["Destination.swift"] = call.replace('"a"', '"changed"')
        self.assertTrue(authority_relocation_transition_violations(old, new, previous, altered))
        for path in ("Destination.swift", "Third.swift"):
            altered = {**current, path: call + "\n" + call}
            self.assertTrue(authority_relocation_transition_violations(old, new, previous, altered))
        for field, value in (("pattern", "compile"), ("scope_files", ["Destination.swift"]),
                             ("baseline_occurrences", 3), ("allowed_files", ["Destination.swift", "Third.swift"])):
            altered = copy.deepcopy(new)
            altered[field] = value
            altered["owner_relocation"]["to_contract_sha256"] = authority_metric_digest(altered)
            self.assertTrue(authority_relocation_transition_violations(old, altered, previous, current))
        for field in ("from_contract_sha256", "to_contract_sha256", "from_file", "to_file", "design_doc", "owner"):
            altered = copy.deepcopy(new)
            altered["owner_relocation"][field] = "forged"
            if field == "owner":
                altered["owner_relocation"][field] = ""
            self.assertTrue(authority_relocation_transition_violations(old, altered, previous, current))
        self.assertEqual(authority_relocation_transition_violations(new, copy.deepcopy(new), {}, {}), [])
        for field, changed in (("pattern", "compile"), ("scope_files", ["Destination.swift"]),
                               ("allowed_files", ["Destination.swift", "NewOwner.swift"])):
            altered = copy.deepcopy(new); altered[field] = changed
            self.assertTrue(authority_relocation_transition_violations(new, altered, {}, {}))
        for action in ("rewrite", "delete"):
            altered = copy.deepcopy(new)
            if action == "rewrite":
                altered["owner_relocation"]["reason"] = "rewrite a committed receipt"
            else:
                del altered["owner_relocation"]
            self.assertTrue(authority_relocation_transition_violations(new, altered, {}, {}))

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

    def test_passive_declaration_classification_preserves_global_analyzer_discovery(self) -> None:
        layout = json.loads(SCENE_LAYOUT_PATH.read_text())
        rule = copy.deepcopy(next(rule for rule in layout["render_chain_authority_ratchet"]["rules"]
                                  if rule.get("metric") == "classified-declarations"))
        rule.update(baseline_occurrences=0, allowed_files=[])
        classification = rule["classifications"][0]
        declaration = classification["declaration"]
        positive = "#if DEBUG\nfinal class SceneDebugFrameCapture {\n" + declaration + "\n}\n#endif\n"
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / classification["file"]
            source.parent.mkdir(parents=True)
            source.write_text(positive)
            self.assertEqual(render_chain_authority_violations(root, [rule]), [])
            source.write_text(positive.replace(declaration, 'let message = """\n#endif\n"""\n' + declaration))
            self.assertEqual(render_chain_authority_violations(root, [rule]), [])
            mutations = {
                "same-file analyzer": positive.replace("\n}\n", "\nstruct NewAdmission {}\n}\n"),
                "method in passive enum": positive.replace("rejected(String) }", "rejected(String); func resolve() {} }"),
                "state in passive enum": positive.replace("rejected(String) }", "rejected(String); static var count = 0 }"),
                "changed condition": positive.replace("#if DEBUG", "#if RELEASE"),
                "alternate branch": positive.replace("#if DEBUG", "#if DEBUG\n#else"),
                "changed owner": positive.replace("SceneDebugFrameCapture", "OtherCapture"),
                "nested scope": positive.replace(declaration, "func nested() { " + declaration + " }"),
                "removed declaration": positive.replace(declaration, ""),
                "signature in string": positive.replace(declaration, 'let text = "' + declaration + '"'),
                "fake conditional in string": positive.replace("#if DEBUG\n", "", 1).replace(
                    "\n#endif\n", "\n").replace(declaration, 'let message = """\n#if DEBUG\n"""\n' + declaration),
            }
            for name, content in mutations.items():
                with self.subTest(name=name):
                    source.write_text(content)
                    self.assertTrue(render_chain_authority_violations(root, [rule]))
            source.write_text(positive)
            (root / "New.swift").write_text("struct NewAdmission {}\n")
            self.assertTrue(render_chain_authority_violations(root, [rule]))
            (root / "New.swift").write_text("extension SceneDebugFrameCapture.Admission { func resolve() {} }\n")
            self.assertTrue(render_chain_authority_violations(root, [rule]))
            (root / "New.swift").write_text("extension SceneDebugFrameCapture.`Admission` { func resolve() {} }\n")
            self.assertTrue(render_chain_authority_violations(root, [rule]))
            (root / "New.swift").write_text("typealias ResultType = SceneDebugFrameCapture.Admission\nextension ResultType { func resolve() {} }\n")
            self.assertTrue(render_chain_authority_violations(root, [rule]))
            (root / "New.swift").write_text("typealias Holder = SceneDebugFrameCapture\n")
            (root / "Alias.swift").write_text("typealias ResultType = Holder.Admission\n")
            (root / "Extension.swift").write_text("extension ResultType { func resolve() {} }\n")
            self.assertTrue(any("New.swift: typealias" in value for value in
                                render_chain_authority_violations(root, [rule])))

    def test_local_alias_metric_rejects_new_owners_and_unclassified_references(self) -> None:
        layout = json.loads(SCENE_LAYOUT_PATH.read_text())
        rule = next(rule for rule in layout["render_chain_authority_ratchet"]["rules"]
                    if rule.get("metric") == "local-alias-declarations")
        classification = rule["classifications"][0]
        declaration = classification["declaration"]
        body = declaration + "\nlet texture = dependencyEffect?.texture\n"
        def wrapped(body: str) -> str:
            return "struct SceneImageLayerCompositor {\nfunc drawOutcome() {\n" + body + "\n}\n}\n"
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / classification["file"]
            source.parent.mkdir(parents=True)
            source.write_text(wrapped(body))
            self.assertEqual(render_chain_authority_violations(root, [rule]), [])
            source.write_text(wrapped(body + "let second = dependencyEffect?.texture\n"))
            self.assertEqual(render_chain_authority_violations(root, [rule]), [])
            mutations = {
                "second declaration": wrapped(body + declaration),
                "mutable alias": wrapped(body.replace("let dependencyEffect", "var dependencyEffect")),
                "different producer": wrapped(body.replace("dependencyEffects.first", "otherEffects.first")),
                "extended producer": wrapped(body.replace("dependencyEffects.first", "dependencyEffects.first ?? other")),
                "new unknown read": wrapped(body + "consume(dependencyEffect)"),
                "property owner": wrapped(body) + "struct Other { let dependencyEffect: Int }",
                "outside scope": wrapped(body) + "let other = dependencyEffect?.texture",
                "wrong owning function": wrapped(body).replace("func drawOutcome", "func other"),
                "nested declaration": wrapped("if enabled { " + body + " }"),
                "member reference": wrapped(body + "let other = request.dependencyEffect?.texture"),
                "assignment": wrapped(body + "dependencyEffect?.texture = replacement"),
                "compound assignment": wrapped(body + "dependencyEffect?.blendMode %= 2"),
                "indexed assignment": wrapped(body + "dependencyEffect?.texture[0] = replacement"),
                "inout": wrapped(body + "mutate(&dependencyEffect?.texture)"),
            }
            for name, content in mutations.items():
                with self.subTest(name=name):
                    source.write_text(content)
                    self.assertTrue(render_chain_authority_violations(root, [rule]))
            source.write_text(wrapped(body))
            (root / "New.swift").write_text("let dependencyEffect = other.first\n")
            self.assertTrue(render_chain_authority_violations(root, [rule]))

    def test_classification_migration_binds_both_measured_contracts(self) -> None:
        # Protocol counterexamples must not depend on whether the repository's
        # first migration has already been committed. The separate live ratchet
        # test checks the selected Git base against the real current inventory.
        for metric in ("classified-declarations", "local-alias-declarations"):
            old = {
                "id": "fixture-inventory", "role": "inventory",
                "pattern": "fixtureOwner", "baseline_occurrences": 5,
                "allowed_files": ["Owner.swift"],
            }
            new = copy.deepcopy(old)
            new.update(metric=metric, baseline_occurrences=1, classifications=[{
                "declaration": "let fixtureOwner = request.owners.first",
            }])
            new["classification_migration"] = {
                "from_contract_sha256": authority_metric_digest(old),
                "to_contract_sha256": authority_metric_digest(new),
                "design_doc": "docs/development/structural-governance-design.md",
                "owner": "fixture owner", "reason": "reviewed metric migration",
                "retirement": "remove with the retired inventory",
            }
            self.assertEqual(classification_transition_violations(old, new), [])
            self.assertEqual(classification_transition_violations(new, copy.deepcopy(new)), [])
            for digest in ("from_contract_sha256", "to_contract_sha256"):
                invalid = copy.deepcopy(new)
                invalid["classification_migration"][digest] = "0" * 64
                self.assertTrue(classification_transition_violations(old, invalid))
            altered = copy.deepcopy(new)
            altered["classifications"][0]["declaration"] += " changed"
            self.assertTrue(classification_transition_violations(old, altered))
            altered["classification_migration"]["to_contract_sha256"] = authority_metric_digest(altered)
            self.assertTrue(classification_transition_violations(new, altered))
            retired = copy.deepcopy(old)
            retired["role"] = "retirement"
            self.assertTrue(classification_transition_violations(retired, new))
            removed = copy.deepcopy(new)
            del removed["classification_migration"]
            self.assertTrue(classification_transition_violations(new, removed))
            reopened = copy.deepcopy(altered)
            reopened["classification_migration"]["from_contract_sha256"] = authority_metric_digest(removed)
            reopened["classification_migration"]["to_contract_sha256"] = authority_metric_digest(reopened)
            self.assertTrue(classification_transition_violations(removed, reopened))
            for field, value in (("pattern", "NEVER"), ("scan_root", "Elsewhere"),
                                 ("scope_files", ["Only.swift"]), ("start_marker", "START"),
                                 ("end_marker", "END")):
                with self.subTest(field=field):
                    narrowed = copy.deepcopy(new)
                    narrowed[field] = value
                    self.assertTrue(classification_transition_violations(new, narrowed))
                    narrowed["classification_migration"]["to_contract_sha256"] = authority_metric_digest(narrowed)
                    self.assertTrue(classification_transition_violations(old, narrowed))
            shrunk = copy.deepcopy(new)
            shrunk["baseline_occurrences"] -= 1
            self.assertEqual(classification_transition_violations(new, shrunk), [])
            retired = copy.deepcopy(new)
            retired.update(classifications=[], baseline_occurrences=0, allowed_files=[])
            del retired["classification_migration"]
            self.assertEqual(classification_transition_violations(new, retired), [])
            reopened["classification_migration"]["from_contract_sha256"] = authority_metric_digest(retired)
            self.assertTrue(classification_transition_violations(retired, reopened))

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

    def test_relative_markdown_links_and_fragments_in_documentation_exist(self) -> None:
        missing: list[str] = []
        for relative in sorted(managed_documents(REPOSITORY_ROOT)):
            document = REPOSITORY_ROOT / relative
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
                    continue
                fragment = unquote(parsed.fragment)
                if fragment and resolved.is_file() and resolved.suffix == ".md":
                    anchors = markdown_anchors(resolved.read_text(encoding="utf-8"))
                    if fragment not in anchors:
                        missing.append(
                            f"{document.relative_to(REPOSITORY_ROOT)} -> {target} "
                            "(missing fragment)"
                        )

        self.assertEqual(missing, [], "Missing relative Markdown links:\n" + "\n".join(missing))

    def test_render_chain_scan_preserves_rule_ranges_and_refreshes_between_calls(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / "Owner.swift"
            source.write_text("FIRST\nOWNER()\nSECOND\nOWNER()\nEND\n// OWNER()\n")
            rules = [
                {"id": "first", "pattern": "OWNER", "allowed_files": ["Owner.swift"],
                 "baseline_occurrences": 1, "start_marker": "FIRST", "end_marker": "SECOND"},
                {"id": "second", "pattern": "OWNER", "allowed_files": ["Owner.swift"],
                 "baseline_occurrences": 1, "start_marker": "SECOND", "end_marker": "END"},
            ]
            self.assertEqual(render_chain_authority_violations(root, rules), [])
            source.write_text("FIRST\nOWNER()\nSECOND\nOWNER()\nOWNER()\nEND\n")
            violations = render_chain_authority_violations(root, rules)
            self.assertEqual(len(violations), 1)
            self.assertIn("second: occurrences 2 != baseline 1", violations[0])

    def test_documentation_links_include_untracked_but_exclude_ignored_artifacts(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            subprocess.run(["git", "init", "--quiet"], cwd=root, check=True, capture_output=True)
            (root / ".gitignore").write_text("docs/evidence/\n")
            (root / "docs/evidence").mkdir(parents=True)
            (root / "docs/evidence/ignored.md").write_text("[ignored broken link](missing.md)")
            (root / "docs/one.md").write_text("[two](two.md)")
            (root / "docs/two.md").write_text("# Two\n")
            with patch(__name__ + ".REPOSITORY_ROOT", root):
                self.test_relative_markdown_links_and_fragments_in_documentation_exist()
                (root / "docs/untracked.md").write_text("[broken](missing.md)")
                with self.assertRaisesRegex(AssertionError, "untracked.md"):
                    self.test_relative_markdown_links_and_fragments_in_documentation_exist()


if __name__ == "__main__":
    unittest.main()
