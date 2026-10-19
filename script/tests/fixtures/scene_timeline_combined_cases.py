"""Authored Combined Timeline inputs shared by compiler and playback gates."""

import copy


def combined_scene(*, renamed=False, response=(None, None)):
    def key(frame, value):
        return {"frame": frame, "value": value}

    def animation(endpoints, *, root=False):
        options = {"fps": 10 if root else 3, "length": 20 if root else 90,
                   "mode": "single" if root else "loop", "startpaused": root,
                   "wraploop": not root, "name": "paired motion" if root else "child name",
                   "smoothing": None if root else 0.4, "stiffness": None if root else 0.2}
        return {**{f"c{i}": [key(0, 0), key(20, value)]
                   for i, value in enumerate(endpoints)}, "relative": True, "options": options}

    layer_id = 301 if renamed else 201
    root_key = "angles" if renamed else "origin"
    group = {"id": layer_id, "name": "different card" if renamed else "paired card",
             "image": "models/second-art.json" if renamed else "models/first-art.json",
             "origin": {"value": "10 20 30", "animation": animation([2, 4, 6], root=root_key == "origin")},
             "angles": {"value": "1 2 3", "animation": animation([4, 6, 8], root=root_key == "angles")},
             "scale": {"value": "1 2 3", "animation": animation([0.5, 1, 1.5])}}
    members = [key for key in ("origin", "angles", "scale") if key != root_key]
    if renamed:
        members.reverse()
        group = dict(reversed(list(group.items())))
        group[root_key]["animation"]["options"]["name"] = "renamed cohort"
    group[root_key]["animation"]["options"].update(smoothing=response[0], stiffness=response[1])
    group[root_key]["animation"]["options"]["children"] = [{"key": key} for key in members]
    for child in members:
        group[child]["animation"]["options"]["parent"] = {"key": root_key}
    independent = {"id": 202, "image": "models/independent.json", "alpha": {
        "value": 1, "animation": {"c0": [key(0, 0), key(20, 1)], "options": {
            "fps": 10, "length": 20, "mode": "single", "name": "independent"}}}}
    return {"version": 3, "objects": [group, independent]}


def accepted_combined_scenes():
    responses = {"nil-default": (None, None), "minimum": (0, 1),
                 "middle": (0.4, 87), "maximum": (0.9, 200),
                 "smoothing-only": (0.4, None), "stiffness-only": (None, 87)}
    cases = {f"{label}-renamed-{renamed}": (combined_scene(renamed=renamed, response=response), list(response))
             for renamed in (False, True) for label, response in responses.items()}
    # String wire values have always parsed as nil; they are not typed nonfinite IR.
    for renamed in (False, True):
        for field in (0, 1):
            for value in ("NaN", "Infinity"):
                response = [None, None]
                response[field] = value
                cases[f"wire-string-{field}-{value}-{renamed}"] = (
                    combined_scene(renamed=renamed, response=response), [None, None])
    return cases


def rejected_combined_scenes():
    cases = {}
    for label in ("missing-member", "missing-parent", "self", "cycle", "double-parent",
                  "duplicate-child", "unsupported-host", "absolute", "components",
                  "loop-response", "wrap-range", "nonfinite-lane", "bad-base"):
        scene = combined_scene()
        group = scene["objects"][0]
        options = {key: group[key]["animation"]["options"] for key in ("origin", "angles", "scale")}
        if label == "missing-member":
            del group["scale"]
        elif label == "missing-parent":
            options["angles"]["parent"] = {"key": "absent"}
        elif label == "self":
            options["origin"]["children"].append({"key": "origin"})
        elif label == "cycle":
            options["origin"]["parent"] = {"key": "angles"}
            options["angles"]["children"] = [{"key": "origin"}]
        elif label == "double-parent":
            options["scale"]["children"] = [{"key": "angles"}]
        elif label == "duplicate-child":
            options["origin"]["children"].append({"key": "angles"})
        elif label == "unsupported-host":
            group["color"] = group.pop("scale")
            options["origin"]["children"][1] = {"key": "color"}
        elif label == "absolute":
            group["angles"]["animation"]["relative"] = False
        elif label == "components":
            del group["scale"]["animation"]["c2"]
        elif label == "loop-response":
            options["origin"].update(mode="loop", wraploop=False, smoothing=0.4, stiffness=87)
        elif label == "wrap-range":
            options["origin"].update(mode="loop", wraploop=True)
        elif label == "nonfinite-lane":
            group["angles"]["animation"]["c0"][1]["value"] = "NaN"
        elif label == "bad-base":
            group["origin"]["value"] = "NaN 0 0"
        cases[label] = scene
    for field, value in (("smoothing", -0.001), ("smoothing", 0.900001),
                         ("stiffness", 0), ("stiffness", 201)):
        scene = combined_scene()
        scene["objects"][0]["origin"]["animation"]["options"][field] = value
        cases[f"invalid-{field}-{value}"] = scene
    return cases


