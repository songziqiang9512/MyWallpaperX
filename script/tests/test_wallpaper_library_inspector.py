"""Actual mixed Inspector composition/host tokens and native Quick Look ownership.

Source metadata/layout leaves record actions here; actual Video preview and Steam
layout/invalidation gates remain separate. No library, decoder or renderer runs.
"""
import hashlib
import json
import os
import plistlib
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from script.tests.test_ui_library_algorithms import declaration

ROOT = Path(__file__).resolve().parents[2]

@unittest.skipUnless(sys.platform == "darwin", "requires AppKit/Quick Look")
class WallpaperLibraryInspectorTests(unittest.TestCase):
    def test_unbound_image_inspector_cannot_be_constructed(self):
        paths = [ROOT / "MyWallpaperX" / name for name in (
            "Shared/UI/WallpaperInspectorActions.swift", "Shared/UI/InspectorFooterMetrics.swift",
            "Shared/UI/InspectorBadgeView.swift", "Shared/UI/InspectorFadingScrollView.swift",
            "Modules/StaticImageLibrary/UI/SILInspectorSupport.swift", "Modules/StaticImageLibrary/UI/SILInspectorView.swift",
            "Modules/OnlineLibrary/UI/OnlineLibraryDownloadsInspectorSupport.swift", "Modules/OnlineLibrary/UI/OnlineLibraryDownloadsInspectorView.swift")]
        paths.append(ROOT / "script/tests/fixtures/WallpaperInspectorOrganizationHarness.swift")
        hashes = {str(p): hashlib.sha256(p.read_bytes()).hexdigest() for p in paths}
        with tempfile.TemporaryDirectory(prefix="mwx-image-inspector-required-actions-", dir="/private/tmp") as directory:
            work = Path(directory)
            frozen = []
            for index, path in enumerate(paths):
                target = work / f"Source{index}.swift"; target.write_bytes(path.read_bytes()); frozen.append(target)
            misuse = work / "UnboundInspector.swift"
            misuse.write_text("import AppKit\n@MainActor func cannotBindLegacyOwner(_ value:SILWallpaper,_ service:SILService) {\n"
                "_ = SILInspectorView(wallpaper:value,service:service)\n}\n")
            check = subprocess.run(["xcrun", "swiftc", "-parse-as-library", "-swift-version", "5", "-default-isolation", "MainActor", "-typecheck",
                *map(str, frozen), str(misuse), "-module-cache-path", str(work / "modules")], capture_output=True, text=True, timeout=120)
            self.assertNotEqual(check.returncode, 0, check.stdout + check.stderr)
            self.assertIn("missing argument for parameter 'libraryActions'", check.stderr)
        self.assertEqual(hashes, {str(p): hashlib.sha256(p.read_bytes()).hexdigest() for p in paths})

    def test_fixed_identity_host_and_native_preview(self):
        sources = [ROOT / "MyWallpaperX" / name for name in (
            "Models/WallpaperReference.swift", "Models/WallpaperContent.swift", "Models/WallpaperLibraryPage.swift",
            "Core/LibraryCollections/WallpaperLibraryQuery.swift", "Shared/UI/WallpaperInspectorActions.swift",
            "Shared/UI/InspectorHost.swift", "Shared/UI/InspectorHostActions.swift", "Shared/UI/InspectorHostBridge.swift",
            "Shared/UI/InspectorHostViewController.swift", "Shared/UI/ListThumbnailTintSource.swift",
            "Shell/AppKitListBackgroundTint.swift", "Shell/AppKitMainSplitView.swift",
            "App/WallpaperLibraryInspectorCoordinator.swift")]
        harness = ROOT / "script/tests/fixtures/WallpaperLibraryInspectorHarness.swift"
        module = ROOT / "MyWallpaperX/Shared/UI/ModuleFocusable.swift"
        commands = ROOT / "MyWallpaperX/App/WallpaperLibraryCommands.swift"
        undo = ROOT / "MyWallpaperX/App/WallpaperLibraryRelationshipUndo.swift"
        popover = ROOT / "MyWallpaperX/Shared/UI/ToolbarMenuPopover.swift"
        dependencies = sources + [harness, module, commands, undo, popover]
        hashes = {str(p): hashlib.sha256(p.read_bytes()).hexdigest() for p in dependencies}
        with tempfile.TemporaryDirectory(prefix="mwx-inspector-", dir="/private/tmp") as directory:
            work = Path(directory)
            helpers = work / "HostProtocol.swift"
            content = module.read_text()
            start = content.index("enum ModuleIdentifier: String {")
            end = content.index("}", start) + 1
            helpers.write_text("import Foundation\n" + content[start:end] + "\n" + declaration(
                popover.read_text(), "protocol ToolbarGridScrollDismissalSurface:") + "\n" + "extension Notification.Name {\n" + "\n".join(
                f' static let {name} = Notification.Name("{name}")' for name in (
                    "inspectorHostOpenRequested", "inspectorHostCloseRequested", "inspectorHostMountContentRequested",
                    "inspectorHostDidPresent", "inspectorHostDidClose")) + "\n}\n")
            frozen = []
            for index, source in enumerate(sources + [harness]):
                target = work / f"Source{index}.swift"
                if source == harness:
                    actual = source.read_text().replace("// ACTUAL_FAVORITE_ACTION_STATE", declaration(
                        commands.read_text(), "nonisolated struct WallpaperLibraryFavoriteActionState"))
                    actual = actual.replace("// ACTUAL_RELATIONSHIP_UNDO_MANAGER", declaration(
                        undo.read_text(), "@MainActor final class RelationshipUndoManager:"))
                    target.write_text(actual)
                else:
                    target.write_bytes(source.read_bytes())
                frozen.append(target)
            contents = work / "InspectorChecks.app/Contents"
            (contents / "MacOS").mkdir(parents=True)
            (contents / "Info.plist").write_bytes(plistlib.dumps({"CFBundleExecutable": "checks",
                "CFBundleIdentifier": "com.mywallpaperx.tests.inspector-preview", "CFBundleName": "Inspector Checks", "CFBundlePackageType": "APPL"}))
            binary = contents / "MacOS/checks"
            result = subprocess.run(["xcrun", "swiftc", "-parse-as-library", "-swift-version", "5", "-default-isolation", "MainActor",
                *map(str, frozen), str(helpers), "-module-cache-path", str(work / "modules"), "-o", str(binary)],
                capture_output=True, text=True, timeout=150)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            home = work / "home"; home.mkdir()
            run = subprocess.run([str(binary), str(work)], capture_output=True, text=True, timeout=40,
                env=dict(os.environ, HOME=str(home), CFFIXED_USER_HOME=str(home)))
            self.assertEqual(run.returncode, 0, run.stdout + run.stderr)
            checks = json.loads(run.stdout)
            self.assertGreaterEqual(len(checks), 21)
            for name, passed in checks.items():
                with self.subTest(name=name): self.assertIs(passed, True, run.stdout + run.stderr)
        self.assertEqual(hashes, {str(p): hashlib.sha256(p.read_bytes()).hexdigest() for p in dependencies})

    def test_original_image_and_pixabay_views_use_injected_actions(self):
        sources = [ROOT / "MyWallpaperX" / name for name in (
            "Shared/UI/WallpaperInspectorActions.swift", "Shared/UI/InspectorFooterMetrics.swift",
            "Shared/UI/InspectorBadgeView.swift", "Shared/UI/InspectorFadingScrollView.swift",
            "Modules/StaticImageLibrary/UI/SILInspectorSupport.swift", "Modules/StaticImageLibrary/UI/SILInspectorView.swift",
            "Modules/OnlineLibrary/UI/OnlineLibraryDownloadsInspectorSupport.swift", "Modules/OnlineLibrary/UI/OnlineLibraryDownloadsInspectorView.swift")]
        sources.append(ROOT / "script/tests/fixtures/WallpaperInspectorOrganizationHarness.swift")
        hashes = {str(p): hashlib.sha256(p.read_bytes()).hexdigest() for p in sources}
        with tempfile.TemporaryDirectory(prefix="mwx-inspector-actions-", dir="/private/tmp") as directory:
            work = Path(directory)
            frozen = []
            for index, source in enumerate(sources):
                target = work / f"Source{index}.swift"
                target.write_bytes(source.read_bytes()); frozen.append(target)
            binary = work / "checks"
            result = subprocess.run(["xcrun", "swiftc", "-parse-as-library", "-swift-version", "5", "-default-isolation", "MainActor",
                *map(str, frozen), "-module-cache-path", str(work / "modules"), "-o", str(binary)], capture_output=True, text=True, timeout=150)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            home = work / "home"; home.mkdir()
            run = subprocess.run([str(binary), str(work)], capture_output=True, text=True, timeout=30,
                env=dict(os.environ, HOME=str(home), CFFIXED_USER_HOME=str(home)))
            self.assertEqual(run.returncode, 0, run.stdout + run.stderr)
            checks = json.loads(run.stdout)
            self.assertGreaterEqual(len(checks), 11)
            for name, passed in checks.items():
                with self.subTest(name=name): self.assertIs(passed, True, run.stdout + run.stderr)
        self.assertEqual(hashes, {str(p): hashlib.sha256(p.read_bytes()).hexdigest() for p in sources})

if __name__ == "__main__": unittest.main()
