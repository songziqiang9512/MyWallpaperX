import AppKit
import Foundation

// ACTUAL_FAVORITE_ACTION_STATE

// Controlled ownership/focus leaves. No real application window is shown.
enum MenuTestFocus { static var keyWindow:NSWindow? }
final class MenuTestWindow:NSWindow {
    let relationshipUndo=UndoManager()
    override var undoManager:UndoManager?{relationshipUndo}
}
final class NativeMenuEditor:NSTextView {
    let textUndo=UndoManager()
    override var undoManager:UndoManager?{textUndo}
}
final class AppUpdateController:NSObject {
    static let shared=AppUpdateController()
    @objc func checkForUpdates(_ sender:Any?){}
}
final class PlaylistCommands {var creates=0;func create(){creates += 1}}
final class MenuPlaybackWorkspace {
    var playing: WallpaperReference?
    func isPlaying(_ reference: WallpaperReference) -> Bool { playing == reference }
}
final class WallpaperLibraryCommands {
    private var selectedItems:[WallpaperContentItem]=[]
    var selectionReads=0
    var selection:[WallpaperContentItem] {
        get { selectionReads += 1; return selectedItems }
        set {
            if selectedItems.map(\.reference) != newValue.map(\.reference) { favoriteSessionID=UUID(); didChangeSelection?() }
            selectedItems=newValue
        }
    }
    var canOrganize=true,canImport=true,canToggleSelection=true
    var didChangeSelection: (() -> Void)?
    let workspace = MenuPlaybackWorkspace()
    var favoriteReferences=Set<WallpaperReference>()
    var favoriteResetEpoch=UUID(),favoriteSessionID=UUID()
    var currentPage:()->WallpaperLibraryPage?={nil}
    var favoriteTargets:[[WallpaperReference]]=[]
    var favoriteActionState:WallpaperLibraryFavoriteActionState {
        .init(canEdit:canOrganize,hasItems:!selection.isEmpty,
            allFavorite:selection.allSatisfy{favoriteReferences.contains($0.reference)},
            allOrganizable:selection.allSatisfy{$0.capabilities.contains(.organize)})
    }
    var canFavorite:Bool{favoriteActionState.canExecute}
    var playlists:PlaylistCommands?=PlaylistCommands()
    var imports=0,selectAllCalls=0,selectionCalls=0,deletes=0,applies=0,stops=0,favorites=0,adds=0,infos=0,previews=0,reveals=0
    var removalTitle="从列表移除"
    func importFiles(){imports += 1}
    func selectAll(){selectAllCalls += 1}
    func toggleSelectionMode(){selectionCalls += 1}
    func remove(){deletes += 1}
    func makePrimaryAction(for item: WallpaperContentItem) -> (() -> Void)? {
        guard item.capabilities.contains(.play) else { return nil }
        let playing = workspace.isPlaying(item.reference)
        return { if playing { self.stops += 1 } else { self.applies += 1 } }
    }
    func toggleFavorite(){if canFavorite{favorites += 1;favoriteTargets.append(selection.map(\.reference))}}
    // Controlled fixed-context factory leaf. The real Commands/SQLite policy
    // runs in CommandTransactions; this gate proves native menu retention.
    func makeFavoriteAction()->(()->Void)? {
        let action=favoriteActionState
        guard action.canExecute else{return nil}
        let refs=selection.map(\.reference),page=currentPage(),epoch=favoriteResetEpoch,session=favoriteSessionID
        return{[weak self] in
            guard let self,self.currentPage() == page,self.favoriteResetEpoch == epoch,self.favoriteSessionID == session,
                  self.selection.map(\.reference) == refs,self.favoriteActionState.canExecute,
                  self.favoriteActionState.isRemoving == action.isRemoving else{return}
            self.toggleFavorite()
        }
    }
    func choosePlaylist(){adds += 1}
    func inspectSelection(){infos += 1}
    func previewSelection(){previews += 1}
    func reveal(){reveals += 1}
}
final class WallpaperLibraryPresentation {
    struct Selection { var isSelecting = false; var sessionID = UUID() }
    var page = WallpaperLibraryPage.videos
    var selectionState = Selection()
}
// Controlled Picker capability leaf; the real Picker/Grid are exercised in
// test_wallpaper_playlist_picker. Other sheets never adopt this delegate.
final class WallpaperPlaylistPickerController:NSObject,NSWindowDelegate {
    var canFocusSearch=false,canZoomIn=false,canZoomOut=false
    var searches=0,zooms:[Int]=[]
    func canZoom(_ delta:Int)->Bool{delta > 0 ? canZoomIn : canZoomOut}
    func focusSearch(){if canFocusSearch{searches += 1}}
    func performZoom(_ delta:Int){if canZoom(delta){zooms.append(delta)}}
}
final class MainWindowController:NSWindowController {
    lazy var libraryCommands:WallpaperLibraryCommands = {
        let commands=WallpaperLibraryCommands()
        commands.currentPage={[weak self] in self?.libraryPresentation.page}
        commands.didChangeSelection = { [weak self] in self?.libraryPresentation.selectionState.sessionID = UUID() }
        return commands
    }()
    let libraryPresentation=WallpaperLibraryPresentation()
    var searches=0,zooms:[Int]=[],pages:[WallpaperLibraryPage]=[]
    var canZoomIn=true,canZoomOut=true
    var canDeleteSelectedPlaylist=false,playlistDeleteCalls=0
    var browserActions:WallpaperInspectorActions?
    lazy var browser = MainMenuBrowserComposition(presentation: libraryPresentation)
    var imageRefreshes = 0
    func selectedBrowserPrimaryAction() -> (title: String, action: () -> Void)? {
        browser.selectedBrowserPrimaryAction()
    }
    func selectedBrowserInfoAction() -> (() -> Void)? { browser.selectedBrowserInfoAction() }
    func selectedBrowserPreviewAction() -> (() -> Void)? { browser.selectedBrowserPreviewAction() }
    func refreshOnlineImages() { imageRefreshes += 1 }
    func selectedBrowserOrganizationActions()->WallpaperInspectorActions?{browserActions}
    func focusLibrarySearch(){searches += 1}
    func performLibraryZoom(_ value:Int){zooms.append(value)}
    func canZoomLibrary(_ value:Int)->Bool{value > 0 ? canZoomIn : canZoomOut}
    func navigateLibraryPage(_ page:WallpaperLibraryPage){pages.append(page);libraryPresentation.page=page}
    func deleteSelectedPlaylist(){if canDeleteSelectedPlaylist{playlistDeleteCalls += 1}}
}
enum MainWindowCoordinator {static var mainWindowController:MainWindowController?}
enum ManualNavigationDirection {case previous,next}
enum CrossRuntimeWallpaperNavigator {static var directions:[ManualNavigationDirection]=[];static func navigate(_ value:ManualNavigationDirection){directions.append(value)}}
final class SteamWorkshopService {static let shared=SteamWorkshopService();var refreshes=0;func refresh(){refreshes += 1}}
final class PixabayService {static let shared=PixabayService();var refreshes=0;func refresh(){refreshes += 1}}
final class AppDelegate:NSObject,NSApplicationDelegate,NSMenuItemValidation {
    @objc func showAboutMenuAction(_ sender:Any?){}
    @objc func showSettingsMenuAction(_ sender:Any?){}
    @objc func closeWindowMenuAction(_ sender:Any?){}
    // ACTUAL_DELEGATE_MENU
}

