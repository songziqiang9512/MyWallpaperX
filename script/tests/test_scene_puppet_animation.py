#!/usr/bin/env python3

"""Contract tests for the restricted version-matched Puppet animation reader."""

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
                        "trackStates": animation.transformTrackStates.map(\.rawValue),
                        "sampleCounts": animation.transformsByBone.map(\.count),
                        "alphaByBone": animation.alphaByBone.map {
                            $0.map { $0.map { Double($0) } } as Any
                        } ?? NSNull(),
                        "events": animation.events.map {
                            ["name": $0.name, "frame": $0.frame,
                             "recordedTime": Double($0.recordedTime)] as [String: Any]
                        },
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


def event_record(recorded_time: float, payload: object, *, terminated: bool = True) -> bytes:
    encoded = payload if isinstance(payload, bytes) else json.dumps(
        payload, ensure_ascii=False, separators=(",", ":")
    ).encode()
    return struct.pack("<f", recorded_time) + encoded + (b"\0" if terminated else b"")


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
    per_bone_auxiliary_trailer: bool = False,
    alpha_by_bone: list[list[float]] | None = None,
    alpha_track_state: int = 0,
    alpha_track_bytes_delta: int = 0,
    alpha_presence: int | None = None,
    alpha_reserved: int = 0,
    mdla5_trailer: bool = False,
    legacy_trailer: bool = False,
    legacy_trailer34: bool = False,
    events: list[bytes] | None = None,
    declared_event_count: int | None = None,
    modern_prefix: bytes = b"\0" * 25,
    track_states: list[int] | None = None,
    track_samples: dict[int, list[tuple[float, ...]]] | None = None,
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
        body += struct.pack("<II", 0 if track_states is None else track_states[bone], byte_count)
        samples = bytearray()
        for frame in range(sample_count):
            samples += struct.pack(
                "<9f",
                *(track_samples[bone][frame] if track_samples and bone in track_samples else
                  transform(frame, bone, nan_component=nan_transform and frame == 1 and bone == 0)),
            )
        body += samples[:byte_count]
    if legacy_trailer:
        body += b"\0" * 10
        return bytes(body)
    if legacy_trailer34:
        body += b"\0" * 34
        return bytes(body)
    body += struct.pack("<I", alpha_reserved)
    if per_bone_auxiliary_trailer and auxiliary and alpha_by_bone is None:
        values = [index / frame_count for index in range(sample_count)]
        alpha_by_bone = [values] * bone_count
    present = int(alpha_by_bone is not None) if alpha_presence is None else alpha_presence
    body += bytes([present])
    if alpha_by_bone is not None:
        for bone, values in enumerate(alpha_by_bone):
            byte_count = len(values) * 4
            if bone == 0:
                byte_count += alpha_track_bytes_delta
                if per_bone_auxiliary_trailer and bad_auxiliary_key:
                    byte_count -= 4
            body += struct.pack("<II", alpha_track_state, byte_count)
            body += struct.pack(f"<{len(values)}f", *values)
    if mdla5_trailer:
        body += b"\0" * 29
        return bytes(body)
    if per_bone_auxiliary_trailer:
        body += b"\0" * 4
        return bytes(body)
    if auxiliary:
        values = [index / frame_count for index in range(sample_count)]
        key = 0xDEADBEEF if bad_auxiliary_key else 0x418A55D5
        body += b"\1" + struct.pack("<IIII", 1, key, 1, sample_count * 4)
        body += struct.pack(f"<{sample_count}f", *values)
    else:
        body += b"\0"
    body += modern_prefix
    records = events or []
    body += struct.pack("<I", len(records) if declared_event_count is None else declared_event_count)
    body += b"".join(records)
    return bytes(body)


