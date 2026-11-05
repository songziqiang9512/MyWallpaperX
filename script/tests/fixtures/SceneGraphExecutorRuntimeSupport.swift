
import simd

struct HarnessDedicatedAudioExecutionPlan { let audio: Bool? }

extension SceneEffectStageExecutionPlan {
    var shake: HarnessDedicatedAudioExecutionPlan? { nil }
    var pulse: HarnessDedicatedAudioExecutionPlan? { nil }
}

struct SceneEffectExactRuntimeSubject: Hashable {
    let key: SceneAuthoredEffectRenderPlan.EffectKey
    let family: String
}

struct SceneEffectDefinition {
    enum PerspectiveUVRole { case absent, quad(materialKeys: [String]), invalid }
    let relativePath: String
    let functions: SceneJSONValue?
    var perspectiveUVRole: PerspectiveUVRole = .absent
}

struct SceneUtilityLayer {
    enum Kind { case composition, project, fullscreen }
    let kind: Kind
    var passthrough = false
}

struct SceneRenderDescriptor {
    struct PassDescriptor {
        let passIndex: Int
        let combos: [String: Int]
    }

    struct EffectDescriptor {
        let id: String
        let file: String
        let visible: Bool?
        let passes: [PassDescriptor]
    }

    struct Layer {
        let id: Int
        let effects: [EffectDescriptor]
        var contentKind: String = "image"
        var colorBlendMode: Int? = nil
        var staticModelPath: String? = nil
        var particlePath: String? = nil
        var utilityLayer: SceneUtilityLayer? = nil
        var parentID: Int? = nil
        var childLayerIDs: [Int] = []
        var dependencyLayerIDs: [Int] = []
        var authoredDependencies: [String] = []
        var namedReferences: [SceneDependencyRenderPlan.Reference] = []
        var potentialNamedReferences: [SceneDependencyRenderPlan.Reference] = []
        var namedBindings: [SceneDependencyRenderPlan.Binding] = []
        var potentialNamedBindings: [SceneDependencyRenderPlan.Binding] = []
        var visible: Bool = true
    }

    struct MaterialPassDescriptor {
        let id: String
        let materialPath: String
        let combos: [String: Int]
    }

    let layers: [Layer]
    let materialPasses: [MaterialPassDescriptor]
    let effectDefinitions: [SceneEffectDefinition]

    var renderOrderLayerIDs: [Int] {
        layers.map(\.id)
    }
}

// Utility descriptor grammar has its own production gate. This harness
// supplies only the fullscreen route so it can exercise captured-main Programs.
enum SceneUtilityLayerSourceRoute {
    enum Failure: String, Error { case utilityShape = "utility-shape" }

    struct Resolution {
        let capturesCompositionSubtree: Bool
        var usesAuthoredLocalSource: Bool { false }
    }

    static func resolve(
        layer: SceneRenderDescriptor.Layer,
        descriptor: SceneRenderDescriptor
    ) -> Result<Resolution, Failure> {
        guard layer.utilityLayer?.kind == .fullscreen else { return .failure(.utilityShape) }
        return .success(.init(capturesCompositionSubtree: false))
    }
}

enum SceneLayerVisibility {
    static func visibleLayerIDs(in descriptor: SceneRenderDescriptor) -> Set<Int> {
        Set(descriptor.layers.filter(\.visible).map(\.id))
    }
}

enum SceneDependencyGraphAnalysis {
    static func references(
        in layers: [SceneRenderDescriptor.Layer]
    ) -> [SceneDependencyRenderPlan.Reference] {
        layers.flatMap(\.namedReferences)
    }

    static func potentialNamedReferences(
        in layers: [SceneRenderDescriptor.Layer]
    ) -> [SceneDependencyRenderPlan.Reference] {
        layers.flatMap(\.potentialNamedReferences)
    }
}

/* DEPENDENCY_PLAN_MODEL */

// Preselected carrier data only. Program preparation below is production.
extension SceneDependencyRenderPlan {
    static func isMultiProviderUtilityCandidate(
        layer: SceneRenderDescriptor.Layer, references: [Reference]
    ) -> Bool { layer.utilityLayer != nil && Set(references.map(\.providerLayerID)).count > 1 }

    static func activeDependencyProviderLayerIDs(
        layer: SceneRenderDescriptor.Layer, references: [Reference]
    ) -> Set<Int>? { Set(references.map(\.providerLayerID)) }

