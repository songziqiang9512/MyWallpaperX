import Foundation

extension WallpaperProvider {
    nonisolated var libraryDisplayName: String {
        switch self {
        case .videoLibrary: return String(localized: "Local Videos")
        case .staticImageLibrary: return String(localized: "Local Images")
        case .steamWorkshop: return String(localized: "Workshop")
        case .pixabay: return "Pixabay"
        case .wallhaven: return "Wallhaven"
        case .pixiv: return "Pixiv"
        }
    }

    nonisolated var librarySearchTerms: [String] {
        switch self {
        case .videoLibrary: return [rawValue, libraryDisplayName, String(localized: "My Videos"), String(localized: "Video Library")]
        case .staticImageLibrary: return [rawValue, libraryDisplayName, String(localized: "My Images"), String(localized: "Image Library")]
        case .steamWorkshop: return [rawValue, libraryDisplayName, String(localized: "Steam Workshop"), String(localized: "Workshop Subscriptions")]
        case .pixabay, .wallhaven, .pixiv: return [rawValue, libraryDisplayName]
        }
    }
}

/// Navigation identity is independent of a mutable title or a source module.
nonisolated enum WallpaperLibraryPage: Hashable, Codable, Sendable {
    case videos, images, downloads, recent
    case workshop, pixabay, wallhaven, pixiv
    case playlists, favorites
    case playlist(UUID)

    func title(playlistName: String? = nil) -> String {
        switch self {
        case .videos: return String(localized: "My Videos")
        case .images: return String(localized: "My Images")
        case .downloads: return String(localized: "My Downloads")
        case .recent: return String(localized: "Recently Used")
        case .workshop: return String(localized: "Workshop")
        case .pixabay: return "Pixabay"
        case .wallhaven: return "Wallhaven"
        case .pixiv: return "Pixiv"
        case .playlists: return String(localized: "All Playlists")
        case .favorites: return String(localized: "Favorite")
        case .playlist: return playlistName ?? String(localized: "Playlist")
        }
    }

    var persistenceKey: String {
        switch self {
        case .videos: return "library.videos"
        case .images: return "library.images"
        case .downloads: return "library.downloads"
        case .recent: return "library.recent"
        case .workshop: return "browse.workshop"
        case .pixabay: return "browse.pixabay"
        case .wallhaven: return "browse.wallhaven"
        case .pixiv: return "browse.pixiv"
        case .playlists: return "playlists.all"
        case .favorites: return "playlists.favorites"
        case .playlist(let id): return "playlist." + id.uuidString
        }
    }

    var isRemoteBrowse: Bool {
        switch self {
        case .workshop, .pixabay, .wallhaven, .pixiv: return true
        default: return false
        }
    }


}

nonisolated enum WallpaperLibrarySort: String, Codable, Sendable {
    case sourceOrder, name, fileSize, createdAt, modifiedAt, lastUsed, addedAt, favoritedAt
}

nonisolated enum WallpaperLibraryStatusFilter: String, Codable, Sendable {
    case playable, unavailable, transferring, failed
}

