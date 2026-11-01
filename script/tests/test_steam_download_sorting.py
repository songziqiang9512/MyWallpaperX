"""Real local statistics and metadata date persistence, without the user's library."""
import json
from pathlib import Path
import subprocess
import tempfile
import unittest

from script.tests.test_steam_library_interactions import method
from script.tests.test_video_thumbnail_prefetch import SWIFT_ISOLATION_FLAGS

ROOT = Path(__file__).resolve().parents[2]
CORE = ROOT / 'MyWallpaperX/Modules/SteamWorkshop/Core'


class SteamDownloadSortingTests(unittest.TestCase):
    def test_project_preview_reuses_one_decoded_input_and_keeps_selection_order(self):
        models = (CORE / 'SteamWorkshopAPIModels.swift').read_text()
        browser = (CORE / 'SteamWorkshopModels.swift').read_text()
        records = (CORE / 'SteamWorkshopService+LibraryRecords.swift').read_text()
        sync = (CORE / 'SteamWorkshopService+DownloadLibrarySync.swift').read_text()
        declarations = '\n'.join(method(models, name) for name in (
            'nonisolated struct SteamWorkshopProjectGeneral:',
            'nonisolated struct SteamWorkshopProject:',
            'nonisolated struct SteamWorkshopDownloadMetadataSnapshot:'))
        declarations += '\n' + '\n'.join(method(browser, name) for name in (
            'nonisolated enum SteamWorkshopPreviewAssetKind:',
            'nonisolated struct SteamWorkshopDetailField:',
            'nonisolated struct SteamWorkshopBrowserItem:'))
        declarations += '\n' + method((CORE / 'SteamWorkshopLibraryTransaction.swift').read_text(),
            'nonisolated struct SteamWorkshopLibraryCommit:')
        loader = method(records, '    nonisolated static func loadWorkshopProject(')
        self.assertEqual(loader.count('Data(contentsOf: projectFileURL)'), 1)
        loader = loader.replace('Data(contentsOf: projectFileURL)', 'ReadProbe.read(projectFileURL)')
        methods = loader + '\n' + '\n'.join(method(records, name) for name in (
            '    nonisolated static func preferredPreviewRelativePath(',
            '    nonisolated static func resolveVideoURL(',
            '    nonisolated static private func videoFileCandidates(',
            '    nonisolated static private func relativePath(',
            '    nonisolated static func localCreationDate(',
            '    func downloadMetadataIndexDirectoryURL(',
            '    func downloadMetadataFileURL(for itemID:'))
        methods += '\n' + '\n'.join(method(sync, name) for name in (
            '    private func persistProjectDownloadMetadata(',
            '    private func writeDownloadMetadataSnapshot('))
        # Keep the old persist body compilable with its retired preview reader.
        legacy_preview = '    private func resolvePreviewRelativePath('
        if legacy_preview in sync:
            methods += '\n' + method(sync, legacy_preview)
        fixture = r'''
import Foundation

nonisolated enum ReadProbe {
    nonisolated(unsafe) static var count = 0
    static func read(_ url: URL) throws -> Data {
        count += 1
        return try Data(contentsOf: url)
    }
}
// MODELS
@MainActor final class SteamWorkshopService {
    let libraryRootURL: URL
    init(root: URL) { libraryRootURL = root }
    func browserItemForDownload(id: String) -> SteamWorkshopBrowserItem? { nil }
// METHODS
}

@main enum ProjectPreview {
    @MainActor static func main() throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data([1]).write(to: root.appendingPathComponent("outside.png"))
        let service = SteamWorkshopService(root: root)
        var checks: [String: Bool] = [:]
        var projectReads: [String: Int] = [:]
        func browserItem(_ id: String) -> SteamWorkshopBrowserItem {
            .init(id: id, title: "Fixture \(id)", author: "Author", authorProfileURL: nil, authorWorkshopURL: nil,
                hasAdultContent: false, summary: "Summary", descriptionText: "Description", tags: ["Tag"],
                workshopTypeText: nil, ageRatingText: nil, genreText: nil, categoryText: nil, dependencyIDs: [],
                previewImageURL: nil, previewVideoURL: nil, previewAssetKind: .unknown, fileSizeText: nil,
                resolutionText: nil, postedText: nil, updatedText: nil, favoritesText: nil, subscriptionsText: nil,
                scoreText: nil, lifetimeFavoritesText: nil, lifetimeSubscriptionsText: nil, visibilityText: nil,
                moderationText: nil, detailFields: [.init(label: "Field", value: "Value")],
                detailURL: URL(string: "https://example.invalid/item/" + id)!)
        }
        @discardableResult
        func run(_ name: String, project: [String: Any]?, files: [String], expected: String?,
                 metadata: String? = nil, metadataExpected: String? = nil, expectedVideo: String? = nil,
                 rawProject: Data? = nil, directoryName: String? = nil, fetchedAt: TimeInterval = 200) throws -> SteamWorkshopDownloadMetadataSnapshot {
            let id = directoryName ?? name, directory = root.appendingPathComponent(id, isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            for path in files {
                let url = directory.appendingPathComponent(path)
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                    withIntermediateDirectories: true)
                try Data([1]).write(to: url)
            }
            let data = try rawProject ?? project.map { try JSONSerialization.data(withJSONObject: $0) }
            let projectURL = directory.appendingPathComponent("project.json")
            if let data { try data.write(to: projectURL) }
            else if FileManager.default.fileExists(atPath: projectURL.path) { try FileManager.default.removeItem(at: projectURL) }
            let item = browserItem(id), fetched = Date(timeIntervalSince1970: fetchedAt)
            ReadProbe.count = 0
            service.persistProjectDownloadMetadata(item: item, id: id, targetURL: directory, fetchedAt: fetched)
            projectReads[name] = ReadProbe.count
            checks[name + "-singleRead"] = ReadProbe.count == 1
            let persisted = try JSONDecoder().decode(SteamWorkshopDownloadMetadataSnapshot.self,
                from: Data(contentsOf: service.downloadMetadataFileURL(for: id)))
            checks[name + "-selection"] = persisted.previewRelativePath == expected
            checks[name + "-persisted-fields"] = persisted.item == item && persisted.fetchedAt == fetched
                && persisted.sourceVideoRelativePath == expectedVideo && persisted.exportedVideoURL == nil
                && persisted.legacyFolderURL == directory && persisted.legacyRemoved == nil && persisted.commit == nil
                && persisted.firstDownloadedAt != nil
            if let metadata {
                let decoded = try data.map { try JSONDecoder().decode(SteamWorkshopProject.self, from: $0) }
                checks[name + "-metadata"] = SteamWorkshopService.preferredPreviewRelativePath(
                    in: directory, project: decoded, fallbackPath: metadata) == metadataExpected
            }
            return persisted
        }
        try run("declared", project: ["preview": "authored.gif"],
            files: ["authored.gif", "preview.png"], expected: "authored.gif")
        try run("conventional", project: ["preset": ["image": "preset.png"]],
            files: ["preset.png", "preview.jpg"], expected: "preview.jpg")
        try run("mixed-preset", project: ["preset": ["backgroundimageb": false,
            "backgroundimage": ["ignored"], "background_image": 42,
            "foreground_image": "animated.gif", "image": "folder/still.png", "bgimage": "later.png"]],
            files: ["animated.gif", "folder/still.png", "later.png", "preview.gif"],
            expected: "folder/still.png")
        try run("preset-order", project: ["preset": ["backgroundimageb": "first.png", "image": "later.png"]],
            files: ["first.png", "later.png"], expected: "first.png")
        try run("gif", project: ["preset": ["image": "missing.png"]],
            files: ["preview.gif", "metadata.png"], expected: "preview.gif",
            metadata: "metadata.png", metadataExpected: "preview.gif")
        try run("metadata", project: [:], files: ["metadata.png"], expected: nil,
            metadata: "metadata.png", metadataExpected: "metadata.png")
        try run("no-project", project: nil, files: ["preview.webp"], expected: "preview.webp")
        try run("bad-preset", project: ["preset": false], files: [], expected: nil)
        try run("outside", project: ["preview": "../outside.png"], files: [], expected: nil,
            metadata: "../outside.png", metadataExpected: nil)
        try run("inside-parent", project: ["preview": "folder/../still.png"],
            files: ["folder/seed", "still.png"], expected: "folder/../still.png")
        try run("malformed-project", project: nil, files: ["preview.png"], expected: "preview.png",
            rawProject: Data("{".utf8))
        try run("declared-video", project: ["file": "nested/selected.mp4", "preview": "authored.png"],
            files: ["nested/selected.mp4", "other.mov", "authored.png", "preview.png"], expected: "authored.png",
            expectedVideo: "nested/selected.mp4")
        let first = try run("reload-first", project: ["preview": "first.png"],
            files: ["first.png", "second.png", "preview.webp"], expected: "first.png", directoryName: "reload")
        let next = try run("reload-next", project: ["preview": "second.png"], files: [], expected: "second.png",
            directoryName: "reload", fetchedAt: 300)
        let missing = try run("reload-missing", project: nil, files: [], expected: "preview.webp",
            directoryName: "reload", fetchedAt: 400)
        let malformed = try run("reload-malformed", project: nil, files: [], expected: "preview.webp",
            rawProject: Data("{".utf8), directoryName: "reload", fetchedAt: 500)
        let recovered = try run("reload-recovered", project: ["preview": "first.png"], files: [], expected: "first.png",
            directoryName: "reload", fetchedAt: 600)
        checks["subsequent-persist-rereads-changed-missing-and-recovered-project-without-losing-first-date"] =
            [next, missing, malformed, recovered].allSatisfy { $0.firstDownloadedAt == first.firstDownloadedAt }
        FileHandle.standardError.write(Data(("Project persistence reads: " + String(decoding:
            try JSONSerialization.data(withJSONObject: projectReads, options: [.sortedKeys]), as: UTF8.self) + "\n").utf8))
        print(String(decoding: try JSONSerialization.data(withJSONObject: checks, options: [.sortedKeys]),
            as: UTF8.self))
    }
}
'''
        with tempfile.TemporaryDirectory(prefix='mwx-project-preview-', dir='/private/tmp') as directory:
            work = Path(directory)
            source = work / 'Harness.swift'
            source.write_text(fixture.replace('// MODELS', declarations).replace('// METHODS', methods))
            binary = work / 'preview'
            build = subprocess.run(['xcrun', 'swiftc', *SWIFT_ISOLATION_FLAGS, '-warnings-as-errors', '-parse-as-library',
                str(ROOT / 'MyWallpaperX/Core/SteamWorkshopStorage/ScenePlaybackSource.swift'), str(source),
                '-module-cache-path', str(work / 'modules'), '-o', str(binary)],
                capture_output=True, text=True, timeout=120)
            self.assertEqual(build.returncode, 0, build.stdout + build.stderr)
            result = subprocess.run([str(binary), str(work / 'library')],
                capture_output=True, text=True, timeout=30)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            checks = json.loads(result.stdout)
            self.assertTrue(checks)
            for name, passed in checks.items():
                with self.subTest(name=name):
                    self.assertTrue(passed)

    def test_first_download_date_and_exact_local_bytes(self):
        records = (CORE / 'SteamWorkshopService+LibraryRecords.swift').read_text()
        sync = (CORE / 'SteamWorkshopService+DownloadLibrarySync.swift').read_text()
        parsing = (CORE / 'SteamWorkshopService+ParsingUtilities.swift').read_text()
        metadata = method((CORE / 'SteamWorkshopAPIModels.swift').read_text(), 'struct SteamWorkshopDownloadMetadataSnapshot')
        commit = method((CORE / 'SteamWorkshopLibraryTransaction.swift').read_text(), 'nonisolated struct SteamWorkshopLibraryCommit')
        methods = '\n'.join(method(records, signature) for signature in [
            '    nonisolated static func localDownloadStatistics(', '    nonisolated static func localCreationDate(',
            '    nonisolated static func localFileSizeBytes(', '    nonisolated static func directoryTotalBytes('])
        methods += '\n' + method(parsing, '    nonisolated static func fileSizeText(forBytes')
        methods += '\n' + method(sync, '    private func writeDownloadMetadataSnapshot(')
        template = (ROOT / 'script/tests/fixtures/SteamDownloadSortingHarness.swift').read_text()
        with tempfile.TemporaryDirectory(prefix='mwx-steam-sort-', dir='/private/tmp') as directory:
            work = Path(directory)
            source = work / 'Harness.swift'
            source.write_text(template.replace('// MODELS', commit + '\n' + metadata).replace('// METHODS', methods))
            binary = work / 'sorting'
            build = subprocess.run(['xcrun', 'swiftc', '-parse-as-library',
                str(ROOT / 'MyWallpaperX/Core/SteamWorkshopStorage/ScenePlaybackSource.swift'), str(source),
                '-module-cache-path', str(work / 'modules'), '-o', str(binary)], capture_output=True, text=True, timeout=120)
            self.assertEqual(build.returncode, 0, build.stdout + build.stderr)
            run = subprocess.run([str(binary), str(work / 'library')], capture_output=True, text=True, timeout=30)
            self.assertEqual(run.returncode, 0, run.stdout + run.stderr)
            checks = json.loads(run.stdout)
            self.assertTrue(checks)
            for name, passed in checks.items():
                with self.subTest(name=name):
                    self.assertTrue(passed)


if __name__ == '__main__':
    unittest.main()
