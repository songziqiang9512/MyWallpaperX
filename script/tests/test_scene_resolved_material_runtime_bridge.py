#!/usr/bin/env python3

"""R4 resolved-material bridge, submission, and resource contracts."""

from __future__ import annotations

import json
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
SCENE_ROOT = REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene"
RUNTIME_CATALOG = (
    SCENE_ROOT / "RenderGraph/SceneResolvedMaterialRuntimeCatalog.swift"
)
RUNTIME_BRIDGE = (
    SCENE_ROOT
    / "Runtime/ResolvedMaterialExecution/SceneResolvedMaterialRuntimeBridge.swift"
)
ASSET_CATALOG = (
    SCENE_ROOT / "Resources/SceneMaterialAssetTextureCatalog.swift"
)
LAUNCH = SCENE_ROOT / "Runtime/SceneDesktopWallpaperHost+Launch.swift"
TEXTURE_FRAME = SCENE_ROOT / "Rendering/SceneMetalRenderer+TextureFrame.swift"
COMPOSITOR = SCENE_ROOT / "Rendering/SceneImageLayerCompositor.swift"
LAYER_SOURCE_PASSTHROUGH_PLAN = (
    SCENE_ROOT / "Rendering/SceneLayerSourcePassthroughPlan.swift"
)
GRAPH_COMPOSITION = (
    SCENE_ROOT / "Rendering/SceneResolvedMaterialGraphComposition.swift"
)
RENDERER_DIAGNOSTICS = (
    SCENE_ROOT / "Rendering/SceneMetalRenderer+Diagnostics.swift"
)
FRAME_PREFLIGHT = (
    SCENE_ROOT / "Rendering/SceneResolvedMaterialFramePreflight.swift"
)
TARGET_ALLOCATOR = (
    SCENE_ROOT / "RenderGraph/GraphTargets/ScenePersistentGraphTargetAllocator.swift"
)
TARGET_CACHE = (
    SCENE_ROOT / "RenderGraph/GraphTargets/SceneOffscreenTextureAllocationCache.swift"
)
TARGET_SHARED_PAIR = (
    SCENE_ROOT / "RenderGraph/GraphTargets/SceneOffscreenTextureAllocationCache+SharedPair.swift"
)
TARGET_BATCH = (
    SCENE_ROOT / "RenderGraph/GraphTargets/SceneOffscreenTextureAllocationCache+Batch.swift"
)
TARGET_PREFLIGHT = (
    SCENE_ROOT / "RenderGraph/GraphTargets/SceneOffscreenTexturePool+PersistentGraphTargets.swift"
)
OFFSCREEN_RESOLUTION_POLICY = (
    SCENE_ROOT / "RenderGraph/GraphTargets/SceneOffscreenResolutionPolicy.swift"
)
DRAW_REQUEST = SCENE_ROOT / "Rendering/SceneImageLayerDrawRequest.swift"
UTILITY_FRAME_RENDERER = (
    SCENE_ROOT / "Rendering/SceneUtilityPlanFrameRenderer.swift"
)
METAL_RENDERER = SCENE_ROOT / "Rendering/SceneMetalRenderer.swift"
METAL_VIEW_FRAME_CONTEXT = (
    SCENE_ROOT / "Rendering/SceneMetalView+FrameContext.swift"
)
METAL_VIEW = SCENE_ROOT / "Rendering/SceneMetalView.swift"
TEXT_TEXTURE_LOADER = SCENE_ROOT / "Text/SceneTextTextureLoader.swift"
HOST = SCENE_ROOT / "Runtime/SceneDesktopWallpaperHost.swift"
DEBUG_RUNNER = REPOSITORY_ROOT / "MyWallpaperX/App/DebugScenePlaybackRunner.swift"
DEBUG_SCENE_SWITCH_RUNNER = (
    REPOSITORY_ROOT
    / "MyWallpaperX/App/DebugScenePlaybackRunner+SceneSwitch.swift"
)
DEBUG_SURFACE_STOP_RELAUNCH_RUNNER = (
    REPOSITORY_ROOT
    / "MyWallpaperX/App/DebugScenePlaybackRunner+SurfaceStopRelaunch.swift"
)
DEBUG_PAUSE_RESUME_RUNNER = (
    REPOSITORY_ROOT
    / "MyWallpaperX/App/DebugScenePlaybackRunner+PauseResume.swift"
)
HOST_FRAME_DRIVER = (
    SCENE_ROOT / "Runtime/SceneDesktopWallpaperHost+FrameDriver.swift"
)
SUBMISSION_COORDINATOR = (
    SCENE_ROOT
    / "Runtime/ResolvedMaterialExecution/SceneResolvedMaterialSubmissionCoordinator.swift"
)
SUBMISSION_COMPLETION = (
    SCENE_ROOT
    / "Runtime/ResolvedMaterialExecution/SceneResolvedMaterialSubmissionCoordinator+Completion.swift"
)
SUBMISSION_LIFECYCLE = (
    SCENE_ROOT
    / "Runtime/ResolvedMaterialExecution/SceneResolvedMaterialSubmissionCoordinator+Lifecycle.swift"
)
SUBMISSION_FRAME_COMMIT = (
    SCENE_ROOT
    / "Runtime/ResolvedMaterialExecution/SceneResolvedMaterialSubmissionCoordinator+FrameCommit.swift"
)
SUBMISSION_EXECUTION = (
    SCENE_ROOT
    / "Runtime/ResolvedMaterialExecution/SceneResolvedMaterialSubmissionCoordinator+Execution.swift"
)
GRAPH_OBSERVATION = SCENE_ROOT / "Runtime/SceneGraphExecutionObservation.swift"
GRAPH_TELEMETRY = SCENE_ROOT / "Runtime/SceneGraphExecutionTelemetry.swift"
GRAPH_OBSERVATION_BUILDER = (
    SCENE_ROOT
    / "Runtime/ResolvedMaterialExecution/SceneResolvedMaterialGraphObservationBuilder.swift"
)
SUBMISSION_SWIFT_SOURCES = [
    GRAPH_OBSERVATION,
    GRAPH_TELEMETRY,
    GRAPH_OBSERVATION_BUILDER,
    OFFSCREEN_RESOLUTION_POLICY,
    RUNTIME_BRIDGE,
    SUBMISSION_COORDINATOR,
    SUBMISSION_LIFECYCLE,
    SUBMISSION_COMPLETION,
    SUBMISSION_FRAME_COMMIT,
    SUBMISSION_EXECUTION,
]


ASSET_HARNESS = r'''
import Foundation
import Metal

struct SceneVFSAssetPath: Hashable { let value: String }
enum SceneTextureLoadPurpose: String, Hashable {
    case mask, flow
    var reportToken: String { rawValue }
}
struct SceneAssetTextureIdentity: Hashable {
    let path: SceneVFSAssetPath
    let purpose: SceneTextureLoadPurpose
    var reportToken: String { "\(path.value):\(purpose.rawValue)" }
}
enum SceneFrameTextureIdentity: Equatable { case asset(SceneAssetTextureIdentity) }
enum SceneShaderTextureFormat: UInt32 {
    case rgba8888 = 0
    var macroValue: Int { Int(rawValue) }
}
enum SceneTextureContent: Hashable { case data }
struct SceneTextureCandidate {
    let purpose: SceneTextureLoadPurpose
    let complete: Bool
    let authoredFormat: SceneShaderTextureFormat?
    let content: SceneTextureContent = .data
}
struct SceneTextureProviderPublication {
    let requestIdentity: SceneFrameTextureIdentity
    let candidate: SceneTextureCandidate
    let contentGeneration: UInt64
    var isComplete: Bool { candidate.complete }
}
enum SceneTextureProviderState {
    case ready(SceneTextureProviderPublication), absent, pending, unavailable
}
enum SceneAssetTextureLaunchState: Hashable {
    case ready(SceneTextureContent), absent, pending, unavailable
}
struct SceneRenderDescriptor {}
struct SceneResourceView { let urls: [String: URL] }
struct SceneTexturePathResolver {
    let resourceView: SceneResourceView
    init(resourceView: SceneResourceView, descriptor: SceneRenderDescriptor) {
        self.resourceView = resourceView
    }
    func resolveTextureFile(named name: String) -> URL? { resourceView.urls[name] }
}
enum SceneTextureCandidateLoadOutcome {
    case loaded(SceneTextureCandidate), failed(Int)
}
final class SceneTextureLoader {
    func loadCandidate(
        from url: URL,
        purpose: SceneTextureLoadPurpose,
        device: MTLDevice
    ) -> SceneTextureCandidateLoadOutcome {
        if url.lastPathComponent == "bad" { return .failed(1) }
        return .loaded(.init(
            purpose: purpose,
            complete: url.lastPathComponent != "incomplete",
            authoredFormat: .rgba8888
        ))
    }
}

@main
enum Harness {
    static func main() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            print("{\"available\":false}")
            return
        }
        func identity(_ path: String, _ purpose: SceneTextureLoadPurpose) -> SceneAssetTextureIdentity {
            .init(path: .init(value: path), purpose: purpose)
        }
        let goodMask = identity("good", .mask)
        let goodFlow = identity("good", .flow)
        let missing = identity("missing", .mask)
        let bad = identity("bad", .mask)
        let incomplete = identity("incomplete", .mask)
        let catalog = SceneMaterialAssetTextureCatalog(
            demands: [goodMask, goodFlow, missing, bad, incomplete],
            resourceView: .init(urls: [
                "good": URL(fileURLWithPath: "/tmp/good"),
                "bad": URL(fileURLWithPath: "/tmp/bad"),
                "incomplete": URL(fileURLWithPath: "/tmp/incomplete"),
            ]),
            descriptor: .init(),
            device: device
        )
        func disposition(_ identity: SceneAssetTextureIdentity) -> String {
            switch catalog.states[identity] {
            case let .ready(publication):
                return publication.requestIdentity == .asset(identity)
                    && publication.candidate.purpose == identity.purpose
                    && publication.contentGeneration == 1 ? "ready" : "invalid"
            case .absent: return "absent"
            case .pending: return "pending"
            case .unavailable: return "unavailable"
            case nil: return "missing-state"
            }
        }
        let output: [String: Any] = [
            "available": true,
            "goodMask": disposition(goodMask),
            "goodFlow": disposition(goodFlow),
            "missing": disposition(missing),
            "bad": disposition(bad),
            "incomplete": disposition(incomplete),
            "stateCount": catalog.states.count,
            "report": catalog.reportLines.joined(separator: "\n"),
            "goodMaskFormat": catalog.launchFormatFacts[goodMask.reportToken] ?? -999,
            "missingFormat": catalog.launchFormatFacts[missing.reportToken] ?? -999,
            "badFormat": catalog.launchFormatFacts[bad.reportToken] ?? -999,
            "goodMaskLaunch": launchDisposition(catalog.launchStates[goodMask]),
            "missingLaunch": launchDisposition(catalog.launchStates[missing]),
            "badLaunch": launchDisposition(catalog.launchStates[bad]),
            "incompleteLaunch": launchDisposition(catalog.launchStates[incomplete]),
        ]
        let data = try JSONSerialization.data(withJSONObject: output, options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }

    private static func launchDisposition(
        _ state: SceneAssetTextureLaunchState?
    ) -> String {
        switch state {
        case .ready(.data): return "ready-data"
        case .absent: return "absent"
        case .pending: return "pending"
        case .unavailable: return "unavailable"
        case nil: return "missing-state"
        }
    }
}
'''


VFS_SUPPORT = r'''
import Foundation

struct SceneRenderDescriptor {
    struct Layer { let imagePath: String? }
    struct ModelMaterialLink { let modelPath: String; let materialPath: String? }
    struct MaterialPassDescriptor { let materialPath: String; let texturePaths: [String] }
    let modelMaterialLinks: [ModelMaterialLink]
    let materialPasses: [MaterialPassDescriptor]
}

@main
enum Harness {
    static func main() throws {
        let package = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let loose = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
        let stock = URL(fileURLWithPath: CommandLine.arguments[3], isDirectory: true)
        let view = SceneResourceView(
            projectRootURL: loose,
            packageRootURL: package,
            stockAssetsRootURL: stock
        )
        let resolver = SceneTexturePathResolver(
            resourceView: view,
            descriptor: .init(modelMaterialLinks: [], materialPasses: [])
        )
        let output = [
            "shared": resolver.resolveTextureFile(named: "materials/shared.png")?.path ?? "",
            "bare": resolver.resolveTextureFile(named: "bare")?.path ?? "",
            "stock": resolver.resolveTextureFile(named: "assets/stock-only.png")?.path ?? "",
            "missing": resolver.resolveTextureFile(named: "missing")?.path ?? "",
        ]
        let data = try JSONSerialization.data(withJSONObject: output, options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }
}
'''


