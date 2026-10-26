"""Real installed-record builder on owned disk; discovery work is observed only in copied sources."""
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

from script.tests.test_steam_library_transaction import SOURCES as TRANSACTION_SOURCES
from script.tests.test_thumbnail_return_reuse import SWIFT_ISOLATION_FLAGS
from script.tests.test_ui_library_algorithms import declaration

ROOT = Path(__file__).resolve().parents[2]
CORE = Path('MyWallpaperX/Modules/SteamWorkshop/Core')
OWNER = CORE / 'SteamWorkshopService+LibraryRecords.swift'
SYNC = CORE / 'SteamWorkshopService+DownloadLibrarySync.swift'
API = CORE / 'SteamWorkshopAPIModels.swift'
PARSING = CORE / 'SteamWorkshopService+ParsingUtilities.swift'
FIXTURE = Path('script/tests/fixtures/SteamLibraryLegacyDiscoveryChecks.swift')
TEST = Path('script/tests/test_steam_library_legacy_discovery.py')
PRODUCT_SOURCES = [
    *(path.relative_to(ROOT) for path in TRANSACTION_SOURCES),
    CORE / 'SteamWorkshopModels.swift', CORE / 'SteamWorkshopService+Constants.swift',
    Path('MyWallpaperX/Modules/SteamWorkshop/Scene/SteamWorkshopSceneService+SceneDetection.swift'),
    Path('MyWallpaperX/Modules/SteamWorkshop/Web/Core/SteamWorkshopWebValidationModels.swift'),
    Path('MyWallpaperX/Modules/SteamWorkshop/Web/Core/SteamWorkshopDownloadRecord+Web.swift'),
]
MEMBERS = (
    '    nonisolated static func loadWorkshopProject(',
    '    nonisolated static func detailCacheDirectoryURL(',
    '    nonisolated static func detailCacheFileURL(',
    '    nonisolated static func legacyDownloadMetadataFileURL(',
    '    nonisolated static func preferredPreviewRelativePath(',
    '    nonisolated static func loadDetailCache(id:',
    '    nonisolated static func loadDetailCacheSnapshot(',
    '    nonisolated static func scanBuildInstalledRecord(at directory:',
    '    nonisolated static func resolveVideoURL(',
    '    nonisolated static func resolveHTMLURL(',
    '    nonisolated static func resolveContentType(',
    '    nonisolated static func scanBuildInstalledRecord(\n        from metadata:',
    '    nonisolated static func hasLocalWorkshopContent(',
    '    nonisolated static private func videoFileCandidates(',
    '    nonisolated static private func relativePath(',
    '    nonisolated static func localDownloadStatistics(',
    '    nonisolated static func localCreationDate(',
    '    nonisolated static func localFileSizeBytes(',
    '    nonisolated static func directoryTotalBytes(',
    '    nonisolated static private func scanLoadDownloadMetadataSnapshot(',
)
PREPARATION_MEMBERS = (
    '    private nonisolated static func scanPrepareInstalledRecord(at directory:',
    '    private nonisolated static func scanPrepareInstalledRecord(\n        from metadata:',
    '    private nonisolated static func scanProjectInstalledRecord(',
)
CHECKS = {
    'projectPreferredHTMLAndPreviewSurvive', 'projectSceneKeepsLooseEntry',
    'metadataKeepsSourceAndBrowserFields', 'packageOnlyRemainsScene',
    'HTMLOnlyDirectoryStillDiscovered', 'videoOnlyDirectoryStillDiscovered',
    'emptyDirectoryStaysAbsent', 'projectGhostStaysAbsent', 'metadataGhostStaysAbsent',
    'directoryNamedPackageStaysAbsent', 'malformedProjectStillFindsActualHTML',
    'preferredVideoOutranksLargerAlternative', 'missingPreferredFallsBackToCurrentIndex',
    'dependencyShellKeepsHostAndStatus', 'missingDependencyKeepsLocalShell',
    'dependencyCycleStopsWithoutInventingEntry', 'managedSnapshotReturnsBeforeLegacyProbe',
    'removedManagedSnapshotDoesNotReviveAlias', 'managedWithoutCommitDoesNotReviveAlias',
    'outsideHTMLSymlinkRemainsUnavailable', 'exportedVideoUsesCurrentExistingFile',
    'recordBytesAndDatesArePreparedFromRealInputs',
    'sharedHostRowsAndTransitiveEntryStayIdentical',
    'admittedHostsWithoutHTMLKeepTheirFolders',
    'declaredSceneAndVideoCanStillHostHTML',
    'admittedWebRootOutranksSceneAndGhostFallsThrough',
    'metadataSelectedHostRootOutranksAlias',
    'browserClassificationStillAdmitsLooseSceneHost',
    'managedDependencyKeepsCommitAndNoAliasRules',
    'ghostAndSelfDependencyDoNotInventHosts',
    'directMetadataBuilderKeepsSelectedRootAndFields',
}
WORK_CHECKS = {
    'markedDirectoriesHaveOnlyActualResolverCalls', 'HTMLOnlySkipsUnusedVideoPreflight',
    'videoOnlyRetainsNecessaryDiscovery', 'emptyRetainsNecessaryDiscovery',
    'metadataSourceAvoidsVideoDiscoveryUntilMissing', 'managedAliasNeverProbesLegacyDirectory',
    'preferredNameReachesActualResolvers', 'dependencyHostStillResolvesOnce', 'markerExistsShortCircuitsInOrder',
    'dependencyEdgesDoNotProjectHostRows', 'publishedHostStillProjectsAllDisplayFields',
    'transitiveEdgesDoNotProjectIntermediateRows',
}


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def prepare_legacy_discovery_sources(tree, work, fixture_tree=None):
    """Use the complete two builder overloads and their real transitive leaves, not guard stand-ins."""
    paths = list(dict.fromkeys([OWNER, SYNC, API, PARSING, FIXTURE, TEST, *PRODUCT_SOURCES,
        Path('script/tests/test_steam_library_transaction.py'),
        Path('script/tests/test_thumbnail_return_reuse.py'),
        Path('script/tests/test_ui_library_algorithms.py')]))
    fixture_tree = fixture_tree or tree
    hashes = {str(path): digest((fixture_tree if path in (FIXTURE, TEST) else tree) / path) for path in paths}
    source = (tree / OWNER).read_text()
    fragments = [declaration(source, 'nonisolated struct SteamWorkshopInstalledLibraryScanContext:')]
    signatures = MEMBERS
    if 'private nonisolated struct SteamWorkshopInstalledRecordPreparation {' in source:
        fragments.append(declaration(source, 'private nonisolated struct SteamWorkshopInstalledRecordPreparation {'))
        signatures += PREPARATION_MEMBERS
    members = [declaration(source, signature) for signature in signatures]
    # Task-copy entry observations; source/admission and projection bodies stay real.
    observed = []
    for signature, member in zip(signatures, members):
        for kind in ('HTML', 'Video'):
            if signature == '    nonisolated static func resolve' + kind + 'URL(':
                opening = member.index('{') + 1
                member = member[:opening] + '\n        LegacyDiscoveryObservation.shared.entered("' + kind + \
                    '", directory: directory, preferred: preferredFileName)\n' + member[opening:]
        for selector, kind, directory in (
            ('    nonisolated static func preferredPreviewRelativePath(', 'Preview', 'directory'),
            ('    nonisolated static func localDownloadStatistics(', 'Statistics', 'sampleDirectory ?? standaloneFile?.deletingLastPathComponent()'),
        ):
            if signature == selector:
                opening = member.index('{') + 1
                member = member[:opening] + '\n        LegacyDiscoveryObservation.shared.entered("' + kind + \
                    '", directory: ' + directory + ', preferred: nil)\n' + member[opening:]
        preflight = ('    private nonisolated static func scanPrepareInstalledRecord(at directory:'
                     if PREPARATION_MEMBERS[0] in signatures else
                     '    nonisolated static func scanBuildInstalledRecord(at directory:')
        if signature == preflight:
            for kind, path in [('project', 'projectURL.path'), ('metadata', 'metadataURL.path'),
                               ('package', 'directory.appendingPathComponent("scene.pkg").path')]:
                original = 'FileManager.default.fileExists(atPath: ' + path + ')'
                if member.count(original) != 1:
                    raise ValueError('unique original preflight fileExists required: ' + kind)
                member = member.replace(original, 'LegacyDiscoveryObservation.shared.exists("' + kind
                    + '", directory: directory, path: ' + path + ')', 1)
        observed.append(member)
    observed.append(declaration((tree / SYNC).read_text(), '    nonisolated static func scanLoadDownloadMetadataEntry('))
    observed.append(declaration((tree / PARSING).read_text(), '    nonisolated static func fileSizeText('))
    fragments += ['@MainActor final class SteamWorkshopService {}',
                  'extension SteamWorkshopService {\n' + '\n'.join(observed) + '\n}']
    generated = work / 'InstalledRecordBuilder.swift'
    generated.write_text('import Foundation\n' + '\n'.join(fragments) + '\n')
    facts = work / 'InstalledRecordFacts.swift'
    facts.write_text('import Foundation\n' + '\n'.join(declaration((tree / API).read_text(), signature)
        for signature in ('nonisolated struct SteamWorkshopProjectGeneral:',
                          'nonisolated struct SteamWorkshopProject:',
                          'nonisolated struct SteamWorkshopDownloadMetadataSnapshot:',
                          'nonisolated struct SteamWorkshopDetailCacheSnapshot:')) + '\n')
    harness = work / FIXTURE.name
    harness.write_text((fixture_tree / FIXTURE).read_text())
    member_hashes = {signature: hashlib.sha256(member.encode()).hexdigest()
                     for signature, member in zip(signatures, members)}
    return [*(tree / path for path in PRODUCT_SOURCES), generated, facts, harness], {
        'inputs': hashes, 'completeOriginalMemberSHA256': member_hashes,
        'observations': ['entry of actual resolveHTMLURL', 'entry of actual resolveVideoURL',
                         'entry of actual preferredPreviewRelativePath and localDownloadStatistics',
                         'three original preflight fileExists calls delegated to Foundation through test observer'],
        'scope': __doc__, 'generatedSHA256': {path.name: digest(path) for path in (generated, facts, harness)},
    }


