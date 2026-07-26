#!/usr/bin/env python3

"""Contract tests for the restricted MDLV0023/MDLA0006 rotation IR reader."""

from __future__ import annotations

import json
import math
import shutil
import struct
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SCRIPT_DIR))

from scene_real_test_fixtures import runtime_homes_root


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
SCENE_ROOT = REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene"
SWIFT_SOURCE = SCENE_ROOT / "Format/SceneMdlPuppetAnimationReader.swift"
SWIFT_MODEL_SOURCE = SCENE_ROOT / "Format/SceneMdlPuppetAnimation.swift"
REAL_ASSET_ROOT = runtime_homes_root()

HARNESS = r'''
import Foundation

@main
enum Harness {
    static func main() throws {
        var results: [[String: Any]] = []
        for path in CommandLine.arguments.dropFirst() {
            let data = try Data(contentsOf: URL(fileURLWithPath: path))
            var entry: [String: Any] = ["file": (path as NSString).lastPathComponent]
            do {
                guard let set = try SceneMdlPuppetAnimationReader.read(data: data) else {
                    entry["ok"] = true
                    entry["absent"] = true
                    results.append(entry)
                    continue
                }
                entry["ok"] = true
                entry["boneCount"] = set.boneCount
                entry["animations"] = set.animations.map { animation in
                    [
                        "id": animation.id,
                        "name": animation.name,
                        "mode": animation.mode,
                        "fps": Double(animation.framesPerSecond),
                        "frameCount": animation.frameCount,
                        "duration": Double(animation.durationSeconds),
                        "trackCount": animation.transformsByBone.count,
                        "sampleCounts": animation.transformsByBone.map(\.count),
                        "firstTransform": animation.transformsByBone.first?.first.map {
                            [
                                Double($0.translation.x), Double($0.translation.y),
                                Double($0.translation.z), Double($0.rotation.x),
                                Double($0.rotation.y), Double($0.rotation.z),
                                Double($0.scale.x), Double($0.scale.y), Double($0.scale.z),
                            ]
                        } ?? [],
                        "lastTransform": animation.transformsByBone.first?.last.map {
                            [
                                Double($0.translation.x), Double($0.translation.y),
                                Double($0.translation.z), Double($0.rotation.x),
                                Double($0.rotation.y), Double($0.rotation.z),
                                Double($0.scale.x), Double($0.scale.y), Double($0.scale.z),
                            ]
                        } ?? [],
                    ] as [String: Any]
                }
            } catch let error as SceneMdlPuppetAnimationReadError {
                entry["ok"] = false
                entry["error"] = error.description
            }
            results.append(entry)
        }
        let payload = try JSONSerialization.data(withJSONObject: results)
        FileHandle.standardOutput.write(payload)
    }
}
'''


def transform(frame: int, bone: int, nan_component: bool = False) -> tuple[float, ...]:
    rotation_x = float("nan") if nan_component else frame * 0.1
    return (
        bone * 10.0,
        frame * 2.0,
        0.0,
        rotation_x,
        bone * 0.01,
        frame * -0.02,
        1.0,
        1.0,
        1.0,
    )


def animation_record(
    animation_id: int,
    name: str,
    frame_count: int,
    bone_count: int,
    *,
    fps: float = 30.0,
    mode: str = "loop",
    header_state: int = 0,
    transform_state: int = 0,
    declared_bones: int | None = None,
    bad_track_bytes: bool = False,
    nan_transform: bool = False,
    auxiliary: bool = False,
    bad_auxiliary_key: bool = False,
) -> bytes:
    body = bytearray(struct.pack("<II", animation_id, header_state))
    body += name.encode() + b"\0"
    body += mode.encode() + b"\0"
    body += struct.pack(
        "<fIII",
        fps,
        frame_count,
        transform_state,
        bone_count if declared_bones is None else declared_bones,
    )
    sample_count = frame_count + 1
    expected_bytes = sample_count * 36
    for bone in range(bone_count):
        byte_count = expected_bytes - 4 if bad_track_bytes and bone == 0 else expected_bytes
        body += struct.pack("<II", 0, byte_count)
        samples = bytearray()
        for frame in range(sample_count):
            samples += struct.pack(
                "<9f",
                *transform(frame, bone, nan_component=nan_transform and frame == 1 and bone == 0),
            )
        body += samples[:byte_count]
    body += b"\0" * 5
    if auxiliary:
        values = [index / frame_count for index in range(sample_count)]
        key = 0xDEADBEEF if bad_auxiliary_key else 0x418A55D5
        body += b"\1" + struct.pack("<IIII", 1, key, 1, sample_count * 4)
        body += struct.pack(f"<{sample_count}f", *values)
    else:
        body += b"\0"
    body += b"\0" * 29
    return bytes(body)


