#!/usr/bin/env python3

from __future__ import annotations

import json
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
RUNTIME_SOURCE = (
    REPOSITORY_ROOT
    / "MyWallpaperX/Core/SteamWorkshopScene/RenderGraph/LayerDependencies"
    / "SceneDependencyFrameRuntime.swift"
)


HARNESS_SOURCE = r'''
import CoreGraphics
import Foundation
import Metal
import simd

struct SceneEffectPassSlot: Hashable {
    let effectID: String
    let passIndex: Int
    let slotIndex: Int
}

struct SceneNamedTextureReference: Hashable {
    enum Variant: Hashable { case primary }
    let providerLayerID: Int
    let variant: Variant
}

struct SceneAuthoredEffectRenderPlan {
    struct EffectKey: Hashable {
        let layerID: Int
        let effectIndex: Int
        let descriptorID: String
    }
}

struct SceneUtilityLayer {
    enum Kind { case composition }
    let kind: Kind
}

struct SceneRenderDescriptor {
    struct Layer {
        let id: Int
        let contentKind: String
        let utilityLayer: SceneUtilityLayer?
        let alpha: Double?
        let colorRGB: [Double]?
    }

    let layers: [Layer]
    let bindings: [Int: SceneDependencyRenderPlan.Binding]
    let graphOutputProviderLayerIDs: Set<Int>
}

struct SceneDependencyRenderPlan {
    struct Reference: Hashable {
        let consumerLayerID: Int
        let providerLayerID: Int
        let slot: SceneEffectPassSlot
        let variant: SceneNamedTextureReference.Variant
    }

    struct Binding: Hashable {
        enum Kind: Hashable {
            case resolvedMaterial
            case solidLayer
            case imageLayerBlend
            case visibleImageGraphOutput
        }

        let consumerLayerID: Int
        let providerLayerID: Int
        let slot: SceneEffectPassSlot
        let blendMode: Int
        let kind: Kind
        let requiresForwardCapture = false
        let requiresResolvedMaterialProgram = false
    }

    let bindingsByConsumerLayerID: [Int: Binding]
    let requiredProviderLayerIDs: Set<Int>
    let requiredGraphOutputProviderLayerIDs: Set<Int>
    let requiredEffectConsumerLayerIDs: Set<Int>

    init(
        descriptor: SceneRenderDescriptor,
        visibleLayerIDs: Set<Int>,
        executableUtilityConsumerLayerIDs: Set<Int>,
        verifiedXRayStageKeys: Set<SceneAuthoredEffectRenderPlan.EffectKey>,
        admittedResolvedMaterialReferences: Set<Reference> = []
    ) {
        _ = visibleLayerIDs
        _ = executableUtilityConsumerLayerIDs
        _ = verifiedXRayStageKeys
        _ = admittedResolvedMaterialReferences
        bindingsByConsumerLayerID = descriptor.bindings
        requiredProviderLayerIDs = Set(descriptor.bindings.values.map(
            \.providerLayerID
        ))
        requiredGraphOutputProviderLayerIDs =
            descriptor.graphOutputProviderLayerIDs
        requiredEffectConsumerLayerIDs = Set(descriptor.bindings.keys)
    }

    func blocksStaticLayerSourcePassthrough(for layerID: Int) -> Bool {
        _ = layerID
        return false
    }

    func resolvedMaterialPreparationOrder(
        authoredLayerIDs: [Int]
    ) -> [Int]? {
        authoredLayerIDs
    }
}

struct SceneDependencyEffectInput {
    let consumerLayerID: Int
    let providerLayerID: Int
    let variant: SceneNamedTextureReference.Variant
    let slot: SceneEffectPassSlot
    let blendMode: Int
    let frameEpoch: UInt64
    let texture: MTLTexture
}

enum SceneFrameTextureIdentity: Hashable {
    case namedLayerTarget(SceneNamedTextureReference)
}

final class SceneFrameTextureRegistry {
    enum Status { case ready(MTLTexture) }

    var frameEpoch: UInt64
    private(set) var readyPublicationCount = 0
    private var textures: [SceneFrameTextureIdentity: MTLTexture] = [:]

    init(frameEpoch: UInt64) {
        self.frameEpoch = frameEpoch
    }

    func texture(for identity: SceneFrameTextureIdentity) -> MTLTexture? {
        textures[identity]
    }

    func set(_ status: Status, for identity: SceneFrameTextureIdentity) {
        switch status {
        case let .ready(texture):
            readyPublicationCount += 1
            textures[identity] = texture
        }
    }
}

final class SceneNamedRenderTargetPool {
    static let maximumDimension = 4_096
    private let device: MTLDevice

    init(device: MTLDevice) {
        self.device = device
    }

    func texture(for layerID: Int, width: Int, height: Int) -> MTLTexture? {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: width,
            height: height,
            mipmapped: false
        )
        descriptor.usage = [.shaderRead, .renderTarget]
        let texture = device.makeTexture(descriptor: descriptor)
        texture?.label = "reservation-\(layerID)"
        return texture
    }
}

final class SceneGPUCompletionTelemetry {
    init(phase: String) { _ = phase }
    func record(layerID: Int, encoded: Bool, on commandBuffer: MTLCommandBuffer) {
        _ = layerID
        _ = encoded
        _ = commandBuffer
    }
    func recordFailure(layerID: Int) { _ = layerID }
}

enum SceneTexturePurpose { case premultipliedColor }
enum SceneTextureSampling {
    case linearClamp
    case nearestRepeat
    var isResolvedForMaterialProgram: Bool { true }
    var usesClampBorderFallback: Bool { false }
    var imageLayerUniformMode: UInt32 {
        switch self {
        case .linearClamp: 0
        case .nearestRepeat: 3
        }
    }
}
struct SceneTextureContent { let isResolved: Bool }

struct SceneTextureCandidate {
    let texture: MTLTexture
    let purpose: SceneTexturePurpose
    let content: SceneTextureContent
    let sampling: SceneTextureSampling
    let uvTransform: SceneTextureUVTransform

    func axisAlignedMappedUVScale(
        expectedPurpose: SceneTexturePurpose
    ) -> SIMD2<Float>? {
        _ = expectedPurpose
        return SIMD2(repeating: 1)
    }
}

struct SceneTextureUVTransform {
    let uniform0: SIMD4<Float>
    let uniform1: SIMD4<Float>
    static let identity = Self(
        uniform0: SIMD4(1, 1, 0, 0),
        uniform1: SIMD4(0, 0, 0, 0)
    )
}

struct SceneLayerFragmentUniforms {
    var textureFrame0 = SIMD4<Float>.zero
    var textureFrame1 = SIMD4<Float>.zero
    var sourceSampling = SIMD2<UInt32>.zero
    var alpha: Float = 1
    var tint = SIMD4<Float>(repeating: 1)
    static func neutral() -> Self { .init() }
}

extension SIMD3 where Scalar == Float {
    init(_ values: [Double], fill: Float) {
        self.init(
            values.indices.contains(0) ? Float(values[0]) : fill,
            values.indices.contains(1) ? Float(values[1]) : fill,
            values.indices.contains(2) ? Float(values[2]) : fill
        )
    }
}

enum SceneCaptureGeometryResolver {
    struct Geometry {
        let pixelSize: CGSize
        let sourceUV: SceneTextureUVTransform
    }
    static func resolve(
        kind: SceneUtilityLayer.Kind,
        layerMVP: simd_float4x4,
        viewportSize: CGSize
    ) -> Geometry? {
        _ = kind
        _ = layerMVP
        return .init(pixelSize: viewportSize, sourceUV: .identity)
    }
}

final class SceneImageLayerPipeline {}

enum SceneOffscreenEffectRenderer {
    static var lastTextureFrame0 = SIMD4<Float>.zero
    static var lastTextureFrame1 = SIMD4<Float>.zero
    static var lastSourceSampling = SIMD2<UInt32>.zero

    static func captureSource(
        sourceTexture: MTLTexture,
        target: MTLTexture,
        sourceUniforms: SceneLayerFragmentUniforms,
        pipeline: SceneImageLayerPipeline,
        commandBuffer: MTLCommandBuffer
    ) -> Bool {
        _ = sourceTexture
        _ = target
        lastTextureFrame0 = sourceUniforms.textureFrame0
        lastTextureFrame1 = sourceUniforms.textureFrame1
        lastSourceSampling = sourceUniforms.sourceSampling
        _ = pipeline
        _ = commandBuffer
        return true
    }
}

final class SceneMainPassEncoder {
    private let texture: MTLTexture
    private let commandBuffer: MTLCommandBuffer

    init(texture: MTLTexture, commandBuffer: MTLCommandBuffer) {
        self.texture = texture
        self.commandBuffer = commandBuffer
    }

    func encodeOffscreen(_ body: (MTLCommandBuffer) -> Bool) -> Bool {
        body(commandBuffer)
    }

    func withReadableTarget(
        _ body: (MTLTexture, MTLCommandBuffer) -> Bool
    ) -> Bool? {
        body(texture, commandBuffer)
    }
}

private func texture(
    _ device: MTLDevice,
    width: Int = 2,
    height: Int = 2,
    label: String
) -> MTLTexture {
    let descriptor = MTLTextureDescriptor.texture2DDescriptor(
        pixelFormat: .bgra8Unorm,
        width: width,
        height: height,
        mipmapped: false
    )
    descriptor.usage = [.shaderRead, .renderTarget]
    descriptor.storageMode = .shared
    guard let result = device.makeTexture(descriptor: descriptor) else {
        fatalError("texture unavailable")
    }
    result.label = label
    return result
}

@main
enum Harness {
    static func main() throws {
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue(),
              let commandBuffer = queue.makeCommandBuffer() else {
            print("{\"metalAvailable\":false}")
            return
        }
        let provider = SceneRenderDescriptor.Layer(
            id: 400,
            contentKind: "image",
            utilityLayer: nil,
            alpha: 1,
            colorRGB: [1, 1, 1]
        )
        let binding = SceneDependencyRenderPlan.Binding(
            consumerLayerID: 401,
            providerLayerID: 400,
            slot: .init(effectID: "blend", passIndex: 0, slotIndex: 1),
            blendMode: 0,
            kind: .visibleImageGraphOutput
        )
        let descriptor = SceneRenderDescriptor(
            layers: [provider],
            bindings: [401: binding],
            graphOutputProviderLayerIDs: [400]
        )
        let runtime = SceneDependencyFrameRuntime(
            descriptor: descriptor,
            visibleLayerIDs: [400, 401],
            executableUtilityConsumerLayerIDs: [],
            device: device
        )
        let source = texture(device, label: "provider-source")
        let candidate = SceneTextureCandidate(
            texture: source,
            purpose: .premultipliedColor,
            content: .init(isResolved: true),
            sampling: .linearClamp,
            uvTransform: .identity
        )
        var reservationFailure: String?
        let provisionalInput = runtime.reserveEffectInput(
            for: binding,
            providerLayer: provider,
            providerTexture: source,
            providerCandidate: candidate,
            layerMVP: matrix_identity_float4x4,
            viewportSize: CGSize(width: 2, height: 2),
            frameEpoch: 13,
            failureReason: &reservationFailure
        )
        let compositionProvider = SceneRenderDescriptor.Layer(
            id: 450,
            contentKind: "composition",
            utilityLayer: .init(kind: .composition),
            alpha: 1,
            colorRGB: [1, 1, 1]
        )
        let compositionBinding = SceneDependencyRenderPlan.Binding(
            consumerLayerID: 451,
            providerLayerID: 450,
            slot: .init(effectID: "clipping", passIndex: 0, slotIndex: 1),
            blendMode: 0,
            kind: .resolvedMaterial
        )
        let compositionRuntime = SceneDependencyFrameRuntime(
            descriptor: .init(
                layers: [compositionProvider],
                bindings: [451: compositionBinding],
                graphOutputProviderLayerIDs: []
            ),
            visibleLayerIDs: [450, 451],
            executableUtilityConsumerLayerIDs: [451],
            device: device
        )
        var compositionReservationFailure: String?
        let compositionInput = compositionRuntime.reserveEffectInput(
            for: compositionBinding,
            providerLayer: compositionProvider,
            providerTexture: nil,
            providerCandidate: nil,
            layerMVP: matrix_identity_float4x4,
            viewportSize: CGSize(width: 3, height: 4),
            frameEpoch: 13,
            failureReason: &compositionReservationFailure
        )
        let resolvedMaterialReservesFromGeometryWithoutBaseSource =
            compositionInput?.texture.width == 3
                && compositionInput?.texture.height == 4
                && compositionReservationFailure == nil
        let output = texture(device, label: "provider-graph-output")
        let expectedOutputBytes: [UInt8] = [
            5, 17, 29, 255,
            41, 53, 67, 223,
            79, 83, 97, 191,
            101, 113, 127, 159,
        ]
        output.replace(
            region: MTLRegionMake2D(0, 0, output.width, output.height),
            mipmapLevel: 0,
            withBytes: expectedOutputBytes,
            bytesPerRow: output.width * 4
        )
        let registry = SceneFrameTextureRegistry(frameEpoch: 13)
        let unavailableBeforePublication: Bool
        switch runtime.resolvedMaterialEffectInputResolution(
            for: 401,
            textureRegistry: registry
        ) {
        case let .unavailable(reasonCode):
            unavailableBeforePublication =
                reasonCode == "external-primary-provider-capture-unavailable"
        case .ready, .invalid:
            unavailableBeforePublication = false
        }
        let installed = runtime.installPreparedGraphOutputs(
            [400: output],
            frameEpoch: 13
        )
        let rawCaptureRefused = runtime.captureProviderIfRequired(
            layer: provider,
            sourceTexture: source,
            sourceCandidate: candidate,
            layerMVP: matrix_identity_float4x4,
            viewportSize: CGSize(width: 2, height: 2),
            pipeline: .init(),
            textureRegistry: registry,
            mainPass: .init(texture: source, commandBuffer: commandBuffer)
        ) == false
        let fallbackRuntime = SceneDependencyFrameRuntime(
            descriptor: descriptor,
            visibleLayerIDs: [400, 401],
            executableUtilityConsumerLayerIDs: [],
            device: device
        )
        var fallbackReservationFailure: String?
        let fallbackReservation = fallbackRuntime.reserveEffectInput(
            for: binding,
            providerLayer: provider,
            providerTexture: source,
            providerCandidate: candidate,
            layerMVP: matrix_identity_float4x4,
            viewportSize: CGSize(width: 2, height: 2),
            frameEpoch: 13,
            failureReason: &fallbackReservationFailure
        )
        let fallbackRegistry = SceneFrameTextureRegistry(frameEpoch: 13)
        let sourceFallbackPublished = fallbackRuntime
            .captureGraphSourceFallbackIfRequired(
                layer: provider,
                sourceTexture: source,
                sourceCandidate: candidate,
                layerMVP: matrix_identity_float4x4,
                viewportSize: CGSize(width: 2, height: 2),
                pipeline: .init(),
                textureRegistry: fallbackRegistry,
                mainPass: .init(
                    texture: source,
                    commandBuffer: commandBuffer
                )
            ) == true
        let sourceFallbackReady: Bool
        switch fallbackRuntime.resolvedMaterialEffectInputResolution(
            for: 401,
            textureRegistry: fallbackRegistry
        ) {
        case let .ready(value):
            sourceFallbackReady = value.texture === fallbackReservation?.texture
                && value.texture !== source
                && fallbackReservationFailure == nil
                && fallbackRegistry.readyPublicationCount == 1
        case .unavailable, .invalid:
            sourceFallbackReady = false
        }
        let wrongObjectRejected = runtime.publishGraphOutputIfRequired(
            layerID: 400,
            texture: provisionalInput!.texture,
            textureRegistry: registry,
            commandBuffer: commandBuffer
        ) == false
        let failedPublicationLeftReservationUnpublished =
            registry.readyPublicationCount == 0
        let published = runtime.publishGraphOutputIfRequired(
            layerID: 400,
            texture: output,
            textureRegistry: registry,
            commandBuffer: commandBuffer
        ) == true
        let readyInput: SceneDependencyEffectInput?
        switch runtime.resolvedMaterialEffectInputResolution(
            for: 401,
            textureRegistry: registry
        ) {
        case let .ready(value): readyInput = value
        case .unavailable, .invalid: readyInput = nil
        }
        let directInput = runtime.effectInput(
            for: 401,
            textureRegistry: registry
        )
        let capturedUV = SceneTextureUVTransform(
            uniform0: SIMD4(0.125, 0.25, 0.5, 0),
            uniform1: SIMD4(0, 0.75, 0, 0)
        )
        let captureProvider = SceneRenderDescriptor.Layer(
            id: 500,
            contentKind: "image",
            utilityLayer: nil,
            alpha: 1,
            colorRGB: [1, 1, 1]
        )
        let captureBinding = SceneDependencyRenderPlan.Binding(
            consumerLayerID: 501,
            providerLayerID: 500,
            slot: .init(effectID: "blend", passIndex: 0, slotIndex: 1),
            blendMode: 0,
            kind: .imageLayerBlend
        )
        let captureRuntime = SceneDependencyFrameRuntime(
            descriptor: .init(
                layers: [captureProvider],
                bindings: [501: captureBinding],
                graphOutputProviderLayerIDs: []
            ),
            visibleLayerIDs: [500, 501],
            executableUtilityConsumerLayerIDs: [],
            device: device
        )
        var missingImageSourceFailure: String?
        let imageProviderStillRequiresExactSource = captureRuntime
            .reserveEffectInput(
                for: captureBinding,
                providerLayer: captureProvider,
                providerTexture: nil,
                providerCandidate: nil,
                layerMVP: matrix_identity_float4x4,
                viewportSize: CGSize(width: 2, height: 2),
                frameEpoch: 13,
                failureReason: &missingImageSourceFailure
            ) == nil
            && missingImageSourceFailure == "image-provider-invalid"
        let captureRegistry = SceneFrameTextureRegistry(frameEpoch: 13)
        let captureCandidate = SceneTextureCandidate(
            texture: source,
            purpose: .premultipliedColor,
            content: .init(isResolved: true),
            sampling: .nearestRepeat,
            uvTransform: capturedUV
        )
        let capturedNonDefaultSourceAtom = captureRuntime.captureProviderIfRequired(
            layer: captureProvider,
            sourceTexture: source,
            sourceCandidate: captureCandidate,
            layerMVP: matrix_identity_float4x4,
            viewportSize: CGSize(width: 2, height: 2),
            pipeline: .init(),
            textureRegistry: captureRegistry,
            mainPass: .init(texture: source, commandBuffer: commandBuffer)
        ) == true
            && SceneOffscreenEffectRenderer.lastTextureFrame0
                == capturedUV.uniform0
            && SceneOffscreenEffectRenderer.lastTextureFrame1
                == capturedUV.uniform1
            && SceneOffscreenEffectRenderer.lastSourceSampling == SIMD2(3, 0)
            && captureRegistry.readyPublicationCount == 1
        let wrongSize = texture(
            device,
            width: 3,
            height: 2,
            label: "wrong-sized-output"
        )
        let wrongSizeRejected = !runtime.installPreparedGraphOutputs(
            [400: wrongSize],
            frameEpoch: 13
        )
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        let gpuCompleted = commandBuffer.status == .completed
            && commandBuffer.error == nil
        var publishedBytes = [UInt8](
            repeating: 0,
            count: expectedOutputBytes.count
        )
        provisionalInput?.texture.getBytes(
            &publishedBytes,
            bytesPerRow: output.width * 4,
            from: MTLRegionMake2D(0, 0, output.width, output.height),
            mipmapLevel: 0
        )
        let copiedGraphOutputBytes = gpuCompleted
            && publishedBytes == expectedOutputBytes
        registry.frameEpoch = 14
        let epochAdvanceClearsReservation: Bool
        switch runtime.resolvedMaterialEffectInputResolution(
            for: 401,
            textureRegistry: registry
        ) {
        case let .invalid(reasonCode):
            epochAdvanceClearsReservation =
                reasonCode == "external-primary-reservation-missing"
        case .ready, .unavailable:
            epochAdvanceClearsReservation = false
        }
        let result: [String: Any] = [
            "metalAvailable": true,
            "reserved": provisionalInput != nil && reservationFailure == nil,
            "resolvedMaterialReservesFromGeometryWithoutBaseSource":
                resolvedMaterialReservesFromGeometryWithoutBaseSource,
            "imageProviderStillRequiresExactSource":
                imageProviderStillRequiresExactSource,
            "graphCaptureRequired": runtime.requiresGraphOutputCapture(
                for: 400
            ),
            "unavailableBeforePublication": unavailableBeforePublication,
            "installed": installed,
            "rawCaptureRefused": rawCaptureRefused,
            "sourceFallbackPublished": sourceFallbackPublished,
            "sourceFallbackReady": sourceFallbackReady,
            "wrongObjectRejected": wrongObjectRejected,
            "failedPublicationLeftReservationUnpublished":
                failedPublicationLeftReservationUnpublished,
            "published": published,
            "publicationCount": registry.readyPublicationCount,
            "gpuCompleted": gpuCompleted,
            "copiedGraphOutputBytes": copiedGraphOutputBytes,
            "readyUsesDistinctNamedTarget":
                readyInput?.texture === provisionalInput?.texture
                && readyInput?.texture !== output,
            "directInputUsesDistinctNamedTarget":
                directInput?.texture === provisionalInput?.texture
                && directInput?.texture !== output,
            "capturedNonDefaultSourceAtom": capturedNonDefaultSourceAtom,
            "wrongSizeRejected": wrongSizeRejected,
            "epochAdvanceClearsReservation": epochAdvanceClearsReservation,
        ]
        let data = try JSONSerialization.data(
            withJSONObject: result,
            options: [.sortedKeys]
        )
        print(String(decoding: data, as: UTF8.self))
    }
}
'''


