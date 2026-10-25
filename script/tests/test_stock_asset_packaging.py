"""Exercise the real stock copy and verify the retained authored resource closure."""
import base64
import hashlib
import json
import os
import re
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "MyWallpaperX/Resources/SceneStockAssets.bundle"
INDEX_SOURCE = ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Resources/Assets/SceneResourceIndex.swift"
MANIFEST_NAME = "SceneStockIndex.json"

INDEX_CHECKER = r'''
import Foundation

@main struct PackagedIndexCheck {
    static func main() throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let built = SceneResourceIndexBuilder().buildWithCompleteness(rootURL: root)
        guard built.isComplete else {
            throw NSError(domain: "PackagedIndexCheck", code: 1)
        }
        let rows = built.index.resources.map {
            ["relativePath": $0.relativePath, "fileSize": $0.fileSize] as [String: Any]
        }
        let data = try JSONSerialization.data(withJSONObject: rows, options: [.sortedKeys])
        FileHandle.standardOutput.write(data)
    }
}
'''


def original_index_rows(assets, work):
    """The original filesystem kernel, not Python visibility approximations."""
    harness = work / "PackagedIndexCheck.swift"
    harness.write_text(INDEX_CHECKER)
    binary = work / "packaged-index-check"
    subprocess.run([
        "xcrun", "--sdk", "macosx", "swiftc", "-parse-as-library", "-O",
        str(INDEX_SOURCE), str(harness),
        "-module-cache-path", str(work / "modules"), "-o", str(binary),
    ], check=True, capture_output=True)
    result = subprocess.run([str(binary), str(assets)], check=True, capture_output=True)
    return json.loads(result.stdout)


def editor_only(path):
    parts = path.parts
    return (len(parts) >= 4 and parts[:2] in (("assets", "effects"), ("assets", "presets"))
            and parts[3] == "preview") or (
        parts[:3] == ("assets", "materials", "particle") and path.name.endswith("_preview.gif"))


class StockAssetPackagingTests(unittest.TestCase):
    def test_copy_preserves_every_runtime_byte_and_removes_stale_editor_files(self):
        with tempfile.TemporaryDirectory(prefix="mwx-stock-package-") as temporary:
            destination = Path(temporary) / "Test.app/Contents/Resources/SceneStockAssets.bundle"
            destination.mkdir(parents=True)
            (destination / "stale").write_text("old output")
            subprocess.run(["bash", str(ROOT / "script/copy-scene-stock-assets.sh"), str(destination)], check=True)
            expected = {}
            for path in SOURCE.rglob("*"):
                relative = path.relative_to(SOURCE)
                if path.is_file() and not editor_only(relative) and not any(
                    name in (".mimosa", ".DS_Store") for name in relative.parts
                ):
                    expected[relative] = hashlib.sha256(path.read_bytes()).digest()
            actual = {p.relative_to(destination): hashlib.sha256(p.read_bytes()).digest()
                      for p in destination.rglob("*") if p.is_file()
                      and p.relative_to(destination) != Path(MANIFEST_NAME)}
            self.assertEqual(actual, expected)
            self.assertTrue(any(p.parts[0] == "Licenses" for p in actual))
            manifest = destination / MANIFEST_NAME
            self.assertTrue(manifest.is_file())
            self.assertLessEqual(manifest.stat().st_size, 4 * 1024 * 1024)
            envelope = json.loads(manifest.read_bytes())
            self.assertEqual(set(envelope), {"schemaVersion", "payload", "sha256"})
            self.assertEqual(envelope["schemaVersion"], 1)
            payload = base64.b64decode(envelope["payload"], validate=True)
            self.assertEqual(hashlib.sha256(payload).hexdigest(), envelope["sha256"])
            rows = json.loads(payload)
            self.assertTrue(rows)
            indexed = {}
            assets = destination / "assets"
            for row in rows:
                self.assertEqual(set(row), {"relativePath", "fileSize"})
                self.assertIsInstance(row["relativePath"], str)
                self.assertIsInstance(row["fileSize"], int)
                self.assertGreaterEqual(row["fileSize"], 0)
                self.assertNotIn(row["relativePath"], indexed)
                indexed[row["relativePath"]] = row["fileSize"]
                self.assertEqual((assets / row["relativePath"]).stat().st_size, row["fileSize"])
            original = original_index_rows(assets, Path(temporary))
            self.assertEqual(indexed, {row["relativePath"]: row["fileSize"] for row in original})
            self.assertEqual(len(rows), len(original))

    def test_failed_generator_build_removes_previous_manifest(self):
        with tempfile.TemporaryDirectory(prefix="mwx-stock-failed-build-") as temporary:
            work = Path(temporary)
            destination = work / "Test.app/Contents/Resources/SceneStockAssets.bundle"
            destination.mkdir(parents=True)
            manifest = destination / MANIFEST_NAME
            manifest.write_text("previous successful inventory")
            tools = work / "tools"
            tools.mkdir()
            xcrun = tools / "xcrun"
            xcrun.write_text("#!/bin/sh\nexit 73\n")
            xcrun.chmod(0o755)
            environment = dict(os.environ)
            environment["PATH"] = str(tools) + os.pathsep + environment.get("PATH", "")
            environment["DERIVED_FILE_DIR"] = str(work / "build")
            completed = subprocess.run(
                ["bash", str(ROOT / "script/copy-scene-stock-assets.sh"), str(destination)],
                env=environment, capture_output=True,
            )
            self.assertEqual(completed.returncode, 73)
            self.assertFalse(manifest.exists())
            self.assertNotIn(b"Scene stock index:", completed.stdout)

    def test_retained_json_does_not_depend_on_editor_previews(self):
        for path in SOURCE.rglob("*.json"):
            relative = path.relative_to(SOURCE)
            if editor_only(relative) or ".mimosa" in relative.parts:
                continue
            # Some authored documents have trailing commas. Inspect JSON string
            # tokens directly rather than dropping those documents from the audit.
            text = path.read_text()
            for token in re.finditer(r'"(?:\\.|[^"\\])*"', text):
                value = json.loads(token.group())
                normalized = value.replace("\\", "/").lower()
                is_preview = "preview/" in normalized or normalized.endswith("_preview.gif")
                # Effect metadata names an editor project; runtime loads passes
                # and dependencies, and retains this metadata byte-for-byte.
                is_metadata = re.search(r'"preview"\s*:\s*$', text[:token.start()]) is not None
                self.assertFalse(is_preview and not is_metadata, f"{relative}: {value}")


if __name__ == "__main__":
    unittest.main()
