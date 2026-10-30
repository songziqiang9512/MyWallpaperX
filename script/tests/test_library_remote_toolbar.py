"""Real remote toolbar factories and native overflow with recording service leaves."""
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

from script.tests.test_video_thumbnail_prefetch import SWIFT_ISOLATION_FLAGS
from script.tests.test_steam_library_interactions import method
from script.tests.native_app_harness import prepare_native_app, run_native_app
from script.tests.test_ui_library_algorithms import declaration

ROOT = Path(__file__).resolve().parents[2]


BROWSER_PREVIEW_LEAF = '''
    var browserPreviews: [WallpaperReference: URL] = [:]
    var browserPreviewRequests: [WallpaperReference] = []
    func browserItemForDownload(id: String) -> ToolbarPreviewItem? {
        let reference = WallpaperReference(provider: .steamWorkshop, sourceID: id)
        browserPreviewRequests.append(reference)
        return browserPreviews[reference].map { ToolbarPreviewItem(previewImageURL: $0) }
    }
'''


TASK_SNAPSHOT_PREVIEW_CHECKS = r'''
        do {
            let priorDownloads = service.downloads, priorJobs = service.downloadJobStore.jobs
            let priorHistory = service.downloadJobStore.history, priorToken = service.previewReloadToken
            let priorPreviews = service.browserPreviews, priorRequests = service.browserPreviewRequests
            let priorLookups = service.latestDownloadRecordCalls
            defer {
                service.downloads = priorDownloads; service.downloadJobStore.jobs = priorJobs
                service.downloadJobStore.history = priorHistory; service.previewReloadToken = priorToken
                service.browserPreviews = priorPreviews; service.browserPreviewRequests = priorRequests
                service.latestDownloadRecordCalls = priorLookups
            }
            let recordURL = URL(string: "https://fixture.invalid/record.jpg")!
            let browserURL = URL(string: "https://fixture.invalid/browser.jpg")!
            let skippedURL = URL(string: "https://fixture.invalid/duplicate.jpg")!
            let decomposedID = "e\u{301}", composedID = "\u{e9}"
            func reference(_ item: String) -> WallpaperReference { .init(provider: .steamWorkshop, sourceID: item) }
            func row(_ item: String, in rows: [DownloadTaskRow]) -> DownloadTaskRow? {
                rows.first { $0.id.reference == reference(item) }
            }
            func history(_ id: String, item: String, owner: String, outcome: SteamDownloadHistoryOutcome = .completed) -> SteamDownloadHistoryEntry {
                .init(jobID: id, workshopItemId: item, title: id, accountSteamId: owner, attempt: 1,
                    outcome: outcome, failureMessage: nil, recordID: nil, terminalAt: Date(timeIntervalSince1970: 2))
            }
            service.downloads = [
                .init(id: "record-preview", status: .ready, previewURL: recordURL),
                .init(id: "duplicate-preview", status: .ready),
                .init(id: "duplicate-preview", status: .ready, previewURL: skippedURL),
                .init(id: "ready-history", status: .ready, previewURL: recordURL),
                .init(id: decomposedID, status: .ready, previewURL: recordURL)]
            service.browserPreviews = Dictionary(uniqueKeysWithValues:
                ["record-preview", "duplicate-preview", "browser-only", "missing-history", composedID].map { (reference($0), browserURL) })
            service.browserPreviewRequests = []; service.latestDownloadRecordCalls = 0; service.previewReloadToken = 17
            service.downloadJobStore.jobs = ["record-preview", "duplicate-preview", "browser-only", "missing-preview"].enumerated().map {
                job("preview-\($0.offset)", item: $0.element, state: .running, account: account, ordinal: $0.offset)
            }
            service.downloadJobStore.history = [
                history("ready", item: "ready-history", owner: account),
                history("missing", item: "missing-history", owner: account),
                history("foreign", item: "foreign-history", owner: "other-account"),
                history("active", item: "browser-only", owner: account, outcome: .failed),
                history("decomposed", item: decomposedID, owner: account),
                history("composed", item: composedID, owner: account)]
            let previewSnapshot = taskCommands.snapshot()
            checks["task-snapshot-uses-published-preview-before-browser-fallback"] =
                row("record-preview", in: previewSnapshot.active)?.thumbnailKey == recordURL.absoluteString + ":17"
                && !service.browserPreviewRequests.contains(reference("record-preview"))
            checks["task-snapshot-first-duplicate-with-nil-preview-keeps-browser-fallback"] =
                row("duplicate-preview", in: previewSnapshot.active)?.thumbnailKey == browserURL.absoluteString + ":17"
            checks["task-snapshot-missing-record-keeps-browser-or-empty-preview"] =
                previewSnapshot.active.count == 4
                && row("browser-only", in: previewSnapshot.active)?.thumbnailKey == browserURL.absoluteString + ":17"
                && row("missing-preview", in: previewSnapshot.active)?.thumbnailKey == nil
            checks["task-snapshot-history-keeps-ready-reveal-missing-retry-and-account-gating"] =
                row("ready-history", in: previewSnapshot.history)?.actions == [.removeHistory, .revealFile]
                && row("ready-history", in: previewSnapshot.history)?.thumbnailKey == recordURL.absoluteString + ":17"
                && row("missing-history", in: previewSnapshot.history)?.actions == [.removeHistory, .retry]
                && row("missing-history", in: previewSnapshot.history)?.thumbnailKey == browserURL.absoluteString + ":17"
                && row("foreign-history", in: previewSnapshot.history)?.actions == [.removeHistory]
                && row("browser-only", in: previewSnapshot.history)?.actions == [.removeHistory]
            checks["task-snapshot-keeps-byte-distinct-record-previews-and-actions-separate"] =
                reference(decomposedID) != reference(composedID)
                && row(decomposedID, in: previewSnapshot.history)?.thumbnailKey == recordURL.absoluteString + ":17"
                && row(decomposedID, in: previewSnapshot.history)?.actions == [.removeHistory, .revealFile]
                && row(composedID, in: previewSnapshot.history)?.thumbnailKey == browserURL.absoluteString + ":17"
                && row(composedID, in: previewSnapshot.history)?.actions == [.removeHistory, .retry]
            checks["task-snapshot-does-not-repeat-record-array-lookups"] = service.latestDownloadRecordCalls == 0
            service.latestDownloadRecordCalls = 0
            checks["real-record-accessor-keeps-byte-distinct-identities"] = service.latestDownloadRecord(for: composedID) == nil
                && service.latestDownloadRecordCalls == 1
            service.downloads = [.init(id: "record-preview", status: .ready, previewURL: skippedURL)]
            let freshPreview = taskCommands.steamPreviewURL(id: "record-preview",
                publishedPreviewURL: service.latestDownloadRecord(for: "record-preview")?.previewURL)
            checks["thumbnail-url-consumer-can-use-the-current-record-after-a-snapshot"] = freshPreview == skippedURL
                && service.latestDownloadRecordCalls == 2
        }
'''


