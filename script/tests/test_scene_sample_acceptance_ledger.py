#!/usr/bin/env python3
"""Focused contract tests for the Scene sample acceptance ledger."""

from __future__ import annotations

import json
import os
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch


SCRIPT_ROOT = Path(__file__).resolve().parents[1]
if str(SCRIPT_ROOT) not in sys.path:
    sys.path.insert(0, str(SCRIPT_ROOT))

from scene_sample_acceptance_ledger import (  # noqa: E402
    ALLOWED_VERDICTS,
    build_ledger,
    cluster_for,
    render_markdown,
    validate_verdict_references,
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

    def test_p0_2_verdict_relation_fields_default_to_unknown(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            samples = self._corpus(root)
            (root / "docs/scene/evidence").mkdir(parents=True)
            _write(root / "docs/scene/evidence/ready.md", {"note": "observed"})
            archive = _write(root / "archive.json", _archive([
                {"id": "10", "runtime": {"status": "not-run", "firstBreakpoint": None}},
            ]))
            legacy = _write(root / "legacy.json", _verdicts({
                "10": {"verdict": "fail", "reviewedOn": "2026-09-08", "note": "legacy entry"},
            }))
            ledger = build_ledger(samples, archive, legacy, root)
            row = next(item for item in ledger["samples"] if item["id"] == "10")
            self.assertEqual(row["reviewer"], "unknown")
            self.assertEqual(row["runs"], [])
            self.assertEqual(row["evidence"], [])
            self.assertEqual(row["remainingDifferences"], "unknown")
            self.assertEqual(row["officialComparison"], "unknown")
            summary = ledger["summary"]
            self.assertEqual(
                sorted(summary["officialComparisonCounts"]),
                ["blocked", "compared", "not-run", "unknown"],
            )
            self.assertEqual(summary["officialComparisonCounts"]["unknown"], 3)
            self.assertEqual(summary["reviewedWithoutViewer"], 1)
            self.assertEqual(summary["reviewedWithoutEvidence"], 1)

            # A blank string is a placeholder, not a recorded viewer identity.
            blank = _write(root / "blank.json", _verdicts({
                "10": {"verdict": "fail", "reviewedOn": "2026-09-08",
                       "reviewer": "   ", "remainingDifferences": "\t "},
            }))
            blanked = build_ledger(samples, archive, blank, root)
            row = next(item for item in blanked["samples"] if item["id"] == "10")
            self.assertEqual(row["reviewer"], "unknown")
            self.assertEqual(row["remainingDifferences"], "unknown")
            self.assertEqual(blanked["summary"]["reviewedWithoutViewer"], 1)

            full = _write(root / "full.json", _verdicts({
                "10": {
                    "verdict": "fail",
                    "reviewedOn": "2026-09-08",
                    "note": "annotated",
                    "reviewer": "operator",
                    "runs": ["/private/tmp/mwx-run/report.json#10"],
                    "evidence": ["docs/scene/evidence/ready.md#L3"],
                    "remainingDifferences": "text clipping",
                    "officialComparison": "not-run",
                },
                "20": {
                    "verdict": "pass",
                    "reviewedOn": "2026-09-08",
                    "note": "annotated",
                    "reviewer": "operator",
                    "evidence": ["docs/scene/evidence/ready.md"],
                    "remainingDifferences": "none",
                    "officialComparison": "compared",
                },
            }))
            annotated = build_ledger(samples, archive, full, root)
            row = next(item for item in annotated["samples"] if item["id"] == "10")
            self.assertEqual(row["reviewer"], "operator")
            self.assertEqual(row["runs"], ["/private/tmp/mwx-run/report.json#10"])
            self.assertEqual(row["evidence"], ["docs/scene/evidence/ready.md#L3"])
            self.assertEqual(row["remainingDifferences"], "text clipping")
            self.assertEqual(row["officialComparison"], "not-run")
            summary = annotated["summary"]
            self.assertEqual(summary["reviewedWithoutViewer"], 0)
            self.assertEqual(summary["reviewedWithoutEvidence"], 0)
            self.assertEqual(summary["officialComparisonCounts"]["unknown"], 1)
            markdown = render_markdown(annotated)
            self.assertIn("官方对照状态", markdown)
            for expected_row in (
                "| `unknown` | 1 |",
                "| `not-run` | 1 |",
                "| `blocked` | 0 |",
                "| `compared` | 1 |",
            ):
                self.assertIn(expected_row, markdown)

    def test_p0_2_verdict_relation_fields_fail_closed(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            samples = self._corpus(root)
            (root / "docs/scene/evidence").mkdir(parents=True)
            archive = _write(root / "archive.json", _archive([]))
            for name, entry, expected in (
                ("bad-official", {"officialComparison": "looks-compared"}, "officialComparison"),
                ("blank-official", {"officialComparison": "  "}, "officialComparison"),
                ("bad-runs", {"runs": "one-path"}, "runs must be a list"),
                ("mixed-runs", {"runs": ["ok", 5]}, "runs must be a list"),
                ("bad-reviewer", {"reviewer": 7}, "must be strings"),
                ("bad-remaining", {"remainingDifferences": None}, "must be strings"),
            ):
                overlay = _write(root / f"{name}.json", _verdicts({
                    "10": {"verdict": "fail", "reviewedOn": "2026-09-08", **entry},
                }))
                with self.assertRaisesRegex(ValueError, expected):
                    build_ledger(samples, archive, overlay, root)
            missing = _write(root / "missing.json", _verdicts({
                "10": {"verdict": "fail", "reviewedOn": "2026-09-08",
                       "evidence": ["docs/scene/evidence/does-not-exist.md#x"]},
            }))
            with self.assertRaisesRegex(ValueError, r"dangling references \(1\)"):
                build_ledger(samples, archive, missing, root)
            escaping = _write(root / "escaping.json", _verdicts({
                "10": {"verdict": "fail", "reviewedOn": "2026-09-08",
                       "evidence": ["../../../../etc/hosts"]},
            }))
            with self.assertRaisesRegex(ValueError, "outside-repository"):
                build_ledger(samples, archive, escaping, root)
            link = root / "docs/scene/escape-link"
            try:
                link.symlink_to("/etc/hosts")
            except OSError:
                link = None
            if link is not None:
                # An in-repository path that leaves the repository through a
                # symlink is an escape, not a filename to verify -- and the
                # absolute spelling of that same path is an escape too.
                for reference in ("docs/scene/escape-link", str(link)):
                    symlinked = _write(root / "symlinked.json", _verdicts({
                        "10": {"verdict": "fail", "reviewedOn": "2026-09-08",
                               "evidence": [reference]},
                    }))
                    with self.assertRaisesRegex(ValueError, "outside-repository"):
                        build_ledger(samples, archive, symlinked, root)
            # A directory is not a screenshot or run identity.
            directory_citation = _write(root / "directory.json", _verdicts({
                "10": {"verdict": "fail", "reviewedOn": "2026-09-08",
                       "evidence": ["docs/scene/evidence"]},
            }))
            with self.assertRaisesRegex(ValueError, "not-a-file"):
                build_ledger(samples, archive, directory_citation, root)

    def test_repository_internal_citations_are_checked_in_any_spelling(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            samples = self._corpus(root)
            archive = _write(root / "archive.json", _archive([]))
            (root / "docs/scene/evidence").mkdir(parents=True)
            tracked = _write(root / "docs/scene/evidence/ready.md", {"note": "observed"})
            spaced_name = "docs/scene/evidence note 01.48.33.png"
            (root / spaced_name).write_bytes(b"png")
            # `#` and `=` are filename characters, not only annotation syntax.
            (root / "docs/scene/evi2#dence.png").write_bytes(b"png")
            (root / "docs/scene/evi2").write_bytes(b"png")
            (root / "docs/scene/ led.md").write_bytes(b"md")
            (root / "docs/scene/lead.md").write_bytes(b"md")
            accepted = _write(root / "accepted.json", _verdicts({
                "10": {
                    "verdict": "fail",
                    "reviewedOn": "2026-09-08",
                    "evidence": [
                        # A filename with spaces is a path, not an annotation,
                        # with or without a trailing anchor/checksum note.
                        spaced_name,
                        spaced_name + "#L1",
                        spaced_name + " sha256=deadbeef",
                        spaced_name + "\tsize=3",
                        spaced_name + " sha256=deadbeef size=3 md5=crc crc32=1 blake2b=2",
                        "docs/scene/lead.md ",
                        "./docs/scene/evidence/ready.md",
                        "docs/scene/evidence/ready.md#L2",
                        "docs/scene/evi2#dence.png",
                        "docs/scene/evi2#dence.png#L1",
                        "docs/scene/ led.md",
                        str(tracked),
                    ],
                },
            }))
            ledger = build_ledger(samples, archive, accepted, root)
            self.assertEqual(ledger["summary"]["reviewedWithoutEvidence"], 0)

            # A same-prefix sibling must not lend its identity to a reference
            # that names a different, absent file.
            (root / "docs/scene/evi").write_bytes(b"png")
            for reference in (
                "docs/scene/evi dence note absent.png",
                # An unrecognized `#...` suffix is part of the path too: the
                # sibling `docs/scene/evi2` must not vouch for it.
                "docs/scene/evi2#absent.png",
                # Leading whitespace is not stripped, so this names no file.
                " docs/scene/lead.md",
            ):
                collision = _write(root / "collision.json", _verdicts({
                    "10": {"verdict": "fail", "reviewedOn": "2026-09-08",
                           "evidence": [reference]},
                }))
                with self.assertRaisesRegex(ValueError, "file-missing"):
                    build_ledger(samples, archive, collision, root)

            absolute_missing = _write(root / "absolute-missing.json", _verdicts({
                "10": {"verdict": "fail", "reviewedOn": "2026-09-08",
                       "evidence": [str(root / "docs/scene/evidence/gone.md")]},
            }))
            # An absolute spelling of a repository path is checked like the
            # relative one instead of being waved through as repository-external.
            with self.assertRaisesRegex(ValueError, "file-missing"):
                build_ledger(samples, archive, absolute_missing, root)

    def test_verdict_reference_gate_skips_transient_and_non_repository_paths(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            samples = self._corpus(root)
            archive = _write(root / "archive.json", _archive([]))
            evidence = [
                "/private/tmp/mwx-run/ready.png",
                "~/Movies/MyWallpaperX/创意工坊/Scene/10/截屏 01.48.33.png",
                "$HOME/Movies/MyWallpaperX/创意工坊/Scene/10/截屏 01.48.33.png",
            ]
            environment = {"HOME": "/nonexistent-home-for-reference-gate"}
            transient = _write(root / "transient.json", _verdicts({
                "10": {
                    "verdict": "fail",
                    "reviewedOn": "2026-09-08",
                    "runs": ["/private/tmp/mwx-run/report.json#10 sha256=deadbeef"],
                    "evidence": evidence,
                },
            }))
            with patch.dict(os.environ, environment):
                ledger = build_ledger(samples, archive, transient, root)
            row = next(item for item in ledger["samples"] if item["id"] == "10")
            self.assertEqual(row["verdict"], "fail")
            self.assertEqual(row["evidence"], evidence)
            for name, reference in (("anchor-only", "#anchor-only"), ("blank", "   ")):
                empty = _write(root / f"{name}.json", _verdicts({
                    "10": {"verdict": "fail", "reviewedOn": "2026-09-08", "evidence": [reference]},
                }))
                with self.assertRaisesRegex(ValueError, "reference-empty"):
                    build_ledger(samples, archive, empty, root)

    def test_verdict_loader_never_rewrites_the_human_overlay(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            samples = self._corpus(root)
            archive = _write(root / "archive.json", _archive([]))
            overlay = _write(root / "verdicts.json", _verdicts({
                "10": {"verdict": "fail", "reviewedOn": "2026-09-08", "note": "legacy entry"},
            }))
            before = overlay.read_bytes()
            before_mtime = overlay.stat().st_mtime_ns
            build_ledger(samples, archive, overlay, root)
            build_ledger(samples, archive, overlay, root)
            self.assertEqual(overlay.read_bytes(), before)
            self.assertEqual(overlay.stat().st_mtime_ns, before_mtime)
            document = json.loads(overlay.read_text(encoding="utf-8"))
            self.assertEqual(sorted(document["verdicts"]["10"]), ["note", "reviewedOn", "verdict"])

    def test_verdict_reference_validator_never_raises_on_malformed_input(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory).resolve()
            records = validate_verdict_references({
                "10": ["not-an-object"],
                "20": {"runs": 5, "evidence": [1, 2]},
                "30": {"evidence": "one-path"},
                "40": {"evidence": ["a" * 5000]},
                "50": {"evidence": ["docs/scene/evidence note 01.48.33.png"]},
            }, root)
            # The validator's own containers are guarded too: an audit script
            # calling it on unnormalized input gets records, not a traceback.
            self.assertEqual(
                validate_verdict_references(["10"], root)[0]["code"],
                "verdict-container-shape-invalid",
            )
            self.assertEqual(
                validate_verdict_references({"10": {}}, None)[0]["code"],
                "verdict-repository-root-invalid",
            )
            self.assertTrue(records)
            for record in records:
                self.assertEqual(
                    sorted(record), ["code", "field", "reference", "sample_id"]
                )
                self.assertTrue(record["code"].startswith("verdict-"))
            codes = {record["code"] for record in records}
            self.assertIn("verdict-entry-shape-invalid", codes)
            self.assertIn("verdict-evidence-reference-invalid", codes)
            shape = next(record for record in records if record["sample_id"] == "10")
            self.assertEqual((shape["field"], shape["reference"]), ("", ""))
            overlong = [record for record in records if record["sample_id"] == "40"]
            self.assertEqual(len(overlong), 1)
            self.assertEqual(overlong[0]["code"], "verdict-evidence-reference-unresolvable")



if __name__ == "__main__":
    unittest.main()