    static func potentialNamedBindings(
        descriptor: SceneRenderDescriptor, authoredPlans: [SceneAuthoredEffectRenderPlan] = [],
        visibleLayerIDs: Set<Int>,
        executableUtilityConsumerLayerIDs: Set<Int> = []
    ) -> [Int: [Binding]] {
        Dictionary(uniqueKeysWithValues: descriptor.layers.map { ($0.id, $0.potentialNamedBindings) })
    }

    init(
        descriptor: SceneRenderDescriptor, visibleLayerIDs: Set<Int>,
        executableUtilityConsumerLayerIDs: Set<Int> = [],
        admittedResolvedMaterialReferences: Set<Reference> = [],
        preparedNamedInputBindingsByConsumerLayerID: [Int: [Binding]] = [:]
    ) {
        let products = SceneDependencyGraphAnalysis.references(in: descriptor.layers)
        let potentials = Set(SceneDependencyGraphAnalysis.potentialNamedReferences(in: descriptor.layers))
            .intersection(admittedResolvedMaterialReferences)
        references = products + potentials.filter { !products.contains($0) }
        namedReferenceConsumerLayerIDs = Set(references.map(\.consumerLayerID))
        self.executableUtilityConsumerLayerIDs = executableUtilityConsumerLayerIDs
        multiProviderCandidateLayerIDs = []
        var singles: [Int: Binding] = [:]
        var aggregates: [Int: MultiProviderAggregate] = [:]
        for layer in descriptor.layers {
            let vector = preparedNamedInputBindingsByConsumerLayerID[layer.id] ?? layer.namedBindings
            if vector.count == 1 { singles[layer.id] = vector[0] }
            if vector.count > 1 { aggregates[layer.id] = .init(consumerLayerID: layer.id, bindings: vector) }
        }
        bindingsByConsumerLayerID = singles
        multiProviderAggregatesByConsumerLayerID = aggregates
        requiredEffectConsumerLayerIDs = Set(singles.keys).union(aggregates.keys)
        staticModelBindingsByConsumerLayerID = [:]
        let vector = descriptor.layers.flatMap { preparedNamedInputBindingsByConsumerLayerID[$0.id] ?? $0.namedBindings }
        let providerIDs = Set(vector.map(\.providerLayerID))
        requiredProviderLayerIDs = providerIDs
        requiredGraphOutputProviderLayerIDs = Set(descriptor.layers.filter {
            providerIDs.contains($0.id) && !$0.effects.isEmpty
        }.map(\.id))
        staticLayerSourcePassthroughBlockedLayerIDs = namedReferenceConsumerLayerIDs.union(requiredProviderLayerIDs)
        cyclicLayerIDs = []
        issues = []
    }
}

struct SceneEffectStageProgram {
    let effectKey: SceneAuthoredEffectRenderPlan.EffectKey
    let inputRole: SceneAuthoredEffectInputRole
    let stageGraph: SceneAuthoredEffectRenderPlan
    let executionPlan: SceneEffectStageExecutionPlan
}

struct AdmittedLayerGraph {
    let layerID: Int
    let renderGraph: SceneAuthoredEffectRenderPlan
    let stagePrograms: [SceneEffectStageProgram]

    var executionStages: [SceneEffectStageExecutionPlan] {
        stagePrograms.map(\.executionPlan)
    }
}

final class SceneResolvedMaterialRuntimeBridge {
/* SOURCE_MATERIAL_DECLARATIONS */
    struct FrameInputs {
        enum DependencyUnavailability: String, Hashable {
            case providerSourceUnavailable =
                "external-primary-provider-source-unavailable"
        }

        let time: Float
        let dynamicValues: SceneDynamicSnapshot
        let pointerIsInside: Bool
        let layerModelMatrix: simd_float4x4
        let effectOutputModelViewProjection: simd_float4x4
        let effectUnitModelMatrix: simd_float4x4? = nil
        let directDrawGeometry: SceneDirectDrawOutputGeometry.Resolved? = nil
        let directDrawSourceMaterialKey: SceneResolvedMaterialExecutionCapabilityCatalog.MaterialKey? = nil
        let terminalReplayModelViewProjection: simd_float4x4?
        let effectTextureProjectionMatrixInverse: simd_float4x4
        let effectDrawAlpha: Float = 1
        let effectDrawColor = SIMD3<Float>(repeating: 1)
        // The single ordered dependency lane: a one-element vector when a
        // single-provider dependency is reserved, empty otherwise.
        let dependencyEffects: [SceneDependencyEffectInput]
        let dependencyUnavailability: DependencyUnavailability?
        var stageActivationDecisions: [SceneAuthoredEffectRenderPlan.EffectKey:
            SceneResolvedMaterialStageActivationPolicy.Decision] = [:]

