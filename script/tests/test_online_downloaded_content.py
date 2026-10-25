"""Actual Pixabay source scan/metadata, shared query and deletion receipts.

Filesystem enumeration, dates, AV metadata loader, source workers and generation
checks are production. Hooks count/hold worker reads, release one stale worker
with an IO error, and inject unlink permission/synchronization acknowledgement failures; transport and thumbnail cache are recording leaves.
Generic selection receipts live in the actual Commands/Presentation gate. No network, user media or full App process runs.
"""
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile
import unittest

from script.tests.test_ui_library_algorithms import declaration

ROOT = Path(__file__).resolve().parents[2]
MODULE = ROOT / "MyWallpaperX/Modules/OnlineLibrary"
SERVICE = MODULE / "Core/OnlineLibraryService.swift"
CONTENT = MODULE / "Core/OnlineLibraryDownloadedContent.swift"
INSPECTOR = MODULE / "UI/OnlineLibraryDownloadsInspectorSupport.swift"
FIXTURE = ROOT / "script/tests/fixtures/OnlineDownloadedContentHarness.swift"


class OnlineDownloadedContentTests(unittest.TestCase):
    def test_single_source_scan_reuse_failures_and_real_deletion_results(self):
        service = SERVICE.read_text()
        start = service.index("    private var downloadedContentTask:")
        end = service.index("    // MARK: - 公开接口", start)
        source_owner = service[start:end].replace("private init()", "init()")
        for signature in ("    func download(item:", "    func downloadAndSet(", "    private func postReadyToPlay(",
                          "    private func startDownload(", "    func deleteLocalFiles(", "    func setLocalFileAsWallpaper("):
            source_owner += "\n" + declaration(service, signature)
        removal = "let outcome = WallpaperSourceFileDeletion.remove(prepared)"
        self.assertEqual(source_owner.count(removal), 1)
        source_owner = source_owner.replace(removal, "let outcome = DownloadedDeletionLeaf.remove(prepared)")
        source_owner = re.sub(r"\bprivate\s+", "", source_owner)
        field_signatures = (
            "    @Published var downloadingIDs:", "    @Published var downloadProgressByID:",
            "    @Published private(set) var downloadedIDs:", "    @Published var downloadError:",
            "    @Published var downloadSuccessMessage:", "    @Published var lastDownloadedItemID:")
        fields = "\n".join(next(line for line in service.splitlines() if line.startswith(signature))
                           for signature in field_signatures)
        fields = re.sub(r"\bprivate\(set\)\s+", "", fields)
        content = CONTENT.read_text()
        metadata = "    static func load(from url: URL) async -> Self {"
        self.assertEqual(content.count(metadata), 1)
        content = content.replace(metadata, metadata + "\n        await DownloadedSourceProbe.shared.metadataRead()")
        ending = "        return Scan(entries: entries, warnings: warnings)"
        self.assertEqual(content.count(ending), 1)
        content = content.replace(ending, "        await DownloadedSourceProbe.shared.finishedScan()\n" + ending)
        beginning = "    static func scan(in directory: URL, reusing previous: [OLDownloadedEntry]) async throws -> Scan {"
        self.assertEqual(content.count(beginning), 1)
        content = content.replace(beginning, beginning + "\n        try await DownloadedSourceProbe.shared.startedScan()")
        fixture = FIXTURE.read_text().replace("// SOURCE_FIELDS", fields).replace("// SOURCE_OWNER", source_owner)
        fixture = fixture.replace("// INSPECTOR_SNAPSHOT", declaration(INSPECTOR.read_text(), "struct OnlineLibraryDownloadsInspectorSnapshot"))
        shared_values = [ROOT / "MyWallpaperX/Models/WallpaperReference.swift", ROOT / "MyWallpaperX/Models/WallpaperContent.swift",
                         ROOT / "MyWallpaperX/Shared/WallpaperSourceFileDeletion.swift",
                         ROOT / "MyWallpaperX/Models/WallpaperLibraryPage.swift",
                         ROOT / "MyWallpaperX/Core/LibraryCollections/WallpaperLibraryQuery.swift",
                         MODULE / "Core/OnlineLibraryModels.swift", MODULE / "Core/PixabayLibraryContentProjection.swift"]
        originals = [SERVICE, CONTENT, INSPECTOR, FIXTURE, Path(__file__).resolve(), *shared_values]
        inputs = {str(path): hashlib.sha256(path.read_bytes()).hexdigest() for path in originals}
        with tempfile.TemporaryDirectory(prefix="mwx-online-content-", dir="/private/tmp") as temporary:
            work = Path(temporary)
            (work / "Content.swift").write_text(content)
            (work / "Checks.swift").write_text(fixture)
            build = subprocess.run(["xcrun", "swiftc", "-parse-as-library", "-swift-version", "5",
                "-default-isolation", "MainActor", *map(str, shared_values), str(work / "Content.swift"), str(work / "Checks.swift"),
                "-module-cache-path", str(work / "modules"), "-o", str(work / "checks")],
                capture_output=True, text=True, timeout=120)
            self.assertEqual(build.returncode, 0, build.stdout + build.stderr)
            home = work / "home"; home.mkdir()
            run = subprocess.run([str(work / "checks"), str(work / "media")], capture_output=True, text=True, timeout=45,
                env=dict(os.environ, HOME=str(home), CFFIXED_USER_HOME=str(home)))
            self.assertEqual(run.returncode, 0, run.stdout + run.stderr)
            checks = json.loads(run.stdout)
            self.assertTrue(checks)
            for name, passed in checks.items():
                with self.subTest(name=name): self.assertIs(passed, True)
            self.assertEqual(inputs, {str(path): hashlib.sha256(path.read_bytes()).hexdigest() for path in originals})
            print(json.dumps(checks, sort_keys=True))


if __name__ == "__main__":
    unittest.main()
