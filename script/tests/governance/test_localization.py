from __future__ import annotations

import json
from pathlib import Path
import shutil
import subprocess
import sys
from tempfile import TemporaryDirectory
import unittest

from script.governance import check_localization as checker


class LocalizationTests(unittest.TestCase):
    def test_staged_source_and_catalog_are_the_only_commit_inputs(self):
        with TemporaryDirectory() as directory:
            root = Path(directory)
            tool = root / "script/governance/check_localization.py"
            tool.parent.mkdir(parents=True)
            shutil.copyfile(checker.__file__, tool)

            def git(*args):
                subprocess.run(["git", *args], cwd=root, capture_output=True, check=True)

            git("init", "-q")
            for target, path in checker.CATALOGS.items():
                (root / path).parent.mkdir(parents=True)
                (root / path).write_text('{"sourceLanguage":"en","strings":{}}')
            git("add", "MyWallpaperX", "ScreenSaverSources")
            git("-c", "core.hooksPath=/dev/null", "-c", "user.name=Fixture",
                "-c", "user.email=test@example.invalid", "commit", "-qm", "base")

            source = root / "ScreenSaverSources/Probe.swift"
            source.write_text(r'''
                // String(localized: "Ignored")
                let name = String(
                    localized: "About \(displayName(fallback: "app"))\nWelcome")
            ''')
            git("add", "ScreenSaverSources/Probe.swift")
            source.write_text('let name = String(localized: "Unstaged lookup")')

            path = root / checker.CATALOGS["ScreenSaverSources"]
            key = "About %@\nWelcome"
            localizations = {
                language: {"stringUnit": {"state": "translated", "value": key}}
                for language in checker.PLURAL_FORMS
            }
            path.write_text(json.dumps({"sourceLanguage": "en", "strings": {key: {"localizations": localizations}}}))
            command = [sys.executable, "-B", str(tool), "--changed"]
            unstaged = subprocess.run(command, cwd=root, capture_output=True, text=True)
            self.assertEqual(unstaged.returncode, 1)
            self.assertIn("About %@", unstaged.stderr)
            git("add", str(checker.CATALOGS["ScreenSaverSources"]))
            staged = subprocess.run(command, cwd=root, capture_output=True, text=True)
            self.assertEqual(staged.returncode, 0, staged.stderr)

            path.write_text('{"sourceLanguage":"en","strings":{}}')
            git("add", str(checker.CATALOGS["ScreenSaverSources"]))
            missing = subprocess.run(command, cwd=root, capture_output=True, text=True)
            self.assertEqual(missing.returncode, 1)
            self.assertIn("About %@", missing.stderr)

    def test_source_lookup_uses_interpolation_positions_and_nested_calls(self):
        keys = checker.source_keys(r'''
            let title = String(localized: /* translator /* nested */ note */
                #"Open \#(String(localized: "Gallery"))"#)
            let count = String(localized: "Items: \(Int(4))")
            let caption = "String(localized: \"Ignored\")"
            let multiline = String(localized: """
                    Hello \
                    world
                """)
        ''')
        entries = {"Open %@", "Gallery", "Items: %lld", "    Hello     world"}
        self.assertEqual(checker.source_catalog_errors(keys, entries), ([], entries))
        errors, _ = checker.source_catalog_errors(keys, entries - {"Items: %lld"} | {"%lld: Items"})
        self.assertEqual(len(errors), 1)
        self.assertIn("Items: %@", errors[0])

    def test_reordering_requires_the_original_argument_positions(self):
        key = "Count %lld Recent %@"
        units = {
            language: {"stringUnit": {"state": "translated", "value": key}}
            for language in checker.PLURAL_FORMS
        }
        catalog = {"sourceLanguage": "en", "strings": {key: {"localizations": units}}}
        units["de"]["stringUnit"]["value"] = "%@ zuletzt %lld"
        self.assertEqual(len(checker.catalog_errors(catalog)), 1)
        units["de"]["stringUnit"]["value"] = "%2$@ zuletzt %1$lld"
        self.assertEqual(checker.catalog_errors(catalog), [])
