import CoreGraphics
import Foundation
import Metal
import simd

// Harness stubs mirror the exact member surface the compiled product files
// touch. Product files listed in STATIC_SOURCE_DRAW_ONLY_SOURCES stay verbatim.

nonisolated enum SceneTextureLoadPurpose: Hashable, Sendable {
    case premultipliedColor, straightAlbedo, preservedChannels, mask, noise
    case flow, phase, normal, depth, lookupTable
}

enum SceneFrameTextureIdentity: Equatable { case layerSource(Int) }

nonisolated struct SceneTextureProviderPublication {
    let requestIdentity: SceneFrameTextureIdentity
    let candidate: SceneTextureCandidate
    let contentGeneration: UInt64
    var isComplete: Bool

    var texture: MTLTexture { candidate.texture }
}

struct SceneRenderDescriptor {
    struct Layer {
        let id: Int
        let contentKind: String
        var effects: [EffectDescriptor] = []
        var colorBlendMode: Int? = nil
        var clampUVs: Bool = false
        var noInterpolation: Bool = false
        var brightness: Float? = nil
    }

    struct EffectDescriptor {
        let id: String
        let file: String
        var visible: Bool? = nil
        var passes: [PassDescriptor] = []
    }

    struct PassDescriptor {
        let id: String
        let passIndex: Int
        var texturePaths: [String] = []
        var textureSlots: [String?] = []
        var userTextureInputs: [String] = []
        var combos: [String: Int] = [:]
    }
}

struct SceneNamedTextureReference {
    enum Variant { case primary }
    let providerLayerID: Int
    let variant: Variant
}

struct SceneEffectPassSlot {
    let slotIndex: Int
}

struct SceneFrameTextureResource {
    static func reservedNamedLayerTarget(
        reference: SceneNamedTextureReference,
        frameEpoch: UInt64,
        texture: MTLTexture,
        content: SceneTextureContent,
        consumerLayerID: Int
    ) -> SceneFrameTextureResource? { nil }
}

struct SceneGraphRenderTargetResidencyPin {}
class SceneOffscreenTexturePool {
    struct CompositionTarget { let texture: MTLTexture; let pin: SceneGraphRenderTargetResidencyPin? = nil }
    func compositionTarget(width: Int, height: Int, commandBuffer: MTLCommandBuffer?) -> CompositionTarget? { nil }
}

struct SceneLayerEffectSourceExtent { let pixelSize: CGSize }

struct SceneDynamicSnapshot {
    static func empty(frameIndex: Int) -> SceneDynamicSnapshot { .init() }
}

enum SceneAudioSpectrumSnapshot { case silent }

struct SceneAuthoredShaderFrameInputs {}

struct SceneGeometryProduct {}

enum SceneGraphExecutionResetReason { case deviceLoss }

enum SceneBlendModeShaderSource { static let maximumMode = 32 }

enum SceneLayerVisibility {
    static func hasCurrentSourceDisplayAuthority(
        for layer: SceneRenderDescriptor.Layer,
        snapshot: SceneDynamicSnapshot?
    ) -> Bool { true }
}

enum SceneLayerColorBlendRenderer {
    static func supports(_ blendMode: Int) -> Bool {
        (0 ... SceneBlendModeShaderSource.maximumMode).contains(blendMode)
    }
}

// Fog evaluation belongs to the real GPU gate; this routing fixture only
// needs the typed request/default argument accepted by production callers.
struct SceneImageDistanceFogUniforms {}

struct SceneLayerFragmentUniforms {
    let time: Float
    var alpha: Float
    let dependencyBlendMode: UInt32
    let usesDependencyBlend: UInt32
    let cursorUV: SIMD2<Float>
    let sourceSampling: SIMD2<UInt32>
    let tint: SIMD4<Float>
    let textureFrame0: SIMD4<Float>
    let textureFrame1: SIMD4<Float>
}

