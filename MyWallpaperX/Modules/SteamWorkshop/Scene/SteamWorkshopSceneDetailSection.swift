import SwiftUI

struct SteamWorkshopSceneDetailSection: View {
    let record: SteamWorkshopDownloadRecord
    let report: SceneDiagnosticsReport
    let propertyContext: SteamWorkshopScenePropertyContext?
    let openPropertyEditor: () -> Void

    private var rows: [SteamWorkshopSceneDiagnosticsRow] {
        let capabilityProfile = report.capabilityProfile
        let renderDescriptor = report.renderDescriptor
        return [
            SteamWorkshopSceneDiagnosticsRow(label: "入口", value: report.project?.entryPath ?? "未解析"),
            SteamWorkshopSceneDiagnosticsRow(label: "资源数", value: "\(report.resourceIndex.resources.count)"),
            SteamWorkshopSceneDiagnosticsRow(label: "对象数", value: "\(report.sceneDocument?.objectCount ?? 0)"),
            SteamWorkshopSceneDiagnosticsRow(label: "effect", value: "\(report.sceneDocument?.effectCount ?? 0)"),
            SteamWorkshopSceneDiagnosticsRow(label: "模型", value: "\(report.assetCatalog?.models.count ?? 0)"),
            SteamWorkshopSceneDiagnosticsRow(label: "材质", value: "\(report.assetCatalog?.materials.count ?? 0)"),
            SteamWorkshopSceneDiagnosticsRow(label: "材质 pass", value: "\(report.assetCatalog?.materialPassCount ?? 0)"),
            SteamWorkshopSceneDiagnosticsRow(label: "shader 引用", value: "\(report.assetCatalog?.shaderReferences.count ?? 0)"),
            SteamWorkshopSceneDiagnosticsRow(label: "资源引用", value: "\(report.sceneDocument?.referencedResourcePaths.count ?? 0)"),
            SteamWorkshopSceneDiagnosticsRow(label: "引用命中", value: "\(report.resourceReferences?.resolvedCount ?? 0)"),
            SteamWorkshopSceneDiagnosticsRow(label: "内置引用", value: "\(report.resourceReferences?.builtInReferenceCount ?? 0)"),
            SteamWorkshopSceneDiagnosticsRow(label: "引用缺失", value: "\(report.resourceReferences?.missingReferences.count ?? 0)"),
            SteamWorkshopSceneDiagnosticsRow(
                label: report.project?.packageURL?.lastPathComponent ?? "Scene 资源包",
                value: record.scenePackageURL == nil ? "缺失" : "已找到"
            ),
            SteamWorkshopSceneDiagnosticsRow(label: "PKGV 索引", value: "\(report.packageReport?.packageIndex?.entries.count ?? 0)"),
            SteamWorkshopSceneDiagnosticsRow(label: "缓存解包", value: "\(report.packageReport?.discoveredPaths.count ?? 0)"),
            SteamWorkshopSceneDiagnosticsRow(label: "shader blob", value: "\(report.resourceIndex.count(kind: .shaderBlob))"),
            SteamWorkshopSceneDiagnosticsRow(label: "脚本", value: capabilityProfile?.hasScripts == true ? "有" : "无"),
            SteamWorkshopSceneDiagnosticsRow(label: "粒子", value: capabilityProfile?.hasParticles == true ? "有" : "无"),
            SteamWorkshopSceneDiagnosticsRow(label: "音频处理", value: capabilityProfile?.supportsAudioProcessing == true ? "声明支持" : "未声明"),
            SteamWorkshopSceneDiagnosticsRow(label: "阻塞能力", value: capabilityProfile?.firstStageRendererGaps.joined(separator: "、") ?? "未解析"),
            SteamWorkshopSceneDiagnosticsRow(label: "render layer", value: "\(renderDescriptor?.layers.count ?? 0)"),
            SteamWorkshopSceneDiagnosticsRow(label: "root layer", value: "\(renderDescriptor?.rootLayerIDs.count ?? 0)"),
            SteamWorkshopSceneDiagnosticsRow(label: "render order", value: renderDescriptor?.renderOrderPolicy ?? "未解析"),
            SteamWorkshopSceneDiagnosticsRow(label: "render pass", value: "\(renderDescriptor?.materialPasses.count ?? 0)"),
            SteamWorkshopSceneDiagnosticsRow(label: "effect pass", value: "\(report.sceneDocument?.objects.flatMap { $0.effects }.reduce(0) { $0 + $1.passes.count } ?? 0)"),
            SteamWorkshopSceneDiagnosticsRow(label: "内联脚本", value: "\(report.sceneDocument?.objects.filter(\.hasInlineScript).count ?? 0)")
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Divider()
                .overlay(Color.white.opacity(0.035))

            if propertyContext != nil {
                Button("属性调节", systemImage: "slider.horizontal.3", action: openPropertyEditor)
                    .buttonStyle(.bordered)
                    .help("在独立窗口中调节 Scene 属性")
            }

            Text("Scene 诊断")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)

            ForEach(rows) { row in
                SteamWorkshopInlineNotice(
                    icon: "square.stack.3d.up",
                    text: "\(row.label)：\(row.value)"
                )
            }

            ForEach(report.issues) { issue in
                SteamWorkshopInlineNotice(
                    icon: issue.severity == .blocking ? "exclamationmark.triangle.fill" : "info.circle",
                    text: issue.message
                )
            }
        }
        .padding(.horizontal, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
