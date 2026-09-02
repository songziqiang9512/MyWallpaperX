import Foundation

struct SceneRuntimeModel {
    let project: SceneProject
    let sceneDocument: SceneDocument
    let assetCatalog: SceneAssetCatalog
    let resourceReferences: SceneResourceReferenceIndex
    let resourceIndex: SceneResourceIndex
    let packageReport: ScenePkgExtractionReport?
    let resourceView: SceneResourceView
    let capabilityProfile: SceneCapabilityProfile
    let authoredRenderDescriptor: SceneRenderDescriptor
    let renderDescriptor: SceneRenderDescriptor
    let sharedLayerAlphaProgram: SceneSharedLayerAlphaProgram
    let propertyVectorProjection: SceneScriptVectorCandidateCatalog
    let authoredEffectRenderPlans: [SceneAuthoredEffectRenderPlan]
    let runtimeInput: SceneRuntimeInput

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
        let sourceFacts = SceneRuntimeSourceFactsBuilder().build(
            rootURL: rootURL,
            propertyOverrides: propertyOverrides
        )
        guard let project = sourceFacts.project else {
            throw BuildError.missingProject
        }
        guard let sceneDocument = sourceFacts.sceneDocument else {
            throw BuildError.missingSceneDocument(
                sourceFacts.sceneDocumentLoadErrorDescription
            )
        }
        guard let assetCatalog = sourceFacts.assetCatalog else {
            throw BuildError.missingAssetCatalog
        }
        guard let resourceReferences = sourceFacts.resourceReferences else {
            throw BuildError.missingResourceReferences
        }
        let capabilityProfile = sourceFacts.capabilityProfile
        guard let renderDescriptor = sourceFacts.renderDescriptor else {
            throw BuildError.missingRenderDescriptor
        }
        let compilation = ScenePropertyBindingCompiler().compile(
            report: sceneDocument.userPropertyResolution.bindingReport,
            catalog: project.userProperties
        )
        guard let sharedLayerAlphaProgram =
                SceneSharedLayerAlphaProgramCompiler.compile(
                    descriptor: renderDescriptor,
                    scriptBindings: sceneDocument.scriptBindings,
                    scriptSourceEvidence: sceneDocument.scriptSourceEvidence
                ) else {
            throw BuildError.missingRenderDescriptor
        }
        let timelineTargets = Set(
            SceneTimelineTargetCompiler.compile(descriptor: renderDescriptor)
                .bindings.map(\.target)
        )
        let structuralPropertyVectorProjection = SceneScriptVectorProgram.project(
            descriptor: renderDescriptor,
            scriptBindings: sceneDocument.scriptBindings,
            timelineTargets: timelineTargets
        )
        let sharedAlphaProjectedDescriptor = SceneSharedLayerAlphaProjection.apply(
            program: sharedLayerAlphaProgram,
            to: renderDescriptor
        )
        let displayProjectedDescriptor = SceneIdentityDisplayScriptProjection.apply(
            to: sharedAlphaProjectedDescriptor,
            sourceEvidence: sceneDocument.scriptSourceEvidence
        )
        let mediaProjectedDescriptor = SceneInitialMediaEffectVisibilityProjection.apply(
            to: displayProjectedDescriptor,
            scriptBindings: sceneDocument.scriptBindings,
            sourceEvidence: sceneDocument.scriptSourceEvidence
        )
        let sharedAlphaTargets = Set(
            sharedLayerAlphaProgram.definitions.map(\.target)
        )
        let projectedScalarTargets = SceneScriptScalarProgram.projectedTargets(
            descriptor: renderDescriptor,
            scriptBindings: sceneDocument.scriptBindings,
            timelineTargets: timelineTargets
        ).subtracting(sharedAlphaTargets)
        let scalarProjectedDescriptor = SceneScriptScalarDisplayProjection.apply(
            admittedTargets: projectedScalarTargets,
            to: mediaProjectedDescriptor
        )
        let admittedParticleRateLayerIDs = Set(
            projectedScalarTargets.compactMap { target -> Int? in
                guard case let .particle(layerID, .rate) = target else { return nil }
                return layerID
            }
        )
        let particleProjectedDescriptor = SceneScriptParticleProjection.apply(
            admittedRateLayerIDs: admittedParticleRateLayerIDs,
            to: scalarProjectedDescriptor
        )
        let runtimeDescriptor = SceneScriptedLayerTransformProjection.apply(
            admittedSceneScriptScaleLayerIDs:
                structuralPropertyVectorProjection.admittedScaleLayerIDs,
            to: particleProjectedDescriptor
        )
        let visibleLayerIDs = SceneLayerVisibility.visibleLayerIDs(
            in: runtimeDescriptor
        )
        let typedVisibilityOwnerLayerIDs = Set(
            structuralPropertyVectorProjection.uniqueCandidates.compactMap {
                candidate -> Int? in
                guard case let .layer(layerID, .visibility) =
                        candidate.definition.target else { return nil }
                return layerID
            }
        )
        let hasVisibleStaticModelConsumer = runtimeDescriptor.layers.contains {
            $0.staticModelPath != nil && visibleLayerIDs.contains($0.id)
        }
        let sceneScriptColorConsumerLayerIDs: Set<Int> = Set(
            runtimeDescriptor.layers.compactMap { layer in
                let hasConsumer = layer.supportsDirectLayerColorConsumer
                    || (layer.contentKind == "text"
                        && layer.text != nil
                        && layer.textStyle != nil)
                    || (hasVisibleStaticModelConsumer
                        && (layer.spotLight != nil
                            || layer.directionalLight != nil))
                guard hasConsumer,
                      visibleLayerIDs.contains(layer.id)
                        || typedVisibilityOwnerLayerIDs.contains(layer.id)
                else { return nil }
                return layer.id
            }
        )
        let propertyVectorProjection = SceneScriptVectorProgram.project(
            descriptor: renderDescriptor,
            scriptBindings: sceneDocument.scriptBindings,
            timelineTargets: timelineTargets,
            admittedLayerColorConsumerIDs: sceneScriptColorConsumerLayerIDs,
            shaderContracts: assetCatalog.shaderContracts
        )
        let runtimeInput = SceneRuntimeInput(
            renderDescriptor: runtimeDescriptor,
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
            resourceIndex: sourceFacts.resourceIndex,
            packageReport: sourceFacts.packageReport,
            resourceView: sourceFacts.resourceView,
            capabilityProfile: capabilityProfile,
            authoredRenderDescriptor: renderDescriptor,
            renderDescriptor: runtimeInput.renderDescriptor,
            sharedLayerAlphaProgram: sharedLayerAlphaProgram,
            propertyVectorProjection: propertyVectorProjection,
            authoredEffectRenderPlans: runtimeInput.authoredEffectRenderPlans,
            runtimeInput: runtimeInput
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
