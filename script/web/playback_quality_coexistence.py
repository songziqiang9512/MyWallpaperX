#!/usr/bin/env python3
"""Signed Scene/Web/Video handoff, cold restoration, quality import or Scene reapply."""

import argparse
import json
import os
from pathlib import Path
import pwd
import shutil
import subprocess
import time
import uuid

from wallpaper_startup_benchmark import (
    child_processes, defaults_values, finish_selection_process, isolated_path,
    production_preferences_identity, tree_identity,
)
from web_benchmark_capture import (
    discard_staged_app, png_has_non_black_pixel, png_motion_metrics, png_rgb_pixels,
    require_fresh_output_dir, stage_signed_app, verify_staged_app,
)
from web_debug_defaults import delete_debug_defaults_suite, make_debug_defaults_suite


BUNDLE_ID = "com.songziqiang.MyWallpaperX.Debug.Coexistence"
WEB_ID = "9000000002"
WEB = """<!doctype html><meta charset=utf-8><style>
html,body{margin:0;height:100%;background:rgb(185,15,38)}
#mark{position:absolute;top:27%;width:18%;height:45%;background:rgb(231,235,248)}
#fps{position:absolute;left:0;top:0;width:35%;height:25%;background:rgb(185,15,38)}
</style><div id=fps></div><div id=mark></div><script>
const fpsMarker = document.getElementById("fps");
window.wallpaperPropertyListener = {
  applyGeneralProperties(p) {
    fpsMarker.style.background = p.fps === 15 ? "rgb(12,190,38)"
      : p.fps === 25 ? "rgb(196,40,210)"
      : p.fps === 60 ? "rgb(22,34,215)"
      : typeof p.fps === "number" ? "rgb(25,185,215)" : "rgb(223,175,7)";
  }
};
const mark = document.getElementById("mark");
function draw(t) {
  mark.style.left = 12 + 60 * ((t % 3500) / 3500) + "%";
  requestAnimationFrame(draw);
}
requestAnimationFrame(draw);
</script>"""


def run_phase(command, environment, directory, phase, timeout):
    report = directory / "native.json"
    args = [*command, "--mwx-debug-coexistence-report", str(report),
            "--mwx-debug-coexistence-phase", phase]
    deadline = time.monotonic() + timeout
    children = {}
    captured = set()
    with (directory / "app.log").open("w") as log:
        process = subprocess.Popen(args, stdout=log, stderr=subprocess.STDOUT,
                                   env=environment, start_new_session=True)
        try:
            while process.poll() is None and time.monotonic() < deadline:
                children.update(child_processes(process.pid))
                request = directory / "capture-request.json"
                if request.is_file():
                    value = json.loads(request.read_text())
                    name, window = value["name"], value["window"]
                    if phase == "scene-reapply":
                        names = ("settings-reapply", "settings-reapply-pending", "settings-reapply-applied")
                    elif phase == "scene-selection-edit":
                        names = ("selection-edit-video",)
                    elif phase == "quality-import":
                        names = ("video-import-before", "video-import-after")
                    else:
                        names = ("video-paused", "video-still", "video-resumed", "video-running")
                    if name not in names:
                        raise RuntimeError("unexpected window capture request")
                    if name not in captured:
                        temporary = directory / f"{name}-inflight.png"
                        capture = subprocess.run(
                            ["/usr/sbin/screencapture", "-x", "-o", "-t", "png", "-l", str(int(window)), str(temporary)],
                            capture_output=True, text=True, timeout=8)
                        if capture.returncode or not png_has_non_black_pixel(temporary):
                            raise RuntimeError("window capture failed; check Screen Recording: " + capture.stderr)
                        temporary.rename(directory / f"{name}.png")
                        captured.add(name)
                time.sleep(.15)
            if process.poll() is None:
                raise RuntimeError(f"{phase} did not finish normal product exit")
            if process.returncode or not report.is_file():
                raise RuntimeError(f"{phase} exited without a successful native report")
            result = json.loads(report.read_text())
            if result.get("passed") is not True:
                raise RuntimeError(result.get("failure", f"{phase} failed"))
        finally:
            cleanup = finish_selection_process(process, children)
            (directory / "processes.json").write_text(json.dumps(cleanup, indent=2) + "\n")
        if cleanup["errors"] or cleanup["remainingOwnedChildren"] or not cleanup["ownedProcessesExited"]:
            raise RuntimeError("normal exit did not drain precisely owned child processes")
        if phase in ("quality-import", "scene-selection-edit"):
            return result
        prepared = {}
        marker = "phase=session-candidate "
        for line in (directory / "app.log").read_text().splitlines():
            if marker in line:
                values = dict(word.split("=", 1) for word in line.split(marker, 1)[1].split() if "=" in word)
                prepared[values["session"]] = values
        if phase == "scene-reapply":
            observations = result["sceneReapply"]
            sessions = {key: prepared.get(observations[key]["sessionID"], {})
                        for key in ("before", "after", "reverted")}
            applied = {key: values.get("postProcessing") for key, values in sessions.items()}
            textures = {key: values.get("textureQuality") for key, values in sessions.items()}
            if (applied != {"before": "enabled", "after": "disabled", "reverted": "disabled"}
                    or textures != {"before": "quality", "after": "performance", "reverted": "performance"}):
                raise RuntimeError(f"Scene did not prepare the chosen modes and textures: {applied}, {textures}")
            result["preparedSceneTextures"] = textures
        else:
            keys, expected = (("scene-in", "scene-back"), "enabled") if phase == "switch" else (("scene",), "disabled")
            applied = {key: prepared.get(result[key]["resumed"]["sessionID"], {}).get("postProcessing")
                       for key in keys}
            if any(mode != expected for mode in applied.values()):
                raise RuntimeError(f"{phase} Scene did not prepare the saved post-processing mode: {applied}")
        result["preparedScenePostProcessing"] = applied
        (directory / "native.json").write_text(json.dumps(result, indent=2) + "\n")
        return result