struct SceneBaseMaterialLitCapturePayload {
    let requiresReflection = false
    let hasDirectLighting = true
    func resolvingEnvironment(for target: MTLTexture, commandBuffer: MTLCommandBuffer) -> Self? { self }
}
final class SceneImageLayerPipeline { static func bindQuad(encoder: MTLRenderCommandEncoder) {} }

final class SceneLayerColorBlendPipeline {
    private(set) static weak var lastCreated: SceneLayerColorBlendPipeline?
    let device: MTLDevice
    let framebufferSnapshot: SceneFramebufferSnapshot
    init(device: MTLDevice, state: Int) {
        self.device = device
        framebufferSnapshot = SceneFramebufferSnapshot(device: device, label: "draw-only fixture")
        Self.lastCreated = self
    }
    var renderTargetResidentByteCost: Int { framebufferSnapshot.residentByteCost }
}

final class ScenePipelineSlot<Value> {
    private let factory: () -> Value?
    private var resolved: Value?
    private var isResolved = false
    init(factory: @escaping () -> Value?) { self.factory = factory }
    func resolve() -> Value? {
        guard !isResolved else { return resolved }
        resolved = factory()
        isResolved = true
        return resolved
    }
    func resolvedValue() -> Value? { isResolved ? resolved : nil }
}

enum SceneGraphOutputPublicationResult: Equatable {
    case published
    case unavailable(reasonCode: String)
    case invalid(reasonCode: String)
}

final class SceneImageEffectPipelineRepository {
    let device: MTLDevice
    init(device: MTLDevice) { self.device = device }
    func layerColorBlendState() -> Int? { 0 }
}

final class SceneMainPassEncoder {
    func retainCompositionPin(_ pin: SceneGraphRenderTargetResidencyPin?) {}
    let device: MTLDevice
    init(device: MTLDevice) { self.device = device }
    func encoder() -> MTLRenderCommandEncoder? { nil }
    func encodeOffscreen<Result>(
        _ operation: (MTLCommandBuffer) -> Result
    ) -> Result {
        operation(device.makeCommandQueue()!.makeCommandBuffer()!)
    }
    func withReadableTarget<Result>(
        _ operation: (MTLTexture, MTLCommandBuffer) -> Result
    ) -> Result? { nil }
}

enum SceneImageLayerMainPassRenderer {
    struct RecordedDraw {
        let texture: MTLTexture
        let dependencyTexture: MTLTexture?
        let layerID: Int
        let uniforms: SceneLayerFragmentUniforms
    }

    static var recorded: [RecordedDraw] = []

    static func draw(
        texture: MTLTexture,
        mvp: simd_float4x4,
        uniforms: SceneLayerFragmentUniforms,
        dependencyTexture: MTLTexture?,
        layer: SceneRenderDescriptor.Layer,
        pipeline: SceneImageLayerPipeline,
        colorBlendPipeline: SceneLayerColorBlendPipeline?,
        distanceFog: SceneImageDistanceFogUniforms = .init(),
        geometryProduct: SceneGeometryProduct? = nil,
        mainPass: SceneMainPassEncoder
    ) -> Bool {
        recorded.append(.init(
            texture: texture,
            dependencyTexture: dependencyTexture,
            layerID: layer.id,
            uniforms: uniforms
        ))
        return true
    }
}

enum SceneOffscreenEffectRenderer {
    static var captureSucceeds = false
    static var capturedUniforms: SceneLayerFragmentUniforms?
    static func captureSource(
        sourceTexture: MTLTexture,
        target: MTLTexture,
        sourceUniforms: SceneLayerFragmentUniforms,
        pipeline: SceneImageLayerPipeline,
        commandBuffer: MTLCommandBuffer,
        sourceLighting: SceneBaseMaterialLitCapturePayload? = nil
    ) -> Bool {
        capturedUniforms = sourceUniforms
        return captureSucceeds
    }
}

