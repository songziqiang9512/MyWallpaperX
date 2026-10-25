import AppKit
import Foundation
import ImageIO

// PRODUCTION_STATIC_IMAGE_MODEL

@main
struct WallpaperContentProjectionHarness {
    static func main() throws {
        var checks: [String: Bool] = [:]
        let local = WallpaperContentLocalFacts(isPublishedLocally: true, isAvailable: true,
                                               canPlay: true, canDelete: true, canQuickLook: true,
                                               canRename: true, canExport: true,
                                               resourceRevision: "revision-original")
        let unavailable = WallpaperContentLocalFacts(isPublishedLocally: true, isAvailable: false,
                                                     canPlay: true, canDelete: true, canQuickLook: true)
        let remote = WallpaperContentLocalFacts(isPublishedLocally: false, isAvailable: true,
                                                canPlay: true, canDelete: true, canQuickLook: true)
        let video = VideoWallpaper(id: "42", title: "Shared title", path: "/never-opened/movie.mp4",
                                   thumbnailPath: "/never-opened/thumb.png", isFavorite: true,
                                   lastUsed: Date(timeIntervalSince1970: 100), tags: ["Old tag"],
                                   fileSize: 4096, duration: 12, resolution: "1920x1080",
                                   firstIndexedAt: Date(timeIntervalSince1970: 30))
        let ownVideo = VideoLibraryContentProjection.project(video, facts: local)
        checks["video uses original identity without a receipt"] = ownVideo.reference == .init(provider: .videoLibrary, sourceID: "42")
        checks["video preserves resolved metadata and revision"] = ownVideo.metadata.durationSeconds == 12
            && ownVideo.metadata.fileSizeBytes == 4096 && ownVideo.metadata.resourceRevision == "revision-original"
            && ownVideo.metadata.thumbnailPath == video.thumbnailPath && ownVideo.title == video.title
        checks["video createdAt comes only from source admission not legacy lastUsed"] = ownVideo.metadata.createdAt == Date(timeIntervalSince1970: 30)
            && ownVideo.metadata.lastUsedAt == Date(timeIntervalSince1970: 100)
        let unknownTime = VideoWallpaper(id: "legacy", title: "Legacy", path: "/not-read/legacy.mp4", lastUsed: Date(timeIntervalSince1970: 200))
        checks["legacy video admission remains unknown without consulting media"] = VideoLibraryContentProjection.project(unknownTime, facts: local).metadata.createdAt == nil
        checks["local file existence is an injected fact"] = ownVideo.capabilities.contains([.organize, .play, .quickLook])
            && ownVideo.organizationItem.isPublishedLocally && ownVideo.organizationItem.isAvailable
        let steamReference = WallpaperReference(provider: .steamWorkshop, sourceID: "video:same.name")
        let receipt = WallpaperContentBackingPublication(backingVideoID: "42", publishedReference: steamReference,
                                                         proof: .publishedDownload)
        let backed = VideoLibraryContentProjection.project(video, facts: local, backing: receipt)
        checks["trusted publication retains original owner target"] = backed.reference == steamReference
            && backed.providerReference == ownVideo.reference && backed.aliases.first?.alias == ownVideo.reference
            && backed.metadata.createdAt == ownVideo.metadata.createdAt
        let wrongReceipt = WallpaperContentBackingPublication(backingVideoID: "different",
                                                              publishedReference: steamReference, proof: .publishedDownload)
        checks["unmatched receipt never aliases equal metadata"] = VideoLibraryContentProjection.project(video, facts: local,
                                                                                                        backing: wrongReceipt).aliases.isEmpty
        let absentVideo = VideoLibraryContentProjection.project(video, facts: unavailable)
        checks["missing local resource retains metadata and delete without new organization"] = absentVideo.publishedAvailability == .unavailable
            && absentVideo.capabilities.contains(.delete) && !absentVideo.capabilities.contains(.organize)
            && !absentVideo.capabilities.contains(.play) && absentVideo.locator.path == video.path

        let imageJSON = """
        {"id":"42","path":"/never-opened/still.heic","title":"Still","fileSize":8000,
        "pixelWidth":4000,"pixelHeight":3000,"tags":["Old image tag"],"lastUsed":0,"addedAt":0}
        """
        let image = try JSONDecoder().decode(SILWallpaper.self, from: Data(imageJSON.utf8))
        let still = StaticImageLibraryContentProjection.project(image, facts: local)
        checks["same numeric source ID stays distinct across providers"] = still.reference != ownVideo.reference
            && still.reference == .init(provider: .staticImageLibrary, sourceID: "42")
        checks["image metadata and local capabilities survive"] = still.kind == .image
            && still.metadata.resolutionText == "4000×3000" && still.metadata.fileSizeBytes == 8000
            && still.capabilities.contains([.organize, .play, .quickLook, .reveal])

        let browser = try browserItem(id: "42")
        let published = record(id: "42", contentType: .video, status: .ready, browser: browser)
        let failedUpdate = record(id: "42", contentType: .video, status: .failed("replacement failed"), browser: browser)
        let old = SteamWorkshopLibraryContentProjection.project(record: failedUpdate, facts: local)!
        checks["Steam full description survives a different display summary"] = old.metadata.summary == "Summary"
            && old.metadata.descriptionText == "Description"
        checks["Steam record tags missing from browser tags remain source-searchable"] = old.metadata.sourceTags == ["AuthorTag", "OriginalTag"]
        let legacyMetadata = try JSONSerialization.data(withJSONObject: ["sourceTags": ["legacy"], "detailFields": []])
        let decodedLegacyMetadata = try JSONDecoder().decode(WallpaperContentMetadata.self, from: legacyMetadata)
        checks["legacy metadata JSON without new optional description still decodes"] = decodedLegacyMetadata.descriptionText == nil
            && decodedLegacyMetadata.sourceTags == ["legacy"]
        checks["failed Steam update never revokes published playback or organization"] = old.publishedAvailability == .available
            && old.capabilities.contains([.play, .organize, .retryUpdate]) && old.acquisition.phase == .idle
            && old.update.phase == .failed && old.update.failureMessage == "replacement failed"
        let initial = SteamWorkshopLibraryContentProjection.project(record: failedUpdate, facts: remote)!
        checks["failed first download cannot organize or play"] = initial.publishedAvailability == .remote
            && initial.acquisition.phase == .failed && initial.update.phase == .idle
            && initial.capabilities.contains(.retryDownload) && !initial.capabilities.contains(.organize)
            && !initial.capabilities.contains(.play)
        let progress = SteamWorkshopDownloadProgressSnapshot(itemID: "42", jobKey: "job", attempt: 3,
                                                             sequence: 9, phase: .waiting, totalBytes: 100,
                                                             verifiedBytes: 37, failureMessage: nil)
        let waiting = SteamWorkshopLibraryContentProjection.project(record: published, facts: local, progress: progress)!
        checks["replacement progress is independent and keeps attempt identity"] = waiting.update.phase == .waiting
            && waiting.update.jobKey == "job" && waiting.update.attempt == 3
            && waiting.update.sequence == 9 && waiting.update.fraction == 0.37
            && waiting.capabilities.contains([.play, .organize, .cancelDownload])
        let mismatched = SteamWorkshopDownloadProgressSnapshot(itemID: "another", jobKey: "other-job", attempt: 5,
                                                                sequence: 50, phase: .failed, totalBytes: nil,
                                                                verifiedBytes: 0, failureMessage: "wrong item")
        checks["unrelated progress never changes the projected record"] = SteamWorkshopLibraryContentProjection.project(
            record: published, facts: local, progress: mismatched)?.update == .idle
        let synthetic = SteamWorkshopLibraryContentProjection.project(
            record: record(id: "video:same.name", contentType: .video, status: .ready), facts: local, backing: receipt)!
        checks["opaque standalone Steam video keeps local capabilities and publication alias"] = synthetic.reference == steamReference
            && synthetic.capabilities.contains([.organize, .play]) && !synthetic.capabilities.contains(.subscribe)
            && synthetic.aliases == backed.aliases
        let scene = SteamWorkshopLibraryContentProjection.project(
            record: record(id: "scene", contentType: .scene, status: .ready),
            facts: WallpaperContentLocalFacts(isPublishedLocally: true, isAvailable: true, canPlay: false, canDelete: true))!
        checks["unsupported local Scene may still be organized"] = scene.kind == .scene
            && scene.capabilities.contains(.organize) && !scene.capabilities.contains(.play)
        let web = SteamWorkshopLibraryContentProjection.project(record: record(id: "web", contentType: .web, status: .ready), facts: local)!
        checks["web kind and metadata use the original record"] = web.kind == .web && web.metadata.modifiedAt == Date(timeIntervalSince1970: 200)
        let browse = SteamWorkshopLibraryContentProjection.project(browserItem: browser, facts: remote, backing: receipt)!
        checks["remote Steam browse cannot gain local permissions or alias from hints"] = browse.capabilities.contains([.download, .subscribe, .openSource])
            && !browse.capabilities.contains([.organize]) && browse.aliases.isEmpty && browse.locator.path == nil
        checks["browser metadata does not become local tags"] = browse.metadata.sourceTags == ["AuthorTag"]
            && browse.metadata.author == "Author" && browse.metadata.detailFields == [.init(label: "Score", value: "98%")]
        checks["mismatched browser and record are rejected"] = SteamWorkshopLibraryContentProjection.project(
            record: published, browserItem: try browserItem(id: "other"), facts: local) == nil
        let unicodeRecord = record(id: "video:é", contentType: .video, status: .ready)
        checks["Unicode-equivalent opaque IDs cannot borrow browser metadata"] = SteamWorkshopLibraryContentProjection.project(
            record: unicodeRecord, browserItem: try browserItem(id: "video:e\u{301}"), facts: local) == nil
        let unicodeProgress = SteamWorkshopDownloadProgressSnapshot(itemID: "video:e\u{301}", jobKey: "unrelated-unicode",
                                                                     attempt: 1, sequence: 1, phase: .failed,
                                                                     totalBytes: nil, verifiedBytes: 0, failureMessage: "other identity")
        checks["Unicode-equivalent opaque IDs cannot borrow progress"] = SteamWorkshopLibraryContentProjection.project(
            record: unicodeRecord, facts: local, progress: unicodeProgress)?.update == .idle

        let online = OnlineLibraryVideoItem(id: 42, pageURL: "https://pixabay.com/videos/id-42/", tags: " forest, sky ",
                                            duration: 9, user: "Pixabay Author",
                                            videos: OnlineLibraryVideoFiles(large: OnlineLibraryVideoFile(
                                                url: "https://example.test/movie.mp4", width: 1920, height: 1080,
                                                size: 9999, thumbnail: "https://example.test/preview.jpg"),
                                                medium: nil, small: nil, tiny: nil))
        let pixabayReference = WallpaperReference(provider: .pixabay, sourceID: "42")
        let pixabayReceipt = WallpaperContentBackingPublication(backingVideoID: "42", publishedReference: pixabayReference,
                                                                proof: .publishedDownload)
        let remoteOnline = PixabayLibraryContentProjection.project(item: online, facts: remote, backing: pixabayReceipt)!
        checks["remote Pixabay remains unorganized despite matching number or title"] = remoteOnline.reference == pixabayReference
            && remoteOnline.capabilities.contains(.download) && !remoteOnline.capabilities.contains(.organize)
            && !remoteOnline.capabilities.contains(.play) && remoteOnline.aliases.isEmpty
        let download = PixabayPublishedDownload(id: 42, localURL: URL(fileURLWithPath: "/never-opened/42-Shared title.mp4"),
                                                fileSize: 5000, duration: 15, resolutionString: "1280×720",
                                                thumbnailSourceKey: "original-thumbnail-owner-key")
        let localOnline = PixabayLibraryContentProjection.project(item: online, download: download, facts: local,
                                                                  backing: pixabayReceipt)!
        checks["Pixabay preserves resolved downloaded metadata over remote values"] = localOnline.metadata.durationSeconds == 15
            && localOnline.metadata.fileSizeBytes == 5000 && localOnline.metadata.resolutionText == "1280×720"
            && localOnline.metadata.author == "Pixabay Author" && localOnline.metadata.sourceTags == ["forest", "sky"]
            && localOnline.capabilities.contains([.organize, .play, .delete])
        checks["only explicit matching published provenance emits alias"] = localOnline.aliases.first?.canonical == pixabayReference
            && PixabayLibraryContentProjection.project(download: download, facts: local)?.aliases.isEmpty == true
        let otherNamespaceReceipt = WallpaperContentBackingPublication(
            backingVideoID: "42", publishedReference: WallpaperReference(provider: .steamWorkshop, sourceID: "42"),
            proof: .publishedDownload)
        checks["same numbered receipts from another provider cannot emit aliases"] = PixabayLibraryContentProjection.project(
            download: download, facts: local, backing: otherNamespaceReceipt)?.aliases.isEmpty == true
            && SteamWorkshopLibraryContentProjection.project(record: published, facts: local,
                                                              backing: pixabayReceipt)?.aliases.isEmpty == true
        checks["same path and title never implicitly merge Steam and Pixabay"] = localOnline.reference != synthetic.reference
            && localOnline.reference != ownVideo.reference && localOnline.reference != still.reference
        let pixabayUpdate = PixabayLibraryContentProjection.project(download: download, facts: local,
            update: .init(phase: .failed, failureMessage: "replacement failed"))!
        checks["Pixabay update failure keeps existing local capabilities"] = pixabayUpdate.update.phase == .failed
            && pixabayUpdate.acquisition.phase == .idle && pixabayUpdate.capabilities.contains([.play, .organize])
            && !pixabayUpdate.capabilities.contains(.retryUpdate) && !pixabayUpdate.capabilities.contains(.cancelDownload)
        let acquiringOnline = PixabayLibraryContentProjection.project(item: online, facts: remote,
            acquisition: .init(phase: .transferring, totalBytes: 100, completedBytes: 25))!
        checks["Pixabay transfer progress cannot invent a cancellation command"] = acquiringOnline.acquisition.phase == .transferring
            && acquiringOnline.acquisition.fraction == 0.25 && !acquiringOnline.capabilities.contains(.cancelDownload)
            && !acquiringOnline.capabilities.contains(.organize)
        let failedInitialOnline = PixabayLibraryContentProjection.project(item: online, facts: remote,
            acquisition: .init(phase: .failed, failureMessage: "initial failed"))!
        checks["Pixabay initial failure retains only its existing download retry command"] = failedInitialOnline.capabilities.contains(.retryDownload)
            && !failedInitialOnline.capabilities.contains(.retryUpdate) && !failedInitialOnline.capabilities.contains(.cancelDownload)
        checks["missing source snapshots return no invented content"] = PixabayLibraryContentProjection.project(facts: remote) == nil
            && SteamWorkshopLibraryContentProjection.project(facts: remote) == nil

        let encoded = try JSONEncoder().encode([ownVideo, still, synthetic, localOnline])
        checks["shared content is a lossless metadata-only Codable value"] = try JSONDecoder().decode([WallpaperContentItem].self, from: encoded)
            == [ownVideo, still, synthetic, localOnline]
        let output = try JSONEncoder().encode(checks)
        print(String(decoding: output, as: UTF8.self))
    }

