#!/usr/bin/env python3

"""Behavior gate: download progress ticks must not restart card animations.

Every visible downloading card receives progress snapshots several times a
second. The contracts locked here (each observable at runtime, not by source
shape):

- an in-flight indeterminate bar sweep is never removed and re-added when the
  applied progress inputs are unchanged, and disappears only when the state
  actually leaves indeterminate,
- the title marquee keeps its running scroll across text-only updates
  (per-tick "12% -> 13% ..." rewrites), and across duplicate snapshot
  replays,
- a duplicate snapshot delivery (rebind replay) is a full no-op for the card.
"""

from __future__ import annotations

import pathlib
import subprocess
import tempfile
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[2]
UI = ROOT / "MyWallpaperX/Modules/SteamWorkshop/UI"
CORE = ROOT / "MyWallpaperX/Modules/SteamWorkshop/Core"
SHARED_UI = ROOT / "MyWallpaperX/Shared/UI"

SOURCES = [
    UI / "AppKitSteamWorkshopBrowserItem.swift",
    UI / "AppKitSteamWorkshopBrowserItem+Presentation.swift",
    UI / "AppKitSteamWorkshopBrowserItemSupportViews.swift",
    UI / "SteamWorkshopPreviewPlaceholderView.swift",
    CORE / "SteamWorkshopPreviewImageSupport.swift",
    CORE / "SteamWorkshopPreviewRequestCoordinator.swift",
    CORE / "SteamWorkshopModels.swift",
    CORE / "SteamWorkshopDownloadProgress.swift",
    CORE / "SteamWorkshopDownloadThumbnailPipeline.swift",
    SHARED_UI / "UIInteractionAnimation.swift",
    SHARED_UI / "AppearanceAwareContainerView.swift",
    SHARED_UI / "NSViewExtensions.swift",
    SHARED_UI / "ThumbnailCache.swift",
]

SUPPORT = r'''
import AppKit
import Combine
import Foundation

final class SteamWorkshopService {
    static let shared = SteamWorkshopService()
    let steamAuth = SteamAuthProbe()
    let steamSubscriptions = SteamSubscriptionsProbe()
    @Published var source: Int = 0
    @MainActor let downloadProgressStore = SteamWorkshopDownloadProgressStore()
    func presentSteamLoginForUserAction(context: String) {}
    func latestDownloadRecord(for id: String) -> SteamWorkshopDownloadRecord? { nil }
    func isDownloading(itemID: String) -> Bool { false }
    // f140ee42 让卡片解析"下载失败意图"文案（真实实现 +DownloadFiltering.swift），
    // 本 fixture 编译整份 BrowserItem，需要同名入口保持无操作。
    func failedDownloadIntentMessage(for id: String) -> String? { nil }
    func isDownloaded(itemID: String) -> Bool { false }
    func isRecordCurrentlyPlaying(_ record: SteamWorkshopDownloadRecord) -> Bool { false }
    func isLaunchPending(_ id: String) -> Bool { false }
}

final class SteamAuthProbe {
    var isOnline: Bool { false }
}

enum SteamSubscriptionProbeState: Equatable {
    case known(Bool)
    case loading
    case writing
    case reconciling
}

final class SteamSubscriptionsProbe {
    @Published var states: [String: SteamSubscriptionProbeState] = [:]
    func state(for id: String) -> SteamSubscriptionProbeState { states[id] ?? .known(false) }
    func toggle(_ id: String) {}
    func refresh(_ id: String) {}
}

enum SteamWorkshopItemMenu {
    static func make(item: SteamWorkshopBrowserItem, service: SteamWorkshopService) -> NSMenu {
        NSMenu()
    }
}

enum PlaybackCommand { case stop }
enum PlaybackEngineTarget { case scene, video }
final class PlaybackCommandMultiplexer {
    static let shared = PlaybackCommandMultiplexer()
    func dispatch(_ command: PlaybackCommand, to target: PlaybackEngineTarget) {}
}

// Mirror of the Web/Core validation enum referenced by the shared models.
enum SteamWorkshopWebDependencyStatus: Equatable {
    case none
    case available(itemID: String)
    case missing(itemID: String)
}
'''

