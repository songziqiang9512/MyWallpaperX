// Real filesystem admission and one observed enumeration per resolver call.
// The old sort oracle sees only the exact already-admitted candidate sequence.
import Foundation

nonisolated struct HTMLResolutionSnapshot: Sendable {
    let candidates: [URL]?
    let root: URL?
    let comparisons: Int
}
nonisolated final class HTMLResolutionObservation: @unchecked Sendable {
    static let shared = HTMLResolutionObservation()
    private let lock = NSLock()
    private var candidates: [URL]?
    private var root: URL?
    private var comparisons = 0
    func reset() {
        lock.lock(); defer { lock.unlock() }
        candidates = nil; root = nil; comparisons = 0
    }
    func admitted(_ values: [URL], root directory: URL) {
        lock.lock(); defer { lock.unlock() }
        candidates = values; root = directory
    }
    func compared() {
        lock.lock(); defer { lock.unlock() }
        comparisons += 1
    }
    var snapshot: HTMLResolutionSnapshot {
        lock.lock(); defer { lock.unlock() }
        return .init(candidates: candidates, root: root, comparisons: comparisons)
    }
}

@MainActor enum SteamWorkshopService {
    // PRODUCTION_RESOLVER_AND_RELATIVE_PATH
    // PRODUCTION_PURE_TIE_SELECTOR
}

@MainActor struct HTMLFixtures {
    let base: URL
    func directory(_ name: String) throws -> URL {
        let url = base.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
    func file(_ path: String, in directory: URL, contents: String = "<html>owned fixture</html>") throws -> URL {
        let url = directory.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(contents.utf8).write(to: url)
        return url.resolvingSymlinksInPath().standardizedFileURL
    }
    func link(_ name: String, in directory: URL, to target: URL) throws -> URL {
        let url = directory.appendingPathComponent(name)
        try FileManager.default.createSymbolicLink(at: url, withDestinationURL: target)
        return url
    }
}

@main
@MainActor struct SteamHTMLResolutionHarness {
    // Independent frozen old comparator, including the literal substring rule.
    // It does not call the production comparator or enumerate the filesystem.
    static func oldRelativePath(_ file: URL, under root: URL) -> String {
        let prefix = root.standardizedFileURL.path
        let path = file.standardizedFileURL.path
        guard path.hasPrefix(prefix) else { return file.lastPathComponent }
        return path.dropFirst(prefix.count).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }
    static func oldPriority(_ path: String) -> Int {
        let lower = path.localizedLowercase
        if lower == "index.html" || lower == "index.htm" { return 0 }
        if lower.hasSuffix("/index.html") || lower.hasSuffix("/index.htm") { return 1 }
        if lower == "default.html" || lower == "default.htm" { return 2 }
        if lower.contains("/ui/") || lower.contains("/assets/") || lower.contains("/preview") { return 5 }
        return 3
    }
    static func oldLess(_ lhs: URL, _ rhs: URL, under root: URL) -> Bool {
        let left = oldRelativePath(lhs, under: root), right = oldRelativePath(rhs, under: root)
        let lp = oldPriority(left), rp = oldPriority(right)
        if lp != rp { return lp < rp }
        let ld = left.split(separator: "/").count, rd = right.split(separator: "/").count
        if ld != rd { return ld < rd }
        return left.localizedLowercase.localizedStandardCompare(right.localizedLowercase) == .orderedAscending
    }

