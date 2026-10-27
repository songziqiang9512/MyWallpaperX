"""Actual mixed Inspector composition/host tokens and native Quick Look ownership.

Source metadata/layout leaves record actions here; actual Video preview and Steam
layout/invalidation gates remain separate. Image selection uses the real Browser
and App selection callback bodies plus real Coordinator/Quick Look. A controlled
thumbnail leaf drives remote A/B, close and scope races through actual PNG export
and the native panel. Image detail layout, WebKit, network and wallpaper application
are not covered by this composition gate.
The original image/Pixabay layout gate also runs the real downloaded thumbnail
store, file fingerprints and shared cache, with only its AV frame leaf controlled
and public cache registrations/completions observed. Its HOME/cache namespace is isolated.
"""
import hashlib
import json
import os
import plistlib
import re
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from script.tests.test_ui_library_algorithms import declaration
from script.tests.native_app_harness import prepare_native_app, run_native_app

ROOT = Path(__file__).resolve().parents[2]
DOWNLOADED_STORE = ROOT / "MyWallpaperX/Modules/OnlineLibrary/UI/AppKitOLDownloadsItem.swift"
DOWNLOADED_IDENTITY = ROOT / "MyWallpaperX/Modules/OnlineLibrary/Core/OnlineLibraryDownloadedContent.swift"
DOWNLOADED_CARD_DEPENDENCIES = [ROOT / "MyWallpaperX" / name for name in (
    "Shared/UI/AppearanceAwareContainerView.swift", "Shared/UI/NSViewExtensions.swift",
    "Shared/UI/UIInteractionAnimation.swift", "Shared/UI/WallpaperGridScrollView.swift",
    "Shared/Components/WallpaperCardInteractionView.swift", "Shared/Components/WallpaperCardSupportViews.swift",
    "Shared/Components/WallpaperCardControlsView.swift")]


def original_inspector_gate_source(path, tree=ROOT):
    tree = Path(tree)
    downloaded_store = tree / "MyWallpaperX/Modules/OnlineLibrary/UI/AppKitOLDownloadsItem.swift"
    downloaded_identity = tree / "MyWallpaperX/Modules/OnlineLibrary/Core/OnlineLibraryDownloadedContent.swift"
    content = path.read_text()
    if path == downloaded_store:
        # The store is inserted below with its real identity/cache. Expose only
        # the actual card's private UI state; none of its methods are replaced.
        return "import AppKit\nimport QuartzCore\n" + re.sub(r"\bprivate\s+", "",
            declaration(content, "final class AppKitOLDownloadsItem:"))
    if path.name == "WallpaperInspectorOrganizationHarness.swift":
        cache = (tree / "MyWallpaperX/Shared/UI/ThumbnailCache.swift").read_text()
        begin = declaration(cache, "    private func beginImageRequest(")
        delivery = declaration(begin, "        let deliver: (NSImage?) -> Void =")
        if content.count("// ACTUAL_CACHE_IMAGE_DELIVERY") != 1:
            raise ValueError("expected one real cache delivery insertion point")
        content = content.replace("// ACTUAL_CACHE_IMAGE_DELIVERY", delivery)
        store = downloaded_store.read_text()
        actual = declaration(downloaded_identity.read_text(), "nonisolated enum OnlineLibraryDownloadedFileIdentity")
        fingerprint = "        var fileURL = url.standardizedFileURL"
        if actual.count(fingerprint) != 1:
            raise ValueError("expected one real downloaded fingerprint read")
        actual = actual.replace(fingerprint,
            "        DownloadedInspectorCacheProbe.shared.fingerprintRegistered(url.path)\n" + fingerprint, 1)
        actual += "\n" + declaration(store, "enum OLDownloadedThumbnailStore")
        actual += "\n" + declaration(store, "extension OLDownloadedThumbnailStore")
        method = declaration(actual, "    static func loadThumbnail(")
        observed = method.replace("        guard !cancellation.cancelled",
            "        DownloadedInspectorCacheProbe.shared.sourceRegistered()\n        guard !cancellation.cancelled", 1)
        if method == observed:
            raise ValueError("expected original downloaded source admission")
        actual = actual.replace(method, observed, 1)
        if content.count("// ACTUAL_DOWNLOADED_STORE") != 1:
            raise ValueError("expected one real downloaded store insertion point")
        content = content.replace("// ACTUAL_DOWNLOADED_STORE", actual)
    elif path.name == "ThumbnailCache.swift":
        method = declaration(content, "    func loadImageAsync(")
        boundary = "        guard let request = beginImageRequest"
        if method.count(boundary) != 1:
            raise ValueError("expected original public async cache admission")
        observed = method.replace(boundary,
            "        DownloadedInspectorCacheProbe.shared.registered(key, priority: priority, cancellation: cancellation)\n"
            "        let originalCompletion = completion\n"
            "        let completion: (NSImage?) -> Void = { image in\n"
            "            DownloadedInspectorCacheProbe.shared.completed(cancellation, image: image)\n"
            "            originalCompletion(image)\n"
            "        }\n" + boundary, 1)
        content = content.replace(method, observed, 1)
    return content


