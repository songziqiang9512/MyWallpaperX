import Foundation

private func ref(_ provider: WallpaperProvider, _ id: String) -> WallpaperReference {
    WallpaperReference(provider: provider, sourceID: id)
}

private func item(_ provider: WallpaperProvider, _ id: String, _ tags: [String] = [],
                  favorite: Bool = false, path: String? = nil) -> LibraryCollectionsMigrationItem {
    LibraryCollectionsMigrationItem(
        reference: ref(provider, id),
        locator: WallpaperLocator(path: path, titleHint: "Title \(id)",
                                  mediaKind: provider == .staticImageLibrary ? .image : .video,
                                  provenance: "legacy-record"),
        tags: tags, isFavorite: favorite
    )
}

private func alias(_ source: WallpaperReference, _ destination: WallpaperReference) -> WallpaperReferenceAlias {
    WallpaperReferenceAlias(alias: source, canonical: destination, proof: .publishedDownload)
}

private func mixedInput() -> LibraryCollectionsMigrationInput {
    let first = item(.videoLibrary, "backing-one", [" A ", "Café"], favorite: true,
                     path: "/disconnected/volume/first.mp4")
    let second = item(.videoLibrary, "42", ["A", "orphanVideo"], favorite: true)
    let duplicate = item(.videoLibrary, "backing-two", ["A"], favorite: true)
    let image = item(.staticImageLibrary, "42", ["A", "Image"], favorite: true,
                     path: "/disconnected/volume/still.heic")
    return LibraryCollectionsMigrationInput(
        manifestID: "capture-fixture-v1", capturedAt: Date(timeIntervalSince1970: 1_700_000_000),
        videos: [first, second, duplicate],
        videoTags: [" A ", "Café", "Empty", "UPPER", "case"],
        staticImages: [image, item(.staticImageLibrary, "another", ["orphanImage"])],
        staticImageTags: ["A", "Cafe\u{301}", "Image", "Case"],
        recent: [duplicate, first, image, item(.pixabay, "42"), item(.steamWorkshop, "42")],
        aliases: [alias(first.reference, ref(.steamWorkshop, "video:雪山.movie")),
                  alias(duplicate.reference, ref(.videoLibrary, "backing-one"))]
    )
}

private func errorName(_ body: () throws -> Void) -> String {
    do { try body(); return "success" }
    catch { return String(describing: error) }
}

