"""CPU boundary for reflected MSL attachment-read derivation, not authored UV proof."""
from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPOSITORY_ROOT / "script"))
from scene_swift_source_sets import scene_swift_sources

SOURCE = REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Compilation/ShaderPreparation/SceneGenericShaderAttachmentReadLowering.swift"
SWIFT_SOURCES = tuple(dict.fromkeys((*scene_swift_sources("authored_shader_frontend_core"), SOURCE)))

PREFIX = '''#pragma clang diagnostic ignored "-Wmissing-prototypes"
#include <metal_stdlib>
#include <simd/simd.h>
using namespace metal;
struct Input { float2 uv [[user(locn0)]]; };
struct Output { float4 color [[color(0)]]; };
inline float4 decodeColor(float4 value) { return float4(value.xyz / max(value.w, 0.01), value.w); }
inline float4 encodeColor(float4 value) { return float4(value.xyz * value.w, value.w); }
vertex float4 vertexEntry(uint index [[vertex_id]]) { return float4(0.0, 0.0, 0.0, 1.0); }
'''
PARAMETERS = ('Input in [[stage_in]], texture2d<float> sourceImage [[texture(0)]], '
              'texture2d<float> overlayImage [[texture(1)]], '
              'sampler baseSampling [[sampler(0)]], sampler overlaySampling [[sampler(1)]]')
SAMPLE = 'sourceImage.sample(baseSampling, in.uv)'
BODY = '''    float4 base = decodeColor(sourceImage.sample(baseSampling, in.uv));
    float4 overlay = overlayImage.sample(overlaySampling, in.uv);
    return Output{encodeColor(base + overlay * 0.125)};
'''


def shader(body=BODY, parameters=PARAMETERS, prefix=PREFIX, entry='draw'):
    return prefix + f'fragment Output {entry}({parameters})\n{{\n' + body + '}\n'


def case(name, source, *, entry='draw', texture='sourceImage', count=1):
    return dict(name=name, metalSource=source, fragmentFunctionName=entry,
                sourceTextureName=texture, sourceSampleCallCount=count)


BASE = shader()
RENAMED = BASE.replace('sourceImage', 'backdrop').replace('baseSampling', 'sampleState') \
    .replace('draw(', 'shade(').replace('float4 base =', 'float4 ink =') \
    .replace('base + overlay', 'ink + overlay')
GROUPED_SAMPLE = 'sourceImage.sample((baseSampling), ((in.uv)))'
TWO_BODY = BODY.replace('float4 base = decodeColor(' + SAMPLE + ');',
    'float4 base = decodeColor(' + SAMPLE + ') + decodeColor(' + GROUPED_SAMPLE + ');')