final class FixtureCompositionPool: SceneOffscreenTexturePool {
    let target: MTLTexture
    init(target: MTLTexture) { self.target = target }
    override func compositionTarget(width: Int, height: Int, commandBuffer: MTLCommandBuffer?) -> CompositionTarget? {
        .init(texture: target)
    }
}

enum SceneEffectExecutionOrigin { case image, solid, text, quad }

enum SceneEffectRouteOperationOutcome: Equatable {
    case encoded
    case failed(reasonCode: String)
}

enum SceneEffectCPUInvocationOutcome {
    case encodedOutput
    case failed(reasonCode: String)
}

struct SceneEffectExecutionIdentity {
    let layerID: Int
    let effectIndex: Int
    let descriptorID: String
}

final class SceneEffectExecutionFrameTrace {
    struct RouteRecord: Equatable {
        let layerID: Int
        let origin: SceneEffectExecutionOrigin
        let operation: String
        let outcome: SceneEffectRouteOperationOutcome
    }

    private(set) var records: [RouteRecord] = []

    @discardableResult
    func recordRouteOperation(
        layerID: Int,
        origin: SceneEffectExecutionOrigin,
        operation: String,
        outcome: SceneEffectRouteOperationOutcome
    ) -> Bool {
        records.append(.init(
            layerID: layerID,
            origin: origin,
            operation: operation,
            outcome: outcome
        ))
        return true
    }

    @discardableResult
    func recordExact(
        identity: SceneEffectExecutionIdentity,
        origin: SceneEffectExecutionOrigin,
        family: String,
        backend: String,
        outcome: SceneEffectCPUInvocationOutcome
    ) -> Bool { true }
}

enum SceneResolvedMaterialExecutionCapabilityCatalog {
    struct Token: Equatable {}
}

struct ScenePersistentGraphTargetFramePlan {
    struct GraphPlanKey { let layerID: Int }
    struct GraphPlan { let key: GraphPlanKey }
    let graphPlan: GraphPlan
}

enum ScenePersistentGraphTargetPlanningFailure {
    static func isLocalFallbackReasonCode(_ reasonCode: String) -> Bool { false }
}

struct SceneSystemProviderTextureIdentity: Hashable {}

enum SceneFrameTextureRegistry {
    enum ProviderStatus: Hashable { case ready }
}

struct SceneFrameTextureRegistrySnapshot {}

final class SceneFramePerformanceTelemetry {}

enum SceneTextureProviderState {
    case ready(SceneTextureProviderPublication), absent, pending, unavailable
}

final class SceneResolvedMaterialRuntimeBridge {
    struct FrameInputs {
        enum DependencyUnavailability: String {
            case providerSourceUnavailable = "external-primary-provider-source-unavailable"
        }
    }
    struct SceneBackgroundRequirement {}
    enum SourceRoute: Equatable { case transparentDirectDraw }
    struct FrameInputContract {
        enum EmittedOutputGeometrySource { case authoredCanvasDirectDraw }
        let emittedOutputGeometrySource: EmittedOutputGeometrySource
    }
    struct Token: Equatable {}
    enum DependencyOwnership {
        struct Aggregate { let hasStrictBindingVector: Bool; let bindings: [Int] }
        case unowned
        case externalAggregate(Aggregate)
    }
    struct ClaimedExecution {
        let token: SceneResolvedMaterialExecutionCapabilityCatalog.Token
        let layerID: Int
        let dependencyOwnership: DependencyOwnership
        let sceneBackgroundRequirement: SceneBackgroundRequirement?
        let sourceRoute: SourceRoute
        let frameInputContract: FrameInputContract
    }
    enum ClaimOutcome {
        case notMigrated
        case rejected(reasonCode: String)
        case claimed(ClaimedExecution)
    }
    struct ExecutionTicket {
        let finalContent: SceneTextureContent
        let consumesExternalPrimaryDependency: Bool
        var hasTerminalMaterialReplay: Bool { false }
    }
    enum ExecutionResult {
        case encoded(texture: MTLTexture, ticket: ExecutionTicket)
        case failed(reasonCode: String)
    }
    enum MarkOutcome { case consumed; case failed(reasonCode: String) }
    struct FramePreparationRequest {}
    enum FramePreparationResult { case ready; case rejected(reasonCode: String) }
    struct ExecutionEvidenceSubject {
        struct Key {
            let layerID: Int
            let effectIndex: Int
            let descriptorID: String
        }
        let key: Key
        let family: String
    }
    enum ExecutionEvidenceOutcome {
        case encodedOutput
        case failed(reasonCode: String)
    }

