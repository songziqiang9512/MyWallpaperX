import AppKit
import Combine

final class TrackedLease { var cancelled = false; func cancel() { cancelled = true } }
final class TrackedPrefetch {
    var lease: TrackedLease?
    func start() { if lease?.cancelled != false { lease = TrackedLease() } }
    func cancelAll() { lease?.cancel() }
    func cancelAllPrefetch() { cancelAll() }
}
final class AppKitWallpaperItem: NSCollectionViewItem {
    var lease: TrackedLease?
    func setThumbnailVisible(_ active: Bool) {
        if active { if lease?.cancelled != false { lease = TrackedLease() } }
        else { lease?.cancel() }
    }
}
final class AppKitSteamWorkshopBrowserItem: NSCollectionViewItem {
    var lease: TrackedLease?
    func setPreviewVisible(_ active: Bool) {
        if active { if lease?.cancelled != false { lease = TrackedLease() } }
        else { lease?.cancel() }
    }
}
final class ProbeCollection {
    let video = AppKitWallpaperItem()
    let steam = AppKitSteamWorkshopBrowserItem()
    func visibleItems() -> [NSCollectionViewItem] { [video, steam] }
}
final class SteamWorkshopDownloadsBridge {
    static let shared = SteamWorkshopDownloadsBridge()
    var isActive = false
}
class WindowProbe: NSView {
    var cancellables = Set<AnyCancellable>()
    func installNotifications() {}
    let collectionView = ProbeCollection()
    let thumbnailProvider = TrackedPrefetch()
    let previewPrefetch = TrackedPrefetch()
    var viewportPrefetchWorkItem: DispatchWorkItem?
    var previewPrefetchWorkItem: DispatchWorkItem?
    var lastPrefetchOffsetY: CGFloat?
    var thumbnailWindowVisibilityObservation: NSKeyValueObservation?
    var missingPathWindowObservers: [NSObjectProtocol] = []
    func updateMissingPathProbeTimer() {}
    func scheduleRestingScrollOriginCapture() {}
    func prefetchCurrentViewport() { thumbnailProvider.start(); previewPrefetch.start() }
    deinit { missingPathWindowObservers.forEach { NotificationCenter.default.removeObserver($0) } }
}

// Only filesystem/cache/card leaves are controlled; the window observers,
// predicates, scheduling, cancellation, hide/unhide and callbacks are production.
// PRODUCTION_CLASSES

@main struct WindowLifecycleHarness {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        var checks: [String: Bool] = [:]
        for (index, probe) in [(1, P1())] {
            let window = NSWindow(contentRect: NSRect(x: 14000, y: 14000, width: 500, height: 300),
                styleMask: [.titled, .miniaturizable], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            let ancestor = NSView(frame: NSRect(x: 0, y: 0, width: 500, height: 300))
            probe.frame = ancestor.bounds; ancestor.addSubview(probe); window.contentView = ancestor
            probe.installNotifications()
            func pump(_ condition: () -> Bool) -> Bool {
                let until = Date().addingTimeInterval(2)
                while !condition(), Date() < until { RunLoop.main.run(until: Date().addingTimeInterval(0.005)) }
                return condition()
            }
            func active() -> Bool {
                let prefetch = index == 0 ? probe.thumbnailProvider : probe.previewPrefetch
                let card = index == 0 ? probe.collectionView.video.lease : probe.collectionView.steam.lease
                return prefetch.lease?.cancelled == false && card?.cancelled == false
            }
            window.orderFrontRegardless()
            // No scheduling calls or synthetic notifications: real visibility
            // KVO is the only entry from this point to each production owner.
            checks["\(index)-orderInStartsConsumers"] = pump { active() }
            let oldPrefetch = (index == 0 ? probe.thumbnailProvider : probe.previewPrefetch).lease
            let oldCard = index == 0 ? probe.collectionView.video.lease : probe.collectionView.steam.lease
            window.orderOut(nil)
            checks["\(index)-orderOutCancelsInflightConsumers"] = pump {
                oldPrefetch?.cancelled == true && oldCard?.cancelled == true
            }
            window.orderFrontRegardless()
            checks["\(index)-orderInResumesConsumers"] = pump { active() }
            ancestor.isHidden = true
            window.miniaturize(nil)
            let mini = pump { window.isMiniaturized }
            window.deminiaturize(nil)
            let restored = pump { !window.isMiniaturized && window.isVisible }
            RunLoop.main.run(until: Date().addingTimeInterval(0.08))
            let hiddenPrefetch = (index == 0 ? probe.thumbnailProvider : probe.previewPrefetch).lease
            let hiddenCard = index == 0 ? probe.collectionView.video.lease : probe.collectionView.steam.lease
            checks["\(index)-hiddenAncestorCannotResumeAfterDemini"] = mini && restored
                && hiddenPrefetch?.cancelled == true && hiddenCard?.cancelled == true
            ancestor.isHidden = false
            checks["\(index)-ancestorUnhideResumesConsumers"] = pump { active() }
            window.close()
        }
        print(String(data: try JSONSerialization.data(withJSONObject: checks, options: [.sortedKeys]), encoding: .utf8)!)
    }
}
