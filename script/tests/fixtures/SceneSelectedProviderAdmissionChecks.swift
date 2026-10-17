import Foundation
import Metal

// Pure descriptor data only. Dependency discovery, conservation, structural
// admission, binding and executable selection are complete production files.
struct SceneDocument {
    struct ShaderValue {
        let valueKind: String
        let userBinding: String?
        let components: [Double]?
    }
}

struct SceneEffectTextureInput {
    enum Kind { case path, system, property, unknown }
    let kind: Kind
    let value: String
}

struct SceneUtilityLayer {
    enum Kind: String { case composition, project, fullscreen }
    let kind: Kind
    var copyBackground = true
    var passthrough = false
}

struct SceneRenderDescriptor {
    struct ModelMaterialLink {
        let modelPath: String
        let materialPath: String?
    }
    struct MaterialPassDescriptor {
        var id = ""
        var materialPath = ""
        var passIndex = 0
        var texturePaths: [String] = []
        var textureSlots: [String?] = []
        var userTextureInputs: [SceneEffectTextureInput?] = []
        var combos: [String: Int] = [:]
    }
    struct EffectDescriptor {
        struct PassDescriptor {
            let passIndex: Int
            let texturePaths: [String]
            let textureSlots: [String?]
            var userTextureInputs: [SceneEffectTextureInput?] = []
            let combos: [String: Int]
            let constantShaderValues: [String: SceneDocument.ShaderValue]
        }
        let id: String
        let file: String
        let visible: Bool?
        let passes: [PassDescriptor]
    }
    typealias PassDescriptor = EffectDescriptor.PassDescriptor
    struct Layer {
        struct DisplayScriptOwnership { let visible: Bool }
        let id: Int
        let effects: [EffectDescriptor]
        var contentKind = "image"
        var staticModelPath: String? = nil
        var puppetMeshPath: String? = nil
        var particlePath: String? = nil
        var imagePath: String? = nil
        var utilityLayer: SceneUtilityLayer? = nil
        var parentID: Int? = nil
        var childLayerIDs: [Int] = []
        var dependencyLayerIDs: [Int] = []
        var authoredDependencies: [String] = []
        var displayScriptOwnership: DisplayScriptOwnership? = nil
        var colorBlendMode: Int? = nil
        var visible: Bool? = true
    }
    let layers: [Layer]
    let renderOrderLayerIDs: [Int]
    var modelMaterialLinks: [ModelMaterialLink] = []
    var materialPasses: [MaterialPassDescriptor] = []
    var effectDefinitions: [SceneEffectDefinition] = []
}

// These adjacent rendering seams are linked but never executed by this CPU
// fixture. A call here is a test failure rather than a substituted policy.
enum SceneUtilityLayerSourceRoute {
    enum Failure: String, Error, Equatable {
        case utilityShape = "utility-shape"
    }
    struct Resolution {
        let capturesCompositionSubtree: Bool
        let usesIsolatedGroupTarget: Bool
        let orderedCompositionSubtreeLayerIDs: [Int]
        let triggerLayerID: Int
    }
    static func resolve(layer: SceneRenderDescriptor.Layer,
                        descriptor: SceneRenderDescriptor) -> Result<Resolution, Failure> {
        preconditionFailure("source capture is outside this CPU admission gate")
    }
}
enum SceneLayerVisibility {
    static func visibleLayerIDs(in descriptor: SceneRenderDescriptor) -> Set<Int> {
        preconditionFailure("parent visibility is outside this CPU admission gate")
    }
}
enum SceneBlendModeShaderSource {
    static var maximumMode: Int { preconditionFailure("framebuffer planning is not executed") }
}
extension SceneOffscreenTexturePool {
    var sceneColorResetEpoch: UUID { preconditionFailure("no GPU targets") }
    func compositionGroupTarget(layerID: Int, width: Int, height: Int,
                                commandBuffer: MTLCommandBuffer) -> PinnedTexture? {
        preconditionFailure("no GPU targets")
    }
}

@main
private enum SelectedProviderAdmissionChecks {
    typealias Layer = SceneRenderDescriptor.Layer
    typealias Effect = SceneRenderDescriptor.EffectDescriptor
    typealias Ownership = SceneResolvedMaterialDependencyOwnershipCompiler

    static func effect(name: String, provider: Int, visible: Bool,
                       variant: String = "a", plain: Bool = false) -> Effect {
        let path = "_rt_imageLayerComposite_\(provider)_\(variant)"
        return Effect(id: name, file: "effects/blend/effect.json", visible: visible,
            passes: [.init(passIndex: 0, texturePaths: [path], textureSlots: [nil, path],
                combos: plain ? ["BLENDMODE": 0] : ["BLENDMODE": 0,
                    "TRANSFORMUV": 1, "TRANSFORMREPEAT": 1, "WRITEALPHA": 1],
                constantShaderValues: plain ? [:] : [
                    "blendscale": .init(valueKind: "number", userBinding: nil, components: [0.5])])])
    }