    var shouldDeferFrame: Bool { false }
    enum TerminalMaterialReplayOutcome {
        case notApplicable
        case consumed
        case failed(reasonCode: String)
    }
    func drawTerminalMaterialReplay(
        _ ticket: ExecutionTicket,
        mainPass: SceneMainPassEncoder
    ) -> TerminalMaterialReplayOutcome { .notApplicable }
    func invalidate(reason: SceneGraphExecutionResetReason) {}
    func claim(layerID: Int) -> ClaimOutcome { .notMigrated }
    func preflightClaim(layerID: Int) -> ClaimOutcome { .notMigrated }
    func recordClaimedFailure(reasonCode: String) {}
    func executeClaimed(
        claim: ClaimedExecution,
        dependencyEffects: [SceneDependencyEffectInput],
        sceneBackgroundTexture: MTLTexture?,
        commandBuffer: MTLCommandBuffer
    ) -> ExecutionResult { .failed(reasonCode: "harness-inert") }
    func executionEvidenceSubjects(
        for claim: ClaimedExecution
    ) -> [ExecutionEvidenceSubject] { [] }
    func executionEvidenceOutcome(
        for subject: ExecutionEvidenceSubject,
        claim: ClaimedExecution,
        ticket: ExecutionTicket
    ) -> ExecutionEvidenceOutcome { .encodedOutput }
    func executionEvidenceFamily(
        for key: ExecutionEvidenceSubject.Key
    ) -> String? { nil }
    func markComposite(
        _ ticket: ExecutionTicket,
        texture: MTLTexture,
        consumed: Bool
    ) -> MarkOutcome { .consumed }
    func markNamedPublication(
        _ ticket: ExecutionTicket,
        texture: MTLTexture,
        published: Bool
    ) -> MarkOutcome { .consumed }
    func discardNamedPublicationOutputLocally(
        _ ticket: ExecutionTicket,
        texture: MTLTexture,
        reasonCode: String
    ) -> MarkOutcome { .consumed }
    func rejectPreparedExternalDependencyLocally(
        layerID: Int,
        reasonCode: String
    ) -> Bool { false }
    func prepareFrame(
        _ requests: [FramePreparationRequest],
        pool: SceneOffscreenTexturePool?,
        commandBuffer: MTLCommandBuffer,
        resourceBundle: SceneResolvedMaterialFrameResourceBundle? = nil,
        performanceTelemetry: SceneFramePerformanceTelemetry?
    ) -> FramePreparationResult {
        precondition(resourceBundle == nil, "resource phase is outside this draw-only fixture")
        return .ready
    }
    func preparedOutputTexturesByLayerID() -> [Int: MTLTexture]? { nil }
    func preparedExternalDependencyBypassReason(layerID: Int) -> String? { nil }
    func installFrameLocalFallbacks(_ fallbacks: [Int: String]) -> Bool {
        fallbacks.isEmpty
    }
    func deferPreparedFrame() -> Bool { true }
    func resolvedAssetStates(
        sceneTime: TimeInterval
    ) -> [SceneAssetTextureIdentity: SceneTextureProviderState] { [:] }
    func commitResolvedAssetFrame() {}
    func discardResolvedAssetFrame() {}
    func systemProviderBlocks(
        for states: [SceneSystemProviderTextureIdentity: SceneTextureProviderState]
    ) -> [SceneSystemProviderTextureIdentity: SceneFrameTextureRegistry.ProviderStatus] { [:] }
    func beginFrame(
        textureSnapshot: SceneFrameTextureRegistrySnapshot,
        dynamicSnapshot: SceneDynamicSnapshot,
        frameInputs: SceneAuthoredShaderFrameInputs
    ) {}
    func cancelUnsubmittedFrame(on commandBuffer: MTLCommandBuffer) {}
    func sealFrame(on commandBuffer: MTLCommandBuffer) -> Bool { true }
    func endFrame() {}
}