    static func main() throws {
        let fixtures = HTMLFixtures(base: URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true))
        var checks: [String: Bool] = [:]
        var metrics: [String: [String: Int]] = [:]
        var oracleMatches = true, firstTieMatches = true, canonicalAndContained = true
        var preferredDoesNotEnumerate = true, observedSelections = 0
        func same(_ actual: URL?, _ expected: URL?) -> Bool {
            actual?.absoluteString == expected?.absoluteString
        }
        func resolve(_ label: String, in directory: URL, preferred: String? = nil, isPreferredHit: Bool = false) -> URL? {
            HTMLResolutionObservation.shared.reset()
            let actual = SteamWorkshopService.resolveHTMLURL(in: directory, preferredFileName: preferred)
            let observation = HTMLResolutionObservation.shared.snapshot
            var oldComparisons = 0, tieCount = 0, distinctTieCount = 0
            if let candidates = observation.candidates, let root = observation.root {
                observedSelections += 1
                let winner = candidates.sorted { lhs, rhs in
                    oldComparisons += 1
                    return oldLess(lhs, rhs, under: root)
                }.first
                oracleMatches = oracleMatches && same(actual, winner)
                canonicalAndContained = canonicalAndContained
                    && root == directory.resolvingSymlinksInPath().standardizedFileURL
                    && candidates.allSatisfy {
                        $0 == $0.resolvingSymlinksInPath().standardizedFileURL
                            && $0.path.hasPrefix(root.path + "/")
                    }
                if let winner {
                    let ties = candidates.filter {
                        !oldLess($0, winner, under: root) && !oldLess(winner, $0, under: root)
                    }
                    tieCount = ties.count
                    distinctTieCount = Set(ties.map(\.absoluteString)).count
                    firstTieMatches = firstTieMatches && same(actual, ties.first)
                }
            }
            if isPreferredHit {
                preferredDoesNotEnumerate = preferredDoesNotEnumerate
                    && observation.candidates == nil && observation.root == nil && observation.comparisons == 0
            }
            metrics[label] = ["candidates": observation.candidates?.count ?? -1,
                "selectionComparisons": observation.comparisons, "oldSortComparisons": oldComparisons,
                "linearComparisonCount": max(0, (observation.candidates?.count ?? 0) - 1),
                "minimumRankTies": tieCount, "distinctMinimumRankURLs": distinctTieCount]
            return actual
        }

        let empty = try fixtures.directory("empty")
        checks["emptyDirectoryHasNoEntry"] = resolve("empty", in: empty) == nil
        checks["missingDirectoryHasNoEntry"] = resolve("missing", in: empty.appendingPathComponent("missing")) == nil
        let invalid = try fixtures.directory("invalid")
        _ = try fixtures.file("readme.txt", in: invalid)
        _ = try fixtures.file("video.mp4", in: invalid)
        try FileManager.default.createDirectory(at: invalid.appendingPathComponent("folder.html"), withIntermediateDirectories: true)
        checks["nonHTMLFilesAndHTMLNamedDirectoriesAreRejected"] = resolve("invalid", in: invalid) == nil

