"""Single-backend routing without retired acquisition state or startup cleanup."""

from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[2]
MODULE = ROOT / "MyWallpaperX/Modules/SteamWorkshop"
CORE = MODULE / "Core"


class SteamBackendMigrationTests(unittest.TestCase):
    def test_every_product_browse_context_has_one_structured_route(self):
        route = (CORE / "SteamWorkshopService+SteamKitBrowse.swift").read_text()
        fetching = (CORE / "SteamWorkshopService+BrowseFetching.swift").read_text()
        pagination = (CORE / "SteamWorkshopService+BrowsePageLoading.swift").read_text()

        self.assertNotIn("isSteamKitBrowseEnabled", route + fetching + pagination)
        self.assertNotIn("mwx-legacy-steam-browse", route + fetching + pagination)
        self.assertIn("if shouldUseSteamKitStructuredBrowse", fetching)
        self.assertIn("fetchDiscoveryViaSteamKit", fetching)
        self.assertIn("fetchPersonalViaSteamKit", fetching)
        self.assertIn("loadMoreDiscoveryViaSteamKitIfNeeded", pagination)
        self.assertIn("loadMorePersonalViaSteamKitIfNeeded", pagination)
        self.assertNotIn("URLSession.shared.data(from:", fetching + pagination)

        self.assertIn("case .author", route)
        self.assertIn("case .details", route)
        self.assertIn("queryClient.author", route)
        self.assertIn("queryClient.details", route)
        presentation = (CORE / "SteamWorkshopService+ItemDetailPresentation.swift").read_text()
        self.assertGreaterEqual(presentation.count("fetchWorkshopItemViaSteamKit"), 3)
        self.assertNotIn("fetchPublishedFileDetails", presentation)

    def test_startup_does_not_consume_retired_auth_runtime_or_html_cache(self):
        service = (CORE / "SteamWorkshopService.swift").read_text()
        initializer = service[service.index("    private init()"):service.index(
            "    /// SK3.3", service.index("    private init()"))]
        retired_calls = (
            "loadAuthenticationState", "refreshSteamRuntimeStatus",
            "loadCachedBrowserItemsIfPossible", "prepareRuntimeIfNeeded",
            "showLoginPanel", "presentCommunityLogin",
        )
        for call in retired_calls:
            self.assertNotIn(call, initializer)
        self.assertIn("restoreSavedSteamSessionIfAuthorized()", initializer)
        self.assertIn("reloadInstalledItems()", initializer)

        all_source = "\n".join(
            path.read_text(errors="ignore")
            for path in MODULE.rglob("*.swift")
        )
        for symbol in (
            "SteamCommunitySessionController", "SteamWorkshopBrowseStub",
            "SteamWorkshopBundledRuntimeMetadata", "SteamWorkshopBrowserCacheSnapshot",
            "isSteamKitBrowseEnabled", "isLoginSheetPresented", "steamUsername",
            "steamPassword", "steamGuardCode", "browserNextPage",
        ):
            self.assertNotIn(symbol, all_source)


    def test_retired_acquisition_cleanup_is_absent(self):
        service = (CORE / "SteamWorkshopService.swift").read_text()
        self.assertNotIn("SteamWorkshopLegacyAcquisitionRetirement", service)
        self.assertFalse((CORE / "SteamWorkshopLegacyAcquisitionRetirement.swift").exists())

    def test_structured_details_publish_dependency_and_creator_identity(self):
        helper = (ROOT / "SteamService/WorkshopQueries.cs").read_text()
        client = (CORE / "SteamWorkshopQueryClient.swift").read_text()
        self.assertIn("return_children = true", helper)
        self.assertIn("includechildren = true", helper)
        self.assertIn("dependencyIds", helper)
        self.assertIn("creatorSteamId = file.creator == 0 ? null : file.creator.ToString()", helper)
        self.assertIn("let dependencyIds: [String]", client)
        self.assertIn("let creatorSteamId: String?", client)
        self.assertIn("if let creatorSteamId, !validID(creatorSteamId)", client)
        self.assertIn("Set(dependencyIds).count == dependencyIds.count", client)

    def test_public_web_links_remain_display_actions_only(self):
        links = (CORE / "SteamWorkshopService+URLBuilders.swift").read_text()
        self.assertIn("makeDetailURL", links)
        self.assertIn("normalizedAuthorWorkshopURL", links)
        self.assertNotIn("URLSession", links)
        self.assertNotIn("WKWebView", links)



if __name__ == "__main__":
    unittest.main()