@main enum MainMenuCommandChecks {
    @MainActor static func main()throws {
        let app=NSApplication.shared;app.setActivationPolicy(.prohibited)
        let delegate=AppDelegate();app.delegate=delegate
        let window=MenuTestWindow(contentRect:NSRect(x:0,y:0,width:400,height:300),styleMask:[.titled],backing:.buffered,defer:false)
        window.isReleasedWhenClosed=false
        let controller=MainWindowController(window:window);MainWindowCoordinator.mainWindowController=controller
        MenuTestFocus.keyWindow=window
        defer{MenuTestFocus.keyWindow=nil;MainWindowCoordinator.mainWindowController=nil;window.close()}
        MainMenuBuilder.installMainMenu()
        func all(_ menu:NSMenu)->[NSMenuItem]{menu.items.flatMap{[$0]+($0.submenu.map(all) ?? [])}}
        let items=all(app.mainMenu!)
        func item(_ command:MainMenuCommand)->NSMenuItem{items.first{$0.identifier == command.identifier}!}
        func send(_ command:MainMenuCommand)->Bool {
            let entry=item(command)
            return app.sendAction(entry.action!,to:entry.target,from:entry)
        }
        func closeGroups(_ undo:UndoManager){while undo.groupingLevel > 0{undo.endUndoGrouping()}}
        var checks:[String:Bool]=[:]
        let productItems=items.filter{$0.identifier?.rawValue.hasPrefix("MyWallpaperX.Menu.") == true}
        checks["native-menu-identifiers-are-unique-and-page-navigation-complete"] = Set(productItems.compactMap(\.identifier)).count == productItems.count
            && MainMenuCommand.allCases.allSatisfy{command in productItems.contains{$0.identifier == command.identifier}}
        checks["native-undo-redo-keep-standard-key-equivalents"] = item(.undo).keyEquivalent == "z" && item(.undo).keyEquivalentModifierMask == [.command]
            && item(.redo).keyEquivalent == "z" && item(.redo).keyEquivalentModifierMask == [.command,.shift]
        checks["playlist-naming-and-original-key-equivalents-remain"] = item(.createPlaylist).title.contains("播放列表")
            && item(.createPlaylist).keyEquivalent == "n" && item(.addToPlaylist).keyEquivalent == "t"
            && item(.favorite).keyEquivalent == "d" && item(.importFiles).keyEquivalent == "o"
        checks["fixed-sidebar-has-no-menu-toggle-identifier-or-selector"] = !items.contains {
            $0.identifier?.rawValue == "MyWallpaperX.Menu.toggleSidebar"
                || $0.action == #selector(NSSplitViewController.toggleSidebar(_:))
        }
        // The original Toolbar owns the geometry rule. These supplied facade
        // facts prove menu validation consumes it without another width model.
        controller.canZoomIn=false
        checks["three-column-limit-disables-only-menu-zoom-in"] = !delegate.validateMenuItem(item(.zoomIn))
            && delegate.validateMenuItem(item(.zoomOut))
        controller.canZoomIn=true;controller.canZoomOut=false
        checks["six-column-limit-disables-only-menu-zoom-out"] = delegate.validateMenuItem(item(.zoomIn))
            && !delegate.validateMenuItem(item(.zoomOut))
        controller.canZoomIn=false
        checks["unmounted-or-zero-width-disables-both-native-menu-zoom-directions"] = !delegate.validateMenuItem(item(.zoomIn))
            && !delegate.validateMenuItem(item(.zoomOut))
        controller.canZoomIn=true;controller.canZoomOut=true
        item(.importFiles).title="任意本地化文案"
        controller.libraryPresentation.page = .images
        checks["identifier-validation-does-not-dispatch-by-mutating-title"] = delegate.validateMenuItem(item(.importFiles)) && item(.importFiles).title == "导入图片…"
        let unknown=NSMenuItem(title:"导入图片",action:#selector(AppDelegate.importMenuAction(_:)),keyEquivalent:"")
        unknown.identifier = .init("unknown.command")
        checks["unknown-identifier-cannot-use-title-to-open-import"] = !delegate.validateMenuItem(unknown)
        unknown.identifier=nil;unknown.title="translated title"
        let overflow=NSMenuItem(title:"translated title",action:#selector(AppDelegate.importMenuAction(_:)),keyEquivalent:"")
        checks["stable-selector-validates-standard-overflow-without-title"] = delegate.validateMenuItem(overflow)
        let ref=WallpaperReference(provider:.staticImageLibrary,sourceID:"image")
        let image=WallpaperContentItem(reference:ref,providerReference:ref,locator:.init(path:"/controlled/image.png",mediaKind:.image),title:"image",kind:.image,
            publishedAvailability:.available,capabilities:[.play,.organize,.inspect,.quickLook,.reveal],metadata:.init(),acquisition:.idle,update:.idle,aliases:[])
        controller.libraryCommands.selection=[image]
        checks["mixed-provider-actions-are-not-video-only"] = [.applyWallpaper,.favorite,.addToPlaylist,.info,.preview,.revealOrRefresh].allSatisfy{delegate.validateMenuItem(item($0))}
        for command in [MainMenuCommand.applyWallpaper, .addToPlaylist, .info] {
            controller.libraryCommands.selectionReads=0
            let enabled=delegate.validateMenuItem(item(command))
            checks["menu-validation-reads-one-selection-for-\(command.rawValue)"] = enabled && controller.libraryCommands.selectionReads == 1
        }
        _ = send(.applyWallpaper);_ = send(.favorite);_ = send(.addToPlaylist);_ = send(.info);_ = send(.preview);_ = send(.revealOrRefresh)
        checks["native-target-selector-actions-use-shared-window-commands"] = controller.libraryCommands.applies == 1 && controller.libraryCommands.favorites == 1
            && controller.libraryCommands.adds == 1 && controller.libraryCommands.infos == 1 && controller.libraryCommands.previews == 1 && controller.libraryCommands.reveals == 1
        let offlineRef=WallpaperReference(provider:.steamWorkshop,sourceID:"offline-favorite")
        let offline=WallpaperContentItem(reference:offlineRef,providerReference:offlineRef,locator:.init(mediaKind:.video),title:"offline",kind:.video,
            publishedAvailability:.unavailable,capabilities:[.inspect],metadata:.init(),acquisition:.idle,update:.idle,aliases:[])
        controller.libraryCommands.selection=[offline]
        controller.libraryCommands.favoriteReferences=[offlineRef]
        checks["local-offline-favorite-menu-removes-without-enabling-add-to-playlist"] = delegate.validateMenuItem(item(.favorite))
            && item(.favorite).title == "取消特别喜爱" && !delegate.validateMenuItem(item(.addToPlaylist))
        let beforeOfflineFavorite=controller.libraryCommands.favorites
        _ = send(.favorite)
        checks["offline-removal-menu-dispatches-through-original-command-owner"] = controller.libraryCommands.favorites == beforeOfflineFavorite+1
        controller.libraryCommands.canOrganize=false
        let beforeReadonlyFavorite=controller.libraryCommands.favorites
        let readonlyFavoriteEnabled=delegate.validateMenuItem(item(.favorite))
        _ = send(.favorite)
        checks["readonly-favorite-menu-retains-removal-title-without-executing"] = !readonlyFavoriteEnabled
            && item(.favorite).title == "取消特别喜爱" && controller.libraryCommands.favorites == beforeReadonlyFavorite
        controller.libraryCommands.canOrganize=true
        controller.libraryCommands.selection=[image,offline]
        checks["mixed-offline-favorite-and-online-unfavorite-menu-does-not-advertise-noop-add"] = !delegate.validateMenuItem(item(.favorite))
            && item(.favorite).title == "特别喜爱"
        controller.libraryCommands.selection=[image]
        controller.libraryCommands.favoriteReferences=[]
        _ = delegate.validateMenuItem(item(.favorite))
        let beforeHeldLocalFavorite=controller.libraryCommands.favorites
        let beforeHeldLocalTargets=controller.libraryCommands.favoriteTargets
        controller.libraryCommands.selection=[offline]
        controller.libraryCommands.favoriteReferences=[offlineRef]
        _ = send(.favorite)
        checks["held-local-favorite-menu-cannot-retarget-later-selection-on-the-same-page"] = controller.libraryCommands.favorites == beforeHeldLocalFavorite
            && controller.libraryCommands.favoriteTargets == beforeHeldLocalTargets
        controller.libraryCommands.selection=[image]
        controller.libraryCommands.favoriteReferences=[ref]
        _ = delegate.validateMenuItem(item(.favorite))
        controller.libraryCommands.favoriteReferences=[]
        _ = send(.favorite)
        checks["held-local-removal-menu-cannot-turn-into-add-after-favorite-state-reverses"] = controller.libraryCommands.favorites == beforeHeldLocalFavorite
            && controller.libraryCommands.favoriteTargets == beforeHeldLocalTargets
        _ = delegate.validateMenuItem(item(.favorite))
        controller.libraryCommands.favoriteResetEpoch=UUID()
        _ = send(.favorite)
        checks["held-local-favorite-menu-rejects-reset-before-new-validation"] = controller.libraryCommands.favorites == beforeHeldLocalFavorite
        _ = delegate.validateMenuItem(item(.favorite))
        controller.libraryPresentation.page = .downloads
        _ = send(.favorite)
        checks["held-local-favorite-menu-cannot-survive-a-page-change"] = controller.libraryCommands.favorites == beforeHeldLocalFavorite
        controller.libraryPresentation.page = .images
        for page in [WallpaperLibraryPage.workshop,.pixabay,.wallhaven,.pixiv] {
            let steamRefreshes = SteamWorkshopService.shared.refreshes
            let pixabayRefreshes = PixabayService.shared.refreshes
            let imageRefreshes = controller.imageRefreshes
            controller.libraryPresentation.page=page;controller.libraryCommands.canImport=false;controller.libraryCommands.canToggleSelection=false
            checks["remote-import-and-bulk-selection-disabled-\(page.persistenceKey)"] = !delegate.validateMenuItem(item(.importFiles)) && !delegate.validateMenuItem(item(.toggleSelection))
            checks["remote-search-zoom-remain-without-manual-refresh-\(page.persistenceKey)"] = delegate.validateMenuItem(item(.search))
                && delegate.validateMenuItem(item(.zoomIn)) && !delegate.validateMenuItem(item(.revealOrRefresh)) && item(.revealOrRefresh).title == "在 Finder 中显示"
            _ = send(.search);_ = send(.zoomIn);_ = send(.zoomOut);_ = send(.revealOrRefresh)
            checks["retired-refresh-cannot-dispatch-to-any-source-\(page.persistenceKey)"] =
                SteamWorkshopService.shared.refreshes - steamRefreshes == 0
                && PixabayService.shared.refreshes - pixabayRefreshes == 0
                && controller.imageRefreshes - imageRefreshes == 0
        }
        checks["remote-search-and-zoom-retain-owners-with-no-manual-refresh"] = SteamWorkshopService.shared.refreshes == 0 && PixabayService.shared.refreshes == 0
            && controller.imageRefreshes == 0 && controller.searches == 4 && controller.zooms == [1,-1,1,-1,1,-1,1,-1]
        var browserFavorites:[String]=[],browserPlaylists:[String]=[]
        var browserID="download-A"
        controller.libraryPresentation.page = .workshop
        func browserActions(_ id:String, canFavorite:Bool=true, canOrganize:Bool=true, isFavorite:Bool=false)->WallpaperInspectorActions {
            let page = controller.libraryPresentation.page
            return .init(state:.init(isPlaying:false,isFavorite:isFavorite,canPerformPrimary:true,canFavorite:canFavorite,canOrganize:canOrganize,playlistNames:[]),
                onPrimary:{},onToggleFavorite:{
                    guard browserID == id,controller.libraryPresentation.page == page else{return}
                    browserFavorites.append(id)
                },onChoosePlaylist:{_ in
                    guard browserID == id,controller.libraryPresentation.page == page else{return}
                    browserPlaylists.append(id)
                })
        }
        controller.browserActions=browserActions(browserID)
        let localOrganizationCounts=(controller.libraryCommands.favorites,controller.libraryCommands.adds)
        checks["downloaded-browser-selection-enables-native-organization-items"] = delegate.validateMenuItem(item(.favorite)) && delegate.validateMenuItem(item(.addToPlaylist))
        _ = send(.favorite);_ = send(.addToPlaylist)
        checks["browser-native-menu-dispatches-fixed-actions-without-local-selection"] = browserFavorites == ["download-A"] && browserPlaylists == ["download-A"]
            && controller.libraryCommands.favorites == localOrganizationCounts.0 && controller.libraryCommands.adds == localOrganizationCounts.1
        browserID="download-B";controller.browserActions=browserActions(browserID)
        _ = send(.favorite);_ = send(.addToPlaylist)
        checks["held-browser-main-menu-does-not-borrow-a-new-selected-download"] = browserFavorites == ["download-A"] && browserPlaylists == ["download-A"]
        _ = delegate.validateMenuItem(item(.favorite));_ = delegate.validateMenuItem(item(.addToPlaylist))
        _ = send(.favorite);_ = send(.addToPlaylist)
        checks["fresh-native-validation-captures-current-browser-target"] = browserFavorites == ["download-A","download-B"] && browserPlaylists == ["download-A","download-B"]
        controller.libraryPresentation.page = .images
        _ = send(.favorite);_ = send(.addToPlaylist)
        checks["old-browser-main-menu-after-page-change-cannot-fall-through-to-local-selection"] = browserFavorites.count == 2 && browserPlaylists.count == 2
            && controller.libraryCommands.favorites == localOrganizationCounts.0 && controller.libraryCommands.adds == localOrganizationCounts.1
        controller.libraryPresentation.page = .workshop;controller.browserActions=nil
        checks["undownloaded-browser-selection-disables-main-menu-organization"] = !delegate.validateMenuItem(item(.favorite)) && !delegate.validateMenuItem(item(.addToPlaylist))
        _ = send(.favorite);_ = send(.addToPlaylist)
        checks["unpublished-browser-main-menu-cannot-use-stale-local-command-selection"] = controller.libraryCommands.favorites == localOrganizationCounts.0
            && controller.libraryCommands.adds == localOrganizationCounts.1
        controller.libraryPresentation.page = .pixabay
        checks["remote-pixabay-without-local-organization-target-never-borrows-library-selection"] = !delegate.validateMenuItem(item(.favorite)) && !delegate.validateMenuItem(item(.addToPlaylist))
        controller.browserActions = browserActions(browserID)
        let pixabayEnabled = delegate.validateMenuItem(item(.favorite)) && delegate.validateMenuItem(item(.addToPlaylist))
        _ = send(.favorite); _ = send(.addToPlaylist)
        checks["pixabay-native-menu-has-the-same-favorite-and-playlist-actions"] = pixabayEnabled
            && browserFavorites == ["download-A", "download-B", "download-B"] && browserPlaylists == browserFavorites
            && controller.libraryCommands.favorites == localOrganizationCounts.0 && controller.libraryCommands.adds == localOrganizationCounts.1
        controller.libraryPresentation.page = .workshop
        controller.browserActions=browserActions(browserID,canFavorite:true,canOrganize:false,isFavorite:true)
        checks["remote-offline-favorite-menu-separates-removal-from-playlist-eligibility"] = delegate.validateMenuItem(item(.favorite))
            && item(.favorite).title == "取消特别喜爱" && !delegate.validateMenuItem(item(.addToPlaylist))
        controller.browserActions=browserActions(browserID,canFavorite:false,canOrganize:false,isFavorite:true)
        checks["remote-readonly-or-busy-favorite-menu-never-borrows-local-eligibility"] = !delegate.validateMenuItem(item(.favorite))
            && !delegate.validateMenuItem(item(.addToPlaylist))
        checks.merge(runMainMenuBrowserSelectionChecks(controller: controller, delegate: delegate, image: image, item: item, send: send)) { _, new in new }
        _ = send(.playlists)
        checks["page-command-navigates-by-fixed-id-and-checks-state"] = controller.pages.last == .playlists
            && delegate.validateMenuItem(item(.playlists)) && item(.playlists).state == .on
        checks["directory-delete-requires-native-focused-real-playlist-facade"] = !delegate.validateMenuItem(item(.deleteSelected))
        controller.canDeleteSelectedPlaylist=true
        let wallpaperDeleteCount=controller.libraryCommands.deletes
        let directoryDeleteEnabled=delegate.validateMenuItem(item(.deleteSelected)) && item(.deleteSelected).title == "删除列表…"
        _ = send(.deleteSelected)
        checks["directory-delete-menu-dispatches-once-without-removing-wallpapers"] = directoryDeleteEnabled
            && controller.playlistDeleteCalls == 1 && controller.libraryCommands.deletes == wallpaperDeleteCount
        let editor=NativeMenuEditor(frame:NSRect(x:0,y:0,width:200,height:100));editor.isEditable=true;editor.allowsUndo=true
        window.contentView!.addSubview(editor);window.makeFirstResponder(editor)
        editor.string="alpha beta";editor.setSelectedRange(NSRange(location:0,length:0))
        let commandCounts=(controller.libraryCommands.selectAllCalls,controller.libraryCommands.deletes,controller.libraryCommands.previews,controller.libraryCommands.applies)
        _ = send(.selectAll)
        checks["native-text-select-all-never-selects-wallpaper-cards"] = editor.selectedRange().length == editor.string.utf16.count && controller.libraryCommands.selectAllCalls == commandCounts.0
        _ = send(.deleteSelected)
        checks["native-text-delete-never-removes-wallpaper-cards"] = editor.string.isEmpty && controller.libraryCommands.deletes == commandCounts.1
        checks["native-text-delete-has-text-title-and-never-deletes-selected-playlist"] = delegate.validateMenuItem(item(.deleteSelected))
            && item(.deleteSelected).title == "删除" && controller.playlistDeleteCalls == 1
        editor.string="alpha beta";editor.setSelectedRange(NSRange(location:2,length:0))
        _ = send(.nextWallpaper)
        checks["native-text-command-right-keeps-line-end-navigation"] = editor.selectedRange().location == editor.string.utf16.count && CrossRuntimeWallpaperNavigator.directions.isEmpty
        _ = send(.previousWallpaper)
        checks["native-text-command-left-keeps-line-start-navigation"] = editor.selectedRange().location == 0 && CrossRuntimeWallpaperNavigator.directions.isEmpty
        _ = send(.preview);_ = send(.applyWallpaper)
        checks["native-text-space-return-never-apply-or-preview-wallpaper"] = editor.string.hasPrefix(" \n")
            && controller.libraryCommands.previews == commandCounts.2 && controller.libraryCommands.applies == commandCounts.3
        editor.isEditable=false
        let beforeReadOnly=(controller.libraryCommands.deletes,controller.libraryCommands.applies,controller.libraryCommands.previews)
        _ = send(.deleteSelected);_ = send(.applyWallpaper);_ = send(.preview)
        checks["read-only-native-text-cannot-fall-through-to-card-commands"] = !delegate.validateMenuItem(item(.deleteSelected))
            && controller.libraryCommands.deletes == beforeReadOnly.0 && controller.libraryCommands.applies == beforeReadOnly.1 && controller.libraryCommands.previews == beforeReadOnly.2
        editor.isEditable=true
        editor.textUndo.removeAllActions();window.relationshipUndo.removeAllActions()
        var textChanges=0,relationshipChanges=0
        editor.textUndo.registerUndo(withTarget:editor){_ in textChanges += 1};closeGroups(editor.textUndo)
        window.relationshipUndo.registerUndo(withTarget:window){_ in relationshipChanges += 1};closeGroups(window.relationshipUndo)
        _ = send(.undo)
        checks["text-responder-undo-never-consumes-relationship-stack"] = textChanges == 1 && relationshipChanges == 0 && window.relationshipUndo.canUndo
        window.makeFirstResponder(window.contentView)
        _ = send(.undo)
        checks["window-undo-uses-native-relationship-manager"] = relationshipChanges == 1
        _ = send(.nextWallpaper);_ = send(.previousWallpaper)
        checks["nontext-navigation-uses-existing-global-navigator"] = CrossRuntimeWallpaperNavigator.directions == [.next,.previous]
        MainWindowCoordinator.mainWindowController=nil
        checks["closed-window-menu-never-recreates-a-controller"] = !delegate.validateMenuItem(item(.createPlaylist)) && !delegate.validateMenuItem(item(.importFiles))
            && !delegate.validateMenuItem(item(.search)) && !delegate.validateMenuItem(item(.zoomIn))
        print(String(data:try JSONSerialization.data(withJSONObject:checks,options:[.sortedKeys]),encoding:.utf8)!)
    }
}
