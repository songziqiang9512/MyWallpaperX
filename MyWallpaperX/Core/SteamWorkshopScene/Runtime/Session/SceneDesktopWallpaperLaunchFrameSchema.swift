import Foundation

/// Launch-stable inputs shared by every Scene surface during frame updates.
///
/// The values in this schema describe the producers and consumers that may
/// participate in a frame. Launch-stable producers are prepared once;
/// authored layer definitions use a small revisioned cache because script
/// topology may publish a new target after a successful frame.
nonisolated final class SceneDesktopWallpaperLaunchFrameSchema: @unchecked Sendable {
    let dynamicLayerRuntime: SceneScriptDynamicLayerRuntime
    let sceneScriptStatefulTargets: Set<SceneDynamicTarget>
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
            case let .layer(layerID, _), let .text(layerID, _):
                result.insert(layerID)
            case .scene, .camera, .effectVisibility, .effectConstant,
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
        preparedDeviceResources: ScenePreparedDeviceResources,
        dynamicImageMaterialColorTargets: [String: SceneDynamicTarget],
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
        if let configuredCatalogSignature,
           configuredCatalogSignature == SceneScriptQuickJSDomain
               .catalogSignature(for: runtimeInput.renderDescriptor) {
            sceneScriptLayerCatalogToken = configuredCatalogSignature
        } else {
            sceneScriptLayerCatalogToken = nil
        }
        let dynamicLayerRuntime = SceneScriptDynamicLayerRuntime(
            descriptor: runtimeInput.renderDescriptor,
            authoredMutationLayerIDs: sceneScriptOwnerLayerIDs,
            dynamicImageTemplates: Dictionary(
                uniqueKeysWithValues: preparedDeviceResources.baseImages
                    .dynamicImageResources.map { key, resource in
                        (key, SceneScriptDynamicImageLayerTemplate(
                            modelPath: resource.modelPath,
                            renderSizeWH: resource.renderSizeWH,
                            materialColorTarget: dynamicImageMaterialColorTargets[key]
                        ))
                    }
            )
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
        )
        self.sceneScriptStatefulTargets = Set(
            propertyVectorScriptProgram.bindings.map(\.definition.target)
                + sceneScriptScalarProgram.bindings.map(\.target)
                + sceneScriptStringProgram.bindings.map(\.target)
        )
    }
}
