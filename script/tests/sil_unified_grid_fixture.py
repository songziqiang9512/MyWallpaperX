"""Assemble the real SIL card/provider, App adapter and unified native grid.

Other providers are recording leaves shared with the adapter gate. Test copies
only expose state, optionally inject a bounded original cache and count native
layout invalidation; no retired grid/controller implementation is retained.
"""
from pathlib import Path
import re

from script.tests.test_ui_library_algorithms import declaration

ROOT = Path(__file__).resolve().parents[2]


def assemble(work: Path, *, count_layout=False, count_collection=False, cache_name=None, observe_loads=False, observe_configures=False, observe_failure_signatures=False):
    app = ROOT / "MyWallpaperX"
    model_path = app / "Modules/StaticImageLibrary/Core/SILService.swift"
    card_path = app / "Modules/StaticImageLibrary/UI/SILGridItemView.swift"
    provider_path = app / "Modules/StaticImageLibrary/UI/SILThumbnailProvider.swift"
    adapter_path = app / "App/WallpaperLibraryCellAdapter.swift"
    grid_path = app / "Shell/WallpaperLibraryGridController.swift"
    leaves_path = ROOT / "script/tests/fixtures/WallpaperLibraryCellAdapterHarness.swift"
    online_card_path = app / "Shared/UI/OnlineImageGridItem.swift"
    online_library_stub = ROOT / "script/tests/fixtures/OnlineImageLibraryAppStub.swift"
    product_model = model_path.read_text()
    model = "import AppKit\n" + declaration(product_model, "struct SILWallpaper:") + "\n"
    model += declaration(product_model, "enum SILThumbnailStore")
    card = "import AppKit\nimport QuartzCore\n" + re.sub(r"\bprivate\s+", "", declaration(card_path.read_text(), "final class SILGridItem:"))
    if observe_configures:
        start = "        wallpaperID = wallpaper.id"
        assert card.count(start) == 1
        card = card.replace(start, "        SILCardObservation.configurations += 1\n" + start)
    provider = provider_path.read_text()
    if observe_failure_signatures:
        signature = "nonisolated func silGridThumbnailFailureSignature(atPath path: String) -> String? {"
        assert provider.count(signature) == 1
        provider = provider.replace(signature, signature + "\n    SILSignatureReads.shared.record()", 1)
        image = "nonisolated func silGridThumbnailImage(atPath path: String) -> NSImage? {"
        assert provider.count(image) == 1
        provider = provider.replace(image, image + "\n    SILSignatureReads.shared.recordDecode()", 1)
        failure_boundary = "                            decodeFailureSignature.store(signature)"
        assert provider.count(failure_boundary) == 1
        provider = provider.replace(failure_boundary,
            "                            SILFailureDeliveryProbe.shared.waitIfHeld(path)\n" + failure_boundary, 1)
        failures = "    private var failureSourceSignatures: [String: String] = [:]"
        assert provider.count(failures) == 1
        # Read-only observation in the compiled copy. Negative entries below
        # still come exclusively from the real ImageIO failure path.
        provider = provider.replace(failures, failures + "\n    var recordedFailureSignatures: Set<String> { Set(failureSourceSignatures.values) }", 1)
    if observe_loads:
        signature = "        // 内存快路径：命中直接同步完成，零文件系统调用、零队列跳转"
        assert provider.count(signature) == 1
        provider = provider.replace(signature, "        SILLoadObservation.started(path, cancellation, priority: priority)\n"
            "        let originalCompletion = completion\n"
            "        let completion: (SILThumbnailLoadResult) -> Void = { result in\n"
            "            SILLoadObservation.finished(cancellation); originalCompletion(result)\n"
            "        }\n" + signature)
    adapter = re.sub(r"\bprivate\s+", "", adapter_path.read_text())
    if cache_name:
        constructor = "let imageThumbnails = SILThumbnailProvider()"
        assert adapter.count(constructor) == 1
        adapter = adapter.replace(constructor, f"let imageThumbnails = SILThumbnailProvider(cache: {cache_name})")
    grid = re.sub(r"\bprivate\s+", "", grid_path.read_text())
    if count_layout:
        constructor = "let layout = NSCollectionViewFlowLayout()"
        assert grid.count(constructor) == 1
        grid = grid.replace(constructor, "let layout = CountingFlowLayout()")
    if count_collection:
        constructor = "let collection = WallpaperLibraryCollectionView()"
        assert grid.count(constructor) == 1
        grid = grid.replace(constructor, "let collection = CountingLibraryCollectionView()")
        grid = grid.replace("final class WallpaperLibraryCollectionView:", "class WallpaperLibraryCollectionView:")
    leaves = leaves_path.read_text()
    signatures = (
        "final class WallpaperManager", "final class SILService", "struct SteamWorkshopBrowserItem:",
        "struct SteamWorkshopDownloadRecord:", "final class SteamWorkshopDownloadProgressStore",
        "final class SteamWorkshopService", "struct OLDownloadedEntry:", "struct DownloadedSnapshot",
        "final class OnlineLibraryService", "enum SteamWorkshopDownloadGridSupport",
        "final class AppKitThumbnailProvider", "final class RecordingThumbnailCache", "enum OLDownloadedThumbnailStore",
        "func steamWorkshopPreviewSources(", "final class SteamWorkshopPreviewState",
        "class RecordingCard:", "final class AppKitWallpaperItem:", "final class AppKitOLDownloadsItem:",
        "final class AppKitSteamWorkshopBrowserItem:", "private enum RecordingProgressStyle",
        "private final class RecordingImageGlass", "private final class RecordingImageBar",
        "final class OnlineImageGridItem:")
    other = "import AppKit\n" + "\n".join(declaration(leaves, signature) for signature in signatures)
    # Online images remain a recording source leaf, as in the full App adapter
    # gate. Retain its actual transfer method without copying that gate's main
    # harness or the unrelated Commands menu probes.
    marker = "// ACTUAL_IMAGE_TRANSFER"
    assert other.count(marker) == 1
    other = other.replace(marker, declaration(online_card_path.read_text(), "    func applyTransfer("))
    assert "// ACTUAL_" not in other
    generated = {"SILModel.swift": model, "SILCard.swift": card, "SILProvider.swift": provider,
                 "Adapter.swift": adapter, "Grid.swift": grid, "OtherProviderLeaves.swift": other}
    sources = []
    for name, value in generated.items():
        path = work / name
        path.write_text(value)
        sources.append(path)
    original = [model_path, card_path, provider_path, adapter_path, grid_path, leaves_path,
                online_card_path, Path(__file__).resolve()]
    dependencies = [app / name for name in (
        "Models/VideoWallpaper.swift", "Models/WallpaperReference.swift", "Models/WallpaperContent.swift",
        "Core/OnlineImages/OnlineImageModels.swift", "Core/OnlineImages/OnlineImageContentProjection.swift",
        "Models/WallpaperLibraryPage.swift", "Modules/StaticImageLibrary/Core/StaticImageLibraryContentProjection.swift",
        "Shared/UI/DecodedThumbnailMemoryCache.swift",
        "Shared/UI/GridThumbnailDecoder.swift", "Shared/UI/ThumbnailCache.swift",
        "Shared/UI/AppearanceAwareContainerView.swift", "Shared/UI/NSViewExtensions.swift",
        "Shared/UI/UIInteractionAnimation.swift", "Shared/UI/WallpaperGridScrollView.swift",
        "Shared/UI/BoxSelectionState.swift", "Shared/UI/GridThumbnailPrefetchDemand.swift",
        "Shared/Components/WallpaperCardInteractionView.swift", "Shared/Components/WallpaperCardSupportViews.swift",
        "Shared/Components/WallpaperCardControlsView.swift", "Shared/Components/WallpaperLibraryGridMetrics.swift")]
    dependencies.append(online_library_stub)
    return sources + dependencies, original + dependencies