        let ranked = try fixtures.directory("ranked")
        let rootIndex = try fixtures.file("index.html", in: ranked)
        for name in ["deep/index.htm", "default.html", "ordinary.htm", "nested/ui/example.html"] {
            _ = try fixtures.file(name, in: ranked)
        }
        checks["rootIndexOutranksNestedIndexDefaultAndOrdinary"] = same(resolve("ranked", in: ranked), rootIndex)
        let nested = try fixtures.directory("nested-index")
        let nestedIndex = try fixtures.file("deep/index.html", in: nested)
        _ = try fixtures.file("default.htm", in: nested)
        checks["nestedIndexOutranksRootDefault"] = same(resolve("nested-index", in: nested), nestedIndex)
        let defaults = try fixtures.directory("default")
        let defaultEntry = try fixtures.file("default.htm", in: defaults)
        for name in ["a.html", "nested/ui/a.html", "nested/assets/a.html"] { _ = try fixtures.file(name, in: defaults) }
        checks["defaultOutranksOrdinaryAndResourceFiles"] = same(resolve("default", in: defaults), defaultEntry)
        let resources = try fixtures.directory("resources")
        let ordinary = try fixtures.file("ordinary/main.html", in: resources)
        for name in ["nested/ui/first.html", "nested/assets/first.html", "nested/preview/first.html"] {
            _ = try fixtures.file(name, in: resources)
        }
        checks["ordinaryOutranksNestedResourceSubtrees"] = same(resolve("resources", in: resources), ordinary)
        let depth = try fixtures.directory("depth")
        let shallow = try fixtures.file("z.html", in: depth)
        _ = try fixtures.file("a/deeper.html", in: depth)
        checks["shallowOrdinaryEntryPrecedesDeeperEntry"] = same(resolve("depth", in: depth), shallow)
        var topLevelResourcesMatch = true
        for name in ["ui", "assets", "preview"] {
            let root = try fixtures.directory("top-level-" + name)
            let top = try fixtures.file(name + "/entry.html", in: root)
            _ = try fixtures.file("deep/ordinary/entry.html", in: root)
            topLevelResourcesMatch = topLevelResourcesMatch && same(resolve("top-level-" + name, in: root), top)
        }
        checks["topLevelResourceNamesKeepTheirExistingPriority"] = topLevelResourcesMatch
        let numbers = try fixtures.directory("numbers")
        _ = try fixtures.file("entry-10.html", in: numbers)
        let second = try fixtures.file("entry-2.html", in: numbers)
        checks["naturalNumberOrderKeepsTheSameFullURL"] = same(resolve("numbers", in: numbers), second)
        let uppercase = try fixtures.directory("uppercase")
        let upperEntry = try fixtures.file("INDEX.HTM", in: uppercase)
        checks["uppercaseHTMExtensionIsAccepted"] = same(resolve("uppercase", in: uppercase), upperEntry)

        let preferredRoot = try fixtures.directory("preferred")
        let fallback = try fixtures.file("index.html", in: preferredRoot)
        let declared = try fixtures.file("nested/chosen.HTM", in: preferredRoot)
        _ = try fixtures.file("readme.txt", in: preferredRoot)
        try FileManager.default.createDirectory(at: preferredRoot.appendingPathComponent("directory.html"), withIntermediateDirectories: true)
        checks["preferredNormalizesWhitespaceAndBackslashes"] = same(resolve("preferred", in: preferredRoot,
            preferred: " \n nested\\chosen.HTM \t", isPreferredHit: true), declared)
        let missingPreferred = resolve("missing-preferred", in: preferredRoot, preferred: "missing.html")
        let emptyPreferred = resolve("empty-preferred", in: preferredRoot, preferred: " \n\t")
        checks["missingAndEmptyPreferredFallBackToRootIndex"] = same(missingPreferred, fallback) && same(emptyPreferred, fallback)
        checks["unsupportedPreferredFallsBackToHTML"] = same(resolve("unsupported-preferred", in: preferredRoot,
            preferred: "readme.txt"), fallback)
        checks["preferredHTMLNamedDirectoryIsRejected"] = same(resolve("directory-preferred", in: preferredRoot,
            preferred: "directory.html"), fallback)

        let hidden = try fixtures.directory("hidden-file")
        let hiddenEntry = try fixtures.file(".entry.html", in: hidden)
        checks["hiddenFileIsSkippedByFallback"] = resolve("hidden-file", in: hidden) == nil
        checks["hiddenFileRemainsAvailableAsExplicitPreferred"] = same(resolve("hidden-file-preferred", in: hidden,
            preferred: ".entry.html", isPreferredHit: true), hiddenEntry)
        let hiddenDirectory = try fixtures.directory("hidden-directory")
        let hiddenNested = try fixtures.file(".private/index.html", in: hiddenDirectory)
        checks["hiddenDirectoryIsSkippedByFallback"] = resolve("hidden-directory", in: hiddenDirectory) == nil
        checks["hiddenDirectoryRemainsAvailableAsExplicitPreferred"] = same(resolve("hidden-directory-preferred", in: hiddenDirectory,
            preferred: ".private/index.html", isPreferredHit: true), hiddenNested)
        let package = try fixtures.directory("package")
        _ = try fixtures.file("Fixture.app/Contents/Info.plist", in: package,
            contents: "<?xml version=\"1.0\"?><plist version=\"1.0\"><dict><key>CFBundlePackageType</key><string>APPL</string></dict></plist>")
        let packageEntry = try fixtures.file("Fixture.app/Contents/Resources/index.html", in: package)
        checks["packageDescendantsAreSkippedByFallback"] = resolve("package", in: package) == nil
        checks["packageEntryRemainsAvailableAsExplicitPreferred"] = same(resolve("package-preferred", in: package,
            preferred: "Fixture.app/Contents/Resources/index.html", isPreferredHit: true), packageEntry)

