import AppKit
import Combine

// Native popup/menu/action and the composition subscription/method are production
// declarations. Unrelated settings-row chrome and Shell outputs are recording
// leaves; this does not claim behind-window pixels or full settings layout.
@MainActor final class BackgroundSettingsDependency {
    @Published var settings = WallpaperSettings()
}
@MainActor final class BackgroundSettingsControls: NSObject {
    let dependency = BackgroundSettingsDependency()
    var isUpdatingUI = false
    let libraryBackgroundPopup = NSPopUpButton()
    let libraryCardClickPopup = NSPopUpButton()
    let multiDisplaySwitch = SettingsToggle()
    let keepDockIconSwitch = SettingsToggle()
    let fillModeFitButton = NSButton(radioButtonWithTitle: "Fit", target: nil, action: nil)
    let fillModeFillButton = NSButton(radioButtonWithTitle: "Fill", target: nil, action: nil)
    @objc private func openScreenSaverSettings() {}
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
        let form = SettingsFormView()
        controls.setupDisplaySection(form); controls.bind(); controls.refresh()
        checks["settings-uses-two-native-popup-choices-and-defaults-to-existing-tint"] = controls.libraryBackgroundPopup.itemTitles == LibraryBackgroundStyle.allCases.map(\.title)
            && (controls.libraryBackgroundPopup.selectedItem?.representedObject as? LibraryBackgroundStyle) == .listCoverTint
            && controls.libraryBackgroundPopup.isDescendant(of: form)
        let choseNative = controls.choose(.macOSNative)
        checks["native-popup-action-updates-the-real-settings-value"] = choseNative && controls.dependency.settings.libraryBackgroundStyle == .macOSNative
        controls.dependency.settings.libraryBackgroundStyle = .listCoverTint
        controls.refresh()
        checks["external-settings-update-restores-native-popup-selection"] = (controls.libraryBackgroundPopup.selectedItem?.representedObject as? LibraryBackgroundStyle) == .listCoverTint
        controls.isUpdatingUI = true
        _ = controls.choose(.macOSNative)
        checks["programmatic-settings-refresh-does-not-write-back-stale-popup"] = controls.dependency.settings.libraryBackgroundStyle == .listCoverTint

        controls.isUpdatingUI = false
        checks["card-click-native-popup-defaults-to-selection-only"] = controls.libraryCardClickPopup.itemTitles == LibraryCardClickAction.allCases.map(\.title)
            && (controls.libraryCardClickPopup.selectedItem?.representedObject as? LibraryCardClickAction) == .selectOnly
            && controls.libraryCardClickPopup.isDescendant(of: form)
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
        print(String(decoding: try JSONSerialization.data(withJSONObject: checks, options: [.sortedKeys]), as: UTF8.self))
    }
}
