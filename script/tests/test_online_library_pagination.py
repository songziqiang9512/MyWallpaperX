"""Real Pixabay fetch/search publication and URLSession cancellation boundaries.

The production response decoder, search/reset/loadNextPage, fetchPage, buildURL
and published fields are compiled unchanged. URLProtocol supplies controlled
HTTP/transport outcomes; only thumbnail cancellation is a recording leaf. This
does not test external Pixabay availability or downloaded-content scanning.
"""
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

from script.tests.test_ui_library_algorithms import declaration

ROOT = Path(__file__).resolve().parents[2]
SERVICE = ROOT / "MyWallpaperX/Modules/OnlineLibrary/Core/OnlineLibraryService.swift"
MODELS = ROOT / "MyWallpaperX/Modules/OnlineLibrary/Core/OnlineLibraryModels.swift"
FIXTURE = ROOT / "script/tests/fixtures/OnlineLibraryPaginationHarness.swift"


@unittest.skipUnless(sys.platform == "darwin", "Combine/AppKit require macOS")
class OnlineLibraryPaginationTests(unittest.TestCase):
    def test_real_http_pages_are_unique_and_cancelled_requests_cannot_publish(self):
        selected = Path(os.environ.get("MWX_ONLINE_PAGINATION_SOURCE", SERVICE))
        source = selected.read_text()
        decoder = source[source.index("private struct OLResponse:"):source.index("// MARK: - 服务")]
        field_prefixes = ("    @Published var items:", "    @Published var isLoading:",
                          "    @Published var errorMessage:", "    @Published var hasMore:",
                          "    @Published var totalHits:", "    @Published private(set) var currentParams",
                          "    private var currentPage:", "    private(set) var hasLoadedOnce:",
                          "    @Published var toolbarQuery:", "    private var searchTask:",
                          "    private var itemIndexByID:")
        fields = "\n".join(next(line for line in source.splitlines() if line.startswith(prefix))
                           for prefix in field_prefixes)
        owner = "\n".join(declaration(source, signature) for signature in (
            "    func clearAPIKeyAndReset(", "    func search(params:", "    func loadNextPage(",
            "    private func fetchPage(", "    private func buildURL("))
        template = FIXTURE.read_text().replace("// PRODUCTION_DECODER", decoder)
        template = template.replace("// PRODUCTION_FIELDS", fields).replace("// PRODUCTION_OWNER", owner)
        paths = [selected, MODELS, FIXTURE, Path(__file__).resolve(),
                 ROOT / "script/tests/test_ui_library_algorithms.py"]
        inputs = {str(path): hashlib.sha256(path.read_bytes()).hexdigest() for path in paths}
        with tempfile.TemporaryDirectory(prefix="mwx-online-pagination-", dir="/private/tmp") as folder:
            work = Path(folder)
            (work / "Checks.swift").write_text(template)
            home = work / "home"; home.mkdir()
            environment = dict(os.environ, HOME=str(home), CFFIXED_USER_HOME=str(home))
            command = ["xcrun", "swiftc", "-swift-version", "5", "-default-isolation", "MainActor",
                       "-warnings-as-errors", "-parse-as-library", str(MODELS), str(work / "Checks.swift"),
                       "-module-cache-path", str(work / "modules"), "-o", str(work / "checks")]
            build = subprocess.run(command, capture_output=True, text=True, env=environment, timeout=120)
            proof = None
            if destination := os.environ.get("MWX_ONLINE_PAGINATION_PROOF_DIR"):
                Path(destination).mkdir(parents=True, exist_ok=True)
                proof = Path(tempfile.mkdtemp(prefix="paging-", dir=destination))
                (proof / "compile.log").write_text(build.stdout + build.stderr)
                (proof / "inputs.json").write_text(json.dumps({"inputs": inputs, "command": command,
                    "scope": __doc__, "transforms": ["extract unchanged owner/fields/decoder; inject ephemeral URLSession in fixture"]}, indent=2))
            self.assertEqual(build.returncode, 0, build.stdout + build.stderr)
            modes = [os.environ["MWX_ONLINE_PAGINATION_MODE"]] if os.environ.get("MWX_ONLINE_PAGINATION_MODE") else ["pages", "cancellation"]
            for mode in modes:
                with self.subTest(mode=mode):
                    run = subprocess.run([str(work / "checks"), mode], capture_output=True, text=True,
                                         env=environment, timeout=35)
                    if proof:
                        (proof / f"{mode}.stdout.log").write_text(run.stdout)
                        (proof / f"{mode}.stderr.log").write_text(run.stderr)
                    self.assertEqual(run.returncode, 0, run.stdout + run.stderr)
                    checks = json.loads(run.stdout)
                    self.assertTrue(checks)
                    print(json.dumps(checks, sort_keys=True))
                    for name, passed in checks.items():
                        self.assertIs(passed, True, name + "\n" + run.stderr)
            self.assertEqual(inputs, {str(path): hashlib.sha256(path.read_bytes()).hexdigest() for path in paths})


if __name__ == "__main__":
    unittest.main()
