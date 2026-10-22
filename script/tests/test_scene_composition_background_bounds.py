"""No authored root effects: copied local background, bounds and one output.

The pixel oracle is fixed independently of captures. App execution, PNG parsing,
hash freezing, isolated HOME and evidence retention reuse the authored-order
integration gate. These owned solids qualify the bounded local-source profile;
they do not infer the official client's algorithm for effect-bearing groups.
"""

from __future__ import annotations

import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest
from unittest.mock import patch

from script.tests import test_scene_composition_authored_order_integration as app_fixture
from script.tests import test_scene_composition_source_identity as source_fixture


PLANNER_HARNESS = source_fixture.HARNESS.split("@main", 1)[0] + r'''
@main
enum BackgroundLocalPlannerProbe {
    static func main() throws {
        func probe(_ rootID: Int = 20, _ childID: Int = 21,
                   copy: Bool = true, effects: [SceneRenderDescriptor.EffectDescriptor] = [],
                   childEffects: [SceneRenderDescriptor.EffectDescriptor] = [],
                   ortho: Bool = true, perspective: Bool = false,
                   passthrough: Bool = false, childKind: String = "solid",
                   dependencies: [Int] = [], admitted: Bool = false) -> [String: Any] {
            var utility = SceneUtilityLayer(kind: .composition)
            utility.copyBackground = copy
            utility.passthrough = passthrough
            var root = SceneRenderDescriptor.Layer(id: rootID, contentKind: "composition",
                utilityLayer: utility, dependencyLayerIDs: dependencies,
                childLayerIDs: [childID], visible: true, effects: effects)
            root.usesPerspective = perspective
            let child = SceneRenderDescriptor.Layer(parentID: rootID, id: childID,
                contentKind: childKind, utilityLayer: nil, dependencyLayerIDs: [],
                childLayerIDs: [], visible: true, effects: childEffects)
            // Array order is deliberately different from the authored order.
            var descriptor = SceneRenderDescriptor(layers: [child, root],
                renderOrderLayerIDs: [rootID, childID])
            descriptor.camera.authoredOrthographicProjectionActive = ortho
            let plans = SceneUtilityLayerRuntimePlanner.plans(in: descriptor,
                resolvedMaterialLayerIDs: admitted ? [rootID] : [])
            let execution = SceneUtilityLayerRuntimePlanner.execution(in: descriptor, plans: plans)
            let plan = plans[rootID]!
            return ["root": rootID, "child": childID,
                "disposition": plan.disposition.rawValue,
                "local": plan.usesAuthoredLocalSource,
                "captureRoots": execution.captureLayerIDs.sorted(),
                "localRoots": execution.localSourceRootIDs.sorted(),
                "backgroundRoots": execution.copyBackgroundRootIDs.sorted(),
                "members": execution.membersByRootID[rootID] ?? [],
                "childOwner": execution.memberRootsByLayerID[childID] ?? -1,
                "order": execution.orderedLayerIDs]
        }
        let hidden = SceneRenderDescriptor.EffectDescriptor(id: "own-hidden",
            file: "effects/renamed-inactive-filter.json", visible: false, passes: [])
        let visible = SceneRenderDescriptor.EffectDescriptor(id: "own-visible",
            file: "effects/another-filter.json", visible: true, passes: [])
        let facts: [String: [String: Any]] = [
            "background": probe(),
            "renamed": probe(709, 218),
            "transparent": probe(copy: false),
            "child-effect": probe(childEffects: [visible]),
            "hidden-authored-effect": probe(effects: [hidden], admitted: true),
            "unprepared-hidden-effect": probe(effects: [hidden]),
            "visible-authored-effect": probe(effects: [visible], admitted: true),
            "not-orthographic": probe(ortho: false),
            "perspective": probe(perspective: true),
            "passthrough": probe(passthrough: true),
            "model-member": probe(childKind: "model"),
            "particle-member": probe(childKind: "particle"),
            "external-dependency": probe(dependencies: [901]),
        ]
        print(String(decoding: try JSONSerialization.data(withJSONObject: facts,
            options: [.sortedKeys]), as: UTF8.self))
    }
}
'''


