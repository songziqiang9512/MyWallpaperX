import AppKit

/// Native menu semantics consume the current PageID and the App's shared
/// commands. No source bridge or translated display title selects a library.
@MainActor enum MainWindowMenuCommands {
    private static var inputWindow: NSWindow? {
        guard let window = NSApp.keyWindow, WallpaperLibrarySheetPresentation.permitsInput(in: window) else { return nil }
        return window
    }
    private static var controller: MainWindowController? {
        guard let controller = MainWindowCoordinator.mainWindowController, let window = controller.window,
              inputWindow === window else { return nil }
        return controller
    }
    private static var commands: WallpaperLibraryCommands? { controller?.libraryCommands }
    private static var page: WallpaperLibraryPage? { controller?.libraryPresentation.page }
    private static var picker: WallpaperPlaylistPickerController? { inputWindow?.delegate as? WallpaperPlaylistPickerController }
    private static var textView: NSTextView? { inputWindow?.firstResponder as? NSTextView }
    private static var editableText: NSTextView? { textView.flatMap { $0.isEditable ? $0 : nil } }
    private static var defaultButton: NSButtonCell? {
        guard let window = inputWindow, window !== MainWindowCoordinator.mainWindowController?.window,
              let cell = window.defaultButtonCell, cell.isEnabled else { return nil }
        return cell
    }
    private static var undoManager: UndoManager? {
        if let textView { return textView.isEditable ? textView.undoManager : nil }
        return inputWindow?.undoManager
    }
    private static func localAction(for references: [WallpaperReference], perform: @escaping () -> Void) -> () -> Void {
        let owner = controller, capturedPage = page, session = controller?.libraryPresentation.selectionState.sessionID
        return { [weak owner] in
            guard let owner, controller === owner, self.page == capturedPage,
                  owner.libraryPresentation.selectionState.sessionID == session,
                  owner.libraryCommands.selection.map(\.reference) == references else { return }
            perform()
        }
    }

    static func validate(_ item: NSMenuItem) -> Bool {
        guard let command = MainMenuCommand.resolve(item) else { return false }
        if let destination = command.page {
            item.state = destination == page ? .on : .off
            return controller != nil
        }
        switch command {
        case .about, .settings: return true
        case .closeWindow: return inputWindow != nil
        case .undo:
            item.title = undoManager?.undoMenuItemTitle ?? "撤销"
            return undoManager?.canUndo == true
        case .redo:
            item.title = undoManager?.redoMenuItemTitle ?? "重做"
            return undoManager?.canRedo == true
        case .createPlaylist: return commands?.canOrganize == true
        case .importFiles:
            switch page {
            case .videos, .recent: item.title = "导入视频…"
            case .images: item.title = "导入图片…"
            default: item.title = "导入壁纸…"
            }
            return commands?.canImport == true
        case .toggleSelection: return commands?.canToggleSelection == true
        case .deleteSelected:
            item.representedObject = nil
            if textView != nil { item.title = "删除"; return editableText != nil }
            if page == .playlists { item.title = "删除列表…"; return controller?.canDeleteSelectedPlaylist == true }
            item.title = commands?.removalTitle ?? "移除所选"
            guard let commands, commands.canOrganize else { return false }
            let selection = commands.selection
            guard !selection.isEmpty else { return false }
            item.representedObject = localAction(for: selection.map(\.reference)) { [weak commands] in commands?.remove() }
            return true
        case .search: return picker.map { $0.canFocusSearch } ?? (controller != nil)
        case .zoomIn: return picker.map { $0.canZoom(1) } ?? (controller?.canZoomLibrary(1) == true)
        case .zoomOut: return picker.map { $0.canZoom(-1) } ?? (controller?.canZoomLibrary(-1) == true)
        case .applyWallpaper:
            item.representedObject = nil
            item.title = "设为壁纸"
            if editableText != nil { return true }
            if let defaultButton { item.title = defaultButton.title; return true }
            if textView != nil { return false }
            if page?.isRemoteBrowse == true {
                guard let primary = controller?.selectedBrowserPrimaryAction() else { return false }
                item.title = primary.title; item.representedObject = primary.action; return true
            }
            guard controller?.libraryPresentation.selectionState.isSelecting == false, let commands else { return false }
            let selection = commands.selection
            guard selection.count == 1, selection[0].capabilities.contains(.play),
                  let primary = commands.makePrimaryAction(for: selection[0]) else { return false }
            item.title = commands.workspace.isPlaying(selection[0].reference) ? "停止播放" : "设为壁纸"
            item.representedObject = localAction(for: selection.map(\.reference), perform: primary)
            return true
        case .nextWallpaper, .previousWallpaper:
            // The action returns the standard cursor operation to the editor.
            // Disabling this key equivalent would still swallow Cmd+arrow.
            return textView != nil || controller != nil
        case .favorite:
            item.representedObject = nil
            item.title = "特别喜爱"
            if page?.isRemoteBrowse == true {
                guard let actions = controller?.selectedBrowserOrganizationActions(), actions.state.canFavorite else { return false }
                item.title = actions.state.isFavorite ? "取消特别喜爱" : "特别喜爱"
                item.representedObject = actions.onToggleFavorite
                return true
            }
            guard page?.isRemoteBrowse != true, let commands else { return false }
            item.title = commands.favoriteActionState.title
            guard let action = commands.makeFavoriteAction() else { return false }
            item.representedObject = action
            return true
        case .addToPlaylist:
            item.representedObject = nil
            if page?.isRemoteBrowse == true {
                guard let actions = controller?.selectedBrowserOrganizationActions(), actions.state.canOrganize else { return false }
                item.representedObject = { actions.onChoosePlaylist(nil) }
                return true
            }
            guard page?.isRemoteBrowse != true, let commands, commands.canOrganize else { return false }
            let selection = commands.selection
            guard !selection.isEmpty, selection.allSatisfy({ $0.capabilities.contains(.organize) }) else { return false }
            item.representedObject = localAction(for: selection.map(\.reference)) { [weak commands] in commands?.choosePlaylist() }
            return true
        case .info:
            item.representedObject = nil
            if page?.isRemoteBrowse == true {
                item.representedObject = controller?.selectedBrowserInfoAction()
                return item.representedObject != nil
            }
            guard let selection = commands?.selection, selection.count == 1 else { return false }
            guard selection[0].capabilities.contains(.inspect) else { return false }
            item.representedObject = localAction(for: selection.map(\.reference)) { commands?.inspectSelection() }
            return true
        case .preview:
            item.representedObject = nil
            if textView != nil { return editableText != nil }
            if page?.isRemoteBrowse == true {
                item.representedObject = controller?.selectedBrowserPreviewAction()
                return item.representedObject != nil
            }
            guard let selection = commands?.selection, selection.count == 1 else { return false }
            guard selection[0].capabilities.contains(.quickLook) || selection[0].kind == .web || selection[0].kind == .scene else { return false }
            item.representedObject = localAction(for: selection.map(\.reference)) { commands?.previewSelection() }
            return true
        case .revealOrRefresh:
            item.representedObject = nil
            item.title = "在 Finder 中显示"
            guard page?.isRemoteBrowse != true, let commands else { return false }
            let selection = commands.selection
            guard selection.contains(where: { $0.capabilities.contains(.reveal) }) else { return false }
            item.representedObject = localAction(for: selection.map(\.reference)) { [weak commands] in commands?.reveal() }
            return true
        default: return false
        }
    }

