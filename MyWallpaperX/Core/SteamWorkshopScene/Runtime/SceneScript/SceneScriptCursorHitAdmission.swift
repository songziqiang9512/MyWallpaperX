import Foundation

nonisolated enum SceneScriptCursorHitAdmission {
    static func accepts(_ layer: SceneRenderDescriptor.Layer) -> Bool {
        guard let size = layer.sizeWH,
              size.count == 2,
              size.allSatisfy({ $0.isFinite && $0 > 0 }) else {
            return false
        }
        if let origin = layer.originXYZ,
           origin.count != 3 || !origin.allSatisfy(\.isFinite) {
            return false
        }
        if let scale = layer.scaleXYZ,
           scale.count != 3
               || !scale.allSatisfy({ $0.isFinite && $0 != 0 }) {
            return false
        }
        if let angles = layer.anglesXYZ,
           angles.count != 3 || !angles.allSatisfy(\.isFinite) {
            return false
        }
        if let parallax = layer.parallaxDepthXY,
           parallax.count != 2 || !parallax.allSatisfy(\.isFinite) {
            return false
        }
        return true
    }
}
