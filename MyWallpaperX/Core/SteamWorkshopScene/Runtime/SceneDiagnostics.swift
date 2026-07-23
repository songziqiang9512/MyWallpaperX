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

    let project: SceneProject?
    let sceneDocument: SceneDocument?
    let assetCatalog: SceneAssetCatalog?
    let resourceReferences: SceneResourceReferenceIndex?
    let resourceIndex: SceneResourceIndex
    let packageReport: ScenePkgExtractionReport?
    let issues: [Issue]
    let capabilityProfile: SceneCapabilityProfile?
    let renderDescriptor: SceneRenderDescriptor?
    let interpretationFileURL: URL?
    let interpretationFileError: String?

    var isLaunchableInCurrentBuild: Bool {
        false
    }
}

struct SceneDiagnosticsBuilder {
    func build(
        rootURL: URL,
        propertyOverrides: [String: SceneUserPropertyValue] = [:]
    ) -> SceneDiagnosticsReport {
        let project = try? SceneProjectLoader().load(from: rootURL)
        let resourceIndex = SceneResourceIndexBuilder().build(rootURL: rootURL)
        let packageReport: ScenePkgExtractionReport? = {
            guard let packageURL = project?.packageURL else { return nil }
            return try? ScenePkgExtractor(toolURL: nil).extract(
                packageURL: packageURL,
                outputURL: rootURL.appendingPathComponent(".scene-extracted", isDirectory: true)
            )
        }()
        let sceneDocument = project.flatMap {
            try? SceneDocumentLoader().load(
                project: $0,
                packageReport: packageReport,
                propertyOverrides: propertyOverrides
            )
        }
        let assetCatalog = project.flatMap {
            try? SceneAssetCatalogLoader().load(project: $0, packageReport: packageReport)
        }
        let resourceReferences = sceneDocument.map {
            SceneResourceReferenceIndexBuilder().build(
                document: $0,
                packageReport: packageReport,
                resourceIndex: resourceIndex
            )
        }
        let capabilityProfile = SceneCapabilityProfileBuilder().build(
            project: project,
            sceneDocument: sceneDocument,
            assetCatalog: assetCatalog,
            resourceReferences: resourceReferences,
            resourceIndex: resourceIndex
        )
        let renderDescriptor: SceneRenderDescriptor? = {
            guard let project,
                  let sceneDocument,
                  let assetCatalog,
                  let resourceReferences else {
                return nil
            }

            return SceneRenderDescriptorBuilder().build(
                project: project,
                sceneDocument: sceneDocument,
                assetCatalog: assetCatalog,
                resourceReferences: resourceReferences,
                capabilityProfile: capabilityProfile
            )
        }()
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
            issues.append(.init(severity: .blocking, message: "scene.json 尚未解析成功。"))
        }

        if let assetCatalog {
            issues.append(.init(severity: .info, message: "已解析资产：model \(assetCatalog.models.count) 个，material \(assetCatalog.materials.count) 个，effect definition \(assetCatalog.effectDefinitions.count) 个，material pass \(assetCatalog.materialPassCount) 个，shader 引用 \(assetCatalog.shaderReferences.count) 个。"))
            if !assetCatalog.effectDefinitionDiagnostics.isEmpty {
                issues.append(.init(
                    severity: .warning,
                    message: "Effect definition 有 \(assetCatalog.effectDefinitionDiagnostics.count) 项保真诊断，已写入派生解释文件。"
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
        let interpretationFileResult = Self.writeInterpretationFileIfPossible(
            project: project,
            sceneDocument: sceneDocument,
            assetCatalog: assetCatalog,
            renderDescriptor: renderDescriptor,
            propertyOverrides: propertyOverrides,
            outputDirectory: packageReport?.outputURL
        )
        let interpretationFileURL = interpretationFileResult.url
        if let interpretationFileURL {
            issues.append(.init(severity: .info, message: "已生成并验证 Scene 派生解释文件：\(interpretationFileURL.lastPathComponent)。"))
        } else if let error = interpretationFileResult.error {
            issues.append(.init(severity: .warning, message: "Scene 派生解释文件生成失败：\(error)"))
        }

        return SceneDiagnosticsReport(
            project: project,
            sceneDocument: sceneDocument,
            assetCatalog: assetCatalog,
            resourceReferences: resourceReferences,
            resourceIndex: resourceIndex,
            packageReport: packageReport,
            issues: issues,
            capabilityProfile: capabilityProfile,
            renderDescriptor: renderDescriptor,
            interpretationFileURL: interpretationFileURL,
            interpretationFileError: interpretationFileResult.error
        )
    }

    // Derived renderer state belongs to the package cache. The Workshop sample
    // remains read-only, and rebuilding the package cache regenerates this file.
    private static func writeInterpretationFileIfPossible(
        project: SceneProject?,
        sceneDocument: SceneDocument?,
        assetCatalog: SceneAssetCatalog?,
        renderDescriptor: SceneRenderDescriptor?,
        propertyOverrides: [String: SceneUserPropertyValue],
        outputDirectory: URL?
    ) -> (url: URL?, error: String?) {
        guard let project, let sceneDocument, let assetCatalog, let renderDescriptor else {
            return (nil, nil)
        }
        guard let outputDirectory else {
            return (nil, "Scene 缓存目录不可用，无法生成派生解释文件。")
        }
        do {
            let compilation = ScenePropertyBindingCompiler().compile(
                report: sceneDocument.userPropertyResolution.bindingReport,
                catalog: project.userProperties
            )
            let url = try SceneInterpretationFileWriter().write(
                renderDescriptor: renderDescriptor,
                propertyBindingProgram: compilation.program,
                effectivePropertyValues: project.userProperties.effectiveValues(
                    overrides: propertyOverrides
                ),
                shaderContracts: assetCatalog.shaderContracts,
                outputDirectory: outputDirectory
            )
            let file = try SceneInterpretationFileReader().read(from: url)
            guard file.sourceEntryPath == renderDescriptor.entryPath else {
                return (nil, "派生解释文件入口不匹配：\(file.sourceEntryPath)")
            }
            return (url, nil)
        } catch {
            return (nil, error.localizedDescription)
        }
    }
}
