"""Static source-layout policy, separate from product behavior and compilation."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]


class DebugSourceLayoutTests(unittest.TestCase):
    def test_debug_sources_are_scoped_under_app_debug(self):
        self.assertEqual(list((ROOT / 'MyWallpaperX/App').glob('Debug*.swift')), [])
        sources = list((ROOT / 'MyWallpaperX/App/Debug').glob('*.swift'))
        self.assertTrue(sources)
        for source in sources:
            with self.subTest(source=source.name):
                text = source.read_text()
                active = [line for line in text.splitlines() if line.strip() and not line.lstrip().startswith('//')]
                self.assertEqual(active[0].strip(), '#if DEBUG')
                self.assertEqual(active[-1].strip(), '#endif')

    def test_xcode_source_root_is_synchronized(self):
        # The actual checkpoint build validates membership/type checking; this
        # structural policy catches accidentally replacing its discovery model.
        project = (ROOT / 'MyWallpaperX.xcodeproj/project.pbxproj').read_text()
        self.assertIn('PBXFileSystemSynchronizedRootGroup', project)
        self.assertNotIn('App/Debug/', project)