class SceneCompositionBackgroundPlannerTests(unittest.TestCase):
    """Actual SourceRoute/Planner/membership; no Metal device is created."""

    @classmethod
    def setUpClass(cls):
        if shutil.which("swiftc") is None:
            raise unittest.SkipTest("swiftc unavailable")
        cls.temporary_directory = tempfile.TemporaryDirectory(prefix="mwx-background-planner-")
        cls.addClassCleanup(cls.temporary_directory.cleanup)
        root = Path(cls.temporary_directory.name)
        harness = root / "Harness.swift"
        harness.write_text(PLANNER_HARNESS, encoding="utf-8")
        binary = root / "probe"
        subprocess.run(
            ["xcrun", "--sdk", "macosx", "swiftc",
             "-D", "SCENE_ACTUAL_COMPOSITION_TARGETS",
             "-D", "SCENE_ACTUAL_COMPOSITION_SOURCE_ROUTE",
             *(str(path) for path in source_fixture.SWIFT_SOURCES), str(harness),
             "-module-cache-path", str(root / "module-cache"), "-framework", "Metal",
             "-o", str(binary)],
            check=True, capture_output=True, text=True)
        result = subprocess.run([str(binary)], check=True, capture_output=True, text=True)
        cls.facts = json.loads(result.stdout)

    def test_background_no_effect_source_is_captured_without_a_material_program(self):
        for name, root, child, copies in (("background", 20, 21, True),
                                         ("renamed", 709, 218, True),
                                         ("transparent", 20, 21, False),
                                         ("child-effect", 20, 21, True)):
            with self.subTest(case=name):
                self.assertEqual(self.facts[name], {
                    "root": root, "child": child, "disposition": "capture", "local": True,
                    "captureRoots": [root], "localRoots": [root],
                    "backgroundRoots": [root] if copies else [], "members": [child],
                    "childOwner": root, "order": [child, root]})

    def test_any_authored_root_effect_keeps_the_prepared_viewport_background_path(self):
        for name in ("hidden-authored-effect", "visible-authored-effect"):
            with self.subTest(case=name):
                value = self.facts[name]
                self.assertEqual(value["disposition"], "capture", value)
                self.assertFalse(value["local"], value)
                self.assertEqual(value["localRoots"], [], value)
                self.assertEqual(value["captureRoots"], [20], value)
                self.assertEqual(value["backgroundRoots"], [20], value)
                self.assertEqual(value["members"], [21], value)
                self.assertEqual(value["childOwner"], 20, value)

    def test_neighboring_unqualified_profiles_do_not_gain_local_capture(self):
        for name in ("unprepared-hidden-effect", "not-orthographic", "perspective",
                     "passthrough", "model-member", "particle-member", "external-dependency"):
            with self.subTest(case=name):
                value = self.facts[name]
                self.assertFalse(value["local"], value)
                self.assertEqual(value["localRoots"], [], value)
                self.assertEqual(value["captureRoots"], [], value)
                self.assertEqual(value["members"], [], value)
                self.assertEqual(value["childOwner"], -1, value)


def _authored_point(local, quarter_turn):
    """Place an authored Y-up point; convert to PNG canvas only in the oracle."""
    x, y = local
    return (128 - y, 128 + x) if quarter_turn else (128 + x, 128 + y)


def fixture_entries(*, copy_background=None, renamed=False, quarter_turn=False):
    if copy_background is not None and not isinstance(copy_background, bool):
        raise ValueError("copy_background must be omitted, false, or true")
    ids = (709, 218, 901, 73, 307) if renamed else (20, 21, 22, 10, 30)
    root_id, red_id, green_id, prior_id, later_id = ids
    solid_path = "models/renamed-color-card.json" if renamed else "models/owned-bounds-solid.json"

    def solid(layer_id, center, size, color, **extra):
        return {"id": layer_id, "name": f"Owned renamed card {layer_id}" if renamed else f"Owned card {layer_id}",
                "image": solid_path, "origin": f"{center[0]} {center[1]} 0",
                "size": f"{size[0]} {size[1]}", "color": color, "visible": True, **extra}

    background = [solid(1, (128, 128), (256, 256), "0 0 1"),
                  solid(2, (48, 128), (96, 256), "0 1 0"),
                  solid(3, (128, 48), (256, 96), "1 1 0")]
    prior = solid(prior_id, _authored_point((32, 0), quarter_turn), (16, 16), "0 1 1")
    later = solid(later_id, _authored_point((-32, 0), quarter_turn), (8, 8), "1 1 1")
    root = {"id": root_id, "name": "Renamed local background root" if renamed else "Owned local background root",
            "image": "models/util/composelayer.json", "origin": "128 128 0", "size": "96 80",
            "config": {"passthrough": False}, "alpha": .5, "visible": True}
    if copy_background is not None:
        root["copybackground"] = copy_background
    if quarter_turn:
        root["angles"] = "0 0 1.5707963267948966"
    red = solid(red_id, (0, 0), (160, 32), "1 0 0", parent=root_id, alpha=.5)
    green = solid(green_id, (16, 0), (48, 120), "0 1 0", parent=root_id, alpha=.5)
    # The root's authored cut point stays between the prior and later peers;
    # child placement on either side must produce the same ordered group.
    objects = background + [prior] + ([red, green, root, later] if renamed
                                      else [root, later, red, green])
    # These ordinary, opaque producers are independent of the composition.
    # Two asymmetric anchors qualify Y orientation; a plain transform parent
    # and off-axis child independently qualify the radians/rotation sign.
    if quarter_turn:
        angle_parent = solid(6003, (204, 128), (2, 2), "1 1 1", angles="0 0 1.5707963267948966")
        angle_child = solid(6004, (16, 0), (10, 10), "1 0 1", parent=6003)
        objects += [solid(6001, (60, 68), (10, 10), "1 0 0"),
                    solid(6002, (196, 188), (10, 10), "0 1 1"), angle_parent, angle_child]
    scene = {"version": 3,
             "general": {"orthogonalprojection": {"width": 256, "height": 256},
                         "clearcolor": "0 0 0"}, "objects": objects}
    return {"type": "scene", "file": "scene.json"}, {
        "scene.json": app_fixture.encoded(scene),
        solid_path: app_fixture.encoded({"solidlayer": True, "width": 256, "height": 256}),
        "models/util/composelayer.json": app_fixture.encoded(
            {"width": 96, "height": 80, "autosize": False})}


