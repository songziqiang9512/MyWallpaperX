import Foundation

struct SceneMetalRendererDiagnostic {
    let imageLayerCount: Int
    let particleLayerCount: Int
    let textLayerCount: Int
    let containerLayerCount: Int
    let effectPassCount: Int
    let materialPassCount: Int
    let rendererGaps: [String]
}
