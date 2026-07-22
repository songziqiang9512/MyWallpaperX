import Foundation

extension SteamWorkshopService {
    func sceneDiagnosticsReport(for record: SteamWorkshopDownloadRecord) -> SceneDiagnosticsReport? {
        guard record.contentType == .scene else { return nil }
        return SceneDiagnosticsBuilder().build(rootURL: record.folderURL)
    }

    func sceneDiagnosticsSummary(for record: SteamWorkshopDownloadRecord) -> String {
        guard let report = sceneDiagnosticsReport(for: record) else {
            return "当前记录不是 Scene 类型。"
        }

        let resources = report.resourceIndex.resources.count
        let packageEntries = report.packageReport?.packageIndex?.entries.count ?? 0
        let extractedEntries = report.packageReport?.discoveredPaths.count ?? 0
        let objectCount = report.sceneDocument?.objectCount ?? 0
        let effectCount = report.sceneDocument?.effectCount ?? 0
        let modelCount = report.assetCatalog?.models.count ?? 0
        let materialCount = report.assetCatalog?.materials.count ?? 0
        let resolvedReferences = report.resourceReferences?.resolvedCount ?? 0
        let builtInReferences = report.resourceReferences?.builtInReferenceCount ?? 0
        let missingReferences = report.resourceReferences?.missingReferences.count ?? 0
        let packageState = record.scenePackageURL.map { "已找到 \($0.lastPathComponent)" } ?? "缺少 Scene 资源包"
        return "Scene 资源 \(resources) 项 · 对象 \(objectCount) 个 · effect \(effectCount) 个 · model \(modelCount) 个 · material \(materialCount) 个 · 引用命中 \(resolvedReferences) 项 · 内置引用 \(builtInReferences) 项 · 引用缺失 \(missingReferences) 项 · PKGV 索引 \(packageEntries) 项 · 缓存解包 \(extractedEntries) 项 · \(packageState)"
    }
}