def prepare_sil_inspector_sources(tree, work, inspector_override=None, fixture_tree=None):
    """The existing native Inspector closure, also used by the task-only pair."""
    tree, work = Path(tree), Path(work)
    downloaded_store = tree / "MyWallpaperX/Modules/OnlineLibrary/UI/AppKitOLDownloadsItem.swift"
    downloaded_identity = tree / "MyWallpaperX/Modules/OnlineLibrary/Core/OnlineLibraryDownloadedContent.swift"
    sources = [tree / "MyWallpaperX" / name for name in (
        "Shared/UI/DecodedThumbnailMemoryCache.swift", "Shared/UI/ThumbnailCache.swift",
        "Shared/UI/WallpaperInspectorActions.swift", "Shared/UI/InspectorFooterMetrics.swift",
        "Shared/UI/InspectorBadgeView.swift", "Shared/UI/InspectorFadingScrollView.swift",
        "Shared/UI/ModuleFocusable.swift", "Shared/UI/InspectorHost.swift", "Shared/UI/InspectorHostBridge.swift",
        "Shared/UI/InspectorHostActions.swift", "Shared/UI/InspectorHostViewController.swift",
        "Modules/StaticImageLibrary/UI/SILInspectorSupport.swift", "Modules/StaticImageLibrary/UI/SILInspectorView.swift",
        "Modules/OnlineLibrary/UI/OnlineLibraryDownloadsInspectorSupport.swift", "Modules/OnlineLibrary/UI/OnlineLibraryDownloadsInspectorView.swift")]
    if inspector_override is not None:
        sources[sources.index(tree / "MyWallpaperX/Modules/StaticImageLibrary/UI/SILInspectorView.swift")] = Path(inspector_override)
    sources += [tree / path.relative_to(ROOT) for path in DOWNLOADED_CARD_DEPENDENCIES]
    sources.append(downloaded_store)
    sources.append((Path(fixture_tree) if fixture_tree is not None else tree) / "script/tests/fixtures/WallpaperInspectorOrganizationHarness.swift")
    inputs = {str(p): hashlib.sha256(p.read_bytes()).hexdigest() for p in [*sources, downloaded_identity, Path(__file__).resolve()]}
    frozen = []
    for index, source in enumerate(sources):
        target = work / f"Source{index}.swift"
        target.write_text(original_inspector_gate_source(source, tree))
        frozen.append(target)
    return frozen, inputs


