import Foundation

@main
struct LegacyLibrarySnapshotChecks {
    static func main() throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let mode = CommandLine.arguments[2]
        let backup = root.appendingPathComponent("backup")
        let index = root.appendingPathComponent(["bad-permission", "fallback-unreadable"].contains(mode) ? "locked/index.sqlite3" : "index.sqlite3")
        let images = root.appendingPathComponent("sil.json")
        let one = VideoWallpaper(id: "one", title: "One", path: "/offline/one.mp4", isFavorite: true,
                                 tags: ["A", "Keep"])
        let two = VideoWallpaper(id: "two", title: "Two", path: "/offline/two.mp4")
        var changes = WallpaperIndexStartupChanges()
        let edited = VideoWallpaper(id: "provisional", title: "Changed", path: one.path,
                                    isFavorite: false, tags: ["A", "Keep", "Added"])
        changes.record(path: one.path, old: one, new: edited, fields: [.favorite])
        changes.steps.append(.renameTag("A", "Renamed"))
        changes.record(path: two.path, old: two, new: nil)
        let encoder = JSONEncoder()
        var checks: [String: Bool] = [:]
        let recent = [VideoWallpaper(id: "orphan", title: "Offline recent", path: "/offline/recent.mp4")]
        var frozen = LegacyLibraryFrozenDefaults(startupChanges: try encoder.encode(changes),
                                                videoTags: try encoder.encode(["A", "Empty"]),
                                                staticImageTags: ["Image empty"],
                                                recentWallpapers: try encoder.encode(recent))
        if ["fallback-empty", "fallback-bad-db-tags", "fallback-bad-db", "fallback-unreadable"].contains(mode) {
            frozen = LegacyLibraryFrozenDefaults(wallpaperFallback: try encoder.encode([VideoWallpaper]()),
                                                  startupChanges: try encoder.encode(changes))
        } else if mode == "fallback-nonempty" {
            let duplicate = VideoWallpaper(id: "duplicate", title: "Duplicate", path: "/offline/nested/../two.mp4")
            frozen = LegacyLibraryFrozenDefaults(wallpaperFallback: try encoder.encode([two, duplicate]))
        } else if mode == "view-preferences" {
            let dated = [("late", 30.0), ("first-tie", 10.0), ("second-tie", 10.0), ("middle", 20.0)].map {
                VideoWallpaper(id: $0.0, title: $0.0, path: "/offline/\($0.0).mp4", lastUsed: Date(timeIntervalSince1970: $0.1))
            }
            let auxiliary = try PropertyListSerialization.data(fromPropertyList: ["WallpaperSettings": Data([1, 2, 3])], format: .binary, options: 0)
            frozen = .init(wallpaperFallback: try encoder.encode(dated), auxiliaryPreferences: auxiliary)
        } else if mode == "missing-index" {
            changes.seeds = [one, two]
            frozen = LegacyLibraryFrozenDefaults(startupChanges: try encoder.encode(changes))
        } else if mode == "initialized-empty" {
            frozen = LegacyLibraryFrozenDefaults(startupChanges: try encoder.encode(WallpaperIndexStartupChanges(seeds: [one])))
        } else if mode == "fresh" {
            frozen = LegacyLibraryFrozenDefaults()
        } else if mode == "bad-journal" || mode == "fallback-bad-journal" {
            changes.version = 99
            frozen = LegacyLibraryFrozenDefaults(
                wallpaperFallback: mode == "fallback-bad-journal" ? try encoder.encode([VideoWallpaper]()) : nil,
                startupChanges: try encoder.encode(changes))
        } else if mode == "bad-fallback" {
            frozen = LegacyLibraryFrozenDefaults(wallpaperFallback: Data("bad".utf8))
        } else if mode == "bad-tags" {
            frozen = LegacyLibraryFrozenDefaults(videoTags: Data("bad".utf8))
        } else if mode == "frozen-auxiliary" {
            let name = "MWX.LegacyCapture." + UUID().uuidString
            let defaults = UserDefaults(suiteName: name)!
            defer { defaults.removePersistentDomain(forName: name) }
            defaults.set(try encoder.encode(changes), forKey: "WallpaperIndexStartupChangesV1")
            defaults.set(Data("invalid json intentionally".utf8), forKey: "WallpaperSettings")
            defaults.set(["tag:Alpha": ["mode": "name", "ascending": false]], forKey: "PerSelectionSortStates")
            defaults.set("not a decodable SIL sort state", forKey: "SILSortState")
            defaults.set(1.25, forKey: "gridZoomOffset")
            defaults.set(-2, forKey: "SILGridZoomOffset")
            defaults.set(Data([0, 1, 255]), forKey: "CurrentWallpaper")
            defaults.set(false, forKey: "PlaybackState")
            defaults.set("scene", forKey: "ActiveWallpaperRuntime")
            defaults.set("video:opaque", forKey: "LastWorkshopPlaybackRecordID")
            defaults.set("size", forKey: "OLDownloadsSortMode")
            defaults.set(false, forKey: "OLDownloadsSortAscending")
            defaults.set(-1, forKey: "onlineLibrary.gridZoomOffset")
            defaults.set("credential must not be copied", forKey: "SteamToken")
            frozen = try LegacyLibraryFrozenDefaults(defaults: defaults)
            let auxiliary = try PropertyListSerialization.propertyList(from: frozen.auxiliaryPreferences!, options: [], format: nil) as! [String: Any]
            checks["auxiliary exact bytes and types retained"] = auxiliary["WallpaperSettings"] as? Data == Data("invalid json intentionally".utf8) && auxiliary["CurrentWallpaper"] as? Data == Data([0, 1, 255]) && auxiliary["gridZoomOffset"] as? Double == 1.25 && auxiliary["PlaybackState"] as? Bool == false
            checks["undecodable auxiliary values remain opaque"] = auxiliary["SILSortState"] as? String == "not a decodable SIL sort state"
            checks["only explicit noncredential auxiliary whitelist"] = auxiliary.count == 12 && auxiliary["SteamToken"] == nil
            checks["online download preferences retain exact legacy keys"] = auxiliary["OLDownloadsSortMode"] as? String == "size"
                && auxiliary["OLDownloadsSortAscending"] as? Bool == false && auxiliary["onlineLibrary.gridZoomOffset"] as? Int == -1
        } else if mode == "wrong-defaults-type" {
            let name = "MWX.LegacyCapture." + UUID().uuidString
            let defaults = UserDefaults(suiteName: name)!
            defer { defaults.removePersistentDomain(forName: name) }
            defaults.set("wrong", forKey: "Wallpapers")
            do { _ = try LegacyLibraryFrozenDefaults(defaults: defaults); checks["wrong type rejected"] = false }
            catch { checks["wrong type rejected"] = true }
            print(String(data: try encoder.encode(checks), encoding: .utf8)!)
            return
        }
        var rawValues = try frozen.auxiliaryPreferences.map {
            try PropertyListSerialization.propertyList(from: $0, options: [], format: nil) as! [String: Any]
        } ?? [:]
        rawValues["Wallpapers"] = frozen.wallpaperFallback
        rawValues["WallpaperIndexStartupChangesV1"] = frozen.startupChanges
        rawValues["WallpaperTags"] = frozen.videoTags
        rawValues["SILTags"] = frozen.staticImageTags
        rawValues["RecentWallpapers"] = frozen.recentWallpapers
        let rawDefaults = try PropertyListSerialization.data(fromPropertyList: rawValues, format: .binary, options: 0)
        let inputURL = root.appendingPathComponent("source-input.json")
        do {
            let captured = try LegacyLibrarySnapshot.capture(rawDefaults: rawDefaults, indexURL: index,
                staticImageURL: images, backupDirectoryURL: backup, inputSnapshotURL: inputURL,
                capturedAt: Date(timeIntervalSince1970: 100))
            checks["success expected"] = !mode.hasPrefix("bad-") && mode != "fallback-unreadable"
            checks["manifest published"] = FileManager.default.fileExists(atPath: backup.appendingPathComponent("manifest.json").path)
            checks["frozen defaults retained"] = FileManager.default.fileExists(atPath: backup.appendingPathComponent("defaults.json").path)
            checks["successful capture publishes its exact durable input"] = try JSONDecoder().decode(LibraryCollectionsMigrationInput.self,
                from: Data(contentsOf: inputURL)) == captured.migrationInput
            if mode == "view-preferences" {
                let auxiliaryValues = try PropertyListSerialization.propertyList(from: captured.viewPreferences.auxiliaryPreferences!,
                    options: [], format: nil) as? [String: Data]
                checks["video legacy display rank uses frozen lastUsed with stable ties"] = captured.viewPreferences.videoTimeOrder.map(\.sourceID)
                    == ["first-tie", "second-tie", "middle", "late"]
                checks["image missing and malformed legacy clocks stay unknown in source order"] = captured.viewPreferences.imageTimeOrder.map(\.sourceID)
                    == ["image-early", "image-late", "image-unknown", "image-malformed"]
                checks["frozen ranks leave actual source and member order untouched"] = captured.videos.map(\.reference.sourceID)
                    == ["late", "first-tie", "second-tie", "middle"]
                checks["migration input carries opaque preferences without live defaults"] = captured.migrationInput.viewPreferences == captured.viewPreferences
                    && captured.viewPreferences.auxiliaryPreferences == frozen.auxiliaryPreferences
                    && auxiliaryValues?["WallpaperSettings"] == Data([1, 2, 3])
            } else if mode == "fresh" || mode == "initialized-empty" {
                checks["empty store cannot resurrect defaults or seeds"] = captured.videos.isEmpty
            } else if ["fallback-empty", "fallback-bad-journal", "fallback-bad-db-tags", "fallback-bad-db"].contains(mode) {
                checks["empty complete fallback supersedes journal and sqlite"] = captured.videos.isEmpty
                checks["fallback presence recorded"] = captured.manifest.usedCompleteVideoFallback
            } else if mode == "fallback-nonempty" {
                checks["complete fallback supersedes sqlite"] = captured.videos.map(\.reference.sourceID) == ["two"]
            } else {
                checks["explicit deletion not resurrected"] = captured.videos.map(\.reference.sourceID) == ["one"]
                checks["explicit false favorite preserved"] = captured.videos.first?.isFavorite == false
                checks["sqlite identity retained"] = captured.videos.first?.reference.sourceID == "one"
                checks["ordered global tag operation preserved"] = captured.videos.first?.tags == ["Keep", "Added", "Renamed"]
                checks["title edit preserved"] = captured.videos.first?.locator.titleHint == "Changed"
            }
            if mode == "fallback-bad-db" {
                checks["unreadable superseded index explicitly non-authoritative"] = captured.manifest.sources[1].interpretation == "superseded-raw-unreadable" && captured.manifest.sources[1].recordCount == nil
                checks["raw recovery has explicit path"] = captured.manifest.sources[1].backupRelativePath == "wallpaper_index.sqlite3.raw"
            } else if mode != "missing-index" && mode != "fresh" {
                checks["wal backup present"] = FileManager.default.fileExists(atPath: backup.appendingPathComponent("wallpaper_index.sqlite3").path)
                if captured.manifest.usedCompleteVideoFallback {
                    checks["superseded index not interpreted"] = captured.manifest.sources[1].interpretation == "superseded-consistent-backup" && captured.manifest.sources[1].recordCount == nil
                } else { checks["original db initialized"] = captured.manifest.videoIndexInitialized }
            } else {
                checks["absent index explicit"] = !captured.manifest.videoIndexInitialized && captured.manifest.sources[1].present == false
            }
            if mode == "view-preferences" {
                checks["all offline image relations survive optional clock interpretation"] = captured.staticImages.count == 4
            } else if mode == "fresh" {
                checks["absent image store stays absent"] = captured.staticImages.isEmpty
            } else {
                checks["offline image survives"] = captured.staticImages.map(\.reference.sourceID) == ["image-missing"]
                checks["image tags intact"] = captured.staticImages.first?.tags == ["Image empty", "Unlisted"]
            }
            if mode == "journal" {
                checks["explicit empty video tag retained"] = captured.videoTags == ["A", "Empty"]
                checks["explicit empty image tag retained"] = captured.staticImageTags == ["Image empty"]
                checks["offline recent survives without normalization"] = captured.recent.map(\.reference.sourceID) == ["orphan"]
                checks["input adapter retains records"] = captured.migrationInput.videos == captured.videos
                let second = try LegacyLibrarySnapshot.capture(rawDefaults: rawDefaults, indexURL: index, staticImageURL: images,
                    backupDirectoryURL: root.appendingPathComponent("backup-two"), inputSnapshotURL: root.appendingPathComponent("source-input-two.json"),
                    capturedAt: Date(timeIntervalSince1970: 200))
                checks["manifest identity independent of capture date"] = captured.manifestID == second.manifestID
                do {
                    _ = try LegacyLibrarySnapshot.capture(rawDefaults: rawDefaults, indexURL: index, staticImageURL: images,
                        backupDirectoryURL: backup, inputSnapshotURL: inputURL)
                    checks["cannot overwrite backup"] = false
                } catch LegacyLibraryCaptureError.backupAlreadyExists { checks["cannot overwrite backup"] = true }
            }
        } catch {
            checks["failure expected"] = mode.hasPrefix("bad-") || mode == "fallback-unreadable"
            checks["error never publishes complete marker"] = !FileManager.default.fileExists(atPath: backup.appendingPathComponent("manifest.json").path)
            checks["raw defaults retained on failure"] = FileManager.default.fileExists(atPath: backup.appendingPathComponent("defaults.json").path)
        }
        print(String(data: try encoder.encode(checks), encoding: .utf8)!)
    }
}