class LibraryRemoteToolbarTests(unittest.TestCase):
    def test_online_image_menu_disables_duplicate_starts_during_transfer(self):
        app = ROOT / 'MyWallpaperX/App/WallpaperLibraryOnlineImages.swift'
        commands = ROOT / 'MyWallpaperX/App/WallpaperLibraryCommands.swift'
        recovery = ROOT / 'MyWallpaperX/App/WallpaperLibraryDownloadRecovery.swift'
        fixture = ROOT / 'script/tests/fixtures/OnlineImageMenuHarness.swift'
        sources = [ROOT / 'MyWallpaperX' / path for path in [
            'Shared/Components/ActionMenuItem.swift', 'Shared/UI/WallpaperInspectorActions.swift', 'Shared/UI/WallpaperOpenWithMenu.swift', 'Models/WallpaperReference.swift',
            'Models/WallpaperContent.swift', 'Models/WallpaperLibraryPage.swift', 'Core/OnlineImages/OnlineImageModels.swift',
            'Core/OnlineImages/OnlineImageContentProjection.swift']]
        observed = [app, commands, recovery, fixture, *sources, Path(__file__),
                    ROOT / 'script/tests/test_steam_library_interactions.py',
                    ROOT / 'script/tests/test_ui_library_algorithms.py']
        hashes = {str(path): hashlib.sha256(path.read_bytes()).hexdigest() for path in observed}
        actual = '\n'.join(method(app.read_text(), name) for name in (
            '    private func menu(', '    private func downloadFirst(', '    private func page(',
            '    func selectedPrimaryAction(', '    func selectedOrganizationActions('))
        self.assertEqual(actual.count('NSWorkspace.shared.open('), 1)
        actual = actual.replace('NSWorkspace.shared.open(', 'MenuBrowser.open(')
        actual_recovery = declaration(recovery.read_text(), '@MainActor enum WallpaperLibraryDownloadRecovery')
        self.assertEqual(actual_recovery.count('NSWorkspace.shared.open('), 1)
        actual_recovery = actual_recovery.replace('@MainActor enum ', '@MainActor private enum ', 1)
        actual_recovery = actual_recovery.replace('NSWorkspace.shared.open(', 'MenuBrowser.open(')
        template = fixture.read_text()
        self.assertEqual(template.count('// ACTUAL_IMAGE_MENU'), 1)
        for marker, body in {
            '// ACTUAL_LIBRARY_FAVORITE_STATE': declaration(commands.read_text(), 'nonisolated struct WallpaperLibraryFavoriteActionState'),
            '// ACTUAL_LIBRARY_CONTEXT_MENU': declaration(commands.read_text(), '    func contextMenu('),
            '// ACTUAL_LIBRARY_DOWNLOAD_RECOVERY': actual_recovery,
            '// ACTUAL_LIBRARY_PRIMARY': '\n'.join(declaration(commands.read_text(), signature) for signature in (
                '    func makePrimaryAction(', '    func makeApplyAction(')),
        }.items():
            self.assertEqual(template.count(marker), 1)
            template = template.replace(marker, body)
        with tempfile.TemporaryDirectory(prefix='mwx-online-image-menu-', dir='/private/tmp') as directory:
            work = Path(directory)
            frozen = []
            for path in sources:
                target = work / path.name; shutil.copy2(path, target); frozen.append(str(target))
            harness = work / 'Checks.swift'
            harness.write_text(template.replace('// ACTUAL_IMAGE_MENU', actual))
            binary = work / 'checks'
            built = subprocess.run(['xcrun', 'swiftc', *SWIFT_ISOLATION_FLAGS, '-warnings-as-errors', '-parse-as-library',
                *frozen, str(harness), '-module-cache-path', str(work / 'modules'), '-o', str(binary)],
                capture_output=True, text=True, timeout=120)
            self.assertEqual(built.returncode, 0, built.stdout + built.stderr)
            run = subprocess.run([str(binary)], capture_output=True, text=True, timeout=15)
            self.assertEqual(run.returncode, 0, run.stdout + run.stderr)
            self.assertTrue(run.stdout.strip(), run.stderr)
            checks = json.loads(run.stdout)
            self.assertTrue(checks)
            for source in ('wallhaven', 'pixiv'):
                for scenario in (
                    'idle-menu-starts-both-original-download-intents',
                    'idle-actions-keep-the-clicked-artwork-and-apply-meaning',
                    'busy-menu-disables-start-actions-and-keeps-cancel-source-author',
                    'cancel-dispatches-to-the-existing-transfer-and-restores-starts',
                    'held-menu-cannot-start-on-a-different-page',
                    'owned-modal-input-domain-revokes-held-download',
                    'published-content-keeps-native-library-actions-without-download-duplicates',
                    'remote-idle-has-one-source-page',
                    'remote-busy-has-one-source-page',
                    'composed-recovery-retries-the-fixed-reference',
                    'held-page-revokes-recovery-and-source-page',
                    'epoch-and-modal-revoke-recovery-without-losing-webpage',
                    'read-only-recovery-fallback-retains-one-online-source-page',
                    'read-only-source-page-remains-usable',
                    'read-only-busy-keeps-one-cancel',
                    'ordinary-library-keeps-original-recovery-page-and-retry',
                    'ordinary-library-recovery-page-keeps-reference',
                ):
                    self.assertIs(checks[f'{source}-{scenario}'], True, run.stdout + run.stderr)
                for availability in ('available', 'unavailable'):
                    for scenario in (
                        'idle-retains-shared-actions-without-transfer-duplicates',
                        'busy-has-one-shared-cancel-and-keeps-original-actions',
                        'cancel-dispatches-once-to-the-fixed-asset',
                        'held-page-revokes-shared-cancel',
                        'modal-domain-revokes-shared-cancel',
                        'selection-session-revokes-shared-cancel',
                        'reset-revokes-shared-cancel',
                        'next-menu-retains-one-cancel',
                        'idle-has-one-source-page-and-preserves-retry',
                        'busy-has-one-source-page-and-preserves-retry',
                        'source-page-keeps-clicked-artwork',
                    ):
                        self.assertIs(checks[f'{source}-local-{availability}-{scenario}'], True,
                                      run.stdout + run.stderr)
            self.assertIs(checks['pixiv-author-command-remains-available'], True, run.stdout + run.stderr)
            for name, passed in checks.items():
                with self.subTest(name=name): self.assertIs(passed, True, run.stdout + run.stderr)
            print(json.dumps(checks, sort_keys=True))
        self.assertEqual(hashes, {str(path): hashlib.sha256(path.read_bytes()).hexdigest() for path in observed})

    def test_signout_service_keeps_confirmed_account_intent(self):
        service = ROOT / 'MyWallpaperX/Modules/SteamWorkshop/Core/SteamWorkshopService.swift'
        fixture = ROOT / 'script/tests/fixtures/LibraryToolbarSignoutHarness.swift'
        parser = ROOT / 'script/tests/test_steam_library_interactions.py'
        paths = [service, fixture, parser, Path(__file__)]
        hashes = {str(path): hashlib.sha256(path.read_bytes()).hexdigest() for path in paths}
        actual = method(service.read_text(), '    func signOutEverywhere(')
        template = fixture.read_text()
        self.assertEqual(template.count('// PRODUCTION_SIGNOUT'), 1)
        with tempfile.TemporaryDirectory(prefix='mwx-toolbar-signout-', dir='/private/tmp') as directory:
            work = Path(directory)
            source = work / 'Signout.swift'
            source.write_text(template.replace('// PRODUCTION_SIGNOUT', actual))
            binary = work / 'checks'
            build = subprocess.run(['xcrun', 'swiftc', *SWIFT_ISOLATION_FLAGS, '-warnings-as-errors', '-parse-as-library',
                str(source), '-module-cache-path', str(work / 'modules'), '-o', str(binary)],
                capture_output=True, text=True, timeout=120)
            self.assertEqual(build.returncode, 0, build.stdout + build.stderr)
            run = subprocess.run([str(binary)], capture_output=True, text=True, timeout=10)
            self.assertEqual(run.returncode, 0, run.stdout + run.stderr)
            self.assertTrue(run.stdout.strip(), run.stderr)
            checks = json.loads(run.stdout)
            print(json.dumps(checks, sort_keys=True))
            self.assertEqual(len(checks), 11)
            for name, passed in checks.items():
                with self.subTest(name=name): self.assertIs(passed, True, run.stdout + run.stderr)
            self.assertEqual(hashes, {str(path): hashlib.sha256(path.read_bytes()).hexdigest() for path in paths})

    def test_original_source_commands_and_native_overflow(self):
        relative = [
            'Shared/Components/ActionMenuItem.swift', 'Shared/Components/WallpaperLibraryGridMetrics.swift',
            'Shared/Components/WallpaperLibraryZoomControl.swift', 'Shared/UI/ToolbarMenuPopover.swift',
            'Shared/Components/WallpaperLibraryControlStyle.swift',
            'Shared/UI/WallpaperFilterPanelController.swift', 'Shared/UI/WallpaperLibrarySheetPresentation.swift',
            'Models/WallpaperReference.swift', 'Models/WallpaperContent.swift', 'Models/DownloadTask.swift',
            'Core/OnlineImages/OnlineImageModels.swift',
            'Modules/Downloads/Core/DownloadHistoryStore.swift', 'Modules/Downloads/Core/DownloadTaskProjection.swift',
            'Modules/Downloads/UI/DownloadTaskRowView.swift', 'Modules/Downloads/UI/DownloadTasksPopover.swift',
            'Modules/SteamWorkshop/Core/SteamWorkshopBrowseFilters.swift',
            'Modules/SteamWorkshop/Core/SteamWorkshopAgeRatingSupport.swift',
            'Modules/SteamWorkshop/UI/SteamWorkshopFilterPanel.swift',
            'Modules/SteamWorkshop/Core/SteamWorkshopDownloadTaskProjection.swift',
            'Modules/SteamWorkshop/Toolbar/SteamWorkshopToolbarIdentifiers.swift',
            'Modules/SteamWorkshop/Toolbar/SteamWorkshopToolbarController.swift',
            'Modules/SteamWorkshop/Toolbar/SteamWorkshopToolbarController+Actions.swift',
            'Modules/SteamWorkshop/Toolbar/SteamWorkshopToolbarController+Configuration.swift',
            'Modules/SteamWorkshop/Toolbar/SteamWorkshopToolbarController+Layouts.swift',
            'Modules/Pixabay/Core/PixabayModels.swift',
            'Modules/Pixabay/Toolbar/PixabayToolbarController.swift',
            'Modules/Pixabay/Toolbar/PixabayFilterPanel.swift',
        ]
        paths = [ROOT / 'MyWallpaperX' / path for path in relative]
        paths.append(ROOT / 'script/tests/fixtures/NativeAppHarness.swift')
        paths.append(ROOT / 'script/tests/fixtures/NativeFilterPanelSnapshot.swift')
        fixture = ROOT / 'script/tests/fixtures/LibraryRemoteToolbarHarness.swift'
        tasks = ROOT / 'MyWallpaperX/App/DownloadTasksController.swift'
        models = ROOT / 'MyWallpaperX/Modules/SteamWorkshop/Core/SteamWorkshopJobStore.swift'
        service = ROOT / 'MyWallpaperX/Modules/SteamWorkshop/Core/SteamWorkshopService.swift'
        navigation = ROOT / 'MyWallpaperX/Modules/SteamWorkshop/Core/SteamWorkshopService+BrowseNavigation.swift'
        filtering = ROOT / 'MyWallpaperX/Modules/SteamWorkshop/Core/SteamWorkshopService+DownloadFiltering.swift'
        accessors = ROOT / 'MyWallpaperX/Modules/SteamWorkshop/Core/SteamWorkshopService+DownloadAccessors.swift'
        observed = [*paths, fixture, tasks, models, service, navigation, filtering, accessors, Path(__file__), ROOT / 'script/tests/native_app_harness.py',
                    ROOT / 'script/tests/test_ui_library_algorithms.py']
        hashes = {str(path): hashlib.sha256(path.read_bytes()).hexdigest() for path in observed}
        template = fixture.read_text()
        lookup = method(accessors.read_text(), '    func latestDownloadRecord(').replace(
            'SteamWorkshopDownloadRecord', 'ToolbarDownloadRecord')
        lookup = lookup.replace('        downloads.first(', '        latestDownloadRecordCalls += 1\n        return downloads.first(')
        for marker, content in {
            '// ACTUAL_STEAM_QUERY_FIELDS': '\n'.join(declaration(service.read_text(), signature) for signature in [
                '    @Published var source:', '    @Published var browserContentMode:',
                '    @Published var trendingWindow:', '    @Published var facetFilters:',
                '    @Published var personalSort:', '    @Published var browserQuery:']).replace(
                    '            guard !isUpdatingBrowserQueryProgrammatically',
                    '            queries.append(browserQuery)\n            guard !isUpdatingBrowserQueryProgrammatically'),
            '// ACTUAL_STEAM_QUERY_ACTIONS': method(navigation.read_text(), '    func setBrowserQuery(')
                + '\n' + method(filtering.read_text(), '    func clearFilters('),
            '// ACTUAL_TASK_MODELS': '\n'.join(declaration(models.read_text(), signature) for signature in [
                'enum SteamDownloadJobState:', 'struct SteamDownloadJob:',
                'enum SteamDownloadHistoryOutcome:', 'struct SteamDownloadHistoryEntry:']),
            '// ACTUAL_TASK_COMMANDS': '\n'.join(method(tasks.read_text(), signature) for signature in [
                '    func makePopoverController(', '    private func snapshot(', '    private func perform(',
                '    private func clearHistory(', '    private func steamPhase(', '    private func steamPreviewURL(']),
            '// ACTUAL_DOWNLOAD_LOOKUP': '    var latestDownloadRecordCalls = 0\n' + lookup,
            '// BROWSER_PREVIEW_LEAF': BROWSER_PREVIEW_LEAF,
            '// TASK_SNAPSHOT_PREVIEW_CHECKS': TASK_SNAPSHOT_PREVIEW_CHECKS,
        }.items():
            self.assertEqual(template.count(marker), 1)
            template = template.replace(marker, content)
        with tempfile.TemporaryDirectory(prefix='mwx-remote-toolbar-', dir='/private/tmp') as directory:
            work = Path(directory)
            copies = []
            for path in paths:
                copied = work / path.name
                shutil.copy2(path, copied)
                copies.append(str(copied))
            harness = work / 'Checks.swift'; harness.write_text(template); copies.append(str(harness))
            binary = prepare_native_app(work, 'LibraryRemoteToolbar')
            build = subprocess.run(['xcrun', 'swiftc', *SWIFT_ISOLATION_FLAGS, '-warnings-as-errors', '-parse-as-library',
                *copies, '-module-cache-path', str(work / 'modules'), '-o', str(binary)],
                capture_output=True, text=True, timeout=120)
            self.assertEqual(build.returncode, 0, build.stdout + build.stderr)
            run = run_native_app(binary, timeout=35)
            self.assertEqual(run.launch_returncode, 0, run.stdout + run.stderr)
            self.assertTrue(run.stdout.strip(), run.stderr)
            checks = json.loads(run.stdout)
            self.assertTrue(checks)
            print(json.dumps(checks, sort_keys=True))
            for name, passed in checks.items():
                with self.subTest(name=name): self.assertIs(passed, True, run.stdout + run.stderr)
            self.assertEqual(hashes, {str(path): hashlib.sha256(path.read_bytes()).hexdigest() for path in observed})


if __name__ == '__main__':
    unittest.main()
