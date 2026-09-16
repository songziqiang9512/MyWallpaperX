//
//  AppKitSteamWorkshopDownloadsGridView.swift
//  MyWallpaperX
//

import AppKit
import Combine

final class AppKitSteamWorkshopDownloadsContainerView: NSView, ModuleFocusable {
    private enum Section {
        case main
    }

    private let service: SteamWorkshopService
    var onOpen: (SteamWorkshopBrowserItem) -> Void
    var onSetAsWallpaper: (SteamWorkshopDownloadRecord) -> Void

    private var cancellables = Set<AnyCancellable>()
    private var orderedIDs: [String] = []
    private var recordsByID: [String: SteamWorkshopDownloadRecord] = [:]
    private var keyboardFocusedID: String?
    private var currentColumnCount = 1
    private var moduleActivationObserver: NSObjectProtocol?
    private var isApplyingSelectionSnapshot = false
    private var pendingLayoutInvalidation = false

    private let scrollView: NSScrollView = {
        let s = NSScrollView()
        s.drawsBackground = false
        s.hasVerticalScroller = true
        s.hasHorizontalScroller = false
        s.translatesAutoresizingMaskIntoConstraints = false
        return s
    }()

    private lazy var collectionView: SteamWorkshopKeyboardCollectionView = {
        let cv = SteamWorkshopKeyboardCollectionView()
        cv.isSelectable = false
        cv.allowsEmptySelection = true
        cv.backgroundColors = [.clear]
        cv.translatesAutoresizingMaskIntoConstraints = false
        cv.keyboardDelegate = self
        cv.accessibleItemsProvider = { [weak self] in
            guard let self else { return [] }
            return self.collectionView.indexPathsForVisibleItems().sorted().compactMap {
                self.collectionView.item(at: $0)?.view
            }
        }
        cv.cardPressStateHandler = { [weak self] indexPath, pressed in
            guard let self,
                  let item = self.collectionView.item(at: indexPath) as? AppKitSteamWorkshopBrowserItem else { return }
            item.applyPressedState(pressed)
        }
        cv.primaryClickHandler = { [weak self] indexPath in
            self?.handlePrimaryClick(at: indexPath) ?? false
        }
        cv.contextMenuProvider = { [weak self] indexPath in
            self?.makeContextMenu(for: indexPath)
        }
        cv.onBackgroundLeftClick = { [weak self] in
            self?.handleBackgroundClick()
        }
        return cv
    }()

    private let emptyLabel: NSTextField = {
        let label = NSTextField(labelWithString: SteamWorkshopDownloadsDisplayMode.all.emptyStateText)
        label.alignment = .center
        label.textColor = .secondaryLabelColor
        label.font = .systemFont(ofSize: 13, weight: .regular)
        label.isHidden = true
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private lazy var flowLayout: NSCollectionViewFlowLayout = {
        SteamWorkshopGridLayoutSupport.makeFlowLayout()
    }()

    private lazy var dataSource: NSCollectionViewDiffableDataSource<Section, String> = {
        NSCollectionViewDiffableDataSource<Section, String>(collectionView: collectionView) { [weak self] _, _, id in
            guard let self,
                  let record = self.recordsByID[id] else { return nil }
            let item = AppKitSteamWorkshopBrowserItem(nibName: nil, bundle: nil)
            self.configureDownloadItem(item, for: record)
            return item
        }
    }()

    init(
        service: SteamWorkshopService,
        onOpen: @escaping (SteamWorkshopBrowserItem) -> Void,
        onSetAsWallpaper: @escaping (SteamWorkshopDownloadRecord) -> Void
    ) {
        self.service = service
        self.onOpen = onOpen
        self.onSetAsWallpaper = onSetAsWallpaper
        super.init(frame: .zero)
        setup()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    deinit {
        if let moduleActivationObserver {
            NotificationCenter.default.removeObserver(moduleActivationObserver)
        }
    }

    func requestFocus() {
        window?.makeFirstResponder(collectionView)
    }

    var hasPreviewableSelection: Bool {
        !service.isDownloadsMultiSelectMode
            && service.selectedDownloadRecord.map(service.cachedCanLaunchDownloadRecord(_:)) == true
    }

    override func layout() {
        super.layout()
        updateLayoutItemSize()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        SteamWorkshopDownloadsBridge.shared.isActive = (window != nil)
        syncVisiblePreviewAnimationStates(isVisible: window != nil)
    }

    private func setup() {
        SteamWorkshopDownloadsBridge.shared.container = self
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor

        collectionView.collectionViewLayout = flowLayout
        collectionView.dataSource = dataSource
        collectionView.delegate = self
        scrollView.documentView = collectionView

        addSubview(scrollView)
        addSubview(emptyLabel)

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),

            emptyLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])