        init(
            dependencyEffects: [SceneDependencyEffectInput] = [],
            dependencyUnavailability: DependencyUnavailability? = nil,
            dynamicValues: SceneDynamicSnapshot = .empty(frameIndex: 0),
            pointerIsInside: Bool = true,
            effectOutputModelViewProjection: simd_float4x4 = matrix_identity_float4x4,
            terminalReplayModelViewProjection: simd_float4x4? = nil
        ) {
            time = 0
            self.dynamicValues = dynamicValues
            self.pointerIsInside = pointerIsInside
            layerModelMatrix = matrix_identity_float4x4
            self.effectOutputModelViewProjection = effectOutputModelViewProjection
            self.terminalReplayModelViewProjection = terminalReplayModelViewProjection
            effectTextureProjectionMatrixInverse = matrix_identity_float4x4
            self.dependencyEffects = dependencyEffects
            self.dependencyUnavailability = dependencyUnavailability
        }
    }
}

struct SceneDependencyEffectInput {
    let consumerLayerID: Int
    let providerLayerID: Int
    let slot: SceneEffectPassSlot
    let variant: SceneNamedTextureReference.Variant
    let frameEpoch: UInt64
    let blendMode: Int
    let texture: MTLTexture
    var content: SceneTextureContent
    let namedReference: SceneNamedTextureReference
    let reservedMaterialResource: SceneFrameTextureResource?

    init(
        consumerLayerID: Int = 1,
        providerLayerID: Int = 2,
        slot: SceneEffectPassSlot = SceneEffectPassSlot(
            effectID: "fixture", passIndex: 0, slotIndex: 1
        ),
        variant: SceneNamedTextureReference.Variant = .primary,
        frameEpoch: UInt64,
        blendMode: Int = 0,
        texture: MTLTexture,
        content: SceneTextureContent = .color(.resolved(.premultipliedAlpha)),
        namedReference: SceneNamedTextureReference,
        reservedMaterialResource: SceneFrameTextureResource? = nil
    ) {
        self.consumerLayerID = consumerLayerID
        self.providerLayerID = providerLayerID
        self.slot = slot
        self.variant = variant
        self.frameEpoch = frameEpoch
        self.blendMode = blendMode
        self.texture = texture
        self.content = content
        self.namedReference = namedReference
        self.reservedMaterialResource = reservedMaterialResource
    }

    func withContent(_ content: SceneTextureContent) -> Self {
        var result = self
        result.content = content
        return result
    }
}

enum SceneEffectStageRenderer {
    struct PreparedStage {
        let sourceTexture: MTLTexture
        let composeTexture: MTLTexture
        let outputTexture: MTLTexture
    }
    enum StagePreparation {
        case ready(PreparedStage)
        case rejected(reason: String)
    }

    static func prepareStage(
        _ stage: SceneEffectStageExecutionPlan,
        sourceTexture: MTLTexture,
        targets: SceneGraphRenderTargetTable,
        inputs: SceneResolvedMaterialRuntimeBridge.FrameInputs,
        sourcePipeline: SceneImageLayerPipeline,
        time: Float
    ) -> StagePreparation {
        _ = inputs
        _ = sourcePipeline
        _ = time
        guard targets.inputTexture === sourceTexture,
              targets.fullFramePair.first !== targets.fullFramePair.second else {
            return .rejected(reason: "fixture-stage-unavailable")
        }
        let composeTexture: MTLTexture
        if sourceTexture === targets.fullFramePair.first {
            composeTexture = targets.fullFramePair.second
        } else if sourceTexture === targets.fullFramePair.second {
            composeTexture = targets.fullFramePair.first
        } else {
            return .rejected(reason: "fixture-pair-endpoint")
        }
        return .ready(.init(
            sourceTexture: sourceTexture,
            composeTexture: composeTexture,
            outputTexture: targets.outputTexture
        ))
    }

