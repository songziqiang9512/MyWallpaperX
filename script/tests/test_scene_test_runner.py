#!/usr/bin/env python3

"""Tests for the Scene-aware module scheduler."""

from __future__ import annotations

import argparse
import ast
import contextlib
import io
import sys
import tempfile
import time
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest import mock


SCRIPT_DIRECTORY = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SCRIPT_DIRECTORY))

import run_scene_tests as runner


AVAILABLE_MODULES = [
    "test_scene_audio_spectrum_input",
    "test_scene_particle_runtime",
    "test_system_audio_spectrum",
    "test_web_runtime_switch_benchmark",
]


def missing_local_test_imports(directory: Path) -> list[str]:
    """Check local module paths without importing or executing test consumers.

    Namespace-package imports name child modules; imports from a .py module
    name attributes, whose behavior remains the consumer test's responsibility.
    """
    roots = {path.stem for path in directory.glob('*.py')}
    roots.update(path.name for path in directory.iterdir() if path.is_dir())
    missing = []
    for file in directory.rglob('*.py'):
        for node in ast.walk(ast.parse(file.read_text(encoding='utf-8'))):
            names = []
            if isinstance(node, ast.Import):
                names = [alias.name for alias in node.names]
            elif isinstance(node, ast.ImportFrom):
                module = node.module or ''
                if node.level:
                    parent = ['script', 'tests', *file.relative_to(directory).parts[:-1]]
                    module = '.'.join(parent[:len(parent) - node.level + 1]
                                      + (module.split('.') if module else []))
                names = [module]
            for name in names:
                if name == 'script.tests':
                    parts = []
                elif name.startswith('script.tests.'):
                    parts = name.split('.')[2:]
                elif name.split('.')[0] in roots or name.startswith('test_'):
                    parts = name.split('.')
                else:
                    continue
                target = directory.joinpath(*parts)
                candidates = [target]
                if (isinstance(node, ast.ImportFrom) and target.is_dir()
                        and not (target / '__init__.py').is_file()):
                    candidates.extend(target / alias.name for alias in node.names
                                      if alias.name != '*')
                for candidate in candidates:
                    if not candidate.with_suffix('.py').is_file() and not candidate.is_dir():
                        missing.append(f'{file.relative_to(directory)}: '
                                       f'{candidate.relative_to(directory)}')
    return sorted(set(missing))


class RunSceneTestsSelectionTests(unittest.TestCase):
    def test_release_scope_is_bounded_and_requires_every_declared_module(self) -> None:
        available = sorted(runner.RELEASE_MODULES | {"test_scene_unrelated_effect"})
        selected = runner.discover_modules(available, scope="release")
        self.assertEqual(set(selected), {f"script.tests.{name}" for name in runner.RELEASE_MODULES})
        self.assertNotIn("script.tests.test_scene_unrelated_effect", selected)
        with self.assertRaisesRegex(ValueError, "missing release test"):
            runner.discover_modules(available[1:], scope="release")

    def test_release_profile_references_real_test_modules(self) -> None:
        available = [path.stem for path in runner.TESTS_DIRECTORY.glob("test_*.py")]
        self.assertTrue(runner.discover_modules(available, scope="release"))

    def test_test_module_imports_and_declared_release_selection_still_exist(self) -> None:
        self.assertEqual(missing_local_test_imports(runner.TESTS_DIRECTORY), [])

    def test_local_import_audit_resolves_fixture_children_and_relative_support(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            (directory / 'fixtures').mkdir()
            oracle = directory / 'fixtures/oracle.py'
            support = directory / 'support.py'
            oracle.write_text('from ..support import value\n')
            support.write_text('value = 1\n')
            consumer = directory / 'test_consumer.py'
            imports = [
                'import script.tests.fixtures.oracle',
                'from script.tests.fixtures.oracle import value',
                'from script.tests.fixtures import oracle',
                'from .fixtures import oracle',
                'from .fixtures.oracle import value',
                'from . import support',
                'from .support import value',
            ]
            consumer.write_text('\n'.join(imports) + '\n')
            self.assertEqual(missing_local_test_imports(directory), [])
            oracle.unlink()
            for statement in imports[:5]:
                with self.subTest(statement=statement):
                    consumer.write_text(statement + '\n')
                    self.assertEqual(missing_local_test_imports(directory),
                                     ['test_consumer.py: fixtures/oracle'])
            oracle.write_text('from ..support import value\n')
            consumer.write_text('\n'.join(imports[-2:]) + '\n')
            support.unlink()
            self.assertEqual(missing_local_test_imports(directory),
                             ['fixtures/oracle.py: support', 'test_consumer.py: support'])

    def test_default_scope_preserves_all_module_selection(self) -> None:
        self.assertEqual(
            runner.discover_modules(AVAILABLE_MODULES),
            [
                "script.tests.test_scene_audio_spectrum_input",
                "script.tests.test_scene_particle_runtime",
                "script.tests.test_system_audio_spectrum",
                "script.tests.test_web_runtime_switch_benchmark",
            ],
        )

    def test_scene_scope_selects_only_scene_prefixed_modules(self) -> None:
        self.assertEqual(
            runner.discover_modules(AVAILABLE_MODULES, scope="scene"),
            [
                "script.tests.test_scene_audio_spectrum_input",
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

    def test_requested_modules_with_keyword_add_exact_non_scene_dependencies(self) -> None:
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

    def test_requested_modules_without_keyword_are_exact(self) -> None:
        self.assertEqual(
            runner.discover_modules(
                AVAILABLE_MODULES,
                scope="scene",
                requested_modules=[
                    "test_scene_audio_spectrum_input",
                    "test_system_audio_spectrum",
                ],
            ),
            [
                "script.tests.test_scene_audio_spectrum_input",
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

    def test_fail_fast_reports_failure_and_cancels_unstarted_work(self) -> None:
        modules = [f"script.tests.test_case_{index}" for index in range(30)]
        def execute(module):
            time.sleep(0.01)
            return module, 1 if module == modules[0] else 0, 0.01, "actionable failure"
        output = io.StringIO()
        with mock.patch.object(runner, "discover_modules", return_value=modules), \
             mock.patch.object(runner, "run_module", side_effect=execute) as run, \
             contextlib.redirect_stdout(output), contextlib.redirect_stderr(output):
            self.assertEqual(runner.main(["--fail-fast", "--jobs", "1"]), 1)
        self.assertLess(run.call_count, len(modules))
        self.assertIn("actionable failure", output.getvalue())
        self.assertNotIn("ALL OK", output.getvalue())

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
