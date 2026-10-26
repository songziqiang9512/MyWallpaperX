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
  (the shared preview state is activated by its detail container).
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
    SHARED_UI / "DecodedThumbnailMemoryCache.swift",
    SHARED_UI / "GridThumbnailDecoder.swift",
    CORE / "SteamWorkshopPreviewSource.swift",
    SHARED_UI / "WallpaperGridScrollView.swift",
    UI / "AppKitSteamWorkshopBrowserItem.swift",
    UI / "AppKitSteamWorkshopBrowserItem+Presentation.swift",
    ROOT / "MyWallpaperX/Shared/Components/WallpaperCardInteractionView.swift",
    ROOT / "MyWallpaperX/Shared/Components/WallpaperCardSupportViews.swift",
    UI / "SteamWorkshopPreviewPlaceholderView.swift",
    UI / "SteamWorkshopPreviewState.swift",
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
    var navigationVersion = 0
    static let shared = SteamWorkshopService()
    let steamAuth = SteamAuthProbe()
    let steamSubscriptions = SteamSubscriptionsProbe()
    @Published var source: Int = 0
    @MainActor let downloadProgressStore = SteamWorkshopDownloadProgressStore()
    func presentSteamLoginForUserAction(context: String) {}
    func latestDownloadRecord(for id: String) -> SteamWorkshopDownloadRecord? { nil }
    func failedDownloadIntentMessage(for id: String) -> String? { nil }
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
    static func make(item: SteamWorkshopBrowserItem, service: SteamWorkshopService, navigationVersion: Int? = nil) -> NSMenu {
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

private final class CardSource: NSObject, NSCollectionViewDataSource {
    var cards: [AppKitSteamWorkshopBrowserItem] = []
    func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int { cards.count }
    func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem { cards[indexPath.item] }
}

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
        let scroll = WallpaperGridScrollView(frame: NSRect(x: 0, y: 0, width: 300, height: 240))
        let container = NSCollectionView(frame: NSRect(x: 0, y: 0, width: 300, height: 500))
        let layout = NSCollectionViewFlowLayout()
        layout.itemSize = NSSize(width: 250, height: 180)
        layout.minimumLineSpacing = 10
        container.collectionViewLayout = layout
        scroll.documentView = container
        window.contentView = scroll
        window.orderFrontRegardless()

        let item = AppKitSteamWorkshopBrowserItem()
        let source = CardSource()
        source.cards = [item]
        container.dataSource = source
        container.reloadData()
        container.layoutSubtreeIfNeeded()
        item.view.layoutSubtreeIfNeeded()
        precondition(container.visibleItems().contains(item), "the production Steam card must really be visible")

        func enterEvent(_ inside: Bool, target: AppKitSteamWorkshopBrowserItem? = nil) -> NSEvent {
            let target = target ?? item
            let visible = target.view.bounds.intersection(target.view.visibleRect)
            let local = inside
                ? NSPoint(x: visible.midX, y: visible.midY)
                : NSPoint(x: -60, y: -60)
            let location = target.view.convert(local, to: nil)
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

        // Deterministic loader delivery isolates mouse eligibility here. The
        // lifecycle gate separately exercises real GIF data and cache eviction.
        item.previewState = SteamWorkshopPreviewState(loaders: .init(
            image: { _, _, _, done in done(NSImage(size: NSSize(width: 48, height: 48))) },
            animation: { _, _, done in done(NSImage(size: NSSize(width: 48, height: 48))) },
            video: { _, done in done(nil) }, retryDelay: { _ in nil }, invalidate: { _ in }))
        item.previewState.onChange = { [weak item] in item?.applyPreviewState() }
        item.loadPreview(from: URL(fileURLWithPath: "/fixture/preview.gif"), fallbackVideoURL: nil)

        // Hidden glass has no window geometry/layout work. Its original view
        // and controls are retained and reattached before the first reveal.
        precondition(item.overlayBar.superview == nil, "idle Steam glass must be detached")
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
        precondition(item.overlayBar.superview === item.cardView, "hover must attach original glass")
        let bar = item.overlayBar
        item.mouseExited(with: enterEvent(false))
        item.mouseEntered(with: enterEvent(true))
        // The real pointer is deliberately outside this offscreen window;
        // layout correctly clears synthetic hover. Keep the original persistent
        // visibility input true while pumping completion callbacks.
        item.shouldPersistBarVisibility = true
        let revealDeadline = Date().addingTimeInterval(0.35)
        while Date() < revealDeadline { RunLoop.main.run(until: Date().addingTimeInterval(0.005)) }
        precondition(item.overlayBar === bar && item.overlayBar.superview === item.cardView,
            "a stale collapse completion must not detach a revealed persistent bar")
        item.shouldPersistBarVisibility = false
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

        // Real card + real shared scroll: transition suppresses the active
        // preview, guarded mouse events cannot restart it, and newly visible
        // cards read the same owning scroll state without waiting for replay.
        item.setPreviewVisible(true)
        item.mouseEntered(with: enterEvent(true))
        precondition(item.previewImageView.animates, "positive GIF control before scroll")
        NotificationCenter.default.post(name: NSScrollView.willStartLiveScrollNotification, object: scroll)
        precondition(scroll.isGridScrolling && !item.isHovering && !item.previewImageView.animates,
            "scroll must stop the actual Steam card hover and GIF")
        precondition(item.view.trackingAreas.isEmpty, "scroll must detach Steam hover tracking")
        precondition(item.overlayBar.superview == nil, "scroll must remove invisible glass from the window")
        item.mouseMoved(with: enterEvent(true))
        item.mouseEntered(with: enterEvent(true))
        precondition(!item.isHovering && !item.previewImageView.animates,
            "hover events during scroll must not restart the actual GIF")
        let fresh = AppKitSteamWorkshopBrowserItem()
        source.cards.append(fresh)
        container.reloadData()
        container.layoutSubtreeIfNeeded()
        fresh.viewDidLayout()
        precondition(fresh.view.enclosingScrollView === scroll && fresh.view.isGridHoverSuppressed,
            "a new card must read the same active scroll owner")
        precondition(container.visibleItems().contains(fresh) && !fresh.view.bounds.intersection(fresh.view.visibleRect).isEmpty,
            "the new card positive control must really be visible")
        let freshFrame = fresh.view.frame
        let freshEnter = enterEvent(true, target: fresh)
        fresh.mouseEntered(with: freshEnter)
        precondition(fresh.view.trackingAreas.isEmpty, "a new scrolling Steam card must not install hover tracking")
        precondition(!fresh.isHovering, "newly visible real card must remain idle during scroll")
        NotificationCenter.default.post(name: NSScrollView.didEndLiveScrollNotification, object: scroll)
        let deadline = Date().addingTimeInterval(0.18)
        while Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.005)) }
        precondition(!scroll.isGridScrolling && !item.previewImageView.animates,
            "settlement must use the current pointer, not revive the old GIF")
        precondition(fresh.view.trackingAreas.count == 1, "settlement must restore one Steam hover tracking area")
        fresh.mouseEntered(with: freshEnter)
        precondition(fresh.isHovering, "the exact same new-card event must enter hover after scroll; before=\(freshFrame) now=\(fresh.view.frame) bounds=\(fresh.view.bounds) visible=\(fresh.view.visibleRect) local=\(fresh.view.convert(freshEnter.locationInWindow, from: nil)) scrolling=\(scroll.isGridScrolling)")
        // Persistent playback/download visibility uses the same bar even
        // without hover. Multi-select hides it, exiting restores it immediately.
        fresh.isHovering = false
        fresh.currentDisplayContext = .downloads
        fresh.shouldPersistBarVisibility = true
        fresh.applyHoverStyle(animated: false)
        precondition(fresh.overlayBar.superview === fresh.cardView && fresh.overlayBar.alphaValue > 0,
            "persistent bar must remain attached")
        fresh.isMultiSelectMode = true
        fresh.applyHoverStyle(animated: false)
        precondition(fresh.overlayBar.superview == nil, "multi-select must detach persistent glass")
        fresh.isMultiSelectMode = false
        fresh.applyHoverStyle(animated: false)
        precondition(fresh.overlayBar.superview === fresh.cardView, "exit multi-select must restore persistent glass")
        fresh.prepareForReuse()
        precondition(fresh.overlayBar.superview == nil, "reuse must retire old presentation")
        window.orderOut(nil)
        print("Steam list thumbnails: static unless hovered PASS")
    }
}
'''

BLACK_FRAME_HARNESS = r'''
import AppKit
import CoreGraphics
import Foundation
import ImageIO

