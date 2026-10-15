import Foundation
import CryptoKit

// Only unused shader/domain surroundings are value fixtures. Cache and its
// persistent support compile from production source; this is an IO/wire gate,
// not analyzer, variant-consumer, or renderer acceptance.
// Legacy JSONs in variant_analysis_v22 were written once by the unmodified
// v22 owner b4306295…256f, binary99c7a1ae…fe93, from self-authored comment
// shader strings. They contain no Workshop sources or media.
enum SceneGenericShaderProgramArtifact {
    static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
enum SceneResolvedMaterialShaderSchema { struct Sampler {} }
struct ScenePersistentSamplerRecord: Codable {
    let slot: Int
    var canonicalSortKey: String { "unused" }
    init(sampler: SceneResolvedMaterialShaderSchema.Sampler) { slot = 0 }
    func rebuild() -> SceneResolvedMaterialShaderSchema.Sampler? { nil }
}
struct SceneAuthoredShaderRuntimeLoopBounds: Codable {
    let vertex: [String: Int]
    let fragment: [String: Int]
    static let none = Self(vertex: [:], fragment: [:])
}
enum SceneShaderColorTransfer: Codable { case passthrough(textureSlot: Int) }
enum SceneShaderCompatibilityTarget: String { case fixture }
enum SceneAuthoredEffectRenderPlan { struct TextureIdentity {} }
enum SceneResolvedMaterialTemplate {
    struct UniformDeclaration { let name: String; let value: Int }
}
enum SceneMaterialDemandAnalysisPersistentCache {
    static func uniformValue(_ value: Int) -> String { String(value) }
}
typealias SceneAuthoredShaderSpatialWeightedColorBlendFact = SceneResolvedMaterialVariantAnalysisCache.SpatialWeightedColorBlendMirror
enum SceneAuthoredShaderGeneratedStraightRGBAAnalyzer {
    typealias SourceCarriedFact = SceneResolvedMaterialVariantAnalysisCache.SourceCarriedRGBAMirror
    typealias SourceCarriedTransfer = SourceCarriedFact.Transfer
    typealias SourceCarriedShape = SourceCarriedFact.Shape
}
enum SceneAuthoredShaderConditionalGeneratedRGBAnalyzer {
    struct Fact {
        let alphaCarrierSlot: Int
        let generatedOpaqueColorSlots: Set<Int>
        let scalarRedSlots: Set<Int>
        let scalarGreenSlots: Set<Int>
        let scalarBlueSlots: Set<Int>
        let scalarAlphaSlots: Set<Int>
        let sampleCallCounts: [Int: Int]
        let generatedSampleCallCounts: [Int: Int]
        let scalarRedSampleCallCounts: [Int: Int]
        let scalarGreenSampleCallCounts: [Int: Int]
        let scalarBlueSampleCallCounts: [Int: Int]
        let scalarAlphaSampleCallCounts: [Int: Int]
    }
}
struct SceneAuthoredShaderSameAlphaReconstructedRGBFilterFact {
    let sourceSlot: Int
    let sourceSampleCallCounts: [Int: Int]
    let dataSampleCallCounts: [Int: [Int: Int]]
    let preservesSnapshotAlpha: Bool
    var auxiliarySlots: Set<Int> { Set(dataSampleCallCounts.keys) }
}
typealias SceneAuthoredShaderNeutralTextureResolutionFact = SceneResolvedMaterialVariantAnalysisCache.NeutralTextureResolutionMirror
typealias SceneAuthoredShaderAlphaAttenuationFact = SceneResolvedMaterialVariantAnalysisCache.AuxiliaryRedCarrierMirror
typealias SceneAuthoredShaderGraphInputColorBlendFact = SceneResolvedMaterialVariantAnalysisCache.ColorBlendCarrierMirror
enum SceneAuthoredShaderPreviousBlurredCompositeAnalyzer {
    typealias Fact = SceneResolvedMaterialVariantAnalysisCache.PreviousBlurredCompositeShapeMirror
}
enum SceneShaderTextureFormat: String { case fixture }

private typealias Cache = SceneResolvedMaterialVariantAnalysisCache
private var checks: [String: Bool] = [:]

private func record() -> Cache.Record {
    .init(canonicalVertex: "// self-authored vertex", canonicalFragment: "// self-authored fragment",
        activeSamplerNames: ["g_B", "g_A"], resolvedIntegerCombos: ["B": 2, "A": 1],
        sourceActiveSamplers: [:], runtimeLoopBounds: .none,
        sourceColorTransfer: .passthrough(textureSlot: 0),
        rgba8UnormAccumulatorSourceSlot: nil, spatialWeightedColorBlend: nil,
        sourceCarriedRGBA: .init(sourceSlot: 0, transfer: .straight, shape: .existing,
            auxiliaryDataSlots: [7, 2, 6, 1, 5, 3, 4]),
        conditionalGeneratedRGB: .init(alphaCarrierSlot: 0,
            generatedOpaqueColorSlots: [7, 1, 3], scalarRedSlots: [6, 2],
            scalarGreenSlots: [5, 1], scalarBlueSlots: [4, 2], scalarAlphaSlots: [7, 5]),
        sameAlphaReconstructedRGB: .init(sourceSlot: 0, auxiliarySlots: [5, 2],
            preservesSnapshotAlpha: true), neutralTextureResolution: nil,
        alphaAttenuationFact: .init(sourceSlot: 0, auxiliaryRedSlots: [7, 2]),
        colorBlendFact: .init(sourceSlot: 0, auxiliaryRedSlots: [6, 1], alphaOutput: .preserved),
        previousBlurredCompositeFact: nil)
}

private func file(_ root: URL, _ key: String) -> URL {
    root.appendingPathComponent("SceneVariantAnalysis-v22").appendingPathComponent(key + ".json")
}
private func object(_ bytes: Data) throws -> [String: Any] {
    try JSONSerialization.jsonObject(with: bytes) as! [String: Any]
}
private func encoded(_ value: [String: Any]) throws -> Data {
    try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .withoutEscapingSlashes])
}
private struct Snapshot: Equatable {
    let bytes: Data
    let modified: Date?
    let fileNumber: UInt64?
    init(_ url: URL) throws {
        bytes = try Data(contentsOf: url)
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        modified = attributes[.modificationDate] as? Date
        fileNumber = (attributes[.systemFileNumber] as? NSNumber)?.uint64Value
    }
}
private func readOnlyLoad(_ root: URL, _ key: String) throws -> Cache.Record? {
    let url = file(root, key), before = try Snapshot(file(root, key))
    let result = Cache.load(keySHA256: key)
    checks[key + "-read-only"] = try Snapshot(url) == before
    return result
}

