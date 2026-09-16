//
//  SILGridContainerView.swift
//  MyWallpaperX — Modules/StaticImageLibrary/UI
//
//  参照 AppKitLibraryGridContainerView。
//  数据由外部 updateNSView 推入，容器内部不订阅 SILService。
//
import AppKit
import Combine

enum SILThumbnailLoadResult {
    case image(NSImage)
    case missingFile
    case unavailable
}

final class SILGridContainerView: NSView, ModuleFocusable {
    private enum Section { case main }

    // MARK: - 子视图
    private let emptyLabel: NSTextField = {
        let l = NSTextField(labelWithString: "还没有图片壁纸\n点击工具栏 + 导入")
        l.alignment = .center; l.textColor = .secondaryLabelColor
        l.font = .systemFont(ofSize: 18, weight: .regular)
        l.lineBreakMode = .byWordWrapping; l.maximumNumberOfLines = 2
        l.isHidden = true; l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    private let scrollView: NSScrollView = {
        let sv = NSScrollView()
        sv.drawsBackground = false; sv.hasVerticalScroller = true
        sv.hasHorizontalScroller = false
        sv.translatesAutoresizingMaskIntoConstraints = false
        return sv
    }()

    lazy var collectionView: SILCollectionView = {
        let cv = SILCollectionView()
        cv.isSelectable = true; cv.allowsMultipleSelection = false
        cv.backgroundColors = [.clear]; cv.delegate = self
        cv.onBackgroundLeftClick = { [weak self] in self?.handleBackgroundClick() }
        cv.contextMenuProvider = { [weak self] ip in self?.makeContextMenu(for: ip) }
        cv.cardInteractionHandler = {}
        cv.cardPressStateHandler = { [weak self] ip, p in self?.updateCardPressState(at: ip, isPressed: p) }
        // 已选中卡片再次点击：呼出详情面板（新选中由 didSelect 处理）。
        cv.primaryClickHandler = { [weak self] ip in
            guard let self, !SILService.shared.isMultiSelectMode,
                  ip.item < orderedIDs.count else { return false }
            if SILService.shared.selectedID == orderedIDs[ip.item] {
                SILService.shared.presentInspectorForSelectedWallpaper()
                return true
            }
            return false
        }
        cv.boxSelectionBeginHandler = { [weak self] ip in self?.beginBoxSelection(at: ip) ?? false }
        cv.boxSelectionUpdateHandler = { [weak self] r in self?.updateBoxSelection(in: r) }
        cv.boxSelectionEndHandler = { [weak self] in self?.endBoxSelection() }
        cv.translatesAutoresizingMaskIntoConstraints = false
        return cv
    }()

    private lazy var waterfallLayout: SILWaterfallLayout = {
        let l = SILWaterfallLayout()
        l.columnSpacing = 8
        l.rowSpacing = 10
        l.sectionInset = NSEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        l.aspectRatioProvider = { [weak self] ip in
            guard let self, ip.item < self.orderedIDs.count,
                  let w = self.wallpapersByID[self.orderedIDs[ip.item]] else { return 16.0 / 9.0 }
            return w.aspectRatio
        }
        return l
    }()

    private lazy var dataSource: NSCollectionViewDiffableDataSource<Section, String> = {
        NSCollectionViewDiffableDataSource<Section, String>(collectionView: collectionView) {
            [weak self] cv, ip, wid -> NSCollectionViewItem? in
            guard let self, let w = self.wallpapersByID[wid] else { return nil }
            guard let item = cv.makeItem(withIdentifier: SILGridItem.reuseID, for: ip) as? SILGridItem else { return nil }
            let svc = SILService.shared
            let isSel = svc.selectedID == wid || svc.selectedIDs.contains(wid)
            item.configure(
                wallpaper: w, isSelected: isSel,
                isMultiSelectMode: svc.isMultiSelectMode
            ) { [weak self] completion in
                guard let self else {
                    completion(.unavailable)
                    return
                }
                guard FileManager.default.fileExists(atPath: w.path) else {
                    completion(.missingFile)
                    return
                }
                if let signature = self.thumbnailFailureSignature(for: w),
                   self.failedThumbnailSignatures.contains(signature) {
                    completion(.unavailable)
                    return
                }
                self.thumbnailCache.load(forKey: w.path, loader: {
                    guard let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: w.path) as CFURL, nil) else { return nil }
                    let opts: [CFString: Any] = [
                        kCGImageSourceThumbnailMaxPixelSize: 512,
                        kCGImageSourceCreateThumbnailFromImageAlways: true,
                        kCGImageSourceCreateThumbnailWithTransform: true
                    ]
                    guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { return nil }
                    return NSImage(cgImage: cg, size: .zero)
                }, completion: { [weak self] image in
                    guard let self else {
                        completion(image.map(SILThumbnailLoadResult.image) ?? .unavailable)
                        return
                    }
                    if let signature = self.thumbnailFailureSignature(for: w) {
                        if image != nil {
                            self.failedThumbnailSignatures.remove(signature)
                        } else {
                            self.failedThumbnailSignatures.insert(signature)
                        }
                    }
                    completion(image.map(SILThumbnailLoadResult.image) ?? .unavailable)
                })
            }
            return item
        }
    }()

    // MARK: - 状态
    private let thumbnailCache = SILThumbnailStore.sharedCache
    private var failedThumbnailSignatures: Set<String> = []
    var wallpapersByID: [String: SILWallpaper] = [:]
    /// 当前标签上下文；nil 表示「我的图片」全库，由 Shell detail host 写入
    var currentSILTag: String? = nil
    private var orderedIDs: [String] = []
    private var lastKnownMultiSelectMode: Bool = false
    private var orderedIndexByID: [String: Int] = [:]
    private var lastAppliedIDs: [String] = []
    private var pendingIDs: [String] = []
    private var isSnapshotScheduled = false
    private var isVisibleRefreshScheduled = false
    private var isSelectionSyncScheduled = false
    private var isSelectionVisualUpdateScheduled = false
    private var isLayoutItemSizeUpdateScheduled = false
    var isApplyingSelectionSnapshot = false
    private var lastObservedSelectedIDs = Set<String>()
    private var boxSelectionState: BoxSelectionState?
    private var restingScrollOrigin: NSPoint?
    private var isScrollToTopAnimating = false
    private var scrollToTopObserver: NSObjectProtocol?
    private var moduleFocusObserver: NSObjectProtocol?
    private var missingPathTimer: DispatchSourceTimer?

    // MARK: - Init
    init() {
        super.init(frame: .zero)
        SILGridItem.resetHoverTracking()
        setupViewHierarchy()
        observeScrollToTop()
        startMissingPathTimer()
        _ = dataSource
        observeModuleFocusRequests()
    }
    @available(*, unavailable) required init?(coder: NSCoder) { nil }

    deinit {
        scrollToTopObserver.map { NotificationCenter.default.removeObserver($0) }
        moduleFocusObserver.map { NotificationCenter.default.removeObserver($0) }
        missingPathTimer?.cancel()
    }

    // MARK: - ModuleFocusable

    func requestFocus() {
        window?.makeFirstResponder(collectionView)
    }

    private func observeModuleFocusRequests() {
        moduleFocusObserver = NotificationCenter.default.addObserver(
            forName: .moduleDidBecomeActive,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self,
                  let module = notification.userInfo?["module"] as? String,
                  module == ModuleIdentifier.staticImageLibrary.rawValue else { return }
            self.requestFocus()
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil else { return }
        scheduleRestingScrollOriginCapture()
    }

    override func layout() {
        super.layout()
        scheduleLayoutItemSizeUpdate()
    }

    // MARK: - 外部数据入口
    func update(wallpapers: [SILWallpaper]) {
        var byID: [String: SILWallpaper] = [:]
        for w in wallpapers { byID[w.id] = w }
        wallpapersByID = byID
        orderedIDs = wallpapers.map(\.id)
        orderedIndexByID = Dictionary(uniqueKeysWithValues: orderedIDs.enumerated().map { ($1, $0) })
        applySnapshot(ids: orderedIDs)
        scheduleSyncSelection()
        emptyLabel.isHidden = !orderedIDs.isEmpty
    }

    /// 外部 zoomOffset 变化时调用，触发 layout 重新计算卡片尺寸
    func invalidateLayout() {
        scheduleLayoutItemSizeUpdate()
    }

    // MARK: - Snapshot
    private func applySnapshot(ids: [String]) {
        pendingIDs = ids
        guard !isSnapshotScheduled else { return }
        isSnapshotScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.isSnapshotScheduled = false
            let ids = self.pendingIDs
            guard ids != self.lastAppliedIDs else { return }
            let animate = !self.lastAppliedIDs.isEmpty
                && abs(ids.count - self.lastAppliedIDs.count)
                    <= max(20, self.collectionView.indexPathsForVisibleItems().count + 10)
            var snap = NSDiffableDataSourceSnapshot<Section, String>()
            snap.appendSections([.main]); snap.appendItems(ids, toSection: .main)
            self.dataSource.apply(snap, animatingDifferences: animate) { [weak self] in
                guard let self else { return }
                self.lastAppliedIDs = ids
                self.scheduleVisibleRefresh()
                self.scheduleRestingScrollOriginCapture()
            }
        }
    }
}