def verify_pixels(root):
    checks = {}
    for kind in ("web", "video"):
        paths = [root / f"{kind}-{label}.png" for label in ("paused", "still", "resumed", "running")]
        frozen = png_motion_metrics(paths[0], paths[1], threshold=3, region=(.1, .1, .9, .9))
        resumed = png_motion_metrics(paths[1], paths[2], threshold=3, region=(.1, .1, .9, .9))
        running = png_motion_metrics(paths[2], paths[3], threshold=3, region=(.1, .1, .9, .9))
        checks[kind] = {"frozen": frozen, "resumed": resumed, "running": running}
        if (not all((frozen, resumed, running)) or frozen["changed_ratio"] > .001
                or min(resumed["changed_ratio"], running["changed_ratio"]) < .01):
            raise RuntimeError(f"{kind} pixels did not freeze and advance: {checks[kind]}")
    checks["webGeneralFPSMarkerRGB"] = web_fps_marker(root / "web-running.png")
    return checks


def web_fps_marker(path):
    decoded = png_rgb_pixels(path)
    if decoded is None:
        raise RuntimeError("could not decode the author fps marker")
    width, height, rows = decoded
    start = int(.1 * width) * 3
    return list(rows[int(.1 * height)][start:start + 3])


def verify_import_pixels(root):
    before = web_fps_marker(root / "web-import-before.png")
    after = web_fps_marker(root / "web-import-after.png")
    if min(before[0] - before[1], before[2] - before[1],
           after[1] - after[0], after[2] - after[0]) < 60:
        raise RuntimeError(f"Web did not keep its author document and adopt the imported fps: {before}, {after}")
    video_paths = [root / f"video-import-{label}.png" for label in ("before", "after")]
    motion = png_motion_metrics(*video_paths, threshold=3, region=(.1, .1, .9, .9))
    if not motion or motion["changed_ratio"] < .01:
        raise RuntimeError(f"Video did not keep producing real frames over the import: {motion}")
    return {"webFPSBeforeRGB": before, "webFPSAfterRGB": after, "videoMotion": motion}


def verify_reapply_pixels(root):
    paths = [root / f"scene-reapply-{name}.jpg" for name in ("before", "after", "still", "reverted")]
    changed = png_motion_metrics(paths[0], paths[1], threshold=3, region=(.1, .1, .9, .9))
    frozen = png_motion_metrics(paths[1], paths[2], threshold=3, region=(.1, .1, .9, .9))
    returned = png_motion_metrics(paths[2], paths[3], threshold=3, region=(.1, .1, .9, .9))
    if (not all((changed, frozen, returned)) or max(frozen["changed_ratio"], returned["changed_ratio"]) > .001
            or changed["changed_ratio"] < .001):
        raise RuntimeError(f"Scene pixels did not change and then remain paused: {changed}, {frozen}, {returned}")
    return {"automaticallyReapplied": changed, "stillPaused": frozen, "returnedToApplied": returned}


