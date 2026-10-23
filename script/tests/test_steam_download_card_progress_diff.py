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
import hashlib
import json
import os
import shutil
import subprocess
import tempfile
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[2]
UI = ROOT / "MyWallpaperX/Modules/SteamWorkshop/UI"
CORE = ROOT / "MyWallpaperX/Modules/SteamWorkshop/Core"
SHARED_UI = ROOT / "MyWallpaperX/Shared/UI"

SOURCES = [
    SHARED_UI / "DecodedThumbnailMemoryCache.swift",
    SHARED_UI / "GridThumbnailDecoder.swift",
    CORE / "SteamWorkshopPreviewSource.swift",
    SHARED_UI / "WallpaperGridScrollView.swift",
    UI / "AppKitSteamWorkshopBrowserItem.swift",
    UI / "AppKitSteamWorkshopBrowserItem+Presentation.swift",
    UI / "AppKitSteamWorkshopBrowserItemSupportViews.swift",
    UI / "SteamWorkshopPreviewPlaceholderView.swift",
    UI / "SteamWorkshopPreviewState.swift",
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
    var loginPrompts = 0
    func presentSteamLoginForUserAction(context: String) { loginPrompts += 1 }
    func latestDownloadRecord(for id: String) -> SteamWorkshopDownloadRecord? { nil }
    func isDownloading(itemID: String) -> Bool { false }
    // f140ee42 让卡片解析"下载失败意图"文案（真实实现 +DownloadFiltering.swift），
    // 本 fixture 编译整份 BrowserItem，需要同名入口保持无操作。
    func failedDownloadIntentMessage(for id: String) -> String? { nil }
    func isDownloaded(itemID: String) -> Bool { false }
    func isRecordCurrentlyPlaying(_ record: SteamWorkshopDownloadRecord) -> Bool { false }
    var launchPendingID: String?
    func isLaunchPending(_ id: String) -> Bool { launchPendingID == id }
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

        store.clear(itemID: item.id, jobKey: "job-1")
        let ready = SteamWorkshopDownloadRecord(id: item.id, title: item.title, description: "", tags: [],
            folderURL: URL(fileURLWithPath: "/fixture"), projectFileURL: nil, ownEntryHTMLURL: nil,
            dependencyHostEntryHTMLURL: nil, dependencyHostFolderURL: nil, entryHTMLURL: nil,
            resolvedWebRootURL: nil, previewURL: nil, sourceVideoURL: nil, exportedVideoURL: nil,
            updatedAt: Date(), sizeText: "100 MB", status: .ready, browserItem: item,
            contentType: .scene, dependencyItemID: nil, dependencyStatus: .none)
        let service = SteamWorkshopService.shared
        var openedDetails = 0
        func launchCard(playing: Bool = false, multiSelect: Bool = false) {
            card.configure(displayContext: .downloads, isPlaying: playing, item: item,
                downloadRecord: ready, downloadProgressStore: store, isDownloading: false, isDownloaded: true,
                isMultiSelectMode: multiSelect, isKeyboardFocused: false,
                onOpen: { openedDetails += 1 }, onDownload: {}, onSetAsWallpaper: { service.launchPendingID = item.id }, onCancelDownload: {})
            card.isHovering = false
            card.applyHoverStyle(animated: false)
        }
        launchCard()
        card.viewDidLayout()
        func assertSymbolSize(_ image: NSImage?, named name: String) {
            let metrics = card.metrics(for: card.cardView.bounds.size)
            let config = NSImage.SymbolConfiguration(pointSize: max(11, metrics.iconButtonSize * 0.56), weight: .medium)
            let expected = NSImage(systemSymbolName: name, accessibilityDescription: nil)!.withSymbolConfiguration(config)!
            precondition(image?.size == expected.size, "same-size state update lost its symbol configuration: \(name)")
        }
        assertSymbolSize(card.statusBadgeButton.image, named: "play.fill")
        let firstTracking = card.view.trackingAreas.first
        precondition(firstTracking != nil, "card tracking identity control must be nonempty")
        card.viewDidLayout()
        precondition(firstTracking === card.view.trackingAreas.first, "unchanged layout must preserve card tracking")
        precondition(!card.currentBarVisibility, "an idle ready download keeps its hover-only bar")
        card.statusBadgeButton.performClick(nil)
        precondition(service.launchPendingID == item.id, "the play button must enter the pending launch")
        launchCard()
        assertSymbolSize(card.statusBadgeButton.image, named: "hourglass")
        precondition(card.currentBarVisibility, "pending launch must pin the bar before playback starts")
        precondition(card.statusBadgeButton.accessibilityLabel()?.contains("正在切换") == true,
                     "pending keeps the launch badge; stop styling still waits for playback")
        launchCard(multiSelect: true)
        precondition(!card.currentBarVisibility, "multi-select still suppresses the bar")
        service.launchPendingID = "another-record"
        launchCard()
        precondition(!card.currentBarVisibility, "another card's launch must not pin this bar")
        service.launchPendingID = nil
        launchCard(playing: true)
        assertSymbolSize(card.statusBadgeButton.image, named: "stop.fill")
        precondition(card.currentBarVisibility, "successful playback must keep the existing persistent bar")
        launchCard()
        precondition(!card.currentBarVisibility, "failed/cancelled launch returns to the original idle behavior")
        assertSymbolSize(card.statusBadgeButton.image, named: "play.fill")
        card.configure(displayContext: .browser, item: item, downloadRecord: nil,
            downloadProgressStore: store, isDownloading: false, isDownloaded: false,
            isKeyboardFocused: false, onOpen: {}, onDownload: {}, onSetAsWallpaper: {}, onCancelDownload: {})
        card.viewDidLayout()
        service.steamSubscriptions.states[item.id] = .known(true)
        card.refreshSubscribeHeart()
        precondition(card.detailButton.accessibilityLabel() == "取消订阅：\(item.title)", "heart test must enter subscribed browser chrome")
        assertSymbolSize(card.detailButton.image, named: "heart.fill")
        service.steamSubscriptions.states[item.id] = .known(false)
        card.refreshSubscribeHeart()
        precondition(card.detailButton.accessibilityLabel() == "订阅：\(item.title)", "heart test must enter unsubscribed browser chrome")
        assertSymbolSize(card.detailButton.image, named: "heart")
        // Retired per-button tracking identity is covered by real hit regions,
        // target/action delivery and disabled -> enabled transitions instead.
        let proof = ProcessInfo.processInfo.environment["MWX_STEAM_NATIVE_BUTTON_PROOF_DIR"]
            .map { URL(fileURLWithPath: $0, isDirectory: true) }
        var buttonFrames: [String: [[CGFloat]]] = [:]
        func capture(_ name: String) {
            guard let proof else { return }
            card.view.layoutSubtreeIfNeeded()
            let bitmap = card.view.bitmapImageRepForCachingDisplay(in: card.view.bounds)!
            card.view.cacheDisplay(in: card.view.bounds, to: bitmap)
            try! bitmap.representation(using: .png, properties: [:])!.write(to: proof.appendingPathComponent(name + ".png"))
        }
        for dark in [false, true] {
            window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
            for width: CGFloat in [200, 280, 380] {
                card.view.frame.size = NSSize(width: width, height: 220)
                launchCard()
                card.isHovering = true
                card.applyHoverStyle(animated: false)
                card.viewDidLayout()
                let buttons = [card.detailButton, card.statusBadgeButton]
                let frames = buttons.map(\.frame)
                for button in buttons {
                    precondition(button.target === card && button.action != nil, "native button keeps its actual command owner")
                    precondition(button.frame.width >= 20 && button.frame.height >= 20
                        && card.overlayBar.bounds.contains(button.frame), "button hit frame stays inside overlay after resize")
                    for point in [NSPoint(x: 1, y: 1), NSPoint(x: button.bounds.midX, y: button.bounds.midY),
                                  NSPoint(x: button.bounds.maxX - 1, y: button.bounds.maxY - 1)] {
                        let hit = card.view.hitTest(button.convert(point, to: card.view.superview))
                        precondition(hit === button || hit?.isDescendant(of: button) == true,
                            "button's full rectangle must retain the action, not open the card")
                    }
                }
                card.viewDidLayout()
                precondition(buttons.map(\.frame) == frames, "repeated layout must not move native button targets")
                let beforeDetails = openedDetails
                card.detailButton.performClick(nil)
                precondition(openedDetails == beforeDetails + 1, "download detail button opens exactly once")
                service.launchPendingID = nil
                card.statusBadgeButton.performClick(nil)
                precondition(service.launchPendingID == item.id, "native status button preserves play command")
                service.launchPendingID = nil
                let name = "card-\(dark ? "dark" : "light")-\(Int(width))"
                buttonFrames[name] = frames.map { [$0.minX, $0.minY, $0.width, $0.height] }
                capture(name)
            }
            card.configure(displayContext: .browser, item: item, downloadRecord: nil,
                downloadProgressStore: store, isDownloading: false, isDownloaded: false,
                isKeyboardFocused: false, onOpen: {}, onDownload: {}, onSetAsWallpaper: {}, onCancelDownload: {})
            card.isHovering = true
            card.applyHoverStyle(animated: false)
            for state: SteamSubscriptionProbeState in [.known(true), .loading, .known(false)] {
                service.steamSubscriptions.states[item.id] = state
                card.refreshSubscribeHeart()
                card.viewDidLayout()
                precondition(card.detailButton.isEnabled == (state != .loading), "busy membership prevents duplicate requests")
                let before = service.loginPrompts
                card.detailButton.performClick(nil)
                precondition(service.loginPrompts == before + (state == .loading ? 0 : 1),
                    "disabled button is inert and re-enabled button restores the original command")
                capture("subscription-\(dark ? "dark" : "light")-\(state)")
            }
        }
        if let proof {
            try! JSONSerialization.data(withJSONObject: buttonFrames, options: [.prettyPrinted, .sortedKeys])
                .write(to: proof.appendingPathComponent("button-frames.json"))
        }
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
            identities = {str(path): hashlib.sha256(path.read_bytes()).hexdigest() for path in SOURCES}
            frozen = root / "sources"
            frozen.mkdir()
            for path in SOURCES:
                shutil.copy2(path, frozen / path.name)
            compilation = subprocess.run(
                [
                    "xcrun",
                    "swiftc",
                    "-parse-as-library",
                    str(support),
                    *map(str, [frozen / path.name for path in SOURCES]),
                    str(harness),
                    "-o",
                    str(binary),
                ],
                cwd=ROOT,
                capture_output=True,
                text=True,
                timeout=240,
            )
            self.assertEqual((compilation.returncode, identities), (0, {
                str(path): hashlib.sha256(path.read_bytes()).hexdigest() for path in SOURCES
            }), compilation.stderr)
            run = subprocess.run(
                # Literal command head; the probe binary is a tempdir
                # artifact of the compilation above, never external input.
                ["/usr/bin/env", str(binary)],
                cwd=ROOT,
                capture_output=True,
                text=True,
                timeout=60,
            )
            if destination := os.environ.get("MWX_STEAM_NATIVE_BUTTON_PROOF_DIR"):
                target = pathlib.Path(destination)
                target.mkdir(parents=True, exist_ok=True)
                (target / "source-inputs.json").write_text(json.dumps(identities, indent=2))
                (target / "compile.log").write_text(compilation.stdout + compilation.stderr)
                (target / "runtime.log").write_text(run.stdout + run.stderr)
            self.assertEqual(run.returncode, 0, run.stderr or run.stdout)
            self.assertIn("PASS", run.stdout)


if __name__ == "__main__":
    unittest.main()
