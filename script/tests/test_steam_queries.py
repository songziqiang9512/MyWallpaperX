"""Real query decoder, raw-page store and subscription owner; offline wire and account transitions."""
import pathlib
import subprocess
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
CORE = ROOT / 'MyWallpaperX/Modules/SteamWorkshop/Core'

class SteamQueryTests(unittest.TestCase):
    def test_real_query_and_subscription_owners(self):
        browse = (CORE / 'SteamWorkshopService+SteamKitBrowse.swift').read_text()
        store = browse[browse.index('@MainActor\nfinal class SteamKitBrowseStore'):]
        projection = browse[browse.index('    private func steamKitPersonalPostProcess'):browse.index('\n}\n\n/// 查询条目')]
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
                        'SteamWorkshopQueryClient.swift', 'SteamWorkshopSubscriptionStore.swift', 'SteamWorkshopBrowseFilters.swift']],
                       extracted, ROOT / 'script/tests/fixtures/SteamQueryHarness.swift']
            binary = folder / 'queries'
            subprocess.run(['xcrun', 'swiftc', '-parse-as-library', *map(str, sources), '-o', str(binary)], check=True, timeout=120)
            subprocess.run([str(binary)], check=True, timeout=30)
