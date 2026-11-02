
import Foundation
import Dispatch
import Metal
import simd

struct SceneRenderDescriptor {
    struct Layer {
        var id: Int = 0
        let utilityLayer: Bool?
        let usesPerspective: Bool?
        var hasPerspectiveGeometryConsumer = false
        var hasFramebufferMaterialSource = false
    }

    struct CameraDescriptor {
        let eye: [Float]
        let center: [Float]
        let up: [Float]
        let orthoWidth: Float?
        let orthoHeight: Float?
        let fovDegrees: Float?
        let perspectiveOverrideFOVDegrees: Float?
        let nearZ: Float
        let farZ: Float
    }
}
