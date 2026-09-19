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
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Dependencies/SceneDependencyFrameRuntime.swift"
)
STATIC_MODEL_RUNTIME_SOURCE = RUNTIME_SOURCE.with_name(
    "SceneDependencyFrameRuntime+StaticModel.swift"
)
AGGREGATE_VALIDATION_RUNTIME_SOURCE = RUNTIME_SOURCE.with_name(
    "SceneDependencyFrameRuntime+AggregateValidation.swift"
)
GEOMETRY_RUNTIME_SOURCE = RUNTIME_SOURCE.with_name(
    "SceneDependencyFrameRuntime+Geometry.swift"
)
EFFECT_INPUT_RESOLUTION_RUNTIME_SOURCE = RUNTIME_SOURCE.with_name(
    "SceneDependencyFrameRuntime+EffectInputResolution.swift"
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
        struct Effect { let visible: Bool? }
        let id: Int
        let contentKind: String
        let utilityLayer: SceneUtilityLayer?
        let alpha: Double?
        let colorRGB: [Double]?
        var effects: [Effect] = []
        let clampUVs: Bool? = nil
        let noInterpolation: Bool? = nil
    }

    let layers: [Layer]
    let bindings: [Int: SceneDependencyRenderPlan.Binding]
    let graphOutputProviderLayerIDs: Set<Int>
    var aggregates: [Int: SceneDependencyRenderPlan.MultiProviderAggregate] = [:]
    var staticModelConsumerProviders: [Int: Int] = [:]
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
            case geometryLayer
            case visibleImageGraphOutput
        }

        let consumerLayerID: Int
        let providerLayerID: Int
        let slot: SceneEffectPassSlot
        let referenceSlots: [SceneEffectPassSlot]
        let blendMode: Int
        let kind: Kind
        let requiresForwardCapture: Bool
        let requiresResolvedMaterialProgram: Bool

        init(
            consumerLayerID: Int,
            providerLayerID: Int,
            slot: SceneEffectPassSlot,
            referenceSlots: [SceneEffectPassSlot]? = nil,
            blendMode: Int,
            kind: Kind,
            requiresForwardCapture: Bool = false,
            requiresResolvedMaterialProgram: Bool = false
        ) {
            self.consumerLayerID = consumerLayerID
            self.providerLayerID = providerLayerID
            self.slot = slot
            self.referenceSlots = referenceSlots ?? [slot]
            self.blendMode = blendMode
            self.kind = kind
            self.requiresForwardCapture = requiresForwardCapture
            self.requiresResolvedMaterialProgram =
                requiresResolvedMaterialProgram
        }
    }

    struct MultiProviderAggregate: Hashable {
        let consumerLayerID: Int
        let bindings: [Binding]
        let authoredSlotOrder: [SceneEffectPassSlot]

        var orderedBindings: [Binding] {
            guard authoredSlotOrder.count == bindings.count else { return [] }
            var bindingsBySlot: [SceneEffectPassSlot: Binding] = [:]
            for binding in bindings {
                guard bindingsBySlot.updateValue(
                    binding, forKey: binding.slot
                ) == nil else { return [] }
            }
            guard bindingsBySlot.count == authoredSlotOrder.count else {
                return []
            }
            return authoredSlotOrder.compactMap { bindingsBySlot[$0] }
        }

        var providerLayerIDs: Set<Int> {
            Set(bindings.map(\.providerLayerID))
        }

        var referenceSlots: [SceneEffectPassSlot] {
            authoredSlotOrder
        }

        var hasStrictBindingVector: Bool {
            guard bindings.count >= 2,
                  authoredSlotOrder.count == bindings.count,
                  Set(authoredSlotOrder).count == authoredSlotOrder.count,
                  Set(authoredSlotOrder) == Set(bindings.map(\.slot)),
                  bindings == orderedBindings,
                  Set(bindings.map(\.providerLayerID)).count > 1 else {
                return false
            }
            return bindings.allSatisfy { binding in
                binding.consumerLayerID == consumerLayerID
                    && binding.providerLayerID != consumerLayerID
                    && binding.referenceSlots == [binding.slot]
                    && (
                        binding.kind == .imageLayerBlend
                            || binding.kind == .geometryLayer
                    )
                    && binding.blendMode == 0
                    && binding.requiresResolvedMaterialProgram
            }
        }

        func admits(_ references: [Reference]) -> Bool {
            guard hasStrictBindingVector else { return false }
            let expected = orderedBindings.map {
                Reference(
                    consumerLayerID: consumerLayerID,
                    providerLayerID: $0.providerLayerID,
                    slot: $0.slot,
                    variant: .primary
                )
            }
            return references == expected
        }
    }

    struct StaticModelBinding {
        let consumerLayerID: Int
        let providerLayerID: Int
        let materialPath: String
        let passIndex: Int
        let slotIndex: Int
        let variant: SceneNamedTextureReference.Variant
        let requiresForwardCapture: Bool
    }

    let bindingsByConsumerLayerID: [Int: Binding]
    let multiProviderAggregatesByConsumerLayerID:
        [Int: MultiProviderAggregate]
    let staticModelBindingsByConsumerLayerID: [Int: StaticModelBinding]
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
        multiProviderAggregatesByConsumerLayerID = descriptor.aggregates
        staticModelBindingsByConsumerLayerID = Dictionary(
            uniqueKeysWithValues: descriptor.staticModelConsumerProviders.map {
                consumer, provider in
                (consumer, StaticModelBinding(
                    consumerLayerID: consumer,
                    providerLayerID: provider,
                    materialPath: "materials/unseen/runtime.json",
                    passIndex: 0,
                    slotIndex: 0,
                    variant: .primary,
                    requiresForwardCapture: true
                ))
            }
        )
        requiredProviderLayerIDs = Set(descriptor.bindings.values.map(
            \.providerLayerID
        )).union(
            descriptor.aggregates.values.flatMap { $0.providerLayerIDs }
        ).union(descriptor.staticModelConsumerProviders.values)
        requiredGraphOutputProviderLayerIDs =
            descriptor.graphOutputProviderLayerIDs
        requiredEffectConsumerLayerIDs = Set(descriptor.bindings.keys)
            .union(descriptor.aggregates.keys)
    }

    func aggregateBindingIsPlanned(_ binding: Binding) -> Bool {
        guard let aggregate = multiProviderAggregatesByConsumerLayerID[
            binding.consumerLayerID
        ], aggregate.hasStrictBindingVector else {
            return false
        }
        return aggregate.bindings.contains(binding)
    }

    func resolvedMaterialExecutionLayerIDs(
        visibleRootLayerIDs: Set<Int>,
        availableExecutionLayerIDs: Set<Int>
    ) -> Set<Int> {
        var reachable = visibleRootLayerIDs.intersection(
            availableExecutionLayerIDs
        )
        var changed = true
        while changed {
            changed = false
            for binding in bindingsByConsumerLayerID.values
            where reachable.contains(binding.consumerLayerID)
                && requiredGraphOutputProviderLayerIDs.contains(
                    binding.providerLayerID
                )
                && availableExecutionLayerIDs.contains(binding.providerLayerID)
            {
                changed = reachable.insert(binding.providerLayerID).inserted
                    || changed
            }
            for aggregate in multiProviderAggregatesByConsumerLayerID.values
            where reachable.contains(aggregate.consumerLayerID) {
                for providerID in aggregate.providerLayerIDs
                where requiredGraphOutputProviderLayerIDs.contains(providerID)
                    && availableExecutionLayerIDs.contains(providerID) {
                    changed = reachable.insert(providerID).inserted
                        || changed
                }
            }
        }
        return reachable
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

    func forwardDependencyPreparationOrder(
        authoredLayerIDs: [Int],
        activeExecutionLayerIDs: Set<Int>,
        activeStaticModelConsumerLayerIDs: Set<Int> = []
    ) -> [Int]? {
        _ = authoredLayerIDs
        _ = activeExecutionLayerIDs
        _ = activeStaticModelConsumerLayerIDs
        return []
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
    var content: SceneTextureContent = .color(.resolved(.premultipliedAlpha))
}

enum SceneFrameTextureIdentity: Hashable {
    case namedLayerTarget(SceneNamedTextureReference)
}

final class SceneFrameTextureRegistry {
    enum Status { case ready(MTLTexture) }

    var frameEpoch: UInt64
    private(set) var readyPublicationCount = 0
    private(set) var typedPublicationCount = 0
    private var textures: [SceneFrameTextureIdentity: MTLTexture] = [:]
    private var contents: [SceneFrameTextureIdentity: SceneTextureContent] = [:]

    init(frameEpoch: UInt64) {
        self.frameEpoch = frameEpoch
    }

    func texture(for identity: SceneFrameTextureIdentity) -> MTLTexture? {
        textures[identity]
    }

    func completeNamedLayerTargetTexture(
        reference: SceneNamedTextureReference,
        frameEpoch: UInt64
    ) -> MTLTexture? {
        guard frameEpoch == self.frameEpoch else { return nil }
        return texture(for: .namedLayerTarget(reference))
    }

    struct Resource {
        struct Publication {
            struct Candidate { let content: SceneTextureContent }
            let texture: MTLTexture
            let candidate: Candidate
        }
        let publication: Publication
    }
    func completeNamedLayerTargetResource(
        reference: SceneNamedTextureReference,
        frameEpoch: UInt64
    ) -> Resource? {
        guard frameEpoch == self.frameEpoch,
              let texture = texture(for: .namedLayerTarget(reference)) else { return nil }
        return .init(publication: .init(
            texture: texture,
            candidate: .init(content: contents[.namedLayerTarget(reference)]
                ?? .color(.resolved(.premultipliedAlpha)))
        ))
    }

    func set(_ status: Status, for identity: SceneFrameTextureIdentity) {
        switch status {
        case let .ready(texture):
            readyPublicationCount += 1
            textures[identity] = texture
        }
    }

    @discardableResult
    func publishReservedNamedLayerTarget(
        reference: SceneNamedTextureReference,
        frameEpoch: UInt64,
        texture: MTLTexture,
        content: SceneTextureContent = .color(.resolved(.premultipliedAlpha))
    ) -> Bool {
        guard frameEpoch > 0 else { return false }
        typedPublicationCount += 1
        contents[.namedLayerTarget(reference)] = content
        set(.ready(texture), for: .namedLayerTarget(reference))
        return self.texture(
            for: .namedLayerTarget(reference)
        ) === texture
    }
}

final class SceneNamedRenderTargetPool {
    static let maximumDimension = 2_048
    private let device: MTLDevice
    private(set) var residentByteCost = 0

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
        residentByteCost = width * height * 4
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
    case linearRepeat
    case nearestClamp
    case nearestRepeat
    var isResolvedForMaterialProgram: Bool { true }
    var usesClampBorderFallback: Bool { false }
    private var isNearest: Bool {
        switch self {
        case .nearestClamp, .nearestRepeat: true
        case .linearClamp, .linearRepeat: false
        }
    }
    private var isClamped: Bool {
        switch self {
        case .linearClamp, .nearestClamp: true
        case .linearRepeat, .nearestRepeat: false
        }
    }
    var imageLayerUniformMode: UInt32 {
        switch self {
        case .linearClamp: 0
        case .linearRepeat: 1
        case .nearestClamp: 2
        case .nearestRepeat: 3
        }
    }

    func applying(
        clampUVs: Bool?,
        noInterpolation: Bool?
    ) -> Self {
        let clamped = clampUVs ?? isClamped
        let nearest = noInterpolation ?? isNearest
        switch (nearest, clamped) {
        case (false, true): return .linearClamp
        case (false, false): return .linearRepeat
        case (true, true): return .nearestClamp
        case (true, false): return .nearestRepeat
        }
    }
}
enum StubAlpha { case premultipliedAlpha }
enum StubColor { case resolved(StubAlpha) }
struct SceneTextureContent: Equatable {
    let isResolved: Bool
    var isData = false
    static let data = Self(isResolved: true, isData: true)
    static func color(_ value: StubColor) -> Self { .init(isResolved: true) }
    var isColorContent: Bool { !isData }
}

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

typealias ColorBlendBinder = () -> Void

enum SceneEffectSourceExtentContract: Equatable {
    case exactSamplingTexture
}

enum SceneMatrix {
    static func ortho(
        left: Float,
        right: Float,
        bottom: Float,
        top: Float,
        near: Float,
        far: Float
    ) -> simd_float4x4 {
        let rl = right - left
        let tb = top - bottom
        let fn = far - near
        return simd_float4x4(columns: (
            SIMD4(2 / rl, 0, 0, 0),
            SIMD4(0, 2 / tb, 0, 0),
            SIMD4(0, 0, -1 / fn, 0),
            SIMD4(-(right + left) / rl, -(top + bottom) / tb, -near / fn, 1)
        ))
    }

    static func scale(_ value: SIMD3<Float>) -> simd_float4x4 {
        simd_float4x4(diagonal: SIMD4(value, 1))
    }
}

struct SceneGeometryProduct {
    let ownerLayerID: Int
    let samplingTexture: MTLTexture
    let resourceGeneration: UInt64
    let isPreparedForPublication: (MTLCommandBuffer) -> Bool
    let encode: (
        MTLRenderCommandEncoder,
        MTLTexture,
        MTLTexture?,
        simd_float4x4,
        SceneLayerFragmentUniforms,
        ColorBlendBinder?
    ) -> Bool
    let authoredSize: SIMD2<Float>
    let effectSourceExtentContract: SceneEffectSourceExtentContract

    func matchesInstalledSource(
        layerID: Int,
        texture: MTLTexture
    ) -> Bool {
        ownerLayerID == layerID
            && resourceGeneration > 0
            && samplingTexture === texture
            && authoredSize.x.isFinite
            && authoredSize.y.isFinite
            && authoredSize.x >= 1
            && authoredSize.y >= 1
    }

    func supportsNamedProviderPlacement(
        providerOutputMVP: simd_float4x4,
        consumerOutputMVP: simd_float4x4
    ) -> Bool {
        for column in 0 ..< 4 {
            for row in 0 ..< 4 {
                guard providerOutputMVP[column][row]
                        == consumerOutputMVP[column][row] else {
                    return false
                }
            }
        }
        return true
    }
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
    static var lastAlpha: Float = 0
    static var lastTint = SIMD4<Float>.zero

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
        lastAlpha = sourceUniforms.alpha
        lastTint = sourceUniforms.tint
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

    func encodeOffscreen<Result>(
        _ body: (MTLCommandBuffer) -> Result
    ) -> Result {
        body(commandBuffer)
    }

    func withReadableTarget<Result>(
        _ body: (MTLTexture, MTLCommandBuffer) -> Result
    ) -> Result? {
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
        // A provider owns one publication target even when different consumers
        // describe how they consume it with different binding kinds. This is
        // the real shape used by a visible graph provider that also feeds an
        // aggregate composition.
        let mixedProvider = SceneRenderDescriptor.Layer(
            id: 710,
            contentKind: "image",
            utilityLayer: nil,
            alpha: 1,
            colorRGB: [1, 1, 1]
        )
        let mixedSibling = SceneRenderDescriptor.Layer(
            id: 711,
            contentKind: "image",
            utilityLayer: nil,
            alpha: 1,
            colorRGB: [1, 1, 1]
        )
        let mixedVisibleBinding = SceneDependencyRenderPlan.Binding(
            consumerLayerID: 712,
            providerLayerID: 710,
            slot: .init(effectID: "visible", passIndex: 0, slotIndex: 1),
            blendMode: 0,
            kind: .visibleImageGraphOutput
        )
        let mixedAggregateBinding = SceneDependencyRenderPlan.Binding(
            consumerLayerID: 713,
            providerLayerID: 710,
            slot: .init(effectID: "aggregate-a", passIndex: 0, slotIndex: 1),
            blendMode: 0,
            kind: .imageLayerBlend,
            requiresResolvedMaterialProgram: true
        )
        let mixedSiblingBinding = SceneDependencyRenderPlan.Binding(
            consumerLayerID: 713,
            providerLayerID: 711,
            slot: .init(effectID: "aggregate-b", passIndex: 0, slotIndex: 1),
            blendMode: 0,
            kind: .imageLayerBlend,
            requiresResolvedMaterialProgram: true
        )
        let mixedAggregate = SceneDependencyRenderPlan.MultiProviderAggregate(
            consumerLayerID: 713,
            bindings: [mixedAggregateBinding, mixedSiblingBinding],
            authoredSlotOrder: [
                mixedAggregateBinding.slot,
                mixedSiblingBinding.slot,
            ]
        )
        let mixedRuntime = SceneDependencyFrameRuntime(
            descriptor: .init(
                layers: [mixedProvider, mixedSibling],
                bindings: [712: mixedVisibleBinding],
                graphOutputProviderLayerIDs: [710],
                aggregates: [713: mixedAggregate]
            ),
            visibleLayerIDs: [710, 712, 713],
            executableUtilityConsumerLayerIDs: [],
            device: device
        )
        var mixedAggregateReservationFailure: String?
        let mixedAggregateInput = mixedRuntime.reserveEffectInput(
            for: mixedAggregateBinding,
            providerLayer: mixedProvider,
            providerTexture: source,
            providerCandidate: candidate,
            layerMVP: matrix_identity_float4x4,
            viewportSize: CGSize(width: 2, height: 2),
            frameEpoch: 18,
            failureReason: &mixedAggregateReservationFailure
        )
        var mixedVisibleReservationFailure: String?
        let mixedVisibleInput = mixedRuntime.reserveEffectInput(
            for: mixedVisibleBinding,
            providerLayer: mixedProvider,
            providerTexture: source,
            providerCandidate: candidate,
            layerMVP: matrix_identity_float4x4,
            viewportSize: CGSize(width: 2, height: 2),
            frameEpoch: 18,
            failureReason: &mixedVisibleReservationFailure
        )
        var mixedSiblingReservationFailure: String?
        let mixedSiblingInput = mixedRuntime.reserveEffectInput(
            for: mixedSiblingBinding,
            providerLayer: mixedSibling,
            providerTexture: source,
            providerCandidate: candidate,
            layerMVP: matrix_identity_float4x4,
            viewportSize: CGSize(width: 2, height: 2),
            frameEpoch: 18,
            failureReason: &mixedSiblingReservationFailure
        )
        let missingAggregateRegistry = SceneFrameTextureRegistry(frameEpoch: 18)
        let aggregatePublicationMissIsUnavailable: Bool
        switch mixedRuntime.aggregateEffectInputResolution(
            for: mixedAggregate,
            textureRegistry: missingAggregateRegistry
        ) {
        case let .unavailable(reasonCode):
            aggregatePublicationMissIsUnavailable =
                reasonCode == "external-primary-provider-capture-unavailable"
        case .ready, .invalid:
            aggregatePublicationMissIsUnavailable = false
        }
        let wrongAggregateRegistry = SceneFrameTextureRegistry(frameEpoch: 18)
        let foreignAggregateTexture = texture(
            device,
            label: "foreign-aggregate-publication"
        )
        _ = wrongAggregateRegistry.publishReservedNamedLayerTarget(
            reference: .init(providerLayerID: 710, variant: .primary),
            frameEpoch: 18,
            texture: foreignAggregateTexture
        )
        let aggregatePublicationIdentityDriftIsInvalid: Bool
        switch mixedRuntime.aggregateEffectInputResolution(
            for: mixedAggregate,
            textureRegistry: wrongAggregateRegistry
        ) {
        case let .invalid(reasonCode):
            aggregatePublicationIdentityDriftIsInvalid =
                reasonCode == "external-primary-aggregate-publication-mismatch"
        case .ready, .unavailable:
            aggregatePublicationIdentityDriftIsInvalid = false
        }
        let mixedOutput = texture(device, label: "mixed-provider-output")
        let mixedRegistry = SceneFrameTextureRegistry(frameEpoch: 18)
        let mixedOutputInstalled = mixedRuntime.installPreparedGraphOutputs(
            [710: mixedOutput],
            frameEpoch: 18
        )
        let mixedPublicationSucceeded = mixedRuntime
            .publishGraphOutputIfRequired(
                layerID: 710,
                texture: mixedOutput,
                publicationRole: .visibleMainLoop,
                textureRegistry: mixedRegistry,
                commandBuffer: commandBuffer
            ) == .published
        let mixedConsumerKindsShareProviderPublication =
            mixedAggregate.hasStrictBindingVector
                && mixedAggregateReservationFailure == nil
                && mixedVisibleReservationFailure == nil
                && mixedSiblingReservationFailure == nil
                && mixedSiblingInput != nil
                && mixedAggregateInput?.texture === mixedVisibleInput?.texture
                && mixedOutputInstalled
                && mixedPublicationSucceeded
                && mixedRegistry.completeNamedLayerTargetTexture(
                    reference: .init(providerLayerID: 710, variant: .primary),
                    frameEpoch: 18
                ) === mixedAggregateInput?.texture
        // A prepared graph target can be larger than the physical carrier
        // texture (for example a puppet/image provider rendered at a
        // normalized logical extent). Reservation, source fallback capture,
        // and graph publication must all use that one prepared extent.
        let preparedExtentProvider = SceneRenderDescriptor.Layer(
            id: 700,
            contentKind: "image",
            utilityLayer: nil,
            alpha: 1,
            colorRGB: [1, 1, 1]
        )
        let preparedExtentBinding = SceneDependencyRenderPlan.Binding(
            consumerLayerID: 701,
            providerLayerID: 700,
            slot: .init(effectID: "prepared", passIndex: 0, slotIndex: 0),
            blendMode: 0,
            kind: .visibleImageGraphOutput
        )
        let preparedExtentRuntime = SceneDependencyFrameRuntime(
            descriptor: .init(
                layers: [preparedExtentProvider],
                bindings: [701: preparedExtentBinding],
                graphOutputProviderLayerIDs: [700]
            ),
            visibleLayerIDs: [700, 701],
            executableUtilityConsumerLayerIDs: [],
            device: device
        )
        let physicalCarrier = texture(
            device,
            width: 7,
            height: 5,
            label: "prepared-extent-source"
        )
        let physicalCarrierCandidate = SceneTextureCandidate(
            texture: physicalCarrier,
            purpose: .premultipliedColor,
            content: .init(isResolved: true),
            sampling: .linearClamp,
            uvTransform: .identity
        )
        var preparedExtentFailure: String?
        let preparedExtentInput = preparedExtentRuntime.reserveEffectInput(
            for: preparedExtentBinding,
            providerLayer: preparedExtentProvider,
            providerTexture: physicalCarrier,
            providerCandidate: physicalCarrierCandidate,
            layerMVP: matrix_identity_float4x4,
            viewportSize: CGSize(width: 7, height: 5),
            preparedOutputExtent: (width: 8, height: 4),
            frameEpoch: 17,
            failureReason: &preparedExtentFailure
        )
        let preparedExtentOutput = texture(
            device,
            width: 8,
            height: 4,
            label: "prepared-extent-output"
        )
        let preparedExtentRegistry = SceneFrameTextureRegistry(frameEpoch: 17)
        let preparedExtentInstalled = preparedExtentRuntime
            .installPreparedGraphOutputs(
                [700: preparedExtentOutput],
                frameEpoch: 17
            )
        let preparedExtentFallbackCaptured = preparedExtentRuntime
            .captureGraphSourceFallbackIfRequired(
                layer: preparedExtentProvider,
                sourceTexture: physicalCarrier,
                sourceCandidate: physicalCarrierCandidate,
                layerMVP: matrix_identity_float4x4,
                viewportSize: CGSize(width: 7, height: 5),
                pipeline: .init(),
                textureRegistry: preparedExtentRegistry,
                mainPass: .init(
                    texture: physicalCarrier,
                    commandBuffer: commandBuffer
                )
            ) == .published
        let preparedExtentCapturePublished = preparedExtentRegistry
            .completeNamedLayerTargetTexture(
                reference: .init(providerLayerID: 700, variant: .primary),
                frameEpoch: 17
            ) === preparedExtentInput?.texture
        let preparedExtentPublished = preparedExtentRuntime
            .publishGraphOutputIfRequired(
                layerID: 700,
                texture: preparedExtentOutput,
                publicationRole: .visibleMainLoop,
                textureRegistry: preparedExtentRegistry,
                commandBuffer: commandBuffer
            ) == .published
        let preparedExtentWrongSize = texture(
            device,
            width: 7,
            height: 5,
            label: "prepared-extent-wrong-size"
        )
        let preparedExtentWrongSizeRejected = preparedExtentRuntime
            .publishGraphOutputIfRequired(
                layerID: 700,
                texture: preparedExtentWrongSize,
                publicationRole: .visibleMainLoop,
                textureRegistry: preparedExtentRegistry,
                commandBuffer: commandBuffer
            ) == .invalid(
                reasonCode: "named-provider-publication-identity-invalid"
            )
        // The publication route fills its named target with a single
        // full-region blit, so a reservation whose target normalized below
        // its prepared source must refuse the copy instead of writing out of
        // bounds.
        let oversizedSource = texture(
            device,
            width: 4096,
            height: 1,
            label: "prepared-extent-oversized-source"
        )
        var oversizedSourceReservationFailure: String?
        let oversizedSourceReservation = preparedExtentRuntime
            .reserveEffectInput(
                for: preparedExtentBinding,
                providerLayer: preparedExtentProvider,
                providerTexture: oversizedSource,
                providerCandidate: SceneTextureCandidate(
                    texture: oversizedSource,
                    purpose: .premultipliedColor,
                    content: .init(isResolved: true),
                    sampling: .linearClamp,
                    uvTransform: .identity
                ),
                layerMVP: matrix_identity_float4x4,
                viewportSize: CGSize(width: 4096, height: 1),
                preparedOutputExtent: (width: 4096, height: 1),
                frameEpoch: 23,
                failureReason: &oversizedSourceReservationFailure
            )
        let oversizedSourceRegistry = SceneFrameTextureRegistry(frameEpoch: 23)
        let oversizedSourceInstalled = preparedExtentRuntime
            .installPreparedGraphOutputs(
                [700: oversizedSource],
                frameEpoch: 23
            )
        // Over-cap without a rasterization pipeline keeps the historical
        // fail-closed contract.
        let preparedExtentTargetBelowSourceRejected =
            oversizedSourceReservation?.texture.width == 2_048
                && oversizedSourceReservation?.texture.height == 1
                && oversizedSourceReservationFailure == nil
                && oversizedSourceInstalled
                && preparedExtentRuntime.publishGraphOutputIfRequired(
                    layerID: 700,
                    texture: oversizedSource,
                    publicationRole: .visibleMainLoop,
                    textureRegistry: oversizedSourceRegistry,
                    commandBuffer: commandBuffer
                ) == .invalid(
                    reasonCode:
                        "named-provider-publication-target-extent-invalid"
                )
        // Over-cap resolved COLOR with a rasterization pipeline publishes
        // through the aspect-normalized capped target (the same downsampling
        // contract the geometry route owns); data content stays fail-closed.
        let oversizedRasterizedPublished =
            preparedExtentRuntime.publishGraphOutputIfRequired(
                layerID: 700,
                texture: oversizedSource,
                publicationRole: .visibleMainLoop,
                textureRegistry: oversizedSourceRegistry,
                commandBuffer: commandBuffer,
                imagePipeline: SceneImageLayerPipeline()
            ) == .published
        let oversizedDataRejected =
            preparedExtentRuntime.publishGraphOutputIfRequired(
                layerID: 700,
                texture: oversizedSource,
                publicationRole: .visibleMainLoop,
                textureRegistry: oversizedSourceRegistry,
                commandBuffer: commandBuffer,
                content: .data,
                imagePipeline: SceneImageLayerPipeline()
            ) == .invalid(
                    reasonCode:
                        "named-provider-publication-target-extent-invalid"
                )

        // Geometry providers reserve an authored-local target, but graph
        // output remains only a sampling source. Publication must execute the
        // typed GeometryProduct on the current command buffer and must reject
        // stale identity, placement, pose, and encode state.
        let geometryProvider = SceneRenderDescriptor.Layer(
            id: 800,
            contentKind: "image",
            utilityLayer: nil,
            alpha: 1,
            colorRGB: [1, 1, 1]
        )
        let geometrySibling = SceneRenderDescriptor.Layer(
            id: 801,
            contentKind: "image",
            utilityLayer: nil,
            alpha: 1,
            colorRGB: [1, 1, 1]
        )
        let geometryBinding = SceneDependencyRenderPlan.Binding(
            consumerLayerID: 802,
            providerLayerID: 800,
            slot: .init(effectID: "geometry", passIndex: 0, slotIndex: 1),
            blendMode: 0,
            kind: .geometryLayer,
            requiresResolvedMaterialProgram: true
        )
        let geometrySiblingBinding = SceneDependencyRenderPlan.Binding(
            consumerLayerID: 802,
            providerLayerID: 801,
            slot: .init(effectID: "flat", passIndex: 0, slotIndex: 1),
            blendMode: 0,
            kind: .imageLayerBlend,
            requiresResolvedMaterialProgram: true
        )
        let geometryAggregate = SceneDependencyRenderPlan.MultiProviderAggregate(
            consumerLayerID: 802,
            bindings: [geometryBinding, geometrySiblingBinding],
            authoredSlotOrder: [geometryBinding.slot, geometrySiblingBinding.slot]
        )
        func geometryRuntime() -> SceneDependencyFrameRuntime {
            SceneDependencyFrameRuntime(
                descriptor: .init(
                    layers: [geometryProvider, geometrySibling],
                    bindings: [:],
                    graphOutputProviderLayerIDs: [800],
                    aggregates: [802: geometryAggregate]
                ),
                visibleLayerIDs: [800, 802],
                executableUtilityConsumerLayerIDs: [802],
                device: device
            )
        }
        let geometryAtlas = texture(
            device,
            width: 3,
            height: 2,
            label: "geometry-atlas"
        )
        let geometryGraphOutput = texture(
            device,
            width: 3,
            height: 2,
            label: "geometry-graph-output"
        )
        let geometryGraphBytes = [UInt8](
            repeating: 211,
            count: geometryGraphOutput.width * geometryGraphOutput.height * 4
        )
        geometryGraphOutput.replace(
            region: MTLRegionMake2D(
                0, 0, geometryGraphOutput.width, geometryGraphOutput.height
            ),
            mipmapLevel: 0,
            withBytes: geometryGraphBytes,
            bytesPerRow: geometryGraphOutput.width * 4
        )
        var encodedGeometrySource: MTLTexture?
        let geometryProduct = SceneGeometryProduct(
            ownerLayerID: 800,
            samplingTexture: geometryAtlas,
            resourceGeneration: 7,
            isPreparedForPublication: { candidate in
                candidate === commandBuffer
            },
            encode: { _, sourceTexture, _, _, _, _ in
                encodedGeometrySource = sourceTexture
                return true
            },
            authoredSize: SIMD2(4, 3),
            effectSourceExtentContract: .exactSamplingTexture
        )
        let geometrySuccessRuntime = geometryRuntime()
        var geometryReservationFailure: String?
        let geometryInput = geometrySuccessRuntime.reserveEffectInput(
            for: geometryBinding,
            providerLayer: geometryProvider,
            providerTexture: geometryAtlas,
            providerCandidate: nil,
            layerMVP: matrix_identity_float4x4,
            viewportSize: CGSize(width: 16, height: 9),
            preparedOutputExtent: (width: 3, height: 2),
            geometryProduct: geometryProduct,
            providerOutputMVP: matrix_identity_float4x4,
            consumerOutputMVP: matrix_identity_float4x4,
            frameEpoch: 19,
            failureReason: &geometryReservationFailure
        )
        let geometryPreparedOutputInstalled = geometrySuccessRuntime
            .installPreparedGraphOutputs([800: geometryGraphOutput], frameEpoch: 19)
        let geometryRegistry = SceneFrameTextureRegistry(frameEpoch: 19)
        let geometryPublished = geometrySuccessRuntime
            .publishGraphOutputIfRequired(
                layerID: 800,
                texture: geometryGraphOutput,
                publicationRole: .visibleMainLoop,
                textureRegistry: geometryRegistry,
                commandBuffer: commandBuffer,
                geometryProduct: geometryProduct
            ) == .published
        let geometryPublishedExactReservation = geometryRegistry
            .completeNamedLayerTargetTexture(
                reference: .init(providerLayerID: 800, variant: .primary),
                frameEpoch: 19
            ) === geometryInput?.texture
        let oversizedGeometryProduct = SceneGeometryProduct(
            ownerLayerID: 800,
            samplingTexture: geometryAtlas,
            resourceGeneration: 9,
            isPreparedForPublication: { _ in true },
            encode: { _, _, _, _, _, _ in true },
            authoredSize: SIMD2(2_667, 1_500),
            effectSourceExtentContract: .exactSamplingTexture
        )
        let oversizedGeometryRuntime = geometryRuntime()
        var oversizedGeometryFailure: String?
        let oversizedGeometryInput = oversizedGeometryRuntime.reserveEffectInput(
            for: geometryBinding,
            providerLayer: geometryProvider,
            providerTexture: geometryAtlas,
            providerCandidate: nil,
            layerMVP: matrix_identity_float4x4,
            viewportSize: CGSize(width: 16, height: 9),
            preparedOutputExtent: (width: 3, height: 2),
            geometryProduct: oversizedGeometryProduct,
            providerOutputMVP: matrix_identity_float4x4,
            consumerOutputMVP: matrix_identity_float4x4,
            frameEpoch: 20,
            failureReason: &oversizedGeometryFailure
        )
        let oversizedGeometryMVP = SceneDependencyFrameRuntime
            .geometryPublicationMVP(oversizedGeometryProduct)
        let oversizedGeometryNormalized = oversizedGeometryInput?.texture.width == 2_048
            && oversizedGeometryInput?.texture.height == 1_152
            && oversizedGeometryFailure == nil
        let oversizedGeometryKeepsAuthoredLocalProjection =
            abs((oversizedGeometryMVP?[0][0] ?? 0) - (2 / 2_667)) < 0.000001
            && abs((oversizedGeometryMVP?[1][1] ?? 0) - (2 / 1_500)) < 0.000001

        func geometryReservationRejected(
            product: SceneGeometryProduct,
            providerTexture: MTLTexture,
            providerMVP: simd_float4x4 = matrix_identity_float4x4,
            consumerMVP: simd_float4x4 = matrix_identity_float4x4,
            expectedReason: String
        ) -> Bool {
            let runtime = geometryRuntime()
            var reason: String?
            return runtime.reserveEffectInput(
                for: geometryBinding,
                providerLayer: geometryProvider,
                providerTexture: providerTexture,
                providerCandidate: nil,
                layerMVP: matrix_identity_float4x4,
                viewportSize: CGSize(width: 16, height: 9),
                preparedOutputExtent: (width: 3, height: 2),
                geometryProduct: product,
                providerOutputMVP: providerMVP,
                consumerOutputMVP: consumerMVP,
                frameEpoch: 20,
                failureReason: &reason
            ) == nil && reason == expectedReason
        }
        let wrongLayerGeometryProduct = SceneGeometryProduct(
            ownerLayerID: 899,
            samplingTexture: geometryAtlas,
            resourceGeneration: 7,
            isPreparedForPublication: { _ in true },
            encode: { _, _, _, _, _, _ in true },
            authoredSize: SIMD2(4, 3),
            effectSourceExtentContract: .exactSamplingTexture
        )
        let wrongGenerationGeometryProduct = SceneGeometryProduct(
            ownerLayerID: 800,
            samplingTexture: geometryAtlas,
            resourceGeneration: 0,
            isPreparedForPublication: { _ in true },
            encode: { _, _, _, _, _, _ in true },
            authoredSize: SIMD2(4, 3),
            effectSourceExtentContract: .exactSamplingTexture
        )
        var mismatchedPlacement = matrix_identity_float4x4
        mismatchedPlacement.columns.3.x = 1
        let geometryWrongLayerRejected = geometryReservationRejected(
            product: wrongLayerGeometryProduct,
            providerTexture: geometryAtlas,
            expectedReason: "geometry-provider-source-identity-invalid"
        )
        let geometryWrongSourceRejected = geometryReservationRejected(
            product: geometryProduct,
            providerTexture: geometryGraphOutput,
            expectedReason: "geometry-provider-source-identity-invalid"
        )
        let geometryWrongGenerationRejected = geometryReservationRejected(
            product: wrongGenerationGeometryProduct,
            providerTexture: geometryAtlas,
            expectedReason: "geometry-provider-source-identity-invalid"
        )
        let geometryPlacementMismatchRejected = geometryReservationRejected(
            product: geometryProduct,
            providerTexture: geometryAtlas,
            consumerMVP: mismatchedPlacement,
            expectedReason: "geometry-provider-placement-mismatch"
        )

        let staleGeometryRuntime = geometryRuntime()
        var staleGeometryFailure: String?
        _ = staleGeometryRuntime.reserveEffectInput(
            for: geometryBinding,
            providerLayer: geometryProvider,
            providerTexture: geometryAtlas,
            providerCandidate: nil,
            layerMVP: matrix_identity_float4x4,
            viewportSize: CGSize(width: 16, height: 9),
            preparedOutputExtent: (width: 3, height: 2),
            geometryProduct: geometryProduct,
            providerOutputMVP: matrix_identity_float4x4,
            consumerOutputMVP: matrix_identity_float4x4,
            frameEpoch: 21,
            failureReason: &staleGeometryFailure
        )
        let staleGeometryRegistry = SceneFrameTextureRegistry(frameEpoch: 22)
        let staleGeometryRejected = staleGeometryRuntime
            .publishGraphOutputIfRequired(
                layerID: 800,
                texture: geometryGraphOutput,
                publicationRole: .visibleMainLoop,
                textureRegistry: staleGeometryRegistry,
                commandBuffer: commandBuffer,
                geometryProduct: geometryProduct
            ) == .invalid(
                reasonCode: "named-provider-reservation-missing"
            )

        func failedGeometryPublication(
            prepared: Bool,
            encodeResult: Bool,
            frameEpoch: UInt64
        ) -> Bool {
            let product = SceneGeometryProduct(
                ownerLayerID: 800,
                samplingTexture: geometryAtlas,
                resourceGeneration: 8,
                isPreparedForPublication: { _ in prepared },
                encode: { _, _, _, _, _, _ in encodeResult },
                authoredSize: SIMD2(4, 3),
                effectSourceExtentContract: .exactSamplingTexture
            )
            let runtime = geometryRuntime()
            var reason: String?
            guard runtime.reserveEffectInput(
                for: geometryBinding,
                providerLayer: geometryProvider,
                providerTexture: geometryAtlas,
                providerCandidate: nil,
                layerMVP: matrix_identity_float4x4,
                viewportSize: CGSize(width: 16, height: 9),
                preparedOutputExtent: (width: 3, height: 2),
                geometryProduct: product,
                providerOutputMVP: matrix_identity_float4x4,
                consumerOutputMVP: matrix_identity_float4x4,
                frameEpoch: frameEpoch,
                failureReason: &reason
            ) != nil, reason == nil else { return false }
            let registry = SceneFrameTextureRegistry(frameEpoch: frameEpoch)
            return runtime.publishGraphOutputIfRequired(
                layerID: 800,
                texture: geometryGraphOutput,
                publicationRole: .visibleMainLoop,
                textureRegistry: registry,
                commandBuffer: commandBuffer,
                geometryProduct: product
            ) == .unavailable(
                reasonCode: prepared
                    ? "geometry-provider-encode-unavailable"
                    : "geometry-provider-pose-unavailable"
            ) && registry.readyPublicationCount == 0
        }
        let geometryPoseNotReadyRejected = failedGeometryPublication(
            prepared: false,
            encodeResult: true,
            frameEpoch: 23
        )
        let geometryEncodeFailureRejected = failedGeometryPublication(
            prepared: true,
            encodeResult: false,
            frameEpoch: 24
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
            251, 17, 29, 5,
            41, 253, 67, 23,
            79, 83, 197, 91,
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
        ) == .unavailable(reasonCode: "graph-provider-raw-capture-unavailable")
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
            ) == .published
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
            publicationRole: .visibleMainLoop,
            textureRegistry: registry,
            commandBuffer: commandBuffer
        ) == .invalid(
            reasonCode: "named-provider-publication-identity-invalid"
        )
        let failedPublicationLeftReservationUnpublished =
            registry.readyPublicationCount == 0
        let published = runtime.publishGraphOutputIfRequired(
            layerID: 400,
            texture: output,
            publicationRole: .visibleMainLoop,
            textureRegistry: registry,
            commandBuffer: commandBuffer,
            content: .data
        ) == .published
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
        ) == .published
            && SceneOffscreenEffectRenderer.lastTextureFrame0
                == capturedUV.uniform0
            && SceneOffscreenEffectRenderer.lastTextureFrame1
                == capturedUV.uniform1
            && SceneOffscreenEffectRenderer.lastSourceSampling == SIMD2(3, 0)
            && captureRegistry.readyPublicationCount == 1
            && captureRegistry.typedPublicationCount == 1
        let modelSolidProvider = SceneRenderDescriptor.Layer(
            id: 500,
            contentKind: "solid",
            utilityLayer: nil,
            alpha: 1,
            colorRGB: [1, 1, 1]
        )
        let modelRuntime = SceneDependencyFrameRuntime(
            descriptor: .init(
                layers: [modelSolidProvider],
                bindings: [:],
                graphOutputProviderLayerIDs: [],
                staticModelConsumerProviders: [610: 500]
            ),
            visibleLayerIDs: [],
            executableUtilityConsumerLayerIDs: [],
            device: device
        )
        let modelRegistry = SceneFrameTextureRegistry(frameEpoch: 13)
        let inactiveModelProviderDoesNotCapture = !modelRuntime.requiresCapture(
            for: 500,
            activeStaticModelConsumerLayerIDs: []
        )
        let activeModelProviderCaptures = modelRuntime.requiresCapture(
            for: 500,
            activeStaticModelConsumerLayerIDs: [610]
        ) && modelRuntime.captureProviderIfRequired(
            layer: modelSolidProvider,
            sourceTexture: source,
            sourceCandidate: nil,
            providerAlpha: 0.25,
            providerColor: SIMD3(0.2, 0.4, 0.6),
            layerMVP: matrix_identity_float4x4,
            viewportSize: CGSize(width: 2, height: 2),
            pipeline: .init(),
            textureRegistry: modelRegistry,
            mainPass: .init(texture: source, commandBuffer: commandBuffer)
        ) == .published
        let modelInput = modelRuntime.staticModelNamedAlbedo(
            for: 610,
            materialPath: "materials/unseen/runtime.json",
            expectedReference: .init(
                providerLayerID: 500,
                variant: .primary
            ),
            textureRegistry: modelRegistry
        )
        let modelProviderCarriesDynamicAppearance = activeModelProviderCaptures
            && SceneOffscreenEffectRenderer.lastAlpha == 0.25
            && SceneOffscreenEffectRenderer.lastTint == SIMD4(0.2, 0.4, 0.6, 1)
            && modelInput?.texture !== source
            && modelInput?.frameEpoch == 13
            && modelInput?.isPremultiplied == true
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
        var geometryPublicationBytes = [UInt8](repeating: 255, count: 4 * 3 * 4)
        geometryInput?.texture.getBytes(
            &geometryPublicationBytes,
            bytesPerRow: 4 * 4,
            from: MTLRegionMake2D(0, 0, 4, 3),
            mipmapLevel: 0
        )
        let geometryGraphOutputWasRasterInput = gpuCompleted
            && encodedGeometrySource === geometryGraphOutput
            && geometryPublicationBytes.allSatisfy { $0 == 0 }
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
        let inactiveProviderNeedsNoReservation = runtime.installPreparedGraphOutputs(
            [400: output], frameEpoch: 14
        ) && !runtime.requiresDemandedGraphOutputCapture(for: 400)
        let result: [String: Any] = [
            "metalAvailable": true,
            "inactiveProviderNeedsNoReservation": inactiveProviderNeedsNoReservation,
            "reserved": provisionalInput != nil && reservationFailure == nil,
            "mixedConsumerKindsShareProviderPublication":
                mixedConsumerKindsShareProviderPublication,
            "aggregatePublicationMissIsUnavailable":
                aggregatePublicationMissIsUnavailable,
            "aggregatePublicationIdentityDriftIsInvalid":
                aggregatePublicationIdentityDriftIsInvalid,
            "preparedExtentReserved": preparedExtentInput?.texture.width == 8
                && preparedExtentInput?.texture.height == 4
                && preparedExtentFailure == nil
                && physicalCarrier.width == 7
                && physicalCarrier.height == 5,
            "preparedExtentInstalled": preparedExtentInstalled,
            "preparedExtentFallbackCaptured": preparedExtentFallbackCaptured,
            "preparedExtentCapturePublished": preparedExtentCapturePublished,
            "preparedExtentPublished": preparedExtentPublished,
            "preparedExtentWrongSizeRejected": preparedExtentWrongSizeRejected,
            "oversizedRasterizedPublished": oversizedRasterizedPublished,
            "oversizedDataRejected": oversizedDataRejected,
            "preparedExtentTargetBelowSourceRejected":
                preparedExtentTargetBelowSourceRejected,
            "geometryReservation": geometryInput?.texture.width == 4
                && geometryInput?.texture.height == 3
                && geometryReservationFailure == nil,
            "geometryPreparedOutputInstalled": geometryPreparedOutputInstalled,
            "geometryPublished": geometryPublished,
            "geometryPublishedExactReservation":
                geometryPublishedExactReservation,
            "oversizedGeometryNormalized": oversizedGeometryNormalized,
            "oversizedGeometryKeepsAuthoredLocalProjection":
                oversizedGeometryKeepsAuthoredLocalProjection,
            "geometryGraphOutputWasRasterInput":
                geometryGraphOutputWasRasterInput,
            "geometryWrongLayerRejected": geometryWrongLayerRejected,
            "geometryWrongSourceRejected": geometryWrongSourceRejected,
            "geometryWrongGenerationRejected": geometryWrongGenerationRejected,
            "geometryPlacementMismatchRejected":
                geometryPlacementMismatchRejected,
            "staleGeometryRejected": staleGeometryRejected,
            "geometryPoseNotReadyRejected": geometryPoseNotReadyRejected,
            "geometryEncodeFailureRejected": geometryEncodeFailureRejected,
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
            "namedDataRetained": readyInput?.content == .data
                && directInput?.content == .data,
            "readyUsesDistinctNamedTarget":
                readyInput?.texture === provisionalInput?.texture
                && readyInput?.texture !== output,
            "directInputUsesDistinctNamedTarget":
                directInput?.texture === provisionalInput?.texture
                && directInput?.texture !== output,
            "capturedNonDefaultSourceAtom": capturedNonDefaultSourceAtom,
            "graphOutputTypedPublication": registry.typedPublicationCount == 1,
            "captureTypedPublication": captureRegistry.typedPublicationCount == 1,
            "inactiveModelProviderDoesNotCapture":
                inactiveModelProviderDoesNotCapture,
            "modelProviderCarriesDynamicAppearance":
                modelProviderCarriesDynamicAppearance,
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
        self.maxDiff = None
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
                    str(AGGREGATE_VALIDATION_RUNTIME_SOURCE),
                    str(GEOMETRY_RUNTIME_SOURCE),
                    str(EFFECT_INPUT_RESOLUTION_RUNTIME_SOURCE),
                    str(STATIC_MODEL_RUNTIME_SOURCE),
                    str(
                        REPOSITORY_ROOT
                        / "MyWallpaperX/Core/SteamWorkshopScene/Diagnostics/ScenePerformanceCounterHub.swift"
                    ),
                    str(
                        REPOSITORY_ROOT
                        / "MyWallpaperX/Core/SteamWorkshopScene/Diagnostics/SceneGPUCensus.swift"
                    ),
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
                    "inactiveProviderNeedsNoReservation": True,
                    "reserved": True,
                    "mixedConsumerKindsShareProviderPublication": True,
                    "aggregatePublicationMissIsUnavailable": True,
                    "aggregatePublicationIdentityDriftIsInvalid": True,
                    "preparedExtentReserved": True,
                    "preparedExtentInstalled": True,
                    "preparedExtentFallbackCaptured": True,
                    "preparedExtentCapturePublished": True,
                    "preparedExtentPublished": True,
                    "preparedExtentWrongSizeRejected": True,
                    "preparedExtentTargetBelowSourceRejected": True,
                    "oversizedRasterizedPublished": True,
                    "oversizedDataRejected": True,
                    "geometryReservation": True,
                    "geometryPreparedOutputInstalled": True,
                    "geometryPublished": True,
                    "geometryPublishedExactReservation": True,
                    "oversizedGeometryNormalized": True,
                    "oversizedGeometryKeepsAuthoredLocalProjection": True,
                    "geometryGraphOutputWasRasterInput": True,
                    "geometryWrongLayerRejected": True,
                    "geometryWrongSourceRejected": True,
                    "geometryWrongGenerationRejected": True,
                    "geometryPlacementMismatchRejected": True,
                    "staleGeometryRejected": True,
                    "geometryPoseNotReadyRejected": True,
                    "geometryEncodeFailureRejected": True,
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
                    "graphOutputTypedPublication": True,
                    "captureTypedPublication": True,
                    "gpuCompleted": True,
                    "copiedGraphOutputBytes": True,
                    "namedDataRetained": True,
                    "readyUsesDistinctNamedTarget": True,
                    "directInputUsesDistinctNamedTarget": True,
                    "capturedNonDefaultSourceAtom": True,
                    "inactiveModelProviderDoesNotCapture": True,
                    "modelProviderCarriesDynamicAppearance": True,
                    "wrongSizeRejected": True,
                    "epochAdvanceClearsReservation": True,
                },
            )


if __name__ == "__main__":
    unittest.main()
