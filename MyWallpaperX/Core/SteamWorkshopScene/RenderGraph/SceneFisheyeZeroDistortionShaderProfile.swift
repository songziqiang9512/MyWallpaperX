import CryptoKit
import Foundation

/// Exact stock shader contract admitted by the bounded zero-distortion Fisheye backend.
nonisolated enum SceneFisheyeZeroDistortionShaderProfile: Equatable {
    case stock

    private struct CanonicalShaderPayload: Encodable {
        let identity: String
        let sourceKind: SceneShaderContract.SourceKind
        let stages: [SceneShaderContract.Stage]
        let diagnostics: [SceneShaderContract.Diagnostic]
    }

    nonisolated static func resolve(
        _ contracts: [SceneShaderContract]
    ) -> SceneFisheyeZeroDistortionShaderProfile? {
        let matches = contracts.filter { normalized($0.identity) == shaderIdentity }
        guard matches.count == 1,
              let contract = matches.first,
              contract.sourceKind == .authoredSource,
              contract.diagnostics.isEmpty,
              contract.canonicalSHA256 == canonicalSHA256,
              canonicalHash(contract) == canonicalSHA256,
              contract.stages.count == 2 else {
            return nil
        }
        let expected: [(SceneShaderContract.StageKind, String, String)] = [
            (.vertex, vertexPath, vertexSHA256),
            (.fragment, fragmentPath, fragmentSHA256),
        ]
        guard zip(contract.stages, expected).allSatisfy({ stage, fingerprint in
            stage.kind == fingerprint.0
                && normalized(stage.relativePath) == fingerprint.1
                && stage.rawSHA256 == fingerprint.2
                && sha256(Data(stage.source.utf8)) == fingerprint.2
        }) else {
            return nil
        }
        return .stock
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

    private nonisolated static func normalized(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "/").lowercased()
    }

    private nonisolated static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private nonisolated static let shaderIdentity = "effects/fisheye"
    private nonisolated static let canonicalSHA256 =
        "4b3aefcf2a7a96a5180d064925b8246fe073e0c1f6ff4c1a4b2b002fb97d94c2"
    private nonisolated static let vertexPath = "shaders/effects/fisheye.vert"
    private nonisolated static let vertexSHA256 =
        "0b346bf8e6d1fb2aafee37d80d46ec4821c08d3fc62b11c42b23112a4b8739cb"
    private nonisolated static let fragmentPath = "shaders/effects/fisheye.frag"
    private nonisolated static let fragmentSHA256 =
        "45194dc82dbb7e4114ccd4632b92510430c7658f57f6d1c9377a629d2a2d1fe1"
}