@main
struct LibraryCollectionsMigrationHarness {
    static func main() throws {
        let scenario = CommandLine.arguments[1]
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let decoder = JSONDecoder()
        switch scenario {
        case "mixed":
            let input = mixedInput()
            let manifest = try LibraryCollectionsMigration.prepareManifest(for: input)
            let result = try LibraryCollectionsMigration.build(input, manifest: manifest)
            print(String(decoding: try encoder.encode(result), as: UTF8.self))
        case "prepare":
            let directory = URL(fileURLWithPath: CommandLine.arguments[2])
            let input = mixedInput()
            let manifest = try LibraryCollectionsMigration.prepareManifest(for: input)
            try encoder.encode(input).write(to: directory.appendingPathComponent("input.json"))
            try encoder.encode(manifest).write(to: directory.appendingPathComponent("manifest.json"))
            let result = try LibraryCollectionsMigration.build(input, manifest: manifest)
            try encoder.encode(result).write(to: directory.appendingPathComponent("before.json"))
            print("{}")
        case "resume", "recapture":
            let directory = URL(fileURLWithPath: CommandLine.arguments[2])
            let captured = try decoder.decode(LibraryCollectionsMigrationInput.self,
                                           from: Data(contentsOf: directory.appendingPathComponent("input.json")))
            let input = scenario == "resume" ? captured : LibraryCollectionsMigrationInput(
                manifestID: captured.manifestID, capturedAt: captured.capturedAt.addingTimeInterval(3600),
                videos: captured.videos, videoTags: captured.videoTags, staticImages: captured.staticImages,
                staticImageTags: captured.staticImageTags, recent: captured.recent, aliases: captured.aliases)
            let stored = try decoder.decode(LibraryCollectionsMigrationManifest.self,
                                            from: Data(contentsOf: directory.appendingPathComponent("manifest.json")))
            let manifest = try LibraryCollectionsMigration.prepareManifest(for: input, reusing: stored)
            let result = try LibraryCollectionsMigration.build(input, manifest: manifest)
            print(String(decoding: try encoder.encode(result), as: UTF8.self))
        case "empty":
            let input = LibraryCollectionsMigrationInput(manifestID: "empty-fallback",
                                                          capturedAt: .distantPast, videoTags: ["Empty"])
            let manifest = try LibraryCollectionsMigration.prepareManifest(for: input)
            print(String(decoding: try encoder.encode(LibraryCollectionsMigration.build(input, manifest: manifest)),
                         as: UTF8.self))
        case "recent":
            let recent = [item(.videoLibrary, "alias")] + (0..<75).map { item(.pixabay, String($0)) }
                + [item(.pixabay, "1")]
            let input = LibraryCollectionsMigrationInput(manifestID: "recent-capture", capturedAt: .distantPast,
                                                          recent: recent,
                                                          aliases: [alias(ref(.videoLibrary, "alias"), ref(.pixabay, "0"))])
            let manifest = try LibraryCollectionsMigration.prepareManifest(for: input)
            print(String(decoding: try encoder.encode(LibraryCollectionsMigration.build(input, manifest: manifest)),
                         as: UTF8.self))
        case "failures":
            let a = ref(.videoLibrary, "a")
            let b = ref(.steamWorkshop, "b")
            let c = ref(.pixabay, "c")
            func mapping(_ aliases: [WallpaperReferenceAlias]) throws {
                let input = LibraryCollectionsMigrationInput(manifestID: "bad", capturedAt: .distantPast,
                                                              aliases: aliases)
                let manifest = try LibraryCollectionsMigration.prepareManifest(for: input)
                _ = try LibraryCollectionsMigration.build(input, manifest: manifest)
            }
            let original = mixedInput()
            let goodManifest = try LibraryCollectionsMigration.prepareManifest(for: original)
            var checks: [String: String] = [:]
            checks["cycle"] = errorName { try mapping([alias(a, b), alias(b, a)]) }
            checks["selfAlias"] = errorName { try mapping([alias(a, a)]) }
            checks["conflict"] = errorName { try mapping([alias(a, b), alias(a, c)]) }
            checks["emptyReference"] = errorName {
                let input = LibraryCollectionsMigrationInput(manifestID: "bad-ref", capturedAt: .distantPast,
                                                              recent: [item(.steamWorkshop, "")])
                let manifest = try LibraryCollectionsMigration.prepareManifest(for: input)
                _ = try LibraryCollectionsMigration.build(input, manifest: manifest)
            }
            checks["emptyName"] = errorName {
                let input = LibraryCollectionsMigrationInput(manifestID: "bad-tag", capturedAt: .distantPast,
                                                              videoTags: [" \n "])
                _ = try LibraryCollectionsMigration.prepareManifest(for: input)
            }
            checks["wrongSnapshot"] = errorName {
                let other = LibraryCollectionsMigrationInput(manifestID: "different", capturedAt: original.capturedAt)
                _ = try LibraryCollectionsMigration.build(other, manifest: goodManifest)
            }
            checks["changedTags"] = errorName {
                let changed = LibraryCollectionsMigrationInput(manifestID: original.manifestID,
                                                                capturedAt: original.capturedAt, videoTags: ["Replacement"])
                _ = try LibraryCollectionsMigration.prepareManifest(for: changed, reusing: goodManifest)
            }
            checks["duplicateUUID"] = errorName {
                let repeated = goodManifest.tagMappings.map {
                    LibraryCollectionsMigrationTagMapping(normalizedName: $0.normalizedName,
                                                           playlistID: goodManifest.tagMappings[0].playlistID,
                                                           displayName: $0.displayName, origins: $0.origins)
                }
                let bad = LibraryCollectionsMigrationManifest(schemaVersion: 1,
                                                               sourceManifestID: goodManifest.sourceManifestID,
                                                               capturedAt: goodManifest.capturedAt, tagMappings: repeated)
                _ = try LibraryCollectionsMigration.build(original, manifest: bad)
            }
            checks["unknownSchema"] = errorName {
                let bad = LibraryCollectionsMigrationManifest(schemaVersion: 99,
                                                               sourceManifestID: goodManifest.sourceManifestID,
                                                               capturedAt: goodManifest.capturedAt,
                                                               tagMappings: goodManifest.tagMappings)
                _ = try LibraryCollectionsMigration.build(original, manifest: bad)
            }
            print(String(decoding: try encoder.encode(checks), as: UTF8.self))
        default:
            fatalError("Unknown scenario")
        }
    }
}
