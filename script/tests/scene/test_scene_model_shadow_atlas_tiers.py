"""Verify real map dimensions, fallback, and use through the model-shadow frame owner."""
from pathlib import Path
import unittest

from script.tests.scene.test_scene_directional_shadow_frame_owner import (
    SCENE, SHELL, SOURCES, UNUSED_ORDERED_SUPPORT, pool_fixture, shadow_fixture,
)


def model_shadow_density_cases():
    directional = [{'kind': 'directional', 'id': 101}]
    four = [{'kind': 'directional', 'id': i} for i in [101, 102, 103, 104]]
    rows = [dict(name=f'extent-{width}', width=width, height=64 if width == 64 else 8,
                 budgetBytes=384 * 1024 * 1024, lights=directional)
            for width in [64, 1024, 1025, 2048, 2049, 4096]]
    rows += [dict(name='low-small-pass', width=64, height=64, directionalLimit=512,
                  budgetBytes=384 * 1024 * 1024, lights=directional),
             dict(name='high-fit-sized', width=2048, height=8, directionalLimit=2048,
                  budgetBytes=384 * 1024 * 1024, lights=directional),
             dict(name='no-authored-caster', width=64, height=64, caster=False,
                  budgetBytes=384 * 1024 * 1024, lights=directional),
             dict(name='legacy-generated', width=64, height=64, legacy=True,
                  budgetBytes=384 * 1024 * 1024, lights=directional),
             dict(name='generated-unbound', width=64, height=64, unbindLights=True,
                  budgetBytes=384 * 1024 * 1024, lights=directional),
             dict(name='height-dominant', width=8, height=1025,
                  budgetBytes=384 * 1024 * 1024, lights=directional),
             dict(name='renamed-extent-2049', width=2049, height=8, layerID=8113,
                  materialPath='surfaces/Π renamed finish',
                  budgetBytes=384 * 1024 * 1024, lights=directional)]
    rows += [dict(name=f'four-{budget}-{cap}', width=2049, height=8,
                  budgetBytes=budget * 1024 * 1024, lights=four, directionalLimit=cap)
             for budget, cap in [(16, 4096), (12, 4096), (384, 4096), (16, 2048), (3, 512)]]
    mixed = dict(width=2049, height=8, budgetBytes=384 * 1024 * 1024,
                  lights=[{'kind': kind, 'id': i} for kind, i in
                          [('directional', 101), ('invalid-spot', 102),
                           ('point', 103), ('spot', 104)]])
    rows += [dict(name='no-directional-influence', width=64, height=64, disjointCaster=True,
                  budgetBytes=384 * 1024 * 1024, lights=directional),
             dict(mixed, name='mixed-no-directional-influence', disjointCaster=True)]
    rows += [dict(mixed, name=f'{tier}-mixed-with-spot-gap', directionalLimit=cap)
             for tier, cap in [('ultra', 4096), ('high', 2048), ('medium', 1024), ('low', 512), ('disabled', None)]]
    rows.append(dict(name='unlit-large-pass', width=4096, height=8, lit=False,
                     budgetBytes=384 * 1024 * 1024, lights=directional))
    return rows


