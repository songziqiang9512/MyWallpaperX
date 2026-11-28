import Foundation
import simd

/// One frame's authored shader lighting, separate from native lighting payloads.
/// Each field keeps its own availability; an invalid lamp cannot invent a
/// default value or remove an otherwise valid ambient/geometry input.
nonisolated struct SceneAuthoredShaderLightingInputs: Sendable {
    let positions: [SIMD3<Float>]?
    let colorsPremultiplied: [SIMD4<Float>]?
    let ambient: SIMD3<Float>?
    let worldFromRenderWorld: simd_float4x4?
    var directLights: DirectLights = .empty

    struct DirectLights: Sendable {
        fileprivate static let stride = MemoryLayout<SIMD4<Float>>.stride
        static let empty = Self(pointCount: 0, spotCount: 0)

        fileprivate(set) var pointColor: Data
        fileprivate(set) var pointOrigin: Data
        fileprivate(set) var spotColor: Data
        fileprivate(set) var spotOrigin: Data
        fileprivate(set) var spotDirection: Data

        fileprivate init(pointCount: Int, spotCount: Int) {
            pointColor = Data(count: pointCount * Self.stride)
            pointOrigin = Data(count: pointCount * Self.stride)
            spotColor = Data(count: spotCount * Self.stride)
            spotOrigin = Data(count: spotCount * Self.stride)
            spotDirection = Data(count: spotCount * Self.stride)
        }

        fileprivate static func store(_ value: SIMD4<Float>, at slot: Int, in bytes: inout Data) {
            let start = slot * stride
            withUnsafeBytes(of: value) { bytes.replaceSubrange(start ..< start + stride, with: $0) }
        }
    }

    static let unavailable = Self(
        positions: nil, colorsPremultiplied: nil,
        ambient: nil, worldFromRenderWorld: nil
    )
    private static let emptyPositions = Array(repeating: SIMD3<Float>(0, 100, 0), count: 4)
    private static let zeroColors = Array(repeating: SIMD3<Float>.zero, count: 4)
    private static let zeroPackedColors = Array(repeating: SIMD4<Float>.zero, count: 3)

    /// Accumulated only by SceneLightSnapshot's existing author-ordered walk.
    /// Native admission, light budgets and payloads do not consume this value.
    struct Builder {
        private let worldFromRenderWorld: simd_float4x4?
        private let ambient: SIMD3<Float>?
        private var positions = SceneAuthoredShaderLightingInputs.emptyPositions
        private var colors = SceneAuthoredShaderLightingInputs.zeroColors
        private var count = 0
        private var positionsAvailable = true
        private var colorsAvailable = true
        private var directLights = DirectLights.empty
        private var directPointSlot = 0
        private var directSpotSlot = 0

        init(orthographicHeight: Float?, ambient: [Float]?, directLightSlots: (point: Int, spot: Int) = (0, 0)) {
            if let height = orthographicHeight, height.isFinite, height > 0 {
                worldFromRenderWorld = simd_float4x4(columns: (
                    SIMD4(1, 0, 0, 0), SIMD4(0, -1, 0, 0),
                    SIMD4(0, 0, 1, 0), SIMD4(0, height, 0, 1)
                ))
                if let ambient {
                    self.ambient = ambient.count == 3
                        && ambient.allSatisfy({ $0.isFinite && $0 >= 0 })
                        ? SIMD3(ambient[0], ambient[1], ambient[2]) : nil
                } else {
                    self.ambient = .zero
                }
                if directLightSlots.point > 0 || directLightSlots.spot > 0 {
                    directLights = DirectLights(pointCount: directLightSlots.point, spotCount: directLightSlots.spot)
                }
            } else {
                worldFromRenderWorld = nil
                self.ambient = nil
                positionsAvailable = false
                colorsAvailable = false
            }
        }

        mutating func appendDirectPoint(
            position: SIMD3<Float>, color: SIMD3<Float>, intensity: Float, radius: Float, exponent: Float
        ) {
            guard let worldFromRenderWorld,
                  directPointSlot * DirectLights.stride < directLights.pointOrigin.count else { return }
            let authoredPosition = worldFromRenderWorld * SIMD4(position, 1)
            let slot = directPointSlot
            directPointSlot += 1
            DirectLights.store(SIMD4(color * intensity, radius), at: slot, in: &directLights.pointColor)
            DirectLights.store(SIMD4(authoredPosition.x, authoredPosition.y, authoredPosition.z, exponent),
                at: slot, in: &directLights.pointOrigin)
        }

        mutating func appendDirectSpot(
            position: SIMD3<Float>, direction: SIMD3<Float>, color: SIMD3<Float>, intensity: Float,
            radius: Float, innerConeCosine: Float, outerConeCosine: Float
        ) {
            guard let worldFromRenderWorld,
                  directSpotSlot * DirectLights.stride < directLights.spotOrigin.count else { return }
            let authoredPosition = worldFromRenderWorld * SIMD4(position, 1)
            let authoredDirection = worldFromRenderWorld * SIMD4(direction, 0)
            let slot = directSpotSlot
            directSpotSlot += 1
            DirectLights.store(SIMD4(color * intensity, radius), at: slot, in: &directLights.spotColor)
            DirectLights.store(SIMD4(authoredPosition.x, authoredPosition.y, authoredPosition.z, innerConeCosine),
                at: slot, in: &directLights.spotOrigin)
            DirectLights.store(SIMD4(authoredDirection.x, authoredDirection.y, authoredDirection.z, outerConeCosine),
                at: slot, in: &directLights.spotDirection)
        }

        mutating func rejectUnsupportedLight() {
            positionsAvailable = false
            colorsAvailable = false
        }

        mutating func appendPoint(
            renderWorldPosition: SIMD3<Float>?,
            color: SIMD3<Float>?, intensity: Float?, radius: Float?
        ) {
            let slot = count
            count += 1
            guard slot < 4 else {
                rejectUnsupportedLight()
                return
            }
            if let position = renderWorldPosition,
               position.x.isFinite, position.y.isFinite, position.z.isFinite,
               let worldFromRenderWorld {
                let authored = SIMD3(
                    position.x,
                    Float(Double(worldFromRenderWorld.columns.3.y) - Double(position.y)),
                    position.z
                )
                if authored.x.isFinite, authored.y.isFinite, authored.z.isFinite {
                    positions[slot] = authored
                } else {
                    positionsAvailable = false
                }
            } else {
                positionsAvailable = false
            }
            guard let color, let intensity, let radius,
                  color.x.isFinite, color.y.isFinite, color.z.isFinite,
                  color.x >= 0, color.y >= 0, color.z >= 0,
                  intensity.isFinite, intensity >= 0,
                  radius.isFinite, radius >= 0 else {
                colorsAvailable = false
                return
            }
            // Double avoids premature Float overflow in radius², including
            // zero-intensity/zero-color lights whose final energy is valid.
            let energy = Double(intensity) * Double(radius) * Double(radius)
            let packed = SIMD3(
                Float(Double(color.x) * energy),
                Float(Double(color.y) * energy),
                Float(Double(color.z) * energy)
            )
            guard packed.x.isFinite, packed.y.isFinite, packed.z.isFinite else {
                colorsAvailable = false
                return
            }
            colors[slot] = packed
        }

        func finish() -> SceneAuthoredShaderLightingInputs {
            let packed: [SIMD4<Float>]?
            if !colorsAvailable {
                packed = nil
            } else if count == 0 {
                packed = SceneAuthoredShaderLightingInputs.zeroPackedColors
            } else {
                packed = [
                    SIMD4(colors[0], colors[3].x),
                    SIMD4(colors[1], colors[3].y),
                    SIMD4(colors[2], colors[3].z),
                ]
            }
            return .init(
                positions: positionsAvailable ? positions : nil,
                colorsPremultiplied: packed,
                ambient: ambient, worldFromRenderWorld: worldFromRenderWorld,
                directLights: directLights
            )
        }
    }
}
