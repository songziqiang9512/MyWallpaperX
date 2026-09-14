from pathlib import Path
import subprocess
import tempfile
import unittest

from script.source_relocations import unchanged_source_relocations


class SourceRelocationTests(unittest.TestCase):
    def test_only_unique_unchanged_moves_transfer_identity(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            subprocess.run(["git", "init", "-q", directory], check=True)
            (root / "old.swift").write_text("let value = 1\n")
            subprocess.run(["git", "add", "old.swift"], cwd=root, check=True)
            subprocess.run([
                "git", "-c", "user.name=Fixture", "-c", "user.email=fixture@example.test",
                "commit", "-qm", "fixture",
            ], cwd=root, check=True)
            (root / "new.swift").write_text("let value = 1\n")
            def moves():
                return unchanged_source_relocations(
                    root, "HEAD", ["old.swift"], ["new.swift", "copy.swift"]
                )
            self.assertEqual(moves(), {})  # Old owner still exists.
            (root / "old.swift").unlink()
            self.assertEqual(moves(), {"old.swift": "new.swift"})
            (root / "new.swift").write_text("let value = 2\n")
            self.assertEqual(moves(), {})  # Content changed during move.
            (root / "new.swift").write_text("let value = 1\n")
            (root / "copy.swift").write_text("let value = 1\n")
            self.assertEqual(moves(), {})  # Ambiguous copies.
