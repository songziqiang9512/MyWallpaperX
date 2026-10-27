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
        countLimit: 180,
        // 大图库长会话时限制已解码位图驻留（预算总表见 ThumbnailCache.init 注释）
        totalCostLimit: 64 * 1024 * 1024,
        namespace: "staticimagelibrary",
        usesFailureCache: true
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

    init(path: String, reusingMetadata: SILWallpaper? = nil) {
        self.id = UUID().uuidString
        self.path = path
        self.title = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
        if let reusingMetadata {
            self.fileSize = reusingMetadata.fileSize
            self.pixelWidth = reusingMetadata.pixelWidth
            self.pixelHeight = reusingMetadata.pixelHeight
        } else {
            self.fileSize = (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? Int64)
            // Read dimensions without decoding pixels.
            if let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
               let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any] {
                self.pixelWidth  = props[kCGImagePropertyPixelWidth]  as? Int
                self.pixelHeight = props[kCGImagePropertyPixelHeight] as? Int
            } else {
                self.pixelWidth  = nil
                self.pixelHeight = nil
            }
        }
        self.tags = []
        self.lastUsed = Date.distantPast
        self.addedAt = Date()
    }
}

// MARK: - SILService

final class SILService: ObservableObject {

    static var startupMigrationRecoveryMessage: String?
    static var defersMissingFileCleanupForPersonalSettingsRecovery = false
    static let shared = SILService()
    let migrationRecoveryMessage: String?
    var allowsLibraryMutation: Bool { migrationRecoveryMessage == nil }

    private func admitLibraryMutation(in window: NSWindow? = nil) -> Bool {
        guard let migrationRecoveryMessage else { return true }
        let alert = makeAppAlert(title: "资料库需要恢复", message: migrationRecoveryMessage + "\n仍可浏览和播放，恢复资料库后再导入或整理。",
                                 style: .warning, buttons: ["知道了"])
        presentAppAlert(alert, in: window)
        return false
    }

    @Published var wallpapers: [SILWallpaper] = []
    private let persistenceURL: URL
    private let initialMissingFilesAlertRetryLimit = 5
    private var metadataLoadGeneration: UInt64 = 0
    nonisolated private struct MissingImageDimensions: Sendable {
        let id: String
        let path: String
        let pixelWidth: Int?
        let pixelHeight: Int?
    }

    /// 供外部（如重置功能）访问持久化文件路径
    var silPersistenceURL: URL { persistenceURL }

    private init() {
        migrationRecoveryMessage = Self.startupMigrationRecoveryMessage
        let appSupport = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent(Bundle.main.bundleIdentifier ?? "MyWallpaperX")
        try? FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
        self.persistenceURL = appSupport.appendingPathComponent("sil_wallpapers.json")
        load()
        reconcileMissingFilesOnLaunch()
    }

    // MARK: - 持久化

