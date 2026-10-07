#!/usr/bin/env python3
"""Real Puppet playback must publish only complete poses to Metal geometry."""

from __future__ import annotations

import json
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

from script.tests.test_scene_puppet_playback import SCENE_ROOT, SWIFT_SOURCES


PLAYBACK_SOURCES = [
    "Format/SceneMdlPuppetAttachmentReader.swift",
    "Systems/Puppet/ScenePuppetAttachmentPoseProjection.swift",
    "Systems/Puppet/ScenePuppetTranslationMotion.swift",
    "Systems/Puppet/ScenePuppetPlaybackState.swift",
    "Systems/Properties/ScenePuppetAnimationPropertyTarget.swift",
    "Rendering/Geometry/SceneGeometryProduct.swift",
    "Rendering/Frame/SceneSourceUpdateTransaction.swift",
    "Rendering/Metal/SceneMetalPipeline.swift",
    "Rendering/Targets/SceneOffscreenResolutionPolicy.swift",
    "Diagnostics/ScenePerformanceCounterHub.swift",
]

HARNESS = r'''
import CryptoKit
import Foundation
import Metal
import simd

// These peripheral contracts supply an immutable empty property snapshot and
// observe allocations/evidence. Playback, evaluation, publication, FIFO state,
// geometry encoding, the image pipeline and all Metal objects are production.
enum SceneDynamicTarget: Hashable {
    case scriptInstanceProperty(layerID: Int, path: [String])
}
enum SceneDynamicValue { case bool(Bool) }
struct SceneDynamicResolvedValue { let value: SceneDynamicValue }
struct SceneDynamicSnapshot {
    let frameIndex: UInt64
    subscript(target: SceneDynamicTarget) -> SceneDynamicResolvedValue? { nil }
}
struct SceneScriptPuppetBoneMutation {
    let layerID: Int, boneIndex: Int
    let matrix: [Double]
}
enum ScenePuppetLayerLoad {
    struct BoneConfiguration {
        let names: [String], parentIndices: [Int]
        let worldMatrices: [Double], localMatrices: [Double]
    }
}
enum SceneDesktopWallpaperHost { static let usesDebugEvidenceWindow = false }
enum Observation {
    static var buffers: [MTLBuffer] = []
    static var evidence: [[SIMD2<Float>]] = []
    static weak var previousCommand: MTLCommandBuffer?
}
extension MTLDevice {
    func makeSceneBuffer(length: Int) -> MTLBuffer? {
        guard let buffer = makeBuffer(length: length, options: .storageModeShared) else {
            return nil
        }
        // Make an accidental pre-publication draw observably uninitialized.
        buffer.contents().initializeMemory(as: UInt8.self, repeating: 0xA5, count: length)
        Observation.buffers.append(buffer)
        return buffer
    }
    func makeSceneBuffer(bytes: UnsafeRawPointer, length: Int) -> MTLBuffer? {
        makeBuffer(bytes: bytes, length: length, options: .storageModeShared)
    }
}
final class ScenePuppetBoneEvidence {
    static func isEnabled(for layerID: Int) -> Bool { true }
    func record(layerID: Int, revision: UInt64, frame: UInt64, sceneTime: Double,
                scriptWritten: Bool, displacement: Float,
                positions: [SIMD2<Float>], commandBuffer: MTLCommandBuffer) {
        Observation.evidence.append(positions)
    }
}

func columns(_ matrix: simd_float4x4) -> [Float] {
    (0..<4).flatMap { column in (0..<4).map { matrix[column][$0] } }
}
func pose(scale: Float = 1, translationX: Float = 0) -> SceneMdlPuppetAnimation.Transform {
    .init(translation: SIMD3(translationX, 0, 0), rotation: .zero,
          scale: SIMD3(scale, 1, 1))
}
func fixture(poses: [SceneMdlPuppetAnimation.Transform], weight: Double,
             wideVertex: Bool = false)
    -> (SceneMdlPuppetMesh, SceneMdlPuppetRig, ScenePuppetAnimationSelection) {
    let mesh = SceneMdlPuppetMesh(version: "MDLV0023", vertexStride: 80,
        meshBlockOffset: 9, vertices: [
            .init(x: wideVertex ? 2 : -0.5, y: -0.5, z: 0, u: 0, v: 0),
            .init(x: wideVertex ? 1e6 : 0.5, y: -0.5, z: 0, u: 1, v: 0),
            .init(x: wideVertex ? 2 : 0, y: 0.5, z: 0, u: 0, v: 1),
        ], indices: [0, 1, 2])
    let rig = SceneMdlPuppetRig(bones: [
        .init(parentIndex: -1, bindLocalMatrixColumnMajor: columns(matrix_identity_float4x4))
    ], vertexWeights: mesh.vertices.map { _ in
        .init(boneIndices: SIMD4(0, 0, 0, 0), boneWeights: SIMD4(1, 0, 0, 0))
    })
    let animation = SceneMdlPuppetAnimation(id: 1, name: "publication", mode: "single",
        framesPerSecond: 1, frameCount: poses.count - 1, transformsByBone: [poses])
    let layer = ScenePuppetAnimationLayer(id: 1, animationID: 1, name: "publication",
        additive: true, blend: weight, blendIn: false, blendOut: false,
        blendTime: 0, rate: 1, visible: true, visibilityBinding: nil)
    return (mesh, rig, .init(clips: [.init(layer: layer, animation: animation)],
                             composition: .layered))
}
func texture(_ device: MTLDevice, size: Int, renderTarget: Bool = false) -> MTLTexture {
    let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm,
        width: size, height: size, mipmapped: false)
    descriptor.storageMode = .shared
    descriptor.usage = renderTarget ? [.renderTarget] : [.shaderRead]
    return device.makeTexture(descriptor: descriptor)!
}
func bufferBytes(_ buffers: [MTLBuffer]) -> [Data] {
    buffers.map { Data(bytes: $0.contents(), count: $0.length) }
}
func makePlayback(_ fixture: (SceneMdlPuppetMesh, SceneMdlPuppetRig,
                              ScenePuppetAnimationSelection),
                  device: MTLDevice, pipeline: SceneImageLayerPipeline,
                  atlas: MTLTexture) throws -> ScenePuppetPlaybackState.Output {
    let identity = columns(matrix_identity_float4x4)
    return try ScenePuppetPlaybackState.make(layerID: 42, mesh: fixture.0,
        rig: fixture.1, selection: fixture.2,
        attachments: [.init(boneIndex: 0, name: "tip",
            modelLocalFrameColumnMajor: identity, modelBindFrameColumnMajor: identity)],
        atlasTexture: atlas, layerWidth: 16, layerHeight: 16,
        device: device, pipeline: pipeline).get()
}

struct Frame {
    let readyBefore: Bool, readyAfter: Bool, drew: Bool
    let differentLiveCommandReady: Bool, previousCommandReleased: Bool
    let draws: UInt64
    let pixels: [UInt8]
    let attachments: [String: simd_float4x4]
    var report: [String: Any] {
        ["readyBefore": readyBefore, "readyAfter": readyAfter, "drew": drew,
         "differentLiveCommandReady": differentLiveCommandReady,
         "previousCommandReleased": previousCommandReleased,
         "draws": draws, "litPixels": pixels.enumerated().filter {
             $0.offset % 4 == 3 && $0.element > 0
         }.count, "imageSHA256": SHA256.hash(data: Data(pixels)).map {
             String(format: "%02x", $0)
         }.joined()]
    }
}
func render(_ output: ScenePuppetPlaybackState.Output, sceneTime: Double,
            device: MTLDevice, queue: MTLCommandQueue, atlas: MTLTexture,
            mvp: simd_float4x4 = matrix_identity_float4x4) -> Frame {
    return autoreleasepool {
        let previousCommandReleased = Observation.previousCommand == nil
        let command = queue.makeCommandBuffer()!
        let transaction = SceneSourceUpdateTransaction()
        let readyBefore = output.product.isPreparedForPublication(command)
        let attachments = output.state.encode(sceneTime: sceneTime,
            dynamicValues: .init(frameIndex: UInt64(sceneTime * 10)),
            commandBuffer: command, transaction: transaction)
        let readyAfter = output.product.isPreparedForPublication(command)
        let differentLiveCommand = queue.makeCommandBuffer()!
        let differentLiveCommandReady = output.product.isPreparedForPublication(differentLiveCommand)
        let target = texture(device, size: 32, renderTarget: true)
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = target
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0)
        let encoder = command.makeRenderCommandEncoder(descriptor: pass)!
        let uniforms = SceneLayerFragmentUniforms(time: Float(sceneTime), alpha: 1,
            dependencyBlendMode: 0, usesDependencyBlend: 0, cursorUV: .zero,
            sourceSampling: SIMD2(2, 0), tint: SIMD4(repeating: 1),
            textureFrame0: SIMD4(0, 0, 1, 0), textureFrame1: SIMD4(0, 1, 0, 0))
        let before = ScenePerformanceCounterHub.shared.snapshot()[.geometryDrawCalls]!
        // Invoke the real direct encoder even when publication is unavailable.
        let drew = output.product.encode(encoder, atlas, nil, mvp, uniforms, nil)
        let draws = ScenePerformanceCounterHub.shared.snapshot()[.geometryDrawCalls]! - before
        encoder.endEncoding()
        transaction.arm(on: command)
        transaction.didSubmit()
        command.commit()
        command.waitUntilCompleted()
        precondition(command.status == .completed && command.error == nil)
        var pixels = [UInt8](repeating: 0, count: 32 * 32 * 4)
        pixels.withUnsafeMutableBytes {
            target.getBytes($0.baseAddress!, bytesPerRow: 32 * 4,
                            from: MTLRegionMake2D(0, 0, 32, 32), mipmapLevel: 0)
        }
        Observation.previousCommand = command
        return Frame(readyBefore: readyBefore, readyAfter: readyAfter, drew: drew,
                     differentLiveCommandReady: differentLiveCommandReady,
                     previousCommandReleased: previousCommandReleased,
                     draws: draws, pixels: pixels, attachments: attachments)
    }
}

@main enum Harness {
    static func main() throws {
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue() else { fatalError("Metal unavailable") }
        let library = try device.makeLibrary(URL: URL(fileURLWithPath: CommandLine.arguments[1]))
        let pipeline = SceneImageLayerPipeline(device: device, library: library)!
        let atlas = texture(device, size: 2)
        let white = [UInt8](repeating: 255, count: 2 * 2 * 4)
        white.withUnsafeBytes {
            atlas.replace(region: MTLRegionMake2D(0, 0, 2, 2), mipmapLevel: 0,
                          withBytes: $0.baseAddress!, bytesPerRow: 2 * 4)
        }
        let singularFixture = fixture(poses: [pose(), pose(scale: 0.5)], weight: 2)
        let singular = try makePlayback(singularFixture, device: device,
                                        pipeline: pipeline, atlas: atlas)
        let initialBuffers = bufferBytes(Observation.buffers)
        let firstFailure = render(singular, sceneTime: 1, device: device, queue: queue, atlas: atlas)
        let rejectedEvidence = Observation.evidence.isEmpty
        let rejectedBuffers = bufferBytes(Observation.buffers) == initialBuffers
        let firstRecovery = render(singular, sceneTime: 0, device: device, queue: queue, atlas: atlas)

        // Large but finite scale leaves the first vertex finite and overflows
        // the second. Verify the fixture reaches a genuinely partial write.
        let partialFixture = fixture(poses: [pose(), pose(scale: 1e6),
            pose(translationX: 5e-25)], weight: 1e30, wideVertex: true)
        let evaluator = try ScenePuppetAnimationEvaluator(mesh: partialFixture.0,
            rig: partialFixture.1, additiveAnimations: partialFixture.2.clips.map(\.animation))
        let sentinel = SIMD2<Float>(-123, -456)
        var points = [SIMD2<Float>](repeating: sentinel, count: 3)
        var locals = [matrix_identity_float4x4], skins = locals, worlds = locals
        var partialRejected = false
        do {
            try points.withUnsafeMutableBufferPointer {
                try evaluator.writeDeformedPositions(selection: partialFixture.2,
                    frameSamples: [.init(frameA: 1, frameB: 1)], into: $0,
                    localMatricesScratch: &locals, skinMatricesScratch: &skins,
                    worldMatricesScratch: &worlds)
            }
        } catch let error as ScenePuppetAnimationEvaluationFailure {
            partialRejected = error == .invalidDeformedVertex
        }
        let verifiedPartialWrite = partialRejected && points[0] != sentinel
            && points[0].x.isFinite && points[0].y.isFinite
            && points[1] == sentinel && points[2] == sentinel
        Observation.buffers.removeAll()
        Observation.evidence.removeAll()
        let partial = try makePlayback(partialFixture, device: device,
                                       pipeline: pipeline, atlas: atlas)
        let mvp = SceneMatrix.translation(SIMD3<Float>(-0.5, 0, 0))
            * SceneMatrix.scale(SIMD3<Float>(1e-6, 1, 1))
        let good = render(partial, sceneTime: 0, device: device, queue: queue, atlas: atlas, mvp: mvp)
        let goodBuffers = bufferBytes(Observation.buffers)
        let goodEvidence = Observation.evidence.last!
        let failed = render(partial, sceneTime: 1, device: device, queue: queue, atlas: atlas, mvp: mvp)
        let retainedBuffers = bufferBytes(Observation.buffers) == goodBuffers
        let retainedEvidence = Observation.evidence.last == goodEvidence
        let recovered = render(partial, sceneTime: 2, device: device, queue: queue, atlas: atlas, mvp: mvp)
        let refreshedBuffers = bufferBytes(Observation.buffers) != goodBuffers
        let refreshedEvidence = Observation.evidence.last != goodEvidence
        let result: [String: Any] = [
            "metalDevice": device.name,
            "firstFailure": firstFailure.report, "firstRecovery": firstRecovery.report,
            "firstFailureBuffersUntouched": rejectedBuffers,
            "firstFailureHasNoEvidence": rejectedEvidence,
            "verifiedPartialWrite": verifiedPartialWrite,
            "good": good.report, "partialFailure": failed.report, "recovered": recovered.report,
            "partialFailureBuffersUnchanged": retainedBuffers,
            "partialFailurePixelsUnchanged": failed.pixels == good.pixels,
            "partialFailureAttachmentsUnchanged": failed.attachments == good.attachments,
            "partialFailureEvidenceUnchanged": retainedEvidence,
            "recoveryBuffersChanged": refreshedBuffers,
            "recoveryPixelsChanged": recovered.pixels != good.pixels,
            "recoveryAttachmentsChanged": recovered.attachments != good.attachments,
            "recoveryEvidenceChanged": refreshedEvidence,
        ]
        print(String(decoding: try JSONSerialization.data(withJSONObject: result,
            options: [.sortedKeys]), as: UTF8.self))
    }
}
'''


class PuppetBufferPublicationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        if not shutil.which("swiftc") or not shutil.which("xcrun"):
            raise unittest.SkipTest("Swift/Metal toolchain unavailable")
        with tempfile.TemporaryDirectory(prefix="mwx-puppet-publication-") as directory:
            root = Path(directory)
            source = root / "publication.swift"
            source.write_text(HARNESS, encoding="utf-8")
            air, library, binary = root / "image.air", root / "image.metallib", root / "publication"
            commands = [
                ["xcrun", "--sdk", "macosx", "metal", "-c",
                 str(SCENE_ROOT / "Rendering/Composition/SceneImageLayer.metal"), "-o", str(air)],
                ["xcrun", "--sdk", "macosx", "metallib", str(air), "-o", str(library)],
                ["swiftc", "-D", "DEBUG", *map(str, SWIFT_SOURCES),
                 *(str(SCENE_ROOT / path) for path in PLAYBACK_SOURCES),
                 str(source), "-o", str(binary)],
            ]
            for command in commands:
                run = subprocess.run(command, capture_output=True, text=True, timeout=120)
                if run.returncode:
                    raise RuntimeError(run.stdout + run.stderr)
            run = subprocess.run([str(binary), str(library)], capture_output=True,
                                 text=True, check=True, timeout=30)
            cls.result = json.loads(run.stdout)
        print(json.dumps(cls.result, sort_keys=True))

    def test_first_failed_pose_has_no_publication_or_direct_draw(self) -> None:
        failed = self.result["firstFailure"]
        self.assertFalse(failed["readyBefore"])
        self.assertFalse(failed["readyAfter"])
        self.assertFalse(failed["drew"])
        self.assertEqual(failed["draws"], 0)
        self.assertEqual(failed["litPixels"], 0)
        self.assertTrue(self.result["firstFailureBuffersUntouched"])
        self.assertTrue(self.result["firstFailureHasNoEvidence"])
        recovery = self.result["firstRecovery"]
        self.assertTrue(recovery["readyAfter"])
        self.assertTrue(recovery["drew"])
        self.assertGreater(recovery["litPixels"], 0)

    def test_later_partial_evaluation_retains_last_complete_pose(self) -> None:
        self.assertTrue(self.result["verifiedPartialWrite"])
        self.assertGreater(self.result["good"]["litPixels"], 0)
        failed = self.result["partialFailure"]
        self.assertTrue(failed["readyAfter"])
        self.assertTrue(failed["drew"])
        self.assertEqual(failed["draws"], 1)
        for field in ("Buffers", "Pixels", "Attachments", "Evidence"):
            with self.subTest(field=field):
                self.assertTrue(self.result[f"partialFailure{field}Unchanged"])

    def test_valid_frame_after_failure_replaces_the_retained_pose(self) -> None:
        recovered = self.result["recovered"]
        self.assertTrue(recovered["readyAfter"])
        self.assertTrue(recovered["drew"])
        self.assertEqual(recovered["draws"], 1)
        self.assertGreater(recovered["litPixels"], 0)
        for field in ("Buffers", "Pixels", "Attachments", "Evidence"):
            with self.subTest(field=field):
                self.assertTrue(self.result[f"recovery{field}Changed"])

    def test_new_command_buffer_requires_its_own_publication(self) -> None:
        for name in ("firstRecovery", "good", "partialFailure", "recovered"):
            with self.subTest(frame=name):
                self.assertFalse(self.result[name]["readyBefore"])
                self.assertTrue(self.result[name]["readyAfter"])
                self.assertFalse(self.result[name]["differentLiveCommandReady"])
                self.assertTrue(self.result[name]["previousCommandReleased"])


if __name__ == "__main__":
    unittest.main()
