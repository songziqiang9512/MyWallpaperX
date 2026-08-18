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
            "after_snapshot": result / "scene-after-window.png",
        }
        for key, path in files.items():
            path.write_bytes(key.encode("utf-8"))
        report = {
            "samples": [{
                "id": "42",
                "runtime_sample": str(output / "runtime/runtime-samples/42"),
                "evidence": {
                    key: str(path) for key, path in files.items()
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
            self.assertEqual(len(manifest["runs"][0]["files"]), 5)
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


if __name__ == "__main__":
    unittest.main()
