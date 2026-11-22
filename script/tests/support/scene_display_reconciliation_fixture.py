"""Assertions over on-demand snapshots from the existing real Scene App runner."""
from pathlib import Path
import json
import re


STAGES = ("before", "after", "settled")
SURFACE_IDENTITIES = ("surfaceIdentity", "viewIdentity", "rendererTextureRegistryIdentity",
                      "windowNumber", "graphRuntimeIdentity")
FROZEN_FRAME_FIELDS = ("simulationFrameIndex", "dynamicGeneration", "sceneTime",
                       "topologyRevision", "destroyedLayerIDs", "spriteTimes")
SIMULATOR_STATE_FIELDS = {"simulationTime", "playbackIntent", "playbackRevision", "randomState",
                          "accumulator", "nextParticleID", "emitters", "particles", "normalizedLives",
                          "dynamicControlPoints", "dynamicControlPointAngles"}
EMITTER_STATE_FIELDS = {"elapsed", "remainder", "emittedInstantaneous", "initialDelayElapsed",
                        "emittedRateThisFrame", "periodicIsEmitting", "periodicRandomState", "periodicUsedCount"}


def load_reconciliation_snapshots(evidence: Path) -> dict:
    return {stage: json.loads((evidence / f"surface-rebuild-{stage}.json").read_text())
            for stage in STAGES}


def assert_retained_surfaces(case, observed: dict, screens: int, *, paused: bool,
                             remaining_screens: int | None = None,
                             target_displays: set[str] | None = None) -> tuple:
    before, after, settled = (observed[stage] for stage in STAGES)
    case.assertTrue(before["sessionID"] and before["requestID"], observed)
    displays = set(before["surfacesByDisplay"])
    case.assertEqual(len(displays), screens, observed)
    targets = set(after["surfacesByDisplay"])
    if target_displays is not None:
        case.assertEqual(targets, target_displays, observed)
    elif remaining_screens is None:
        case.assertEqual(targets, displays, observed)
    else:
        case.assertEqual(len(targets), remaining_screens, observed)
        case.assertTrue(targets and targets < displays, observed)
    retained = displays & targets
    live_frames = {str(row["displayID"]): row["frame"] for row in before["capturedTopology"]}
    case.assertTrue(live_frames, observed)
    for stage, snapshot in observed.items():
        for key in ("sessionID", "requestID"):
            case.assertEqual(snapshot[key], before[key], observed)
        current_displays = displays if stage == "before" else targets
        case.assertEqual(snapshot["surfaceCount"], len(current_displays), observed)
        case.assertEqual(set(snapshot["surfacesByDisplay"]), current_displays, observed)
        for field in SURFACE_IDENTITIES:
            identities = [row[field] for row in snapshot["surfacesByDisplay"].values()]
            case.assertTrue(all(identities), (field, observed))
            case.assertEqual(len(set(identities)), len(current_displays), (field, observed))
    for display in targets:
        original = before["surfacesByDisplay"].get(display)
        for snapshot in (after, settled):
            current = snapshot["surfacesByDisplay"][display]
            if original is not None:
                for field in SURFACE_IDENTITIES:
                    case.assertEqual(current[field], original[field], (display, field, observed))
            case.assertEqual(current["windowFrame"], current["targetFrame"], (display, observed))
            if display in live_frames:
                case.assertEqual(current["targetFrame"], live_frames[display], observed)
            case.assertIn(current["targetFrame"], list(live_frames.values()), observed)
            bounds, drawable = current["viewBounds"], current["drawableSize"]
            case.assertEqual(bounds[2:], current["windowFrame"][2:], (display, observed))
            for actual, points in zip(drawable, bounds[2:], strict=True):
                case.assertAlmostEqual(actual, points * current["contentsScale"], delta=1, msg=str(observed))
        if remaining_screens is None and target_displays is None:
            case.assertNotEqual(original["windowFrame"][2:], after["surfacesByDisplay"][display]["windowFrame"][2:], observed)
    if paused:
        for snapshot in (before, after):
            case.assertTrue(snapshot["isPlaybackPaused"], observed)
            case.assertFalse(snapshot["isFrameDriverActive"], observed)
        for field in ("sceneTime", "committedFrameIndex", "committedGeneration",
                      "committedTopologyRevision", "committedDestroyedLayerIDs"):
            case.assertEqual(before[field], after[field], (field, observed))
        for display in retained:
            for field in FROZEN_FRAME_FIELDS:
                case.assertEqual(before["surfacesByDisplay"][display][field],
                                 after["surfacesByDisplay"][display][field], (display, field, observed))
    else:
        case.assertFalse(before["isPlaybackPaused"] or after["isPlaybackPaused"], observed)
        case.assertTrue(before["isFrameDriverActive"] and after["isFrameDriverActive"], observed)
        case.assertGreater(after["sceneTime"], before["sceneTime"], observed)
        case.assertGreater(after["committedFrameIndex"], before["committedFrameIndex"], observed)
    return before, after, settled


