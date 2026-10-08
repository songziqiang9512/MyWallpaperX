#!/usr/bin/env python3

from __future__ import annotations

import json
import hashlib
import os
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
GEOMETRY_PRODUCT_SOURCE = (
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Geometry/SceneGeometryProduct.swift"
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
    struct ColorTargetFormat { let metalPixelFormat: MTLPixelFormat = .bgra8Unorm }
    let colorTargetFormat = ColorTargetFormat()
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

    private let pixelFormat: MTLPixelFormat

    init(device: MTLDevice, pixelFormat: MTLPixelFormat) {
        self.device = device
        self.pixelFormat = pixelFormat
    }

    func texture(for layerID: Int, width: Int, height: Int) -> MTLTexture? {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: pixelFormat,
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
enum StubAlpha: Equatable { case premultipliedAlpha, straightAlpha, opaque }
enum StubColor: Equatable { case resolved(StubAlpha) }
enum SceneTextureContent: Equatable {
    case color(StubColor)
    case data
    init(isResolved: Bool) { self = .color(.resolved(.premultipliedAlpha)) }
    var isResolved: Bool { true }
    var isColorContent: Bool { self != .data }
}

struct SceneTextureCandidate {
    let texture: MTLTexture
    let purpose: SceneTexturePurpose
    let content: SceneTextureContent
    let sampling: SceneTextureSampling
    let uvTransform: SceneTextureUVTransform
    // This older regression shell uses identity-only prepared candidates.
    // Actual metadata admission is exercised by the native-owner gate below.
    var physicalSize: CGSize { CGSize(width: texture.width, height: texture.height) }
    var mappedSize: CGSize { physicalSize }
    func materialProgramUVTransform() -> SceneTextureUVTransform? { uvTransform }

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
    typealias AuxiliaryRetainer = (@escaping () -> Void) -> Void
    var prepare: ((MTLCommandBuffer, SIMD2<Int>, simd_float4x4, AuxiliaryRetainer) -> Void)? = nil
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

    func retainAuxiliaryRelease(_ release: @escaping () -> Void) {
        commandBuffer.addCompletedHandler { _ in release() }
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
                reasonCode: "named-provider-publication-target-extent-invalid"
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
        // Hidden effect-chain provider under a resolvedMaterial binding:
        // within-cap prepared extents keep identity, over-cap extents
        // normalize, and the rasterized publication publishes color /
        // fails closed for data. (A reservation whose extent differs from
        // normalized(source) is unreachable through reserveEffectInput -
        // both derive from the same function - so the mismatch guard is
        // exercised implicitly by these shapes.)
        let hiddenChainProvider = SceneRenderDescriptor.Layer(
            id: 800,
            contentKind: "image",
            utilityLayer: nil,
            alpha: 1,
            colorRGB: [1, 1, 1],
            effects: [.init(visible: true)]
        )
        let hiddenChainBinding = SceneDependencyRenderPlan.Binding(
            consumerLayerID: 801,
            providerLayerID: 800,
            slot: .init(effectID: "hidden", passIndex: 0, slotIndex: 1),
            blendMode: 0,
            kind: .resolvedMaterial
        )
        let hiddenChainRuntime = SceneDependencyFrameRuntime(
            descriptor: .init(
                layers: [hiddenChainProvider],
                bindings: [801: hiddenChainBinding],
                graphOutputProviderLayerIDs: [800]
            ),
            visibleLayerIDs: [800, 801],
            executableUtilityConsumerLayerIDs: [],
            device: device
        )
        var hiddenWithinCapFailure: String?
        let hiddenWithinCap = hiddenChainRuntime.reserveEffectInput(
            for: hiddenChainBinding,
            providerLayer: hiddenChainProvider,
            providerTexture: nil,
            providerCandidate: nil,
            layerMVP: matrix_identity_float4x4,
            viewportSize: CGSize(width: 1024, height: 512),
            preparedOutputExtent: (width: 1024, height: 512),
            frameEpoch: 31,
            failureReason: &hiddenWithinCapFailure
        )
        let hiddenOverCapRuntime = SceneDependencyFrameRuntime(
            descriptor: .init(
                layers: [hiddenChainProvider],
                bindings: [801: hiddenChainBinding],
                graphOutputProviderLayerIDs: [800]
            ),
            visibleLayerIDs: [800, 801],
            executableUtilityConsumerLayerIDs: [],
            device: device
        )
        var hiddenOverCapFailure: String?
        let hiddenOverCap = hiddenOverCapRuntime.reserveEffectInput(
            for: hiddenChainBinding,
            providerLayer: hiddenChainProvider,
            providerTexture: nil,
            providerCandidate: nil,
            layerMVP: matrix_identity_float4x4,
            viewportSize: CGSize(width: 4096, height: 2048),
            preparedOutputExtent: (width: 4096, height: 2048),
            frameEpoch: 32,
            failureReason: &hiddenOverCapFailure
        )
        let hiddenOverCapOutput = texture(
            device,
            width: 4096,
            height: 2048,
            label: "hidden-chain-oversized-output"
        )
        let hiddenOverCapRegistry = SceneFrameTextureRegistry(frameEpoch: 32)
        let hiddenOverCapInstalled = hiddenOverCapRuntime
            .installPreparedGraphOutputs(
                [800: hiddenOverCapOutput],
                frameEpoch: 32
            )
        let hiddenOverCapPublished = hiddenOverCapRuntime
            .publishGraphOutputIfRequired(
                layerID: 800,
                texture: hiddenOverCapOutput,
                publicationRole: .namedProviderPrepass,
                textureRegistry: hiddenOverCapRegistry,
                commandBuffer: commandBuffer,
                imagePipeline: SceneImageLayerPipeline()
            ) == .published
        let hiddenDataRejected = hiddenOverCapRuntime
            .publishGraphOutputIfRequired(
                layerID: 800,
                texture: hiddenOverCapOutput,
                publicationRole: .namedProviderPrepass,
                textureRegistry: hiddenOverCapRegistry,
                commandBuffer: commandBuffer,
                content: .data,
                imagePipeline: SceneImageLayerPipeline()
            ) == .invalid(
                reasonCode: "named-provider-publication-content-mismatch"
            )
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
                        "named-provider-publication-content-mismatch"
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
        var encodedGeometryAssociation: UInt32 = 99
        let geometryProduct = SceneGeometryProduct(
            ownerLayerID: 800,
            samplingTexture: geometryAtlas,
            resourceGeneration: 7,
            isPreparedForPublication: { candidate in
                candidate === commandBuffer
            },
            encode: { _, sourceTexture, _, _, uniforms, _ in
                encodedGeometrySource = sourceTexture
                encodedGeometryAssociation = uniforms.sourceSampling.y
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
                geometryProduct: geometryProduct,
                content: .color(.resolved(.straightAlpha))
            ) == .published
        let geometryStraightAssociatedExactlyOnce = encodedGeometryAssociation == 1
            && geometryRegistry.completeNamedLayerTargetResource(
                reference: .init(providerLayerID: 800, variant: .primary),
                frameEpoch: 19
            )?.publication.candidate.content == .color(.resolved(.premultipliedAlpha))
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
        // The production GeometryProduct requires its caller to own auxiliary
        // releases. A missing retainer must reject before prepare or color
        // encode, leave the reservation unpublished, and permit a later retry.
        var auxiliaryOrder: [String] = [], auxiliaryExtent = SIMD2<Int>.zero
        var auxiliaryReleases: [() -> Void] = []
        defer { auxiliaryReleases.forEach { $0() } }
        let auxiliaryProduct = SceneGeometryProduct(
            ownerLayerID: 800, samplingTexture: geometryAtlas, resourceGeneration: 8,
            prepare: { submitted, extent, _, retain in
                precondition(submitted === commandBuffer)
                let blit = submitted.makeBlitCommandEncoder()!
                blit.endEncoding()
                auxiliaryOrder.append("prepare"); auxiliaryExtent = extent
                retain({})
            },
            isPreparedForPublication: { _ in true },
            encode: { _, _, _, _, _, _ in auxiliaryOrder.append("encode"); return true },
            authoredSize: SIMD2(4, 3), effectSourceExtentContract: .exactSamplingTexture
        )
        let auxiliaryRuntime = geometryRuntime()
        var auxiliaryFailure: String?
        let auxiliaryInput = auxiliaryRuntime.reserveEffectInput(
            for: geometryBinding, providerLayer: geometryProvider,
            providerTexture: geometryAtlas, providerCandidate: nil,
            layerMVP: matrix_identity_float4x4, viewportSize: CGSize(width: 16, height: 9),
            preparedOutputExtent: (width: 3, height: 2), geometryProduct: auxiliaryProduct,
            providerOutputMVP: matrix_identity_float4x4, consumerOutputMVP: matrix_identity_float4x4,
            frameEpoch: 25, failureReason: &auxiliaryFailure
        )
        let auxiliaryRegistry = SceneFrameTextureRegistry(frameEpoch: 25)
        let missingAuxiliaryOwnerRejected = auxiliaryInput != nil && auxiliaryFailure == nil
            && auxiliaryRuntime.publishGraphOutputIfRequired(
                layerID: 800, texture: geometryGraphOutput, publicationRole: .visibleMainLoop,
                textureRegistry: auxiliaryRegistry, commandBuffer: commandBuffer,
                geometryProduct: auxiliaryProduct
            ) == .unavailable(reasonCode: "geometry-provider-auxiliary-owner-unavailable")
            && auxiliaryOrder.isEmpty && auxiliaryRegistry.readyPublicationCount == 0
        let ownedAuxiliaryPreparedBeforeColor = auxiliaryRuntime.publishGraphOutputIfRequired(
            layerID: 800, texture: geometryGraphOutput, publicationRole: .visibleMainLoop,
            textureRegistry: auxiliaryRegistry, commandBuffer: commandBuffer,
            geometryProduct: auxiliaryProduct, retainAuxiliary: { auxiliaryReleases.append($0) }
        ) == .published && auxiliaryOrder == ["prepare", "encode"]
            && auxiliaryExtent == SIMD2(4, 3) && auxiliaryReleases.count == 1
            && auxiliaryRegistry.completeNamedLayerTargetTexture(
                reference: .init(providerLayerID: 800, variant: .primary), frameEpoch: 25
            ) === auxiliaryInput?.texture
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
        // A second owner phase may ask the same provider to publish the same
        // graph ticket after the first publication has already completed. It
        // must reuse the typed reservation without requiring another blit.
        let completedQueue = device.makeCommandQueue()!
        let completedBuffer = completedQueue.makeCommandBuffer()!
        completedBuffer.commit()
        completedBuffer.waitUntilCompleted()
        let repeatedPublicationReusesCompletedReservation = runtime
            .publishGraphOutputIfRequired(
                layerID: 400,
                texture: output,
                publicationRole: .namedProviderPrepass,
                textureRegistry: registry,
                commandBuffer: completedBuffer,
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
            "hiddenWithinCapIdentity": hiddenWithinCap?.texture.width == 1_024
                && hiddenWithinCap?.texture.height == 512
                && hiddenWithinCapFailure == nil,
            "hiddenOverCapNormalized": hiddenOverCap?.texture.width == 2_048
                && hiddenOverCap?.texture.height == 1_024
                && hiddenOverCapFailure == nil
                && hiddenOverCapInstalled,
            "hiddenOverCapPublished": hiddenOverCapPublished,
            "hiddenDataRejected": hiddenDataRejected,
            "oversizedRasterizedPublished": oversizedRasterizedPublished,
            "oversizedDataRejected": oversizedDataRejected,
            "preparedExtentTargetBelowSourceRejected":
                preparedExtentTargetBelowSourceRejected,
            "geometryReservation": geometryInput?.texture.width == 4
                && geometryInput?.texture.height == 3
                && geometryReservationFailure == nil,
            "geometryPreparedOutputInstalled": geometryPreparedOutputInstalled,
            "geometryPublished": geometryPublished,
            "geometryStraightAssociatedExactlyOnce": geometryStraightAssociatedExactlyOnce,
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
            "missingAuxiliaryOwnerRejected": missingAuxiliaryOwnerRejected,
            "ownedAuxiliaryPreparedBeforeColor": ownedAuxiliaryPreparedBeforeColor,
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
            "repeatedPublicationReusesCompletedReservation":
                repeatedPublicationReusesCompletedReservation,
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

# Legacy named-model scaffolds still extract the prepared peripheral leaves
# above. These two runtime gates compile the real GeometryProduct instead.
GEOMETRY_HARNESS_SOURCE = (
    HARNESS_SOURCE[:HARNESS_SOURCE.index("struct SceneGeometryProduct {")]
    + HARNESS_SOURCE[HARNESS_SOURCE.index("extension SIMD3 where Scalar == Float {"):]
)


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
            harness.write_text(GEOMETRY_HARNESS_SOURCE, encoding="utf-8")
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
                    str(GEOMETRY_PRODUCT_SOURCE),
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
                    "hiddenWithinCapIdentity": True,
                    "hiddenOverCapNormalized": True,
                    "hiddenOverCapPublished": True,
                    "hiddenDataRejected": True,
                    "oversizedRasterizedPublished": True,
                    "oversizedDataRejected": True,
                    "geometryReservation": True,
                    "geometryPreparedOutputInstalled": True,
                    "geometryPublished": True,
                    "geometryStraightAssociatedExactlyOnce": True,
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
                    "missingAuxiliaryOwnerRejected": True,
                    "ownedAuxiliaryPreparedBeforeColor": True,
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
                    "repeatedPublicationReusesCompletedReservation": True,
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


ATLAS_NATIVE_MAIN = r'''
@main enum AtlasNamedProbe {
    static func texture(_ device: MTLDevice, _ width: Int, _ height: Int) -> MTLTexture {
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm,
            width: width, height: height, mipmapped: false)
        d.storageMode = .shared; d.usage = [.shaderRead, .renderTarget]
        return device.makeSceneTexture(descriptor: d)!
    }
    static func candidate(_ t: MTLTexture) -> SceneTextureCandidate {
        .init(texture: t, identity: .builtIn(name: "own-atlas"),
            generation: .immutable(revision: 1), purpose: .premultipliedColor,
            content: .color(.resolved(.premultipliedAlpha)),
            physicalSize: CGSize(width: t.width, height: t.height),
            mappedSize: CGSize(width: t.width, height: t.height),
            uvTransform: .init(origin: SIMD2(0.25, 0.25),
                xAxis: SIMD2(0.5, 0), yAxis: SIMD2(0, 0.5)), sampling: .linearClamp)
    }
    static func main() throws {
        guard let d = MTLCreateSystemDefaultDevice() else {
            print("{\"metalUnavailable\":true}"); return
        }
        let source = texture(d, 64, 32), registry = SceneFrameTextureRegistry()
        let provider = SceneRenderDescriptor.Layer(id: 700, contentKind: "image",
            utilityLayer: nil, alpha: 1, colorRGB: [1, 1, 1], effects: [.init(visible: true)])
        let binding = SceneDependencyRenderPlan.Binding(consumerLayerID: 701,
            providerLayerID: 700, slot: .init(effectID: "owned", passIndex: 0, slotIndex: 1),
            blendMode: 0, kind: .visibleImageGraphOutput)
        let runtime = SceneDependencyFrameRuntime(descriptor: .init(layers: [provider],
            bindings: [701: binding], graphOutputProviderLayerIDs: [700]),
            visibleLayerIDs: [700, 701], executableUtilityConsumerLayerIDs: [], device: d)
        let epoch = registry.beginFrame(frameIndex: 1, layerSources: [:])
        var reason: String?
        let reserved = runtime.reserveEffectInput(for: binding, providerLayer: provider,
            providerTexture: source, providerCandidate: candidate(source),
            layerMVP: matrix_identity_float4x4, viewportSize: CGSize(width: 80, height: 40),
            preparedOutputExtent: (80, 40), frameEpoch: epoch, failureReason: &reason)
        var report: [String: Any] = ["reservationAccepted": reserved != nil,
            "reservationReason": reason as Any? ?? NSNull(),
            "sourceExtent": [source.width, source.height],
            "targetExtent": [reserved?.texture.width ?? 0, reserved?.texture.height ?? 0]]
        if reserved != nil {
            report["publication"] = try publication(d)
            report["safety"] = try safety(d)
            report["lifecycle"] = try lifecycle(d)
            report["budget"] = budget(d)
            report["geometryRepresentation"] = geometryRepresentation(d)
        }
        print(String(decoding: try JSONSerialization.data(withJSONObject: report,
            options: [.sortedKeys]), as: UTF8.self))
    }
}
'''


ATLAS_NATIVE_EXTRA = r'''
extension AtlasNamedProbe {
    static func geometryRepresentation(_ d: MTLDevice) -> [[String: Any]] {
        let q = d.makeCommandQueue()!, image = SceneImageLayerPipeline(device: d)!
        let provider = SceneRenderDescriptor.Layer(id: 800, contentKind: "image",
            utilityLayer: nil, alpha: 1, colorRGB: [1, 1, 1])
        let binding = SceneDependencyRenderPlan.Binding(consumerLayerID: 801,
            providerLayerID: 800, slot: .init(effectID: "owned-geometry", passIndex: 0, slotIndex: 1),
            blendMode: 0, kind: .geometryLayer, requiresResolvedMaterialProgram: true)
        var rows: [[String: Any]] = []
        for straight in [false, true] {
            for alpha: UInt8 in [0, 128, 255] {
                let runtime = SceneDependencyFrameRuntime(descriptor: .init(layers: [provider],
                    bindings: [801: binding], graphOutputProviderLayerIDs: [800]),
                    visibleLayerIDs: [800, 801], executableUtilityConsumerLayerIDs: [], device: d)
                let registry = SceneFrameTextureRegistry(), source = texture(d, 1, 1)
                let associated = [64, 128, 200].map { UInt8((Float($0) * Float(alpha) / 255).rounded()) }
                let input = (straight ? [UInt8(64), 128, 200] : associated) + [alpha]
                input.withUnsafeBytes { source.replace(region: MTLRegionMake2D(0, 0, 1, 1),
                    mipmapLevel: 0, withBytes: $0.baseAddress!, bytesPerRow: 4) }
                let epoch = registry.beginFrame(frameIndex: 1, layerSources: [:]), cb = q.makeCommandBuffer()!
                var association: UInt32 = 99, encodes = 0
                let product = SceneGeometryProduct(ownerLayerID: 800, samplingTexture: source,
                    resourceGeneration: 1, isPreparedForPublication: { $0 === cb },
                    encode: { encoder, texture, _, mvp, uniforms, _ in
                        association = uniforms.sourceSampling.y; encodes += 1
                        image.bind(encoder: encoder)
                        image.drawLayer(texture: texture, mvp: mvp, uniforms: uniforms, encoder: encoder)
                        return true
                    }, authoredSize: SIMD2(1, 1), effectSourceExtentContract: .exactSamplingTexture)
                var reason: String?
                let reserved = runtime.reserveEffectInput(for: binding, providerLayer: provider,
                    providerTexture: source, providerCandidate: nil, layerMVP: matrix_identity_float4x4,
                    viewportSize: CGSize(width: 1, height: 1), preparedOutputExtent: (1, 1),
                    geometryProduct: product, providerOutputMVP: matrix_identity_float4x4,
                    consumerOutputMVP: matrix_identity_float4x4, frameEpoch: epoch, failureReason: &reason)
                let published = runtime.publishGraphOutputIfRequired(layerID: 800, texture: source,
                    publicationRole: .visibleMainLoop, textureRegistry: registry, commandBuffer: cb,
                    geometryProduct: product, content: .color(.resolved(straight ? .straightAlpha : .premultipliedAlpha)))
                let atom = registry.completeNamedLayerTargetResource(
                    reference: .init(providerLayerID: 800, variant: .primary), frameEpoch: epoch)
                let copied = reserved.map { readback(d, $0.texture, cb) }
                cb.commit(); cb.waitUntilCompleted()
                rows.append(["straight": straight, "alpha": alpha, "reserved": reserved != nil && reason == nil,
                    "published": status(published), "association": association, "encodes": encodes,
                    "actualPMA": atom?.publication.candidate.content == .color(.resolved(.premultipliedAlpha)),
                    "sourceUnchanged": read(source) == input, "pixel": copied.map(read) ?? [],
                    "expected": associated + [alpha], "completed": cb.status == .completed && cb.error == nil])
            }
        }
        return rows
    }
    static func fixture(_ d: MTLDevice, planned: Bool = true) ->
        (SceneRenderDescriptor.Layer, [SceneDependencyRenderPlan.Binding], SceneDependencyFrameRuntime) {
        let provider = SceneRenderDescriptor.Layer(id: 700, contentKind: "image",
            utilityLayer: nil, alpha: 1, colorRGB: [1, 1, 1], effects: planned ? [.init(visible: true)] : [])
        let bindings = [701, 702].map { consumer in
            SceneDependencyRenderPlan.Binding(consumerLayerID: consumer, providerLayerID: 700,
                slot: .init(effectID: "own-\(consumer)", passIndex: 0, slotIndex: 1),
                blendMode: 0, kind: planned ? .visibleImageGraphOutput : .imageLayerBlend)
        }
        let runtime = SceneDependencyFrameRuntime(descriptor: .init(layers: [provider],
            bindings: Dictionary(uniqueKeysWithValues: bindings.map { ($0.consumerLayerID, $0) }),
            graphOutputProviderLayerIDs: planned ? [700] : []), visibleLayerIDs: [700, 701, 702],
            executableUtilityConsumerLayerIDs: [], device: d)
        return (provider, bindings, runtime)
    }
    static func reserve(_ f: (SceneRenderDescriptor.Layer, [SceneDependencyRenderPlan.Binding], SceneDependencyFrameRuntime),
        _ source: MTLTexture, _ c: SceneTextureCandidate?, _ epoch: UInt64,
        _ extent: (Int, Int)? = (80, 40), consumer: Int = 0) -> (SceneDependencyEffectInput?, String?) {
        var reason: String?
        let input = f.2.reserveEffectInput(for: f.1[consumer], providerLayer: f.0,
            providerTexture: source, providerCandidate: c, layerMVP: matrix_identity_float4x4,
            viewportSize: CGSize(width: 80, height: 40), preparedOutputExtent: extent,
            frameEpoch: epoch, failureReason: &reason)
        return (input, reason)
    }
    static func altered(_ c: SceneTextureCandidate, texture t: MTLTexture? = nil,
        physical: CGSize? = nil, mapped: CGSize? = nil, uv: SceneTextureUVTransform? = nil,
        purpose: SceneTextureLoadPurpose? = nil, sampling: SceneTextureSampling? = nil) -> SceneTextureCandidate {
        .init(texture: t ?? c.texture, identity: c.identity, generation: c.generation,
            purpose: purpose ?? c.purpose, content: c.content, physicalSize: physical ?? c.physicalSize,
            mappedSize: mapped ?? c.mappedSize, uvTransform: uv ?? c.uvTransform,
            sampling: sampling ?? c.sampling)
    }
    static func status(_ value: SceneGraphOutputPublicationResult?) -> String {
        switch value {
        case .published: return "published"
        case let .invalid(reason): return "invalid:" + reason
        case let .unavailable(reason): return "unavailable:" + reason
        case nil: return "not-required"
        }
    }
    static func resolution(_ r: SceneDependencyFrameRuntime, _ registry: SceneFrameTextureRegistry) -> String {
        switch r.resolvedMaterialEffectInputResolution(for: 701, textureRegistry: registry) {
        case .ready: return "ready"
        case let .invalid(reason): return "invalid:" + reason
        case let .unavailable(reason): return "unavailable:" + reason
        }
    }
    // Deliberately distinct graph-final bytes, supplied at the prepared-output
    // boundary. This native gate does not claim to execute an effect compiler.
    static func bytes(_ width: Int, _ height: Int, _ phase: Int) -> [UInt8] {
        (0 ..< width * height).flatMap { i -> [UInt8] in
            let x = i % width, y = i / width
            return [UInt8((x * 3 + phase * 17) % 256), UInt8((y * 5 + phase * 31) % 256),
                    UInt8((x + y + phase * 43) % 256), 255]
        }
    }
    static func pattern(_ d: MTLDevice, _ width: Int, _ height: Int, _ phase: Int) -> MTLTexture {
        let t = texture(d, width, height), data = bytes(width, height, phase)
        data.withUnsafeBytes { t.replace(region: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0,
            withBytes: $0.baseAddress!, bytesPerRow: width * 4) }
        return t
    }
    static func read(_ t: MTLTexture) -> [UInt8] {
        var data = [UInt8](repeating: 0, count: t.width * t.height * 4)
        t.getBytes(&data, bytesPerRow: t.width * 4, from: MTLRegionMake2D(0, 0, t.width, t.height), mipmapLevel: 0)
        return data
    }
    static func readback(_ d: MTLDevice, _ source: MTLTexture, _ cb: MTLCommandBuffer) -> MTLTexture {
        let output = texture(d, source.width, source.height), blit = cb.makeBlitCommandEncoder()!
        blit.copy(from: source, sourceSlice: 0, sourceLevel: 0, sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
            sourceSize: MTLSize(width: source.width, height: source.height, depth: 1),
            to: output, destinationSlice: 0, destinationLevel: 0, destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0))
        blit.endEncoding(); return output
    }
    static func copies() -> UInt64 {
        ScenePerformanceCounterHub.shared.snapshot()[.graphOutputPublicationCopies] ?? 0
    }
    static func publication(_ d: MTLDevice) throws -> [[String: Any]] {
        let f = fixture(d), source = texture(d, 64, 32), registry = SceneFrameTextureRegistry()
        let q = d.makeCommandQueue()!, image = SceneImageLayerPipeline(device: d)!
        let reference = SceneNamedTextureReference(providerLayerID: 700, variant: .primary)
        var rows: [[String: Any]] = []
        for phase in [1, 2] {
            let epoch = registry.beginFrame(frameIndex: UInt64(phase), layerSources: [:])
            let c = phase == 1 ? candidate(source) : nil
            let first = reserve(f, source, c, epoch), second = reserve(f, source, c, epoch, consumer: 1)
            let before = resolution(f.2, registry), output = pattern(d, 80, 40, phase), cb = q.makeCommandBuffer()!
            let installed = f.2.installPreparedGraphOutputs([700: output], frameEpoch: epoch), count = copies()
            let published = status(f.2.publishGraphOutputIfRequired(layerID: 700, texture: output,
                publicationRole: .visibleMainLoop, textureRegistry: registry, commandBuffer: cb))
            let repeated = status(f.2.publishGraphOutputIfRequired(layerID: 700, texture: output,
                publicationRole: .visibleMainLoop, textureRegistry: registry, commandBuffer: cb))
            let inputs = [701, 702].compactMap { f.2.effectInput(for: $0, textureRegistry: registry) }
            let atom = registry.completeNamedLayerTargetResource(reference: reference, frameEpoch: epoch)
            var draws: [MTLTexture] = []
            for input in inputs {
                let target = texture(d, 80, 40)
                let pass = SceneMainPassEncoder(commandBuffer: cb, target: target,
                    clearColor: MTLClearColorMake(0, 0, 0, 1), clearEnabled: true)
                var mvp = matrix_identity_float4x4; mvp.columns.0.x = 2; mvp.columns.1.y = 2
                let encoder = pass.encoder()!; image.bind(encoder: encoder)
                image.drawLayer(texture: input.texture, mvp: mvp, uniforms: .neutral(), encoder: encoder)
                precondition(pass.finishEnsuringClear()); draws.append(target)
            }
            let copied = readback(d, first.0!.texture, cb)
            cb.commit(); cb.waitUntilCompleted(); registry.commitFramePublication()
            let expected = bytes(80, 40, phase)
            rows.append(["epoch": epoch, "candidateProvided": phase == 1,
                "installed": installed, "published": published, "repeated": repeated,
                "beforePublication": before, "resolution": resolution(f.2, registry),
                "shared": first.0?.texture === second.0?.texture && inputs.count == 2
                    && inputs.allSatisfy { $0.texture === first.0?.texture },
                "typed": atom?.publication.texture === first.0?.texture,
                "copies": copies() - count, "copiedExactly": read(copied) == expected,
                "consumerCount": draws.count,
                "consumerPixelsMatch": draws.allSatisfy { zip(read($0), expected).allSatisfy { abs(Int($0.0) - Int($0.1)) <= 1 } },
                "firstPixelBGRA": Array(read(copied).prefix(4)), "completed": cb.status == .completed && cb.error == nil])
        }
        return rows
    }
    static func safety(_ d: MTLDevice) throws -> [String: Any] {
        let source = texture(d, 64, 32), c = candidate(source), q = d.makeCommandQueue()!
        let bad: [(String, SceneTextureCandidate)] = [
            ("physical-nan", altered(c, physical: CGSize(width: CGFloat.nan, height: 32))),
            ("physical-noninteger", altered(c, physical: CGSize(width: 64.5, height: 32))),
            ("physical-mismatch", altered(c, physical: CGSize(width: 63, height: 32))),
            ("mapped-zero", altered(c, mapped: CGSize(width: 0, height: 32))),
            ("mapped-infinite", altered(c, mapped: CGSize(width: CGFloat.infinity, height: 32))),
            ("mapped-noninteger", altered(c, mapped: CGSize(width: 63.5, height: 32))),
            ("mapped-outbounds", altered(c, mapped: CGSize(width: 65, height: 32))),
            ("uv-nan", altered(c, uv: .init(origin: SIMD2(Float.nan, 0), xAxis: SIMD2(0.5, 0), yAxis: SIMD2(0, 0.5)))),
            ("uv-outbounds", altered(c, uv: .init(origin: SIMD2(0.75, 0), xAxis: SIMD2(0.5, 0), yAxis: SIMD2(0, 0.5)))),
            ("uv-negative", altered(c, uv: .init(origin: SIMD2(-0.25, 0), xAxis: SIMD2(0.5, 0), yAxis: SIMD2(0, 0.5)))),
            ("wrong-texture", altered(c, texture: texture(d, 64, 32))),
            ("wrong-purpose", altered(c, purpose: .preservedChannels))]
        var invalid: [[String: Any]] = []
        for (name, value) in bad {
            let f = fixture(d), registry = SceneFrameTextureRegistry(), epoch = registry.beginFrame(frameIndex: 1, layerSources: [:])
            let result = reserve(f, source, value, epoch)
            invalid.append(["name": name, "accepted": result.0 != nil, "reason": result.1 as Any? ?? NSNull(),
                "publication": status(f.2.publishGraphOutputIfRequired(layerID: 700, texture: source,
                    publicationRole: .visibleMainLoop, textureRegistry: registry, commandBuffer: q.makeCommandBuffer()!))])
        }
        let raw = fixture(d, planned: false), rawResult = reserve(raw, source, c, 1, nil)
        let nilRawResult = reserve(fixture(d, planned: false), source, nil, 1, nil)
        let invalidDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm,
            width: 64, height: 32, mipmapped: false)
        invalidDescriptor.usage = .renderTarget
        let invalidTexture = d.makeSceneTexture(descriptor: invalidDescriptor)!
        let invalidActualTexture = reserve(fixture(d), invalidTexture, nil, 1)
        let forged = reserve(fixture(d, planned: false), source, c, 1)
        let absent = reserve(fixture(d), source, c, 1, nil)
        let invalidExtent = reserve(fixture(d), source, c, 1, (0, 40))
        let fallbackFixture = fixture(d), fallbackRegistry = SceneFrameTextureRegistry()
        let fallbackEpoch = fallbackRegistry.beginFrame(frameIndex: 1, layerSources: [:])
        let fallbackSource = pattern(d, 64, 32, 6), fallbackCandidate = altered(candidate(fallbackSource), uv: .identity)
        let fallbackInput = reserve(fallbackFixture, fallbackSource, fallbackCandidate, fallbackEpoch, nil)
        let fallbackCB = q.makeCommandBuffer()!
        let fallbackPass = SceneMainPassEncoder(commandBuffer: fallbackCB, target: texture(d, 64, 32),
            clearColor: MTLClearColorMake(0, 0, 0, 1), clearEnabled: true)
        let fallbackPublished = status(fallbackFixture.2.captureGraphSourceFallbackIfRequired(
            layer: fallbackFixture.0, sourceTexture: fallbackSource, sourceCandidate: fallbackCandidate,
            layerMVP: matrix_identity_float4x4, viewportSize: CGSize(width: 64, height: 32),
            pipeline: SceneImageLayerPipeline(device: d)!, textureRegistry: fallbackRegistry, mainPass: fallbackPass))
        precondition(fallbackPass.finishEnsuringClear())
        let fallbackBytes = readback(d, fallbackInput.0!.texture, fallbackCB)
        fallbackCB.commit(); fallbackCB.waitUntilCompleted(); fallbackRegistry.commitFramePublication()
        let tiny = texture(d, 4096, 4096)
        let tinyCandidate = altered(candidate(tiny), mapped: CGSize(width: 1, height: 1),
            uv: .init(origin: .zero, xAxis: SIMD2(1.0 / 4096.0, 0), yAxis: SIMD2(0, 1.0 / 4096.0)))
        let tinyResult = reserve(fixture(d, planned: false), tiny, tinyCandidate, 1, nil)
        let f = fixture(d), registry = SceneFrameTextureRegistry(), epoch = registry.beginFrame(frameIndex: 1, layerSources: [:])
        let valid = reserve(f, source, c, epoch)
        let conflict = reserve(f, source, c, epoch, (81, 40))
        let wrongExtent = f.2.installPreparedGraphOutputs([700: texture(d, 79, 40)], frameEpoch: epoch)
        let wrongExtentPublication = status(f.2.publishGraphOutputIfRequired(layerID: 700, texture: texture(d, 79, 40),
            publicationRole: .visibleMainLoop, textureRegistry: registry, commandBuffer: q.makeCommandBuffer()!))
        let alias = f.2.installPreparedGraphOutputs([700: valid.0!.texture], frameEpoch: epoch)
        let aliasPublication = status(f.2.publishGraphOutputIfRequired(layerID: 700, texture: valid.0!.texture,
            publicationRole: .visibleMainLoop, textureRegistry: registry, commandBuffer: q.makeCommandBuffer()!))
        let output = pattern(d, 80, 40, 1), cb = q.makeCommandBuffer()!
        let good = status(f.2.publishGraphOutputIfRequired(layerID: 700, texture: output,
            publicationRole: .visibleMainLoop, textureRegistry: registry, commandBuffer: cb))
        let changed = status(f.2.publishGraphOutputIfRequired(layerID: 700, texture: pattern(d, 80, 40, 2),
            publicationRole: .visibleMainLoop, textureRegistry: registry, commandBuffer: cb))
        cb.commit(); cb.waitUntilCompleted(); registry.commitFramePublication()
        let nextEpoch = registry.beginFrame(frameIndex: 2, layerSources: [:])
        let staleRegistryRefused = !registry.publishReservedNamedLayerTarget(reference: .init(providerLayerID: 700, variant: .primary),
            frameEpoch: epoch, texture: valid.0!.texture)
        let stale = status(f.2.publishGraphOutputIfRequired(layerID: 700, texture: output,
            publicationRole: .visibleMainLoop, textureRegistry: registry, commandBuffer: q.makeCommandBuffer()!))
        return ["invalidCandidates": invalid, "rawMappingAccepted": rawResult.0 != nil,
            "rawMappingReason": rawResult.1 as Any? ?? NSNull(),
            "nilRawAccepted": nilRawResult.0 != nil, "nilRawReason": nilRawResult.1 as Any? ?? NSNull(),
            "invalidActualTextureAccepted": invalidActualTexture.0 != nil,
            "invalidActualTextureReason": invalidActualTexture.1 as Any? ?? NSNull(),
            "fakePlanReason": forged.1 as Any? ?? NSNull(), "missingPlanExtentReason": absent.1 as Any? ?? NSNull(),
            "fakePlanAccepted": forged.0 != nil, "missingPlanExtentAccepted": absent.0 != nil,
            "invalidPlanExtentAccepted": invalidExtent.0 != nil, "conflictAccepted": conflict.0 != nil,
            "invalidPlanExtentReason": invalidExtent.1 as Any? ?? NSNull(), "tinyRawAccepted": tinyResult.0 != nil,
            "plannedRawFallbackAccepted": fallbackInput.0 != nil, "plannedRawFallbackReason": fallbackInput.1 as Any? ?? NSNull(),
            "plannedRawFallbackPublication": fallbackPublished,
            "plannedRawFallbackPixels": zip(read(fallbackBytes), bytes(64, 32, 6)).allSatisfy { abs(Int($0.0) - Int($0.1)) <= 1 },
            "plannedRawFallbackCompleted": fallbackCB.status == .completed && fallbackCB.error == nil,
            "tinyRawReason": tinyResult.1 as Any? ?? NSNull(), "conflictReason": conflict.1 as Any? ?? NSNull(),
            "wrongExtentInstalled": wrongExtent, "wrongExtentPublication": wrongExtentPublication,
            "aliasInstalled": alias, "aliasPublication": aliasPublication,
            "goodPublication": good, "changedSourcePublication": changed,
            "staleRegistryRefused": staleRegistryRefused, "epochAdvanced": nextEpoch > epoch,
            "stalePublication": stale, "completed": cb.status == .completed && cb.error == nil]
    }
    static func lifecycle(_ d: MTLDevice) throws -> [String: Any] {
        let f = fixture(d), source = texture(d, 64, 32), q = d.makeCommandQueue()!, event = d.makeSharedEvent()!
        var cb: MTLCommandBuffer? = q.makeCommandBuffer()!
        cb!.encodeWaitForEvent(event, value: 1)
        defer { event.signaledValue = 1 }
        weak var oldTarget: MTLTexture?
        var copied: MTLTexture?, recoveryBytes: MTLTexture?, recoveryCB: MTLCommandBuffer?
        var result: [String: Any] = [:]
        autoreleasepool {
            let registry = SceneFrameTextureRegistry(), epoch = registry.beginFrame(frameIndex: 1, layerSources: [:])
            let first = reserve(f, source, candidate(source), epoch)
            oldTarget = first.0!.texture
            let output = pattern(d, 80, 40, 3)
            result["firstPublication"] = status(f.2.publishGraphOutputIfRequired(layerID: 700, texture: output,
                publicationRole: .visibleMainLoop, textureRegistry: registry, commandBuffer: cb!))
            copied = readback(d, first.0!.texture, cb!); registry.commitFramePublication(); cb!.commit()
            result["pending"] = cb!.status != .completed && cb!.status != .error
            let next = registry.beginFrame(frameIndex: 2, layerSources: [:]), second = reserve(f, source, candidate(source), next, (120, 60))
            let cancelled = q.makeCommandBuffer()!, nextOutput = pattern(d, 120, 60, 4)
            result["resizedDistinct"] = second.0?.texture !== first.0?.texture
                && second.0?.texture.width == 120 && second.0?.texture.height == 60
            result["cancelledPublication"] = status(f.2.publishGraphOutputIfRequired(layerID: 700, texture: nextOutput,
                publicationRole: .visibleMainLoop, textureRegistry: registry, commandBuffer: cancelled))
            registry.discardFramePublication()
            result["cancelledNotSubmitted"] = cancelled.status == .notEnqueued
            result["cancelledUnavailable"] = resolution(f.2, registry)
            let recoveryEpoch = registry.beginFrame(frameIndex: 3, layerSources: [:])
            let recovered = reserve(f, source, candidate(source), recoveryEpoch, (120, 60))
            let recoveredOutput = pattern(d, 120, 60, 5)
            recoveryCB = q.makeCommandBuffer()!
            result["recoveryEpochAdvanced"] = recoveryEpoch > next && next > epoch
            result["recoveryReserved"] = recovered.0 != nil && recovered.1 == nil
            result["recoveryPublication"] = status(f.2.publishGraphOutputIfRequired(layerID: 700, texture: recoveredOutput,
                publicationRole: .visibleMainLoop, textureRegistry: registry, commandBuffer: recoveryCB!))
            recoveryBytes = readback(d, recovered.0!.texture, recoveryCB!)
            registry.commitFramePublication(); recoveryCB!.commit()
        }
        result["oldTargetRetainedInFlight"] = oldTarget != nil
        event.signaledValue = 1; cb!.waitUntilCompleted()
        recoveryCB!.waitUntilCompleted()
        result["completed"] = cb!.status == .completed && cb!.error == nil
        result["oldPixelsSurviveResizeCancel"] = read(copied!) == bytes(80, 40, 3)
        cb = nil
        result["oldTargetReleasedAfterCompletion"] = oldTarget == nil
        result["recoveryCompleted"] = recoveryCB!.status == .completed && recoveryCB!.error == nil
        result["recoveryPixels"] = read(recoveryBytes!) == bytes(120, 60, 5)
        return result
    }
    static func budget(_ d: MTLDevice) -> [String: Any] {
        let f = fixture(d), source = texture(d, 64, 32), registry = SceneFrameTextureRegistry()
        let epoch = registry.beginFrame(frameIndex: 1, layerSources: [:]), b = SceneResourceBudget.shared
        let q = d.makeCommandQueue()!, output = pattern(d, 80, 40, 7), cb = q.makeCommandBuffer()!
        let rejectionsBefore = b.snapshot.rejectionCount
        let held = b.maximumBytes - b.snapshot.residentBytes
        precondition(b.reserve(held, kind: .gpu))
        let failed = reserve(f, source, candidate(source), epoch)
        let failedPublication = status(f.2.publishGraphOutputIfRequired(layerID: 700, texture: output,
            publicationRole: .visibleMainLoop, textureRegistry: registry, commandBuffer: cb))
        let rejected = b.snapshot.rejectionCount
        b.release(held, kind: .gpu)
        let recovered = reserve(f, source, candidate(source), epoch)
        return ["acceptedUnderExhaustion": failed.0 != nil, "reason": failed.1 as Any? ?? NSNull(),
            "budgetRejectionObserved": rejected > rejectionsBefore, "failedPublication": failedPublication,
            "recoveryAccepted": recovered.0 != nil && recovered.1 == nil,
            "unpublishedResolution": resolution(f.2, registry)]
    }
}
'''


def run_native_atlas_probe():
    # The existing scaffold supplies only already-prepared plan/peripheral
    # types. Runtime, pool, registry, candidates, allocation and Metal are real.
    # Import lazily: named-model fixtures already import this module's shell.
    from script.tests import test_scene_named_model_shadow as native
    from script.tests.test_scene_directional_shadow import run_swift

    parent = os.environ.get("MWX_ATLAS_NAMED_EVIDENCE")
    if parent:
        Path(parent).mkdir(parents=True, exist_ok=True)
    work = Path(tempfile.mkdtemp(prefix="atlas-named-", dir=parent))
    snapshot = work / "production"
    sources = list(native.DEPENDENCY_SOURCES)
    metal = REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Composition/SceneImageLayer.metal"
    ref = os.environ.get("MWX_ATLAS_NAMED_PRODUCT_REF")
    inputs = {}
    for source in [*sources, metal]:
        relative = source.relative_to(REPOSITORY_ROOT)
        data = (subprocess.check_output(["git", "show", f"{ref}:{relative}"], cwd=REPOSITORY_ROOT)
                if ref else source.read_bytes())
        frozen = snapshot / relative
        frozen.parent.mkdir(parents=True, exist_ok=True)
        frozen.write_bytes(data)
        digest = hashlib.sha256(data).hexdigest()
        if not ref and hashlib.sha256(source.read_bytes()).hexdigest() != digest:
            raise AssertionError(f"production source changed while freezing: {source}")
        inputs[str(source)] = {"frozen": str(frozen), "sha256": digest,
                               "productionRef": ref or "current-tree"}
    support = native.dependency_support() + ATLAS_NATIVE_MAIN + ATLAS_NATIVE_EXTRA
    identity = {"inputs": inputs, "harnessSHA256": hashlib.sha256(support.encode()).hexdigest(),
                "testSHA256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
                "scope": "real native owners; prepared plan and unused peripherals scaffolded"}
    (work / "input-manifest.json").write_text(json.dumps(identity, indent=2))
    previous = {key: os.environ.get(key) for key in
                ("MWX_DIRECTIONAL_SHADOW_EVIDENCE", "MWX_DIRECTIONAL_SHADOW_PRODUCT_SNAPSHOT")}
    os.environ["MWX_DIRECTIONAL_SHADOW_EVIDENCE"] = str(work)
    os.environ.pop("MWX_DIRECTIONAL_SHADOW_PRODUCT_SNAPSHOT", None)
    try:
        result = run_swift([snapshot / s.relative_to(REPOSITORY_ROOT) for s in sources],
            support, label="atlas-named", metal_sources=[snapshot / metal.relative_to(REPOSITORY_ROOT)])
    finally:
        for key, value in previous.items():
            if value is None: os.environ.pop(key, None)
            else: os.environ[key] = value
        after = {str(Path(value["frozen"])): hashlib.sha256(Path(value["frozen"]).read_bytes()).hexdigest()
                 for value in inputs.values()}
        (work / "inputs-after.json").write_text(json.dumps(after, indent=2))
        if any(after[value["frozen"]] != value["sha256"] for value in inputs.values()):
            raise AssertionError(f"frozen production input changed: {work}")
    return result


class SceneAtlasNamedNativeOwnerTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.report = run_native_atlas_probe()

    def test_legal_atlas_reserves_actual_prepared_extent(self):
        self.assertTrue(self.report["reservationAccepted"], self.report)
        self.assertIsNone(self.report["reservationReason"])
        self.assertEqual(self.report["sourceExtent"], [64, 32])
        self.assertEqual(self.report["targetExtent"], [80, 40])

    def test_geometry_raster_associates_actual_straight_once_and_publishes_pma(self):
        rows = self.report["geometryRepresentation"]
        self.assertEqual(len(rows), 6)
        for row in rows:
            with self.subTest(straight=row["straight"], alpha=row["alpha"]):
                for key in ("reserved", "actualPMA", "sourceUnchanged", "completed"):
                    self.assertTrue(row[key], (key, row))
                self.assertEqual(row["published"], "published")
                self.assertEqual(row["association"], int(row["straight"]))
                self.assertEqual(row["encodes"], 1)
                for actual, expected in zip(row["pixel"], row["expected"], strict=True):
                    self.assertAlmostEqual(actual, expected, delta=1, msg=row)

    def test_two_consumers_share_once_per_epoch_and_observe_changed_pixels(self):
        rows = self.report["publication"]
        self.assertEqual(len(rows), 2)
        self.assertLess(rows[0]["epoch"], rows[1]["epoch"])
        self.assertEqual([row["candidateProvided"] for row in rows], [True, False])
        self.assertNotEqual(rows[0]["firstPixelBGRA"], rows[1]["firstPixelBGRA"])
        for row in rows:
            with self.subTest(epoch=row["epoch"]):
                self.assertEqual(row["beforePublication"], "unavailable:external-primary-provider-capture-unavailable")
                self.assertEqual(row["published"], "published")
                self.assertEqual(row["repeated"], "published")
                self.assertEqual(row["resolution"], "ready")
                self.assertEqual(row["copies"], 1)
                self.assertEqual(row["consumerCount"], 2)
                for key in ("installed", "shared", "typed", "copiedExactly", "consumerPixelsMatch", "completed"):
                    self.assertTrue(row[key], (key, row))

    def test_illegal_metadata_and_texture_identity_are_hard_rejected(self):
        self.assertFalse(self.report["safety"]["invalidActualTextureAccepted"])
        self.assertEqual(self.report["safety"]["invalidActualTextureReason"], "image-provider-invalid")
        rows = self.report["safety"]["invalidCandidates"]
        self.assertEqual({row["name"] for row in rows}, {
            "physical-nan", "physical-noninteger", "physical-mismatch", "mapped-zero", "mapped-infinite",
            "mapped-noninteger", "mapped-outbounds", "uv-nan", "uv-outbounds", "uv-negative", "wrong-texture", "wrong-purpose"})
        for row in rows:
            with self.subTest(input=row["name"]):
                self.assertFalse(row["accepted"], row)
                self.assertEqual(row["reason"], "image-provider-invalid")
                self.assertEqual(row["publication"], "invalid:named-provider-reservation-missing")

    def test_raw_mapping_miss_preserves_tiny_and_planned_source_fallback(self):
        row = self.report["safety"]
        self.assertFalse(row["rawMappingAccepted"])
        self.assertEqual(row["rawMappingReason"], "image-provider-mapping-unavailable")
        self.assertFalse(row["nilRawAccepted"])
        self.assertEqual(row["nilRawReason"], "image-provider-mapping-unavailable")
        self.assertEqual(row["missingPlanExtentReason"], "image-provider-mapping-unavailable")
        self.assertFalse(row["missingPlanExtentAccepted"])
        self.assertTrue(row["tinyRawAccepted"])
        self.assertIsNone(row["tinyRawReason"])
        self.assertTrue(row["plannedRawFallbackAccepted"])
        self.assertIsNone(row["plannedRawFallbackReason"])
        self.assertEqual(row["plannedRawFallbackPublication"], "published")
        self.assertTrue(row["plannedRawFallbackPixels"])
        self.assertTrue(row["plannedRawFallbackCompleted"])

    def test_prepared_plan_extent_alias_and_stale_publication_rejections(self):
        row = self.report["safety"]
        self.assertEqual(row["fakePlanReason"], "prepared-output-plan-invalid")
        self.assertEqual(row["invalidPlanExtentReason"], "prepared-output-plan-invalid")
        self.assertEqual(row["conflictReason"], "reservation-mismatch")
        for key in ("fakePlanAccepted", "invalidPlanExtentAccepted", "conflictAccepted"):
            self.assertFalse(row[key], (key, row))
        self.assertFalse(row["wrongExtentInstalled"])
        self.assertEqual(row["wrongExtentPublication"], "invalid:named-provider-publication-identity-invalid")
        self.assertFalse(row["aliasInstalled"])
        self.assertEqual(row["aliasPublication"], "invalid:named-provider-publication-identity-invalid")
        self.assertEqual(row["goodPublication"], "published")
        self.assertEqual(row["changedSourcePublication"], "invalid:named-provider-publication-identity-invalid")
        self.assertTrue(row["staleRegistryRefused"] and row["epochAdvanced"] and row["completed"])
        self.assertEqual(row["stalePublication"], "invalid:named-provider-reservation-missing")

    def test_inflight_resize_cancel_preserves_original_and_recovers(self):
        row = self.report["lifecycle"]
        for key in ("pending", "resizedDistinct", "cancelledNotSubmitted", "oldTargetRetainedInFlight",
                    "completed", "oldPixelsSurviveResizeCancel", "oldTargetReleasedAfterCompletion",
                    "recoveryReserved", "recoveryEpochAdvanced", "recoveryCompleted", "recoveryPixels"):
            self.assertTrue(row[key], (key, row))
        self.assertEqual(row["firstPublication"], "published")
        self.assertEqual(row["cancelledPublication"], "published")
        self.assertEqual(row["cancelledUnavailable"], "unavailable:external-primary-provider-capture-unavailable")
        self.assertEqual(row["recoveryPublication"], "published")

    def test_real_resident_budget_failure_stays_resource_rejection(self):
        row = self.report["budget"]
        self.assertFalse(row["acceptedUnderExhaustion"])
        self.assertEqual(row["reason"], "target-pool-unavailable")
        self.assertEqual(row["failedPublication"], "invalid:named-provider-reservation-missing")
        self.assertTrue(row["budgetRejectionObserved"] and row["recoveryAccepted"])
        self.assertEqual(row["unpublishedResolution"], "unavailable:external-primary-provider-capture-unavailable")


if __name__ == "__main__":
    unittest.main()
