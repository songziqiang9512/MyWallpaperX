#!/usr/bin/env python3

"""Behavior gate: Steam list thumbnails stay static unless hovered.

The browse grid and the downloads grid share AppKitSteamWorkshopBrowserItem.
Every visible card used to start its animated GIF preview as soon as the
grid entered a window; each animated GIF is a main-thread timer-driven frame
sequence, so a screenful of cards staggered scrolling. The contract now:

- the default and the visible-but-idle state are static frames,
- only a hovered card animates, and leaving the card stops it again,
- keyboard focus never plays the preview,
- the detail sheet keeps its always-animated preview
  (SteamWorkshopItemDetailPreviewSupport owns that switch, untouched here).
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
    ROOT / "MyWallpaperX/Shared/UI/ThumbnailCache.swift",
    CORE / "SteamWorkshopModels.swift",
    CORE / "SteamWorkshopDownloadProgress.swift",
    CORE / "SteamWorkshopDownloadThumbnailPipeline.swift",
    SHARED_UI / "UIInteractionAnimation.swift",
    SHARED_UI / "AppearanceAwareContainerView.swift",
    SHARED_UI / "NSViewExtensions.swift",
]

SUPPORT = r'''
import AppKit
import Combine
import Foundation

// Out-of-closure product singletons, stubbed with the exact member surface
// the item family references. The probe drives the item directly; none of
// these bodies run except as compile-time witnesses.

final class SteamWorkshopService {
    static let shared = SteamWorkshopService()
    let steamAuth = SteamAuthProbe()
    let steamSubscriptions = SteamSubscriptionsProbe()
    @Published var source: Int = 0
    @MainActor let downloadProgressStore = SteamWorkshopDownloadProgressStore()
    func presentSteamLoginForUserAction(context: String) {}
    func latestDownloadRecord(for id: String) -> SteamWorkshopDownloadRecord? { nil }
    func isDownloading(itemID: String) -> Bool { false }
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

// Mirror of the Web/Core validation enum referenced by the shared models.
enum SteamWorkshopWebDependencyStatus: Equatable {
    case none
    case available(itemID: String)
    case missing(itemID: String)
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
'''

HARNESS = r'''
import AppKit
import Foundation

@main struct Harness {
    @MainActor static func main() {
        _ = NSApplication.shared
        // The window lives far offscreen so the real cursor can never sit
        // inside the card; hover state is driven by synthesized events only.
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 240),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.setFrameOrigin(NSPoint(x: 14_000, y: 14_000))
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 240))
        window.contentView = container
        window.orderFrontRegardless()

        let item = AppKitSteamWorkshopBrowserItem()
        item.view.frame = NSRect(x: 25, y: 30, width: 250, height: 180)
        container.addSubview(item.view)
        item.view.layoutSubtreeIfNeeded()

        func enterEvent(_ inside: Bool) -> NSEvent {
            let local = inside
                ? NSPoint(x: item.view.bounds.midX, y: item.view.bounds.midY)
                : NSPoint(x: -60, y: -60)
            let location = item.view.convert(local, to: nil)
            return NSEvent.enterExitEvent(
                with: inside ? .mouseEntered : .mouseExited,
                location: location,
                modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber,
                context: nil,
                eventNumber: 0,
                trackingNumber: 0,
                userData: nil
            )!
        }

        // 1. Fresh card: static frame.
        precondition(!item.previewImageView.animates, "a fresh card must not animate")

        // 2. Grid enters a window: every visible card is preview-visible and
        // yet stays static — this is the batched-GIF main-thread saving.
        item.setPreviewVisible(true)
        precondition(!item.previewImageView.animates, "visible-but-idle cards must stay static")

        // 3. Keyboard focus never plays the preview.
        item.setKeyboardFocus(true)
        precondition(!item.previewImageView.animates, "keyboard focus must not animate the preview")

        // 4. Hover plays; leaving stops.
        item.mouseEntered(with: enterEvent(true))
        precondition(item.previewImageView.animates, "a hovered card must animate")
        item.mouseExited(with: enterEvent(false))
        precondition(!item.previewImageView.animates, "leaving the card must stop the animation")

        // 5. Hovering again replays without re-configuring the card.
        item.mouseEntered(with: enterEvent(true))
        precondition(item.previewImageView.animates, "re-entering must animate again")
        item.mouseExited(with: enterEvent(false))
        precondition(!item.previewImageView.animates, "second exit must stop the animation")

        // 6. The grid hiding the preview (window gone) also stops a hovered card.
        item.mouseEntered(with: enterEvent(true))
        precondition(item.previewImageView.animates, "hover must animate before the grid hides")
        item.setPreviewVisible(false)
        precondition(!item.previewImageView.animates, "hiding the preview must stop the animation")

        print("Steam list thumbnails: static unless hovered PASS")
    }
}
'''


class SteamListThumbnailAnimationTests(unittest.TestCase):
    def test_list_thumbnails_stay_static_unless_hovered(self) -> None:
        with tempfile.TemporaryDirectory(
            prefix="mwx-steam-thumbnail-anim-"
        ) as directory:
            root = pathlib.Path(directory)
            support = root / "Support.swift"
            harness = root / "Harness.swift"
            binary = root / "thumbnail-anim-probe"
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
