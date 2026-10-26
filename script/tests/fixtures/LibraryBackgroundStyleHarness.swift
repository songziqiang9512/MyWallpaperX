import AppKit
import Combine

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
    func bind() {
        // ACTUAL_STYLE_BINDING
    }
    func refresh() {
        let settings = dependency.settings
        // ACTUAL_STYLE_REFRESH
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
    private var backgroundStyle = LibraryBackgroundStyle.listCoverTint
    func start() {
        // ACTUAL_STYLE_SUBSCRIPTION
    }
    // ACTUAL_STYLE_PROJECTION
}

@main enum LibraryBackgroundStyleHarness {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        var checks: [String: Bool] = [:]
        let controls = BackgroundSettingsControls()
        controls.setupDisplaySection(); controls.bind(); controls.refresh()
        checks["settings-uses-two-native-popup-choices-and-defaults-to-existing-tint"] = controls.libraryBackgroundPopup.itemTitles == ["列表封面取色", "macOS原生"]
            && (controls.libraryBackgroundPopup.selectedItem?.representedObject as? LibraryBackgroundStyle) == .listCoverTint
            && controls.displaySection.rows.first === controls.libraryBackgroundPopup
            && controls.libraryBackgroundPopup.identifier?.rawValue == "主窗口背景"
        let choseNative = controls.choose(.macOSNative)
        checks["native-popup-action-updates-the-real-settings-value"] = choseNative && controls.dependency.settings.libraryBackgroundStyle == .macOSNative
        controls.dependency.settings.libraryBackgroundStyle = .listCoverTint
        controls.refresh()
        checks["external-settings-update-restores-native-popup-selection"] = (controls.libraryBackgroundPopup.selectedItem?.representedObject as? LibraryBackgroundStyle) == .listCoverTint
        controls.isUpdatingUI = true
        _ = controls.choose(.macOSNative)
        checks["programmatic-settings-refresh-does-not-write-back-stale-popup"] = controls.dependency.settings.libraryBackgroundStyle == .listCoverTint

        let composition = BackgroundComposition(), first = UUID(), second = UUID()
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
        print(String(data: try JSONSerialization.data(withJSONObject: checks, options: [.sortedKeys]), encoding: .utf8)!)
    }
}