@unittest.skipUnless(sys.platform == 'darwin', 'real Foundation/descriptor installed-library gate requires macOS')
class SteamLibraryLegacyDiscoveryTests(unittest.TestCase):
    def test_actual_builder_records_and_short_circuit_discovery(self):
        with tempfile.TemporaryDirectory(prefix='mwx-legacy-discovery-', dir='/private/tmp') as directory:
            work = Path(directory)
            home, temporary, cases = work / 'home', work / 'tmp', work / 'cases'
            for path in (home, temporary, cases): path.mkdir()
            environment = dict(os.environ, HOME=str(home), CFFIXED_USER_HOME=str(home),
                               TMPDIR=str(temporary) + '/')
            sources, inputs = prepare_legacy_discovery_sources(ROOT, work)
            target = os.environ.get('MWX_LEGACY_DISCOVERY_PROOF_DIR')
            proof = Path(target) if target else None
            if proof: proof.mkdir(parents=True, exist_ok=True)

            def save(name, text):
                if proof: (proof / name).write_text(text)

            def execute(command, name, timeout):
                result = subprocess.run(command, env=environment, capture_output=True, text=True, timeout=timeout)
                save(name + '-stdout.log', result.stdout)
                save(name + '-stderr.log', result.stderr)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                return result

            binary = work / 'legacy-discovery'
            command = ['xcrun', 'swiftc', *SWIFT_ISOLATION_FLAGS, '-warnings-as-errors', '-parse-as-library',
                       *map(str, sources), '-module-cache-path', str(work / 'modules'), '-o', str(binary)]
            save('inputs.json', json.dumps({**inputs, 'compile': command}, indent=2) + '\n')
            for path in sources:
                if path.parent == work: save(path.name, path.read_text())
            execute(command, 'compile', 180)
            execute([str(binary), str(cases), 'setup'], 'setup', 30)
            for phase in ('initial', 'changed'):
                if phase == 'changed': execute([str(binary), str(cases), 'mutate'], 'mutate', 30)
                result = json.loads(execute([str(binary), str(cases), phase], phase, 45).stdout)
                save(phase + '-results.json', json.dumps(result, indent=2) + '\n')
                self.assertEqual(set(result['checks']), CHECKS)
                self.assertEqual(set(result['workChecks']), WORK_CHECKS)
                for group in ('checks', 'workChecks'):
                    for name, passed in result[group].items():
                        with self.subTest(phase=phase, group=group, name=name): self.assertTrue(passed, result)
                self.assertEqual(inputs['inputs'], {path: digest(ROOT / path) for path in inputs['inputs']})


if __name__ == '__main__':
    unittest.main()
