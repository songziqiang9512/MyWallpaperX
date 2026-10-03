from pathlib import Path
import tempfile
import unittest
from script.repository_residue import inventory


class RepositoryResidueTests(unittest.TestCase):
    def test_nested_residue_inventoried_without_reading_or_deleting(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            target = root / 'MyWallpaperX/Core/.mimosa/nested'
            target.mkdir(parents=True)
            (target / 'evidence').write_bytes(b'abc')
            quarantined = root / '.codex/residue/.mimosa'
            quarantined.mkdir(parents=True)
            (quarantined / 'preserved').write_bytes(b'keep')
            rows = inventory(root)
            self.assertEqual([(r['path'], r['files'], r['bytes']) for r in rows],
                             [('MyWallpaperX/Core/.mimosa', 1, 3)])
            self.assertEqual((target / 'evidence').read_bytes(), b'abc')

    def test_symlinked_external_directory_is_not_traversed(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            external = root / 'outside/.mimosa'
            external.mkdir(parents=True)
            (root / 'MyWallpaperX').mkdir()
            (root / 'MyWallpaperX/link').symlink_to(external.parent, target_is_directory=True)
            self.assertEqual(inventory(root), [])

    def test_reserved_name_symlink_does_not_read_target(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'outside').mkdir()
            (root / 'outside/evidence').write_bytes(b'private payload')
            (root / 'MyWallpaperX').mkdir()
            (root / 'MyWallpaperX/.mimosa').symlink_to(root / 'outside', target_is_directory=True)
            result = inventory(root)
            self.assertEqual((result[0]['files'], result[0]['bytes'], result[0]['symlinks']), (0, 0, 1))
