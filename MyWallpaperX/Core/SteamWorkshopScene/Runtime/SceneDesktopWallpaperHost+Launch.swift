import Foundation
import Metal

nonisolated struct SceneWallpaperLaunchState: Equatable, Sendable {
    enum Phase: String, Equatable, Sendable {
        case accepted
        case preparingModel
        case preparingPrograms
        case preparingResources
        case preparingSurfaces
        case launched
        case cancelled
        case failed
    }

    let requestID: UUID
    let recordID: String?
    let phase: Phase
    let message: String

    var isInProgress: Bool {
        switch phase {
        case .accepted, .preparingModel, .preparingPrograms,
             .preparingResources, .preparingSurfaces:
            true
        case .launched, .cancelled, .failed:
            false
        }
    }
}

extension Notification.Name {
    static let sceneWallpaperLaunchStateDidChange = Notification.Name(
        "SceneWallpaperLaunchStateDidChange"
    )
}

nonisolated final class SceneWallpaperLaunchCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    func cancel() {
        lock.lock()
        cancelled = true
        lock.unlock()
    }

    func check() throws {
        lock.lock()
        let isCancelled = cancelled
        lock.unlock()
        if isCancelled {
            throw SceneDesktopWallpaperHostLaunchError.cancelled
        }
    }
}

struct SceneDesktopWallpaperLaunchContext {
    let runtimeInput: SceneRuntimeInput
    let effectAdmissionCatalog: SceneEffectAdmissionCatalog
    let resolvedMaterialCatalog: SceneResolvedMaterialRuntimeCatalog
    let resolvedMaterialExecutionCapabilities:
        SceneResolvedMaterialExecutionCapabilityCatalog
    let materialAssetCatalog: SceneMaterialAssetTextureCatalog
    let pipelineRepository: SceneImageEffectPipelineRepository
    let spriteTextureLoader: SceneMultiImageSpriteTextureLoader
    let timelineProgram: SceneTimelineProgram
    let textScriptProgram: SceneTextScriptProgram
    let mediaPlaybackPlaceholderFadeProgram:
        SceneMediaPlaybackPlaceholderFadeProgram
    let mediaColorTransitionProgram: SceneMediaColorTransitionProgram
    let sharedLayerAlphaProgram: SceneSharedLayerAlphaProgram
    let launchOriginTransitionProgram: SceneLaunchOriginTransitionProgram
    let hoverOriginTransitionProgram: SceneHoverOriginTransitionProgram
    let audioScaledValueProgram: SceneAudioScaledValueProgram
    let propertyVectorScriptProgram: SceneScriptVectorProgram
    let sceneScriptScalarProgram: SceneScriptScalarProgram
    let mediaThumbnailBindings: SceneMediaThumbnailBindingProgram
    var liveState: ScenePropertyLiveUpdateState
    let userPropertyTextureURLs: [String: URL]
    let cacheDirectory: URL
    let resourceView: SceneResourceView
    let logURL: URL?
    let recordID: String?