        service.$displayedDownloads
            .receive(on: DispatchQueue.main)
            .sink { [weak self] records in
                self?.applyRecords(records)
                self?.refreshVisibleDownloadItems()
            }
            .store(in: &cancellables)

        service.$launchPendingRecordID
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.refreshVisibleDownloadItems()
            }
            .store(in: &cancellables)

        service.$downloadsDisplayMode
            .receive(on: DispatchQueue.main)
            .sink { [weak self] mode in
                self?.emptyLabel.stringValue = mode.emptyStateText
            }
            .store(in: &cancellables)

        service.$selectedDownloadID
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.applySelection()
                self?.refreshVisibleDownloadItems()
            }
            .store(in: &cancellables)

        service.$selectedDownloadIDs
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.applySelection()
                self?.refreshVisibleDownloadItems()
            }
            .store(in: &cancellables)

        service.$isDownloadsMultiSelectMode
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isMultiSelect in
                guard let self else { return }
                self.collectionView.allowsMultipleSelection = isMultiSelect
                self.applySelection()
                self.refreshVisibleDownloadItems()
            }
            .store(in: &cancellables)

        WallpaperManager.shared.objectWillChange.map { _ in () }
            .merge(with: NotificationCenter.default.publisher(for: .sceneWallpaperLaunchStateDidChange).map { _ in () })
            .receive(on: DispatchQueue.main)
            .map { [weak self] _ -> Set<String> in
                guard let self else { return [] }
                return Set(self.service.downloads.filter { self.service.isRecordCurrentlyPlaying($0) }.map(\.id))
            }
            .removeDuplicates()
            .sink { [weak self] _ in self?.refreshVisibleDownloadItems() }
            .store(in: &cancellables)

        service.$zoomOffset
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateLayoutItemSize()
            }
            .store(in: &cancellables)

        moduleActivationObserver = NotificationCenter.default.addObserver(
            forName: .moduleDidBecomeActive,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let module = notification.userInfo?["module"] as? String,
                  module == ModuleIdentifier.steamWorkshop.rawValue else { return }
            self?.requestFocus()
        }

        applyRecords(service.displayedDownloads)
    }

    private func applyRecords(_ records: [SteamWorkshopDownloadRecord]) {
        recordsByID = Dictionary(uniqueKeysWithValues: records.map { ($0.id, $0) })
        orderedIDs = records.map(\.id)

        if let selectedID = service.selectedDownloadID,
           orderedIDs.contains(selectedID) == false {
            service.selectDownload(itemID: nil)
        }

        emptyLabel.isHidden = !orderedIDs.isEmpty

        var snapshot = NSDiffableDataSourceSnapshot<Section, String>()
        snapshot.appendSections([.main])
        snapshot.appendItems(orderedIDs, toSection: .main)
        dataSource.apply(snapshot, animatingDifferences: true)
        ensureKeyboardFocus()
    }

    private func configureDownloadItem(_ item: AppKitSteamWorkshopBrowserItem, for record: SteamWorkshopDownloadRecord) {
        let displayItem = record.displayItem ?? SteamWorkshopDownloadGridSupport.fallbackDisplayItem(for: record)
        let canLaunchRecord = service.cachedCanLaunchDownloadRecord(record)
        item.configure(
            displayContext: .downloads,
            isPlaying: service.isRecordCurrentlyPlaying(record),
            item: displayItem,
            downloadRecord: record,
            downloadProgressStore: service.downloadProgressStore,
            isDownloading: record.status == .downloading,
            isDownloaded: canLaunchRecord,
            isMultiSelectMode: service.isDownloadsMultiSelectMode,
            isKeyboardFocused: service.effectiveSelectedDownloadIDs.contains(record.id),
            onOpen: { [weak self] in
                self?.presentDownloadDetail(for: record.id)
            },
            onDownload: { [weak self] in
                guard let self else { return }
                SteamWorkshopDownloadGridSupport.performPrimaryAction(
                    for: record,
                    service: self.service,
                    onSetAsWallpaper: self.onSetAsWallpaper
                )
            },
            onSetAsWallpaper: { [weak self] in self?.onSetAsWallpaper(record) },
            onCancelDownload: { [weak self] in self?.service.cancelDownload(itemID: record.id) }
        )
        item.setPrefersCircularPlayBadge(canLaunchRecord)
    }

    private func refreshVisibleDownloadItems() {
        for visibleItem in collectionView.visibleItems() {
            guard let item = visibleItem as? AppKitSteamWorkshopBrowserItem,
                  let indexPath = collectionView.indexPath(for: item),
                  indexPath.item < orderedIDs.count else { continue }
            let id = orderedIDs[indexPath.item]
            guard let record = recordsByID[id] else { continue }
            configureDownloadItem(item, for: record)
        }
    }

    private func syncVisiblePreviewAnimationStates(isVisible: Bool) {
        for visibleItem in collectionView.visibleItems() {
            guard let item = visibleItem as? AppKitSteamWorkshopBrowserItem else { continue }
            item.setPreviewVisible(isVisible)
        }
    }

    private func updateLayoutItemSize() {
        let metrics = SteamWorkshopGridLayoutSupport.metrics(
            boundsWidth: bounds.width,
            zoomOffset: service.zoomOffset,
            hoverScale: AppKitSteamWorkshopBrowserItem.hoverScale,
            sectionInset: flowLayout.sectionInset
        )
        currentColumnCount = metrics.columns
        flowLayout.minimumInteritemSpacing = metrics.interitemSpacing
        flowLayout.minimumLineSpacing = metrics.lineSpacing
        let newSize = metrics.itemSize
        guard flowLayout.itemSize != newSize else { return }
        flowLayout.itemSize = newSize
        scheduleLayoutInvalidation()
    }

    private func scheduleLayoutInvalidation() {
        guard pendingLayoutInvalidation == false else { return }
        pendingLayoutInvalidation = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.pendingLayoutInvalidation = false
            self.collectionView.collectionViewLayout?.invalidateLayout()
        }
    }

    private func ensureKeyboardFocus() {
        guard !orderedIDs.isEmpty else {
            keyboardFocusedID = nil
            service.replaceSelectedDownloads(with: [], primaryID: nil)
            return
        }
        if let focusedID = keyboardFocusedID, orderedIDs.contains(focusedID) {
            reloadKeyboardFocus(previous: nil, next: focusedID)
            return
        }
        focusItem(at: 0)
    }

    private func focusItem(at index: Int) {
        guard index >= 0, index < orderedIDs.count else { return }
        let nextID = orderedIDs[index]
        let previousID = keyboardFocusedID
        guard previousID != nextID else {
            reloadKeyboardFocus(previous: previousID, next: nextID)
            scrollToItem(nextID)
            return
        }
        keyboardFocusedID = nextID
        if !service.isDownloadsMultiSelectMode {
            service.selectDownload(itemID: nextID)
        }
        reloadKeyboardFocus(previous: previousID, next: nextID)
        scrollToItem(nextID)
    }

    private var focusedIndex: Int? {
        guard let id = keyboardFocusedID else { return nil }
        return orderedIDs.firstIndex(of: id)
    }

    private func handleReturnKey() -> Bool {
        guard let id = keyboardFocusedID,
              let record = recordsByID[id] else { return false }
        SteamWorkshopDownloadGridSupport.performPrimaryAction(
            for: record,
            service: service,
            onSetAsWallpaper: onSetAsWallpaper
        )
        return true
    }

    private func handleEscapeKey() -> Bool {
        if service.isDownloadsMultiSelectMode {
            service.exitDownloadsMultiSelectMode()
            return true
        }
        guard service.selectedDownloadInspectorItem != nil else { return false }
        InspectorHostActions.postClose()
        return true
    }

    private func handleArrowKey(_ keyCode: UInt16) -> Bool {
        guard let destination = SteamWorkshopGridKeyboardNavigation.destinationIndex(
            keyCode: keyCode,
            currentIndex: focusedIndex,
            itemCount: orderedIDs.count,
            columnCount: currentColumnCount
        ) else { return false }
        focusItem(at: destination)
        return true
    }

    func moveSelectionByArrowKey(_ keyCode: UInt16) {
        _ = handleArrowKey(keyCode)
    }

    func previewSelected() {
        guard !service.isDownloadsMultiSelectMode,
              let previewURL = service.selectedDownloadRecord?.videoURL else { return }
        SteamWorkshopDownloadsQuickLookController.shared.open(previewURL: previewURL) { [weak self] in
            guard let self, !self.service.isDownloadsMultiSelectMode else { return nil }
            return self.service.selectedDownloadRecord?.videoURL
        }
    }

    private func handleBackgroundClick() {
        guard !service.isDownloadsMultiSelectMode else { return }
        keyboardFocusedID = nil
        service.selectDownload(itemID: nil)
    }

    private func makeContextMenu(for indexPath: IndexPath?) -> NSMenu? {
        if let indexPath,
           indexPath.item >= 0,
           indexPath.item < orderedIDs.count {
            let id = orderedIDs[indexPath.item]
            keyboardFocusedID = id
            if service.isDownloadsMultiSelectMode {
                if !service.selectedDownloadIDs.contains(id) {
                    service.replaceSelectedDownloads(with: [id], primaryID: id)
                }
            } else if service.selectedDownloadID != id {
                service.selectDownload(itemID: id)
            }
            reloadKeyboardFocus(previous: nil, next: id)
        }

        let selection = service.effectiveSelectedDownloadIDs
        guard !selection.isEmpty else { return nil }

        let menu = NSMenu()
        menu.autoenablesItems = false

        if !service.isDownloadsMultiSelectMode,
           let record = service.selectedDownloadRecord {
            if let primaryActionItem = makePrimaryActionMenuItem(for: record) {
                menu.addItem(primaryActionItem)
            }

            menu.addItem(
                makeMenuItem(
                    title: "详情信息",
                    symbolName: "info.circle",
                    action: #selector(contextShowInfo),
                    isEnabled: service.canShowSelectedDownloadInfo
                )
            )

            menu.addItem(
                makeMenuItem(
                    title: "查看文件",
                    symbolName: "folder",
                    action: #selector(contextRevealItem),
                    isEnabled: service.canRevealSelectedDownload
                )
            )
            menu.addItem(.separator())
        }

        menu.addItem(
            makeMenuItem(
                title: "删除",
                symbolName: "trash",
                action: #selector(contextDeleteSelected),
                isEnabled: service.canDeleteSelectedDownload
            )
        )
        return menu
    }

    private func handlePrimaryClick(at indexPath: IndexPath) -> Bool {
        guard indexPath.item >= 0, indexPath.item < orderedIDs.count else { return true }
        let id = orderedIDs[indexPath.item]
        if !service.isDownloadsMultiSelectMode {
            let previousID = keyboardFocusedID
            keyboardFocusedID = id
            reloadKeyboardFocus(previous: previousID, next: id)
            service.selectDownload(itemID: id)
            // 点击卡片（含已选中卡片再次点击）直接呼出详情面板。
            service.presentSelectedDownloadInfo()
            return true
        }

        var selectedIDs = service.selectedDownloadIDs
        if selectedIDs.contains(id) {
            selectedIDs.remove(id)
        } else {
            selectedIDs.insert(id)
        }
        keyboardFocusedID = id
        service.replaceSelectedDownloads(with: selectedIDs, primaryID: id)
        return true
    }

    private func scrollToItem(_ id: String) {
        guard let indexPath = indexPathForItemID(id),
              let attrs = flowLayout.layoutAttributesForItem(at: indexPath) else { return }
        let itemFrame = attrs.frame
        let visibleRect = scrollView.contentView.bounds
        guard !visibleRect.contains(itemFrame) else { return }
        let targetY: CGFloat
        if itemFrame.minY < visibleRect.minY {
            targetY = max(0, itemFrame.minY - 4)
        } else {
            targetY = itemFrame.maxY - visibleRect.height + 4
        }
        scrollView.contentView.setBoundsOrigin(NSPoint(x: visibleRect.origin.x, y: targetY))
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    private func indexPathForItemID(_ id: String) -> IndexPath? {
        guard let index = orderedIDs.firstIndex(of: id) else { return nil }
        return IndexPath(item: index, section: 0)
    }

    private func cellForItemID(_ id: String) -> AppKitSteamWorkshopBrowserItem? {
        guard let indexPath = indexPathForItemID(id) else { return nil }
        return collectionView.item(at: indexPath) as? AppKitSteamWorkshopBrowserItem
    }

    private func reloadKeyboardFocus(previous: String?, next: String?) {
        updateKeyboardFocusItem(withID: previous, focused: false)
        updateKeyboardFocusItem(withID: next, focused: true)
    }

    private func applySelection() {
        let selectedIndexPaths = Set(collectionView.selectionIndexPaths)
        guard !selectedIndexPaths.isEmpty else { return }
        isApplyingSelectionSnapshot = true
        collectionView.deselectItems(at: selectedIndexPaths)
        isApplyingSelectionSnapshot = false
    }

    private func presentDownloadDetail(for id: String) {
        guard recordsByID[id] != nil else { return }
        service.presentDownloadInfo(for: id)
    }

    private func updateKeyboardFocusItem(withID id: String?, focused: Bool) {
        guard let id else { return }
        if let item = cellForItemID(id) {
            item.setKeyboardFocus(focused)
            return
        }
        guard let indexPath = indexPathForItemID(id) else { return }
        collectionView.reloadItems(at: Set([indexPath]))
    }
}

