import Foundation

/// Provider namespaces and opaque source IDs define identity. Media kind,
/// filenames and paths may change without changing a user's relationships.
nonisolated enum WallpaperProvider: String, Codable, CaseIterable, Sendable {
    case videoLibrary, staticImageLibrary, steamWorkshop, pixabay, wallhaven, pixiv

    /// Search normalization only. It neither validates remote actions nor
    /// changes opaque reference identity, including leading zeros.
    static func workshopItemIDSearchID(from query: String) -> String? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.count >= 6,
           trimmed.unicodeScalars.allSatisfy({ (48...57).contains($0.value) }) {
            return trimmed
        }
        guard let regex = try? NSRegularExpression(pattern: #"(?:^|[?&\s])id=(\d{6,})\b"#,
                                                   options: [.caseInsensitive, .dotMatchesLineSeparators]),
              let match = regex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)),
              let range = Range(match.range(at: 1), in: trimmed) else { return nil }
        return String(trimmed[range])
    }
}

nonisolated struct WallpaperReference: Hashable, Codable, Sendable {
    let provider: WallpaperProvider
    let sourceID: String

    var storageKey: String { provider.rawValue + ":" + Data(sourceID.utf8).base64EncodedString() }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.provider == rhs.provider && lhs.sourceID.utf8.elementsEqual(rhs.sourceID.utf8)
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(provider)
        hasher.combine(sourceID.utf8.count)
        for byte in sourceID.utf8 { hasher.combine(byte) }
    }


    init(provider: WallpaperProvider, sourceID: String) {
        self.provider = provider
        self.sourceID = sourceID
    }

    init?(storageKey: String) {
        guard let separator = storageKey.firstIndex(of: ":"),
              let provider = WallpaperProvider(rawValue: String(storageKey[..<separator])),
              let data = Data(base64Encoded: String(storageKey[storageKey.index(after: separator)...])),
              let sourceID = String(data: data, encoding: .utf8), !sourceID.isEmpty else { return nil }
        self.init(provider: provider, sourceID: sourceID)
        guard self.storageKey == storageKey else { return nil }
    }
}

nonisolated enum WallpaperMediaKind: String, Codable, Sendable {
    case image, video, web, scene, unknown
}

/// A recovery hint only. The provider still owns current file availability,
/// revision and thumbnails. A matching path alone never authorizes an alias.
nonisolated struct WallpaperLocator: Codable, Equatable, Sendable {
    var path: String?
    var titleHint: String?
    var mediaKind: WallpaperMediaKind
    var provenance: String?

    init(path: String? = nil, titleHint: String? = nil, mediaKind: WallpaperMediaKind = .unknown,
         provenance: String? = nil) {
        self.path = path
        self.titleHint = titleHint
        self.mediaKind = mediaKind
        self.provenance = provenance
    }
}

nonisolated struct WallpaperReferenceLocator: Codable, Equatable, Sendable {
    let reference: WallpaperReference
    var locator: WallpaperLocator
}

nonisolated struct WallpaperPlaylist: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var name: String
    let createdAt: Date
    var modifiedAt: Date
    var sidebarRank: Int
    var descriptionText: String?
    var customCoverAssetID: UUID?

    init(id: UUID = UUID(), name: String, createdAt: Date = Date(), modifiedAt: Date? = nil, sidebarRank: Int,
         descriptionText: String? = nil, customCoverAssetID: UUID? = nil) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt ?? createdAt
        self.sidebarRank = sidebarRank
        self.descriptionText = WallpaperPlaylistMetadata.normalizedDescription(descriptionText)
        self.customCoverAssetID = customCoverAssetID
    }

    var metadata: WallpaperPlaylistMetadata {
        .init(name: name, descriptionText: descriptionText, customCoverAssetID: customCoverAssetID)
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, createdAt, modifiedAt, sidebarRank, descriptionText, customCoverAssetID
        case createdAtReferenceDate, modifiedAtReferenceDate
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        name = try values.decode(String.self, forKey: .name)
        createdAt = try values.decodeIfPresent(Double.self, forKey: .createdAtReferenceDate)
            .map(Date.init(timeIntervalSinceReferenceDate:)) ?? values.decode(Date.self, forKey: .createdAt)
        modifiedAt = try values.decodeIfPresent(Double.self, forKey: .modifiedAtReferenceDate)
            .map(Date.init(timeIntervalSinceReferenceDate:)) ?? values.decode(Date.self, forKey: .modifiedAt)
        sidebarRank = try values.decode(Int.self, forKey: .sidebarRank)
        descriptionText = WallpaperPlaylistMetadata.normalizedDescription(try values.decodeIfPresent(String.self, forKey: .descriptionText))
        customCoverAssetID = try values.decodeIfPresent(UUID.self, forKey: .customCoverAssetID)
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(id, forKey: .id); try values.encode(name, forKey: .name)
        try values.encode(createdAt.timeIntervalSinceReferenceDate, forKey: .createdAtReferenceDate)
        try values.encode(modifiedAt.timeIntervalSinceReferenceDate, forKey: .modifiedAtReferenceDate)
        try values.encode(sidebarRank, forKey: .sidebarRank)
        try values.encodeIfPresent(descriptionText, forKey: .descriptionText)
        try values.encodeIfPresent(customCoverAssetID, forKey: .customCoverAssetID)
    }
}

