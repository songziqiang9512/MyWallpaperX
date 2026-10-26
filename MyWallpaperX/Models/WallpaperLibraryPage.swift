import Foundation

extension WallpaperProvider {
    nonisolated var libraryDisplayName: String {
        switch self {
        case .videoLibrary: return "本地视频"
        case .staticImageLibrary: return "本地图片"
        case .steamWorkshop: return "Steam 创意工坊"
        case .pixabay: return "Pixabay"
        }
    }

    nonisolated var librarySearchTerms: [String] {
        switch self {
        case .videoLibrary: return [rawValue, libraryDisplayName, "我的视频", "视频库"]
        case .staticImageLibrary: return [rawValue, libraryDisplayName, "我的图片", "图片库"]
        case .steamWorkshop: return [rawValue, libraryDisplayName, "工坊订阅"]
        case .pixabay: return [rawValue, libraryDisplayName]
        }
    }
}

/// Navigation identity is independent of a mutable title or a source module.
nonisolated enum WallpaperLibraryPage: Hashable, Codable, Sendable {
    case videos, images, downloads, recent
    case workshop, pixabay
    case playlists, favorites
    case playlist(UUID)

    func title(playlistName: String? = nil) -> String {
        switch self {
        case .videos: return "我的视频"
        case .images: return "我的图片"
        case .downloads: return "我的下载"
        case .recent: return "最近使用"
        case .workshop: return "创意工坊"
        case .pixabay: return "Pixabay"
        case .playlists: return "所有播放列表"
        case .favorites: return "特别喜爱"
        case .playlist: return playlistName ?? "播放列表"
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
        case .playlists: return "playlists.all"
        case .favorites: return "playlists.favorites"
        case .playlist(let id): return "playlist." + id.uuidString
        }
    }

    var isRemoteBrowse: Bool {
        switch self {
        case .workshop, .pixabay: return true
        default: return false
        }
    }

    // The retired subscriptions page is read-only compatibility. Personal
    // browsing now belongs to Steam's existing context, not a Shell page.
    private enum CodingKeys: String, CodingKey {
        case videos, images, downloads, recent, workshop, workshopSubscriptions, pixabay, playlists, favorites, playlist
    }
    private enum PlaylistKey: String, CodingKey { case _0 }
    private struct Empty: Codable {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard container.allKeys.count == 1, let key = container.allKeys.first else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Invalid library page"))
        }
        if key == .playlist {
            let value = try container.nestedContainer(keyedBy: PlaylistKey.self, forKey: key)
            self = .playlist(try value.decode(UUID.self, forKey: ._0))
            return
        }
        _ = try container.nestedContainer(keyedBy: PlaylistKey.self, forKey: key)
        switch key {
        case .videos: self = .videos
        case .images: self = .images
        case .downloads: self = .downloads
        case .recent: self = .recent
        case .workshop, .workshopSubscriptions: self = .workshop
        case .pixabay: self = .pixabay
        case .playlists: self = .playlists
        case .favorites: self = .favorites
        case .playlist: preconditionFailure("handled above")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        let key: CodingKeys
        switch self {
        case .videos: key = .videos
        case .images: key = .images
        case .downloads: key = .downloads
        case .recent: key = .recent
        case .workshop: key = .workshop
        case .pixabay: key = .pixabay
        case .playlists: key = .playlists
        case .favorites: key = .favorites
        case .playlist(let id):
            var value = container.nestedContainer(keyedBy: PlaylistKey.self, forKey: .playlist)
            try value.encode(id, forKey: ._0)
            return
        }
        try container.encode(Empty(), forKey: key)
    }
}

nonisolated enum WallpaperLibrarySort: String, Codable, Sendable {
    case sourceOrder, name, fileSize, createdAt, modifiedAt, lastUsed, addedAt, favoritedAt, legacyTime
}

nonisolated enum WallpaperLibraryStatusFilter: String, Codable, Sendable {
    case all, playable, unavailable, transferring, failed
}

