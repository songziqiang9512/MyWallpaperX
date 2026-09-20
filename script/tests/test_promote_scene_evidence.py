import importlib.util
import json
import tempfile
import unittest
from pathlib import Path
from unittest import mock


SCRIPT = Path(__file__).resolve().parents[1] / "promote_scene_evidence.py"
SPEC = importlib.util.spec_from_file_location("promote_scene_evidence", SCRIPT)
assert SPEC is not None and SPEC.loader is not None
promotion = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(promotion)


class PromoteSceneEvidenceTests(unittest.TestCase):
    def make_report(self, root: Path, escaped: Path | None = None) -> Path:
        output = root / "output"
        result = output / "results/42"
        result.mkdir(parents=True)
        files = {
            "app_log": result / "app.log",
            "preview_log": result / "scene-preview.log",
            "runtime_evidence": result / "scene-runtime-evidence.json",
            "ready_snapshot": result / "scene-ready-window.png",
            "hover_snapshot": result / "scene-hover-window.png",
            "after_snapshot": result / "scene-after-window.png",
        }
        trajectory = [
            result / "scene-pointer-trajectory-00-window.png",
            result / "scene-pointer-trajectory-01-window.png",
        ]
        for key, path in files.items():
            path.write_bytes(key.encode("utf-8"))
        for index, path in enumerate(trajectory):
            path.write_bytes(f"trajectory-{index}".encode("utf-8"))
        report = {
            "samples": [{
                "id": "42",
                "runtime_sample": str(output / "runtime/runtime-samples/42"),
                "evidence": {
                    **{key: str(path) for key, path in files.items()},
                    "app_log_path": str(files["app_log"]),
                    "pointer_trajectory_snapshots": [
                        str(path) for path in trajectory
                    ],
                },
            }],
        }
        if escaped is not None:
            report["samples"][0]["evidence"]["app_log"] = str(escaped)
        report_path = output / "report.json"
        report_path.write_text(json.dumps(report), encoding="utf-8")
        return report_path

    def test_caches_only_bounded_evidence_and_preserves_report(self) -> None:
        with tempfile.TemporaryDirectory(prefix="mwx-evidence-promotion-") as directory:
            root = Path(directory)
            report = self.make_report(root)
            evidence_root = root / "repository-evidence"
            with mock.patch.object(promotion, "EVIDENCE_ROOT", evidence_root):
                destination = promotion.promote(
                    [("positive", report)],
                    Path("v1/test-package"),
                    max_package_mib=1,
                )

            archived_report = destination / "positive/report.json"
            self.assertEqual(archived_report.read_bytes(), report.read_bytes())
            self.assertFalse((destination / "positive/runtime").exists())
            manifest = json.loads((destination / "manifest.json").read_text())
            self.assertEqual(
                manifest["retention_class"],
                "local-ignored-evidence-cache",
            )
            self.assertEqual(len(manifest["runs"][0]["files"]), 8)
            self.assertEqual(
                manifest["runs"][0]["files"][4]["key"],
                "hover_snapshot",
            )
            self.assertEqual(
                [
                    item["key"]
                    for item in manifest["runs"][0]["files"]
                    if item["key"].startswith("pointer_trajectory_snapshot_")
                ],
                [
                    "pointer_trajectory_snapshot_00",
                    "pointer_trajectory_snapshot_01",
                ],
            )
            self.assertEqual(
                manifest["runs"][0]["report_sha256"],
                promotion.sha256(report),
            )

    def test_rejects_evidence_outside_benchmark_output(self) -> None:
        with tempfile.TemporaryDirectory(prefix="mwx-evidence-promotion-") as directory:
            root = Path(directory)
            escaped = root / "outside.log"
            escaped.write_text("outside")
            report = self.make_report(root, escaped=escaped)
            evidence_root = root / "repository-evidence"
            with mock.patch.object(promotion, "EVIDENCE_ROOT", evidence_root):
                with self.assertRaisesRegex(ValueError, "escapes benchmark output"):
                    promotion.promote(
                        [("negative", report)],
                        Path("v1/test-package"),
                        max_package_mib=1,
                    )

    def test_caches_product_entry_log_and_daemon_result_aliases(self) -> None:
        with tempfile.TemporaryDirectory(prefix="mwx-evidence-promotion-") as directory:
            root = Path(directory)
            output = root / "output"
            result = output / "results/42"
            result.mkdir(parents=True)
            app_log = result / "app.log"
            daemon_result = result / "scene-daemon-client-result.json"
            app_log.write_text("product entry", encoding="utf-8")
            daemon_result.write_text("{}", encoding="utf-8")
            report = output / "report.json"
            report.write_text(
                json.dumps({
                    "samples": [{
                        "id": "42",
                        "evidence": {
                            "app_log_path": str(app_log),
                            "daemon_client_result_path": str(daemon_result),
                        },
                    }],
                }),
                encoding="utf-8",
            )

            planned, total_bytes = promotion.promotion_plan([
                ("product-entry", report),
            ])

            self.assertEqual(
                [item["key"] for item in planned[0]["files"]],
                ["app_log_path", "daemon_client_result_path"],
            )
            self.assertEqual(
                total_bytes,
                report.stat().st_size + app_log.stat().st_size
                + daemon_result.stat().st_size,
            )

    def test_rejects_escaping_or_duplicate_sample_identities(self) -> None:
        malformed_ids = ("/tmp/escape", "../escape", "１２３", "sample-42")
        for sample_id in malformed_ids:
            with self.subTest(sample_id=sample_id), tempfile.TemporaryDirectory(
                prefix="mwx-evidence-promotion-"
            ) as directory:
                report = self.make_report(Path(directory))
                payload = json.loads(report.read_text(encoding="utf-8"))
                payload["samples"][0]["id"] = sample_id
                report.write_text(json.dumps(payload), encoding="utf-8")
                with self.assertRaisesRegex(
                    ValueError,
                    "sample evidence is malformed",
                ):
                    promotion.promotion_plan([("malformed", report)])

        with tempfile.TemporaryDirectory(
            prefix="mwx-evidence-promotion-"
        ) as directory:
            report = self.make_report(Path(directory))
            payload = json.loads(report.read_text(encoding="utf-8"))
            payload["samples"].append(payload["samples"][0])
            report.write_text(json.dumps(payload), encoding="utf-8")
            with self.assertRaisesRegex(ValueError, "duplicate sample identity"):
                promotion.promotion_plan([("duplicate", report)])

    def test_rejects_malformed_pointer_trajectory_evidence(self) -> None:
        malformed_values = (
            "scene-pointer-trajectory-00-window.png",
            {"0": "scene-pointer-trajectory-00-window.png"},
            2,
            ["scene-pointer-trajectory-00-window.png"],
            ["scene-pointer-trajectory-00-window.png", 2],
            ["scene-pointer-trajectory-00-window.png", ""],
            ["scene-pointer-trajectory-00-window.png"] * 9,
        )
        for value in malformed_values:
            with self.subTest(value=value):
                with tempfile.TemporaryDirectory(
                    prefix="mwx-evidence-promotion-"
                ) as directory:
                    report = self.make_report(Path(directory))
                    payload = json.loads(report.read_text(encoding="utf-8"))
                    payload["samples"][0]["evidence"][
                        "pointer_trajectory_snapshots"
                    ] = value
                    report.write_text(json.dumps(payload), encoding="utf-8")
                    with self.assertRaisesRegex(
                        ValueError,
                        "pointer trajectory evidence is malformed",
                    ):
                        promotion.promotion_plan([("malformed", report)])

    def test_allows_absent_none_or_empty_pointer_trajectory_evidence(self) -> None:
        for value in ("absent", None, []):
            with self.subTest(value=value):
                with tempfile.TemporaryDirectory(
                    prefix="mwx-evidence-promotion-"
                ) as directory:
                    report = self.make_report(Path(directory))
                    payload = json.loads(report.read_text(encoding="utf-8"))
                    if value == "absent":
                        del payload["samples"][0]["evidence"][
                            "pointer_trajectory_snapshots"
                        ]
                    else:
                        payload["samples"][0]["evidence"][
                            "pointer_trajectory_snapshots"
                        ] = value
                    report.write_text(json.dumps(payload), encoding="utf-8")
                    planned, _ = promotion.promotion_plan([("valid", report)])
                    self.assertFalse(any(
                        item["key"].startswith("pointer_trajectory_snapshot_")
                        for item in planned[0]["files"]
                    ))


if __name__ == "__main__":
    unittest.main()
