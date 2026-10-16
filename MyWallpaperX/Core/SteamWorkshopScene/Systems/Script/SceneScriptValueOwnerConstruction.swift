import Foundation

/// Immutable export metadata shared by ordinary creation and committed-child
/// adoption. Reading it never invokes an authored callback or resets a budget.
nonisolated struct SceneScriptValueOwnerExports {
    let handlesMediaThumbnail: Bool
    let handlesMediaPlayback: Bool
    let handlesMediaProperties: Bool
    let handlesMediaTimeline: Bool
    let handlesUserProperties: Bool
    let handlesInit: Bool
    let handlesUpdate: Bool
    let animationEventExport: UInt32
    let exportedCursorEvents: Set<SceneScriptCursorEventKind>
    let hasAudioRegistration: Bool

    var supportsPreparedTextClone: Bool {
        !hasAudioRegistration && !handlesMediaThumbnail && !handlesMediaPlayback
            && !handlesMediaProperties && !handlesMediaTimeline
            && exportedCursorEvents.isEmpty
    }

    static func read(owner: OpaquePointer) throws -> Self {
        var cursorEvents: Set<SceneScriptCursorEventKind> = []
        for event in SceneScriptCursorEventKind.allCases {
            if try SceneScriptOwnerExportBridge.contains(event.callbackName, owner: owner) {
                cursorEvents.insert(event)
            }
        }
        return try .init(
            handlesMediaThumbnail: SceneScriptOwnerExportBridge.contains("mediaThumbnailChanged", owner: owner),
            handlesMediaPlayback: SceneScriptOwnerExportBridge.contains("mediaPlaybackChanged", owner: owner),
            handlesMediaProperties: SceneScriptOwnerExportBridge.contains("mediaPropertiesChanged", owner: owner),
            handlesMediaTimeline: SceneScriptOwnerExportBridge.contains("mediaTimelineChanged", owner: owner),
            handlesUserProperties: SceneScriptOwnerExportBridge.contains("applyUserProperties", owner: owner),
            handlesInit: SceneScriptOwnerExportBridge.contains("init", owner: owner),
            handlesUpdate: SceneScriptOwnerExportBridge.contains("update", owner: owner),
            animationEventExport: mwx_scene_quickjs_owner_animation_event_export(owner),
            exportedCursorEvents: cursorEvents,
            hasAudioRegistration: SceneScriptAudioHost.hasRegistration(owner: owner)
        )
    }
}

