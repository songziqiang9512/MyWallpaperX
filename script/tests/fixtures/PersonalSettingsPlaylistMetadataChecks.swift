import AppKit
import Foundation

extension PersonalSettingsImportHarness {
    @MainActor static func runPlaylistMetadataChecks(root: URL, manager: WallpaperManager, images: SILService,
                                                     checks: inout [String: Bool]) async throws {
        // The earlier source/termination assertions are complete. Start this
        // independent metadata section with an explicitly durable empty source,
        // rather than racing its previously scheduled missing-file cleanup.
        manager.wallpapersAutoSaveWorkItem?.cancel(); manager.missingIndexedSourceScanWorkItem?.cancel()
        manager.initialIndexInternalPublication = true; manager.wallpapers = []; manager.initialIndexInternalPublication = false
        try manager.persistWallpaperIndexNow([])
        images.wallpapers = []; try images.persistWallpaperMetadata([])
        let url = root.appendingPathComponent("cover-profile.sqlite")
        let store = UserCollectionsStore(url: url)
        let initial = try await store.snapshot()
        let controller = UserCollectionsController(store: store, snapshot: initial)
        let recovery = root.appendingPathComponent("cover-recovery.json")
        let importer = PersonalSettingsImportCoordinator(manager: manager, images: images, collections: controller, recoveryURL: recovery,
            readVideoSort: { .init(mode: .name, ascending: true) }, validateVideoSort: { _, _ in }, applyVideoSort: { _, _ in })
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2, bitsPerSample: 8,
            samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 8, bitsPerPixel: 32)!
        for x in 0..<2 { for y in 0..<2 {
            bitmap.setColor(NSColor(srgbRed: 0.3, green: 0.5, blue: 0.7, alpha: 1), atX: x, y: y)
        } }
        let asset = WallpaperPlaylistCoverAsset(imageData: bitmap.representation(using: .png, properties: [:])!, pixelWidth: 2, pixelHeight: 2)
        let fractionalDate = Date(timeIntervalSince1970: 1234.375)
        let id = try await controller.createPlaylist(metadata: .init(name: "Portable cover", descriptionText: "A description", customCoverAssetID: asset.id),
            coverAsset: asset, at: fractionalDate)
        let hidden = ref("hidden", .videoLibrary)
        let member = WallpaperOrganizationItem(reference: hidden, locator: .init(), isPublishedLocally: true, isAvailable: true)
        _ = try await controller.perform([.addMembers(id, [member], fractionalDate), .setFavorite(member, true, fractionalDate), .setLibraryExcluded([hidden], true)])
        let profile = root.appendingPathComponent("cover-profile.json")
        _ = try await importer.exportPersonalSettings(to: profile)
        let portableBytes = try Data(contentsOf: profile)
        let portable = try LibraryPersonalSettings.decode(portableBytes)
        checks["SchemaEightExportsOnlyReferencedControlledCoverCopiesAndExplicitHideStates"] = portable.schemaVersion == 8
            && portable.collections.coverAssets == [asset] && portable.collections.playlists.first?.descriptionText == "A description"
            && portable.collections.libraryExclusionStates.contains { $0.reference == hidden && $0.isExcluded } == true
            && portable.collections.expectedLibraryExclusions == nil
        let downloads = [WallpaperProvider.steamWorkshop, .pixabay, .wallhaven, .pixiv].map { ref($0 == .pixiv ? "123:p0" : "old-download-hide", $0) }
        _ = try await controller.perform(.setLibraryExcluded(downloads, true))
        let exported = try LibraryPersonalSettings.export(sources: [], preferences: portable.preferences, state: controller.snapshot, coverAssets: [asset])
        checks["DownloadProviderHidesAreNotExportedButLocalSourceHideRemainsPortable"] = exported.collections.libraryExclusionStates.contains { downloads.contains($0.reference) } == false
            && exported.collections.libraryExclusionStates.contains { $0.reference == hidden && $0.isExcluded } == true
        var collectionsWithDownloadHides = portable.collections
        collectionsWithDownloadHides.libraryExclusionStates = downloads.map { .init(reference: $0, isExcluded: true) }
            + [.init(reference: hidden, isExcluded: true)]
        for provider in [WallpaperProvider.steamWorkshop, .pixabay, .wallhaven, .pixiv] {
            let backing = ref("aliased-download-hide", provider == .pixiv ? .staticImageLibrary : .videoLibrary)
            var aliased = collectionsWithDownloadHides
            aliased.aliases = [.init(alias: backing, canonical: downloads.first { $0.provider == provider }!, proof: .restoredSourceRecord)]
            aliased.libraryExclusionStates.append(.init(reference: backing, isExcluded: true))
            let object = try JSONSerialization.jsonObject(with: LibraryPersonalSettings.encode(.init(exportedAt: Date(), preferences: portable.preferences, sources: [], collections: aliased))) as! [String: Any]
            let input = try LibraryPersonalSettings.decode(JSONSerialization.data(withJSONObject: object))
            let mapped = try LibraryPersonalSettings.plan(input, sources: [], beforePreferences: portable.preferences,
                targetPreferences: portable.preferences, state: controller.snapshot, normalizedPaths: [:], missingPathCount: 0)
            checks["SchemaEightRejectsAliased\(provider.rawValue)DownloadHideButKeepsLocalSource"] = mapped.collections.libraryExclusionStates.map(\.reference) == [hidden]
        }
        _ = try await controller.perform(.setLibraryExcluded(downloads, false))
        func transparentPNG(width: Int, height: Int) -> Data {
            let copy = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8,
                samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                bytesPerRow: width * 4, bitsPerPixel: 32)!
            copy.bitmapData!.initialize(repeating: 0, count: copy.bytesPerRow * height)
            copy.setColor(NSColor(srgbRed: 0.2, green: 0.4, blue: 0.6, alpha: 0.5), atX: width - 1, y: height - 1)
            return copy.representation(using: .png, properties: [:])!
        }
        for (label, width, height) in [("Boundary512x256", 512, 256), ("TransparentTinyPNG", 2, 2)] {
            let copy = WallpaperPlaylistCoverAsset(imageData: transparentPNG(width: width, height: height), pixelWidth: width, pixelHeight: height)
            var incoming = portable.collections
            incoming.playlists[0].customCoverAssetID = copy.id; incoming.coverAssets = [copy]
            try write(.init(exportedAt: Date(), preferences: .init(from: manager.settings), sources: [], collections: incoming), to: profile)
            _ = try await importer.importPersonalSettings(from: profile)
            let persisted = try await controller.playlistCoverAsset(id: copy.id, expectedEpoch: controller.snapshot.resetEpoch)
            let pixels = persisted.flatMap { NSBitmapImageRep(data: $0.imageData) }
            checks["SchemaEightImports" + label + "ThroughRealCoverValidation"] = persisted == copy
                && controller.snapshot.playlists.first { $0.id == id }?.customCoverAssetID == copy.id
                && pixels?.pixelsWide == width && pixels?.pixelsHigh == height && pixels?.colorAt(x: 0, y: 0)?.alphaComponent == 0
        }
        // Fractional dates must survive the actual recovery snapshot exactly.
        _ = try await controller.editPlaylistMetadata(id: id, expected: controller.snapshot.playlists[0].metadata,
            replacement: .init(name: "Portable cover", descriptionText: "A description", customCoverAssetID: asset.id),
            at: fractionalDate, expectedEpoch: controller.snapshot.resetEpoch)
        let automatic = WallpaperPlaylist(id: id, name: "Automatic", createdAt: Date(timeIntervalSince1970: 10), sidebarRank: 0)
        let clearPayload = PersonalSettingsPayload(exportedAt: Date(timeIntervalSince1970: 20), preferences: .init(from: manager.settings),
            sources: [], collections: .init(playlists: [automatic], libraryExclusionStates: [.init(reference: hidden, isExcluded: false)]))
        try write(clearPayload, to: profile)
        _ = try await importer.importPersonalSettings(from: profile)
        checks["SchemaEightExplicitAutomaticAndFalseHideAreAppliedByOriginalImportChain"] = controller.snapshot.playlists.first { $0.id == id }?.customCoverAssetID == nil
            && controller.snapshot.playlists.first { $0.id == id }?.descriptionText == nil && controller.snapshot.excludedLibraryReferences.isEmpty
        _ = try await controller.editPlaylistMetadata(id: id, expected: controller.snapshot.playlists[0].metadata,
            replacement: .init(name: "Automatic fractional"), at: fractionalDate, expectedEpoch: controller.snapshot.resetEpoch)
        let beforeBad = controller.snapshot
        let exactEncoder = JSONEncoder(); exactEncoder.dateEncodingStrategy = .iso8601
        let exactDecoder = JSONDecoder(); exactDecoder.dateDecodingStrategy = .iso8601
        checks["ExpectedOrganizationRecoveryCodecPreservesActualFractionalPlaylistMemberAndFavoriteDates"] =
            try exactDecoder.decode(LibraryCollectionsOrganizationState.self, from: exactEncoder.encode(beforeBad.organizationState)) == beforeBad.organizationState
                && beforeBad.playlists[0].modifiedAt == fractionalDate && beforeBad.members[0].addedAt == fractionalDate
                && beforeBad.favorites[0].favoritedAt == fractionalDate
        var badCollections = portable.collections
        badCollections.coverAssets = [.init(id: asset.id, imageData: Data("not-an-image".utf8), pixelWidth: 2, pixelHeight: 2)]
        try write(.init(exportedAt: Date(), preferences: .init(from: manager.settings), sources: [], collections: badCollections), to: profile)
        do {
            _ = try await importer.importPersonalSettings(from: profile)
            checks["UndecodableCoverCopyIsRejectedBeforeRecoveryOrRelationshipWrites"] = false
        } catch PersonalSettingsError.invalidPayload(_) {
            checks["UndecodableCoverCopyIsRejectedBeforeRecoveryOrRelationshipWrites"] = controller.snapshot == beforeBad
                && !FileManager.default.fileExists(atPath: recovery.path)
        }
        for (label, invalid) in [
            ("OversizedDeclaration", WallpaperPlaylistCoverAsset(id: asset.id, imageData: asset.imageData, pixelWidth: 8192, pixelHeight: 8192)),
            ("OversizedActualPixels", WallpaperPlaylistCoverAsset(id: asset.id, imageData: transparentPNG(width: 513, height: 2), pixelWidth: 2, pixelHeight: 2)),
            ("OversizedEncodedBytes", WallpaperPlaylistCoverAsset(id: asset.id,
                imageData: Data(repeating: 0, count: WallpaperPlaylistCoverAsset.maxEncodedBytes + 1), pixelWidth: 2, pixelHeight: 2))
        ] {
            badCollections.coverAssets = [invalid]
            try write(.init(exportedAt: Date(), preferences: .init(from: manager.settings), sources: [], collections: badCollections), to: profile)
            do {
                _ = try await importer.importPersonalSettings(from: profile)
                checks["SchemaEightRejects" + label + "BeforeRecoveryOrRelationshipWrites"] = false
            } catch PersonalSettingsError.invalidPayload(_) {
                checks["SchemaEightRejects" + label + "BeforeRecoveryOrRelationshipWrites"] = controller.snapshot == beforeBad
                    && !FileManager.default.fileExists(atPath: recovery.path) && importer.allowsEditing
            }
        }
        try portableBytes.write(to: profile)
        try sql(url, "CREATE TRIGGER cover_profile_fail BEFORE INSERT ON playlists BEGIN SELECT RAISE(ABORT,'controlled cover profile failure'); END")
        do {
            _ = try await importer.importPersonalSettings(from: profile)
            checks["CoverProfileFailureRetainsOriginalMetadataAndDurableRecovery"] = false
        } catch {
            checks["CoverProfileFailureRetainsOriginalMetadataAndDurableRecovery"] = controller.snapshot == beforeBad
                && FileManager.default.fileExists(atPath: recovery.path) && !importer.allowsEditing
        }
        try sql(url, "DROP TRIGGER cover_profile_fail")
        let resumed = PersonalSettingsImportCoordinator(manager: manager, images: images, collections: controller, recoveryURL: recovery,
            readVideoSort: { .init(mode: .name, ascending: true) }, validateVideoSort: { _, _ in }, applyVideoSort: { _, _ in })
        _ = try await resumed.resumeIfNeeded()
        let restoredAsset = try await controller.playlistCoverAsset(id: asset.id, expectedEpoch: controller.snapshot.resetEpoch)
        checks["RestartedOriginalRecoveryReplaysCoverBytesDescriptionAndHiddenStateExactlyOnce"] = resumed.allowsEditing
            && restoredAsset == asset && controller.snapshot.playlists.first { $0.id == id }?.descriptionText == "A description"
            && controller.snapshot.excludedLibraryReferences.contains { $0.reference == hidden }
        let reopened = UserCollectionsStore(url: url, allowCreate: false)
        let disk = try await reopened.snapshot()
        checks["PortableMetadataProfileReopensWithSameIdsAndNoMediaSourceSubstitution"] = disk == controller.snapshot
            && disk.playlists.count == 1 && disk.playlists[0].id == id
    }
}
