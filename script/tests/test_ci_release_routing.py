"""CI selects real fixture consumers and keeps unknown inputs fail-closed."""
from pathlib import Path
from types import SimpleNamespace
import sys
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'script'))
import verify_scene_change as verify
import run_scene_tests as runner
from web_wallpaper_benchmark import load_sample_matrix


class CIReleaseRoutingTests(unittest.TestCase):
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
