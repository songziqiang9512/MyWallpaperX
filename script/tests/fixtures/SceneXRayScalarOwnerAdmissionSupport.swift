import Foundation
import simd

struct SceneXRayEffectTextures {
    let effectID: String
    let blendTexturePath: String
    let haloTexturePath: String?
    let opacityMaskPath: String?
    let blendPropertyKey: String?
    let haloPropertyKey: String?
    let blendUVScale: SIMD2<Float>
    let opacityUVScale: SIMD2<Float>

    func matches(_ declaration: SceneXRayRuntimePlanner.Declaration) -> Bool {
        effectID == declaration.effectID
            && blendTexturePath == declaration.blendTexturePath
            && haloTexturePath == declaration.haloTexturePath
            && opacityMaskPath == declaration.opacityMaskPath
            && blendPropertyKey == declaration.blendPropertyKey
            && haloPropertyKey == declaration.haloPropertyKey
    }
}

// The stock hash/source-graph identity has its own production gate. This seam
// deliberately lets the real planner body and compiler extension reach scalar
// admission; it does not claim full stock-identity integration.
extension SceneAuthoredXRayPlanner {
    static let definitionPath = "effects/xray/effect.json"
    static let materialPath = "materials/effects/xray.json"
    static let materialPassID = "materials/effects/xray.json#0"
    static let shaderIdentity = "effects/xray"

    struct StockIdentityProfile {
        let version: Int?
        let replacementKey: String?
        let group: String
        let materialSemanticSHA256: String
        let shaderCanonicalSHA256: String
        let shaderDependencySHA256: String
    }

    static func currentStockDefinitionMatches(
        descriptor: SceneRenderDescriptor,
        path: String
    ) -> Bool {
        path.replacingOccurrences(of: "\\\\", with: "/").lowercased()
            == "effects/xray/effect.json"
    }

    static func currentStockMaterialMatches(
        descriptor: SceneRenderDescriptor
    ) -> Bool {
        true
    }

    static func currentStockShaderContractMatches(
        _ contracts: [SceneShaderContract]
    ) -> Bool {
        contracts.count == 1
    }

    static func containsCandidate(graph: Graph) -> Bool {
        graph.effects.contains {
            $0.definitionPath.replacingOccurrences(
                of: "\\\\",
                with: "/"
            ).lowercased() == "effects/xray/effect.json"
        }
    }
}
