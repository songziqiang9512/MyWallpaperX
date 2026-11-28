import AppKit
import Combine

/// Native form rows and their bindings. Menus contain the real persisted
/// value or a playlist UUID, so changes to labels don't change preferences.
final class AppKitInterfaceSettingsForm: NSObject {
    private typealias Preferences = WallpaperInterfacePreferences
    private let settings = WallpaperInterfaceSettings.shared
    private var subscriptions = Set<AnyCancellable>()
    private let startupPopup = NSPopUpButton()
    var playlists: () -> [(id: UUID, name: String)] = { [] }

    func install(in form: SettingsFormView) {
        form.addSection(String(localized: "Startup"))
        startupPopup.target = self
        startupPopup.action = #selector(selectStartupPage)
        startupPopup.setAccessibilityLabel(String(localized: "Page on Launch"))
        form.addGroup(String(localized: "Page on Launch"), controls: [startupPopup], symbol: "macwindow.badge.plus")
        refreshStartupPages()
        addPopup(String(localized: "App Appearance"), to: form, key: \.appearance, symbol: "circle.lefthalf.filled", titles: [
            String(localized: "Follow System"), String(localized: "Light"), String(localized: "Dark")
        ])
        addPopup(String(localized: "Menu Bar Icon"), to: form, key: \.statusIcon, symbol: "menubar.rectangle", titles: [
            String(localized: "GPU Percentage"), String(localized: "Wallpaper Icon")
        ])

        form.addSection(String(localized: "Workshop"))
        addPopup(String(localized: "Workshop Preview"), to: form, key: \.workshopPreview, symbol: "play.rectangle", titles: [
            String(localized: "On Hover and in Details"), String(localized: "In Details Only"), String(localized: "Static Covers")
        ])
        addSidebarSources(to: form)
        settings.publisher(for: \.startupPage).dropFirst()
            .sink { [weak self] _ in self?.refreshStartupPages() }.store(in: &subscriptions)
        NotificationCenter.default.publisher(for: NSPopUpButton.willPopUpNotification, object: startupPopup)
            .sink { [weak self] _ in self?.refreshStartupPages() }.store(in: &subscriptions)
    }

    func refreshStartupPages() {
        startupPopup.removeAllItems()
        let choices: [(Preferences.StartupPage, String)] = [
            (.lastPage, String(localized: "Last Open Page")), (.videos, String(localized: "My Videos")),
            (.workshop, String(localized: "Workshop")), (.favorites, String(localized: "Favorite"))
        ]
        for (page, title) in choices {
            startupPopup.addItem(withTitle: title)
            startupPopup.lastItem?.representedObject = page
        }
        let available = playlists()
        if !available.isEmpty {
            startupPopup.menu?.addItem(.separator())
            for playlist in available {
                // NSMenu permits duplicate names, whereas NSPopUpButton's title
                // insertion replaces a previous item with the same title.
                let item = NSMenuItem(title: playlist.name, action: nil, keyEquivalent: "")
                item.representedObject = playlist.id
                startupPopup.menu?.addItem(item)
            }
        }
        let values = settings.values
        let selected = startupPopup.itemArray.first {
            if values.startupPage == .playlist { return ($0.representedObject as? UUID) == values.startupPlaylist && values.startupPlaylist != nil }
            return ($0.representedObject as? Preferences.StartupPage) == values.startupPage
        }
        startupPopup.select(selected ?? startupPopup.item(at: 0))
    }

    @objc private func selectStartupPage() {
        let value = startupPopup.selectedItem?.representedObject
        settings.update {
            $0.startupPlaylist = value as? UUID
            $0.startupPage = (value as? Preferences.StartupPage) ?? .playlist
        }
    }

    private func addPopup<Value: CaseIterable & Equatable>(
        _ title: String, to form: SettingsFormView, key: WritableKeyPath<Preferences, Value>, symbol: String, titles: [String]
    ) {
        let popup = NSPopUpButton()
        popup.setAccessibilityLabel(title)
        let values = Array(Value.allCases)
        popup.addItems(withTitles: titles)
        bind(popup) { [weak self, weak popup] in
            guard let self, let popup, values.indices.contains(popup.indexOfSelectedItem) else { return }
            self.settings.update { $0[keyPath: key] = values[popup.indexOfSelectedItem] }
        }
        settings.publisher(for: key).sink { [weak popup] value in
            popup?.selectItem(at: values.firstIndex(of: value) ?? 0)
        }.store(in: &subscriptions)
        form.addGroup(title, controls: [popup], symbol: symbol)
    }

    private func addSidebarSources(to form: SettingsFormView) {
        let sources: [(Preferences.Source, String, String)] = [
            (.workshop, String(localized: "Workshop"), "shippingbox"), (.wallhaven, "Wallhaven", "photo"),
            (.pixiv, "Pixiv", "paintbrush.pointed"), (.pixabay, "Pixabay", "photo.stack")
        ]
        let controls = sources.map { source, label, symbol in
            let button = SettingsToggle()
            button.title = label
            button.symbolName = symbol
            bind(button) { [weak self, weak button] in
                guard let self, let button else { return }
                self.settings.update {
                    if button.state == .on { $0.hiddenSources.remove(source) }
                    else { $0.hiddenSources.insert(source) }
                }
            }
            settings.publisher(for: \.hiddenSources)
                .sink { [weak button] in button?.state = $0.contains(source) ? .off : .on }
                .store(in: &subscriptions)
            return button
        }
        form.addSection(String(localized: "Sidebar Sources"))
        form.addGroup(String(localized: "Sidebar Sources"), controls: controls)
    }

    private final class Action: NSObject {
        let perform: () -> Void
        init(_ perform: @escaping () -> Void) { self.perform = perform }
        @objc func invoke() { perform() }
    }

    private var actions: [Action] = []

    private func bind(_ control: NSControl, action: @escaping () -> Void) {
        let target = Action(action)
        actions.append(target)
        control.target = target
        control.action = #selector(Action.invoke)
    }
}
