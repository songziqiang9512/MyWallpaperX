"""Directional raster coverage against independent exact triangle/ray geometry."""
import copy
from fractions import Fraction
import hashlib
import json
import os
from pathlib import Path
import struct
import unittest

from script.tests import test_scene_directional_shadow as shared
from script.tests import test_scene_static_model_pipeline as model

FIXTURE = Path(__file__).with_name('fixtures') / 'SceneDirectionalShadowPrimitiveCoverageChecks.swift'
DEPTH_TOLERANCE = 2e-5


def vectors():
    result = []

    def add(name, positions, indices=None, **extra):
        item = dict(name=name, positions=positions, indices=indices or [0, 1, 2],
                    materialPath='materials/primitive.json', **extra)
        result.append(item)
        return item

    for width in [.001, .002, .004, .008, .016, .032, .1, 1.0]:
        for phase in [-.001, 0, .001]:
            for third_depth in [.45, .55]:
                add(f'narrow-w{width}-p{phase}-z{third_depth}', [
                    [8.5+phase, 8.2, .45], [8.5+phase+width, 8.5, .55],
                    [8.5+phase, 8.8, third_depth]])
    add('large-inside', [[5, 5, .4], [12, 5, .6], [8, 12, .5]])
    add('large-outside', [[3, 3, .4], [6, 3, .6], [4, 6, .5]])
    for phase in [-.04, -.02, 0, .02, .04, .12]:
        add(f'flat-phase{phase}', [[8.44+phase, 8.2, .5],
            [8.56+phase, 8.2, .5], [8.5+phase, 8.8, .5]])

    quad = [[6, 6, .4], [11, 6, .6], [11, 11, .7], [6, 11, .5]]
    add('shared-edge', quad, [0, 1, 2, 0, 2, 3])
    # Each corner of the first indexed triangle has vertex_id % 3 == 0.
    slots = [quad[0], quad[3], quad[3], quad[1], quad[3], quad[3], quad[2]]
    indexed = add('indexed-共享', slots, [0, 3, 6, 0, 6, 1])
    renamed = copy.deepcopy(indexed)
    renamed.update(name='renamed-Ω', materialPath='coatings/独立-surface.json')
    result.append(renamed)
    translated = copy.deepcopy(renamed)
    translated.update(name='translated-equivalent', worldShift=[16, -8, 4])
    result.append(translated)

    tetra = [[8.501, 8.2, .45], [8.502, 8.5, .55], [8.501, 8.8, .45],
             [8.501+1/3000, 8.55, .45+.1/3+.01]]
    faces = [0, 1, 2, 0, 3, 1, 1, 3, 2, 2, 3, 0]
    add('tetra-outside', tetra, faces)
    inside = [[p[0]-.0015, p[1], p[2]] for p in tetra]
    add('tetra-narrow-inside', inside, faces)
    add('tetra-stable-inside', [[8.5+(p[0]-8.5)*100, p[1], p[2]] for p in inside], faces)
    return result


def _float32(value):
    return Fraction.from_float(struct.unpack('<f', struct.pack('<f', value))[0])


def submitted_vertices(item):
    # Reproduce only the literal fixture input projection/Float32 storage.
    return [[8*(_float32(p[0]/8-1)+1), 8*(1-_float32(1-p[1]/8)), _float32(p[2])]
            for p in item['positions']]


def _edge(a, b, p):
    return (b[0]-a[0])*(p[1]-a[1]) - (b[1]-a[1])*(p[0]-a[0])


def triangle_ray(triangle, point):
    """Exact edge containment, then axial ray/3D-plane intersection; no derivatives."""
    a, b, c = triangle
    area = _edge(a, b, c)
    if not area:
        return None
    edges = [_edge(triangle[i], triangle[(i+1) % 3], point) for i in range(3)]
    if any(e*area < 0 for e in edges):
        return None
    u, v = [b[i]-a[i] for i in range(3)], [c[i]-a[i] for i in range(3)]
    normal = [u[1]*v[2]-u[2]*v[1], u[2]*v[0]-u[0]*v[2], u[0]*v[1]-u[1]*v[0]]
    depth = (sum(normal[i]*a[i] for i in range(3))
             - normal[0]*point[0] - normal[1]*point[1]) / normal[2]
    return float(depth), all(edges)


def expected_map(item):
    vertices = submitted_vertices(item)
    triangles = [[vertices[j] for j in item['indices'][i:i+3]]
                 for i in range(0, len(item['indices']), 3)]
    result = []
    for y in range(16):
        for x in range(16):
            hits = [hit for triangle in triangles
                    if (hit := triangle_ray(triangle, [Fraction(2*x+1, 2), Fraction(2*y+1, 2)]))
                    is not None and 0 <= hit[0] <= 1]
            result.append(min(hits) if hits else None)
    return result