class SceneDirectionalShadowDensityTests(unittest.TestCase):
    """Real Frame/pool outputs; typed lights do not qualify authored light selection."""

    @classmethod
    def setUpClass(cls):
        fixture = Path(__file__).resolve().parents[1] / 'fixtures' / 'SceneDirectionalShadowDensityChecks.swift'
        support = (pool_fixture.HARNESS.split('@main', 1)[0] + SHELL
                   + UNUSED_ORDERED_SUPPORT + fixture.read_text())
        cls.cases = model_shadow_density_cases()
        report = shadow_fixture.run_swift(SOURCES, support, label='shadow-density',
                    metal_sources=[SCENE/'Rendering/Composition/SceneStaticModel.metal'],
                    input_value=cls.cases, swift_flags=('-DDEBUG',))
        cls.rows = {row['name']: row for row in report['rows']}

    def assert_healthy_color(self, row):
        self.assertTrue(row['finished'] and row['completed'], row)
        self.assertGreater(max(row['colorRGBA'][:3]), 0, row)
        self.assertEqual(row['colorRGBA'][3], 255, row)

    def assert_maps(self, row, expected):
        actual = [(m['lightID'], m['slots'], m['width'], m['height']) for m in row['maps']]
        self.assertEqual(actual, expected, row)

    def test_actual_receiver_pass_extent_selects_literal_shadow_sizes(self):
        for name, edge in [('extent-64', 1024), ('extent-1024', 1024),
                           ('extent-1025', 2048), ('extent-2048', 2048),
                           ('extent-2049', 4096), ('extent-4096', 4096),
                           ('height-dominant', 2048), ('renamed-extent-2049', 4096)]:
            with self.subTest(case=name):
                row = self.rows[name]
                self.assert_healthy_color(row)
                self.assertTrue(row['colorEncodedLit'], row)
                self.assert_maps(row, [(101, [0], edge, edge)])
                supplied = next(case for case in self.cases if case['name'] == name)
                self.assertEqual(row['physicalExtent'], [supplied['width'], supplied['height']])
        self.assertEqual(self.rows['renamed-extent-2049']['maps'], self.rows['extent-2049']['maps'])
        self.assertEqual(self.rows['renamed-extent-2049']['colorRGBA'], self.rows['extent-2049']['colorRGBA'])

    def test_budget_preserves_lights_at_their_tier_or_its_fallback(self):
        for name, count, edge in [('four-16-4096', 4, 1024), ('four-12-4096', 3, 1024), ('four-384-4096', 4, 4096),
                                  ('four-16-2048', 4, 1024), ('four-3-512', 3, 512)]:
            with self.subTest(case=name):
                row = self.rows[name]
                self.assert_healthy_color(row)
                self.assertTrue(row['colorEncodedLit'], row)
                self.assert_maps(row, [(101 + slot, [slot], edge, edge) for slot in range(count)])
                reference = 'low-mixed-with-spot-gap' if edge == 512 else 'four-384-4096'
                self.assertEqual([m['matrix'] for m in row['maps']], [self.rows[reference]['maps'][0]['matrix']] * count)

    def test_mixed_projection_sizes_keep_original_slots_after_invalid_spot(self):
        ultra = self.rows['ultra-mixed-with-spot-gap']['maps'][0]['matrix']
        tiers = [('ultra', 4096, 1024), ('high', 2048, 1024), ('medium', 1024, 1024), ('low', 512, 512)]
        for tier, edge, local in tiers:
            row = self.rows[f'{tier}-mixed-with-spot-gap']
            self.assert_healthy_color(row)
            self.assertTrue(row['colorEncodedLit'], row)
            self.assert_maps(row, [(101, [0], edge, edge), (103, [2], 3 * local, 2 * local), (104, [3], local, local)])
            matrix = row['maps'][0]['matrix']
            if tier == 'low':
                self.assertEqual(matrix[2::4], ultra[2::4], row)
                offsets = [value * 256 for value in matrix[12:14]]
                self.assertEqual(offsets, [round(value) for value in offsets], row)
            else:
                self.assertEqual(matrix, ultra, row)
        disabled = self.rows['disabled-mixed-with-spot-gap']
        self.assert_healthy_color(disabled)
        self.assert_maps(disabled, [])
        self.assertEqual(disabled['shadowResidentBytes'], 0)
        self.assertTrue(disabled['shadowPipelinesSkipped'])

    def test_shadow_use_observes_bound_faces_and_limits(self):
        for name, expected in [
            ('extent-64', [('directional', 1024, 'receiverExtent')]),
            ('extent-2049', [('directional', 4096, None)]),
            ('low-small-pass', [('directional', 512, None)]),
            ('high-fit-sized', [('directional', 2048, 'receiverExtent')]),
            ('medium-mixed-with-spot-gap', [('directional', 1024, None),
                ('point', 1024, 'lightFamily'), ('spot', 1024, 'lightFamily'), ('spot', None, None)]),
            ('four-12-4096', [('directional', 1024, 'reduced')] * 3 + [('directional', None, None)]),
            ('ultra-mixed-with-spot-gap', [('directional', 4096, None),
                ('point', 1024, 'lightFamily'), ('spot', 1024, 'lightFamily'), ('spot', None, None)]),
            ('mixed-no-directional-influence',
                [('point', 1024, 'lightFamily'), ('spot', 1024, 'lightFamily'), ('spot', None, None)]),
        ]:
            with self.subTest(case=name):
                row = self.rows[name]
                self.assert_healthy_color(row)
                actual = row['shadowUse']
                self.assertEqual(actual['state'], 'active', row)
                self.assertEqual([(m['family'], m['face'], m['limit']) for m in actual['maps']], expected, row)
        unbound = self.rows['generated-unbound']
        self.assert_healthy_color(unbound)
        self.assert_maps(unbound, [(101, [0], 1024, 1024)])
        self.assertEqual(unbound['shadowUse'], {'state': 'unavailable'}, unbound)
        self.assert_maps(self.rows['legacy-generated'], [(101, [0], 1024, 1024)])
        self.assert_maps(self.rows['no-authored-caster'], [])
        self.assert_maps(self.rows['no-directional-influence'], [])
        for name in ('legacy-generated', 'no-authored-caster', 'no-directional-influence', 'unlit-large-pass'):
            self.assert_healthy_color(self.rows[name])
            self.assertEqual(self.rows[name]['shadowUse'], {'state': 'noReceiver'})

    def test_no_lit_receiver_keeps_color_without_directional_target(self):
        row = self.rows['unlit-large-pass']
        self.assert_healthy_color(row)
        self.assertFalse(row['colorEncodedLit'], row)
        self.assertEqual(row['maps'], [], row)
        self.assertEqual(row['shadowResidentBytes'], 0, row)