    static func encodePreparedStage(
        _ stage: PreparedStage,
        commandBuffer: MTLCommandBuffer
    ) -> Bool {
        guard stage.sourceTexture !== stage.composeTexture,
              stage.composeTexture !== stage.outputTexture,
              stage.sourceTexture.width == stage.composeTexture.width,
              stage.sourceTexture.height == stage.composeTexture.height,
              stage.composeTexture.width == stage.outputTexture.width,
              stage.composeTexture.height == stage.outputTexture.height,
              let encoder = commandBuffer.makeBlitCommandEncoder() else {
            return false
        }
        let size = MTLSize(
            width: stage.sourceTexture.width,
            height: stage.sourceTexture.height,
            depth: 1
        )
        encoder.copy(
            from: stage.sourceTexture,
            sourceSlice: 0,
            sourceLevel: 0,
            sourceOrigin: .init(x: 0, y: 0, z: 0),
            sourceSize: size,
            to: stage.composeTexture,
            destinationSlice: 0,
            destinationLevel: 0,
            destinationOrigin: .init(x: 0, y: 0, z: 0)
        )
        encoder.copy(
            from: stage.composeTexture,
            sourceSlice: 0,
            sourceLevel: 0,
            sourceOrigin: .init(x: 0, y: 0, z: 0),
            sourceSize: size,
            to: stage.outputTexture,
            destinationSlice: 0,
            destinationLevel: 0,
            destinationOrigin: .init(x: 0, y: 0, z: 0)
        )
        encoder.endEncoding()
        return true
    }
}

struct SceneResolvedMaterialRuntimeCatalog {
    typealias Graph = SceneAuthoredEffectRenderPlan

    typealias Key = SceneResolvedMaterialKey

    enum Entry {
        case template(SceneResolvedMaterialTemplate,
            textureFormatSlots: Result<Set<Int>, SceneResolvedMaterialFailure>)
        case failure(SceneResolvedMaterialFailure)
    }

    struct ResourceDemandIssue: Hashable {
        enum Code: Hashable { case samplerSchemaUnavailable, purposeUnproven }
        let key: Key
        let slot: Int
        let code: Code
        init(key: Key, slot: Int, code: Code = .purposeUnproven) {
            self.key = key
            self.slot = slot
            self.code = code
        }
    }

    let entries: [Key: Entry]
    let resourceDemandIssues: Set<ResourceDemandIssue>
    let systemProviderDemandsByMaterial: [Key: Set<SceneSystemProviderTextureIdentity>]
    let entryObserver: ((Graph.Node) -> Void)?

    init(
        entries: [Key: Entry],
        resourceDemandIssues: Set<ResourceDemandIssue> = [],
        systemProviderDemandsByMaterial: [Key: Set<SceneSystemProviderTextureIdentity>] = [:],
        entryObserver: ((Graph.Node) -> Void)? = nil
    ) {
        self.entries = entries
        self.resourceDemandIssues = resourceDemandIssues
        self.systemProviderDemandsByMaterial = systemProviderDemandsByMaterial
        self.entryObserver = entryObserver
    }

    func entry(for node: Graph.Node) -> Entry? {
        entryObserver?(node)
        return entries[.init(effect: node.effect, nodeIndex: node.nodeIndex)]
    }

    func admittedEntry(
        for node: Graph.Node,
        graph: Graph,
        descriptor: SceneRenderDescriptor
    ) -> Entry? {
        _ = graph
        _ = descriptor
        return entry(for: node)
    }
}

final class ScenePreparedPersistentGraphTargets {
    struct HistoryRehydrateCopy {
        let sourceToken: SceneGraphExecutionState.PhysicalToken
        let sourceTexture: MTLTexture
        let targetToken: SceneGraphExecutionState.PhysicalToken
        let targetTexture: MTLTexture
    }
}

extension SceneResolvedMaterialExecutionCapabilityCatalog {
    func claim(
        _ admittedGraph: AdmittedLayerGraph
    ) -> ClaimedLayer? {
        claim(layerID: admittedGraph.layerID)
    }

    func resolve(
        _ token: Token,
        for admittedGraph: AdmittedLayerGraph
    ) -> LayerCapability? {
        guard let capability = resolve(token),
              capability.layerID == admittedGraph.layerID else { return nil }
        return capability
    }
}