    var resolvedMaterialStartupReportLines: [String] {
        resolvedMaterialCatalog.reportLines
            + resolvedMaterialExecutionCapabilities.reportLines
            + materialAssetCatalog.reportLines + [
            "scene script VM: schema=quickjs-ng-typed-v2"
                + " bindings=\(sceneScriptScalarProgram.bindings.count)"
                + " vec3Bindings=\(propertyVectorScriptProgram.bindings.count)"
                + " targets=\(sceneScriptScalarProgram.definitions.count)"
                + " route=generic-only fallback=previous-current",
            "resolved material system providers: schema=r3-system-provider-v1"
                + " demands=\(resolvedMaterialCatalog.systemProviderDemands.count)"
                + " missingState=unavailable"
                + " reason=snapshot-lifecycle-unproven",
            "scene media placeholder fade: schema=bounded-playback-fade-v1"
                + " bindings=\(mediaPlaybackPlaceholderFadeProgram.bindings.count)"
                + " input=typed-inbox liveProvider=unavailable initialMode=stopped",
            "scene media color transition: schema=bounded-thumbnail-palette-v2"
                + " bindings=\(mediaColorTransitionProgram.bindings.count)"
                + " input=typed-inbox liveProvider=unavailable",
            "scene shared layer alpha: schema=bounded-shared-alpha-v1"
                + " flags=\(sharedLayerAlphaProgram.initialFlags.keys.sorted())"
                + " bindings=\(sharedLayerAlphaProgram.bindings.count)"
                + " layerIDs=\(sharedLayerAlphaProgram.layerIDs)"
                + " interaction=unavailable",
            "scene launch origin transition: schema=bounded-shared-origin-v1"
                + " cohorts=\(launchOriginTransitionProgram.cohorts.count)"
                + " bindings=\(launchOriginTransitionProgram.bindings.count)"
                + " scalarBindings=\(launchOriginTransitionProgram.scalarBindings.count)"
                + " layerIDs=\(launchOriginTransitionProgram.layerIDs)"
                + " interaction=cursor-click",
            "scene hover origin transition: schema=bounded-hover-origin-v1"
                + " cohorts=\(hoverOriginTransitionProgram.cohorts.count)"
                + " owners=\(hoverOriginTransitionProgram.ownerLayerIDs)"
                + " bindings=\(hoverOriginTransitionProgram.bindings.count)"
                + " layerIDs=\(hoverOriginTransitionProgram.layerIDs)"
                + " interaction=cursor-enter-leave",
            "scene audio scaled value: schema=bounded-audio-scaled-value-v1"
                + " bindings=\(audioScaledValueProgram.bindings.count)"
                + " rejectedParticleLayerIDs="
                + "\(audioScaledValueProgram.rejectedParticleLayerIDs)"
                + " rejectedScaleLayerIDs="
                + "\(audioScaledValueProgram.rejectedScaleLayerIDs)"
                + " resolution=16",
            "scene property vector scripts: schema=quickjs-ng-vec3-v1"
                + " bindings=\(propertyVectorScriptProgram.bindings.count)"
                + " route=generic-only fallback=previous-current"
                + " scaleLayerIDs="
                + "\(Array(propertyVectorScriptProgram.admittedScaleLayerIDs).sorted())"
        ]
    }

