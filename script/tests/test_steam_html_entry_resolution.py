"""Exercise the real HTML entry resolver and its unchanged admission boundaries.

The old ordering oracle consumes the exact candidate array admitted by one
production enumeration. It never enumerates a second time to predict tie order.
Only a pure selection tie check supplies distinct literal URLs without filesystem
admission; all real guard cases still run the complete production resolver.
"""
import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

from script.tests.test_ui_library_algorithms import declaration
from script.tests.test_video_thumbnail_prefetch import SWIFT_ISOLATION_FLAGS


ROOT = Path(__file__).resolve().parents[2]
OWNER = ROOT / 'MyWallpaperX/Modules/SteamWorkshop/Core/SteamWorkshopService+LibraryRecords.swift'
FIXTURE = ROOT / 'script/tests/fixtures/SteamHTMLResolutionHarness.swift'
CHECKS = {
    'emptyDirectoryHasNoEntry', 'missingDirectoryHasNoEntry',
    'nonHTMLFilesAndHTMLNamedDirectoriesAreRejected',
    'rootIndexOutranksNestedIndexDefaultAndOrdinary',
    'nestedIndexOutranksRootDefault', 'defaultOutranksOrdinaryAndResourceFiles',
    'ordinaryOutranksNestedResourceSubtrees', 'shallowOrdinaryEntryPrecedesDeeperEntry',
    'topLevelResourceNamesKeepTheirExistingPriority', 'naturalNumberOrderKeepsTheSameFullURL',
    'uppercaseHTMExtensionIsAccepted', 'preferredNormalizesWhitespaceAndBackslashes',
    'missingAndEmptyPreferredFallBackToRootIndex', 'unsupportedPreferredFallsBackToHTML',
    'preferredHTMLNamedDirectoryIsRejected', 'hiddenFileIsSkippedByFallback',
    'hiddenFileRemainsAvailableAsExplicitPreferred', 'hiddenDirectoryIsSkippedByFallback',
    'hiddenDirectoryRemainsAvailableAsExplicitPreferred', 'packageDescendantsAreSkippedByFallback',
    'packageEntryRemainsAvailableAsExplicitPreferred', 'insideFileSymlinkReturnsCanonicalTarget',
    'outsideFileSymlinkCannotEscapeEntryRoot', 'siblingPrefixSymlinkCannotEscapeEntryRoot',
    'parentTraversalPreferredFallsBackInsideRoot', 'containedRelativeTraversalPreferredStillResolves',
    'rootSymlinkReturnsCanonicalEntry', 'insideDirectorySymlinkPreferredRemainsContained',
    'outsideDirectorySymlinkPreferredCannotEscape', 'outsideFixturesRemainUntouched',
    'sameEnumerationCandidatesMatchFormerSortWinner', 'equivalentRanksKeepFirstAdmittedCandidate',
    'capturedRootsAndCandidatesStayCanonicalAndContained', 'preferredFastPathsDoNotEnumerate',
    'largeCandidateSetKeepsTheFormerEntryChoice',
}


class SteamHTMLEntryResolutionTests(unittest.TestCase):
    def test_real_resolver_order_preference_and_filesystem_admission(self):
        paths = [OWNER, FIXTURE, Path(__file__),
                 ROOT / 'script/tests/test_ui_library_algorithms.py',
                 ROOT / 'script/tests/test_video_thumbnail_prefetch.py']

        def fingerprints():
            return {str(path.relative_to(ROOT)): hashlib.sha256(path.read_bytes()).hexdigest() for path in paths}

        identities = fingerprints()
        owner = OWNER.read_text()
        resolver = declaration(owner, '    nonisolated static func resolveHTMLURL(')
        selection_start = resolver.index('        return candidateURLs.')
        selection_end = resolver.rindex('\n    }')
        selection = resolver[selection_start:selection_end]
        tie_selector = '''    nonisolated static func chooseAdmittedForTieCheck(
        candidateURLs: [URL], normalizedDirectory: URL
    ) -> URL? {
''' + selection + '\n    }'
        admission = '''        candidateURLs = enumerator.compactMap { element in
            guard let url = element as? URL else { return nil }
            return resolvedContainedHTMLURL(url)
        }'''
        self.assertEqual(resolver.count(admission), 1)
        resolver = resolver.replace(admission, admission + '\n'
            '        HTMLResolutionObservation.shared.admitted(candidateURLs, root: normalizedDirectory)', 1)
        comparator = '{ lhs, rhs in'
        self.assertEqual(resolver.count(comparator), 1)
        resolver = resolver.replace(comparator, comparator + '\n'
            '            HTMLResolutionObservation.shared.compared()', 1)
        relative = declaration(owner, '    nonisolated static private func relativePath(')
        template = FIXTURE.read_text()
        for marker, fragment in {
            '// PRODUCTION_RESOLVER_AND_RELATIVE_PATH': resolver + '\n' + relative,
            '// PRODUCTION_PURE_TIE_SELECTOR': tie_selector,
        }.items():
            self.assertEqual(template.count(marker), 1)
            template = template.replace(marker, fragment)
        with tempfile.TemporaryDirectory(prefix='mwx-steam-html-', dir='/private/tmp') as directory:
            work = Path(directory)
            proof = os.environ.get('MWX_STEAM_HTML_PROOF_DIR')
            target = Path(proof) if proof else None
            if target:
                target.mkdir(parents=True, exist_ok=True)

            def save(name, value):
                if target:
                    (target / name).write_text(value)

            save('inputs.json', json.dumps({'inputs': identities, 'flags': SWIFT_ISOLATION_FLAGS,
                'transforms': ['observe admitted candidate array and root after enumeration',
                               'count calls at the unchanged selection comparator entry',
                               'wrap the unmodified final selection statement for pure literal tie inputs'],
                'pureTieSelectionSHA256': hashlib.sha256(selection.encode()).hexdigest(),
                'pureTieScope': 'Distinct literal URLs model already-admitted entries on a case-sensitive volume; no filesystem admission claim.',
                'scope': __doc__}, indent=2) + '\n')
            source = work / 'Harness.swift'
            source.write_text(template)
            binary = work / 'html-entry'
            build = subprocess.run(['xcrun', 'swiftc', *SWIFT_ISOLATION_FLAGS, '-warnings-as-errors',
                '-parse-as-library', str(source), '-module-cache-path', str(work / 'modules'), '-o', str(binary)],
                capture_output=True, text=True, timeout=120)
            save('compile.log', build.stdout + build.stderr)
            self.assertEqual(build.returncode, 0, build.stdout + build.stderr)
            self.assertEqual(identities, fingerprints())
            home, fixtures = work / 'home', work / 'cases'
            home.mkdir()
            fixtures.mkdir()
            run = subprocess.run([str(binary), str(fixtures)],
                env=dict(os.environ, HOME=str(home), CFFIXED_USER_HOME=str(home)),
                capture_output=True, text=True, timeout=30)
            save('runtime.log', run.stderr)
            save('stdout.log', run.stdout)
            self.assertEqual(run.returncode, 0, run.stdout + run.stderr)
            checks = json.loads(run.stdout)
            save('checks.json', json.dumps(checks, indent=2) + '\n')
            self.assertEqual(identities, fingerprints())
            self.assertEqual(set(checks), CHECKS)
            for name, passed in checks.items():
                with self.subTest(name=name):
                    self.assertTrue(passed, run.stderr)


if __name__ == '__main__':
    unittest.main()
