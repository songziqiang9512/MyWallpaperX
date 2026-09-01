import Foundation

extension SceneDesktopWallpaperHost {
    /// Startup deferral is a launch/resource policy, not graph admission. Its
    /// own source keeps small graph harnesses independent from property and
    /// surface lifecycle types.
    static func deferredEffectlessBaseImageLayerIDs(
        in descriptor: SceneRenderDescriptor,
        bindingProgram: ScenePropertyBindingProgram,
        effectivePropertyValues: [String: SceneUserPropertyValue]
    ) -> Set<Int> {
        guard !descriptor.layers.contains(where: {
            $0.contentKind == "particle"
        }) else { return [] }
        let eligibleLayerIDs: Set<Int> = Set(descriptor.layers.compactMap { layer in
            guard layer.contentKind == "image",
                  layer.effects.isEmpty,
                  layer.dependencyLayerIDs.isEmpty,
                  layer.authoredDependencies.isEmpty,
                  layer.puppetMeshPath == nil,
                  layer.puppetAnimationLayers.isEmpty,
                  layer.timelines.isEmpty,
                  layer.particleTimelines.isEmpty,
                  layer.displayScriptOwnership?.isEmpty != false,
                  layer.scriptBindings?.isEmpty != false,
                  layer.textureAnimationScripts?.isEmpty != false,
                  !layer.hasInlineScript else { return nil }
            return layer.id
        })
        let propertyValues = bindingProgram.evaluate(
            effectiveValues: effectivePropertyValues
        ).userValues
        let snapshot = SceneDynamicSnapshotResolver().resolve(
            frameIndex: 0,
            generation: 0,
            definitions: bindingProgram.definitions,
            userValues: propertyValues
        ).snapshot
        return SceneDynamicLayerVisibilityRouteAdmission.layerIDs(
            in: descriptor,
            candidates: bindingProgram.liveConditionalLayerVisibilityTargets
        ).intersection(eligibleLayerIDs).subtracting(
            SceneLayerVisibility.visibleLayerIDs(
                in: descriptor,
                snapshot: snapshot
            )
        )
    }
}
