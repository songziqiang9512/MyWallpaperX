// Controlled service leaves and real model declarations precede this file via
// library_catalog_fixture. No private grid probe, source index or timer is copied.
@main enum LibraryVisibleSourceLifecycleHarness {
    @MainActor static func wait(_ predicate: () -> Bool) async -> Bool {
        for _ in 0..<300 {
            if predicate() { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return predicate()
    }

    @MainActor static func audit(_ provider: WallpaperProvider, root: URL) async throws -> [String: Bool] {
        var checks: [String: Bool] = [:]
        for mutation in ["replacePath", "delete", "reorder", "notVisible", "hidden"] {
            let prefix = provider.rawValue + ":" + mutation + ":"
            let folder = root.appendingPathComponent(provider.rawValue + "-" + mutation)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let a = folder.appendingPathComponent("A.media"), b = folder.appendingPathComponent("B.media")
            let replacement = folder.appendingPathComponent("replacement.media")
            for url in [a, b, replacement] { try Data([1, 2, 3]).write(to: url) }
            let manager = WallpaperManager(), images = SILService(), steam = SteamWorkshopService(), online = OnlineLibraryService()
            manager.didFinishInitialIndexLoad = true
            steam.hasCompletedInstalledLibraryLoad = true
            online.downloadedContent = .init(revision: 1, entries: [], status: .init(phase: .ready(warnings: []), hasSuccessfulScan: true))
            func replace(_ records: [(String, URL)]) throws {
                if provider == .videoLibrary {
                    manager.wallpapers = records.map { .init(id: $0.0, title: $0.0, path: $0.1.path) }
                } else {
                    images.wallpapers = try records.map {
                        try JSONDecoder().decode(SILWallpaper.self, from: JSONSerialization.data(withJSONObject: [
                            "id": $0.0, "title": $0.0, "path": $0.1.path, "tags": [], "lastUsed": 0, "addedAt": 0]))
                    }
                }
            }
            try replace([("A", a), ("B", b)])
            let controller = WallpaperLibraryCatalogController(manager: manager, images: images, steam: steam, online: online)
            func items() -> [WallpaperContentItem] { provider == .videoLibrary ? controller.catalog.videos : controller.catalog.images }
            let ready = await wait { controller.catalog.loadedProviders.count == 4 && items().count == 2 }
            precondition(ready, "initial catalog must settle before controlling its existing file worker")
            let aRef = WallpaperReference(provider: provider, sourceID: "A")
            let bRef = WallpaperReference(provider: provider, sourceID: "B")
            let token = UUID(), held = CatalogFileProbe.shared.holdNext()
            controller.setVisibleReferences([aRef], sourceToken: token)
            let entered = await wait { CatalogFileProbe.shared.snapshot.active == 1 }
            var mainResponded = false
            DispatchQueue.main.async { mainResponded = true }
            _ = await wait { mainResponded }
            for _ in 0..<40 { controller.setVisibleReferences([aRef], sourceToken: token) }
            let blocked = CatalogFileProbe.shared.snapshot
            checks[prefix + "actualWorkerIsOffMainSingleFlightDuringRepeatedViewportInput"] = entered && mainResponded
                && blocked.active == 1 && blocked.maximum == 1 && blocked.total == 1 && blocked.offMain
            // The captured old worker will now discover A missing. Its result
            // can commit only if source generation and consumer scope still match.
            try FileManager.default.removeItem(at: a)
            var mutationPublished = true
            switch mutation {
            case "replacePath":
                // A negative-control run omits this source publication. The
                // unchanged old snapshot must not satisfy our replacement case.
                if ProcessInfo.processInfo.environment["MWX_TEST_DROP_REPLACEMENT"] != "1" {
                    try replace([("A", replacement), ("B", b)])
                }
                mutationPublished = await wait { items().first?.locator.path == replacement.path }
            case "delete":
                try replace([("B", b)])
                mutationPublished = await wait { items().map(\.reference) == [bRef] }
            case "reorder":
                try replace([("B", b), ("A", a)])
                mutationPublished = await wait { items().map(\.reference) == [bRef, aRef] }
            case "notVisible": controller.setVisibleReferences([bRef], sourceToken: token)
            default: controller.setVisibleReferences([], sourceToken: token)
            }
            let acceptedBeforeCompletion = items()
            held.signal()
            _ = await wait { CatalogFileProbe.shared.snapshot.active == 0 }
            try await Task.sleep(for: .milliseconds(80))
            let expectedAPath = mutation == "replacePath" ? replacement.path : a.path
            let currentAPathIsCorrect = mutation == "delete" ? items().allSatisfy { $0.reference != aRef }
                : items().first { $0.reference == aRef }?.locator.path == expectedAPath
            checks[prefix + "lateRealFileResultCannotOverwriteAcceptedIdentityOrderOrFacts"] = mutationPublished && currentAPathIsCorrect
                && items() == acceptedBeforeCompletion
                && items().allSatisfy { $0.publishedAvailability == .available && $0.capabilities.contains(.play) }
            let expected = mutation == "delete" ? [bRef] : mutation == "reorder" ? [bRef, aRef] : [aRef, bRef]
            checks[prefix + "oldIndexOccupantNeverReceivesAnotherResourcesResult"] = items().map(\.reference) == expected
                && items().first { $0.reference == bRef }?.locator.path == b.path
            controller.setVisibleReferences([], sourceToken: token)
            _ = await wait { controller.visibleAvailabilityTask == nil && CatalogFileProbe.shared.snapshot.active == 0 }
            let settled = CatalogFileProbe.shared.snapshot.total
            try await Task.sleep(for: .milliseconds(40))
            checks[prefix + "releasedScopeDoesNotRestartLateWorkOrDeleteSourceRows"] = controller.visibleAvailabilityTask == nil
                && CatalogFileProbe.shared.snapshot.total == settled
                && (provider == .videoLibrary ? manager.wallpapers.count : images.wallpapers.count) == expected.count
            CatalogFileProbe.shared.stop()
        }
        return checks
    }

    @MainActor static func main() async throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[1])
        var checks = try await audit(.videoLibrary, root: root)
        checks.merge(try await audit(.staticImageLibrary, root: root)) { _, next in next }
        print(String(decoding: try JSONEncoder().encode(checks), as: UTF8.self))
    }
}
