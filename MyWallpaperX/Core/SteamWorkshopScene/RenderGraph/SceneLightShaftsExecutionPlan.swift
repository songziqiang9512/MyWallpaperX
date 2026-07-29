import simd

nonisolated struct SceneLightShaftsPerspectiveTransform {
    let row0: SIMD3<Float>
    let row1: SIMD3<Float>
    let row2: SIMD3<Float>

    nonisolated static func make(
        points: (SIMD2<Float>, SIMD2<Float>, SIMD2<Float>, SIMD2<Float>)
    ) -> SceneLightShaftsPerspectiveTransform? {
        let sources = [points.0, points.1, points.2, points.3]
        let targets = [
            SIMD2<Double>(0, 0),
            SIMD2<Double>(1, 0),
            SIMD2<Double>(1, 1),
            SIMD2<Double>(0, 1),
        ]
        guard sources.allSatisfy({ $0.x.isFinite && $0.y.isFinite }) else {
            return nil
        }

        var system = Array(
            repeating: Array(repeating: 0.0, count: 9),
            count: 8
        )
        for index in sources.indices {
            let x = Double(sources[index].x)
            let y = Double(sources[index].y)
            let u = targets[index].x
            let v = targets[index].y
            system[index * 2] = [
                x, y, 1, 0, 0, 0, -u * x, -u * y, u,
            ]
            system[index * 2 + 1] = [
                0, 0, 0, x, y, 1, -v * x, -v * y, v,
            ]
        }

        guard solve(&system) else { return nil }
        let values = system.map { $0[8] }
        guard values.allSatisfy(\.isFinite) else { return nil }
        let transform = SceneLightShaftsPerspectiveTransform(
            row0: SIMD3(Float(values[0]), Float(values[1]), Float(values[2])),
            row1: SIMD3(Float(values[3]), Float(values[4]), Float(values[5])),
            row2: SIMD3(Float(values[6]), Float(values[7]), 1)
        )
        guard transform.isFinite,
              zip(sources, targets).allSatisfy({ source, target in
                  guard let mapped = transform.project(source) else { return false }
                  return simd_distance(
                      mapped,
                      SIMD2(Float(target.x), Float(target.y))
                  ) <= 0.001
              }),
              transform.hasStableDenominatorAcrossUnitQuad else {
            return nil
        }
        return transform
    }

    nonisolated func project(_ point: SIMD2<Float>) -> SIMD2<Float>? {
        let source = SIMD3(point.x, point.y, 1)
        let denominator = simd_dot(row2, source)
        guard denominator.isFinite, abs(denominator) > 0.00001 else {
            return nil
        }
        let result = SIMD2(
            simd_dot(row0, source) / denominator,
            simd_dot(row1, source) / denominator
        )
        return result.x.isFinite && result.y.isFinite ? result : nil
    }

    nonisolated var isFinite: Bool {
        [row0, row1, row2].allSatisfy {
            $0.x.isFinite && $0.y.isFinite && $0.z.isFinite
        }
    }

    nonisolated private var hasStableDenominatorAcrossUnitQuad: Bool {
        let denominators = [
            row2.z,
            row2.x + row2.z,
            row2.y + row2.z,
            row2.x + row2.y + row2.z,
        ]
        guard denominators.allSatisfy({ $0.isFinite && abs($0) > 0.00001 }),
              let first = denominators.first else {
            return false
        }
        return denominators.allSatisfy { ($0 > 0) == (first > 0) }
    }

    nonisolated private static func solve(_ system: inout [[Double]]) -> Bool {
        for column in 0..<8 {
            guard let pivotRow = (column..<8).max(
                by: { abs(system[$0][column]) < abs(system[$1][column]) }
            ),
            abs(system[pivotRow][column]) > 0.000000001 else {
                return false
            }
            system.swapAt(column, pivotRow)
            let pivot = system[column][column]
            for entry in column..<9 {
                system[column][entry] /= pivot
            }
            for row in 0..<8 where row != column {
                let factor = system[row][column]
                for entry in column..<9 {
                    system[row][entry] -= factor * system[column][entry]
                }
            }
        }
        return true
    }
}

nonisolated struct SceneLightShaftsExecutionPlan {
    let layerID: Int
    let effectKey: SceneAuthoredEffectRenderPlan.EffectKey
    let renderGraph: SceneAuthoredEffectRenderPlan
    let points: (SIMD2<Float>, SIMD2<Float>, SIMD2<Float>, SIMD2<Float>)
    let effectUVTransform: SceneLightShaftsPerspectiveTransform
    let feather: SIMD2<Float>
    let scale: SIMD2<Float>
    let radius: Float
    let noiseAmount: Float
    let noiseScale: Float
    let smoothness: Float
    let speed: Float
    let intensity: Float
    let exponent: Float
    let noiseTexturePath: String
    let gradientTexturePath: String
}
