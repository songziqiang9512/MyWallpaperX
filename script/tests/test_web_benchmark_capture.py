#!/usr/bin/env python3

from __future__ import annotations

import binascii
import hashlib
import plistlib
import shutil
import struct
import sys
import tempfile
import unittest
import zlib
from pathlib import Path
from unittest import mock

SCRIPT_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SCRIPT_DIR))

import web_benchmark_capture as capture


def write_rgb_png(path: Path, red: int, green: int, blue: int) -> None:
    def chunk(kind: bytes, payload: bytes) -> bytes:
        body = kind + payload
        return struct.pack(">I", len(payload)) + body + struct.pack(">I", binascii.crc32(body))

    header = struct.pack(">IIBBBBB", 1, 1, 8, 2, 0, 0, 0)
    pixels = zlib.compress(bytes((0, red, green, blue)))
    path.write_bytes(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", header) + chunk(b"IDAT", pixels) + chunk(b"IEND", b""))


class WebBenchmarkCaptureTests(unittest.TestCase):
    def test_output_directory_must_be_fresh(self) -> None:
        with tempfile.TemporaryDirectory(prefix="mwx-capture-output-") as directory:
            output = Path(directory) / "report"
            self.assertEqual(capture.require_fresh_output_dir(output), output)
            (output / "stale.txt").write_text("stale", encoding="utf-8")
            with self.assertRaises(FileExistsError):
                capture.require_fresh_output_dir(output)
            file_path = Path(directory) / "file.txt"
            file_path.write_text("not a directory", encoding="utf-8")
            with self.assertRaises(FileExistsError):
                capture.require_fresh_output_dir(file_path)

    def test_logged_snapshot_paths_reject_unlogged_and_outside_files(self) -> None:
        with tempfile.TemporaryDirectory(prefix="mwx-capture-paths-") as directory:
            root = Path(directory)
            sample_dir = root / "sample"
            sample_dir.mkdir()
            accepted = sample_dir / "web-snapshot-1-ready-window.png"
            unlogged = sample_dir / "web-snapshot-1-stale.png"
            outside = root / "outside.png"
            for path in (accepted, unlogged, outside):
                path.write_bytes(b"png")
            metadata = {
                "snapshots": [
                    {"path": str(accepted)},
                    {"path": str(outside)},
                    {"path": str(sample_dir / "missing.png")},
                ]
            }
            self.assertEqual(capture.logged_snapshot_paths(metadata, sample_dir), [accepted.resolve()])
            self.assertTrue(capture.has_window_snapshot([accepted]))
            self.assertFalse(capture.has_window_snapshot([unlogged]))

    def test_png_non_black_check_distinguishes_black_and_visible_pixels(self) -> None:
        with tempfile.TemporaryDirectory(prefix="mwx-capture-png-") as directory:
            root = Path(directory)
            black = root / "black.png"
            visible = root / "visible.png"
            write_rgb_png(black, 0, 0, 0)
            write_rgb_png(visible, 0, 8, 0)
            self.assertFalse(capture.png_has_non_black_pixel(black))
            self.assertTrue(capture.png_has_non_black_pixel(visible))

    def test_16_bit_png_filters_and_visibility_use_full_pixel_stride(self) -> None:
        def chunk(kind, payload):
            body = kind + payload
            return struct.pack(">I", len(payload)) + body + struct.pack(">I", binascii.crc32(body))
        with tempfile.TemporaryDirectory(prefix="mwx-capture-16bit-") as directory:
            for filter_type in range(5):
                path = Path(directory) / f"filter-{filter_type}.png"
                raw = struct.pack(">8H", 0, 0, 0, 65535, 0, 8192, 16384, 65535)
                previous = bytes(len(raw))
                rows = []
                for row in (raw, raw):
                    filtered = bytearray()
                    for i, value in enumerate(row):
                        left = row[i - 8] if i >= 8 else 0
                        up = previous[i]
                        upper_left = previous[i - 8] if i >= 8 else 0
                        predictor = (0, left, up, (left + up) // 2,
                                     capture._paeth(left, up, upper_left))[filter_type]
                        filtered.append((value - predictor) & 255)
                    rows.append(bytes([filter_type]) + filtered)
                    previous = row
                header = struct.pack(">IIBBBBB", 2, 2, 16, 6, 0, 0, 0)
                path.write_bytes(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", header)
                                 + chunk(b"IDAT", zlib.compress(b"".join(rows))) + chunk(b"IEND", b""))
                self.assertTrue(capture.png_has_non_black_pixel(path))
                self.assertEqual(capture.png_rgb_pixels(path),
                                 (2, 2, [bytes([0, 0, 0, 0, 32, 64])] * 2))
                self.assertEqual(capture.png_motion_metrics(path, path)["mean_delta"], 0)

    def test_png_flat_border_ratio_detects_uniform_frame(self) -> None:
        with tempfile.TemporaryDirectory(prefix="mwx-capture-border-") as directory:
            flat = Path(directory) / "flat.png"
            write_rgb_png(flat, 128, 128, 128)
            self.assertEqual(capture.png_flat_border_ratio(flat), 1.0)

    def test_png_motion_metrics_distinguish_identical_and_changed_pixels(self) -> None:
        with tempfile.TemporaryDirectory(prefix="mwx-capture-motion-") as directory:
            root = Path(directory)
            first = root / "first.png"
            same = root / "same.png"
            changed = root / "changed.png"
            write_rgb_png(first, 8, 16, 32)
            write_rgb_png(same, 8, 16, 32)
            write_rgb_png(changed, 64, 16, 32)

            same_metrics = capture.png_motion_metrics(first, same)
            changed_metrics = capture.png_motion_metrics(first, changed)
            self.assertEqual(same_metrics, {"mean_delta": 0.0, "changed_ratio": 0.0})
            self.assertIsNotNone(changed_metrics)
            self.assertGreater(changed_metrics["mean_delta"], 0)
            self.assertEqual(changed_metrics["changed_ratio"], 1.0)

    def test_motion_roi_excludes_unrelated_pixels_and_rejects_empty_regions(self):
        first = (2, 1, 3, 3, [bytes([0, 0, 0, 0, 0, 0])])
        second = (2, 1, 3, 3, [bytes([255, 255, 255, 0, 0, 0])])
        def measure(region):
            with mock.patch.object(capture, "_decode_png_rows", side_effect=[first, second]):
                return capture.png_motion_metrics(Path("first"), Path("second"), region=region)
        self.assertEqual(measure(None)["changed_ratio"], .5)
        self.assertEqual(measure((0, 0, .5, 1))["changed_ratio"], 1)
        self.assertEqual(measure((.5, 0, 1, 1)), {"mean_delta": 0, "changed_ratio": 0})
        for region in [(-1, 0, 1, 1), (0, 0, 0, 1), (0, 0, .1, 1), (0, 0, float("nan"), 1)]:
            with self.assertRaises(ValueError):
                measure(region)

    @mock.patch.object(capture, "_identity_values")
    @mock.patch.object(capture, "_verify_signature")
    @mock.patch.object(capture, "_ditto_copy")
    def test_stage_and_verify_signed_app_identity(
        self,
        copy_app: mock.Mock,
        verify_signature: mock.Mock,
        identity_values: mock.Mock,
    ) -> None:
        with tempfile.TemporaryDirectory(prefix="mwx-capture-app-") as directory:
            root = Path(directory)
            source_bundle = root / "Source.app"
            source_binary = source_bundle / "Contents/MacOS/MyWallpaperX"
            source_binary.parent.mkdir(parents=True)
            source_binary.write_bytes(b"binary")
            output = root / "output"
            output.mkdir()

            copy_app.side_effect = lambda source, destination: shutil.copytree(source, destination)
            identity_values.return_value = {
                "bundle_identifier": "com.songziqiang.MyWallpaperX",
                "team_identifier": "H9QWU9XN8R",
                "cdhash": "abc123",
                "short_version": "2.0.6",
                "bundle_version": "1",
                "executable_sha256": "def456",
            }

            runtime_binary, identity = capture.stage_signed_app(source_binary, output)
            self.assertTrue(runtime_binary.is_file())
            self.assertEqual(Path(identity["runtime_bundle_path"]).name, source_bundle.name)
            self.assertTrue(identity["verified_before"])
            self.assertIsNone(identity["verified_after"])

            capture.verify_staged_app(identity)
            self.assertTrue(identity["verified_after"])
            self.assertEqual(verify_signature.call_count, 3)

            changed = dict(identity_values.return_value)
            changed["cdhash"] = "changed"
            identity_values.return_value = changed
            with self.assertRaises(capture.AppIdentityError):
                capture.verify_staged_app(identity)
            self.assertFalse(identity["verified_after"])

            identity_values.return_value = changed
            capture.discard_staged_app(identity)
            self.assertFalse(runtime_binary.exists())
            self.assertFalse(identity["runtime_retained"])
            self.assertIsNone(identity["runtime_root_path"])
            self.assertIsNone(identity["runtime_bundle_path"])
            self.assertIsNone(identity["runtime_executable_path"])

    @mock.patch.object(capture, "_codesign_values")
    @mock.patch.object(capture, "_verify_signature")
    @mock.patch.object(capture, "_ditto_copy")
    def test_canonical_runtime_basename_preserves_distinct_signed_sources(
        self,
        copy_app: mock.Mock,
        verify_signature: mock.Mock,
        codesign_values: mock.Mock,
    ) -> None:
        with tempfile.TemporaryDirectory(prefix="mwx-capture-canonical-") as directory:
            root = Path(directory).resolve()
            output = root / "output"
            output.mkdir()
            copy_app.side_effect = lambda source, destination: shutil.copytree(source, destination)
            codesign_values.return_value = {
                "bundle_identifier": "com.songziqiang.MyWallpaperX.Debug.Startup",
                "team_identifier": "H9QWU9XN8R",
                "cdhash": "same-code-identity",
            }
            runtime_roots = []
            for basename in ("Baseline-copy.app", "Candidate-signed.app"):
                with self.subTest(source=basename):
                    source_bundle = root / basename
                    source_binary = source_bundle / "Contents/MacOS/MyWallpaperX"
                    source_binary.parent.mkdir(parents=True)
                    source_binary.write_bytes(b"unchanged executable bytes")
                    (source_bundle / "Contents/Info.plist").write_bytes(plistlib.dumps({
                        "CFBundleIdentifier": "com.songziqiang.MyWallpaperX.Debug.Startup",
                        "CFBundleExecutable": "MyWallpaperX",
                        "CFBundleShortVersionString": "2.11.0",
                        "CFBundleVersion": "283",
                    }))
                    source_files = {path.relative_to(source_bundle): path.read_bytes()
                                    for path in source_bundle.rglob("*") if path.is_file()}
                    runtime_binary, identity = capture.stage_signed_app(
                        source_binary, output, runtime_bundle_name="MyWallpaperX.app")
                    runtime_bundle = Path(identity["runtime_bundle_path"])
                    runtime_root = Path(identity["runtime_root_path"])
                    runtime_roots.append(runtime_root)
                    self.assertEqual(runtime_bundle.name, "MyWallpaperX.app")
                    self.assertEqual(runtime_bundle.parent, runtime_root)
                    self.assertEqual(runtime_binary.relative_to(runtime_bundle),
                                     source_binary.relative_to(source_bundle))
                    self.assertEqual(Path(identity["source_bundle_path"]), source_bundle)
                    self.assertEqual(Path(identity["source_executable_path"]), source_binary)
                    self.assertEqual({path.relative_to(runtime_bundle): path.read_bytes()
                                      for path in runtime_bundle.rglob("*") if path.is_file()}, source_files)
                    self.assertEqual(identity["executable_sha256"],
                                     hashlib.sha256(source_binary.read_bytes()).hexdigest())
                    copy_app.assert_any_call(source_bundle, runtime_bundle)
                    capture.verify_staged_app(identity)
                    self.assertTrue(identity["verified_after"])
                    capture.discard_staged_app(identity)
                    self.assertFalse(runtime_root.exists())
                    self.assertFalse(identity["runtime_retained"])
                    self.assertEqual({path.relative_to(source_bundle): path.read_bytes()
                                      for path in source_bundle.rglob("*") if path.is_file()}, source_files)
            self.assertEqual(len(set(runtime_roots)), 2)
            self.assertEqual(verify_signature.call_count, 6)

    @mock.patch.object(capture, "_identity_values", return_value={})
    @mock.patch.object(capture, "_verify_signature")
    @mock.patch.object(capture, "_ditto_copy")
    def test_explicit_runtime_basename_rejects_non_leaf_before_copy(
        self,
        copy_app: mock.Mock,
        _verify_signature: mock.Mock,
        _identity_values: mock.Mock,
    ) -> None:
        with tempfile.TemporaryDirectory(prefix="mwx-capture-invalid-name-") as directory:
            root = Path(directory).resolve()
            source_binary = root / "Source.app/Contents/MacOS/MyWallpaperX"
            source_binary.parent.mkdir(parents=True)
            source_binary.write_bytes(b"unchanged source")
            output = root / "output"
            output.mkdir()
            for basename in ("", ".", "..", "../Escape.app", "nested/MyWallpaperX.app",
                             str(root / "Absolute.app")):
                with self.subTest(basename=basename):
                    with self.assertRaises(capture.AppIdentityError):
                        capture.stage_signed_app(source_binary, output, runtime_bundle_name=basename)
                    copy_app.assert_not_called()
                    self.assertEqual(list(output.iterdir()), [])
                    self.assertEqual(source_binary.read_bytes(), b"unchanged source")

    def test_discard_staged_app_rejects_paths_outside_runtime_root(self) -> None:
        with tempfile.TemporaryDirectory(prefix="mwx-capture-cleanup-") as directory:
            root = Path(directory)
            runtime_root = root / "runtime-app-fixture"
            runtime_root.mkdir()
            outside_bundle = root / "Outside.app"
            outside_binary = outside_bundle / "Contents/MacOS/MyWallpaperX"
            outside_binary.parent.mkdir(parents=True)
            outside_binary.write_bytes(b"binary")
            identity = {
                "runtime_root_path": str(runtime_root),
                "runtime_bundle_path": str(outside_bundle),
                "runtime_executable_path": str(outside_binary),
            }

            with self.assertRaises(capture.AppIdentityError):
                capture.discard_staged_app(identity)
            self.assertTrue(runtime_root.is_dir())


if __name__ == "__main__":
    unittest.main()
