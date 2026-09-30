//
//  SILService.swift
//  MyWallpaperX — Modules/StaticImageLibrary/Core
//
//  图片壁纸库核心服务。
//  依赖：Models、Shared（无）。不依赖 VideoLibrary 任何类型。
//

import AppKit
import Combine
import Foundation
import UniformTypeIdentifiers

enum SILThumbnailStore {
    static let sharedCache = ThumbnailCache(
        label: "com.mywallpaper.sil.thumbnail",
        countLimit: 180
    )
}

// MARK: - 数据模型

struct SILWallpaper: Identifiable, Codable, Hashable {
    var id: String
    var path: String
    var title: String
    var fileSize: Int64?
    var pixelWidth: Int?
    var pixelHeight: Int?
    var tags: [String]
    var lastUsed: Date
    var addedAt: Date

    /// 图片宽高比（width/height），无尺寸信息时返回 16/9 作为默认值
    var aspectRatio: CGFloat {
        guard let w = pixelWidth, let h = pixelHeight, h > 0 else { return 16.0 / 9.0 }
        return CGFloat(w) / CGFloat(h)
    }

    init(path: String) {
        self.id = UUID().uuidString
        self.path = path
        self.title = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
        self.fileSize = (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? Int64)
        // 从图片文件读取像素尺寸（不解码像素，只读 metadata，极快）
        if let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
           let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any] {
            self.pixelWidth  = props[kCGImagePropertyPixelWidth]  as? Int
            self.pixelHeight = props[kCGImagePropertyPixelHeight] as? Int
        } else {
            self.pixelWidth  = nil
            self.pixelHeight = nil
        }
        self.tags = []
        self.lastUsed = Date.distantPast
        self.addedAt = Date()
    }
}

enum SILSortMode: String, CaseIterable, Codable {
    case none
    case name
    case lastUsed
    case fileSize
    case addedAt

    var displayName: String {
        switch self {
        case .none:     return "默认顺序"
        case .name:     return "文件名称"
        case .lastUsed: return "最近使用"
        case .fileSize: return "文件大小"
        case .addedAt:  return "添加时间"
        }
    }
}

struct SILSortState: Codable, Equatable {
    var mode: SILSortMode = .none
    var ascending: Bool = true
}

// MARK: - SILService

final class SILService: ObservableObject {

    static let shared = SILService()

    @Published var wallpapers: [SILWallpaper] = []
    @Published var selectedID: String? = nil
    @Published var selectedIDs: Set<String> = []
    @Published var inspectedWallpaperID: String? = nil
    @Published var isMultiSelectMode: Bool = false
    @Published var gridZoomOffset: Int = 0
    @Published var searchQuery: String = ""
    @Published var sortState: SILSortState = SILSortState()
    /// 当前网格实际列数，由 SILGridContainerView 在 layout 时写入，供方向键导航使用
    var visibleGridColumnCount: Int = 4
    /// 图片库专属标签列表（与视频库 WallpaperManager.tags 完全独立）
    @Published var silTags: [String] = []
    /// 当前激活的侧边栏标签上下文；nil 表示「我的图片」全库，非 nil 表示标签子视图
    /// 由 SILToolbarController 在收到 staticImageLibraryModeDidChange 通知时维护
    var currentContextTag: String? = nil

    private let persistenceURL: URL
    private let zoomOffsetKey = "SILGridZoomOffset"
    private let sortStateKey  = "SILSortState"
    private let silTagsKey    = "SILTags"
    private let initialMissingFilesAlertRetryLimit = 5

    /// 供外部（如重置功能）访问持久化文件路径
    var silPersistenceURL: URL { persistenceURL }

    private init() {
        let appSupport = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent(Bundle.main.bundleIdentifier ?? "MyWallpaperX")
        try? FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
        self.persistenceURL = appSupport.appendingPathComponent("sil_wallpapers.json")
        load()
        gridZoomOffset = UserDefaults.standard.integer(forKey: zoomOffsetKey)
        if let data = UserDefaults.standard.data(forKey: sortStateKey),
           let state = try? JSONDecoder().decode(SILSortState.self, from: data) {
            sortState = state
        }
        if let saved = UserDefaults.standard.stringArray(forKey: silTagsKey) {
            silTags = saved
        }
        reconcileMissingFilesOnLaunch()
    }

    // MARK: - 持久化

