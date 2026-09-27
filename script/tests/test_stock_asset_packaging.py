"""Exercise the real stock copy and verify the retained authored resource closure."""
import hashlib
import json
import re
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "MyWallpaperX/Resources/SceneStockAssets.bundle"


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
                      for p in destination.rglob("*") if p.is_file()}
            self.assertEqual(actual, expected)
            self.assertTrue(any(p.parts[0] == "Licenses" for p in actual))

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
