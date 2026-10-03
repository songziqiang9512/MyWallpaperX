import importlib.util
import json
import subprocess
import sys
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

    def test_retention_deletes_only_expired_unchanged_closed_packages(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory).resolve()
            report = self.make_report(root)
            with mock.patch.object(promotion, 'EVIDENCE_ROOT', root / 'evidence'):
                package = promotion.promote([('positive', report)], Path('run'), 1)
                manifest = json.loads((package / 'manifest.json').read_text())
                with mock.patch.object(promotion.subprocess, 'run') as proc:
                    proc.return_value.returncode = 1
                    proc.return_value.stdout = b''
                    proc.return_value.stderr = b''
                    self.assertEqual(promotion.prune_expired(manifest['expires_at'] - 1)['removed'], [])
                    self.assertEqual(promotion.prune_expired(manifest['expires_at'] + 1)['removed'], [str(package)])
                self.assertFalse(package.exists())
                self.assertTrue(report.exists())

    def test_retention_preserves_modified_unknown_active_and_protected_evidence(self):
        for kind in ('modified', 'unknown', 'active', 'protected', 'symlink', 'uncertain'):
            with self.subTest(kind=kind), tempfile.TemporaryDirectory() as directory:
                root = Path(directory).resolve()
                report = self.make_report(root)
                with mock.patch.object(promotion, 'EVIDENCE_ROOT', root / 'evidence'):
                    package = promotion.promote([('positive', report)], Path('run'), 1,
                                                protect_reason='unresolved GPU failure' if kind == 'protected' else '')
                    if kind == 'modified':
                        (package / 'positive/report.json').write_text('changed')
                    elif kind == 'unknown':
                        (package / 'new-failure.log').write_text('unique')
                    elif kind == 'symlink':
                        (package / 'external').symlink_to(report)
                    with mock.patch.object(promotion.subprocess, 'run') as proc:
                        proc.return_value.returncode = 0 if kind == 'active' else 1
                        proc.return_value.stdout = b'123' if kind == 'active' else b''
                        proc.return_value.stderr = b'permission denied' if kind == 'uncertain' else b''
                        result = promotion.prune_expired(promotion.time.time() + 100 * 86400)
                    self.assertEqual(result['removed'], [])
                    self.assertTrue(package.exists())
                    self.assertTrue(report.exists())

    def test_nonobject_manifests_are_retained_without_interrupting_other_packages(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory).resolve()
            report = self.make_report(root)
            evidence = root / 'evidence'
            with mock.patch.object(promotion, 'EVIDENCE_ROOT', evidence):
                before = promotion.promote([('positive', report)], Path('00-expired'), 1)
                after = promotion.promote([('positive', report)], Path('99-expired'), 1)
                unknown = []
                for index, value in enumerate(([], None, 3, 'unknown')):
                    package = evidence / f'10-unknown-{index}'
                    package.mkdir()
                    manifest = package / 'manifest.json'
                    manifest.write_text(json.dumps(value))
                    unknown.append((manifest, manifest.read_bytes()))
                with mock.patch.object(promotion.subprocess, 'run') as proc:
                    proc.return_value.returncode = 1
                    proc.return_value.stdout = proc.return_value.stderr = b''
                    result = promotion.prune_expired(promotion.time.time() + 100 * 86400)
                self.assertEqual(result['removed'], [str(before), str(after)])
                self.assertEqual({item['path'] for item in result['retained']},
                                 {str(path.parent) for path, _ in unknown})
                for path, data in unknown:
                    self.assertEqual(path.read_bytes(), data)
                self.assertTrue(all('expected an object' in item['reason']
                                    for item in result['retained']))

    def test_destination_cannot_name_cache_root_and_concurrent_producers_are_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory).resolve()
            with mock.patch.object(promotion, 'EVIDENCE_ROOT', root / 'evidence'):
                for path in (Path('.'), Path('fresh/..'), Path('../escape')):
                    with self.assertRaises(ValueError):
                        promotion.destination_path(path)
                with promotion.evidence_lock():
                    with self.assertRaises(BlockingIOError):
                        with promotion.evidence_lock():
                            self.fail('a second producer entered the critical section')

    def test_root_and_ancestor_symlinks_never_redirect_promotion_or_pruning(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory).resolve()
            outside = root / 'outside'
            outside.mkdir()
            link = root / 'link'
            link.symlink_to(outside, target_is_directory=True)
            for evidence in (link, link / 'runs'):
                with mock.patch.object(promotion, 'EVIDENCE_ROOT', evidence):
                    with self.assertRaisesRegex(ValueError, 'symlink'):
                        promotion.destination_path(Path('new'))
                    result = promotion.prune_expired()
                    self.assertEqual(result['removed'], [])
                    self.assertEqual(len(result['retained']), 1)
            self.assertTrue(outside.exists())

    def test_actual_copy_growth_is_rejected_and_temporary_output_removed(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory).resolve()
            report = self.make_report(root)
            original = promotion.shutil.copyfile
            def growing_copy(source, target):
                result = original(source, target)
                with Path(target).open('ab') as output:
                    output.write(b'x' * (1024 * 1024))
                return result
            with mock.patch.object(promotion, 'EVIDENCE_ROOT', root / 'evidence'):
                with mock.patch.object(promotion.shutil, 'copyfile', side_effect=growing_copy):
                    with self.assertRaisesRegex(ValueError, 'including manifest'):
                        promotion.promote([('positive', report)], Path('run'), 1)
                self.assertEqual(list((root / 'evidence').iterdir()), [])

    def test_aggregate_cache_budget_prevents_unbounded_package_growth(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory).resolve()
            report = self.make_report(root)
            with mock.patch.object(promotion, 'EVIDENCE_ROOT', root / 'evidence'):
                (root / 'evidence').mkdir()
                (root / 'evidence/existing.bin').write_bytes(b'x' * (1024 * 1024))
                with self.assertRaisesRegex(ValueError, 'cache budget'):
                    promotion.promote([('positive', report)], Path('run'), 1, max_cache_mib=1)
                self.assertFalse((root / 'evidence/run').exists())

    def test_manifest_bytes_count_at_both_exact_budget_boundaries(self):
        for budget in ('package', 'cache'):
            with self.subTest(budget=budget), tempfile.TemporaryDirectory() as directory:
                root = Path(directory).resolve()
                report = self.make_report(root)
                evidence = root / 'evidence'
                evidence.mkdir()
                _, payload_bytes = promotion.promotion_plan([('positive', report)])
                padding = 1024 * 1024 - payload_bytes
                if budget == 'package':
                    source = report.parent / 'results/42/app.log'
                    source.write_bytes(source.read_bytes() + b'x' * padding)
                else:
                    source = evidence / 'unknown-evidence.bin'
                    source.write_bytes(b'x' * padding)
                before = source.read_bytes()
                with mock.patch.object(promotion, 'EVIDENCE_ROOT', evidence):
                    with self.assertRaisesRegex(ValueError, 'including manifest'):
                        promotion.promote([('positive', report)], Path('run'),
                                          1 if budget == 'package' else 2,
                                          max_cache_mib=1 if budget == 'cache' else 2)
                    # A failed transaction releases its lock for the next operation.
                    with promotion.evidence_lock():
                        pass
                self.assertEqual(source.read_bytes(), before)
                self.assertEqual(set(evidence.iterdir()),
                                 {source} if budget == 'cache' else set())

    def test_cross_process_lock_blocks_both_mutators_until_released(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory).resolve()
            report = self.make_report(root)
            evidence = root / 'evidence'
            lock = root / '.evidence-retention.lock'
            holder = subprocess.Popen(
                [sys.executable, '-B', '-c',
                 'import fcntl, sys\n'
                 'with open(sys.argv[1], "a") as lock:\n'
                 ' fcntl.flock(lock, fcntl.LOCK_EX)\n'
                 ' print("locked", flush=True)\n'
                 ' sys.stdin.readline()\n', str(lock)],
                stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                text=True,
            )
            try:
                self.assertEqual(holder.stdout.readline().strip(), 'locked')
                with mock.patch.object(promotion, 'EVIDENCE_ROOT', evidence):
                    with self.assertRaises(BlockingIOError):
                        promotion.promote([('positive', report)], Path('run'), 1)
                    retained = promotion.prune_expired()
                    self.assertEqual(retained['removed'], [])
                    self.assertEqual(len(retained['retained']), 1)
                    self.assertFalse(evidence.exists())
                    holder.communicate('\n', timeout=10)
                    self.assertEqual(holder.returncode, 0)
                    self.assertTrue(promotion.promote(
                        [('positive', report)], Path('run'), 1).exists())
            finally:
                if holder.poll() is None:
                    holder.kill()
                holder.communicate()

    def test_lock_symlink_never_opens_or_changes_its_target(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory).resolve()
            report = self.make_report(root)
            sentinel = root / 'unknown-data'
            sentinel.write_bytes(b'unique evidence')
            (root / '.evidence-retention.lock').symlink_to(sentinel)
            with mock.patch.object(promotion, 'EVIDENCE_ROOT', root / 'evidence'):
                with self.assertRaises(OSError):
                    promotion.promote([('positive', report)], Path('run'), 1)
                self.assertEqual(promotion.prune_expired()['removed'], [])
            self.assertEqual(sentinel.read_bytes(), b'unique evidence')
            self.assertFalse((root / 'evidence').exists())

    def test_root_manifest_and_archive_are_never_removable_packages(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory).resolve()
            report = self.make_report(root)
            evidence = root / 'runs'
            archive = root / 'archive'
            archive.mkdir()
            archived = archive / 'unique-failure.log'
            archived.write_bytes(b'legacy unknown evidence')
            with mock.patch.object(promotion, 'EVIDENCE_ROOT', evidence):
                package = promotion.promote([('positive', report)], Path('run'), 1)
                # Even producer-shaped metadata cannot turn the cache root into a package.
                (evidence / 'manifest.json').write_text(json.dumps({
                    'producer': 'promote_scene_evidence', 'expires_at': 1, 'runs': [],
                }))
                with mock.patch.object(promotion.subprocess, 'run') as proc:
                    proc.return_value.returncode = 1
                    proc.return_value.stdout = proc.return_value.stderr = b''
                    result = promotion.prune_expired(promotion.time.time() + 100 * 86400)
                self.assertEqual(result['removed'], [str(package)])
                self.assertEqual(len(result['retained']), 1)
                self.assertTrue((evidence / 'manifest.json').exists())
                self.assertEqual(archived.read_bytes(), b'legacy unknown evidence')

    def test_caches_only_bounded_evidence_and_preserves_report(self) -> None:
        with tempfile.TemporaryDirectory(prefix="mwx-evidence-promotion-") as directory:
            root = Path(directory).resolve()
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
            root = Path(directory).resolve()
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
            root = Path(directory).resolve()
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

    def test_accepts_the_current_install_layout_sample_identity(self) -> None:
        """A `<workshopId>-<uuid>` identity is a sample id, not a malformed one."""
        sample_id = "3803482159-d8652063-b9f0-4a8a-8d37-7432dc242f3f"
        with tempfile.TemporaryDirectory(
            prefix="mwx-evidence-promotion-"
        ) as directory:
            report = self.make_report(Path(directory))
            payload = json.loads(report.read_text(encoding="utf-8"))
            payload["samples"][0]["id"] = sample_id
            report.write_text(json.dumps(payload), encoding="utf-8")
            planned, _ = promotion.promotion_plan([("current", report)])
            self.assertEqual(planned[0]["label"], "current")
            self.assertEqual(
                [item["key"] for item in planned[0]["files"]][0], "app_log"
            )

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
