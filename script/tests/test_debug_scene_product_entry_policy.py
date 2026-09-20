from __future__ import annotations

import os
import pwd
import shutil
import subprocess
import tempfile
import textwrap
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
POLICY_SOURCE = ROOT / "MyWallpaperX/App/DebugSceneProductEntryPolicy.swift"


class DebugSceneProductEntryPolicyTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        swiftc = shutil.which("swiftc")
        if swiftc is None:
            raise unittest.SkipTest("swiftc is unavailable")
        cls._temporary_directory = tempfile.TemporaryDirectory()
        cls._root = Path(cls._temporary_directory.name)
        cls._executable = cls._root / "policy-harness"
        harness = cls._root / "PolicyHarness.swift"
        harness.write_text(
            textwrap.dedent(
                """
                import Foundation

                @main
                struct PolicyHarness {
                    static func main() {
                        let arguments = Array(CommandLine.arguments.dropFirst())
                        guard let mode = arguments.first else { exit(64) }
                        switch mode {
                        case "coordinator":
                            let appArguments = Array(arguments.dropFirst())
                            print(DebugSceneProductEntryPolicy
                                .requiresProductCoordinator(arguments: appArguments))
                        case "directory":
                            guard arguments.count == 3 else { exit(64) }
                            let protected = URL(
                                fileURLWithPath: arguments[1],
                                isDirectory: true
                            )
                            let accepted = DebugSceneProductEntryPolicy
                                .isolatedExistingDirectory(
                                    rawPath: arguments[2],
                                    disjointFrom: protected
                                ) != nil
                            print(accepted)
                        case "account-home":
                            guard let home = DebugSceneProductEntryPolicy
                                    .protectedUserHomeURL() else { exit(1) }
                            print(home.path)
                        default:
                            exit(64)
                        }
                    }
                }
                """
            ),
            encoding="utf-8",
        )
        subprocess.run(
            [
                swiftc,
                "-D",
                "DEBUG",
                str(POLICY_SOURCE),
                str(harness),
                "-o",
                str(cls._executable),
            ],
            check=True,
            cwd=ROOT,
            capture_output=True,
            text=True,
        )

    @classmethod
    def tearDownClass(cls) -> None:
        cls._temporary_directory.cleanup()

    def run_policy(self, *arguments: str) -> bool:
        completed = subprocess.run(
            [str(self._executable), *arguments],
            check=True,
            cwd=ROOT,
            capture_output=True,
            text=True,
        )
        return completed.stdout.strip() == "true"

    def test_account_home_ignores_fixed_cfpreferences_home(self) -> None:
        fixed_home = self._root / "fixed-home"
        fixed_home.mkdir()
        environment = os.environ.copy()
        environment["CFFIXED_USER_HOME"] = str(fixed_home)
        completed = subprocess.run(
            [str(self._executable), "account-home"],
            check=True,
            cwd=ROOT,
            env=environment,
            capture_output=True,
            text=True,
        )
        self.assertEqual(
            Path(completed.stdout.strip()).resolve(),
            Path(pwd.getpwuid(os.getuid()).pw_dir).resolve(),
        )
        self.assertNotEqual(
            Path(completed.stdout.strip()).resolve(),
            fixed_home.resolve(),
        )

    def test_only_product_entry_requires_product_coordinator(self) -> None:
        daemon = "--mwx-debug-scene-daemon-client"
        product = "--mwx-debug-scene-product-entry"
        root = ["--mwx-debug-scene-root", "/private/tmp/scene"]
        self.assertFalse(self.run_policy("coordinator", daemon, *root))
        self.assertFalse(self.run_policy("coordinator", product, *root))
        self.assertFalse(self.run_policy("coordinator", daemon, product))
        self.assertTrue(
            self.run_policy("coordinator", daemon, product, *root)
        )

    def test_isolated_directory_rejects_all_protected_root_overlap(self) -> None:
        protected_parent = self._root / "real-library"
        protected = protected_parent / "workshop"
        protected_child = protected / "Scene"
        isolated = self._root / "isolated-workshop"
        protected_child.mkdir(parents=True)
        isolated.mkdir()

        self.assertTrue(
            self.run_policy("directory", str(protected), str(isolated))
        )
        for candidate in (protected_parent, protected, protected_child):
            with self.subTest(candidate=candidate):
                self.assertFalse(
                    self.run_policy(
                        "directory", str(protected), str(candidate)
                    )
                )

    def test_isolated_directory_rejects_missing_file_and_symlink_overlap(self) -> None:
        protected = self._root / "protected"
        protected.mkdir()
        ordinary_file = self._root / "not-a-directory"
        ordinary_file.write_text("x", encoding="utf-8")
        alias = self._root / "protected-alias"
        alias.symlink_to(protected, target_is_directory=True)

        for candidate in (self._root / "missing", ordinary_file, alias):
            with self.subTest(candidate=candidate):
                self.assertFalse(
                    self.run_policy(
                        "directory", str(protected), str(candidate)
                    )
                )


if __name__ == "__main__":
    unittest.main()
