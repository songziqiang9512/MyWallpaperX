import CryptoKit
import Foundation
import simd

extension SceneAuthoredWorkshopSimpleAudioBarsPlanner {
    nonisolated struct CanonicalShaderPayload: Encodable {
        let identity: String
        let sourceKind: SceneShaderContract.SourceKind
        let stages: [SceneShaderContract.Stage]
        let diagnostics: [SceneShaderContract.Diagnostic]
    }

    nonisolated static func profile(
        from authored: [String: Int]
    ) -> Parameters.Profile? {
        let allowed = Set([
            "SHAPE", "TRANSPARENCY", "RESOLUTION", "BLENDMODE",
            "A_SMOOTH_CURVE", "ANTIALIAS", "CLIP_LOW", "CLIP_HIGH",
        ])
        var values: [String: Int] = [:]
        for (key, value) in authored {
            let normalizedKey = key.uppercased()
            guard allowed.contains(normalizedKey),
                  values.updateValue(value, forKey: normalizedKey) == nil else {
                return nil
            }
        }
        let normalizedValues = (
            shape: values["SHAPE", default: 0],
            transparency: values["TRANSPARENCY", default: 1],
            resolution: values["RESOLUTION", default: 32],
            blendMode: values["BLENDMODE", default: 0],
            smoothCurve: values["A_SMOOTH_CURVE", default: 0],
            antialias: values["ANTIALIAS", default: 0],
            clipLow: values["CLIP_LOW", default: 0],
            clipHigh: values["CLIP_HIGH", default: 0]
        )
        guard normalizedValues.shape == 0,
              normalizedValues.transparency == 1,
              normalizedValues.blendMode == 0,
              normalizedValues.smoothCurve == 0,
              normalizedValues.antialias == 0 else {
            return nil
        }
        switch (
            normalizedValues.resolution,
            normalizedValues.clipLow,
            normalizedValues.clipHigh
        ) {
        case (32, 1, 0): return .bottomReplace32ClipLow
        case (64, 0, 1): return .bottomReplace64ClipHigh
        default: return nil
        }
    }

    nonisolated static func parameters(
        from authored: [String: SceneDocument.ShaderValue],
        effectKey: Graph.EffectKey,
        profile: Parameters.Profile
    ) -> Parameters? {
        var values: [String: SceneDocument.ShaderValue] = [:]
        for (key, value) in authored {
            guard expectedConstantNames.contains(key.lowercased()),
                  values.updateValue(value, forKey: key.lowercased()) == nil else {
                return nil
            }
        }
        guard let countValue = scalar(values["bar count"], kind: "number"),
              countValue.rounded() == countValue,
              (1.0 ... 200.0).contains(countValue),
              let color = color(values["bar color"], effectKey: effectKey),
              let spacing = scalar(values["bar spacing"], kind: "number"),
              abs(spacing - 0.30000001) <= 0.000_001,
              let bounds = vector(
                  values["lower/upper bar bounds"],
                  count: 2,
                  kind: "vector"
              ),
              0 <= bounds[0], bounds[0] < bounds[1], bounds[1] <= 1,
              let opacity = scalar(
                  values["ui_editor_properties_opacity"],
                  kind: "number"
              ),
              (0 ... 1).contains(opacity),
              inactiveVector(values["circle start/end angles"], count: 2),
              inactiveVector(values["anti-alias blurring"], count: 2) else {
            return nil
        }
        return Parameters(
            profile: profile,
            barCount: Int(countValue),
            staticOrFallbackColor: color.value,
            colorBinding: color.binding,
            barSpacing: Float(spacing),
            lowerBound: Float(bounds[0]),
            upperBound: Float(bounds[1]),
            opacity: Float(opacity)
        )
    }

    private nonisolated static func color(
        _ value: SceneDocument.ShaderValue?,
        effectKey: Graph.EffectKey
    ) -> (
        value: SIMD3<Float>,
        binding: SceneWorkshopAudioBarsExecutionPlan.ConstantBinding
    )? {
        guard let value,
              value.valueKind.lowercased() == "binding",
              let propertyKey = value.userBinding?.trimmingCharacters(
                  in: .whitespacesAndNewlines
              ),
              !propertyKey.isEmpty,
              let components = value.components,
              components.count == 3,
              components.allSatisfy({ $0.isFinite && (0 ... 1).contains($0) }) else {
            return nil
        }
        return (
            SIMD3(Float(components[0]), Float(components[1]), Float(components[2])),
            .init(
                propertyKey: propertyKey,
                layerID: effectKey.layerID,
                effectIndex: effectKey.effectIndex,
                passIndex: 0,
                constantName: "bar color"
            )
        )
    }

