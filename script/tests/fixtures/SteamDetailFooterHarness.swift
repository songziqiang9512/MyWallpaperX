import AppKit

@MainActor final class ActionTarget: NSObject {
    var presses = 0
    @objc func press() { presses += 1 }
}
@main struct FooterHarness {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        let target = ActionTarget()
        let footer = SteamWorkshopDetailFooterView()
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 280, height: SteamWorkshopDetailFooterView.height), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let host = NSView()
        window.contentView = host
        footer.translatesAutoresizingMaskIntoConstraints = false
        host.addSubview(footer)
        NSLayoutConstraint.activate([
            footer.leadingAnchor.constraint(equalTo: host.leadingAnchor),
            footer.trailingAnchor.constraint(equalTo: host.trailingAnchor),
            footer.topAnchor.constraint(equalTo: host.topAnchor),
            footer.bottomAnchor.constraint(equalTo: host.bottomAnchor)
        ])
        let fixedWidth = footer.widthAnchor.constraint(equalToConstant: 280)
        fixedWidth.isActive = true
        footer.heightAnchor.constraint(equalToConstant: SteamWorkshopDetailFooterView.height).isActive = true
        for width in [CGFloat(280), 320, 400] {
            for title in ["下载壁纸", "下载依赖 #12345678901234567890", "正在保存…", "取消下载", "设为壁纸"] {
                let primary = button(title, target: target)
                let more = button("", target: target)
                let subscription = button("", target: target)
                footer.configure(primary: primary, webpage: subscription, properties: more)
                fixedWidth.constant = width
                window.setContentSize(NSSize(width: width, height: SteamWorkshopDetailFooterView.height))
                RunLoop.main.run(until: Date().addingTimeInterval(0.05))
                host.layoutSubtreeIfNeeded()
                let controls = [primary, subscription, more]
                for control in controls {
                    precondition(footer.bounds.contains(control.frame), "footer action escaped")
                    precondition(control.frame.height == InspectorFooterMetrics.height)
                    for peer in controls where peer !== control {
                        precondition(!control.frame.intersects(peer.frame), "footer actions overlap")
                    }
                }
                precondition(primary.frame.width == width - 2 * InspectorFooterMetrics.height - 16, "primary \(primary.frame) expected \(width) window \(window.frame)")
                let originalFrame = primary.frame
                primary.setProgressFill(0.5)
                primary.layoutSubtreeIfNeeded()
                let fill = primary.layer!.sublayers!.first!
                precondition(primary.layer!.masksToBounds && primary.layer!.cornerRadius > 0)
                precondition(abs(fill.frame.width - primary.bounds.width * 0.5) < 0.01)
                primary.setProgressFill(2)
                precondition(fill.frame.width == primary.bounds.width)
                primary.setProgressFill(-1)
                precondition(fill.frame.width == 0)
                primary.setProgressFill(.nan)
                precondition(fill.superlayer == nil)
                precondition(primary.frame == originalFrame, "progress must preserve button geometry")
                precondition(primary.acceptsFirstResponder)
                precondition(primary.accessibilityPerformPress())
                primary.isEnabled = false
                precondition(!primary.accessibilityPerformPress() && !primary.acceptsFirstResponder)
            }
        }
        let tags = SteamWorkshopTagStripView(tags: ["Anime", "Audio responsive", "Customizable", "Dual 7680 x 2160", "Puppet Warp", "很长的标签名称用于检查窄栏展示"])
        for width in [CGFloat(280), 320, 400] {
            tags.frame = NSRect(x: 0, y: 0, width: width, height: 500)
            tags.layoutSubtreeIfNeeded()
            precondition(tags.intrinsicContentSize.height == 34)
            precondition(tags.documentView!.bounds.width > width)
            tags.contentView.scroll(to: NSPoint(x: 50, y: 0))
            tags.reflectScrolledClipView(tags.contentView)
            tags.layoutSubtreeIfNeeded()
            precondition(tags.contentView.bounds.origin.x == 50, "hidden-scroller clip must retain horizontal position")
            precondition(!tags.hasHorizontalScroller && !tags.hasVerticalScroller)
            precondition(tags.toolTip == nil)

            for chip in tags.documentView!.subviews {
                precondition(chip.frame.minX >= 0 && chip.frame.maxX <= tags.documentView!.bounds.width)
                for peer in tags.documentView!.subviews where peer !== chip { precondition(!chip.frame.intersects(peer.frame)) }
            }
        }
        let bar = SteamWorkshopGlassBarView(frame: NSRect(x: 0, y: 0, width: 200, height: 40))
        bar.layer?.cornerRadius = 12
        bar.applyProgress(style: .downloading, fraction: 0.5, indeterminate: false, animated: false)
        bar.layoutSubtreeIfNeeded()
        let clip = bar.layer!.sublayers!.first { $0.masksToBounds }!
        precondition(bar.layer!.masksToBounds && clip.masksToBounds)
        precondition(clip.frame.width == 100 && clip.frame.height == 40)
        precondition(clip.cornerRadius == 12)
        bar.applyProgress(style: .downloading, fraction: 2, indeterminate: false, animated: false)
        precondition(clip.frame.width == 200)
        bar.applyProgress(style: .downloading, fraction: .nan, indeterminate: false, animated: false)
        precondition(clip.frame.width == 0)
        precondition(target.presses == 15)
        window.close()
        print("Detail footer: 15 width/title cases, one pinned action row and accessibility dispatch PASS")
    }
    @MainActor static func button(_ title: String, target: ActionTarget) -> InspectorFooterButton {
        InspectorFooterButton(title: title, image: NSImage(systemSymbolName: "arrow.down.circle", accessibilityDescription: nil), kind: .primary, target: target, action: #selector(ActionTarget.press))
    }
}