@unittest.skipUnless(sys.platform == "darwin", "requires AppKit/Quick Look")
class WallpaperLibraryInspectorTests(unittest.TestCase):
    def test_unbound_image_inspector_cannot_be_constructed(self):
        paths = [ROOT / "MyWallpaperX" / name for name in (
            "Shared/UI/DecodedThumbnailMemoryCache.swift", "Shared/UI/ThumbnailCache.swift",
            "Shared/UI/WallpaperInspectorActions.swift", "Shared/UI/InspectorFooterMetrics.swift",
            "Shared/UI/InspectorBadgeView.swift", "Shared/UI/InspectorFadingScrollView.swift",
            "Shared/UI/ModuleFocusable.swift", "Shared/UI/InspectorHost.swift", "Shared/UI/InspectorHostBridge.swift",
            "Shared/UI/InspectorHostActions.swift", "Shared/UI/InspectorHostViewController.swift",
            "Modules/StaticImageLibrary/UI/SILInspectorSupport.swift", "Modules/StaticImageLibrary/UI/SILInspectorView.swift",
            "Modules/OnlineLibrary/UI/OnlineLibraryDownloadsInspectorSupport.swift", "Modules/OnlineLibrary/UI/OnlineLibraryDownloadsInspectorView.swift")]
        paths += [*DOWNLOADED_CARD_DEPENDENCIES, DOWNLOADED_STORE,
                  ROOT / "script/tests/fixtures/WallpaperInspectorOrganizationHarness.swift"]
        observed = [*paths, DOWNLOADED_STORE, DOWNLOADED_IDENTITY, Path(__file__)]
        hashes = {str(p): hashlib.sha256(p.read_bytes()).hexdigest() for p in observed}
        with tempfile.TemporaryDirectory(prefix="mwx-image-inspector-required-actions-", dir="/private/tmp") as directory:
            work = Path(directory)
            frozen = []
            for index, path in enumerate(paths):
                target = work / f"Source{index}.swift"; target.write_text(original_inspector_gate_source(path)); frozen.append(target)
            misuse = work / "UnboundInspector.swift"
            misuse.write_text("import AppKit\n@MainActor func cannotBindLegacyOwner(_ value:SILWallpaper,_ service:SILService) {\n"
                "_ = SILInspectorView(wallpaper:value,service:service)\n}\n")
            check = subprocess.run(["xcrun", "swiftc", "-parse-as-library", "-swift-version", "5", "-default-isolation", "MainActor", "-typecheck",
                *map(str, frozen), str(misuse), "-module-cache-path", str(work / "modules")], capture_output=True, text=True, timeout=120)
            self.assertNotEqual(check.returncode, 0, check.stdout + check.stderr)
            self.assertIn("missing argument for parameter 'libraryActions'", check.stderr)
        self.assertEqual(hashes, {str(p): hashlib.sha256(p.read_bytes()).hexdigest() for p in observed})

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
        sources.append(ROOT / "script/tests/fixtures/NativeAppHarness.swift")
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
                    actual = actual.replace("// ACTUAL_IMAGE_BROWSER_ESCAPE", declaration(
                        image_browser.read_text(), "        grid.onEscape ="))
                    actual = actual.replace("// ACTUAL_IMAGE_SELECTION_ASSEMBLY", declaration(
                        image_assembly.read_text(), "        browser.onSelectionChange ="))
                    actual = actual.replace("// ACTUAL_IMAGE_ESCAPE_ASSEMBLY", declaration(
                        image_assembly.read_text(), "        browser.onEscape ="))
                    target.write_text(actual)
                else:
                    target.write_bytes(source.read_bytes())
                frozen.append(target)
            binary = prepare_native_app(work, "InspectorChecks")
            result = subprocess.run(["xcrun", "swiftc", "-parse-as-library", "-swift-version", "5", "-default-isolation", "MainActor",
                *map(str, frozen), str(helpers), "-module-cache-path", str(work / "modules"), "-o", str(binary)],
                capture_output=True, text=True, timeout=150)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            run = run_native_app(binary, [str(work)], timeout=45)
            self.assertEqual(run.launch_returncode, 0, run.stdout + run.stderr)
            self.assertTrue(run.stdout.strip(), run.stderr)
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
            self.assertTrue(checks["image-same-reference-late-dimensions-and-last-used-refresh-in-place"])
            self.assertTrue(checks["image-inspector-keeps-negative-cache-read-and-write-disabled"])
            self.assertTrue(checks["image-metadata-and-action-echoes-do-not-reload-preview-or-rebuild-unchanged-content"])
            self.assertTrue(checks["image-unmount-cancels-its-consumer-without-reacquiring-offscreen"])
            self.assertTrue(checks["image-remount-reacquires-one-lease-and-keeps-the-current-preview"])
            self.assertTrue(checks["image-source-change-reloads-only-the-new-path"])
            self.assertTrue(checks["image-a-b-a-current-request-delivers-real-red-preview"])
            self.assertTrue(checks["image-a-b-a-old-same-path-and-other-source-late-deliveries-cannot-overwrite-current-pixels"])
            self.assertTrue(checks["pixabay-cold-visible-demand-fills-only-the-existing-preview"])
            self.assertTrue(checks["pixabay-action-and-relationship-echoes-keep-document-and-image-demand"])
            self.assertTrue(checks["pixabay-same-id-metadata-refreshes-without-reloading-preview"])
            self.assertTrue(checks["pixabay-closed-consumer-rejects-late-frame-and-remounts-once"])
            self.assertTrue(checks["pixabay-shared-producer-survives-one-inspector-leaving"])
            self.assertTrue(checks["pixabay-source-replacement-cancels-old-consumer-and-retains-current-image-while-loading"])
            self.assertTrue(checks["pixabay-current-source-fills-in-place-and-ignores-unchanged-publication"])
            self.assertTrue(checks["pixabay-same-path-new-fingerprint-fills-current-image-without-changing-preview-object"])
            self.assertTrue(checks["pixabay-real-visible-first-queued-replacement-rejects-before-generation"])
            self.assertTrue(checks["pixabay-real-card-inspector-and-near-share-one-producer-and-survive-card-exit"])
            self.assertTrue(checks["pixabay-real-card-and-inspector-ignore-a-warm-old-scan-hint"])
            self.assertTrue(checks["pixabay-current-warm-card-remount-and-action-echo-preserve-pixels-without-av"])
            self.assertTrue(checks["pixabay-real-card-admission-resolves-one-live-key-off-main"])
            self.assertTrue(checks["pixabay-active-first-card-and-inspector-finish-once-with-nil-after-source-change"])
            self.assertTrue(checks["pixabay-next-actual-card-demand-reads-current-source-after-uncached-nil"])
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
            self.assertIs(report["functional"]["checks"]["cancelledReleasedRequestDoesNotInvokeCallback"], True)
            self.assertEqual(report["functional"]["completionThreads"], [True, True])
            self.assertEqual(len(report["functional"]["requestedKeys"]), 3)
            self.assertEqual(report["work"], {"warmReadyAtInitReturn": 1, "delayedReadyAtDeliveryReturn": 1,
                                             "deliveredCallbacks": 2, "suppressedCallbacks": 1})
            print(json.dumps({"previewDelivery": report}, sort_keys=True))
        self.assertEqual(hashes, {p: hashlib.sha256(Path(p).read_bytes()).hexdigest() for p in hashes})

if __name__ == "__main__": unittest.main()
