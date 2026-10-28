import AppKit
import Foundation

@main struct OnlineDownloadToastChecks {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        var applied = 0, dismissed = 0
        let toast = WallpaperGridNoticeView()
        func present() {
            toast.update(messages: ["下载完成的示例壁纸 Example wallpaper"],
                actions: [("设为壁纸", { applied += 1 })], showsClose: true, onDismiss: { dismissed += 1 })
        }
        present()
        let window = NSWindow(contentRect: NSRect(x: 14000, y: 14000, width: 800, height: 400),
            styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.orderFront(nil)
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
                checks[key + "-chrome"] = toast.style == .regular && toast.cornerRadius == 24
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
                // The real hover handlers cancel/rearm this same notice timer.
                let event = NSEvent.enterExitEvent(with: .mouseEntered, location: .zero, modifierFlags: [],
                    timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 1,
                    trackingNumber: 0, userData: nil)!
                toast.mouseEntered(with: event)
                checks[key + "-hover-keeps-visible"] = !toast.isHidden
                toast.mouseExited(with: event)
                let previousApplied = applied, previousDismissed = dismissed
                action.performClick(nil); close.performClick(nil)
                checks[key + "-native-actions"] = applied == previousApplied + 1 && dismissed == previousDismissed + 1
                toast.update(messages: [])
                present()
                clip.scroll(to: .zero)
            }
        }
        let oldAction = views(toast).compactMap { $0 as? NSButton }.first { $0.title == "设为壁纸" }!
        let before = applied
        toast.update(messages: ["新的错误"])
        oldAction.performClick(nil)
        checks["retired-command-cannot-run"] = applied == before
        let deadline = Date().addingTimeInterval(5.2)
        while Date() < deadline {
            toast.update(messages: ["新的错误"])
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        }
        checks["unchanged-source-does-not-renew-five-second-lifetime"] = toast.isHidden
        checks["expired-notice-has-no-interaction-region"] = !toast.permitsInteraction(at: .zero)
        toast.update(messages: ["新的错误"], event: 1)
        checks["a-new-identical-error-event-reappears-after-the-old-notice-expired"] = !toast.isHidden
        toast.update(messages: ["第二条"], showsClose: false)
        toast.update(messages: ["第二条"], showsClose: true)
        checks["same-message-can-update-close-style"] = views(toast).compactMap { $0 as? NSButton }
            .contains { $0.toolTip == "关闭" && !$0.isHiddenOrHasHiddenAncestor }
        let result: [String: Any] = ["checks": checks, "geometry": geometry,
            "observedAreaIdentities": Set(registeredAreas.map(ObjectIdentifier.init)).count,
            "scope": "real toast/clip geometry, tracking policy, callbacks and native button actions; no physical pointer, network or performance measurement"]
        FileHandle.standardOutput.write(try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys]))
        window.contentView = nil; window.close()
    }
}