// MARK: - 调度
extension SILGridContainerView {
    func scheduleVisibleRefresh() {
        guard !isVisibleRefreshScheduled else { return }
        isVisibleRefreshScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.isVisibleRefreshScheduled = false; self.refreshVisibleItems()
        }
    }
    private func scheduleSyncSelection() {
        guard !isSelectionSyncScheduled else { return }
        isSelectionSyncScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.isSelectionSyncScheduled = false; self.syncSelectionFromService()
        }
    }
    /// 多选模式变化时立即刷新所有可见 item
    func refreshVisibleItemsIfNeeded(isMultiSelectMode: Bool) {
        guard lastKnownMultiSelectMode != isMultiSelectMode else { return }
        lastKnownMultiSelectMode = isMultiSelectMode
        refreshVisibleItems()
    }

    func scheduleSelectionVisualUpdate() {
        guard !isSelectionVisualUpdateScheduled else { return }
        isSelectionVisualUpdateScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.isSelectionVisualUpdateScheduled = false; self.updateSelectionVisualsIfNeeded()
        }
    }
    private func scheduleRestingScrollOriginCapture() {
        guard restingScrollOrigin == nil else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, self.restingScrollOrigin == nil,
                  self.window != nil, !self.lastAppliedIDs.isEmpty else { return }
            self.restingScrollOrigin = self.scrollView.contentView.bounds.origin
        }
    }
    private func refreshVisibleItems() {
        let vips = Set(collectionView.indexPathsForVisibleItems()); guard !vips.isEmpty else { return }
        let svc = SILService.shared
        var selIDs = svc.selectedIDs; if let sid = svc.selectedID { selIDs.insert(sid) }
        let isMulti = svc.isMultiSelectMode
        var reload = Set<IndexPath>()
        for ip in vips {
            guard ip.item < orderedIDs.count else { continue }
            let wid = orderedIDs[ip.item]
            if let item = collectionView.item(at: ip) as? SILGridItem {
                item.applySelectionState(isSelected: selIDs.contains(wid), multiSelectMode: isMulti)
            } else { reload.insert(ip) }
        }
        if !reload.isEmpty { collectionView.reloadItems(at: reload) }
    }
    private func syncSelectionFromService() {
        let svc = SILService.shared
        collectionView.allowsMultipleSelection = svc.isMultiSelectMode
        collectionView.isBoxSelectionEnabled = svc.isMultiSelectMode
        if svc.isMultiSelectMode {
            if !collectionView.selectionIndexPaths.isEmpty {
                isApplyingSelectionSnapshot = true; collectionView.selectionIndexPaths = []; isApplyingSelectionSnapshot = false
            }; return
        }
        var selIDs = svc.selectedIDs; if let sid = svc.selectedID { selIDs.insert(sid) }
        var ips = Set<IndexPath>()
        for id in selIDs { if let idx = orderedIndexByID[id] { ips.insert(IndexPath(item: idx, section: 0)) } }
        guard collectionView.selectionIndexPaths != ips else { return }
        isApplyingSelectionSnapshot = true; collectionView.selectionIndexPaths = ips; isApplyingSelectionSnapshot = false
    }
    private func updateSelectionVisualsIfNeeded() {
        let svc = SILService.shared
        var cur = svc.selectedIDs; if let sid = svc.selectedID { cur.insert(sid) }
        let changed = cur.symmetricDifference(lastObservedSelectedIDs); lastObservedSelectedIDs = cur
        guard !changed.isEmpty else { return }
        let vips = Set(collectionView.indexPathsForVisibleItems()); var reload = Set<IndexPath>()
        for id in changed {
            guard let idx = orderedIndexByID[id] else { continue }
            let ip = IndexPath(item: idx, section: 0); guard vips.contains(ip) else { continue }
            if let item = collectionView.item(at: ip) as? SILGridItem {
                item.applySelectionState(isSelected: cur.contains(id), multiSelectMode: svc.isMultiSelectMode)
            } else { reload.insert(ip) }
        }
        if !reload.isEmpty { collectionView.reloadItems(at: reload) }
        scrollToSelectedIfNeeded()
    }
    func scrollToSelectedIfNeeded() {
        guard !SILService.shared.isMultiSelectMode, let sid = SILService.shared.selectedID,
              let idx = orderedIndexByID[sid] else { return }
        let ip = IndexPath(item: idx, section: 0)
        guard let attrs = waterfallLayout.layoutAttributesForItem(at: ip) else { return }
        let frame = attrs.frame; let visible = scrollView.contentView.bounds
        guard !visible.contains(frame) else { return }
        let y = frame.minY < visible.minY ? max(0, frame.minY - 4) : frame.maxY - visible.height + 4
        scrollView.contentView.setBoundsOrigin(NSPoint(x: visible.origin.x, y: y))
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }
}