extension AppKitSteamWorkshopDownloadsContainerView: SteamWorkshopKeyboardDelegate {
    func steamWorkshopCollectionView(_ collectionView: SteamWorkshopKeyboardCollectionView, handleKey event: NSEvent) -> Bool {
        if event.keyCode == 0,
           event.modifierFlags.intersection([.command]) == .command,
           event.modifierFlags.intersection([.control, .option, .shift]).isEmpty,
           service.isDownloadsMultiSelectMode {
            service.replaceSelectedDownloads(with: Set(orderedIDs), primaryID: keyboardFocusedID ?? orderedIDs.first)
            return true
        }

        if service.isDownloadsMultiSelectMode {
            return handleArrowKey(event.keyCode)
        }
        switch event.keyCode {
        case 123, 124, 125, 126:
            return handleArrowKey(event.keyCode)
        case let keyCode where SteamWorkshopGridKeyboardNavigation.isPrimaryActionKey(keyCode):
            guard !event.isARepeat else { return true }
            return handleReturnKey()
        case 53:
            return handleEscapeKey()
        default:
            break
        }
        return false
    }
}

extension AppKitSteamWorkshopDownloadsContainerView: NSCollectionViewDelegateFlowLayout {
    func collectionView(
        _ collectionView: NSCollectionView,
        willDisplay item: NSCollectionViewItem,
        forRepresentedObjectAt indexPath: IndexPath
    ) {
        guard let item = item as? AppKitSteamWorkshopBrowserItem else { return }
        item.setPreviewVisible(true)
    }

