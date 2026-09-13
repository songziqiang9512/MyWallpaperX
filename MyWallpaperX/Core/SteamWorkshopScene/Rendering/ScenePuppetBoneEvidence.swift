#if DEBUG
import CryptoKit
import Foundation
import Metal

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