class SceneDependencyGraphOutputRuntimeTests(unittest.TestCase):
    @unittest.skipUnless(shutil.which("swiftc"), "swiftc is required")
    def test_graph_output_copies_into_distinct_reservation_and_publishes_once(
        self,
    ) -> None:
        with tempfile.TemporaryDirectory(
            prefix="mwx-scene-dependency-graph-output-"
        ) as directory:
            root = Path(directory)
            harness = root / "Harness.swift"
            binary = root / "dependency-graph-output"
            harness.write_text(HARNESS_SOURCE, encoding="utf-8")
            compilation = subprocess.run(
                [
                    "xcrun",
                    "--sdk",
                    "macosx",
                    "swiftc",
                    str(RUNTIME_SOURCE),
                    str(harness),
                    "-framework",
                    "Metal",
                    "-o",
                    str(binary),
                ],
                capture_output=True,
                text=True,
            )
            self.assertEqual(compilation.returncode, 0, compilation.stderr)
            completed = subprocess.run(
                [str(binary)],
                check=True,
                capture_output=True,
                text=True,
            )
            result = json.loads(completed.stdout)
            if not result["metalAvailable"]:
                self.skipTest("Metal device unavailable")
            self.assertEqual(
                result,
                {
                    "metalAvailable": True,
                    "reserved": True,
                    "resolvedMaterialReservesFromGeometryWithoutBaseSource": True,
                    "imageProviderStillRequiresExactSource": True,
                    "graphCaptureRequired": True,
                    "unavailableBeforePublication": True,
                    "installed": True,
                    "rawCaptureRefused": True,
                    "sourceFallbackPublished": True,
                    "sourceFallbackReady": True,
                    "wrongObjectRejected": True,
                    "failedPublicationLeftReservationUnpublished": True,
                    "published": True,
                    "publicationCount": 1,
                    "gpuCompleted": True,
                    "copiedGraphOutputBytes": True,
                    "readyUsesDistinctNamedTarget": True,
                    "directInputUsesDistinctNamedTarget": True,
                    "capturedNonDefaultSourceAtom": True,
                    "wrongSizeRejected": True,
                    "epochAdvanceClearsReservation": True,
                },
            )


if __name__ == "__main__":
    unittest.main()
