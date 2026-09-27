"""Exercise release preparation and the workflow's actual shell with fake services."""

import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import textwrap
import unittest

from script.validate_release_notes import validate_notes, validate_release, version_tuple


ROOT = Path(__file__).resolve().parents[2]
VERSION = "2.0.10"
NOTES = f"""# MyWallpaperX {VERSION}

本次更新改善壁纸下载和播放控制。

## 新增
- 无。

## 修改
- 暂停策略统一控制三种壁纸类型。

## 优化
- 下载列表更清晰。

## 修复
- 修复下载失败后无法重试的问题。

## 已知问题
- 部分场景仍有兼容性限制。
"""


def workflow_shell(name):
    """Load a run block as executable input, without a YAML runtime dependency."""
    workflow = (ROOT / ".github/workflows/build.yml").read_text()
    step = workflow.split(f"      - name: {name}\n", 1)[1].split("      - name:", 1)[0]
    return textwrap.dedent(step.split("        run: |\n", 1)[1])


class ReleaseNotesTests(unittest.TestCase):
    def test_accepts_user_facing_notes_and_explicit_empty_categories(self):
        validate_notes(NOTES, VERSION)

    def test_rejects_missing_mismatched_or_unfinished_content(self):
        cases = [
            "", NOTES.replace(VERSION, "2.0.9"),
            NOTES.replace("本次更新改善壁纸下载和播放控制。", ""),
            NOTES.replace("## 修复", "## 其他"),
            NOTES.replace("- 下载列表更清晰。", "- "),
            NOTES + "\n## 修改\n- 重复。\n",
            NOTES + "\nTODO\n", NOTES + "\n待填写\n",
            "<!--\n" + NOTES + "\n-->",
            (ROOT / "docs/releases/TEMPLATE.md").read_text().replace("<version>", VERSION),
        ]
        for notes in cases:
            with self.subTest(notes=notes[-50:]), self.assertRaises(ValueError):
                validate_notes(notes, VERSION)

    def test_rejects_release_without_any_change(self):
        notes = re.sub(r"(?m)^- .+", "- 无。", NOTES)
        with self.assertRaises(ValueError):
            validate_notes(notes, VERSION)

    def test_version_is_numeric_and_cannot_inject_path_or_shell(self):
        self.assertGreater(version_tuple("2.0.10"), version_tuple("2.0.9"))
        for version in ("../2.0.10", "2.0.10\nX=bad", "$(touch bad)", "2.01.0", "v2.0.10", "2.0.10-beta"):
            with self.subTest(version=version), self.assertRaises(ValueError):
                version_tuple(version)


class ReleaseExecutionTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory(prefix="mwx-release-test-")
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        (self.root / "script").mkdir()
        for name in ("prepare_release_version.sh", "resolve_version.sh", "update_project_version.sh", "validate_release_notes.py", "release_version.py"):
            shutil.copy2(ROOT / "script" / name, self.root / "script" / name)
        self.project = self.root / "MyWallpaperX.xcodeproj/project.pbxproj"
        self.project.parent.mkdir()
        self.project.write_text("MARKETING_VERSION = 2.0.9;\nCURRENT_PROJECT_VERSION = 1;\n")
        (self.root / "docs/releases").mkdir(parents=True)
        self.notes = self.root / f"docs/releases/{VERSION}.md"
        self.notes.write_text(NOTES)
        self.git("init", "-q")
        self.git("config", "user.name", "Release Test")
        self.git("config", "user.email", "release@example.invalid")
        self.git("add", "script", "MyWallpaperX.xcodeproj", "docs")
        self.git("commit", "-qm", "Fixture")
        self.git("tag", "build-2.0.9")
        self.log = self.root / "commands.jsonl"
        self.bin = self.root / "bin"
        self.bin.mkdir()
        self.env = dict(os.environ, PATH=f"{self.bin}:{os.environ['PATH']}",
                        COMMAND_LOG=str(self.log), APP_NAME="MyWallpaperX",
                        MARKETING_VERSION=VERSION, REQUESTED_VERSION=VERSION,
                        DIST_DIR="dist", PACKAGE_NAME=f"MyWallpaperX-{VERSION}-abcdef0",
                        GITHUB_SHA="abcdef0123456789", EXPECTED_SHA="abcdef0123456789",
                        GITHUB_ENV=str(self.root / "github-env"), RUNNER_TEMP=str(self.root / "runner"))
        self.stub("gh", """
if args[:2] == ['release', 'view']:
    sys.exit(0 if os.environ.get('EXISTING_RELEASE') == '1' else 1)
if args[:2] == ['release', 'download']:
    directory = Path(args[args.index('--dir') + 1])
    directory.mkdir(parents=True, exist_ok=True)
    (directory / 'appcast.xml').write_text('<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"><channel><item><sparkle:version>1</sparkle:version><sparkle:shortVersionString>2.0.9</sparkle:shortVersionString></item></channel></rss>')
if args[:2] == ['release', 'create']:
    if os.environ.get('FAIL_CREATE') == '1': sys.exit(1)
    if '--notes-file' in args:
        assert Path(args[args.index('--notes-file') + 1]).read_text()
if args[:2] == ['release', 'edit'] and os.environ.get('FAIL_EDIT') == '1': sys.exit(1)
""")

    def git(self, *args):
        return subprocess.check_output(["git", *args], cwd=self.root, text=True).strip()

    def stub(self, name, body):
        path = self.bin / name
        path.write_text("#!/usr/bin/env python3\nimport json, os, sys\nfrom pathlib import Path\n"
                        "args = sys.argv[1:]\n"
                        "with open(os.environ['COMMAND_LOG'], 'a') as log: log.write(json.dumps([Path(sys.argv[0]).name, *args]) + '\\n')\n"
                        + body)
        path.chmod(0o755)

    def run_shell(self, script):
        return subprocess.run(["bash", "--noprofile", "--norc", "-eo", "pipefail", "-c", script],
                              cwd=self.root, env=self.env, text=True, capture_output=True)

    def commands(self):
        return [json.loads(line) for line in self.log.read_text().splitlines()] if self.log.exists() else []

    def test_missing_notes_and_conflicting_project_versions_stop_validation(self):
        with self.assertRaises(ValueError):
            validate_release(self.root, VERSION, check_project=True)
        self.project.write_text(f'MARKETING_VERSION = "{VERSION}";\n')
        validate_release(self.root, VERSION, check_project=True)
        self.project.write_text(self.project.read_text() + "MARKETING_VERSION = 2.0.9;\n")
        with self.assertRaises(ValueError):
            validate_release(self.root, VERSION, check_project=True)
        self.notes.unlink()
        with self.assertRaises(FileNotFoundError):
            validate_release(self.root, VERSION)

    def test_existing_or_newer_tag_blocks_release(self):
        validate_release(self.root, VERSION, check_tags=True)
        for tag in ("build-2.0.10", "build-2.0.11"):
            self.git("tag", tag)
            with self.subTest(tag=tag), self.assertRaises(ValueError):
                validate_release(self.root, VERSION, check_tags=True)
            self.git("tag", "-d", tag)

    def test_preparation_changes_only_project_without_staging_or_committing(self):
        head = self.git("rev-parse", "HEAD")
        (self.root / "parallel.txt").write_text("parallel work")
        self.git("add", "parallel.txt")
        staged = self.git("diff", "--cached")
        result = self.run_shell(f"bash script/prepare_release_version.sh {VERSION}")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn(f"MARKETING_VERSION = {VERSION};", self.project.read_text())
        self.assertEqual(self.git("rev-parse", "HEAD"), head)
        self.assertEqual(self.git("diff", "--cached"), staged)
        self.assertEqual(self.notes.read_text(), NOTES)

    def test_preparation_stops_before_mutation_on_invalid_notes_or_dirty_project(self):
        original = self.project.read_text()
        self.notes.write_text("TODO")
        result = self.run_shell(f"bash script/prepare_release_version.sh {VERSION}")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.project.read_text(), original)
        self.notes.write_text(NOTES)
        self.project.write_text(original + "// parallel edit\n")
        result = self.run_shell(f"bash script/prepare_release_version.sh {VERSION}")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.project.read_text(), original + "// parallel edit\n")

    def test_preparation_advances_past_both_committed_and_published_build(self):
        for current, published, expected in ((277, 278, 279), (300, 278, 301)):
            self.project.write_text(f"MARKETING_VERSION = 2.0.9;\nCURRENT_PROJECT_VERSION = {current};\n")
            self.git("add", "MyWallpaperX.xcodeproj/project.pbxproj")
            self.git("commit", "-qm", f"Fixture build {current}")
            result = self.run_shell(f"bash script/prepare_release_version.sh {VERSION} {published}")
            self.assertEqual(result.returncode, 0, result.stderr)
            resolved = self.run_shell("bash script/resolve_version.sh --release")
            self.assertEqual(resolved.returncode, 0, resolved.stderr)
            self.assertEqual(resolved.stdout, f"MARKETING_VERSION={VERSION}\nBUILD_VERSION={expected}\n")

    def test_resolver_rejects_unsafe_version_before_writing_environment(self):
        self.project.write_text("MARKETING_VERSION = 2.0.10\nUNSAFE=true;\n")
        result = self.run_shell("bash script/resolve_version.sh --release")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(result.stdout, "")

    def test_workflow_preflight_copies_exact_notes_and_rejects_mismatch_or_draft(self):
        self.project.write_text(f"MARKETING_VERSION = {VERSION};\nCURRENT_PROJECT_VERSION = 2;\n")
        shell = workflow_shell("Validate version and authored release notes")
        result = self.run_shell(shell)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((self.root / "dist/release-notes.md").read_text(), NOTES)
        for key, value in (("REQUESTED_VERSION", "2.0.9"), ("EXISTING_RELEASE", "1"), ("EXPECTED_SHA", "another-commit")):
            previous = self.env.get(key)
            self.env[key] = value
            self.assertNotEqual(self.run_shell(shell).returncode, 0)
            if previous is None: self.env.pop(key)
            else: self.env[key] = previous

    def test_release_uploads_draft_before_publishing_latest_then_updates_feed(self):
        (self.root / "dist").mkdir()
        (self.root / "dist/release-notes.md").write_text(NOTES)
        shell = workflow_shell("Publish stable GitHub Release") + "\n" + workflow_shell("Publish Sparkle update feed")
        result = self.run_shell(shell)
        self.assertEqual(result.returncode, 0, result.stderr)
        commands = self.commands()
        self.assertEqual([command[1:3] for command in commands],
                         [["release", "create"], ["release", "edit"], ["release", "view"], ["release", "create"]])
        self.assertIn("--draft", commands[0])
        self.assertIn("--draft=false", commands[1])
        self.assertIn("--prerelease=false", commands[1])
        self.assertIn("--latest", commands[1])
        self.assertNotIn("--clobber", commands[0])
        self.assertIn("--latest=false", commands[-1])
        self.assertIn(self.env["GITHUB_SHA"], commands[0])

    def test_failed_upload_or_publish_never_updates_feed(self):
        (self.root / "dist").mkdir()
        (self.root / "dist/release-notes.md").write_text(NOTES)
        shell = workflow_shell("Publish stable GitHub Release") + "\n" + workflow_shell("Publish Sparkle update feed")
        for key, calls in (("FAIL_CREATE", 1), ("FAIL_EDIT", 2)):
            self.log.unlink(missing_ok=True)
            self.env[key] = "1"
            result = self.run_shell(shell)
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(len(self.commands()), calls)
            self.env.pop(key)

    def test_signing_uses_current_helper_path_and_seals_app_after_nested_code(self):
        self.env.update(DERIVED_DATA_PATH="build/DerivedData", CONFIGURATION="Release",
                        DEVELOPER_ID_APPLICATION="fixture identity")
        app = self.root / "build/DerivedData/Build/Products/Release/MyWallpaperX.app"
        helper = app / "Contents/Resources/SteamService"
        helper.mkdir(parents=True)
        (helper / "SteamService").touch()
        for name in ("MyWallpaperXWallpaperDaemon", "glslang", "spirv-cross"):
            path = app / "Contents/Helpers" / name
            path.parent.mkdir(exist_ok=True)
            path.touch()
        sparkle = app / "Contents/Frameworks/Sparkle.framework/Versions/B"
        for name in ("XPCServices/Installer.xpc", "XPCServices/Downloader.xpc", "Autoupdate", "Updater.app"):
            path = sparkle / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.touch()
        # Replace only the external signing service. The workflow's shell runs unchanged.
        (self.root / "script/sign-steam-helper.sh").write_text(
            'set -e\ntest -f "$1/SteamService"\ncodesign --steam-fixture "$1/SteamService"\n')
        self.stub("codesign", "assert Path(args[-1]).exists(), args[-1]\n")
        result = self.run_shell(workflow_shell("Sign app"))
        self.assertEqual(result.returncode, 0, result.stderr)
        commands = self.commands()
        self.assertTrue(commands[0][-1].endswith("Contents/Resources/SteamService/SteamService"))
        self.assertTrue(commands[-2][-1].endswith("MyWallpaperX.app"))
        self.assertIn("--verify", commands[-1])
        downloader = next(command for command in commands if command[-1].endswith("Downloader.xpc"))
        self.assertIn("--preserve-metadata=entitlements", downloader)


if __name__ == "__main__":
    unittest.main()