    func collectionView(
        _ collectionView: NSCollectionView,
        didEndDisplaying item: NSCollectionViewItem,
        forRepresentedObjectAt indexPath: IndexPath
    ) {
        guard let item = item as? AppKitSteamWorkshopBrowserItem else { return }
        item.setPreviewVisible(false)
    }

    func collectionView(_ collectionView: NSCollectionView, didSelectItemsAt indexPaths: Set<IndexPath>) {
        guard !isApplyingSelectionSnapshot else { return }
        let selectedIDs = Set<String>(collectionView.selectionIndexPaths.compactMap { indexPath in
            guard indexPath.item < orderedIDs.count else { return nil }
            return orderedIDs[indexPath.item]
        })
        guard !selectedIDs.isEmpty else {
            service.replaceSelectedDownloads(with: [], primaryID: nil)
            return
        }
        let selectedID = indexPaths.first.flatMap { path in
            path.item < orderedIDs.count ? orderedIDs[path.item] : nil
        } ?? selectedIDs.first
        let previousID = keyboardFocusedID
        keyboardFocusedID = selectedID
        service.replaceSelectedDownloads(with: selectedIDs, primaryID: selectedID)
        reloadKeyboardFocus(previous: previousID, next: selectedID)
    }

    func collectionView(_ collectionView: NSCollectionView, didDeselectItemsAt indexPaths: Set<IndexPath>) {
        guard !isApplyingSelectionSnapshot else { return }
        let remainingIDs = Set<String>(collectionView.selectionIndexPaths.compactMap { indexPath in
            guard indexPath.item < orderedIDs.count else { return nil }
            return orderedIDs[indexPath.item]
        })
        let previousID = keyboardFocusedID
        keyboardFocusedID = remainingIDs.contains(previousID ?? "") ? previousID : remainingIDs.first
        service.replaceSelectedDownloads(with: remainingIDs, primaryID: keyboardFocusedID)
        reloadKeyboardFocus(previous: previousID, next: keyboardFocusedID)
    }
}

