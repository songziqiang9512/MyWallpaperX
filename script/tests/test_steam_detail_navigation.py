"""Execute production detail and navigation owners with an offline Steam transport."""
from pathlib import Path
import os
import subprocess
import tempfile
import unittest
from script.tests.test_steam_library_interactions import method

ROOT = Path(__file__).resolve().parents[2]
CORE = ROOT / 'MyWallpaperX/Modules/SteamWorkshop/Core'

class SteamDetailNavigationTests(unittest.TestCase):
    def test_detail_repair_and_author_navigation(self):
        browse = (CORE / 'SteamWorkshopService+SteamKitBrowse.swift').read_text()
        detail = (CORE / 'SteamWorkshopService+ItemDetailPresentation.swift').read_text()
        nav = (CORE / 'SteamWorkshopService+BrowseNavigation.swift').read_text()
        download = (CORE / 'SteamWorkshopService+DownloadSelection.swift').read_text()
        loading = (CORE / 'SteamWorkshopService+BrowsePageLoading.swift').read_text()
        recovery = (CORE / 'SteamWorkshopService+BrowseStateRecovery.swift').read_text()
        models = (CORE / 'SteamWorkshopModels.swift').read_text()
        api = (CORE / 'SteamWorkshopAPIModels.swift').read_text()
        with tempfile.TemporaryDirectory(prefix='mwx-detail-navigation-', dir='/private/tmp') as temporary:
            work = Path(temporary)
            fragments = ['import AppKit\nimport Combine\nimport Foundation']
            fragments += [method(models, start) for start in [
                'nonisolated enum SteamWorkshopPreviewAssetKind',
                'nonisolated struct SteamWorkshopDetailField', 'nonisolated struct SteamWorkshopBrowserItem']]
            fragments += [method(api, start) for start in ['enum SteamWorkshopBrowseContext',
                'struct SteamWorkshopDiscoveryBrowseSnapshot', 'enum SteamWorkshopAuthorReturnDestination',
                'enum SteamWorkshopBrowseSection',
                'nonisolated struct SteamWorkshopDetailCacheSnapshot']]
            cache = (CORE/'SteamWorkshopService+LibraryRecords.swift').read_text()
            fragments.append('enum DiskCacheProbe {\n'
                'enum Constants { static let detailCacheTTL: TimeInterval = 86400 }\n'
                'static func detailCacheFileURL(id: String) -> URL { URL(fileURLWithPath: ProcessInfo.processInfo.environment["HOME"]!).appendingPathComponent(id + ".json") }\n'
                + method(cache, '    nonisolated static func loadDetailCache(') + '\n'
                + method(cache, '    nonisolated static func loadDetailCacheSnapshot(') + '\n}')
            wire = (ROOT / 'script/tests/fixtures/SteamQueryHarness.swift').read_text()
            fragments.append(method(wire, 'final class QueryTransport'))
            fragments.append(browse[browse.index('@MainActor\nfinal class SteamKitBrowseStore'):])
            start = browse.index('extension SteamWorkshopBrowserItem {')
            fragments.append(browse[start:browse.index('/// 分页与代际状态', start)])
            fragments.append('extension SteamWorkshopService {\n' + '\n'.join([
                method(browse, '    func fetchWorkshopItemViaSteamKit('),
                *[method(detail, start) for start in ['    func presentItemDetail(',
                    '    func dismissItemDetail(', '    func cancelSelectedItemDetailRefresh(',
                    '    func refreshSelectedDownloadInspectorDetailIfNeeded(',
                    '    func persistRefreshedDownloadMetadata(',
                    '    private func refreshSelectedBrowserItemDetailIfNeeded(']],
                *[method(nav, start) for start in ['    var canReturnFromBrowse:',
                    '    func showMySubscriptions(', '    func returnFromBrowseSubpage(',
                    '    func enterBrowseSection(', '    func invalidatePersonalBrowseSnapshot(',
                    '    func showAuthorWorkshop(',
                    '    func returnToDiscoveryBrowse(', '    func requestSteamWorkshopBrowserSelection(',
                    '    func updateDisplayedBrowserItems(',
                    '    func makeDiscoveryBrowseSnapshot(', '    func restoreDiscoveryBrowseSnapshot(']],
                method((CORE/'SteamWorkshopService+BrowseHydration.swift').read_text(), '    func mergeBrowserItem('),
                *[method((CORE/'SteamWorkshopService+BrowseFetching.swift').read_text(), start)
                  for start in ['    func prepareForBrowserEntry(', '    func navigateToBrowse(']],
                *[method(download, start) for start in ['    func dismissDownloadInspector(',
                    '    func presentDownloadInspector(']],
                method((CORE/'SteamWorkshopService.swift').read_text(), '    private func observeSteamAccountIdentityForPersonalSources('),
                method(recovery, '    func updateBrowserScrollMetrics('),
                method(recovery, '    func consumePendingBrowserScrollRestoreOffset('),
                method(loading, '    var allowsAutomaticBrowserContinuation:'),
                method(loading, '    func retryLoadingMoreBrowserItems('),
                method((CORE/'SteamWorkshopService+LibraryRecords.swift').read_text(), '    nonisolated static func creatorID(')
            ]) + '\nfunc openDownload(_ item: SteamWorkshopBrowserItem) { presentDownloadInspector(item) }\n}')
            grid = (ROOT/'MyWallpaperX/Modules/SteamWorkshop/UI/AppKitSteamWorkshopBrowserGridView.swift').read_text()
            fragments.append('extension GridProbe {\n' + method(grid, '    private func checkLoadMore(')
                             + '\nfunc check() { checkLoadMore() }\n}')
            actual = work/'ActualOwners.swift'
            actual.write_text('\n'.join(fragments))
            sources = [ROOT/'MyWallpaperX/Core/DaemonKit/DaemonNewlineJSON.swift',
                ROOT/'MyWallpaperX/Core/DaemonKit/DaemonProcessTransport.swift',
                ROOT/'MyWallpaperX/Shared/UI/WallpaperGridScrollView.swift',
                *[CORE/name for name in ['SteamServiceProtocol.swift', 'SteamServiceClient.swift',
                    'SteamWorkshopQueryClient.swift', 'SteamWorkshopSubscriptionStore.swift',
                    'SteamWorkshopBrowseFilters.swift', 'SteamWorkshopAgeRatingSupport.swift',
                    'SteamWorkshopDetailRefreshSupport.swift',
                    'SteamWorkshopService+ParsingUtilities.swift']], actual,
                ROOT/'script/tests/fixtures/SteamDetailNavigationHarness.swift']
            binary = work/'check'
            result = subprocess.run(['xcrun', 'swiftc', '-parse-as-library',
                *map(str,sources), '-o', str(binary)], capture_output=True, text=True, timeout=120)
            self.assertEqual(result.returncode,0,result.stdout+result.stderr)
            result = subprocess.run([str(binary)], env=dict(os.environ, HOME=str(work), CFFIXED_USER_HOME=str(work)),
                capture_output=True,text=True,timeout=30)
            self.assertEqual(result.returncode,0,result.stdout+result.stderr)
            self.assertIn('detail/navigation PASS',result.stdout)

if __name__ == '__main__':
    unittest.main()
