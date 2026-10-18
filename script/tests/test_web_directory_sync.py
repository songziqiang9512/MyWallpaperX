"""An unset directory must never enumerate the process working directory."""
import subprocess
import tempfile
import unittest
from pathlib import Path

from script.tests.test_steam_library_interactions import method
from script.tests.test_web_compat_parity import source_block

ROOT = Path(__file__).resolve().parents[2]
HOST = ROOT / "MyWallpaperX/Core/SteamWorkshopWeb/Host"

HARNESS = r'''
import Foundation
final class Host {
// PRODUCT
}
func check(_ value: @autoclosure () -> Bool, _ message: String) {
    if !value() { fatalError(message) }
}
@main enum Harness {
    static func main() throws {
        let host = Host()
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        try Data("must not be disclosed".utf8).write(to: cwd.appendingPathComponent("cwd-secret.txt"))
        func payload(_ path: String, key: String = "slides") throws -> String {
            String(data: try JSONSerialization.data(withJSONObject: [key:
                ["type":"directory", "mode":"fetchall", "value":path]]), encoding: .utf8)!
        }
        for (index, path) in ["", "  ", "\n\t"].enumerated() {
            let status = host.directorySyncStatus(forPath: path)
            check(!status.isAccessible && status.errorMessage == "directory_path_empty", "empty path error")
            check(status.snapshot.filesByPath.isEmpty, "empty path must not expose cwd")
            let result = host.computeFetchAllDirectorySyncResult(using: try payload(path, key: "renamed\(index)"), previousSnapshots: [:])
            check(result.snapshotsByProperty.values.allSatisfy { $0.filesByPath.isEmpty }, "empty snapshot")
            check(result.watchedDirectoriesByProperty.isEmpty && !result.hasFetchAllDirectory, "no empty-directory polling")
            check(result.changeNotifications.isEmpty, "no spurious files")
        }
        let directory = cwd.appendingPathComponent("selected directory")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("renamed.png")
        try Data([1]).write(to: file)
        let json = try payload(directory.path)
        let initial = host.computeFetchAllDirectorySyncResult(using: json, previousSnapshots: [:])
        check(initial.hasFetchAllDirectory && initial.watchedDirectoriesByProperty.count == 1, "selected directory watched")
        check(initial.changeNotifications.first?.addedOrChangedFiles == [file.path], "initial contents")
        let unchanged = host.computeFetchAllDirectorySyncResult(using: json, previousSnapshots: initial.snapshotsByProperty)
        check(unchanged.changeNotifications.isEmpty, "unchanged directory sends no duplicate list")
        let cleared = host.computeFetchAllDirectorySyncResult(using: try payload(""), previousSnapshots: initial.snapshotsByProperty)
        check(cleared.changeNotifications.first?.removedFiles == [file.path], "clearing removes prior contents")
        check(cleared.changeNotifications.first?.addedOrChangedFiles.isEmpty == true, "clearing never adds cwd")
        check(!cleared.hasFetchAllDirectory && cleared.watchedDirectoriesByProperty.isEmpty, "clearing stops polling")
        let missing = host.computeFetchAllDirectorySyncResult(using: try payload(directory.appendingPathComponent("missing").path), previousSnapshots: [:])
        check(missing.hasFetchAllDirectory && missing.watchedDirectoriesByProperty.isEmpty, "missing explicit directory retains retry")
        print("web-directory-sync-pass")
    }
}
'''


class WebDirectorySyncTests(unittest.TestCase):
    def test_unset_and_selected_directory_semantics(self):
        types = (HOST / "WebWallpaperHostTypes.swift").read_text()
        source = (HOST / "DedicatedWebWallpaperHostPlaceholderAdapter+DirectorySync.swift").read_text()
        declarations = [source_block(types, "struct " + name) for name in (
            "DirectorySnapshot", "DirectorySyncStatus", "FetchAllDirectoryProperty",
            "FetchAllDirectoryNotification", "FetchAllDirectoryAccessNotification", "FetchAllDirectorySyncResult")]
        declarations += [method(source, signature) for signature in (
            "func parseFetchAllDirectoryProperties(", "func computeFetchAllDirectorySyncResult(",
            "func directorySyncStatus(")]
        with tempfile.TemporaryDirectory(prefix="mwx-web-directory-sync-") as temporary:
            root = Path(temporary)
            (root / "Harness.swift").write_text(HARNESS.replace("// PRODUCT", "\n".join(declarations)))
            compile_result = subprocess.run(["xcrun", "swiftc", "-parse-as-library", str(root / "Harness.swift"),
                "-o", str(root / "harness")], capture_output=True, text=True, timeout=60)
            self.assertEqual(compile_result.returncode, 0, compile_result.stderr)
            run = subprocess.run([str(root / "harness")], cwd=root, capture_output=True, text=True, timeout=15)
            self.assertEqual(run.returncode, 0, run.stdout + run.stderr)
            self.assertIn("web-directory-sync-pass", run.stdout)
