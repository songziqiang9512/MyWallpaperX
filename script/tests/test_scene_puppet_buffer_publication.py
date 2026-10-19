#!/usr/bin/env python3
"""Real Puppet playback publishes complete pose/coverage frames to Metal."""

from __future__ import annotations

import json
import hashlib
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

from script.tests.test_scene_puppet_playback import SCENE_ROOT, SWIFT_SOURCES
from script.tests.test_scene_puppet_direct_playback import EXTRA_SOURCES, PIPELINE, static_model_carrier_source, puppet_bone_evidence_leaf_source
FOG_HEADER = SCENE_ROOT / "Rendering/Composition/SceneDistanceFog.metalh"


PLAYBACK_SOURCES = [
    "Runtime/Frame/SceneMaterialRenderState.swift",
    "Format/SceneMdlPuppetAttachmentReader.swift",
    "Systems/Puppet/ScenePuppetAttachmentPoseProjection.swift",
    "Systems/Puppet/ScenePuppetTranslationMotion.swift",
    "Systems/Puppet/ScenePuppetAnimationPlaybackRuntime.swift",
    "Systems/Puppet/ScenePuppetAnimationControl.swift",
    "Systems/Puppet/ScenePuppetClipping.swift",
    "Systems/Puppet/ScenePuppetPlaybackState.swift",
    "Systems/Properties/ScenePuppetAnimationPropertyTarget.swift",
    "Rendering/Geometry/SceneGeometryProduct.swift",
    "Rendering/Frame/SceneSourceUpdateTransaction.swift",
    "Rendering/Metal/SceneMetalPipeline.swift",
    "Rendering/Composition/SceneBlendModeShaderSource.swift",
    "Rendering/Targets/SceneOffscreenResolutionPolicy.swift",
    "Diagnostics/ScenePerformanceCounterHub.swift",
]