def preregistration(*, copy_background=None, renamed=False, quarter_turn=False):
    """Fixed source-over arithmetic and points; never adjusted to captures."""
    if copy_background is False:
        raise ValueError("this pixel gate qualifies copied background only")
    # RGB checks on opaque background expose root/child alpha applied twice.
    # overlap: .5 * (.5*green + .5*(.5*red + .5*blue)) + .5*blue.
    points = {
        "background_x_position": ((-20, 28), (0, 0, 255)),
        "background_y_position": ((-20, -24), (0, 0, 255)),
        "background_other_region": ((-40, 28), (255, 255, 0) if quarter_turn else (0, 255, 0)),
        "half_alpha_overlap": ((12, 0), (32, 64, 159)),
        "red_only_alpha": ((-20, 0), (64, 0, 191)),
        "green_only_alpha": ((20, 28), (0, 64, 191)),
        "outside_root_x_inside_red": ((64, 0), (0, 0, 255)),
        "outside_root_y_inside_green": ((16, 52), (0, 255, 0) if quarter_turn else (0, 0, 255)),
        "outside_both_healthy_background": ((64, 52), (0, 255, 0) if quarter_turn else (0, 0, 255)),
        "prior_peer_enters_background": ((32, 0), (32, 223, 159)),
        "later_peer_stays_front": ((-32, 0), (255, 255, 255)),
    }
    # Independent explicit canvas rectangles, not derived through the group
    # placement helper. PNG Y=256-authoredY; parent Rz(+pi/2)*(16,0)=(0,16).
    oracle = {
        "geometry_authored_low_y_anchor": {"canvasRect": (57, 185, 63, 191), "expectedRGB": (255, 0, 0)},
        "geometry_authored_high_y_anchor": {"canvasRect": (193, 65, 199, 71), "expectedRGB": (0, 255, 255)},
        "geometry_radian_parent_child": {"canvasRect": (201, 109, 207, 115), "expectedRGB": (255, 0, 255)},
    } if quarter_turn else {}
    geometry_controls = tuple(oracle)
    for name, (local, expected) in points.items():
        x, y = _authored_point(local, quarter_turn)
        # WorldFrame maps authored Y to H-Y; orthographic projection has
        # bottom=+halfY/top=-halfY, so Metal PNG Y follows renderer-world Y.
        # measure_capture only applies centered cover scaling, with no flip.
        oracle[name] = {"canvasRect": (x - 3, 256 - y - 3, x + 3, 256 - y + 3),
                        "expectedRGB": expected}
    protocol = {"canvas": app_fixture.CANVAS,
            "parameters": {"copybackground": "omitted" if copy_background is None else copy_background,
                           "renamed": renamed, "quarterTurn": quarter_turn,
                           "rootSize": [96, 80], "rootAlpha": .5, "childAlphas": [.5, .5],
                           "rootAuthoredEffectCount": 0},
            "oracle": oracle, "channelTolerance": app_fixture.CHANNEL_TOLERANCE,
            "minimumCorrectAreaFraction": app_fixture.MINIMUM_CORRECT_FRACTION,
            "captureMapping": "existing centered orthographic 256x256 cover mapping",
            "alphaBoundary": "opaque framebuffer RGB response tests authored alpha once; no direct alpha-channel readback",
            "evidenceBoundary": "owned no-root-effect local background group; not passthrough or effect-bearing parity",
            "oracleSourceSHA256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest()}
    if quarter_turn:
        protocol.update(
            geometryControls=geometry_controls,
            qualificationBoundary="any geometry-control failure invalidates this capture for all group-behavior claims",
            coordinateContract="authored Rz(+theta) in radians; renderer world Y=256-authoredY; PNG canvas Y=renderer world Y")
    return protocol


class SceneCompositionBackgroundBoundsIntegrationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        app_fixture.SceneCompositionAuthoredOrderIntegrationTests.setUpClass.__func__(cls)

    def run_fixture(self, **parameters):
        # Reuse the runner as-is. Only its owned-input/oracle providers differ;
        # its PNG parser, lifecycle assertions, hashes and cleanup stay shared.
        project, entries = fixture_entries(**parameters)
        protocol = preregistration(**parameters)
        with patch.object(app_fixture, "fixture_entries", return_value=(project, entries)), \
                patch.object(app_fixture, "preregistration", return_value=protocol):
            return app_fixture.SceneCompositionAuthoredOrderIntegrationTests.run_case(self, effect=False)

    def test_omitted_background_uses_local_pixels_and_clips_both_axes(self):
        self.run_fixture()

    def test_true_background_renamed_quarter_turn_keeps_source_axes_and_order(self):
        self.run_fixture(copy_background=True, renamed=True, quarter_turn=True)


if __name__ == "__main__":
    unittest.main()
