"""Actual managed publication -> SourceFacts/ModelBuilder package consumption.

No Root/Reader/Project/Catalog substitution. The existing builder harness keeps
only its outside VM/planning/shader-interface leaves unavailable. A predecessor
comparison uses actual frozen source files selected by an explicit environment
path; neither HEAD nor rewritten predecessor product text is accepted as one.
"""
from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
import runpy
import shutil
import subprocess
import tempfile
import unittest

from script.tests import test_scene_static_model_parts as parts
from script.tests.scene_pkg_fixture import make_package
from script.tests.test_steam_library_transaction import SOURCES as LIBRARY_SOURCES, digest

REPO = Path(__file__).resolve().parents[2]
SCENE = REPO / 'MyWallpaperX/Core/SteamWorkshopScene'
HARNESS = REPO / 'script/tests/fixtures/ScenePackageSourceInputHarness.swift'
BEFORE_ENV = 'MWX_SCENE_PACKAGE_BEFORE_SOURCE'
EVIDENCE_ENV = 'MWX_SCENE_PACKAGE_INPUT_EVIDENCE'

PRODUCER = r'''
import Foundation
@main enum Producer {
    @MainActor static func main() throws {
        let base = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let home = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
        precondition(FileManager.default.homeDirectoryForCurrentUser.resolvingSymlinksInPath().standardizedFileURL
            == home.resolvingSymlinksInPath().standardizedFileURL, "producer HOME mismatch")
        typealias T = SteamWorkshopLibraryTransaction
        let stage = base.appendingPathComponent("staging/job-" + String(repeating: "a", count: 32), isDirectory: true)
        let identity = try T.stagingLeaseIdentity(stagingURL: stage, stagingRoot: base.appendingPathComponent("staging"))
        var frame = try SteamServiceFrameDecoder.decode(Data(contentsOf: base.appendingPathComponent("receipt.json"))).get()
        var fields = frame.root["data"]!.objectValue!
        fields["stagingDevice"] = .string(String(identity.device)); fields["stagingInode"] = .string(String(identity.inode))
        fields["stagingBirthSeconds"] = .string(String(identity.birthSeconds!))
        fields["stagingBirthNanoseconds"] = .string(String(identity.birthNanoseconds!))
        frame.root["data"] = .object(fields)
        let staged = try SteamWorkshopStagedReceipt(frame: frame, jobId: "package-source-input", workshopId: "123456",
            accountSteamId: "76561198000000000", accountEpoch: 7, stagingRoot: base.appendingPathComponent("staging").path)
        let library = base.appendingPathComponent("library", isDirectory: true)
        let prepared = try T.prepare(receipt: staged, attempt: 1, libraryRoot: library)
        let current = try T.canonicalCommit(prepared)
        struct Metadata: Encodable { let commit: SteamWorkshopLibraryCommit }
        try T.publishCanonical(prepared, metadata: JSONEncoder().encode(Metadata(commit: current)), libraryRoot: library)
        let source = ScenePlaybackSource(rootURL: try T.contentURL(for: current, libraryRoot: library),
            managed: .init(storageIdentity: T.storageIdentity(for: current)!, generation: current.generation!))
        try JSONEncoder().encode(source).write(to: base.appendingPathComponent("source.json"))
        try JSONEncoder().encode(current).write(to: base.appendingPathComponent("commit.json"))
        print(String(decoding: try JSONEncoder().encode(source), as: UTF8.self))
    }
}
'''


def source_map(paths):
    return {str(path): hashlib.sha256(Path(path).read_bytes()).hexdigest() for path in dict.fromkeys(paths)}


def support(text):
    # The shared builder fixture includes the real MDL parser.
    return text.split('@main', 1)[0]