def build_mdl(
    animations: list[bytes] | None = None,
    *,
    magic: bytes = b"MDLV0023",
    bone_count: int = 2,
    include_attachment_boundary: bool = False,
    animation_marker: bytes = b"MDLA0006\0",
    declared_animation_count: int | None = None,
    corrupt_end_offset: bool = False,
) -> bytes:
    if animations is None:
        animations = [animation_record(101, "Idle", 2, bone_count)]
    prefix = bytearray(magic + b"\0" + b"\0" * 24)
    mdls_offset = len(prefix)
    mdls = bytearray(b"MDLS0004\0" + b"\0" * 4 + struct.pack("<I", bone_count))
    mdat = bytearray(b"MDAT0001\0" + b"\0" * 4) if include_attachment_boundary else bytearray()
    mdla_offset = len(prefix) + len(mdls) + len(mdat)
    struct.pack_into("<I", mdls, 9, len(prefix) + len(mdls) if mdat else mdla_offset)
    if mdat:
        struct.pack_into("<I", mdat, 9, mdla_offset)
    count = len(animations) if declared_animation_count is None else declared_animation_count
    mdla = bytearray(animation_marker + b"\0" * 4 + struct.pack("<I", count))
    mdla += b"".join(animations)
    end_offset = mdla_offset + len(mdla) + (1 if corrupt_end_offset else 0)
    struct.pack_into("<I", mdla, 9, end_offset)
    return bytes(prefix + mdls + mdat + mdla)