struct StaticSourceDrawOnlyReport: Codable {
    var snapshotCapacityCommitsAndRollsBack = false
    var litCaptureFailureKeepsAuthoredUniforms = false
    var litCaptureRecoveryUsesCapturedTexture = false
    var metalAvailable = false
    var degradedPlanBuilt = false
    var degradedPlanDrawsRequestTexture = false
    var degradedPlanKeepsStaticFileAtom = false
    var degradedPlanCarriesLayerSourceIdentity = false
    var degradedPlanKeepsResolvedSample = false
    var degradedPlanContentMirrorsRequestCandidate = false
    var degradedPlanGeometryDrawable = false
    var graphPublicationActiveBuildsNormalPlan = false
    var flagOffKeepsGraphRoleRejection = false
    var flagOnBlendGuardUnaffected = false
    var flagOnTextureFrameGuardUnaffected = false
    var compositorDegradedEncoded = false
    var compositorDegradedDrewRequestBaseTexture = false
    var compositorDegradedTraceOperation = false
    var compositorFlagOffFails = false
    var compositorFlagOffTraceReason = false
}

@main
struct StaticSourceDrawOnlyHarness {
    static func makeTexture(_ device: MTLDevice) -> MTLTexture {
        let descriptor = MTLTextureDescriptor()
        descriptor.textureType = .type2D
        descriptor.pixelFormat = .rgba8Unorm
        descriptor.width = 4
        descriptor.height = 4
        descriptor.usage = [.shaderRead]
        return device.makeTexture(descriptor: descriptor)!
    }

