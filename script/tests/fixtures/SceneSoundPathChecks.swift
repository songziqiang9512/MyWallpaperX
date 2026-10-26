import AVFoundation
import Foundation

extension SoundResources {
    static func pathSelection(_ base: URL, virtualPackage: Bool) throws -> [String: Bool] {
        let package = base.appendingPathComponent("package"), loose = base.appendingPathComponent("loose")
        let stock = base.appendingPathComponent("stock"), cache = base.appendingPathComponent("cache")
        let original = wav(0.3), alias = wav(0.42), mixed = wav(0.22), stockBytes = wav(0.7)
        try write(wav(0.5), loose.appendingPathComponent("audio/renamed.wav"))
        try write(stockBytes, stock.appendingPathComponent("audio/stock-only.wav"))
        try write(Data([1]), stock.appendingPathComponent("audio/inner/proof.bin"))
        try write(wav(0.8), stock.appendingPathComponent("assets/audio/full-first.wav"))
        try write(wav(0.9), stock.appendingPathComponent("audio/full-first.wav"))
        try write(wav(0.6), stock.appendingPathComponent("audio/late.wav"))
        let root: SceneResourceView.Root
        if virtualPackage {
            let fixture = URL(fileURLWithPath: CommandLine.arguments[3]).appendingPathComponent("path-spellings.pkg")
            let url = base.appendingPathComponent("scene.pkg")
            try write(Data(contentsOf: fixture), url)
            root = try .package(openedPackage: ScenePkgReader().openPackage(packageURL: url))
        } else {
            try write(original, package.appendingPathComponent("audio/renamed.wav"))
            try write(alias, package.appendingPathComponent("audio/raw\\leaf.wav"))
            try write(mixed, package.appendingPathComponent("Audio/Mixed.WAV"))
            try write(Data([1]), package.appendingPathComponent("audio/inner/proof.bin"))
            root = .init(source: .package, url: package)
        }
        let view = SceneResourceView(projectRoot: .init(source: .loose, url: loose), packageRoot: root,
            stockRoot: .init(source: .stock, url: stock))
        var facts: [String: Bool] = [:]
        let aliases = ["audio/raw/leaf.wav", "./audio/raw/leaf.wav",
            "audio//raw///leaf.wav", "./audio/./raw//leaf.wav"]
        let canonical = view.resolvedResource(forReference: aliases[0])!
        let program = try prepare(aliases, view: view, cache: cache, mode: "random")
        let resources = program.bindings.first?.resources ?? []
        var sameAlias = resources.count == aliases.count && program.diagnostics.isEmpty
        for (index, path) in aliases.enumerated() {
            let selected = try view.literalEntry(relativePath: path, selection: .indexedReference)
            sameAlias = try sameAlias && selected?.owner === canonical.owner
                && selected?.relativePath == canonical.relativePath
                && resources[index].file === resources[0].file
                && resources[index].file.map { try Data(contentsOf: $0.url) } == alias
        }
        facts["dotAndRepeatedSeparatorsKeepIndexedRawAliasAndOneFile"] = sameAlias && files(cache).count == 1
        let identity = try canonical.currentIdentity()
        var spellings = true
        for path in ["./audio/renamed.wav", "audio//renamed.wav", "audio/./renamed.wav",
                     "audio/inner/../renamed.wav"] {
            let selected = try view.literalEntry(relativePath: path, selection: .indexedReference)
            let plan = try prepare([path], view: view, cache: cache)
            spellings = try spellings && selected?.owner === root && plan.bindings.count == 1
                && plan.bindings.first?.resources.first?.file.map { try Data(contentsOf: $0.url) } == original
        }
        facts["equivalentInRootSpellingsUseActualPackageBytes"] = spellings
        facts["indexedAliasIdentityUnchanged"] = try identity == canonical.currentIdentity()
        var caseSelection = true
        for path in ["Audio/Mixed.WAV", "audio/mixed.wav", "./AUDIO/MIXED.WAV", "Audio//Mixed.WAV"] {
            let selected = try view.literalEntry(relativePath: path, selection: .indexedReference)
            caseSelection = try caseSelection && selected?.owner === root && selected?.readBytes() == mixed
        }
        facts["caseProjectionRemainsTheOriginalIndexedSelection"] = caseSelection
        var stockSelection = true
        for path in ["assets/audio/stock-only.wav", "./assets/audio/stock-only.wav",
                     "assets//audio//stock-only.wav", "./assets//audio/./stock-only.wav",
                     "assets/audio/inner/../stock-only.wav"] {
            let selected = try view.literalEntry(relativePath: path, selection: .indexedReference)
            let plan = try prepare([path], view: view, cache: cache)
            stockSelection = try stockSelection && selected?.source == .stock && plan.bindings.count == 1
                && plan.bindings.first?.resources.first?.file.map { try Data(contentsOf: $0.url) } == stockBytes
        }
        facts["stockAssetsPrefixAndNewSpellingsKeepStockOwner"] = stockSelection
        let full = try view.literalEntry(relativePath: "./assets//audio/full-first.wav", selection: .indexedReference)
        facts["stockFullRelativeNameStillPrecedesAssetsAlias"] = try full?.readBytes() == wav(0.8)
        // This directory did not exist in the captured index. A canonical miss
        // must still reach stock rather than become a new unavailable loose slot.
        try fm.createDirectory(at: loose.appendingPathComponent("audio/late.wav"), withIntermediateDirectories: true)
        let late = try view.literalEntry(relativePath: "audio/late.wav", selection: .indexedReference)
        facts["canonicalIndexMissDoesNotProbeUnindexedDirectory"] = try late?.source == .stock
            && late?.readBytes() == wav(0.6)
        facts["defaultLiteralPolicyStillExcludesStock"] = try view.literalEntry(relativePath: "audio/stock-only.wav") == nil
        facts["defaultLiteralMissingRelativePathDoesNotBecomeEscape"] = try view.literalEntry(relativePath: "./assets/absent.wav") == nil
        let missing = try prepare(["audio/absent/../renamed.wav", "audio/renamed.wav"], view: view, cache: cache)
        facts["missingParentComponentDoesNotFoldToAnotherFile"] = try missing.bindings.count == 1
            && missing.diagnostics.count == 1 && missing.diagnostics[0].reason == .resourceUnavailable
            && missing.diagnostics[0].detail == "audio/absent/../renamed.wav"
            && missing.bindings[0].resources[0].file.map { try Data(contentsOf: $0.url) } == original
        if virtualPackage {
            let file = try FileHandle(forWritingTo: base.appendingPathComponent("scene.pkg"))
            try file.seekToEnd(); try file.write(contentsOf: Data([0])); try file.close()
            var changed = false
            do { _ = try prepare(["audio/inner/../renamed.wav"], view: view, cache: cache) }
            catch SceneResourceView.ReadError.sourceChanged { changed = true }
            facts["changedPackageDuringLiteralLookupRemainsHardError"] = changed
            // The same stale Root must throw if actually queried. Unsupported
            // sources exit before this lookup, rather than promoting that
            // irrelevant source revision into a failure of the Scene.
            var unsupported = [("audio/inner/../unused.gif", "gif")]
            if !AVURLAsset.isPlayableExtendedMIMEType("audio/ogg") {
                unsupported.append(("audio/inner/../unused.ogg", "ogg"))
            }
            for (path, ext) in unsupported {
                let rejected = try prepare([path], view: view, cache: cache)
                facts["unsupported-" + ext + "DoesNotQueryChangedRoot"] = rejected.bindings.isEmpty
                    && rejected.diagnostics.count == 1 && rejected.diagnostics[0].reason == .audioFormatUnsupported
                    && rejected.diagnostics[0].detail == ext
            }
        }
        withExtendedLifetime(program) {}
        return facts
    }

