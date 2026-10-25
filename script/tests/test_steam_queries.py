"""Real query decoder, raw-page store and subscription owner; offline wire and account transitions."""
import pathlib
import subprocess
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
CORE = ROOT / 'MyWallpaperX/Modules/SteamWorkshop/Core'

class SteamQueryTests(unittest.TestCase):
    def test_personal_empty_state_uses_live_auth_identity(self):
        view = (ROOT / 'MyWallpaperX/Modules/SteamWorkshop/UI/AppKitSteamWorkshopBrowserView.swift').read_text()
        guidance = view[view.index('    private var personalLoginGuidance: String?'):]
        self.assertIn('service.shouldUseSteamKitPersonal', guidance)
        self.assertIn('!service.steamAuth.isOnline', guidance)
        self.assertIn('请使用工具栏的「登录 Steam」', guidance)
        self.assertIn('service.steamAuth.$steamId.map', view)
        self.assertNotIn('service.showLoginPanel()', guidance)

    def test_real_query_and_subscription_owners(self):
        browse = (CORE / 'SteamWorkshopService+SteamKitBrowse.swift').read_text()
        store = browse[browse.index('@MainActor\nfinal class SteamKitBrowseStore'):]
        projection = browse[browse.index('    private func steamKitStructuredPostProcess'):browse.index('\n}\n\n/// 查询条目')]
        navigation = (CORE / 'SteamWorkshopService+BrowseNavigation.swift').read_text()
        from script.tests.test_steam_library_interactions import method
        reconcile = method(navigation, '    func reconcileSubscriptionWrite(')
        display = method(navigation, '    func updateDisplayedBrowserItems(')
        search_parser = method((CORE / 'SteamWorkshopService+BrowserSupport.swift').read_text(),
                               '    nonisolated static func workshopItemIDSearchID(')
        restoration = '\n'.join(method(navigation, signature) for signature in [
            '    func makeDiscoveryBrowseSnapshot(', '    func restoreDiscoveryBrowseSnapshot(',
            '    func enterBrowseSection(', '    func invalidatePersonalBrowseSnapshot(',
            '    func returnToDiscoveryBrowse('])
        fetching = (CORE / 'SteamWorkshopService+BrowseFetching.swift').read_text()
        restoration += '\n' + method(fetching, '    func prepareForBrowserEntry(') + '\n' + method(fetching, '    func refresh(')
        models = (CORE / 'SteamWorkshopAPIModels.swift').read_text()
        snapshot = method(models, 'enum SteamWorkshopAuthorReturnDestination') + '\n' + models[models.index('enum SteamWorkshopBrowseSection'):models.index('nonisolated struct SteamWorkshopDetailCacheSnapshot')]

        service = (CORE / 'SteamWorkshopService.swift').read_text()
        start = service.index('        store.didReconcileWrite =')
        hook = service[start:service.index('        return store', start)]
        fixture = '''import Foundation
extension Notification.Name { static let appKitSelectItemRequested = Notification.Name("select") }
@MainActor final class Projection {
 let steamKitBrowseStore: SteamKitBrowseStore
 var personalSort = SteamWorkshopPersonalSort.fileSize
 var remoteMembership = false
 lazy var steamSubscriptions: SteamWorkshopSubscriptionStore = {
  let store = SteamWorkshopSubscriptionStore(identity: { 1 }, read: { [unowned self] _ in self.remoteMembership },
   write: { [unowned self] _, subscribed in self.remoteMembership = subscribed })
  // MEMBERSHIP_HOOK
  return store
 }()
 struct MembershipItem {
  let id: String
  var title = "", author = "", summary = "", descriptionText = ""
  var tags: [String] = []
 }
 struct BrowseContext { var isAuthorWorkshop = false; static var discovery: Self { Self() } }
 var browseContext = BrowseContext()
 struct Auth { var isOnline = true; var steamId: String? = "a" }
 var steamAuth = Auth()
 var browserContentMode = SteamWorkshopBrowserContentMode.all
 var facetFilters = SteamWorkshopBrowseFacetFilters.none
 var browserState = SteamWorkshopBrowserLoadState.loaded
 var selectedBrowserItemError: String?
 var isRefreshingSelectedBrowserItem = false
 var currentPageTitle = ""
 var currentWorkshopItemID: String?
 var selectedBrowserItem: MembershipItem?
 var currentBrowserScrollOffsetY: CGFloat = 500
 var pendingBrowserScrollRestoreOffset: CGFloat?
 var navigations = 0
 var navigationVersion = 0
 var suppressAutomaticBrowseNavigation = false
 var retainedBrowseSections: [SteamWorkshopBrowseSection: SteamWorkshopDiscoveryBrowseSnapshot] = [:]
 var authorWorkshopReturnDestination: SteamWorkshopAuthorReturnDestination?
 var currentDownloadsScrollOffsetY: CGFloat = 0
 var pendingDownloadsScrollRestoreOffsetY: CGFloat?
 var discoveryBrowseSnapshot: SteamWorkshopDiscoveryBrowseSnapshot?
 var savedDiscoveryQueryBeforeAuthorBrowse: String?
 func dismissItemDetail() { selectedBrowserItem = nil }
 func cancelSelectedItemDetailRefresh() {}
 func dismissDownloadInspector() {}
 func setBrowserQuery(_ value: String) { browserQuery = value }
 func navigateToBrowse() { navigations += 1 }
 var browserQuery = ""
 var hasMoreBrowserItems = false
 var displayedBrowserItems: [MembershipItem] = []
 var browserItems: [MembershipItem] = [] { didSet { updateDisplayedBrowserItems() } }
 var shouldUseSteamKitPersonal = true
 var shouldUseSteamKitStructuredBrowse = false
 var browserFetchTask: Task<Void, Never>?
 var isLoadingMoreBrowserItems = false
 var isRefreshingBrowserFeed = false
 var browserLoadMoreFailureMessage: String?
 var browserLoadMoreRetryAfter = Date.distantPast
 var consecutiveEmptyLoadMorePages = 0
 var statusMessage = ""
 var refreshes = 0
 // SOURCE_ID_SEARCH_PARSER
 func loadMoreBrowserItemsIfNeeded() {}
 func fetchBrowserItems(forceRefresh: Bool) { refreshes += 1 }
 var source = SteamWorkshopSource.mySubscriptions
 var trendingWindow = SteamWorkshopTrendingWindow.allTime
 init(_ store: SteamKitBrowseStore) { steamKitBrowseStore = store }
''' + projection.replace('private func steamKitStructuredPostProcess', 'func steamKitStructuredPostProcess')\
    .replace('private func steamKitPersonalPostProcess', 'func steamKitPersonalPostProcess') + '\n' + reconcile + '\n' + display + '\n' + restoration + '\n}\n' + snapshot + '\ntypealias SteamWorkshopBrowserItem = Projection.MembershipItem\n' + store
        fixture = fixture.replace('// MEMBERSHIP_HOOK', hook).replace('// SOURCE_ID_SEARCH_PARSER', search_parser)
        with tempfile.TemporaryDirectory(prefix='mwx-steam-queries-') as folder:
            folder = pathlib.Path(folder)
            extracted = folder / 'ActualBrowseStore.swift'
            extracted.write_text(fixture)
            sources = [ROOT / 'MyWallpaperX/Models/WallpaperReference.swift',
                       ROOT / 'MyWallpaperX/Core/DaemonKit/DaemonNewlineJSON.swift',
                       ROOT / 'MyWallpaperX/Core/DaemonKit/DaemonProcessTransport.swift',
                       *[CORE / name for name in ['SteamServiceProtocol.swift', 'SteamServiceClient.swift',
                        'SteamWorkshopQueryClient.swift', 'SteamWorkshopSubscriptionStore.swift',
                        'SteamWorkshopBrowseFilters.swift', 'SteamWorkshopAgeRatingSupport.swift']],
                       extracted, ROOT / 'script/tests/fixtures/SteamQueryHarness.swift']
            binary = folder / 'queries'
            subprocess.run(['xcrun', 'swiftc', '-parse-as-library', *map(str, sources), '-o', str(binary)], check=True, timeout=120)
            subprocess.run([str(binary)], check=True, timeout=30)