HARNESS = r'''
import AppKit
import Foundation

@main struct Harness {
    @MainActor static func main() {
        _ = NSApplication.shared
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 260),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.setFrameOrigin(NSPoint(x: 14_000, y: 14_000))
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: 260))
        window.contentView = container
        window.orderFrontRegardless()

        // -- GlassBar: an unchanged indeterminate sweep is never restarted --
        let bar = SteamWorkshopGlassBarView(frame: NSRect(x: 0, y: 0, width: 200, height: 28))
        container.addSubview(bar)
        bar.layoutSubtreeIfNeeded()
        bar.setProgressAnimationVisible(true)
        bar.applyProgress(style: .downloading, fraction: nil, indeterminate: true, animated: false)
        guard let firstSweep = bar.activeIndeterminateAnimation else {
            fputs("expected a running indeterminate sweep\n", stderr)
            exit(1)
        }
        bar.applyProgress(style: .downloading, fraction: nil, indeterminate: true, animated: false)
        bar.setProgressAnimationVisible(true)
        precondition(bar.activeIndeterminateAnimation === firstSweep, "unchanged progress inputs restarted the sweep")
        bar.applyProgress(style: .downloading, fraction: 0.5, indeterminate: false, animated: false)
        precondition(bar.activeIndeterminateAnimation == nil, "determinate progress must stop the sweep")
        bar.applyProgress(style: .downloading, fraction: nil, indeterminate: true, animated: false)
        guard let secondSweep = bar.activeIndeterminateAnimation, secondSweep !== firstSweep else {
            fputs("re-entering indeterminate must start a fresh sweep\n", stderr)
            exit(1)
        }

        // -- Card: marquee keeps scrolling across text-only progress ticks --
        let item = SteamWorkshopBrowserItem(
            id: "probe-item",
            title: "Probe Wallpaper",
            author: "Probe Author",
            authorProfileURL: nil,
            authorWorkshopURL: nil,
            hasAdultContent: false,
            summary: "",
            descriptionText: "",
            tags: [],
            workshopTypeText: nil,
            ageRatingText: nil,
            genreText: nil,
            categoryText: nil,
            dependencyIDs: [],
            previewImageURL: nil,
            previewVideoURL: nil,
            previewAssetKind: .unknown,
            fileSizeText: "100 MB",
            resolutionText: nil,
            postedText: nil,
            updatedText: nil,
            favoritesText: nil,
            subscriptionsText: nil,
            scoreText: nil,
            lifetimeFavoritesText: nil,
            lifetimeSubscriptionsText: nil,
            visibilityText: nil,
            moderationText: nil,
            detailFields: [],
            detailURL: URL(fileURLWithPath: "/tmp/mwx-probe-detail")
        )
        let card = AppKitSteamWorkshopBrowserItem()
        card.view.frame = NSRect(x: 30, y: 40, width: 250, height: 180)
        container.addSubview(card.view)
        card.view.layoutSubtreeIfNeeded()

        let store = SteamWorkshopDownloadProgressStore()
        func configureCard() {
            card.configure(
                displayContext: .downloads,
                item: item,
                downloadRecord: nil,
                downloadProgressStore: store,
                isDownloading: true,
                isDownloaded: false,
                isKeyboardFocused: false,
                onOpen: {},
                onDownload: {},
                onSetAsWallpaper: {},
                onCancelDownload: {}
            )
        }
        configureCard()
        store.begin(itemID: "probe-item", jobKey: "job-1", attempt: 1)

        func accessibilityValue() -> String {
            (card.overlayBar.accessibilityValue() as? String) ?? ""
        }
        // Long byte strings keep the marquee text wider than its row so the
        // scroll is actually running.
        precondition(store.receiveHelperEvent(
            itemID: "probe-item", jobKey: "job-1", attempt: 1, sequence: 1,
            stage: "chunks", totalBytes: 1_234_567_890, verifiedBytes: 123_456_789
        ), "the first transferring tick must be accepted")
        precondition(accessibilityValue().contains("10%"),
                     "the card must surface the 10% status text")
        guard let marqueeAt10 = card.titleMarqueeView.activeMarqueeAnimation else {
            fputs("expected a running marquee on a visible transferring card\n", stderr)
            exit(1)
        }
        precondition(store.receiveHelperEvent(
            itemID: "probe-item", jobKey: "job-1", attempt: 1, sequence: 2,
            stage: "chunks", totalBytes: 1_234_567_890, verifiedBytes: 246_913_578
        ), "the second transferring tick must be accepted")
        precondition(accessibilityValue().contains("20%"),
                     "the card must surface the 20% status text")
        precondition(card.titleMarqueeView.activeMarqueeAnimation === marqueeAt10,
                     "a text-only progress tick restarted the marquee scroll")

        // A rebind replays the stored snapshot; the duplicate delivery is a
        // full no-op for the card (the marquee animation survives untouched).
        configureCard()
        precondition(card.titleMarqueeView.activeMarqueeAnimation === marqueeAt10,
                     "a duplicate snapshot delivery disturbed the marquee")

        // Determinate completion leaves the sweep stopped.
        _ = store.receiveHelperEvent(
            itemID: "probe-item", jobKey: "job-1", attempt: 1, sequence: 3,
            stage: "chunks", totalBytes: 1_234_567_890, verifiedBytes: 1_234_567_890
        )
        precondition(card.overlayBar.activeIndeterminateAnimation == nil,
                     "a determinate card must not run the indeterminate sweep")

        print("Steam download card progress diffing PASS")
    }
}
'''


class SteamDownloadCardProgressDiffTests(unittest.TestCase):
    def test_progress_ticks_never_restart_card_animations(self) -> None:
        with tempfile.TemporaryDirectory(
            prefix="mwx-steam-progress-diff-"
        ) as directory:
            root = pathlib.Path(directory)
            support = root / "Support.swift"
            harness = root / "Harness.swift"
            binary = root / "progress-diff-probe"
            support.write_text(SUPPORT, encoding="utf-8")
            harness.write_text(HARNESS, encoding="utf-8")
            compilation = subprocess.run(
                [
                    "xcrun",
                    "swiftc",
                    "-parse-as-library",
                    str(support),
                    *map(str, SOURCES),
                    str(harness),
                    "-o",
                    str(binary),
                ],
                cwd=ROOT,
                capture_output=True,
                text=True,
                timeout=240,
            )
            self.assertEqual(compilation.returncode, 0, compilation.stderr)
            run = subprocess.run(
                # Literal command head; the probe binary is a tempdir
                # artifact of the compilation above, never external input.
                ["/usr/bin/env", str(binary)],
                cwd=ROOT,
                capture_output=True,
                text=True,
                timeout=60,
            )
            self.assertEqual(run.returncode, 0, run.stderr or run.stdout)
            self.assertIn("PASS", run.stdout)


if __name__ == "__main__":
    unittest.main()