// ABI-only disabled tail for the actual Image shader bound below. Fog
// evaluation stays in the canonical product header, not in this scaffold.
struct SceneImageDistanceFogUniforms {
    var color = SIMD4<Float>.zero
    var range = SIMD4<Float>.zero
    var cameraRelativeOrigin = SIMD4<Float>.zero
    var modelX = SIMD4<Float>.zero
    var modelY = SIMD4<Float>.zero
}

struct SceneLayerFragmentUniforms {
    // Mirrors the product layout in SceneMetalPipeline.swift so the real
    // lit-capture shader reads the same bytes the CPU struct produces.
    var time: Float
    var alpha: Float
    var dependencyBlendMode: UInt32
    var usesDependencyBlend: UInt32
    var cursorUV: SIMD2<Float>
    var sourceSampling: SIMD2<UInt32>
    var tint: SIMD4<Float>
    var textureFrame0: SIMD4<Float>
    var textureFrame1: SIMD4<Float>
    var distanceFog: SceneImageDistanceFogUniforms = .init()
    var sourceCaptureProjection: simd_float4x4 = matrix_identity_float4x4

    init(
        time: Float = 0,
        alpha: Float = 1,
        dependencyBlendMode: UInt32 = 0,
        usesDependencyBlend: UInt32 = 0,
        cursorUV: SIMD2<Float> = .zero,
        sourceSampling: SIMD2<UInt32> = .zero,
        tint: SIMD4<Float>,
        textureFrame0: SIMD4<Float> = .init(0, 0, 1, 0),
        textureFrame1: SIMD4<Float> = .init(0, 1, 0, 0)
    ) {
        self.time = time
        self.alpha = alpha
        self.dependencyBlendMode = dependencyBlendMode
        self.usesDependencyBlend = usesDependencyBlend
        self.cursorUV = cursorUV
        self.sourceSampling = sourceSampling
        self.tint = tint
        self.textureFrame0 = textureFrame0
        self.textureFrame1 = textureFrame1
    }

    static func neutral() -> Self {
        .init(tint: SIMD4<Float>(repeating: 1))
    }
}

struct SceneImageLayerPipeline {
    var pixelFormat: MTLPixelFormat = .bgra8Unorm
    private struct Vertex {
        let position: SIMD2<Float>
        let texcoord: SIMD2<Float>
        let vertexCoverage: Float = 1
    }

    private static let vertices = [
        Vertex(position: .init(-0.5, -0.5), texcoord: .init(0, 1)),
        Vertex(position: .init( 0.5, -0.5), texcoord: .init(1, 1)),
        Vertex(position: .init(-0.5,  0.5), texcoord: .init(0, 0)),
        Vertex(position: .init( 0.5,  0.5), texcoord: .init(1, 0)),
    ]

    let state: MTLRenderPipelineState

    func bind(encoder: MTLRenderCommandEncoder) {
        encoder.setRenderPipelineState(state)
        Self.bindQuad(encoder: encoder)
    }

    static func bindQuad(encoder: MTLRenderCommandEncoder) {
        var vertices = Self.vertices
        encoder.setVertexBytes(
            &vertices,
            length: vertices.count * MemoryLayout<Vertex>.stride,
            index: 0
        )
    }

    func drawLayer(
        texture: MTLTexture,
        dependencyTexture: MTLTexture? = nil,
        mvp: simd_float4x4,
        uniforms: SceneLayerFragmentUniforms,
        encoder: MTLRenderCommandEncoder
    ) {
        var mvp = mvp
        var uniforms = uniforms
        var clipTransform = SIMD4<Float>.zero
        encoder.setVertexBytes(
            &mvp,
            length: MemoryLayout<simd_float4x4>.size,
            index: 1
        )
        encoder.setFragmentBytes(
            &uniforms,
            length: MemoryLayout<SceneLayerFragmentUniforms>.size,
            index: 0
        )
        encoder.setFragmentTexture(texture, index: 0)
        encoder.setFragmentTexture(dependencyTexture ?? texture, index: 1)
        encoder.setFragmentTexture(texture, index: 2)
        encoder.setFragmentBytes(&clipTransform, length: MemoryLayout<SIMD4<Float>>.size, index: 1)
        encoder.drawPrimitives(
            type: .triangleStrip,
            vertexStart: 0,
            vertexCount: 4
        )
    }
}
