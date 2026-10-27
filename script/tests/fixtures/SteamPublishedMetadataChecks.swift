import Foundation
import Darwin

/// Exercises the real publishedMetadata owner and its descriptor-bound read leaves.
enum SteamPublishedMetadataChecks {
    static func run(base: URL) throws -> String {
        typealias T = SteamWorkshopLibraryTransaction
        let fm = FileManager.default
        let library = base.appendingPathComponent("metadata-library", isDirectory: true)
        let index = library.appendingPathComponent(T.metadataName, isDirectory: true)
        try fm.createDirectory(at: index, withIntermediateDirectories: true)
        let first = Data("first-current-metadata".utf8)
        let second = Data("second-current-metadata".utf8)
        let video = Data("legacy-video-metadata".utf8)
        try first.write(to: index.appendingPathComponent("123456.json"))
        try second.write(to: index.appendingPathComponent("234567.json"))
        try video.write(to: index.appendingPathComponent("video-deadbeef.json"))
        try Data("not-metadata".utf8).write(to: index.appendingPathComponent("123456.json.author"))
        try Data("not-an-item".utf8).write(to: index.appendingPathComponent("not-an-id.json"))
        let literalNames = ["video:literal.json", "video\\literal.json", String(repeating: "界", count: 100) + ".json"]
        for name in literalNames { try Data(name.utf8).write(to: index.appendingPathComponent(name)) }
        var checks: [String: Bool] = [:]
        func check(_ name: String, _ value: Bool) {
            precondition(value, name)
            checks[name] = true
        }
        func read(_ complete: Bool, item: String? = nil, filename: String? = nil) throws -> [String: Data] {
            try T.publishedMetadata(libraryRoot: library, requireComplete: complete,
                                    matchingItemID: item, matchingFilename: filename)
        }
        func rejects(_ name: String, _ body: () throws -> Void) {
            do { try body(); preconditionFailure(name) }
            catch { checks[name] = true }
        }
        for complete in [false, true] {
            let suffix = complete ? "Complete" : "BestEffort"
            check("itemTarget" + suffix, try read(complete, item: "123456") == ["123456": first])
            check("numericFilenameTarget" + suffix,
                  try read(complete, filename: "234567.json") == ["234567": second])
            check("videoFilenameTarget" + suffix,
                  try read(complete, filename: "video-deadbeef.json") == ["video-deadbeef": video])
            for name in literalNames {
                check("literalBasename" + suffix + ":" + name,
                      try read(complete, filename: name) == [String(name.dropLast(5)): Data(name.utf8)])
            }
            check("bothFiltersIntersect" + suffix,
                  try read(complete, item: "234567", filename: "234567.json") == ["234567": second])
            check("bothFiltersPreserveExplicitVideoName" + suffix,
                  try read(complete, item: "video-deadbeef", filename: "video-deadbeef.json")
                    == ["video-deadbeef": video])
            check("differentFiltersAreEmpty" + suffix,
                  try read(complete, item: "123456", filename: "234567.json").isEmpty)
            check("missingItemIsEmpty" + suffix, try read(complete, item: "999999").isEmpty)
            check("missingFilenameIsEmpty" + suffix, try read(complete, filename: "absent.json").isEmpty)
            for invalid in ["", "0", "../123456", "123456/../234567", "not-an-id", "18446744073709551616"] {
                check("invalidItemIsEmpty" + suffix + ":" + invalid,
                      try read(complete, item: invalid).isEmpty)
            }
            check("wholeIndexKeepsNumericItemsOnly" + suffix,
                  try read(complete) == ["123456": first, "234567": second])
        }
        for invalid in ["../123456.json", "nested/123456.json", "/123456.json", "123456.txt", "bad\0.json"] {
            rejects("invalidFilenameRejected:" + invalid) { _ = try read(true, filename: invalid) }
        }

        // A root or index missing from a local-only library is still distinct from an
        // existing target that cannot be read. Complete whole-index consumers stay strict.
        let localOnly = base.appendingPathComponent("local-only", isDirectory: true)
        try fm.createDirectory(at: localOnly, withIntermediateDirectories: true)
        for complete in [false, true] {
            check("missingIndexTargetIsEmpty:\(complete)",
                  try T.publishedMetadata(libraryRoot: localOnly, requireComplete: complete,
                                          matchingItemID: "123456").isEmpty)
        }
        rejects("missingIndexWholeCompleteFails") {
            _ = try T.publishedMetadata(libraryRoot: localOnly, requireComplete: true)
        }

        let target = index.appendingPathComponent("345678.json")
        let outside = base.appendingPathComponent("outside.json")
        try Data("outside-must-not-be-read".utf8).write(to: outside)
        for kind in ["symlink", "directory", "hardlink", "oversized"] {
            switch kind {
            case "symlink": try fm.createSymbolicLink(at: target, withDestinationURL: outside)
            case "directory": try fm.createDirectory(at: target, withIntermediateDirectories: false)
            case "hardlink": try fm.linkItem(at: outside, to: target)
            default:
                precondition(fm.createFile(atPath: target.path, contents: nil))
                let output = try FileHandle(forWritingTo: target)
                try output.truncate(atOffset: UInt64(4 * 1024 * 1024 + 1))
                try output.close()
            }
            // errno is not an error result for a successful open/fstat. An error from
            // the selected FD/read must not become a missing target because of it.
            errno = ENOENT
            rejects("existing" + kind + "ItemCompleteFails") { _ = try read(true, item: "345678") }
            errno = ENOENT
            rejects("existing" + kind + "FilenameCompleteFails") {
                _ = try read(true, filename: "345678.json")
            }
            check("existing" + kind + "BestEffortIsEmpty", try read(false, item: "345678").isEmpty)
            check("otherTargetIgnores" + kind, try read(true, item: "123456") == ["123456": first])
            check("wholeIndexSkips" + kind + "BestEffort",
                  try read(false) == ["123456": first, "234567": second])
            rejects("wholeIndex" + kind + "CompleteFails") { _ = try read(true) }
            try fm.removeItem(at: target)
        }
        check("outsideBytesUnchanged", try Data(contentsOf: outside) == Data("outside-must-not-be-read".utf8))
        try Data("replacement".utf8).write(to: index.appendingPathComponent("123456.json"), options: .atomic)
        check("nextReadUsesCurrentReplacement",
              try read(true, item: "123456") == ["123456": Data("replacement".utf8)])
        let encoded = try JSONSerialization.data(withJSONObject: checks, options: [.sortedKeys])
        return String(decoding: encoded, as: UTF8.self)
    }
}
