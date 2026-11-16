"""CPU geometry against the production directional projector; no Metal device."""
import copy
import hashlib
import json
import math
import os
from pathlib import Path
import unittest

from script.tests import test_scene_directional_shadow as native

REPO = Path(__file__).resolve().parents[2]
SOURCE = REPO / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Metal/SceneStaticModelShadow.swift"
FIXTURE = Path(__file__).with_name("fixtures") / "SceneDirectionalShadowFitChecks.swift"
IDENTITY = [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1]
ZERO = [0] * 16


def box(low, high, *, world=None, clip=None):
    return {"minimum": low, "maximum": high, "world": world or IDENTITY, "clip": clip}


def vectors():
    caster = box([-.25, -.25, .75], [.25, .25, .8])
    receiver = box([-.5, -.5, .4], [.5, .5, .6], clip=IDENTITY)
    base = {"name": "base", "casters": [caster], "receivers": [receiver],
            "towardLight": [0, 0, 1], "resolution": 1024,
            "witnesses": [[0, 0, .5], [.2, .2, .5], [-.2, -.2, .5]]}
    result = []

    def add(name, **values):
        item = copy.deepcopy(base)
        item.update(name=name, **values)
        result.append(item)
        return item

    add("base")
    add("renamed-Ω", resourceName="models/unrelated-名字.mdl", towardLight=[0, 0, 2])
    add("remote-caster-xy", casters=[caster, box([10000, 10000, .75], [10001, 10001, .8])])
    add("remote-caster-xy-z", casters=[caster, box([10000, 10000, -1e8], [10001, 10001, -1e8+16])])
    add("outside-receiver-z", receivers=[receiver, box([-.2, -.2, -1e8], [.2, .2, -1e8+16], clip=IDENTITY)])
    add("relevant-offscreen-caster", casters=[caster, box([-.2, -.2, 100], [.2, .2, 101])],
        witnesses=[[0, 0, .5], [0, 0, 100.5]])
    distant = box([-.2, -.2, -101], [.2, .2, -99])
    add("nil-distant-receiver", receivers=[receiver, distant], witnesses=[[0, 0, .5], [0, 0, -100]])
    add("zero-distant-receiver", receivers=[receiver, dict(distant, clip=ZERO)],
        witnesses=[[0, 0, .5], [0, 0, -100]])
    add("outside-only", receivers=[dict(distant, clip=IDENTITY)])
    add("nil-only", receivers=[distant], witnesses=[[0, 0, -100]])
    add("zero-only", receivers=[dict(distant, clip=ZERO)], witnesses=[[0, 0, -100]])
    wide_caster = box([-5, -5, .75], [5, 5, .8])
    long_receiver = box([-100, -.1, .4], [.05, .1, .6], clip=IDENTITY)
    add("long-grazing", casters=[wide_caster], receivers=[long_receiver],
        witnesses=[[-.99, 0, .5], [.049, 0, .5]])
    add("literal-grazing-crop", casters=[wide_caster],
        receivers=[box([-1, -.1, .4], [.05, .1, .6])],
        witnesses=[[-.99, 0, .5], [.049, 0, .5]])
    add("camera-in-box", casters=[wide_caster], receivers=[box([-100]*3, [100]*3, clip=IDENTITY)],
        witnesses=[[-.99, -.99, .01], [.99, .99, .99]])
    add("literal-clip-cube", casters=[wide_caster], receivers=[box([-1, -1, 0], [1, 1, 1])],
        witnesses=[[-.99, -.99, .01], [.99, .99, .99]])
    c = math.sqrt(.5)
    diagonal = [c, c, 0, 0, -c, c, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1]
    add("diagonal-no-corner-inside", casters=[wide_caster],
        receivers=[box([-3, -.05, .45], [3, .05, .55], world=diagonal, clip=IDENTITY)],
        witnesses=[[0, 0, .5], [.6, .6, .5], [-.6, -.6, .5]])
    reverse = [-1, 0, 0, 0, 0, 1, 0, 0, 0, 0, -1, 0, 0, 0, 1, 1]
    add("opposite-reverse-depth", receivers=[dict(receiver, clip=reverse)])
    # FOV90/aspect1, eye(0,0,2), near1/far3, reverse Metal depth.
    perspective = [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, .5, -1, 0, 0, .5, 2]
    add("native-perspective", receivers=[dict(receiver, clip=perspective)])
    canvas = [.25, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1]
    right_receiver = box([2.9, -.1, .4], [3.1, .1, .6], clip=canvas)
    both_casters = [caster, box([2.9, -.1, .75], [3.1, .1, .8])]
    add("mixed-native-canvas", casters=both_casters,
        receivers=[dict(receiver, clip=perspective), right_receiver], witnesses=[[0, 0, .5], [3, 0, .5]])
    add("mixed-literal-reference", casters=both_casters,
        receivers=[dict(receiver, clip=None), dict(right_receiver, clip=None)], witnesses=[[0, 0, .5], [3, 0, .5]])
    shift = [16, -8, 4]
    world = list(IDENTITY)
    world[12:15] = shift
    clip = list(IDENTITY)
    clip[12:15] = [-x for x in shift]
    add("parent-translation-equivalent", casters=[dict(caster, world=world)],
        receivers=[dict(receiver, world=world, clip=clip)],
        witnesses=[[p[i]+shift[i] for i in range(3)] for p in base["witnesses"]])
    return result


class SceneDirectionalShadowFitTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.vectors = vectors()
        source = Path(os.environ.get("MWX_SHADOW_FIT_SOURCE", SOURCE)).resolve()
        owned = [Path(__file__), FIXTURE, source]
        before = {str(p): hashlib.sha256(p.read_bytes()).hexdigest() for p in owned}
        flags = ("-D", "MWX_OLD_SHADOW_API") if os.environ.get("MWX_SHADOW_FIT_OLD_API") == "1" else ()
        cls.report = native.run_swift([source], FIXTURE.read_text(), label="cpu-fit",
                                     input_value=cls.vectors, swift_flags=flags)
        if any(hashlib.sha256(Path(p).read_bytes()).hexdigest() != digest for p, digest in before.items()):
            raise AssertionError("CPU fit source or fixture changed during compile/run")
        cls.rows = {r["name"]: r for r in cls.report["rows"]}

    def equal_matrix(self, a, b):
        self.assertTrue(a["present"] and b["present"])
        for actual, expected in zip(a["matrix"], b["matrix"]):
            self.assertLessEqual(abs(actual-expected), 8 * 2**-23 * max(1, abs(expected)))

    def witnesses_inside(self, row):
        self.assertTrue(row["present"])
        for x, y, z in row["witnessClip"]:
            self.assertLessEqual(abs(x), 1+1e-5)
            self.assertLessEqual(abs(y), 1+1e-5)
            self.assertGreaterEqual(z, -1e-5)
            self.assertLessEqual(z, 1+1e-5)

    def test_unrelated_remote_bounds_do_not_dilute_visible_shadow(self):
        base = self.rows["base"]
        for name in ["remote-caster-xy", "remote-caster-xy-z", "outside-receiver-z"]:
            with self.subTest(case=name):
                self.equal_matrix(self.rows[name], base)

    def test_offscreen_relevant_caster_remains_in_light_depth(self):
        row = self.rows["relevant-offscreen-caster"]
        self.witnesses_inside(row)
        self.assertLess(row["witnessClip"][1][2], row["witnessClip"][0][2])

    def test_true_convex_intersections_match_independent_literal_crops(self):
        for actual, literal in [("long-grazing", "literal-grazing-crop"),
                                ("camera-in-box", "literal-clip-cube")]:
            with self.subTest(case=actual):
                self.equal_matrix(self.rows[actual], self.rows[literal])
                self.witnesses_inside(self.rows[actual])
        self.assertLess(max(self.rows["long-grazing"]["worldUnitsPerTexel"]), 1.1/1024)
        self.assertLess(max(self.rows["camera-in-box"]["worldUnitsPerTexel"]), 2.1/1024)
        row = self.rows["diagonal-no-corner-inside"]
        self.witnesses_inside(row)
        # Its real intersection is inside the literal unit clip square.
        self.assertLess(max(row["worldUnitsPerTexel"]), 2.1/1024)

    def test_outside_receiver_does_not_request_a_shadow_map(self):
        self.assertFalse(self.rows["outside-only"]["present"])

    def test_reverse_native_and_canvas_domains_keep_their_receivers(self):
        for name in ["opposite-reverse-depth", "native-perspective"]:
            with self.subTest(case=name):
                self.equal_matrix(self.rows[name], self.rows["base"])
        self.equal_matrix(self.rows["mixed-native-canvas"], self.rows["mixed-literal-reference"])
        self.witnesses_inside(self.rows["mixed-native-canvas"])

    def test_xy_texel_size_does_not_depend_on_relevant_depth_span(self):
        base = self.rows["base"]["worldUnitsPerTexel"]
        for name in ["relevant-offscreen-caster", "nil-distant-receiver"]:
            with self.subTest(case=name):
                for actual, expected in zip(self.rows[name]["worldUnitsPerTexel"], base):
                    self.assertLessEqual(abs(actual-expected), 8 * 2**-23 * expected)

    def test_unknown_or_degenerate_clip_preserves_complete_bounds(self):
        for a, b in [("nil-distant-receiver", "zero-distant-receiver"), ("nil-only", "zero-only")]:
            self.equal_matrix(self.rows[a], self.rows[b])
            self.witnesses_inside(self.rows[a])
        self.assertTrue(self.rows["nil-only"]["present"])

    def test_equivalent_parent_trs_and_identity_free_payload(self):
        self.equal_matrix(self.rows["renamed-Ω"], self.rows["base"])
        for actual, expected in zip(self.rows["parent-translation-equivalent"]["witnessClip"],
                                    self.rows["base"]["witnessClip"]):
            for a, b in zip(actual, expected):
                self.assertLessEqual(abs(a-b), 1e-5)
        self.witnesses_inside(self.rows["parent-translation-equivalent"])


if __name__ == "__main__":
    unittest.main()
