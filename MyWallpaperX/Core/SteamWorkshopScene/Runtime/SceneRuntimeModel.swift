import Foundation

struct SceneRuntimeModel {
    let project: SceneProject
    let sceneDocument: SceneDocument
    let assetCatalog: SceneAssetCatalog
    let resourceReferences: SceneResourceReferenceIndex
    let resourceIndex: SceneResourceIndex
    let capabilityProfile: SceneCapabilityProfile
    let renderDescriptor: SceneRenderDescriptor
    let authoredEffectRenderPlans: [SceneAuthoredEffectRenderPlan]
    let runtimeInput: SceneRuntimeInput
    let diagnostics: SceneDiagnosticsReport

    /// Compatibility inputs remain two independent provenance-bearing facts.
    /// No unverified rule is applied merely by exposing this context.
    nonisolated var compatibilityContext: SceneCompatibilityContext {
        SceneCompatibilityContext(
            projectVersion: .init(
                value: project.declaredVersion,
                sourceKind: .projectJSON,
                sourceRelativePath: "project.json",
                fieldName: "version"
            ),
            sceneVersion: .init(
                value: sceneDocument.declaredVersion,
                sourceKind: .sceneEntry,
                sourceRelativePath: project.entryPath,
                fieldName: "version"
            )
        )
    }
}

struct SceneRuntimeModelBuilder {
    enum BuildError: LocalizedError {
        case missingProject
        case missingSceneDocument(String?)
        case missingAssetCatalog
        case missingResourceReferences
        case missingRenderDescriptor

        var errorDescription: String? {
            switch self {
            case .missingProject:
                return "无法构建 Scene runtime：项目未解析。"
            case let .missingSceneDocument(detail):
                if let detail, !detail.isEmpty {
                    return "无法构建 Scene runtime：\(detail)"
                }
                return "无法构建 Scene runtime：scene.json 未解析。"
            case .missingAssetCatalog:
                return "无法构建 Scene runtime：资产摘要未解析。"
            case .missingResourceReferences:
                return "无法构建 Scene runtime：资源引用索引未建立。"
            case .missingRenderDescriptor:
                return "无法构建 Scene runtime：renderer 输入描述未建立。"
            }
        }
    }

    func build(
        rootURL: URL,
        propertyOverrides: [String: SceneUserPropertyValue] = [:]
    ) throws -> SceneRuntimeModel {
        let diagnostics = SceneDiagnosticsBuilder().build(
            rootURL: rootURL,
            propertyOverrides: propertyOverrides
        )
        guard let project = diagnostics.project else {
            throw BuildError.missingProject
        }
        guard let sceneDocument = diagnostics.sceneDocument else {
            throw BuildError.missingSceneDocument(
                diagnostics.sceneDocumentLoadErrorDescription
            )
        }
        guard let assetCatalog = diagnostics.assetCatalog else {
            throw BuildError.missingAssetCatalog
        }
        guard let resourceReferences = diagnostics.resourceReferences else {
            throw BuildError.missingResourceReferences
        }
        let capabilityProfile = SceneCapabilityProfileBuilder().build(
            project: project,
            sceneDocument: sceneDocument,
            assetCatalog: assetCatalog,
            resourceReferences: resourceReferences,
            resourceIndex: diagnostics.resourceIndex
        )
        guard let renderDescriptor = diagnostics.renderDescriptor else {
            throw BuildError.missingRenderDescriptor
        }
        let compilation = ScenePropertyBindingCompiler().compile(
            report: sceneDocument.userPropertyResolution.bindingReport,
            catalog: project.userProperties
        )
        let runtimeInput = SceneRuntimeInput(
            renderDescriptor: renderDescriptor,
            propertyBindingProgram: compilation.program,
            effectivePropertyValues: project.userProperties.effectiveValues(
                overrides: propertyOverrides
            ),
            shaderContracts: assetCatalog.shaderContracts
        )

        return SceneRuntimeModel(
            project: project,
            sceneDocument: sceneDocument,
            assetCatalog: assetCatalog,
            resourceReferences: resourceReferences,
            resourceIndex: diagnostics.resourceIndex,
            capabilityProfile: capabilityProfile,
            renderDescriptor: runtimeInput.renderDescriptor,
            authoredEffectRenderPlans: runtimeInput.authoredEffectRenderPlans,
            runtimeInput: runtimeInput,
            diagnostics: diagnostics
        )
    }
}

final class ScenePlaybackController {
    private(set) var currentModel: SceneRuntimeModel?

    func prepare(model: SceneRuntimeModel) {
        currentModel = model
    }

    func stop() {
        currentModel = nil
    }
}

struct SceneRenderer {
    enum Backend: String {
        case metal
    }

    let backend: Backend = .metal
}

struct SceneInputModel {
    enum CursorEvent: String {
        case enter
        case move
        case leave
        case click
    }
}

struct SceneTimelineModel {
    let duration: TimeInterval?
}

struct SceneShaderModel {
    let shaderResources: [SceneResourceIndex.Resource]
    let shaderBlobResources: [SceneResourceIndex.Resource]
}
