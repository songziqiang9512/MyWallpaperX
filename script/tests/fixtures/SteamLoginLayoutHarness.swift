import AppKit
import CoreImage

@main struct LoginLayoutHarness {
    @MainActor static func main() throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let output = CommandLine.arguments.count > 1 ? URL(fileURLWithPath: CommandLine.arguments[1]) : nil
        let panel = SteamLoginPanelView()
        let window = SteamLoginWindow(contentRect: NSRect(x: 0, y: 0, width: SteamLoginPanelView.width, height: SteamLoginPanelView.height),
                                      styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = panel
        window.center()
        let pages: [(String, SteamLoginPanelView.Page)] = [
            ("qr", .qr), ("password", .password),
            ("device", .guardInput(.deviceConfirmation)),
            ("guard", .guardInput(.deviceCode(previousIncorrect: true))),
            ("email", .guardInput(.emailCode(emailDomain: "a-very-long-mail-domain.example.com", previousIncorrect: false)))
        ]
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            window.appearance = NSAppearance(named: appearance)
            for (name, page) in pages {
                panel.showPage(page)
                precondition(window.frame.size == NSSize(width: SteamLoginPanelView.width, height: SteamLoginPanelView.height), "page \(name) frame \(window.frame)")
                panel.loginButton.keyEquivalent = "\r"
                panel.guardSubmitButton.keyEquivalent = "\r"
                panel.statusLabel.stringValue = name == "guard" ? "上一枚验证码未通过，请重新输入。你也可以切换登录方式，或取消本次登录。" : "请选择登录方式，安全连接你的 Steam 账号。"
                panel.setQRImage(name == "qr" ? SteamLoginQRCodeImageView.image(for: "https://example.invalid/steam-login-preview") : nil)
                window.orderFront(nil)
                panel.layoutSubtreeIfNeeded()
                RunLoop.main.run(until: Date().addingTimeInterval(0.08))
                panel.layoutSubtreeIfNeeded()
                let visibleControls = descendants(panel).compactMap { $0 as? NSControl }.filter {
                    !$0.isHiddenOrHasHiddenAncestor && ($0 is NSButton || ($0 as? NSTextField)?.isEditable == true)
                }
                for control in visibleControls {
                    let frame = control.convert(control.bounds, to: panel)
                    precondition(panel.bounds.insetBy(dx: -1, dy: -1).contains(frame), "control outside panel: \(control) \(frame)")
                    precondition(frame.width >= 20 && frame.height >= 16, "collapsed control: \(frame)")
                    for peer in visibleControls where peer !== control {
                        let other = peer.convert(peer.bounds, to: panel)
                        precondition(!frame.insetBy(dx: 1, dy: 1).intersects(other.insetBy(dx: 1, dy: 1)), "overlapping controls")
                    }
                }
                if name == "password" {
                    precondition(panel.usernameField.superview!.bounds.height == 40)
                    precondition(panel.passwordField.superview!.bounds.height == 40)
                    precondition(window.makeFirstResponder(panel.usernameField))
                }
                if let output {
                    let bitmap = panel.bitmapImageRepForCachingDisplay(in: panel.bounds)!
                    panel.cacheDisplay(in: panel.bounds, to: bitmap)
                    let data = bitmap.representation(using: .png, properties: [:])!
                    try data.write(to: output.appendingPathComponent("login-\(name)-\(appearance.rawValue).png"))
                }
            }
        }
        let challenge = "https://example.invalid/steam-login-preview"
        let image = SteamLoginQRCodeImageView.image(for: challenge)!
        let detector = CIDetector(ofType: CIDetectorTypeQRCode, context: nil, options: [CIDetectorAccuracy: CIDetectorAccuracyHigh])!
        let features = detector.features(in: CIImage(data: image.tiffRepresentation!)!)
        precondition((features.first as? CIQRCodeFeature)?.messageString == challenge, "rendered QR must decode exactly")
        // Switching repeatedly must not accumulate competing constraints or controls.
        for _ in 0..<20 { panel.showPage(.password); panel.showPage(.qr) }
        panel.setQRImage(nil)
        precondition(panel.qrImageView.image == nil && !panel.zoomQRButton.isEnabled)
        window.close()
        print("Login layout: 10 light/dark pages, bounds, control separation, focus and page reuse PASS")
    }
    @MainActor static func descendants(_ view: NSView) -> [NSView] {
        view.subviews.flatMap { [$0] + descendants($0) }
    }
}
