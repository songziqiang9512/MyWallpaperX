import Foundation
import Metal

struct SceneDesktopWallpaperLaunchContext {
    let runtimeInput: SceneRuntimeInput
    let authoredEffectCatalog: SceneAuthoredEffectExecutionCatalog
    let pipelineRepository: SceneImageEffectPipelineRepository
    let timelineProgram: SceneTimelineProgram
    var liveState: ScenePropertyLiveUpdateState
    let userPropertyTextureURLs: [String: URL]
    let cacheDirectory: URL
    let resourceView: SceneResourceView
    let logURL: URL?
    let recordID: String?
}

enum SceneDesktopWallpaperHostLaunchError: LocalizedError {
    case missingPackageCache
    case noSurface

    var errorDescription: String? {
        switch self {
        case .missingPackageCache:
            "Scene 资源缓存不可用。"
        case .noSurface:
            "Scene 宿主未能创建可播放表面。"
        }
    }
}

extension SceneDesktopWallpaperHost {
    @discardableResult
    func launch(
        rootURL: URL,
        propertyOverrides: [String: SceneUserPropertyValue] = [:],
        userPropertyTextureURLs: [String: URL] = [:],
        logURL: URL? = nil,
        recordID: String? = nil
    ) throws -> SceneRuntimeModel {
        let model = try SceneRuntimeModelBuilder().build(
            rootURL: rootURL,
            propertyOverrides: propertyOverrides
        )
        guard let cacheDirectory = model.diagnostics.packageReport?.outputURL else {
            throw SceneDesktopWallpaperHostLaunchError.missingPackageCache
        }
        let runtimeInput = model.runtimeInput
        let authoredEffectCatalog = SceneAuthoredEffectExecutionCatalog(
            descriptor: runtimeInput.renderDescriptor,
            authoredPlans: runtimeInput.authoredEffectRenderPlans,
            shaderContracts: runtimeInput.shaderContracts
        )
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw SceneDesktopWallpaperHostLaunchError.noSurface
        }
        try activate(SceneDesktopWallpaperLaunchContext(
            runtimeInput: runtimeInput,
            authoredEffectCatalog: authoredEffectCatalog,
            pipelineRepository: SceneImageEffectPipelineRepository(device: device),
            timelineProgram: SceneTimelineTargetCompiler.compile(
                descriptor: runtimeInput.renderDescriptor
            ),
            liveState: ScenePropertyLiveUpdateState(
                program: runtimeInput.propertyBindingProgram,
                effectiveValues: runtimeInput.effectivePropertyValues,
                activeConsumerTargets: Self.activeLiveConsumerTargets(
                    in: runtimeInput.renderDescriptor,
                    authoredEffectCatalog: authoredEffectCatalog
                )
            ),
            userPropertyTextureURLs: userPropertyTextureURLs,
            cacheDirectory: cacheDirectory,
            resourceView: model.diagnostics.resourceView,
            logURL: logURL,
            recordID: recordID
        ))
        return model
    }
}