    func makeResolvedMaterialRuntime() -> SceneResolvedMaterialRuntimeBridge {
        .init(
            catalog: resolvedMaterialCatalog,
            capabilities: resolvedMaterialExecutionCapabilities,
            assets: materialAssetCatalog,
            device: pipelineRepository.device
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
    case cancelled
    case missingPackageCache
    case conflictingBoundedSceneScriptTargets(String)
    case invalidBoundedSceneScriptProgramAt(String)
    case noSurface

    var errorDescription: String? {
        switch self {
        case .cancelled:
            "Scene 启动请求已取消。"
        case .missingPackageCache:
            "Scene 资源缓存不可用。"
        case .conflictingBoundedSceneScriptTargets(let details):
            "Scene 有界脚本目标存在冲突，已停止启动。\(details)"
        case .invalidBoundedSceneScriptProgramAt(let phase):
            "Scene 有界脚本目标在 \(phase) 无法形成，已停止启动。"
        case .noSurface:
            "Scene 宿主未能创建可播放表面。"
        }
    }
}

extension SceneDesktopWallpaperHost {
    struct PreparedLaunch {
        let model: SceneRuntimeModel
        let context: SceneDesktopWallpaperLaunchContext
    }

    func requestLaunch(
        rootURL: URL,
        propertyOverrides: [String: SceneUserPropertyValue] = [:],
        userPropertyTextureURLs: [String: URL] = [:],
        logURL: URL? = nil,
        recordID: String? = nil,
        completion: @escaping @MainActor (Result<SceneRuntimeModel, Error>) -> Void
    ) {
        launchCancellation?.cancel()
        nextLaunchRequestGeneration &+= 1
        nextSceneScriptGeneration &+= 1
        let requestGeneration = nextLaunchRequestGeneration
        let scriptGeneration = nextSceneScriptGeneration
        let requestID = UUID()
        let cancellation = SceneWallpaperLaunchCancellation()
        launchCancellation = cancellation
        publishLaunchState(.init(
            requestID: requestID,
            recordID: recordID,
            phase: .accepted,
            message: "已接受 Scene 壁纸请求"
        ))

        launchPreparationQueue.async { [weak self] in
            guard let self else { return }
            do {
                let prepared = try Self.prepareLaunch(
                    rootURL: rootURL,
                    propertyOverrides: propertyOverrides,
                    userPropertyTextureURLs: userPropertyTextureURLs,
                    logURL: logURL,
                    recordID: recordID,
                    sceneScriptGeneration: scriptGeneration,
                    cancellation: cancellation
                ) { [weak self] phase, message in
                    DispatchQueue.main.async {
                        guard let self,
                              self.nextLaunchRequestGeneration == requestGeneration else {
                            return
                        }
                        self.publishLaunchState(.init(
                            requestID: requestID,
                            recordID: recordID,
                            phase: phase,
                            message: message
                        ))
                    }
                }
                DispatchQueue.main.async { [weak self] in
                    guard let self,
                          self.nextLaunchRequestGeneration == requestGeneration else {
                        return
                    }
                    do {
                        try cancellation.check()
                        self.publishLaunchState(.init(
                            requestID: requestID,
                            recordID: recordID,
                            phase: .preparingSurfaces,
                            message: "正在准备显示器与 Scene 表面"
                        ))
                        try self.activate(prepared.context)
                        self.launchCancellation = nil
                        self.publishLaunchState(.init(
                            requestID: requestID,
                            recordID: recordID,
                            phase: .launched,
                            message: "Scene 已开始渲染"
                        ))
                        completion(.success(prepared.model))
                    } catch {
                        self.finishLaunchFailure(
                            error,
                            requestID: requestID,
                            recordID: recordID,
                            completion: completion
                        )
                    }
                }
            } catch {
                DispatchQueue.main.async { [weak self] in
                    guard let self,
                          self.nextLaunchRequestGeneration == requestGeneration else {
                        return
                    }
                    self.finishLaunchFailure(
                        error,
                        requestID: requestID,
                        recordID: recordID,
                        completion: completion
                    )
                }
            }
        }
    }

    func cancelPendingLaunch(recordID: String? = nil) {
        guard let state = launchState,
              state.isInProgress,
              recordID == nil || state.recordID == recordID else {
            return
        }
        launchCancellation?.cancel()
        launchCancellation = nil
        nextLaunchRequestGeneration &+= 1
        publishLaunchState(.init(
            requestID: state.requestID,
            recordID: state.recordID,
            phase: .cancelled,
            message: "已取消 Scene 壁纸准备"
        ))
    }

    static func isLaunchCancellation(_ error: Error) -> Bool {
        guard let launchError = error as? SceneDesktopWallpaperHostLaunchError else {
            return false
        }
        if case .cancelled = launchError {
            return true
        }
        return false
    }

    @discardableResult
    func launch(
        rootURL: URL,
        propertyOverrides: [String: SceneUserPropertyValue] = [:],
        userPropertyTextureURLs: [String: URL] = [:],
        logURL: URL? = nil,
        recordID: String? = nil
    ) throws -> SceneRuntimeModel {
        nextSceneScriptGeneration &+= 1
        let prepared = try Self.prepareLaunch(
            rootURL: rootURL,
            propertyOverrides: propertyOverrides,
            userPropertyTextureURLs: userPropertyTextureURLs,
            logURL: logURL,
            recordID: recordID,
            sceneScriptGeneration: nextSceneScriptGeneration,
            cancellation: nil,
            progress: nil
        )
        try activate(prepared.context)
        return prepared.model
    }

    private static func prepareLaunch(
        rootURL: URL,
        propertyOverrides: [String: SceneUserPropertyValue],
        userPropertyTextureURLs: [String: URL],
        logURL: URL?,
        recordID: String?,
        sceneScriptGeneration: UInt64,
        cancellation: SceneWallpaperLaunchCancellation?,
        progress: ((SceneWallpaperLaunchState.Phase, String) -> Void)?
    ) throws -> PreparedLaunch {
        try cancellation?.check()
        progress?(.preparingModel, "正在验证资源包并解析场景")
        let model = try SceneRuntimeModelBuilder().build(
            rootURL: rootURL,
            propertyOverrides: propertyOverrides,
            sceneScriptGeneration: sceneScriptGeneration
        )
        try cancellation?.check()
        progress?(.preparingPrograms, "正在准备材质、脚本与渲染计划")
        guard let cacheDirectory = model.diagnostics.packageReport?.outputURL else {
            throw SceneDesktopWallpaperHostLaunchError.missingPackageCache
        }
        let runtimeInput = model.runtimeInput
        let timelineProgram = SceneTimelineTargetCompiler.compile(
            descriptor: runtimeInput.renderDescriptor
        )
        let launchOriginTransitionProgram =
            SceneLaunchOriginTransitionProgramCompiler.compile(
                descriptor: runtimeInput.renderDescriptor,
                scriptBindings: model.sceneDocument.scriptBindings,
                scriptSourceEvidence: model.sceneDocument.scriptSourceEvidence
            )
        let launchOriginTransitionTargets = Set(
            launchOriginTransitionProgram.definitions.map(\.target)
        )
        let hoverOriginTransitionProgram =
            SceneHoverOriginTransitionProgramCompiler.compile(
                descriptor: runtimeInput.renderDescriptor,
                scriptBindings: model.sceneDocument.scriptBindings,
                scriptSourceEvidence: model.sceneDocument.scriptSourceEvidence
            )
        let hoverOriginTransitionTargets = Set(
            hoverOriginTransitionProgram.definitions.map(\.target)
        )
        let audioScaledValueTargets = Set(
            model.audioScaledValueProgram.definitions.map(\.target)
        )
        let propertyVectorScriptTargets = Set(
            model.propertyVectorScriptProgram.definitions.map(\.target)
        )
        let propertyBindingDefinitions =
            runtimeInput.propertyBindingProgram.definitions
        let propertyBindingTargets = Set(
            propertyBindingDefinitions.map(\.target)
        )
        let userPropertyProducers = Set(
            runtimeInput.propertyBindingProgram.instructions.map {
                SceneDynamicUserPropertyProducer(
                    propertyKey: $0.propertyKey,
                    target: $0.target,
                    valueType: $0.valueType
                )
            }
        )
        let timelineDefinitions = Set(
            timelineProgram.bindings.map(\.definition)
        )
        let timelineTargets = Set(timelineDefinitions.map(\.target))
        typealias VisibilityOwner =
            SceneResolvedMaterialExecutionCapabilityAdmission
                .DynamicEffectVisibilityOwner
        // User-property visibility stays live for typed consumers; otherwise
        // live-state rejects atomically and the service relaunches the Scene.
        // Admission only blocks frame-driven topology changes here.
        var frameDrivenEffectVisibilityOwners = Set<VisibilityOwner>()
        let initiallyInactiveMediaOwners =
            SceneInitialMediaEffectVisibilityProjection.initiallyInactiveOwners(
                scriptBindings: model.sceneDocument.scriptBindings,
                sourceEvidence: model.sceneDocument.scriptSourceEvidence
            )
        for binding in timelineProgram.bindings {
            guard case let .effectVisibility(layerID, effectIndex) =
                    binding.definition.target else { continue }
            frameDrivenEffectVisibilityOwners.insert(.init(
                layerID: layerID,
                effectIndex: effectIndex
            ))
        }
        for binding in model.sceneDocument.scriptBindings {
            guard binding.owner.kind == .effect,
                  binding.targetKey == "visible",
                  let layerID = binding.owner.objectID,
                  let effectIndex = binding.owner.effectIndex,
                  !initiallyInactiveMediaOwners.contains(.init(
                      layerID: layerID,
                      effectIndex: effectIndex
                  )) else { continue }
            frameDrivenEffectVisibilityOwners.insert(.init(
                layerID: layerID,
                effectIndex: effectIndex
            ))
        }
        let executablePropertyFallbackTargets =
            SceneEffectStageAuthoredFallbackOwnerPartition.executableTargets(
                definitions: propertyBindingDefinitions
            )
        guard let mediaPlaybackPlaceholderFadeCandidates =
                SceneMediaPlaybackPlaceholderFadeProgramCompiler.compile(
                    descriptor: runtimeInput.renderDescriptor,
                    scriptBindings: model.sceneDocument.scriptBindings
                ) else {
            throw SceneDesktopWallpaperHostLaunchError
                .invalidBoundedSceneScriptProgramAt("media-placeholder-candidates")
        }
        let mediaPlaybackPlaceholderFadeCandidateTargets = Set(
            mediaPlaybackPlaceholderFadeCandidates.bindings.map(\.definition.target)
        )
        guard let mediaColorTransitionCandidates =
                SceneMediaColorTransitionProgramCompiler.compile(
                    descriptor: runtimeInput.renderDescriptor,
                    scriptBindings: model.sceneDocument.scriptBindings
                ) else {
            throw SceneDesktopWallpaperHostLaunchError
                .invalidBoundedSceneScriptProgramAt("media-color-candidates")
        }
        let mediaColorTransitionCandidateTargets = Set(
            mediaColorTransitionCandidates.bindings.map(\.definition.target)
        )
        let boundedProducerTargets: [(String, Set<SceneDynamicTarget>, Int)] = [
            ("launch-origin", launchOriginTransitionTargets,
             launchOriginTransitionProgram.definitions.count),
            ("hover-origin", hoverOriginTransitionTargets,
             hoverOriginTransitionProgram.definitions.count),
            ("audio-scaled", audioScaledValueTargets,
             model.audioScaledValueProgram.definitions.count),
            ("property-vector", propertyVectorScriptTargets,
             model.propertyVectorScriptProgram.definitions.count),
            ("media-placeholder", mediaPlaybackPlaceholderFadeCandidateTargets,
             mediaPlaybackPlaceholderFadeCandidates.bindings.count),
            ("media-color", mediaColorTransitionCandidateTargets,
             mediaColorTransitionCandidates.bindings.count),
        ]
        var boundedSceneScriptTargets: Set<SceneDynamicTarget> = []
        var boundedProducerConflicts: [String] = []
        for (name, targets, definitionCount) in boundedProducerTargets {
            if targets.count != definitionCount {
                boundedProducerConflicts.append("\(name)/duplicate")
            }
            if !targets.isDisjoint(with: propertyBindingTargets) {
                boundedProducerConflicts.append("\(name)/property")
            }
            if !targets.isDisjoint(with: timelineTargets) {
                boundedProducerConflicts.append("\(name)/timeline")
            }
            if !targets.isDisjoint(with: boundedSceneScriptTargets) {
                boundedProducerConflicts.append("\(name)/bounded-peer")
            }
            boundedSceneScriptTargets.formUnion(targets)
        }
        guard boundedProducerConflicts.isEmpty else {
            throw SceneDesktopWallpaperHostLaunchError
                .conflictingBoundedSceneScriptTargets(
                    " phases=\(boundedProducerConflicts.joined(separator: ","))"
                )
        }
        let sceneScriptScalarProgram = SceneScriptScalarProgram.compile(
            domain: model.sceneScriptDomain,
            descriptor: runtimeInput.renderDescriptor,
            scriptBindings: model.sceneDocument.scriptBindings,
            excludedTargets: boundedSceneScriptTargets,
            generation: sceneScriptGeneration
        )
        let sceneScriptScalarTargets = Set(
            sceneScriptScalarProgram.definitions.map(\.target)
        )
        guard sceneScriptScalarTargets.count
                == sceneScriptScalarProgram.definitions.count,
              sceneScriptScalarTargets.isDisjoint(with: boundedSceneScriptTargets) else {
            throw SceneDesktopWallpaperHostLaunchError
                .invalidBoundedSceneScriptProgramAt("scalar-target-ownership")
        }
        let provenSceneScriptValueTargets = mediaPlaybackPlaceholderFadeCandidateTargets
            .union(mediaColorTransitionCandidateTargets)
            .union(launchOriginTransitionProgram.scalarBindings.map {
                $0.definition.target
            })
            .union(sceneScriptScalarTargets)
        let resolvedMaterialAdmissionCandidates =
            SceneResolvedMaterialExecutionCapabilityAdmission.compile(
                descriptor: runtimeInput.renderDescriptor,
                authoredPlans: runtimeInput.authoredEffectRenderPlans,
                dynamicEffectVisibilityOwners:
                    frameDrivenEffectVisibilityOwners,
                startupInactiveEffectVisibilityTargets:
                    runtimeInput.startupInactiveEffectVisibilityTargets,
                conditionSchemaEvidence:
                    SceneGraphConditionSchemaEvidenceCompiler.compile(
                        descriptor: runtimeInput.renderDescriptor,
                        authoredPlans: runtimeInput.authoredEffectRenderPlans,
                        shaderContracts: runtimeInput.shaderContracts
                    )
            )
        let resolvedMaterialCatalog = SceneResolvedMaterialRuntimeCatalog(
            descriptor: runtimeInput.renderDescriptor,
            admissionCandidates: resolvedMaterialAdmissionCandidates,
            shaderContracts: runtimeInput.shaderContracts,
            userPropertyProducers: userPropertyProducers,
            propertyDefinitions: propertyBindingDefinitions,
            timelineDefinitions: timelineDefinitions,
            provenSceneScriptValueTargets: provenSceneScriptValueTargets
        )
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw SceneDesktopWallpaperHostLaunchError.noSurface
        }
        try cancellation?.check()
        progress?(.preparingResources, "正在加载纹理并预检 Metal 资源")
        let materialAssetCatalog = SceneMaterialAssetTextureCatalog(
            demands: resolvedMaterialCatalog.assetDemands,
            resourceView: model.diagnostics.resourceView,
            descriptor: runtimeInput.renderDescriptor,
            device: device
        )
        let resolvedMaterialExecutionCapabilities =
            SceneResolvedMaterialExecutionCapabilityCatalog(
                admissionCandidates: resolvedMaterialAdmissionCandidates,
                materialCatalog: resolvedMaterialCatalog,
                dynamicProducers: .init(
                    userProperties: userPropertyProducers,
                    authoredFallbackTargets:
                        executablePropertyFallbackTargets,
                    timelineDefinitions: timelineDefinitions,
                    sceneScriptTargets: provenSceneScriptValueTargets
                ),
                assetFormatFacts: materialAssetCatalog.launchFormatFacts,
                assetStates: materialAssetCatalog.launchStates
            )
        let resolvedMaterialSubjects = resolvedMaterialExecutionCapabilities
            .runtimeDispositionOwnerships.flatMap(\.subjects)
        let verifiedXRayStockIdentityKeys =
            SceneXRayStockIdentityVerifier.verifiedStockIdentityEffectKeys(
                descriptor: runtimeInput.renderDescriptor,
                shaderContracts: runtimeInput.shaderContracts
            )
        let effectAdmissionCatalog = SceneEffectAdmissionCatalog(
            descriptor: runtimeInput.renderDescriptor,
            authoredPlans: runtimeInput.authoredEffectRenderPlans,
            resolvedMaterialSubjects: resolvedMaterialSubjects,
            startupInactiveEffectVisibilityTargets:
                runtimeInput.startupInactiveEffectVisibilityTargets,
            verifiedXRayStageKeys: verifiedXRayStockIdentityKeys
        )
        let sceneScriptConsumerTargets =
            resolvedMaterialExecutionCapabilities.sceneScriptConsumerTargets
        guard let mediaPlaybackPlaceholderFadeProgram =
                SceneMediaPlaybackPlaceholderFadeProgram.validated(
                    bindings: mediaPlaybackPlaceholderFadeCandidates.bindings.filter {
                        sceneScriptConsumerTargets.contains(
                            $0.definition.target
                        )
                    }
                ) else {
            throw SceneDesktopWallpaperHostLaunchError
                .invalidBoundedSceneScriptProgramAt("media-placeholder-consumers")
        }
        guard let mediaColorTransitionProgram =
                SceneMediaColorTransitionProgram.validated(
                    bindings: mediaColorTransitionCandidates.bindings.filter {
                        sceneScriptConsumerTargets.contains(
                            $0.definition.target
                        )
                    }
                ) else {
            throw SceneDesktopWallpaperHostLaunchError
                .invalidBoundedSceneScriptProgramAt("media-color-consumers")
        }
        let mediaThumbnailBindings = SceneMediaThumbnailBindingCompiler.compile(
            descriptor: runtimeInput.renderDescriptor,
            scriptBindings: model.sceneDocument.scriptBindings
        )
        let context = SceneDesktopWallpaperLaunchContext(
            runtimeInput: runtimeInput,
            effectAdmissionCatalog: effectAdmissionCatalog,
            resolvedMaterialCatalog: resolvedMaterialCatalog,
            resolvedMaterialExecutionCapabilities:
                resolvedMaterialExecutionCapabilities,
            materialAssetCatalog: materialAssetCatalog,
            pipelineRepository: SceneImageEffectPipelineRepository(device: device),
            spriteTextureLoader: SceneMultiImageSpriteTextureLoader(),
            timelineProgram: timelineProgram,
            textScriptProgram: SceneTextScriptCompiler.compile(
                descriptor: runtimeInput.renderDescriptor
            ),
            mediaPlaybackPlaceholderFadeProgram:
                mediaPlaybackPlaceholderFadeProgram,
            mediaColorTransitionProgram: mediaColorTransitionProgram,
            sharedLayerAlphaProgram: model.sharedLayerAlphaProgram,
            launchOriginTransitionProgram: launchOriginTransitionProgram,
            hoverOriginTransitionProgram: hoverOriginTransitionProgram,
            audioScaledValueProgram: model.audioScaledValueProgram,
            propertyVectorScriptProgram: model.propertyVectorScriptProgram,
            sceneScriptScalarProgram: sceneScriptScalarProgram,
            mediaThumbnailBindings: mediaThumbnailBindings,
            liveState: ScenePropertyLiveUpdateState(
                program: runtimeInput.propertyBindingProgram,
                effectiveValues: runtimeInput.effectivePropertyValues,
                activeConsumerTargets: Self.activeLiveConsumerTargets(
                    in: runtimeInput.renderDescriptor,
                    resolvedMaterialExecutionCapabilities:
                        resolvedMaterialExecutionCapabilities
                )
            ),
            userPropertyTextureURLs: userPropertyTextureURLs,
            cacheDirectory: cacheDirectory,
            resourceView: model.diagnostics.resourceView,
            logURL: logURL,
            recordID: recordID
        )
        try cancellation?.check()
        return PreparedLaunch(model: model, context: context)
    }

    private func publishLaunchState(_ state: SceneWallpaperLaunchState) {
        launchState = state
        NSLog(
            "MWX SCENE STARTUP: request=%@ record=%@ phase=%@ message=%@",
            state.requestID.uuidString,
            state.recordID ?? "-",
            state.phase.rawValue,
            state.message
        )
        NotificationCenter.default.post(
            name: .sceneWallpaperLaunchStateDidChange,
            object: state
        )
    }

    private func finishLaunchFailure(
        _ error: Error,
        requestID: UUID,
        recordID: String?,
        completion: @MainActor (Result<SceneRuntimeModel, Error>) -> Void
    ) {
        launchCancellation = nil
        let cancelled = Self.isLaunchCancellation(error)
        publishLaunchState(.init(
            requestID: requestID,
            recordID: recordID,
            phase: cancelled ? .cancelled : .failed,
            message: cancelled ? "已取消 Scene 壁纸准备" : "Scene 壁纸准备失败"
        ))
        completion(.failure(error))
    }

}
