#!/usr/bin/env python3
"""Real Metal base-capture/composition behavior for bounded 2D material lighting."""
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from script.tests import test_scene_texture_candidate as texture_fixture

ROOT = Path(__file__).resolve().parents[2]
SCENE = ROOT / 'MyWallpaperX/Core/SteamWorkshopScene'

class SceneLitImageLayerTests(unittest.TestCase):
    def test_world_space_capture_and_terminal_composition(self):
        with tempfile.TemporaryDirectory(prefix='scene-lit-image-') as temporary:
            work = Path(temporary)
            air = []
            for name in ['SceneImageLayer', 'SceneLitImageLayer']:
                output = work / (name + '.air')
                subprocess.run(['xcrun','-sdk','macosx','metal','-c',str(SCENE / 'Rendering/Composition' / (name+'.metal')),'-o',str(output)],check=True,capture_output=True,text=True)
                air.append(str(output))
            library = work / 'fixture.metallib'
            subprocess.run(['xcrun','-sdk','macosx','metallib',*air,'-o',str(library)],check=True,capture_output=True,text=True)
            sources = ['Rendering/Metal/SceneMetalPipeline.swift','Rendering/Metal/SceneLitImageLayerPipeline.swift',
                'Rendering/Composition/SceneOffscreenEffectRenderer+Capture.swift',
                'Diagnostics/ScenePerformanceCounterHub.swift','Diagnostics/SceneGPUCensus.swift']
            support = work / 'Support.swift'
            support.write_text(texture_fixture.HARNESS.split('@main', 1)[0] + 'import simd\nenum SceneMatrix { static func scale(_ v: SIMD3<Float>) -> simd_float4x4 { simd_float4x4(diagonal: SIMD4(v,1)) } }\n')
            binary = work / 'fixture'
            compiled = subprocess.run(['xcrun','swiftc','-parse-as-library',*[str(p) for p in dict.fromkeys(texture_fixture.SWIFT_SOURCES + [SCENE / s for s in sources])],str(support),str(ROOT/'script/tests/fixtures/SceneLitImageLayerHarness.swift'),'-module-cache-path',str(work/'module-cache'),'-o',str(binary)],capture_output=True,text=True)
            self.assertEqual(compiled.returncode,0,compiled.stderr)
            result = subprocess.run([str(binary),str(library)],capture_output=True,text=True)
            self.assertEqual(result.returncode,0,result.stderr)
            report = json.loads(result.stdout)
            self.assertEqual(report['rectangleRotationNormalCases'],12)
            self.assertLess(report['maxOracleError'],0.002)
            self.assertEqual(report['flatNormalError'],0)
            print(json.dumps(report,sort_keys=True))

if __name__ == '__main__': unittest.main()