// MARK: - 布局 + 视图层级
extension SILGridContainerView {
    private func scheduleLayoutItemSizeUpdate() {
        guard !isLayoutItemSizeUpdateScheduled else { return }
        isLayoutItemSizeUpdateScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.isLayoutItemSizeUpdateScheduled = false
            self.updateLayoutItemSize()
        }
    }

    func updateLayoutItemSize() {
        let inset = waterfallLayout.sectionInset
        let avail = max(0, bounds.width - inset.left - inset.right)
        let cols = GridLayoutHelper.columnCount(for: avail, zoomOffset: SILService.shared.gridZoomOffset)
        // 同步到 SILService，供方向键导航使用
        SILService.shared.visibleGridColumnCount = cols
        guard waterfallLayout.columnCount != cols else { return }
        waterfallLayout.columnCount = cols
        waterfallLayout.invalidateLayout()
    }
    private func setupViewHierarchy() {
        wantsLayer = true; layer?.backgroundColor = NSColor.clear.cgColor
        collectionView.collectionViewLayout = waterfallLayout
        collectionView.register(SILGridItem.self, forItemWithIdentifier: SILGridItem.reuseID)
        scrollView.documentView = collectionView
        scrollView.contentView.postsBoundsChangedNotifications = true
        addSubview(scrollView); addSubview(emptyLabel)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
            emptyLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }
    private func observeScrollToTop() {
        scrollToTopObserver = NotificationCenter.default.addObserver(
            forName: .appKitRequestScrollToTopForCurrentSelection, object: nil, queue: .main
        ) { [weak self] _ in self?.scrollToTop(animated: true) }
    }
    private func scrollToTop(animated: Bool) {
        guard !isScrollToTopAnimating, scrollView.documentView != nil else { return }
        let target = restingScrollOrigin ?? .zero
        guard scrollView.contentView.bounds.origin != target else { return }
        isScrollToTopAnimating = true
        NotificationCenter.default.post(name: .appKitLibraryGridScrollToTopAnimationWillStart, object: nil)
        NSAnimationContext.runAnimationGroup { ctx in
            let dist = abs(scrollView.contentView.bounds.origin.y - target.y)
            ctx.duration = animated ? min(0.36, max(0.20, dist / 5200.0)) : 0
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.18, 0.85, 0.20, 1.0)
            self.scrollView.contentView.animator().setBoundsOrigin(target)
        } completionHandler: { [weak self] in
            guard let self else { return }
            self.scrollView.reflectScrolledClipView(self.scrollView.contentView)
            self.isScrollToTopAnimating = false
            NotificationCenter.default.post(name: .appKitLibraryGridScrollToTopAnimationDidEnd, object: nil)
        }
    }
    private func startMissingPathTimer() {
        let t = DispatchSource.makeTimerSource(queue: .main)
        t.schedule(deadline: .now() + 2.0, repeating: 2.0, leeway: .milliseconds(300))
        t.setEventHandler { [weak self] in self?.probeMissingPaths() }
        missingPathTimer = t; t.resume()
    }
    private func probeMissingPaths() {
        let vips = collectionView.indexPathsForVisibleItems(); guard !vips.isEmpty else { return }
        var reload = Set<IndexPath>()
        for ip in vips {
            guard ip.item < orderedIDs.count, let w = wallpapersByID[orderedIDs[ip.item]] else { continue }
            if !FileManager.default.fileExists(atPath: w.path) { reload.insert(ip) }
        }
        if !reload.isEmpty { collectionView.reloadItems(at: reload) }
    }

    private func thumbnailFailureSignature(for wallpaper: SILWallpaper) -> String? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: wallpaper.path) else { return nil }
        let size = (attrs[.size] as? NSNumber)?.int64Value ?? -1
        let modifiedAt = (attrs[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        return "\(wallpaper.path)|\(size)|\(Int64(modifiedAt))"
    }
}

