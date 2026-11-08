"""Layer color Timeline inputs and assertions for the real compiler/runtime harness."""

import copy


FIRST = [0.25, 0.5, 0.75]
SECOND = [0.75, 0.25, 0.5]
AUTHORED = [0.125, 0.25, 0.5]


def layer_color_cases():
    for renamed in (False, True):
        layer_id = 731 if renamed else 120
        color = {"value": AUTHORED if renamed else "0.125 0.25 0.5", "animation": {
            **{f"c{i}": [{"frame": 0, "value": start},
                         {"frame": 30, "value": end}]
               for i, (start, end) in enumerate(zip(FIRST, SECOND))},
            "options": {"fps": 30, "length": 60, "mode": "loop",
                        "name": "renamedTintCurve" if renamed else "videoTintCurve"}}}
        alpha = {"value": 1, "animation": {"c0": [{"frame": 0, "value": 0.25},
                                                   {"frame": 30, "value": 0.75}],
                                            "options": {"fps": 30, "length": 60, "mode": "loop"}}}
        layer = {"id": layer_id, "name": "renamed tint" if renamed else "video tint",
                 "image": "models/renamed/media-card.json" if renamed else "models/user/video.json",
                 "color": color, "alpha": alpha}
        if renamed:
            layer = dict(reversed(list(layer.items())))
        scene = {"version": 3, "objects": [layer]}
        expected = {"id": layer_id, "authored": AUTHORED}
        suffix = "renamed" if renamed else "original"
        yield suffix, scene, expected
        missing = copy.deepcopy(scene)
        del missing["objects"][0]["color"]["value"]
        yield "white-default-" + suffix, missing, {**expected, "authored": [1, 1, 1]}
        coexisting = copy.deepcopy(scene)
        argument = "renamedShade" if renamed else "inputColor"
        coexisting["objects"][0]["color"].update(
            user="renamed-color-property" if renamed else "tint-property",
            script=f"export function update({argument}) {{ return {argument}; }}")
        yield "coexisting-producers-" + suffix, coexisting, expected
        for kind in ("model", "particle"):
            alternate = copy.deepcopy(scene)
            item = alternate["objects"][0]
            item[kind] = item.pop("image").replace("models/", kind + "s/")
            yield kind + "-" + suffix, alternate, expected

    for name, diagnostic in (("two-lanes", "componentMismatch"), ("four-lanes", "componentMismatch"),
                             ("relative", "relativeUnsupported"), ("text", "unsupportedHost"),
                             ("group", "combinedAnimationUnsupported"),
                             ("nonfinite-lane", "nonFiniteValue@c1")):
        rejected = copy.deepcopy(scene)
        layer = rejected["objects"][0]
        curve = layer["color"]["animation"]
        if name == "two-lanes":
            del curve["c2"]
        elif name == "four-lanes":
            curve["c3"] = copy.deepcopy(curve["c0"])
        elif name == "relative":
            curve["relative"] = True
        elif name == "text":
            del layer["image"]
            layer["text"] = "glyph color keeps its own consumer"
        elif name == "group":
            curve["options"]["children"] = [{"key": "zoom"}]
        else:
            curve["c1"][-1]["value"] = "NaN"
        yield name, rejected, {**expected, "diagnostic": diagnostic}


def assert_layer_color_result(test, result, expected):
    layer_id = expected["id"]
    target = f"layer:{layer_id}:color"
    bindings = [binding for binding in result["bindings"] if binding["target"] == target]
    runtime = result["layerColorRuntime"][str(layer_id)]
    for phase, alpha in zip(runtime["phases"], (0.25, 0.75)):
        test.assertEqual(phase["alpha"], alpha, result)
        test.assertEqual(phase["alphaSource"], "timeline", result)
    test.assertFalse(any(binding["target"].startswith((f"text:{layer_id}:color", f"particle:{layer_id}:"))
                         for binding in result["bindings"]), result)
    if "diagnostic" in expected:
        test.assertEqual(bindings, [], result)
        separator = ":" if expected["diagnostic"].startswith("nonFiniteValue") else ": "
        test.assertIn(f"layer {layer_id} color{separator}{expected['diagnostic']}", result["diagnostics"])
        for phase in runtime["phases"]:
            test.assertEqual(phase["source"], "missing", result)
            test.assertEqual(phase["consumed"], expected["authored"], result)
        return
    test.assertEqual(len(bindings), 1, result)
    binding = bindings[0]
    test.assertEqual((binding["valueType"], binding["componentCount"], binding["composition"]),
                     ("vector3", 3, "absolute"), result)
    authored = "vector3(" + ",".join(str(float(value)) for value in expected["authored"]) + ")"
    test.assertEqual(binding["authored"], authored, result)
    test.assertEqual(result["diagnostics"], [], result)
    for phase, color in zip(runtime["phases"], (FIRST, SECOND)):
        test.assertEqual(phase["source"], "timeline", result)
        test.assertEqual(phase["consumed"], color, result)
    for name, source, color, diagnostics in (
            ("authored", "authored", expected["authored"], []),
            ("user", "userProperty", [0.25, 0.75, 0.125], []),
            ("timeline", "timeline", SECOND, []),
            ("script", "sceneScript", [0.5, 0.125, 0.75], []),
            ("invalid-script", "timeline", SECOND, ["valueTypeMismatch"]),
            ("invalid-user", "authored", expected["authored"], ["valueTypeMismatch"])):
        value = runtime["sources"][name]
        test.assertEqual(value["source"], source, (name, result))
        test.assertEqual(value["consumed"], color, (name, result))
        test.assertEqual(value["diagnostics"], diagnostics, (name, result))