    func load() {
        invalidatePendingMetadataLoad()
        guard let data = try? Data(contentsOf: persistenceURL),
              let decoded = try? JSONDecoder().decode([SILWallpaper].self, from: data) else { return }
        wallpapers = decoded
        // 旧索引立即可见，缺失尺寸只在 utility 读 header，不阻塞网格展示。
        let missing = decoded.filter { $0.pixelWidth == nil || $0.pixelHeight == nil }.map {
            MissingImageDimensions(id: $0.id, path: $0.path, pixelWidth: $0.pixelWidth, pixelHeight: $0.pixelHeight)
        }
        guard !missing.isEmpty else { return }
        let generation = metadataLoadGeneration
        DispatchQueue.global(qos: .utility).async { [weak self] in
            var updates: [(request: MissingImageDimensions, width: Int?, height: Int?)] = []
            for request in missing {
                if let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: request.path) as CFURL, nil),
                   let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any] {
                    updates.append((request, props[kCGImagePropertyPixelWidth] as? Int,
                                    props[kCGImagePropertyPixelHeight] as? Int))
                }
            }
            guard !updates.isEmpty else { return }
            DispatchQueue.main.async { [weak self] in
                self?.applyLoadedImageDimensions(updates, generation: generation)
            }
        }
    }

    func invalidatePendingMetadataLoad() {
        metadataLoadGeneration &+= 1
    }

    private func applyLoadedImageDimensions(
        _ updates: [(request: MissingImageDimensions, width: Int?, height: Int?)], generation: UInt64
    ) {
        guard generation == metadataLoadGeneration else { return }
        var enriched = wallpapers
        var indicesByID: [String: [Int]] = [:]
        for index in enriched.indices { indicesByID[enriched[index].id, default: []].append(index) }
        var changed = false
        for update in updates {
            for index in indicesByID[update.request.id] ?? [] where enriched[index].path == update.request.path {
                if update.request.pixelWidth == nil, enriched[index].pixelWidth == nil, let width = update.width {
                    enriched[index].pixelWidth = width
                    changed = true
                }
                if update.request.pixelHeight == nil, enriched[index].pixelHeight == nil, let height = update.height {
                    enriched[index].pixelHeight = height
                    changed = true
                }
            }
        }
        if changed {
            wallpapers = enriched
            save()
        }
    }

    func save() {
        guard migrationRecoveryMessage == nil else { return }
        try? persistWallpaperMetadata(wallpapers)
    }

    /// Same JSON owner for normal saves and an acknowledged settings import.
    func persistWallpaperMetadata(_ values: [SILWallpaper], synchronize: Bool = false) throws {
        guard allowsLibraryMutation else {
            throw CocoaError(.fileWriteNoPermission, userInfo: [NSLocalizedDescriptionKey: migrationRecoveryMessage ?? "资料库需要恢复"])
        }
        let data = try JSONEncoder().encode(values)
        try data.write(to: persistenceURL, options: .atomic)
        guard synchronize else { return }
        let handle = try FileHandle(forWritingTo: persistenceURL)
        defer { try? handle.close() }
        try handle.synchronize()
    }

    private func reconcileMissingFilesOnLaunch() {
        guard migrationRecoveryMessage == nil, !Self.defersMissingFileCleanupForPersonalSettingsRecovery else { return }
        let fm = FileManager.default
        let removed = wallpapers.filter { !fm.fileExists(atPath: $0.path) }
        guard !removed.isEmpty else { return }

        let removedIDs = Set(removed.map(\.id))
        wallpapers.removeAll { removedIDs.contains($0.id) }
        save()
        scheduleInitialMissingFilesAlert(for: removed, attempt: 0)
    }

    func resumeMissingFileCleanupAfterSettingsRecovery() {
        guard Self.defersMissingFileCleanupForPersonalSettingsRecovery else { return }
        Self.defersMissingFileCleanupForPersonalSettingsRecovery = false
        reconcileMissingFilesOnLaunch()
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

    var currentActiveWallpaperPath: String? {
        guard let screen = NSScreen.main else { return nil }
        return NSWorkspace.shared.desktopImageURL(for: screen)?.path
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

    func importImages(from urls: [URL], presentingIn window: NSWindow? = nil,
                      presentsSummary: Bool = true, completion: ((WallpaperSourceImportResult) -> Void)? = nil) {
        guard admitLibraryMutation(in: window) else { return }
        let importEpoch = metadataLoadGeneration
        // 枚举目录、逐文件读元数据都在后台执行，主线程只做落库与 UI 刷新
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            var fileURLs: [URL] = []
            var rejected: [WallpaperSourceImportResult.Item] = []
            let fm = FileManager.default
            for url in urls {
                var isDir: ObjCBool = false
                if fm.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
                    let previousCount = fileURLs.count
                    if let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: nil) {
                        for case let fileURL as URL in enumerator where Self.isSupportedImage(fileURL) {
                            fileURLs.append(fileURL)
                        }
                    }
                    if previousCount == fileURLs.count {
                        rejected.append(.init(sourceURL: url, disposition: .failed, organizationItem: nil,
                                              failureMessage: "目录无法读取或没有支持的图片"))
                    }
                } else if Self.isSupportedImage(url) {
                    fileURLs.append(url)
                } else {
                    rejected.append(.init(sourceURL: url, disposition: .failed, organizationItem: nil, failureMessage: "不支持的图片格式"))
                }
            }
            let requestedCount = fileURLs.count
            var candidates: [(url: URL, wallpaper: SILWallpaper, available: Bool)] = []
            candidates.reserveCapacity(requestedCount)
            // Repeated raw paths share only this worker's first metadata;
            // each occurrence keeps its own identity and availability.
            var metadataByRawPath: [Data: SILWallpaper] = [:]
            for url in fileURLs {
                let path = url.path
                var isDirectory: ObjCBool = false
                if fm.fileExists(atPath: path, isDirectory: &isDirectory), !isDirectory.boolValue {
                    let key = Data(path.utf8)
                    let metadata = metadataByRawPath[key]
                    let wallpaper = SILWallpaper(path: path, reusingMetadata: metadata)
                    if case .none = metadata { metadataByRawPath[key] = wallpaper }
                    candidates.append((url, wallpaper, fm.isReadableFile(atPath: path)))
                } else {
                    rejected.append(.init(sourceURL: url, disposition: .failed, organizationItem: nil,
                                          failureMessage: isDirectory.boolValue ? "该路径是目录，不是图片文件" : "文件不存在"))
                }
            }
            let missingCount = requestedCount - candidates.count
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.finishImport(candidates: candidates, importEpoch: importEpoch,
                                   requestedCount: requestedCount,
                                   missingCount: missingCount,
                                   presentingIn: window,
                                   presentsSummary: presentsSummary, rejected: rejected, completion: completion)
            }
        }
    }

    /// Commit source metadata on the main thread; membership is a separate Store transaction.
    private func finishImport(
        candidates: [(url: URL, wallpaper: SILWallpaper, available: Bool)], importEpoch: UInt64,
        requestedCount: Int,
        missingCount: Int,
        presentingIn window: NSWindow?,
        presentsSummary: Bool, rejected: [WallpaperSourceImportResult.Item], completion: ((WallpaperSourceImportResult) -> Void)?
    ) {
        guard metadataLoadGeneration == importEpoch else { return }
        var staged = wallpapers
        var indexByNormalizedPath: [String: Int] = [:]
        for (index, wallpaper) in wallpapers.enumerated() {
            let key = Self.normalizedPath(wallpaper.path)
            if indexByNormalizedPath[key] == nil { indexByNormalizedPath[key] = index }
        }
        var added = 0
        var addedPaths = Set<String>()
        var duplicateCount = 0
        for candidate in candidates {
            let key = Self.normalizedPath(candidate.url.path)
            if indexByNormalizedPath[key] != nil {
                duplicateCount += 1
                continue
            }
            indexByNormalizedPath[key] = staged.count
            staged.append(candidate.wallpaper)
            addedPaths.insert(key)
            added += 1
        }

        var persistenceFailure: String?
        if completion != nil, !candidates.isEmpty {
            // An explicit organization/relocation command must not receive a
            // successful source receipt before this same JSON owner saves it.
            do {
                try persistWallpaperMetadata(staged, synchronize: true)
                if added > 0 { wallpapers = staged }
            } catch {
                // Atomic write may have succeeded before its durability ACK
                // failed. Keep this source owner's memory aligned with the
                // readable disk fact, but never grant organization success.
                if let data = try? Data(contentsOf: persistenceURL),
                   let saved = try? JSONDecoder().decode([SILWallpaper].self, from: data) {
                    wallpapers = saved
                }
                persistenceFailure = "图片资料库未获保存确认：" + error.localizedDescription
                added = 0
            }
        } else {
            if added > 0 {
                wallpapers = staged
                save()
            }
        }
        guard metadataLoadGeneration == importEpoch else { return }
        if presentsSummary {
            var lines: [String] = [
                "总选择：\(requestedCount) 个",
                "新增导入：\(added) 个"
            ]
            let skipped = requestedCount - added - duplicateCount - missingCount
            if duplicateCount > 0 { lines.append("\(duplicateCount) 个文件已存在于列表中") }
            if missingCount > 0  { lines.append("\(missingCount) 个文件不存在") }
            if skipped > 0       { lines.append("未处理：\(skipped) 个") }
            if let persistenceFailure { lines.append(persistenceFailure) }
            let alert = makeAppAlert(title: "导入结果", message: lines.joined(separator: "\n"))
            presentAppAlert(alert, in: window ?? appModalHostWindow())
            guard metadataLoadGeneration == importEpoch else { return }
        }
        if let completion {
            var reportedNew = Set<String>()
            let accepted = candidates.map { candidate -> WallpaperSourceImportResult.Item in
                if let persistenceFailure {
                    return .init(sourceURL: candidate.url, disposition: .failed, organizationItem: nil,
                                 failureMessage: persistenceFailure)
                }
                let key = Self.normalizedPath(candidate.url.path)
                guard let index = indexByNormalizedPath[key], wallpapers.indices.contains(index) else {
                    return .init(sourceURL: candidate.url, disposition: .failed, organizationItem: nil,
                                 failureMessage: "资料库内容已变化，未完成入库")
                }
                let item = wallpapers[index]
                let disposition: WallpaperSourceImportResult.Disposition = addedPaths.contains(key) && reportedNew.insert(key).inserted ? .added : .existing
                return .init(sourceURL: candidate.url, disposition: disposition,
                    organizationItem: .init(reference: .init(provider: .staticImageLibrary, sourceID: item.id),
                        locator: .init(path: item.path, titleHint: item.title, mediaKind: .image),
                        isPublishedLocally: true, isAvailable: candidate.available),
                    failureMessage: candidate.available ? nil : "图片已入库但无法读取，未加入列表")
            }
            completion(.init(items: accepted + rejected))
        }
    }

    private static func normalizedPath(_ path: String) -> String {
        URL(fileURLWithPath: path).resolvingSymlinksInPath().standardizedFileURL.path
    }

    // MARK: - 删除

    /// Delete only explicitly confirmed regular source files. Keeping source
    /// facts lets retained relationships become unavailable instead of vanish.
    func deleteSourceFiles(ids: [String], isInUse: @escaping (URL) -> Bool,
                           completion: @escaping (WallpaperSourceDeletionResult) -> Void) {
        let generation = metadataLoadGeneration
        var results: [WallpaperSourceDeletionResult.Item] = []
        var requests: [(WallpaperReference, WallpaperSourceFileDeletion.Prepared)] = []
        for id in Set(ids.map { Data($0.utf8) }) {
            guard let item = wallpapers.first(where: { Data($0.id.utf8) == id }) else { continue }
            let reference = WallpaperReference(provider: .staticImageLibrary, sourceID: item.id)
            let url = URL(fileURLWithPath: item.path).standardizedFileURL
            do {
                guard allowsLibraryMutation else { throw CocoaError(.fileWriteNoPermission) }
                guard !isInUse(url) else {
                    throw CocoaError(.fileWriteNoPermission, userInfo: [NSLocalizedDescriptionKey: "源图片正在播放或准备，请先停止播放后重试"])
                }
                requests.append((reference, try WallpaperSourceFileDeletion.prepare(url)))
            } catch {
                results.append(.init(reference: reference, sourceURL: url, succeeded: false, sourceFileDeleted: false,
                    failureMessage: error.localizedDescription))
            }
        }
        guard !requests.isEmpty else { completion(.init(items: results)); return }
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else { return }
            var results = results
            var outcomes: [Data: WallpaperSourceFileDeletion.Outcome] = [:]
            for (reference, request) in requests {
                let key = Data(request.url.path.utf8), prior = outcomes[key]
                let unlinked = DispatchQueue.main.sync {
                    guard self.metadataLoadGeneration == generation && self.allowsLibraryMutation
                        && self.wallpapers.contains(where: { $0.id.utf8.elementsEqual(reference.sourceID.utf8) && Self.normalizedPath($0.path) == Self.normalizedPath(request.url.path) })
                        && !isInUse(request.url) else {
                        return WallpaperSourceFileDeletion.Outcome(sourceFileDeleted: false,
                            failureMessage: "资料库或播放状态已变化，未删除源文件")
                    }
                    // The original playback admission is MainActor-isolated.
                    // Nothing can accept this source between this guard and unlink.
                    return prior ?? WallpaperSourceFileDeletion.unlinkPrepared(request)
                }
                let outcome = unlinked.succeeded && prior == nil
                    ? WallpaperSourceFileDeletion.synchronizeDirectory(after: request) : unlinked
                outcomes[key] = outcome
                results.append(.init(reference: reference, sourceURL: request.url, succeeded: outcome.succeeded,
                    sourceFileDeleted: outcome.sourceFileDeleted, failureMessage: outcome.failureMessage))
            }
            let report = WallpaperSourceDeletionResult(items: results)
            DispatchQueue.main.async { completion(report) }
        }
    }

}
