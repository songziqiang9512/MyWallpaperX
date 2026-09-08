#!/usr/bin/env python3
"""Focused contract tests for the Scene sample acceptance ledger."""

from __future__ import annotations

import json
import sys
import tempfile
import unittest
from pathlib import Path


SCRIPT_ROOT = Path(__file__).resolve().parents[1]
if str(SCRIPT_ROOT) not in sys.path:
    sys.path.insert(0, str(SCRIPT_ROOT))

from scene_sample_acceptance_ledger import (  # noqa: E402
    ALLOWED_VERDICTS,
    build_ledger,
    cluster_for,
    render_markdown,
)


def _write(path: Path, value: object) -> Path:
    path.write_text(json.dumps(value, ensure_ascii=False), encoding="utf-8")
    return path


def _archive(rows: list[dict]) -> dict:
    return {"kind": "scene-sample-debug-archive", "generatedAtUtc": "2026-09-07T00:00:00+00:00", "samples": rows}


def _verdicts(entries: dict) -> dict:
    return {"schemaVersion": 1, "allowedVerdicts": list(ALLOWED_VERDICTS), "verdicts": entries}


class SceneSampleAcceptanceLedgerTests(unittest.TestCase):
    def _corpus(self, root: Path) -> Path:
        samples = root / "Scene"
        (samples / "10").mkdir(parents=True)
        (samples / "20").mkdir()
        (samples / "30").mkdir()
        (samples / "not-a-sample").mkdir()
        _write(samples / "10" / "project.json", {
            "title": "Ten | pipe",
            "general": {"properties": {
                "schemecolor": {"type": "color", "value": "1 1 1"},
                "speed": {"type": "slider", "value": 1, "condition": "toggle.value == true"},
                "toggle": {"type": "bool", "value": True},
                "legacy": {"value": 3},
            }},
        })
        _write(samples / "20" / "project.json", {
            "title": "Twenty",
            "general": {"properties": {"schemecolor": {"type": "color", "value": "1 1 1"}}},
        })
        return samples

    def test_runtime_evidence_never_produces_a_visual_verdict(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            samples = self._corpus(root)
            archive = _write(root / "archive.json", _archive([
                {"id": "10", "runtime": {"status": "structural-chain-complete-visual-review", "firstBreakpoint": None}},
                {"id": "20", "runtime": {"status": "blocked", "firstBreakpoint": {
                    "stage": "effect-admission", "owner": "EffectStageAdmission",
                    "reasonCode": "unified-capability-unavailable",
                    "capabilityProfileOrAuthoredShape": "backend:effect-family:blend",
                }}},
            ]))
            verdicts = _write(root / "verdicts.json", _verdicts({
                "20": {"verdict": "fail", "reviewedOn": "2026-09-08", "note": "effect missing"},
            }))
            ledger = build_ledger(samples, archive, verdicts)

        by_id = {row["id"]: row for row in ledger["samples"]}
        self.assertEqual(sorted(by_id), ["10", "20", "30"])
        self.assertEqual(by_id["10"]["verdict"], "unreviewed")
        self.assertEqual(by_id["10"]["cluster"], "visual-review")
        self.assertEqual(by_id["10"]["authored"]["parameterCount"], 4)
        self.assertEqual(by_id["10"]["authored"]["conditionalCount"], 1)
        self.assertEqual(by_id["10"]["authored"]["typeCounts"], {"bool": 1, "color": 1, "slider": 1, "untyped": 1})
        self.assertFalse(by_id["10"]["authored"]["schemeColorOnly"])
        self.assertTrue(by_id["20"]["authored"]["schemeColorOnly"])
        self.assertEqual(by_id["20"]["cluster"], "effect-chain")
        self.assertEqual(by_id["20"]["verdict"], "fail")
        self.assertEqual(by_id["20"]["firstBreakpoint"]["reasonCode"], "unified-capability-unavailable")
        self.assertEqual(by_id["30"]["runtimeStatus"], "not-run")
        self.assertEqual(by_id["30"]["cluster"], "not-run")
        self.assertEqual(by_id["30"]["authored"]["parseState"], "missing-project")
        self.assertEqual(ledger["summary"]["verdictCounts"], {"unreviewed": 2, "pass": 0, "fail": 1, "platform-unsupported": 0})
        self.assertEqual(ledger["summary"]["samplesWithAuthoredParameters"], 1)

        markdown = render_markdown(ledger)
        self.assertIn("| `10` | Ten \\| pipe | 4(1) bool 1 color 1 slider 1 untyped 1 |", markdown)
        self.assertIn("`effect-admission / EffectStageAdmission / unified-capability-unavailable / backend:effect-family:blend`", markdown)
        self.assertIn("| `30` | 30 | `missing-project` | `not-run` | - | `not-run` | `unreviewed` |  |", markdown)
        self.assertIn("`fail` 2026-09-08", markdown)
        self.assertNotIn("| `pass` | 1 |", markdown)

    def test_cluster_mapping_follows_first_breakpoint_owner(self) -> None:
        self.assertEqual(cluster_for("degraded-runtime", {"stage": "resource-load", "owner": "ParticleRuntime"}), "particle-load")
        self.assertEqual(cluster_for("degraded-runtime", {"stage": "resource-load", "owner": "BaseImageTextureStore"}), "texture-load")
        self.assertEqual(cluster_for("blocked", {"stage": "graph-execution", "owner": "GraphExecutor"}), "effect-chain")
        self.assertEqual(cluster_for("degraded-runtime", {"stage": "script-execution", "owner": "SceneScriptVM"}), "scenescript")
        self.assertEqual(cluster_for("structural-chain-complete-visual-review", None), "visual-review")
        self.assertEqual(cluster_for("not-run", None), "not-run")

    def test_invalid_overlays_fail_closed(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            samples = self._corpus(root)
            archive = _write(root / "archive.json", _archive([]))
            bad_value = _write(root / "bad-value.json", _verdicts({"10": {"verdict": "looks-fine", "reviewedOn": "2026-09-08"}}))
            with self.assertRaisesRegex(ValueError, "invalid verdict"):
                build_ledger(samples, archive, bad_value)
            missing_date = _write(root / "missing-date.json", _verdicts({"10": {"verdict": "pass"}}))
            with self.assertRaisesRegex(ValueError, "requires reviewedOn"):
                build_ledger(samples, archive, missing_date)
            unknown_sample = _write(root / "unknown.json", _verdicts({"99": {"verdict": "fail", "reviewedOn": "2026-09-08"}}))
            with self.assertRaisesRegex(ValueError, "absent from the root"):
                build_ledger(samples, archive, unknown_sample)
            wrong_allowed = _write(root / "allowed.json", {"allowedVerdicts": ["pass"], "verdicts": {}})
            with self.assertRaisesRegex(ValueError, "allowedVerdicts"):
                build_ledger(samples, archive, wrong_allowed)


if __name__ == "__main__":
    unittest.main()