/// The edit precondition deliberately excludes member order and modifiedAt.
/// Adding a member while a sheet is open does not change the user's draft.
nonisolated struct WallpaperPlaylistMetadata: Codable, Equatable, Sendable {
    var name: String
    var descriptionText: String?
    var customCoverAssetID: UUID?

    init(name: String, descriptionText: String? = nil, customCoverAssetID: UUID? = nil) {
        self.name = name
        self.descriptionText = Self.normalizedDescription(descriptionText)
        self.customCoverAssetID = customCoverAssetID
    }

    static func normalizedDescription(_ value: String?) -> String? {
        guard let text = value?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        return text
    }
}

/// An immutable, eagerly prepared image copy. No original file URL is retained.
/// Snapshots carry only its ID; the original Store supplies bytes on demand.
nonisolated struct WallpaperPlaylistCoverAsset: Codable, Equatable, Sendable, Identifiable {
    static let maxDimension = 512
    static let maxEncodedBytes = 4 * 1024 * 1024
    let id: UUID
    let imageData: Data
    let pixelWidth: Int
    let pixelHeight: Int

    init(id: UUID = UUID(), imageData: Data, pixelWidth: Int, pixelHeight: Int) {
        self.id = id; self.imageData = imageData
        self.pixelWidth = pixelWidth; self.pixelHeight = pixelHeight
    }

    var isValidControlledCopy: Bool {
        Self.allowsCopy(encodedByteCount: imageData.count, pixelWidth: pixelWidth, pixelHeight: pixelHeight)
    }

    static func allowsCopy(encodedByteCount: Int, pixelWidth: Int, pixelHeight: Int) -> Bool {
        (1...maxEncodedBytes).contains(encodedByteCount)
            && (1...maxDimension).contains(pixelWidth) && (1...maxDimension).contains(pixelHeight)
    }
}

/// A hide intent's original Store revision is its identity. Repeated explicit
/// hide revokes a previously captured restore even when visibility is unchanged.
nonisolated struct WallpaperLibraryExclusion: Codable, Equatable, Sendable {
    let reference: WallpaperReference
    let revision: Int64
}

nonisolated struct WallpaperPlaylistMember: Codable, Equatable, Sendable {
    let playlistID: UUID
    let reference: WallpaperReference
    var position: Int
    let addedAt: Date

    init(playlistID: UUID, reference: WallpaperReference, position: Int, addedAt: Date) {
        self.playlistID = playlistID; self.reference = reference; self.position = position; self.addedAt = addedAt
    }

    private enum CodingKeys: String, CodingKey { case playlistID, reference, position, addedAt, addedAtReferenceDate }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        playlistID = try values.decode(UUID.self, forKey: .playlistID)
        reference = try values.decode(WallpaperReference.self, forKey: .reference)
        position = try values.decode(Int.self, forKey: .position)
        addedAt = try values.decodeIfPresent(Double.self, forKey: .addedAtReferenceDate)
            .map(Date.init(timeIntervalSinceReferenceDate:)) ?? values.decode(Date.self, forKey: .addedAt)
    }
    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(playlistID, forKey: .playlistID); try values.encode(reference, forKey: .reference)
        try values.encode(position, forKey: .position)
        try values.encode(addedAt.timeIntervalSinceReferenceDate, forKey: .addedAtReferenceDate)
    }
}

