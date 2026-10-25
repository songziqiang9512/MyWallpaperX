"""Real primary-action factory, native action dispatch and async SQLite Undo.

Commands use controlled source/page/renderer leaves. This does not drive a full
Shell, user library, media renderer or present a real modal sheet.
"""
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest
from script.tests.test_ui_library_algorithms import declaration
from script.tests.test_video_thumbnail_prefetch import SWIFT_ISOLATION_FLAGS

ROOT = Path(__file__).resolve().parents[2]


class WallpaperLibraryCommandTransactionsTests(unittest.TestCase):
    def test_native_fixed_action_and_real_organization_undo(self):
        paths = [ROOT / 'MyWallpaperX' / p for p in (
            'Models/WallpaperReference.swift', 'Models/WallpaperContent.swift', 'Models/WallpaperLibraryPage.swift',
            'Models/WallpaperSourceImportResult.swift',
            'Core/LibraryCollections/UserCollectionsStore.swift', 'Core/LibraryCollections/UserCollectionsController.swift',
            'Core/LibraryCollections/WallpaperLibraryQuery.swift',
            'Shell/WallpaperLibraryPresentation.swift',
            'Core/PlaybackControl/WallpaperRuntimeSwitch.swift', 'Core/PlaybackControl/PlaybackSwitchTransaction.swift',
            'Core/PlaybackControl/WallpaperPlaybackSequence.swift', 'Shared/Components/ActionMenuItem.swift',
            'Shared/Components/WallpaperLibrarySymbols.swift',
            'Shared/UI/WallpaperInspectorActions.swift',
            'App/WallpaperLibraryRelationshipUndo.swift')]
        commands = (ROOT / 'MyWallpaperX/App/WallpaperLibraryCommands.swift').read_text()
        factory = '\n'.join(declaration(commands, signature) for signature in (
            '    func makePrimaryAction(', '    func makeApplyAction(', '    func stop('))
        fixture = (ROOT / 'script/tests/fixtures/WallpaperLibraryCommandTransactionsHarness.swift').read_text()
        fixture = fixture.replace('// ACTUAL_PRIMARY_FACTORY', factory)
        fixture = fixture.replace('// ACTUAL_PLAYLIST_MENU', declaration(commands, '    func makePlaylistMenu('))
        fixture = fixture.replace('// ACTUAL_FAVORITE_STATE', declaration(commands, 'nonisolated struct WallpaperLibraryFavoriteActionState'))
        fixture = fixture.replace('// ACTUAL_CARD_STATE', declaration(commands, 'nonisolated struct WallpaperLibraryCardStateProjection'))
        fixture = fixture.replace('// ACTUAL_FAVORITE_COMMANDS', '\n'.join(declaration(commands, signature) for signature in (
            '    var canFavorite:', '    var favoriteActionState:', '    func favoriteActionState(', '    private func favoriteState(',
            '    func toggleFavorite(', '    func makeFavoriteAction(', '    private func resolveSelection(',
            '    var canBeginManualOrdering:', '    func beginManualOrdering(')))
        fixture = fixture.replace('// ACTUAL_RECENT_MENU', '\n'.join(declaration(commands, signature) for signature in (
            '    func makeRecentMenu(', '    private func clearRecent(', '    private func perform(')))
        removal_methods = '\n'.join(declaration(commands, signature) for signature in (
            '    private func removalTitle(', '    func remove(', '    private func removeConfirmed(',
            '    private func deleteSourceFiles('))
        # Observe the actual synchronous command-admission boundary; retain the
        # entire async product transaction so no-op tests cannot pass before a
        # wrongly admitted Task eventually writes to SQLite.
        perform = declaration(commands, '    private func perform(').replace(
            '        let epoch = collections.snapshot.resetEpoch',
            '        admittedWrites += 1\n        let epoch = collections.snapshot.resetEpoch', 1)
        fixture = fixture.replace('// ACTUAL_REMOVAL_COMMANDS', removal_methods + '\n' + perform)
        restoration = '\n'.join(declaration(commands, signature) for signature in (
            '    func makeRestoreLibraryAction(', '    func makeExplicitLibraryRestorationReceipt(',
            '    static func makeExplicitLibraryRestorationReceipt('))
        fixture = fixture.replace('// ACTUAL_RESTORATION_COMMANDS', restoration.replace(
            'in workspace: WallpaperLibraryWorkspace', 'in workspace: RemovalWorkspace'))
        restoration_fixture = ROOT / 'script/tests/fixtures/WallpaperLibraryRestorationChecks.swift'
        fixture += '\n' + restoration_fixture.read_text()
        composition_path = ROOT / 'MyWallpaperX/App/WallpaperLibraryWindowComposition.swift'
        steam_path = ROOT / 'MyWallpaperX/Modules/SteamWorkshop/UI/AppKitSteamWorkshopBrowserItem+Presentation.swift'
        composition = composition_path.read_text()
        projection_fixture = ROOT / 'script/tests/fixtures/WallpaperLibraryCompositionProjectionChecks.swift'
        fixture += '\n' + projection_fixture.read_text()
        fixture = fixture.replace('// ACTUAL_CARD_STATE_PREPARATION', declaration(composition, '    private func prepareCardState('))
        fixture = fixture.replace('// ACTUAL_RENDER_SIGNATURE', declaration(composition, '    private struct RenderSignature:'))
        fixture = fixture.replace('// ACTUAL_FILE_DROP_BINDING', declaration(composition, '    private func configureFileDrop('))
        grid_path = ROOT / 'MyWallpaperX/Shell/WallpaperLibraryGridController.swift'
        grid_fixture_path = ROOT / 'script/tests/fixtures/WallpaperLibraryGridHarness.swift'
        grid = grid_path.read_text()
        fixture = fixture.replace('// ACTUAL_FILE_DROP_RECEIPT', '\n'.join(declaration(grid, signature) for signature in (
            '    func collectionView(_ collectionView: NSCollectionView, validateDrop',
            '    func collectionView(_ collectionView: NSCollectionView, acceptDrop', '    private func fileURLs(')))
        fixture = fixture.replace('// ACTUAL_DRAG_INFO_LEAF', declaration(grid_fixture_path.read_text(), '@MainActor final class GridDropInfo:'))
        fixture = fixture.replace('// ACTUAL_REMOTE_ACTIONS', '\n'.join(declaration(composition, signature) for signature in (
            '    private func makeCardFavoriteAction(', '    private func onlineOrganization(',
            '    private func remoteOrganization(', '    private func acceptsRemoteAction(',
            '    private func remotePrimaryAction(', '    private func remoteInspectorActions(',
            '    private func remoteOrganizationMenu(', '    func selectedBrowserOrganizationActions(')))
        fixture = fixture.replace('// ACTUAL_STEAM_ORGANIZATION', declaration(steam_path.read_text(), '    struct OrganizationPresentation'))
        inputs = paths + [ROOT / 'MyWallpaperX/App/WallpaperLibraryCommands.swift',
                          ROOT / 'script/tests/fixtures/WallpaperLibraryCommandTransactionsHarness.swift', composition_path, steam_path,
                          grid_path, grid_fixture_path, restoration_fixture, projection_fixture]
        identities = {str(p): hashlib.sha256(p.read_bytes()).hexdigest() for p in inputs}
        with tempfile.TemporaryDirectory(prefix='mwx-command-transactions-', dir='/private/tmp') as directory:
            work = Path(directory)
            copies = []
            for path in paths:
                copied = work / path.name; shutil.copy2(path, copied); copies.append(str(copied))
                if path.name == 'WallpaperLibraryQuery.swift':
                    query = copied.read_text()
                    enum_marker = 'nonisolated enum WallpaperLibraryQuery {'
                    resolver_marker = '            self.aliases = try WallpaperLibraryQuery.aliasMap(aliases)'
                    self.assertEqual(query.count(enum_marker), 1, enum_marker)
                    self.assertEqual(query.count(resolver_marker), 1, resolver_marker)
                    query = query.replace(enum_marker,
                        'nonisolated enum WallpaperLibraryQuery {\n    nonisolated(unsafe) static var resolverInitializationCount = 0', 1)
                    query = query.replace(resolver_marker,
                        '            WallpaperLibraryQuery.resolverInitializationCount += 1\n' + resolver_marker, 1)
                    copied.write_text(query)
            harness = work / 'Checks.swift'; harness.write_text(fixture)
            binary = work / 'checks'
            built = subprocess.run(['xcrun', 'swiftc', *SWIFT_ISOLATION_FLAGS, '-warnings-as-errors', '-parse-as-library',
                *copies, str(harness), '-module-cache-path', str(work / 'modules'), '-o', str(binary)],
                capture_output=True, text=True, timeout=120)
            self.assertEqual(built.returncode, 0, built.stdout + built.stderr)
            ran = subprocess.run([str(binary), str(work)], capture_output=True, text=True, timeout=35)
            self.assertEqual(ran.returncode, 0, ran.stdout + ran.stderr)
            checks = json.loads(ran.stdout)
            self.assertGreaterEqual(len(checks), 10)
            for name, passed in checks.items():
                with self.subTest(name=name): self.assertIs(passed, True)
            print(json.dumps(checks, sort_keys=True))
            self.assertEqual(identities, {str(p): hashlib.sha256(p.read_bytes()).hexdigest() for p in inputs})


if __name__ == '__main__': unittest.main()