SUBMISSION_COORDINATOR_FIXTURE = r'''
import Foundation
import Metal

struct SceneGraphMaterialFunctionInvocationRequest {}
struct SceneGraphClearFunctionRegistry {
    init() {}
}

struct SceneAuthoredEffectRenderPlan {
    struct EffectKey: Hashable {
        let layerID: Int
        let effectIndex: Int
        let descriptorID: String
    }
    enum TextureKind: Hashable { case framebuffer, effectOutput, layerSource }
    struct TextureIdentity: Hashable {
        let kind: TextureKind
        let layerID: Int
        let effect: EffectKey?
        let name: String?
    }
    enum NodeKind: Equatable { case material, copy, swap }
    struct Node {
        let nodeIndex: Int
        let kind: NodeKind
        let materialOrdinal: Int?
        let commandSource: TextureIdentity?
        let commandTarget: TextureIdentity?

        init(
            nodeIndex: Int,
            kind: NodeKind,
            materialOrdinal: Int? = nil,
            commandSource: TextureIdentity? = nil,
            commandTarget: TextureIdentity? = nil
        ) {
            self.nodeIndex = nodeIndex
            self.kind = kind
            self.materialOrdinal = materialOrdinal
            self.commandSource = commandSource
            self.commandTarget = commandTarget
        }
    }
    struct Effect { let key: EffectKey }
    let layerID: Int
    let effects: [Effect]
    let nodes: [Node]
    let renderTargets: [TextureIdentity]

    init(
        layerID: Int,
        effects: [Effect],
        nodes: [Node],
        renderTargets: [TextureIdentity] = []
    ) {
        self.layerID = layerID
        self.effects = effects
        self.nodes = nodes
        self.renderTargets = renderTargets
    }
}

struct SceneLayerFullFramePairPlan {
    enum Member { case zero, one }
    struct NodeStep {
        let nodeIndex: Int
        let kind: SceneAuthoredEffectRenderPlan.NodeKind
        let rotatesAfterNode: Bool
    }
    struct EffectStep {
        let effect: SceneAuthoredEffectRenderPlan.EffectKey
        let inputIdentity: SceneAuthoredEffectRenderPlan.TextureIdentity
        let outputIdentity: SceneAuthoredEffectRenderPlan.TextureIdentity
        let inputMember: Member
        let outputMember: Member
        let nodes: [NodeStep]
    }
    let layerID: Int
}

struct SceneGraphExecutionState {
    typealias Identity = SceneAuthoredEffectRenderPlan.TextureIdentity
    static let maximumNodeCount = 512
    static let maximumLogicalBindingCount = 512
    struct PhysicalToken: Hashable { let rawValue: String }
    struct ResourceDescriptor: Equatable {
        let extent: SceneGraphRenderTargetPlan.PixelExtent
        let format: SceneGraphRenderTargetPlan.TextureFormat
        let addressMode: SceneGraphRenderTargetPlan.UVAddressMode

        init(
            extent: SceneGraphRenderTargetPlan.PixelExtent = .init(
                width: 2,
                height: 2
            ),
            format: SceneGraphRenderTargetPlan.TextureFormat = .rgbaBackbuffer,
            addressMode: SceneGraphRenderTargetPlan.UVAddressMode
        ) {
            self.extent = extent
            self.format = format
            self.addressMode = addressMode
        }
    }
    struct VersionedResource {
        let token: PhysicalToken
        let descriptor: ResourceDescriptor
        let contentGeneration: UInt64

        init(
            token: PhysicalToken,
            descriptor: ResourceDescriptor = .init(addressMode: .clampToEdge),
            contentGeneration: UInt64
        ) {
            self.token = token
            self.descriptor = descriptor
            self.contentGeneration = contentGeneration
        }
    }
    enum InitializationReason { case authoredClear }
    struct MaterialBinding {}
    struct MaterialTarget {}
    enum Intent {
        case initialize(
            identity: Identity,
            resource: VersionedResource,
            reason: InitializationReason
        )
        case material(
            nodeIndex: Int,
            materialOrdinal: Int,
            bindings: [MaterialBinding],
            target: MaterialTarget?
        )
        case copy(
            nodeIndex: Int,
            commandOrdinal: Int,
            source: Identity,
            sourceResource: VersionedResource,
            target: Identity,
            targetResource: VersionedResource
        )
        case swap(
            nodeIndex: Int,
            commandOrdinal: Int,
            source: Identity,
            sourceResource: VersionedResource,
            target: Identity,
            targetResource: VersionedResource
        )
    }
    struct Transaction {
        let intents: [Intent]
        let mappingBefore: [Identity: VersionedResource]
        let mappingAfter: [Identity: VersionedResource]
        let allocationGeneration: UInt64
        let effectGeneration: UInt64
        let resetGeneration: UInt64
    }
    struct Transition {
        let nextState: SceneGraphExecutionState
        let transaction: Transaction
    }
    let effectGeneration: UInt64?
    let resetGeneration: UInt64?
    let allocationGeneration: UInt64?
    let logicalMapping: [Identity: VersionedResource]
    let historyLogicalIdentities: Set<Identity>
    let historyClosureIdentities: Set<Identity>

    func hasSameCompletePlan(as other: Self) -> Bool {
        let lhs = logicalMapping.mapValues(\.descriptor)
        let rhs = other.logicalMapping.mapValues(\.descriptor)
        return lhs == rhs
    }
}

enum SceneTextureLoadPurpose: Hashable { case premultipliedColor }
enum SceneTextureProviderIdentity: Hashable {
    case graph(allocationGeneration: UInt64, physicalToken: String)
    case sceneBackground(consumerLayerID: Int, frameEpoch: UInt64)
    var reportToken: String {
        switch self {
        case let .graph(generation, token): return "graph:\(generation):\(token)"
        case let .sceneBackground(layerID, epoch): return "background:\(layerID):\(epoch)"
        }
    }
}
enum SceneTextureCandidateIdentity: Hashable {
    case provider(SceneTextureProviderIdentity)
    case file(String)
    case builtIn(String)
}
enum SceneFrameTextureIdentity: Hashable {
    case graph(SceneAuthoredEffectRenderPlan.TextureIdentity)
    case system(String)
    case sceneBackground(Int)

    var reportToken: String {
        switch self {
        case let .graph(identity):
            let effect = identity.effect.map {
                "\($0.layerID):\($0.effectIndex):\($0.descriptorID)"
            } ?? "none"
            return "graph:\(identity.kind):\(identity.layerID):\(effect):\(identity.name ?? "none")"
        case let .system(name): return "system:\(name)"
        case let .sceneBackground(layerID): return "scene-background:\(layerID)"
        }
    }
}

enum SceneShaderStableDigest {
    static func hash(_ data: Data) -> String { "data-\(data.count)" }
    static func hash(_ graph: SceneAuthoredEffectRenderPlan) -> String {
        "graph-\(graph.layerID)-\(graph.nodes.count)"
    }
}
enum SceneTextureSampling { case linearClamp, linearRepeat }
struct SceneTextureCandidate {
    let texture: MTLTexture
    let identity: SceneTextureCandidateIdentity
    let purpose: SceneTextureLoadPurpose
    let sampling: SceneTextureSampling

    init(
        texture: MTLTexture,
        identity: SceneTextureCandidateIdentity,
        purpose: SceneTextureLoadPurpose,
        sampling: SceneTextureSampling = .linearClamp
    ) {
        self.texture = texture
        self.identity = identity
        self.purpose = purpose
        self.sampling = sampling
    }
}
struct SceneTextureProviderPublication {
    let requestIdentity: SceneFrameTextureIdentity
    let candidate: SceneTextureCandidate
    let contentGeneration: UInt64
    var texture: MTLTexture { candidate.texture }
    var isComplete: Bool { contentGeneration > 0 }
    func isSameAtom(as other: Self) -> Bool {
        requestIdentity == other.requestIdentity
            && candidate.identity == other.candidate.identity
            && candidate.sampling == other.candidate.sampling
            && contentGeneration == other.contentGeneration
            && texture === other.texture
    }
}
struct SceneFrameTextureResource {
    let publication: SceneTextureProviderPublication
    let resourceGeneration: UInt64
    var isCompleteGraphResource: Bool {
        resourceGeneration > 0
            && publication.contentGeneration == resourceGeneration
    }
    func isCompleteSceneBackground(consumerLayerID: Int, frameEpoch: UInt64) -> Bool {
        resourceGeneration == frameEpoch
            && publication.contentGeneration == frameEpoch
            && publication.requestIdentity == .sceneBackground(consumerLayerID)
            && publication.texture.usage.contains(.renderTarget)
            && publication.texture.usage.contains(.shaderRead)
    }
}

enum SceneResolvedMaterialInFlightCapacity {
    static let maximumSubmissions = 2
}

struct SceneGraphRenderTargetPlan: Equatable {
    enum UVAddressMode { case clampToEdge, repeatWrap }
    enum TextureFormat: String { case rgbaBackbuffer }
    struct PixelExtent: Equatable {
        let width: Int
        let height: Int
    }
    let identity: Int
}
struct SceneGraphRenderTargetTable { let plan: SceneGraphRenderTargetPlan }
struct SceneGraphRenderTargetLease {
    struct FullFramePair {
        let first: SceneGraphExecutionState.PhysicalToken
        let second: SceneGraphExecutionState.PhysicalToken
    }
    let table: SceneGraphRenderTargetTable
    let generation: UInt64
    let texturesByToken: [SceneGraphExecutionState.PhysicalToken: MTLTexture]
    let fullFramePair: FullFramePair

    static func graphSamplingMatches(
        _ resource: SceneFrameTextureResource,
        descriptor: SceneGraphExecutionState.ResourceDescriptor
    ) -> Bool {
        graphSamplingMatches(
            resource,
            expectedSampling: descriptor.addressMode == .repeatWrap
                ? .linearRepeat
                : .linearClamp
        )
    }

    static func graphSamplingMatches(
        _ resource: SceneFrameTextureResource,
        expectedSampling: SceneTextureSampling
    ) -> Bool {
        resource.isCompleteGraphResource
            && resource.publication.candidate.sampling == expectedSampling
    }
}

final class SceneGraphRenderTargetResidencyPin: @unchecked Sendable {
    typealias EffectKey = SceneAuthoredEffectRenderPlan.EffectKey
    typealias Token = SceneGraphExecutionState.PhysicalToken
    enum Purpose: Hashable { case submission, history(EffectKey, Set<Token>) }
    let purpose: Purpose
    let generation: UInt64
    private(set) var active = true
    private(set) var releaseCount = 0
    init(purpose: Purpose, generation: UInt64) {
        self.purpose = purpose
        self.generation = generation
    }
    func release() {
        guard active else { return }
        active = false
        releaseCount += 1
    }
}

final class ScenePreparedPersistentGraphTargets {
    typealias EffectKey = SceneAuthoredEffectRenderPlan.EffectKey
    typealias Token = SceneGraphExecutionState.PhysicalToken
    struct HistoryRehydrateCopy {}
    struct Commit {
        let leases: [SceneGraphRenderTargetLease]
        let submissionPin: SceneGraphRenderTargetResidencyPin
        let historyPinsByEffect: [EffectKey: SceneGraphRenderTargetResidencyPin]
        func releaseAll() {
            submissionPin.release()
            historyPinsByEffect.values.forEach { $0.release() }
        }
    }
    let leases: [SceneGraphRenderTargetLease]
    let historyRehydrateCopiesByEffect: [EffectKey: [HistoryRehydrateCopy]]
    private var action: ((
        [EffectKey: Set<Token>],
        Set<EffectKey>,
        MTLCommandBuffer?
    ) -> Commit?)?
    init(
        leases: [SceneGraphRenderTargetLease] = [],
        historyRehydrateCopiesByEffect: [EffectKey: [HistoryRehydrateCopy]] = [:],
        action: ((
            [EffectKey: Set<Token>],
            Set<EffectKey>,
            MTLCommandBuffer?
        ) -> Commit?)? = nil
    ) {
        self.leases = leases
        self.historyRehydrateCopiesByEffect = historyRehydrateCopiesByEffect
        self.action = action
    }
    func commitAndPin(
        historyTokensByEffect: [EffectKey: Set<Token>],
        discardedHistoryEffects: Set<EffectKey> = [],
        commandBuffer: MTLCommandBuffer? = nil
    ) -> Commit? {
        let current = action
        action = nil
        return current?(
            historyTokensByEffect,
            discardedHistoryEffects,
            commandBuffer
        )
    }
}

enum SceneResolvedMaterialExecutionCapabilityAdmission {
    static let maximumEffectsPerLayer = 512
    static let maximumNodesPerLayer = 65_536
}
struct SceneResolvedMaterialAdmittedLayer {
    enum SourceRoute {
        case capturedLayerTexture
        case capturedMainTargetTexture
        case transparentDirectDraw
    }
}
struct SceneEffectPassSlot: Hashable {
    let effectID: String
    let passIndex: Int
    let slotIndex: Int
}
enum SceneNamedTextureReference {
    enum Variant: Hashable {
        case primary
        case secondary
    }
}
struct SceneDependencyRenderPlan {
    struct Binding: Hashable {
        enum Kind: Hashable {
            case resolvedMaterial
            case solidLayer
            case imageLayerBlend
        }

        let consumerLayerID: Int
        let providerLayerID: Int
        let slot: SceneEffectPassSlot
        let referenceSlots: [SceneEffectPassSlot]
        let blendMode: Int
        let kind: Kind

        init(
            consumerLayerID: Int,
            providerLayerID: Int,
            slot: SceneEffectPassSlot,
            referenceSlots: [SceneEffectPassSlot]? = nil,
            blendMode: Int,
            kind: Kind
        ) {
            self.consumerLayerID = consumerLayerID
            self.providerLayerID = providerLayerID
            self.slot = slot
            self.referenceSlots = referenceSlots ?? [slot]
            self.blendMode = blendMode
            self.kind = kind
        }
    }
}
enum SceneResolvedMaterialDependencyOwnership: Equatable {
    case none
    case graphInternal(referenceCount: Int)
    case externalPrimary(SceneDependencyRenderPlan.Binding)
}
struct SceneEffectStageExecutionPlan {}
final class SceneResolvedMaterialExecutionCapabilityCatalog {
    struct SceneBackgroundRequirement: Equatable {
        let layerID: Int
        let effect: SceneAuthoredEffectRenderPlan.EffectKey
        let nodeIndex: Int
        let slot: Int
    }
    struct Token: Hashable { let value: Int }
    struct Claim { let token: Token }
    struct AdmittedProduct {
        let graph: SceneAuthoredEffectRenderPlan
        let clearFunctions: SceneGraphClearFunctionRegistry

        init(
            graph: SceneAuthoredEffectRenderPlan,
            clearFunctions: SceneGraphClearFunctionRegistry = .init()
        ) {
            self.graph = graph
            self.clearFunctions = clearFunctions
        }
    }
    struct ExactEffectSubject: Hashable {
        let key: SceneAuthoredEffectRenderPlan.EffectKey
        let family: String
    }
    struct RuntimeDispositionOwnership {
        let layerID: Int
        let subjects: [ExactEffectSubject]
    }
    struct StageCapability {
        let subject: ExactEffectSubject?
        let dedicatedExecutionPlan: SceneEffectStageExecutionPlan?
        let visualFailureReasonCode: String?

        init(
            subject: ExactEffectSubject?,
            dedicatedExecutionPlan: SceneEffectStageExecutionPlan? = nil,
            visualFailureReasonCode: String? = nil
        ) {
            self.subject = subject
            self.dedicatedExecutionPlan = dedicatedExecutionPlan
            self.visualFailureReasonCode = visualFailureReasonCode
        }
    }
    struct ChainCapability {
        let layerID: Int
        let pairPlan: SceneLayerFullFramePairPlan
        let admittedProducts: [AdmittedProduct]
        let stages: [StageCapability]
        let fullFrameExtentPolicy: SceneFullFrameExtentPolicy
        let dependencyOwnership: SceneResolvedMaterialDependencyOwnership
        let sourceRoute: SceneResolvedMaterialAdmittedLayer.SourceRoute
        let sceneBackgroundRequirement: SceneBackgroundRequirement? = nil
        let requiresInvertibleEffectTextureProjection: Bool = false
        var effectSubjectsAreConserved: Bool {
            let expected = admittedProducts.flatMap { $0.graph.effects.map(\.key) }
            return !expected.isEmpty && Set(expected).count == expected.count
        }
    }
    let capabilitiesByLayerID: [Int: ChainCapability]
    let resolvesClaims: Bool
    init(
        capability: ChainCapability? = nil,
        additionalCapabilities: [ChainCapability] = [],
        resolvesClaims: Bool = true
    ) {
        let values = ([capability].compactMap { $0 } + additionalCapabilities)
        self.capabilitiesByLayerID = Dictionary(
            uniqueKeysWithValues: values.map { ($0.layerID, $0) }
        )
        self.resolvesClaims = resolvesClaims
    }
    func claim(layerID: Int) -> Claim? {
        capabilitiesByLayerID[layerID] == nil
            ? nil : .init(token: .init(value: layerID))
    }
    func productAuthorityRejectionReason(layerID: Int) -> String? { nil }
    func resolve(_ token: Token) -> ChainCapability? {
        resolvesClaims ? capabilitiesByLayerID[token.value] : nil
    }
    var runtimeDispositionOwnerships: [RuntimeDispositionOwnership] {
        capabilitiesByLayerID.keys.sorted().compactMap { layerID in
            guard let capability = capabilitiesByLayerID[layerID] else { return nil }
            return .init(
                layerID: layerID,
                subjects: capability.stages.compactMap(\.subject)
            )
        }
    }
    var executionLayerIDs: Set<Int> { Set(capabilitiesByLayerID.keys) }
    var sceneBackgroundLayerIDs: Set<Int> {
        Set(capabilitiesByLayerID.values.compactMap {
            $0.sceneBackgroundRequirement?.layerID
        })
    }
}

struct SceneLayerGraphTargetPlan {
    struct Key { let layerID: Int }
    let key: Key
}
struct ScenePersistentGraphTargetFramePlan {
    let graphPlan: SceneLayerGraphTargetPlan
}
struct SceneResolvedMaterialFrameTargetPlan {
    let token: SceneResolvedMaterialExecutionCapabilityCatalog.Token
    let allocation: ScenePersistentGraphTargetFramePlan
}
final class SceneOffscreenTexturePool {
    typealias Factory = (
        ScenePersistentGraphTargetFramePlan
    ) -> ScenePreparedPersistentGraphTargets?
    let factory: Factory
    private(set) var batchCommitCount = 0
    private(set) var discardedHistoryEffectsByCommit: [[
        Set<ScenePreparedPersistentGraphTargets.EffectKey>
    ]] = []
    init(
        prepared: ScenePreparedPersistentGraphTargets? = .init(),
        factory: Factory? = nil
    ) {
        self.factory = factory ?? { _ in prepared }
    }
    func preparePersistentGraphTargets(
        framePlan: ScenePersistentGraphTargetFramePlan
    ) -> ScenePreparedPersistentGraphTargets? {
        factory(framePlan)
    }
    func preparePersistentGraphTargets(
        framePlans: [ScenePersistentGraphTargetFramePlan]
    ) -> [ScenePreparedPersistentGraphTargets]? {
        let values = framePlans.compactMap(factory)
        return values.count == framePlans.count ? values : nil
    }
    func commitAndPinPersistentGraphTargets(
        _ targets: [ScenePreparedPersistentGraphTargets],
        historyTokensByTarget: [[ScenePreparedPersistentGraphTargets.EffectKey:
            Set<ScenePreparedPersistentGraphTargets.Token>]],
        discardedHistoryEffectsByTarget: [
            Set<ScenePreparedPersistentGraphTargets.EffectKey>
        ]? = nil,
        commandBuffer: MTLCommandBuffer
    ) -> [ScenePreparedPersistentGraphTargets.Commit]? {
        let discarded = discardedHistoryEffectsByTarget ?? Array(
            repeating: [],
            count: targets.count
        )
        guard targets.count == historyTokensByTarget.count,
              targets.count == discarded.count else { return nil }
        discardedHistoryEffectsByCommit.append(discarded)
        let commits = zip(
            zip(targets, historyTokensByTarget),
            discarded
        ).compactMap {
            $0.0.0.commitAndPin(
                historyTokensByEffect: $0.0.1,
                discardedHistoryEffects: $0.1,
                commandBuffer: commandBuffer
            )
        }
        guard commits.count == targets.count else {
            commits.forEach { $0.releaseAll() }
            return nil
        }
        batchCommitCount += 1
        return commits
    }
}

struct SceneLayerFragmentUniforms {}
struct SceneImageLayerPipeline {}
struct SceneImageLayerMasks {}
struct SceneAuthoredEffectPipelineSet {}
struct SceneAudioSpectrumSnapshot {}
struct SceneDependencyEffectInput {
    let consumerLayerID: Int
    let providerLayerID: Int
    let variant: SceneNamedTextureReference.Variant
    let slot: SceneEffectPassSlot
    let blendMode: Int
    let frameEpoch: UInt64
    let texture: MTLTexture

    var slotIndex: Int { slot.slotIndex }
}
struct SceneResolvedMaterialFailure: Error {}
struct SceneFrameTextureRegistrySnapshot { let frameIndex: UInt64; let valid: Bool; var frameEpoch: UInt64 { frameIndex } }
struct SceneDynamicSnapshot {}
struct SceneAuthoredShaderFrameInputs {}
struct SceneResolvedMaterialFrameSnapshot {
    let frameIndex: UInt64
    var textureRegistrySnapshot: SceneFrameTextureRegistrySnapshot { .init(frameIndex: frameIndex, valid: true) }
    static func validated(
        textureSnapshot: SceneFrameTextureRegistrySnapshot,
        dynamicSnapshot: SceneDynamicSnapshot,
        frameInputs: SceneAuthoredShaderFrameInputs
    ) -> Result<Self, SceneResolvedMaterialFailure> {
        _ = dynamicSnapshot
        _ = frameInputs
        return textureSnapshot.valid
            ? .success(.init(frameIndex: textureSnapshot.frameIndex))
            : .failure(.init())
    }
}

struct SceneAssetTextureIdentity: Hashable { let value: String }
enum SceneTextureProviderState { case unavailable }
struct SceneUserPropertyTextureIdentity: Hashable {
    let propertyKey: String
    let purpose: SceneTextureLoadPurpose
    init?(propertyKey: String, purpose: SceneTextureLoadPurpose) {
        guard !propertyKey.isEmpty else { return nil }
        self.propertyKey = propertyKey
        self.purpose = purpose
    }
}
enum SceneFrameTextureRegistry { enum ProviderStatus { case unavailable } }
enum SceneMediaThumbnailTextureStore {
    struct Snapshot {
        let publications: [String: SceneTextureProviderPublication]
        let systemTextures: [String: MTLTexture]
    }
}
struct SceneResolvedMaterialRuntimeCatalog {
    struct SystemProviderDemand: Hashable {
        let name: String
        let purpose: SceneTextureLoadPurpose
    }
    let userPropertyDemands: Set<SceneUserPropertyTextureIdentity>
    let systemProviderDemands: Set<SystemProviderDemand>
}
struct SceneMaterialAssetTextureCatalog {
    final class FrameProvider {
        let catalog: SceneMaterialAssetTextureCatalog

        init(catalog: SceneMaterialAssetTextureCatalog) {
            self.catalog = catalog
        }

        func states(
            sceneTime: TimeInterval
        ) -> [SceneAssetTextureIdentity: SceneTextureProviderState] {
            catalog.states
        }
    }

    let states: [SceneAssetTextureIdentity: SceneTextureProviderState]

    func makeFrameProvider() -> FrameProvider { .init(catalog: self) }
}

extension SceneResolvedMaterialRuntimeBridge.DedicatedFrameInputs {
    static let fixture = Self(
        masks: .init(),
        dynamicValues: .init(),
        pipelines: .init(),
        cursorUV: .zero,
        previousCursorUV: .zero,
        pointerIsInside: false,
        previousPointerIsInside: false,
        pointerMovement: 0,
        primaryButtonIsDown: false,
        layerModelMatrix: .init(diagonal: .init(repeating: 1)),
        effectTextureProjectionMatrixInverse: .init(
            diagonal: .init(repeating: 1)
        ),
        frameTime: 1 / 60,
        time: 0,
        audioSpectrum: .init(),
        dependencyEffect: nil
    )

    func replacingDependencyEffect(
        _ dependencyEffect: SceneDependencyEffectInput?
    ) -> Self {
        .init(
            masks: masks,
            dynamicValues: dynamicValues,
            pipelines: pipelines,
            cursorUV: cursorUV,
            previousCursorUV: previousCursorUV,
            pointerIsInside: pointerIsInside,
            previousPointerIsInside: previousPointerIsInside,
            pointerMovement: pointerMovement,
            primaryButtonIsDown: primaryButtonIsDown,
            layerModelMatrix: layerModelMatrix,
            effectTextureProjectionMatrixInverse:
                effectTextureProjectionMatrixInverse,
            frameTime: frameTime,
            time: time,
            audioSpectrum: audioSpectrum,
            dependencyEffect: dependencyEffect
        )
    }
}

final class SceneResolvedMaterialGraphExecutor {
    typealias Graph = SceneAuthoredEffectRenderPlan
    typealias State = SceneGraphExecutionState
    enum Failure: String, Error {
        case unavailable = "fixture-preflight-unavailable"
        var isColorContractVisualRejection: Bool { false }
    }
    struct PreparedStage {
        let effect: Graph.EffectKey
        let graph: Graph
        let pairStep: SceneLayerFullFramePairPlan.EffectStep
        let transition: State.Transition
        let inputWidth, inputHeight: Int
        let historyRehydrateCopyCount: Int
        let historyContentDiscarded: Bool
        let frameResources: [Graph.TextureIdentity: SceneFrameTextureResource]
        let persistentResources: [Graph.TextureIdentity: SceneFrameTextureResource]
        let effectOutputResource: SceneFrameTextureResource
        let programCacheKeys: [String]
        let effectLocalFailureReasonCode: String?
        let effectLocalActivationBypassReasonCode: String?
        let discardedPersistentTargetState: Bool
    }
    struct PreparedGraph {
        let stages: [PreparedStage]
        let finalResource: SceneFrameTextureResource
        let finalTexture: MTLTexture
        let historyTokensByEffect: [Graph.EffectKey: Set<State.PhysicalToken>]
        let sceneBackgroundResource: SceneFrameTextureResource? = nil
    }
    static var prepareCallCount = 0
    static var prepareTokens: [Int] = []
    static var preparedByToken: [Int: PreparedGraph] = [:]
    static var preparedDependencyTextureByToken: [Int: ObjectIdentifier] = [:]
    static var encodeSucceeds = false
    init?(
        device: MTLDevice,
        capabilities: SceneResolvedMaterialExecutionCapabilityCatalog
    ) { _ = device; _ = capabilities }
    func prepare(
        token: SceneResolvedMaterialExecutionCapabilityCatalog.Token,
        leases: [SceneGraphRenderTargetLease],
        historyRehydrateCopiesByEffect: [Graph.EffectKey: [ScenePreparedPersistentGraphTargets.HistoryRehydrateCopy]],
        frame: SceneResolvedMaterialFrameSnapshot,
        sceneBackgroundResource: SceneFrameTextureResource? = nil,
        sourceTexture: MTLTexture?,
        sourceUniforms: SceneLayerFragmentUniforms?,
        sourcePipeline: SceneImageLayerPipeline,
        dedicatedInputs: SceneResolvedMaterialRuntimeBridge.DedicatedFrameInputs,
        commandBuffer: MTLCommandBuffer,
        previousStates: [Graph.EffectKey: State],
        previousGraphResources: [Graph.EffectKey: [Graph.TextureIdentity: SceneFrameTextureResource]],
        materialFunctionInvocations:
            [SceneGraphMaterialFunctionInvocationRequest] = [],
        effectGeneration: UInt64,
        resetGeneration: UInt64
    ) -> Result<PreparedGraph, Failure> {
        _ = token; _ = leases; _ = historyRehydrateCopiesByEffect; _ = frame
        _ = materialFunctionInvocations; _ = sceneBackgroundResource
        _ = sourceTexture; _ = sourceUniforms; _ = sourcePipeline
        _ = dedicatedInputs; _ = commandBuffer
        _ = previousStates; _ = previousGraphResources
        _ = effectGeneration; _ = resetGeneration
        Self.prepareCallCount += 1
        Self.prepareTokens.append(token.value)
        if let texture = dedicatedInputs.dependencyEffect?.texture {
            Self.preparedDependencyTextureByToken[token.value] =
                ObjectIdentifier(texture)
        }
        return Self.preparedByToken[token.value].map(Result.success)
            ?? .failure(.unavailable)
    }
    func encode(_ value: PreparedGraph, commandBuffer: MTLCommandBuffer) -> Bool {
        _ = value; _ = commandBuffer; return Self.encodeSucceeds
    }
    func encodeResult(
        _ value: PreparedGraph,
        commandBuffer: MTLCommandBuffer
    ) -> Result<Void, Failure> {
        _ = value; _ = commandBuffer
        return Self.encodeSucceeds ? .success(()) : .failure(.unavailable)
    }
    func reset() -> Bool { true }
}

private typealias Coordinator = SceneResolvedMaterialSubmissionCoordinator
private typealias Graph = SceneAuthoredEffectRenderPlan
private typealias State = SceneGraphExecutionState

private let effect = Graph.EffectKey(
    layerID: 7, effectIndex: 0, descriptorID: "fixture"
)
private let historyIdentity = Graph.TextureIdentity(
    kind: .framebuffer, layerID: 7, effect: effect, name: "history"
)
private let observationOutputIdentity = Graph.TextureIdentity(
    kind: .effectOutput, layerID: 7, effect: effect, name: "pair-output"
)

private func effect(for layerID: Int) -> Graph.EffectKey {
    layerID == 7 ? effect : .init(
        layerID: layerID,
        effectIndex: 0,
        descriptorID: "fixture-\(layerID)"
    )
}

private func outputIdentity(for layerID: Int) -> Graph.TextureIdentity {
    let value = effect(for: layerID)
    return .init(
        kind: .effectOutput,
        layerID: layerID,
        effect: value,
        name: "pair-output-\(layerID)"
    )
}

private func makeTexture(_ device: MTLDevice, _ label: String) -> MTLTexture {
    let descriptor = MTLTextureDescriptor.texture2DDescriptor(
        pixelFormat: .bgra8Unorm,
        width: 2,
        height: 2,
        mipmapped: false
    )
    descriptor.usage = [.shaderRead, .renderTarget]
    guard let texture = device.makeTexture(descriptor: descriptor) else {
        fatalError("texture unavailable")
    }
    texture.label = label
    return texture
}

private func makeResource(
    texture: MTLTexture,
    token: String,
    generation: UInt64
) -> SceneFrameTextureResource {
    .init(
        publication: .init(
            requestIdentity: .graph(historyIdentity),
            candidate: .init(
                texture: texture,
                identity: .provider(.graph(
                    allocationGeneration: generation,
                    physicalToken: token
                )),
                purpose: .premultipliedColor
            ),
            contentGeneration: 1
        ),
        resourceGeneration: 1
    )
}

private func makeTail(
    device: MTLDevice,
    token: String,
    generation: UInt64,
    pin: SceneGraphRenderTargetResidencyPin,
    reset: UInt64 = 1
) -> Coordinator.Tail {
    let versioned = State.VersionedResource(
        token: .init(rawValue: token),
        contentGeneration: 1
    )
    let state = State(
        effectGeneration: 1,
        resetGeneration: reset,
        allocationGeneration: generation,
        logicalMapping: [historyIdentity: versioned],
        historyLogicalIdentities: [historyIdentity],
        historyClosureIdentities: [historyIdentity]
    )
    return .init(
        state: state,
        persistentResources: [
            historyIdentity: makeResource(
                texture: makeTexture(device, "history-\(token)"),
                token: token,
                generation: generation
            )
        ],
        historyPin: pin,
        mappingGeneration: generation
    )
}

private func makePrepared(
    device: MTLDevice,
    texture: MTLTexture? = nil
) -> SceneResolvedMaterialGraphExecutor.PreparedGraph {
    let final = texture ?? makeTexture(device, "final")
    return .init(
        stages: [],
        finalResource: makeResource(texture: final, token: "final", generation: 1),
        finalTexture: final,
        historyTokensByEffect: [:]
    )
}

private func makeObservationTransition(
    device: MTLDevice
) -> SceneResolvedMaterialGraphExecutor.PreparedStage {
    let resource = SceneFrameTextureResource(
        publication: .init(
            requestIdentity: .graph(observationOutputIdentity),
            candidate: .init(
                texture: makeTexture(device, "observation-output"),
                identity: .provider(.graph(
                    allocationGeneration: 3,
                    physicalToken: "observation-output-token"
                )),
                purpose: .premultipliedColor
            ),
            contentGeneration: 1
        ),
        resourceGeneration: 1
    )
    let graph = Graph(
        layerID: 7,
        effects: [.init(key: effect)],
        nodes: [.init(
            nodeIndex: 0,
            kind: .material,
            materialOrdinal: 0
        )]
    )
    let nextState = State(
        effectGeneration: 4,
        resetGeneration: 5,
        allocationGeneration: 3,
        logicalMapping: [:],
        historyLogicalIdentities: [],
        historyClosureIdentities: []
    )
    let transaction = State.Transaction(
        intents: [.material(
            nodeIndex: 0,
            materialOrdinal: 0,
            bindings: [],
            target: nil
        )],
        mappingBefore: [:],
        mappingAfter: [:],
        allocationGeneration: 3,
        effectGeneration: 4,
        resetGeneration: 5
    )
    return .init(
        effect: effect,
        graph: graph,
        pairStep: .init(
            effect: effect,
            inputIdentity: observationOutputIdentity,
            outputIdentity: observationOutputIdentity,
            inputMember: .zero,
            outputMember: .zero,
            nodes: [.init(
                nodeIndex: 0,
                kind: .material,
                rotatesAfterNode: true
            )]
        ),
        transition: .init(nextState: nextState, transaction: transaction),
        inputWidth: 2_048,
        inputHeight: 1_152,
        historyRehydrateCopyCount: 0,
        historyContentDiscarded: false,
        frameResources: [:],
        persistentResources: [:],
        effectOutputResource: resource,
        programCacheKeys: ["fixture-program"],
        effectLocalFailureReasonCode: nil,
        effectLocalActivationBypassReasonCode: nil,
        discardedPersistentTargetState: false
    )
}

private func makeObservedPrepared(
    device: MTLDevice
) -> SceneResolvedMaterialGraphExecutor.PreparedGraph {
    let transition = makeObservationTransition(device: device)
    return .init(
        stages: [transition],
        finalResource: transition.effectOutputResource,
        finalTexture: transition.effectOutputResource.publication.texture,
        historyTokensByEffect: [:]
    )
}

private func makeAtomicPrepared(
    device: MTLDevice,
    layerID: Int,
    generation: UInt64,
    terminalSampling: SceneTextureSampling = .linearClamp,
    discardedPersistentTargetState: Bool = false,
    forgedDiscardTransaction: Bool = false
) -> SceneResolvedMaterialGraphExecutor.PreparedGraph {
    let key = effect(for: layerID)
    let output = outputIdentity(for: layerID)
    let texture = makeTexture(device, "atomic-final-\(layerID)")
    let resource = SceneFrameTextureResource(
        publication: .init(
            requestIdentity: .graph(output),
            candidate: .init(
                texture: texture,
                identity: .provider(.graph(
                    allocationGeneration: generation,
                    physicalToken: "atomic-output-\(layerID)"
                )),
                purpose: .premultipliedColor,
                sampling: terminalSampling
            ),
            contentGeneration: 1
        ),
        resourceGeneration: 1
    )
    let graph = Graph(
        layerID: layerID,
        effects: [.init(key: key)],
        nodes: [.init(nodeIndex: 0, kind: .material, materialOrdinal: 0)],
        renderTargets: discardedPersistentTargetState ? [output] : []
    )
    let state = State(
        effectGeneration: 1,
        resetGeneration: 1,
        allocationGeneration: generation,
        logicalMapping: [:],
        historyLogicalIdentities: [],
        historyClosureIdentities: []
    )
    let transaction = State.Transaction(
        intents: discardedPersistentTargetState && !forgedDiscardTransaction
            ? []
            : [.material(
                nodeIndex: 0,
                materialOrdinal: 0,
                bindings: [],
                target: nil
            )],
        mappingBefore: [:],
        mappingAfter: [:],
        allocationGeneration: generation,
        effectGeneration: 1,
        resetGeneration: 1
    )
    let transition = SceneResolvedMaterialGraphExecutor.PreparedStage(
        effect: key,
        graph: graph,
        pairStep: .init(
            effect: key,
            inputIdentity: output,
            outputIdentity: output,
            inputMember: .zero,
            outputMember: .zero,
            nodes: [.init(
                nodeIndex: 0,
                kind: .material,
                rotatesAfterNode: true
            )]
        ),
        transition: .init(nextState: state, transaction: transaction),
        inputWidth: 2_048,
        inputHeight: 1_152,
        historyRehydrateCopyCount: 0,
        historyContentDiscarded: false,
        frameResources: [:],
        persistentResources: [:],
        effectOutputResource: resource,
        programCacheKeys: ["atomic-program-\(layerID)"],
        effectLocalFailureReasonCode: discardedPersistentTargetState
            ? "fixture-effect-local-visual-failure"
            : nil,
        effectLocalActivationBypassReasonCode: nil,
        discardedPersistentTargetState: discardedPersistentTargetState
    )
    return .init(
        stages: [transition],
        finalResource: resource,
        finalTexture: texture,
        historyTokensByEffect: [:]
    )
}

private func makeAtomicTargets(
    layerID: Int,
    generation: UInt64
) -> (
    prepared: ScenePreparedPersistentGraphTargets,
    commit: ScenePreparedPersistentGraphTargets.Commit
) {
    let lease = SceneGraphRenderTargetLease(
        table: .init(plan: .init(identity: layerID)),
        generation: generation,
        texturesByToken: [:],
        fullFramePair: .init(
            first: .init(rawValue: "pair-\(layerID)-zero"),
            second: .init(rawValue: "pair-\(layerID)-one")
        )
    )
    let commit = ScenePreparedPersistentGraphTargets.Commit(
        leases: [lease],
        submissionPin: .init(purpose: .submission, generation: generation),
        historyPinsByEffect: [:]
    )
    return (
        .init(leases: [lease], action: { _, _, _ in commit }),
        commit
    )
}

private func makeCommittedObservationBase() -> State {
    .init(
        effectGeneration: 3,
        resetGeneration: 4,
        allocationGeneration: 2,
        logicalMapping: [historyIdentity: .init(
            token: .init(rawValue: "committed-history-token"),
            contentGeneration: 7
        )],
        historyLogicalIdentities: [historyIdentity],
        historyClosureIdentities: [historyIdentity]
    )
}

private func makeCommit(
    generation: UInt64,
    historyPin: SceneGraphRenderTargetResidencyPin? = nil
) -> ScenePreparedPersistentGraphTargets.Commit {
    .init(
        leases: [],
        submissionPin: .init(purpose: .submission, generation: generation),
        historyPinsByEffect: historyPin.map { [effect: $0] } ?? [:]
    )
}

private func makeLedger(
    coordinator: Coordinator,
    identity: UInt64,
    commandBuffer: MTLCommandBuffer,
    prepared: SceneResolvedMaterialGraphExecutor.PreparedGraph,
    preparedDependencyEffect: SceneDependencyEffectInput? = nil,
    commit: ScenePreparedPersistentGraphTargets.Commit,
    blueprint: Coordinator.CandidateBlueprint? = nil,
    candidate: [Graph.EffectKey: Coordinator.Tail]? = nil,
    phase: Coordinator.LedgerPhase,
    submissionID: UInt64? = nil,
    claimed: Bool = true,
    consumed: Bool = false
) -> Coordinator.PreparedLedger {
    .init(
        identity: identity,
        epoch: coordinator.executionEpoch,
        frameIndex: identity,
        layerID: 7,
        capabilityToken: .init(value: 7),
        prepared: prepared,
        preparedDependencyEffect: preparedDependencyEffect,
        commandBuffer: commandBuffer,
        committedBaseTails: coordinator.committedTails,
        blueprint: blueprint,
        candidateTails: candidate,
        commit: commit,
        phase: phase,
        claimConsumed: claimed,
        ticketConsumed: consumed,
        outputConsumed: consumed,
        compositorConsumed: consumed,
        submissionID: submissionID
    )
}

private func externalPrimaryBinding(
    consumerLayerID: Int = 7,
    providerLayerID: Int = 42,
    slotIndex: Int = 1,
    blendMode: Int = 0,
    kind: SceneDependencyRenderPlan.Binding.Kind = .resolvedMaterial
) -> SceneDependencyRenderPlan.Binding {
    .init(
        consumerLayerID: consumerLayerID,
        providerLayerID: providerLayerID,
        slot: .init(
            effectID: "effect-\(consumerLayerID)",
            passIndex: 0,
            slotIndex: slotIndex
        ),
        blendMode: blendMode,
        kind: kind
    )
}

private func dependencyInput(
    binding: SceneDependencyRenderPlan.Binding,
    texture: MTLTexture,
    frameEpoch: UInt64 = 13,
    consumerLayerID: Int? = nil,
    providerLayerID: Int? = nil,
    variant: SceneNamedTextureReference.Variant = .primary,
    slot: SceneEffectPassSlot? = nil,
    blendMode: Int? = nil
) -> SceneDependencyEffectInput {
    .init(
        consumerLayerID: consumerLayerID ?? binding.consumerLayerID,
        providerLayerID: providerLayerID ?? binding.providerLayerID,
        variant: variant,
        slot: slot ?? binding.slot,
        blendMode: blendMode ?? binding.blendMode,
        frameEpoch: frameEpoch,
        texture: texture
    )
}

private func makeCapabilities(
    layerIDs: [Int] = [7],
    dependencyOwnershipByLayerID: [
        Int: SceneResolvedMaterialDependencyOwnership
    ] = [:],
    visualFailureReasonByLayerID: [Int: String] = [:],
    resolvesClaims: Bool = true
) -> SceneResolvedMaterialExecutionCapabilityCatalog {
    let capabilities = layerIDs.map { layerID ->
        SceneResolvedMaterialExecutionCapabilityCatalog.ChainCapability in
        let key = effect(for: layerID)
        let graph = Graph(
            layerID: layerID,
            effects: [.init(key: key)],
            nodes: [.init(nodeIndex: 0, kind: .material)]
        )
        return .init(
            layerID: layerID,
            pairPlan: .init(layerID: layerID),
            admittedProducts: [.init(graph: graph)],
            stages: [.init(
                subject: .init(
                    key: key,
                    family: visualFailureReasonByLayerID[layerID] == nil
                        ? "resolved-material" : "visual-failure-passthrough"
                ),
                visualFailureReasonCode: visualFailureReasonByLayerID[layerID]
            )],
            fullFrameExtentPolicy: .standard,
            dependencyOwnership:
                dependencyOwnershipByLayerID[layerID] ?? .none,
            sourceRoute: .capturedLayerTexture
        )
    }
    return .init(
        capability: capabilities.first,
        additionalCapabilities: Array(capabilities.dropFirst()),
        resolvesClaims: resolvesClaims
    )
}

private final class LogRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String] = []

    func append(_ value: String) {
        lock.lock()
        storage.append(value)
        lock.unlock()
    }

    var lines: [String] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}

private func makeCoordinator(
    _ device: MTLDevice,
    layerIDs: [Int] = [7],
    dependencyOwnershipByLayerID: [
        Int: SceneResolvedMaterialDependencyOwnership
    ] = [:],
    resolvesClaims: Bool = true,
    logSink: @escaping Coordinator.LogSink = { _ in }
) -> Coordinator {
    .init(
        device: device,
        capabilities: makeCapabilities(
            layerIDs: layerIDs,
            dependencyOwnershipByLayerID: dependencyOwnershipByLayerID,
            resolvesClaims: resolvesClaims
        ),
        logSink: logSink
    )
}

private func seedPendingSuccess(
    coordinator: Coordinator,
    identity: UInt64,
    commandBuffer: MTLCommandBuffer,
    tail: Coordinator.Tail?,
    commit: ScenePreparedPersistentGraphTargets.Commit,
    prepared: SceneResolvedMaterialGraphExecutor.PreparedGraph? = nil
) {
    _ = coordinator.observeCommandBufferLocked(commandBuffer)
    let ledger = makeLedger(
        coordinator: coordinator,
        identity: identity,
        commandBuffer: commandBuffer,
        prepared: prepared ?? makePrepared(device: commandBuffer.device),
        commit: commit,
        candidate: tail.map { [effect: $0] } ?? [:],
        phase: .sealed,
        submissionID: identity,
        consumed: true
    )
    coordinator.activeByID[identity] = ledger
    coordinator.pendingSubmissions.append(.init(
        identity: identity,
        ledgerIDs: [identity],
        commandBufferIdentities: [ObjectIdentifier(commandBuffer)],
        finalTails: tail.map { [effect: $0] } ?? [:],
        successObservationsByLedger: [identity: []],
        gpuStatus: nil,
        cancellationReason: nil,
        retiredHistoryPins: []
    ))
    coordinator.scheduledTails = tail.map { [effect: $0] } ?? [:]
}

private struct CancellationResult {
    let graphLines: [String]
    let releasedPins: Bool
    let clearedState: Bool
}

private func runPendingCancellation(
    device: MTLDevice,
    queue: MTLCommandQueue,
    reasonCode: String,
    gpuStatus: SceneGraphExecutionGPUCompletionStatus,
    consumed: Bool = true
) -> CancellationResult {
    let recorder = LogRecorder()
    let coordinator = makeCoordinator(
        device,
        logSink: { recorder.append($0) }
    )
    let commandBuffer = queue.makeCommandBuffer()!
    _ = coordinator.observeCommandBufferLocked(commandBuffer)
    let historyPin = SceneGraphRenderTargetResidencyPin(
        purpose: .history(effect, [.init(rawValue: "cancelled-history")]),
        generation: 3
    )
    let retiredPin = SceneGraphRenderTargetResidencyPin(
        purpose: .history(effect, [.init(rawValue: "retired-history")]),
        generation: 2
    )
    let commit = makeCommit(generation: 3, historyPin: historyPin)
    let tail = makeTail(
        device: device,
        token: "cancelled-history",
        generation: 3,
        pin: historyPin
    )
    coordinator.activeByID[1] = makeLedger(
        coordinator: coordinator,
        identity: 1,
        commandBuffer: commandBuffer,
        prepared: makeObservedPrepared(device: device),
        commit: commit,
        candidate: [effect: tail],
        phase: .sealed,
        submissionID: 1,
        consumed: consumed
    )
    coordinator.pendingSubmissions = [.init(
        identity: 1,
        ledgerIDs: [1],
        commandBufferIdentities: [ObjectIdentifier(commandBuffer)],
        finalTails: [effect: tail],
        successObservationsByLedger: [1: []],
        gpuStatus: nil,
        cancellationReason: reasonCode,
        retiredHistoryPins: [retiredPin]
    )]
    coordinator.completeCommandBuffer(
        identity: ObjectIdentifier(commandBuffer),
        status: gpuStatus
    )
    return .init(
        graphLines: recorder.lines.filter {
            $0.contains("axis=graph-execution")
        },
        releasedPins: commit.submissionPin.releaseCount == 1
            && historyPin.releaseCount == 1
            && retiredPin.releaseCount == 1,
        clearedState: coordinator.activeByID.isEmpty
            && coordinator.pendingSubmissions.isEmpty
    )
}

private func recordedFailure(
    _ result: CancellationResult,
    reasonCode: String,
    gpuStatus: SceneGraphExecutionGPUCompletionStatus?
) -> Bool {
    let gpu = gpuStatus?.rawValue ?? "-"
    return result.releasedPins
        && result.clearedState
        && result.graphLines.contains {
            $0.contains("outcome=failed")
                && $0.contains("failure=\(reasonCode)")
                && $0.contains("gpuCompletion=\(gpu)")
                && !$0.contains("diagnostic=")
    }
}

private struct DependencyExecutionProbe {
    let reasonCode: String
    let consumesExternalPrimaryDependency: Bool?
}

private func executeExternalDependency(
    device: MTLDevice,
    queue: MTLCommandQueue,
    binding: SceneDependencyRenderPlan.Binding,
    preparedDependencyEffect: SceneDependencyEffectInput?,
    readyDependencyEffect: SceneDependencyEffectInput?
) -> DependencyExecutionProbe {
    SceneResolvedMaterialGraphExecutor.encodeSucceeds = true
    let coordinator = makeCoordinator(
        device,
        dependencyOwnershipByLayerID: [7: .externalPrimary(binding)]
    )
    let buffer = queue.makeCommandBuffer()!
    let commit = makeCommit(generation: 1)
    coordinator.frameIsActive = true
    coordinator.frame = .init(frameIndex: 13)
    coordinator.activeByID[1] = makeLedger(
        coordinator: coordinator,
        identity: 1,
        commandBuffer: buffer,
        prepared: makePrepared(device: device),
        preparedDependencyEffect: preparedDependencyEffect,
        commit: commit,
        phase: .allocationCommitted,
        claimed: false
    )
    coordinator.activeTransactions = [1]
    coordinator.preparedLedgerByLayerID = [7: 1]
    coordinator.framePreparationComplete = true
    let claim: SceneResolvedMaterialRuntimeBridge.ClaimedExecution
    switch coordinator.claim(layerID: 7) {
    case let .claimed(value): claim = value
    case let .rejected(reasonCode):
        return .init(
            reasonCode: reasonCode,
            consumesExternalPrimaryDependency: nil
        )
    case .notMigrated:
        return .init(
            reasonCode: "not-migrated",
            consumesExternalPrimaryDependency: nil
        )
    }
    switch coordinator.executeClaimed(
        claim: claim,
        dependencyEffect: readyDependencyEffect,
        commandBuffer: buffer
    ) {
    case let .encoded(_, ticket):
        return .init(
            reasonCode: "encoded",
            consumesExternalPrimaryDependency:
                ticket.consumesExternalPrimaryDependency
        )
    case let .failed(reasonCode):
        return .init(
            reasonCode: reasonCode,
            consumesExternalPrimaryDependency: nil
        )
    }
}

@main
enum Harness {
    static func main() throws {
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue() else {
            print("{\"metalAvailable\":false}")
            return
        }
        var results: [String: Bool] = [:]

        do {
            let binding = externalPrimaryBinding()
            let reservedTexture = makeTexture(device, "dependency-reservation")
            let reserved = dependencyInput(
                binding: binding,
                texture: reservedTexture
            )
            let exact = executeExternalDependency(
                device: device,
                queue: queue,
                binding: binding,
                preparedDependencyEffect: reserved,
                readyDependencyEffect: dependencyInput(
                    binding: binding,
                    texture: reservedTexture
                )
            )
            results["externalDependencyExactReadyMatchIssuesTicket"] =
                exact.reasonCode == "encoded"
                && exact.consumesExternalPrimaryDependency == true

            let missing = executeExternalDependency(
                device: device,
                queue: queue,
                binding: binding,
                preparedDependencyEffect: reserved,
                readyDependencyEffect: nil
            )
            results["externalDependencyMissingReadyRejected"] =
                missing.reasonCode == "prepared-frame-consumption-rejected"

            let wrongProvider = executeExternalDependency(
                device: device,
                queue: queue,
                binding: binding,
                preparedDependencyEffect: reserved,
                readyDependencyEffect: dependencyInput(
                    binding: binding,
                    texture: reservedTexture,
                    providerLayerID: binding.providerLayerID + 1
                )
            )
            results["externalDependencyWrongProviderRejected"] =
                wrongProvider.reasonCode
                    == "prepared-frame-consumption-rejected"

            let wrongSlot = executeExternalDependency(
                device: device,
                queue: queue,
                binding: binding,
                preparedDependencyEffect: reserved,
                readyDependencyEffect: dependencyInput(
                    binding: binding,
                    texture: reservedTexture,
                    slot: .init(
                        effectID: binding.slot.effectID,
                        passIndex: binding.slot.passIndex,
                        slotIndex: binding.slot.slotIndex + 1
                    )
                )
            )
            results["externalDependencyWrongSlotRejected"] =
                wrongSlot.reasonCode == "prepared-frame-consumption-rejected"

            let wrongBlend = executeExternalDependency(
                device: device,
                queue: queue,
                binding: binding,
                preparedDependencyEffect: reserved,
                readyDependencyEffect: dependencyInput(
                    binding: binding,
                    texture: reservedTexture,
                    blendMode: binding.blendMode == 5 ? 0 : 5
                )
            )
            results["externalDependencyWrongBlendRejected"] =
                wrongBlend.reasonCode == "prepared-frame-consumption-rejected"

            let stale = executeExternalDependency(
                device: device,
                queue: queue,
                binding: binding,
                preparedDependencyEffect: reserved,
                readyDependencyEffect: dependencyInput(
                    binding: binding,
                    texture: reservedTexture,
                    frameEpoch: reserved.frameEpoch + 1
                )
            )
            results["externalDependencyWrongEpochRejected"] =
                stale.reasonCode == "prepared-frame-consumption-rejected"

            let wrongObject = executeExternalDependency(
                device: device,
                queue: queue,
                binding: binding,
                preparedDependencyEffect: reserved,
                readyDependencyEffect: dependencyInput(
                    binding: binding,
                    texture: makeTexture(device, "dependency-ready-lookalike")
                )
            )
            results["externalDependencyWrongObjectRejected"] =
                wrongObject.reasonCode
                    == "prepared-frame-consumption-rejected"
        }

        do {
            let binding = externalPrimaryBinding(
                slotIndex: 3,
                blendMode: 0,
                kind: .solidLayer
            )
            let reservedTexture = makeTexture(
                device,
                "solid-dependency-reservation"
            )
            let reserved = dependencyInput(
                binding: binding,
                texture: reservedTexture
            )
            let exact = executeExternalDependency(
                device: device,
                queue: queue,
                binding: binding,
                preparedDependencyEffect: reserved,
                readyDependencyEffect: dependencyInput(
                    binding: binding,
                    texture: reservedTexture
                )
            )
            results["solidDependencyExactReadyMatchIssuesTicket"] =
                exact.reasonCode == "encoded"
                && exact.consumesExternalPrimaryDependency == true

            let missing = executeExternalDependency(
                device: device,
                queue: queue,
                binding: binding,
                preparedDependencyEffect: reserved,
                readyDependencyEffect: nil
            )
            results["solidDependencyMissingReadyRejected"] =
                missing.reasonCode == "prepared-frame-consumption-rejected"

            let secondary = executeExternalDependency(
                device: device,
                queue: queue,
                binding: binding,
                preparedDependencyEffect: reserved,
                readyDependencyEffect: dependencyInput(
                    binding: binding,
                    texture: reservedTexture,
                    variant: .secondary
                )
            )
            results["solidDependencySecondaryRejected"] =
                secondary.reasonCode == "prepared-frame-consumption-rejected"

            let wrongEffect = executeExternalDependency(
                device: device,
                queue: queue,
                binding: binding,
                preparedDependencyEffect: reserved,
                readyDependencyEffect: dependencyInput(
                    binding: binding,
                    texture: reservedTexture,
                    slot: .init(
                        effectID: "wrong-effect",
                        passIndex: binding.slot.passIndex,
                        slotIndex: binding.slot.slotIndex
                    )
                )
            )
            results["solidDependencyWrongEffectRejected"] =
                wrongEffect.reasonCode == "prepared-frame-consumption-rejected"

            let wrongPass = executeExternalDependency(
                device: device,
                queue: queue,
                binding: binding,
                preparedDependencyEffect: reserved,
                readyDependencyEffect: dependencyInput(
                    binding: binding,
                    texture: reservedTexture,
                    slot: .init(
                        effectID: binding.slot.effectID,
                        passIndex: 1,
                        slotIndex: binding.slot.slotIndex
                    )
                )
            )
            results["solidDependencyWrongPassRejected"] =
                wrongPass.reasonCode == "prepared-frame-consumption-rejected"
        }

        do {
            let recorder = LogRecorder()
            let coordinator = makeCoordinator(
                device,
                logSink: { recorder.append($0) }
            )
            coordinator.invalidate(reason: .surfaceStop)
            results["normalInvalidateHasNoGraphDiagnostic"] = recorder.lines
                .allSatisfy { !$0.contains("axis=graph-execution diagnostic=") }
        }

        do {
            let coordinator = makeCoordinator(device)
            let priorResource = State.VersionedResource(
                token: .init(rawValue: "prior-history"),
                contentGeneration: 4
            )
            let nextResource = State.VersionedResource(
                token: .init(rawValue: "next-history"),
                contentGeneration: 4
            )
            let previous = State(
                effectGeneration: 1,
                resetGeneration: 1,
                allocationGeneration: 1,
                logicalMapping: [historyIdentity: priorResource],
                historyLogicalIdentities: [historyIdentity],
                historyClosureIdentities: [historyIdentity]
            )
            let next = State(
                effectGeneration: 1,
                resetGeneration: 1,
                allocationGeneration: 2,
                logicalMapping: [historyIdentity: nextResource],
                historyLogicalIdentities: [historyIdentity],
                historyClosureIdentities: [historyIdentity]
            )
            let transaction = State.Transaction(
                intents: [],
                mappingBefore: [historyIdentity: nextResource],
                mappingAfter: [historyIdentity: nextResource],
                allocationGeneration: 2,
                effectGeneration: 1,
                resetGeneration: 1
            )
            let copyOnWrite = coordinator.resetReasonLocked(
                previous: previous,
                next: next,
                transaction: transaction,
                historyRehydrateCopyCount: 1,
                historyContentDiscarded: false
            )
            results["stableHistoryAllocationClassifiesCopyOnWrite"] =
                copyOnWrite.valid && copyOnWrite.reason == .historyCopyOnWrite

            let changedResource = State.VersionedResource(
                token: .init(rawValue: "changed-history"),
                descriptor: .init(
                    extent: .init(width: 4, height: 4),
                    addressMode: .clampToEdge
                ),
                contentGeneration: 0
            )
            let changed = State(
                effectGeneration: 1,
                resetGeneration: 1,
                allocationGeneration: 2,
                logicalMapping: [historyIdentity: changedResource],
                historyLogicalIdentities: [historyIdentity],
                historyClosureIdentities: [historyIdentity]
            )
            let reprepare = coordinator.resetReasonLocked(
                previous: previous,
                next: changed,
                transaction: transaction,
                historyRehydrateCopyCount: 0,
                historyContentDiscarded: true
            )
            results["descriptorChangeClassifiesAllocationReprepare"] =
                reprepare.valid && reprepare.reason == .allocationReprepare

            let emptyPrevious = State(
                effectGeneration: 1,
                resetGeneration: 1,
                allocationGeneration: 1,
                logicalMapping: [:],
                historyLogicalIdentities: [],
                historyClosureIdentities: []
            )
            let emptyNext = State(
                effectGeneration: 1,
                resetGeneration: 1,
                allocationGeneration: 2,
                logicalMapping: [:],
                historyLogicalIdentities: [],
                historyClosureIdentities: []
            )
            let rebind = coordinator.resetReasonLocked(
                previous: emptyPrevious,
                next: emptyNext,
                transaction: transaction,
                historyRehydrateCopyCount: 0,
                historyContentDiscarded: false
            )
            results["historyFreeFreshIdentityClassifiesAllocationRebind"] =
                rebind.valid && rebind.reason == .allocationRebind

            let unknown = coordinator.resetReasonLocked(
                previous: previous,
                next: next,
                transaction: transaction,
                historyRehydrateCopyCount: 0,
                historyContentDiscarded: false
            )
            results["unknownHistoryTransitionRejected"] = !unknown.valid

            let initial = coordinator.resetReasonLocked(
                previous: nil,
                next: next,
                transaction: transaction,
                historyRehydrateCopyCount: 0,
                historyContentDiscarded: false
            )
            coordinator.invalidate(reason: .executorInvalidation)
            let invalidatedTransaction = State.Transaction(
                intents: [],
                mappingBefore: [:],
                mappingAfter: [:],
                allocationGeneration: 3,
                effectGeneration: 1,
                resetGeneration: coordinator.resetGeneration
            )
            let invalidatedNext = State(
                effectGeneration: 1,
                resetGeneration: coordinator.resetGeneration,
                allocationGeneration: 3,
                logicalMapping: [:],
                historyLogicalIdentities: [],
                historyClosureIdentities: []
            )
            let invalidated = coordinator.resetReasonLocked(
                previous: nil,
                next: invalidatedNext,
                transaction: invalidatedTransaction,
                historyRehydrateCopyCount: 0,
                historyContentDiscarded: false
            )
            results["freshAndInvalidatedInitialStatesKeepDistinctReasons"] =
                initial.valid && initial.reason == .initial
                && invalidated.valid
                && invalidated.reason == .executorInvalidation
        }

        for (key, reason) in [
            ("deviceLossInvalidateHasGraphDiagnostic", SceneGraphExecutionResetReason.deviceLoss),
            ("executorInvalidateHasGraphDiagnostic", SceneGraphExecutionResetReason.executorInvalidation),
        ] {
            let recorder = LogRecorder()
            let coordinator = makeCoordinator(
                device,
                logSink: { recorder.append($0) }
            )
            coordinator.invalidate(reason: reason)
            results[key] = recorder.lines.contains {
                $0.contains("axis=graph-execution diagnostic=")
                    && $0.contains("runtime-invalidated-\(reason.rawValue)")
            }
        }

        for (key, reason) in [
            ("pendingSurfaceStopCancelsSilently", SceneGraphExecutionResetReason.surfaceStop),
            ("pendingSceneSwitchCancelsSilently", SceneGraphExecutionResetReason.sceneSwitch),
        ] {
            let cancellation = runPendingCancellation(
                device: device,
                queue: queue,
                reasonCode: reason.rawValue,
                gpuStatus: .completed
            )
            results[key] = cancellation.graphLines.isEmpty
                && cancellation.releasedPins
                && cancellation.clearedState
        }

        for (key, reason) in [
            ("allocationReprepareRemainsFailure", SceneGraphExecutionResetReason.allocationReprepare),
            ("effectReparseRemainsFailure", SceneGraphExecutionResetReason.effectReparse),
            ("deviceLossRemainsFailure", SceneGraphExecutionResetReason.deviceLoss),
            ("executorInvalidationRemainsFailure", SceneGraphExecutionResetReason.executorInvalidation),
        ] {
            let cancellation = runPendingCancellation(
                device: device,
                queue: queue,
                reasonCode: reason.rawValue,
                gpuStatus: .completed
            )
            results[key] = recordedFailure(
                cancellation,
                reasonCode: reason.rawValue,
                gpuStatus: nil
            )
        }

        let unknownCancellation = runPendingCancellation(
            device: device,
            queue: queue,
            reasonCode: "fixture-invariant-failure",
            gpuStatus: .completed
        )
        results["unknownCancellationRemainsFailure"] = recordedFailure(
            unknownCancellation,
            reasonCode: "fixture-invariant-failure",
            gpuStatus: nil
        )

        let failedSurfaceStop = runPendingCancellation(
            device: device,
            queue: queue,
            reasonCode: SceneGraphExecutionResetReason.surfaceStop.rawValue,
            gpuStatus: .failed
        )
        results["surfaceStopGPUFailureRemainsFailure"] = recordedFailure(
            failedSurfaceStop,
            reasonCode: SceneGraphExecutionResetReason.surfaceStop.rawValue,
            gpuStatus: .failed
        )

        let invalidSurfaceStop = runPendingCancellation(
            device: device,
            queue: queue,
            reasonCode: SceneGraphExecutionResetReason.surfaceStop.rawValue,
            gpuStatus: .completed,
            consumed: false
        )
        results["invalidSurfaceStopLedgerRemainsFailure"] = recordedFailure(
            invalidSurfaceStop,
            reasonCode: "lifecycle-cancellation-ledger-invariant-rejected",
            gpuStatus: nil
        )

        do {
            let prepared = makeObservationTransition(device: device)
            let success = try SceneResolvedMaterialGraphObservationBuilder.make(
                prepared,
                runtimeInstanceIdentity: "runtime-fixture",
                frameIndex: 10,
                transactionID: 12,
                executionEpoch: 11,
                mappingGeneration: 9,
                resetReason: .initial,
                terminalEffect: effect,
                terminalCompositorConsumed: true,
                outcome: .succeeded,
                gpu: .completed
            )
            let succeeded: Bool
            if case .succeeded = success.outcome { succeeded = true }
            else { succeeded = false }
            results["productionObservationBuilderSuccess"] = succeeded
                && success.identity.layerID == 7
                && success.nodeCounts.authored == 1
                && success.nodeCounts.material == 1
                && success.nodeCounts.rejected == 0
                && success.nodeCounts.compose == 1
                && success.composeSlotBefore == .primary
                && success.composeSlotAfter == .primary
                && success.finalOutput?.physicalIdentity
                    == "observation-output-token"
                && success.compositorConsumed
                && success.gpuCompletionStatus == .completed
                && success.resetReason == .initial
                && success.allocationGeneration == 3
                && success.mappingGeneration == 9
                && success.inputWidth == 2_048
                && success.inputHeight == 1_152
                && success.historyRehydrateCopyCount == 0
                && !success.historyContentDiscarded
                && success.transactionIdentity == "r4:11:12:0"
                && success.programIdentity == "fixture-program"

            let failed = try SceneResolvedMaterialGraphObservationBuilder.make(
                prepared,
                runtimeInstanceIdentity: "runtime-fixture",
                frameIndex: 10,
                transactionID: 13,
                executionEpoch: 11,
                mappingGeneration: 8,
                resetReason: .effectReparse,
                committedBaseState: makeCommittedObservationBase(),
                terminalEffect: effect,
                terminalCompositorConsumed: false,
                outcome: .failed(reasonCode: "fixture-gpu-failed"),
                gpu: .failed
            )
            let failedWithExpectedReason: Bool
            if case let .failed(reason) = failed.outcome {
                failedWithExpectedReason = reason == "fixture-gpu-failed"
            } else {
                failedWithExpectedReason = false
            }
            results["productionObservationBuilderFailure"] =
                failedWithExpectedReason
                && failed.nodeCounts.authored == 1
                && failed.nodeCounts.material == 0
                && failed.nodeCounts.rejected == 1
                && failed.nodeCounts.compose == 0
                && failed.composeSlotBefore == .none
                && failed.composeSlotAfter == .none
                && failed.finalOutput == nil
                && !failed.compositorConsumed
                && failed.gpuCompletionStatus == .failed
                && failed.resetReason == nil
                && failed.allocationGeneration == 2
                && failed.mappingGeneration == 8
                && failed.historyState == .reused
        }

        do {
            let coordinator = makeCoordinator(device)
            let admitted: Bool
            switch coordinator.preflightClaim(layerID: 7) {
            case .claimed: admitted = true
            case .rejected, .notMigrated: admitted = false
            }
            results["claimUsesCentralCapabilityAdmission"] = admitted
                && coordinator.frameClaimed == 0
        }

        do {
            let coordinator = makeCoordinator(device)
            let buffer = queue.makeCommandBuffer()!
            coordinator.beginFrame(
                textureSnapshot: .init(frameIndex: 2, valid: true),
                dynamicSnapshot: .init(),
                frameInputs: .init()
            )
            let rejectedBeforePrepare: Bool
            switch coordinator.claim(layerID: 7) {
            case let .rejected(reasonCode):
                rejectedBeforePrepare = reasonCode == "frame-candidate-not-prepared"
            case .claimed, .notMigrated:
                rejectedBeforePrepare = false
            }
            let emptyOutcome = coordinator.prepareFrame(
                [],
                pool: nil,
                commandBuffer: buffer
            )
            let emptyReady: Bool
            if case .ready = emptyOutcome { emptyReady = true }
            else { emptyReady = false }
            results["claimWaitsForAtomicFramePreparation"] =
                rejectedBeforePrepare
                && emptyReady
                && coordinator.framePreparationComplete
                && coordinator.frameClaimed == 0
                && coordinator.activeByID.isEmpty
                && coordinator.sealFrame(on: buffer)
            _ = coordinator.endFrame()
        }

        do {
            SceneResolvedMaterialGraphExecutor.preparedByToken = [
                7: makeAtomicPrepared(
                    device: device,
                    layerID: 7,
                    generation: 1,
                    discardedPersistentTargetState: true
                ),
            ]
            let coordinator = makeCoordinator(device)
            let buffer = queue.makeCommandBuffer()!
            coordinator.beginFrame(
                textureSnapshot: .init(frameIndex: 3, valid: true),
                dynamicSnapshot: .init(),
                frameInputs: .init()
            )
            guard case let .claimed(claim) = coordinator.preflightClaim(
                layerID: 7
            ) else { fatalError("discard fixture claim unavailable") }
            let targets = makeAtomicTargets(layerID: 7, generation: 1)
            let pool = SceneOffscreenTexturePool(prepared: targets.prepared)
            let outcome = coordinator.prepareFrame(
                [.init(
                    claim: claim,
                    targetPlan: .init(
                        token: claim.token,
                        allocation: .init(graphPlan: .init(key: .init(layerID: 7)))
                    ),
                    sourceTexture: makeTexture(device, "discard-source"),
                    sourceUniforms: .init(),
                    sourcePipeline: .init(),
                    dedicatedInputs: .fixture
                )],
                pool: pool,
                commandBuffer: buffer
            )
            let ready: Bool
            if case .ready = outcome { ready = true }
            else { ready = false }
            results["typedHistoryDiscardReachesPoolExactly"] =
                ready
                && pool.batchCommitCount == 1
                && pool.discardedHistoryEffectsByCommit == [
                    [Set([effect(for: 7)])],
                ]
                && targets.commit.historyPinsByEffect.isEmpty
            _ = coordinator.endFrame()
            targets.commit.releaseAll()
        }

        do {
            SceneResolvedMaterialGraphExecutor.preparedByToken = [
                7: makeAtomicPrepared(
                    device: device,
                    layerID: 7,
                    generation: 1,
                    discardedPersistentTargetState: true,
                    forgedDiscardTransaction: true
                ),
            ]
            let coordinator = makeCoordinator(device)
            let buffer = queue.makeCommandBuffer()!
            coordinator.beginFrame(
                textureSnapshot: .init(frameIndex: 4, valid: true),
                dynamicSnapshot: .init(),
                frameInputs: .init()
            )
            guard case let .claimed(claim) = coordinator.preflightClaim(
                layerID: 7
            ) else { fatalError("forged discard fixture claim unavailable") }
            let targets = makeAtomicTargets(layerID: 7, generation: 1)
            let pool = SceneOffscreenTexturePool(prepared: targets.prepared)
            let outcome = coordinator.prepareFrame(
                [.init(
                    claim: claim,
                    targetPlan: .init(
                        token: claim.token,
                        allocation: .init(graphPlan: .init(key: .init(layerID: 7)))
                    ),
                    sourceTexture: makeTexture(device, "forged-discard-source"),
                    sourceUniforms: .init(),
                    sourcePipeline: .init(),
                    dedicatedInputs: .fixture
                )],
                pool: pool,
                commandBuffer: buffer
            )
            let reason: String
            if case let .rejected(value) = outcome { reason = value }
            else { reason = "ready" }
            results["forgedHistoryDiscardRejectedBeforePoolCommit"] =
                reason == "persistent-allocation-commit-rejected"
                && pool.batchCommitCount == 0
                && pool.discardedHistoryEffectsByCommit.isEmpty
            _ = coordinator.endFrame()
            targets.commit.releaseAll()
            SceneResolvedMaterialGraphExecutor.preparedByToken = [:]
        }

        do {
            SceneResolvedMaterialGraphExecutor.prepareCallCount = 0
            SceneResolvedMaterialGraphExecutor.prepareTokens = []
            SceneResolvedMaterialGraphExecutor.encodeSucceeds = false
            SceneResolvedMaterialGraphExecutor.preparedByToken = [
                7: makeAtomicPrepared(device: device, layerID: 7, generation: 1),
            ]
            let coordinator = makeCoordinator(device, layerIDs: [7, 8])
            let buffer = queue.makeCommandBuffer()!
            coordinator.beginFrame(
                textureSnapshot: .init(frameIndex: 3, valid: true),
                dynamicSnapshot: .init(),
                frameInputs: .init()
            )
            func claim(_ layerID: Int) ->
                SceneResolvedMaterialRuntimeBridge.ClaimedExecution {
                switch coordinator.preflightClaim(layerID: layerID) {
                case let .claimed(value): return value
                case let .rejected(reasonCode): fatalError(reasonCode)
                case .notMigrated: fatalError("claim unavailable")
                }
            }
            let claim7 = claim(7)
            let claim8 = claim(8)
            let targets7 = makeAtomicTargets(layerID: 7, generation: 1)
            let targets8 = makeAtomicTargets(layerID: 8, generation: 2)
            let pool = SceneOffscreenTexturePool(factory: { plan in
                switch plan.graphPlan.key.layerID {
                case 7: targets7.prepared
                case 8: targets8.prepared
                default: nil
                }
            })
            let outcome = coordinator.prepareFrame(
                [
                    .init(
                        claim: claim7,
                        targetPlan: .init(
                            token: claim7.token,
                            allocation: .init(graphPlan: .init(key: .init(layerID: 7)))
                        ),
                        sourceTexture: makeTexture(device, "atomic-source-7"),
                        sourceUniforms: .init(),
                        sourcePipeline: .init(),
                        dedicatedInputs: .fixture
                    ),
                    .init(
                        claim: claim8,
                        targetPlan: .init(
                            token: claim8.token,
                            allocation: .init(graphPlan: .init(key: .init(layerID: 8)))
                        ),
                        sourceTexture: makeTexture(device, "atomic-source-8"),
                        sourceUniforms: .init(),
                        sourcePipeline: .init(),
                        dedicatedInputs: .fixture
                    ),
                ],
                pool: pool,
                commandBuffer: buffer
            )
            let reason: String
            switch outcome {
            case let .rejected(value): reason = value
            case .ready: reason = "ready"
            }
            let postFailureClaimRejected: Bool
            switch coordinator.claim(layerID: 7) {
            case let .rejected(reasonCode):
                postFailureClaimRejected =
                    reasonCode == "frame-candidate-not-prepared"
            case .claimed, .notMigrated:
                postFailureClaimRejected = false
            }
            results["secondPreparationFailureRollsBackWholeFrame"] =
                reason == "graph-preflight-fixture-preflight-unavailable"
                && SceneResolvedMaterialGraphExecutor.prepareTokens == [7, 8]
                && targets7.commit.submissionPin.releaseCount == 0
                && pool.batchCommitCount == 0
                && coordinator.activeByID.isEmpty
                && coordinator.activeTransactions.isEmpty
                && coordinator.preparedLedgerByLayerID.isEmpty
                && !coordinator.framePreparationComplete
                && coordinator.frameRequiresDrop
                && coordinator.frameClaimed == 0
                && postFailureClaimRejected
            targets7.commit.releaseAll()
            targets8.commit.releaseAll()
            SceneResolvedMaterialGraphExecutor.preparedByToken = [:]
        }

        do {
            SceneResolvedMaterialGraphExecutor.prepareCallCount = 0
            SceneResolvedMaterialGraphExecutor.prepareTokens = []
            SceneResolvedMaterialGraphExecutor.encodeSucceeds = true
            SceneResolvedMaterialGraphExecutor.preparedByToken = [
                7: makeAtomicPrepared(device: device, layerID: 7, generation: 1),
                8: makeAtomicPrepared(device: device, layerID: 8, generation: 2),
                9: makeAtomicPrepared(device: device, layerID: 9, generation: 3),
                10: makeAtomicPrepared(device: device, layerID: 10, generation: 4),
            ]
            let binding7 = externalPrimaryBinding(
                consumerLayerID: 7, providerLayerID: 42
            )
            let binding8 = externalPrimaryBinding(
                consumerLayerID: 8, providerLayerID: 7
            )
            let binding9 = externalPrimaryBinding(
                consumerLayerID: 9, providerLayerID: 8
            )
            let dependencyTexture7 = makeTexture(
                device, "cascading-dependency-reservation-7"
            )
            let dependencyTexture8 = makeTexture(
                device, "cascading-dependency-reservation-8"
            )
            let dependencyTexture9 = makeTexture(
                device, "cascading-dependency-reservation-9"
            )
            let recorder = LogRecorder()
            let coordinator = makeCoordinator(
                device,
                layerIDs: [7, 8, 9, 10],
                dependencyOwnershipByLayerID: [
                    7: .externalPrimary(binding7),
                    8: .externalPrimary(binding8),
                    9: .externalPrimary(binding9),
                ],
                logSink: recorder.append
            )
            let buffer = queue.makeCommandBuffer()!
            coordinator.beginFrame(
                textureSnapshot: .init(frameIndex: 3, valid: true),
                dynamicSnapshot: .init(),
                frameInputs: .init()
            )
            func cascadingPreflightClaim(_ layerID: Int) ->
                SceneResolvedMaterialRuntimeBridge.ClaimedExecution {
                switch coordinator.preflightClaim(layerID: layerID) {
                case let .claimed(value): return value
                case let .rejected(reasonCode): fatalError(reasonCode)
                case .notMigrated: fatalError("claim unavailable")
                }
            }
            let claims = [7, 8, 9, 10].map(cascadingPreflightClaim)
            let targets7 = makeAtomicTargets(layerID: 7, generation: 1)
            let targets8 = makeAtomicTargets(layerID: 8, generation: 2)
            let targets9 = makeAtomicTargets(layerID: 9, generation: 3)
            let targets10 = makeAtomicTargets(layerID: 10, generation: 4)
            let preparedTargets = [
                7: targets7.prepared,
                8: targets8.prepared,
                9: targets9.prepared,
                10: targets10.prepared,
            ]
            let pool = SceneOffscreenTexturePool(factory: { plan in
                preparedTargets[plan.graphPlan.key.layerID]
            })
            let dependencies = [
                7: dependencyInput(
                    binding: binding7,
                    texture: dependencyTexture7,
                    frameEpoch: 3
                ),
                8: dependencyInput(
                    binding: binding8,
                    texture: dependencyTexture8,
                    frameEpoch: 3
                ),
                9: dependencyInput(
                    binding: binding9,
                    texture: dependencyTexture9,
                    frameEpoch: 3
                ),
            ]
            let prepared = coordinator.prepareFrame(
                claims.map { claim in
                    .init(
                        claim: claim,
                        targetPlan: .init(
                            token: claim.token,
                            allocation: .init(
                                graphPlan: .init(key: .init(
                                    layerID: claim.layerID
                                ))
                            )
                        ),
                        sourceTexture: makeTexture(
                            device, "cascading-source-\(claim.layerID)"
                        ),
                        sourceUniforms: .init(),
                        sourcePipeline: .init(),
                        dedicatedInputs: dependencies[claim.layerID].map {
                            .fixture.replacingDependencyEffect($0)
                        } ?? .fixture
                    )
                },
                pool: pool,
                commandBuffer: buffer
            )
            let preparedReady: Bool
            if case .ready = prepared { preparedReady = true }
            else { preparedReady = false }
            let rejectionReason =
                "external-primary-provider-capture-unavailable"
            let cascadingRejections = [7, 8, 9].map { layerID in
                coordinator.rejectPreparedExternalDependencyLocally(
                    layerID: layerID,
                    reasonCode: rejectionReason
                )
            }
            let claim10ForExecution: SceneResolvedMaterialRuntimeBridge
                .ClaimedExecution
            switch coordinator.claim(layerID: 10) {
            case let .claimed(value): claim10ForExecution = value
            case let .rejected(reasonCode): fatalError(reasonCode)
            case .notMigrated: fatalError("claim unavailable")
            }
            let execution = coordinator.executeClaimed(
                claim: claim10ForExecution,
                dependencyEffect: nil,
                commandBuffer: buffer
            )
            let independentEncoded: Bool
            let independentComposited: Bool
            switch execution {
            case let .encoded(texture, ticket):
                independentEncoded = true
                if case .consumed = coordinator.markComposite(
                    ticket, texture: texture, consumed: true
                ) {
                    independentComposited = true
                } else {
                    independentComposited = false
                }
            case .failed:
                independentEncoded = false
                independentComposited = false
            }
            let sealed = coordinator.sealFrame(on: buffer)
            buffer.commit()
            buffer.waitUntilCompleted()
            coordinator.completeCommandBuffer(
                identity: ObjectIdentifier(buffer),
                status: buffer.status == .completed && buffer.error == nil
                    ? .completed : .failed
            )
            _ = coordinator.endFrame()
            let rejectionDiagnostics = recorder.lines.filter {
                $0.contains("dependency-subgraph-local-rejection layer=")
            }
            results["cascadingDependencyCaptureFailureRejectsTransitiveSubgraph"] =
                preparedReady
                && cascadingRejections == [true, true, true]
                && independentEncoded
                && independentComposited
                && sealed
                && buffer.status == .completed
                && buffer.error == nil
                && coordinator.activeByID.isEmpty
                && coordinator.pendingSubmissions.isEmpty
                && targets7.commit.submissionPin.releaseCount == 1
                && targets8.commit.submissionPin.releaseCount == 1
                && targets9.commit.submissionPin.releaseCount == 1
                && targets10.commit.submissionPin.releaseCount == 1
                && coordinator.frameFailures == 0
                && rejectionDiagnostics.count == 3
                && [7, 8, 9].allSatisfy { layerID in
                    rejectionDiagnostics.contains(where: {
                        $0.contains("layer=\(layerID) ")
                    })
                }
            SceneResolvedMaterialGraphExecutor.preparedByToken = [:]
        }

        do {
            SceneResolvedMaterialGraphExecutor.prepareCallCount = 0
            SceneResolvedMaterialGraphExecutor.prepareTokens = []
            SceneResolvedMaterialGraphExecutor
                .preparedDependencyTextureByToken = [:]
            SceneResolvedMaterialGraphExecutor.encodeSucceeds = true
            let providerPrepared = makeAtomicPrepared(
                device: device,
                layerID: 7,
                generation: 1
            )
            let consumerPrepared = makeAtomicPrepared(
                device: device,
                layerID: 8,
                generation: 2
            )
            SceneResolvedMaterialGraphExecutor.preparedByToken = [
                7: providerPrepared,
                8: consumerPrepared,
            ]
            let binding = externalPrimaryBinding(
                consumerLayerID: 8,
                providerLayerID: 7
            )
            let provisionalTexture = makeTexture(
                device,
                "nested-dependency-provisional"
            )
            let provisionalInput = dependencyInput(
                binding: binding,
                texture: provisionalTexture,
                frameEpoch: 13
            )
            let coordinator = makeCoordinator(
                device,
                layerIDs: [7, 8],
                dependencyOwnershipByLayerID: [8: .externalPrimary(binding)]
            )
            let buffer = queue.makeCommandBuffer()!
            coordinator.beginFrame(
                textureSnapshot: .init(frameIndex: 13, valid: true),
                dynamicSnapshot: .init(),
                frameInputs: .init()
            )
            func preflightClaim(_ layerID: Int) ->
                SceneResolvedMaterialRuntimeBridge.ClaimedExecution {
                switch coordinator.preflightClaim(layerID: layerID) {
                case let .claimed(value): return value
                case let .rejected(reasonCode): fatalError(reasonCode)
                case .notMigrated: fatalError("claim unavailable")
                }
            }
            let providerClaim = preflightClaim(7)
            let consumerClaim = preflightClaim(8)
            let providerTargets = makeAtomicTargets(
                layerID: 7,
                generation: 1
            )
            let consumerTargets = makeAtomicTargets(
                layerID: 8,
                generation: 2
            )
            let pool = SceneOffscreenTexturePool(factory: { plan in
                plan.graphPlan.key.layerID == 7
                    ? providerTargets.prepared : consumerTargets.prepared
            })
            let preparation = coordinator.prepareFrame(
                [
                    .init(
                        claim: providerClaim,
                        targetPlan: .init(
                            token: providerClaim.token,
                            allocation: .init(
                                graphPlan: .init(key: .init(layerID: 7))
                            )
                        ),
                        sourceTexture: makeTexture(
                            device,
                            "nested-provider-source"
                        ),
                        sourceUniforms: .init(),
                        sourcePipeline: .init(),
                        dedicatedInputs: .fixture
                    ),
                    .init(
                        claim: consumerClaim,
                        targetPlan: .init(
                            token: consumerClaim.token,
                            allocation: .init(
                                graphPlan: .init(key: .init(layerID: 8))
                            )
                        ),
                        sourceTexture: makeTexture(
                            device,
                            "nested-consumer-source"
                        ),
                        sourceUniforms: .init(),
                        sourcePipeline: .init(),
                        dedicatedInputs: .fixture
                            .replacingDependencyEffect(provisionalInput)
                    ),
                ],
                pool: pool,
                commandBuffer: buffer
            )
            let preparedReady: Bool
            if case .ready = preparation { preparedReady = true }
            else { preparedReady = false }
            let outputs = coordinator.preparedOutputTexturesByLayerID()
            let namedReservationWasRetained =
                SceneResolvedMaterialGraphExecutor
                    .preparedDependencyTextureByToken[8]
                    == ObjectIdentifier(provisionalTexture)
                && outputs?[7] === providerPrepared.finalTexture
                && outputs?[8] === consumerPrepared.finalTexture

            let providerPublished: Bool
            let providerTerminalIsNotCompositor: Bool
            switch coordinator.claim(layerID: 7) {
            case let .claimed(claim):
                switch coordinator.executeClaimed(
                    claim: claim,
                    dependencyEffect: nil,
                    commandBuffer: buffer
                ) {
                case let .encoded(texture, ticket):
                    if case .consumed = coordinator.markNamedPublication(
                        ticket,
                        texture: texture,
                        published: true
                    ) {
                        providerPublished = true
                    } else {
                        providerPublished = false
                    }
                    providerTerminalIsNotCompositor =
                        coordinator.activeByID[ticket.identity]?.phase
                            == .outputConsumed
                        && coordinator.activeByID[ticket.identity]?
                            .outputConsumed == true
                        && coordinator.activeByID[ticket.identity]?
                            .compositorConsumed == false
                case .failed:
                    providerPublished = false
                    providerTerminalIsNotCompositor = false
                }
            case .rejected, .notMigrated:
                providerPublished = false
                providerTerminalIsNotCompositor = false
            }

            let consumerComposited: Bool
            let readyInput = dependencyInput(
                binding: binding,
                texture: provisionalTexture,
                frameEpoch: 13
            )
            switch coordinator.claim(layerID: 8) {
            case let .claimed(claim):
                switch coordinator.executeClaimed(
                    claim: claim,
                    dependencyEffect: readyInput,
                    commandBuffer: buffer
                ) {
                case let .encoded(texture, ticket):
                    if case .consumed = coordinator.markComposite(
                        ticket,
                        texture: texture,
                        consumed: true
                    ) {
                        consumerComposited = true
                    } else {
                        consumerComposited = false
                    }
                case .failed:
                    consumerComposited = false
                }
            case .rejected, .notMigrated:
                consumerComposited = false
            }
            let sealed = coordinator.sealFrame(on: buffer)
            buffer.commit()
            buffer.waitUntilCompleted()
            coordinator.completeCommandBuffer(
                identity: ObjectIdentifier(buffer),
                status: buffer.status == .completed && buffer.error == nil
                    ? .completed : .failed
            )
            results[
                "preparedProviderOutputKeepsNamedReservationWithoutCompositorOwnership"
            ] = preparedReady
                && namedReservationWasRetained
                && providerPublished
                && providerTerminalIsNotCompositor
                && consumerComposited
                && sealed
                && buffer.status == .completed
                && buffer.error == nil
                && coordinator.activeByID.isEmpty
                && coordinator.pendingSubmissions.isEmpty
                && pool.batchCommitCount == 1
                && providerTargets.commit.submissionPin.releaseCount == 1
                && consumerTargets.commit.submissionPin.releaseCount == 1
            _ = coordinator.endFrame()
            SceneResolvedMaterialGraphExecutor.preparedByToken = [:]
            SceneResolvedMaterialGraphExecutor
                .preparedDependencyTextureByToken = [:]
            SceneResolvedMaterialGraphExecutor.encodeSucceeds = false
        }

        do {
            SceneResolvedMaterialGraphExecutor.prepareCallCount = 0
            SceneResolvedMaterialGraphExecutor.prepareTokens = []
            SceneResolvedMaterialGraphExecutor.encodeSucceeds = true
            SceneResolvedMaterialGraphExecutor.preparedByToken = [
                7: makeAtomicPrepared(device: device, layerID: 7, generation: 1),
                8: makeAtomicPrepared(device: device, layerID: 8, generation: 2),
            ]
            let binding = externalPrimaryBinding(consumerLayerID: 7)
            let dependencyTexture = makeTexture(
                device, "local-dependency-failure-reservation"
            )
            let dependency = dependencyInput(
                binding: binding,
                texture: dependencyTexture,
                frameEpoch: 3
            )
            let recorder = LogRecorder()
            let coordinator = makeCoordinator(
                device,
                layerIDs: [7, 8],
                dependencyOwnershipByLayerID: [7: .externalPrimary(binding)],
                logSink: recorder.append
            )
            let buffer = queue.makeCommandBuffer()!
            coordinator.beginFrame(
                textureSnapshot: .init(frameIndex: 3, valid: true),
                dynamicSnapshot: .init(),
                frameInputs: .init()
            )
            func preflightClaim(_ layerID: Int) ->
                SceneResolvedMaterialRuntimeBridge.ClaimedExecution {
                switch coordinator.preflightClaim(layerID: layerID) {
                case let .claimed(value): return value
                case let .rejected(reasonCode): fatalError(reasonCode)
                case .notMigrated: fatalError("claim unavailable")
                }
            }
            let claim7 = preflightClaim(7)
            let claim8 = preflightClaim(8)
            let targets7 = makeAtomicTargets(layerID: 7, generation: 1)
            let targets8 = makeAtomicTargets(layerID: 8, generation: 2)
            let pool = SceneOffscreenTexturePool(factory: { plan in
                switch plan.graphPlan.key.layerID {
                case 7: targets7.prepared
                case 8: targets8.prepared
                default: nil
                }
            })
            let prepared = coordinator.prepareFrame(
                [
                    .init(
                        claim: claim7,
                        targetPlan: .init(
                            token: claim7.token,
                            allocation: .init(
                                graphPlan: .init(key: .init(layerID: 7))
                            )
                        ),
                        sourceTexture: makeTexture(device, "local-source-7"),
                        sourceUniforms: .init(),
                        sourcePipeline: .init(),
                        dedicatedInputs: .fixture.replacingDependencyEffect(
                            dependency
                        )
                    ),
                    .init(
                        claim: claim8,
                        targetPlan: .init(
                            token: claim8.token,
                            allocation: .init(
                                graphPlan: .init(key: .init(layerID: 8))
                            )
                        ),
                        sourceTexture: makeTexture(device, "local-source-8"),
                        sourceUniforms: .init(),
                        sourcePipeline: .init(),
                        dedicatedInputs: .fixture
                    ),
                ],
                pool: pool,
                commandBuffer: buffer
            )
            let preparedReady: Bool
            if case .ready = prepared { preparedReady = true }
            else { preparedReady = false }
            let integrityReasonRejected = !coordinator
                .rejectPreparedExternalDependencyLocally(
                    layerID: 7,
                    reasonCode: "external-primary-reservation-missing"
                )
            let rejectedLocally = coordinator
                .rejectPreparedExternalDependencyLocally(
                    layerID: 7,
                    reasonCode:
                        "external-primary-provider-capture-unavailable"
                )
            let claim8ForExecution: SceneResolvedMaterialRuntimeBridge
                .ClaimedExecution
            switch coordinator.claim(layerID: 8) {
            case let .claimed(value): claim8ForExecution = value
            case let .rejected(reasonCode): fatalError(reasonCode)
            case .notMigrated: fatalError("claim unavailable")
            }
            let execution = coordinator.executeClaimed(
                claim: claim8ForExecution,
                dependencyEffect: nil,
                commandBuffer: buffer
            )
            let encoded: Bool
            let composited: Bool
            switch execution {
            case let .encoded(texture, ticket):
                encoded = true
                if case .consumed = coordinator.markComposite(
                    ticket, texture: texture, consumed: true
                ) {
                    composited = true
                } else {
                    composited = false
                }
            case .failed:
                encoded = false
                composited = false
            }
            let sealed = coordinator.sealFrame(on: buffer)
            buffer.commit()
            buffer.waitUntilCompleted()
            coordinator.completeCommandBuffer(
                identity: ObjectIdentifier(buffer),
                status: buffer.status == .completed && buffer.error == nil
                    ? .completed : .failed
            )
            _ = coordinator.endFrame()
            results["externalDependencyCaptureFailureRejectsOnlyItsSubgraph"] =
                preparedReady
                && integrityReasonRejected
                && rejectedLocally
                && encoded
                && composited
                && sealed
                && buffer.status == .completed
                && buffer.error == nil
                && targets7.commit.submissionPin.releaseCount == 1
                && targets8.commit.submissionPin.releaseCount == 1
                && coordinator.frameFailures == 0
                && recorder.lines.contains(where: {
                    $0.contains("dependency-subgraph-local-rejection layer=7")
                })
            SceneResolvedMaterialGraphExecutor.preparedByToken = [:]
        }

        do {
            SceneResolvedMaterialGraphExecutor.prepareCallCount = 0
            SceneResolvedMaterialGraphExecutor.prepareTokens = []
            SceneResolvedMaterialGraphExecutor.preparedByToken = [
                7: makeAtomicPrepared(
                    device: device,
                    layerID: 7,
                    generation: 2,
                    terminalSampling: .linearRepeat
                ),
            ]
            let previousPin = SceneGraphRenderTargetResidencyPin(
                purpose: .history(
                    effect,
                    [.init(rawValue: "terminal-repeat-safe-history")]
                ),
                generation: 1
            )
            let previousTail = makeTail(
                device: device,
                token: "terminal-repeat-safe-history",
                generation: 1,
                pin: previousPin
            )
            let previousResource = previousTail.persistentResources[historyIdentity]!
            let coordinator = makeCoordinator(device)
            coordinator.committedTails = [effect: previousTail]
            coordinator.scheduledTails = coordinator.committedTails
            let buffer = queue.makeCommandBuffer()!
            coordinator.beginFrame(
                textureSnapshot: .init(frameIndex: 4, valid: true),
                dynamicSnapshot: .init(),
                frameInputs: .init()
            )
            let claim: SceneResolvedMaterialRuntimeBridge.ClaimedExecution
            switch coordinator.preflightClaim(layerID: 7) {
            case let .claimed(value): claim = value
            case let .rejected(reasonCode): fatalError(reasonCode)
            case .notMigrated: fatalError("claim unavailable")
            }
            let targets = makeAtomicTargets(layerID: 7, generation: 2)
            let pool = SceneOffscreenTexturePool(factory: { _ in targets.prepared })
            let transactionIDBefore = coordinator.nextTransactionID
            let outcome = coordinator.prepareFrame(
                [.init(
                    claim: claim,
                    targetPlan: .init(
                        token: claim.token,
                        allocation: .init(graphPlan: .init(key: .init(layerID: 7)))
                    ),
                    sourceTexture: makeTexture(device, "repeat-terminal-source"),
                    sourceUniforms: .init(),
                    sourcePipeline: .init(),
                    dedicatedInputs: .fixture
                )],
                pool: pool,
                commandBuffer: buffer
            )
            let reason: String
            switch outcome {
            case let .rejected(value): reason = value
            case .ready: reason = "ready"
            }
            let postFailureClaimRejected: Bool
            switch coordinator.claim(layerID: 7) {
            case let .rejected(reasonCode):
                postFailureClaimRejected =
                    reasonCode == "frame-candidate-not-prepared"
            case .claimed, .notMigrated:
                postFailureClaimRejected = false
            }
            let previousPublicationPreserved: Bool = {
                guard let committed = coordinator.committedTails[effect],
                      let scheduled = coordinator.scheduledTails[effect],
                      committed.historyPin === previousPin,
                      scheduled.historyPin === previousPin,
                      committed.mappingGeneration == previousTail.mappingGeneration,
                      scheduled.mappingGeneration == previousTail.mappingGeneration,
                      let current = committed.persistentResources[historyIdentity],
                      current.publication.isSameAtom(
                          as: previousResource.publication
                      ),
                      current.publication.candidate.sampling == .linearClamp,
                      current.publication.requestIdentity == .graph(historyIdentity),
                      current.publication.texture === previousResource.publication.texture,
                      case let .provider(.graph(generation, token)) =
                        current.publication.candidate.identity else { return false }
                return generation == 1
                    && token == "terminal-repeat-safe-history"
                    && current.resourceGeneration == 1
                    && current.publication.contentGeneration == 1
            }()
            results["repeatTerminalPublicationRejectsBeforeLedgerAndPreservesPreviousCurrent"] =
                reason == "persistent-allocation-commit-rejected"
                && SceneResolvedMaterialGraphExecutor.prepareTokens == [7]
                && coordinator.activeByID.isEmpty
                && coordinator.activeTransactions.isEmpty
                && coordinator.preparedLedgerByLayerID.isEmpty
                && coordinator.pendingSubmissions.isEmpty
                && coordinator.nextTransactionID == transactionIDBefore
                && coordinator.commandBufferRecords.isEmpty
                && coordinator.frameFailures == 1
                && coordinator.frameRequiresDrop
                && !coordinator.framePreparationComplete
                && coordinator.frameClaimed == 0
                && pool.batchCommitCount == 0
                && targets.commit.submissionPin.releaseCount == 0
                && buffer.status == .notEnqueued
                && previousPin.active
                && previousPin.releaseCount == 0
                && previousPublicationPreserved
                && postFailureClaimRejected
            targets.commit.releaseAll()
            SceneResolvedMaterialGraphExecutor.preparedByToken = [:]
        }

        do {
            SceneResolvedMaterialGraphExecutor.prepareCallCount = 0
            SceneResolvedMaterialGraphExecutor.prepareTokens = []
            SceneResolvedMaterialGraphExecutor.encodeSucceeds = true
            SceneResolvedMaterialGraphExecutor.preparedByToken = [
                7: makeAtomicPrepared(device: device, layerID: 7, generation: 1),
                8: makeAtomicPrepared(device: device, layerID: 8, generation: 2),
            ]
            let coordinator = makeCoordinator(device, layerIDs: [7, 8])
            let buffer = queue.makeCommandBuffer()!
            coordinator.beginFrame(
                textureSnapshot: .init(frameIndex: 4, valid: true),
                dynamicSnapshot: .init(),
                frameInputs: .init()
            )
            func preflightClaim(_ layerID: Int) ->
                SceneResolvedMaterialRuntimeBridge.ClaimedExecution {
                switch coordinator.preflightClaim(layerID: layerID) {
                case let .claimed(value): return value
                case let .rejected(reasonCode): fatalError(reasonCode)
                case .notMigrated: fatalError("claim unavailable")
                }
            }
            let preflight7 = preflightClaim(7)
            let preflight8 = preflightClaim(8)
            let targets7 = makeAtomicTargets(layerID: 7, generation: 1)
            let targets8 = makeAtomicTargets(layerID: 8, generation: 2)
            let pool = SceneOffscreenTexturePool(factory: { plan in
                plan.graphPlan.key.layerID == 7
                    ? targets7.prepared : targets8.prepared
            })
            let prepared = coordinator.prepareFrame(
                [
                    .init(
                        claim: preflight7,
                        targetPlan: .init(
                            token: preflight7.token,
                            allocation: .init(graphPlan: .init(key: .init(layerID: 7)))
                        ),
                        sourceTexture: makeTexture(device, "success-source-7"),
                        sourceUniforms: .init(),
                        sourcePipeline: .init(),
                        dedicatedInputs: .fixture
                    ),
                    .init(
                        claim: preflight8,
                        targetPlan: .init(
                            token: preflight8.token,
                            allocation: .init(graphPlan: .init(key: .init(layerID: 8)))
                        ),
                        sourceTexture: makeTexture(device, "success-source-8"),
                        sourceUniforms: .init(),
                        sourcePipeline: .init(),
                        dedicatedInputs: .fixture
                    ),
                ],
                pool: pool,
                commandBuffer: buffer
            )
            let atomicallyPublished: Bool
            if case .ready = prepared {
                atomicallyPublished = coordinator.framePreparationComplete
                    && coordinator.activeByID.count == 2
                    && Set(coordinator.preparedLedgerByLayerID.keys) == [7, 8]
                    && coordinator.frameClaimed == 0
            } else {
                atomicallyPublished = false
            }
            func consume(_ layerID: Int) -> Bool {
                let claim: SceneResolvedMaterialRuntimeBridge.ClaimedExecution
                switch coordinator.claim(layerID: layerID) {
                case let .claimed(value): claim = value
                case .rejected, .notMigrated: return false
                }
                switch coordinator.executeClaimed(
                    claim: claim,
                    dependencyEffect: nil,
                    commandBuffer: buffer
                ) {
                case let .encoded(texture, ticket):
                    let outcome = coordinator.markComposite(
                        ticket,
                        texture: texture,
                        consumed: true
                    )
                    if case .consumed = outcome { return true }
                    return false
                case .failed:
                    return false
                }
            }
            let consumed = consume(7) && consume(8)
            let composited = coordinator.activeByID.values.allSatisfy {
                $0.phase == .outputConsumed && $0.compositorConsumed
            }
            let sealed = coordinator.sealFrame(on: buffer)
            let oneSubmission = coordinator.pendingSubmissions.count == 1
                && coordinator.pendingSubmissions[0].ledgerIDs.count == 2
            coordinator.completeCommandBuffer(
                identity: ObjectIdentifier(buffer),
                status: .completed
            )
            results["twoCandidatesPublishConsumeAndCommitAtomically"] =
                atomicallyPublished
                && SceneResolvedMaterialGraphExecutor.prepareTokens == [7, 8]
                && consumed && composited && sealed && oneSubmission
                && coordinator.frameClaimed == 2
                && coordinator.frameEncoded == 2
                && coordinator.activeByID.isEmpty
                && coordinator.pendingSubmissions.isEmpty
                && pool.batchCommitCount == 1
                && targets7.commit.submissionPin.releaseCount == 1
                && targets8.commit.submissionPin.releaseCount == 1
            _ = coordinator.endFrame()
            SceneResolvedMaterialGraphExecutor.preparedByToken = [:]
            SceneResolvedMaterialGraphExecutor.encodeSucceeds = false
        }

        do {
            let coordinator = makeCoordinator(device)
            let exact: Bool
            switch coordinator.preflightClaim(layerID: 7) {
            case let .claimed(claim):
                exact = claim.admittedGraphs.flatMap {
                    $0.effects.map(\.key)
                } == [effect]
            case .rejected, .notMigrated:
                exact = false
            }
            results["claimCarriesGraphIdentityOnly"] = exact
        }

        do {
            let bridge = SceneResolvedMaterialRuntimeBridge(
                catalog: .init(
                    userPropertyDemands: [],
                    systemProviderDemands: []
                ),
                capabilities: makeCapabilities(layerIDs: [7, 8]),
                assets: .init(states: [:]),
                device: device
            )
            let key7 = effect(for: 7)
            let key8 = effect(for: 8)
            guard case let .claimed(claim7) = bridge.preflightClaim(layerID: 7),
                  case let .claimed(claim8) = bridge.preflightClaim(layerID: 8) else {
                fatalError("fixture capability claims unavailable")
            }
            results["uninstalledDispositionEvidenceIsNotInvoked"] =
                bridge.executionEvidenceSubjects(for: claim7).isEmpty
                && bridge.executionEvidenceSubjects(for: claim8).isEmpty
            bridge.installExecutionEvidence([
                .init(key: key7, family: "generic-framebuffer"),
            ])
            guard let fallback7 = bridge.executionEvidenceSubjects(
                for: claim7
            ).first else {
                fatalError("installed fixture disposition unavailable")
            }
            results["bridgeProjectsOnlyInstalledDispositionEvidence"] =
                fallback7.key == key7
                && fallback7.family == "generic-framebuffer"
                && bridge.executionEvidenceSubjects(for: claim8).isEmpty
            results["executionEvidenceOverridesFallbackFamily"] =
                bridge.executionEvidenceFamily(for: fallback7.key)
                    == "generic-framebuffer"
            results["missingExecutionEvidenceKeepsFallbackIsolated"] =
                bridge.executionEvidenceFamily(for: key8) == nil

            let passthroughBridge = SceneResolvedMaterialRuntimeBridge(
                catalog: .init(
                    userPropertyDemands: [],
                    systemProviderDemands: []
                ),
                capabilities: makeCapabilities(
                    layerIDs: [9],
                    visualFailureReasonByLayerID: [
                        9: "material-variant-envelope-frontend",
                    ]
                ),
                assets: .init(states: [:]),
                device: device
            )
            passthroughBridge.installExecutionEvidence([
                .init(
                    key: effect(for: 9),
                    family: "visual-failure-passthrough"
                ),
            ])
            if case let .claimed(passthroughClaim) = passthroughBridge
                .preflightClaim(layerID: 9),
               let passthroughSubject = passthroughBridge
                .executionEvidenceSubjects(for: passthroughClaim).first,
               case let .failed(reasonCode) = passthroughBridge
                .executionEvidenceOutcome(
                    for: passthroughSubject,
                    claim: passthroughClaim,
                    ticket: .init(
                        identity: 0,
                        epoch: 0,
                        finalTextureIdentity: ObjectIdentifier(device),
                        consumesExternalPrimaryDependency: false,
                        effectFailures: []
                    )
                ) {
                results["visualFailurePassthroughKeepsFailedTelemetry"] =
                    passthroughSubject.family == "visual-failure-passthrough"
                    && reasonCode == "effect-local-passthrough-"
                        + "material-variant-envelope-frontend"
            } else {
                results["visualFailurePassthroughKeepsFailedTelemetry"] = false
            }

            if case let .failed(reasonCode) = bridge.executionEvidenceOutcome(
                for: fallback7,
                claim: claim7,
                ticket: .init(
                    identity: 1,
                    epoch: 1,
                    finalTextureIdentity: ObjectIdentifier(device),
                    consumesExternalPrimaryDependency: false,
                    effectFailures: [.init(
                        layerID: key7.layerID,
                        effectIndex: key7.effectIndex,
                        descriptorID: key7.descriptorID,
                        reasonCode: "material-pass-preparation-library-compilation"
                    )]
                )
            ) {
                results["dynamicRendererPassthroughKeepsFailedTelemetry"] =
                    reasonCode == "effect-local-passthrough-"
                        + "material-pass-preparation-library-compilation"
            } else {
                results["dynamicRendererPassthroughKeepsFailedTelemetry"] = false
            }

            bridge.installExecutionEvidence([
                .init(key: key7, family: "generic-framebuffer"),
                .init(key: key7, family: "generic-framebuffer"),
                .init(key: key8, family: "second-family"),
            ])
            results["malformedExecutionEvidenceDropsOnlyInvalidKey"] =
                bridge.executionEvidenceFamily(for: key7) == nil
                && bridge.executionEvidenceFamily(for: key8) == "second-family"
                && bridge.executionEvidenceReportLines.contains {
                    $0.contains("issue: duplicate-key count=1")
                }

            bridge.installExecutionEvidence([
                .init(key: key7, family: "  "),
                .init(key: key8, family: "second-family"),
            ])
            results["emptyExecutionFamilyDropsOnlyInvalidKey"] =
                bridge.executionEvidenceFamily(for: key7) == nil
                && bridge.executionEvidenceFamily(for: key8) == "second-family"
                && bridge.executionEvidenceReportLines.contains {
                    $0.contains("issue: empty-family count=1")
                }
        }

        do {
            let coordinator = makeCoordinator(device, resolvesClaims: false)
            coordinator.frameIsActive = true
            let reason: String
            switch coordinator.preflightClaim(layerID: 7) {
            case let .rejected(reasonCode): reason = reasonCode
            case .claimed: reason = "claimed"
            case .notMigrated: reason = "not-migrated"
            }
            coordinator.recordClaimedFailure(reasonCode: reason)
            results["invalidCapabilityTokenRejectsWithoutLegacyFallback"] =
                reason == "execution-capability-token-invalid"
                && coordinator.frameClaimed == 0
                && coordinator.frameFailures == 1
                && coordinator.frameRequiresDrop
        }

        do {
            let recorder = LogRecorder()
            let coordinator = makeCoordinator(
                device,
                logSink: { recorder.append($0) }
            )
            coordinator.beginFrame(
                textureSnapshot: .init(frameIndex: 21, valid: true),
                dynamicSnapshot: .init(),
                frameInputs: .init()
            )
            let reason = "frame-target-plan-unsupported-target-descriptor"
            let installed = coordinator.installFrameLocalFallbacks([7: reason])
            let rejectedWithTypedReason: Bool
            switch coordinator.claim(layerID: 7) {
            case let .rejected(reasonCode):
                rejectedWithTypedReason = reasonCode == reason
            case .claimed, .notMigrated:
                rejectedWithTypedReason = false
            }
            results["typedTargetDescriptorFallbackRemainsLayerLocal"] =
                installed && rejectedWithTypedReason
                && recorder.lines.contains {
                    $0.contains("layer-local-fallback count=1 entries=7:\(reason)")
                }
        }

        do {
            let recorder = LogRecorder()
            let coordinator = makeCoordinator(
                device,
                logSink: { recorder.append($0) }
            )
            let buffer = queue.makeCommandBuffer()!
            coordinator.beginFrame(
                textureSnapshot: .init(frameIndex: 22, valid: true),
                dynamicSnapshot: .init(),
                frameInputs: .init()
            )
            let reason =
                "utility-composition-subtree-source-coverage-unavailable"
            let installed = coordinator.installFrameLocalFallbacks([7: reason])
            let rejectedWithTypedReason: Bool
            switch coordinator.claim(layerID: 7) {
            case let .rejected(reasonCode):
                rejectedWithTypedReason = reasonCode == reason
            case .claimed, .notMigrated:
                rejectedWithTypedReason = false
            }
            let preparedWithoutRootTarget: Bool
            switch coordinator.prepareFrame([], pool: nil, commandBuffer: buffer) {
            case .ready:
                preparedWithoutRootTarget = true
            case .rejected:
                preparedWithoutRootTarget = false
            }
            let frameStayedLocal = !coordinator.frameRequiresDrop
            let sealed = coordinator.sealFrame(on: buffer)
            buffer.commit()
            buffer.waitUntilCompleted()
            let audit = coordinator.endFrame().joined(separator: "\n")
            results["utilitySubtreeCoverageFallbackRemainsLayerLocal"] =
                installed && rejectedWithTypedReason
                && preparedWithoutRootTarget && frameStayedLocal && sealed
                && buffer.status == .completed
                && audit.contains("failures=0")
                && audit.contains("localFallbacks=1")
                && recorder.lines.contains {
                    $0.contains("layer-local-fallback count=1 entries=7:\(reason)")
                }
        }

        do {
            let recorder = LogRecorder()
            let coordinator = makeCoordinator(
                device,
                logSink: { recorder.append($0) }
            )
            let buffer = queue.makeCommandBuffer()!
            coordinator.frameIsActive = true
            coordinator.frame = .init(frameIndex: 1)
            let claim: SceneResolvedMaterialRuntimeBridge.ClaimedExecution
            switch coordinator.preflightClaim(layerID: 7) {
            case let .claimed(value): claim = value
            case let .rejected(reasonCode): fatalError(reasonCode)
            case .notMigrated: fatalError("claim unavailable")
            }
            let targetPlan = SceneResolvedMaterialFrameTargetPlan(
                token: claim.token,
                allocation: .init(graphPlan: .init(key: .init(layerID: 7)))
            )
            let outcome = coordinator.prepareFrame(
                [.init(
                    claim: claim,
                    targetPlan: targetPlan,
                    sourceTexture: makeTexture(device, "preflight-source"),
                    sourceUniforms: .init(),
                    sourcePipeline: .init(),
                    dedicatedInputs: .fixture
                )],
                pool: .init(),
                commandBuffer: buffer
            )
            let expected = "graph-preflight-fixture-preflight-unavailable"
            let reason: String
            switch outcome {
            case let .rejected(value): reason = value
            case .ready: reason = "ready"
            }
            results["preflightFailureReasonReachesCoordinatorEvidence"] =
                reason == expected
                && recorder.lines.contains {
                    $0.contains("axis=graph-execution diagnostic=\(expected)")
                }
                && coordinator.frameClaimed == 0
                && coordinator.frameFailures == 1
                && coordinator.frameRequiresDrop
        }

        do {
            let coordinator = makeCoordinator(device)
            let buffer = queue.makeCommandBuffer()!
            let prepared = makePrepared(device: device)
            let firstCommit = makeCommit(generation: 1)
            let secondCommit = makeCommit(generation: 1)
            coordinator.frameIsActive = true
            coordinator.activeByID[1] = makeLedger(
                coordinator: coordinator, identity: 1,
                commandBuffer: buffer, prepared: prepared,
                commit: firstCommit, phase: .allocationCommitted,
                claimed: false
            )
            coordinator.activeByID[2] = makeLedger(
                coordinator: coordinator, identity: 2,
                commandBuffer: buffer, prepared: prepared,
                commit: secondCommit, phase: .allocationCommitted
            )
            coordinator.activeTransactions = [1, 2]
            coordinator.preparedLedgerByLayerID = [7: 1]
            coordinator.framePreparationComplete = true
            let claimed: Bool
            switch coordinator.claim(layerID: 7) {
            case .claimed: claimed = true
            case .rejected: claimed = false
            case .notMigrated: claimed = false
            }
            coordinator.recordClaimedFailure(reasonCode: "post-claim-failed")
            results["postClaimFailureDropsWholeFrame"] = claimed
                && coordinator.frameClaimed == 1
                && coordinator.frameFailures == 1
                && coordinator.frameRequiresDrop
                && coordinator.activeByID.isEmpty
                && firstCommit.submissionPin.releaseCount == 1
                && secondCommit.submissionPin.releaseCount == 1
                && coordinator.resetGeneration == 1
        }

        do {
            let coordinator = makeCoordinator(device)
            let firstBuffer = queue.makeCommandBuffer()!
            let foreignBuffer = queue.makeCommandBuffer()!
            let commit = makeCommit(generation: 1)
            coordinator.frameIsActive = true
            coordinator.frame = .init(frameIndex: 1)
            coordinator.activeByID[1] = makeLedger(
                coordinator: coordinator, identity: 1,
                commandBuffer: firstBuffer,
                prepared: makePrepared(device: device),
                commit: commit, phase: .allocationCommitted
            )
            coordinator.activeTransactions = [1]
            coordinator.preparedLedgerByLayerID = [7: 1]
            coordinator.framePreparationComplete = true
            SceneResolvedMaterialGraphExecutor.prepareCallCount = 0
            let claim: SceneResolvedMaterialRuntimeBridge.ClaimedExecution
            switch coordinator.preflightClaim(layerID: 7) {
            case let .claimed(value): claim = value
            case let .rejected(reasonCode): fatalError(reasonCode)
            case .notMigrated: fatalError("claim unavailable")
            }
            let outcome = coordinator.executeClaimed(
                claim: claim,
                dependencyEffect: nil,
                commandBuffer: foreignBuffer
            )
            let reason: String
            switch outcome {
            case let .failed(value): reason = value
            case .encoded: reason = "encoded"
            }
            results["foreignBufferRejectedBeforePrepare"] =
                reason == "prepared-frame-consumption-rejected"
                && SceneResolvedMaterialGraphExecutor.prepareCallCount == 0
                && coordinator.activeByID.isEmpty
                && commit.submissionPin.releaseCount == 1
        }

        do {
            let coordinator = makeCoordinator(device)
            let buffer = queue.makeCommandBuffer()!
            let texture = makeTexture(device, "ticket-final")
            let historyPin = SceneGraphRenderTargetResidencyPin(
                purpose: .history(effect, [.init(rawValue: "A")]),
                generation: 1
            )
            let tail = makeTail(
                device: device, token: "A", generation: 1, pin: historyPin
            )
            let commit = makeCommit(generation: 1, historyPin: historyPin)
            coordinator.frameIsActive = true
            _ = coordinator.observeCommandBufferLocked(buffer)
            coordinator.activeByID[1] = makeLedger(
                coordinator: coordinator, identity: 1,
                commandBuffer: buffer,
                prepared: makePrepared(device: device, texture: texture),
                commit: commit, candidate: [effect: tail], phase: .encoded
            )
            coordinator.activeTransactions = [1]
            let ticket = SceneResolvedMaterialRuntimeBridge.ExecutionTicket(
                identity: 1,
                epoch: coordinator.executionEpoch,
                finalTextureIdentity: ObjectIdentifier(texture),
                consumesExternalPrimaryDependency: false,
                effectFailures: []
            )
            let firstOutcome = coordinator.markComposite(
                ticket, texture: texture, consumed: true
            )
            let firstWasConsumed: Bool
            if case .consumed = firstOutcome { firstWasConsumed = true }
            else { firstWasConsumed = false }
            let consumedOnce = coordinator.activeByID[1]?.phase == .outputConsumed
                && coordinator.activeByID[1]?.ticketConsumed == true
            let reusedOutcome = coordinator.markComposite(
                ticket, texture: texture, consumed: true
            )
            let reuseReason: String?
            if case let .failed(reasonCode) = reusedOutcome {
                reuseReason = reasonCode
            } else {
                reuseReason = nil
            }
            results["ticketIsSingleConsumption"] = firstWasConsumed
                && reuseReason == "final-composite-ticket-reused"
                && consumedOnce
                && coordinator.activeByID.isEmpty
                && coordinator.frameRequiresDrop
                && commit.submissionPin.releaseCount == 1
                && historyPin.releaseCount == 1
        }

        do {
            let coordinator = makeCoordinator(device)
            let buffer = queue.makeCommandBuffer()!
            _ = coordinator.observeCommandBufferLocked(buffer)
            let oldPin = SceneGraphRenderTargetResidencyPin(
                purpose: .history(effect, [.init(rawValue: "A")]), generation: 1
            )
            let oldTail = makeTail(
                device: device, token: "A", generation: 1, pin: oldPin
            )
            coordinator.committedTails = [effect: oldTail]
            coordinator.scheduledTails = coordinator.committedTails
            let newPin = SceneGraphRenderTargetResidencyPin(
                purpose: .history(effect, [.init(rawValue: "B")]), generation: 2
            )
            let newTail = makeTail(
                device: device, token: "B", generation: 2, pin: newPin
            )
            let commit = makeCommit(generation: 2, historyPin: newPin)
            let ledger = makeLedger(
                coordinator: coordinator, identity: 1,
                commandBuffer: buffer, prepared: makePrepared(device: device),
                commit: commit, candidate: [effect: newTail],
                phase: .sealed, submissionID: 1, consumed: true
            )
            coordinator.activeByID[1] = ledger
            coordinator.pendingSubmissions = [.init(
                identity: 1, ledgerIDs: [1],
                commandBufferIdentities: [ObjectIdentifier(buffer)],
                finalTails: [effect: newTail],
                successObservationsByLedger: [1: []], gpuStatus: nil,
                cancellationReason: nil, retiredHistoryPins: []
            )]
            coordinator.invalidate(reason: .surfaceStop)
            let heldBeforeCallback = oldPin.active && newPin.active
                && commit.submissionPin.active
                && coordinator.pendingSubmissions.count == 1
                && coordinator.committedTails.isEmpty
            coordinator.completeCommandBuffer(
                identity: ObjectIdentifier(buffer), status: .completed
            )
            results["invalidateDefersPinReleaseUntilTerminal"] = heldBeforeCallback
                && !oldPin.active && !newPin.active
                && !commit.submissionPin.active
                && oldPin.releaseCount == 1 && newPin.releaseCount == 1
                && coordinator.pendingSubmissions.isEmpty
                && coordinator.committedTails.isEmpty
        }

        do {
            let coordinator = makeCoordinator(device)
            let first = queue.makeCommandBuffer()!
            let second = queue.makeCommandBuffer()!
            _ = coordinator.observeCommandBufferLocked(first)
            _ = coordinator.observeCommandBufferLocked(second)
            let retired = SceneGraphRenderTargetResidencyPin(
                purpose: .history(effect, [.init(rawValue: "old")]), generation: 1
            )
            let firstCommit = makeCommit(generation: 2)
            let secondCommit = makeCommit(generation: 3)
            coordinator.activeByID[1] = makeLedger(
                coordinator: coordinator, identity: 1, commandBuffer: first,
                prepared: makePrepared(device: device), commit: firstCommit,
                phase: .sealed, submissionID: 9
            )
            coordinator.activeByID[2] = makeLedger(
                coordinator: coordinator, identity: 2, commandBuffer: second,
                prepared: makePrepared(device: device), commit: secondCommit,
                phase: .sealed, submissionID: 9
            )
            coordinator.pendingSubmissions = [.init(
                identity: 9, ledgerIDs: [1, 2],
                commandBufferIdentities: [
                    ObjectIdentifier(first), ObjectIdentifier(second)
                ],
                finalTails: [:], successObservationsByLedger: [:],
                gpuStatus: nil, cancellationReason: "aggregate-cancelled",
                retiredHistoryPins: [retired]
            )]
            coordinator.completeCommandBuffer(
                identity: ObjectIdentifier(second), status: .completed
            )
            let reverseHeld = coordinator.pendingSubmissions.count == 1
                && retired.active && firstCommit.submissionPin.active
                && secondCommit.submissionPin.active
            coordinator.completeCommandBuffer(
                identity: ObjectIdentifier(first), status: .completed
            )
            results["aggregateBarrierWaitsForAllBuffers"] = reverseHeld
                && coordinator.pendingSubmissions.isEmpty
                && !retired.active && !firstCommit.submissionPin.active
                && !secondCommit.submissionPin.active
        }

        do {
            let coordinator = makeCoordinator(device)
            let first = queue.makeCommandBuffer()!
            let pinA = SceneGraphRenderTargetResidencyPin(
                purpose: .history(effect, [.init(rawValue: "queue-A")]),
                generation: 1
            )
            let tailA = makeTail(
                device: device, token: "queue-A", generation: 1, pin: pinA
            )
            let commitA = makeCommit(generation: 1, historyPin: pinA)
            seedPendingSuccess(
                coordinator: coordinator, identity: 1,
                commandBuffer: first, tail: tailA, commit: commitA
            )
            let successor = queue.makeCommandBuffer()!
            let stateBeforeDeferredFrame = (
                coordinator.nextTransactionID,
                coordinator.executionEpoch,
                coordinator.commandBufferRecords.count
            )
            coordinator.beginFrame(
                textureSnapshot: .init(frameIndex: 2, valid: true),
                dynamicSnapshot: .init(),
                frameInputs: .init()
            )
            results["historyPendingDefersDescendantBeforeFramePrepare"] =
                coordinator.shouldDeferFrame
                && coordinator.frameRequiresDrop
                && coordinator.frameWaitsForPendingSubmission
                && coordinator.frameDeferred == 1
                && coordinator.nextTransactionID == stateBeforeDeferredFrame.0
                && coordinator.executionEpoch == stateBeforeDeferredFrame.1
                && coordinator.commandBufferRecords.count
                    == stateBeforeDeferredFrame.2
                && coordinator.commandBufferRecords[
                    ObjectIdentifier(successor)
                ] == nil
                && coordinator.activeTransactions.isEmpty
                && coordinator.preparedLedgerByLayerID.isEmpty
            _ = coordinator.endFrame()
            coordinator.completeCommandBuffer(
                identity: ObjectIdentifier(first), status: .completed
            )
        }

        do {
            let coordinator = makeCoordinator(device)
            let buffer = queue.makeCommandBuffer()!
            let commit = makeCommit(generation: 1)
            coordinator.beginFrame(
                textureSnapshot: .init(frameIndex: 20, valid: true),
                dynamicSnapshot: .init(),
                frameInputs: .init()
            )
            coordinator.activeByID[1] = makeLedger(
                coordinator: coordinator,
                identity: 1,
                commandBuffer: buffer,
                prepared: makePrepared(device: device),
                commit: commit,
                phase: .allocationCommitted,
                claimed: false
            )
            coordinator.activeTransactions = [1]
            coordinator.preparedLedgerByLayerID = [effect.layerID: 1]
            let deferred = coordinator.deferPreparedFrame()
            let report = coordinator.endFrame().last ?? ""
            results["preparedFrameDeferralCancelsWithoutFailure"] = deferred
                && !commit.submissionPin.active
                && commit.submissionPin.releaseCount == 1
                && coordinator.activeByID.isEmpty
                && coordinator.activeTransactions.isEmpty
                && coordinator.preparedLedgerByLayerID.isEmpty
                && report.contains("failures=0 deferred=1")
        }

        do {
            let coordinator = makeCoordinator(device)
            let first = queue.makeCommandBuffer()!
            let second = queue.makeCommandBuffer()!
            let commitA = makeCommit(generation: 1)
            let commitB = makeCommit(generation: 2)
            seedPendingSuccess(
                coordinator: coordinator, identity: 1,
                commandBuffer: first, tail: nil, commit: commitA
            )
            let firstLeavesCapacity = !coordinator.shouldDeferFrame
            seedPendingSuccess(
                coordinator: coordinator, identity: 2,
                commandBuffer: second, tail: nil, commit: commitB
            )
            let stateBeforeDeferredFrame = (
                coordinator.nextTransactionID,
                coordinator.executionEpoch,
                coordinator.effectGeneration,
                coordinator.resetGeneration
            )
            coordinator.beginFrame(
                textureSnapshot: .init(frameIndex: 3, valid: true),
                dynamicSnapshot: .init(),
                frameInputs: .init()
            )
            let capacityDefersWithoutAdvancing = coordinator.frameRequiresDrop
                && coordinator.frameWaitsForPendingSubmission
                && coordinator.frameDeferred == 1
                && coordinator.pendingSubmissions.count == 2
                && coordinator.activeByID.count == 2
                && stateBeforeDeferredFrame.0 == coordinator.nextTransactionID
                && stateBeforeDeferredFrame.1 == coordinator.executionEpoch
                && stateBeforeDeferredFrame.2 == coordinator.effectGeneration
                && stateBeforeDeferredFrame.3 == coordinator.resetGeneration
                && coordinator.scheduledTails.isEmpty
            _ = coordinator.endFrame()

            coordinator.completeCommandBuffer(
                identity: ObjectIdentifier(second), status: .completed
            )
            let reverseCompletionHeld = coordinator.pendingSubmissions.count == 2
                && coordinator.committedTails.isEmpty
                && commitA.submissionPin.active && commitB.submissionPin.active
            coordinator.completeCommandBuffer(
                identity: ObjectIdentifier(first), status: .completed
            )
            results["twoPendingSubmissionsUseBoundedCapacity"] = firstLeavesCapacity
                && capacityDefersWithoutAdvancing
                && Coordinator.maximumPendingSubmissions
                    == SceneResolvedMaterialInFlightCapacity.maximumSubmissions
            results["reverseGPUCompletionCommitsOnlyFromQueueHead"] =
                reverseCompletionHeld
                && coordinator.pendingSubmissions.isEmpty
                && coordinator.activeByID.isEmpty
                && coordinator.committedTails.isEmpty
                && coordinator.scheduledTails.isEmpty
                && commitA.submissionPin.releaseCount == 1
                && commitB.submissionPin.releaseCount == 1
        }

        do {
            let recorder = LogRecorder()
            let coordinator = makeCoordinator(
                device,
                logSink: { recorder.append($0) }
            )
            let first = queue.makeCommandBuffer()!
            let second = queue.makeCommandBuffer()!
            let commitA = makeCommit(generation: 1)
            let commitB = makeCommit(generation: 2)
            seedPendingSuccess(
                coordinator: coordinator, identity: 1,
                commandBuffer: first,
                tail: nil,
                commit: commitA,
                prepared: makeObservedPrepared(device: device)
            )
            seedPendingSuccess(
                coordinator: coordinator, identity: 2,
                commandBuffer: second,
                tail: nil,
                commit: commitB,
                prepared: makeObservedPrepared(device: device)
            )
            let epochBeforeFailure = coordinator.executionEpoch
            coordinator.completeCommandBuffer(
                identity: ObjectIdentifier(first), status: .failed
            )
            let independentSuccessRemains = !coordinator.shouldDeferFrame
                && coordinator.executionEpoch == epochBeforeFailure
                && coordinator.pendingSubmissions.count == 1
                && coordinator.pendingSubmissions[0].identity == 2
                && coordinator.pendingSubmissions[0].cancellationReason == nil
                && coordinator.committedTails.isEmpty
                && coordinator.scheduledTails.isEmpty
                && commitA.submissionPin.releaseCount == 1
                && commitB.submissionPin.active
            coordinator.completeCommandBuffer(
                identity: ObjectIdentifier(second), status: .completed
            )
            let failureLines = recorder.lines.filter {
                $0.contains("axis=graph-execution")
                    && $0.contains("outcome=failed")
            }
            results["historyFreeFailureDoesNotCancelIndependentSuccess"] =
                independentSuccessRemains
                && coordinator.pendingSubmissions.isEmpty
                && coordinator.activeByID.isEmpty
                && coordinator.committedTails.isEmpty
                && coordinator.scheduledTails.isEmpty
                && !coordinator.shouldDeferFrame
                && commitA.submissionPin.releaseCount == 1
                && commitB.submissionPin.releaseCount == 1
                && failureLines.contains {
                    $0.contains("failure=gpu-command-buffer-failed")
                        && $0.contains("gpuCompletion=failed")
                }
                && !failureLines.contains {
                    $0.contains("failure=ancestor-transaction-invalidated")
                }
        }

        do {
            let coordinator = makeCoordinator(device)
            let buffer = queue.makeCommandBuffer()!
            _ = coordinator.observeCommandBufferLocked(buffer)
            coordinator.frameIsActive = true
            coordinator.frame = .init(frameIndex: 4)
            let firstCommit = makeCommit(generation: 1)
            let secondCommit = makeCommit(generation: 1)
            coordinator.activeByID[1] = makeLedger(
                coordinator: coordinator, identity: 1, commandBuffer: buffer,
                prepared: makePrepared(device: device), commit: firstCommit,
                blueprint: .init(
                    states: [:], resources: [:], mappingGenerations: [:],
                    resetReasons: [:]
                ),
                candidate: [:], phase: .outputConsumed, consumed: true
            )
            coordinator.activeByID[2] = makeLedger(
                coordinator: coordinator, identity: 2, commandBuffer: buffer,
                prepared: makePrepared(device: device), commit: secondCommit,
                blueprint: .init(
                    states: [:], resources: [:], mappingGenerations: [:],
                    resetReasons: [:]
                ),
                candidate: [:], phase: .outputConsumed, consumed: true
            )
            coordinator.activeTransactions = [1, 2]
            let sealed = coordinator.sealFrame(on: buffer)
            results["sameFrameTransactionsSealAsOneSubmission"] = sealed
                && coordinator.pendingSubmissions.count == 1
                && coordinator.pendingSubmissions[0].ledgerIDs == [1, 2]
                && coordinator.pendingSubmissions[0].commandBufferIdentities
                    == [ObjectIdentifier(buffer)]
                && coordinator.activeTransactions.isEmpty
                && coordinator.activeByID.count == 2
        }

        do {
            let coordinator = makeCoordinator(device)
            let bufferA = queue.makeCommandBuffer()!
            let pinA = SceneGraphRenderTargetResidencyPin(
                purpose: .history(effect, [.init(rawValue: "A")]), generation: 1
            )
            let tailA = makeTail(
                device: device, token: "A", generation: 1, pin: pinA
            )
            let commitA = makeCommit(generation: 1, historyPin: pinA)
            seedPendingSuccess(
                coordinator: coordinator, identity: 1,
                commandBuffer: bufferA, tail: tailA, commit: commitA
            )
            coordinator.completeCommandBuffer(
                identity: ObjectIdentifier(bufferA), status: .completed
            )
            let resetAfterA = coordinator.resetGeneration

            let bufferB = queue.makeCommandBuffer()!
            let pinB = SceneGraphRenderTargetResidencyPin(
                purpose: .history(effect, [.init(rawValue: "B")]), generation: 2
            )
            let tailB = makeTail(
                device: device, token: "B", generation: 2, pin: pinB
            )
            let commitB = makeCommit(generation: 2, historyPin: pinB)
            seedPendingSuccess(
                coordinator: coordinator, identity: 2,
                commandBuffer: bufferB, tail: tailB, commit: commitB
            )
            coordinator.completeCommandBuffer(
                identity: ObjectIdentifier(bufferB), status: .failed
            )
            let baseForC = coordinator.scheduledTails[effect]
            let reusedA = baseForC?.state.logicalMapping[historyIdentity]?
                .token.rawValue == "A"
                && baseForC?.historyPin === pinA
                && coordinator.resetGeneration == resetAfterA

            let bufferC = queue.makeCommandBuffer()!
            let pinC = SceneGraphRenderTargetResidencyPin(
                purpose: .history(effect, [.init(rawValue: "A")]), generation: 1
            )
            let tailC = makeTail(
                device: device, token: "A", generation: 1, pin: pinC
            )
            let commitC = makeCommit(generation: 1, historyPin: pinC)
            seedPendingSuccess(
                coordinator: coordinator, identity: 3,
                commandBuffer: bufferC, tail: tailC, commit: commitC
            )
            coordinator.completeCommandBuffer(
                identity: ObjectIdentifier(bufferC), status: .completed
            )
            results["aSuccessBFailureCReusesAWithoutReset"] = reusedA
                && commitB.submissionPin.releaseCount == 1
                && pinB.releaseCount == 1
                && pinA.releaseCount == 1
                && !pinA.active && pinC.active
                && coordinator.committedTails[effect]?.historyPin === pinC
                && coordinator.resetGeneration == resetAfterA
        }

        let payload: [String: Any] = [
            "metalAvailable": true,
            "results": results,
        ]
        let data = try JSONSerialization.data(
            withJSONObject: payload,
            options: [.sortedKeys]
        )
        print(String(decoding: data, as: UTF8.self))
    }
}
'''


