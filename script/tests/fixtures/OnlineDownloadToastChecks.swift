import AppKit
import Foundation

@main struct OnlineDownloadToastChecks {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        var hover: [Bool] = []
        var applied = 0, dismissed = 0
        let toast = OnlineLibraryDownloadToastView(message: "下载完成的示例壁纸 Example wallpaper",
            onSetAsWallpaper: { applied += 1 }, onDismiss: { dismissed += 1 }, onHoverChange: { hover.append($0) })
        let window = NSWindow(contentRect: NSRect(x: 14000, y: 14000, width: 800, height: 400),
            styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 800, height: 400))
        window.contentView = root
        let clip = NSClipView(frame: NSRect(x: 0, y: 0, width: 720, height: 180))
        let document = NSView(frame: NSRect(x: 0, y: 0, width: 720, height: 320))
        root.addSubview(clip); clip.documentView = document
        document.addSubview(toast)
        let width = toast.widthAnchor.constraint(equalToConstant: 680)
        NSLayoutConstraint.activate([toast.leadingAnchor.constraint(equalTo: document.leadingAnchor, constant: 20),
            toast.topAnchor.constraint(equalTo: document.topAnchor, constant: 20), width])
        func views(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(views) }
        func rect(_ rect: NSRect) -> [Double] { [rect.minX, rect.minY, rect.width, rect.height].map(Double.init) }
        var checks: [String: Bool] = [:]
        var geometry: [String: Any] = [:]
        var registeredAreas: [NSTrackingArea] = []
        for (appearance, appearanceName) in [(NSAppearance.Name.aqua, "light"), (.darkAqua, "dark")] {
            toast.appearance = NSAppearance(named: appearance)
            for value: CGFloat in [360, 520, 680] {
                let key = "\(appearanceName)-\(Int(value))"
                width.constant = value
                clip.frame.size.width = value + 40
                clip.frame.size.height = 180
                clip.scroll(to: .zero)
                document.frame.size.width = value + 40
                document.layoutSubtreeIfNeeded(); toast.layoutSubtreeIfNeeded()
                let buttons = views(toast).compactMap { $0 as? NSButton }
                let action = buttons.first { $0.title == "设为壁纸" }!
                let close = buttons.first { $0.toolTip == "关闭" }!
                geometry[key] = ["toast": rect(toast.frame), "apply": rect(action.convert(action.bounds, to: toast)),
                    "dismiss": rect(close.convert(close.bounds, to: toast))]
                checks[key + "-actions-inside"] = buttons.allSatisfy { toast.bounds.contains($0.convert($0.bounds, to: toast)) }
                checks[key + "-chrome"] = toast.material == .hudWindow && toast.blendingMode == .withinWindow
                    && toast.state == .active && toast.layer?.cornerRadius == 26
                // AppKit owns clipping; no product handler or action is replaced.
                clip.frame.size.height = toast.bounds.height / 2
                clip.scroll(to: toast.frame.origin); document.layoutSubtreeIfNeeded()
                checks[key + "-partial-clip"] = toast.visibleRect.height > 0 && toast.visibleRect.height < toast.bounds.height
                for _ in 0..<4 {
                    toast.updateTrackingAreas()
                    let areas = toast.trackingAreas.filter { ($0.owner as? NSView) === toast }
                    checks[key + "-one-area"] = areas.count == 1
                    checks[key + "-native-policy"] = areas.count == 1 && areas[0].options.contains(.inVisibleRect)
                        && areas[0].options.contains(.activeInKeyWindow) && areas[0].options.contains(.mouseEnteredAndExited)
                    registeredAreas += areas
                }
                hover.removeAll()
                for type: NSEvent.EventType in [.mouseEntered, .mouseExited] {
                    let event = NSEvent.enterExitEvent(with: type, location: .zero, modifierFlags: [],
                        timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 1,
                        trackingNumber: 0, userData: nil)!
                    toast.mouseEnteredOrExitedForCheck(event)
                }
                checks[key + "-hover-callbacks"] = hover == [true, false]
                let previousApplied = applied, previousDismissed = dismissed
                action.performClick(nil); close.performClick(nil)
                checks[key + "-native-actions"] = applied == previousApplied + 1 && dismissed == previousDismissed + 1
                clip.scroll(to: .zero)
            }
        }
        let result: [String: Any] = ["checks": checks, "geometry": geometry,
            "observedAreaIdentities": Set(registeredAreas.map(ObjectIdentifier.init)).count,
            "scope": "real toast/clip geometry, tracking policy, callbacks and native button actions; no physical pointer, timer owner, network or performance measurement"]
        FileHandle.standardOutput.write(try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys]))
        window.contentView = nil; window.close()
    }
}

private extension OnlineLibraryDownloadToastView {
    func mouseEnteredOrExitedForCheck(_ event: NSEvent) {
        if event.type == .mouseEntered { mouseEntered(with: event) } else { mouseExited(with: event) }
    }
}
