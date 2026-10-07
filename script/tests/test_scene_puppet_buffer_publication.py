#!/usr/bin/env python3
"""Real Puppet playback publishes complete pose/coverage frames to Metal."""

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
    "Systems/Puppet/ScenePuppetAnimationPlaybackRuntime.swift",
    "Systems/Puppet/ScenePuppetAnimationControl.swift",
    "Systems/Puppet/ScenePuppetPlaybackState.swift",
    "Systems/Properties/ScenePuppetAnimationPropertyTarget.swift",
    "Rendering/Geometry/SceneGeometryProduct.swift",
    "Rendering/Frame/SceneSourceUpdateTransaction.swift",
    "Rendering/Metal/SceneMetalPipeline.swift",
    "Rendering/Composition/SceneBlendModeShaderSource.swift",
    "Rendering/Targets/SceneOffscreenResolutionPolicy.swift",
    "Diagnostics/ScenePerformanceCounterHub.swift",
]

HARNESS = r'''
import CryptoKit
import Foundation
import Metal
import simd

// These peripheral contracts supply immutable property snapshots and
// observe allocations/evidence. Playback, evaluation, publication, FIFO state,
// geometry encoding, the image pipeline and all Metal objects are production.
enum SceneDynamicTarget: Hashable {
    case scriptInstanceProperty(layerID: Int, path: [String])
}
enum SceneDynamicValue { case bool(Bool) }
struct SceneDynamicResolvedValue { let value: SceneDynamicValue }
struct SceneDynamicSnapshot {
    let frameIndex: UInt64
    let values: [SceneDynamicTarget: SceneDynamicResolvedValue]
    init(frameIndex: UInt64, values: [SceneDynamicTarget: SceneDynamicResolvedValue] = [:]) {
        self.frameIndex = frameIndex
        self.values = values
    }
    subscript(target: SceneDynamicTarget) -> SceneDynamicResolvedValue? { values[target] }
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
             wideVertex: Bool = false, alpha: [Float]? = nil,
             visibilityBinding: String? = nil)
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
        framesPerSecond: 1, frameCount: poses.count - 1, transformsByBone: [poses],
        alphaByBone: alpha.map { [$0] })
    let layer = ScenePuppetAnimationLayer(id: 1, animationID: 1, name: "publication",
        additive: true, blend: weight, blendIn: false, blendOut: false,
        blendTime: 0, rate: 1, visible: true, visibilityBinding: visibilityBinding)
    return (mesh, rig, .init(clips: [.init(layer: layer, animation: animation)],
                             composition: .layered))
}
func weightedFixture(alpha: [Float], weights: SIMD4<Float>)
    -> (SceneMdlPuppetMesh, SceneMdlPuppetRig, ScenePuppetAnimationSelection) {
    let base = fixture(poses: [pose(), pose()], weight: 1)
    // Every influence has a parent except the root. Exported alpha is already
    // inherited, so runtime parent multiplication would change the pixels.
    let rig = SceneMdlPuppetRig(bones: alpha.indices.map { index in
        .init(parentIndex: index - 1,
              bindLocalMatrixColumnMajor: columns(matrix_identity_float4x4))
    }, vertexWeights: base.0.vertices.map { _ in
        .init(boneIndices: SIMD4(0, 1, 2, 3), boneWeights: weights)
    })
    let animation = SceneMdlPuppetAnimation(id: 1, name: "coverage", mode: "single",
        framesPerSecond: 1, frameCount: 1,
        transformsByBone: alpha.map { _ in [pose(), pose()] },
        alphaByBone: alpha.map { [$0, $0] })
    return (base.0, rig, .init(clips: [.init(layer: base.2.clips[0].layer,
                                           animation: animation)], composition: .layered))
}
func pairedSelection(alpha: [Float]?, bothTracks: Bool)
    -> Result<ScenePuppetAnimationSelection?, ScenePuppetAnimationSelectionFailure> {
    let first = fixture(poses: [pose(), pose()], weight: 1, alpha: alpha).2.clips[0]
    let second = SceneMdlPuppetAnimation(id: 2, name: "second", mode: "single",
        framesPerSecond: 1, frameCount: 1, transformsByBone: first.animation.transformsByBone,
        alphaByBone: bothTracks ? first.animation.alphaByBone : nil)
    let secondLayer = ScenePuppetAnimationLayer(id: 2, animationID: 2, name: "second",
        additive: true, blend: 1, blendIn: false, blendOut: false,
        blendTime: 0, rate: 1, visible: true, visibilityBinding: nil)
    return ScenePuppetAnimationSelector.select(layers: [first.layer, secondLayer],
        animationSet: .init(boneCount: 1, animations: [first.animation, second]))
}
func selectionReport(_ result: Result<ScenePuppetAnimationSelection?, ScenePuppetAnimationSelectionFailure>)
    -> [String: Any] {
    switch result {
    case let .success(selection?): return ["state": "allowed", "clips": selection.clips.count]
    case .success(nil): return ["state": "inactive"]
    case .failure(.unsupportedLayer(_)): return ["state": "unsupported"]
    case let .failure(failure): return ["state": failure.description]
    }
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
         "draws": draws, "centerBGRA": Array(pixels[(16 * 32 + 16) * 4..<(16 * 32 + 17) * 4]),
         "litPixels": pixels.enumerated().filter {
             $0.offset % 4 == 3 && $0.element > 0
         }.count, "imageSHA256": SHA256.hash(data: Data(pixels)).map {
             String(format: "%02x", $0)
         }.joined()]
    }
}
func render(_ output: ScenePuppetPlaybackState.Output? = nil, sceneTime: Double,
            device: MTLDevice, queue: MTLCommandQueue, atlas: MTLTexture,
            animationFrame: ScenePuppetAnimationPlaybackRuntime.LayerFrame? = nil,
            mvp: simd_float4x4 = matrix_identity_float4x4,
            layerAlpha: Float = 1, clipVisible: Bool? = nil,
            ordinaryPipeline: SceneImageLayerPipeline? = nil,
            colorBlendState: SceneLayerColorBlendPipelineState? = nil,
            colorBlendMode: Int = 31) -> Frame {
    return autoreleasepool {
        let previousCommandReleased = Observation.previousCommand == nil
        let command = queue.makeCommandBuffer()!
        let transaction = SceneSourceUpdateTransaction()
        let readyBefore = output?.product.isPreparedForPublication(command) ?? false
        let values: [SceneDynamicTarget: SceneDynamicResolvedValue] = clipVisible.map {
            [ScenePuppetAnimationPropertyTarget.visibility(layerID: 42, animationLayerID: 1):
                .init(value: .bool($0))]
        } ?? [:]
        // Legacy publication fixtures supply a requested pose directly; the
        // shared-runtime integration case below supplies the launch's snapshot.
        let samples = animationFrame ?? .init(samples: output?.state.selection.clips.map { clip in
            let visible = clip.layer.visibilityBinding == nil ? clip.layer.visible == true : clipVisible == true
            return visible ? ScenePuppetAnimationEvaluator.frameSample(sceneTime: sceneTime,
                rate: clip.layer.rate ?? 1, animation: clip.animation) : nil
        } ?? [])
        let attachments = output?.state.encode(animationFrame: samples, sceneTime: sceneTime,
            dynamicValues: .init(frameIndex: UInt64(sceneTime * 10), values: values),
            commandBuffer: command, transaction: transaction) ?? [:]
        let readyAfter = output?.product.isPreparedForPublication(command) ?? false
        let differentLiveCommand = queue.makeCommandBuffer()!
        let differentLiveCommandReady = output?.product.isPreparedForPublication(differentLiveCommand) ?? false
        let target = texture(device, size: 32, renderTarget: true)
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = target
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0)
        let encoder = command.makeRenderCommandEncoder(descriptor: pass)!
        let uniforms = SceneLayerFragmentUniforms(time: Float(sceneTime), alpha: layerAlpha,
            dependencyBlendMode: 0, usesDependencyBlend: 0, cursorUV: .zero,
            sourceSampling: SIMD2(2, 0), tint: SIMD4(repeating: 1),
            textureFrame0: SIMD4(0, 0, 1, 0), textureFrame1: SIMD4(0, 1, 0, 0))
        let before = ScenePerformanceCounterHub.shared.snapshot()[.geometryDrawCalls]!
        // Invoke the real direct encoder even when publication is unavailable.
        let drew: Bool
        if let colorBlendState {
            let background = texture(device, size: 32)
            let backgroundPixels: [UInt8] = (0..<32 * 32).flatMap { _ in [16, 32, 48, 255] }
            backgroundPixels.withUnsafeBytes {
                background.replace(region: MTLRegionMake2D(0, 0, 32, 32), mipmapLevel: 0,
                    withBytes: $0.baseAddress!, bytesPerRow: 32 * 4)
            }
            // Exercise the exact alternate production fragment through the
            // geometry binder hook, with only fixed test uniforms/texture binds.
            let bind: SceneGeometryProduct.ColorBlendBinder = { encoder, source, matrix in
                var mvp = matrix
                var mode = Int32(colorBlendMode)
                encoder.setRenderPipelineState(colorBlendState.renderPipeline)
                encoder.setVertexBytes(&mvp, length: MemoryLayout<simd_float4x4>.size, index: 1)
                encoder.setFragmentBytes(&mode, length: MemoryLayout<Int32>.size, index: 0)
                encoder.setFragmentTexture(source, index: 0)
                encoder.setFragmentTexture(background, index: 1)
            }
            if let output {
                drew = output.product.encode(encoder, atlas, nil, mvp, uniforms, bind)
            } else {
                bind(encoder, atlas, mvp)
                SceneImageLayerPipeline.bindQuad(encoder: encoder)
                encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
                drew = true
            }
        } else if let output {
            drew = output.product.encode(encoder, atlas, nil, mvp, uniforms, nil)
        } else {
            let pipeline = ordinaryPipeline!
            pipeline.bind(encoder: encoder)
            pipeline.drawLayer(texture: atlas, mvp: mvp, uniforms: uniforms, encoder: encoder)
            drew = true
        }
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
            pose(translationX: 5e-25)], weight: 1e30, wideVertex: true,
            alpha: [1, 0.25, 1])
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

        // Premultiplied BGRA plus independent layer opacity makes missing or
        // repeated bone coverage observable in both color and alpha channels.
        let coloredAtlas = texture(device, size: 2)
        let coloredPixels: [UInt8] = (0..<4).flatMap { _ in [32, 64, 96, 128] }
        coloredPixels.withUnsafeBytes {
            coloredAtlas.replace(region: MTLRegionMake2D(0, 0, 2, 2), mipmapLevel: 0,
                withBytes: $0.baseAddress!, bytesPerRow: 2 * 4)
        }
        let ordinary = render(sceneTime: 0, device: device, queue: queue,
            atlas: coloredAtlas, layerAlpha: 0.5, ordinaryPipeline: pipeline)
        let opaque = try makePlayback(fixture(poses: [pose(), pose()], weight: 1),
            device: device, pipeline: pipeline, atlas: coloredAtlas)
        let absentAlpha = render(opaque, sceneTime: 0, device: device, queue: queue,
            atlas: coloredAtlas, layerAlpha: 0.5)
        let opaqueBuffers = bufferBytes(Observation.buffers)
        let absentAlphaLater = render(opaque, sceneTime: 1, device: device, queue: queue,
            atlas: coloredAtlas, layerAlpha: 0.5)
        let staticBuffersUnchanged = bufferBytes(Observation.buffers) == opaqueBuffers

        let alphaOnly = try makePlayback(fixture(poses: [pose(), pose()], weight: 1,
            alpha: [1, 0], visibilityBinding: "enabled"), device: device,
            pipeline: pipeline, atlas: coloredAtlas)
        let fullAlpha = render(alphaOnly, sceneTime: 0, device: device, queue: queue,
            atlas: coloredAtlas, layerAlpha: 0.5, clipVisible: true)
        let fullBuffers = bufferBytes(Observation.buffers)
        let halfAlpha = render(alphaOnly, sceneTime: 0.5, device: device, queue: queue,
            atlas: coloredAtlas, layerAlpha: 0.5, clipVisible: true)
        let halfBuffers = bufferBytes(Observation.buffers)
        let alphaOnlyBuffersChanged = halfBuffers != fullBuffers
        let halfAgain = render(alphaOnly, sceneTime: 0.5, device: device, queue: queue,
            atlas: coloredAtlas, layerAlpha: 0.5, clipVisible: true)
        let repeatedAlphaBuffersUnchanged = bufferBytes(Observation.buffers) == halfBuffers
        let zeroAlpha = render(alphaOnly, sceneTime: 1, device: device, queue: queue,
            atlas: coloredAtlas, layerAlpha: 0.5, clipVisible: true)
        let hiddenAlpha = render(alphaOnly, sceneTime: 1, device: device, queue: queue,
            atlas: coloredAtlas, layerAlpha: 0.5, clipVisible: false)
        let visibleAgain = render(alphaOnly, sceneTime: 1, device: device, queue: queue,
            atlas: coloredAtlas, layerAlpha: 0.5, clipVisible: true)
        let alphaOnlyAttachmentsUnchanged = [halfAlpha, halfAgain, zeroAlpha,
            hiddenAlpha, visibleAgain].allSatisfy { $0.attachments == fullAlpha.attachments }
        let alphaOnlyPositionsUnchanged = Observation.evidence.suffix(6).allSatisfy {
            $0 == [SIMD2<Float>(-0.5, -0.5), SIMD2<Float>(0.5, -0.5), SIMD2<Float>(0, 0.5)]
        }

        let mixed = try makePlayback(weightedFixture(alpha: [0, 1, 0, 0],
            weights: SIMD4(2, 2, 2, 2)), device: device, pipeline: pipeline,
            atlas: coloredAtlas)
        let mixedFrame = render(mixed, sceneTime: 0.5, device: device, queue: queue,
            atlas: coloredAtlas, layerAlpha: 0.5)
        let inherited = try makePlayback(weightedFixture(alpha: [0.5, 0.5, 0.5, 0.5],
            weights: SIMD4(0, 0, 0, 3)), device: device, pipeline: pipeline,
            atlas: coloredAtlas)
        let inheritedFrame = render(inherited, sceneTime: 0.5, device: device, queue: queue,
            atlas: coloredAtlas, layerAlpha: 0.5)
        let inheritedBuffers = bufferBytes(Observation.buffers)
        let inheritedLater = render(inherited, sceneTime: 1, device: device, queue: queue,
            atlas: coloredAtlas, layerAlpha: 0.5)
        let constantAlphaBuffersUnchanged = bufferBytes(Observation.buffers) == inheritedBuffers
        var blendedAlpha: [String: [String: Any]] = [:]
        for weight in [Double(0), 0.5, 2] {
            let output = try makePlayback(fixture(poses: [pose(), pose()], weight: weight,
                alpha: [0, 0]), device: device, pipeline: pipeline, atlas: coloredAtlas)
            blendedAlpha[String(weight)] = render(output, sceneTime: 0.5,
                device: device, queue: queue, atlas: coloredAtlas, layerAlpha: 0.5).report
        }

        let colorBlend = SceneLayerColorBlendPipelineState(device: device)!
        let ordinaryColorBlend = render(sceneTime: 0, device: device, queue: queue,
            atlas: coloredAtlas, colorBlendState: colorBlend)
        var colorBlendFrames: [String: [String: Any]] = [:]
        var colorBlendMultiplyFrames: [String: [String: Any]] = [:]
        for (name, time) in [("full", Double(0)), ("half", 0.5), ("zero", 1)] {
            colorBlendFrames[name] = render(alphaOnly, sceneTime: time, device: device,
                queue: queue, atlas: coloredAtlas, clipVisible: true,
                colorBlendState: colorBlend).report
            colorBlendMultiplyFrames[name] = render(alphaOnly, sceneTime: time,
                device: device, queue: queue, atlas: coloredAtlas, clipVisible: true,
                colorBlendState: colorBlend, colorBlendMode: 2).report
        }
        let oneOpaqueTrack = pairedSelection(alpha: [1, 1], bothTracks: false)
        let bothOpaqueTracks = pairedSelection(alpha: [1, 1], bothTracks: true)
        var opaqueMultiClipFrame: [String: Any] = [:]
        if case let .success(selection?) = bothOpaqueTracks {
            let base = fixture(poses: [pose(), pose()], weight: 1)
            let output = try makePlayback((base.0, base.1, selection),
                device: device, pipeline: pipeline, atlas: coloredAtlas)
            opaqueMultiClipFrame = render(output, sceneTime: 0.5, device: device,
                queue: queue, atlas: coloredAtlas, layerAlpha: 0.5).report
        }

        let sharedFixture = fixture(poses: [pose(), pose(translationX: 0.25)],
            weight: 1, alpha: [1, 0], visibilityBinding: "enabled")
        let sharedRuntime = ScenePuppetAnimationPlaybackRuntime()
        try sharedRuntime.register(layerID: 42, selection: sharedFixture.2,
            authoredLayers: sharedFixture.2.clips.map(\.layer)).get()
        func sharedFrame(_ index: UInt64, _ time: Double, _ visible: Bool)
            -> ScenePuppetAnimationPlaybackRuntime.LayerFrame {
            sharedRuntime.advance(frameIndex: index, sceneTime: time,
                dynamicValues: .init(frameIndex: index, values: [
                    ScenePuppetAnimationPropertyTarget.visibility(layerID: 42, animationLayerID: 1):
                        .init(value: .bool(visible))]))[42]!
        }
        let surfaceA = try makePlayback(sharedFixture, device: device, pipeline: pipeline, atlas: coloredAtlas)
        let startSamples = sharedFrame(0, 0, true)
        _ = render(surfaceA, sceneTime: 0, device: device, queue: queue, atlas: coloredAtlas,
            animationFrame: startSamples, layerAlpha: 0.5)
        _ = sharedFrame(1, 0.25, true)
        // No drawable or encode consumes these simulated cadences. Visibility
        // and position still progress at the shared simulation boundary.
        _ = sharedFrame(2, 0.5, false)
        let hiddenSamples = sharedFrame(3, 2, false)
        let hiddenShared = render(surfaceA, sceneTime: 2, device: device, queue: queue,
            atlas: coloredAtlas, animationFrame: hiddenSamples, layerAlpha: 0.5)
        let resumeSamples = sharedFrame(4, 2.25, true)
        surfaceA.state.advanceBonePhysics(animationFrame: resumeSamples, deltaTime: 0.25)
        let resumedPose = surfaceA.state.poseConfiguration(animationFrame: resumeSamples)!
        let resumedAttachments = surfaceA.state.prepareFrame(animationFrame: resumeSamples)
        let resumedA = render(surfaceA, sceneTime: 2.25, device: device, queue: queue,
            atlas: coloredAtlas, animationFrame: resumeSamples, layerAlpha: 0.5)
        // A second surface/rebuild registers the same definition without resetting.
        try sharedRuntime.register(layerID: 42, selection: sharedFixture.2,
            authoredLayers: sharedFixture.2.clips.map(\.layer)).get()
        let surfaceB = try makePlayback(sharedFixture, device: device, pipeline: pipeline, atlas: coloredAtlas)
        let duplicateSamples = sharedFrame(4, 200, false)
        let resumedB = render(surfaceB, sceneTime: 2.25, device: device, queue: queue,
            atlas: coloredAtlas, animationFrame: duplicateSamples, layerAlpha: 0.5)
        // Pause keeps identical sample indices; blend must still invalidate the
        // prepared geometry and update alpha in the actual Metal draw.
        let controlledFixture = fixture(poses: [pose(), pose()], weight: 1, alpha: [0.5, 0.5])
        let controlled = try makePlayback(controlledFixture, device: device,
            pipeline: pipeline, atlas: coloredAtlas)
        let controls = ScenePuppetAnimationPlaybackRuntime()
        try controls.register(layerID: 42, selection: controlledFixture.2,
            authoredLayers: controlledFixture.2.clips.map(\.layer)).get()
        let identity = ScenePuppetAnimationIdentity(layerID: 42,
            animationLayerIndex: 0, animationLayerID: 1)
        _ = controls.advance(frameIndex: 0, sceneTime: 0,
            dynamicValues: .init(frameIndex: 0, values: [:]))
        try controls.apply([
            .init(identity: identity, action: .pause, callbackEpoch: 1, ordinal: 0),
            .init(identity: identity, action: .setFrame(0), callbackEpoch: 1, ordinal: 1),
            .init(identity: identity, action: .setBlend(0.5), callbackEpoch: 1, ordinal: 2)
        ], frameIndex: 0).get()
        let halfBlend = controls.advance(frameIndex: 1, sceneTime: 1,
            dynamicValues: .init(frameIndex: 1, values: [:]))[42]!
        let dynamicHalfBlend = render(controlled, sceneTime: 1, device: device,
            queue: queue, atlas: coloredAtlas, animationFrame: halfBlend, layerAlpha: 0.5)
        try controls.apply([.init(identity: identity, action: .setBlend(1),
            callbackEpoch: 2, ordinal: 0)], frameIndex: 1).get()
        let fullBlend = controls.advance(frameIndex: 2, sceneTime: 2,
            dynamicValues: .init(frameIndex: 2, values: [:]))[42]!
        let dynamicFullBlend = render(controlled, sceneTime: 2, device: device,
            queue: queue, atlas: coloredAtlas, animationFrame: fullBlend, layerAlpha: 0.5)
        let result: [String: Any] = [
            "metalDevice": device.name,
            "dynamicHalfBlend": dynamicHalfBlend.report,
            "dynamicFullBlend": dynamicFullBlend.report,
            "dynamicBlendSamplesEqual": halfBlend.samples == fullBlend.samples,
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
            "quadVertexStride": MemoryLayout<SceneQuadVertex>.stride,
            "quadVertexDefaultCoverage": SceneQuadVertex(position: .zero, texcoord: .zero).vertexCoverage,
            "ordinaryQuad": ordinary.report, "absentAlpha": absentAlpha.report,
            "absentAlphaLater": absentAlphaLater.report,
            "staticBuffersUnchanged": staticBuffersUnchanged,
            "fullAlpha": fullAlpha.report, "halfAlpha": halfAlpha.report,
            "halfAlphaAgain": halfAgain.report, "zeroAlpha": zeroAlpha.report,
            "hiddenAlpha": hiddenAlpha.report, "visibleAgain": visibleAgain.report,
            "alphaOnlyBuffersChanged": alphaOnlyBuffersChanged,
            "repeatedAlphaBuffersUnchanged": repeatedAlphaBuffersUnchanged,
            "alphaOnlyAttachmentsUnchanged": alphaOnlyAttachmentsUnchanged,
            "alphaOnlyPositionsUnchanged": alphaOnlyPositionsUnchanged,
            "mixedWeights": mixedFrame.report, "inheritedAlpha": inheritedFrame.report,
            "inheritedAlphaLater": inheritedLater.report,
            "constantAlphaBuffersUnchanged": constantAlphaBuffersUnchanged,
            "blendedAlpha": blendedAlpha,
            "ordinaryColorBlend": ordinaryColorBlend.report,
            "colorBlendFrames": colorBlendFrames,
            "colorBlendMultiplyFrames": colorBlendMultiplyFrames,
            "oneOpaqueAlphaTrackSelection": selectionReport(oneOpaqueTrack),
            "bothOpaqueAlphaTracksSelection": selectionReport(bothOpaqueTracks),
            "opaqueMultiClipFrame": opaqueMultiClipFrame,
            "contributingAlphaMultiClipSelection": selectionReport(
                pairedSelection(alpha: [1, 0.5], bothTracks: false)),
            "sharedHidden": hiddenShared.report, "sharedResumedA": resumedA.report,
            "sharedResumedB": resumedB.report,
            "sharedResumedPoseX": resumedPose.bones.localMatrices[12],
            "sharedResumedAttachmentX": resumedAttachments["tip"]!.columns.3.x,
            "sharedSurfacePixelsMatch": resumedA.pixels == resumedB.pixels,
            "sharedSurfaceAttachmentsMatch": resumedA.attachments == resumedB.attachments,
        ]
        print(String(decoding: try JSONSerialization.data(withJSONObject: result,
            options: [.sortedKeys]), as: UTF8.self))
    }
}
'''


