"""Local composition background, bounds and root-effect visibility.

The pixel oracle is fixed independently of captures. App execution, PNG parsing,
hash freezing, isolated HOME and evidence retention reuse the authored-order
integration gate. These owned solids qualify the bounded local-source profile;
they do not infer the official client's algorithm for effect-bearing groups.
Top-level passthrough cases additionally exercise an owned root Program through
the existing live-effect runner; planner admission alone never proves a Program.
Ordinary background groups additionally use a spatial root Program: its local
UV mirror must exchange two markers, not merely remove out-of-bounds pixels.
"""

from __future__ import annotations

import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import unittest
from unittest.mock import patch

from script.tests import test_scene_composition_authored_order_integration as app_fixture
from script.tests import test_scene_composition_source_identity as source_fixture
from script.tests import test_scene_fullscreen_visibility_integration as visibility_fixture


PLANNER_HARNESS = source_fixture.HARNESS.split("@main", 1)[0] + r'''
@main
enum BackgroundLocalPlannerProbe {
    static func main() throws {
        func probe(_ rootID: Int = 20, _ childID: Int = 21,
                   copy: Bool = true, effects: [SceneRenderDescriptor.EffectDescriptor] = [],
                   childEffects: [SceneRenderDescriptor.EffectDescriptor] = [],
                   ortho: Bool = true, perspective: Bool = false,
                   passthrough: Bool = false, childKind: String = "solid",
                   dependencies: [Int] = [], admitted: Bool = false,
                   nested: Bool = false, nestedBackground: Bool = false,
                   nestedPassthrough: Bool = false) -> [String: Any] {
            var utility = SceneUtilityLayer(kind: .composition)
            utility.copyBackground = copy
            utility.passthrough = passthrough
            var root = SceneRenderDescriptor.Layer(parentID: nested ? 900 : nil,
                id: rootID, contentKind: "composition",
                utilityLayer: utility, dependencyLayerIDs: dependencies,
                childLayerIDs: [childID], visible: true, effects: effects)
            root.usesPerspective = perspective
            var childUtility: SceneUtilityLayer?
            let populatedChildUtility = nestedBackground || nestedPassthrough
            if populatedChildUtility {
                var composition = SceneUtilityLayer(kind: .composition)
                composition.copyBackground = nestedBackground
                composition.passthrough = nestedPassthrough
                childUtility = composition
            }
            let child = SceneRenderDescriptor.Layer(parentID: rootID, id: childID,
                contentKind: populatedChildUtility ? "composition" : childKind,
                utilityLayer: childUtility, dependencyLayerIDs: [],
                childLayerIDs: populatedChildUtility ? [childID + 100] : [],
                visible: true, effects: childEffects)
            // Array order is deliberately different from the authored order.
            var layers = [child, root]
            var order = [rootID, childID]
            if populatedChildUtility {
                layers.append(SceneRenderDescriptor.Layer(parentID: childID,
                    id: childID + 100, contentKind: "solid", utilityLayer: nil,
                    dependencyLayerIDs: [], childLayerIDs: [], visible: true, effects: []))
                order.append(childID + 100)
            }
            if nested {
                var parentUtility = SceneUtilityLayer(kind: .composition)
                parentUtility.copyBackground = false
                let inner = SceneRenderDescriptor.Layer(parentID: 901, id: 900,
                    contentKind: "composition", utilityLayer: parentUtility,
                    dependencyLayerIDs: [], childLayerIDs: [rootID], visible: true, effects: [])
                let outer = SceneRenderDescriptor.Layer(id: 901,
                    contentKind: "composition", utilityLayer: parentUtility,
                    dependencyLayerIDs: [], childLayerIDs: [900], visible: true, effects: [])
                layers = [child, root, inner, outer]
                order = [childID, 901, rootID, 900]
            }
            var descriptor = SceneRenderDescriptor(layers: layers, renderOrderLayerIDs: order)
            descriptor.camera.authoredOrthographicProjectionActive = ortho
            let plans = SceneUtilityLayerRuntimePlanner.plans(in: descriptor,
                resolvedMaterialLayerIDs: admitted ? [rootID] : [])
            let execution = SceneUtilityLayerRuntimePlanner.execution(in: descriptor, plans: plans)
            let plan = plans[rootID]!
            var fact: [String: Any] = ["root": rootID, "child": childID,
                "disposition": plan.disposition.rawValue,
                "local": plan.usesAuthoredLocalSource,
                "captureRoots": execution.captureLayerIDs.sorted(),
                "localRoots": execution.localSourceRootIDs.sorted(),
                "backgroundRoots": execution.copyBackgroundRootIDs.sorted(),
                "members": execution.membersByRootID[rootID] ?? [],
                "childOwner": execution.memberRootsByLayerID[childID] ?? -1,
                "order": execution.orderedLayerIDs]
            if nestedPassthrough {
                fact["nestedDisposition"] = plans[childID]!.disposition.rawValue
                fact["grandchildOwner"] = execution.memberRootsByLayerID[childID + 100] ?? -1
            }
            return fact
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
            "unprepared-visible-effect": probe(effects: [visible]),
            "nested-background-viewport": probe(effects: [hidden], admitted: true,
                nestedBackground: true),
            "background-effect-nested-passthrough": probe(effects: [visible], admitted: true,
                nestedPassthrough: true),
            "transparent-effect-nested-passthrough": probe(copy: false, effects: [visible],
                admitted: true, nestedPassthrough: true),
            "background-no-effect-nested-passthrough": probe(nestedPassthrough: true),
            "nested-passthrough-own-effect": probe(effects: [visible], childEffects: [visible],
                admitted: true, nestedPassthrough: true),
            "not-orthographic": probe(ortho: false),
            "perspective": probe(perspective: true),
            "passthrough-no-effect": probe(passthrough: true),
            "passthrough-renamed": probe(709, 218, copy: false, passthrough: true),
            "passthrough-hidden-effect": probe(effects: [hidden], passthrough: true, admitted: true),
            "passthrough-visible-effect": probe(effects: [visible], passthrough: true, admitted: true),
            "passthrough-unprepared-visible-effect": probe(effects: [visible], passthrough: true),
            "passthrough-not-orthographic": probe(ortho: false, passthrough: true),
            "passthrough-perspective": probe(perspective: true, passthrough: true),
            "passthrough-model-member": probe(passthrough: true, childKind: "model"),
            "passthrough-particle-member": probe(passthrough: true, childKind: "particle"),
            "passthrough-external-dependency": probe(passthrough: true, dependencies: [901]),
            "nested-passthrough-structural": probe(copy: false, passthrough: true, nested: true),
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

    def test_ordinary_root_effect_seeds_keep_the_admitted_local_source(self):
        # The unprepared hidden case has no admitted material Program. Capture
        # proves only its source route; the App spatial cases below prove FX.
        for name in ("hidden-authored-effect", "visible-authored-effect",
                     "unprepared-hidden-effect"):
            with self.subTest(case=name):
                value = self.facts[name]
                self.assertEqual(value["disposition"], "capture", value)
                self.assertTrue(value["local"], value)
                self.assertEqual(value["localRoots"], [20], value)
                self.assertEqual(value["captureRoots"], [20], value)
                self.assertEqual(value["backgroundRoots"], [20], value)
                self.assertEqual(value["members"], [21], value)
                self.assertEqual(value["childOwner"], 20, value)

    def test_top_level_passthrough_plans_keep_one_local_source_for_all_effect_seeds(self):
        # admitted is a planner input, not a fabricated compile/Program result.
        for name, root, child, copies in (
                ("passthrough-no-effect", 20, 21, True),
                ("passthrough-renamed", 709, 218, False),
                ("passthrough-hidden-effect", 20, 21, True),
                ("passthrough-visible-effect", 20, 21, True)):
            with self.subTest(case=name):
                self.assertEqual(self.facts[name], {
                    "root": root, "child": child, "disposition": "capture", "local": True,
                    "captureRoots": [root], "localRoots": [root],
                    "backgroundRoots": [root] if copies else [], "members": [child],
                    "childOwner": root, "order": [child, root]})

    def test_unprepared_visible_effect_does_not_gain_execution(self):
        for name in ("unprepared-visible-effect", "passthrough-unprepared-visible-effect"):
            with self.subTest(case=name):
                value = self.facts[name]
                self.assertTrue(value["local"], value)
                self.assertEqual(value["disposition"], "unsupportedEffects", value)
                self.assertEqual(value["captureRoots"], [], value)
                self.assertEqual(value["localRoots"], [], value)
                self.assertEqual(value["members"], [], value)

    def test_populated_nested_background_keeps_its_existing_viewport_owner(self):
        value = self.facts["nested-background-viewport"]
        self.assertFalse(value["local"], value)
        self.assertNotIn(20, value["localRoots"], value)
        self.assertEqual(value["disposition"], "capture", value)
        self.assertIn(20, value["captureRoots"], value)

    def test_nested_passthrough_remains_a_structural_member_not_a_new_owner(self):
        value = self.facts["nested-passthrough-structural"]
        self.assertEqual(value["disposition"], "skippedNoEffect", value)
        self.assertFalse(value["local"], value)
        self.assertEqual(value["captureRoots"], [900, 901], value)
        self.assertEqual(value["localRoots"], [900, 901], value)
        self.assertEqual(value["members"], [], value)
        self.assertEqual(value["childOwner"], 900, value)
        self.assertEqual(value["order"], [21, 20, 900, 901], value)
        for name, copies in (("background-effect-nested-passthrough", True),
                             ("transparent-effect-nested-passthrough", False),
                             ("background-no-effect-nested-passthrough", True)):
            with self.subTest(case=name):
                self.assertEqual(self.facts[name], {
                    "root": 20, "child": 21, "disposition": "capture", "local": True,
                    "captureRoots": [20], "localRoots": [20],
                    "backgroundRoots": [20] if copies else [], "members": [21, 121],
                    "childOwner": 20, "grandchildOwner": 20,
                    "nestedDisposition": "skippedNoEffect", "order": [21, 121, 20]})
        value = self.facts["nested-passthrough-own-effect"]
        self.assertEqual(value["disposition"], "unsupportedChildren", value)
        self.assertEqual(value["nestedDisposition"], "unsupportedChildren", value)
        self.assertFalse(value["local"], value)
        for key in ("captureRoots", "localRoots", "backgroundRoots", "members"):
            self.assertEqual(value[key], [], value)
        self.assertEqual((value["childOwner"], value["grandchildOwner"]), (-1, -1), value)

    def test_neighboring_unqualified_profiles_do_not_gain_local_capture(self):
        for name in ("not-orthographic", "perspective",
                     "model-member", "particle-member", "external-dependency",
                     "passthrough-not-orthographic", "passthrough-perspective",
                     "passthrough-model-member", "passthrough-particle-member",
                     "passthrough-external-dependency"):
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


def ordinary_root_program_fixture(*, enabled):
    """An off-center local UV mirror, using the existing owned effect schema."""
    solid_path = "models/owned-local-uv-card.json"

    def solid(layer_id, center, size, color, **extra):
        return {"id": layer_id, "name": f"Owned local UV marker {layer_id}",
                "image": solid_path, "origin": f"{center[0]} {center[1]} 0",
                "size": f"{size[0]} {size[1]}", "color": color,
                "alpha": 1, "visible": True, **extra}

    background = solid(1, (128, 128), (256, 256), "0 0 1")
    root = {"id": 20, "name": "Owned ordinary local UV root",
            "image": "models/util/composelayer.json", "origin": "112 120 0",
            "size": "96 80", "config": {"passthrough": False},
            "copybackground": True, "alpha": 1, "visible": True,
            "effects": [{"id": 200, "file": "effects/own_flip_x/effect.json",
                         "visible": enabled}]}
    # Root source X spans 64...160: these centers are UV .25 and .75.
    red = solid(21, (-24, 0), (12, 12), "1 0 0", parent=20)
    green = solid(22, (24, 0), (12, 12), "0 1 0", parent=20)
    center = solid(23, (0, 0), (12, 12), "0 1 1", parent=20)
    outside_x = solid(24, (0, 28), (160, 12), "1 0 1", parent=20)
    outside_y = solid(25, (0, 56), (160, 12), "1 1 0", parent=20)
    later = solid(30, (208, 184), (12, 12), "1 1 1")
    scene = {"version": 3, "general": {
        "orthogonalprojection": {"width": 256, "height": 256},
        "clearcolor": "0 0 0"},
        "objects": [background, root, later, red, green, center, outside_x, outside_y]}
    _, template = app_fixture.fixture_entries(effect=True)
    entries = {name.replace("own_invert", "own_flip_x"):
               data.replace(b"own_invert", b"own_flip_x")
               for name, data in template.items()
               if name.startswith(("effects/", "materials/", "shaders/"))}
    entries.update({"scene.json": app_fixture.encoded(scene),
        solid_path: app_fixture.encoded({"solidlayer": True, "width": 256, "height": 256}),
        "models/util/composelayer.json": app_fixture.encoded(
            {"width": 96, "height": 80, "autosize": False}),
        "shaders/own_flip_x.frag": (
            b"uniform sampler2D g_Texture0;\nvarying vec2 v_TexCoord;\n"
            b"void main(){gl_FragColor=texSample2D(g_Texture0,"
            b"vec2(1.0-v_TexCoord.x,v_TexCoord.y));}\n")})
    return {"type": "scene", "file": "scene.json"}, entries


def ordinary_root_program_preregistration(*, enabled):
    """Fixed canvas ROI colors; no source-geometry resolver or image fitting."""
    # PNG Y=256-authoredY. A viewport mirror is about X=128, while this
    # root's local mirror is about X=112, so it cannot pass the swap oracle.
    points = {
        "source_uv_quarter": ((88, 136), (0, 255, 0) if enabled else (255, 0, 0)),
        "source_uv_three_quarters": ((136, 136), (255, 0, 0) if enabled else (0, 255, 0)),
        "source_center": ((112, 136), (0, 255, 255)),
        "source_inside_x_stripe": ((148, 108), (255, 0, 255)),
        "outside_root_x_positive": ((176, 108), (0, 0, 255)),
        "outside_root_x_negative": ((48, 108), (0, 0, 255)),
        "outside_root_y_marker": ((112, 80), (0, 0, 255)),
        "later_peer_stays_front": ((208, 72), (255, 255, 255)),
        "healthy_background": ((208, 136), (0, 0, 255)),
    }
    return {"canvas": app_fixture.CANVAS,
        "parameters": {"passthrough": False, "copybackground": True,
                       "rootCenter": [112, 120], "rootSize": [96, 80],
                       "rootAlpha": 1, "rootAuthoredEffectCount": 1,
                       "rootEffectEnabled": enabled},
        "oracle": {name: {"canvasRect": (x - 3, y - 3, x + 3, y + 3),
                          "expectedRGB": color} for name, ((x, y), color) in points.items()},
        "channelTolerance": app_fixture.CHANNEL_TOLERANCE,
        "minimumCorrectAreaFraction": app_fixture.MINIMUM_CORRECT_FRACTION,
        "captureMapping": "existing centered orthographic 256x256 cover mapping",
        "evidenceBoundary": "owned ordinary local source and actual horizontal-UV Program; not official internal FBO, nonlinear RGB or full parity",
        "oracleSourceSHA256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest()}


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

    def run_ordinary_root_program(self, *, enabled):
        source_digest = hashlib.sha256(Path(__file__).read_bytes()).hexdigest()
        project, entries = ordinary_root_program_fixture(enabled=enabled)
        protocol = ordinary_root_program_preregistration(enabled=enabled)
        with patch.object(app_fixture, "fixture_entries", return_value=(project, entries)), \
                patch.object(app_fixture, "preregistration", return_value=protocol):
            result = app_fixture.SceneCompositionAuthoredOrderIntegrationTests.run_case(
                self, effect=True, enabled=enabled)
        log, _ = result
        encoded_frames = set(re.findall(
            r"axis=effect-cpu-invocation frame=(\d+) [^\n]*\blayer=20 effect=0 "
            r"[^\n]*\boutcome=encoded-output\b", log))
        if enabled:
            completed_frames = set(re.findall(
                r"phase=surface-submission state=completed frame=(\d+) "
                r"surface=\d+ gpu=completed\b", log))
            self.assertTrue(encoded_frames & completed_frames,
                            "root Program must encode and complete on the same frame")
        else:
            self.assertFalse(encoded_frames, "disabled root Program must not encode")
        self.assertEqual(hashlib.sha256(Path(__file__).read_bytes()).hexdigest(), source_digest)
        return result

    def test_ordinary_hidden_root_effect_captures_local_source_and_clips_both_axes(self):
        self.run_ordinary_root_program(enabled=False)

    def test_ordinary_active_root_program_mirrors_local_uv_and_clips_both_axes(self):
        self.run_ordinary_root_program(enabled=True)


def passthrough_fixture(*, renamed=False, initial_visible=False):
    """Use the existing local solids plus the existing owned invert Program."""
    project, entries = fixture_entries(copy_background=True)
    scene = json.loads(entries["scene.json"])
    root = next(row for row in scene["objects"] if row["id"] == 20)
    key = "renamed_filter_enabled" if renamed else "filter_enabled"
    root["config"]["passthrough"] = True
    root["effects"] = [{"id": 200, "file": "effects/own_invert/effect.json",
                        "visible": {"user": key, "value": initial_visible}}]
    _, effect_entries = app_fixture.fixture_entries(effect=True)
    entries.update({name: data for name, data in effect_entries.items()
                    if name.startswith(("effects/", "materials/", "shaders/"))})
    project["general"] = {"properties": {key: {"type": "bool", "value": initial_visible}}}
    if renamed:
        ids = {10: 405, 21: 618, 22: 902, 30: 701}
        for row in scene["objects"]:
            row["id"] = ids.get(row["id"], row["id"])
            row["name"] = f"Unseen local-source object {row['id']}"
            if row.get("image") == "models/owned-bounds-solid.json":
                row["image"] = "models/another-plain-card.json"
        entries["models/another-plain-card.json"] = entries.pop("models/owned-bounds-solid.json")
        # Both children precede the root in the authored array; the root's
        # cut point remains after the prior peer and before the healthy peer.
        by_id = {row["id"]: row for row in scene["objects"]}
        scene["objects"] = [by_id[value] for value in (1, 2, 3, 405, 618, 902, 20, 701)]
    entries["scene.json"] = app_fixture.encoded(scene)
    if renamed:
        entries = {name.replace("own_invert", "unseen_local_filter"):
                   data.replace(b"own_invert", b"unseen_local_filter") for name, data in entries.items()}
    protocol = passthrough_preregistration(renamed=renamed, initial_visible=initial_visible)
    entries["owned-local-passthrough-oracle.json"] = app_fixture.encoded(protocol)
    return project, entries, protocol, key


def passthrough_preregistration(*, renamed=False, initial_visible=False):
    """Same background/member arithmetic, with one root RGB inversion."""
    protocol = preregistration(copy_background=True)
    hidden = protocol["oracle"]
    hidden["plain_child_second_patch"] = {
        "canvasRect": (105, 116, 111, 122), "expectedRGB": (64, 0, 191)}
    # Invert the composed local source once, retaining its alpha; the root's
    # .5 alpha then composites once over the original opaque framebuffer.
    active_colors = {
        "background_x_position": (128, 128, 128),
        "background_y_position": (128, 128, 128),
        "background_other_region": (128, 128, 128),
        "half_alpha_overlap": (96, 64, 223),
        "red_only_alpha": (64, 128, 191),
        "plain_child_second_patch": (64, 128, 191),
        "green_only_alpha": (128, 64, 191),
        "prior_peer_enters_background": (96, 159, 223),
    }
    active = {name: dict(row, expectedRGB=active_colors.get(name, row["expectedRGB"]))
              for name, row in hidden.items()}
    protocol.update(
        parameters=dict(protocol["parameters"], passthrough=True, renamed=renamed,
                        rootAuthoredEffectCount=1, effectInitiallyVisible=initial_visible),
        oracle=active if initial_visible else hidden,
        snapshotOracles={"scene-ready-window.png": active if initial_visible else hidden,
                         "scene-series-0002-window.png": hidden if initial_visible else active,
                         "scene-after-window.png": active if initial_visible else hidden},
        effectSequence=[initial_visible, not initial_visible, initial_visible],
        transparentHole="No child covers the two background_position patches; copied background must retain its authored source position before the root FX.",
        evidenceBoundary="owned top-level passthrough local source, completed invert Program and typed Bool roundtrip; no official spatial/alpha parity")
    return protocol


class SceneCompositionPassthroughEffectBoundsIntegrationTests(unittest.TestCase):
    setUpClass = classmethod(visibility_fixture.SceneFullscreenVisibilityIntegrationTests.setUpClass.__func__)

    def run_passthrough(self, *, renamed=False, initial_visible=False):
        source_digest = hashlib.sha256(Path(__file__).read_bytes()).hexdigest()
        project, entries, protocol, key = passthrough_fixture(
            renamed=renamed, initial_visible=initial_visible)
        # The existing live-effect runner owns App identity, isolated HOME,
        # property acknowledgements, same surface/window, actual Program/GPU,
        # three settled snapshots, hash checks, cleanup and optional retention.
        # Its three smoke ROIs are a subset of this fixture's fixed full oracle.
        rects = {"background": protocol["oracle"]["red_only_alpha"]["canvasRect"],
                 "child": protocol["oracle"]["plain_child_second_patch"]["canvasRect"],
                 "nonchild": protocol["oracle"]["later_peer_stays_front"]["canvasRect"]}

        def measure(path, _smoke_protocol):
            return app_fixture.measure_capture(path, protocol)

        with patch.object(visibility_fixture, "fixture_entries", return_value=(project, entries)), \
                patch.object(visibility_fixture, "measure_capture", side_effect=measure), \
                patch.object(visibility_fixture, "RECTS", rects), \
                patch.object(visibility_fixture, "WHITE", (64, 0, 191)), \
                patch.object(visibility_fixture, "GRAY", (64, 128, 191)), \
                patch.object(visibility_fixture, "GREEN", (255, 255, 255)):
            result = visibility_fixture.SceneFullscreenVisibilityIntegrationTests.run_case(
                self, inactive_effect=not initial_visible, launch={key: initial_visible},
                sequence=[{key: not initial_visible}, {key: initial_visible}],
                expected_dims=[not initial_visible, initial_visible])
        self.assertEqual(hashlib.sha256(Path(__file__).read_bytes()).hexdigest(), source_digest)
        return result

    def test_top_level_passthrough_effect_roundtrip_keeps_local_background_holes_and_bounds(self):
        self.run_passthrough()

    def test_renamed_reordered_passthrough_effect_uses_the_same_source_and_single_output(self):
        self.run_passthrough(renamed=True)

    def test_initially_active_passthrough_effect_roundtrip_keeps_the_same_local_source(self):
        self.run_passthrough(initial_visible=True)


if __name__ == "__main__":
    unittest.main()
