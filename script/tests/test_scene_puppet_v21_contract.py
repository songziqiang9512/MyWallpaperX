#!/usr/bin/env python3
"""MDLV0021 version contracts through the existing reader fixtures/harnesses."""

from __future__ import annotations

import json
import shutil
import struct
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))
from script.tests import test_scene_puppet_animation as animation
from script.tests import test_scene_puppet_mesh as mesh
from script.tests import test_scene_puppet_rig as rig

SOURCES = {
    "rig": list(rig.SWIFT_SOURCES),
    "attachment": list(mesh.SWIFT_SOURCES),
    "animation": [animation.SWIFT_MODEL_SOURCE, animation.SWIFT_SOURCE],
}
HARNESSES = {"rig": rig.HARNESS, "attachment": mesh.HARNESS, "animation": animation.HARNESS}


def build_v21(*, rig_options=None, attachment_options=None, records=None) -> bytes:
    """Join existing self-authored record builders and repair absolute block ends."""
    body = bytearray(rig.build_rig_mdl(
        magic=b"MDLV0021", skeleton_marker=b"MDLS0003\0", **(rig_options or {}),
    )[:-9])
    skeleton = body.index(b"MDLS0003\0")
    attachment_fixture = mesh.build_attachment_mdl(
        magic=b"MDLV0021", skeleton_marker=b"MDLS0003", **(attachment_options or {}),
    )
    attachments = bytearray(attachment_fixture[attachment_fixture.index(b"MDAT0001\0"):])
    struct.pack_into("<I", body, skeleton + 9, len(body))
    struct.pack_into("<I", attachments, 9, len(body) + len(attachments))
    body += attachments
    if records is None:
        records = [animation.animation_record(101, "Idle", 2, 2),
                   animation.animation_record(202, "Blink", 3, 2, fps=60, mode="single")]
    clips = bytearray(b"MDLA0006\0" + b"\0" * 4 + struct.pack("<I", len(records)))
    clips += b"".join(records)
    struct.pack_into("<I", clips, 9, len(body) + len(clips))
    return bytes(body + clips)


def changed_word(blob: bytes, offset: int, value: int) -> bytes:
    result = bytearray(blob)
    struct.pack_into("<I", result, offset, value)
    return bytes(result)


def fixtures() -> dict[str, bytes]:
    valid = build_v21()
    skeleton, attachment, clip = (valid.index(marker) for marker in
                                  (b"MDLS0003\0", b"MDAT0001\0", b"MDLA0006\0"))
    record = bytearray(animation.animation_record(101, "Idle", 2, 2))
    first_track = 8 + len(b"Idle\0") + len(b"loop\0") + 16
    struct.pack_into("<I", record, first_track, 1)
    return {
        "valid.mdl": valid,
        "wrong-skeleton.mdl": valid.replace(b"MDLS0003\0", b"MDLS0002\0"),
        "wrong-animation.mdl": valid.replace(b"MDLA0006\0", b"MDLA0005\0"),
        "skeleton-bounds.mdl": changed_word(valid, skeleton + 9, len(valid) + 1),
        "attachment-bounds.mdl": changed_word(valid, attachment + 9, len(valid) + 1),
        "animation-bounds.mdl": changed_word(valid, clip + 9, len(valid) + 1),
        "animation-extra-byte.mdl": changed_word(valid + b"\0", clip + 9, len(valid) + 1),
        "stride84.mdl": build_v21(rig_options={"stride": 84}),
        "bad-parent.mdl": build_v21(rig_options={"bad_parent": True}),
        "bad-skin-bone.mdl": build_v21(rig_options={"bad_bone_index": True}),
        "bad-attachment-bone.mdl": build_v21(attachment_options={"attachment_bone": 9}),
        "bone-state.mdl": changed_word(valid, skeleton + 17 + len(b"root\0"), 2),
        "header-state.mdl": build_v21(records=[animation.animation_record(101, "Idle", 2, 2, header_state=1)]),
        "transform-state.mdl": build_v21(records=[animation.animation_record(101, "Idle", 2, 2, transform_state=1)]),
        "track-state.mdl": build_v21(records=[bytes(record)]),
        "animation-bones.mdl": build_v21(records=[animation.animation_record(101, "Idle", 2, 2, declared_bones=3)]),
        "legacy-trailer.mdl": build_v21(records=[animation.animation_record(101, "Idle", 2, 2, legacy_trailer34=True)]),
    }