// MARK: - 交互
extension SILGridContainerView {
    func handleBackgroundClick() {
        guard !SILService.shared.isMultiSelectMode else { return }
        SILService.shared.clearSingleSelection(); collectionView.selectionIndexPaths = []
    }
    func updateCardPressState(at ip: IndexPath, isPressed: Bool) {
        guard ip.item < orderedIDs.count else { return }
        (collectionView.item(at: ip) as? SILGridItem)?.applyPressedState(isPressed)
    }
    func beginBoxSelection(at ip: IndexPath?) -> Bool {
        guard SILService.shared.isMultiSelectMode else { return false }
        let svc = SILService.shared
        let mode: BoxSelectionState.Mode
        if let ip, ip.item < orderedIDs.count {
            mode = svc.selectedIDs.contains(orderedIDs[ip.item]) ? .deselect : .select
        } else { mode = .select }
        boxSelectionState = BoxSelectionState(mode: mode, initialIDs: svc.selectedIDs); return true
    }
    func updateBoxSelection(in rect: NSRect) {
        guard let state = boxSelectionState else { return }
        var ids = Set<String>()
        let q = rect.standardized
        if let attrs = collectionView.collectionViewLayout?.layoutAttributesForElements(in: q) {
            for a in attrs where a.representedElementCategory == .item {
                if let i = a.indexPath?.item, i < orderedIDs.count { ids.insert(orderedIDs[i]) }
            }
        }
        let result = state.resolve(touching: ids)
        guard result != SILService.shared.selectedIDs else { return }
        SILService.shared.replaceMultiSelection(with: result)
    }
    func endBoxSelection() { boxSelectionState = nil }
    func makeContextMenu(for ip: IndexPath?) -> NSMenu? {
        if let ip, ip.item < orderedIDs.count {
            let id = orderedIDs[ip.item]
            if SILService.shared.isMultiSelectMode {
                if !SILService.shared.selectedIDs.contains(id) { SILService.shared.replaceMultiSelection(with: [id]) }
            } else { SILService.shared.setSingleSelection(id) }
        }
        guard let id = SILService.shared.singleEffectiveSelectedID ?? SILService.shared.selectedIDs.first,
              wallpapersByID[id] != nil else { return nil }
        let svc = SILService.shared
        let menu = NSMenu(title: "SILMenu")
        menu.autoenablesItems = false
        let singleSelectionEnabled = svc.singleEffectiveSelectedID != nil

        menu.addItem(
            makeMenuItem(
                title: "设为壁纸",
                symbolName: "photo",
                accessibilityDescription: "设为壁纸",
                action: #selector(ctxSetAsWallpaper),
                isEnabled: singleSelectionEnabled
            )
        )

        menu.addItem(
            makeMenuItem(
                title: "快速预览",
                symbolName: "eye",
                accessibilityDescription: "快速预览",
                action: #selector(ctxQuickLook),
                isEnabled: singleSelectionEnabled
            )
        )

        menu.addItem(.separator())

        menu.addItem(
            makeMenuItem(
                title: "查看文件",
                symbolName: "folder",
                accessibilityDescription: "查看文件",
                action: #selector(ctxReveal),
                isEnabled: singleSelectionEnabled
            )
        )

        menu.addItem(
            makeMenuItem(
                title: "详细信息",
                symbolName: "info.circle",
                accessibilityDescription: "详细信息",
                action: #selector(ctxInfo),
                isEnabled: singleSelectionEnabled
            )
        )

        menu.addItem(
            makeMenuItem(
                title: "添加标签",
                symbolName: "tag",
                accessibilityDescription: "添加标签",
                action: #selector(ctxAddTag),
                isEnabled: !svc.silTags.isEmpty
            )
        )

        menu.addItem(.separator())

        menu.addItem(
            makeMenuItem(
                title: "从列表移除",
                symbolName: "trash",
                accessibilityDescription: "移除",
                action: #selector(ctxDelete),
                isEnabled: true
            )
        )

        return menu
    }
    private func makeMenuItem(
        title: String,
        symbolName: String,
        accessibilityDescription: String,
        action: Selector,
        isEnabled: Bool
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.isEnabled = isEnabled
        item.image = NSImage(
            systemSymbolName: symbolName,
            accessibilityDescription: accessibilityDescription
        )
        return item
    }
    @objc private func ctxSetAsWallpaper() {
        guard let id = SILService.shared.singleEffectiveSelectedID,
              let wallpaper = wallpapersByID[id] else { return }
        NotificationCenter.default.post(
            name: .staticImageWallpaperReadyToApply,
            object: nil,
            userInfo: ["imageURL": URL(fileURLWithPath: wallpaper.path)]
        )
    }
    @objc private func ctxQuickLook() {
        guard let id = SILService.shared.singleEffectiveSelectedID, let w = wallpapersByID[id] else { return }
        SILQuickLookController.shared.open(url: URL(fileURLWithPath: w.path))
    }
    @objc private func ctxReveal() {
        guard let id = SILService.shared.singleEffectiveSelectedID, let w = wallpapersByID[id] else { return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: w.path)])
    }
    @objc private func ctxInfo() {
        guard let id = SILService.shared.singleEffectiveSelectedID, wallpapersByID[id] != nil else { return }
        SILService.shared.presentInspectorForSelectedWallpaper()
    }
    @objc private func ctxAddTag() {
        let svc = SILService.shared
        let ids = svc.effectiveSelectedIDs
        guard !ids.isEmpty else { return }
        let tags = svc.silTags
        guard !tags.isEmpty else { return }
        let picker = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        picker.addItems(withTitles: tags)
        picker.selectItem(at: 0)
        let alert = makeAppAlert(
            title: "添加图片标签",
            message: "请选择要添加的标签",
            buttons: ["确定", "取消"],
            accessoryView: picker
        )
        presentAppAlert(alert, in: window) { r in
            guard r == .alertFirstButtonReturn,
                  let tag = picker.titleOfSelectedItem, !tag.isEmpty else { return }
            SILService.shared.addSILTag(tag, toSelected: ids)
        }
    }

    @objc private func ctxDelete() {
        let ids = SILService.shared.effectiveSelectedIDs; guard !ids.isEmpty else { return }
        let isTagContext = currentSILTag != nil
        let message = isTagContext
            ? "将从标签「\(currentSILTag!)」中移除 \(ids.count) 张图片（不删除「我的图片」总库中的记录）。"
            : "将从列表中移除 \(ids.count) 张图片（不删除原文件）。"
        let alert = makeAppAlert(title: "移除图片壁纸",
            message: message,
            style: .warning, buttons: ["移除", "取消"])
        presentAppAlert(alert, in: window) { [weak self] r in
            guard r == .alertFirstButtonReturn else { return }
            if let tag = self?.currentSILTag {
                SILService.shared.removeFromSILTag(tag, ids: ids)
            } else {
                SILService.shared.remove(ids: ids)
            }
        }
    }
}

