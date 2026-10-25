"""Execute real helper publish/sign policy with codesign replaced at its leaf."""
import json
import os
from pathlib import Path
import plistlib
import re
import shlex
import shutil
import subprocess
import sys
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]
IDENTITY = "Developer ID Application: Signing Fixture (FIXTURE123)"


@unittest.skipUnless(sys.platform == "darwin", "requires macOS Mach-O file classification")
class SteamHelperSigningTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix="mwx-helper-signing-")
        self.addCleanup(temporary.cleanup)
        self.folder = Path(temporary.name)
        self.repo = self.folder / "repo with spaces"
        scripts = self.repo / "script"
        scripts.mkdir(parents=True)
        service = self.repo / "SteamService"
        service.mkdir()
        shutil.copy2(ROOT / "SteamService/SteamService.entitlements", service)
        self.sign_log = self.folder / "codesign.jsonl"
        self.dotnet_log = self.folder / "dotnet.jsonl"
        self.file_log = self.folder / "file.jsonl"
        self.recorder = self.folder / "record codesign"
        self.recorder.write_text(
            f"#!{sys.executable}\n"
            "import json, os, sys\n"
            "with open(os.environ['MWX_TEST_CODESIGN_LOG'], 'a') as stream:\n"
            "    stream.write(json.dumps(sys.argv[1:]) + '\\n')\n"
            "if '--verify' in sys.argv and os.environ.get('MWX_TEST_VERIFY_FAIL'):\n"
            "    sys.exit(13)\n"
        )
        self.recorder.chmod(0o755)
        classifier = self.folder / "record file classification"
        classifier.write_text(
            f"#!{sys.executable}\n"
            "import json, os, sys\n"
            "with open(os.environ['MWX_TEST_FILE_LOG'], 'a') as stream:\n"
            "    stream.write(json.dumps(sys.argv[1:]) + '\\n')\n"
            "os.execv('/usr/bin/file', ['/usr/bin/file'] + sys.argv[1:])\n"
        )
        classifier.chmod(0o755)
        for name in ("publish-steam-helper.sh", "sign-steam-helper.sh"):
            source = (ROOT / "script" / name).read_text()
            # Preserve all real shell decisions, including publish -> sign.
            source = source.replace("/usr/bin/codesign", shlex.quote(str(self.recorder)))
            source = source.replace("/usr/bin/file", shlex.quote(str(classifier)))
            (scripts / name).write_text(source)
        self.publisher = self.folder / "fake dotnet"
        self.publisher.write_text(
            f"#!{sys.executable}\n"
            "import json, os, pathlib, shutil, sys\n"
            "args = sys.argv[1:]\n"
            "with open(os.environ['MWX_TEST_DOTNET_LOG'], 'a') as stream:\n"
            "    stream.write(json.dumps(args) + '\\n')\n"
            "if args[0] == 'restore':\n"
            "    sys.exit(0)\n"
            "if args[0] != 'publish':\n"
            "    sys.exit(2)\n"
            "output = pathlib.Path(args[args.index('-o') + 1])\n"
            "output.mkdir(parents=True, exist_ok=True)\n"
            "for name in ('SteamService', 'libcoreclr.dylib', 'libhostfxr.dylib', 'nested/dependency.dylib'):\n"
            "    target = output / name\n"
            "    target.parent.mkdir(parents=True, exist_ok=True)\n"
            "    shutil.copyfile('/usr/bin/true', target)\n"
            "    target.chmod(0o755 if name == 'SteamService' else 0o600)\n"
            "for name in ('SteamService.dll', 'SteamKit2.dll', 'SteamService.deps.json'):\n"
            "    target = output / name\n"
            "    target.write_text('fixture resource')\n"
            "    target.chmod(0o755)\n"
        )
        self.publisher.chmod(0o755)
        self.env = os.environ.copy()
        for key in ("CONFIGURATION", "MWX_STEAM_HELPER_TIMESTAMP_POLICY",
                    "EXPANDED_CODE_SIGN_IDENTITY", "MWX_TEST_VERIFY_FAIL"):
            self.env.pop(key, None)
        self.env.update(DOTNET=str(self.publisher),
                        MWX_TEST_CODESIGN_LOG=str(self.sign_log),
                        MWX_TEST_DOTNET_LOG=str(self.dotnet_log),
                        MWX_TEST_FILE_LOG=str(self.file_log))

    def run_command(self, args, *, overrides=None):
        environment = self.env | (overrides or {})
        return subprocess.run(args, cwd=self.repo, env=environment, text=True,
                              stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                              timeout=20, check=False)

    def calls(self):
        if not self.sign_log.exists():
            return []
        return [json.loads(line) for line in self.sign_log.read_text().splitlines()]

    def classification_calls(self):
        if not self.file_log.exists():
            return []
        return [json.loads(line) for line in self.file_log.read_text().splitlines()]

    def prepare_payload(self):
        helper = self.folder / "direct helper"
        result = self.run_command([str(self.publisher), "publish", "-o", str(helper)])
        self.assertEqual(result.returncode, 0, result.stdout)
        return helper

    def sign(self, identity=IDENTITY, policy=None):
        helper = self.prepare_payload()
        args = ["/bin/bash", str(self.repo / "script/sign-steam-helper.sh"), str(helper), identity]
        if policy is not None:
            args.append(policy)
        return self.run_command(args), helper

    def publish(self, *, overrides=None):
        output = self.folder / "products/helper"
        output.parent.mkdir(exist_ok=True)
        result = self.run_command(
            ["/bin/bash", str(self.repo / "script/publish-steam-helper.sh"),
             str(output), str(self.folder / "intermediates")],
            overrides={"EXPANDED_CODE_SIGN_IDENTITY": IDENTITY} | (overrides or {}))
        return result, output

    def assert_signing(self, helper, *, timestamp, identity=IDENTITY, options="runtime"):
        classified = self.classification_calls()
        expected_files = {"SteamService", "libcoreclr.dylib", "libhostfxr.dylib",
                          "nested/dependency.dylib", "SteamService.dll", "SteamKit2.dll",
                          "SteamService.deps.json"}
        self.assertEqual(len(classified), len(expected_files), classified)
        self.assertTrue(all(call[:-1] == ["-b"] for call in classified), classified)
        self.assertEqual({Path(call[-1]).relative_to(helper).as_posix() for call in classified},
                         expected_files)
        calls = self.calls()
        self.assertEqual(len(calls), 5, calls)
        nested, apphost, verify = calls[:3], calls[3], calls[4]
        self.assertEqual({Path(call[-1]).relative_to(helper).as_posix() for call in nested},
                         {"libcoreclr.dylib", "libhostfxr.dylib", "nested/dependency.dylib"})
        prefix = ["--force", timestamp, "--options", options, "--sign", identity]
        for call in nested:
            self.assertEqual(call[:-1], prefix)
        entitlements = self.repo / "SteamService/SteamService.entitlements"
        self.assertEqual(apphost, prefix + ["--entitlements", str(entitlements), str(helper / "SteamService")])
        self.assertEqual(verify, ["--verify", "--strict", str(helper / "SteamService")])
        with entitlements.open("rb") as stream:
            self.assertIs(plistlib.load(stream)["com.apple.security.cs.allow-jit"], True)

    def assert_payload_permissions(self, helper):
        native_files = {"SteamService", "libcoreclr.dylib", "libhostfxr.dylib",
                        "nested/dependency.dylib"}
        for path in helper.rglob("*"):
            if path.is_file():
                mode = 0o755 if path.relative_to(helper).as_posix() in native_files else 0o644
                self.assertEqual(path.stat().st_mode & 0o777, mode, path)

    def assert_published(self, result, output, *, timestamp, identity=IDENTITY, options="runtime", configuration="Release"):
        self.assertEqual(result.returncode, 0, result.stdout)
        # The real signer runs in the fresh directory before rsync publication.
        signed_helper = Path(self.calls()[-1][-1]).parent
        self.assert_signing(signed_helper, timestamp=timestamp, identity=identity, options=options)
        self.assertNotEqual(signed_helper, output)
        self.assertFalse(signed_helper.exists())
        self.assertTrue((output / "SteamService").is_file())
        self.assert_payload_permissions(output)
        dotnet = [json.loads(line) for line in self.dotnet_log.read_text().splitlines()]
        self.assertEqual([args[0] for args in dotnet], ["restore", "publish"])
        self.assertIn("--locked-mode", dotnet[0])
        self.assertIn("--no-restore", dotnet[1])
        self.assertEqual(dotnet[1][dotnet[1].index("-c") + 1], configuration)
        self.assertIn("-p:TargetName=SteamService", dotnet[1])
        self.assertEqual(list(output.parent.glob(".mwx-steam-publish.*")), [])

    def test_direct_real_identity_defaults_to_required_timestamp(self):
        result, helper = self.sign()
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assert_signing(helper, timestamp="--timestamp")
        self.assert_payload_permissions(helper)

    def test_direct_none_preserves_real_identity_runtime_and_jit(self):
        result, helper = self.sign(policy="none")
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assert_signing(helper, timestamp="--timestamp=none")

    def test_adhoc_never_requests_timestamp_or_hardened_runtime(self):
        for policy in (None, "required", "none"):
            with self.subTest(policy=policy):
                self.sign_log.unlink(missing_ok=True)
                self.file_log.unlink(missing_ok=True)
                result, helper = self.sign(identity="-", policy=policy)
                self.assertEqual(result.returncode, 0, result.stdout)
                self.assert_signing(helper, timestamp="--timestamp=none", identity="-", options="0")

    def test_invalid_direct_policy_fails_before_codesign(self):
        result, _ = self.sign(policy="optional")
        self.assertEqual(result.returncode, 2, result.stdout)
        self.assertIn("Invalid timestamp policy", result.stdout)
        self.assertEqual(self.calls(), [])
        self.assertEqual(self.classification_calls(), [])

    def test_publish_debug_forces_no_timestamp(self):
        result, output = self.publish(overrides={"CONFIGURATION": "Debug",
                                                "MWX_STEAM_HELPER_TIMESTAMP_POLICY": "required"})
        self.assert_published(result, output, timestamp="--timestamp=none", configuration="Debug")

    def test_publish_release_defaults_to_required_timestamp(self):
        result, output = self.publish(overrides={"CONFIGURATION": "Release"})
        self.assert_published(result, output, timestamp="--timestamp")

    def test_publish_without_configuration_defaults_to_required_timestamp(self):
        result, output = self.publish()
        self.assert_published(result, output, timestamp="--timestamp")

    def test_publish_empty_identity_selects_adhoc_without_timestamp(self):
        result, output = self.publish(overrides={"CONFIGURATION": "Release",
                                                "EXPANDED_CODE_SIGN_IDENTITY": ""})
        self.assert_published(result, output, timestamp="--timestamp=none", identity="-", options="0")

    def test_publish_diagnostic_xcconfig_explicit_policy(self):
        config = (ROOT / "script/scene_diagnostic_build.xcconfig").read_text()
        policy = re.findall(r"^MWX_STEAM_HELPER_TIMESTAMP_POLICY\s*=\s*(\w+)\s*$", config, re.MULTILINE)
        self.assertEqual(policy, ["none"])
        result, output = self.publish(overrides={"CONFIGURATION": "Release",
                                                "MWX_STEAM_HELPER_TIMESTAMP_POLICY": policy[0]})
        self.assert_published(result, output, timestamp="--timestamp=none")

    def test_invalid_publish_policy_does_not_publish_or_sign(self):
        result, output = self.publish(overrides={"CONFIGURATION": "Release",
                                                "MWX_STEAM_HELPER_TIMESTAMP_POLICY": "optional"})
        self.assertEqual(result.returncode, 2, result.stdout)
        self.assertEqual(self.calls(), [])
        self.assertEqual(self.classification_calls(), [])
        self.assertFalse(output.exists())
        self.assertEqual(list(output.parent.glob(".mwx-steam-publish.*")), [])

    def test_strict_verify_failure_preserves_previous_published_output(self):
        output = self.folder / "products/helper"
        output.mkdir(parents=True)
        marker = output / "SteamService.deps.json"
        marker.write_text("previous publication")
        result, output = self.publish(overrides={"CONFIGURATION": "Debug", "MWX_TEST_VERIFY_FAIL": "1"})
        self.assertEqual(result.returncode, 13, result.stdout)
        self.assertEqual(marker.read_text(), "previous publication")
        signed_helper = Path(self.calls()[-1][-1]).parent
        self.assert_signing(signed_helper, timestamp="--timestamp=none")
        self.assertFalse(signed_helper.exists())
        self.assertEqual(list(output.parent.glob(".mwx-steam-publish.*")), [])


if __name__ == "__main__":
    unittest.main()