    static func pathBoundaryChecks(_ base: URL) throws -> [String: Bool] {
        let (_, cache) = try sourceSetup(base)
        let package = base.appendingPathComponent("package"), outside = base.appendingPathComponent("outside")
        try write(wav(0.9), outside.appendingPathComponent("peer.wav"))
        try write(Data([1]), outside.appendingPathComponent("child/proof.bin"))
        try write(wav(0.4), package.appendingPathComponent("inner/peer.wav"))
        try write(Data([1]), package.appendingPathComponent("inner/child/proof.bin"))
        try write(wav(0.8), package.appendingPathComponent("peer.wav"))
        let pivot = package.appendingPathComponent("pivot")
        try fm.createSymbolicLink(at: pivot, withDestinationURL: package.appendingPathComponent("inner/child"))
        let captured = view(base)
        let inRoot = try prepare(["pivot/../peer.wav"], view: captured, cache: cache)
        var facts = ["inRootSymlinkParentUsesActualFilesystemPeer":
            (try inRoot.bindings[0].resources[0].file.map { try Data(contentsOf: $0.url) }) == wav(0.4)]
        try fm.removeItem(at: pivot)
        try fm.createSymbolicLink(at: pivot, withDestinationURL: outside.appendingPathComponent("child"))
        var local = true
        for path in ["../outside/peer.wav", "audio/../../outside/peer.wav", outside.appendingPathComponent("peer.wav").path,
                     "audio/nul\0leaf.wav", "pivot/../peer.wav"] {
            let plan = try SceneSoundPlaybackProgram.compile(document: .init(objects: [
                .init(id: 1, sound: sound([path, "audio/first.wav"])),
                .init(id: 2, sound: sound(["audio/first.wav"]))]),
                resourceView: captured, privateCacheDirectory: cache)
            local = try local && plan.bindings.count == 2 && plan.diagnostics.count == 1
                && plan.diagnostics[0].reason == .malformedSourceList && plan.diagnostics[0].detail == path
                && plan.bindings.allSatisfy { $0.resources.count == 1 && $0.resources[0].file != nil }
                && plan.bindings[0].resources[0].file.map { try Data(contentsOf: $0.url) } == wav(0.3)
        }
        facts["invalidQueriesRejectOnlyTheirSourceWithoutReadingOutside"] = local
        return facts
    }
}