    static func main() {
        var report = StaticSourceDrawOnlyReport()
        guard let device = MTLCreateSystemDefaultDevice() else {
            emit(report)
            return
        }
        report.metalAvailable = true
        let texture = makeTexture(device)
        let candidate = SceneTextureCandidate(
            texture: texture,
            identity: .file(path: "textures/base.png"),
            generation: .file(
                byteCount: 64,
                modifiedAtBits: 1,
                revision: .init(
                    fileSystemID: 1,
                    fileID: 2,
                    statusChangedAtSeconds: 0,
                    statusChangedAtNanoseconds: 0
                )
            ),
            purpose: .premultipliedColor,
            content: .color(.resolved(.premultipliedAlpha)),
            physicalSize: CGSize(width: 4, height: 4),
            mappedSize: CGSize(width: 4, height: 4),
            uvTransform: .identity,
            sampling: .linearClamp
        )
        let publication = SceneTextureProviderPublication(
            requestIdentity: .layerSource(875),
            candidate: candidate,
            contentGeneration: 7,
            isComplete: true
        )
        let visibleEffects = [SceneRenderDescriptor.EffectDescriptor(
            id: "875#effect#0",
            file: "effects/blur/effect.json",
            visible: true,
            passes: []
        )]

        func blockedRequest(
            blendMode: Int?,
            textureFrame: SceneTextureUVTransform = .identity
        ) -> SceneImageLayerDrawRequest {
            SceneImageLayerDrawRequest(
                layer: SceneRenderDescriptor.Layer(
                    id: 875,
                    contentKind: "image",
                    effects: visibleEffects,
                    colorBlendMode: blendMode
                ),
                texture: texture,
                baseTextureCandidate: candidate,
                masks: .empty,
                textureFrame: textureFrame,
                mvp: matrix_identity_float4x4,
                uniforms: SceneImageLayerUniformValues(
                    time: 0,
                    alpha: 1,
                    cursorUV: .zero
                ),
                offscreenTexturePool: nil,
                effectSourceExtent: nil,
                requiresSourceCopy: false,
                finalCompositeAlpha: nil,
                blocksStaticLayerSourcePassthrough: true
            )
        }

        // 1. Blocked static source + flag on + resolvable texture -> degraded
        //    draw-only plan that never claims publication identity.
        let request = blockedRequest(blendMode: 0)
        let flagOnResult = SceneLayerSourcePassthroughPlan.resolve(
            request: request,
            publication: publication,
            route: .unclaimed,
            allowsStaticSourceGraphPublication: false,
            allowsUnpublishedStaticSourceDraw: true
        )
        if case let .success(plan) = flagOnResult {
            report.degradedPlanBuilt = plan.degradedFromPublication
            report.degradedPlanDrawsRequestTexture =
                plan.source.texture === request.texture
            report.degradedPlanKeepsStaticFileAtom =
                plan.source.kind == .staticFile
            report.degradedPlanCarriesLayerSourceIdentity =
                plan.source.requestIdentity == .layerSource(875)
            report.degradedPlanKeepsResolvedSample =
                plan.source.uvTransform == .identity
                && request.resolvedBaseTextureSample()
                    .map { plan.source.sampling == $0.sampling } == true
            report.degradedPlanContentMirrorsRequestCandidate =
                plan.source.resourceIdentity == candidate.identity
                && plan.source.resourceGeneration == candidate.generation
                && plan.source.purpose == candidate.purpose
                && plan.source.content == candidate.content
                && plan.source.physicalSize == candidate.physicalSize
                && plan.source.mappedSize == candidate.mappedSize
                && plan.source.authoredFormat == candidate.authoredFormat
            report.degradedPlanGeometryDrawable =
                plan.projectedGeometry.clippedArea > 0
                && plan.projectedGeometry.clippedNDCVertices.count >= 3
        }

        // Complement: an active graph publisher keeps the normal plan shape.
        let publisherActiveResult = SceneLayerSourcePassthroughPlan.resolve(
            request: request,
            publication: publication,
            route: .unclaimed,
            allowsStaticSourceGraphPublication: true,
            allowsUnpublishedStaticSourceDraw: true
        )
        if case let .success(plan) = publisherActiveResult {
            report.graphPublicationActiveBuildsNormalPlan =
                !plan.degradedFromPublication
        }

        // 2. Flag off keeps the exact graph-role rejection.
        let flagOffResult = SceneLayerSourcePassthroughPlan.resolve(
            request: request,
            publication: publication,
            route: .unclaimed
        )
        if case let .failure(reason) = flagOffResult {
            report.flagOffKeepsGraphRoleRejection =
                reason == .staticSourceGraphRolePresent
        }

        // 4. Flag on rescues only the graph-role rejection; every other guard
        //    still rejects with its own reason.
        let blendResult = SceneLayerSourcePassthroughPlan.resolve(
            request: blockedRequest(blendMode: 99),
            publication: publication,
            route: .unclaimed,
            allowsStaticSourceGraphPublication: false,
            allowsUnpublishedStaticSourceDraw: true
        )
        if case let .failure(reason) = blendResult {
            report.flagOnBlendGuardUnaffected = reason == .layerBlendUnsupported
        }
        let textureFrameResult = SceneLayerSourcePassthroughPlan.resolve(
            request: blockedRequest(
                blendMode: 0,
                textureFrame: SceneTextureUVTransform(
                    origin: SIMD2(0.25, 0.25),
                    xAxis: SIMD2(0.5, 0),
                    yAxis: SIMD2(0, 0.5)
                )
            ),
            publication: publication,
            route: .unclaimed,
            allowsStaticSourceGraphPublication: false,
            allowsUnpublishedStaticSourceDraw: true
        )
        if case let .failure(reason) = textureFrameResult {
            report.flagOnTextureFrameGuardUnaffected =
                reason == .textureFrameNonidentity
        }

        // 5. Compositor: unclaimed + graph-role rejection + flag encodes the
        //    base texture in the main pass and traces the draw-only route;
        //    flag off fails closed with the unchanged reason.
        let pipeline = SceneImageLayerPipeline()
        let mainPass = SceneMainPassEncoder(device: device)
        let compositor = SceneImageLayerCompositor(
            pipelineRepository: SceneImageEffectPipelineRepository(device: device)
        )
        var prepared = 0
        let initialCapacity = compositor.prepareSnapshotCapacity(width: 4, height: 4, pixelFormat: .bgra8Unorm) {
            prepared += 1; return true
        }
        let retainedCost = compositor.renderTargetResidentByteCost
        // Probe the actual snapshot owned by the fixture pipeline. Accounting
        // alone cannot detect a rollback that retains the rejected 8x8 texture.
        let snapshot = SceneLayerColorBlendPipeline.lastCreated!.framebufferSnapshot
        let captureDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm, width: 4, height: 4, mipmapped: false
        )
        captureDescriptor.storageMode = .shared
        let captureTarget = device.makeTexture(descriptor: captureDescriptor)!
        let pixels = [UInt8](repeating: 0, count: 64)
        pixels.withUnsafeBytes {
            captureTarget.replace(region: MTLRegionMake2D(0, 0, 4, 4), mipmapLevel: 0,
                                  withBytes: $0.baseAddress!, bytesPerRow: 16)
        }
        let captureQueue = device.makeCommandQueue()!
        func completedCapture() -> MTLTexture? {
            let buffer = captureQueue.makeCommandBuffer()!
            let captured = snapshot.capture(target: captureTarget, commandBuffer: buffer)
            buffer.commit()
            buffer.waitUntilCompleted()
            return buffer.status == .completed ? captured : nil
        }
        let retainedTexture = completedCapture()
        let rejectedCapacity = compositor.prepareSnapshotCapacity(width: 8, height: 8, pixelFormat: .bgra8Unorm) {
            prepared += 1; return false
        }
        let rolledBackCost = compositor.renderTargetResidentByteCost
        let rolledBackTexture = completedCapture()
        report.snapshotCapacityCommitsAndRollsBack = initialCapacity && !rejectedCapacity
            && prepared == 2 && retainedCost == 64 && rolledBackCost == retainedCost
            && retainedTexture != nil && retainedTexture === rolledBackTexture
            && rolledBackTexture?.width == 4 && rolledBackTexture?.height == 4
        SceneImageLayerMainPassRenderer.recorded.removeAll()
        let degradedTrace = SceneEffectExecutionFrameTrace()
        let degradedOutcome = compositor.drawOutcome(
            request,
            explicitLayerSourcePublication: publication,
            resolvedMaterialGraphOutputPublisher: nil,
            layerSourceGraphFallbackPublisher: nil,
            allowsUnpublishedStaticSourceDraw: true,
            pipeline: pipeline,
            mainPass: mainPass,
            executionTrace: degradedTrace,
            executionOrigin: .image
        )
        report.compositorDegradedEncoded =
            degradedOutcome == .layerSourcePassthrough
        report.compositorDegradedDrewRequestBaseTexture =
            SceneImageLayerMainPassRenderer.recorded.count == 1
            && SceneImageLayerMainPassRenderer.recorded[0].texture
                === request.texture
            && SceneImageLayerMainPassRenderer.recorded[0].dependencyTexture
                == nil
        report.compositorDegradedTraceOperation = degradedTrace.records == [
            .init(
                layerID: 875,
                origin: .image,
                operation: "degraded-static-source-draw-only",
                outcome: .encoded
            )
        ]
        SceneImageLayerMainPassRenderer.recorded.removeAll()
        let failedTrace = SceneEffectExecutionFrameTrace()
        let failedOutcome = compositor.drawOutcome(
            request,
            explicitLayerSourcePublication: publication,
            resolvedMaterialGraphOutputPublisher: nil,
            layerSourceGraphFallbackPublisher: nil,
            pipeline: pipeline,
            mainPass: mainPass,
            executionTrace: failedTrace,
            executionOrigin: .image
        )
        report.compositorFlagOffFails = failedOutcome == .failed
            && SceneImageLayerMainPassRenderer.recorded.isEmpty
        report.compositorFlagOffTraceReason = failedTrace.records == [
            .init(
                layerID: 875,
                origin: .image,
                operation: "unclaimed-effect-product-authority",
                outcome: .failed(
                    reasonCode:
                        "unclaimed-visible-effects-static-source-graph-role-present"
                )
            )
        ]
        // A capture encoder can be unavailable before any command is emitted.
        // The optional lit path must draw the original authored source intact.
        let target = makeTexture(device)
        let sprite = SceneTextureUVTransform(origin: SIMD2(0.25, 0.125),
            xAxis: SIMD2(0.5, 0), yAxis: SIMD2(0, 0.25))
        let authoredTint = SIMD3<Float>(0.2, 0.6, 0.8)
        let litRequest = SceneImageLayerDrawRequest(
            layer: .init(id: 876, contentKind: "image"), texture: texture,
            masks: .empty, textureFrame: sprite,
            mvp: matrix_identity_float4x4,
            uniforms: .init(time: 0, alpha: 0.25, cursorUV: .zero, tint: authoredTint),
            offscreenTexturePool: FixtureCompositionPool(target: target),
            effectSourceExtent: .init(pixelSize: CGSize(width: 4, height: 4)),
            requiresSourceCopy: false, finalCompositeAlpha: nil,
            sourceLighting: SceneBaseMaterialLitCapturePayload()
        )
        SceneImageLayerMainPassRenderer.recorded.removeAll()
        _ = compositor.drawOutcome(litRequest, explicitLayerSourcePublication: nil,
            pipeline: pipeline, mainPass: mainPass)
        let failedCaptureDraw = SceneImageLayerMainPassRenderer.recorded.last!
        report.litCaptureFailureKeepsAuthoredUniforms = failedCaptureDraw.texture === texture
            && failedCaptureDraw.uniforms.alpha == 0.25
            && failedCaptureDraw.uniforms.tint == SIMD4(authoredTint, 1)
            && failedCaptureDraw.uniforms.textureFrame0 == sprite.uniform0
            && failedCaptureDraw.uniforms.textureFrame1 == sprite.uniform1
        SceneOffscreenEffectRenderer.captureSucceeds = true
        SceneImageLayerMainPassRenderer.recorded.removeAll()
        _ = compositor.drawOutcome(litRequest, explicitLayerSourcePublication: nil,
            pipeline: pipeline, mainPass: mainPass)
        let recoveryDraw = SceneImageLayerMainPassRenderer.recorded.last!
        report.litCaptureRecoveryUsesCapturedTexture = recoveryDraw.texture === target
            && recoveryDraw.uniforms.alpha == 1
            && SceneOffscreenEffectRenderer.capturedUniforms?.alpha == 0.25
            && SceneOffscreenEffectRenderer.capturedUniforms?.tint == SIMD4(authoredTint, 1)
            && SceneOffscreenEffectRenderer.capturedUniforms?.textureFrame0 == sprite.uniform0
        emit(report)
    }

    static func emit(_ report: StaticSourceDrawOnlyReport) {
        let data = try! JSONEncoder().encode(report)
        print(String(decoding: data, as: UTF8.self))
    }
}