nonisolated struct WallpaperFavorite: Codable, Equatable, Sendable {
    let reference: WallpaperReference
    var favoritedAt: Date?
    var migrationOrder: Int?

    init(reference: WallpaperReference, favoritedAt: Date? = nil, migrationOrder: Int? = nil) {
        self.reference = reference; self.favoritedAt = favoritedAt; self.migrationOrder = migrationOrder
    }
    private enum CodingKeys: String, CodingKey { case reference, favoritedAt, favoritedAtReferenceDate, migrationOrder }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        reference = try values.decode(WallpaperReference.self, forKey: .reference)
        favoritedAt = try values.decodeIfPresent(Double.self, forKey: .favoritedAtReferenceDate)
            .map(Date.init(timeIntervalSinceReferenceDate:)) ?? values.decodeIfPresent(Date.self, forKey: .favoritedAt)
        migrationOrder = try values.decodeIfPresent(Int.self, forKey: .migrationOrder)
    }
    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(reference, forKey: .reference)
        try values.encodeIfPresent(favoritedAt?.timeIntervalSinceReferenceDate, forKey: .favoritedAtReferenceDate)
        try values.encodeIfPresent(migrationOrder, forKey: .migrationOrder)
    }
}

nonisolated struct WallpaperRecentUse: Codable, Equatable, Sendable {
    let reference: WallpaperReference
    var lastSuccessfulUseAt: Date?
    var commitSequence: Int64
    var migrationOrder: Int?
}

nonisolated enum WallpaperAliasProof: String, Codable, Sendable {
    case publishedDownload, restoredSourceRecord, explicitUserRelocation
}

nonisolated struct WallpaperReferenceAlias: Codable, Equatable, Sendable {
    let alias: WallpaperReference
    let canonical: WallpaperReference
    let proof: WallpaperAliasProof
}

/// Normal user organization commands require a currently published local item.
/// Migration/explicit backup restore use their own recoverable import command.
nonisolated struct WallpaperOrganizationItem: Sendable {
    let reference: WallpaperReference
    let locator: WallpaperLocator
    let isPublishedLocally: Bool
    let isAvailable: Bool
}

nonisolated struct UserCollectionsSnapshot: Sendable, Equatable {
    let revision: Int64
    let resetEpoch: UUID
    let migrationManifestID: String?
    let playlists: [WallpaperPlaylist]
    let members: [WallpaperPlaylistMember]
    let favorites: [WallpaperFavorite]
    let recent: [WallpaperRecentUse]
    let aliases: [WallpaperReferenceAlias]
    let locators: [WallpaperReferenceLocator]
    let excludedLibraryReferences: [WallpaperLibraryExclusion]

    init(revision: Int64, resetEpoch: UUID, migrationManifestID: String?, playlists: [WallpaperPlaylist],
         members: [WallpaperPlaylistMember], favorites: [WallpaperFavorite], recent: [WallpaperRecentUse],
         aliases: [WallpaperReferenceAlias], locators: [WallpaperReferenceLocator],
         excludedLibraryReferences: [WallpaperLibraryExclusion] = []) {
        self.revision = revision; self.resetEpoch = resetEpoch; self.migrationManifestID = migrationManifestID
        self.playlists = playlists; self.members = members; self.favorites = favorites; self.recent = recent
        self.aliases = aliases; self.locators = locators; self.excludedLibraryReferences = excludedLibraryReferences
    }
}

/// Metadata-only payload. It neither imports files nor starts playback.
/// The settings exporter deliberately excludes `recent`; migration backups
/// retain it. The formal settings schema/version is owned by that exporter.
nonisolated struct LibraryCollectionsImport: Codable, Equatable, Sendable {
    var playlists: [WallpaperPlaylist] = []
    var members: [WallpaperPlaylistMember] = []
    var favorites: [WallpaperFavorite] = []
    var recent: [WallpaperRecentUse] = []
    var aliases: [WallpaperReferenceAlias] = []
    var locators: [WallpaperReferenceLocator] = []
}

/// A bounded Undo/import precondition. Playback history, cache/source hints and
/// database revision are deliberately outside organization equality.
nonisolated struct LibraryCollectionsOrganizationState: Codable, Equatable, Sendable {
    let playlists: [WallpaperPlaylist]
    let members: [WallpaperPlaylistMember]
    let favorites: [WallpaperFavorite]
    /// Validation only; organization Undo never restores identity aliases.
    let aliases: [WallpaperReferenceAlias]
}

extension UserCollectionsSnapshot {
    nonisolated var organizationState: LibraryCollectionsOrganizationState {
        .init(playlists: playlists, members: members, favorites: favorites, aliases: aliases)
    }
}