def fixture():
    entries, _ = parts.native_fixture(1)
    scene = json.loads(entries.pop('scene.json'))
    entries.pop('project.json')
    scene['objects'].append({'id': 71, 'name': 'Packaged image', 'image': 'models/active.json',
                             'origin': '80 64 0', 'size': '32 16',
                             'visible': {'user': 'enabled', 'value': True},
                             'alpha': {'user': 'amount', 'value': .6}})
    entries['scene.json'] = json.dumps(scene, sort_keys=True).encode()
    entries['models/active.json'] = b'{"material":"materials/active.json","width":32,"height":16}'
    entries['models/unreferenced.json'] = b'{"material":"materials/unreferenced.json","width":17,"height":19}'
    entries['materials/active.json'] = b'{"passes":[{"shader":"genericimage","textures":["materials/part000.png"],"combos":{"PROBE":1}}]}'
    entries['materials/unreferenced.json'] = b'{"passes":[{"shader":"genericimage","textures":["materials/peer.png"]}]}'
    entries['unused/payload.bin'] = b'UNCONSUMED-PAYLOAD-0123456789'
    project = {'type': 'scene', 'file': 'scene.json', 'title': 'Package source input', 'version': 5,
               'general': {'properties': {'enabled': {'type': 'bool', 'value': True},
                                          'amount': {'type': 'slider', 'value': .6}}}}
    author = {'project.json': json.dumps(project, sort_keys=True).encode(),
              'scene.pkg': make_package(list(entries.items())),
              'scene.json': b'{"objects":[{"id":900,"name":"valid loose fallback"}]}',
              'models/zz-loose-unreferenced.json': b'{"material":"materials/zz-loose-unreferenced.json"}',
              'materials/zz-loose-unreferenced.json': b'{"passes":[{"shader":"genericimage"}]}',
              'materials/part000.json': b'{"passes":[{"shader":"genericimage","combos":{"LOOSE_PEER":1}}]}'}
    return author, entries


class ScenePackageSourceInputTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temporary = tempfile.TemporaryDirectory(prefix='mwx-package-source-', dir='/private/tmp')
        cls.work = Path(cls.temporary.name).resolve()
        evidence = os.environ.get(EVIDENCE_ENV)
        cls.evidence = Path(evidence).resolve() if evidence else None
        if cls.evidence:
            cls.evidence.mkdir(parents=True, exist_ok=True)
        cls.identities = {}
        cls.executables = {}
        cls.build('producer', list(LIBRARY_SOURCES), PRODUCER)
        sources = list(dict.fromkeys([*parts.builder.SWIFT_SOURCES, *parts.reader.SWIFT_SOURCES,
                                     SCENE / 'Runtime/Session/SceneDesktopWallpaperLaunchModels.swift']))
        text = support(parts.builder.HARNESS_SOURCE) + HARNESS.read_text()
        cls.build('current', sources, text, current=True)
        before = os.environ.get(BEFORE_ENV)
        cls.before_root = Path(before).resolve() if before else None
        if cls.before_root:
            # Execute only fixture declarations to obtain the original closure;
            # all its product paths point into the actual recorded predecessor.
            before_builder = runpy.run_path(str(cls.before_root / 'script/tests/test_scene_alpha_display_builder_fixture.py'))
            before_reader = runpy.run_path(str(cls.before_root / 'script/tests/test_scene_static_model_reader.py'))
            before_sources = list(dict.fromkeys([*before_builder['SWIFT_SOURCES'], *before_reader['SWIFT_SOURCES'],
                cls.before_root / 'MyWallpaperX/Core/SteamWorkshopScene/Runtime/Session/SceneDesktopWallpaperLaunchModels.swift']))
            before_text = support(before_builder['HARNESS_SOURCE']) + HARNESS.read_text()
            cls.build('before', before_sources, before_text, current=True)

    @classmethod
    def emit(cls, name, value):
        if cls.evidence:
            (cls.evidence / (name + '.json')).write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n')

    @classmethod
    def build(cls, label, sources, text, current=False):
        harness = cls.work / (label + '.swift')
        harness.write_text(text)
        tracked = [*sources, harness, Path(__file__), HARNESS,
                   Path(parts.__file__), Path(parts.builder.__file__), Path(parts.reader.__file__)]
        before = source_map(tracked)
        command = ['xcrun', '--sdk', 'macosx', 'swiftc', '-swift-version', '5', '-parse-as-library']
        if current:
            command += ['-D', 'D8_CURRENT']
        binary = cls.work / label
        command += [*map(str, sources), str(harness), '-module-cache-path', str(cls.work / 'modules'),
                    '-framework', 'Metal', '-o', str(binary)]
        result = subprocess.run(command, capture_output=True, text=True, timeout=240)
        after = source_map(tracked)
        cls.emit(label + '-build', {'command': command, 'sourceBefore': before, 'sourceAfter': after,
                                  'exitCode': result.returncode, 'stdout': result.stdout, 'stderr': result.stderr,
                                  'binarySHA256': hashlib.sha256(binary.read_bytes()).hexdigest() if binary.exists() else None})
        if before != after:
            raise AssertionError('source changed during compilation: ' + label)
        if result.returncode:
            raise AssertionError(result.stdout + result.stderr)
        cls.identities.update(before)
        cls.executables[label] = binary

    @classmethod
    def tearDownClass(cls):
        cls.emit('final-sources', {'sourceBefore': cls.identities, 'sourceAfter': source_map(map(Path, cls.identities)),
                                  'predecessorSourceRoot': str(cls.before_root) if cls.before_root else None})
        cls.temporary.cleanup()

    def environment(self, home):
        home.mkdir(parents=True, exist_ok=True)
        return {**os.environ, 'HOME': str(home), 'CFFIXED_USER_HOME': str(home)}

    def run_native(self, label, arguments, home, evidence_name):
        before = source_map(map(Path, self.identities))
        result = subprocess.run([str(self.executables[label]), *map(str, arguments), str(home)],
                                env=self.environment(home), capture_output=True, text=True, timeout=45)
        after = source_map(map(Path, self.identities))
        self.emit(evidence_name, {'binary': label, 'arguments': list(map(str, arguments)), 'home': str(home),
                                 'exitCode': result.returncode, 'stdout': result.stdout, 'stderr': result.stderr,
                                 'sourcesStable': before == after})
        self.assertEqual(before, after)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        return json.loads(result.stdout)

    def imported(self, label, legacy=False, unused_aliases=False, renamed=False):
        author, entries = fixture()
        if renamed:
            entries['variant.json'] = entries.pop('scene.json')
            project = json.loads(author['project.json'])
            project['file'] = 'variant.json'
            author['project.json'] = json.dumps(project, sort_keys=True).encode()
            author['variant.json'] = author.pop('scene.json')
            author.pop('scene.pkg')
            author['variant.pkg'] = make_package(list(entries.items()))
        if unused_aliases:
            # Unused same-target aliases remain metadata only. The current
            # virtual Root selects the first authored entry without expansion.
            entries['unused/compat-alias.bin'] = b'ignored equal-byte alias'
            entries['unused\\compat-alias.bin'] = entries['unused/compat-alias.bin']
            author['scene.pkg'] = make_package(list(entries.items()))
            legacy = True
        if legacy:
            # Real original transaction warm-policy ineligibility; never patch a
            # marker/ref or fabricate a manifest to manufacture an old source.
            author['unused-legacy.pkg'] = b'valid-legacy-author-file-not-a-PKGV'
        base = self.work / label
        stage = base / 'staging' / ('job-' + 'a' * 32)
        stage.mkdir(parents=True)
        for relative, value in author.items():
            path = stage / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(value)
        receipt = {'v': 1, 'type': 'result', 'requestId': 'r', 'ok': True, 'accountEpoch': 7,
                   'data': {'receiptVersion': 2, 'contentDigest': digest(author), 'jobId': 'package-source-input',
                            'workshopId': '123456', 'accountSteamId': '76561198000000000', 'stagedComplete': True,
                            'projectJsonPresent': True, 'manifestId': '123', 'stagingPath': str(stage),
                            'stagingDevice': str(stage.stat().st_dev), 'stagingInode': str(stage.stat().st_ino),
                            'verifiedBytes': sum(map(len, author.values())), 'totalBytes': sum(map(len, author.values()))}}
        (base / 'receipt.json').write_text(json.dumps(receipt))
        source = self.run_native('producer', [base], self.work / 'producer-home', label + '-producer')
        source_file = base / 'source.json'
        root = base / 'library/Scene/123456'
        self.assertEqual(json.loads((base / 'commit.json').read_bytes())['contentDigest'], digest(author))
        self.assertEqual(set(source['managed']), {'storageIdentity', 'generation'})
        self.emit(label + '-inputs', {'authorSHA256': {p: hashlib.sha256(v).hexdigest() for p, v in author.items()},
                                     'packageEntriesSHA256': {p: hashlib.sha256(v).hexdigest() for p, v in entries.items()},
                                     'source': source, 'commit': json.loads((base / 'commit.json').read_bytes())})
        return root, source_file, author, entries

    def equivalent_directory(self, label, author, entries):
        directory = self.work / label
        flattened = {p: v for p, v in author.items() if not p.endswith('.pkg')}
        flattened.update(entries)
        for relative, value in flattened.items():
            path = directory / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(value)
        return directory

    def test_actual_managed_source_matches_directory_and_recorded_predecessor(self):
        root, source_file, author, entries = self.imported('equivalence')
        current = self.run_native('current', [root, source_file, 'projection'], self.work / 'current-home', 'current-projection')
        self.assertEqual(current['project']['entry'], 'scene.json')
        self.assertEqual(current['project']['title'], 'Package source input')
        self.assertEqual([x['id'] for x in current['runtimeDescriptor']['layers']], [1, 2, 71])
        image = next(x for x in current['runtimeDescriptor']['layers'] if x['id'] == 71)
        self.assertAlmostEqual(image['alpha'], .35)
        self.assertTrue(image['visible'])
        selected = next(x for x in current['runtimeDescriptor']['materialPasses']
                        if x['materialPath'] == 'materials/part000.json')
        self.assertEqual(selected['combos']['LIGHTING'], 0)
        self.assertNotIn('LOOSE_PEER', selected['combos'])
        self.assertNotIn('models/unreferenced.json', {x['path'] for x in current['catalogModels']})
        self.assertNotIn('models/zz-loose-unreferenced.json', {x['path'] for x in current['catalogModels']})
        self.assertNotIn('materials/unreferenced.json', current['catalogMaterialPaths'])
        self.assertNotIn('materials/zz-loose-unreferenced.json', current['catalogMaterialPaths'])
        links = {(x['modelPath'], x.get('materialPath')) for x in current['runtimeDescriptor']['modelMaterialLinks']}
        self.assertNotIn(('models/unreferenced.json', 'materials/unreferenced.json'), links)
        self.assertNotIn(('models/zz-loose-unreferenced.json', 'materials/zz-loose-unreferenced.json'), links)
        self.assertIn(('models/parts.mdl', 'materials/part000.json'), links)
        # Collapse package-first priority into one equivalent physical namespace.
        directory = self.equivalent_directory('equivalent-directory', author, entries)
        loose = self.run_native('current', [directory, '-', 'projection'], self.work / 'directory-home', 'directory-projection')
        self.assertEqual(current, loose)
        if self.before_root:
            predecessor = self.run_native('before', [root, source_file, 'projection'], self.work / 'before-home', 'actual-before-projection')
            # The old catalog eagerly read unused author definitions. Compare
            # common consumers, retaining equality of the actual active chain.
            selected_models = {x['path'] for x in current['catalogModels']}
            selected_materials = set(current['catalogMaterialPaths'])
            predecessor['catalogModels'] = [x for x in predecessor['catalogModels'] if x['path'] in selected_models]
            old_materials = predecessor['catalogMaterialPaths']
            predecessor['catalogMaterialRawSHA'] = [value for path, value in zip(old_materials, predecessor['catalogMaterialRawSHA'])
                if path in selected_materials]
            predecessor['catalogMaterialPaths'] = [x for x in old_materials if x in selected_materials]
            for key in ('authoredDescriptor', 'runtimeDescriptor'):
                old_descriptor, descriptor = predecessor[key], current[key]
                selected_links = {(x['modelPath'], x.get('materialPath')) for x in descriptor['modelMaterialLinks']}
                old_descriptor['modelMaterialLinks'] = [x for x in old_descriptor['modelMaterialLinks']
                    if (x['modelPath'], x.get('materialPath')) in selected_links]
                old_descriptor['materialPasses'] = [x for x in old_descriptor['materialPasses']
                    if x['materialPath'] in selected_materials]
                for paths in ('shaderReferences', 'textureReferences'):
                    old_descriptor[paths] = [x for x in old_descriptor[paths] if x in descriptor[paths]]
                states = old_descriptor.get('preparedImageMaterialStatesByModelPath')
                if states is not None:
                    old_descriptor['preparedImageMaterialStatesByModelPath'] = {path: value for path, value in states.items()
                        if path in descriptor.get('preparedImageMaterialStatesByModelPath', {})}
            self.assertEqual(current, predecessor)
        self.emit('equivalence-result', {'directoryEqual': True, 'predecessorRequested': bool(self.before_root),
                                         'predecessorActiveProjectionEqual': True if self.before_root else None})

    def test_local_edits_optional_hints_current_revision_and_cancellation(self):
        root, source_file, _, _ = self.imported('integrity')
        checks = self.run_native('current', [root, source_file, 'mutable'], self.work / 'integrity-home', 'integrity-results')
        for name, passed in checks.items():
            with self.subTest(fact=name):
                self.assertIs(passed, True)
        old, old_source, _, _ = self.imported('legacy', unused_aliases=True)
        checks = self.run_native('current', [old, old_source, 'legacy'], self.work / 'legacy-home', 'legacy-results')
        for name, passed in checks.items():
            with self.subTest(fact=name):
                self.assertIs(passed, True)
        if self.before_root:
            current = self.run_native('current', [old, old_source, 'projection'], self.work / 'legacy-home',
                                      'legacy-current-projection')
            predecessor = self.run_native('before', [old, old_source, 'projection'], self.work / 'legacy-before-home',
                                          'legacy-actual-before-projection')
            self.assertEqual(current, predecessor)

    def test_old_managed_selected_package_mounts_without_persistent_receipt(self):
        root, source_file, author, entries = self.imported('temporary', legacy=True)
        publication_before = source_map(sorted(path for path in root.parents[1].rglob('*') if path.is_file()))
        home = self.work / 'temporary-home'
        checks = self.run_native('current', [root, source_file, 'mutable'], home, 'temporary-results')
        for name, passed in checks.items():
            with self.subTest(fact=name):
                self.assertIs(passed, True)
        current = self.run_native('current', [root, source_file, 'projection'], home, 'temporary-projection')
        directory = self.equivalent_directory('temporary-directory', author, entries)
        loose = self.run_native('current', [directory, '-', 'projection'], self.work / 'temporary-directory-home',
                                'temporary-directory-projection')
        self.assertEqual(current, loose)
        if self.before_root:
            predecessor = self.run_native('before', [root, source_file, 'projection'],
                                          self.work / 'temporary-before-home', 'temporary-actual-before-projection')
            self.assertEqual(current, predecessor)
        commit = json.loads((source_file.parent / 'commit.json').read_bytes())
        self.assertIsNone(commit.get('sceneReceipt'))
        self.assertIsNone(json.loads(source_file.read_bytes())['managed'].get('receipt'))
        self.assertEqual(publication_before, source_map(sorted(path for path in root.parents[1].rglob('*') if path.is_file())))
        renamed, renamed_source, renamed_author, renamed_entries = self.imported('temporary-renamed', legacy=True, renamed=True)
        renamed_before = source_map(sorted(path for path in renamed.parents[1].rglob('*') if path.is_file()))
        renamed_home = self.work / 'temporary-renamed-home'
        renamed_route = self.run_native('current', [renamed, renamed_source, 'route'], renamed_home, 'temporary-renamed-route')
        self.assertTrue(all(renamed_route.values()))
        renamed_projection = self.run_native('current', [renamed, renamed_source, 'projection'], renamed_home,
                                             'temporary-renamed-projection')
        self.assertEqual(renamed_projection['project']['entry'], 'variant.json')
        self.assertEqual([x['id'] for x in renamed_projection['runtimeDescriptor']['layers']], [1, 2, 71])
        directory = self.equivalent_directory('temporary-renamed-directory', renamed_author, renamed_entries)
        loose = self.run_native('current', [directory, '-', 'projection'], self.work / 'temporary-renamed-directory-home',
                                'temporary-renamed-directory-projection')
        self.assertEqual(renamed_projection, loose)
        if self.before_root:
            predecessor = self.run_native('before', [renamed, renamed_source, 'projection'],
                                          self.work / 'temporary-renamed-before-home', 'temporary-renamed-actual-before-projection')
            self.assertEqual(renamed_projection, predecessor)
        self.assertEqual(renamed_before, source_map(sorted(path for path in renamed.parents[1].rglob('*') if path.is_file())))
        self.emit('temporary-equivalence-result', {'directoryEqual': True, 'renamedDirectoryEqual': True,
            'predecessorRequested': bool(self.before_root), 'predecessorEqual': True if self.before_root else None,
            'publicationBefore': publication_before, 'publicationAfter': source_map(map(Path, publication_before)),
            'renamedPublicationBefore': renamed_before, 'renamedPublicationAfter': source_map(map(Path, renamed_before))})


if __name__ == '__main__':
    unittest.main()
