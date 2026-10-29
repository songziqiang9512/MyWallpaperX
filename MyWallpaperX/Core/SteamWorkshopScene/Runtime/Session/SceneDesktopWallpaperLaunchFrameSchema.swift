import Foundation

/// Launch-stable inputs shared by every Scene surface during frame updates.
///
/// The values in this schema describe the producers and consumers that may
/// participate in a frame. Launch-stable producers are prepared once;
/// authored layer definitions use a small revisioned cache because script
/// topology may publish a new target after a successful frame.
nonisolated final class SceneDesktopWallpaperLaunchFrameSchema: @unchecked Sendable {
    /// One launch join publishes identical resource eligibility to C, Swift
    /// topology and the material consumer. A texture alone is insufficient.
    static func preparedResourceCatalog(
        descriptor: SceneRenderDescriptor, baseImages: ScenePreparedBaseImageResources,
        models: [SceneAssetCatalog.ModelAsset], sourceMaterialModelPaths: Set<String>
    ) -> (templates: [String: SceneScriptPreparedResourceLayerTemplate],
          lightingProfiles: [String: SceneBaseMaterialLightingProfile]) {
        let autosizeByModel = Dictionary(uniqueKeysWithValues: models.map {
            ($0.relativePath.lowercased(), $0.autosize ?? false)
        })
        var templates: [String: SceneScriptPreparedResourceLayerTemplate] = [:]
        var profiles: [String: SceneBaseMaterialLightingProfile] = [:]
        for (key, resource) in baseImages.dynamicImageResources {
            let autosize = autosizeByModel[key] ?? false
            guard !autosize || resource.naturalSizeWH != nil,
                  resource.lightingProfile != nil || sourceMaterialModelPaths.contains(
                    SceneModelResourceIdentity(resource.modelPath).value) else { continue }
            templates[key] = .init(modelPath: resource.modelPath,
                renderSizeWH: resource.naturalSizeWH ?? resource.renderSizeWH, autosize: autosize,
                puppetMeshPath: resource.puppetMeshPath,
                imageMaterialRenderState: resource.imageMaterialRenderState,
                isVideo: { if case .video = resource.product { return true }; return false }())
            profiles[resource.modelPath] = resource.lightingProfile
        }
        // Empty clones carry no source effects, members, scripts or final texture.
        if (descriptor.camera.orthoHeight ?? 0) > 0 {
            for layer in descriptor.layers where layer.utilityLayer?.kind == .composition {
                guard let path = layer.imagePath else { continue }
                templates[path.lowercased()] = .init(
                    modelPath: path, renderSizeWH: [1, 1], kind: .composition)
            }
        }
        return (templates, profiles)
    }

    let dynamicLayerRuntime: SceneScriptDynamicLayerRuntime
    private(set) var sceneScriptStatefulTargets: Set<SceneDynamicTarget>
    let mediaFrameCoordinator: SceneScriptMediaFrameCoordinator
    /// Launch-frozen QuickJS layer catalog identity. The frame driver publishes
    /// the runtime descriptor every frame, so the schema verifies once at
    /// launch that it matches the catalog configured on the shared domain and
    /// then hands the domain's own signature back as an O(1) frame token.
    /// `nil` keeps the pre-existing per-frame revalidation for catalogs whose
    /// launch projections already differ.
    let sceneScriptLayerCatalogToken: String?
    private let launchDefinitions: [SceneDynamicTargetDefinition]
    private var cachedDefinitionRevision: UInt64?
    private var cachedDynamicDefinitions: [SceneDynamicTargetDefinition] = []
    private var cachedDefinitionIndexRevision: UInt64?
    private var cachedDefinitionIndex: SceneDynamicSnapshotDefinitionIndex?
    private var cachedTextTargetRevision: UInt64?
    private var cachedDynamicTextFieldsByLayerID:
        [Int: Set<SceneDynamicTextField>] = [:]
    private var cachedRuntimeFieldLayerRevision: UInt64?
    private var cachedRuntimeFieldLayerIDs: Set<Int> = []

    /// Only committed topology retirement withdraws a producer. Failed owners
    /// keep previous-current; pending and held frame snapshots remain intact.
    func retireStatefulTargets(_ targets: Set<SceneDynamicTarget>) {
        sceneScriptStatefulTargets.subtract(targets)
    }

    func registerStatefulTargets(_ targets: Set<SceneDynamicTarget>) {
        sceneScriptStatefulTargets.formUnion(targets)
    }

    /// Static producers are merged once at launch. Dynamic authored layer
    /// definitions are appended only when the layer runtime publishes a new
    /// topology revision after a successful frame commit.
    var dynamicDefinitions: [SceneDynamicTargetDefinition] {
        let revision = dynamicLayerRuntime.authoredDefinitionRevision
        if cachedDefinitionRevision == revision {
            return cachedDynamicDefinitions
        }
        var merged = launchDefinitions
        var existing = Set(merged.map(\.target))
        for definition in dynamicLayerRuntime.authoredLayerDefinitions
            where existing.insert(definition.target).inserted {
            merged.append(definition)
        }
        cachedDynamicDefinitions = merged
        cachedDefinitionRevision = revision
        return merged
    }

    /// The target index is rebuilt together with the authored definition
    /// projection and reused by the preliminary SceneScript snapshot and all
    /// surface transactions for the frame.
    var dynamicDefinitionIndex: SceneDynamicSnapshotDefinitionIndex {
        let revision = dynamicLayerRuntime.authoredDefinitionRevision
        if cachedDefinitionIndexRevision == revision,
           let cachedDefinitionIndex {
            return cachedDefinitionIndex
        }
        let index = SceneDynamicSnapshotResolver.prepare(
            definitions: dynamicDefinitions
        )
        cachedDefinitionIndexRevision = revision
        cachedDefinitionIndex = index
        return index
    }

    /// Text provider interest is a launch/prepared projection of the same
    /// definition owner used by the frame snapshot.  It is refreshed only
    /// when authored dynamic-layer topology publishes a new revision.
    var dynamicTextFieldsByLayerID: [Int: Set<SceneDynamicTextField>] {
        let revision = dynamicLayerRuntime.authoredDefinitionRevision
        if cachedTextTargetRevision == revision {
            return cachedDynamicTextFieldsByLayerID
        }
        cachedDynamicTextFieldsByLayerID = dynamicDefinitions.reduce(
            into: [Int: Set<SceneDynamicTextField>]()
        ) { result, definition in
            guard case let .text(layerID, field) = definition.target else {
                return
            }
            result[layerID, default: []].insert(field)
        }
        cachedTextTargetRevision = revision
        return cachedDynamicTextFieldsByLayerID
    }

    /// Only layers whose runtime fields may be authored by a dynamic
    /// definition need a fresh Swift/C payload each frame. Static layers are
    /// explicitly marked as reusing their committed C snapshot fields. The
    /// set is revision-scoped because SceneScript may publish a new dynamic
    /// target when a topology transaction commits.
    var sceneScriptRuntimeFieldLayerIDs: Set<Int> {
        let revision = dynamicLayerRuntime.authoredDefinitionRevision
        if cachedRuntimeFieldLayerRevision == revision {
            return cachedRuntimeFieldLayerIDs
        }
        cachedRuntimeFieldLayerIDs = dynamicDefinitions.reduce(
            into: Set<Int>()
        ) { result, definition in
            switch definition.target {
            case let .layer(layerID, _), let .text(layerID, _),
                 let .effectVisibility(layerID, _):
                result.insert(layerID)
            case .scene, .camera, .effectConstant,
                 .materialConstant, .particle, .scriptInstanceProperty:
                break
            }
        }
        cachedRuntimeFieldLayerRevision = revision
        return cachedRuntimeFieldLayerIDs
    }

    init(
        runtimeInput: SceneRuntimeInput,
        sharedLayerAlphaProgram: SceneSharedLayerAlphaProgram,
        propertyVectorScriptProgram: SceneScriptVectorProgram,
        sceneScriptFallbackDefinitions: [SceneDynamicTargetDefinition],
        sceneScriptScalarProgram: SceneScriptScalarProgram,
        sceneScriptStringProgram: SceneScriptStringProgram,
        sceneScriptOwnerLayerIDs: Set<Int>,
        preparedResourceLayerTemplates: [String: SceneScriptPreparedResourceLayerTemplate],
        timelineProgram: SceneTimelineProgram,
        textScriptProgram: SceneTextScriptProgram
    ) {
        mediaFrameCoordinator = .init(
            vectorProgram: propertyVectorScriptProgram,
            stringProgram: sceneScriptStringProgram,
            scalarProgram: sceneScriptScalarProgram
        )
        let configuredCatalogSignature = propertyVectorScriptProgram.domain?
            .layerCatalogSignature
        do {
            let expectedSignature = try SceneScriptQuickJSDomain
                .catalogSignature(for: runtimeInput.renderDescriptor)
            sceneScriptLayerCatalogToken = configuredCatalogSignature == expectedSignature
                ? configuredCatalogSignature : nil
        } catch {
            // A malformed authored configuration cannot authorize a frame catalog.
            sceneScriptLayerCatalogToken = nil
        }
        let templateFailures = sceneScriptStringProgram.configurePreparedTextTemplates(
            domain: propertyVectorScriptProgram.domain,
            descriptor: runtimeInput.renderDescriptor,
            propertyBindingProgram: runtimeInput.propertyBindingProgram
        )
        for (target, failure) in templateFailures {
#if DEBUG
            NSLog("MWX SceneScript VM: target=%@ preparation=text-template failure=%@ code=%@",
                  String(describing: target), String(describing: failure), failure.code)
#endif
        }
        let dynamicLayerRuntime = SceneScriptDynamicLayerRuntime(
            descriptor: runtimeInput.renderDescriptor,
            authoredMutationLayerIDs: sceneScriptOwnerLayerIDs,
            preparedResourceLayerTemplates: preparedResourceLayerTemplates,
            textTemplates: sceneScriptStringProgram.preparedTextTemplates,
            layerOrderProjection: { [domain = propertyVectorScriptProgram.domain] identities in
                guard let domain else { return identities.isEmpty ? .success(nil) : .failure(.staleOwner) }
                return domain.projectPendingLayerOrder(accepting: identities)
            }
        )
        self.dynamicLayerRuntime = dynamicLayerRuntime
        self.launchDefinitions = SceneDynamicDefinitionMerger.merge(
            propertyDefinitions: runtimeInput.propertyBindingProgram.definitions,
            timelineProgram: timelineProgram,
            textScriptProgram: textScriptProgram,
            additionalDefinitions: sharedLayerAlphaProgram.definitions
                + propertyVectorScriptProgram.definitions
                + sceneScriptFallbackDefinitions
                + sceneScriptScalarProgram.definitions
                + sceneScriptStringProgram.definitions
                + runtimeInput.scriptEffectVisibilityDefinitions
                + runtimeInput.default2DCameraDefinitions(
                    timelineTargets: Set(timelineProgram.bindings.map(\.target)))
        )
        self.sceneScriptStatefulTargets = Set(
            propertyVectorScriptProgram.bindings.map(\.definition.target)
                + sceneScriptScalarProgram.bindings.map(\.target)
                + sceneScriptStringProgram.bindings.map(\.target)
        )
    }
}
