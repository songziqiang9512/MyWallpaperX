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
        for mutation in ["replacePath", "delete", "reorder", "notVisible", "hidden", "selectionReplace", "mergeReplace", "mergeHide"] {
            let prefix = provider.rawValue + ":" + mutation + ":"
            let folder = root.appendingPathComponent(provider.rawValue + "-" + mutation)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let a = folder.appendingPathComponent("A.media"), b = folder.appendingPathComponent("B.media")
            let replacement = folder.appendingPathComponent("replacement.media")
            for url in [a, b, replacement] { try Data([1, 2, 3]).write(to: url) }
            let manager = WallpaperManager(), images = SILService(), steam = SteamWorkshopService(), pixabay = PixabayService()
            manager.didFinishInitialIndexLoad = true
            steam.hasCompletedInstalledLibraryLoad = true
            pixabay.downloadedContent = .init(revision: 1, entries: [], status: .init(phase: .ready(warnings: []), hasSuccessfulScan: true))
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
            let controller = WallpaperLibraryCatalogController(manager: manager, images: images, steam: steam, pixabay: pixabay)
            func items() -> [WallpaperContentItem] { provider == .videoLibrary ? controller.catalog.videos : controller.catalog.images }
            let ready = await wait { controller.catalog.loadedProviders.count == 4 && items().count == 2 }
            precondition(ready, "initial catalog must settle before controlling its existing file worker")
            let aRef = WallpaperReference(provider: provider, sourceID: "A")
            let bRef = WallpaperReference(provider: provider, sourceID: "B")
            let token = UUID()
            let sourceReplacement = mutation == "selectionReplace" || mutation == "mergeReplace"
            let phase: String? = mutation == "selectionReplace" ? "selection-" + provider.rawValue : mutation == "mergeHide" || mutation == "mergeReplace" ? "merge" : nil
            CatalogFileProbe.shared.resetScans()
            let held = phase.map { CatalogFileProbe.shared.holdScan($0) } ?? CatalogFileProbe.shared.holdNext()
            defer { held.signal(); CatalogFileProbe.shared.stop() }
            if mutation == "mergeHide" || mutation == "mergeReplace" { try FileManager.default.removeItem(at: a) }
            var repairs = 0
            let repairSubscription = controller.visibleLocalFactsRefreshed.sink { repairs += 1 }
            defer { repairSubscription.cancel() }
            controller.setVisibleReferences([aRef], sourceToken: token)
            let entered = await wait {
                phase.map { CatalogFileProbe.shared.scans.visits[$0, default: 0] == 1 } ?? (CatalogFileProbe.shared.snapshot.active == 1)
            }
            var mainResponded = false
            DispatchQueue.main.async { mainResponded = true }
            _ = await wait { mainResponded }
            for _ in 0..<40 { controller.setVisibleReferences([aRef], sourceToken: token) }
            let blocked = CatalogFileProbe.shared.snapshot
            let scans = CatalogFileProbe.shared.scans
            let singleFlight = phase.map { scans.visits[$0, default: 0] == 1 && !scans.onMain.contains($0) }
                ?? (blocked.active == 1 && blocked.maximum == 1 && blocked.total == 1 && blocked.offMain)
            checks[prefix + "actualWorkerIsOffMainSingleFlightDuringRepeatedViewportInput"] = entered && mainResponded && singleFlight
            // The captured old worker will now discover A missing. Its result
            // can commit only if source generation and consumer scope still match.
            if mutation != "mergeHide" && mutation != "mergeReplace" { try FileManager.default.removeItem(at: a) }
            var mutationPublished = true
            switch mutation {
            case "replacePath", "selectionReplace", "mergeReplace":
                // A negative-control run omits this source publication. The
                // unchanged old snapshot must not satisfy our replacement case.
                if mutation != "replacePath" || ProcessInfo.processInfo.environment["MWX_TEST_DROP_REPLACEMENT"] != "1" {
                    try replace(sourceReplacement ? [("B", b), ("A", replacement)] : [("A", replacement), ("B", b)])
                }
                mutationPublished = await wait { items().first { $0.reference == aRef }?.locator.path == replacement.path }
                if provider == .videoLibrary, mutationPublished { await controller.videoTask?.value }
            case "delete":
                try replace([("B", b)])
                mutationPublished = await wait { items().map(\.reference) == [bRef] }
            case "reorder":
                try replace([("B", b), ("A", a)])
                mutationPublished = await wait { items().map(\.reference) == [bRef, aRef] }
            case "notVisible": controller.setVisibleReferences([bRef], sourceToken: token)
            case "mergeHide":
                controller.setVisibleReferences([], sourceToken: token)
                controller.setVisibleReferences([aRef], sourceToken: token)
                controller.setVisibleReferences([], sourceToken: token)
                checks[prefix + "cancelledParentKeepsItsHeldPureWorker"] = controller.visibleAvailabilityTask?.isCancelled == true
                    && CatalogFileProbe.shared.scans.visits["merge", default: 0] == 1
            default: controller.setVisibleReferences([], sourceToken: token)
            }
            let acceptedBeforeCompletion = items()
            held.signal()
            if phase != nil {
                if sourceReplacement {
                    let completed = await wait { CatalogFileProbe.shared.scans.visits["refresh-finished", default: 0] > 0 }
                    mutationPublished = mutationPublished && completed
                }
                controller.setVisibleReferences([], sourceToken: token)
                _ = await wait { controller.visibleAvailabilityTask == nil }
            } else {
                _ = await wait { CatalogFileProbe.shared.snapshot.active == 0 }
                try await Task.sleep(for: .milliseconds(80))
            }
            if mutation == "mergeHide" { checks[prefix + "retiredMergeDoesNotSendVideoRepair"] = repairs == 0 }
            let expectedAPath = mutation == "replacePath" || sourceReplacement ? replacement.path : a.path
            let currentAPathIsCorrect = mutation == "delete" ? items().allSatisfy { $0.reference != aRef }
                : items().first { $0.reference == aRef }?.locator.path == expectedAPath
            checks[prefix + "lateRealFileResultCannotOverwriteAcceptedIdentityOrderOrFacts"] = mutationPublished && currentAPathIsCorrect
                && items() == acceptedBeforeCompletion
                && items().allSatisfy { $0.publishedAvailability == .available && $0.capabilities.contains(.play) }
            let expected = mutation == "delete" ? [bRef] : mutation == "reorder" || sourceReplacement ? [bRef, aRef] : [aRef, bRef]
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

    @MainActor static func atomicVideoReplacement(root: URL) async throws -> [String: Bool] {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let source = root.appendingPathComponent("video.mp4")
        let replacement = root.appendingPathComponent("replacement.mp4")
        let date = Date(timeIntervalSince1970: 1_000_000)
        for url in [source, replacement] {
            try Data([8]).write(to: url)
            try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: url.path)
        }
        let oldFile = try FileManager.default.attributesOfItem(atPath: source.path)
        let newFile = try FileManager.default.attributesOfItem(atPath: replacement.path)
        precondition(oldFile[.size] as? Int == newFile[.size] as? Int
                     && oldFile[.modificationDate] as? Date == newFile[.modificationDate] as? Date
                     && oldFile[.systemFileNumber] as? UInt64 != newFile[.systemFileNumber] as? UInt64)

        let manager = WallpaperManager()
        manager.didFinishInitialIndexLoad = true
        manager.wallpapers = [.init(id: "movie", title: "Original", path: source.path)]
        let controller = WallpaperLibraryCatalogController(manager: manager, images: SILService(),
                                                           steam: SteamWorkshopService(), pixabay: PixabayService())
        await controller.videoTask?.value
        let before = controller.catalog.videos[0]
        precondition(rename(replacement.path, source.path) == 0)
        let token = UUID()
        controller.setVisibleReferences([before.providerReference], sourceToken: token)
        let observed = await wait { controller.catalog.videos[0].metadata.resourceRevision != before.metadata.resourceRevision }
        let after = controller.catalog.videos[0]
        controller.setVisibleReferences([], sourceToken: token)
        _ = await wait { controller.visibleAvailabilityTask == nil }

        let pending = CatalogFileProbe.shared.holdNext()
        defer { pending.signal(); CatalogFileProbe.shared.stop() }
        try FileManager.default.moveItem(at: source, to: replacement)
        manager.wallpapers[0].lastUsed = date
        let published = await wait {
            controller.catalog.videos[0].metadata.lastUsedAt == date && CatalogFileProbe.shared.snapshot.active == 1
        }
        let initial = controller.catalog.videos[0]
        pending.signal()
        await controller.videoTask?.value
        let settled = controller.catalog.videos[0]

        return [
            "visible-atomic-replacement-updates-video-revision-with-same-size-and-mtime": observed
                && before.providerReference == after.providerReference && before.metadata.resourceRevision != nil
                && after.metadata.resourceRevision != nil && before.publishedAvailability == .available
                && after.publishedAvailability == .available,
            "same-path-model-publication-retains-checked-video-revision": published
                && initial.metadata.resourceRevision != nil && after.metadata.resourceRevision == initial.metadata.resourceRevision
                && settled.metadata.resourceRevision == initial.metadata.resourceRevision && settled.publishedAvailability == .available,
        ]
    }

    @MainActor static func main() async throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[1])
        var checks = try await audit(.videoLibrary, root: root)
        checks.merge(try await audit(.staticImageLibrary, root: root)) { _, next in next }
        checks.merge(try await atomicVideoReplacement(root: root.appendingPathComponent("atomic"))) { _, next in next }
        print(String(decoding: try JSONEncoder().encode(checks), as: UTF8.self))
    }
}
