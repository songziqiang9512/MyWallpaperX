
import Foundation

struct SceneParticleInstanceOverride: Codable {}

struct SceneParticleDefinitionParser {
    func parseInstanceOverride(_ raw: Any?) -> SceneParticleInstanceOverride? { nil }
}

struct SceneTextDescriptor: Codable {
    let padding: Float
    init(padding: Float = 0) { self.padding = padding }
    static func parse(_ root: [String: Any]) -> SceneTextDescriptor { .init() }
}

enum SceneTextGeometry {
    static func expandedSize(authoredSize: [Float]?, padding: Float) -> [Float]? {
        authoredSize
    }
}

struct ScenePkgExtractionReport {
    let outputURL: URL?
}

struct SceneProject {
    let rootURL: URL
    let entryPath: String
    let userProperties: SceneUserPropertyCatalog
    var entryURL: URL { rootURL.appendingPathComponent(entryPath) }
}

struct BindingPayload: Encodable {
    let source: String
    let ownerKind: String
    let objectIndex: Int?
    let objectID: Int?
    let effectIndex: Int?
    let effectID: Int?
    let passIndex: Int?
    let passID: Int?
    let targetPath: [String]
    let targetKey: String
    let properties: [String: SceneJSONValue]
    let authoredValue: SceneJSONValue?
    let valueType: String
    let wrapperKeys: [String]
    let userPropertyKey: String?

    init(_ binding: SceneScriptBindingIR) {
        source = binding.source
        ownerKind = binding.owner.kind.rawValue
        objectIndex = binding.owner.objectIndex
        objectID = binding.owner.objectID
        effectIndex = binding.owner.effectIndex
        effectID = binding.owner.effectID
        passIndex = binding.owner.passIndex
        passID = binding.owner.passID
        targetPath = binding.targetPath.map {
            switch $0 {
            case let .key(key): key
            case let .index(index): "[\(index)]"
            }
        }
        targetKey = binding.targetKey
        properties = binding.properties
        authoredValue = binding.authoredValue
        valueType = binding.valueType.rawValue
        wrapperKeys = binding.wrapperKeys ?? []
        userPropertyKey = binding.userPropertyKey
    }
}

struct DiagnosticPayload: Encodable {
    let code: String
    let targetPath: [String]

    init(_ diagnostic: SceneScriptBindingDiagnostic) {
        code = diagnostic.code.rawValue
        targetPath = diagnostic.targetPath.map {
            switch $0 {
            case let .key(key): key
            case let .index(index): "[\(index)]"
            }
        }
    }
}

struct SourceEvidencePayload: Encodable {
    let source: String
    let ownerKind: String
    let objectIndex: Int?
    let objectID: Int?
    let effectIndex: Int?
    let effectID: Int?
    let passIndex: Int?
    let passID: Int?
    let targetPath: [String]
    let targetKey: String
    let wrapperKeys: [String]

    init(_ evidence: SceneScriptSourceEvidenceIR) {
        source = evidence.source
        ownerKind = evidence.owner.kind.rawValue
        objectIndex = evidence.owner.objectIndex
        objectID = evidence.owner.objectID
        effectIndex = evidence.owner.effectIndex
        effectID = evidence.owner.effectID
        passIndex = evidence.owner.passIndex
        passID = evidence.owner.passID
        targetPath = evidence.targetPath.map {
            switch $0 {
            case let .key(key): key
            case let .index(index): "[\(index)]"
            }
        }
        targetKey = evidence.targetKey
        wrapperKeys = evidence.wrapperKeys
    }
}

struct Payload: Encodable {
    let bindings: [BindingPayload]
    let diagnostics: [DiagnosticPayload]
    let sourceEvidence: [SourceEvidencePayload]
    let invalidAuthoredBindingCount: Int
    let invalidAuthoredDiagnostics: [DiagnosticPayload]
    let invalidAuthoredSourceEvidence: [SourceEvidencePayload]
    let mixedArraySourceEvidence: [SourceEvidencePayload]
    let legacyWrapperKeysMissing: Bool
}

enum HarnessError: Error { case missingFixture }

@main
enum Harness {
    static func main() throws {
        guard CommandLine.arguments.count == 2 else { throw HarnessError.missingFixture }
        let sceneURL = URL(fileURLWithPath: CommandLine.arguments[1])
        let document = try SceneDocumentLoader().load(from: sceneURL)
        let legacyIR = try JSONDecoder().decode(
            SceneScriptBindingIR.self,
            from: Data("""
            {
              "source": "legacy",
              "owner": {"kind": "object", "objectIndex": 0, "objectID": 9},
              "targetPath": [{"key": {"_0": "origin"}}],
              "properties": {},
              "authoredValue": {"string": {"_0": "0 0 0"}},
              "valueType": "string"
            }
            """.utf8)
        )
        let invalidAuthoredDocument: [String: Any] = [
            "objects": [
                [
                    "id": 999,
                    "origin": [
                        "script": "fixture-invalid-authored",
                        "value": Date(),
                    ],
                ] as [String: Any],
            ],
        ]
        let invalidAuthored = SceneScriptBindingIRParser.parse(
            document: invalidAuthoredDocument
        )
        let invalidAuthoredEvidence = SceneScriptSourceEvidenceCollector.collect(
            document: invalidAuthoredDocument
        )
        let mixedArrayDocument: [String: Any] = [
            "objects": [
                ["malformed", ["script": "fixture-mixed-object"]],
                [
                    "id": 700,
                    "effects": [
                        ["malformed", ["script": "fixture-mixed-effect"]],
                        [
                            "id": 701,
                            "passes": [
                                ["malformed", ["script": "fixture-mixed-pass"]],
                                [
                                    "id": 702,
                                    "metadata": [
                                        "script": "fixture-valid-after-mixed"
                                    ],
                                ],
                            ],
                        ],
                    ],
                ],
            ],
        ]
        let mixedArrayEvidence = SceneScriptSourceEvidenceCollector.collect(
            document: mixedArrayDocument
        )
        let payload = Payload(
            bindings: document.scriptBindings.map(BindingPayload.init),
            diagnostics: document.scriptBindingDiagnostics.map(DiagnosticPayload.init),
            sourceEvidence: document.scriptSourceEvidence.map(SourceEvidencePayload.init),
            invalidAuthoredBindingCount: invalidAuthored.bindings.count,
            invalidAuthoredDiagnostics:
                invalidAuthored.diagnostics.map(DiagnosticPayload.init),
            invalidAuthoredSourceEvidence:
                invalidAuthoredEvidence.map(SourceEvidencePayload.init),
            mixedArraySourceEvidence:
                mixedArrayEvidence.map(SourceEvidencePayload.init),
            legacyWrapperKeysMissing: legacyIR.wrapperKeys == nil
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        print(String(decoding: try encoder.encode(payload), as: UTF8.self))
    }
}