    static func menuUndo() { undoManager?.undo() }
    static func menuRedo() { undoManager?.redo() }
    static func menuCreatePlaylist() { guard commands?.canOrganize == true else { return }; commands?.playlists?.create() }
    static func menuImport() { guard commands?.canImport == true else { return }; commands?.importFiles() }
    static func menuToggleSelection() { commands?.toggleSelectionMode() }
    static func menuDeleteSelected(_ sender: Any?) {
        if let textView {
            if textView.isEditable { textView.delete(sender) }
            return
        }
        if page == .playlists { controller?.deleteSelectedPlaylist(); return }
        if let action = (sender as? NSMenuItem)?.representedObject as? (() -> Void) { action(); return }
        commands?.remove()
    }
    static func menuSearch() {
        if let picker { picker.focusSearch(); return }
        controller?.focusLibrarySearch()
    }
    static func menuZoom(_ delta: Int) {
        if let picker { picker.performZoom(delta); return }
        controller?.performLibraryZoom(delta)
    }
    static func menuApplyWallpaper(_ sender: Any?) {
        if let textView, textView.isEditable {
            textView.insertNewline(sender)
            return
        }
        if let defaultButton { defaultButton.performClick(sender); return }
        guard textView == nil else { return }
        guard controller != nil else { return }
        if page?.isRemoteBrowse != true, controller?.libraryPresentation.selectionState.isSelecting == true { return }
        if let action = (sender as? NSMenuItem)?.representedObject as? (() -> Void) { action(); return }
        if page?.isRemoteBrowse == true { controller?.selectedBrowserPrimaryAction()?.action(); return }
        guard let commands else { return }
        let selection = commands.selection
        guard selection.count == 1, selection[0].capabilities.contains(.play) else { return }
        commands.makePrimaryAction(for: selection[0])?()
    }
    static func menuNavigate(_ direction: ManualNavigationDirection, sender: Any?) {
        if let textView {
            if direction == .next { textView.moveToEndOfLine(sender) }
            else { textView.moveToBeginningOfLine(sender) }
            return
        }
        guard controller != nil else { return }
        CrossRuntimeWallpaperNavigator.navigate(direction)
    }
    static func menuFavorite(_ sender: Any?) {
        guard controller != nil else { return }
        if let action = (sender as? NSMenuItem)?.representedObject as? (() -> Void) { action(); return }
        guard page?.isRemoteBrowse != true else { return }
        commands?.toggleFavorite()
    }
    static func menuAddToPlaylist(_ sender: Any?) {
        guard controller != nil else { return }
        if let action = (sender as? NSMenuItem)?.representedObject as? (() -> Void) { action(); return }
        guard page?.isRemoteBrowse != true else { return }
        commands?.choosePlaylist()
    }
    static func menuInfo(_ sender: Any?) {
        guard controller != nil else { return }
        if let action = (sender as? NSMenuItem)?.representedObject as? (() -> Void) { action(); return }
        if page?.isRemoteBrowse == true { controller?.selectedBrowserInfoAction()?() }
        else { commands?.inspectSelection() }
    }
    static func menuPreview(_ sender: Any?) {
        if let textView {
            if textView.isEditable { textView.insertText(" ", replacementRange: NSRange(location: NSNotFound, length: 0)) }
            return
        }
        guard controller != nil else { return }
        if let action = (sender as? NSMenuItem)?.representedObject as? (() -> Void) { action(); return }
        if page?.isRemoteBrowse == true { controller?.selectedBrowserPreviewAction()?() }
        else { commands?.previewSelection() }
    }
    static func menuRevealOrRefresh(_ sender: Any?) {
        guard controller != nil else { return }
        if let action = (sender as? NSMenuItem)?.representedObject as? (() -> Void) { action(); return }
        if page?.isRemoteBrowse != true { commands?.reveal() }
    }
    static func menuNavigatePage(_ item: NSMenuItem) {
        guard let page = MainMenuCommand.resolve(item)?.page else { return }
        controller?.navigateLibraryPage(page)
    }
}