ONLY_PARAMETERS = 'texture2d<float> sourceImage [[texture(0)]], sampler baseSampling [[sampler(0)]]'
ONLY_BODY = '    return Output{sourceImage.sample(baseSampling, float2(0.5))};\n'
CASES = [
    case('ordinary', BASE),
    case('renamed', RENAMED, entry='shade', texture='backdrop'),
    case('grouped', shader(BODY.replace(SAMPLE, GROUPED_SAMPLE))),
    case('twoSamples', shader(TWO_BODY), count=2),
    case('onlyResourceParameters', shader(ONLY_BODY, ONLY_PARAMETERS)),
    case('resourceFirst', shader(parameters='texture2d<float> sourceImage [[texture(0)]], '
         'sampler baseSampling [[sampler(0)]], Input in [[stage_in]], '
         'texture2d<float> overlayImage [[texture(1)]], sampler overlaySampling [[sampler(1)]]')),
    case('resourceLast', shader(parameters='Input in [[stage_in]], '
         'texture2d<float> overlayImage [[texture(1)]], sampler overlaySampling [[sampler(1)]], '
         'sampler baseSampling [[sampler(0)]], texture2d<float> sourceImage [[texture(0)]]')),
    case('sharedSampler', shader(BODY.replace('overlayImage.sample(overlaySampling,',
                                            'overlayImage.sample(baseSampling,'))),
    case('collision', shader(prefix=PREFIX + 'constant float mwxAttachmentColor = 0.25;\n')),
    case('commentsAndCRLF', shader(BODY.replace(SAMPLE, 'sourceImage /* 中文🙂 */ .sample(baseSampling, in.uv)'),
         prefix=PREFIX + '// sourceImage.read(fake) is only a comment.\n').replace('\n', '\r\n')),
]
REJECTED = {
    'readMethod': BASE.replace(SAMPLE, 'sourceImage.read(uint2(0))'),
    'gatherMethod': BASE.replace(SAMPLE, 'sourceImage.gather(baseSampling, in.uv)'),
    'LODArgument': BASE.replace(SAMPLE, 'sourceImage.sample(baseSampling, in.uv, level(0.0))'),
    'offsetArgument': BASE.replace(SAMPLE, 'sourceImage.sample(baseSampling, in.uv, int2(0))'),
    'resourceAlias': BASE.replace(SAMPLE, 'alias.sample(baseSampling, in.uv)')
        .replace('    float4 base', '    auto alias = sourceImage;\n    float4 base'),
    'helperArgument': BASE.replace(SAMPLE, 'readHelper(sourceImage, baseSampling, in.uv)'),
    'helperSameName': BASE + 'inline float4 helper(texture2d<float> sourceImage) { return float4(0); }\n',
    'resourceShadow': BASE.replace('    float4 base', '    float sourceImage = 0.0;\n    float4 base'),
    'samplerShadow': BASE.replace('    float4 base', '    sampler baseSampling;\n    float4 base'),
    'samplerAlias': BASE.replace('    float4 base', '    auto samplerAlias = baseSampling;\n    float4 base'),
    'missingSampler': BASE.replace(SAMPLE, 'sourceImage.sample(unboundSampler, in.uv)'),
    'helperSamplerUse': BASE.replace('    float4 base', '    observeSampler(baseSampling);\n    float4 base'),
    'wrongTextureBinding': BASE.replace('sourceImage [[texture(0)]]', 'sourceImage [[texture(2)]]'),
    'duplicateTextureBinding': BASE.replace('overlayImage [[texture(1)]]', 'overlayImage [[texture(0)]]'),
    'halfTexture': BASE.replace('texture2d<float> sourceImage', 'texture2d<half> sourceImage'),
    'texture3D': BASE.replace('texture2d<float> sourceImage', 'texture3d<float> sourceImage'),
    'arrayTexture': BASE.replace('sourceImage [[texture(0)]]', 'sourceImage[2] [[texture(0)]]'),
    'otherResourceUse': BASE.replace('    float4 base', '    uint width = sourceImage.get_width();\n    float4 base'),
    'memberReceiver': BASE.replace(SAMPLE, 'holder.' + SAMPLE),
    'nestedSourceSample': BASE.replace(SAMPLE,
        'sourceImage.sample(baseSampling, sourceImage.sample(baseSampling, in.uv).xy)'),
    'multipleFragmentEntries': BASE + BASE,
    'semanticDirective': '#define MAY_CHANGE_CODE 1\n' + BASE,
    'unbalanced': BASE[:-2],
    'unknownToken': BASE.replace('    float4 base', '    const char* text = "unknown";\n    float4 base'),
    'existingColorInput': BASE.replace('Input in [[stage_in]]', 'float4 current [[color(0)]], Input in [[stage_in]]'),
}
CASES += [case(name, text, count=2 if name == 'nestedSourceSample' else 1)
          for name, text in REJECTED.items()]
CASES += [case('zeroCount', BASE, count=0), case('countMismatch', BASE, count=2),
          case('optimizedCountMismatch', shader(TWO_BODY), count=1),
          case('wrongEntry', BASE, entry='otherEntry')]

HARNESS = r'''
import Foundation
private struct Input: Decodable {
    let name: String
    let metalSource: String
    let fragmentFunctionName: String
    let sourceTextureName: String
    let sourceSampleCallCount: Int
}
private struct Output: Encodable { let name: String; let lowered: String? }
@main private enum Main {
    static func main() throws {
        let input = try JSONDecoder().decode([Input].self,
            from: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])))
        let output = input.map { value in Output(name: value.name,
            lowered: SceneGenericShaderAttachmentReadLowering.lower(
                metalSource: value.metalSource, fragmentFunctionName: value.fragmentFunctionName,
                sourceTextureName: value.sourceTextureName, sourceSampleCallCount: value.sourceSampleCallCount)) }
        FileHandle.standardOutput.write(try JSONEncoder().encode(output))
    }
}
'''