class SceneMdlPuppetAnimationReaderTests(unittest.TestCase):
    maxDiff = None

    @classmethod
    def setUpClass(cls):
        if shutil.which("swiftc") is None:
            raise unittest.SkipTest("swiftc is unavailable")
        cls._tmp = tempfile.TemporaryDirectory()
        tmp = Path(cls._tmp.name)
        harness = tmp / "harness.swift"
        harness.write_text(HARNESS)
        cls.binary = tmp / "harness"
        compilation = subprocess.run(
            [
                "swiftc",
                str(SWIFT_MODEL_SOURCE),
                str(SWIFT_SOURCE),
                str(harness),
                "-o",
                str(cls.binary),
            ],
            capture_output=True,
            text=True,
        )
        if compilation.returncode != 0:
            raise AssertionError(f"harness compilation failed:\n{compilation.stderr}")

        valid_animations = [
            animation_record(101, "Idle", 2, 2),
            animation_record(202, "Blink", 3, 2, fps=60, auxiliary=True),
        ]
        cls.fixtures = {
            "valid.mdl": build_mdl(valid_animations, include_attachment_boundary=True),
            "absent.mdl": b"MDLV0023\0" + b"\0" * 32,
            "old-version.mdl": build_mdl(magic=b"MDLV0016"),
            "bad-end.mdl": build_mdl(corrupt_end_offset=True),
            "zero-count.mdl": build_mdl(declared_animation_count=0),
            "duplicate-id.mdl": build_mdl(
                [animation_record(101, "One", 2, 2), animation_record(101, "Two", 2, 2)]
            ),
            "bone-mismatch.mdl": build_mdl(
                [animation_record(101, "Idle", 2, 2, declared_bones=3)]
            ),
            "bad-track-bytes.mdl": build_mdl(
                [animation_record(101, "Idle", 2, 2, bad_track_bytes=True)]
            ),
            "nan-transform.mdl": build_mdl(
                [animation_record(101, "Idle", 2, 2, nan_transform=True)]
            ),
            "bad-auxiliary.mdl": build_mdl(
                [animation_record(101, "Idle", 2, 2, auxiliary=True, bad_auxiliary_key=True)]
            ),
            "unsupported-mode.mdl": build_mdl(
                [animation_record(101, "Idle", 2, 2, mode="mirror")]
            ),
        }
        for name, blob in cls.fixtures.items():
            (tmp / name).write_bytes(blob)

        cls.real_assets = []
        patterns = [
            "3769688830/**/models/spiritblossomahribase_puppet.mdl",
            "3747492842/**/models/身体_puppet.mdl",
            "3768229922/**/models/人物_puppet.mdl",
        ]
        for pattern in patterns:
            cls.real_assets.extend(REAL_ASSET_ROOT.glob(pattern))
        paths = [tmp / name for name in cls.fixtures]
        paths += cls.real_assets
        completed = subprocess.run(
            [str(cls.binary), *map(str, paths)],
            capture_output=True,
            text=True,
        )
        if completed.returncode != 0:
            raise AssertionError(f"harness run failed:\n{completed.stderr}")
        cls.results = {entry["file"]: entry for entry in json.loads(completed.stdout)}

    @classmethod
    def tearDownClass(cls):
        cls._tmp.cleanup()

    def test_valid_two_animation_fixture_preserves_full_transform_ir(self):
        entry = self.results["valid.mdl"]
        self.assertTrue(entry["ok"], entry)
        self.assertEqual(entry["boneCount"], 2)
        self.assertEqual([item["id"] for item in entry["animations"]], [101, 202])
        self.assertEqual(entry["animations"][0]["sampleCounts"], [3, 3])
        self.assertEqual(entry["animations"][1]["sampleCounts"], [4, 4])
        self.assertEqual(
            entry["animations"][0]["firstTransform"],
            [0, 0, 0, 0, 0, 0, 1, 1, 1],
        )
        self.assertAlmostEqual(entry["animations"][0]["lastTransform"][1], 4, places=6)
        self.assertAlmostEqual(entry["animations"][0]["lastTransform"][3], 0.2, places=6)
        self.assertAlmostEqual(entry["animations"][1]["duration"], 0.05, places=6)

    def test_absent_block_returns_no_animation_set(self):
        self.assertEqual(self.results["absent.mdl"].get("absent"), True)

    def test_old_mdl_version_fails_closed(self):
        self.assertIn("unsupported animation mdl magic", self.results["old-version.mdl"]["error"])

    def test_invalid_block_end_fails_closed(self):
        self.assertIn("invalid MDLA0006 bounds", self.results["bad-end.mdl"]["error"])

    def test_zero_animation_count_fails_closed(self):
        self.assertIn("invalid MDLA0006 animation count 0", self.results["zero-count.mdl"]["error"])

    def test_duplicate_animation_id_fails_closed(self):
        self.assertIn("duplicate MDLA0006 animation id 101", self.results["duplicate-id.mdl"]["error"])

    def test_mdls_mdla_bone_count_mismatch_fails_closed(self):
        self.assertIn("has 3 bones; expected 2", self.results["bone-mismatch.mdl"]["error"])

    def test_track_byte_count_must_match_frame_count(self):
        self.assertIn("invalid animation 101 track", self.results["bad-track-bytes.mdl"]["error"])

    def test_non_finite_transform_fails_closed(self):
        self.assertIn("invalid animation 101 transform", self.results["nan-transform.mdl"]["error"])

    def test_unknown_auxiliary_shape_fails_closed(self):
        self.assertIn("invalid verified auxiliary track", self.results["bad-auxiliary.mdl"]["error"])

    def test_unverified_animation_mode_fails_closed(self):
        self.assertIn("unsupported MDLA0006 animation mode mirror", self.results["unsupported-mode.mdl"]["error"])

    def test_three_real_sources_match_scene_animation_ids_when_available(self):
        if len(self.real_assets) != 3:
            self.skipTest("isolated real MDLA0006 assets are unavailable")
        ahri = self.results["spiritblossomahribase_puppet.mdl"]
        body = self.results["身体_puppet.mdl"]
        person = self.results["人物_puppet.mdl"]
        self.assertTrue(ahri["ok"], ahri)
        self.assertEqual(ahri["boneCount"], 73)
        self.assertEqual(
            [item["id"] for item in ahri["animations"]],
            [275, 280, 282, 284, 286, 288, 290, 324, 332, 344, 662, 595, 650],
        )
        self.assertEqual(ahri["animations"][0]["sampleCounts"], [181] * 73)
        self.assertTrue(body["ok"], body)
        self.assertEqual((body["boneCount"], body["animations"][0]["id"]), (7, 337))
        self.assertEqual(body["animations"][0]["fps"], 60)
        self.assertTrue(person["ok"], person)
        self.assertEqual((person["boneCount"], person["animations"][0]["id"]), (24, 275))
        self.assertEqual(person["animations"][0]["frameCount"], 360)


if __name__ == "__main__":
    unittest.main()