def mixed_combined_scenes():
    """Linear authored inputs with independent scalar/vector output oracles."""
    cases = {}
    first = [[10, 20, 30], [2, 3, 4], [0.25]]
    middle = [[12, 24, 36], [2.25, 3.5, 4.75], [0.5]]
    last = [[14, 28, 42], [2.5, 4, 5.5], [0.75]]
    for mode, wraps in (("single", False), ("loop", False), ("loop", True)):
        for root in ("origin", "alpha"):
            for renamed in (False, True):
                layer_id = 703 if renamed else 401
                numeric = float if renamed else int
                options = {"fps": numeric(10), "length": numeric(40), "mode": mode,
                           "startpaused": True, "wraploop": wraps, "name": "mixed cohort"}
                group = {"id": layer_id, "name": "other" if renamed else "mixed",
                         "image": "models/renamed.json" if renamed else "models/mixed.json"}
                for host, base, endpoints in (("origin", "10 20 30", [4, 8, 12]),
                                               ("scale", "2 3 4", [0.5, 1, 1.5]),
                                               ("alpha", 0.375, [0.75])):
                    animation = {f"c{i}": [{"frame": numeric(10), "value": 0.25 if host == "alpha" else 0},
                                            {"frame": numeric(30), "value": end}]
                                 for i, end in enumerate(endpoints)}
                    animation["relative"] = host != "alpha"
                    animation["options"] = dict(options) if host == root else {
                        "fps": 3, "length": 2, "mode": "mirror", "wraploop": True,
                        "startpaused": False, "smoothing": 0.4, "name": "child ignored",
                        "parent": {"key": root}}
                    group[host] = {"value": base, "animation": animation}
                children = [host for host in ("origin", "scale", "alpha") if host != root]
                group[root]["animation"]["options"]["children"] = [
                    {"key": host} for host in (reversed(children) if renamed else children)]
                if renamed:
                    group = dict(reversed(list(group.items())))
                scene = {"version": 3, "objects": [group, combined_scene()["objects"][1]]}
                initial = middle if wraps else first
                final = last if mode == "single" else initial
                expected = {"groupCount": 3, "samples": [initial, first, middle, middle, initial],
                            "curve": [initial, first, middle, last, final, first if mode == "loop" else last]}
                cases[f"{mode}-wrap-{wraps}-{root}-renamed-{renamed}"] = (scene, expected)

    base = cases["loop-wrap-True-origin-renamed-False"][0]
    outside = copy.deepcopy(base)
    alpha = outside["objects"][0]["alpha"]["animation"]["c0"]
    alpha[0]["value"], alpha[1]["value"] = -0.25, 1.25
    expected = copy.deepcopy(cases["loop-wrap-True-origin-renamed-False"][1])
    expected["samples"][1][2] = [-0.25]
    expected["curve"][1][2] = expected["curve"][5][2] = [-0.25]
    expected["curve"][3][2] = [1.25]
    cases["finite-alpha-outside-unit"] = (outside, expected)

    for label in ("relative-alpha", "absolute-transform", "unknown-host", "missing-member",
                  "missing-parent", "duplicate-child", "cycle", "nested", "second-root",
                  "cross-layer", "components", "nonfinite-lane", "overflow-control",
                  "wrap-closing-control", "wrap-range", "wrap-single", "response-loop"):
        scene = copy.deepcopy(base)
        group = scene["objects"][0]
        root_options = group["origin"]["animation"]["options"]
        if label == "relative-alpha":
            group["alpha"]["animation"]["relative"] = True
        elif label == "absolute-transform":
            group["scale"]["animation"]["relative"] = False
        elif label == "unknown-host":
            group["color"] = group.pop("alpha")
            root_options["children"][-1] = {"key": "color"}
        elif label == "missing-member":
            del group["alpha"]
        elif label == "missing-parent":
            group["alpha"]["animation"]["options"]["parent"] = {"key": "absent"}
        elif label == "duplicate-child":
            root_options["children"].append({"key": "alpha"})
        elif label == "cycle":
            root_options["parent"] = {"key": "alpha"}
            group["alpha"]["animation"]["options"]["children"] = [{"key": "origin"}]
        elif label == "nested":
            group["scale"]["animation"]["options"]["children"] = [{"key": "alpha"}]
            group["alpha"]["animation"]["options"]["parent"] = {"key": "scale"}
        elif label == "second-root":
            del group["alpha"]["animation"]["options"]["parent"]
        elif label == "cross-layer":
            scene["objects"].append({"id": 704, "image": "models/peer.json", "alpha": group.pop("alpha")})
        elif label == "components":
            del group["scale"]["animation"]["c2"]
        elif label == "nonfinite-lane":
            group["alpha"]["animation"]["c0"][0]["value"] = "NaN"
        elif label in ("overflow-control", "wrap-closing-control"):
            lane = group["alpha"]["animation"]["c0"]
            key = lane[0 if label == "overflow-control" else -1]
            key.update(value=1e308, front={"enabled": True, "x": 0.5, "y": 1e308})
        elif label == "wrap-range":
            root_options["length"] = 30
        elif label == "wrap-single":
            root_options["mode"] = "single"
        elif label == "response-loop":
            root_options["smoothing"] = 0.4
        cases["reject-" + label] = (scene, {"groupCount": 0})
    return cases
