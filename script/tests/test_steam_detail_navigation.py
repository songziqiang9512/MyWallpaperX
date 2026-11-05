"""Execute production detail and navigation owners with an offline Steam transport."""
from pathlib import Path
import os
import json
import subprocess
import tempfile
import unittest
from script.tests.test_steam_library_interactions import method

ROOT = Path(__file__).resolve().parents[2]
CORE = ROOT / 'MyWallpaperX/Modules/SteamWorkshop/Core'

class SteamDetailNavigationTests(unittest.TestCase):
    def test_inspector_publications_use_current_selection_and_own_close_token(self):
        source = (ROOT / 'MyWallpaperX/Modules/SteamWorkshop/UI/AppKitSteamWorkshopBrowserView.swift').read_text()
        observer = method(source, '        service.$selectedBrowserItem') + '.store(in: &cancellables)'
        host_observer = method(source, '    private func observeInspectorHost(')
        host_observer = host_observer[host_observer.index('        NotificationCenter.default.publisher(for: .inspectorHostDidPresent)'):].split('\n\n', 1)[0]
        methods = '\n'.join(method(source, signature) for signature in (
            '    private func syncSelectedInspectorItem(', '    private func makePresentation(',
            '    private func handleInspectorDidPresent(', '    private func handleInspectorDidClose('))
        harness = r'''
import AppKit
import Combine
enum ModuleIdentifier: String { case steamWorkshop, videoLibrary }
extension Notification.Name {
    static let inspectorHostOpenRequested = Notification.Name("open")
    static let inspectorHostCloseRequested = Notification.Name("close")
    static let inspectorHostMountContentRequested = Notification.Name("mount")
    static let inspectorHostDidPresent = Notification.Name("present")
}
struct SteamWorkshopBrowserItem { let id: String; var title: String { id }; var author: String { "Author" } }
@MainActor final class DetailServiceLeaf {
    @Published var selectedBrowserItem: SteamWorkshopBrowserItem?
    var currentPageTitle = "Workshop", dismissals = 0
    func dismissItemDetail() { dismissals += 1; selectedBrowserItem = nil }
}
@MainActor final class BrowserInspectorProbe {
    let service = DetailServiceLeaf()
    var cancellables = Set<AnyCancellable>()
    var latestInspectorItem: SteamWorkshopBrowserItem?
    var visibleCardID: String?, lastRequestedCardID: String?
    var isHandlingHostClose = false
    var removals = 0, installs: [String] = []
    func bind() { // OBSERVER
        // HOST_OBSERVER
    }
    func installInspectorContent(for item: SteamWorkshopBrowserItem) { installs.append(item.id) }
    func removeInspectorContent() { removals += 1 }
    // METHODS
}
@main struct Checks {
    @MainActor static func main() async throws {
        let probe = BrowserInspectorProbe()
        var opened: [String] = []
        let observation = NotificationCenter.default.addObserver(forName: .inspectorHostOpenRequested,
            object: nil, queue: .main) { note in
            if let request = InspectorHostRequest(userInfo: note.userInfo) { opened.append(request.token.cardID) }
        }
        defer { NotificationCenter.default.removeObserver(observation) }
        func note(_ id: String, module: ModuleIdentifier = .steamWorkshop) -> Notification {
            let request = InspectorHostRequest(token: .init(module: module, cardID: id), title: id)
            return Notification(name: Notification.Name("host-event"), userInfo: request.userInfo)
        }
        probe.bind()
        probe.service.selectedBrowserItem = .init(id: "old-author-item")
        probe.service.selectedBrowserItem = .init(id: "current-item")
        try await Task.sleep(for: .milliseconds(40))
        var checks = ["queued-publisher-never-reopens-a-superseded-inspector":
            !opened.isEmpty && opened.allSatisfy { $0 == "current-item" }]
        let installsBeforePresent = probe.installs.count
        NotificationCenter.default.post(name: .inspectorHostDidPresent, object: nil, userInfo: note("current-item").userInfo)
        checks["real-host-publisher-installs-current-details-before-post-returns"] =
            probe.installs.count == installsBeforePresent + 1 && probe.installs.last == "current-item"
            && probe.visibleCardID == "current-item"
        let ownInstalls = probe.installs.count
        NotificationCenter.default.post(name: .inspectorHostDidPresent, object: nil,
            userInfo: note("current-item", module: .videoLibrary).userInfo)
        checks["other-module-present-cannot-install-browser-details"] = probe.installs.count == ownInstalls
        NotificationCenter.default.post(name: .inspectorHostDidPresent, object: nil,
            userInfo: note("steamWorkshop:current-item:" + UUID().uuidString).userInfo)
        checks["Coordinator-token-present-cannot-install-browser-details"] = probe.installs.count == ownInstalls
        probe.handleInspectorDidPresent(note("current-item"))
        probe.handleInspectorDidClose(note("old-author-item"))
        checks["old-close-cannot-dismiss-current-browser-details"] = probe.service.selectedBrowserItem?.id == "current-item"
            && probe.visibleCardID == "current-item" && probe.service.dismissals == 0
        probe.service.selectedBrowserItem = .init(id: "current-item")
        try await Task.sleep(for: .milliseconds(40))
        probe.handleInspectorDidPresent(note("current-item"))
        probe.handleInspectorDidClose(note("current-item:local-inspection-lease"))
        checks["local-download-close-cannot-dismiss-browser-owned-inspector"] = probe.service.selectedBrowserItem?.id == "current-item"
            && probe.visibleCardID == "current-item" && probe.service.dismissals == 0
        probe.visibleCardID = "retired-item"; probe.lastRequestedCardID = "retired-item"
        probe.service.selectedBrowserItem = .init(id: "current-item")
        probe.handleInspectorDidClose(note("retired-item"))
        checks["visible-old-close-before-new-publication-keeps-new-source-selection"] =
            probe.service.selectedBrowserItem?.id == "current-item" && probe.service.dismissals == 0
        try await Task.sleep(for: .milliseconds(40))
        probe.handleInspectorDidPresent(note("current-item"))
        let previousDismissals = probe.service.dismissals
        probe.handleInspectorDidClose(note("current-item"))
        checks["matching-browser-close-still-releases-details-once"] = probe.service.selectedBrowserItem == nil
            && probe.visibleCardID == nil && probe.lastRequestedCardID == nil && probe.service.dismissals == previousDismissals + 1
        probe.handleInspectorDidClose(note("current-item"))
        checks["duplicate-close-cannot-repeat-source-dismissal"] = probe.service.dismissals == previousDismissals + 1
        print(String(data: try JSONSerialization.data(withJSONObject: checks, options: [.sortedKeys]), encoding: .utf8)!)
    }
}
'''.replace('// OBSERVER', observer).replace('// HOST_OBSERVER', host_observer).replace('// METHODS', methods)
        with tempfile.TemporaryDirectory(prefix='mwx-browser-inspector-', dir='/private/tmp') as directory:
            work = Path(directory); actual = work / 'Checks.swift'; actual.write_text(harness)
            sources = [ROOT / 'MyWallpaperX/Shared/UI' / name for name in (
                'InspectorHost.swift', 'InspectorHostBridge.swift', 'InspectorHostActions.swift')]
            binary = work / 'checks'
            result = subprocess.run(['xcrun', 'swiftc', '-parse-as-library', '-swift-version', '5',
                '-default-isolation', 'MainActor', *map(str, sources), str(actual), '-o', str(binary)],
                capture_output=True, text=True, timeout=60)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            result = subprocess.run([str(binary)], capture_output=True, text=True, timeout=10)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            checks = json.loads(result.stdout)
            for name, value in checks.items():
                with self.subTest(name=name): self.assertIs(value, True)

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
            sources = [ROOT/'MyWallpaperX/Models/WallpaperReference.swift', ROOT/'MyWallpaperX/Models/WallpaperContent.swift',
                ROOT/'MyWallpaperX/Core/DaemonKit/DaemonNewlineJSON.swift',
                ROOT/'MyWallpaperX/Core/DaemonKit/DaemonProcessTransport.swift',
                ROOT/'MyWallpaperX/Shared/UI/WallpaperGridScrollView.swift',
                ROOT/'MyWallpaperX/Shared/ThumbnailRequest.swift',
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