extension AppKitSteamWorkshopDownloadsContainerView {
    private func makePrimaryActionMenuItem(for record: SteamWorkshopDownloadRecord) -> NSMenuItem? {
        let action = SteamWorkshopDownloadGridSupport.primaryAction(for: record, service: service)
        let config: (title: String, symbolName: String)?
        switch action {
        case .setAsWallpaper:
            config = ("设为壁纸", "play.fill")
        case .retryDownload:
            config = ("重新下载", "square.and.arrow.down")
        case .cancelDownload:
            config = ("取消下载", "xmark")
        case .none:
            config = nil
        }
        guard let config else {
            return nil
        }
        return makeMenuItem(
            title: config.title,
            symbolName: config.symbolName,
            action: #selector(contextPerformPrimaryAction)
        )
    }

    private func makeMenuItem(
        title: String,
        symbolName: String,
        action: Selector,
        isEnabled: Bool = true
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.isEnabled = isEnabled
        item.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: title)
        return item
    }

    @objc private func contextPerformPrimaryAction() {
        guard let record = service.selectedDownloadRecord else { return }
        SteamWorkshopDownloadGridSupport.performPrimaryAction(
            for: record,
            service: service,
            onSetAsWallpaper: onSetAsWallpaper
        )
    }

    @objc private func contextShowInfo() {
        service.presentSelectedDownloadInfo()
    }

    @objc private func contextRevealItem() {
        service.revealSelectedDownload()
    }

    @objc private func contextDeleteSelected() {
        service.deleteSelectedDownload()
    }
}