/// Explicit settings restore can retain offline references. This value cannot
/// contain recent history, playback/session state, credentials or wallpaper
/// media. Schema 7 and later carry only the App-owned, bounded custom cover copies.
nonisolated struct LibraryCollectionsPersonalSettingsImport: Codable, Equatable, Sendable {
    struct FavoriteState: Codable, Equatable, Sendable {
        let reference: WallpaperReference
        let isFavorite: Bool
        var favoritedAt: Date? = nil

        init(reference: WallpaperReference, isFavorite: Bool, favoritedAt: Date? = nil) {
            self.reference = reference; self.isFavorite = isFavorite; self.favoritedAt = favoritedAt
        }
        private enum CodingKeys: String, CodingKey { case reference, isFavorite, favoritedAt, favoritedAtReferenceDate }
        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            reference = try values.decode(WallpaperReference.self, forKey: .reference)
            isFavorite = try values.decode(Bool.self, forKey: .isFavorite)
            favoritedAt = try values.decodeIfPresent(Double.self, forKey: .favoritedAtReferenceDate)
                .map(Date.init(timeIntervalSinceReferenceDate:)) ?? values.decodeIfPresent(Date.self, forKey: .favoritedAt)
        }
        func encode(to encoder: Encoder) throws {
            var values = encoder.container(keyedBy: CodingKeys.self)
            try values.encode(reference, forKey: .reference); try values.encode(isFavorite, forKey: .isFavorite)
            try values.encodeIfPresent(favoritedAt?.timeIntervalSinceReferenceDate, forKey: .favoritedAtReferenceDate)
        }
    }
    struct LegacyPlaylistOrigin: Codable, Equatable, Sendable {
        let playlistID: UUID
        let sourceKey: String
        let tag: String
    }
    struct LibraryExclusionState: Codable, Equatable, Sendable {
        let reference: WallpaperReference
        let isExcluded: Bool
    }
    var playlists: [WallpaperPlaylist] = []
    var members: [WallpaperPlaylistMember] = []
    var favoriteStates: [FavoriteState] = []
    var locators: [WallpaperReferenceLocator] = []
    var legacyOrigins: [LegacyPlaylistOrigin] = []
    /// Explicitly declared backup provenance, never inferred from a filename.
    var aliases: [WallpaperReferenceAlias] = []
    var playlistMetadataIsExplicit = false
    var coverAssets: [WallpaperPlaylistCoverAsset] = []
    /// nil is an older profile/recovery: preserve all existing hide state.
    var libraryExclusionStates: [LibraryExclusionState]?
    /// Set by the import planner, never exported. A later hide intent must not
    /// be overwritten by recovery of an earlier multi-owner import.
    var expectedLibraryExclusions: [WallpaperLibraryExclusion]?

    init(playlists: [WallpaperPlaylist] = [], members: [WallpaperPlaylistMember] = [],
         favoriteStates: [FavoriteState] = [], locators: [WallpaperReferenceLocator] = [],
         legacyOrigins: [LegacyPlaylistOrigin] = [], aliases: [WallpaperReferenceAlias] = [],
         playlistMetadataIsExplicit: Bool = false, coverAssets: [WallpaperPlaylistCoverAsset] = [],
         libraryExclusionStates: [LibraryExclusionState]? = nil,
         expectedLibraryExclusions: [WallpaperLibraryExclusion]? = nil) {
        self.playlists = playlists; self.members = members; self.favoriteStates = favoriteStates
        self.locators = locators; self.legacyOrigins = legacyOrigins; self.aliases = aliases
        self.playlistMetadataIsExplicit = playlistMetadataIsExplicit; self.coverAssets = coverAssets
        self.libraryExclusionStates = libraryExclusionStates; self.expectedLibraryExclusions = expectedLibraryExclusions
    }

    private enum CodingKeys: String, CodingKey {
        case playlists, members, favoriteStates, locators, legacyOrigins, aliases
        case playlistMetadataIsExplicit, coverAssets, libraryExclusionStates, expectedLibraryExclusions
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        playlists = try values.decodeIfPresent([WallpaperPlaylist].self, forKey: .playlists) ?? []
        members = try values.decodeIfPresent([WallpaperPlaylistMember].self, forKey: .members) ?? []
        favoriteStates = try values.decodeIfPresent([FavoriteState].self, forKey: .favoriteStates) ?? []
        locators = try values.decodeIfPresent([WallpaperReferenceLocator].self, forKey: .locators) ?? []
        legacyOrigins = try values.decodeIfPresent([LegacyPlaylistOrigin].self, forKey: .legacyOrigins) ?? []
        aliases = try values.decodeIfPresent([WallpaperReferenceAlias].self, forKey: .aliases) ?? []
        playlistMetadataIsExplicit = try values.decodeIfPresent(Bool.self, forKey: .playlistMetadataIsExplicit) ?? false
        coverAssets = try values.decodeIfPresent([WallpaperPlaylistCoverAsset].self, forKey: .coverAssets) ?? []
        libraryExclusionStates = try values.decodeIfPresent([LibraryExclusionState].self, forKey: .libraryExclusionStates)
        expectedLibraryExclusions = try values.decodeIfPresent([WallpaperLibraryExclusion].self, forKey: .expectedLibraryExclusions)
    }
}

