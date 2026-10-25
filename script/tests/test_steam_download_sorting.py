"""Real local statistics and metadata date persistence, without the user's library."""
import json
from pathlib import Path
import subprocess
import tempfile
import unittest

from script.tests.test_steam_library_interactions import method

ROOT = Path(__file__).resolve().parents[2]
CORE = ROOT / 'MyWallpaperX/Modules/SteamWorkshop/Core'


class SteamDownloadSortingTests(unittest.TestCase):
    def test_project_preview_reuses_one_decoded_input_and_keeps_selection_order(self):
        models = (CORE / 'SteamWorkshopAPIModels.swift').read_text()
        records = (CORE / 'SteamWorkshopService+LibraryRecords.swift').read_text()
        sync = (CORE / 'SteamWorkshopService+DownloadLibrarySync.swift').read_text()
        declarations = '\n'.join(method(models, name) for name in (
            'nonisolated struct SteamWorkshopProjectGeneral:',
            'nonisolated struct SteamWorkshopProject:'))
        loader = method(records, '    nonisolated static func loadWorkshopProject(')
        loader = loader.replace('Data(contentsOf: projectFileURL)', 'ReadProbe.read(projectFileURL)')
        methods = '\n'.join((loader,
            method(records, '    nonisolated static func preferredPreviewRelativePath('),
            method(sync, '    private func resolvePreviewRelativePath(')))
        fixture = r'''
import Foundation

enum ReadProbe {
    static var count = 0
    static func read(_ url: URL) throws -> Data {
        count += 1
        return try Data(contentsOf: url)
    }
}
// MODELS
final class SteamWorkshopService {
// METHODS
}

@main enum ProjectPreview {
    static func main() throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data([1]).write(to: root.appendingPathComponent("outside.png"))
        let service = SteamWorkshopService()
        var checks: [String: Bool] = [:]
        func run(_ name: String, project: [String: Any]?, files: [String], expected: String?,
                 metadata: String? = nil, metadataExpected: String? = nil) throws {
            let directory = root.appendingPathComponent(name, isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            for path in files {
                let url = directory.appendingPathComponent(path)
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                    withIntermediateDirectories: true)
                try Data([1]).write(to: url)
            }
            let data = try project.map { try JSONSerialization.data(withJSONObject: $0) }
            if let data { try data.write(to: directory.appendingPathComponent("project.json")) }
            ReadProbe.count = 0
            checks[name + "-selection"] = service.resolvePreviewRelativePath(in: directory) == expected
            checks[name + "-singleRead"] = ReadProbe.count == 1
            let decoded = try data.map { try JSONDecoder().decode(SteamWorkshopProject.self, from: $0) }
            if let metadata {
                checks[name + "-metadata"] = SteamWorkshopService.preferredPreviewRelativePath(
                    in: directory, project: decoded, fallbackPath: metadata) == metadataExpected
            }
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
            build = subprocess.run(['xcrun', 'swiftc', '-parse-as-library', str(source),
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
