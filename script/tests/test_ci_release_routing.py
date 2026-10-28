"""CI selects real fixture consumers and keeps unknown inputs fail-closed."""
from pathlib import Path
from types import SimpleNamespace
import os
import subprocess
import sys
import tempfile
import textwrap
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'script'))
import verify_scene_change as verify
import run_scene_tests as runner
from web_wallpaper_benchmark import load_sample_matrix


def workflow_shell(name):
    workflow = (ROOT / '.github/workflows/ci.yml').read_text()
    step = workflow.split(f'      - name: {name}\n', 1)[1].split('      - name:', 1)[0]
    return textwrap.dedent(step.split('        run: |\n', 1)[1])


class CIReleaseRoutingTests(unittest.TestCase):
    def run_validation_range(self, *, event, before, last_success='', ancestor='',
                             pr_base='', requested_base=''):
        with tempfile.TemporaryDirectory(prefix='mwx-ci-base-test-') as temporary:
            root = Path(temporary)
            binaries = root / 'bin'
            binaries.mkdir()
            env_file = root / 'github-env'
            call_log = root / 'calls'
            gh = binaries / 'gh'
            gh.write_text('''#!/bin/bash
printf '%s\\n' "$*" >> "$CALL_LOG"
printf '%s' "$LAST_SUCCESS_SHA"
''')
            git = binaries / 'git'
            git.write_text('''#!/bin/bash
if [[ "$1" == merge-base && "$2" == --is-ancestor ]]; then
  [[ "$3" == "$ANCESTOR_SHA" ]]
  exit $?
fi
echo "unexpected git invocation: $*" >&2
exit 97
''')
            gh.chmod(0o755)
            git.chmod(0o755)
            environment = dict(
                os.environ,
                PATH=f'{binaries}:{os.environ["PATH"]}',
                EVENT_NAME=event,
                EVENT_BEFORE=before,
                PR_BASE_SHA=pr_base,
                REQUESTED_BASE=requested_base,
                REF_NAME='main',
                GH_TOKEN='test-token',
                GITHUB_ENV=str(env_file),
                RUNNER_TEMP=str(root),
                LAST_SUCCESS_SHA=last_success,
                ANCESTOR_SHA=ancestor,
                CALL_LOG=str(call_log),
            )
            result = subprocess.run(
                ['/bin/bash', '-e', '-c', workflow_shell('Resolve validation range')],
                cwd=ROOT,
                env=environment,
                capture_output=True,
                text=True,
            )
            self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
            values = dict(
                line.split('=', 1)
                for line in env_file.read_text().splitlines()
                if '=' in line
            )
            calls = call_log.read_text().splitlines() if call_log.exists() else []
            return values['BASE_REF'], calls, result.stdout

    def test_push_after_failure_accumulates_then_successful_push_narrows(self):
        failed_a = 'a' * 40
        last_green = 'g' * 40
        base_for_b, calls, output = self.run_validation_range(
            event='push', before=failed_a, last_success=last_green, ancestor=last_green,
        )
        self.assertEqual(base_for_b, last_green)
        self.assertIn('accumulated changes since last successful push', output)
        self.assertIn('--workflow ci.yml --branch main --event push --status success', calls[0])

        successful_b = 'b' * 40
        base_for_c, _, _ = self.run_validation_range(
            event='push', before=successful_b, last_success=successful_b, ancestor=successful_b,
        )
        self.assertEqual(base_for_c, successful_b)

    def test_push_without_success_or_with_non_ancestor_uses_event_base(self):
        event_base = 'e' * 40
        no_success, calls, _ = self.run_validation_range(event='push', before=event_base)
        self.assertEqual(no_success, event_base)
        self.assertEqual(len(calls), 1)

        non_ancestor, _, output = self.run_validation_range(
            event='push', before=event_base, last_success='x' * 40, ancestor='different',
        )
        self.assertEqual(non_ancestor, event_base)
        self.assertIn('not an ancestor', output)

    def test_pull_request_and_manual_dispatch_keep_their_requested_bases(self):
        pr_base = 'p' * 40
        resolved_pr, pr_calls, _ = self.run_validation_range(
            event='pull_request', before='e' * 40, pr_base=pr_base,
            last_success='s' * 40, ancestor='s' * 40,
        )
        self.assertEqual(resolved_pr, pr_base)
        self.assertEqual(pr_calls, [])

        manual_base = 'm' * 40
        resolved_manual, manual_calls, _ = self.run_validation_range(
            event='workflow_dispatch', before='e' * 40, requested_base=manual_base,
            last_success='s' * 40, ancestor='s' * 40,
        )
        self.assertEqual(resolved_manual, manual_base)
        self.assertEqual(manual_calls, [])

    def test_changed_fixture_selects_its_executable_consumer(self):
        registry = verify.load_registry()
        cases = {
            'script/sign-steam-helper.sh': 'test_steam_helper_signing',
            'script/scene_diagnostic_build.xcconfig': 'test_steam_helper_signing',
            'script/playback_process_isolation_benchmark.py': 'test_playback_process_isolation',
            'script/tests/fixtures/SceneAudioSpectrumInputHarness.swift': 'test_scene_audio_spectrum_input',
            'script/tests/fixtures/SceneDefault2DCameraInputChecks.swift': 'test_scene_default_2d_camera_inputs',
            'script/tests/fixtures/SceneNamedModelShadowOrderedHarness.swift': 'test_scene_named_model_shadow',
            'script/tests/fixtures/SceneParticleCameraRenderingHarness.swift': 'test_scene_particle_rendering',
            'script/tests/fixtures/SceneDependencyRenderPlanTestSupport.swift': 'test_scene_dependency_render_plan',
            'script/tests/fixtures/scene_timeline_combined_cases.py': 'test_scene_timeline_target_compiler',
            'script/tests/fixtures/variant_analysis_v22/multi-seven.json': 'test_scene_persistent_cache_behavior',
        }
        for path, consumer in cases.items():
            with self.subTest(path=path):
                modules, _, _ = verify.mapped_tests([path], registry)
                self.assertIn(consumer, modules)
                self.assertTrue((ROOT / 'script/tests' / (consumer + '.py')).is_file())

    def test_unknown_fixture_is_still_blocked_beside_known_input(self):
        args = SimpleNamespace(base='HEAD', phase='inner', test_scope='changed', ci=True)
        gates, _ = verify.build_plan(
            ['script/sign-steam-helper.sh', 'script/tests/fixtures/UnregisteredFutureChecks.swift'],
            args, verify.load_registry())
        blocked = [gate for gate in gates if gate.status == 'blocked']
        self.assertEqual(len(blocked), 1)
        self.assertEqual(blocked[0].gate_id, 'unmapped-change')
        self.assertIn('UnregisteredFutureChecks.swift', blocked[0].unresolved)

    def test_default_release_scope_includes_signing_and_diagnostic_exclusion(self):
        modules = [p.stem for p in (ROOT / 'script/tests').glob('test_*.py')]
        selected = runner.discover_modules(modules, scope='release')
        for module in ['test_steam_helper_signing', 'test_release_diagnostic_isolation',
                       'test_ci_release_routing']:
            self.assertIn('script.tests.' + module, selected)

    def test_web_matrix_loads_without_private_sample_or_app(self):
        path = ROOT / 'script/web_wallpaper_sample_matrix.json'
        samples, config = load_sample_matrix(path)
        self.assertTrue(samples)
        self.assertEqual(len({sample.id for sample in samples}), len(samples))
        self.assertGreater(config['minimum_sample_duration_seconds'], 0)
        modules, _, _ = verify.mapped_tests([path.relative_to(ROOT).as_posix()], verify.load_registry())
        self.assertIn('test_ci_release_routing', modules)


if __name__ == '__main__':
    unittest.main()