def verify_restore(first, second):
    rows = first["switches"]
    restored = second["restored"]
    if ([row["runtime"] for row in rows] != ["scene", "web", "video", "scene"]
            or len({row["ticket"] for row in rows}) != 4
            or len({row["execution"] for row in rows}) != 4
            or not first.get("savedPaused") or first["parentPID"] == second["parentPID"]
            or restored["reference"] != rows[-1]["reference"]
            or any(restored[key] == rows[-1][key] for key in ("ticket", "execution", "request"))):
        raise RuntimeError("cold restore did not preserve the original selection with newly admitted execution")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--app", type=Path, required=True, help="team-signed dedicated .Debug.Coexistence executable")
    parser.add_argument("--scene-root", type=Path, required=True, help="isolated small dynamic numeric Workshop item copy")
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--timeout", type=float, default=120, help="per native phase")
    phase = parser.add_mutually_exclusive_group()
    phase.add_argument("--quality-import", action="store_true", help="run the portable quality-only live import")
    phase.add_argument("--scene-reapply", dest="scene_reapply", action="store_const", const="auto",
                       help="automatically reapply the current Scene through native Settings")
    phase.add_argument("--scene-reapply-manual", dest="scene_reapply", action="store_const", const="manual",
                       help="supersede a manual Scene retry started after portable quality import")
    phase.add_argument("--scene-selection-edit", nargs="?", const="cold", choices=("cold", "fps", "portable"),
                       help="change native Scene quality during an ordinary library selection")
    parser.add_argument("--ui-language", choices=("en", "zh-Hans", "ru", "de", "fr"),
                        help="language of the isolated Settings window")
    args = parser.parse_args()
    scene, output = isolated_path(args.scene_root), isolated_path(args.output_dir)
    library = (Path(pwd.getpwuid(os.getuid()).pw_dir) / "Library").resolve()
    if any(path == library or path.is_relative_to(library) or library.is_relative_to(path)
           for path in (scene, output)):
        parser.error("Scene input and output must be outside the account Library")
    if not scene.name.isascii() or not scene.name.isdecimal() or scene.name == WEB_ID:
        parser.error("expected a numeric Workshop item directory distinct from the local Web fixture")
    if not (scene / "project.json").is_file() or not (scene / "scene.pkg").is_file():
        parser.error("expected an isolated Scene Workshop project.json and scene.pkg")
    if scene == output or scene.is_relative_to(output) or output.is_relative_to(scene):
        parser.error("input Scene and output must be disjoint")
    source = tree_identity(scene)
    require_fresh_output_dir(output)
    output.mkdir(parents=True, exist_ok=True)
    scratch = output / "runtime"
    home = scratch / "home"
    home.mkdir(parents=True)
    temporary = scratch / "tmp"
    temporary.mkdir()
    workshop = scratch / "workshop"
    web = workshop / "Web" / WEB_ID
    web.mkdir(parents=True)
    (web / "project.json").write_text(json.dumps({"type": "web", "file": "index.html"}))
    (web / "index.html").write_text(WEB)
    shutil.copytree(scene, workshop / "Scene" / scene.name)

    binary, identity = stage_signed_app(args.app, output)
    metadata = {"appIdentity": identity, "sceneSource": source, "passed": False}
    token = uuid.uuid4().hex
    suite = make_debug_defaults_suite()
    environment = {key: value for key, value in os.environ.items()
                   if not key.startswith(("MWX_", "MYWALLPAPERX_"))}
    environment.update(HOME=str(home), CFFIXED_USER_HOME=str(home), TMPDIR=str(temporary))
    claimed = False
    production_before = production_preferences_identity()
    try:
        if identity["bundle_identifier"] != BUNDLE_ID or not identity["team_identifier"]:
            raise RuntimeError(f"requires a dedicated team-signed {BUNDLE_ID}")
        if defaults_values(BUNDLE_ID):
            raise RuntimeError("dedicated standard defaults domain already exists")
        subprocess.run(["/usr/bin/defaults", "write", BUNDLE_ID, "MWXStartupDefaultsToken", "-string", token],
                       check=True, capture_output=True)
        claimed = True
        common = [str(binary), "--mwx-debug-user-defaults-suite", suite, "--mwx-debug-suppress-main-window",
                  "--mwx-debug-workshop-root", str(workshop), "--mwx-debug-coexistence-scene", scene.name,
                  "--mwx-debug-coexistence-web", WEB_ID]
        if args.scene_reapply == "manual":
            common.append("--mwx-debug-scene-reapply-manual")
        if args.scene_selection_edit:
            common += ["--mwx-debug-scene-selection-edit", args.scene_selection_edit]
        if args.ui_language:
            common += ["-AppleLanguages", f"({args.ui_language})"]
        negative_report = output / "rejected.json"
        negative = subprocess.run([*common, "--mwx-debug-startup-defaults-token", "wrong",
                                   "--mwx-debug-coexistence-report", str(negative_report),
                                   "--mwx-debug-coexistence-phase", "switch"],
                                  env=environment, capture_output=True, text=True, timeout=10)
        (output / "rejected.log").write_text(negative.stdout + negative.stderr)
        if negative_report.exists() or "MWX COEXISTENCE: dedicated signed test bundle" not in negative.stderr:
            raise RuntimeError("mismatched isolation token did not fail closed")
        metadata["invalidIsolationTokenRejected"] = True
        phases = {}
        if args.scene_reapply:
            phase_order = ("scene-reapply",)
        elif args.scene_selection_edit:
            phase_order = ("scene-selection-edit",)
        elif args.quality_import:
            phase_order = ("quality-import",)
        else:
            phase_order = ("switch", "restore")
        for name in phase_order:
            directory = output / name
            directory.mkdir()
            phases[name] = run_phase([*common, "--mwx-debug-startup-defaults-token", token],
                                     environment, directory, name, args.timeout)
        if args.scene_reapply:
            observation = phases["scene-reapply"]["sceneReapply"]
            if observation.get("manualRetryAfterImport") is not (args.scene_reapply == "manual"):
                raise RuntimeError("native Scene reapply mode did not match the requested gate")
            metadata["pixels"] = verify_reapply_pixels(output / "scene-reapply")
            control = observation["control"]
            if args.ui_language and control["language"] != args.ui_language:
                raise RuntimeError(f"Settings did not use the requested language: {control}")
        elif args.scene_selection_edit:
            observation = phases["scene-selection-edit"]["sceneSelectionEdit"]
            prepared = observation["prepared"]
            current = observation["committed"]
            cold = args.scene_selection_edit == "cold"
            portable = args.scene_selection_edit == "portable"
            modes = ["enabled", "disabled"] if cold else ["enabled"]
            requests = [row["request"] for row in prepared]
            if not (observation["saved"] and observation["sameSelectionSnapshot"] and observation["markerRetained"]
                    and [row["postProcessing"] for row in prepared] == modes
                    and all(row["videoRetained"] and row["ticket"] == current["ticket"] for row in prepared)
                    and len(set(requests)) == len(modes) and requests[-1] == current["request"]
                    and observation["presented"] == observation["finalized"] == [current["request"]]
                    and observation["effectiveFPS"] == (25 if args.scene_selection_edit == "fps" else 15)
                    and (not portable or observation["importedWhilePreparing"])
                    and observation["appliedTextures"] == "quality" and observation["applied"] == modes[-1]
                    and observation["pendingQualityVisible"] is portable):
                raise RuntimeError("ordinary Scene selection did not settle with the expected quality edit")
        elif args.quality_import:
            metadata["pixels"] = verify_import_pixels(output / "quality-import")
        else:
            verify_restore(phases["switch"], phases["restore"])
            metadata["pixels"] = verify_pixels(output / "switch")
            red, green, blue = metadata["pixels"]["webGeneralFPSMarkerRGB"]
            # The WindowServer capture can encode the authored sRGB colors in the display profile.
            if green - max(red, blue) < 60:
                raise RuntimeError(f"real Web author page did not receive follow-animation fps=15, marker RGB {[red, green, blue]}")
        metadata["passed"] = source == tree_identity(scene)
        if not metadata["passed"]:
            raise RuntimeError("isolated input source changed")
    except (ValueError, OSError, RuntimeError, subprocess.SubprocessError) as error:
        metadata["failure"] = str(error)
    finally:
        try:
            verify_staged_app(identity)
            if claimed:
                current = defaults_values(BUNDLE_ID)
                if (current or {}).get("MWXStartupDefaultsToken") != token:
                    raise RuntimeError("dedicated defaults changed owner before cleanup")
                subprocess.run(["/usr/bin/defaults", "delete", BUNDLE_ID], check=True, capture_output=True)
                delete_debug_defaults_suite(suite, environment)
            metadata["productionPreferencesUnchanged"] = production_before == production_preferences_identity()
            if not metadata["productionPreferencesUnchanged"]:
                raise RuntimeError("production preferences changed during the isolated run")
            if metadata["passed"]:
                discard_staged_app(identity)
                shutil.rmtree(scratch)
        except (ValueError, OSError, RuntimeError, subprocess.SubprocessError) as error:
            metadata.update(passed=False, cleanupFailure=str(error))
        (output / "report.json").write_text(json.dumps(metadata, indent=2) + "\n")
    print(output / "report.json")
    return 0 if metadata["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
