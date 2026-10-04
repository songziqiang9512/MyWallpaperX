
import Foundation
enum SceneGraphRenderTargetPlan { enum TextureFormat { case rgba16f, rgbaBackbuffer } }

enum SceneTextGeometry {
    static func expandedSize(authoredSize: [Float]?, padding: Float) -> [Float]? { authoredSize }
}
enum SceneUserPropertyValue {}
enum SceneUserPropertyKind { case sceneTexture }
struct SceneUserPropertyDefinition {
    let key: String
    let kind: SceneUserPropertyKind
}
struct SceneUserPropertyCatalog {
    let definitions: [SceneUserPropertyDefinition]
    static let empty = SceneUserPropertyCatalog(definitions: [])
}

struct SceneUserPropertyDocumentResolver {
    func resolve(
        root: [String: Any],
        catalog: SceneUserPropertyCatalog,
        overrides: [String: SceneUserPropertyValue]
    ) -> SceneUserPropertyResolution { SceneUserPropertyResolution(root: root) }
}
struct ScenePkgExtractionReport { let outputURL: URL? }
struct SceneProject {
    let rootURL: URL
    let entryPath: String
    let userProperties: SceneUserPropertyCatalog
    var entryURL: URL { rootURL.appendingPathComponent(entryPath) }
}
struct SceneMdlPuppetAttachment {
    let name: String
    let sceneBindFrameColumnMajor: [Float]
}
struct SceneAssetCatalog {
    struct ModelAsset {
        var declaredSizeWH: [Float]? { nil }
        let relativePath: String
        let materialPath: String?
        let cropOffsetXY: [Float]?
        let isSolidLayer: Bool
        let puppetPath: String?
        let puppetAttachments: [SceneMdlPuppetAttachment]
    }
    struct MaterialAsset {
        struct Pass {
            let shader: String?
            let textures: [String]
            let textureSlots: [String?]
            let userTextureInputs: [SceneEffectTextureInput?]
            let combos: [String: Int]
            let constantShaderValues: [String: SceneDocument.ShaderValue]
            let userShaderValues: [String: String]
            let blending: String?
            let depthTest: String?
            let depthWrite: String?
            let cullMode: String?
            let alphaWriting: String?
        }
        let relativePath: String
        let rawSHA256: String
        let shaderPathIndependentSHA256: String
        let passes: [Pass]
    }
    let models: [ModelAsset]
    let materials: [MaterialAsset]
    let effectDefinitions: [SceneEffectDefinition]
    let effectDefinitionDiagnostics: [SceneEffectDefinitionDiagnostic]
    let shaderReferences: [String]
    var shaderContracts: [Never] { [] }
    let textureReferences: [String]
}
struct SceneResourceReferenceIndex {
    let missingReferences: [String]
    let builtInReferenceCount: Int
    let runtimeProvidedReferenceCount: Int
}
struct SceneCapabilityProfile { let firstStageRendererGaps: [String] }

struct SceneDiagnosticsReport {
    let project: SceneProject?
    let sceneDocument: SceneDocument?
    let assetCatalog: SceneAssetCatalog?
    let resourceReferences: SceneResourceReferenceIndex?
    let capabilityProfile: SceneCapabilityProfile?
}

enum HarnessError: Error { case missingFixture, descriptorRejected }

