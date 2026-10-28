import AppKit
import Combine

// ACTUAL_SETTINGS_BACKGROUND

@MainActor final class BackgroundTintContentController: NSViewController {
    override func loadView() { view = SettingsRootBackgroundView(frame: .init(x: 0, y: 0, width: 300, height: 200)) }
    func refresh() {}
    // ACTUAL_SETTINGS_TINT_CONSUMER
}

/// Only settings-row refresh and window sizing are leaves. The actual cache,
/// visible consumer, show and native lifecycle methods execute unchanged.
@MainActor final class BackgroundSettingsWindowController: NSWindowController, NSWindowDelegate {
    private let contentController = BackgroundTintContentController()
    private var mainWindowTint: NSColor?
    private var hasShownWindow = false
    init() {
        let window = NSWindow(contentViewController: contentController)
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
    }
    required init?(coder: NSCoder) { nil }
    private func updateWindowSize() {}
    var background: SettingsRootBackgroundView { contentController.view as! SettingsRootBackgroundView }
    // ACTUAL_SETTINGS_TINT_STORE
    // ACTUAL_SETTINGS_TINT_SHOW
    // ACTUAL_SETTINGS_TINT_RESTORE
    // ACTUAL_SETTINGS_TINT_WILL_MINIATURIZE
    // ACTUAL_SETTINGS_TINT_WILL_CLOSE
}

// Native popup/menu/action and the composition subscription/method are production
// declarations. Unrelated settings-row chrome and Shell outputs are recording
// leaves; this does not claim behind-window pixels or full settings layout.
@MainActor final class BackgroundSettingsDependency {
    @Published var settings = WallpaperSettings()
}
@MainActor final class BackgroundRows {
    var rows: [NSView] = []
    func addRow(_ row: NSView) { rows.append(row) }
}
@MainActor final class BackgroundSettingsControls: NSObject {
    let dependency = BackgroundSettingsDependency()
    var isUpdatingUI = false
    let libraryBackgroundPopup = NSPopUpButton()
    let libraryCardClickPopup = NSPopUpButton()
    let multiDisplaySwitch = NSSwitch()
    let fillModeFitButton = NSButton(radioButtonWithTitle: "Fit", target: nil, action: nil)
    let fillModeFillButton = NSButton(radioButtonWithTitle: "Fill", target: nil, action: nil)
    let displaySection = BackgroundRows()
    func makeSettingRow(title: String, iconSystemName: String?, trailing: NSView) -> NSView {
        trailing.identifier = NSUserInterfaceItemIdentifier(title)
        return trailing
    }
    // ACTUAL_DISPLAY_SETUP
    // ACTUAL_STYLE_ACTION
    // ACTUAL_CLICK_ACTION
    func bind() {
        // ACTUAL_STYLE_BINDING
        // ACTUAL_CLICK_BINDING
    }
    func refresh() {
        let settings = dependency.settings
        // ACTUAL_STYLE_REFRESH
        // ACTUAL_CLICK_REFRESH
    }
    func chooseClick(_ action: LibraryCardClickAction) -> Bool {
        libraryCardClickPopup.selectItem(at: LibraryCardClickAction.allCases.firstIndex(of: action)!)
        return NSApp.sendAction(libraryCardClickPopup.action!, to: libraryCardClickPopup.target, from: libraryCardClickPopup)
    }
    func choose(_ style: LibraryBackgroundStyle) -> Bool {
        libraryBackgroundPopup.selectItem(at: LibraryBackgroundStyle.allCases.firstIndex(of: style)!)
        return NSApp.sendAction(libraryBackgroundPopup.action!, to: libraryBackgroundPopup.target, from: libraryBackgroundPopup)
    }
}