    static func inspect(layers: [Layer], consumerID: Int, selected: Int,
                        selectedSlot: String, authorize: Bool = true) -> [String: Any] {
        let descriptor = SceneRenderDescriptor(layers: layers,
            renderOrderLayerIDs: layers.map(\.id))
        let consumer = layers.first { $0.id == consumerID }!
        let rawBefore = consumer.dependencyLayerIDs
        let references = SceneDependencyGraphAnalysis.references(in: layers)
        let structural = Ownership.structuralUtilityConsumerLayerIDs(in: descriptor)
        let plan = SceneDependencyRenderPlan(descriptor: descriptor,
            visibleLayerIDs: [consumerID], executableUtilityConsumerLayerIDs: structural,
            admittedResolvedMaterialReferences: authorize ? Set(references) : [])
        let ownReferences = plan.references.filter { $0.consumerLayerID == consumerID }
        let refused = Ownership.refusedCompositionConsumer(layer: consumer,
            layerID: consumerID, layerReferences: ownReferences, plan: plan)
        let binding = plan.bindingsByConsumerLayerID[consumerID]
        let aggregate = plan.multiProviderAggregatesByConsumerLayerID[consumerID]
        let owner = Ownership.compile(layer: consumer, graph: nil, references: ownReferences,
            binding: binding, aggregate: aggregate)
        let hasOwner = !refused && owner != nil
        let executable = SceneUtilityLayerRuntimePlanner.executableUtilityConsumerLayerIDs(
            in: descriptor, resolvedMaterialLayerIDs: hasOwner ? [consumerID] : [])
        return ["selected": selected, "selectedSlot": selectedSlot,
            "structural": structural.contains(consumerID), "refused": refused,
            "owner": hasOwner, "executable": executable.contains(consumerID),
            "bindingProvider": binding?.providerLayerID ?? -1,
            "bindingSlots": binding?.referenceSlots.map(\.effectID) ?? [],
            "aggregateStrict": aggregate?.hasStrictBindingVector ?? false,
            "aggregateProviders": aggregate?.orderedBindings.map(\.providerLayerID) ?? [],
            "requiredProviders": plan.requiredProviderLayerIDs.sorted(),
            "rawBefore": rawBefore,
            "rawAfter": descriptor.layers.first { $0.id == consumerID }!.dependencyLayerIDs,
            "issues": plan.issues.map { "\($0.layerID):\($0.kind.rawValue)" }.sorted()]
    }

    static func variant(name: String, base: Int) -> [String: Any] {
        let a = base + 1, b = base + 2, consumerID = base + 9
        var sourceA = Layer(id: a, effects: [])
        sourceA.visible = false
        sourceA.imagePath = "models/\(name)-diamond.json"
        var sourceB = Layer(id: b, effects: [])
        sourceB.visible = false
        sourceB.imagePath = "models/\(name)-stripe.json"
        func consumer(_ first: Bool, _ second: Bool) -> Layer {
            var layer = Layer(id: consumerID, effects: [
                effect(name: "\(name)-first", provider: a, visible: first),
                effect(name: "\(name)-second", provider: b, visible: second)])
            layer.contentKind = "composition"
            layer.utilityLayer = .init(kind: .composition)
            layer.dependencyLayerIDs = [a, b]
            return layer
        }
        func check(_ layer: Layer, sources: [Layer]? = nil,
                   selected: Int = -1, slot: String = "", authorize: Bool = true) -> [String: Any] {
            inspect(layers: (sources ?? [sourceA, sourceB]) + [layer],
                consumerID: consumerID, selected: selected, selectedSlot: slot, authorize: authorize)
        }
        let first = consumer(true, false), second = consumer(false, true)
        var rejected: [String: Any] = [:]
        var extra = first
        extra.dependencyLayerIDs.append(base + 3)
        rejected["unexplained"] = check(extra)
        rejected["missing"] = check(first, sources: [sourceB])
        let cyclicA = Layer(id: a, effects: [effect(name: "\(name)-back", provider: consumerID,
            visible: true)], dependencyLayerIDs: [consumerID], visible: false)
        rejected["cycle"] = check(first, sources: [cyclicA, sourceB])
        var duplicate = first
        duplicate.dependencyLayerIDs.append(b)
        rejected["duplicateDeclaration"] = check(duplicate)
        var selfExtra = first
        selfExtra.dependencyLayerIDs.append(consumerID)
        rejected["selfExtra"] = check(selfExtra)
        var unknown = first
        unknown.authoredDependencies = ["unexplained-object"]
        rejected["authoredUnknown"] = check(unknown)
        let secondary = Layer(id: consumerID, effects: [
            effect(name: "\(name)-secondary", provider: a, visible: true, variant: "b"),
            effect(name: "\(name)-second", provider: b, visible: false)],
            contentKind: "composition", utilityLayer: .init(kind: .composition),
            dependencyLayerIDs: [a, b])
        rejected["secondary"] = check(secondary)
        var plain = Layer(id: consumerID, effects: [
            effect(name: "\(name)-plain", provider: a, visible: true, plain: true)])
        plain.dependencyLayerIDs = [a]
        return ["name": name,
            "first": check(first, selected: a, slot: "\(name)-first"),
            "second": check(second, selected: b, slot: "\(name)-second"),
            "both": check(consumer(true, true)), "rejected": rejected,
            "plain": check(plain, selected: a),
            "unadmitted": check(first, authorize: false)]
    }

    static func main() throws {
        let facts: [String: Any] = ["variants": [
            variant(name: "lattice", base: 100), variant(name: "retitled-grain", base: 700)]]
        print(String(decoding: try JSONSerialization.data(withJSONObject: facts,
            options: [.sortedKeys]), as: UTF8.self))
    }
}