nonisolated struct WallpaperLibraryQueryState: Codable, Equatable, Sendable {
    var search = ""
    var provider: WallpaperProvider? = nil
    var kind: WallpaperMediaKind? = nil
    var status: WallpaperLibraryStatusFilter = .all
    /// nil selects the page's default. Recent always retains success order.
    var sort: WallpaperLibrarySort? = nil
    var ascending = true
    /// One frozen compatibility sequence, never a successful-use timestamp or
    /// a mutation of playlist membership. Choosing a new sort retires it.
    var legacyTimeOrder: [WallpaperReference]? = nil
    var preferredColumns = 5
    var scrollAnchor: WallpaperReference? = nil
    /// nil retains v1's explicitly unknown scroll geometry. Native consumers
    /// decide its documented first-item fallback once their items are known.
    var scrollOffset: Double? = nil
    var scrollAtTop: Bool? = nil

    init(search: String = "", provider: WallpaperProvider? = nil, kind: WallpaperMediaKind? = nil,
         status: WallpaperLibraryStatusFilter = .all, sort: WallpaperLibrarySort? = nil,
         ascending: Bool = true, legacyTimeOrder: [WallpaperReference]? = nil,
         preferredColumns: Int = 5, scrollAnchor: WallpaperReference? = nil,
         scrollOffset: Double? = nil, scrollAtTop: Bool? = nil) {
        self.search = search; self.provider = provider; self.kind = kind; self.status = status
        self.sort = sort; self.ascending = ascending; self.legacyTimeOrder = legacyTimeOrder
        self.preferredColumns = preferredColumns; self.scrollAnchor = scrollAnchor
        self.scrollOffset = scrollOffset; self.scrollAtTop = scrollAtTop
    }

    private enum CodingKeys: String, CodingKey {
        case search, provider, kind, status, sort, ascending, legacyTimeOrder
        case preferredColumns, scrollAnchor, scrollOffset, scrollAtTop
        case zoomOffset // Read-only v1 field; its width-dependent meaning is retired.
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        search = try values.decode(String.self, forKey: .search)
        provider = try values.decodeIfPresent(WallpaperProvider.self, forKey: .provider)
        kind = try values.decodeIfPresent(WallpaperMediaKind.self, forKey: .kind)
        status = try values.decode(WallpaperLibraryStatusFilter.self, forKey: .status)
        sort = try values.decodeIfPresent(WallpaperLibrarySort.self, forKey: .sort)
        ascending = try values.decode(Bool.self, forKey: .ascending)
        legacyTimeOrder = try values.decodeIfPresent([WallpaperReference].self, forKey: .legacyTimeOrder)
        preferredColumns = try values.decodeIfPresent(Int.self, forKey: .preferredColumns) ?? 5
        if !values.contains(.preferredColumns), values.contains(.zoomOffset) {
            // Preserve the old codec's type rejection without applying an
            // offset as a requested column count in the new layout.
            _ = try values.decode(Int.self, forKey: .zoomOffset)
        }
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
        try values.encodeIfPresent(provider, forKey: .provider)
        try values.encodeIfPresent(kind, forKey: .kind)
        try values.encode(status, forKey: .status)
        try values.encodeIfPresent(sort, forKey: .sort)
        try values.encode(ascending, forKey: .ascending)
        try values.encodeIfPresent(legacyTimeOrder, forKey: .legacyTimeOrder)
        try values.encode(preferredColumns, forKey: .preferredColumns)
        try values.encodeIfPresent(scrollAnchor, forKey: .scrollAnchor)
        try values.encodeIfPresent(scrollOffset, forKey: .scrollOffset)
        try values.encodeIfPresent(scrollAtTop, forKey: .scrollAtTop)
    }

    var permitsManualReordering: Bool {
        (sort == nil || sort == .sourceOrder) && search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && provider == nil && kind == nil && status == .all
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
        case sourceOrder, name, fileSize, createdAt, lastUsed, legacyTime
    }
    var mode: Mode
    var ascending: Bool
    var legacyTimeOrder: [WallpaperReference]? = nil
}

nonisolated struct WallpaperLibraryVideoSortPatch: Codable, Equatable, Sendable {
    let before: WallpaperLibraryVideoSortPreference
    let target: WallpaperLibraryVideoSortPreference
}

nonisolated enum WallpaperLibraryVideoSortError: Error, LocalizedError {
    case unsupported, readOnly, changed, persistenceFailed
    var errorDescription: String? {
        switch self {
        case .unsupported: return "视频库排序无法用于个人设置。"
        case .readOnly: return "界面状态无法恢复，原设置已保留；不能覆盖视频库排序。"
        case .changed: return "视频库排序已在导入后发生变化，不能覆盖后来的选择。"
        case .persistenceFailed: return "视频库排序未能持久保存，导入恢复记录已保留。"
        }
    }
}
