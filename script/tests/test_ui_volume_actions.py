"""Actual Settings/status volume actions through the real nested volume chain.

Compiles the original UI action bodies, manager volume/mute methods, complete
Video handler, multiplexer, and shared mute/volume authorities. The original
WallpaperEngine volume projection and Scene volume/mute command arms run with
recording IPC leaves. No media, helper, user defaults or desktop is touched;
controls are invoked without opening a window. This proves command counts and
boundary semantics, not audible output or helper transport delivery.
"""
import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

from script.tests.test_ui_library_algorithms import declaration
from script.tests.test_video_thumbnail_prefetch import SWIFT_ISOLATION_FLAGS

ROOT = Path(__file__).resolve().parents[2]


class UIVolumeActionsTests(unittest.TestCase):
    def test_original_ui_actions_avoid_redundant_mute_but_preserve_boundary_and_explicit_intents(self):
        app = ROOT / "MyWallpaperX"
        status = app / "App/StatusBarController.swift"
        status_panel = app / "App/StatusBarPanelViewController.swift"
        settings = app / "Shared/Settings/AppKitSettingsView.swift"
        manager = app / "Modules/VideoLibrary/Core/WallpaperManager+PlaybackSettings.swift"
        engine = app / "Core/Playback/WallpaperEngine.swift"
        daemon = app / "Core/Playback/DaemonProtocol.swift"
        scene = app / "Core/SteamWorkshopScene/Runtime/IPC/SceneDaemonClient.swift"
        fixture = ROOT / "script/tests/fixtures/UIVolumeActionsHarness.swift"
        dependencies = [app / name for name in (
            "Core/SteamWorkshopScene/Systems/Properties/SceneUserProperty.swift",
            "Core/SteamWorkshopStorage/ScenePlaybackSource.swift",
            "Core/PlaybackControl/ScenePlaybackShortcut.swift",
            "Core/PlaybackControl/WallpaperEngineCommand.swift",
            "Core/PlaybackControl/PlaybackEngineControlling.swift",
            "Core/PlaybackControl/PlaybackCommandMultiplexer.swift",
            "Modules/VideoLibrary/Core/VideoPlaybackCommandHandler.swift",
            "Shared/Settings/AppSettingsPanelDependency.swift",
        )]
        paths = [status, status_panel, settings, manager, engine, daemon, scene, fixture,
                 Path(__file__).resolve(), *dependencies]
        inputs = {str(path): hashlib.sha256(path.read_bytes()).hexdigest() for path in paths}
        source = fixture.read_text()
        replacements = {
            "// ACTUAL_STATUS_PERFORM": declaration(status.read_text(), "    private func perform("),
            "// ACTUAL_STATUS_ACTION": declaration(status_panel.read_text(), "    enum Action {"),
            "// ACTUAL_SETTINGS_VOLUME_HANDLER": declaration(settings.read_text(), "    @objc private func handleVolumeChange("),
            "// ACTUAL_SETTINGS_MUTE_HANDLER": declaration(settings.read_text(), "    @objc private func handleMuteToggle("),
            "// ACTUAL_MANAGER_VOLUME_METHODS": "\n".join(declaration(manager.read_text(), signature) for signature in (
                "    func updateVolume(", "    func setMuted(")),
            "// ACTUAL_ENGINE_VOLUME_METHOD": declaration(engine.read_text(), "    public func setVolume("),
        }
        scene_handler = declaration(scene.read_text(), "    func handle(")
        begin = scene_handler.index("        case let .setVolume(volume):")
        end = scene_handler.index("        case let .setPlaybackPaused(paused):", begin)
        replacements["// ACTUAL_SCENE_VOLUME_CASES"] = scene_handler[begin:end]
        for marker, body in replacements.items():
            self.assertEqual(source.count(marker), 1, marker)
            source = source.replace(marker, body)
        source += "\n" + declaration(daemon.read_text(), "struct DaemonCommand:")
        with tempfile.TemporaryDirectory(prefix="mwx-ui-volume-", dir="/private/tmp") as temporary:
            work = Path(temporary)
            home = work / "home"
            home.mkdir()
            env = dict(os.environ, HOME=str(home), CFFIXED_USER_HOME=str(home))
            frozen = []
            for index, path in enumerate(dependencies):
                copy = work / f"Dependency{index}.swift"
                copy.write_text(path.read_text())
                frozen.append(str(copy))
            actual = work / "Checks.swift"
            actual.write_text(source)
            binary = work / "checks"
            build = subprocess.run(["xcrun", "swiftc", "-parse-as-library", *SWIFT_ISOLATION_FLAGS,
                *frozen, str(actual), "-module-cache-path", str(work / "modules"), "-o", str(binary)],
                capture_output=True, text=True, env=env, timeout=100)
            self.assertEqual(build.returncode, 0, build.stdout + build.stderr)
            run = subprocess.run([str(binary)], capture_output=True, text=True, env=env, timeout=25)
            self.assertEqual(run.returncode, 0, run.stdout + run.stderr)
            checks = json.loads(run.stdout)
            for entry in ("status", "settings"):
                for scenario in (
                    "continuous-positive-volume-sends-one-volume-per-input-without-mute-intent",
                    "crossing-zero-keeps-primary-volume-and-one-mute-transition",
                    "repeated-zero-does-not-reissue-mute-or-nested-volume",
                    "zero-to-positive-unmutes-and-immediately-restores-the-new-volume",
                    "next-positive-input-does-not-repeat-the-unmute-transition",
                    "externally-muted-positive-drag-unmutes-without-restoring-an-old-volume",
                ):
                    self.assertIs(checks[entry + "-" + scenario], True, run.stdout + run.stderr)
            self.assertTrue(checks)
            for name, value in checks.items():
                with self.subTest(name=name):
                    self.assertIs(value, True, run.stdout + run.stderr)
            print(json.dumps(checks, sort_keys=True))
        self.assertEqual(inputs, {str(path): hashlib.sha256(path.read_bytes()).hexdigest() for path in paths})


if __name__ == "__main__":
    unittest.main()