nonisolated struct WallpaperLibraryQueryState: Codable, Equatable, Sendable {
    var search = ""
    var providers: Set<WallpaperProvider> = []
    var kinds: Set<WallpaperMediaKind> = []
    var statuses: Set<WallpaperLibraryStatusFilter> = []
    var showsAdultContent = true
    /// nil selects the page's default. Recent always retains success order.
    var sort: WallpaperLibrarySort? = nil
    var ascending = true
    var preferredColumns = 5
    var scrollAnchor: WallpaperReference? = nil
    /// A missing offset uses the native grid's first-item fallback.
    var scrollOffset: Double? = nil
    var scrollAtTop: Bool? = nil

    init(search: String = "", providers: Set<WallpaperProvider> = [], kinds: Set<WallpaperMediaKind> = [],
         statuses: Set<WallpaperLibraryStatusFilter> = [], sort: WallpaperLibrarySort? = nil,
         ascending: Bool = true,
         preferredColumns: Int = 5, scrollAnchor: WallpaperReference? = nil,
         scrollOffset: Double? = nil, scrollAtTop: Bool? = nil, showsAdultContent: Bool = true) {
        self.search = search; self.providers = providers; self.kinds = kinds; self.statuses = statuses
        self.sort = sort; self.ascending = ascending
        self.preferredColumns = preferredColumns; self.scrollAnchor = scrollAnchor
        self.scrollOffset = scrollOffset; self.scrollAtTop = scrollAtTop
        self.showsAdultContent = showsAdultContent
    }

    private enum CodingKeys: String, CodingKey {
        case search, providers, kinds, statuses, showsAdultContent, sort, ascending
        case preferredColumns, scrollAnchor, scrollOffset, scrollAtTop
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        search = try values.decode(String.self, forKey: .search)
        providers = try values.decode(Set<WallpaperProvider>.self, forKey: .providers)
        kinds = try values.decode(Set<WallpaperMediaKind>.self, forKey: .kinds)
        statuses = try values.decode(Set<WallpaperLibraryStatusFilter>.self, forKey: .statuses)
        showsAdultContent = try values.decodeIfPresent(Bool.self, forKey: .showsAdultContent) ?? true
        sort = try values.decodeIfPresent(WallpaperLibrarySort.self, forKey: .sort)
        ascending = try values.decode(Bool.self, forKey: .ascending)
        preferredColumns = try values.decodeIfPresent(Int.self, forKey: .preferredColumns) ?? 5
        scrollAnchor = try values.decodeIfPresent(WallpaperReference.self, forKey: .scrollAnchor)
        scrollOffset = try values.decodeIfPresent(Double.self, forKey: .scrollOffset)
        scrollAtTop = try values.decodeIfPresent(Bool.self, forKey: .scrollAtTop)
        guard (3...6).contains(preferredColumns), scrollOffset?.isFinite != false else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Invalid library view geometry"))
        }
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(search, forKey: .search)
        try values.encode(providers.sorted { $0.rawValue < $1.rawValue }, forKey: .providers)
        try values.encode(kinds.sorted { $0.rawValue < $1.rawValue }, forKey: .kinds)
        try values.encode(statuses.sorted { $0.rawValue < $1.rawValue }, forKey: .statuses)
        try values.encode(showsAdultContent, forKey: .showsAdultContent)
        try values.encodeIfPresent(sort, forKey: .sort)
        try values.encode(ascending, forKey: .ascending)
        try values.encode(preferredColumns, forKey: .preferredColumns)
        try values.encodeIfPresent(scrollAnchor, forKey: .scrollAnchor)
        try values.encodeIfPresent(scrollOffset, forKey: .scrollOffset)
        try values.encodeIfPresent(scrollAtTop, forKey: .scrollAtTop)
    }
}

nonisolated struct WallpaperPlaylistDirectoryEntry: Identifiable, Equatable, Sendable {
    let id: UUID
    let name: String
    /// Canonical members, including members whose local resource is unavailable.
    let count: Int
    /// The first canonical member's provider identity, even when unavailable.
    let coverReference: WallpaperReference?
    let createdAt: Date
    let modifiedAt: Date

    init(id: UUID, name: String, count: Int, coverReference: WallpaperReference?,
         createdAt: Date = .distantPast, modifiedAt: Date = .distantPast) {
        self.id = id
        self.name = name
        self.count = count
        self.coverReference = coverReference
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
    }
}

nonisolated struct WallpaperLibrarySelectionState: Equatable, Sendable {
    /// An action captures this token; a later page visit or selection revokes it.
    var sessionID = UUID()
    var references: Set<WallpaperReference> = []
    var focusedReference: WallpaperReference? = nil
    var isSelecting = false
}

/// One video-library sort preference; no navigation, filters, zoom or history.
nonisolated struct WallpaperLibraryVideoSortPreference: Codable, Equatable, Sendable {
    enum Mode: String, Codable, Sendable {
        case sourceOrder, name, fileSize, createdAt, lastUsed
    }
    var mode: Mode
    var ascending: Bool
}

nonisolated struct WallpaperLibraryVideoSortPatch: Codable, Equatable, Sendable {
    let before: WallpaperLibraryVideoSortPreference
    let target: WallpaperLibraryVideoSortPreference
}

nonisolated enum WallpaperLibraryVideoSortError: Error, LocalizedError {
    case unsupported, readOnly, changed, persistenceFailed
    var errorDescription: String? {
        switch self {
        case .unsupported: return String(localized: "The video library sort order can’t be used for personal settings.")
        case .readOnly: return String(localized: "The interface state couldn't be restored; your original settings were kept and the video library sort order was not changed.")
        case .changed: return String(localized: "The video library sort order changed after import and can’t overwrite the later choice.")
        case .persistenceFailed: return String(localized: "The video library sort order couldn’t be saved persistently; the import recovery record was kept.")
        }
    }
}
