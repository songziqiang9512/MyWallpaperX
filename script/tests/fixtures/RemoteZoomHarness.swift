import AppKit

@MainActor protocol ZoomProbe: AnyObject {
    var makeZoomAction: ((Int) -> (() -> Void)?)? { get set }
    var zoomControl: WallpaperLibraryZoomControl { get }
    var active: Bool { get set }
    func configureZoom(preferredColumns: Int, clipWidth: CGFloat)
}

// PRODUCTION_ZOOM_DECLARATIONS

@main enum RemoteZoomChecks {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        var checks: [String: Bool] = [:]
        for (name, probe) in [("Steam", SteamZoom() as any ZoomProbe), ("Pixabay", PixabayZoom() as any ZoomProbe)] {
            func check(_ key: String, _ value: Bool) { checks[name + key] = value }
            func segment(_ index: Int) {
                // This supplies the segment visible during tracking. The
                // separate full-window gate sends real native mouse events.
                let sender = NSSegmentedControl(labels: ["−", "+"], trackingMode: .selectOne, target: nil, action: nil)
                sender.selectedSegment = index
                precondition(sender.selectedSegment == index)
                NSApp.sendAction(probe.zoomControl.action!, to: probe.zoomControl.target, from: sender)
            }
            var pageColumns = 5, clipWidth: CGFloat = 1400, events: [Int] = []
            probe.configureZoom(preferredColumns: pageColumns, clipWidth: clipWidth)
            check("UnboundControlsAreDisabled", !probe.zoomControl.isEnabled(forSegment: 0) && !probe.zoomControl.isEnabled(forSegment: 1))
            // The App preference writer is a recording leaf. Both source
            // initializers/configure methods and the shared control are real.
            probe.makeZoomAction = { delta in
                let available = WallpaperLibraryGridMetrics.zoomAvailability(preferredColumns: pageColumns, clipWidth: clipWidth)
                guard delta != 0, clipWidth > 0, (delta > 0 ? available.canZoomIn : available.canZoomOut) else { return nil }
                return {
                    events.append(delta)
                    pageColumns = WallpaperLibraryGridMetrics.zoomedColumns(preferredColumns: pageColumns, delta: delta, clipWidth: clipWidth)
                    probe.configureZoom(preferredColumns: pageColumns, clipWidth: clipWidth)
                }
            }
            probe.configureZoom(preferredColumns: pageColumns, clipWidth: clipWidth)
            check("NativePairUsesCapsule", probe.zoomControl.segmentStyle == .capsule && probe.zoomControl.segmentCount == 2 && probe.zoomControl.trackingMode == .momentary)
            check("FiveColumnsHasBothDirections", probe.zoomControl.isEnabled(forSegment: 0) && probe.zoomControl.isEnabled(forSegment: 1))
            segment(0)
            check("MinusShrinksCardsThroughOneCommand", events == [-1] && pageColumns == 6)
            segment(0)
            check("SixColumnEndpointRejectsExtraMinus", events == [-1] && !probe.zoomControl.isEnabled(forSegment: 0))
            segment(1)
            check("PlusEnlargesCardsThroughOneCommand", events == [-1, 1] && pageColumns == 5)
            segment(1); segment(1)
            let atMinimum = events
            segment(1)
            check("ThreeColumnEndpointRejectsExtraPlus", pageColumns == 3 && events == atMinimum && !probe.zoomControl.isEnabled(forSegment: 1))
            pageColumns = 6; clipWidth = 580
            probe.configureZoom(preferredColumns: pageColumns, clipWidth: clipWidth)
            check("ConstrainedPreferenceIsNotOverwritten", pageColumns == 6 && WallpaperLibraryGridMetrics(clipWidth: clipWidth, preferredColumns: pageColumns).columns == 5)
            segment(1)
            check("ConstrainedFirstPlusChangesVisibleColumns", pageColumns == 4 && WallpaperLibraryGridMetrics(clipWidth: clipWidth, preferredColumns: pageColumns).columns == 4)
            let beforeResize = events
            clipWidth = 1400; probe.configureZoom(preferredColumns: pageColumns, clipWidth: clipWidth)
            check("ResizeDoesNotDispatchOrRewritePreference", events == beforeResize && pageColumns == 4)
            clipWidth = 0; probe.configureZoom(preferredColumns: pageColumns, clipWidth: clipWidth)
            segment(0); segment(1)
            check("UnmountedWidthDisablesWithoutDispatch", events == beforeResize && !probe.zoomControl.isEnabled(forSegment: 0) && !probe.zoomControl.isEnabled(forSegment: 1))
            clipWidth = 1400; probe.configureZoom(preferredColumns: pageColumns, clipWidth: clipWidth)
            probe.active = false; segment(0)
            check("InactiveSourceDoesNotBorrowCurrentPage", events == beforeResize)
            probe.active = true; segment(-1)
            check("InvalidNativeSegmentDoesNotDispatch", events == beforeResize)
            probe.makeZoomAction = nil; probe.configureZoom(preferredColumns: pageColumns, clipWidth: clipWidth)
            segment(0)
            check("UnboundSourceCannotWriteOrDispatch", events == beforeResize && pageColumns == 4)
        }
        print(String(data: try JSONSerialization.data(withJSONObject: checks, options: [.sortedKeys]), encoding: .utf8)!)
    }
}
