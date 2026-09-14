import Foundation

extension SceneDesktopWallpaperLaunchContext {
    var resolvedMaterialStartupReportLines: [String] {
        resolvedMaterialCatalog.reportLines
            + resolvedMaterialExecutionCapabilities.reportLines
            + materialAssetCatalog.reportLines + [
            "scene script VM: schema=quickjs-ng-typed-v2"
                + " bindings=\(sceneScriptScalarProgram.bindings.count)"
                + " vectorBindings=\(propertyVectorScriptProgram.bindings.count)"
                + " stringBindings=\(sceneScriptStringProgram.bindings.count)"
                + " targets=\(sceneScriptTargetCount)"
                + " route=generic-only fallback=current-frame-lower-priority",
            "resolved material system providers: schema=r3-system-provider-v1"
                + " demands=\(resolvedMaterialCatalog.systemProviderDemands.count)"
                + " missingState=unavailable"
                + " reason=snapshot-lifecycle-unproven",
            "scene media thumbnail colors: schema=quickjs-ng-thumbnail-colors-v1"
                + " bindings=\(propertyVectorScriptProgram.mediaThumbnailTargets.count)"
                + " activeBindings=\(propertyVectorScriptProgram.mediaThumbnailTargets.intersection(propertyVectorMediaTargets).count)"
                + " route=\(sceneScriptVectorMediaRoute.rawValue)"
                + " fallback=current-frame-lower-priority"
                + " reason=\(sceneScriptVectorMediaRoute.reportReason)"
                + " profile=scenescript-vector-media-thumbnail"
                + " input=typed-inbox liveProvider=unavailable"
                + " targets=\(mediaThumbnailTargetNames)",
            "scene media events: schema=quickjs-ng-media-events-v1"
                + " bindings=\(propertyVectorMediaTargets.count)"
                + " activeBindings=\(propertyVectorScriptProgram.mediaOwnerTargets.intersection(propertyVectorMediaTargets).count)"
                + " route=\(sceneScriptVectorMediaRoute.rawValue)"
                + " fallback=current-frame-lower-priority"
                + " reason=\(sceneScriptVectorMediaRoute.reportReason)"
                + " profile=scenescript-vector-media-events"
                + " input=typed-inbox liveProvider=unavailable"
                + " targets=\(mediaOwnerTargetNames)",
            "scene shared layer alpha: schema=bounded-shared-alpha-v1"
                + " flags=\(sharedLayerAlphaProgram.initialFlags.keys.sorted())"
                + " bindings=\(sharedLayerAlphaProgram.bindings.count)"
                + " layerIDs=\(sharedLayerAlphaProgram.layerIDs)"
                + " interaction=unavailable",
            "scene cursor events: schema=quickjs-ng-cursor-v1"
                + " owners=\(sceneScriptCursorProgram.ownerCount)"
                + " layerIDs=\(sceneScriptCursorProgram.ownerLayerIDs.sorted())"
                + " events=cursorEnter,cursorLeave,cursorDown,cursorMove,cursorUp,cursorClick"
                + " route=generic-only",
            "scene property vector scripts: schema=quickjs-ng-vec3-v1"
                + " bindings=\(propertyVectorScriptProgram.bindings.count)"
                + " passCandidates=\(propertyVectorPassCandidateTargets.count)"
                + " passConsumers=\(propertyVectorPassConsumerTargets.count)"
                + " passOwners=\(propertyVectorPassTargets.count)"
                + " failedPass=\(propertyVectorPassFailedTargets.count)"
                + " unclaimedPass=\(propertyVectorUnclaimedPassTargets.count)"
                + " route=generic-only fallback=current-frame-lower-priority"
                + " scaleLayerIDs="
                + "\(Array(propertyVectorScriptProgram.admittedScaleLayerIDs).sorted())"
        ] + soundPlaybackProgram.reportLines
    }

    private var sceneScriptTargetCount: Int {
        sceneScriptScalarProgram.definitions.count
            + propertyVectorScriptProgram.definitions.count
            + sceneScriptStringProgram.definitions.count
    }

    private var propertyVectorPassTargets: Set<SceneDynamicTarget> {
        Set(propertyVectorScriptProgram.definitions.compactMap { definition in
            guard case .effectConstant = definition.target else { return nil }
            return definition.target
        })
    }

    private var propertyVectorUnclaimedPassTargets: Set<SceneDynamicTarget> {
        propertyVectorPassCandidateTargets.subtracting(
            propertyVectorPassConsumerTargets
        )
    }

    private var mediaThumbnailTargetNames: [String] {
        propertyVectorScriptProgram.mediaThumbnailTargets
            .intersection(propertyVectorMediaTargets)
            .map { String(describing: $0) }.sorted()
    }

    private var mediaOwnerTargetNames: [String] {
        propertyVectorMediaTargets
            .map { String(describing: $0) }.sorted()
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

private extension SceneScriptVectorMediaRouteState {
    var reportReason: String {
        switch self {
        case .genericOnly, .preferGeneric:
            "active"
        case .disableGeneric:
            "route-disabled"
        }
    }
}