def build_mdl(
    animations: list[bytes] | None = None,
    *,
    magic: bytes = b"MDLV0023",
    bone_count: int = 2,
    skeleton_marker: bytes = b"MDLS0004\0",
    include_attachment_boundary: bool = False,
    animation_marker: bytes = b"MDLA0006\0",
    declared_animation_count: int | None = None,
    corrupt_end_offset: bool = False,
) -> bytes:
    if animations is None:
        animations = [animation_record(101, "Idle", 2, bone_count)]
    prefix = bytearray(magic + b"\0" + b"\0" * 24)
    mdls_offset = len(prefix)
    mdls = bytearray(skeleton_marker + b"\0" * 4 + struct.pack("<I", bone_count))
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
                "-module-cache-path", str(tmp / "module-cache"),
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
        bone_alpha = [[1.0, 0.5, 0.0], [0.0, 0.25, 1.0]]
        cls.fixtures = {
            "valid.mdl": build_mdl(valid_animations, include_attachment_boundary=True),
            "valid-modern-alpha.mdl": build_mdl(
                [animation_record(401, "Bone Alpha", 2, 2, alpha_by_bone=bone_alpha)]
            ),
            "valid-modern-both-blocks.mdl": build_mdl([
                animation_record(402, "Alpha And Keyed", 2, 2,
                                 alpha_by_bone=bone_alpha, auxiliary=True),
                animation_record(403, "Next Clip", 2, 2),
            ]),
            "bad-alpha-state.mdl": build_mdl([
                animation_record(401, "Bone Alpha", 2, 2,
                                 alpha_by_bone=bone_alpha, alpha_track_state=1)
            ]),
            "bad-alpha-bytes.mdl": build_mdl([
                animation_record(401, "Bone Alpha", 2, 2,
                                 alpha_by_bone=bone_alpha, alpha_track_bytes_delta=-4)
            ]),
            "bad-alpha-presence.mdl": build_mdl([
                animation_record(401, "Bone Alpha", 2, 2, alpha_presence=2)
            ]),
            "truncated-alpha.mdl": build_mdl([
                animation_record(401, "Bone Alpha", 2, 2,
                                 alpha_by_bone=bone_alpha)[:-35]
            ]),
            "valid-mdlv0016.mdl": build_mdl(
                [animation_record(
                    96,
                    "Legacy Per Bone",
                    2,
                    2,
                    auxiliary=True,
                    per_bone_auxiliary_trailer=True,
                )],
                magic=b"MDLV0016",
                skeleton_marker=b"MDLS0002\0",
                animation_marker=b"MDLA0003\0",
            ),
            "valid-mdlv0016-no-auxiliary.mdl": build_mdl(
                [animation_record(
                    97,
                    "Legacy No Auxiliary",
                    2,
                    2,
                    per_bone_auxiliary_trailer=True,
                )],
                magic=b"MDLV0016",
                skeleton_marker=b"MDLS0002\0",
                animation_marker=b"MDLA0003\0",
            ),
            "bad-mdlv0016-animation-marker.mdl": build_mdl(
                [animation_record(
                    98,
                    "Mismatched Marker",
                    2,
                    2,
                    per_bone_auxiliary_trailer=True,
                )],
                magic=b"MDLV0016",
                skeleton_marker=b"MDLS0002\0",
                animation_marker=b"MDLA0004\0",
            ),
            "bad-mdlv0016-auxiliary.mdl": build_mdl(
                [animation_record(
                    96,
                    "Legacy Per Bone",
                    2,
                    2,
                    auxiliary=True,
                    bad_auxiliary_key=True,
                    per_bone_auxiliary_trailer=True,
                )],
                magic=b"MDLV0016",
                skeleton_marker=b"MDLS0002\0",
                animation_marker=b"MDLA0003\0",
            ),
            "valid-legacy.mdl": build_mdl(
                [animation_record(303, "Legacy", 2, 2, legacy_trailer=True)],
                magic=b"MDLV0017",
                skeleton_marker=b"MDLS0002\0",
                animation_marker=b"MDLA0004\0",
            ),
            "valid-mdlv0019.mdl": build_mdl(
                [animation_record(65, "Animation 1", 2, 2, legacy_trailer34=True)],
                magic=b"MDLV0019",
                skeleton_marker=b"MDLS0002\0",
                animation_marker=b"MDLA0005\0",
            ),
            "bad-mdlv0019-trailer.mdl": build_mdl(
                [animation_record(65, "Animation 1", 2, 2, legacy_trailer=True)],
                magic=b"MDLV0019",
                skeleton_marker=b"MDLS0002\0",
                animation_marker=b"MDLA0005\0",
            ),
            "mismatched-legacy-markers.mdl": build_mdl(
                [animation_record(303, "Legacy", 2, 2)],
                magic=b"MDLV0017",
            ),
            "absent.mdl": b"MDLV0023\0" + b"\0" * 32,
            "unknown-version.mdl": build_mdl(magic=b"MDLV0015"),
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
            "valid-mirror.mdl": build_mdl(
                [animation_record(101, "Mirror", 2, 2, mode="mirror")]
            ),
            "valid-single.mdl": build_mdl(
                [animation_record(102, "Single", 2, 2, mode="single")]
            ),
            "unsupported-mode.mdl": build_mdl(
                [animation_record(103, "Unknown", 2, 2, mode="pingpong")]
            ),
        }
        cue = event_record(0.125, {"frame": 2, "name": "Wake_Ω"})
        cls.fixtures["events-two-clips.mdl"] = build_mdl([
            animation_record(501, "Source motion", 4, 2, events=[cue]),
            animation_record(502, "Target motion", 4, 2),
        ])
        cls.fixtures["renamed-event-resource.mdl"] = build_mdl([
            animation_record(671, "改名动画", 6, 2, fps=60, events=[event_record(
                -7, b' { "name" : "\\u4fe1\\u53f7", "frame" : 2.0 } '
            )]),
        ])
        budget_records = [event_record(0, {"frame": 1, "name": "cue"})] * 1024
        bounded_payload = json.dumps({"frame": 1, "name": "Ω" * 512},
                                     ensure_ascii=False, separators=(",", ":")).encode()
        bounded_payload += b" " * (4096 - len(bounded_payload))
        cls.fixtures["event-exact-string-budgets.mdl"] = build_mdl([
            animation_record(672, "Exact budgets", 2, 2,
                             events=[event_record(0.25, bounded_payload)])
        ])
        for count in (4, 5):
            cls.fixtures[f"event-total-{count * 1024}.mdl"] = build_mdl([
                animation_record(700 + index, f"Budget {index}", 2, 2,
                                 events=budget_records)
                for index in range(count)
            ])
        invalid_payloads = {
            "array": [], "syntax": b"{", "utf8": b"\xff",
            "missing-name": {"frame": 2}, "missing-frame": {"name": "cue"},
            "extra-key": {"frame": 2, "name": "cue", "extra": 1},
            "frame-bool": {"frame": True, "name": "cue"},
            "frame-string": {"frame": "2", "name": "cue"},
            "frame-fraction": {"frame": 1.5, "name": "cue"},
            "frame-zero": {"frame": 0, "name": "cue"},
            "frame-end": {"frame": 4, "name": "cue"},
            "frame-negative": {"frame": -1, "name": "cue"},
            "frame-huge": {"frame": 1e30, "name": "cue"},
            "empty-name": {"frame": 2, "name": ""},
            "name-number": {"frame": 2, "name": 1},
            "name-nul": {"frame": 2, "name": "a\0b"},
            "name-bytes": {"frame": 2, "name": "界" * 342},
            "payload-bytes": b" " * 4097 + b'{"frame":2,"name":"cue"}',
        }
        for label, payload in invalid_payloads.items():
            cls.fixtures[f"bad-event-{label}.mdl"] = build_mdl([
                animation_record(501, "Malformed cue", 4, 2,
                                 events=[event_record(0.125, payload)])
            ])
        for label, value in (("nan", math.nan), ("inf", math.inf), ("negative-inf", -math.inf)):
            cls.fixtures[f"bad-event-time-{label}.mdl"] = build_mdl([
                animation_record(501, "Invalid recorded field", 4, 2,
                                 events=[event_record(value, {"frame": 2, "name": "cue"})])
            ])
        for count in (1025, 0xFFFFFFFF):
            cls.fixtures[f"bad-event-count-{count}.mdl"] = build_mdl([
                animation_record(501, "Count", 4, 2, declared_event_count=count,
                                 events=budget_records + [cue] if count == 1025 else None)
            ])
        for mode in ("mirror", "single"):
            cls.fixtures[f"bad-event-mode-{mode}.mdl"] = build_mdl([
                animation_record(501, "Mode", 4, 2, mode=mode, events=[cue])
            ])
        cls.fixtures["bad-event-short-time.mdl"] = build_mdl([
            animation_record(501, "Short field", 4, 2, events=[b"\0\0"])
        ])
        cls.fixtures["bad-event-count-mismatch.mdl"] = build_mdl([
            animation_record(501, "Count mismatch", 4, 2, events=[cue], declared_event_count=2),
            animation_record(502, "Healthy next", 4, 2),
        ])
        cls.fixtures["bad-event-missing-terminator.mdl"] = build_mdl([
            animation_record(501, "No terminator", 4, 2,
                             events=[event_record(0.125, {"frame": 2, "name": "cue"}, terminated=False)])
        ])
        outside = bytearray(cls.fixtures["events-two-clips.mdl"])
        marker = outside.index(b"MDLA0006\0")
        # Leave physical bytes after the declared MDLA end: they cannot finish the JSON.
        first_payload = outside.index(b'{"frame":2,"name":')
        struct.pack_into("<I", outside, marker + 9, first_payload + 8)
        cls.fixtures["bad-event-outside-declared-block.mdl"] = bytes(outside)
        cls.fixtures["bad-modern-aabb.mdl"] = build_mdl([
            animation_record(501, "Unknown bounds", 4, 2,
                             modern_prefix=struct.pack("<f", 1) + b"\0" * 21)
        ])
        cls.fixtures["bad-modern-scalar-presence.mdl"] = build_mdl([
            animation_record(501, "Unknown curve", 4, 2, modern_prefix=b"\0" * 24 + b"\1")
        ])
        for label, value in (
            ("negative", -0.01), ("above-one", 1.01),
            ("nan", float("nan")), ("infinity", float("inf")),
        ):
            cls.fixtures[f"bad-alpha-{label}.mdl"] = build_mdl([
                animation_record(401, "Bone Alpha", 2, 2,
                                 alpha_by_bone=[[1.0, value, 0.0], bone_alpha[1]])
            ])
        mdla5 = dict(magic=b"MDLV0019", skeleton_marker=b"MDLS0002\0",
                     animation_marker=b"MDLA0005\0")
        cls.mdla5_alpha = [[0, 0.25, 0.5, 0.75, 1],
                           [1, 1, 0, 1, 1], [0.125, 0.25, 0.375, 0.5, 0.625]]
        first = animation_record(781, "Night coverage Ω", 4, 3,
                                 alpha_by_bone=cls.mdla5_alpha, mdla5_trailer=True)
        second = animation_record(902, "Renamed settle", 1, 3, fps=60, mode="mirror",
                                  alpha_by_bone=[[1, 1], [0.75, 0.25], [0, 1]],
                                  mdla5_trailer=True)
        cls.fixtures["renamed-mdla5-alpha-pair.mdl"] = build_mdl(
            [first, second], bone_count=3, include_attachment_boundary=True, **mdla5
        )
        cls.fixtures["single-bone-other-resource-mdla5.mdl"] = build_mdl([
            animation_record(1207, "另名轨道", 3, 1, fps=24, mode="single",
                             alpha_by_bone=[[0, 0.125, 1, 1 + 2 ** -16]],
                             mdla5_trailer=True)
        ], bone_count=1, **mdla5)
        cls.fixtures["mdla5-absent-then-present.mdl"] = build_mdl([
            animation_record(2011, "No coverage", 1, 2, mdla5_trailer=True),
            animation_record(2012, "Coverage follows", 2, 2,
                             alpha_by_bone=bone_alpha, mdla5_trailer=True)
        ], **mdla5)
        cls.fixtures["mdla5-absent-equivalent.mdl"] = build_mdl([
            animation_record(65, "Animation 1", 2, 2, mdla5_trailer=True)
        ], **mdla5)
        malformed = {
            "reserved": dict(alpha_reserved=1),
            "presence": dict(alpha_presence=2),
            "track-state": dict(alpha_track_state=1),
            "short-track": dict(alpha_track_bytes_delta=-4),
            "long-track": dict(alpha_track_bytes_delta=4),
            "missing-bone-track": dict(alpha_by_bone=cls.mdla5_alpha[:2]),
        }
        for label, overrides in malformed.items():
            options = dict(alpha_by_bone=cls.mdla5_alpha, mdla5_trailer=True)
            options.update(overrides)
            cls.fixtures[f"bad-mdla5-{label}.mdl"] = build_mdl([
                animation_record(781, "Malformed coverage", 4, 3, **options)
            ], bone_count=3, **mdla5)
        for label, value in (("negative", -0.001), ("above-domain", 1.0002),
                             ("nan", math.nan), ("inf", math.inf), ("ninf", -math.inf)):
            cls.fixtures[f"bad-mdla5-domain-{label}.mdl"] = build_mdl([
                animation_record(1207, "Illegal coverage", 1, 1,
                                 alpha_by_bone=[[1, value]], mdla5_trailer=True)
            ], bone_count=1, **mdla5)
        for label, record in {
            "truncated-sample": first[:-32],
            "short-tail": first[:-1],
            "nonzero-tail": first[:-1] + b"\1",
            "extra-tail": first + b"\0",
        }.items():
            cls.fixtures[f"bad-mdla5-{label}.mdl"] = build_mdl(
                [record], bone_count=3, **mdla5
            )
        cls.fixtures["bad-mdla5-two-clip-gap.mdl"] = build_mdl(
            [first + b"\0", second], bone_count=3, **mdla5
        )
        for label, overrides in {
            "wrong-version": dict(magic=b"MDLV0017"),
            "wrong-skeleton": dict(skeleton_marker=b"MDLS0003\0"),
            "wrong-animation": dict(animation_marker=b"MDLA0006\0"),
        }.items():
            profile = {**mdla5, **overrides}
            cls.fixtures[f"bad-mdla5-{label}.mdl"] = build_mdl(
                [first], bone_count=3, **profile
            )
        held = (10.0, -20.0, 3.0, 0.1, -0.2, 0.3, 1.5, 0.8, 1.0)
        for filename, clip_id, clip_name, samples in (
            ("dense-reference.mdl", 1301, "Held reference", [held] * 3),
            ("renamed-κ-resource.mdl", 2907, "不同控制", [tuple(x + 0.0 for x in held)] * 3),
        ):
            cls.fixtures[filename] = build_mdl([
                animation_record(clip_id, clip_name, 2, 2, track_states=[1, 0],
                    track_samples={0: samples}, alpha_by_bone=bone_alpha),
                animation_record(clip_id + 1, "Following ordinary clip", 2, 2),
            ], **(dict(magic=b"MDLV0021", skeleton_marker=b"MDLS0003\0") if clip_id == 2907 else {}))
        dense = dict(track_states=[1, 0], track_samples={0: [held] * 3})
        for component in range(9):
            changed = list(held)
            changed[component] += 0.00001
            cls.fixtures[f"bad-dense-vary-{component}.mdl"] = build_mdl([
                animation_record(1301, "Not constant", 2, 2,
                    track_states=[1, 0], track_samples={0: [held, held, tuple(changed)]})])
        for label, options in (("state2", dict(track_states=[2, 0])),
                               ("length", dict(bad_track_bytes=True)),
                               ("nonfinite", dict(track_samples={0: [(math.nan, *held[1:])] * 3}))):
            cls.fixtures[f"bad-dense-{label}.mdl"] = build_mdl([
                animation_record(1301, "Invalid reference", 2, 2, **(dense | options))])
        for label, record, options in (
            ("legacy16", dict(per_bone_auxiliary_trailer=True), dict(magic=b"MDLV0016",
                skeleton_marker=b"MDLS0002\0", animation_marker=b"MDLA0003\0")),
            ("legacy17", dict(legacy_trailer=True), dict(magic=b"MDLV0017",
                skeleton_marker=b"MDLS0002\0", animation_marker=b"MDLA0004\0")),
            ("legacy19", dict(mdla5_trailer=True), mdla5),
        ):
            cls.fixtures[f"bad-dense-{label}.mdl"] = build_mdl([
                animation_record(1301, "Unqualified version", 2, 2, **dense, **record)], **options)
        record = animation_record(1301, "Exact end", 2, 2, **dense)
        cls.fixtures["bad-dense-end.mdl"] = build_mdl([record], corrupt_end_offset=True)
        cls.fixtures["bad-dense-tail.mdl"] = build_mdl([record + b"\0"])
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

    def test_modern_constant_reference_state_is_loss_preserving_and_not_clip_wide(self):
        for name in ("dense-reference.mdl", "renamed-κ-resource.mdl"):
            with self.subTest(name=name):
                entry = self.results[name]
                self.assertTrue(entry["ok"], entry)
                first, following = entry["animations"]
                self.assertEqual(first["trackStates"], [1, 0])
                self.assertEqual(following["trackStates"], [0, 0])
                self.assertEqual(first["sampleCounts"], [3, 3])
                self.assertEqual(first["firstTransform"], first["lastTransform"])
                for actual, expected in zip(first["firstTransform"],
                        [10, -20, 3, .1, -.2, .3, 1.5, .8, 1], strict=True):
                    self.assertAlmostEqual(actual, expected, places=6)
                self.assertEqual(first["alphaByBone"], [[1, .5, 0], [0, .25, 1]])
        self.assertEqual(self.results["valid-legacy.mdl"]["animations"][0]["trackStates"], [0, 0])

    def test_reference_track_does_not_relax_version_shape_numeric_or_exact_end(self):
        cases = {name: result for name, result in self.results.items() if name.startswith("bad-dense-")}
        self.assertEqual(len(cases), 17)
        for name, result in cases.items():
            with self.subTest(name=name):
                self.assertFalse(result["ok"], result)

    def test_modern_events_preserve_typed_fields_and_next_clip_boundary(self):
        entry = self.results["events-two-clips.mdl"]
        self.assertTrue(entry["ok"], entry)
        first, second = entry["animations"]
        self.assertEqual([first["id"], second["id"]], [501, 502])
        self.assertEqual(first["sampleCounts"], [5, 5])
        self.assertEqual(first["events"], [{"name": "Wake_Ω", "frame": 2, "recordedTime": 0.125}])
        self.assertEqual(second["events"], [])
        self.assertEqual(second["lastTransform"][:3], [0, 8, 0])

    def test_event_json_equivalence_and_renamed_unicode_resource(self):
        entry = self.results["renamed-event-resource.mdl"]
        self.assertTrue(entry["ok"], entry)
        animation = entry["animations"][0]
        self.assertEqual((animation["id"], animation["name"], animation["fps"]), (671, "改名动画", 60))
        self.assertEqual(animation["events"], [{"name": "信号", "frame": 2, "recordedTime": -7}])
        bounded = self.results["event-exact-string-budgets.mdl"]
        self.assertTrue(bounded["ok"], bounded)
        event = bounded["animations"][0]["events"][0]
        self.assertEqual(len(event["name"].encode()), 1024)
        self.assertEqual((event["frame"], event["recordedTime"]), (1, 0.25))

    def test_event_count_budgets_are_independent_of_transform_budget(self):
        accepted = self.results["event-total-4096.mdl"]
        self.assertTrue(accepted["ok"], accepted)
        self.assertEqual([len(a["events"]) for a in accepted["animations"]], [1024] * 4)
        rejected = self.results["event-total-5120.mdl"]
        self.assertFalse(rejected["ok"], rejected)
        self.assertIn("invalid bounded event record", rejected["error"])

    def test_malformed_event_records_and_unsupported_modes_fail_closed(self):
        for name in self.fixtures:
            if not name.startswith("bad-event-"):
                continue
            with self.subTest(name=name):
                entry = self.results[name]
                self.assertFalse(entry["ok"], entry)
                self.assertIn("invalid bounded event record", entry["error"])

    def test_zero_event_versions_and_unexplained_modern_fields_keep_boundaries(self):
        for name in ("valid.mdl", "valid-modern-alpha.mdl", "valid-mdlv0016.mdl",
                     "valid-legacy.mdl", "valid-mdlv0019.mdl", "valid-mirror.mdl", "valid-single.mdl"):
            with self.subTest(name=name):
                entry = self.results[name]
                self.assertTrue(entry["ok"], entry)
                self.assertTrue(all(a["events"] == [] for a in entry["animations"]))
        for name in ("bad-modern-aabb.mdl", "bad-modern-scalar-presence.mdl"):
            with self.subTest(name=name):
                entry = self.results[name]
                self.assertFalse(entry["ok"], entry)
                self.assertIn("invalid verified auxiliary track", entry["error"])

    def test_mdlv0017_mdls0002_mdla0004_preserves_the_same_transform_ir(self):
        entry = self.results["valid-legacy.mdl"]
        self.assertTrue(entry["ok"], entry)
        self.assertEqual(entry["boneCount"], 2)
        self.assertEqual(entry["animations"][0]["id"], 303)
        self.assertEqual(entry["animations"][0]["sampleCounts"], [3, 3])

    def test_mdlv0016_mdls0002_mdla0003_reads_per_bone_auxiliary_trailer(self):
        entry = self.results["valid-mdlv0016.mdl"]
        self.assertTrue(entry["ok"], entry)
        self.assertEqual((entry["boneCount"], entry["animations"][0]["id"]), (2, 96))
        self.assertEqual(entry["animations"][0]["sampleCounts"], [3, 3])
        self.assertEqual(entry["animations"][0]["alphaByBone"], [[0, 0.5, 1]] * 2)

    def test_modern_per_bone_alpha_preserves_order_and_every_sample(self):
        entry = self.results["valid-modern-alpha.mdl"]
        self.assertTrue(entry["ok"], entry)
        self.assertEqual(entry["animations"][0]["alphaByBone"],
                         [[1, 0.5, 0], [0, 0.25, 1]])

    def test_modern_alpha_and_keyed_blocks_keep_next_clip_boundary(self):
        entry = self.results["valid-modern-both-blocks.mdl"]
        self.assertTrue(entry["ok"], entry)
        self.assertEqual([animation["id"] for animation in entry["animations"]], [402, 403])
        self.assertEqual(entry["animations"][0]["alphaByBone"],
                         [[1, 0.5, 0], [0, 0.25, 1]])
        self.assertIsNone(entry["animations"][1]["alphaByBone"])

    def test_absent_alpha_remains_nil_across_versions_and_keyed_only_clip(self):
        for name in ("valid.mdl", "valid-mdlv0016-no-auxiliary.mdl",
                     "valid-legacy.mdl", "valid-mdlv0019.mdl"):
            with self.subTest(name=name):
                entry = self.results[name]
                self.assertTrue(entry["ok"], entry)
                self.assertTrue(all(animation["alphaByBone"] is None
                                    for animation in entry["animations"]))

    def test_malformed_or_truncated_alpha_tracks_fail_closed(self):
        for name in ("bad-alpha-state.mdl", "bad-alpha-bytes.mdl",
                     "bad-alpha-presence.mdl", "truncated-alpha.mdl"):
            with self.subTest(name=name):
                entry = self.results[name]
                self.assertFalse(entry["ok"], entry)
                self.assertIn("invalid verified auxiliary track", entry["error"])

    def test_alpha_samples_must_be_finite_and_in_coverage_range(self):
        for label in ("negative", "above-one", "nan", "infinity"):
            with self.subTest(label=label):
                entry = self.results[f"bad-alpha-{label}.mdl"]
                self.assertFalse(entry["ok"], entry)
                self.assertIn("invalid verified auxiliary track", entry["error"])

    def test_mdlv0016_rejects_malformed_per_bone_auxiliary_track(self):
        self.assertIn(
            "invalid verified auxiliary track",
            self.results["bad-mdlv0016-auxiliary.mdl"]["error"],
        )

    def test_mdlv0016_accepts_the_verified_no_auxiliary_trailer(self):
        entry = self.results["valid-mdlv0016-no-auxiliary.mdl"]
        self.assertTrue(entry["ok"], entry)
        self.assertEqual((entry["boneCount"], entry["animations"][0]["id"]), (2, 97))

    def test_mdlv0016_rejects_an_unverified_animation_marker_pair(self):
        self.assertIn(
            "unsupported animation mdl magic",
            self.results["bad-mdlv0016-animation-marker.mdl"]["error"],
        )

    def test_mdlv0017_rejects_the_mismatched_modern_markers(self):
        self.assertIn(
            "unsupported animation mdl magic",
            self.results["mismatched-legacy-markers.mdl"]["error"],
        )

    def test_mdlv0019_mdls0002_mdla0005_preserves_the_same_transform_ir(self):
        entry = self.results["valid-mdlv0019.mdl"]
        self.assertTrue(entry["ok"], entry)
        self.assertEqual(entry["boneCount"], 2)
        self.assertEqual(entry["animations"][0]["id"], 65)
        self.assertEqual(entry["animations"][0]["sampleCounts"], [3, 3])

    def test_mdla5_alpha_preserves_every_bone_sample_and_next_clip(self):
        entry = self.results["renamed-mdla5-alpha-pair.mdl"]
        self.assertTrue(entry["ok"], entry)
        self.assertEqual(entry["boneCount"], 3)
        first, second = entry["animations"]
        self.assertEqual((first["id"], first["name"], first["mode"], first["fps"]),
                         (781, "Night coverage Ω", "loop", 30))
        self.assertEqual(first["sampleCounts"], [5, 5, 5])
        self.assertEqual(first["alphaByBone"], self.mdla5_alpha)
        self.assertEqual(first["lastTransform"][:3], [0, 8, 0])
        self.assertEqual((second["id"], second["name"], second["mode"], second["fps"]),
                         (902, "Renamed settle", "mirror", 60))
        self.assertEqual(second["sampleCounts"], [2, 2, 2])
        self.assertEqual(second["alphaByBone"], [[1, 1], [0.75, 0.25], [0, 1]])
        self.assertEqual(second["lastTransform"][:3], [0, 2, 0])
        self.assertEqual([first["events"], second["events"]], [[], []])

    def test_mdla5_renamed_resource_and_dimensions_do_not_round_alpha(self):
        entry = self.results["single-bone-other-resource-mdla5.mdl"]
        self.assertTrue(entry["ok"], entry)
        clip = entry["animations"][0]
        self.assertEqual((entry["boneCount"], clip["id"], clip["name"], clip["fps"]),
                         (1, 1207, "另名轨道", 24))
        self.assertEqual((clip["mode"], clip["sampleCounts"]), ("single", [4]))
        self.assertEqual(clip["alphaByBone"], [[0, 0.125, 1, 1 + 2 ** -16]])

    def test_mdla5_absent_alpha_keeps_old_wire_and_following_present_track(self):
        self.assertEqual(self.fixtures["mdla5-absent-equivalent.mdl"],
                         self.fixtures["valid-mdlv0019.mdl"])
        self.assertEqual(self.results["mdla5-absent-equivalent.mdl"]["animations"],
                         self.results["valid-mdlv0019.mdl"]["animations"])
        entry = self.results["mdla5-absent-then-present.mdl"]
        self.assertTrue(entry["ok"], entry)
        first, second = entry["animations"]
        self.assertEqual([first["id"], second["id"]], [2011, 2012])
        self.assertIsNone(first["alphaByBone"])
        self.assertEqual(second["alphaByBone"], [[1, 0.5, 0], [0, 0.25, 1]])

    def test_mdla5_bad_alpha_headers_lengths_and_samples_fail_closed(self):
        labels = ("reserved", "presence", "track-state", "short-track", "long-track",
                  "missing-bone-track", "truncated-sample")
        for label in labels:
            with self.subTest(label=label):
                entry = self.results[f"bad-mdla5-{label}.mdl"]
                self.assertFalse(entry["ok"], entry)
                self.assertIn("invalid verified auxiliary track", entry["error"])
        for label in ("negative", "above-domain", "nan", "inf", "ninf"):
            with self.subTest(domain=label):
                entry = self.results[f"bad-mdla5-domain-{label}.mdl"]
                self.assertFalse(entry["ok"], entry)
                self.assertIn("invalid verified auxiliary track", entry["error"])

    def test_mdla5_tail_is_exact_and_cannot_consume_a_following_clip(self):
        for label in ("short-tail", "nonzero-tail", "extra-tail", "two-clip-gap"):
            with self.subTest(label=label):
                entry = self.results[f"bad-mdla5-{label}.mdl"]
                self.assertFalse(entry["ok"], entry)
                self.assertIn("invalid", entry["error"])

    def test_mdla5_alpha_does_not_expand_version_pairs(self):
        for label in ("wrong-version", "wrong-skeleton", "wrong-animation"):
            with self.subTest(label=label):
                entry = self.results[f"bad-mdla5-{label}.mdl"]
                self.assertFalse(entry["ok"], entry)
                expected = ("version-matched preceding MDLS block" if label == "wrong-skeleton"
                            else "unsupported animation mdl magic")
                self.assertIn(expected, entry["error"])

    def test_mdlv0019_rejects_an_unverified_trailer(self):
        self.assertIn(
            "invalid verified auxiliary track",
            self.results["bad-mdlv0019-trailer.mdl"]["error"],
        )

    def test_unknown_mdl_version_fails_closed(self):
        self.assertIn(
            "unsupported animation mdl magic",
            self.results["unknown-version.mdl"]["error"],
        )

    def test_invalid_block_end_fails_closed(self):
        self.assertIn("invalid version-matched MDLA bounds", self.results["bad-end.mdl"]["error"])

    def test_zero_animation_count_fails_closed(self):
        self.assertIn("invalid MDLA animation count 0", self.results["zero-count.mdl"]["error"])

    def test_duplicate_animation_id_fails_closed(self):
        self.assertIn("duplicate MDLA animation id 101", self.results["duplicate-id.mdl"]["error"])

    def test_mdls_mdla_bone_count_mismatch_fails_closed(self):
        self.assertIn("has 3 bones; expected 2", self.results["bone-mismatch.mdl"]["error"])

    def test_track_byte_count_must_match_frame_count(self):
        self.assertIn("invalid animation 101 track", self.results["bad-track-bytes.mdl"]["error"])

    def test_non_finite_transform_fails_closed(self):
        self.assertIn("invalid animation 101 transform", self.results["nan-transform.mdl"]["error"])

    def test_unknown_auxiliary_shape_fails_closed(self):
        self.assertIn("invalid verified auxiliary track", self.results["bad-auxiliary.mdl"]["error"])

    def test_mirror_and_single_animation_modes_are_preserved(self):
        self.assertEqual(self.results["valid-mirror.mdl"]["animations"][0]["mode"], "mirror")
        self.assertEqual(self.results["valid-single.mdl"]["animations"][0]["mode"], "single")

    def test_unverified_animation_mode_fails_closed(self):
        self.assertIn("unsupported MDLA animation mode pingpong", self.results["unsupported-mode.mdl"]["error"])

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
