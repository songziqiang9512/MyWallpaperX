"""Authored Combined Timeline inputs shared by compiler and playback gates."""


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
