import Combine
import Foundation

struct WallpaperInterfacePreferences: Codable, Equatable {
    enum WorkshopPreview: String, Codable, CaseIterable {
        case hoverAndDetails, detailsOnly, staticCover
    }

    enum StartupPage: String, Codable, CaseIterable {
        case lastPage, videos, workshop, favorites, playlist
    }

    enum Appearance: String, Codable, CaseIterable {
        case system, light, dark
    }

    enum StatusIcon: String, Codable, CaseIterable {
        case gpuUsage, icon
    }

    enum Source: String, Codable, CaseIterable {
        case workshop, wallhaven, pixiv, pixabay
    }

    var workshopPreview: WorkshopPreview = .hoverAndDetails
    var startupPage: StartupPage = .lastPage
    var startupPlaylist: UUID?
    var appearance: Appearance = .system
    private var fixedIconAppearance: Appearance?
    var statusIcon: StatusIcon = .gpuUsage
    var hiddenSources: Set<Source> = []

    var iconAppearance: Appearance {
        get { fixedIconAppearance ?? .system }
        set { fixedIconAppearance = newValue == .system ? nil : newValue }
    }
}

/// Device-local presentation preferences, shared by the settings form and the
/// native surfaces that consume them.
@MainActor final class WallpaperInterfaceSettings {
    static let shared = WallpaperInterfaceSettings()
    private static let key = "MyWallpaperX.InterfacePreferences"
    private let defaults: UserDefaults
    private let changes = PassthroughSubject<WallpaperInterfacePreferences, Never>()

    private(set) var values: WallpaperInterfacePreferences

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        values = defaults.data(forKey: Self.key)
            .flatMap { try? JSONDecoder().decode(WallpaperInterfacePreferences.self, from: $0) } ?? .init()
    }

    func publisher<Value: Equatable>(for keyPath: KeyPath<WallpaperInterfacePreferences, Value>) -> AnyPublisher<Value, Never> {
        changes.map { $0[keyPath: keyPath] }.prepend(values[keyPath: keyPath]).removeDuplicates().eraseToAnyPublisher()
    }

    func update(_ edit: (inout WallpaperInterfacePreferences) -> Void) {
        var next = values
        edit(&next)
        guard next != values else { return }
        values = next
        defaults.set(try? JSONEncoder().encode(next), forKey: Self.key)
        changes.send(next)
    }

    func reset() {
        values = .init()
        defaults.removeObject(forKey: Self.key)
        changes.send(values)
    }
}