@main struct Harness {
    @MainActor static func main() {
        func solid(_ color: (Int, Int, Int), _ size: Int) -> CGImage {
            let context = CGContext(
                data: nil, width: size, height: size, bitsPerComponent: 8,
                bytesPerRow: size * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )!
            context.setFillColor(
                red: CGFloat(color.0) / 255, green: CGFloat(color.1) / 255,
                blue: CGFloat(color.2) / 255, alpha: 1
            )
            context.fill(CGRect(x: 0, y: 0, width: size, height: size))
            return context.makeImage()!
        }

        func animatedGIF(frames: [(Int, Int, Int)]) -> Data {
            let url = URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("mwx-black-frame-\(UUID().uuidString).gif")
            let destination = CGImageDestinationCreateWithURL(
                url as CFURL, "com.compuserve.gif" as CFString, frames.count, nil
            )!
            let delay: CFDictionary = [kCGImagePropertyGIFDelayTime: 0.2] as CFDictionary
            for frame in frames {
                CGImageDestinationAddImage(
                    destination, solid(frame, 48),
                    [kCGImagePropertyGIFDictionary: delay] as CFDictionary
                )
            }
            CGImageDestinationFinalize(destination)
            let data = try! Data(contentsOf: url)
            try? FileManager.default.removeItem(at: url)
            return data
        }

        func centerRGB(_ image: NSImage) -> (Int, Int, Int) {
            let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil)!
            var pixel = [UInt8](repeating: 0, count: 4)
            let context = CGContext(
                data: &pixel, width: 1, height: 1, bitsPerComponent: 8,
                bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )!
            context.interpolationQuality = .medium
            context.draw(
                cg, in: CGRect(x: 0, y: 0, width: 1, height: 1)
            )
            return (Int(pixel[0]), Int(pixel[1]), Int(pixel[2]))
        }