private func legacy(_ root: URL) throws {
    for (key, slots) in [("control-singleton", Set([1])), ("multi-seven", Set(1...7))] {
        let value = try readOnlyLoad(root, key)
        checks[key + "-legacy-loaded"] = value?.sourceCarriedRGBA?.auxiliaryDataSlots == slots
    }
}

private func cold(_ root: URL, write: Bool) throws {
    let key = "all-set-mirrors"
    if write {
        checks["load-miss-no-directory"] = Cache.load(keySHA256: key) == nil
            && !FileManager.default.fileExists(atPath: file(root, key).deletingLastPathComponent().path)
        Cache.store(record: record(), keySHA256: key)
    }
    let value = try readOnlyLoad(root, key)
    checks["all-set-mirrors"] = value?.sourceCarriedRGBA?.auxiliaryDataSlots == Set(1...7)
        && value?.conditionalGeneratedRGB?.generatedOpaqueColorSlots == [1, 3, 7]
        && value?.conditionalGeneratedRGB?.scalarRedSlots == [2, 6]
        && value?.conditionalGeneratedRGB?.scalarGreenSlots == [1, 5]
        && value?.conditionalGeneratedRGB?.scalarBlueSlots == [2, 4]
        && value?.conditionalGeneratedRGB?.scalarAlphaSlots == [5, 7]
        && value?.sameAlphaReconstructedRGB?.auxiliarySlots == [2, 5]
        && value?.alphaAttenuationFact?.auxiliaryRedSlots == [2, 7]
        && value?.colorBlendFact?.auxiliaryRedSlots == [1, 6]
    let payload = try object(Data(contentsOf: file(root, key)))["payload"] as! [String: Any]
    let sets: [(String, String, [Int])] = [
        ("sourceCarriedRGBA", "auxiliaryDataSlots", Array(1...7)),
        ("conditionalGeneratedRGB", "generatedOpaqueColorSlots", [1, 3, 7]),
        ("conditionalGeneratedRGB", "scalarRedSlots", [2, 6]),
        ("conditionalGeneratedRGB", "scalarGreenSlots", [1, 5]),
        ("conditionalGeneratedRGB", "scalarBlueSlots", [2, 4]),
        ("conditionalGeneratedRGB", "scalarAlphaSlots", [5, 7]),
        ("sameAlphaReconstructedRGB", "auxiliarySlots", [2, 5]),
        ("alphaAttenuationFact", "auxiliaryRedSlots", [2, 7]),
        ("colorBlendFact", "auxiliaryRedSlots", [1, 6])]
    for (name, field, expected) in sets {
        checks[name + "-" + field + "-sorted-wire"] =
            (payload[name] as? [String: Any])?[field] as? [Int] == expected
    }
}

