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
        fixture = '''import Foundation
@MainActor final class Projection {
 let steamKitBrowseStore: SteamKitBrowseStore
 var personalSort = SteamWorkshopPersonalSort.fileSize
 var source = SteamWorkshopSource.mySubscriptions
 var trendingWindow = SteamWorkshopTrendingWindow.allTime
 init(_ store: SteamKitBrowseStore) { steamKitBrowseStore = store }
''' + projection.replace('private func steamKitPersonalPostProcess', 'func steamKitPersonalPostProcess') + '\n}\n' + store
        with tempfile.TemporaryDirectory(prefix='mwx-steam-queries-') as folder:
            folder = pathlib.Path(folder)
            extracted = folder / 'ActualBrowseStore.swift'
            extracted.write_text(fixture)
            sources = [ROOT / 'MyWallpaperX/Core/DaemonKit/DaemonNewlineJSON.swift',
                       ROOT / 'MyWallpaperX/Core/DaemonKit/DaemonProcessTransport.swift',
                       *[CORE / name for name in ['SteamServiceProtocol.swift', 'SteamServiceClient.swift',
                        'SteamWorkshopQueryClient.swift', 'SteamWorkshopSubscriptionStore.swift',
                        'SteamWorkshopBrowseFilters.swift', 'SteamWorkshopAgeRatingSupport.swift']],
                       extracted, ROOT / 'script/tests/fixtures/SteamQueryHarness.swift']
            binary = folder / 'queries'
            subprocess.run(['xcrun', 'swiftc', '-parse-as-library', *map(str, sources), '-o', str(binary)], check=True, timeout=120)
            subprocess.run([str(binary)], check=True, timeout=30)
