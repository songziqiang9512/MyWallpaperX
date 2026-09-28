"""Exercise the Agent release entrypoint without pushing or publishing anything."""

import contextlib
import io
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

from script import publish_release as publisher


VERSION = "2.0.10"

def feed_xml(version, build):
    return f'<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"><channel><item><sparkle:version>{build}</sparkle:version><sparkle:shortVersionString>{version}</sparkle:shortVersionString></item></channel></rss>'.encode()

SHA = "a" * 40


class PublishReleaseTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="mwx-agent-release-test-")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.notes = self.root / "notes.md"
        self.notes.write_text("正式版本更新日志")
        self.calls = []
        self.branch = "main"
        self.dirty = f"docs/releases/{VERSION}.md"
        self.remote_sha = SHA
        self.failure = None
        self.feed = feed_xml(VERSION, 279)
        self.release_feed = feed_xml(VERSION, 279)
        self.remote_project = None
        self.project = self.root / "MyWallpaperX.xcodeproj/project.pbxproj"
        self.project.parent.mkdir()
        self.project.write_text(f"MARKETING_VERSION = {VERSION};\nCURRENT_PROJECT_VERSION = 279;\n")
        package = f"MyWallpaperX-{VERSION}-{SHA[:7]}"
        self.release = {
            "draft": False, "prerelease": False, "target_commitish": SHA,
            "body": self.notes.read_text(), "html_url": "https://example.invalid/release",
            "assets": [{"name": name, "state": "uploaded", "size": 100} for name in
                       (f"{package}.dmg", f"{package}.dmg.sha256", f"{package}.dSYM.zip", "appcast.xml")],
        }

    def command(self, *args):
        self.calls.append(args)
        if self.failure and args[:len(self.failure)] == self.failure:
            raise subprocess.CalledProcessError(1, args)
        if args[:3] == ("git", "branch", "--show-current"): return self.branch
        if args[:3] == ("git", "diff", "HEAD"): return self.dirty
        if args[:2] == ("git", "rev-parse"): return SHA
        if args[:2] == ("git", "show"): return self.remote_project or self.project.read_text()
        if args[:3] == ("git", "remote", "get-url"): return "https://github.com/fixture/MyWallpaperX.git"
        if args[:3] == ("gh", "repo", "view"): return "fixture/MyWallpaperX"
        if args[:2] == ("git", "ls-remote"): return f"{self.remote_sha}\trefs/heads/main"
        if args[:4] == ("gh", "api", "--method", "POST"):
            return json.dumps({"workflow_run_id": 42, "html_url": "https://example.invalid/run/42"})
        if args[:2] == ("gh", "api") and args[2].endswith("releases/latest"):
            return json.dumps({"tag_name": f"build-{VERSION}"})
        if args[:2] == ("gh", "api"):
            return json.dumps(self.release)
        if args[:3] == ("gh", "release", "download"):
            directory = Path(args[args.index("--dir") + 1])
            directory.mkdir(exist_ok=True)
            (directory / "appcast.xml").write_bytes(
                (feed_xml("2.0.9", 278) if directory.name.startswith("mwx-release-version-") else self.feed) if args[3] == "update-feed" else self.release_feed)
        return ""

    def publish(self, watch_failure=False, test_scope="release"):
        def watch(args, **kwargs):
            self.calls.append(tuple(args))
            if watch_failure: raise subprocess.CalledProcessError(1, args)
        with patch.dict(os.environ), patch.object(publisher, "ROOT", self.root), \
             patch.object(publisher, "validate_release", return_value=self.notes), \
             patch.object(publisher, "run", side_effect=self.command), \
             patch.object(publisher.subprocess, "run", side_effect=watch), \
             contextlib.redirect_stdout(io.StringIO()):
            publisher.publish(VERSION, test_scope)

    def test_prepares_narrow_commit_pushes_dispatches_exact_source_and_waits(self):
        self.publish()
        events = [command[:2] for command in self.calls]
        self.assertLess(events.index(("git", "commit")), events.index(("git", "push")))
        self.assertLess(events.index(("git", "push")), events.index(("gh", "api")))
        dispatch = next(command for command in self.calls if command[:4] == ("gh", "api", "--method", "POST"))
        self.assertIn(f"inputs[source_sha]={SHA}", dispatch)
        self.assertIn(f"inputs[version]={VERSION}", dispatch)
        self.assertIn("inputs[test_scope]=release", dispatch)
        self.assertIn(("gh", "run", "watch", "42", "--exit-status", "--interval", "15"), self.calls)
        commit = next(command for command in self.calls if command[:2] == ("git", "commit"))
        self.assertIn("--only", commit)
        self.assertEqual(commit[-2:], ("MyWallpaperX.xcodeproj/project.pbxproj", f"docs/releases/{VERSION}.md"))

    def test_full_suite_is_explicit_and_invalid_scope_has_no_side_effects(self):
        self.publish(test_scope="all")
        dispatch = next(command for command in self.calls if command[:4] == ("gh", "api", "--method", "POST"))
        self.assertIn("inputs[test_scope]=all", dispatch)
        self.calls.clear()
        with self.assertRaises(ValueError):
            self.publish(test_scope="skip")
        self.assertEqual(self.calls, [])

    def test_parallel_edits_and_wrong_branch_do_not_push_or_dispatch(self):
        for attribute, value in (("dirty", "unrelated.swift"), ("branch", "feature")):
            old = getattr(self, attribute)
            setattr(self, attribute, value)
            self.calls.clear()
            with self.assertRaises(ValueError): self.publish()
            self.assertFalse(any(command[:2] == ("git", "push") for command in self.calls))
            setattr(self, attribute, old)

    def test_failed_push_and_remote_race_do_not_dispatch(self):
        self.failure = ("git", "push")
        with self.assertRaises(subprocess.CalledProcessError): self.publish()
        self.assertFalse(any(command[:2] == ("gh", "api") for command in self.calls))
        self.failure = None
        self.remote_sha = "b" * 40
        self.calls.clear()
        with self.assertRaises(ValueError): self.publish()
        self.assertFalse(any(command[:2] == ("gh", "api") for command in self.calls))

    def test_failed_workflow_is_not_reported_as_success(self):
        with self.assertRaises(subprocess.CalledProcessError): self.publish(watch_failure=True)
        self.assertEqual(sum(command[:3] == ("gh", "release", "download") for command in self.calls), 1)

    def test_remote_project_version_mismatch_prevents_dispatch(self):
        self.remote_project = f"MARKETING_VERSION = {VERSION};\nCURRENT_PROJECT_VERSION = 278;\n"
        with self.assertRaisesRegex(ValueError, "Remote source version"): self.publish()
        self.assertFalse(any(command[:2] == ("gh", "api") for command in self.calls))

    def test_consistently_wrong_published_feeds_are_not_success(self):
        self.release_feed = self.feed = feed_xml(VERSION, 278)
        with self.assertRaisesRegex(ValueError, "Published version/build"): self.publish()

    def test_rejects_wrong_release_state_source_notes_and_incomplete_assets(self):
        for field, value in (("draft", True), ("prerelease", True), ("target_commitish", "wrong"),
                             ("body", "commit log dump"), ("assets", [])):
            previous = self.release[field]
            self.release[field] = value
            with self.subTest(field=field), self.assertRaises(ValueError): self.publish()
            self.release[field] = previous

    def test_rejects_unsynchronized_update_feed(self):
        self.feed = b"old feed"
        with self.assertRaises(ValueError): self.publish()


if __name__ == "__main__":
    unittest.main()
