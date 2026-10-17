"""Authored Combined Timeline inputs shared by compiler and playback gates."""


def combined_scene(*, renamed=False):
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
    group[root_key]["animation"]["options"]["children"] = [{"key": key} for key in members]
    for child in members:
        group[child]["animation"]["options"]["parent"] = {"key": root_key}
    independent = {"id": 202, "image": "models/independent.json", "alpha": {
        "value": 1, "animation": {"c0": [key(0, 0), key(20, 1)], "options": {
            "fps": 10, "length": 20, "mode": "single", "name": "independent"}}}}
    return {"version": 3, "objects": [group, independent]}


def rejected_combined_scenes():
    cases = {}
    for label in ("missing-member", "missing-parent", "self", "cycle", "double-parent",
                  "duplicate-child", "unsupported-host", "absolute", "components",
                  "root-smoothing", "wrap-range", "nonfinite-lane", "bad-base"):
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
        elif label == "root-smoothing":
            options["origin"]["smoothing"] = 0.4
        elif label == "wrap-range":
            options["origin"].update(mode="loop", wraploop=True)
        elif label == "nonfinite-lane":
            group["angles"]["animation"]["c0"][1]["value"] = "NaN"
        elif label == "bad-base":
            group["origin"]["value"] = "NaN 0 0"
        cases[label] = scene
    return cases