class SceneDirectionalShadowPrimitiveCoverageTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.vectors = vectors()
        cls.expected = {item['name']: expected_map(item) for item in cls.vectors}
        paths = [getattr(model, name) for name in [
            'MODEL_SOURCE', 'SAMPLING_SOURCE', 'UV_TRANSFORM_SOURCE',
            'DIRECTIONAL_LIGHT_SOURCE', 'POINT_LIGHT_SOURCE', 'TUBE_LIGHT_SOURCE',
            'SPOT_LIGHT_SOURCE', 'LIGHT_SOURCE', 'VISIBILITY_SOURCE',
            'DYNAMIC_SNAPSHOT_SOURCE', 'DYNAMIC_LAYER_VALUES_SOURCE',
            'PERFORMANCE_COUNTER_SOURCE', 'MATERIAL_SOURCE', 'PIPELINE_SOURCE', 'SHADOW_SOURCE']]
        paths += [*model.MODEL_SUPPORT_SOURCES, model.BINDINGS_SOURCE,
                  shared.SCENE/'Resources/Textures/SceneResourceBudget.swift']
        helpers = [Path(__file__), FIXTURE, Path(model.__file__)]
        identity = {str(p): hashlib.sha256(p.read_bytes()).hexdigest() for p in helpers}
        parent = os.environ.get('MWX_DIRECTIONAL_SHADOW_EVIDENCE')
        if parent:
            Path(parent).mkdir(parents=True, exist_ok=True)
            (Path(parent)/'primitive-coverage-prerun.json').write_text(json.dumps({
                'testSources': identity, 'vectors': cls.vectors,
                'depthTolerance': DEPTH_TOLERANCE}, ensure_ascii=False, indent=2))
        cls.report = shared.run_swift(paths, 'import Foundation\nimport Metal\nimport simd\n'
            + model.LIGHTING_STUB + FIXTURE.read_text(), label='primitive-coverage',
            metal_sources=[model.METAL_SOURCE], input_value=cls.vectors)
        if any(hashlib.sha256(Path(p).read_bytes()).hexdigest() != digest
               for p, digest in identity.items()):
            raise AssertionError('Primitive coverage test or fixture changed during compile/run')
        if not cls.report['supportsBarycentric']:
            raise unittest.SkipTest('Shader barycentric coordinates unavailable; coverage correction unqualified')
        cls.rows = {row['name']: row for row in cls.report['rows']}

    def test_actual_encoding_and_original_triangle_exterior(self):
        self.assertEqual(set(self.rows), set(self.expected))
        for item in self.vectors:
            row = self.rows[item['name']]
            with self.subTest(case=item['name']):
                self.assertTrue(row['encoded'])
                self.assertTrue(row['completed'])
                self.assertEqual(row['materialPath'], item['materialPath'])
                self.assertEqual(len(row['depth']), 256)
                for index, (hit, actual) in enumerate(zip(self.expected[item['name']], row['depth'])):
                    if hit is None:
                        self.assertEqual(actual, 1, (item['name'], index % 16, index // 16, actual))

    def test_written_interior_depth_matches_true_ray(self):
        interior_hits = 0
        for name, row in self.rows.items():
            for index, (hit, actual) in enumerate(zip(self.expected[name], row['depth'])):
                if hit is not None and actual < 1:
                    with self.subTest(case=name, pixel=[index % 16, index // 16]):
                        self.assertAlmostEqual(actual, hit[0], delta=DEPTH_TOLERANCE)
                    interior_hits += bool(hit[1])
        self.assertGreater(interior_hits, 25)
        # Collapsed thin primitives and exact edge ownership do not promise a hit.
        for name in ['large-inside', 'tetra-stable-inside']:
            wanted = self.expected[name][8*16+8]
            self.assertIsNotNone(wanted)
            self.assertTrue(wanted[1])
            self.assertAlmostEqual(self.rows[name]['depth'][8*16+8], wanted[0], delta=DEPTH_TOLERANCE)

    def test_constant_depth_phase_remains_a_binary_coverage_boundary(self):
        for phase in [-.04, -.02, 0, .02, .04, .12]:
            name = f'flat-phase{phase}'
            wanted = .5 if abs(phase) < .03 else 1
            self.assertEqual(self.rows[name]['depth'][8*16+8], wanted, name)
        self.assertTrue(all(value == 1 for value in self.rows['tetra-outside']['depth']))

    def test_shared_indexed_vertices_names_and_equivalent_translation(self):
        reference = self.rows['shared-edge']['depth']
        for y in range(6, 11):
            for x in range(6, 11):
                index = y*16+x
                self.assertIsNotNone(self.expected['shared-edge'][index])
                self.assertAlmostEqual(reference[index], self.expected['shared-edge'][index][0],
                                       delta=DEPTH_TOLERANCE)
        for name in ['indexed-共享', 'renamed-Ω', 'translated-equivalent']:
            self.assertEqual(self.rows[name]['depth'], reference, name)


if __name__ == '__main__':
    unittest.main()
