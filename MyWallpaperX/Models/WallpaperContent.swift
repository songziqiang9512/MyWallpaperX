import Foundation

/// The original source scanner owns this state. A local entry mutation is not
/// evidence that the source's first complete scan succeeded.
nonisolated struct WallpaperSourceScanStatus: Equatable, Sendable {
    enum Phase: Equatable, Sendable {
        case loading
        case ready(warnings: [String])
        case failed(message: String)
    }
    let phase: Phase
    let hasSuccessfulScan: Bool

    static let initial = Self(phase: .loading, hasSuccessfulScan: false)
}

/// Publication and availability describe the last local resource, independently
/// of any initial acquisition or replacement/update attempt.
nonisolated enum WallpaperPublishedAvailability: String, Codable, Sendable {
    case remote, available, unavailable

    var isPublishedLocally: Bool { self != .remote }
    var isAvailable: Bool { self == .available }
}

nonisolated struct WallpaperContentCapabilities: OptionSet, Codable, Equatable, Sendable {
    let rawValue: UInt32
    static let inspect = Self(rawValue: 1 << 0)
    static let play = Self(rawValue: 1 << 1)
    static let organize = Self(rawValue: 1 << 2)
    static let delete = Self(rawValue: 1 << 3)
    static let reveal = Self(rawValue: 1 << 4)
    static let quickLook = Self(rawValue: 1 << 5)
    static let rename = Self(rawValue: 1 << 6)
    static let export = Self(rawValue: 1 << 7)
    static let download = Self(rawValue: 1 << 8)
    static let cancelDownload = Self(rawValue: 1 << 9)
    static let retryDownload = Self(rawValue: 1 << 10)
    static let retryUpdate = Self(rawValue: 1 << 11)
    static let subscribe = Self(rawValue: 1 << 12)
    static let openSource = Self(rawValue: 1 << 13)
}

/// Facts resolved by the existing source owner. Projection never probes files,
/// parses a Scene project or creates a second availability/index/cache owner.
nonisolated struct WallpaperContentLocalFacts: Equatable, Sendable {
    let isPublishedLocally: Bool
    let isAvailable: Bool
    let canPlay: Bool
    let canDelete: Bool
    var canReveal = true
    var canQuickLook = false
    var canRename = false
    var canExport = false
    var localURL: URL? = nil
    var resourceRevision: String? = nil

    var availability: WallpaperPublishedAvailability {
        isPublishedLocally ? (isAvailable ? .available : .unavailable) : .remote
    }

    var capabilities: WallpaperContentCapabilities {
        var value: WallpaperContentCapabilities = [.inspect]
        if isPublishedLocally && canDelete { value.insert(.delete) }
        if isPublishedLocally && isAvailable {
            value.insert(.organize)
            if canPlay { value.insert(.play) }
            if canReveal { value.insert(.reveal) }
            if canQuickLook { value.insert(.quickLook) }
            if canRename { value.insert(.rename) }
            if canExport { value.insert(.export) }
        }
        return value
    }
}

nonisolated struct WallpaperContentTransferState: Codable, Equatable, Sendable {
    enum Phase: String, Codable, Sendable {
        case idle, queued, connecting, preparing, transferring, validating, publishing, waiting, failed
    }
    let phase: Phase
    var totalBytes: Int64? = nil
    var completedBytes: Int64? = nil
    var failureMessage: String? = nil
    var jobKey: String? = nil
    var attempt: Int? = nil
    var sequence: Int? = nil

    static let idle = Self(phase: .idle)
    var fraction: Double? {
        guard let totalBytes, totalBytes > 0, let completedBytes else { return nil }
        return min(1, max(0, Double(completedBytes) / Double(totalBytes)))
    }
    var canCancel: Bool {
        switch phase {
        case .queued, .connecting, .preparing, .transferring, .validating, .waiting: return true
        case .idle, .publishing, .failed: return false
        }
    }
}

nonisolated struct WallpaperContentMetadataField: Codable, Equatable, Sendable {
    let label: String
    let value: String
}

nonisolated struct WallpaperContentMetadata: Codable, Equatable, Sendable {
    var author: String? = nil
    var summary: String? = nil
    /// Full source description may differ from the display summary.
    var descriptionText: String? = nil
    var sourceTags: [String] = []
    var fileSizeBytes: Int64? = nil
    var durationSeconds: Double? = nil
    var resolutionText: String? = nil
    var createdAt: Date? = nil
    var modifiedAt: Date? = nil
    var lastUsedAt: Date? = nil
    var sourceURL: URL? = nil
    var previewURL: URL? = nil
    var previewVideoURL: URL? = nil
    var thumbnailPath: String? = nil
    var resourceRevision: String? = nil
    var detailFields: [WallpaperContentMetadataField] = []
}

/// A source-publication receipt or explicitly restored provenance supplied by
/// the publisher. Equal titles, file bytes or unverified paths cannot create it.
nonisolated struct WallpaperContentBackingPublication: Codable, Equatable, Sendable {
    let backingVideoID: String
    let publishedReference: WallpaperReference
    let proof: WallpaperAliasProof

    var alias: WallpaperReferenceAlias? {
        guard !backingVideoID.isEmpty, !publishedReference.sourceID.isEmpty,
              publishedReference.provider == .steamWorkshop || publishedReference.provider == .pixabay else { return nil }
        return WallpaperReferenceAlias(alias: WallpaperReference(provider: .videoLibrary, sourceID: backingVideoID),
                                       canonical: publishedReference, proof: proof)
    }
}

nonisolated struct WallpaperContentItem: Identifiable, Codable, Equatable, Sendable {
    /// Canonical relationship identity. providerReference remains the original
    /// owner's target for thumbnails, details and other source commands.
    let reference: WallpaperReference
    let providerReference: WallpaperReference
    let locator: WallpaperLocator
    let title: String
    let kind: WallpaperMediaKind
    let publishedAvailability: WallpaperPublishedAvailability
    let capabilities: WallpaperContentCapabilities
    let metadata: WallpaperContentMetadata
    let acquisition: WallpaperContentTransferState
    let update: WallpaperContentTransferState
    let aliases: [WallpaperReferenceAlias]

    var id: WallpaperReference { reference }
    var organizationItem: WallpaperOrganizationItem {
        WallpaperOrganizationItem(reference: reference, locator: locator,
                                  isPublishedLocally: publishedAvailability.isPublishedLocally,
                                  isAvailable: publishedAvailability.isAvailable)
    }
}