        let inside = try fixtures.directory("inside-link")
        let target = try fixtures.file("nested/target.htm", in: inside)
        _ = try fixtures.link("alias.html", in: inside, to: target)
        checks["insideFileSymlinkReturnsCanonicalTarget"] = same(resolve("inside-link-preferred", in: inside,
            preferred: "alias.html", isPreferredHit: true), target)
            && same(resolve("inside-link-fallback", in: inside), target)
        let outside = try fixtures.directory("owned-outside")
        let outsideEntry = try fixtures.file("leaked.html", in: outside, contents: "outside sentinel")
        let outsideBytes = try Data(contentsOf: outsideEntry)
        let externalLink = try fixtures.directory("outside-link")
        let safe = try fixtures.file("index.html", in: externalLink)
        _ = try fixtures.link("leak.html", in: externalLink, to: outsideEntry)
        checks["outsideFileSymlinkCannotEscapeEntryRoot"] = same(resolve("outside-link", in: externalLink), safe)
            && same(resolve("outside-link-preferred", in: externalLink, preferred: "leak.html"), safe)
        let siblings = try fixtures.directory("siblings")
        let entryRoot = siblings.appendingPathComponent("entry", isDirectory: true)
        try FileManager.default.createDirectory(at: entryRoot, withIntermediateDirectories: true)
        let siblingEntry = try fixtures.file("entry-extra/index.html", in: siblings, contents: "sibling sentinel")
        let siblingSafe = try fixtures.file("index.html", in: entryRoot)
        _ = try fixtures.link("sibling.html", in: entryRoot, to: siblingEntry)
        checks["siblingPrefixSymlinkCannotEscapeEntryRoot"] = same(resolve("sibling-prefix", in: entryRoot,
            preferred: "sibling.html"), siblingSafe)
        let traversal = resolve("parent-traversal", in: entryRoot, preferred: "../entry-extra/index.html")
        let backslashTraversal = resolve("backslash-parent-traversal", in: entryRoot, preferred: "..\\entry-extra\\index.html")
        checks["parentTraversalPreferredFallsBackInsideRoot"] = same(traversal, siblingSafe) && same(backslashTraversal, siblingSafe)
        let custom = try fixtures.file("custom.html", in: entryRoot)
        try FileManager.default.createDirectory(at: entryRoot.appendingPathComponent("nested"), withIntermediateDirectories: true)
        checks["containedRelativeTraversalPreferredStillResolves"] = same(resolve("contained-traversal", in: entryRoot,
            preferred: "nested/../custom.html", isPreferredHit: true), custom)
        let rootAlias = try fixtures.link("root-alias", in: siblings, to: entryRoot)
        checks["rootSymlinkReturnsCanonicalEntry"] = same(resolve("root-symlink", in: rootAlias), siblingSafe)
        _ = try fixtures.link("inside-directory", in: inside, to: target.deletingLastPathComponent())
        checks["insideDirectorySymlinkPreferredRemainsContained"] = same(resolve("inside-directory-preferred", in: inside,
            preferred: "inside-directory/target.htm", isPreferredHit: true), target)
        _ = try fixtures.link("outside-directory", in: externalLink, to: outside)
        checks["outsideDirectorySymlinkPreferredCannotEscape"] = same(resolve("outside-directory-preferred", in: externalLink,
            preferred: "outside-directory/leaked.html"), safe)
        let outsideAfter = try Data(contentsOf: outsideEntry)
        let siblingAfter = try Data(contentsOf: siblingEntry)
        checks["outsideFixturesRemainUntouched"] = outsideAfter == outsideBytes
            && siblingAfter == Data("sibling sentinel".utf8)

