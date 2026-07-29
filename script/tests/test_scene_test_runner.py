#!/usr/bin/env python3

"""Tests for the Scene-aware module scheduler."""

from __future__ import annotations

import argparse
import contextlib
import io
import sys
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest import mock


SCRIPT_DIRECTORY = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SCRIPT_DIRECTORY))

import run_scene_tests as runner


AVAILABLE_MODULES = [
    "test_scene_audio_response",
    "test_scene_particle_runtime",
    "test_system_audio_spectrum",
    "test_web_runtime_switch_benchmark",
]


class RunSceneTestsSelectionTests(unittest.TestCase):
    def test_default_scope_preserves_all_module_selection(self) -> None:
        self.assertEqual(
            runner.discover_modules(AVAILABLE_MODULES),
            [
                "script.tests.test_scene_audio_response",
                "script.tests.test_scene_particle_runtime",
                "script.tests.test_system_audio_spectrum",
                "script.tests.test_web_runtime_switch_benchmark",
            ],
        )

    def test_scene_scope_selects_only_scene_prefixed_modules(self) -> None:
        self.assertEqual(
            runner.discover_modules(AVAILABLE_MODULES, scope="scene"),
            [
                "script.tests.test_scene_audio_response",
                "script.tests.test_scene_particle_runtime",
            ],
        )

    def test_repeated_keywords_use_or_matching(self) -> None:
        self.assertEqual(
            runner.discover_modules(
                AVAILABLE_MODULES,
                keywords=["particle", "web_runtime"],
            ),
            [
                "script.tests.test_scene_particle_runtime",
                "script.tests.test_web_runtime_switch_benchmark",
            ],
        )

    def test_requested_modules_append_exact_non_scene_dependencies(self) -> None:
        self.assertEqual(
            runner.discover_modules(
                AVAILABLE_MODULES,
                scope="scene",
                keywords=["particle"],
                requested_modules=[
                    "test_system_audio_spectrum",
                    "test_system_audio_spectrum",
                ],
            ),
            [
                "script.tests.test_scene_particle_runtime",
                "script.tests.test_system_audio_spectrum",
            ],
        )

    def test_unknown_requested_module_is_rejected(self) -> None:
        with self.assertRaisesRegex(
            ValueError,
            r"unknown test module\(s\): test_missing",
        ):
            runner.discover_modules(
                AVAILABLE_MODULES,
                requested_modules=["test_missing"],
            )

    def test_empty_keyword_selection_remains_empty(self) -> None:
        self.assertEqual(
            runner.discover_modules(
                AVAILABLE_MODULES,
                scope="scene",
                keywords=["does-not-exist"],
            ),
            [],
        )

    def test_repeated_cli_options_are_preserved_for_selection(self) -> None:
        arguments = runner.parse_arguments(
            [
                "--scope",
                "scene",
                "-k",
                "audio",
                "-k",
                "particle",
                "--module",
                "test_system_audio_spectrum",
                "--module",
                "test_web_runtime_switch_benchmark",
            ]
        )
        self.assertEqual(arguments.scope, "scene")
        self.assertEqual(arguments.keyword, ["audio", "particle"])
        self.assertEqual(
            arguments.module,
            [
                "test_system_audio_spectrum",
                "test_web_runtime_switch_benchmark",
            ],
        )

    def test_invalid_jobs_scope_and_empty_values_are_rejected(self) -> None:
        invalid_arguments = (
            ["--jobs", "0"],
            ["--jobs", "-1"],
            ["--jobs", "invalid"],
            ["--scope", "invalid"],
            ["--keyword", " "],
            ["--module", ""],
        )
        for arguments in invalid_arguments:
            with self.subTest(arguments=arguments):
                with contextlib.redirect_stderr(io.StringIO()):
                    with self.assertRaisesRegex(SystemExit, "2"):
                        runner.parse_arguments(arguments)

    def test_main_rejects_empty_and_unknown_selections_without_running(self) -> None:
        cases = (
            (
                ["--scope", "scene", "-k", "missing"],
                "没有匹配的测试模块",
            ),
            (
                ["--module", "test_missing"],
                "unknown test module",
            ),
        )
        for arguments, message in cases:
            with self.subTest(arguments=arguments):
                error = io.StringIO()
                with contextlib.redirect_stderr(error):
                    self.assertEqual(runner.main(arguments), 2)
                self.assertIn(message, error.getvalue())

    @mock.patch.object(runner.subprocess, "run")
    def test_module_process_disables_bytecode_writes(
        self,
        run: mock.Mock,
    ) -> None:
        run.return_value = SimpleNamespace(
            returncode=0,
            stdout="",
            stderr="",
        )
        module, returncode, _, output = runner.run_module(
            "script.tests.test_scene_test_runner"
        )
        self.assertEqual(module, "script.tests.test_scene_test_runner")
        self.assertEqual(returncode, 0)
        self.assertEqual(output, "")
        self.assertEqual(
            run.call_args.args[0],
            [
                sys.executable,
                "-B",
                "-m",
                "unittest",
                "script.tests.test_scene_test_runner",
            ],
        )


if __name__ == "__main__":
    unittest.main()