nonisolated enum UserCollectionsCommand: Sendable {
    case createPlaylist(WallpaperPlaylist)
    case createPlaylistWithCover(WallpaperPlaylist, WallpaperPlaylistCoverAsset?)
    case duplicatePlaylist(sourceID: UUID, playlist: WallpaperPlaylist)
    case editPlaylistMetadata(id: UUID, expected: WallpaperPlaylistMetadata, replacement: WallpaperPlaylistMetadata,
                              coverAsset: WallpaperPlaylistCoverAsset?, at: Date)
    case deletePlaylist(UUID)
    case reorderPlaylists([UUID])
    case addMembers(UUID, [WallpaperOrganizationItem], Date)
    case removeMembers(UUID, [WallpaperReference], Date)
    case setFavorite(WallpaperOrganizationItem, Bool, Date)
    case linkAlias(WallpaperReferenceAlias, Date)
    /// Explicit user-selected local replacement. The Store rechecks the old
    /// canonical relationship in its transaction before joining identities.
    case relocateLocalReference(WallpaperReference, WallpaperOrganizationItem, Date)
    case rememberLocator(WallpaperReferenceLocator)
    case removeRecent([WallpaperReference])
    case clearRecent
    case setLibraryExcluded([WallpaperReference], Bool)
    case clearLibraryExclusion(WallpaperReference, expectedRevision: Int64?)
    case restoreOrganization(expected: LibraryCollectionsOrganizationState, replacement: LibraryCollectionsOrganizationState)
}

/// This token revokes asynchronous metadata writes after reset/relaunch. It
/// does not accept, commit or sequence playback: the existing playback ticket
/// supplies the monotonic sequence after its successful product commit.
nonisolated struct LibraryHistoryWriterToken: Sendable, Equatable {
    let resetEpoch: UUID
    let publisherID: UUID
}

nonisolated enum UserCollectionsError: Error, LocalizedError, Equatable {
    case database(String)
    case unsupportedSchema(Int32)
    case corruptData(String)
    case invalidReference
    case invalidName
    case missingPlaylist
    case invalidOrder
    case unavailableForOrganization
    case staleResetEpoch
    case migrationConflict
    case closedForPublication
    case organizationConflict
    case personalSettingsConflict
    case playlistMetadataConflict
    case invalidCoverAsset

    var errorDescription: String? {
        switch self {
        case .database(let message): return "用户资料库读写失败：\(message)"
        case .unsupportedSchema(let version): return "用户资料库版本 \(version) 高于本 App 支持范围，请保留原文件。"
        case .corruptData(let field): return "用户资料库内容无法读取：\(field)"
        case .invalidReference: return "壁纸引用无效。"
        case .invalidName: return "播放列表名称不能为空。"
        case .missingPlaylist: return "播放列表已不存在。"
        case .invalidOrder: return "播放列表成员已变化，请重新排序。"
        case .unavailableForOrganization: return "仅可添加已下载或本地可用的壁纸。"
        case .staleResetEpoch: return "该操作已被资料库重置撤销。"
        case .migrationConflict: return "用户资料库已修改，不能覆盖为旧版本迁移数据。"
        case .closedForPublication: return "迁移暂存连接已关闭，请使用已发布的资料库。"
        case .organizationConflict: return "列表、喜爱或身份关系已变化，无法安全恢复该次整理操作。"
        case .personalSettingsConflict: return "个人设置导入的恢复状态已变化，请保留恢复文件后重新检查。"
        case .playlistMetadataConflict: return "播放列表信息已变化，请重新打开编辑窗口。"
        case .invalidCoverAsset: return "列表封面无法保存，原封面已保留。"
        }
    }
}