        // These names may collate equally or differently on the active volume.
        // Their winner is checked only against this call's admitted sequence.
        let ties = try fixtures.directory("collation-ties")
        for name in ["entry-1.html", "entry-01.HTML", "entry-001.htm"] { _ = try fixtures.file(name, in: ties) }
        _ = resolve("collation-ties", in: ties)
        let large = try fixtures.directory("large")
        for ordinal in 0..<128 {
            let number = (ordinal * 73) % 128 + 1
            _ = try fixtures.file("entry-\(number).html", in: large)
        }
        let first = large.appendingPathComponent("entry-1.html").resolvingSymlinksInPath().standardizedFileURL
        checks["largeCandidateSetKeepsTheFormerEntryChoice"] = same(resolve("large", in: large), first)
            && metrics["large"]?["candidates"] == 128
        checks["sameEnumerationCandidatesMatchFormerSortWinner"] = oracleMatches && observedSelections >= 20
        // Pure selection only: these distinct already-admitted values model a
        // case-sensitive volume. The full resolver above owns all real FS guards.
        let literalRoot = URL(fileURLWithPath: "/literal-root", isDirectory: true)
        let upperLiteral = literalRoot.appendingPathComponent("Entry.html")
        let lowerLiteral = literalRoot.appendingPathComponent("entry.html")
        let greaterLiteral = literalRoot.appendingPathComponent("z.html")
        let forwardTie = SteamWorkshopService.chooseAdmittedForTieCheck(
            candidateURLs: [greaterLiteral, upperLiteral, lowerLiteral], normalizedDirectory: literalRoot)
        let reverseTie = SteamWorkshopService.chooseAdmittedForTieCheck(
            candidateURLs: [greaterLiteral, lowerLiteral, upperLiteral], normalizedDirectory: literalRoot)
        let distinctLiteralURLs = Set([upperLiteral.absoluteString, lowerLiteral.absoluteString]).count
        let literalRanksEquivalent = !oldLess(upperLiteral, lowerLiteral, under: literalRoot)
            && !oldLess(lowerLiteral, upperLiteral, under: literalRoot)
        checks["equivalentRanksKeepFirstAdmittedCandidate"] = firstTieMatches && distinctLiteralURLs == 2
            && literalRanksEquivalent && same(forwardTie, upperLiteral) && same(reverseTie, lowerLiteral)
        checks["capturedRootsAndCandidatesStayCanonicalAndContained"] = canonicalAndContained
        checks["preferredFastPathsDoNotEnumerate"] = preferredDoesNotEnumerate
        let literalTieURLs: [String: Any] = ["scope": "pure-selection-already-admitted-values-no-filesystem-probe",
            "forwardInput": [greaterLiteral.absoluteString, upperLiteral.absoluteString, lowerLiteral.absoluteString],
            "reverseInput": [greaterLiteral.absoluteString, lowerLiteral.absoluteString, upperLiteral.absoluteString],
            "forwardWinner": forwardTie?.absoluteString ?? "nil", "reverseWinner": reverseTie?.absoluteString ?? "nil",
            "distinctURLs": distinctLiteralURLs, "bothDirectionsEquivalentRank": literalRanksEquivalent]
        let observations: [String: Any] = ["calls": metrics, "observedSelections": observedSelections,
            "literalTieURLs": literalTieURLs]
        let data = try JSONSerialization.data(withJSONObject: observations, options: [.sortedKeys])
        FileHandle.standardError.write(data + Data("\n".utf8))
        print(String(data: try JSONSerialization.data(withJSONObject: checks, options: [.sortedKeys]), encoding: .utf8)!)
    }
}
