import Foundation

struct SceneDiagnosticsReport {
    struct Issue: Identifiable {
        enum Severity: String {
            case info
            case warning
            case blocking
        }

        let id = UUID()
        let severity: Severity
        let message: String
    }

    let sourceFacts: SceneRuntimeSourceFacts
    let issues: [Issue]

    var project: SceneProject? { sourceFacts.project }
    var sceneDocument: SceneDocument? { sourceFacts.sceneDocument }
    var assetCatalog: SceneAssetCatalog? { sourceFacts.assetCatalog }
    var resourceReferences: SceneResourceReferenceIndex? {
        sourceFacts.resourceReferences
    }
    var resourceIndex: SceneResourceIndex { sourceFacts.resourceIndex }
    var packageReport: ScenePkgExtractionReport? { sourceFacts.packageReport }
    var resourceView: SceneResourceView { sourceFacts.resourceView }
    var sceneDocumentLoadErrorDescription: String? {
        sourceFacts.sceneDocumentLoadErrorDescription
    }
    var capabilityProfile: SceneCapabilityProfile? {
        sourceFacts.capabilityProfile
    }
    var renderDescriptor: SceneRenderDescriptor? {
        sourceFacts.renderDescriptor
    }

    var isLaunchableInCurrentBuild: Bool {
        false
    }
}

struct SceneDiagnosticsBuilder {
    func build(
        rootURL: URL,
        propertyOverrides: [String: SceneUserPropertyValue] = [:]
    ) -> SceneDiagnosticsReport {
        build(sourceFacts: SceneRuntimeSourceFactsBuilder().build(
            rootURL: rootURL,
            propertyOverrides: propertyOverrides
        ))
    }

    func build(
        sourceFacts: SceneRuntimeSourceFacts
    ) -> SceneDiagnosticsReport {
        let project = sourceFacts.project
        let resourceIndex = sourceFacts.resourceIndex
        let packageReport = sourceFacts.packageReport
        let sceneDocument = sourceFacts.sceneDocument
        let assetCatalog = sourceFacts.assetCatalog
        let resourceReferences = sourceFacts.resourceReferences
        let capabilityProfile = sourceFacts.capabilityProfile
        let renderDescriptor = sourceFacts.renderDescriptor
        let sceneDocumentLoadErrorDescription =
            sourceFacts.sceneDocumentLoadErrorDescription
        var issues: [SceneDiagnosticsReport.Issue] = []

        if project == nil {
            issues.append(.init(severity: .blocking, message: "无法按 Scene 项目读取 project.json。"))
        }

        if let packageURL = project?.packageURL {
            issues.append(.init(
                severity: .info,
                message: "已找到 \(packageURL.lastPathComponent)，正在使用受控缓存解包链路。"
            ))
        } else {
            issues.append(.init(severity: .blocking, message: "未找到 Scene 资源包。"))
        }

        let shaderBlobCount = resourceIndex.count(kind: .shaderBlob)
        if shaderBlobCount > 0 {
            issues.append(.init(severity: .warning, message: "发现 \(shaderBlobCount) 个 DirectX shader blob，Metal 转译尚未实现。"))
        }

        if project?.supportsAudioProcessing == true {
            issues.append(.init(severity: .info, message: "项目声明支持音频处理，第一阶段仅记录该能力。"))
        }

        if let packageReport,
           let blockingMessage = packageReport.blockingMessage {
            issues.append(.init(severity: .blocking, message: blockingMessage))
        } else if let packageReport {
            let magic = packageReport.packageIndex?.magic ?? "unknown"
            issues.append(.init(severity: .info, message: "已读取 Scene 资源包文件表（\(magic)），缓存解包 \(packageReport.discoveredPaths.count) 项。"))
        }

        if let sceneDocument {
            issues.append(.init(severity: .info, message: "已解析 scene.json：对象 \(sceneDocument.objectCount) 个，effect \(sceneDocument.effectCount) 个，资源引用 \(sceneDocument.referencedResourcePaths.count) 个。"))
        } else if project != nil {
            issues.append(.init(
                severity: .blocking,
                message: sceneDocumentLoadErrorDescription
                    ?? "scene.json 尚未解析成功。"
            ))
        }

        if let assetCatalog {
            issues.append(.init(severity: .info, message: "已解析资产：model \(assetCatalog.models.count) 个，material \(assetCatalog.materials.count) 个，effect definition \(assetCatalog.effectDefinitions.count) 个，material pass \(assetCatalog.materialPassCount) 个，shader 引用 \(assetCatalog.shaderReferences.count) 个。"))
            if !assetCatalog.effectDefinitionDiagnostics.isEmpty {
                issues.append(.init(
                    severity: .warning,
                    message: "Effect definition 有 \(assetCatalog.effectDefinitionDiagnostics.count) 项保真诊断，已保留在内存运行模型中。"
                ))
            }
        } else if project != nil {
            issues.append(.init(severity: .warning, message: "models/materials 资产摘要尚未解析成功。"))
        }

        if let resourceReferences {
            let summary = "scene.json 资源引用分类：索引命中 \(resourceReferences.resolvedCount) 个，"
                + "内置引用 \(resourceReferences.builtInReferenceCount) 个，"
                + "运行时命名引用 \(resourceReferences.runtimeProvidedReferenceCount) 个"
            if resourceReferences.missingReferences.isEmpty {
                issues.append(.init(severity: .info, message: "\(summary)，无缺失引用。"))
            } else {
                let preview = resourceReferences.missingReferences.prefix(3).joined(separator: "、")
                issues.append(.init(
                    severity: .warning,
                    message: "\(summary)，另有 \(resourceReferences.missingReferences.count) 个引用未命中当前索引：\(preview)"
                ))
            }
        }

        let capabilityGaps = capabilityProfile.firstStageRendererGaps
        if capabilityGaps.isEmpty {
            issues.append(.init(severity: .info, message: "当前样本未暴露第一阶段已知阻塞能力。"))
        } else {
            issues.append(.init(severity: .warning, message: "第一阶段仍缺少：\(capabilityGaps.joined(separator: "、"))"))
        }

        if let renderDescriptor {
            issues.append(.init(severity: .info, message: "已建立 renderer 输入描述：layer \(renderDescriptor.layers.count) 个，material pass \(renderDescriptor.materialPasses.count) 个。"))
        }

        return SceneDiagnosticsReport(
            sourceFacts: sourceFacts,
            issues: issues
        )
    }
}
