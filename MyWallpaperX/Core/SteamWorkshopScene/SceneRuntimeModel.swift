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
    let interpretationFile: SceneInterpretationFile
    let diagnostics: SceneDiagnosticsReport
}

struct SceneRuntimeModelBuilder {
    enum BuildError: LocalizedError {
        case missingProject
        case missingSceneDocument
        case missingAssetCatalog
        case missingResourceReferences
        case missingRenderDescriptor
        case interpretationEntryMismatch(String)

        var errorDescription: String? {
            switch self {
            case .missingProject:
                return "无法构建 Scene runtime：项目未解析。"
            case .missingSceneDocument:
                return "无法构建 Scene runtime：scene.json 未解析。"
            case .missingAssetCatalog:
                return "无法构建 Scene runtime：资产摘要未解析。"
            case .missingResourceReferences:
                return "无法构建 Scene runtime：资源引用索引未建立。"
            case .missingRenderDescriptor:
                return "无法构建 Scene runtime：renderer 输入描述未建立。"
            case .interpretationEntryMismatch(let entryPath):
                return "无法构建 Scene runtime：派生解释文件入口不匹配：\(entryPath)"
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
            throw BuildError.missingSceneDocument
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
        let rendererInput = try loadRendererInput(
            project: project,
            sceneDocument: sceneDocument,
            propertyOverrides: propertyOverrides,
            diagnostics: diagnostics
        )

        return SceneRuntimeModel(
            project: project,
            sceneDocument: sceneDocument,
            assetCatalog: assetCatalog,
            resourceReferences: resourceReferences,
            resourceIndex: diagnostics.resourceIndex,
            capabilityProfile: capabilityProfile,
            renderDescriptor: rendererInput.renderDescriptor,
            authoredEffectRenderPlans: rendererInput.authoredEffectRenderPlans,
            interpretationFile: rendererInput,
            diagnostics: diagnostics
        )
    }

    private func loadRendererInput(
        project: SceneProject,
        sceneDocument: SceneDocument,
        propertyOverrides: [String: SceneUserPropertyValue],
        diagnostics: SceneDiagnosticsReport
    ) throws -> SceneInterpretationFile {
        if let interpretationFileURL = diagnostics.interpretationFileURL {
            let file = try SceneInterpretationFileReader().read(from: interpretationFileURL)
            guard file.sourceEntryPath == project.entryPath else {
                throw BuildError.interpretationEntryMismatch(file.sourceEntryPath)
            }
            return file
        }

        guard let renderDescriptor = diagnostics.renderDescriptor else {
            throw BuildError.missingRenderDescriptor
        }
        let compilation = ScenePropertyBindingCompiler().compile(
            report: sceneDocument.userPropertyResolution.bindingReport,
            catalog: project.userProperties
        )
        return SceneInterpretationFileWriter().make(
            renderDescriptor: renderDescriptor,
            propertyBindingProgram: compilation.program,
            effectivePropertyValues: project.userProperties.effectiveValues(
                overrides: propertyOverrides
            )
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
