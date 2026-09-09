#if DEBUG
import CryptoKit
import Foundation
import Metal

/// Explicit diagnostic readback of the actual Puppet source produced in the
/// surface command buffer. Never enabled by normal playback or a sample ID.
final class ScenePuppetBoneEvidence {
    private static let layerIDs: Set<Int> = Set(
        (ProcessInfo.processInfo.environment["MYWALLPAPERX_SCENE_DEBUG_PUPPET_BONE_EVIDENCE"] ?? "")
            .split(separator: ",").compactMap { Int($0) })
    static func isEnabled(for layerID: Int) -> Bool { layerIDs.contains(layerID) }
    private var lastTime = -Double.infinity
    private var count = 0

    func record(layerID: Int, revision: UInt64, frame: UInt64, sceneTime: Double,
                scriptWritten: Bool, displacement: Float, texture: MTLTexture, commandBuffer: MTLCommandBuffer) {
        guard Self.layerIDs.contains(layerID), count < 1200,
              sceneTime - lastTime >= 0.08 else { return }
        lastTime = sceneTime
        count += 1
        let width = texture.width, height = texture.height
        let rowBytes = (width * 4 + 255) / 256 * 256
        guard [.rgba8Unorm, .rgba8Unorm_srgb, .bgra8Unorm, .bgra8Unorm_srgb].contains(texture.pixelFormat),
              let buffer = texture.device.makeBuffer(length: rowBytes * height, options: .storageModeShared),
              let blit = commandBuffer.makeBlitCommandEncoder() else { return }
        blit.copy(from: texture, sourceSlice: 0, sourceLevel: 0,
                  sourceOrigin: .init(x: 0, y: 0, z: 0),
                  sourceSize: .init(width: width, height: height, depth: 1),
                  to: buffer, destinationOffset: 0, destinationBytesPerRow: rowBytes,
                  destinationBytesPerImage: rowBytes * height)
        blit.endEncoding()
        commandBuffer.addCompletedHandler { completed in
            guard completed.status == .completed else {
                NSLog("MWX DEBUG SCENE: phase=puppet-bone-output layer=%d frame=%llu revision=%llu gpu=failed",
                      layerID, frame, revision)
                return
            }
            var digest = SHA256()
            for row in 0..<height {
                digest.update(data: Data(bytesNoCopy: buffer.contents().advanced(by: row * rowBytes),
                                         count: width * 4, deallocator: .none))
            }
            let hash = digest.finalize().map { String(format: "%02x", $0) }.joined()
            NSLog("MWX DEBUG SCENE: phase=puppet-bone-output layer=%d frame=%llu revision=%llu sceneTime=%.6f scriptWritten=%@ maxBindDisplacement=%.6f sourceSHA256=%@ width=%d height=%d gpu=completed",
                  layerID, frame, revision, sceneTime, scriptWritten ? "true" : "false", displacement, hash, width, height)
        }
    }
}
#endif