@MainActor final class BackgroundStyleSink {
    var values: [Bool] = []
    var onUpdate: (() -> Void)?
    func setUsesThumbnailTint(_ enabled: Bool) { values.append(enabled); onUpdate?() }
}
@MainActor final class BackgroundArtworkSink {
    var targets: [UUID?] = []
    func updateCurrentDirectory(firstPlaylistID: UUID?) { targets.append(firstPlaylistID) }
}
enum BackgroundPage { case playlists, videos }
struct BackgroundDirectoryEntry { let id: UUID }
struct BackgroundPresentation {
    var page = BackgroundPage.playlists
    struct State { var directoryEntries: [BackgroundDirectoryEntry] = [] }
    var state = State()
}
@MainActor final class BackgroundWorkspace { var presentation = BackgroundPresentation() }
@MainActor final class BackgroundComposition {
    let manager = BackgroundSettingsDependency()
    let sidebar = BackgroundStyleSink(), split = BackgroundStyleSink()
    let artwork = BackgroundArtworkSink(), workspace = BackgroundWorkspace()
    var subscriptions = Set<AnyCancellable>()
    var isVisible = true
    private var backgroundStyle = WallpaperSettings.defaults.libraryBackgroundStyle
    func start() {
        // ACTUAL_STYLE_SUBSCRIPTION
    }
    // ACTUAL_STYLE_PROJECTION
}

@main enum LibraryBackgroundStyleHarness {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        NSApp.finishLaunching()
        var checks: [String: Bool] = [:]
        let controls = BackgroundSettingsControls()
        controls.setupDisplaySection(); controls.bind(); controls.refresh()
        checks["settings-uses-two-native-popup-choices-and-defaults-to-existing-tint"] = controls.libraryBackgroundPopup.itemTitles == ["按列表取色", "macOS原生"]
            && (controls.libraryBackgroundPopup.selectedItem?.representedObject as? LibraryBackgroundStyle) == .listCoverTint
            && controls.displaySection.rows.first === controls.libraryBackgroundPopup
            && controls.libraryBackgroundPopup.identifier?.rawValue == "APP界面色调"
        let choseNative = controls.choose(.macOSNative)
        checks["native-popup-action-updates-the-real-settings-value"] = choseNative && controls.dependency.settings.libraryBackgroundStyle == .macOSNative
        controls.dependency.settings.libraryBackgroundStyle = .listCoverTint
        controls.refresh()
        checks["external-settings-update-restores-native-popup-selection"] = (controls.libraryBackgroundPopup.selectedItem?.representedObject as? LibraryBackgroundStyle) == .listCoverTint
        controls.isUpdatingUI = true
        _ = controls.choose(.macOSNative)
        checks["programmatic-settings-refresh-does-not-write-back-stale-popup"] = controls.dependency.settings.libraryBackgroundStyle == .listCoverTint

        controls.isUpdatingUI = false
        checks["card-click-native-popup-defaults-to-selection-only"] = controls.libraryCardClickPopup.itemTitles == ["仅选中", "打开详情"]
            && (controls.libraryCardClickPopup.selectedItem?.representedObject as? LibraryCardClickAction) == .selectOnly
            && controls.libraryCardClickPopup.identifier?.rawValue == "卡片单击操作"
        checks["card-click-native-popup-action-writes-the-real-preference"] = controls.chooseClick(.openDetails)
            && controls.dependency.settings.libraryCardClickAction == .openDetails
        controls.dependency.settings.libraryCardClickAction = .selectOnly; controls.refresh()
        checks["external-card-click-preference-restores-popup-without-writing-back"] =
            (controls.libraryCardClickPopup.selectedItem?.representedObject as? LibraryCardClickAction) == .selectOnly
        controls.isUpdatingUI = true
        _ = controls.chooseClick(.openDetails)
        checks["programmatic-card-click-refresh-cannot-write-a-stale-menu-value"] = controls.dependency.settings.libraryCardClickAction == .selectOnly

