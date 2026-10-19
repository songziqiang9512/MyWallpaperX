#if DEBUG
import CryptoKit
import Foundation
import Metal
import simd

/// Explicit diagnostic digest of the world-space Puppet geometry submitted in
/// the surface command buffer. Never enabled by normal playback or a sample
/// ID. Direct Puppet rendering deforms vertices while the atlas remains
/// immutable, so a texture readback cannot prove an interactive pose change.
final class ScenePuppetBoneEvidence {
    private static let layerIDs: Set<Int> = Set(
        (ProcessInfo.processInfo.environment["MYWALLPAPERX_SCENE_DEBUG_PUPPET_BONE_EVIDENCE"] ?? "")
            .split(separator: ",").compactMap { Int($0) })
    static func isEnabled(for layerID: Int) -> Bool { layerIDs.contains(layerID) }
    private var lastTime = -Double.infinity
    private var count = 0

    /// Direct geometry is authored model-space XYZ, before the one layer world
    /// transform. Pack each Float bit pattern explicitly: SIMD3 has padding.
    func recordDirect(layerID: Int, revision: UInt64, frame: UInt64, sceneTime: Double,
                      poseStatus: String, selection: ScenePuppetAnimationSelection,
                      animationFrame: ScenePuppetAnimationPlaybackRuntime.LayerFrame,
                      vertices: [SceneMdlStaticModel.Vertex],
                      bindVertices: [SceneMdlStaticModel.Vertex], commandBuffer: MTLCommandBuffer) {
        guard Self.layerIDs.contains(layerID), count < 1200,
              sceneTime - lastTime >= 0.08, !vertices.isEmpty,
              vertices.count == bindVertices.count else { return }
        lastTime = sceneTime
        count += 1
        var digest = SHA256()
        var displacement: Double = 0
        for (vertex, bind) in zip(vertices, bindVertices) {
            for component in [vertex.position.x, vertex.position.y, vertex.position.z] {
                var bits = component.bitPattern.littleEndian
                withUnsafeBytes(of: &bits) { digest.update(bufferPointer: $0) }
            }
            let delta = SIMD3<Double>(Double(vertex.position.x) - Double(bind.position.x),
                Double(vertex.position.y) - Double(bind.position.y),
                Double(vertex.position.z) - Double(bind.position.z))
            displacement = max(displacement, simd_length(delta))
        }
        let positionHash = digest.finalize().map { String(format: "%02x", $0) }.joined()
        let samples: [[String: Any]] = selection.clips.enumerated().map { index, clip in
            let sample = animationFrame.samples.indices.contains(index) ? animationFrame.samples[index] : nil
            return ["clipIndex": index, "animationLayerID": clip.layer.id.map { $0 as Any } ?? NSNull(),
                "animationID": clip.animation.id, "animationName": clip.animation.name,
                "visible": sample != nil, "frameA": sample.map { $0.frameA as Any } ?? NSNull(),
                "frameB": sample.map { $0.frameB as Any } ?? NSNull(),
                "fraction": sample.map { Double($0.fraction) as Any } ?? NSNull(),
                "blend": animationFrame.blends.flatMap { $0.indices.contains(index) ? $0[index] : nil }
                    ?? clip.layer.blend ?? 1]
        }
        guard let data = try? JSONSerialization.data(withJSONObject: samples, options: [.sortedKeys]),
              let sampleJSON = String(data: data, encoding: .utf8) else { return }
        let vertexCount = vertices.count
        commandBuffer.addCompletedHandler { completed in
            NSLog("MWX DEBUG SCENE: phase=puppet-direct-bone-output layer=%d frame=%llu revision=%llu sceneTime=%.9f poseStatus=%@ samples=%@ positionPacking=float32le-xyz positionSHA256=%@ vertexCount=%d maxBindDisplacement=%.9f gpu=%@",
                layerID, frame, revision, sceneTime, poseStatus, sampleJSON, positionHash,
                vertexCount, displacement, completed.status == .completed ? "completed" : "failed")
        }
    }

    func record(layerID: Int, revision: UInt64, frame: UInt64, sceneTime: Double,
                scriptWritten: Bool, displacement: Float,
                positions: [SIMD2<Float>], commandBuffer: MTLCommandBuffer) {
        guard Self.layerIDs.contains(layerID), count < 1200,
              sceneTime - lastTime >= 0.08,
              !positions.isEmpty else { return }
        lastTime = sceneTime
        count += 1
        let geometryHash = positions.withUnsafeBytes { bytes in
            SHA256.hash(data: Data(bytes)).map {
                String(format: "%02x", $0)
            }.joined()
        }
        let vertexCount = positions.count
        commandBuffer.addCompletedHandler { completed in
            guard completed.status == .completed else {
                NSLog("MWX DEBUG SCENE: phase=puppet-bone-output layer=%d frame=%llu revision=%llu gpu=failed",
                      layerID, frame, revision)
                return
            }
            NSLog("MWX DEBUG SCENE: phase=puppet-bone-output layer=%d frame=%llu revision=%llu sceneTime=%.6f scriptWritten=%@ maxBindDisplacement=%.6f geometrySHA256=%@ vertexCount=%d gpu=completed",
                  layerID, frame, revision, sceneTime,
                  scriptWritten ? "true" : "false", displacement,
                  geometryHash, vertexCount)
        }
    }
}
#endif
