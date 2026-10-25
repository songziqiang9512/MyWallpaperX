import Foundation
import CryptoKit
import Darwin

@main enum PackageSourceInputProbe {
    static let overrides: [String: SceneUserPropertyValue] = ["enabled": .bool(true), "amount": .number(0.35)]
    static func canonical(_ url: URL) -> URL { url.resolvingSymlinksInPath().standardizedFileURL }
    static func encoded<T: Encodable>(_ value: T) throws -> Any {
        try JSONSerialization.jsonObject(with: JSONEncoder().encode(value), options: [.fragmentsAllowed])
    }
    static func facts(_ root: URL, sourceFile: URL?, check: (() throws -> Void)? = nil) throws -> SceneRuntimeSourceFacts {
#if D8_CURRENT
        let source = try sourceFile.map { try JSONDecoder().decode(ScenePlaybackSource.self, from: Data(contentsOf: $0)) }
        return try SceneRuntimeSourceFactsBuilder().build(rootURL: root, source: source,
            propertyOverrides: overrides, checkCancellation: check)
#else
        return try SceneRuntimeSourceFactsBuilder().build(rootURL: root,
            propertyOverrides: overrides, checkCancellation: check)
#endif
    }
    static func model(_ root: URL, sourceFile: URL?, check: (() throws -> Void)? = nil) throws -> SceneRuntimeModel {
#if D8_CURRENT
        let source = try sourceFile.map { try JSONDecoder().decode(ScenePlaybackSource.self, from: Data(contentsOf: $0)) }
        return try SceneRuntimeModelBuilder().build(rootURL: root, source: source,
            propertyOverrides: overrides, checkCancellation: check)
#else
        return try SceneRuntimeModelBuilder().build(rootURL: root,
            propertyOverrides: overrides, checkCancellation: check)
#endif
    }
    static func projection(_ facts: SceneRuntimeSourceFacts, _ model: SceneRuntimeModel) throws -> [String: Any] {
        guard let project = facts.project, let document = facts.sceneDocument, let catalog = facts.assetCatalog,
              let descriptor = facts.renderDescriptor else { throw ProbeError.missingFacts }
        return [
            "project": ["entry": project.entryPath, "title": project.title ?? "", "witness": project.sourceWitness ?? "",
                "audio": project.supportsAudioProcessing, "version": try encoded(project.declaredVersion)],
            "sceneAuthoredRoot": try encoded(document.authoredRoot),
            "sceneWitness": document.sourceWitness ?? "",
            "catalogModels": catalog.models.map { ["path": $0.relativePath, "material": $0.materialPath ?? "",
                "autosize": $0.autosize as Any? ?? NSNull(), "size": $0.declaredSizeWH ?? [],
                "crop": $0.cropOffsetXY ?? [], "solid": $0.isSolidLayer, "puppet": $0.puppetPath ?? ""] as [String: Any] },
            "catalogMaterialPaths": catalog.materials.map(\.relativePath),
            "catalogMaterialRawSHA": catalog.materials.map(\.rawSHA256),
            "authoredDescriptor": try encoded(descriptor),
            "runtimeDescriptor": try encoded(model.renderDescriptor),
        ]
    }
    static func projectionBytes(_ root: URL, sourceFile: URL?) throws -> Data {
        try JSONSerialization.data(withJSONObject: projection(facts(root, sourceFile: sourceFile),
            model(root, sourceFile: sourceFile)), options: [.sortedKeys])
    }
    enum ProbeError: Error { case missingFacts, missingEntry }
#if D8_CURRENT
    static func packageOpen(_ url: URL) -> Bool {
        let expected = canonical(url).path
        var current = stat()
        guard lstat(url.path, &current) == 0 else { return false }
        return (0..<512).contains { value in
            var opened = stat()
            guard fstat(Int32(value), &opened) == 0,
                  opened.st_dev == current.st_dev, opened.st_ino == current.st_ino else { return false }
            var path = [CChar](repeating: 0, count: Int(MAXPATHLEN))
            return fcntl(Int32(value), F_GETPATH, &path) == 0
                && canonical(URL(fileURLWithPath: String(cString: path))).path == expected
        }
    }
    static func route(_ root: URL, sourceFile: URL) throws -> [String: Bool] {
        let loaded = try facts(root, sourceFile: sourceFile)
        guard let entry = loaded.project?.entryPath,
              let scene = try loaded.resourceView.literalEntry(relativePath: entry) else { throw ProbeError.missingEntry }
        let packaged: Bool
        switch try scene.currentIdentity() { case .package: packaged = true; case .file: packaged = false }
        return ["hasPackageIdentity": packaged,
            "singleVirtualPackageRoot": loaded.resourceView.roots.filter { $0.source == .package }.count == 1
                && loaded.resourceView.roots.first?.directoryURL == nil,
            "hasNoAuthorExpansion": !FileManager.default.fileExists(atPath: root.appendingPathComponent(".scene-extracted").path)]
    }
    static func mutable(_ root: URL, sourceFile: URL) throws -> [String: Bool] {
        let baseline = try projectionBytes(root, sourceFile: sourceFile)
        var checks = try route(root, sourceFile: sourceFile)
        let extras = [".DS_Store", "capture.png", "notes.txt"]
        for name in extras { try Data("unrelated local bytes".utf8).write(to: root.appendingPathComponent(name)) }
        checks["unrelatedLocalFilesDoNotBlockFactsOrModel"] = try projectionBytes(root, sourceFile: sourceFile) == baseline
        for name in extras { try FileManager.default.removeItem(at: root.appendingPathComponent(name)) }

        let sourceData = try Data(contentsOf: sourceFile)
        var legacyObject = try JSONSerialization.jsonObject(with: sourceData) as! [String: Any]
        if var managed = legacyObject["managed"] as? [String: Any] {
            managed["contentDigest"] = "not-a-playback-permit"
            managed["receipt"] = ["schemaVersion": 999, "relativePath": "../never-open",
                "encodedByteCount": -1, "sha256": "invalid"] as [String: Any]
            legacyObject["managed"] = managed
            let legacyData = try JSONSerialization.data(withJSONObject: legacyObject)
            try legacyData.write(to: sourceFile)
            let currentSource = try JSONDecoder().decode(ScenePlaybackSource.self, from: legacyData)
            checks["badOptionalHintDoesNotBlockCurrentSource"] = try currentSource.isValid
                && projectionBytes(root, sourceFile: sourceFile) == baseline
            try sourceData.write(to: sourceFile)
        }

        let package = root.appendingPathComponent("scene.pkg")
        let original = try Data(contentsOf: package)
        try autoreleasepool {
            let opened = try ScenePkgReader().openPackage(packageURL: package, limits: .compatibility)
            let index = opened.index
            guard let entry = index.entries.first(where: { $0.path == "unused/payload.bin" }), entry.size > 0,
                  let oldHandle = try facts(root, sourceFile: sourceFile).resourceView.literalEntry(relativePath: entry.path) else {
                throw ProbeError.missingEntry
            }
            let oldIdentity = try oldHandle.currentIdentity()
            var changed = original
            let offset = index.dataStartOffset + Int(entry.offset)
            changed[offset] ^= 1
            try changed.write(to: package)
            let current = try facts(root, sourceFile: sourceFile)
            guard let currentHandle = try current.resourceView.literalEntry(relativePath: entry.path) else { throw ProbeError.missingEntry }
            checks["currentPackageRevisionInvalidatesOldCacheIdentity"] = try currentHandle.currentIdentity() != oldIdentity
            checks["unusedPayloadChangeDoesNotBlockPlayback"] = try projectionBytes(root, sourceFile: sourceFile) == baseline
            checks["newConsumerReadsCurrentBytesWithoutHistoricalDigestGate"] = try currentHandle.readBytes()
                == changed.subdata(in: offset..<(offset + Int(entry.size)))
            do { _ = try oldHandle.readBytes(); checks["alreadyOpenedChangedPackageIsRejected"] = false }
            catch SceneResourceView.ReadError.sourceChanged { checks["alreadyOpenedChangedPackageIsRejected"] = true }
            try original.write(to: package)
        }

        let project = root.appendingPathComponent("project.json")
        let projectData = try Data(contentsOf: project)
        var json = try JSONSerialization.jsonObject(with: projectData) as! [String: Any]
        json["title"] = "Updated local title"
        try JSONSerialization.data(withJSONObject: json).write(to: project)
        checks["validLocalProjectEditIsReadNormally"] = try facts(root, sourceFile: sourceFile).project?.title == "Updated local title"
        try projectData.write(to: project)

        for caller in ["facts", "model"] {
            let token = SceneWallpaperLaunchCancellation()
            var reached = false
            let check = {
                if packageOpen(package) { reached = true; token.cancel() }
                try token.check()
            }
            do {
                if caller == "facts" { _ = try facts(root, sourceFile: sourceFile, check: check) }
                else { _ = try model(root, sourceFile: sourceFile, check: check) }
                checks[caller + "CancellationEscapes"] = false
            } catch SceneDesktopWallpaperHostLaunchError.cancelled { checks[caller + "CancellationEscapes"] = reached }
        }
        checks["subsequentNormalReadIsUnaffected"] = try projectionBytes(root, sourceFile: sourceFile) == baseline
        return checks
    }
    static func legacy(_ root: URL, sourceFile: URL) throws -> [String: Bool] {
        let loaded = try facts(root, sourceFile: sourceFile)
        guard let entryPath = loaded.project?.entryPath,
              let entry = try loaded.resourceView.literalEntry(relativePath: entryPath) else { throw ProbeError.missingEntry }
        let packaged: Bool
        switch try entry.currentIdentity() { case .package: packaged = true; case .file: packaged = false }
        return ["unusedAliasesKeepOneVirtualPackageRoot": loaded.resourceView.roots.filter { $0.source == .package }.count == 1
                && loaded.resourceView.roots.first?.directoryURL == nil,
            "unusedAliasesKeepValidDocument": loaded.sceneDocument != nil && loaded.renderDescriptor != nil,
            "unusedAliasesKeepSelectedPackageIdentity": packaged]
    }
#endif
    static func main() throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let sourceFile = CommandLine.arguments[2] == "-" ? nil : URL(fileURLWithPath: CommandLine.arguments[2])
        let mode = CommandLine.arguments[3]
        let result: Any
#if D8_CURRENT
        if mode == "route" { result = try route(root, sourceFile: sourceFile!) }
        else if mode == "mutable" { result = try mutable(root, sourceFile: sourceFile!) }
        else if mode == "legacy" { result = try legacy(root, sourceFile: sourceFile!) }
        else { result = try projection(facts(root, sourceFile: sourceFile), model(root, sourceFile: sourceFile)) }
#else
        result = try projection(facts(root, sourceFile: nil), model(root, sourceFile: nil))
#endif
        let data = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }
}
