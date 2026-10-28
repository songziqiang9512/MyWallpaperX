"""Exercise production UI projection owners with real Combine/main-queue delivery.

The fixture replaces native grid rendering and product services with recording
boundaries. Online subscription, progress, visibility, organization factory/echo
and data-source provider bodies come from production. The real card gate covers
thumbnail identity and wrong-item rejection; this gate records the producer's
target receipt across deferred native application. Retired Shell/tag owners are covered by the new library
presentation, query, grid, sidebar and inspector gates.
This is an event/output regression gate, not a visual or wall-clock benchmark.
"""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

from script.tests.test_steam_library_interactions import method


ROOT = Path(__file__).resolve().parents[2]
APP = ROOT / 'MyWallpaperX'


def methods(source, signatures):
    return '\n'.join(method(source, signature) for signature in signatures)


class UIProjectionEfficiencyTests(unittest.TestCase):
    def test_production_projection_outputs_and_bounded_work(self):
        pixabay = (APP / 'Modules/Pixabay/UI/AppKitPixabayBrowserGridView.swift').read_text()
        template = (ROOT / 'script/tests/fixtures/UIProjectionEfficiencyHarness.swift').read_text()

        # Keep the real subscription block, including throttle and all low-frequency
        # refreshes. Only setup's unrelated AppKit hierarchy construction is omitted.
        setup = method(pixabay, '    private func setup()')
        bindings = setup[setup.index('        // 订阅 items 变化'):setup.rfind('\n    }')]
        provider = method(pixabay, '    private lazy var dataSource:').replace(
            'private lazy var ', 'lazy var ').replace(
            'NSCollectionViewDiffableDataSource<', 'RecordingDataSource<') + '()'

        fragments = {
            '// ONLINE_BINDINGS': bindings,
            '// ONLINE_PROVIDER': provider,
            '// ONLINE_ORGANIZATION_FACTORY': method(pixabay, '    var makeOrganization:'),
            '// ONLINE_METHODS': methods(pixabay, [
                '    private func applyItems(', '    private func publishListThumbnailTint(', '    private func refreshDownloadProgress(',
                '    private func reloadVisibleItems(', '    private func isItemDownloaded(',
                '    private func primaryAction(', '    private func performPrimaryAction(',
                '    func refreshOrganization(',
                '    private func selectItem(', '    private func updateKeyboardFocus(',
                '    private func updateVisibleThumbnailPriorities(',
                '    private func applyThumbnailDemand(']),
        }
        for marker, fragment in fragments.items():
            self.assertEqual(template.count(marker), 1, marker)
            template = template.replace(marker, fragment)
        with tempfile.TemporaryDirectory(prefix='mwx-ui-projection-', dir='/private/tmp') as directory:
            work = Path(directory)
            source = work / 'Harness.swift'
            source.write_text(template)
            binary = work / 'ui-projection'
            build = subprocess.run([
                'xcrun', 'swiftc', '-parse-as-library', str(source),
                str(APP / 'Shared/UI/ListThumbnailTintSource.swift'),
                str(APP / 'Shared/UI/WallpaperInspectorActions.swift'),
                str(ROOT / 'script/tests/fixtures/ListThumbnailTintCacheLeaves.swift'),
                '-module-cache-path', str(work / 'modules'), '-o', str(binary),
            ], capture_output=True, text=True, timeout=120)
            self.assertEqual(build.returncode, 0, build.stdout + build.stderr)
            home = work / 'home'
            home.mkdir()
            run = subprocess.run([str(binary), str(work / 'downloads')],
                env=dict(os.environ, HOME=str(home), CFFIXED_USER_HOME=str(home)),
                capture_output=True, text=True, timeout=30)
            self.assertEqual(run.returncode, 0, run.stdout + run.stderr)
            checks = json.loads(run.stdout)
            if proof := os.environ.get('MWX_UI_PROJECTION_PROOF_DIR'):
                output = Path(proof)
                output.mkdir(parents=True, exist_ok=True)
                (output / 'checks.json').write_text(json.dumps(checks, indent=2) + '\n')
                (output / 'runtime.log').write_text(run.stderr)
            self.assertEqual(set(checks), {'onlineLowFrequencyStatusDoesNotGuessExternalFileAvailability', 'onlineSourcePublicationRefreshesUnrelatedExternalDownload', 'onlineChangedVisibleWindowUpdatesPriorityInIndexOrder', 'onlineNewItemsGenerationInvalidatesSameVisibleIDPriorityWindow', 'onlineQueuedOldIDProgressCannotReconfigureReplacementAtSameIndex', 'onlineProgressRemovalClearsPreviousValue', 'onlineCompletionKeepsFullLowFrequencyStateRefresh', 'onlineRemovedOldProgressKeyDoesNotTouchReplacementCell', 'onlineRepeatedVisibleWindowSendsOneOrderedPriorityUpdate', 'onlineNewlyVisibleCellUsesCurrentStateWithoutNewProgressEvent', 'onlineThrottledBurstDeliversLatestProgress', 'onlineCombineProviderAndCellActionsDoNotRetainContainer', 'onlineProgressARefreshesAWithoutReconfiguringB', 'onlineReleasedContainerIsNotRevivedByQueuedProgress', 'onlineUnchangedProgressDoesNoCellWork'} | {
                'onlineOrganizationFactorySuppliesOnlyEligibleVisibleCards',
                'onlineDownloadedIDsAloneCannotCreateOrganization',
                'onlineRelationshipEchoUsesVisibleIDsWithoutReconfiguration',
                'onlineOrganizationFactoryWithdrawalRevokesWithoutReconfiguration',
                'onlineOrganizationEchoCarriesNewIDAcrossDeferredSnapshot',
                'onlineDeferredProviderUsesCurrentOrganizationWhenNewCellArrives',
            })
            for name, passed in checks.items():
                with self.subTest(name=name):
                    self.assertTrue(passed)


if __name__ == '__main__':
    unittest.main()
