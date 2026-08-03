import Foundation
import Metal

struct SceneDesktopWallpaperLaunchContext {
    let runtimeInput: SceneRuntimeInput
    let authoredEffectCatalog: SceneAuthoredEffectExecutionCatalog
    let resolvedMaterialCatalog: SceneResolvedMaterialRuntimeCatalog
    let materialAssetCatalog: SceneMaterialAssetTextureCatalog
    let pipelineRepository: SceneImageEffectPipelineRepository
    let spriteTextureLoader: SceneMultiImageSpriteTextureLoader
    let timelineProgram: SceneTimelineProgram
    let textScriptProgram: SceneTextScriptProgram
    let timeOfDayEffectScriptProgram: SceneTimeOfDayEffectScriptProgram
    let sceneScriptAudioBarsProgram: SceneScriptAudioBarsProgram
    let mediaThumbnailBindings: SceneMediaThumbnailBindingProgram
    var liveState: ScenePropertyLiveUpdateState
    let userPropertyTextureURLs: [String: URL]
    let cacheDirectory: URL
    let resourceView: SceneResourceView
    let logURL: URL?
    let recordID: String?

    var resolvedMaterialStartupReportLines: [String] {
        resolvedMaterialCatalog.reportLines + materialAssetCatalog.reportLines + [
            "resolved material system providers: schema=r3-system-provider-v1"
                + " demands=\(resolvedMaterialCatalog.systemProviderDemands.count)"
                + " missingState=unavailable"
                + " reason=snapshot-lifecycle-unproven"
        ]
    }

    func makeResolvedMaterialRuntime() -> SceneResolvedMaterialRuntimeBridge {
        .init(
            catalog: resolvedMaterialCatalog,
            assets: materialAssetCatalog
        )
    }

    func appendResolvedMaterialStartupReport() {
        guard let logURL,
              let existing = try? String(contentsOf: logURL, encoding: .utf8) else {
            return
        }
        let separator = existing.isEmpty || existing.hasSuffix("\n") ? "" : "\n"
        let lines = resolvedMaterialStartupReportLines
        try? (existing + separator + lines.joined(separator: "\n") + "\n")
            .write(to: logURL, atomically: true, encoding: .utf8)
    }
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
        let resolvedMaterialCatalog = SceneResolvedMaterialRuntimeCatalog(
            descriptor: runtimeInput.renderDescriptor,
            authoredPlans: runtimeInput.authoredEffectRenderPlans,
            shaderContracts: runtimeInput.shaderContracts
        )
        let timeOfDayEffectScriptProgram = SceneTimeOfDayEffectScriptProgram(
            bindings: authoredEffectCatalog.chainsByLayerID.keys.sorted().flatMap { layerID in
                authoredEffectCatalog.chainsByLayerID[layerID]?.stages.compactMap {
                    $0.blend?.dynamicMultiplyBinding
                } ?? []
            }
        )
        let currentMediaThumbnailBindings = SceneMediaThumbnailBindingCompiler.compile(
            descriptor: runtimeInput.renderDescriptor,
            scriptBindings: model.sceneDocument.scriptBindings
        )
        let mediaThumbnailBindings = SceneMediaThumbnailTransitionCompiler.compile(
            descriptor: runtimeInput.renderDescriptor,
            shaderContracts: runtimeInput.shaderContracts,
            currentProgram: currentMediaThumbnailBindings
        )
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw SceneDesktopWallpaperHostLaunchError.noSurface
        }
        let materialAssetCatalog = SceneMaterialAssetTextureCatalog(
            demands: resolvedMaterialCatalog.assetDemands,
            resourceView: model.diagnostics.resourceView,
            descriptor: runtimeInput.renderDescriptor,
            device: device
        )
        try activate(SceneDesktopWallpaperLaunchContext(
            runtimeInput: runtimeInput,
            authoredEffectCatalog: authoredEffectCatalog,
            resolvedMaterialCatalog: resolvedMaterialCatalog,
            materialAssetCatalog: materialAssetCatalog,
            pipelineRepository: SceneImageEffectPipelineRepository(device: device),
            spriteTextureLoader: SceneMultiImageSpriteTextureLoader(),
            timelineProgram: SceneTimelineTargetCompiler.compile(
                descriptor: runtimeInput.renderDescriptor
            ),
            textScriptProgram: SceneTextScriptCompiler.compile(
                descriptor: runtimeInput.renderDescriptor
            ),
            timeOfDayEffectScriptProgram: timeOfDayEffectScriptProgram,
            sceneScriptAudioBarsProgram: SceneScriptAudioBarsCompiler.compile(
                descriptor: runtimeInput.renderDescriptor,
                shaderContracts: runtimeInput.shaderContracts
            ),
            mediaThumbnailBindings: mediaThumbnailBindings,
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
