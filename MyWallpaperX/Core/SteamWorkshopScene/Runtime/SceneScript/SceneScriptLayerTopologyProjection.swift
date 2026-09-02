import Foundation

nonisolated extension SceneRenderDescriptor {
    func applying(_ topology: SceneScriptLayerTopologySnapshot) -> Self {
        var merged = layers
        merged.append(contentsOf: topology.dynamicLayers)
        return .init(
            entryPath: entryPath, camera: camera, lighting: lighting,
            layers: merged,
            rootLayerIDs: rootLayerIDs + topology.dynamicLayers.map { $0.id },
            renderOrderLayerIDs: topology.renderOrderLayerIDs,
            renderOrderPolicy: renderOrderPolicy,
            modelMaterialLinks: modelMaterialLinks, materialPasses: materialPasses,
            effectDefinitions: effectDefinitions,
            effectDefinitionDiagnostics: effectDefinitionDiagnostics,
            shaderReferences: shaderReferences, textureReferences: textureReferences,
            missingResources: missingResources,
            builtInReferenceCount: builtInReferenceCount,
            runtimeProvidedReferenceCount: runtimeProvidedReferenceCount,
            texturePropertyKeys: texturePropertyKeys,
            firstStageRendererGaps: firstStageRendererGaps
        )
    }
}

nonisolated extension SceneRenderDescriptor.Layer {
    static func dynamicImage(
        _ mutation: SceneScriptLayerMutation,
        template: SceneScriptDynamicImageLayerTemplate
    ) -> Self? {
        guard mutation.isDynamic, mutation.kind == .upsert,
              mutation.assetPath?.caseInsensitiveCompare(template.modelPath)
                == .orderedSame else { return nil }
        let origin = [mutation.origin.x, mutation.origin.y, mutation.origin.z]
            .map(Float.init)
        let scale = [mutation.scale.x, mutation.scale.y, mutation.scale.z]
            .map(Float.init)
        let angles = [mutation.angles.x, mutation.angles.y, mutation.angles.z]
            .map(Float.init)
        let color = [mutation.color.x, mutation.color.y, mutation.color.z].map {
            Float(max(0, min($0, 1)))
        }
        return SceneRenderDescriptor.Layer(
            id: mutation.layerID, layerIndex: mutation.orderIndex, name: nil,
            cameraPath: nil, contentKind: "image",
            imagePath: template.modelPath, particlePath: nil,
            spotLight: nil, particleInstanceOverride: nil, utilityLayer: nil,
            dependencyLayerIDs: [], authoredDependencies: [], parentID: nil,
            childLayerIDs: [], attachmentName: nil,
            parentAttachmentBindFrame: nil, puppetAnimationLayers: [],
            visible: mutation.visible, alpha: mutation.alpha,
            displayScriptOwnership: nil, colorRGB: color,
            colorBlendMode: nil, brightness: 1, imageAlignment: nil,
            origin: nil, size: nil, scale: nil, scaleHasScript: false,
            angles: nil, originXYZ: origin, sizeWH: template.renderSizeWH,
            scaleXYZ: scale, anglesXYZ: angles, parallaxDepthXY: [0, 0],
            disablesParallaxPropagation: false, timelines: [],
            timelineDiagnostics: [], particleTimelines: [],
            particleTimelineDiagnostics: [], modelCropOffsetXY: nil,
            puppetMeshPath: nil, text: nil, textStyle: nil, textScript: nil,
            scriptBindings: nil, textureAnimationScripts: nil,
            hasInlineScript: false, effects: [], effectFiles: [],
            texturePaths: []
        )
    }

    static func dynamicText(_ mutation: SceneScriptLayerMutation) -> Self? {
        guard mutation.isDynamic,
              mutation.kind == SceneScriptLayerMutation.Kind.upsert,
              mutation.text.utf8.count <= 4_096 else { return nil }
        let color = [mutation.color.x, mutation.color.y, mutation.color.z].map {
            Float(max(0, min($0, 1)))
        }
        let style = SceneTextDescriptor.parse([
            "font": mutation.font, "pointsize": mutation.pointSize, "color": color,
        ])
        let origin = [mutation.origin.x, mutation.origin.y, mutation.origin.z].map(Float.init)
        let scale = [mutation.scale.x, mutation.scale.y, mutation.scale.z].map(Float.init)
        let angles = [mutation.angles.x, mutation.angles.y, mutation.angles.z].map(Float.init)
        return SceneRenderDescriptor.Layer(
            id: mutation.layerID, layerIndex: mutation.orderIndex, name: nil,
            cameraPath: nil, contentKind: "text", imagePath: nil, particlePath: nil,
            spotLight: nil, particleInstanceOverride: nil, utilityLayer: nil,
            dependencyLayerIDs: [], authoredDependencies: [], parentID: nil,
            childLayerIDs: [], attachmentName: nil, parentAttachmentBindFrame: nil,
            puppetAnimationLayers: [], visible: mutation.visible, alpha: mutation.alpha,
            displayScriptOwnership: nil, colorRGB: color, colorBlendMode: nil,
            brightness: 1, imageAlignment: nil, origin: nil, size: nil, scale: nil,
            scaleHasScript: false, angles: nil, originXYZ: origin, sizeWH: nil,
            scaleXYZ: scale, anglesXYZ: angles, parallaxDepthXY: [0, 0],
            disablesParallaxPropagation: false, timelines: [], timelineDiagnostics: [],
            particleTimelines: [], particleTimelineDiagnostics: [], modelCropOffsetXY: nil,
            puppetMeshPath: nil, text: mutation.text, textStyle: style, textScript: nil,
            scriptBindings: nil, textureAnimationScripts: nil, hasInlineScript: false,
            effects: [], effectFiles: [], texturePaths: []
        )
    }
}
