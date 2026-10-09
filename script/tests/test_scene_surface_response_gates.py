"""Shared surface math selects its real consumers and cannot hide header debt."""
import unittest

from script import verify_scene_change as verify
from script.tests.test_verify_scene_change import arguments


class SceneSurfaceResponseGateTests(unittest.TestCase):
    def setUp(self):
        self.registry = verify.load_registry()
        self.available = [p.stem for p in (verify.ROOT / 'script/tests').glob('test_*.py')]

    def test_shared_header_selects_only_existing_surface_consumer_gates(self):
        path = 'MyWallpaperX/Core/SteamWorkshopScene/Rendering/Composition/SceneSurfaceResponse.metalh'
        expected = {'test_scene_pbr_scalar', 'test_scene_authored_normal',
                    'test_scene_lit_image_layer', 'test_scene_static_model_emission'}
        report = verify.product_test_mapping([path], self.registry, self.available)
        self.assertEqual(report['product_paths'], [path])
        self.assertEqual(report['mapped_paths'], [path])
        self.assertEqual(report['unmapped_paths'], [])
        self.assertEqual(set(report['mappings'][0]['selected_modules']), expected)
        gates, _ = verify.build_plan([path], arguments(phase='inner'), self.registry)
        self.assertNotIn('unmapped-change', [g.gate_id for g in gates])
        command = next(g.command for g in gates if g.gate_id == 'focused-tests')
        modules = {command[i+1] for i, value in enumerate(command) if value == '--module'}
        self.assertEqual(modules, expected)
        self.assertNotIn('--keyword', command)

    def test_material_value_owner_selects_copy_and_live_value_consumers(self):
        path = 'MyWallpaperX/Core/SteamWorkshopScene/Rendering/Metal/SceneStaticModelMaterial.swift'
        modules, _, _ = verify.mapped_tests([path], self.registry)
        self.assertTrue({'test_scene_static_model_pipeline', 'test_scene_model_material_scripts'} <= modules)

    def test_unregistered_metal_header_remains_visible_and_blocks_inner(self):
        path = 'MyWallpaperX/Core/SteamWorkshopScene/Rendering/Composition/UnmappedSurfaceFixture.metalh'
        report = verify.product_test_mapping([path], self.registry, self.available)
        self.assertEqual(report['product_paths'], [path])
        self.assertEqual(report['unmapped_paths'], [path])
        gates, _ = verify.build_plan([path], arguments(phase='inner'), self.registry)
        gate = next(g for g in gates if g.gate_id == 'unmapped-change')
        self.assertEqual(gate.status, 'blocked')
        self.assertIn(path, gate.unresolved)
