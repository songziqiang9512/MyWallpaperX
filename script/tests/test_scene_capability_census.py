#!/usr/bin/env python3

from __future__ import annotations

import json
import io
import sys
import tempfile
import unittest
from contextlib import redirect_stderr, redirect_stdout
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch


SCRIPT_ROOT = Path(__file__).resolve().parents[1]
if str(SCRIPT_ROOT) not in sys.path:
    sys.path.insert(0, str(SCRIPT_ROOT))

import scene_capability_census as census
import scene_sample_debug_archive as debug_archive
from scene_capability_census_io import (
    PkgArchive,
    ensure_outputs_outside_roots,
    is_sample_directory_name,
    iter_sample_directories,
    validated_sample_id,
)
from script.tests.scene_capability_census_test_support import json_bytes, make_fixture, pkg


class SceneCapabilityCensusTests(unittest.TestCase):
    def test_cli_defaults_use_local_evidence_cache(self) -> None:
        expected = census.REPOSITORY_ROOT / ".artifacts/scene-evidence/census/scene_capability_census_snapshot.json"
        for command in ("generate", "verify", "query"):
            self.assertEqual(census.parse_args([command]).snapshot, expected)
        self.assertEqual(
            census.parse_args(["generate", "--sample-markdown", "/tmp/details.md"]).sample_markdown,
            Path("/tmp/details.md"),
        )
        self.assertEqual(
            debug_archive.parse_args(["--report", "/tmp/report.json", "--output", "/tmp/archive.json"]).snapshot,
            expected,
        )

    def test_missing_query_cache_fails_actionably_without_live_scan(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            args = census.parse_args(["query", "--sample", "123", "--snapshot", str(Path(directory) / "absent.json")])
            error = io.StringIO()
            with patch.object(census, "build_census") as build, redirect_stderr(error):
                self.assertEqual(census.query(args), 1)
                build.assert_not_called()
            self.assertIn("--snapshot <existing-cache>", error.getvalue())
            self.assertIn("generate", error.getvalue())

    def test_missing_archive_cache_fails_before_sample_discovery(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            with patch.object(debug_archive, "iter_sample_directories") as discover:
                with self.assertRaisesRegex(ValueError, "--snapshot <existing-cache>"):
                    debug_archive.build_archive(root, root / "absent.json", [root / "report.json"])
                discover.assert_not_called()

    def test_generate_verify_and_input_root_write_rejection(self) -> None:
        with tempfile.TemporaryDirectory(prefix="mwx-scene-census-") as directory:
            root = Path(directory)
            samples, stock, matrix, ledger = make_fixture(root)
            snapshot = root / "out/census.json"
            markdown = root / "out/census.md"
            args = type("Args", (), {
                "samples_root": samples, "stock_root": stock,
                "matrix": matrix, "ledger": ledger,
                "snapshot": snapshot, "markdown": markdown,
            })()
            with patch.object(census, "atomic_write", wraps=census.atomic_write) as write:
                self.assertEqual(census.generate(args), 0)
            self.assertEqual(
                [call.args[0] for call in write.call_args_list],
                [snapshot, markdown, markdown.with_name("scene-corpus-sample-inventory.md")],
            )
            stored = json.loads(snapshot.read_text(encoding="utf-8"))
            self.assertNotIn("occurrences", stored)
            self.assertEqual(stored["validation"]["occurrence_index"]["count"], 61)
            self.assertEqual(len(stored["validation"]["occurrence_index"]["items"]), 61)
            self.assertEqual(stored["samples"][0]["occurrence_count"], 61)
            system_index = [
                item for item in stored["validation"]["occurrence_index"]["items"]
                if "-system-" in item["kind"]
            ]
            self.assertEqual(len(system_index), 9)
            self.assertEqual(
                {item["effective_visibility"] for item in system_index},
                {"hidden", "visible"},
            )
            manifest = stored["snapshot"]["generator"]["source_manifest"]
            self.assertEqual(set(manifest["files"]), set(census.GENERATOR_PATHS))
            self.assertEqual(manifest["sha256"], census.canonical_sha256(manifest["files"]))
            generated_markdown = markdown.read_text(encoding="utf-8")
            self.assertIn(
                "| family | 修复事件 / 事件运行证据 / 事件回归保护（非能力状态） |",
                generated_markdown,
            )
            self.assertIn("_尚无已登记修复_", generated_markdown)
            sample_page = markdown.with_name("scene-corpus-sample-inventory.md")
            self.assertIn("(scene-corpus-sample-inventory.md)", generated_markdown)
            self.assertIn("(census.md)", sample_page.read_text(encoding="utf-8"))
            self.assertEqual(census.verify(args), 0)
            snapshot_query = type("Args", (), {
                "samples_root": samples, "stock_root": stock,
                "matrix": matrix, "ledger": ledger,
                "family": None, "sample": "0000000001", "domain": "texture",
                "live": False, "snapshot": snapshot,
            })()
            query_output = io.StringIO()
            with redirect_stdout(query_output):
                self.assertEqual(census.query(snapshot_query), 0)
            self.assertEqual(json.loads(query_output.getvalue())["source"], "cached-snapshot")
            snapshot.write_text("{}", encoding="utf-8")
            self.assertEqual(census.verify(args), 1)
            with self.assertRaises(ValueError):
                ensure_outputs_outside_roots([samples / "bad.json"], [samples, stock])

    def test_query_requires_a_filter_and_reconstructs_occurrences(self) -> None:
        with tempfile.TemporaryDirectory(prefix="mwx-scene-census-") as directory:
            samples, stock, matrix, ledger = make_fixture(Path(directory))
            filtered = type("Args", (), {
                "samples_root": samples,
                "stock_root": stock,
                "matrix": matrix,
                "ledger": ledger,
                "family": None,
                "sample": "0000000001",
                "domain": "texture",
                "live": True,
                "snapshot": Path(directory) / "missing.json",
            })()
            output = io.StringIO()
            with redirect_stdout(output):
                self.assertEqual(census.query(filtered), 0)
            payload = json.loads(output.getvalue())
            self.assertEqual(payload["filters"]["sample"], "0000000001")
            self.assertGreater(payload["count"], 0)
            self.assertEqual(
                {value["domain"] for value in payload["occurrences"]},
                {"texture"},
            )

            unfiltered = type("Args", (), {
                "samples_root": samples,
                "stock_root": stock,
                "matrix": matrix,
                "ledger": ledger,
                "family": None,
                "sample": None,
                "domain": None,
                "live": True,
                "snapshot": Path(directory) / "missing.json",
            })()
            with redirect_stderr(io.StringIO()), redirect_stdout(io.StringIO()):
                self.assertEqual(census.query(unfiltered), 2)

    def test_verify_missing_cache_does_not_scan_live_corpus(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            args = type("Args", (), {"snapshot": Path(directory) / "missing.json"})()
            with patch.object(census, "build_census") as build, redirect_stderr(io.StringIO()) as error:
                self.assertEqual(census.verify(args), 1)
            build.assert_not_called()
            self.assertIn("generate", error.getvalue())

    def test_pkg_reader_reports_duplicate_path_without_hiding_it(self) -> None:
        with tempfile.TemporaryDirectory(prefix="mwx-scene-census-") as directory:
            package = Path(directory) / "fixture.pkg"
            package.write_bytes(pkg([
                ("scene.json", b"{}"),
                ("fonts/font.otf", b"same"),
                ("fonts/font.otf", b"same"),
            ]))
            with PkgArchive(package) as archive:
                self.assertEqual(len(archive.entries), 3)
                self.assertEqual(len(archive.matches("fonts/font.otf")), 2)
                duplicate = next(
                    item for item in archive.diagnostics
                    if item["code"] == "duplicate-package-path"
                )
                self.assertTrue(duplicate["content_equal"])

    def test_unsafe_package_paths_and_output_symlinks_fail_closed(self) -> None:
        with tempfile.TemporaryDirectory(prefix="mwx-scene-census-") as directory:
            root = Path(directory)
            package = root / "fixture.pkg"
            package.write_bytes(pkg([
                ("scene.json", b"{}"),
                ("../scene.json", b"unsafe"),
                ("/scene.json", b"absolute"),
            ]))
            with PkgArchive(package) as archive:
                self.assertEqual(len(archive.matches("scene.json")), 1)
                self.assertEqual(
                    sum(item["code"] == "unsafe-package-path" for item in archive.diagnostics),
                    2,
                )

            samples = root / "samples"
            outside = root / "outside"
            samples.mkdir()
            outside.mkdir()
            linked = samples / "linked"
            linked.symlink_to(outside, target_is_directory=True)
            with self.assertRaises(ValueError):
                ensure_outputs_outside_roots([linked / "census.json"], [samples])

    def test_verified_ledger_requires_visible_proof_gates_and_event(self) -> None:
        ledger = {
            "schema_version": 1,
            "status_contract": census.REPAIR_STATUS_CONTRACT,
            "families": [{
                "family_key": "effect/fixture@1",
                "repair_state": "bounded-verified",
                "runtime_proof_state": "partial-chain",
                "regression_protection_state": "synthetic",
                "regression_gates": [{"kind": "synthetic-positive", "reference": "fixture"}],
                "events": [],
            }],
        }
        failures = census.validate_repair_ledger(ledger, {"effect/fixture@1"})
        self.assertEqual(
            {failure["code"] for failure in failures},
            {
                "verified-repair-lacks-visible-proof",
                "verified-repair-lacks-targeted-regression-protection",
                "verified-repair-lacks-regression-gates",
                "verified-repair-lacks-event",
                "verified-repair-missing-fields",
                "verified-repair-field-invalid",
            },
        )

    def test_valid_verified_ledger_and_invalid_enums(self) -> None:
        valid = {
            "schema_version": 1,
            "status_contract": census.REPAIR_STATUS_CONTRACT,
            "families": [{
                "family_key": "effect/fixture@1",
                "repair_state": "bounded-verified",
                "runtime_proof_state": "visible-chain-closed",
                "regression_protection_state": "targeted-runtime",
                "root_cause": "typed public cause",
                "public_fix": "public fix",
                "commit": "abcdef0",
                "targeted_samples": ["fixture"],
                "roi_evidence": ["report#roi"],
                "remaining_boundaries": ["official parity unproven"],
                "regression_gates": [
                    {"kind": "synthetic-positive", "reference": "test#positive"},
                    {"kind": "synthetic-negative", "reference": "test#negative"},
                    {"kind": "targeted-runtime", "reference": "report#runtime"},
                ],
                "events": [{
                    "date": "2026-08-13",
                    "state": "bounded-verified",
                    "commit": "abcdef0",
                    "evidence_refs": ["report#runtime"],
                    "notes": "bounded fixture",
                }],
            }],
        }
        self.assertFalse(census.validate_repair_ledger(valid, {"effect/fixture@1"}))
        rendered = census.render_markdown({
            "summary": {
                "discovered_sample_count": 0, "parsed_sample_count": 0,
                "matrix_sample_count": 0, "matrix_coverage_state": "current-complete",
                "added_since_matrix": [], "occurrence_count": 0, "family_count": 0,
                "parameter_profile_count": 0, "schema_field_profile_count": 0,
                "package_entry_count": 0, "package_unique_path_count": 0,
                "package_byte_count": 0, "unclassified_count": 0,
                "generic_or_unknown_family_count": 0,
                "texture": {
                    "physical_resource_count": 0, "physical_format_counts": {},
                    "physical_feature_counts": {}, "use_occurrence_count": 0,
                    "use_state_counts": {},
                },
                "object_kind_counts": {}, "visible_object_kind_counts": {},
                "effect_instance_count": 0, "particle_layer_count": 0,
                "dynamic_feature_counts": {},
            },
            "samples": [], "families": [], "occurrences": [],
            "repair_ledger": valid,
        })
        self.assertIn("`effect/fixture@1`", rendered)
        self.assertIn("`bounded-verified / visible-chain-closed / targeted-runtime`", rendered)
        self.assertIn("修复事件（非能力状态）", rendered)
        self.assertIn("不是该 family 的能力实现、current、support 或待办状态", rendered)
        self.assertIn("`untriaged` 不表示缺失", rendered)
        self.assertIn("public fix", rendered)
        self.assertIn("official parity unproven", rendered)
        valid["families"][0]["repair_state"] = "complete"
        self.assertIn(
            "repair-state-invalid",
            {failure["code"] for failure in census.validate_repair_ledger(
                valid, {"effect/fixture@1"}
            )},
        )

    def test_repair_references_gate_accepts_resolved_and_transient_targets(self) -> None:
        # A kind outside the built-in defaults proves the gate reads the ledger's
        # own contract instead of silently falling back to the defaults.
        ledger = {
            "entry_contract": {
                "regression_gate_kinds": [
                    *census.DEFAULT_REGRESSION_GATE_KINDS, "fixture-only-kind",
                ],
            },
            "families": [{
                "family_key": "effect/fixture@1",
                "commit": "uncommitted-working-tree",
                "targeted_samples": ["3747492842"],
                "roi_evidence": [
                    "script/scene_capability_census.py#anchor",
                    "/private/tmp/mwx-some-run/report.json sha256=deadbeef",
                ],
                "regression_gates": [
                    {
                        "kind": "synthetic-positive",
                        "reference": "script/tests/test_scene_capability_census_observations.py"
                                     "#test_family_key_ignores_concrete_revision_values",
                    },
                    {
                        "kind": "fixture-only-kind",
                        "reference": "script/scene_capability_census.py"
                                     "#validate_repair_references",
                    },
                    {
                        "kind": "targeted-runtime",
                        "reference": "/private/tmp/mwx-some-run/report.json#3747492842",
                    },
                ],
                "events": [{
                    "date": "2026-09-17",
                    "state": "implemented",
                    "commit": "abcdef0",
                    "evidence_refs": ["script/scene_capability_census.py#anchor"],
                    "notes": "fixture",
                }],
            }],
        }
        failures = census.validate_repair_references(
            ledger, {"3747492842"}, census.REPOSITORY_ROOT
        )
        self.assertEqual(failures, [])

    def test_repair_references_gate_rejects_dangling_and_unknown_targets(self) -> None:
        ledger = {
            "entry_contract": {"regression_gate_kinds": list(census.DEFAULT_REGRESSION_GATE_KINDS)},
            "families": [{
                "family_key": "effect/fixture@1",
                "commit": "not-a-commit",
                "targeted_samples": ["0000000000"],
                "roi_evidence": ["docs/scene/capabilities/does-not-exist.md"],
                "regression_gates": [
                    {
                        "kind": "synthetic-positive",
                        "reference": "script/tests/test_scene_dynamic_snapshot.py"
                                     "#test_symbol_absent_from_every_file_zz",
                    },
                    {
                        "kind": "synthetic-negative",
                        "reference": "script/tests/test_missing_fixture_file.py#test_nothing",
                    },
                    {
                        "kind": "synthetic-negative",
                        "reference": "../outside-the-repository.py#test_nothing",
                    },
                    {"kind": "made-up-kind", "reference": "script/tests/whatever.py#test_x"},
                ],
                "events": [{
                    "date": "2026-09-17",
                    "state": "implemented",
                    "commit": "abcdef0",
                    "evidence_refs": ["docs/scene/capabilities/does-not-exist.md"],
                    "notes": "fixture",
                }],
            }],
        }
        codes = {failure["code"] for failure in census.validate_repair_references(
            ledger, {"3747492842"}, census.REPOSITORY_ROOT
        )}
        self.assertEqual(codes, {
            "repair-sample-reference-unknown",
            "repair-gate-symbol-missing",
            "repair-gate-file-missing",
            "repair-gate-reference-outside-repository",
            "repair-gate-kind-unknown",
            "repair-evidence-file-missing",
            "repair-commit-shape-invalid",
        })

    def test_local_evidence_is_optional_but_missing_gates_and_documents_fail(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            ledger = {"families": [{
                "family_key": "test", "commit": "abcdef0",
                "regression_gates": [{"kind": "synthetic-positive",
                    "reference": ".codex/missing.py#test_example"}],
                "roi_evidence": [".artifacts/scene-evidence/run.json", ".codex/result.json",
                                 "docs/missing.md"],
            }]}
            failures = census.validate_repair_references(ledger, set(), Path(directory))
            self.assertEqual({entry["code"] for entry in failures},
                             {"repair-gate-file-missing", "repair-evidence-file-missing"})
            self.assertEqual(len(failures), 2)

    def test_default_repair_ledger_has_no_dangling_references(self) -> None:
        ledger = census.load_repair_ledger(census.DEFAULT_LEDGER)
        if not census.DEFAULT_SNAPSHOT.is_file():
            self.skipTest(
                "private corpus census cache unavailable; generate explicitly at "
                f"{census.DEFAULT_SNAPSHOT} to check default repair-ledger sample relationships"
            )
        snapshot = json.loads(census.DEFAULT_SNAPSHOT.read_text(encoding="utf-8"))
        sample_ids: set[str] = set()

        def collect(node: object) -> None:
            if isinstance(node, dict):
                values = node.get("sample_ids")
                if isinstance(values, list):
                    sample_ids.update(v for v in values if isinstance(v, str))
                for value in node.values():
                    collect(value)
            elif isinstance(node, list):
                for value in node:
                    collect(value)

        collect(snapshot)
        self.assertTrue(sample_ids)
        failures = census.validate_repair_references(
            ledger, sample_ids, census.REPOSITORY_ROOT
        )
        self.assertEqual(failures, [])

    def test_repair_references_gate_never_raises_on_malformed_input(self) -> None:
        malformed = [
            None,
            [],
            "not a ledger",
            {"families": 5},
            {"families": [{"family_key": "a", "regression_gates": 5}]},
            {"families": [{"family_key": "a", "regression_gates": True}]},
            {"families": [{"family_key": "a", "regression_gates": [
                {"kind": [], "reference": "script/tests/test_scene_capability_census.py#x"},
            ]}]},
            {"families": [{"family_key": "a", "targeted_samples": 7, "roi_evidence": 7}]},
            {"families": [{"family_key": "a", "events": 7}]},
            {"families": [{"family_key": "a", "events": [{"evidence_refs": 7}]}]},
            {"families": [{"family_key": "a", "regression_gates": [
                {"kind": "synthetic-positive", "reference": "a\u0000b.py#x"},
            ]}]},
            {"families": 5, "entry_contract": 7},
        ]
        for index, ledger in enumerate(malformed):
            with self.subTest(index=index):
                failures = census.validate_repair_references(
                    ledger, {"3747492842"}, census.REPOSITORY_ROOT
                )
                self.assertIsInstance(failures, list)
        self.assertEqual(
            {"repair-ledger-not-object"},
            {failure["code"] for failure in census.validate_repair_references(
                None, set(), census.REPOSITORY_ROOT
            )},
        )

    def test_repair_references_gate_rejects_references_that_escape(self) -> None:
        ledger = {
            "families": [{
                "commit": "abcdef0",
                "roi_evidence": [
                    "../../../../etc/hosts",
                    "#anchor only",
                ],
                "regression_gates": [
                    {
                        "kind": "synthetic-positive",
                        "reference": "../sibling-with-same-prefix/file.py#test_x",
                    },
                ],
            }],
        }
        codes = {failure["code"] for failure in census.validate_repair_references(
            ledger, set(), census.REPOSITORY_ROOT
        )}
        self.assertEqual(codes, {
            "repair-gate-reference-outside-repository",
            "repair-evidence-reference-outside-repository",
        })

    def test_repair_gate_symbol_must_be_a_whole_identifier(self) -> None:
        ledger = {
            "families": [{
                "commit": "abcdef0",
                "regression_gates": [
                    {
                        "kind": "synthetic-positive",
                        "reference": "script/scene_capability_census.py"
                                     "#validate_repair_references",
                    },
                    {
                        "kind": "synthetic-negative",
                        "reference": "script/scene_capability_census.py"
                                     "#validate_repair",
                    },
                ],
            }],
        }
        failures = census.validate_repair_references(
            ledger, set(), census.REPOSITORY_ROOT
        )
        self.assertEqual(
            [failure["code"] for failure in failures],
            ["repair-gate-symbol-missing"],
        )


class SceneCapabilityCensusOutputTests(unittest.TestCase):
    def output_args(self, root: Path, *, failed_samples: bool = False) -> SimpleNamespace:
        samples, stock, matrix, ledger = make_fixture(root, include_failures=failed_samples)
        return SimpleNamespace(samples_root=samples, stock_root=stock, matrix=matrix, ledger=ledger,
                               snapshot=root / "out/census.json", markdown=root / "out/overview.md",
                               sample_markdown=root / "out/details.md")

    def test_two_pages_share_one_observation_and_keep_failure_rows_and_matrix_labels(self) -> None:
        with tempfile.TemporaryDirectory(prefix="mwx-census-pages-") as directory:
            root = Path(directory)
            args = self.output_args(root, failed_samples=True)
            args.sample_markdown = root / "details/samples.md"
            args.matrix.write_bytes(json_bytes({"schema_version": 1, "samples": [{"id": "0000000001"}]}))
            with patch.object(census, "build_census", wraps=census.build_census) as build, \
                    patch.object(census, "render_markdown", wraps=census.render_markdown) as overview, \
                    patch.object(census, "render_sample_markdown", wraps=census.render_sample_markdown) as detail, \
                    redirect_stdout(io.StringIO()):
                self.assertEqual(census.generate(args), 0)
                build.assert_called_once()
                overview.assert_called_once()
                detail.assert_called_once()
                self.assertIs(overview.call_args.args[0], detail.call_args.args[0])
            summary_page = args.markdown.read_text(encoding="utf-8")
            sample_page = args.sample_markdown.read_text(encoding="utf-8")
            self.assertIn("[全样本静态明细](../details/samples.md)", summary_page)
            self.assertIn("[声明统计](../out/overview.md)", sample_page)
            self.assertIn("旧1 matrix成员", sample_page)
            for sample_id, member in (("0000000001", "是"), ("0000000002", "否"), ("0000000003", "否")):
                row = next(line for line in sample_page.splitlines() if line.startswith(f"| `{sample_id}` |"))
                self.assertTrue(row.endswith(f"| {member} |"), row)
                self.assertNotIn("新增", row)
                self.assertNotIn("census未join runtime", row)
                self.assertNotIn(f"| `{sample_id}` |", summary_page)
            bad_project = next(line for line in sample_page.splitlines() if line.startswith("| `0000000003` |"))
            self.assertIn("截图+说明", bad_project)
            self.assertIn("project-json-missing", sample_page)
            self.assertIn("json-decode-failed", sample_page)
            stored = json.loads(args.snapshot.read_text(encoding="utf-8"))
            self.assertEqual(stored["summary"]["failed_sample_count"], 2)
            self.assertEqual(len(stored["samples"]), 3)
            with patch.object(census, "build_census", wraps=census.build_census) as build, redirect_stdout(io.StringIO()):
                self.assertEqual(census.verify(args), 0)
                build.assert_called_once()

    def test_verify_identifies_each_output_drift_independently(self) -> None:
        with tempfile.TemporaryDirectory(prefix="mwx-census-drift-") as directory:
            args = self.output_args(Path(directory))
            with redirect_stdout(io.StringIO()):
                self.assertEqual(census.generate(args), 0)
            for field, code in (("snapshot", "snapshot-drift"), ("markdown", "markdown-drift"),
                                ("sample_markdown", "sample-markdown-drift")):
                with self.subTest(output=field):
                    path = getattr(args, field)
                    original = path.read_bytes()
                    try:
                        path.write_bytes(b"independent drift")
                        output = io.StringIO()
                        with patch.object(census, "build_census", wraps=census.build_census) as build, redirect_stdout(output):
                            self.assertEqual(census.verify(args), 1)
                            build.assert_called_once()
                        self.assertEqual([item["code"] for item in json.loads(output.getvalue())["failures"]], [code])
                    finally:
                        path.write_bytes(original)

    def test_cli_default_detail_is_sibling_of_custom_overview(self) -> None:
        with tempfile.TemporaryDirectory(prefix="mwx-census-default-detail-") as directory:
            root = Path(directory)
            samples, stock, matrix, ledger = make_fixture(root)
            overview = root / "custom/custom-overview.md"
            args = census.parse_args(["generate", "--samples-root", str(samples), "--stock-root", str(stock),
                "--matrix", str(matrix), "--ledger", str(ledger), "--snapshot", str(root / "cache.json"),
                "--markdown", str(overview)])
            with patch.object(census, "atomic_write", wraps=census.atomic_write) as write, redirect_stdout(io.StringIO()):
                self.assertEqual(census.generate(args), 0)
            detail = overview.with_name("scene-corpus-sample-inventory.md")
            self.assertEqual([call.args[0] for call in write.call_args_list], [args.snapshot, overview, detail])
            self.assertTrue(detail.is_file())
            self.assertIn("(custom-overview.md)", detail.read_text(encoding="utf-8"))
            self.assertIn("(scene-corpus-sample-inventory.md)", overview.read_text(encoding="utf-8"))

    def test_outputs_in_input_roots_or_resolving_there_fail_before_scan_or_write(self) -> None:
        with tempfile.TemporaryDirectory(prefix="mwx-census-protected-") as directory:
            root = Path(directory)
            args = self.output_args(root)
            args.snapshot.parent.mkdir()
            args.snapshot.write_bytes(b"existing snapshot")
            for input_root in (args.samples_root, args.stock_root):
                protected = input_root / "protected.json"
                protected.write_bytes(b"unchanged input")
                link = root / f"link-{input_root.name}"
                link.symlink_to(input_root, target_is_directory=True)
                for field in ("snapshot", "markdown", "sample_markdown"):
                    for target in (protected, link / "protected.json"):
                        for command in (census.generate, census.verify):
                            with self.subTest(root=input_root.name, output=field, target=target, command=command.__name__):
                                bad = SimpleNamespace(**vars(args))
                                setattr(bad, field, target)
                                with patch.object(census, "build_census") as build, patch.object(census, "atomic_write") as write:
                                    with self.assertRaises(ValueError):
                                        command(bad)
                                    build.assert_not_called()
                                    write.assert_not_called()
                                self.assertEqual(protected.read_bytes(), b"unchanged input")
            self.assertFalse(args.markdown.exists())
            self.assertFalse(args.sample_markdown.exists())
            self.assertEqual(args.snapshot.read_bytes(), b"existing snapshot")

    def test_pairwise_output_collisions_include_symlink_aliases(self) -> None:
        with tempfile.TemporaryDirectory(prefix="mwx-census-collision-") as directory:
            root = Path(directory)
            args = self.output_args(root)
            args.snapshot.parent.mkdir()
            args.snapshot.write_bytes(b"existing snapshot")
            fields = ("snapshot", "markdown", "sample_markdown")
            common = root / "shared-output"
            common.write_bytes(b"preserve shared output")
            alias = root / "shared-alias"
            alias.symlink_to(common)
            for left, right in ((fields[0], fields[1]), (fields[0], fields[2]), (fields[1], fields[2])):
                for second in (common, alias):
                    for command in (census.generate, census.verify):
                        with self.subTest(left=left, right=right, symlink=second == alias, command=command.__name__):
                            bad = SimpleNamespace(**vars(args))
                            setattr(bad, left, common)
                            setattr(bad, right, second)
                            with patch.object(census, "build_census") as build, patch.object(census, "atomic_write") as write:
                                with self.assertRaises(ValueError):
                                    command(bad)
                                build.assert_not_called()
                                write.assert_not_called()
                            self.assertEqual(common.read_bytes(), b"preserve shared output")

    def test_every_projection_failure_precedes_all_writes(self) -> None:
        with tempfile.TemporaryDirectory(prefix="mwx-census-projection-") as directory:
            root = Path(directory)
            args = self.output_args(root)
            outputs = (args.snapshot, args.markdown, args.sample_markdown)
            for existing in (False, True):
                if existing:
                    args.snapshot.parent.mkdir()
                    for output in outputs:
                        output.write_bytes(b"old generation")
                for renderer in ("snapshot_payload", "render_markdown", "render_sample_markdown"):
                    with self.subTest(existing=existing, projection=renderer):
                        with patch.object(census, renderer, side_effect=RuntimeError("projection failure")), \
                                patch.object(census, "build_census", wraps=census.build_census) as build, \
                                patch.object(census, "atomic_write") as write:
                            with self.assertRaisesRegex(RuntimeError, "projection failure"):
                                census.generate(args)
                            build.assert_called_once()
                            write.assert_not_called()
                        for output in outputs:
                            if existing:
                                self.assertEqual(output.read_bytes(), b"old generation")
                            else:
                                self.assertFalse(output.exists())
                if not existing:
                    self.assertFalse(args.snapshot.parent.exists())


class SceneCapabilityFamilyMapTests(unittest.TestCase):
    def test_default_family_map_loads_without_structural_failures(self) -> None:
        family_map, failures = census.load_family_map(census.DEFAULT_FAMILY_MAP)
        self.assertEqual(failures, [])
        self.assertTrue(family_map["vocabulary"])
        self.assertTrue(family_map["rules"])

    def test_default_family_map_anchors_resolve_in_authority_docs(self) -> None:
        family_map, failures = census.load_family_map(census.DEFAULT_FAMILY_MAP)
        self.assertEqual(failures, [])
        self.assertEqual(
            census.family_map_anchor_failures(family_map, census.REPOSITORY_ROOT),
            [],
        )

    def test_apply_family_map_matches_rules_and_records_unknown(self) -> None:
        family_map = {
            "schema_version": 1,
            "vocabulary": {
                "cap.a.one": {"authority": {"doc": "d.md", "row": "r"}, "scope": "s"},
            },
            "rules": [
                {
                    "rule_id": "rule.a.k1",
                    "match": {"domain": "a", "kind": "k1"},
                    "capabilities": [{"capability": "cap.a.one", "profile": "p-coarse"}],
                },
                {
                    "rule_id": "rule.a.fallback",
                    "match": {"domain": "a"},
                    "unknown_reason": "fallback-unknown",
                },
            ],
            "family_overrides": {"a/k2@x": {"unknown_reason": "manual-unknown"}},
        }
        self.assertEqual(census._family_map_structural_failures(family_map), [])
        families = [
            {"family_key": "a/k1@x", "domain": "a", "kind": "k1", "occurrence_count": 2, "sample_count": 2, "sample_ids": ["s1", "s2"]},
            {"family_key": "a/k9@y", "domain": "a", "kind": "k9", "occurrence_count": 3, "sample_count": 2, "sample_ids": ["s2", "s3"]},
            {"family_key": "a/k2@x", "domain": "a", "kind": "k2", "occurrence_count": 1, "sample_count": 1, "sample_ids": ["s1"]},
        ]
        apply_failures: list[dict] = []
        stats = census._apply_family_map(families, family_map, apply_failures)
        self.assertEqual(apply_failures, [])
        self.assertEqual(families[0]["capability_state"], "mapped")
        self.assertEqual(families[0]["capability_refs"][0]["capability"], "cap.a.one")
        self.assertEqual(families[0]["capability_refs"][0]["rule_id"], "rule.a.k1")
        self.assertEqual(families[1]["capability_state"], "unknown")
        self.assertEqual(families[1]["capability_unknown_reason"], "fallback-unknown")
        self.assertEqual(families[2]["capability_unknown_reason"], "manual-unknown")
        self.assertEqual(stats["mapped_family_count"], 1)
        self.assertEqual(stats["unknown_family_count"], 2)
        self.assertEqual(stats["per_capability"]["cap.a.one"]["occurrence_count"], 2)
        self.assertEqual(stats["per_capability"]["cap.a.one"]["sample_count"], 2)

    def test_structural_failures_capture_undefined_capability_and_rule_order(self) -> None:
        bad = {
            "schema_version": 1,
            "vocabulary": {
                "cap.a.one": {"authority": {"doc": "d.md", "row": "r"}, "scope": "s"},
            },
            "rules": [
                {
                    "rule_id": "rule.bad.ref",
                    "match": {"domain": "a", "kind": "k"},
                    "capabilities": [{"capability": "cap.missing.x", "profile": "p"}],
                },
                {"rule_id": "rule.bad.none", "match": {"domain": "a"}},
                {"rule_id": "rule.fallback", "match": {"domain": "a"}, "unknown_reason": "fb"},
                {"rule_id": "rule.bad.order", "match": {"domain": "b"}, "unknown_reason": "fb"},
                {
                    "rule_id": "rule.bad.late-specific",
                    "match": {"domain": "b", "kind": "k"},
                    "capabilities": [{"capability": "cap.a.one", "profile": "p"}],
                },
                {"rule_id": "rule.bad.dup", "match": {"domain": "a"}, "unknown_reason": "fb"},
                {"rule_id": "rule.fallback", "match": {"domain": "c"}, "unknown_reason": "fb"},
            ],
            "family_overrides": {
                "a/bad@type": "bogus",
                "a/bad@outcome": {"profile": "p"},
                "a/bad@ref": {"capabilities": [{"capability": "cap.missing.x", "profile": "p"}]},
                "a/bad@empty-reason": {"unknown_reason": ""},
                "a/bad@capabilities-type": {"capabilities": "bogus"},
                "a/good@override": {"unknown_reason": "manual-unknown"},
            },
        }
        codes = {
            item["code"] for item in census._family_map_structural_failures(bad)
        }
        self.assertIn("family-map-undefined-capability", codes)
        self.assertIn("family-map-rule-outcome-required", codes)
        self.assertIn("family-map-fallback-before-specific", codes)
        self.assertIn("family-map-invalid-rule-id", codes)
        self.assertIn("family-map-invalid-override", codes)
        self.assertIn("family-map-override-outcome-required", codes)
        self.assertIn("family-map-invalid-capabilities-type", codes)

    def test_structural_failures_attribute_override_refs_with_clean_rules(self) -> None:
        clean_rules_map = {
            "schema_version": 1,
            "vocabulary": {
                "cap.a.one": {"authority": {"doc": "d.md", "row": "r"}, "scope": "s"},
            },
            "rules": [
                {
                    "rule_id": "rule.a.fallback",
                    "match": {"domain": "a"},
                    "unknown_reason": "fallback-unknown",
                },
            ],
            "family_overrides": {
                "a/good@x": {"capabilities": [{"capability": "cap.missing.x", "profile": "p"}]},
            },
        }
        failures = census._family_map_structural_failures(clean_rules_map)
        self.assertEqual(
            [failure["code"] for failure in failures],
            ["family-map-undefined-capability"],
        )
        self.assertEqual(failures[0].get("family_key"), "a/good@x")

    def test_apply_family_map_defends_against_malformed_override(self) -> None:
        family_map = {
            "schema_version": 1,
            "vocabulary": {},
            "rules": [],
            "family_overrides": {"a/k1@x": "bogus"},
        }
        families = [
            {"family_key": "a/k1@x", "domain": "a", "kind": "k1", "occurrence_count": 1, "sample_count": 1, "sample_ids": ["s1"]},
        ]
        apply_failures: list[dict] = []
        stats = census._apply_family_map(families, family_map, apply_failures)
        self.assertEqual(families[0]["capability_state"], "unknown")
        self.assertEqual(families[0]["capability_unknown_reason"], "family-map-invalid-override")
        self.assertIn(
            "family-map-invalid-override",
            {failure["code"] for failure in apply_failures},
        )
        self.assertEqual(stats["unknown_family_count"], 1)

    def test_anchor_failures_report_missing_row(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            doc = root / "ledger.md"
            doc.write_text("# row exists here\n", encoding="utf-8")
            family_map = {
                "vocabulary": {
                    "cap.ok.one": {
                        "authority": {"doc": "ledger.md", "row": "row exists"},
                        "scope": "s",
                    },
                    "cap.bad.one": {
                        "authority": {"doc": "ledger.md", "row": "not present"},
                        "scope": "s",
                    },
                },
            }
            failures = census.family_map_anchor_failures(family_map, root)
            self.assertEqual(len(failures), 1)
            self.assertEqual(failures[0]["capability"], "cap.bad.one")
            self.assertEqual(failures[0]["code"], "family-map-anchor-missing")


V2_LAYOUT_SAMPLE = "3782650329-d56d3d28-3f43-4796-bc3b-2bfe1a30452a"


class SceneSampleIdentityTests(unittest.TestCase):
    """A sample's identity is its library directory name in either installed layout."""

    def test_identity_accepts_both_installed_layouts_and_rejects_other_names(self) -> None:
        for accepted in (
            "1300076567",
            V2_LAYOUT_SAMPLE,
            V2_LAYOUT_SAMPLE.upper(),
        ):
            self.assertTrue(is_sample_directory_name(accepted), accepted)
        for rejected in (
            "not-a-sample",
            ".pending-0b1c2d3e-4f50-6071-8293-a4b5c6d7e8f9",
            "0b1c2d3e-4f50-6071-8293-a4b5c6d7e8f9",
            "2524111047-",
            "2524111047-not-a-uuid",
            "2524111047-28157b2b-2046-4f51-a12e-511483ea7bc",
            "2524111047-28157b2b-2046-4f51-a12e-511483ea7bcc-extra",
            "1300076567.txt",
            "",
        ):
            self.assertFalse(is_sample_directory_name(rejected), rejected)

    def test_identity_validation_accepts_a_sample_and_rejects_other_names(self) -> None:
        self.assertEqual(
            validated_sample_id(V2_LAYOUT_SAMPLE, context="fixture"),
            V2_LAYOUT_SAMPLE,
        )
        self.assertEqual(
            validated_sample_id("1300076567", context="fixture"), "1300076567"
        )
        with self.assertRaises(ValueError) as caught:
            validated_sample_id("not-a-sample", context="verdict key")
        self.assertIn("verdict key is not a sample id", str(caught.exception))

    def test_discovery_sees_both_layouts_and_skips_non_samples(self) -> None:
        with tempfile.TemporaryDirectory(prefix="mwx-scene-discovery-") as directory:
            root = Path(directory)
            for name in (
                "1300076567",
                V2_LAYOUT_SAMPLE,
                "not-a-sample",
                ".pending-0b1c2d3e-4f50-6071-8293-a4b5c6d7e8f9",
            ):
                (root / name).mkdir()
            (root / "shortcut").symlink_to(root / "1300076567")
            (root / "1300076568").write_text("file, not a directory", encoding="utf-8")
            discovered = [item.name for item in iter_sample_directories(root)]
            self.assertEqual(discovered, ["1300076567", V2_LAYOUT_SAMPLE])

    def test_census_discovers_a_current_layout_sample_as_its_directory_name(self) -> None:
        with tempfile.TemporaryDirectory(prefix="mwx-scene-census-v2-") as directory:
            root = Path(directory)
            samples, stock, matrix, ledger = make_fixture(root)
            (samples / "0000000001").rename(samples / V2_LAYOUT_SAMPLE)
            built = census.build_census(samples, stock, matrix, ledger)
            self.assertEqual(built["summary"]["discovered_sample_count"], 1)
            self.assertEqual(built["summary"]["parsed_sample_count"], 1)
            self.assertEqual(built["summary"]["added_since_matrix"], [V2_LAYOUT_SAMPLE])
            self.assertEqual(
                [row["sample_id"] for row in built["samples"]], [V2_LAYOUT_SAMPLE]
            )
            self.assertTrue(built["validation"]["conservation"]["occurrences_balanced"])


if __name__ == "__main__":
    unittest.main()
