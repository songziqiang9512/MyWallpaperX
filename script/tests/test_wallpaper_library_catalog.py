"""Index-first Combine catalog + held real file facts; UI/renderer leaves excluded."""
import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

from script.tests.library_catalog_fixture import assemble_catalog_fixture, write_catalog_sources
from script.tests.test_video_thumbnail_prefetch import SWIFT_ISOLATION_FLAGS
from script.tests.test_ui_library_algorithms import declaration
from script.tests.test_steam_library_legacy_discovery import prepare_legacy_discovery_sources

ROOT = Path(__file__).resolve().parents[2]


class WallpaperLibraryCatalogTests(unittest.TestCase):
    def test_live_sources_resource_revisions_update_failure_and_namespace(self):
        fixture, controller, paths, inputs = assemble_catalog_fixture()
        size_path = "MyWallpaperX/Modules/VideoLibrary/Core/WallpaperManager+InitialIndexLoad.swift"
        size_source = (ROOT / size_path).read_text()
        for path in (size_path, "script/tests/test_wallpaper_library_catalog.py", "script/tests/test_ui_library_algorithms.py"):
            inputs[path] = hashlib.sha256((ROOT / path).read_bytes()).hexdigest()
        sizes = declaration(size_source, "    private func scheduleInitialIndexFileSizes(")
        fixture = fixture.replace("// VIDEO_METADATA_RECEIPT", sizes.replace("private func", "func", 1))
        image_source = (ROOT / "MyWallpaperX/Modules/StaticImageLibrary/Core/SILService.swift").read_text()
        load = declaration(image_source, "    func load()")
        callback = "            DispatchQueue.main.async { [weak self] in"
        self.assertEqual(load.count(callback), 1)
        load = load.replace(callback, "            catalogHeaderReady.signal()\n"
            "            precondition(catalogHeaderRelease.wait(timeout: .now() + 5) == .success)\n" + callback)
        methods = "\n".join([declaration(image_source, "    nonisolated private struct MissingImageDimensions:"),
            load, declaration(image_source, "    func invalidatePendingMetadataLoad()"),
            declaration(image_source, "    private func applyLoadedImageDimensions(")])
        fixture = fixture.replace("// IMAGE_METADATA_RECEIPT", methods)
        for marker in (
            "        let previous = Set(visibleReferences.values.flatMap { $0 })",
            "        guard previous != Set(visibleReferences.values.flatMap({ $0 })) else { return }",
        ):
            self.assertEqual(controller.count(marker), 1, marker)
            controller = controller.replace(marker, "        CatalogVisibleFilterProbe.unionBuilds += 1\n" + marker)
        for marker, counter in (("    @discardableResult func publish(", "publishEntries"),
                                ("    func install(", "installEntries")):
            method = declaration(controller, marker)
            self.assertEqual(controller.count(method), 1, marker)
            opening = method.index("{") + 1
            observed = method[:opening] + f"\n        CatalogVisibleFilterProbe.{counter} += 1" + method[opening:]
            controller = controller.replace(method, observed, 1)
        with tempfile.TemporaryDirectory(prefix="mwx-live-catalog-", dir="/private/tmp") as directory:
            work = Path(directory)
            (work / "Checks.swift").write_text(fixture)
            (work / "Controller.swift").write_text(controller)
            compiled_paths = write_catalog_sources(work, paths)
            binary = work / "checks"
            build = subprocess.run(["xcrun", "swiftc", *SWIFT_ISOLATION_FLAGS, "-warnings-as-errors", "-parse-as-library",
                *compiled_paths, str(work / "Controller.swift"), str(work / "Checks.swift"),
                "-module-cache-path", str(work / "modules"), "-o", str(binary)], capture_output=True, text=True, timeout=150)
            self.assertEqual(build.returncode, 0, build.stdout + build.stderr)
            run = subprocess.run([str(binary), str(work / "media")], capture_output=True, text=True, timeout=30,
                env=dict(os.environ, HOME=str(work / "home"), CFFIXED_USER_HOME=str(work / "home")))
            self.assertEqual(run.returncode, 0, run.stdout + run.stderr)
            checks = json.loads(run.stdout)
            self.assertTrue(checks)
            for name, passed in checks.items():
                with self.subTest(name=name): self.assertIs(passed, True)
            self.assertEqual(inputs, {p: hashlib.sha256((ROOT / p).read_bytes()).hexdigest() for p in inputs})


    def test_targeted_startup_replay_replaces_warm_row_once_without_full_source_readiness(self):
        with tempfile.TemporaryDirectory(prefix="mwx-catalog-replay-", dir="/private/tmp") as directory:
            work = Path(directory)
            sources, proof = prepare_legacy_discovery_sources(ROOT, work)
            owner = ROOT / "MyWallpaperX/Modules/SteamWorkshop/Core"
            app_service = (owner / "SteamWorkshopService.swift").read_text()
            sync = (owner / "SteamWorkshopService+DownloadLibrarySync.swift").read_text()
            records = (owner / "SteamWorkshopService+LibraryRecords.swift").read_text()
            content = (owner / "SteamWorkshopService+LibraryContent.swift").read_text()
            access = (owner / "SteamWorkshopService+DownloadAccessors.swift").read_text()
            validation = ROOT / "MyWallpaperX/Modules/SteamWorkshop/Web/Core/SteamWorkshopService+WebValidation.swift"
            read = declaration(sync, "    func loadManagedDownloadSnapshots(")
            marker = "        for (itemID, data) in entries {"
            self.assertEqual(read.count(marker), 1)
            read = read.replace(marker, marker + '\n            LegacyDiscoveryObservation.shared.entered("metadata-decode", directory: libraryRoot, preferred: itemID)', 1)
            members = [read, declaration(sync, "    func managedDownloadSnapshots() ->"),
                declaration(app_service, "    func installedRecordForLaunchReplay("),
                declaration(records, "    func buildInstalledRecord(from metadata:"),
                declaration(records, "    func installedLibraryScanContext("),
                declaration(records, "    func downloadMetadataIndexDirectoryURL("),
                declaration(content, "    func libraryContentItemForExplicitPlayback("),
                declaration(content, "    nonisolated private static func libraryContentFacts("),
                declaration(access, "    func latestDownloadRecord("), declaration(access, "    func canLaunchDownloadRecord("),
                declaration(validation.read_text(), "    nonisolated func webLaunchEntryIsValid(")]
            fields = r"""@MainActor final class SteamWorkshopService {
    var downloads: [SteamWorkshopDownloadRecord] = []
    var hasCompletedInstalledLibraryLoad = false
    let libraryRootURL: URL
    init(root: URL) { libraryRootURL = root }
    var steamDownloadLibraryRootURL: URL { libraryRootURL }
    var videoLibraryRootURL: URL { libraryRootURL.appendingPathComponent("Video") }
    var webLibraryRootURL: URL { libraryRootURL.appendingPathComponent("Web") }
    var sceneLibraryRootURL: URL { libraryRootURL.appendingPathComponent("Scene") }
    var browserItems: [SteamWorkshopBrowserItem] = []
    var selectedBrowserItem: SteamWorkshopBrowserItem?
""" + "\n".join(members) + "\n}"
            generated = next(path for path in sources if path.name == "InstalledRecordBuilder.swift")
            builder = generated.read_text()
            self.assertEqual(builder.count("@MainActor final class SteamWorkshopService {}"), 1)
            generated.write_text(builder.replace("@MainActor final class SteamWorkshopService {}", fields, 1))
            rating = owner / "SteamWorkshopAgeRatingSupport.swift"
            generated.write_text(generated.read_text() + "\n" + declaration(rating.read_text(), "nonisolated enum SteamWorkshopContentRatingSupport"))
            index = next(path for path in sources if path.name == "SteamWorkshopLibraryTransaction+FailedVisibility.swift")
            observed_index = work / index.name
            index_source = index.read_text()
            marker = "                result[itemID] = try readData(file, maximumBytes: 4 * 1024 * 1024)"
            self.assertEqual(index_source.count(marker), 1)
            observed_index.write_text(index_source.replace(marker,
                '                LegacyDiscoveryObservation.shared.entered("metadata-read", directory: libraryRoot, preferred: itemID)\n' + marker, 1))
            sources[sources.index(index)] = observed_index
            harness = sources[-1]
            prefix = harness.read_text().split("@main enum SteamLibraryLegacyDiscoveryChecks {", 1)[0]
            catalog_fixture = ROOT / "script/tests/fixtures/WallpaperLibraryCatalogHarness.swift"
            browser = declaration(catalog_fixture.read_text(), "    static func browser(")
            harness.write_text(prefix + r"""
extension SteamWorkshopDownloadRecord { var isSceneLaunchable: Bool { false } }
@main struct CatalogReplayChecks {
    @MainActor static func main() throws {
        let base = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let library = try SteamWorkshopLibraryTransaction.configuredRoot(base.appendingPathComponent("library"))
        let id = "99101", date = Date(timeIntervalSince1970: 1_700_000_000)
        let commit = SteamWorkshopLibraryCommit(version: 1, workshopId: id, jobId: "owned", attempt: 1,
            directoryName: "11111111-2222-4333-8444-555555555555", manifestId: "77", contentDigest: String(repeating: "a", count: 64),
            contentType: "video", entryPath: "clip.mp4", committedAt: date)
        let folder = try SteamWorkshopLibraryTransaction.contentURL(for: commit, libraryRoot: library)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let clip = folder.appendingPathComponent("clip.mp4")
        try Data([1, 2, 3]).write(to: clip)
        try Data(#"{"type":"video","file":"clip.mp4"}"#.utf8).write(to: folder.appendingPathComponent("project.json"))
        var metadata = SteamWorkshopDownloadMetadataSnapshot(fetchedAt: date, item: try browser(id), sourceVideoRelativePath: "clip.mp4",
            previewRelativePath: nil, exportedVideoURL: clip, legacyFolderURL: folder, commit: commit, firstDownloadedAt: date)
        try SteamWorkshopLibraryTransaction.publish(metadata: JSONEncoder().encode(metadata), itemID: id, libraryRoot: library)
        let service = SteamWorkshopService(root: library)
        let real = service.buildInstalledRecord(from: metadata, legacyDirectory: folder, fallbackProject: nil,
            fallbackIdentifier: id, managedSnapshots: [id: metadata])!
        func cached(_ id: String) throws -> SteamWorkshopDownloadRecord {
            var object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(real)) as! [String: Any]
            object["id"] = id; object["title"] = "cached " + id
            var value = try JSONDecoder().decode(SteamWorkshopDownloadRecord.self, from: JSONSerialization.data(withJSONObject: object))
            value.isStartupSnapshot = true
            return value
        }
        service.downloads = [try cached("before"), try cached(id), try cached("after")]
        _ = LegacyDiscoveryObservation.shared.take()
        let first = service.libraryContentItemForExplicitPlayback(id: id)
        var checks = ["fresh-single-replay-works-before-whole-library-completion": first?.capabilities.contains(.play) == true
            && !service.hasCompletedInstalledLibraryLoad]
        checks["fresh-single-replay-replaces-only-its-exact-row-in-source-order"] = service.downloads.map(\.id) == ["before", id, "after"]
            && service.downloads[1].title == real.title && service.downloads[1].isStartupSnapshot == nil
            && service.downloads[0].isStartupSnapshot == true && service.downloads[2].isStartupSnapshot == true
        var subsequent = true
        for _ in 0..<3 { subsequent = service.libraryContentItemForExplicitPlayback(id: id) == first && subsequent }
        checks["subsequent-single-resolution-keeps-current-source-result"] = subsequent
        let reads = LegacyDiscoveryObservation.shared.take()
        checks["targeted-metadata-read-and-decode-occur-only-on-first-resolution"] =
            reads.filter { $0["kind"] == "metadata-read" }.count == 1
            && reads.filter { $0["kind"] == "metadata-decode" }.count == 1
        metadata.commit?.removed = true
        try SteamWorkshopLibraryTransaction.publish(metadata: JSONEncoder().encode(metadata), itemID: id, libraryRoot: library)
        service.downloads[1] = try cached(id)
        checks["removed-pointer-cannot-borrow-warm-row-or-leftover-file"] = service.libraryContentItemForExplicitPlayback(id: id) == nil
            && FileManager.default.fileExists(atPath: clip.path) && service.downloads[1].isStartupSnapshot == true
        let index = library.appendingPathComponent(SteamWorkshopLibraryTransaction.metadataName).appendingPathComponent(id + ".json")
        try Data("broken metadata".utf8).write(to: index)
        checks["corrupt-targeted-metadata-cannot-fall-back-to-warm-row"] = service.libraryContentItemForExplicitPlayback(id: id) == nil
            && !service.hasCompletedInstalledLibraryLoad
        print(String(decoding: try JSONEncoder().encode(checks), as: UTF8.self))
    }
""" + browser + "\n}\n")
            extra = [ROOT / "MyWallpaperX" / path for path in (
                "Models/WallpaperReference.swift", "Models/WallpaperContent.swift",
                "Modules/SteamWorkshop/Core/SteamWorkshopDownloadRecord+Launchability.swift",
                "Modules/SteamWorkshop/Core/SteamWorkshopLibraryContentProjection.swift")]
            watched = [owner / name for name in ("SteamWorkshopService.swift", "SteamWorkshopService+DownloadLibrarySync.swift",
                "SteamWorkshopService+LibraryRecords.swift", "SteamWorkshopService+LibraryContent.swift", "SteamWorkshopService+DownloadAccessors.swift")]
            watched += [validation, rating, catalog_fixture, Path(__file__), *extra]
            inputs = dict(proof["inputs"])
            inputs.update({str(path.relative_to(ROOT)): hashlib.sha256(path.read_bytes()).hexdigest() for path in watched})
            binary = work / "replay-checks"
            build = subprocess.run(["xcrun", "swiftc", *SWIFT_ISOLATION_FLAGS, "-warnings-as-errors", "-parse-as-library",
                *map(str, [*sources, *extra]), "-module-cache-path", str(work / "modules"), "-o", str(binary)],
                capture_output=True, text=True, timeout=150)
            self.assertEqual(build.returncode, 0, build.stdout + build.stderr)
            run = subprocess.run([str(binary), str(work / "media")], capture_output=True, text=True, timeout=30,
                env=dict(os.environ, HOME=str(work / "home"), CFFIXED_USER_HOME=str(work / "home")))
            self.assertEqual(run.returncode, 0, run.stdout + run.stderr)
            checks = json.loads(run.stdout)
            self.assertEqual(len(checks), 6)
            for name, passed in checks.items():
                with self.subTest(name=name): self.assertIs(passed, True)
            self.assertEqual(inputs, {p: hashlib.sha256((ROOT / p).read_bytes()).hexdigest() for p in inputs})


if __name__ == "__main__":
    unittest.main()
