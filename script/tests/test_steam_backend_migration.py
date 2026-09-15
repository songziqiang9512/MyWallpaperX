"""SK6.1 default-owner and non-destructive upgrade wiring checks."""

from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[2]
CORE = ROOT / "MyWallpaperX/Modules/SteamWorkshop/Core"


class SteamBackendMigrationTests(unittest.TestCase):
    def test_release_default_has_no_persistent_dual_backend_switch(self):
        route = (CORE / "SteamWorkshopService+SteamKitBrowse.swift").read_text()
        gate = route[route.index("    var isSteamKitBrowseEnabled"):route.index(
            "    /// 公开 discovery route")]
        self.assertIn("#if DEBUG", gate)
        self.assertIn("--mwx-legacy-steam-browse", gate)
        self.assertIn("#else\n        return true", gate)
        self.assertNotIn("UserDefaults", gate)
        self.assertNotIn("SteamWorkshop.useSteamKitBrowse", gate)

    def test_all_product_browse_contexts_route_before_legacy_code(self):
        route = (CORE / "SteamWorkshopService+SteamKitBrowse.swift").read_text()
        fetching = (CORE / "SteamWorkshopService+BrowseFetching.swift").read_text()
        entry = fetching[fetching.index("    func fetchBrowserItems"):]
        structured = entry.index("if shouldUseSteamKitStructuredBrowse")
        personal = entry.index("if shouldUseSteamKitPersonal")
        legacy = entry.index("browserFetchTask?.cancel()", personal)
        self.assertLess(structured, personal)
        self.assertLess(personal, legacy)

        pagination = (CORE / "SteamWorkshopService+BrowsePageLoading.swift").read_text()
        self.assertLess(
            pagination.index("if shouldUseSteamKitStructuredBrowse"),
            pagination.index("let browseContext = self.browseContext"),
        )
        self.assertIn("case .author", route)
        self.assertIn("case .details", route)
        self.assertIn("queryClient.author", route)
        self.assertIn("queryClient.details", route)
        item_lookup = route[route.index("    var shouldUseSteamKitItemLookup"):
                            route.index("    var shouldUseSteamKitStructuredBrowse")]
        self.assertNotIn("!source.isPersonal", item_lookup)
        self.assertIn("fetchWorkshopItemViaSteamKit", route)
        presentation = (CORE / "SteamWorkshopService+ItemDetailPresentation.swift").read_text()
        self.assertGreaterEqual(presentation.count("fetchWorkshopItemViaSteamKit"), 3)

    def test_startup_does_not_consume_legacy_auth_runtime_or_html_cache(self):
        service = (CORE / "SteamWorkshopService.swift").read_text()
        initializer = service[service.index("    private init()"):service.index(
            "    /// SK3.3", service.index("    private init()"))]
        rollback_start = initializer.index("if !isSteamKitBrowseEnabled")
        rollback = initializer[rollback_start:initializer.index("#else", rollback_start)]
        self.assertIn("if !isSteamKitBrowseEnabled", rollback)
        self.assertIn("loadAuthenticationState()", rollback)
        self.assertIn("refreshSteamRuntimeStatus()", rollback)
        self.assertIn("loadCachedBrowserItemsIfPossible()", rollback)
        release_start = initializer.index("#else", rollback_start)
        release = initializer[release_start:initializer.index("#endif", release_start)]
        self.assertNotIn("loadAuthenticationState()", release)
        self.assertNotIn("refreshSteamRuntimeStatus()", release)
        self.assertNotIn("loadCachedBrowserItemsIfPossible()", release)
        self.assertNotIn("showLoginPanel()", initializer)
        self.assertIn("restoreSavedSteamSessionIfAuthorized()", initializer)
        self.assertIn("reloadInstalledItems()", initializer)

        fetching = (CORE / "SteamWorkshopService+BrowseFetching.swift").read_text()
        browser_entry = fetching[fetching.index("    func prepareForBrowserEntry"):
                                  fetching.index("    func fetchBrowserItems")]
        self.assertIn("if isSteamKitBrowseEnabled", browser_entry)
        self.assertIn("#if DEBUG", browser_entry)
        self.assertLess(
            browser_entry.index("if isSteamKitBrowseEnabled"),
            browser_entry.index("prepareRuntimeIfNeeded()"),
        )

    def test_job_schema_uses_read_only_legacy_import_sidecar(self):
        store = (CORE / "SteamWorkshopJobStore.swift").read_text()
        self.assertIn('appendingPathComponent("jobs-v3.json")', store)
        self.assertIn('appendingPathComponent("jobs.json")', store)
        self.assertIn("quarantineOnFailure: false", store)
        self.assertIn("save(jobs, history: history)", store)
        self.assertNotIn("removeItem(at: legacyImportURL", store)
        self.assertNotIn("moveItem(at: legacyImportURL", store)

    def test_helper_publishes_creator_identity_for_author_route(self):
        helper = (ROOT / "SteamService/WorkshopQueries.cs").read_text()
        client = (CORE / "SteamWorkshopQueryClient.swift").read_text()
        self.assertIn("creatorSteamId = file.creator == 0 ? null : file.creator.ToString()", helper)
        self.assertIn("let creatorSteamId: String?", client)
        self.assertIn("if let creatorSteamId, !validID(creatorSteamId)", client)


if __name__ == "__main__":
    unittest.main()