extension SceneScriptValueOwner {
    convenience init(
        domain: SceneScriptQuickJSDomain,
        source: String,
        target: SceneDynamicTarget,
        valueType: SceneDynamicValueType = .vector3,
        sourceLayerID: Int? = nil,
        cameraOriginDepthRange: ClosedRange<Double>? = nil,
        effectNames: [String?],
        hasCurrentAnimation: Bool = false,
        puppetAnimationIdentity: ScenePuppetAnimationIdentity? = nil,
        dynamicImagePathsByAuthoredIdentity: [String: String] = [:],
        allowsStatefulLayerSideEffects: Bool = false,
        effectVisibilityGetterSeed: Bool? = nil,
        generation: UInt64,
        budget: SceneScriptScalarBudget,
        constructionWork: SceneScriptConstructionWorkBudget? = nil
    ) throws {
        guard !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              [.scalar, .bool, .vector2, .vector3, .string].contains(valueType),
              generation > 0 else { throw SceneScriptScalarRuntimeFailure.invalidSource }
        if valueType == .scalar, case let .text(_, field) = target, field != .pointSize {
            throw SceneScriptScalarRuntimeFailure.invalidArgument("invalid scalar text target")
        }
        // Discovery must not grant layer-side-effect permission to a value-only
        // Bool/effect/Puppet owner. Other value families retain their VM contract.
        var imagePaths = dynamicImagePathsByAuthoredIdentity
        let acceptsImageRequests: Bool = {
            if valueType != .bool { return true }
            guard puppetAnimationIdentity == nil, case .layer(_, .visibility) = target else { return false }
            return allowsStatefulLayerSideEffects || !imagePaths.isEmpty
        }()
        if acceptsImageRequests {
            for reference in SceneScriptDynamicImageReferenceAnalysis.references(
                in: source, availableModelPaths: domain.dynamicImageAvailableModelPaths
            ) ?? [] {
                imagePaths[reference.authoredPath.lowercased()] = reference.modelPath
            }
        }
        if let constructionWork, !constructionWork.consume() {
            throw constructionWork.failure
        }
        try domain.checkConstructionBoundary()
        var diagnostic = [CChar](repeating: 0, count: 512)
        var creationResult = MWX_SCENE_QUICKJS_INVALID_ARGUMENT
        let created = source.withCString {
            if valueType == .bool && (allowsStatefulLayerSideEffects
                || !dynamicImagePathsByAuthoredIdentity.isEmpty) {
                mwx_scene_quickjs_owner_create_effectful_bool_with_budget(
                    domain.handle, $0, source.utf8.count, generation,
                    budget.interruptBudget, &creationResult,
                    &diagnostic, diagnostic.count
                )
            } else if valueType == .bool {
                mwx_scene_quickjs_owner_create_value_only_with_budget(
                    domain.handle, $0, source.utf8.count, generation,
                    budget.interruptBudget, &creationResult,
                    &diagnostic, diagnostic.count
                )
            } else {
                (valueType == .string
                    ? mwx_scene_quickjs_owner_create_text_with_budget
                    : mwx_scene_quickjs_owner_create_with_budget)(
                    domain.handle, $0, source.utf8.count, generation,
                    budget.interruptBudget, &creationResult,
                    &diagnostic, diagnostic.count
                )
            }
        }
        do {
            try domain.checkConstructionBoundary()
        } catch {
            if let created { mwx_scene_quickjs_owner_destroy(created) }
            throw error
        }
        guard let created else {
            throw Self.failure(creationResult, diagnostic)
        }
        let layerID: Int
        let exports: SceneScriptValueOwnerExports
        do {
            guard sourceLayerID == nil || (target == .camera(.origin) && valueType == .vector3
                    && cameraOriginDepthRange != nil),
                  let targetLayerID = sourceLayerID ?? SceneScriptLayerMutationBridge.layerID(for: target) else {
                throw SceneScriptScalarRuntimeFailure.invalidArgument(
                    "SceneScript owner layer identity unavailable"
                )
            }
            layerID = targetLayerID
            let layerResult = mwx_scene_quickjs_owner_configure_layer_identity(
                created,
                Int64(layerID),
                &diagnostic,
                diagnostic.count
            )
            guard layerResult == MWX_SCENE_QUICKJS_OK else {
                throw Self.failure(layerResult, diagnostic)
            }
            try SceneScriptLayerMutationBridge.configureDynamicImageAliases(
                owner: created, paths: imagePaths)
            let scopeResult = mwx_scene_quickjs_owner_set_property_object_scope(
                created,
                (sourceLayerID != nil || SceneScriptLayerMutationBridge.propertyObjectIsLayer(target)) ? 1 : 0,
                &diagnostic,
                diagnostic.count
            )
            guard scopeResult == MWX_SCENE_QUICKJS_OK else {
                throw Self.failure(scopeResult, diagnostic)
            }
            try SceneScriptLayerMutationBridge.configureEffectVisibilityTarget(
                owner: created, target: target,
                // The getter's read default is the binding's authored seed,
                // not the definition's prepared snapshot seed.
                seedVisible: effectVisibilityGetterSeed ?? true
            )
            try SceneScriptEffectHandleBridge.configure(
                owner: created,
                effectNames: effectNames
            )
            try SceneScriptAnimationHandleBridge.configure(
                owner: created,
                hasCurrentAnimation: hasCurrentAnimation
            )
            if let puppetAnimationIdentity {
                guard valueType == .bool, allowsStatefulLayerSideEffects,
                      !hasCurrentAnimation, puppetAnimationIdentity.layerID == layerID,
                      let id = puppetAnimationIdentity.animationLayerID,
                      target == ScenePuppetAnimationPropertyTarget.visibility(layerID: layerID, animationLayerID: id) else {
                    throw SceneScriptScalarRuntimeFailure.invalidArgument("Puppet animation target identity mismatch")
                }
                try SceneScriptPuppetAnimationBridge.configure(owner: created, identity: puppetAnimationIdentity)
            }
            exports = try .read(owner: created)
            if valueType == .bool {
                let handlesDestroy = try SceneScriptOwnerExportBridge.contains(
                    "destroy", owner: created
                )
                let hasMediaHook = exports.handlesMediaThumbnail || exports.handlesMediaPlayback
                    || exports.handlesMediaProperties || exports.handlesMediaTimeline
                let hasCursorHook = !exports.exportedCursorEvents.isEmpty
                let hasEventHook = hasMediaHook || exports.handlesUserProperties
                    || hasCursorHook || (puppetAnimationIdentity != nil && exports.animationEventExport == 1)
                if exports.handlesInit || exports.handlesUpdate {
                    // A stateful owner's destroy hook joins the existing
                    // exactly-once teardown dispatch (fail-soft, journal
                    // discarded); value-less lanes keep the stricter shape.
                    guard allowsStatefulLayerSideEffects || !handlesDestroy,
                          (allowsStatefulLayerSideEffects || !hasMediaHook),
                          (allowsStatefulLayerSideEffects
                            || exports.exportedCursorEvents.isEmpty),
                          (dynamicImagePathsByAuthoredIdentity.isEmpty
                            && !allowsStatefulLayerSideEffects
                            ? !exports.hasAudioRegistration
                            : true) else {
                        throw SceneScriptScalarRuntimeFailure.invalidSource
                    }
                } else {
                    // Event callbacks share the stateful mutation journal and
                    // current audio snapshot. Registration does not require a
                    // per-frame update; idle owners keep the existing event/
                    // timer scheduling and borrowed cursor ownership.
                    guard hasEventHook,
                          !handlesDestroy,
                          allowsStatefulLayerSideEffects else {
                        throw SceneScriptScalarRuntimeFailure.invalidSource
                    }
                }
            }
        } catch {
            mwx_scene_quickjs_owner_destroy(created)
            throw error
        }
        self.init(
            domain: domain, handle: created, target: target, layerID: layerID,
            valueType: valueType, generation: generation, budget: budget,
            cameraOriginDepthRange: cameraOriginDepthRange,
            puppetAnimationIdentity: puppetAnimationIdentity,
            dynamicImagePathsByAuthoredIdentity: imagePaths,
            allowsStatefulLayerSideEffects: allowsStatefulLayerSideEffects,
            exports: exports
        )
        domain.dynamicImageRequestedModelPaths.formUnion(imagePaths.values)
    }

}