@unittest.skipUnless(shutil.which('swiftc'), 'swiftc is required')
class SceneGenericShaderAttachmentReadTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temporary = tempfile.TemporaryDirectory(prefix='mwx-attachment-read-')
        cls.addClassCleanup(cls.temporary.cleanup)
        root = Path(cls.temporary.name)
        harness, inputs, binary = root/'Harness.swift', root/'cases.json', root/'probe'
        harness.write_text(HARNESS)
        rows = list(CASES)
        cls.actual_artifact = None
        if path := os.environ.get('MWX_ATTACHMENT_READ_ACTUAL_ARTIFACT'):
            artifact = json.loads(Path(path).read_text())
            program = artifact['program']
            source = next(binding['name'] for binding in program['textureBindings'] if binding['slot'] == 0)
            count = int(os.environ['MWX_ATTACHMENT_READ_ACTUAL_SAMPLE_COUNT'])
            rows.append(case('callerArtifact', program['metalSource'],
                entry=program['fragmentFunctionName'], texture=source, count=count))
            cls.actual_artifact = dict(path=path, sha256=hashlib.sha256(Path(path).read_bytes()).hexdigest(),
                                       sourceTextureName=source, sourceSampleCallCount=count)
        inputs.write_text(json.dumps(rows))
        paths = [*SWIFT_SOURCES, Path(__file__), harness, inputs]
        before = {str(p): hashlib.sha256(p.read_bytes()).hexdigest() for p in paths}
        command = ['xcrun', '--sdk', 'macosx', 'swiftc', '-parse-as-library',
            *map(str, SWIFT_SOURCES), str(harness), '-module-cache-path', str(root/'module-cache'), '-o', str(binary)]
        compiled = subprocess.run(command, cwd=REPOSITORY_ROOT, capture_output=True, text=True, timeout=180)
        completed = None
        if compiled.returncode == 0:
            completed = subprocess.run([str(binary), str(inputs)], cwd=REPOSITORY_ROOT,
                                       capture_output=True, text=True, timeout=20)
        after = {str(p): hashlib.sha256(p.read_bytes()).hexdigest() for p in paths}
        if destination := os.environ.get('MWX_ATTACHMENT_READ_EVIDENCE'):
            out = Path(destination); out.mkdir(parents=True, exist_ok=True)
            (out/'compile.json').write_text(json.dumps(dict(argv=command, exit=compiled.returncode,
                stdout=compiled.stdout, stderr=compiled.stderr, before=before, after=after), indent=2))
            (out/'Harness.swift').write_text(HARNESS)
            (out/'actual-artifact.json').write_text(json.dumps(cls.actual_artifact, indent=2))
            if completed is not None:
                (out/'result.json').write_text(completed.stdout)
                (out/'runtime.log').write_text(completed.stderr)
        if before != after:
            raise RuntimeError('Attachment lowering compilation inputs changed')
        if compiled.returncode:
            raise RuntimeError(compiled.stderr)
        if completed is None or completed.returncode:
            raise RuntimeError(completed.stderr if completed is not None else 'harness did not run')
        cls.results = {row['name']: row.get('lowered') for row in json.loads(completed.stdout)}

    def test_reflected_resource_is_replaced_while_color_and_other_resources_survive(self):
        result = self.results['ordinary']
        self.assertIsNotNone(result)
        self.assertEqual(result[:len(PREFIX)], PREFIX)
        self.assertTrue(result.endswith('{\n' + BODY.replace(SAMPLE, 'mwxAttachmentColor') + '}\n'), result)
        self.assertNotIn('texture2d<float> sourceImage', result)
        self.assertNotIn('sampler baseSampling', result)
        self.assertIn('float4 mwxAttachmentColor [[color(0)]]', result)
        self.assertIn('texture2d<float> overlayImage [[texture(1)]]', result)
        self.assertIn('sampler overlaySampling [[sampler(1)]]', result)

    def test_renamed_grouped_and_multiple_sample_variants_use_the_same_contract(self):
        for name in ('renamed', 'grouped', 'twoSamples', 'resourceFirst', 'resourceLast',
                     'onlyResourceParameters', 'commentsAndCRLF'):
            with self.subTest(case=name):
                result = self.results[name]
                self.assertIsNotNone(result)
                self.assertIn('float4 mwxAttachmentColor [[color(0)]]', result)
                self.assertNotIn('sourceImage.sample', result)
                self.assertNotIn('backdrop.sample', result)
        self.assertIn('fragment Output shade(', self.results['renamed'])
        self.assertIn('decodeColor(mwxAttachmentColor) + decodeColor(mwxAttachmentColor)',
                      self.results['twoSamples'])
        self.assertIn('fragment Output draw(float4 mwxAttachmentColor [[color(0)]])',
                      self.results['onlyResourceParameters'])
        self.assertIn('// sourceImage.read(fake) is only a comment.\r\n',
                      self.results['commentsAndCRLF'])

    def test_shared_sampler_and_generated_identifier_collision_are_preserved(self):
        shared = self.results['sharedSampler']
        self.assertIsNotNone(shared)
        self.assertIn('sampler baseSampling [[sampler(0)]]', shared)
        self.assertIn('overlayImage.sample(baseSampling, in.uv)', shared)
        collision = self.results['collision']
        self.assertIsNotNone(collision)
        self.assertIn('constant float mwxAttachmentColor = 0.25;', collision)
        self.assertIn('float4 mwxAttachmentColor1 [[color(0)]]', collision)
        self.assertIn('decodeColor(mwxAttachmentColor1)', collision)

    def test_unproved_resource_uses_and_count_or_signature_mismatches_are_absent(self):
        names = [*REJECTED, 'zeroCount', 'countMismatch', 'optimizedCountMismatch', 'wrongEntry']
        for name in names:
            with self.subTest(case=name):
                self.assertIsNone(self.results[name], name)
        if self.actual_artifact is not None:
            self.assertIsNotNone(self.results['callerArtifact'], self.actual_artifact)


if __name__ == '__main__':
    unittest.main()