    private nonisolated static func scalar(
        _ value: SceneDocument.ShaderValue?,
        kind: String
    ) -> Double? {
        guard let value,
              value.valueKind.lowercased() == kind,
              value.userBinding == nil,
              let components = value.components,
              components.count == 1,
              let component = components.first,
              component.isFinite else {
            return nil
        }
        return component
    }

    private nonisolated static func vector(
        _ value: SceneDocument.ShaderValue?,
        count: Int,
        kind: String
    ) -> [Double]? {
        guard let value,
              value.valueKind.lowercased() == kind,
              value.userBinding == nil,
              let components = value.components,
              components.count == count,
              components.allSatisfy(\.isFinite) else {
            return nil
        }
        return components
    }

    private nonisolated static func inactiveVector(
        _ value: SceneDocument.ShaderValue?,
        count: Int
    ) -> Bool {
        guard let value else { return true }
        return value.valueKind.lowercased() == "vector"
            && value.userBinding == nil
            && value.components?.count == count
            && value.components?.allSatisfy(\.isFinite) == true
    }

    nonisolated static func shaderContractMatches(
        _ contracts: [SceneShaderContract]
    ) -> Bool {
        let matches = contracts.filter { normalized($0.identity) == shaderIdentity }
        guard matches.count == 1, let contract = matches.first,
              contract.sourceKind == .authoredSource,
              contract.diagnostics.isEmpty,
              contract.canonicalSHA256 == shaderCanonicalSHA256,
              canonicalHash(contract) == shaderCanonicalSHA256,
              contract.stages.count == 2 else {
            return false
        }
        let expected: [(SceneShaderContract.StageKind, String, String)] = [
            (.vertex, vertexPath, vertexSHA256),
            (.fragment, fragmentPath, fragmentSHA256),
        ]
        return zip(contract.stages, expected).allSatisfy { stage, fingerprint in
            stage.kind == fingerprint.0
                && normalized(stage.relativePath) == fingerprint.1
                && stage.rawSHA256 == fingerprint.2
                && sha256(Data(stage.source.utf8)) == fingerprint.2
        }
    }

    private nonisolated static func canonicalHash(
        _ contract: SceneShaderContract
    ) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let payload = CanonicalShaderPayload(
            identity: contract.identity,
            sourceKind: contract.sourceKind,
            stages: contract.stages,
            diagnostics: contract.diagnostics
        )
        guard let data = try? encoder.encode(payload) else { return "" }
        return sha256(data)
    }

    nonisolated static func effectOutput(
        _ effect: Graph.EffectKey
    ) -> Graph.TextureIdentity {
        .init(kind: .effectOutput, layerID: effect.layerID, effect: effect, name: nil)
    }

    nonisolated static func normalized(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "/").lowercased()
    }

    private nonisolated static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    nonisolated static let definitionPath =
        "effects/workshop/2084198056/simple_audio_bars/effect.json"
    nonisolated static let materialPath =
        "materials/workshop/2084198056/effects/simple_audio_bars.json"
    nonisolated static let materialPassID = "\(materialPath)#0"
    nonisolated static let materialSHA256 =
        "a283c6fa4cda8c6c91f2e8a737f9c42739473bbd900a0590b50458088b390de9"
    nonisolated static let shaderIdentity =
        "workshop/2084198056/effects/simple_audio_bars"
    nonisolated static let dependencies = [
        materialPath,
        "shaders/workshop/2084198056/effects/simple_audio_bars.frag",
        "shaders/workshop/2084198056/effects/simple_audio_bars.vert",
    ]
    private nonisolated static let shaderCanonicalSHA256 =
        "75c498bcb6c5faaead0b223902fec61bb5b57043f1fbcd2b51e098a663299f00"
    private nonisolated static let vertexPath =
        "shaders/workshop/2084198056/effects/simple_audio_bars.vert"
    private nonisolated static let vertexSHA256 =
        "cbe7c41f414468a69ff24a92007dfaa9139a7f5a8c0cd804375339a73e16fe60"
    private nonisolated static let fragmentPath =
        "shaders/workshop/2084198056/effects/simple_audio_bars.frag"
    private nonisolated static let fragmentSHA256 =
        "65ce71ebbfcc4ba450e540336262dce3e9580cd90c4157e5f21205bedcc64493"
    private nonisolated static let expectedConstantNames = Set([
        "anti-alias blurring",
        "bar color",
        "bar count",
        "bar spacing",
        "circle start/end angles",
        "lower/upper bar bounds",
        "ui_editor_properties_opacity",
    ])
}