@main
enum Harness {
    static func main() throws {
        guard CommandLine.arguments.count == 2 else { throw HarnessError.missingFixture }
        let sceneURL = URL(fileURLWithPath: CommandLine.arguments[1])
        let document = try SceneDocumentLoader().load(from: sceneURL)
        guard let descriptor = SceneRenderDescriptorBuilder().build(
            project: SceneProject(
                rootURL: sceneURL.deletingLastPathComponent(),
                entryPath: sceneURL.lastPathComponent,
                userProperties: .empty
            ),
            sceneDocument: document,
            assetCatalog: SceneAssetCatalog(
                models: [], materials: [], effectDefinitions: [],
                effectDefinitionDiagnostics: [], shaderReferences: [], textureReferences: []
            ),
            resourceReferences: SceneResourceReferenceIndex(
                missingReferences: [], builtInReferenceCount: 0,
                runtimeProvidedReferenceCount: 0
            ),
            capabilityProfile: SceneCapabilityProfile(firstStageRendererGaps: [])
        ) else {
            throw HarnessError.descriptorRejected
        }
        let program = SceneTimelineTargetCompiler.compile(descriptor: descriptor)
        let vectorTarget = SceneDynamicTarget.effectConstant(
            layerID: 30,
            effectIndex: 1,
            passIndex: 1,
            name: "neutralVector"
        )
        let definitions = SceneTimelineRuntime.mergedDefinitions(
            propertyDefinitions: [],
            timelineProgram: program
        )
        var transaction = SceneEvaluationTransaction()
        let first = transaction.evaluate(
            frameIndex: 1,
            definitions: definitions,
            timelineValues: SceneTimelineRuntime.values(
                program: program,
                sceneTime: 0
            )
        )
        let second = transaction.evaluate(
            frameIndex: 2,
            definitions: definitions,
            timelineValues: SceneTimelineRuntime.values(
                program: program,
                sceneTime: 1
            )
        )
        let firstVector = first.snapshot[vectorTarget]
        let secondVector = second.snapshot[vectorTarget]
        let cameraPathFOV: Double =
            descriptor.layers.first(where: { $0.id == 66 })?.cameraPath?.fov ?? -1
        let firstValue = firstVector.map { describe($0.value) } ?? "missing"
        let firstSource = firstVector?.source.rawValue ?? "missing"
        let firstDiagnostics = first.diagnostics.map(\.code.rawValue)
        let secondValue = secondVector.map { describe($0.value) } ?? "missing"
        let secondSource = secondVector?.source.rawValue ?? "missing"
        let secondDiagnostics = second.diagnostics.map(\.code.rawValue)
        let vectorRuntime: [String: Any] = [
            "firstValue": firstValue,
            "firstSource": firstSource,
            "firstGeneration": first.snapshot.generation,
            "firstDiagnostics": firstDiagnostics,
            "secondValue": secondValue,
            "secondSource": secondSource,
            "secondGeneration": second.snapshot.generation,
            "secondDiagnostics": secondDiagnostics,
        ]
        let payload: [String: Any] = [
            "diagnostics": program.diagnostics,
            "cameraPathFOV": cameraPathFOV,
            "vectorRuntime": vectorRuntime,
            "bindings": program.bindings.map { binding in
                [
                    "target": describe(binding.definition.target),
                    "valueType": binding.definition.valueType.rawValue,
                    "authored": describe(binding.definition.authoredValue),
                    "mode": binding.animation.options.mode.rawValue,
                    "componentCount": binding.animation.componentCount,
                    "composition": binding.composition.rawValue,
                ]
            },
        ]
        print(String(decoding: try JSONSerialization.data(
            withJSONObject: payload, options: [.sortedKeys]
        ), as: UTF8.self))
    }

    static func describe(_ target: SceneDynamicTarget) -> String {
        switch target {
        case let .camera(field): "camera:\(field.rawValue)"
        case let .layer(layerID, field): "layer:\(layerID):\(field.rawValue)"
        case let .effectConstant(layerID, effectIndex, passIndex, name):
            "constant:\(layerID):\(effectIndex):\(passIndex):\(name)"
        case let .particle(layerID, field):
            switch field {
            case .alpha: "particle:\(layerID):alpha"
            case .size: "particle:\(layerID):size"
            case .count: "particle:\(layerID):count"
            case let .controlPoint(index): "particle:\(layerID):controlpoint:\(index)"
            case let .controlPointAngles(index): "particle:\(layerID):angles:\(index)"
            default: "particle:\(layerID):other"
            }
        case let .text(layerID, field): "text:\(layerID):\(field.rawValue)"
        default: "other"
        }
    }

    static func describe(_ value: SceneDynamicValue) -> String {
        switch value {
        case let .scalar(v): "scalar(\(v))"
        case let .vector2(x, y): "vector2(\(x),\(y))"
        case let .vector3(x, y, z): "vector3(\(x),\(y),\(z))"
        case let .vector4(x, y, z, w): "vector4(\(x),\(y),\(z),\(w))"
        case .bool, .string: "other"
        }
    }
}