class ScenePuppetV21ContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        swiftc = shutil.which("swiftc")
        if swiftc is None:
            raise unittest.SkipTest("swiftc is unavailable")
        cls.results = {}
        with tempfile.TemporaryDirectory(prefix="mwx-mdlv21-contract-") as directory:
            path = Path(directory)
            inputs = []
            for name, blob in fixtures().items():
                input_path = path / name
                input_path.write_bytes(blob)
                inputs.append(str(input_path))
            for owner, sources in SOURCES.items():
                harness, binary = path / f"{owner}.swift", path / owner
                harness.write_text(HARNESSES[owner], encoding="utf-8")
                compiled = subprocess.run(
                    [swiftc, *map(str, sources), str(harness), "-o", str(binary)],
                    capture_output=True, text=True, timeout=120,
                )
                if compiled.returncode:
                    raise RuntimeError(compiled.stderr)
                completed = subprocess.run(
                    [str(binary), *inputs], check=True, capture_output=True, text=True, timeout=30,
                )
                cls.results[owner] = {row["file"]: row for row in json.loads(completed.stdout)}

    def assert_rejected(self, owner: str, name: str, reason: str) -> None:
        row = self.results[owner][name]
        field = "attachmentError" if owner == "attachment" else "error"
        self.assertIn(reason, row.get(field, ""), row)

    def test_v21_skin_and_bone_values(self) -> None:
        row = self.results["rig"]["valid.mdl"]
        self.assertTrue(row["ok"], row)
        self.assertEqual((row["stride"], row["vertexCount"], row["boneCount"]), (80, 3, 2))
        self.assertEqual(row["boneNames"], ["root", "MouseBone"])
        self.assertEqual(row["parents"], [-1, 0])
        self.assertEqual(row["bindTranslations"], [[0, 0], [10, 20]])
        self.assertEqual(row["weights"][1], {"indices": [0, 1, 0, 0], "weights": [0.25, 0.75, 0, 0]})

    def test_v21_attachment_values_and_axis_projection(self) -> None:
        row = self.results["attachment"]["valid.mdl"]
        self.assertEqual(row["version"], "MDLV0021")
        self.assertNotIn("attachmentError", row)
        hand, orb = row["attachments"]
        self.assertEqual([hand["name"], orb["name"]], ["hand", "orb"])
        self.assertEqual(hand["boneIndex"], 1)
        self.assertEqual(hand["modelLocalFrame"][12:15], [5, 7, 0])
        self.assertEqual(hand["modelFrame"][12:15], [15, 27, 0])
        self.assertEqual(hand["sceneFrame"][12:15], [15, -27, 0])
        self.assertEqual(orb["sceneFrame"][12:15], [0, 0, 0])

    def test_v21_two_clips_keep_full_trs_and_modern_trailer_boundary(self) -> None:
        row = self.results["animation"]["valid.mdl"]
        self.assertTrue(row["ok"], row)
        self.assertEqual(row["boneCount"], 2)
        idle, blink = row["animations"]
        for clip, expected in ((idle, (101, "Idle", "loop", 30, 2, [3, 3])),
                               (blink, (202, "Blink", "single", 60, 3, [4, 4]))):
            self.assertEqual(tuple(clip[key] for key in ("id", "name", "mode", "fps", "frameCount", "sampleCounts")), expected)
            self.assertIsNone(clip["alphaByBone"])
        self.assertAlmostEqual(idle["duration"], 2 / 30, places=6)
        self.assertAlmostEqual(blink["duration"], 3 / 60, places=6)
        self.assertEqual(idle["firstTransform"], [0, 0, 0, 0, 0, 0, 1, 1, 1])
        for actual, expected in zip(idle["lastTransform"], [0, 4, 0, 0.2, 0, -0.04, 1, 1, 1]):
            self.assertAlmostEqual(actual, expected, places=6)
        self.assert_rejected("animation", "legacy-trailer.mdl", "invalid")

    def test_marker_pairs_and_unproven_skin_stride_remain_restricted(self) -> None:
        for owner in SOURCES:
            self.assert_rejected(owner, "wrong-skeleton.mdl", "version-matched")
        self.assert_rejected("animation", "wrong-animation.mdl", "unsupported animation mdl magic")
        self.assert_rejected("rig", "stride84.mdl", "unsupported skinned vertex stride 84")

    def test_absolute_block_bounds_and_complete_animation_consumption(self) -> None:
        for owner in SOURCES:
            self.assert_rejected(owner, "skeleton-bounds.mdl", "bound")
        self.assert_rejected("attachment", "attachment-bounds.mdl", "invalid MDAT0001 bounds")
        self.assert_rejected("animation", "attachment-bounds.mdl", "boundary")
        for name in ("animation-bounds.mdl", "animation-extra-byte.mdl"):
            self.assert_rejected("animation", name, "invalid version-matched MDLA bounds")

    def test_missing_bones_and_invalid_hierarchy_fail_closed(self) -> None:
        self.assert_rejected("rig", "bad-parent.mdl", "invalid rig parent 1 for bone 1")
        self.assert_rejected("attachment", "bad-parent.mdl", "invalid parent 1 for bone 1")
        self.assert_rejected("rig", "bad-skin-bone.mdl", "invalid puppet vertex weights")
        self.assert_rejected("attachment", "bad-attachment-bone.mdl", "references missing bone 9")
        self.assert_rejected("animation", "animation-bones.mdl", "has 3 bones; expected 2")

    def test_unverified_bone_and_animation_states_fail_closed(self) -> None:
        for owner in ("rig", "attachment"):
            self.assert_rejected(owner, "bone-state.mdl", "bone record 0")
        for name in ("header-state.mdl", "transform-state.mdl"):
            self.assert_rejected("animation", name, "invalid MDLA animation header 0")
        self.assert_rejected("animation", "track-state.mdl", "invalid animation 101 track for bone 0")


if __name__ == "__main__":
    unittest.main()