        let composition = BackgroundComposition(), first = UUID(), second = UUID()
        composition.manager.settings.libraryBackgroundStyle = .listCoverTint
        composition.workspace.presentation.state.directoryEntries = [.init(id: first)]
        var authorityDuringSink: [LibraryBackgroundStyle] = []
        composition.split.onUpdate = { [weak composition] in
            if let style = composition?.manager.settings.libraryBackgroundStyle { authorityDuringSink.append(style) }
        }
        composition.start()
        checks["initial-tint-projection-uses-current-directory-first"] = composition.sidebar.values == [true]
            && composition.split.values == [true] && composition.artwork.targets == [first]
        composition.manager.settings.libraryBackgroundStyle = .macOSNative
        checks["settings-willSet-projects-published-native-value-not-old-authority"] = composition.sidebar.values.last == false
            && composition.split.values.last == false && composition.artwork.targets.last! == nil
            && authorityDuringSink.last == .listCoverTint
        let projectedCount = composition.split.values.count
        composition.manager.settings.volume = 8
        checks["unrelated-settings-never-reproject-background-or-directory-demand"] = composition.split.values.count == projectedCount
            && composition.artwork.targets.count == projectedCount
        composition.workspace.presentation.state.directoryEntries = [.init(id: second)]
        composition.manager.settings.libraryBackgroundStyle = .listCoverTint
        checks["switching-back-to-tint-uses-current-first-without-page-render"] = composition.artwork.targets.last! == second
            && composition.sidebar.values.last == true && composition.split.values.last == true
        composition.workspace.presentation.page = .videos
        let directoryCount = composition.artwork.targets.count
        composition.manager.settings.libraryBackgroundStyle = .macOSNative
        checks["non-directory-style-change-does-not-mutate-directory-artwork-demand"] = composition.artwork.targets.count == directoryCount
        composition.workspace.presentation.page = .playlists
        composition.isVisible = false
        composition.manager.settings.libraryBackgroundStyle = .listCoverTint
        checks["hidden-directory-does-not-acquire-tint-only-cover-demand"] = composition.artwork.targets.last! == nil
        let fresh = BackgroundComposition()
        fresh.workspace.presentation.state.directoryEntries = [.init(id: second)]; fresh.start()
        checks["fresh-default-keeps-existing-list-tint-and-directory-thumbnail-demand"] = fresh.sidebar.values == [true]
            && fresh.split.values == [true] && fresh.artwork.targets == [second]
        let restarted = BackgroundComposition()
        restarted.manager.settings.libraryBackgroundStyle = .macOSNative
        restarted.workspace.presentation.state.directoryEntries = [.init(id: second)]
        restarted.start()
        checks["initial-persisted-native-mode-never-requests-directory-tint"] = restarted.sidebar.values == [false]
            && restarted.split.values == [false] && restarted.artwork.targets == [nil]
        var released: BackgroundComposition? = BackgroundComposition()
        weak let weakComposition = released
        released?.start(); released = nil
        checks["settings-subscription-does-not-retain-composition"] = weakComposition == nil
        let tintWindow = NSWindow(contentRect: .init(x: 10000, y: 10000, width: 300, height: 200),
            styleMask: [.titled], backing: .buffered, defer: false)
        tintWindow.isReleasedWhenClosed = false
        let tintMain = AppKitListTintSurface(frame: .init(x: 0, y: 0, width: 300, height: 200))
        let tintSidebar = AppKitListTintSurface()
        tintWindow.contentView = tintMain; tintWindow.orderFrontRegardless()
        let settingsController = BackgroundSettingsWindowController()
        let settingsBackground = settingsController.background
        settingsBackground.usesListTint = true
        var samples = 0
        var sampledColor = ListThumbnailTintColor(red: 0.8, green: 0.3, blue: 0.2)
        var options = AppKitListBackgroundTint.DisplayOptions(allowsTint: true, reduceMotion: true)
        let projection = AppKitListBackgroundTint(sample: { _, completion in
            samples += 1; completion(sampledColor); return {}
        }, displayOptions: { options })
        projection.onProjectionChange = { settingsController.updateMainWindowTint($0, animated: $1) }
        projection.install(sidebar: tintSidebar, main: tintMain)
        let pixels = CGContext(data: nil, width: 8, height: 8, bitsPerComponent: 8, bytesPerRow: 32,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!.makeImage()!
        let source = ListThumbnailTintSource()
        source.update(id: "same-owner", assets: ["thumbnail"]) { receive in
            receive(NSImage(cgImage: pixels, size: .init(width: 8, height: 8))); return {}
        }
        projection.bind(source)
        checks["hidden-settings-consumer-only-retains-the-latest-projected-output"] = settingsBackground.listTint == nil
            && settingsBackground.layer!.sublayers!.first!.backgroundColor == nil && samples == 1
        settingsController.showWindow()
        settingsBackground.layoutSubtreeIfNeeded()
        let tintedLayer = settingsBackground.layer!.sublayers!.first!
        var expectedTint = settingsBackground.listTint!.cgColor
        settingsBackground.effectiveAppearance.performAsCurrentDrawingAppearance {
            expectedTint = (settingsBackground.listTint!.usingColorSpace(.sRGB) ?? settingsBackground.listTint!).cgColor
        }
        checks["settings-consumes-the-main-projection-without-loading-or-sampling-a-second-thumbnail"] = samples == 1
            && tintedLayer.backgroundColor == expectedTint && (tintedLayer.backgroundColor?.alpha ?? 0) > 0
        let key = AppKitListBackgroundTint.animationKey
        checks["first-settings-show-applies-the-latest-tint-without-an-animation"] = tintedLayer.animation(forKey: key) == nil
        let nativeBase = settingsBackground.layer!.backgroundColor
        settingsBackground.usesListTint = false
        checks["settings-native-mode-preserves-its-original-system-background"] = tintedLayer.backgroundColor == nil
            && settingsBackground.layer!.backgroundColor == nativeBase && samples == 1
        settingsBackground.usesListTint = true; settingsController.updateMainWindowTint(nil, animated: false)
        checks["settings-without-a-main-window-tint-uses-only-its-system-background"] = tintedLayer.backgroundColor == nil && samples == 1
        let root = settingsBackground, layer = tintedLayer, controller = settingsController, main = tintMain
        func pump(_ seconds: TimeInterval) {
            CATransaction.flush()
            let deadline = Date().addingTimeInterval(seconds)
            repeat {
                controller.window?.displayIfNeeded()
                if let event = NSApp.nextEvent(matching: .any, until: Date().addingTimeInterval(0.005), inMode: .default, dequeue: true) { NSApp.sendEvent(event) }
                NSApp.updateWindows()
            } while Date() < deadline
        }
        func rgba(_ color: CGColor?) -> [CGFloat]? {
            guard let color, let value = NSColor(cgColor: color)?.usingColorSpace(.deviceRGB) else { return nil }
            return [value.redComponent, value.greenComponent, value.blueComponent, value.alphaComponent]
        }
        func animation() -> CABasicAnimation? { layer.animation(forKey: key) as? CABasicAnimation }
        func animationColor(_ value: Any?) -> [CGFloat]? {
            guard let value, CFGetTypeID(value as CFTypeRef) == CGColor.typeID else { return nil }
            return rgba((value as! CGColor))
        }
        func close(_ lhs: [CGFloat]?, _ rhs: [CGFloat]?, tolerance: CGFloat = 0.04) -> Bool {
            guard let lhs, let rhs else { return false }
            return zip(lhs, rhs).allSatisfy { abs($0 - $1) < tolerance }
        }
        func update(_ id: String) {
            source.update(id: id, assets: [id]) { receive in
                receive(NSImage(cgImage: pixels, size: .init(width: 8, height: 8))); return {}
            }
        }
        let unloaded = BackgroundTintContentController()
        unloaded.updateMainWindowTint(.red, animated: true)
        checks["projection-callback-does-not-load-unopened-settings-content"] = !unloaded.isViewLoaded
        controller.updateMainWindowTint(NSColor(srgbRed: 0.8, green: 0.3, blue: 0.2, alpha: 0.09), animated: false)
        pump(0.03)
        options.reduceMotion = false; sampledColor = .init(red: 0.1, green: 0.2, blue: 0.9)
        update("settings-blue")
        checks["settings-and-main-share-one-075-second-native-color-transition"] = animation()?.keyPath == "backgroundColor"
            && animation()?.duration == 0.75 && (main.layer?.animation(forKey: key) as? CABasicAnimation)?.duration == 0.75
            && samples == 2
        pump(0.15)
        let visible = rgba(layer.presentation()?.backgroundColor), oldTarget = rgba(layer.backgroundColor)
        sampledColor = .init(red: 0.2, green: 0.8, blue: 0.3); update("settings-green")
        let transitionFacts: [String: Any] = ["settingsDuration": animation()?.duration ?? -1,
            "mainDuration": (main.layer?.animation(forKey: key) as? CABasicAnimation)?.duration ?? -1,
            "visibleBeforeRetarget": visible ?? [], "oldModelTarget": oldTarget ?? [],
            "interruptedFrom": animationColor(animation()?.fromValue) ?? [],
            "newModelTarget": rgba(layer.backgroundColor) ?? [], "windowVisible": controller.window?.isVisible == true]
        checks["interrupted-settings-tint-continues-from-its-real-presentation-color"] = visible != nil
            && close(animationColor(animation()?.fromValue), visible) && !close(visible, oldTarget, tolerance: 0.1)
            && animation()?.duration == 0.75 && layer.animationKeys()?.filter { $0 == key }.count == 1 && samples == 3
        options.reduceMotion = true
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)
        checks["original-owner-reduce-motion-output-removes-both-owned-animations-immediately"] = animation() == nil
            && main.layer?.animation(forKey: key) == nil && close(rgba(layer.backgroundColor), rgba(main.layer?.backgroundColor)) && samples == 3
        options.reduceMotion = false; sampledColor = .init(red: 0.9, green: 0.2, blue: 0.1); update("settings-red")
        checks["native-mode-counterexample-starts-with-a-running-tint-transition"] = animation() != nil
        root.usesListTint = false
        checks["settings-native-mode-removes-only-its-tint-immediately"] = layer.backgroundColor == nil && animation() == nil
        root.usesListTint = true
        sampledColor = .init(red: 0.1, green: 0.3, blue: 0.8); update("settings-appearance")
        checks["appearance-counterexample-starts-with-a-running-tint-transition"] = animation() != nil
        let nextIsDark = root.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) != .darkAqua
        root.appearance = NSAppearance(named: nextIsDark ? .darkAqua : .aqua); pump(0.02)
        checks["settings-appearance-reprojects-the-current-dynamic-color-without-a-transition"] = animation() == nil
            && abs((layer.backgroundColor?.alpha ?? 0) - (nextIsDark ? 0.12 : 0.09)) < 0.002
        controller.window?.orderOut(nil)
        let hiddenColor = layer.backgroundColor
        let latest = NSColor(srgbRed: 0.2, green: 0.4, blue: 0.9, alpha: 0.12)
        controller.updateMainWindowTint(latest, animated: true)
        checks["hidden-settings-does-not-project-or-animate-a-new-thumbnail-output"] = layer.backgroundColor == hiddenColor && animation() == nil
        controller.showWindow()
        checks["reopening-settings-applies-the-buffered-output-immediately"] = layer.backgroundColor == latest.cgColor && animation() == nil
        controller.updateMainWindowTint(.red, animated: true)
        controller.window?.close()
        checks["native-settings-close-finishes-the-owned-tint-transition"] = animation() == nil
        tintWindow.close()
        FileHandle.standardError.write(try JSONSerialization.data(withJSONObject: transitionFacts, options: [.sortedKeys]))
        FileHandle.standardError.write(Data([10]))
        print(String(data: try JSONSerialization.data(withJSONObject: checks, options: [.sortedKeys]), encoding: .utf8)!)
    }
}