    private static func browserItem(id: String) throws -> SteamWorkshopBrowserItem {
        let object: [String: Any] = [
            "id": id, "title": "Shared title", "author": "Author", "hasAdultContent": false,
            "summary": "Summary", "descriptionText": "Description", "tags": ["AuthorTag"],
            "dependencyIDs": [], "previewAssetKind": "stillImage", "workshopTypeText": "video",
            "detailFields": [["label": "Score", "value": "98%"]],
            "detailURL": "https://steamcommunity.com/sharedfiles/filedetails/?id=\(id)"
        ]
        return try JSONDecoder().decode(SteamWorkshopBrowserItem.self, from: JSONSerialization.data(withJSONObject: object))
    }

    private static func record(id: String, contentType: SteamWorkshopDownloadContentType,
                               status: SteamWorkshopDownloadRecord.Status,
                               browser: SteamWorkshopBrowserItem? = nil) -> SteamWorkshopDownloadRecord {
        SteamWorkshopDownloadRecord(id: id, title: "Shared title", description: "Description", tags: ["OriginalTag"],
                                    folderURL: URL(fileURLWithPath: "/never-opened/record"), projectFileURL: nil,
                                    ownEntryHTMLURL: nil, dependencyHostEntryHTMLURL: nil, dependencyHostFolderURL: nil,
                                    entryHTMLURL: nil, resolvedWebRootURL: nil, previewURL: nil, sourceVideoURL: nil,
                                    exportedVideoURL: nil, updatedAt: Date(timeIntervalSince1970: 200), sizeText: "4 KB",
                                    status: status, browserItem: browser, contentType: contentType,
                                    dependencyItemID: nil, dependencyStatus: .none, createdAt: Date(timeIntervalSince1970: 100),
                                    sizeBytes: 4096)
    }
}
