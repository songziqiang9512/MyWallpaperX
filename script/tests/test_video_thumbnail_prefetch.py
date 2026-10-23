"""Production Video provider demand leases, with controlled asset validation."""
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile
import unittest

from script.tests.native_app_harness import prepare_native_app, run_native_app

ROOT = Path(__file__).resolve().parents[2]

# Match product isolation/conformance inference rather than the compiler defaults.
SWIFT_ISOLATION_FLAGS = ["-swift-version", "5", "-default-isolation", "MainActor"] + [
    argument
    for feature in ["DisableOutwardActorInference", "InferSendableFromCaptures",
                    "GlobalActorIsolatedTypesUsability", "MemberImportVisibility",
                    "InferIsolatedConformances", "NonisolatedNonsendingByDefault"]
    for argument in ["-enable-upcoming-feature", feature]
]


class VideoThumbnailPrefetchTests(unittest.TestCase):
    def test_steam_scheduler_cancellation_and_visible_promotion(self):
        source = (ROOT / 'MyWallpaperX/Modules/SteamWorkshop/Core/SteamWorkshopPreviewRequestCoordinator.swift').read_text()
        start = source.index('nonisolated enum SteamWorkshopPreviewRequestPriority:')
        end = source.index('nonisolated final class SteamWorkshopPreviewLoadCancellation:', start)
        scheduler = source[source.index('actor SteamWorkshopPreviewRequestScheduler {'):]
        with tempfile.TemporaryDirectory(prefix='mwx-steam-preview-demand-', dir='/private/tmp') as directory:
            work = Path(directory)
            actual = work / 'Scheduler.swift'
            actual.write_text('import Foundation\n' + source[start:end] + scheduler + '\n' +
                (ROOT / 'script/tests/fixtures/SteamPreviewSchedulingChecks.swift').read_text())
            binary = work / 'checks'
            build = subprocess.run(['xcrun', 'swiftc', *SWIFT_ISOLATION_FLAGS, '-warnings-as-errors', '-parse-as-library', str(actual),
                '-module-cache-path', str(work / 'modules'), '-o', str(binary)],
                capture_output=True, text=True, timeout=120)
            self.assertEqual(build.returncode, 0, build.stdout + build.stderr)
            run = subprocess.run([str(binary)], capture_output=True, text=True, timeout=20)
            self.assertEqual(run.returncode, 0, run.stdout + run.stderr)
            checks = json.loads(run.stdout)
            if proof := os.environ.get("MWX_VIDEO_PREFETCH_PROOF_DIR"):
                target = Path(proof); target.mkdir(parents=True, exist_ok=True)
                (target / "steam-scheduler.json").write_text(json.dumps(checks, indent=2) + "\n")
                (target / "steam-scheduler-build.log").write_text(build.stdout + build.stderr)
            for name, passed in checks.items():
                with self.subTest(name=name): self.assertTrue(passed)

    def test_validation_handoff_cancel_and_deleted_asset(self):
        provider = (ROOT / 'MyWallpaperX/Modules/VideoLibrary/UI/AppKitLibraryGridSupport.swift').read_text()
        provider = provider[provider.index('enum VideoLibraryThumbnailStore {'):]
        with tempfile.TemporaryDirectory(prefix='mwx-video-demand-', dir='/private/tmp') as directory:
            work = Path(directory)
            actual = work / 'Provider.swift'
            item = (ROOT / 'MyWallpaperX/Modules/VideoLibrary/UI/AppKitLibraryGridItemView.swift').read_text()
            start = item.index('    func configure(')
            end = item.index('    private func setupViews()', start)
            actual.write_text('import AppKit\n' + provider + '\n@MainActor final class VideoCardProbe {\n' +
                (ROOT / 'script/tests/fixtures/VideoCardProbeFields.swift').read_text() + item[start:end] + '\n}')
            shared = ROOT / 'MyWallpaperX/Shared/UI'
            sources = [actual, shared / 'GridThumbnailDecoder.swift', shared / 'DecodedThumbnailMemoryCache.swift',
                       shared / 'ThumbnailCache.swift', ROOT / 'script/tests/fixtures/VideoThumbnailPrefetchChecks.swift']
            binary = work / 'checks'
            build = subprocess.run(['xcrun', 'swiftc', *SWIFT_ISOLATION_FLAGS, '-warnings-as-errors', '-parse-as-library', *map(str, sources),
                '-module-cache-path', str(work / 'modules'), '-o', str(binary)],
                capture_output=True, text=True, timeout=120)
            self.assertEqual(build.returncode, 0, build.stdout + build.stderr)
            run = subprocess.run([str(binary)], env=dict(os.environ, HOME=str(work / 'home'),
                CFFIXED_USER_HOME=str(work / 'home'), VIDEO_DEMAND_ROOT=str(work)),
                capture_output=True, text=True, timeout=30)
            self.assertEqual(run.returncode, 0, run.stdout + run.stderr)
            checks = json.loads(run.stdout)
            if proof := os.environ.get("MWX_VIDEO_PREFETCH_PROOF_DIR"):
                target = Path(proof); target.mkdir(parents=True, exist_ok=True)
                (target / "checks.json").write_text(json.dumps(checks, indent=2) + "\n")
                (target / "build.log").write_text(build.stdout + build.stderr)
                (target / "runtime.log").write_text(run.stderr)
            self.assertGreaterEqual(len(checks), 12)
            for name, passed in checks.items():
                with self.subTest(name=name):
                    self.assertTrue(passed)

    def test_complete_video_card_hover_click_exit_and_restore_never_scale(self):
        ui = ROOT / 'MyWallpaperX/Modules/VideoLibrary/UI'
        shared = ROOT / 'MyWallpaperX/Shared/UI'
        fixtures = ROOT / 'script/tests/fixtures'
        provider = (ui / 'AppKitLibraryGridSupport.swift').read_text()
        provider = provider[provider.index('enum VideoLibraryThumbnailStore {'):]
        # Reuse only the existing model/controlled asset-validation leaves. The
        # complete card (including its real hierarchy/events) replaces no method.
        leaves = (fixtures / 'VideoThumbnailPrefetchChecks.swift').read_text().split('@main struct VideoThumbnailPrefetchChecks {')[0]
        card = re.sub(r"\bprivate\s+", "", (ui / 'AppKitLibraryGridItemView.swift').read_text())
        with tempfile.TemporaryDirectory(prefix='mwx-video-card-interaction-', dir='/private/tmp') as directory:
            work = Path(directory)
            actual = work / 'ActualCard.swift'
            actual.write_text(leaves + '\n' + provider + '\n' + card)
            sources = [actual, fixtures / 'VideoCardInteractionHarness.swift',
                       fixtures / 'GridCardInteractionChecks.swift', fixtures / 'NativeAppHarness.swift', *[shared / name for name in [
                           'GridThumbnailDecoder.swift', 'DecodedThumbnailMemoryCache.swift', 'ThumbnailCache.swift',
                           'AppearanceAwareContainerView.swift', 'NSViewExtensions.swift',
                           'UIInteractionAnimation.swift', 'WallpaperGridScrollView.swift']]]
            binary = prepare_native_app(work, 'VideoCardInteractionChecks')
            build = subprocess.run(['xcrun', 'swiftc', *SWIFT_ISOLATION_FLAGS, '-warnings-as-errors', '-parse-as-library',
                *map(str, sources), '-module-cache-path', str(work / 'modules'), '-o', str(binary)],
                capture_output=True, text=True, timeout=120)
            self.assertEqual(build.returncode, 0, build.stdout + build.stderr)
            run = run_native_app(binary, timeout=30, proof_environment="MWX_VIDEO_PREFETCH_PROOF_DIR")
            if proof := os.environ.get("MWX_VIDEO_PREFETCH_PROOF_DIR"):
                target = Path(proof); target.mkdir(parents=True, exist_ok=True)
                (target / "whole-card-interaction-build.log").write_text(build.stdout + build.stderr)
                (target / "whole-card-interaction.json").write_text(run.stdout)
                (target / "whole-card-interaction-runtime.log").write_text(run.stderr)
            # LaunchServices reports launcher status; this added group does not
            # replace either pre-existing direct-child exit assertion.
            self.assertEqual(run.launch_returncode, 0, run.stdout + run.stderr)
            checks = json.loads(run.stdout)
            self.assertGreaterEqual(len(checks), 17)
            for name, passed in checks.items():
                with self.subTest(name=name): self.assertIs(passed, True)


if __name__ == '__main__':
    unittest.main()
