
import Foundation

struct SceneRenderDescriptor { var layers: [Layer] }
struct SceneParticleInstanceOverride: Codable {}
struct ScenePuppetAnimationLayer: Codable {}
struct SceneTextDescriptor: Codable { let padding: Float }
struct SceneTextScriptDefinition: Codable {}

struct SceneDocument {
    struct Scene2DCameraPathDefinition: Codable {}
    struct SceneObjectTimeline: Codable {}
    struct SceneParticleTimeline: Codable {}
}

enum SceneTextGeometry {
    static func expandedSize(authoredSize: [Float]?, padding: Float) -> [Float]? {
        authoredSize
    }
}

extension SceneRenderDescriptor {
    struct EffectDescriptor: Codable {}
}

@main
enum Harness {
    static func main() throws {
        let oldCache = """
        {
          "id": 1,
          "layerIndex": 0,
          "contentKind": "image",
          "dependencyLayerIDs": [],
          "authoredDependencies": [],
          "childLayerIDs": [],
          "puppetAnimationLayers": [],
          "disablesParallaxPropagation": false,
          "timelines": [],
          "timelineDiagnostics": [],
          "particleTimelines": [],
          "particleTimelineDiagnostics": [],
          "hasInlineScript": false,
          "effects": [],
          "effectFiles": [],
          "texturePaths": []
        }
        """
        let layer = try JSONDecoder().decode(
            SceneRenderDescriptor.Layer.self,
            from: Data(oldCache.utf8)
        )
        let layersJSON = """
        [
          {
            "id": 1,
            "layerIndex": 0,
            "contentKind": "image",
            "dependencyLayerIDs": [],
            "authoredDependencies": [],
            "childLayerIDs": [],
            "puppetAnimationLayers": [],
            "visible": true,
            "disablesParallaxPropagation": false,
            "timelines": [],
            "timelineDiagnostics": [],
            "particleTimelines": [],
            "particleTimelineDiagnostics": [],
            "hasInlineScript": false,
            "effects": [],
            "effectFiles": [],
            "texturePaths": []
          },
          {
            "id": 2,
            "layerIndex": 1,
            "contentKind": "image",
            "dependencyLayerIDs": [],
            "authoredDependencies": [],
            "childLayerIDs": [3],
            "puppetAnimationLayers": [],
            "visible": true,
            "displayScriptOwnership": {"visible": true, "alpha": false},
            "disablesParallaxPropagation": false,
            "timelines": [],
            "timelineDiagnostics": [],
            "particleTimelines": [],
            "particleTimelineDiagnostics": [],
            "hasInlineScript": true,
            "effects": [],
            "effectFiles": [],
            "texturePaths": []
          },
          {
            "id": 3,
            "layerIndex": 2,
            "contentKind": "image",
            "dependencyLayerIDs": [],
            "authoredDependencies": [],
            "parentID": 2,
            "childLayerIDs": [],
            "puppetAnimationLayers": [],
            "visible": true,
            "disablesParallaxPropagation": false,
            "timelines": [],
            "timelineDiagnostics": [],
            "particleTimelines": [],
            "particleTimelineDiagnostics": [],
            "hasInlineScript": false,
            "effects": [],
            "effectFiles": [],
            "texturePaths": []
          },
          {
            "id": 4,
            "layerIndex": 3,
            "contentKind": "image",
            "dependencyLayerIDs": [],
            "authoredDependencies": [],
            "childLayerIDs": [],
            "puppetAnimationLayers": [],
            "visible": true,
            "displayScriptOwnership": {"visible": false, "alpha": true},
            "disablesParallaxPropagation": false,
            "timelines": [],
            "timelineDiagnostics": [],
            "particleTimelines": [],
            "particleTimelineDiagnostics": [],
            "hasInlineScript": true,
            "effects": [],
            "effectFiles": [],
            "texturePaths": []
          }
        ]
        """
        let layers = try JSONDecoder().decode(
            [SceneRenderDescriptor.Layer].self,
            from: Data(layersJSON.utf8)
        )
        let descriptor = SceneRenderDescriptor(layers: layers)
        let payload: [String: Any] = [
            "oldScriptBindingsMissing": layer.scriptBindings == nil,
            "oldDisplayOwnershipMissing": layer.displayScriptOwnership == nil,
            "visibleLayerIDs": SceneLayerVisibility.visibleLayerIDs(in: descriptor).sorted(),
            "reportLines": SceneLayerVisibility.reportLines(in: descriptor),
        ]
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }
}