        // 1. Black-first animated GIF: the static decode must advance past
        //    the black lead frame and land on real content.
        let blackLead = animatedGIF(frames: [(0, 0, 0), (200, 40, 30)])
        let staticImage = steamWorkshopPreviewImage(from: blackLead)!
        let rgb = centerRGB(staticImage)
        precondition(rgb.0 > 120 && rgb.1 > 15 && rgb.1 < 90 && rgb.2 < 70,
            "static decode must skip the black lead frame; got \(rgb)")

        // 2. Single-frame black source stays faithful (no frame to advance to).
        let singleBlack = animatedGIF(frames: [(0, 0, 0)])
        let singleImage = steamWorkshopPreviewImage(from: singleBlack)!
        let singleRGB = centerRGB(singleImage)
        precondition(singleRGB.0 < 10 && singleRGB.1 < 10 && singleRGB.2 < 10,
            "single-frame black source must stay black; got \(singleRGB)")

        // 3. Non-black lead keeps frame 0 (no unnecessary advance).
        let brightLead = animatedGIF(frames: [(30, 120, 220), (200, 40, 30)])
        let brightImage = steamWorkshopPreviewImage(from: brightLead)!
        let brightRGB = centerRGB(brightImage)
        precondition(brightRGB.2 > 120 && brightRGB.0 < 90,
            "bright lead frame must be kept; got \(brightRGB)")

        // 4. The hover animation path keeps the full sequence.
        precondition(steamWorkshopAnimatedPreviewImage(from: blackLead) != nil,
            "hover animation must still decode the full animated GIF")

        // 5. The shared suspicious check still flags a static black image.
        let blackOnly = steamWorkshopPreviewImage(from: singleBlack)!
        precondition(steamWorkshopPreviewImageLooksSuspicious(blackOnly),
            "static black image must remain suspicious for fallback flows")

        print("Steam static preview black-lead skip PASS")
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

    def test_static_preview_skips_black_leading_frames(self) -> None:
        """Behavior gate: scene GIF cards whose first frame is black.

        The static decode used to always take frame 0; many workshop GIFs
        start with a near-black placeholder frame, so the grid card showed a
        black tile until hover. The static decode now advances (8-frame cap)
        to the first non-black frame. The hover animation path keeps the full
        sequence, and single-frame black sources stay faithful.
        """
        with tempfile.TemporaryDirectory(
            prefix="mwx-steam-thumbnail-black-"
        ) as directory:
            root = pathlib.Path(directory)
            support = root / "Support.swift"
            harness = root / "Harness.swift"
            binary = root / "black-frame-probe"
            support.write_text(SUPPORT, encoding="utf-8")
            harness.write_text(BLACK_FRAME_HARNESS, encoding="utf-8")
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
