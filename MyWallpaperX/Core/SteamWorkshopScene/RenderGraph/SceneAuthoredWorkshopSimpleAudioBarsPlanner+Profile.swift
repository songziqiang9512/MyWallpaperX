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
        from authored: [String: Int],
        revision: AssetContract.Revision
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
        guard normalizedValues.smoothCurve == 0 else {
            return nil
        }
        switch revision {
        case .originalFragmentC:
            guard normalizedValues.shape == 0,
                  normalizedValues.transparency == 1,
                  normalizedValues.blendMode == 0,
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
        case .relocatedLegacy:
            guard normalizedValues.shape == 9,
                  normalizedValues.transparency == 4,
                  normalizedValues.resolution == 16,
                  normalizedValues.blendMode == 31,
                  normalizedValues.antialias == 1,
                  normalizedValues.clipLow == 0,
                  normalizedValues.clipHigh == 0 else {
                return nil
            }
            return .stereoUpDown16IntersectAdd
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
              let bounds = vector(
                  values["lower/upper bar bounds"],
                  count: 2,
                  kind: "vector"
              ),
              0 <= bounds[0], bounds[0] < bounds[1], bounds[1] <= 1,
              inactiveVector(values["circle start/end angles"], count: 2) else {
            return nil
        }
        let opacity: (
            value: Double,
            binding: SceneWorkshopAudioBarsExecutionPlan.ConstantBinding?
        )
        let antiAliasSmoothing: SIMD2<Float>
        switch profile {
        case .bottomReplace32ClipLow, .bottomReplace64ClipHigh:
            guard abs(spacing - 0.30000001) <= 0.000_001,
                  let staticOpacity = scalar(
                      values["ui_editor_properties_opacity"],
                      kind: "number"
                  ),
                  (0 ... 1).contains(staticOpacity),
                  inactiveVector(values["anti-alias blurring"], count: 2) else {
                return nil
            }
            opacity = (staticOpacity, nil)
            antiAliasSmoothing = .zero
        case .stereoUpDown16IntersectAdd:
            guard countValue == 35,
                  abs(spacing - 0.5) <= 0.000_001,
                  abs(bounds[0]) <= 0.000_001,
                  abs(bounds[1] - 0.5) <= 0.000_001,
                  let authoredOpacity = boundScalar(
                      values["ui_editor_properties_opacity"],
                      effectKey: effectKey,
                      constantName: "ui_editor_properties_opacity"
                  ),
                  let smoothing = vector(
                      values["anti-alias blurring"],
                      count: 2,
                      kind: "vector"
                  ),
                  smoothing.allSatisfy({ abs($0 - 0.05) <= 0.000_001 }) else {
                return nil
            }
            opacity = authoredOpacity
            antiAliasSmoothing = SIMD2(0.05, 0.05)
        }
        return Parameters(
            profile: profile,
            barCount: Int(countValue),
            staticOrFallbackColor: color.value,
            colorBinding: color.binding,
            barSpacing: Float(spacing),
            lowerBound: Float(bounds[0]),
            upperBound: Float(bounds[1]),
            opacity: Float(opacity.value),
            opacityBinding: opacity.binding,
            antiAliasSmoothing: antiAliasSmoothing
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

    private nonisolated static func boundScalar(
        _ value: SceneDocument.ShaderValue?,
        effectKey: Graph.EffectKey,
        constantName: String
    ) -> (
        value: Double,
        binding: SceneWorkshopAudioBarsExecutionPlan.ConstantBinding
    )? {
        guard let value,
              value.valueKind.lowercased() == "binding",
              let propertyKey = value.userBinding?.trimmingCharacters(
                  in: .whitespacesAndNewlines
              ),
              !propertyKey.isEmpty,
              let components = value.components,
              components.count == 1,
              let component = components.first,
              component.isFinite,
              (0 ... 1).contains(component) else {
            return nil
        }
        return (
            component,
            .init(
                propertyKey: propertyKey,
                layerID: effectKey.layerID,
                effectIndex: effectKey.effectIndex,
                passIndex: 0,
                constantName: constantName
            )
        )
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
        _ contracts: [SceneShaderContract],
        assets: AssetContract
    ) -> Bool {
        let matches = contracts.filter {
            normalized($0.identity) == assets.shaderIdentity
        }
        guard matches.count == 1, let contract = matches.first,
              contract.sourceKind == .authoredSource,
              contract.diagnostics.isEmpty,
              canonicalHash(contract) == contract.canonicalSHA256,
              assets.canonicalSHA256.map({
                  contract.canonicalSHA256 == $0
              }) ?? true,
              contract.stages.count == 2 else {
            return false
        }
        let expected: [(SceneShaderContract.StageKind, String, String)] = [
            (.vertex, assets.vertexPath, assets.vertexSHA256),
            (.fragment, assets.fragmentPath, assets.fragmentSHA256),
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

    nonisolated static func assetContract(
        forDefinitionPath path: String
    ) -> AssetContract? {
        let normalizedPath = normalized(path)
        let effectsPrefix = "effects/"
        let definitionTail =
            "workshop/2084198056/simple_audio_bars/effect.json"
        guard normalizedPath.hasPrefix(effectsPrefix) else { return nil }
        let relative = String(normalizedPath.dropFirst(effectsPrefix.count))
        guard relative.hasSuffix(definitionTail) else { return nil }
        let namespace = String(relative.dropLast(definitionTail.count))
        let revision: AssetContract.Revision
        if namespace.isEmpty {
            revision = .originalFragmentC
        } else {
            let components = namespace.split(
                separator: "/",
                omittingEmptySubsequences: true
            )
            guard components.count == 2,
                  components[0] == "workshop",
                  !components[1].isEmpty,
                  components[1].allSatisfy(\.isNumber) else {
                return nil
            }
            revision = .relocatedLegacy
        }

        let assetRoot = "\(namespace)workshop/2084198056"
        let materialPath =
            "materials/\(assetRoot)/effects/simple_audio_bars.json"
        let shaderIdentity =
            "\(assetRoot)/effects/simple_audio_bars"
        let vertexPath =
            "shaders/\(assetRoot)/effects/simple_audio_bars.vert"
        let fragmentPath =
            "shaders/\(assetRoot)/effects/simple_audio_bars.frag"
        return AssetContract(
            revision: revision,
            definitionPath: normalizedPath,
            materialPath: materialPath,
            materialPassID: "\(materialPath)#0",
            materialSHA256: revision == .originalFragmentC
                ? originalMaterialSHA256
                : nil,
            shaderIdentity: shaderIdentity,
            dependencies: [materialPath, fragmentPath, vertexPath],
            vertexPath: vertexPath,
            vertexSHA256: vertexSHA256,
            fragmentPath: fragmentPath,
            fragmentSHA256: revision == .originalFragmentC
                ? originalFragmentSHA256
                : relocatedFragmentSHA256,
            canonicalSHA256: revision == .originalFragmentC
                ? originalShaderCanonicalSHA256
                : nil
        )
    }

    private nonisolated static let originalMaterialSHA256 =
        "a283c6fa4cda8c6c91f2e8a737f9c42739473bbd900a0590b50458088b390de9"
    private nonisolated static let originalShaderCanonicalSHA256 =
        "75c498bcb6c5faaead0b223902fec61bb5b57043f1fbcd2b51e098a663299f00"
    private nonisolated static let vertexSHA256 =
        "cbe7c41f414468a69ff24a92007dfaa9139a7f5a8c0cd804375339a73e16fe60"
    private nonisolated static let originalFragmentSHA256 =
        "65ce71ebbfcc4ba450e540336262dce3e9580cd90c4157e5f21205bedcc64493"
    private nonisolated static let relocatedFragmentSHA256 =
        "3ef3b5682caa3779d2b90520e77e1c6fffd28aeaafbb206eadc736830df79020"
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
