import Foundation
import simd

enum SceneLightSnapshot {
    struct Point { let position: SIMD3<Float>; let radius: Float }
    struct Spot {
        let position: SIMD3<Float>
        let directionFromLight: SIMD3<Float>
        let radius: Float
        let outerConeDegrees: Float
        let outerConeCosine: Float
    }
}

@main
struct SceneDirectionalShadowFitChecks {
    static func vector(_ raw: Any) -> SIMD3<Float> {
        let a = raw as! [Double]
        return SIMD3(Float(a[0]), Float(a[1]), Float(a[2]))
    }

    static func matrix(_ raw: Any) -> simd_float4x4 {
        let a = (raw as! [Double]).map(Float.init)
        return simd_float4x4(columns: (
            SIMD4(a[0], a[1], a[2], a[3]), SIMD4(a[4], a[5], a[6], a[7]),
            SIMD4(a[8], a[9], a[10], a[11]), SIMD4(a[12], a[13], a[14], a[15])))
    }

    static func main() throws {
        let input = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
        let cases = try JSONSerialization.jsonObject(with: input) as! [[String: Any]]
        var rows: [[String: Any]] = []
        for item in cases {
            let casters = (item["casters"] as! [[String: Any]]).map { b in
                (minimum: vector(b["minimum"]!), maximum: vector(b["maximum"]!), world: matrix(b["world"]!))
            }
            let receivers = (item["receivers"] as! [[String: Any]]).map { b in
                (minimum: vector(b["minimum"]!), maximum: vector(b["maximum"]!), world: matrix(b["world"]!),
                 clip: b["clip"].flatMap { $0 is NSNull ? nil : matrix($0) })
            }
            #if MWX_OLD_SHADOW_API
            // Only the call shape changes for the saved old implementation;
            // exactly the same authored geometric payload reaches both runs.
            let suppliedReceivers = receivers.map { (minimum: $0.minimum, maximum: $0.maximum, world: $0.world) }
            #else
            let suppliedReceivers = receivers
            #endif
            let fit = SceneDirectionalShadowProjection.make(bounds: casters, receiverBounds: suppliedReceivers,
                directionTowardLight: vector(item["towardLight"]!), resolution: item["resolution"] as! Int)
            var row: [String: Any] = ["name": item["name"]!, "present": fit != nil]
            if let fit {
                let m = fit.worldToClip
                var values: [Float] = []
                for column in 0..<4 { for component in 0..<4 { values.append(m[column][component]) } }
                let x = SIMD3(m[0].x, m[1].x, m[2].x)
                let y = SIMD3(m[0].y, m[1].y, m[2].y)
                let witnesses = (item["witnesses"] as! [[Double]]).map { p -> [Float] in
                    let q = m * SIMD4(vector(p), 1)
                    return [q.x / q.w, q.y / q.w, q.z / q.w]
                }
                row["matrix"] = values
                row["depthBias"] = fit.depthBias
                row["worldUnitsPerTexel"] = [2 / simd_length(x), 2 / simd_length(y)]
                    .map { $0 / Float(item["resolution"] as! Int) }
                row["witnessClip"] = witnesses
            }
            rows.append(row)
        }
        let output = try JSONSerialization.data(withJSONObject: ["rows": rows], options: [.sortedKeys])
        print(String(decoding: output, as: UTF8.self))
    }
}