PLAYBACK_SOURCES += [item for item in EXTRA_SOURCES if item not in PLAYBACK_SOURCES and SCENE_ROOT / item not in SWIFT_SOURCES]
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
// This gate does not test optional GPU stage timing. Keep that diagnostic
// disabled at the external observation boundary; all geometry, publication,
// native encoder creation, draw commands and GPU completion remain real.
enum SceneGPUStageTimestampHook {
    static func render(_ commandBuffer: MTLCommandBuffer,
                       _ descriptor: MTLRenderPassDescriptor,
                       role: String) -> MTLRenderCommandEncoder? {
        commandBuffer.makeRenderCommandEncoder(descriptor: descriptor)
    }
    static func drew(_ encoder: MTLRenderCommandEncoder) {}
}
extension MTLDevice {
    func makeSceneBuffer(length: Int, options: MTLResourceOptions = []) -> MTLBuffer? {
        guard let buffer = makeBuffer(length: length, options: options.union(.storageModeShared)) else {
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
func pairedClips(alpha: [Float]?, peer: [Float]?, additive: [Bool] = [true, true],
                 optionalPeer: Bool = false, boundPeer: Bool = false,
                 renamed: Bool = false, peerShift: Float = 0)
    -> [ScenePuppetAnimationSelection.Clip] {
    [alpha, peer].enumerated().map { index, track in
        let id = (renamed ? 91 : 1) + index
        let sample = pose(translationX: index == 1 ? peerShift : 0)
        let name = "\(renamed ? "renamed" : "coverage")-\(id)"
        let animation = SceneMdlPuppetAnimation(id: id, name: name, mode: "single",
            framesPerSecond: 1, frameCount: 1, transformsByBone: [[sample, sample]],
            alphaByBone: track.map { [$0] })
        let layer = ScenePuppetAnimationLayer(id: id, animationID: id, name: name,
            additive: additive[index], blend: 1, blendIn: false, blendOut: false,
            blendTime: 0, rate: 1, visible: index == 0 || !optionalPeer,
            visibilityBinding: index == 1 && boundPeer ? "peer" : nil,
            hasVisibilityScript: index == 1 && optionalPeer ? true : nil)
        return .init(layer: layer, animation: animation)
    }
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
                var mode = SIMD2<UInt32>(UInt32(colorBlendMode), 0)
                var distanceFog = SceneImageDistanceFogUniforms()
                encoder.setRenderPipelineState(colorBlendState.renderPipeline)
                encoder.setVertexBytes(&mvp, length: MemoryLayout<simd_float4x4>.size, index: 1)
                encoder.setFragmentBytes(&mode, length: MemoryLayout<SIMD2<UInt32>>.size, index: 0)
                encoder.setFragmentBytes(&distanceFog,
                    length: MemoryLayout<SceneImageDistanceFogUniforms>.stride, index: 2)
                encoder.setFragmentTexture(source, index: 0)
                encoder.setFragmentTexture(background, index: 1)
                SceneImageLayerPipeline.bindClipMask(encoder: encoder, texture: source)
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

func multiAlphaChecks(device: MTLDevice, queue: MTLCommandQueue,
                      pipeline: SceneImageLayerPipeline, atlas: MTLTexture) throws -> [String: Any] {
    let base = fixture(poses: [pose(), pose()], weight: 1)
    func select(_ clips: [ScenePuppetAnimationSelection.Clip])
        -> Result<ScenePuppetAnimationSelection?, ScenePuppetAnimationSelectionFailure> {
        ScenePuppetAnimationSelector.select(layers: clips.map(\.layer),
            animationSet: .init(boneCount: 1, animations: clips.map(\.animation)))
    }
    func record(_ clips: [ScenePuppetAnimationSelection.Clip]) throws -> [String: Any] {
        let result = select(clips)
        var row: [String: Any] = ["selection": selectionReport(result),
            "authoredOrder": clips.map { $0.animation.id }]
        if case let .success(selection?) = result {
            row["clipOrder"] = selection.clips.map { $0.animation.id }
            let output = try makePlayback((base.0, base.1, selection), device: device,
                pipeline: pipeline, atlas: atlas)
            let frame = render(output, sceneTime: 0.5, device: device, queue: queue,
                atlas: atlas, layerAlpha: 0.5)
            row["frame"] = frame.report
            row["attachmentX"] = frame.attachments["tip"]!.columns.3.x
        }
        return row
    }
    var allowed: [[String: Any]] = []
    // Equal coverage for opaque/additive variants uses identity contributor TRS;
    // the neutral peer's independent translation must still reach the attachment.
    let cases: [([Float]?, [Bool])] = [(nil, [true, true]), ([1, 1], [false, false]),
        (nil, [false, true]), ([1, 1], [true, false])]
    for (peer, flags) in cases {
        for reverse in [false, true] {
            let clips = pairedClips(alpha: [1, 0.5], peer: peer, additive: flags,
                renamed: reverse, peerShift: 0.125)
            allowed.append(try record(reverse ? Array(clips.reversed()) : clips))
        }
    }
    let opaque = try [record(pairedClips(alpha: [1, 1], peer: nil)),
                      record(pairedClips(alpha: [1, 1], peer: [1, 1]))]
    let optional = try record(pairedClips(alpha: [1, 0.5], peer: [0.5, 0.5], optionalPeer: true))
    let bound = select(pairedClips(alpha: [1, 0.5], peer: [0.5, 0.5], optionalPeer: true, boundPeer: true))
    let near = select(pairedClips(alpha: [1, 0.5], peer: [1, Float(1).nextDown]))
    let conflicting = pairedClips(alpha: [1, 0.5], peer: [0.5, 0.5])
    let manual = try makePlayback((base.0, base.1, .init(clips: conflicting, composition: .layered)),
        device: device, pipeline: pipeline, atlas: atlas)
    let manualFrame = render(manual, sceneTime: 0.5, device: device, queue: queue, atlas: atlas)
    let clips = pairedClips(alpha: [1, 0.5], peer: [1, 1])
    let output = try makePlayback((base.0, base.1, try select(clips).get()!),
        device: device, pipeline: pipeline, atlas: atlas)
    let sample = ScenePuppetAnimationEvaluator.FrameSample(frameA: 0, frameB: 1, fraction: 0.5)
    let hidden = render(output, sceneTime: 0.5, device: device, queue: queue, atlas: atlas,
        animationFrame: .init(samples: [nil, sample]), layerAlpha: 0.5)
    let restored = render(output, sceneTime: 0.5, device: device, queue: queue, atlas: atlas,
        animationFrame: .init(samples: [sample, sample]), layerAlpha: 0.5)
    return ["allowed": allowed, "opaque": opaque, "optional": optional,
        "bound": selectionReport(bound), "nearOne": selectionReport(near),
        "twoContributors": selectionReport(select(conflicting)), "manual": manualFrame.report,
        "hidden": hidden.report, "restored": restored.report]
}

func translationPoseChecks(device: MTLDevice, queue: MTLCommandQueue,
                           pipeline: SceneImageLayerPipeline, atlas: MTLTexture) throws -> [String: Any] {
    let base = fixture(poses: [pose(translationX: 0.1), pose(translationX: 0.1)], weight: 1)
    let rig = SceneMdlPuppetRig(bones: [.init(parentIndex: -1,
        bindLocalMatrixColumnMajor: columns(matrix_identity_float4x4),
        translationPhysics: .init(spring: true, stiffness: 70, friction: 5,
            inertia: 5, maxDistance: 50))], vertexWeights: base.1.vertexWeights)
    let samples = ScenePuppetAnimationPlaybackRuntime.LayerFrame(samples: [.init(frameA: 0, frameB: 0)])
    let physical = try makePlayback((base.0, rig, base.2), device: device, pipeline: pipeline, atlas: atlas)
    var written = matrix_identity_float4x4
    written.columns.0.x = 0.8; written.columns.1.y = 0.9; written.columns.3.x = 0.35
    let mutation = SceneScriptPuppetBoneMutation(layerID: 42, boneIndex: 0,
        matrix: columns(written).map(Double.init))
    func configuration(_ state: ScenePuppetPlaybackState) -> [String: Any] {
        let pose = state.poseConfiguration(animationFrame: samples)!
        let basis = (0..<16).filter { !(12...14).contains($0) }
        return ["queryX": pose.queryLocalMatrices[12], "renderX": pose.bones.localMatrices[12],
            "worldX": pose.bones.worldMatrices[12],
            "queryBasis": basis.map { pose.queryLocalMatrices[$0] },
            "renderBasis": basis.map { pose.bones.localMatrices[$0] },
            "attachmentX": pose.attachmentFrames["tip"]!.columns.3.x]
    }
    func positions() -> [[Float]] { Observation.evidence.last!.map { [$0.x, $0.y] } }
    physical.state.advanceBonePhysics(animationFrame: samples, deltaTime: 1.0 / 30, frameIndex: 10)
    physical.state.apply(scriptBoneMutations: [mutation])
    let firstPose = configuration(physical.state)
    let first = render(physical, sceneTime: 1, device: device, queue: queue, atlas: atlas,
        animationFrame: samples)
    let firstPositions = positions()
    // A second surface/publication of this cadence cannot consume the overlay
    // or integrate another physical step, even with a different requested dt.
    physical.state.advanceBonePhysics(animationFrame: samples, deltaTime: 0.25, frameIndex: 10)
    let samePose = configuration(physical.state)
    let same = render(physical, sceneTime: 1, device: device, queue: queue, atlas: atlas,
        animationFrame: samples)
    let samePositions = positions()
    physical.state.advanceBonePhysics(animationFrame: samples, deltaTime: 0.05, frameIndex: 11)
    let nextPose = configuration(physical.state)
    let next = render(physical, sceneTime: 1.1, device: device, queue: queue, atlas: atlas,
        animationFrame: samples)
    let nextPositions = positions()
    physical.state.advanceBonePhysics(animationFrame: samples, deltaTime: 0.25, frameIndex: 11)
    let nextAgainPose = configuration(physical.state)
    for cadence in UInt64(12)...15 {
        physical.state.advanceBonePhysics(animationFrame: samples, deltaTime: 0.05, frameIndex: cadence)
    }
    let laterPose = configuration(physical.state)
    let later = render(physical, sceneTime: 1.5, device: device, queue: queue, atlas: atlas,
        animationFrame: samples)
    let laterPositions = positions()
    let ordinary = try makePlayback(base, device: device, pipeline: pipeline, atlas: atlas)
    ordinary.state.advanceBonePhysics(animationFrame: samples, deltaTime: 0.05, frameIndex: 10)
    ordinary.state.apply(scriptBoneMutations: [mutation])
    let ordinaryFirstPose = configuration(ordinary.state)
    let ordinaryFirst = render(ordinary, sceneTime: 1, device: device, queue: queue, atlas: atlas,
        animationFrame: samples)
    ordinary.state.advanceBonePhysics(animationFrame: samples, deltaTime: 0.25, frameIndex: 11)
    let ordinaryNextPose = configuration(ordinary.state)
    let ordinaryNext = render(ordinary, sceneTime: 1.1, device: device, queue: queue, atlas: atlas,
        animationFrame: samples)
    return ["firstPose": firstPose, "samePose": samePose, "nextPose": nextPose,
        "nextAgainPose": nextAgainPose, "laterPose": laterPose,
        "first": first.report, "same": same.report, "next": next.report, "later": later.report,
        "firstPositions": firstPositions, "samePositions": samePositions,
        "nextPositions": nextPositions, "laterPositions": laterPositions,
        "ordinaryFirstPose": ordinaryFirstPose, "ordinaryNextPose": ordinaryNextPose,
        "ordinaryFirst": ordinaryFirst.report, "ordinaryNext": ordinaryNext.report]
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
        let validityFixture = fixture(poses: [pose(), pose(scale: 0)], weight: 1, alpha: [1, 0])
        let validity = try makePlayback(validityFixture, device: device,
                                        pipeline: pipeline, atlas: atlas)
        let initialBuffers = bufferBytes(Observation.buffers)
        let firstFailure = render(validity, sceneTime: 1, device: device, queue: queue, atlas: atlas,
            animationFrame: .init(samples: [.init(frameA: 2, frameB: 2)]))
        let rejectedEvidence = Observation.evidence.isEmpty
        let rejectedBuffers = bufferBytes(Observation.buffers) == initialBuffers
        let firstRecovery = render(validity, sceneTime: 0, device: device, queue: queue, atlas: atlas)
        let collapsed = render(validity, sceneTime: 1, device: device, queue: queue, atlas: atlas)
        let collapseRecovery = render(validity, sceneTime: 0, device: device, queue: queue, atlas: atlas)

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

        let fogSource = try String(contentsOfFile: CommandLine.arguments[2], encoding: .utf8)
        let colorBlend = SceneLayerColorBlendPipelineState(device: device, fogShaderSource: fogSource)!
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
        let multiAlpha = try multiAlphaChecks(device: device, queue: queue,
            pipeline: pipeline, atlas: coloredAtlas)

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
        surfaceA.state.advanceBonePhysics(animationFrame: resumeSamples, deltaTime: 0.25, frameIndex: 4)
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
        let controlledBase = fixture(poses: [pose(), pose()], weight: 1)
        let controlledFixture = (controlledBase.0, controlledBase.1,
            ScenePuppetAnimationSelection(clips: pairedClips(alpha: [0.5, 0.5], peer: [1, 1]), composition: .layered))
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
        let dynamicHalfBuffers = bufferBytes(Observation.buffers)
        try controls.apply([.init(identity: identity, action: .setBlend(1),
            callbackEpoch: 2, ordinal: 0)], frameIndex: 1).get()
        let fullBlend = controls.advance(frameIndex: 2, sceneTime: 2,
            dynamicValues: .init(frameIndex: 2, values: [:]))[42]!
        let dynamicFullBlend = render(controlled, sceneTime: 2, device: device,
            queue: queue, atlas: coloredAtlas, animationFrame: fullBlend, layerAlpha: 0.5)
        let dynamicBlendBuffersChanged = dynamicHalfBuffers != bufferBytes(Observation.buffers)
        let queryRenderTranslation = try translationPoseChecks(device: device, queue: queue,
            pipeline: pipeline, atlas: atlas)
        let result: [String: Any] = [
            "queryRenderTranslation": queryRenderTranslation,
            "metalDevice": device.name,
            "dynamicHalfBlend": dynamicHalfBlend.report,
            "dynamicFullBlend": dynamicFullBlend.report,
            "dynamicBlendSamplesEqual": halfBlend.samples == fullBlend.samples,
            "dynamicBlendBuffersChanged": dynamicBlendBuffersChanged,
            "firstFailure": firstFailure.report, "firstRecovery": firstRecovery.report,
            "collapsed": collapsed.report, "collapseRecovery": collapseRecovery.report,
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
            "multiAlpha": multiAlpha,
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
''' + puppet_bone_evidence_leaf_source()


class PuppetBufferPublicationTests(unittest.TestCase):
    def test_translation_query_overlay_expires_once_per_cadence_while_render_rebounds(self):
        facts = self.result["queryRenderTranslation"]
        first, next_pose, later = (facts[key] for key in ("firstPose", "nextPose", "laterPose"))
        self.assertAlmostEqual(first["queryX"], 0.35, places=6)
        self.assertAlmostEqual(first["renderX"], 0.35, places=6)
        self.assertEqual(facts["samePose"], first)
        self.assertEqual(facts["nextAgainPose"], next_pose)
        self.assertEqual(facts["samePositions"], facts["firstPositions"])
        self.assertEqual(facts["same"]["imageSHA256"], facts["first"]["imageSHA256"])
        self.assertAlmostEqual(next_pose["queryX"], 0.1, places=6)
        self.assertAlmostEqual(later["queryX"], 0.1, places=6)
        self.assertGreater(next_pose["renderX"], next_pose["queryX"])
        self.assertLess(next_pose["renderX"], first["renderX"])
        self.assertNotEqual(later["renderX"], next_pose["renderX"])
        for pose_name in ("firstPose", "nextPose", "laterPose"):
            pose = facts[pose_name]
            with self.subTest(pose=pose_name):
                self.assertEqual(pose["queryBasis"], first["queryBasis"])
                self.assertEqual(pose["renderBasis"], first["renderBasis"])
                self.assertEqual(pose["queryBasis"], pose["renderBasis"])
                self.assertAlmostEqual(pose["worldX"], pose["renderX"], places=6)
                self.assertAlmostEqual(pose["attachmentX"], pose["renderX"], places=6)
        self.assertNotEqual(facts["firstPositions"], facts["nextPositions"])
        self.assertNotEqual(facts["nextPositions"], facts["laterPositions"])
        # Every vertex moves by the physical root's displacement, while local
        # query translation has already returned to the nonzero animation base.
        delta = next_pose["renderX"] - first["renderX"]
        for before, after in zip(facts["firstPositions"], facts["nextPositions"]):
            self.assertAlmostEqual(after[0] - before[0], delta, places=6)
            self.assertAlmostEqual(after[1], before[1], places=6)
        self.assertNotEqual(facts["first"]["imageSHA256"], facts["later"]["imageSHA256"])
        for name in ("first", "same", "next", "later"):
            frame = facts[name]
            with self.subTest(gpu_frame=name):
                self.assertTrue(frame["readyAfter"] and frame["drew"])
                self.assertEqual(frame["draws"], 1)
                self.assertGreater(frame["litPixels"], 0)

    def test_nonphysical_bone_keeps_prior_setter_translation_across_cadences(self):
        facts = self.result["queryRenderTranslation"]
        self.assertEqual(facts["ordinaryFirstPose"], facts["ordinaryNextPose"])
        self.assertAlmostEqual(facts["ordinaryNextPose"]["queryX"], 0.35, places=6)
        self.assertAlmostEqual(facts["ordinaryNextPose"]["renderX"], 0.35, places=6)
        self.assertEqual(facts["ordinaryFirst"]["imageSHA256"], facts["ordinaryNext"]["imageSHA256"])

    def test_paused_control_blend_reaches_actual_gpu_coverage(self):
        self.assertTrue(self.result["dynamicBlendSamplesEqual"])
        self.assertTrue(self.result["dynamicBlendBuffersChanged"])
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
            identity_paths = [Path(__file__), PIPELINE, Path(static_model_carrier_source.__code__.co_filename), *SWIFT_SOURCES,
                *(SCENE_ROOT / path for path in PLAYBACK_SOURCES), FOG_HEADER,
                SCENE_ROOT / "Rendering/Composition/SceneLayerColorBlendPipeline.swift",
                SCENE_ROOT / "Rendering/Composition/SceneImageLayer.metal"]
            identity = {str(path): hashlib.sha256(path.read_bytes()).hexdigest() for path in identity_paths}
            source = root / "publication.swift"
            source.write_text(HARNESS + static_model_carrier_source(), encoding="utf-8")
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
            run = subprocess.run([str(binary), str(library), str(FOG_HEADER)], capture_output=True,
                                 text=True, timeout=30)
            if run.returncode:
                raise RuntimeError(f"Puppet publication GPU harness exit {run.returncode}:\n"
                                   + run.stdout + run.stderr)
            if identity != {str(path): hashlib.sha256(path.read_bytes()).hexdigest() for path in identity_paths}:
                raise RuntimeError("product source or Fog header changed during GPU gate")
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

    def test_finite_collapsed_pose_is_published_and_restores_opaque_geometry(self):
        for name in ("collapsed", "collapseRecovery"):
            frame = self.result[name]
            self.assertTrue(frame["readyAfter"] and frame["drew"])
            self.assertEqual(frame["draws"], 1)
        self.assertEqual(self.result["collapsed"]["litPixels"], 0)
        self.assertEqual(self.result["collapseRecovery"]["imageSHA256"],
                         self.result["firstRecovery"]["imageSHA256"])

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

    def test_one_alpha_contributor_preserves_neutral_peers_and_actual_gpu_coverage(self):
        facts = self.result["multiAlpha"]
        for family, expected in (("allowed", [12, 24, 36, 48]), ("opaque", [16, 32, 48, 64])):
            for row in facts[family]:
                with self.subTest(family=family, order=row["authoredOrder"]):
                    self.assertEqual(row["selection"], {"state": "allowed", "clips": 2})
                    self.assertEqual(row["clipOrder"], row["authoredOrder"])
                    self.assert_center_bgra(row["frame"], expected)
        for row in facts["allowed"]:
            self.assertAlmostEqual(row["attachmentX"], 0.125, places=6)
        self.assertEqual(facts["optional"]["selection"], {"state": "allowed", "clips": 1})
        self.assert_center_bgra(facts["optional"]["frame"], [12, 24, 36, 48])
        self.assert_center_bgra(facts["hidden"], [16, 32, 48, 64])
        self.assert_center_bgra(facts["restored"], [12, 24, 36, 48])

    def test_two_alpha_contributors_and_near_one_peer_remain_rejected(self):
        facts = self.result["multiAlpha"]
        for name in ("twoContributors", "nearOne", "bound"):
            self.assertEqual(facts[name], {"state": "unsupported"})
        self.assertFalse(facts["manual"]["readyAfter"])
        self.assertFalse(facts["manual"]["drew"])
        self.assertEqual(facts["manual"]["draws"], 0)
        self.assertEqual(facts["manual"]["litPixels"], 0)

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
