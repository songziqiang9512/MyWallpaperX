import plistlib
from pathlib import Path
import tempfile
import unittest

from script.release_version import appcast_version, project_version, require_newer, validate_artifacts


def feed(version="2.0.10", build=279):
    return f'<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"><channel><item><sparkle:version>{build}</sparkle:version><sparkle:shortVersionString>{version}</sparkle:shortVersionString></item></channel></rss>'.encode()


class ReleaseVersionTests(unittest.TestCase):
    def test_project_is_single_authority_for_version_and_build(self):
        project = 'MARKETING_VERSION = 2.0.10;\nCURRENT_PROJECT_VERSION = 279;\n'
        self.assertEqual(project_version(project * 2), ("2.0.10", 279))
        for conflict in ('CURRENT_PROJECT_VERSION = 280;', 'MARKETING_VERSION = 2.0.9;'):
            with self.assertRaises(ValueError): project_version(project + conflict)

    def test_historical_source_build_277_cannot_republish_over_feed_278(self):
        previous = appcast_version(feed("2.0.9", 278))
        for candidate in (("2.0.10", 277), ("2.0.10", 278), ("2.0.9", 279)):
            with self.assertRaises(ValueError): require_newer(candidate, previous)
        require_newer(("2.0.10", 279), previous)

    def test_app_and_feed_must_match_both_fields(self):
        with tempfile.TemporaryDirectory() as temporary:
            app = Path(temporary) / "MyWallpaperX.app"
            contents = app / "Contents"
            contents.mkdir(parents=True)
            info = contents / "Info.plist"
            appcast = Path(temporary) / "appcast.xml"
            appcast.write_bytes(feed())
            for version, build in (("2.0.10", 279), ("2.0.10", 280), ("2.0.9", 279)):
                info.write_bytes(plistlib.dumps({"CFBundleShortVersionString": version, "CFBundleVersion": str(build)}))
                if (version, build) == ("2.0.10", 279):
                    validate_artifacts((version, build), app=app, appcast=appcast)
                else:
                    with self.assertRaises(ValueError): validate_artifacts(("2.0.10", 279), app=app)
            appcast.write_bytes(feed(build=280))
            with self.assertRaises(ValueError): validate_artifacts(("2.0.10", 279), appcast=appcast)


if __name__ == "__main__":
    unittest.main()