class SceneResolvedMaterialRuntimeBridgeTests(unittest.TestCase):
    def test_preview_and_inline_reporting_only_describe_typed_execution_owners(self) -> None:
        diagnostics = RENDERER_DIAGNOSTICS.read_text(encoding="utf-8")
        view = METAL_VIEW.read_text(encoding="utf-8")
        text_loader = TEXT_TEXTURE_LOADER.read_text(encoding="utf-8")

        self.assertIn("effect runtime resolved-material", diagnostics)
        self.assertIn("resolvedMaterialExecutionLayerIDs", diagnostics)
        self.assertNotIn("if executionStageCount > 1", diagnostics)
        self.assertNotIn("SceneEffectRuntimePlanner", diagnostics)
        self.assertIn("return nil", diagnostics)

        self.assertIn(
            "effectSummary: { [renderer] in renderer.effectRuntimeSummary(for: $0) }",
            view,
        )
        self.assertIn(
            "effectSummary: (SceneRenderDescriptor.Layer) -> String? = { _ in nil }",
            text_loader,
        )
        self.assertNotIn("SceneEffectRuntimePlanner.runtimeSummary", text_loader)
        self.assertNotIn("legacyEffectRuntimeExcludedLayerIDs", view + text_loader)

    def test_resource_demands_share_schema_and_never_guess_regular_assets(self) -> None:
        source = RUNTIME_CATALOG.read_text(encoding="utf-8")
        self.assertIn(
            "SceneResolvedMaterialShaderSchema.reachableSamplers",
            source,
        )
        self.assertIn("SceneResolvedMaterialTextureSlotPurpose", source)
        self.assertIn("userPropertyDemands", source)
        self.assertIn("systemProviderDemands", source)
        self.assertIn("sampler-schema-unavailable", source)
        self.assertIn("texture-purpose-unproven", source)
        self.assertIn("sampler=\\(samplerName)", source)
        self.assertIn("mode=\\(samplerMode)", source)
        self.assertIn("material=\\(materialKey)", source)
        self.assertIn("default=\\(defaultTexture)", source)
        self.assertNotIn("purpose: .premultipliedColor", source)
        self.assertIn("slot.candidates.indices.reversed()", source)
        self.assertIn("if case .graph = candidate.reference", source)
        self.assertIn("return (slot, candidates, false)", source)
        self.assertIn("guard projection.reachesDefault", source)

    def test_asset_catalog_is_eager_exact_and_fail_closed(self) -> None:
        source = ASSET_CATALOG.read_text(encoding="utf-8")
        self.assertIn("SceneTexturePathResolver", source)
        self.assertIn("resolveTextureFile(named: identity.path.value)", source)
        self.assertIn("purpose: identity.purpose", source)
        self.assertIn("requestIdentity: request", source)
        self.assertIn("loaded[identity] = .absent", source)
        self.assertIn("loaded[identity] = .unavailable", source)
        self.assertIn("private let staticStates:", source)
        self.assertIn("private let animatedDefinitions:", source)
        self.assertIn("func makeFrameProvider() -> FrameProvider", source)
        self.assertNotIn("sampleID", source)

    def test_claimed_route_is_current_and_all_post_claim_failures_close(self) -> None:
        composition = GRAPH_COMPOSITION.read_text(encoding="utf-8")
        diagnostics = RENDERER_DIAGNOSTICS.read_text(encoding="utf-8")
        frame_preflight = FRAME_PREFLIGHT.read_text(encoding="utf-8")
        compositor = COMPOSITOR.read_text(encoding="utf-8")
        passthrough_plan = LAYER_SOURCE_PASSTHROUGH_PLAN.read_text(
            encoding="utf-8"
        )
        bridge = RUNTIME_BRIDGE.read_text(encoding="utf-8")

        self.assertIn("static func executeClaimed(", composition)
        self.assertIn("static func preflight(", composition)
        self.assertIn("admittedGraphs: request.claim.admittedGraphs", composition)
        self.assertIn("pairPlan: request.claim.pairPlan", composition)
        self.assertIn("pool.preflightPersistentGraphTargets", composition)
        self.assertIn("framePlan.token == claim.token", composition)
        self.assertIn(
            "for subject in runtime.executionEvidenceSubjects(for: claim)",
            composition,
        )
        self.assertNotIn("exactEffectSubjects", bridge)
        self.assertIn("runtime.executionEvidenceFamily(for: subject.key)", composition)
        self.assertIn(
            "?? subject.family",
            composition,
        )
        self.assertIn("let dispositionCatalog =", diagnostics)
        self.assertEqual(
            diagnostics.count("SceneEffectRuntimeDispositionCatalog("),
            1,
        )
        self.assertIn("installExecutionEvidence(", diagnostics)
        self.assertIn("resolvedMaterialSubjects:", diagnostics)
        self.assertIn("runtimeDispositionSubjects", diagnostics)
        self.assertIn(
            "dispositionCatalog.resolvedMaterialExecutionEvidenceSubjects",
            diagnostics,
        )
        self.assertIn('backend: "resolved-material-graph"', composition)
        self.assertNotIn("authored-effect-graph", composition)
        self.assertIn(
            'runtime.recordClaimedFailure(\n'
            '                reasonCode: "frame-target-plan-consumption-failed"',
            composition,
        )
        self.assertNotIn("SceneEffectStageRenderer", composition)
        self.assertIn(
            "let resolvedMaterialRoute = resolvedMaterialClaim(for: request)",
            compositor,
        )
        self.assertIn(
            "guard !resolvedMaterialRoute.isRejected else { return .failed }",
            compositor,
        )
        self.assertIn(
            "request.resolvedMaterialFrameTargetPlan == nil",
            passthrough_plan,
        )
        self.assertIn("route.allowsLayerSourcePassthrough", passthrough_plan)
        self.assertIn("request.dependencyEffect == nil", passthrough_plan)
        self.assertIn("!request.requiresDependencyEffect", passthrough_plan)
        fallback_start = compositor.index(
            "if let passthroughPlan = SceneLayerSourcePassthroughPlan.make("
        )
        fallback_end = compositor.index(
            "guard !hasUnclaimedVisibleEffects else", fallback_start
        )
        source_passthrough = compositor[fallback_start:fallback_end]
        self.assertIn(
            "route: resolvedMaterialRoute",
            source_passthrough,
        )
        self.assertIn(
            "return encoded ? .layerSourcePassthrough : .failed",
            source_passthrough,
        )
        self.assertNotIn(
            ".normal(consumedDependency:",
            source_passthrough,
        )
        self.assertIn("case .notMigrated:\n            return .unclaimed", composition)
        self.assertIn("case rejected(reasonCode: String)", composition)
        self.assertIn("switch route {", frame_preflight)
        self.assertIn(
            "case let .rejected(reasonCode):\n"
            "                return .rejected(reasonCode: reasonCode)",
            frame_preflight,
        )
        self.assertNotIn(
            "guard let claim = route.execution else { continue }",
            frame_preflight,
        )
        self.assertIn(
            "resolvedMaterialRuntime.recordClaimedFailure(reasonCode: reasonCode)",
            composition,
        )
        self.assertIn("func rejectResolvedMaterialClaim(", composition)
        self.assertIn(
            "resolvedMaterialRuntime?.recordClaimedFailure(reasonCode: reasonCode)",
            composition,
        )
        self.assertGreaterEqual(
            compositor.count("rejectResolvedMaterialClaim(resolvedMaterialClaim"),
            7,
        )
        self.assertIn("case .failed:\n                    return .failed", compositor)
        self.assertIn("switch resolvedMaterialRuntime.markComposite(", composition)
        self.assertIn("case let .failed(reasonCode):", composition)
        self.assertIn('operation: "final-composite"', composition)
        self.assertIn("consumeResolvedMaterialComposite(", compositor)
        self.assertIn("return .failed", compositor)

    def test_external_dependency_is_late_ready_and_composited_once(self) -> None:
        bridge = RUNTIME_BRIDGE.read_text(encoding="utf-8")
        coordinator = SUBMISSION_COORDINATOR.read_text(encoding="utf-8")
        frame_commit = SUBMISSION_FRAME_COMMIT.read_text(encoding="utf-8")
        execution = SUBMISSION_EXECUTION.read_text(encoding="utf-8")
        composition = GRAPH_COMPOSITION.read_text(encoding="utf-8")
        compositor = COMPOSITOR.read_text(encoding="utf-8")

        self.assertIn(
            "let dependencyOwnership: SceneResolvedMaterialDependencyOwnership",
            bridge,
        )
        self.assertIn(
            "let consumesExternalPrimaryDependency: Bool",
            bridge,
        )
        self.assertIn(
            "dependencyEffect: SceneDependencyEffectInput?",
            bridge,
        )
        self.assertIn("let preparedDependencyEffect:", coordinator)
        self.assertIn("let preparedDependencyEffect:", frame_commit)

        compact_coordinator = "".join(coordinator.split())
        self.assertIn(
            "dependencyReservationMatches("
            "request.dedicatedInputs.dependencyEffect,"
            "ownership:claim.dependencyOwnership)",
            compact_coordinator,
        )

        compact_execution = "".join(execution.split())
        self.assertIn(
            "dependenciesMatch(prepared:ledger.preparedDependencyEffect,"
            "ready:dependencyEffect,ownership:claim.dependencyOwnership)",
            compact_execution,
        )
        for contract in (
            "input.consumerLayerID==binding.consumerLayerID",
            "input.providerLayerID==binding.providerLayerID",
            "input.variant==.primary",
            "input.slot==binding.slot",
            "input.blendMode==binding.blendMode",
            "prepared.frameEpoch==ready.frameEpoch",
            "prepared.texture===ready.texture",
        ):
            self.assertIn(contract, compact_execution)
        self.assertIn("case.solidLayer:", compact_execution)
        self.assertIn("binding.slot.passIndex==0", compact_execution)
        self.assertIn("binding.slot.slotIndex==3", compact_execution)
        self.assertIn("binding.blendMode==0", compact_execution)
        self.assertIn(
            "ifcase.externalPrimary=claim.dependencyOwnership",
            compact_execution,
        )
        self.assertIn(
            "consumesExternalPrimaryDependency:"
            "consumesExternalPrimaryDependency",
            compact_execution,
        )

        compact_composition = "".join(composition.split())
        self.assertIn(
            "dependencyEffect:request.dependencyEffect",
            compact_composition,
        )
        self.assertIn(
            "dependencyEffect:dependencyEffect",
            compact_composition,
        )

        compact_compositor = "".join(compositor.split())
        self.assertIn(
            "letdependencyConsumed=graphExecutionTicket?"
            ".consumesExternalPrimaryDependency==true",
            compact_compositor,
        )
        self.assertIn(
            "dependencyBlendMode:dependencyConsumed?nil:"
            "dependencyEffect?.blendMode",
            compact_compositor,
        )
        self.assertIn(
            "dependencyTexture:dependencyConsumed?nil:"
            "dependencyEffect?.texture",
            compact_compositor,
        )
        self.assertNotIn("requiresDependencyEffect", bridge)
        self.assertIn("func recordClaimedFailure(reasonCode: String)", bridge)
        self.assertNotIn("recordClaimedFailure()", bridge)

    def test_execution_evidence_is_installed_after_resources_before_frames(self) -> None:
        view = METAL_VIEW.read_text(encoding="utf-8")
        host = HOST.read_text(encoding="utf-8")
        bridge = RUNTIME_BRIDGE.read_text(encoding="utf-8")
        renderer = (SCENE_ROOT / "Rendering/SceneMetalRenderer+Diagnostics.swift").read_text(
            encoding="utf-8"
        )

        self.assertIn("renderer.runtimeReportLines()", view)
        self.assertNotIn("runtimeReportLines(effectTextures:", view)

        load = host.index("metalView.loadImageLayers(")
        register = host.index("surfaces[screenID] = Surface(", load)
        start = host.index("startFrameDriver()", register)
        self.assertLess(load, register)
        self.assertLess(register, start)
        self.assertIn("func dedicatedEffectStages(", bridge)
        self.assertIn("compactMap(\\.dedicatedExecutionPlan)", bridge)
        self.assertIn("func unifiedDedicatedEffectStages(", renderer)
        self.assertIn("func dedicatedEffectResourceStages(", renderer)
        self.assertIn("renderer.dedicatedEffectResourceStages(for: layer.id)", view)
        self.assertIn('where layer.contentKind == "text"', view)
        self.assertIn(
            "&& !renderer.dedicatedEffectResourceStages(for: layer.id).isEmpty",
            view,
        )
    def test_retired_chain_types_and_routes_are_absent(self) -> None:
        compositor = COMPOSITOR.read_text(encoding="utf-8")
        renderer = METAL_RENDERER.read_text(encoding="utf-8")
        product = compositor + renderer
        for retired in (
            "SceneAuthoredEffectExecutionChain",
            "SceneAuthoredEffectGraphPlanner",
            "authoredEffectChain",
            "chainsByLayerID",
            "renderLegacyAuthoredChain",
            "legacy-authored-chain-product-dispatch",
        ):
            self.assertNotIn(retired, product)

    def test_frame_ordering_context_reaches_reserve_and_commit(self) -> None:
        frame_preflight = FRAME_PREFLIGHT.read_text(encoding="utf-8")
        composition = GRAPH_COMPOSITION.read_text(encoding="utf-8")
        target_preflight = TARGET_PREFLIGHT.read_text(encoding="utf-8")
        allocator = TARGET_ALLOCATOR.read_text(encoding="utf-8")
        cache = TARGET_CACHE.read_text(encoding="utf-8")
        batch = TARGET_BATCH.read_text(encoding="utf-8")
        coordinator = SUBMISSION_COORDINATOR.read_text(encoding="utf-8")
        execution = SUBMISSION_EXECUTION.read_text(encoding="utf-8")

        self.assertIn("commandBuffer: commandBuffer", frame_preflight)
        self.assertIn("commandBuffer: MTLCommandBuffer", frame_preflight)
        self.assertIn("commandBuffer: MTLCommandBuffer? = nil", composition)
        self.assertIn("orderingContext: orderingContext", composition)
        self.assertIn("let orderingContext", composition)
        self.assertIn("orderingContext: contexts.first", target_preflight)
        self.assertIn("orderingContext: orderingContext", allocator)
        self.assertIn("reservation.orderingContext", batch)
        self.assertIn("submissionPins", cache + batch)
        self.assertNotIn("submissionPins = Set<UUID>()", allocator)
        commit = coordinator.index("pool.commitAndPinPersistentGraphTargets(")
        self.assertIn(
            "commandBuffer: commandBuffer",
            coordinator[commit:],
        )
        self.assertIn("executor.encodeResult(", execution)

    def test_normal_invalidation_is_not_a_graph_failure_diagnostic(self) -> None:
        lifecycle = SUBMISSION_LIFECYCLE.read_text(encoding="utf-8")
        frame_commit = SUBMISSION_FRAME_COMMIT.read_text(encoding="utf-8")
        completion = SUBMISSION_COMPLETION.read_text(encoding="utf-8")

        self.assertIn("case .surfaceStop, .sceneSwitch:", lifecycle)
        self.assertIn(
            'emission.diagnostics.append("runtime-invalidated-\\(reason.rawValue)")',
            lifecycle,
        )
        self.assertIn("failActiveFrameLocked(reason:", lifecycle)
        self.assertIn("case cancelled", completion)
        self.assertIn(
            "case SceneGraphExecutionResetReason.surfaceStop.rawValue,",
            completion,
        )
        self.assertIn(
            "SceneGraphExecutionResetReason.sceneSwitch.rawValue:",
            completion,
        )
        self.assertNotIn("SceneGraphExecutionResetReason(rawValue:", completion)
        self.assertIn("emission.diagnostics.append(reason)", frame_commit)
        self.assertIn("emission.diagnostics.append(headReason)", completion)

    def test_observer_precedes_encoding_and_frame_uses_one_buffer(self) -> None:
        coordinator = SUBMISSION_COORDINATOR.read_text(encoding="utf-8")
        execution = SUBMISSION_EXECUTION.read_text(encoding="utf-8")
        frame_commit = SUBMISSION_FRAME_COMMIT.read_text(encoding="utf-8")
        completion = SUBMISSION_COMPLETION.read_text(encoding="utf-8")

        observer = coordinator.index("observeCommandBufferLocked(commandBuffer)")
        prepared = coordinator.index("guard case let .success(prepared)", observer)
        allocation_commit = coordinator.index(
            "pool.commitAndPinPersistentGraphTargets(", prepared
        )
        ledger = coordinator.index("activeByID[identity] = .init(", allocation_commit)
        self.assertLess(observer, prepared)
        self.assertLess(prepared, allocation_commit)
        self.assertLess(allocation_commit, ledger)
        self.assertIn("commandBuffer: commandBuffer", coordinator)
        command_buffer_guard = execution.index(
            "ledger.commandBuffer === commandBuffer"
        )
        encode = execution.index("executor.encodeResult(")
        self.assertLess(command_buffer_guard, encode)
        self.assertIn("ledger.phase == .allocationCommitted", execution)
        self.assertIn('"prepared-frame-consumption-rejected"', execution)
        self.assertEqual(frame_commit.count("addCompletedHandler"), 1)
        self.assertIn(
            "guard commandBuffer.status == .notEnqueued",
            frame_commit,
        )
        seal = frame_commit.index("func sealFrame(on commandBuffer")
        self.assertNotIn("addCompletedHandler", frame_commit[seal:])
        self.assertIn("func completeCommandBuffer(", completion)
        self.assertIn("commandBufferIdentities", completion)

    def test_production_frame_is_sealed_before_command_buffer_commit(self) -> None:
        compositor = (SCENE_ROOT / "Rendering/SceneResolvedMaterialGraphComposition.swift").read_text(
            encoding="utf-8"
        )
        renderer = METAL_RENDERER.read_text(encoding="utf-8")
        frame_end = renderer.index(
            "imageCompositor.endResolvedMaterialFrame(on: commandBuffer)"
        )
        abandon_unsealed = renderer.index("return", frame_end)
        command_commit = renderer.index("commandBuffer.commit()", frame_end)
        self.assertIn(
            "return resolvedMaterialRuntime?.sealFrame(on: commandBuffer) ?? true",
            compositor,
        )
        self.assertLess(frame_end, command_commit)
        self.assertLess(abandon_unsealed, command_commit)
        self.assertIn(
            "guard imageCompositor.endResolvedMaterialFrame(on: commandBuffer) else {\n"
            "            return\n"
            "        }",
            renderer,
        )

    def test_surface_lifecycle_releases_runtime_before_pool_reset(self) -> None:
        bridge = RUNTIME_BRIDGE.read_text(encoding="utf-8")
        view = METAL_VIEW_FRAME_CONTEXT.read_text(encoding="utf-8")
        host = HOST.read_text(encoding="utf-8")
        runner = DEBUG_RUNNER.read_text(encoding="utf-8")
        scene_switch_runner = DEBUG_SCENE_SWITCH_RUNNER.read_text(
            encoding="utf-8"
        )
        surface_stop_runner = DEBUG_SURFACE_STOP_RELAUNCH_RUNNER.read_text(
            encoding="utf-8"
        )
        pause_resume_runner = DEBUG_PAUSE_RESUME_RUNNER.read_text(
            encoding="utf-8"
        )
        lifecycle_runner = (
            runner
            + scene_switch_runner
            + surface_stop_runner
            + pause_resume_runner
        )
        host_driver = HOST_FRAME_DRIVER.read_text(encoding="utf-8")

        self.assertIn("submissions.invalidate(reason: reason)", bridge)
        invalidate = view.index(
            "invalidateResolvedMaterialRuntime(reason: reason)"
        )
        pool_reset = view.index("offscreenTexturePool.reset()", invalidate)
        self.assertLess(invalidate, pool_reset)
        self.assertIn(
            "teardownSurfaces(clearContext: true, reason: .surfaceStop)",
            host,
        )
        self.assertIn(
            "teardownSurfaces(clearContext: true, reason: .sceneSwitch)",
            host,
        )
        self.assertIn(
            "teardownReason: SceneGraphExecutionResetReason = .surfaceStop",
            host,
        )
        self.assertIn(
            "surface.metalView.invalidateResolvedMaterialRuntime(reason: reason)",
            host_driver,
        )
        self.assertNotIn("clearContext\n            ? .sceneSwitch", host_driver)
        self.assertIn("debugInvalidateResolvedMaterialRuntimes(", host)
        self.assertIn("invalidateResolvedMaterialRuntime(reason: reason)", host)
        self.assertIn(
            '"MWX_SCENE_DEBUG_EXECUTOR_INVALIDATE_AFTER"',
            runner,
        )
        self.assertIn("reason: .executorInvalidation", runner)
        self.assertIn('reason: "executor-invalidation-after"', runner)
        self.assertIn(
            '"MWX_SCENE_DEBUG_SCENE_SWITCH_AFTER"', scene_switch_runner
        )
        self.assertIn(
            '"MWX_SCENE_DEBUG_SCENE_SWITCH_ROOT"', scene_switch_runner
        )
        self.assertIn("multiple-runtime-lifecycle-faults", runner)
        self.assertIn(
            "SceneDesktopWallpaperHost.shared.launch(", scene_switch_runner
        )
        self.assertIn(
            "isIsolatedSampleRoot(candidate)", scene_switch_runner
        )
        self.assertIn(
            'phase=scene-switch state=triggered accepted=true',
            scene_switch_runner,
        )
        self.assertIn("model.renderDescriptor.layers.map(\\.id)", scene_switch_runner)
        self.assertIn('reason: "scene-switch-after"', scene_switch_runner)
        self.assertIn(
            '"MWX_SCENE_DEBUG_SURFACE_STOP_RELAUNCH_AFTER"',
            lifecycle_runner,
        )
        self.assertIn(
            "SceneDesktopWallpaperHost.shared.stop()",
            surface_stop_runner,
        )
        self.assertIn(
            'phase=surface-stop-relaunch state=stopped',
            surface_stop_runner,
        )
        self.assertIn(
            'phase=surface-stop-relaunch state=relaunched accepted=true',
            surface_stop_runner,
        )
        self.assertIn(
            'reason: "surface-stop-relaunch-after"',
            surface_stop_runner,
        )
        self.assertIn(
            '"MWX_SCENE_DEBUG_PAUSE_RESUME_AFTER"',
            lifecycle_runner,
        )
        self.assertIn(
            "WallpaperEngine.shared.pauseAllPlayers()",
            pause_resume_runner,
        )
        self.assertIn(
            "WallpaperEngine.shared.resumeAllPlayers()",
            pause_resume_runner,
        )
        self.assertIn('state=paused accepted=%@', pause_resume_runner)
        self.assertIn('state=resumed accepted=%@', pause_resume_runner)
        self.assertIn(
            'reason: "pause-resume-after"',
            pause_resume_runner,
        )

    @unittest.skipUnless(shutil.which("swiftc"), "swiftc is required")
    def test_current_submission_coordinator_lifecycle_behaviors(self) -> None:
        with tempfile.TemporaryDirectory(
            prefix="mwx-r4-submission-coordinator-"
        ) as directory:
            root = Path(directory)
            harness = root / "Harness.swift"
            binary = root / "submission-coordinator"
            harness.write_text(SUBMISSION_COORDINATOR_FIXTURE, encoding="utf-8")
            compilation = subprocess.run(
                [
                    "xcrun",
                    "--sdk",
                    "macosx",
                    "swiftc",
                    "-parse-as-library",
                    *(str(source) for source in SUBMISSION_SWIFT_SOURCES),
                    str(harness),
                    "-framework",
                    "Metal",
                    "-module-cache-path",
                    str(root / "module-cache"),
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
            expected = {
                "externalDependencyExactReadyMatchIssuesTicket",
                "externalDependencyMissingReadyRejected",
                "externalDependencyWrongProviderRejected",
                "externalDependencyWrongSlotRejected",
                "externalDependencyWrongBlendRejected",
                "externalDependencyWrongEpochRejected",
                "externalDependencyWrongObjectRejected",
                "solidDependencyExactReadyMatchIssuesTicket",
                "solidDependencyMissingReadyRejected",
                "solidDependencySecondaryRejected",
                "solidDependencyWrongEffectRejected",
                "solidDependencyWrongPassRejected",
                "normalInvalidateHasNoGraphDiagnostic",
                "stableHistoryAllocationClassifiesCopyOnWrite",
                "descriptorChangeClassifiesAllocationReprepare",
                "historyFreeFreshIdentityClassifiesAllocationRebind",
                "unknownHistoryTransitionRejected",
                "deviceLossInvalidateHasGraphDiagnostic",
                "executorInvalidateHasGraphDiagnostic",
                "pendingSurfaceStopCancelsSilently",
                "pendingSceneSwitchCancelsSilently",
                "allocationReprepareRemainsFailure",
                "effectReparseRemainsFailure",
                "deviceLossRemainsFailure",
                "executorInvalidationRemainsFailure",
                "unknownCancellationRemainsFailure",
                "surfaceStopGPUFailureRemainsFailure",
                "invalidSurfaceStopLedgerRemainsFailure",
                "productionObservationBuilderSuccess",
                "productionObservationBuilderFailure",
                "claimUsesCentralCapabilityAdmission",
                "claimCarriesGraphIdentityOnly",
                "uninstalledDispositionEvidenceIsNotInvoked",
                "bridgeProjectsOnlyInstalledDispositionEvidence",
                "executionEvidenceOverridesFallbackFamily",
                "missingExecutionEvidenceKeepsFallbackIsolated",
                "visualFailurePassthroughKeepsFailedTelemetry",
                "dynamicRendererPassthroughKeepsFailedTelemetry",
                "malformedExecutionEvidenceDropsOnlyInvalidKey",
                "emptyExecutionFamilyDropsOnlyInvalidKey",
                "invalidCapabilityTokenRejectsWithoutLegacyFallback",
                "typedTargetDescriptorFallbackRemainsLayerLocal",
                "utilitySubtreeCoverageFallbackRemainsLayerLocal",
                "preflightFailureReasonReachesCoordinatorEvidence",
                "claimWaitsForAtomicFramePreparation",
                "typedHistoryDiscardReachesPoolExactly",
                "forgedHistoryDiscardRejectedBeforePoolCommit",
                "secondPreparationFailureRollsBackWholeFrame",
                "externalDependencyCaptureFailureRejectsOnlyItsSubgraph",
                "cascadingDependencyCaptureFailureRejectsTransitiveSubgraph",
                "repeatTerminalPublicationRejectsBeforeLedgerAndPreservesPreviousCurrent",
                "preparedProviderOutputKeepsNamedReservationWithoutCompositorOwnership",
                "twoCandidatesPublishConsumeAndCommitAtomically",
                "postClaimFailureDropsWholeFrame",
                "foreignBufferRejectedBeforePrepare",
                "ticketIsSingleConsumption",
                "invalidateDefersPinReleaseUntilTerminal",
                "aggregateBarrierWaitsForAllBuffers",
                "historyPendingDefersDescendantBeforeFramePrepare",
                "preparedFrameDeferralCancelsWithoutFailure",
                "twoPendingSubmissionsUseBoundedCapacity",
                "reverseGPUCompletionCommitsOnlyFromQueueHead",
                "historyFreeFailureDoesNotCancelIndependentSuccess",
                "sameFrameTransactionsSealAsOneSubmission",
                "aSuccessBFailureCReusesAWithoutReset",
                "freshAndInvalidatedInitialStatesKeepDistinctReasons",
            }
            self.assertEqual(set(result["results"]), expected)
            self.assertTrue(all(result["results"].values()), result)

    @unittest.skipUnless(shutil.which("swiftc"), "swiftc is required")
    def test_texture_vfs_preserves_package_loose_stock_precedence(self) -> None:
        with tempfile.TemporaryDirectory(prefix="mwx-r3-vfs-") as directory:
            root = Path(directory)
            package, loose, stock = root / "package", root / "loose", root / "stock"
            for path in (package, loose, stock):
                path.mkdir()
            for base in (package, loose, stock):
                (base / "materials").mkdir()
                (base / "materials/shared.png").write_bytes(b"x")
            (package / "materials/bare.png").write_bytes(b"x")
            (stock / "stock-only.png").write_bytes(b"x")
            harness = root / "Harness.swift"
            binary = root / "vfs"
            harness.write_text(VFS_SUPPORT, encoding="utf-8")
            compilation = subprocess.run(
                [
                    "xcrun", "--sdk", "macosx", "swiftc",
                    str(SCENE_ROOT / "Resources/SceneResourceIndex.swift"),
                    str(SCENE_ROOT / "Resources/SceneResourceView.swift"),
                    str(SCENE_ROOT / "Resources/SceneTexturePathResolver.swift"),
                    str(harness), "-module-cache-path", str(root / "module-cache"),
                    "-o", str(binary),
                ],
                capture_output=True,
                text=True,
            )
            self.assertEqual(compilation.returncode, 0, compilation.stderr)
            completed = subprocess.run(
                [str(binary), str(package), str(loose), str(stock)],
                check=True,
                capture_output=True,
                text=True,
            )
            result = json.loads(completed.stdout)
            self.assertTrue(Path(result["shared"]).resolve().is_relative_to(package.resolve()))
            self.assertTrue(Path(result["bare"]).resolve().is_relative_to(package.resolve()))
            self.assertTrue(Path(result["stock"]).resolve().is_relative_to(stock.resolve()))
            self.assertEqual(result["missing"], "")


if __name__ == "__main__":
    unittest.main()