def reconciliation_interval(case, log: str, *, state: str = "retained") -> str:
    triggered = re.search(r"(?m)^.*phase=surface-reconciliation state=triggered[^\n]*", log)
    retained = re.search(rf"(?m)^.*phase=surface-reconciliation state={state} accepted=true[^\n]*", log)
    case.assertIsNotNone(triggered, log[-6000:])
    case.assertIsNotNone(retained, log[-6000:])
    case.assertLess(triggered.start(), retained.start(), log[-6000:])
    interval = log[triggered.start():retained.end()]
    case.assertNotIn("phase=surface-teardown", interval)
    if state == "retained":
        case.assertNotIn("lifecycle=teardown", interval)
    return interval


def capture_receipts(case, log: str, targets: dict[str, tuple[str, str]]) -> dict:
    lines = log.splitlines()
    observations = [(index, json.loads(line.split("MWX SCENE COMPOSITION OBSERVATION: ", 1)[1]))
        for index, line in enumerate(lines) if "MWX SCENE COMPOSITION OBSERVATION: " in line]
    encoded = [(index, dict(re.findall(r"(\w+)=([^\s]+)", line)))
        for index, line in enumerate(lines) if "phase=snapshot-encoded " in line]
    requests = dict(re.findall(r"phase=snapshot reason=(\S+) request=(\d+) source=metal", log))
    result = {}
    for reason, (display, identity) in targets.items():
        matching = []
        for encoded_index, event in encoded:
            if event["request"] != requests[reason]:
                continue
            for index, row in observations:
                if (index > encoded_index and row.get("captureRequestID") == int(requests[reason])
                    and str(row.get("displayID")) == display and row.get("surfaceIdentity") == identity
                    and row.get("commandBufferToken") == event["commandBufferToken"]
                    and any(item["kind"] == "frame-seal" and item.get("target", {}).get("textureToken") == event["textureToken"]
                        and item["target"].get("width") == int(event["width"])
                        and item["target"].get("height") == int(event["height"]) for item in row["rows"])):
                    matching.append((encoded_index, row))
        case.assertEqual(len(matching), 1, (reason, [(index, event) for index, event in encoded]))
        result[reason] = matching[0]
    return result


def assert_retained_particles(case, observed: dict, *, paused: bool, active_children: bool = False,
                              retained_displays: set[str] | None = None,
                              all_particles_survive: bool = True):
    before, after, settled = (observed[stage] for stage in STAGES)
    lifecycle_ids = set()
    simulator_ids = set()
    for display, original in before["surfacesByDisplay"].items():
        identity = original["particleStateIdentity"]
        case.assertTrue(identity, observed)
        case.assertNotIn(identity, lifecycle_ids, observed)
        lifecycle_ids.add(identity)
        current_snapshots = (after, settled) if retained_displays is None or display in retained_displays else ()
        for snapshot in current_snapshots:
            case.assertEqual(snapshot["surfacesByDisplay"][display]["particleStateIdentity"], identity, observed)
        layers = {str(row["layerID"]): row for row in original["particleLayers"]}
        case.assertTrue(layers, observed)
        for layer_id, layer in layers.items():
            root = layer["root"]
            case.assertIsNotNone(root, observed)
            case.assertTrue(root["simulatorIdentity"] and root["particles"], observed)
            for snapshot in current_snapshots:
                current = {str(row["layerID"]): row for row in
                           snapshot["surfacesByDisplay"][display]["particleLayers"]}.get(layer_id)
                if current is not None:
                    case.assertEqual(current["root"]["simulatorIdentity"], root["simulatorIdentity"], observed)
                    if not paused:
                        case.assertGreater(current["root"]["simulationTime"], root["simulationTime"], observed)
                        case.assertGreaterEqual(int(current["root"]["nextParticleID"]), int(root["nextParticleID"]), observed)
                        case.assertTrue(current["root"]["particles"], observed)
                        if all_particles_survive:
                            case.assertTrue({row["id"] for row in root["particles"]}.issubset(
                                {row["id"] for row in current["root"]["particles"]}), observed)
            all_systems = [root, *[child["frame"] for child in layer["children"]]]
            for system in all_systems:
                case.assertNotIn(system["simulatorIdentity"], simulator_ids, observed)
                simulator_ids.add(system["simulatorIdentity"])
                case.assertTrue(SIMULATOR_STATE_FIELDS.issubset(system), observed)
                case.assertTrue(system["emitters"], observed)
                for emitter in system["emitters"]:
                    case.assertTrue(EMITTER_STATE_FIELDS.issubset(emitter), observed)
            if active_children and layer_id == "42":
                case.assertTrue(layer["children"], observed)
                case.assertTrue(all(child["frame"]["particles"] for child in layer["children"]), observed)
        if paused and current_snapshots:
            case.assertEqual(after["surfacesByDisplay"][display]["particleLayers"], original["particleLayers"], observed)
        if active_children:
            case.assertIn("42", layers, observed)
    return lifecycle_ids