// MARK: - NSCollectionViewDelegate
extension SILGridContainerView: NSCollectionViewDelegate {
    func collectionView(_ cv: NSCollectionView,
                        shouldDeselectItemsAt ips: Set<IndexPath>) -> Set<IndexPath> {
        guard !SILService.shared.isMultiSelectMode else { return ips }; return []
    }
    func collectionView(_ cv: NSCollectionView, willDisplay item: NSCollectionViewItem,
                        forRepresentedObjectAt ip: IndexPath) {
        guard ip.item < orderedIDs.count,
              let w = wallpapersByID[orderedIDs[ip.item]],
              let gi = item as? SILGridItem else { return }
        let svc = SILService.shared
        gi.applySelectionState(
            isSelected: svc.selectedID == w.id || svc.selectedIDs.contains(w.id),
            multiSelectMode: svc.isMultiSelectMode)
    }
    func collectionView(_ cv: NSCollectionView, didSelectItemsAt ips: Set<IndexPath>) {
        guard !isApplyingSelectionSnapshot else { return }
        let svc = SILService.shared
        if !svc.isMultiSelectMode {
            guard let ip = ips.first, ip.item < orderedIDs.count else { return }
            svc.setSingleSelection(orderedIDs[ip.item])
            svc.presentInspectorForSelectedWallpaper()
            return
        }
        let ids = Set(cv.selectionIndexPaths.compactMap { $0.item < orderedIDs.count ? orderedIDs[$0.item] : nil })
        svc.replaceMultiSelection(with: ids)
    }
    func collectionView(_ cv: NSCollectionView, didDeselectItemsAt ips: Set<IndexPath>) {
        guard !isApplyingSelectionSnapshot, SILService.shared.isMultiSelectMode else { return }
        guard (cv as? SILCollectionView)?.lastPrimaryClickIndexPath == nil else { return }
        let ids = Set(cv.selectionIndexPaths.compactMap { $0.item < orderedIDs.count ? orderedIDs[$0.item] : nil })
        SILService.shared.replaceMultiSelection(with: ids)
    }
}
