"""Actual mixed Inspector composition/host tokens and native Quick Look ownership.

Source metadata/layout leaves record actions here; actual Video preview and Steam
layout/invalidation gates remain separate. Image selection uses the real Browser
and App selection callback bodies plus real Coordinator/Quick Look. Image detail
layout, WebKit, network, decoding and wallpaper application are not covered here.
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


def prepare_sil_inspector_sources(tree, work, inspector_override=None, fixture_tree=None):
    """The existing native Inspector closure, also used by the task-only pair."""
    tree, work = Path(tree), Path(work)
    sources = [tree / "MyWallpaperX" / name for name in (
        "Shared/UI/WallpaperInspectorActions.swift", "Shared/UI/InspectorFooterMetrics.swift",
        "Shared/UI/InspectorBadgeView.swift", "Shared/UI/InspectorFadingScrollView.swift",
        "Shared/UI/ModuleFocusable.swift", "Shared/UI/InspectorHost.swift", "Shared/UI/InspectorHostBridge.swift",
        "Shared/UI/InspectorHostActions.swift", "Shared/UI/InspectorHostViewController.swift",
        "Modules/StaticImageLibrary/UI/SILInspectorSupport.swift", "Modules/StaticImageLibrary/UI/SILInspectorView.swift",
        "Modules/OnlineLibrary/UI/OnlineLibraryDownloadsInspectorSupport.swift", "Modules/OnlineLibrary/UI/OnlineLibraryDownloadsInspectorView.swift")]
    if inspector_override is not None:
        sources[sources.index(tree / "MyWallpaperX/Modules/StaticImageLibrary/UI/SILInspectorView.swift")] = Path(inspector_override)
    sources.append((Path(fixture_tree) if fixture_tree is not None else tree) / "script/tests/fixtures/WallpaperInspectorOrganizationHarness.swift")
    inputs = {str(p): hashlib.sha256(p.read_bytes()).hexdigest() for p in [*sources, Path(__file__).resolve()]}
    frozen = []
    for index, source in enumerate(sources):
        target = work / f"Source{index}.swift"
        target.write_bytes(source.read_bytes())
        frozen.append(target)
    return frozen, inputs


@unittest.skipUnless(sys.platform == "darwin", "requires AppKit/Quick Look")
class WallpaperLibraryInspectorTests(unittest.TestCase):
    def test_unbound_image_inspector_cannot_be_constructed(self):
        paths = [ROOT / "MyWallpaperX" / name for name in (
            "Shared/UI/WallpaperInspectorActions.swift", "Shared/UI/InspectorFooterMetrics.swift",
            "Shared/UI/InspectorBadgeView.swift", "Shared/UI/InspectorFadingScrollView.swift",
            "Shared/UI/ModuleFocusable.swift", "Shared/UI/InspectorHost.swift", "Shared/UI/InspectorHostBridge.swift",
            "Shared/UI/InspectorHostActions.swift", "Shared/UI/InspectorHostViewController.swift",
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
            "Core/OnlineImages/OnlineImageModels.swift", "Core/OnlineImages/OnlineImageContentProjection.swift",
            "Core/LibraryCollections/WallpaperLibraryQuery.swift", "Shared/UI/WallpaperInspectorActions.swift",
            "Shared/UI/InspectorHost.swift", "Shared/UI/InspectorHostActions.swift", "Shared/UI/InspectorHostBridge.swift",
            "Shared/UI/InspectorHostViewController.swift", "Shared/UI/ListThumbnailTintSource.swift",
            "Shell/AppKitListBackgroundTint.swift", "Shell/AppKitMainSplitView.swift",
            "App/WallpaperLibraryInspectorCoordinator.swift")]
        sources.append(ROOT / "script/tests/fixtures/OnlineImageLibraryAppStub.swift")
        harness = ROOT / "script/tests/fixtures/WallpaperLibraryInspectorHarness.swift"
        module = ROOT / "MyWallpaperX/Shared/UI/ModuleFocusable.swift"
        commands = ROOT / "MyWallpaperX/App/WallpaperLibraryCommands.swift"
        undo = ROOT / "MyWallpaperX/App/WallpaperLibraryRelationshipUndo.swift"
        popover = ROOT / "MyWallpaperX/Shared/UI/ToolbarMenuPopover.swift"
        image_browser = ROOT / "MyWallpaperX/Shared/UI/OnlineImageBrowserController.swift"
        image_assembly = ROOT / "MyWallpaperX/App/WallpaperLibraryOnlineImages.swift"
        dependencies = sources + [harness, module, commands, undo, popover, image_browser, image_assembly]
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
                    actual = actual.replace("// ACTUAL_IMAGE_BROWSER_SELECTION", declaration(
                        image_browser.read_text(), "        grid.onSelection ="))
                    actual = actual.replace("// ACTUAL_IMAGE_SELECTION_ASSEMBLY", declaration(
                        image_assembly.read_text(), "        browser.onSelectionChange ="))
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
        with tempfile.TemporaryDirectory(prefix="mwx-inspector-actions-", dir="/private/tmp") as directory:
            work = Path(directory)
            frozen, hashes = prepare_sil_inspector_sources(ROOT, work)
            binary = work / "checks"
            result = subprocess.run(["xcrun", "swiftc", "-parse-as-library", "-swift-version", "5", "-default-isolation", "MainActor",
                *map(str, frozen), "-module-cache-path", str(work / "modules"), "-o", str(binary)], capture_output=True, text=True, timeout=150)
            retained = None
            if evidence := os.environ.get("MWX_SIL_INSPECTOR_EVIDENCE"):
                retained = Path(evidence)
                retained.mkdir(parents=True, exist_ok=True)
                for source in frozen:
                    (retained / source.name).write_bytes(source.read_bytes())
                (retained / "inputs.json").write_text(json.dumps(hashes, indent=2) + "\n")
                (retained / "compile.stdout").write_text(result.stdout)
                (retained / "compile.stderr").write_text(result.stderr)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            home = work / "home"; home.mkdir()
            run = subprocess.run([str(binary), str(work)], capture_output=True, text=True, timeout=30,
                env=dict(os.environ, HOME=str(home), CFFIXED_USER_HOME=str(home)))
            self.assertEqual(run.returncode, 0, run.stdout + run.stderr)
            checks = json.loads(run.stdout)
            self.assertGreaterEqual(len(checks), 11)
            for name, passed in checks.items():
                with self.subTest(name=name): self.assertIs(passed, True, run.stdout + run.stderr)
            delivery = subprocess.run([str(binary), str(work), "preview-delivery"], capture_output=True, text=True, timeout=30,
                env=dict(os.environ, HOME=str(home), CFFIXED_USER_HOME=str(home)))
            if retained:
                (retained / "native.stdout").write_text(run.stdout)
                (retained / "native.stderr").write_text(run.stderr)
                (retained / "preview-delivery.stdout").write_text(delivery.stdout)
                (retained / "preview-delivery.stderr").write_text(delivery.stderr)
            self.assertEqual(delivery.returncode, 0, delivery.stdout + delivery.stderr)
            report = json.loads(delivery.stdout)
            for name, passed in report["functional"]["checks"].items():
                with self.subTest(delivery=name): self.assertIs(passed, True, delivery.stdout + delivery.stderr)
            self.assertEqual(report["work"], {"warmReadyAtInitReturn": 1, "delayedReadyAtDeliveryReturn": 1, "deliveredCallbacks": 3})
            print(json.dumps({"previewDelivery": report}, sort_keys=True))
        self.assertEqual(hashes, {p: hashlib.sha256(Path(p).read_bytes()).hexdigest() for p in hashes})

if __name__ == "__main__": unittest.main()