    func load() {
        guard let data = try? Data(contentsOf: persistenceURL),
              let decoded = try? JSONDecoder().decode([SILWallpaper].self, from: data) else { return }
        // 对旧数据补读像素尺寸（新导入的已在 init 时读取）
        wallpapers = decoded.map { w in
            guard w.pixelWidth == nil || w.pixelHeight == nil else { return w }
            var updated = w
            if let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: w.path) as CFURL, nil),
               let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any] {
                updated.pixelWidth  = props[kCGImagePropertyPixelWidth]  as? Int
                updated.pixelHeight = props[kCGImagePropertyPixelHeight] as? Int
            }
            return updated
        }
        // 如果有数据被补充，异步保存
        let needsSave = decoded.contains { $0.pixelWidth == nil || $0.pixelHeight == nil }
        if needsSave {
            DispatchQueue.global(qos: .utility).async { [weak self] in self?.save() }
        }
    }

    func save() {
        guard let data = try? JSONEncoder().encode(wallpapers) else { return }
        try? data.write(to: persistenceURL, options: .atomic)
    }

    func saveZoomOffset() {
        UserDefaults.standard.set(gridZoomOffset, forKey: zoomOffsetKey)
    }

    func saveSortState() {
        if let data = try? JSONEncoder().encode(sortState) {
            UserDefaults.standard.set(data, forKey: sortStateKey)
        }
    }

    func saveSILTags() {
        UserDefaults.standard.set(silTags, forKey: silTagsKey)
    }

    private func reconcileMissingFilesOnLaunch() {
        let fm = FileManager.default
        let removed = wallpapers.filter { !fm.fileExists(atPath: $0.path) }
        guard !removed.isEmpty else { return }

        let removedIDs = Set(removed.map(\.id))
        wallpapers.removeAll { removedIDs.contains($0.id) }
        selectedIDs.subtract(removedIDs)
        if let selectedID, removedIDs.contains(selectedID) {
            self.selectedID = nil
        }
        if let inspectedWallpaperID, removedIDs.contains(inspectedWallpaperID) {
            self.inspectedWallpaperID = nil
        }
        save()
        scheduleInitialMissingFilesAlert(for: removed, attempt: 0)
    }

    private func scheduleInitialMissingFilesAlert(for removed: [SILWallpaper], attempt: Int) {
        guard !removed.isEmpty else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + (attempt == 0 ? 0.9 : 0.45)) { [weak self] in
            guard let self else { return }
            guard let hostWindow = appModalHostWindow() else {
                guard attempt < self.initialMissingFilesAlertRetryLimit else { return }
                self.scheduleInitialMissingFilesAlert(for: removed, attempt: attempt + 1)
                return
            }

            let removedNames = removed.prefix(3).map {
                URL(fileURLWithPath: $0.path).lastPathComponent
            }
            var lines = ["启动时已自动从图库移除 \(removed.count) 个本地不存在的文件。"]
            if !removedNames.isEmpty {
                lines.append(removedNames.joined(separator: "\n"))
            }
            if removed.count > removedNames.count {
                lines.append("其余 \(removed.count - removedNames.count) 个文件也已同步移除。")
            }
            let alert = makeAppAlert(
                title: "图库已清理失效文件",
                message: lines.joined(separator: "\n\n"),
                buttons: ["好"]
            )
            presentAppAlert(alert, in: hostWindow)
        }
    }

    // MARK: - 图片专属标签 CRUD

    /// 新建图片标签，名称去空白后不能为空且不能重复，成功返回规范化名称
    @discardableResult
    func createSILTag(_ name: String) -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !silTags.contains(trimmed) else { return nil }
        silTags.append(trimmed)
        saveSILTags()
        return trimmed
    }

    /// 重命名图片标签，同时更新所有壁纸上的标签引用，返回新名称
    @discardableResult
    func renameSILTag(_ oldName: String, to newName: String) -> String? {
        let trimmed = newName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed != oldName, !silTags.contains(trimmed) else { return nil }
        guard let idx = silTags.firstIndex(of: oldName) else { return nil }
        silTags[idx] = trimmed
        // 同步更新壁纸上的标签引用
        for i in wallpapers.indices {
            if let tagIdx = wallpapers[i].tags.firstIndex(of: oldName) {
                wallpapers[i].tags[tagIdx] = trimmed
            }
        }
        saveSILTags()
        save()
        return trimmed
    }

    /// 删除图片标签，同时从所有壁纸上移除该标签引用
    func deleteSILTag(_ name: String) {
        silTags.removeAll { $0 == name }
        for i in wallpapers.indices {
            wallpapers[i].tags.removeAll { $0 == name }
        }
        saveSILTags()
        save()
    }

    /// 拖拽排序后保存新顺序（只允许已存在的标签，不新增也不删除）
    func reorderSILTags(_ newOrder: [String]) {
        let existing = Set(silTags)
        let filtered = newOrder.filter { existing.contains($0) }
        guard filtered != silTags else { return }
        silTags = filtered
        saveSILTags()
    }

    /// 给选中的壁纸添加标签（单选/多选均支持），完成后自动退出多选模式
    func addSILTag(_ tag: String, toSelected ids: Set<String>) {
        guard silTags.contains(tag) else { return }
        for i in wallpapers.indices where ids.contains(wallpapers[i].id) {
            if !wallpapers[i].tags.contains(tag) {
                wallpapers[i].tags.append(tag)
            }
        }
        save()
        clearSelectionState()
    }

    /// 当前选中壁纸的有效 ID 集合（多选模式用 selectedIDs，单选模式用 selectedID）
    var effectiveSelectedIDs: Set<String> {
        if isMultiSelectMode {
            return selectedIDs
        } else if let id = selectedID {
            return Set([id])
        } else {
            return []
        }
    }

    /// 同 effectiveSelectedIDs，用不同名称避免 MainWindowCoordinator 中的类型推断歧义
    var silSelectedIDs: Set<String> {
        effectiveSelectedIDs
    }

    /// 是否有选中（供 MainWindowCoordinator 用，避免 effectiveSelectedIDs 的类型歧义）
    var hasAnySelection: Bool {
        if isMultiSelectMode { return !selectedIDs.isEmpty }
        return selectedID != nil
    }

    /// 当前唯一有效选中项。
    /// 单选模式返回 `selectedID`，多选模式仅在恰好选中一项时返回该项。
    var singleEffectiveSelectedID: String? {
        if isMultiSelectMode {
            guard selectedIDs.count == 1 else { return nil }
            return selectedIDs.first
        }
        return selectedID
    }

    /// 某标签下的壁纸列表
    func wallpapers(forSILTag tag: String) -> [SILWallpaper] {
        wallpapers.filter { $0.tags.contains(tag) }
    }

    // MARK: - 计算属性

    var sortedWallpapers: [SILWallpaper] {
        let query = searchQuery.trimmingCharacters(in: .whitespaces).lowercased()
        let filtered: [SILWallpaper]
        if query.isEmpty {
            filtered = wallpapers
        } else {
            filtered = wallpapers.filter {
                $0.title.lowercased().contains(query) ||
                $0.path.lowercased().contains(query)
            }
        }
        guard sortState.mode != .none else { return filtered }
        return filtered.sorted { a, b in
            let asc = sortState.ascending
            switch sortState.mode {
            case .none:     return false
            case .name:     return asc ? a.title < b.title : a.title > b.title
            case .lastUsed: return asc ? a.lastUsed < b.lastUsed : a.lastUsed > b.lastUsed
            case .fileSize:
                let as_ = a.fileSize ?? 0; let bs = b.fileSize ?? 0
                return asc ? as_ < bs : as_ > bs
            case .addedAt:  return asc ? a.addedAt < b.addedAt : a.addedAt > b.addedAt
            }
        }
    }

    var currentActiveWallpaperPath: String? {
        guard let screen = NSScreen.main else { return nil }
        return NSWorkspace.shared.desktopImageURL(for: screen)?.path
    }

    // MARK: - 选择

    func setSingleSelection(_ id: String) {
        guard !isMultiSelectMode else { return }
        selectedID = id
        syncSelectedWallpaperInspectorIfNeeded()
    }

    func replaceMultiSelection(with ids: Set<String>) {
        selectedIDs = ids
        syncSelectedWallpaperInspectorIfNeeded()
    }

    func selectAll() {
        selectedIDs = Set(sortedWallpapers.map(\.id))
        syncSelectedWallpaperInspectorIfNeeded()
    }

    func deselectAll() {
        selectedIDs = []
        syncSelectedWallpaperInspectorIfNeeded()
    }

    func clearSingleSelection() {
        selectedID = nil
        syncSelectedWallpaperInspectorIfNeeded()
    }

    func enterMultiSelectMode() {
        isMultiSelectMode = true
        selectedIDs = []
        selectedID = nil
        syncSelectedWallpaperInspectorIfNeeded()
    }

    func exitMultiSelectMode() {
        isMultiSelectMode = false
        selectedIDs = []
        syncSelectedWallpaperInspectorIfNeeded()
    }

    /// 切换列表或执行批量操作后统一调用，效果与视频库 clearSelectionState() 一致
    func clearSelectionState() {
        isMultiSelectMode = false
        selectedIDs = []
        selectedID = nil
        syncSelectedWallpaperInspectorIfNeeded()
    }

    func moveSingleSelectionByArrowKey(_ keyCode: UInt16) {
        guard !isMultiSelectMode else { return }
        // 与网格显示列表保持一致（AppKitDetailHostViewController.updateSILGrid）：
        // 标签上下文只在该标签内导航，无标签上下文时回退全库
        var list = sortedWallpapers
        if let tag = currentContextTag {
            list = list.filter { $0.tags.contains(tag) }
        }
        guard !list.isEmpty else { return }
        guard let current = selectedID, let idx = list.firstIndex(where: { $0.id == current }) else {
            selectedID = list.first?.id
            syncSelectedWallpaperInspectorIfNeeded()
            return
        }
        let cols = max(1, visibleGridColumnCount)
        let newIdx: Int
        switch keyCode {
        case 123: newIdx = max(0, idx - 1)                    // ←
        case 124: newIdx = min(list.count - 1, idx + 1)       // →
        case 125: newIdx = min(list.count - 1, idx + cols)    // ↓
        case 126: newIdx = max(0, idx - cols)                 // ↑
        default: return
        }
        selectedID = list[newIdx].id
        syncSelectedWallpaperInspectorIfNeeded()
    }

    var selectedWallpaperForInspector: SILWallpaper? {
        guard let inspectedWallpaperID else { return nil }
        return wallpapers.first { $0.id == inspectedWallpaperID }
    }

    func presentInspectorForSelectedWallpaper() {
        guard let selectedID = singleEffectiveSelectedID,
              wallpapers.contains(where: { $0.id == selectedID }) else {
            return
        }
        inspectedWallpaperID = selectedID
    }

    func dismissSelectedWallpaperInspector() {
        inspectedWallpaperID = nil
    }

    func syncSelectedWallpaperInspectorIfNeeded() {
        guard inspectedWallpaperID != nil else { return }
        guard let selectedID = singleEffectiveSelectedID,
              wallpapers.contains(where: { $0.id == selectedID }) else {
            inspectedWallpaperID = nil
            return
        }
        inspectedWallpaperID = selectedID
    }

    // MARK: - 导入

    static var allowedUTTypes: [UTType] {
        [.jpeg, .png, .heic, .heif, .tiff, .bmp, .gif, 
         UTType("public.avif") ?? .image,
         UTType(filenameExtension: "webp") ?? .image]
    }

    static func isSupportedImage(_ url: URL) -> Bool {
        guard let type = UTType(filenameExtension: url.pathExtension) else { return false }
        return allowedUTTypes.contains { type.conforms(to: $0) }
    }

    func importImages(from urls: [URL], presentingIn window: NSWindow? = nil) {
        // 枚举目录、逐文件读元数据都在后台执行，主线程只做落库与 UI 刷新
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            var fileURLs: [URL] = []
            let fm = FileManager.default
            for url in urls {
                var isDir: ObjCBool = false
                if fm.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
                    if let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: nil) {
                        for case let fileURL as URL in enumerator where Self.isSupportedImage(fileURL) {
                            fileURLs.append(fileURL)
                        }
                    }
                } else if Self.isSupportedImage(url) {
                    fileURLs.append(url)
                }
            }
            let requestedCount = fileURLs.count
            var candidates: [(url: URL, wallpaper: SILWallpaper)] = []
            candidates.reserveCapacity(requestedCount)
            for url in fileURLs where fm.fileExists(atPath: url.path) {
                candidates.append((url, SILWallpaper(path: url.path)))
            }
            let missingCount = requestedCount - candidates.count
            DispatchQueue.main.async { [weak self] in
                self?.finishImport(candidates: candidates,
                                   requestedCount: requestedCount,
                                   missingCount: missingCount,
                                   presentingIn: window)
            }
        }
    }

    /// 后台元数据读取完成后的主线程落库：按归一化路径去重、补标签、保存并弹出结果
    private func finishImport(
        candidates: [(url: URL, wallpaper: SILWallpaper)],
        requestedCount: Int,
        missingCount: Int,
        presentingIn window: NSWindow?
    ) {
        let tag = currentContextTag
        var indexByNormalizedPath: [String: Int] = [:]
        for (index, wallpaper) in wallpapers.enumerated() {
            let key = Self.normalizedPath(wallpaper.path)
            if indexByNormalizedPath[key] == nil { indexByNormalizedPath[key] = index }
        }
        var added = 0
        var duplicateCount = 0
        for candidate in candidates {
            let key = Self.normalizedPath(candidate.url.path)
            if let index = indexByNormalizedPath[key] {
                // 如果文件已存在于总库，检查是否需要补充当前标签索引
                if let tag, !wallpapers[index].tags.contains(tag) {
                    wallpapers[index].tags.append(tag)
                    added += 1 // 视为成功"索引"到当前标签
                }
                duplicateCount += 1
                continue
            }
            indexByNormalizedPath[key] = wallpapers.count
            var newWallpaper = candidate.wallpaper
            if let tag {
                newWallpaper.tags.append(tag)
            }
            wallpapers.append(newWallpaper)
            added += 1
        }

        if added > 0 { save() }
        // 构建结果弹窗
        var lines: [String] = [
            "总选择：\(requestedCount) 个",
            "新增导入：\(added) 个"
        ]
        let skipped = requestedCount - added - duplicateCount - missingCount
        if duplicateCount > 0 { lines.append("\(duplicateCount) 个文件已存在于列表中") }
        if missingCount > 0  { lines.append("\(missingCount) 个文件不存在") }
        if skipped > 0       { lines.append("未处理：\(skipped) 个") }
        let alert = makeAppAlert(title: "导入结果", message: lines.joined(separator: "\n"))
        presentAppAlert(alert, in: window ?? appModalHostWindow())
    }

    private static func normalizedPath(_ path: String) -> String {
        URL(fileURLWithPath: path).resolvingSymlinksInPath().standardizedFileURL.path
    }

    func importFromPanel(presentingIn window: NSWindow? = nil) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowedContentTypes = Self.allowedUTTypes
        panel.title = "选择图片壁纸"
        if let window {
            panel.beginSheetModal(for: window) { [weak self] response in
                guard response == .OK else { return }
                self?.importImages(from: panel.urls, presentingIn: window)
            }
        } else {
            guard panel.runModal() == .OK else { return }
            importImages(from: panel.urls, presentingIn: nil)
        }
    }

    // MARK: - 删除

    /// 从总库移除（同时清除所有标签引用），删除前先找临近项作为新选中目标
    func remove(ids: Set<String>) {
        let nextID = resolveNextSelectionID(removingIDs: ids)
        wallpapers.removeAll { ids.contains($0.id) }
        selectedIDs.subtract(ids)
        selectedID = nextID
        if isMultiSelectMode { isMultiSelectMode = false }
        syncSelectedWallpaperInspectorIfNeeded()
        save()
    }

    /// 仅从指定标签中移除索引，不删除总库记录，完成后自动退出多选模式
    func removeFromSILTag(_ tag: String, ids: Set<String>) {
        // 标签页移除只是去掉索引，不影响总库，无需跳选中，直接清掉即可
        for i in wallpapers.indices where ids.contains(wallpapers[i].id) {
            wallpapers[i].tags.removeAll { $0 == tag }
        }
        clearSelectionState()
        save()
    }

    /// 删除前在当前排序列表里找到被删项的临近项（优先取后继，否则取前驱）
    private func resolveNextSelectionID(removingIDs: Set<String>) -> String? {
        guard !isMultiSelectMode, let currentID = selectedID,
              removingIDs.contains(currentID) else { return selectedID }
        let list = sortedWallpapers
        guard let idx = list.firstIndex(where: { $0.id == currentID }) else { return nil }
        let next = list[(idx + 1)...].first { !removingIDs.contains($0.id) }
        let prev = list[..<idx].last  { !removingIDs.contains($0.id) }
        return (next ?? prev)?.id
    }

    // MARK: - 信息

    func detailInfoText(for wallpaper: SILWallpaper, completion: @escaping (String) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let url = URL(fileURLWithPath: wallpaper.path)
            var lines: [String] = []
            lines.append("文件名：\(url.lastPathComponent)")
            lines.append("路径：\(wallpaper.path)")
            if let size = wallpaper.fileSize {
                let mb = Double(size) / 1_048_576
                lines.append(String(format: "大小：%.2f MB", mb))
            }
            if let src = CGImageSourceCreateWithURL(url as CFURL, nil),
               let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any] {
                let w = props[kCGImagePropertyPixelWidth] as? Int ?? 0
                let h = props[kCGImagePropertyPixelHeight] as? Int ?? 0
                if w > 0 && h > 0 { lines.append("尺寸：\(w) × \(h)") }
            }
            let fmt = DateFormatter()
            fmt.dateStyle = .medium; fmt.timeStyle = .short
            lines.append("添加时间：\(fmt.string(from: wallpaper.addedAt))")
            if wallpaper.lastUsed > Date.distantPast {
                lines.append("最近使用：\(fmt.string(from: wallpaper.lastUsed))")
            }
            DispatchQueue.main.async { completion(lines.joined(separator: "\n")) }
        }
    }
}
