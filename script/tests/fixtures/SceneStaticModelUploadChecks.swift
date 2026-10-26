import Foundation
import Metal
import simd

/// Reader and full Pipeline are production sources. Reflection only exposes
/// immutable storage to the test; every byte is copied back by a real GPU blit.
@main enum SceneStaticModelUploadChecks {
    static func main() throws {
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue() else {
            print("{\"metalUnavailable\":true}")
            return
        }
        let pipeline = SceneStaticModelPipeline(device: device)!
        let input = try JSONSerialization.jsonObject(with:
            Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))) as! [[String: Any]]
        var rows: [[String: Any]] = []
        for item in input {
            let model = try SceneMdlStaticModelReader.read(data:
                Data(contentsOf: URL(fileURLWithPath: item["path"] as! String)))
            let expectedVertices = model.vertices.withUnsafeBytes { Data($0) }
            let narrow = item["indexBytes"] as! Int == 2
            let expectedIndices = narrow
                ? model.indices.map(UInt16.init).withUnsafeBytes { Data($0) }
                : model.indices.withUnsafeBytes { Data($0) }
            let mesh = pipeline.makeMesh(model: model)!
            let fields = Dictionary(uniqueKeysWithValues: Mirror(reflecting: mesh).children.map {
                ($0.label!, $0.value)
            })
            let vertices = fields["vertexBuffer"] as! MTLBuffer
            let indices = fields["indexBuffer"] as! MTLBuffer
            let indexType = fields["indexType"] as! MTLIndexType
            let vertexResult = device.makeBuffer(length: vertices.length,
                                                  options: .storageModeShared)!
            let indexResult = device.makeBuffer(length: indices.length,
                                                 options: .storageModeShared)!
            let command = queue.makeCommandBuffer()!
            let blit = command.makeBlitCommandEncoder()!
            blit.copy(from: vertices, sourceOffset: 0, to: vertexResult,
                      destinationOffset: 0, size: vertices.length)
            blit.copy(from: indices, sourceOffset: 0, to: indexResult,
                      destinationOffset: 0, size: indices.length)
            blit.endEncoding()
            command.commit()
            command.waitUntilCompleted()
            let expectedMinimum = (item["minimum"] as! [NSNumber]).map(\.floatValue)
            let expectedMaximum = (item["maximum"] as! [NSNumber]).map(\.floatValue)
            let minimum = [mesh.boundsMinimum.x, mesh.boundsMinimum.y, mesh.boundsMinimum.z]
            let maximum = [mesh.boundsMaximum.x, mesh.boundsMaximum.y, mesh.boundsMaximum.z]
            let originalMinimum = model.vertices.reduce(model.vertices[0].position) { simd_min($0, $1.position) }
            let originalMaximum = model.vertices.reduce(model.vertices[0].position) { simd_max($0, $1.position) }
            let originalBits = [originalMinimum.x, originalMinimum.y, originalMinimum.z,
                                originalMaximum.x, originalMaximum.y, originalMaximum.z].map(\.bitPattern)
            rows.append([
                "name": item["name"]!,
                "gpuCompleted": command.status == .completed && command.error == nil,
                "allVertexBytes": vertices.length == expectedVertices.count
                    && Data(bytes: vertexResult.contents(), count: vertices.length) == expectedVertices,
                "allIndexBytes": indices.length == expectedIndices.count
                    && Data(bytes: indexResult.contents(), count: indices.length) == expectedIndices,
                "indexType": indexType == (narrow ? .uint16 : .uint32),
                "tightBounds": minimum == expectedMinimum && maximum == expectedMaximum,
                "boundsBitsMatchOriginal": (minimum + maximum).map(\.bitPattern) == originalBits,
                "counts": mesh.vertexCount == model.vertices.count && mesh.indexCount == model.indices.count,
                "authoredBoundsWereLoose": model.bounds.minimum != minimum || model.bounds.maximum != maximum,
                "vertexCount": mesh.vertexCount, "indexBytes": indices.length / mesh.indexCount,
            ])
        }
        print(String(decoding: try JSONSerialization.data(withJSONObject: ["rows": rows],
            options: [.sortedKeys]), as: UTF8.self))
    }
}