class PuppetBufferPublicationTests(unittest.TestCase):
    def test_paused_control_blend_reaches_actual_gpu_coverage(self):
        self.assertTrue(self.result["dynamicBlendSamplesEqual"])
        half = self.result["dynamicHalfBlend"]
        full = self.result["dynamicFullBlend"]
        self.assertTrue(half["drew"] and full["drew"])
        self.assertNotEqual(half["imageSHA256"], full["imageSHA256"])
        # Atlas alpha .5 × layer .5 × coverage (.75 versus .5).
        self.assertAlmostEqual(half["centerBGRA"][3], 48, delta=1)
        self.assertAlmostEqual(full["centerBGRA"][3], 32, delta=1)

    @classmethod
    def setUpClass(cls) -> None:
        if not shutil.which("swiftc") or not shutil.which("xcrun"):
            raise unittest.SkipTest("Swift/Metal toolchain unavailable")
        with tempfile.TemporaryDirectory(prefix="mwx-puppet-publication-") as directory:
            root = Path(directory)
            source = root / "publication.swift"
            source.write_text(HARNESS, encoding="utf-8")
            # Compile the exact production shader/state prefix. The subsequent
            # broad renderer owns framebuffer routing, which this focused GPU
            # test does not need to replace with stub scene/graph contracts.
            color_blend = root / "color_blend.swift"
            color_blend_prefix, _ = (
                SCENE_ROOT / "Rendering/Composition/SceneLayerColorBlendPipeline.swift"
            ).read_text(encoding="utf-8").split("final class SceneLayerColorBlendPipeline {", 1)
            color_blend.write_text(color_blend_prefix, encoding="utf-8")
            air, library, binary = root / "image.air", root / "image.metallib", root / "publication"
            commands = [
                ["xcrun", "--sdk", "macosx", "metal", "-c",
                 str(SCENE_ROOT / "Rendering/Composition/SceneImageLayer.metal"), "-o", str(air)],
                ["xcrun", "--sdk", "macosx", "metallib", str(air), "-o", str(library)],
                ["swiftc", "-D", "DEBUG", *map(str, SWIFT_SOURCES),
                 *(str(SCENE_ROOT / path) for path in PLAYBACK_SOURCES),
                 str(color_blend), str(source), "-o", str(binary)],
            ]
            for command in commands:
                run = subprocess.run(command, capture_output=True, text=True, timeout=120)
                if run.returncode:
                    raise RuntimeError(run.stdout + run.stderr)
            run = subprocess.run([str(binary), str(library)], capture_output=True,
                                 text=True, check=True, timeout=30)
            cls.result = json.loads(run.stdout)
        print(json.dumps(cls.result, sort_keys=True))

    def assert_center_bgra(self, frame: dict, expected: list[int]) -> None:
        self.assertTrue(frame["drew"])
        self.assertEqual(len(frame["centerBGRA"]), 4)
        for channel, (actual, wanted) in enumerate(zip(frame["centerBGRA"], expected)):
            with self.subTest(channel=channel):
                self.assertAlmostEqual(actual, wanted, delta=1)

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

    def test_shared_vertex_abi_and_ordinary_quad_keep_opaque_coverage(self) -> None:
        self.assertEqual(self.result["quadVertexStride"], 24)
        self.assertEqual(self.result["quadVertexDefaultCoverage"], 1)
        for name in ("ordinaryQuad", "absentAlpha", "absentAlphaLater"):
            with self.subTest(frame=name):
                self.assert_center_bgra(self.result[name], [16, 32, 48, 64])
        self.assertTrue(self.result["staticBuffersUnchanged"])

    def test_alpha_only_animation_samples_coverage_and_changes_color_once(self) -> None:
        # Color atlas [32,64,96,128] × layer alpha .5 × interpolated bone alpha.
        for name, expected in (
            ("fullAlpha", [16, 32, 48, 64]),
            ("halfAlpha", [8, 16, 24, 32]),
            ("zeroAlpha", [0, 0, 0, 0]),
        ):
            with self.subTest(frame=name):
                self.assert_center_bgra(self.result[name], expected)
                self.assertTrue(self.result[name]["readyAfter"])
        self.assertTrue(self.result["alphaOnlyBuffersChanged"])
        self.assertTrue(self.result["alphaOnlyPositionsUnchanged"])
        self.assertTrue(self.result["alphaOnlyAttachmentsUnchanged"])
        self.assertEqual(self.result["zeroAlpha"]["litPixels"], 0)

    def test_repeated_or_constant_alpha_does_not_republish_vertex_bytes(self) -> None:
        self.assertTrue(self.result["repeatedAlphaBuffersUnchanged"])
        self.assertEqual(self.result["halfAlphaAgain"]["imageSHA256"],
                         self.result["halfAlpha"]["imageSHA256"])
        self.assertTrue(self.result["constantAlphaBuffersUnchanged"])
        self.assert_center_bgra(self.result["inheritedAlphaLater"], [8, 16, 24, 32])

    def test_hidden_clip_restores_default_coverage_and_reactivation_resamples(self) -> None:
        self.assert_center_bgra(self.result["hiddenAlpha"], [16, 32, 48, 64])
        self.assert_center_bgra(self.result["visibleAgain"], [0, 0, 0, 0])
        self.assertEqual(self.result["hiddenAlpha"]["imageSHA256"],
                         self.result["fullAlpha"]["imageSHA256"])
        self.assertEqual(self.result["visibleAgain"]["imageSHA256"],
                         self.result["zeroAlpha"]["imageSHA256"])

    def test_normalized_four_bone_weights_mix_exported_alpha_without_parent_product(self) -> None:
        # Non-unit authored weights [2,2,2,2] normalize to quarters; only bone 1 is opaque.
        self.assert_center_bgra(self.result["mixedWeights"], [4, 8, 12, 16])
        # A full-weight fourth-level child keeps exported .5, not .5 to the fourth power.
        self.assert_center_bgra(self.result["inheritedAlpha"], [8, 16, 24, 32])

    def test_static_clip_blend_weights_alpha_from_opaque_and_clamps_coverage(self) -> None:
        for weight, expected in (
            ("0.0", [16, 32, 48, 64]),
            ("0.5", [8, 16, 24, 32]),
            ("2.0", [0, 0, 0, 0]),
        ):
            with self.subTest(weight=weight):
                self.assert_center_bgra(self.result["blendedAlpha"][weight], expected)

    def test_color_blend_fragment_consumes_puppet_coverage_before_unpremultiplying(self) -> None:
        # Additive mode31 adds premultiplied source RGB to [16,32,48],
        # while preserving the framebuffer alpha of 255.
        for name, expected in (
            ("full", [48, 96, 144, 255]),
            ("half", [32, 64, 96, 255]),
            ("zero", [16, 32, 48, 255]),
        ):
            with self.subTest(frame=name):
                self.assert_center_bgra(self.result["colorBlendFrames"][name], expected)
        self.assert_center_bgra(self.result["ordinaryColorBlend"], [48, 96, 144, 255])
        # Multiply mode2 distinguishes scaling only RGB or only alpha from
        # scaling both before unpremultiplication: base × (1 - alpha + premultRGB).
        for name, expected in (
            ("full", [10, 24, 42, 255]),
            ("half", [13, 28, 45, 255]),
            ("zero", [16, 32, 48, 255]),
        ):
            with self.subTest(multiply_frame=name):
                self.assert_center_bgra(self.result["colorBlendMultiplyFrames"][name], expected)

    def test_multi_clip_alpha_rejects_contribution_but_accepts_opaque_tracks(self) -> None:
        for name in ("oneOpaqueAlphaTrackSelection", "bothOpaqueAlphaTracksSelection"):
            with self.subTest(selection=name):
                self.assertEqual(self.result[name], {"state": "allowed", "clips": 2})
        self.assert_center_bgra(self.result["opaqueMultiClipFrame"], [16, 32, 48, 64])
        self.assertEqual(self.result["contributingAlphaMultiClipSelection"],
                         {"state": "unsupported"})

    def test_shared_hidden_resume_keeps_pose_alpha_and_two_surfaces_on_one_sample(self) -> None:
        self.assert_center_bgra(self.result["sharedHidden"], [16, 32, 48, 64])
        for name in ("sharedResumedA", "sharedResumedB"):
            with self.subTest(surface=name):
                self.assert_center_bgra(self.result[name], [8, 16, 24, 32])
        self.assertAlmostEqual(self.result["sharedResumedPoseX"], 0.125)
        self.assertAlmostEqual(self.result["sharedResumedAttachmentX"], 0.125)
        self.assertTrue(self.result["sharedSurfacePixelsMatch"])
        self.assertTrue(self.result["sharedSurfaceAttachmentsMatch"])


if __name__ == "__main__":
    unittest.main()
