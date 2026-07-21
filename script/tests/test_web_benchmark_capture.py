#!/usr/bin/env python3

from __future__ import annotations

import binascii
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


if __name__ == "__main__":
    unittest.main()