private func orderedWire(_ root: URL) throws {
    let key = "ordered-combos"
    Cache.store(record: record(), keySHA256: key)
    let url = file(root, key)
    var envelope = try object(Data(contentsOf: url))
    var payload = envelope["payload"] as! [String: Any]
    let pairs = payload["resolvedIntegerCombos"] as! [[String: Any]]
    payload["resolvedIntegerCombos"] = Array(pairs.reversed())
    envelope["payload"] = payload
    envelope["recordSHA256"] = SceneGenericShaderProgramArtifact.sha256(try encoded(payload))
    try encoded(envelope).write(to: url)
    // This is a typed ordered wire array, not a Set field. Its original order
    // must survive verification even though the runtime rebuild is a dictionary.
    let value = try readOnlyLoad(root, key)
    checks["ordered-nonset-wire-valid"] = value?.resolvedIntegerCombos == ["A": 1, "B": 2]
}

private func invalidWire(_ root: URL) throws {
    let key = "invalid"
    Cache.store(record: record(), keySHA256: key)
    let url = file(root, key), original = try Data(contentsOf: file(root, key))
    let mutations: [(String, (inout [String: Any]) -> Void)] = [
        ("digest", { $0["recordSHA256"] = "foreign" }),
        ("version", { $0["schemaVersion"] = 999 }),
        ("key", { $0["keySHA256"] = "foreign" }),
        ("payload", { envelope in
            var payload = envelope["payload"] as! [String: Any]
            payload["canonicalFragment"] = "// changed without updating digest"
            envelope["payload"] = payload
        })]
    for (name, mutate) in mutations {
        var envelope = try object(original)
        mutate(&envelope)
        try encoded(envelope).write(to: url)
        let before = try Snapshot(url)
        checks[name + "-safe-miss"] = Cache.load(keySHA256: key) == nil
        checks[name + "-load-no-write"] = try Snapshot(url) == before
    }
    try Data([0xff, 0x00]).write(to: url)
    let before = try Snapshot(url)
    checks["corrupt-safe-miss"] = Cache.load(keySHA256: key) == nil
    checks["corrupt-load-no-write"] = try Snapshot(url) == before
}

@main
enum VariantCacheWireChecks {
    static func main() throws {
        let root = URL(fileURLWithPath: ProcessInfo.processInfo.environment["MWX_SCENE_GENERIC_SHADER_CACHE"]!)
        switch CommandLine.arguments[1] {
        case "legacy": try legacy(root)
        case "cold-write": try cold(root, write: true)
        case "cold-read": try cold(root, write: false)
        case "ordered-wire": try orderedWire(root)
        case "invalid-wire": try invalidWire(root)
        default: throw NSError(domain: "unknown wire mode", code: 1)
        }
        print(String(decoding: try JSONSerialization.data(withJSONObject: checks, options: [.sortedKeys]), as: UTF8.self))
        if checks.isEmpty || checks.values.contains(false) { exit(1) }
    }
}
