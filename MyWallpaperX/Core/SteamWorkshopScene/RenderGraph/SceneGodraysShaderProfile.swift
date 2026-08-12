import CryptoKit
import Foundation

/// Godrays 的两组完整 shader 指纹。profile 只在四个 shader contract 全部精确匹配时成立。
nonisolated enum SceneGodraysShaderProfile {
    case stock2842
    case directionalV1

    private struct StageFingerprint {
        let kind: SceneShaderContract.StageKind
        let path: String
        let rawSHA256: String
    }

    private struct ShaderFingerprint {
        let identity: String
        let canonicalSHA256: String
        let stages: [StageFingerprint]
    }

    private struct ProfileFingerprint {
        let profile: SceneGodraysShaderProfile
        let shaders: [ShaderFingerprint]
    }

    nonisolated static func resolve(
        _ contracts: [SceneShaderContract]
    ) -> SceneGodraysShaderProfile? {
        let matches = profiles.filter { profile in
            profile.shaders.allSatisfy { expected in
                let contracts = contracts.filter {
                    normalized($0.identity) == expected.identity
                }
                guard contracts.count == 1, let contract = contracts.first,
                      contract.sourceKind == .authoredSource,
                      contract.diagnostics.isEmpty,
                      contract.canonicalSHA256 == expected.canonicalSHA256,
                      contract.stages.count == expected.stages.count
                else {
                    return false
                }
                return zip(contract.stages, expected.stages).allSatisfy {
                    stage, fingerprint in
                    stage.kind == fingerprint.kind
                        && normalized(stage.relativePath) == fingerprint.path
                        && stage.rawSHA256 == fingerprint.rawSHA256
                        && sha256(Data(stage.source.utf8)) == fingerprint.rawSHA256
                }
            }
        }
        return matches.count == 1 ? matches[0].profile : nil
    }

    private nonisolated static let profiles = [
        ProfileFingerprint(
            profile: .stock2842,
            shaders: [
                shader(
                    "effects/godrays_downsample2",
                    "02ccdadd4e8a13ff7c96827de4a0a16b0aeed2a2557f9059555a4210b56cefd0",
                    "godrays_downsample2",
                    "da20834a9c4985ffb9035b6373d2d77279831d8340a125b6d1a50dffb735601b",
                    "f4cf3742456be482a345e17a1a9bd514d9df5d07e46b2be7d93e30f1e5dd3ab6"
                ),
                shader(
                    "effects/godrays_cast",
                    "82acb5faa8bdb62a64a6482032ce1ef39f36841711d3bedfc0d075f0aae57f7f",
                    "godrays_cast",
                    "47a9753f646d150399faf48b3334d9a2b52c0da3ed38634a2a57914ccd83dd0f",
                    "ca22b4a78b2536a77007fd6e4e27ee40b091b1be94e0fbaa367a1098d064d915"
                ),
                shader(
                    "effects/godrays_gaussian",
                    "7d6537722cb496626b1e834c2e2f3b77e3baf30054eb30b63d959cfe22ec18d9",
                    "godrays_gaussian",
                    "f584b60cf58ff02e768c543bc93743280c4d169802ce798b00e5acb99f3a24be",
                    "be030fe8a6375b4d8856028d070ab692f6efb18cb4184cbd01a059d4de18a644"
                ),
                shader(
                    "effects/godrays_combine",
                    "c4d40bf0fba608b75737ee929db07645be86535cfc4e7e3f3145498f7e8c821d",
                    "godrays_combine",
                    "cd0636f15ff19225b5cbf10af006f9fe43d99c9b782baeb1dbfe62c507816fad",
                    "c4bf993a2176152b0482b04818b2f6d02f2f52018e1c160463b540ede9c0cd1b"
                ),
            ]
        ),
        ProfileFingerprint(
            profile: .directionalV1,
            shaders: [
                shader(
                    "effects/godrays_downsample2",
                    "37b1d9ed839f3b66846054999a8fd1122f0b77932cc439f0c2abc9950cf58c86",
                    "godrays_downsample2",
                    "4b2a12f89ffbddad5f6bd6e3d3d805194f353005b0d45a6fe6f65eb9666e0e76",
                    "15840f175ff02f3675bb5d9821671f544fbc56afcc1e0005cab7742b3f0c2b80"
                ),
                shader(
                    "effects/godrays_cast",
                    "2c51f20d40c366902a9205222062b787eb2ff2e2d187e3f0ec4ed93c89b2e019",
                    "godrays_cast",
                    "47a9753f646d150399faf48b3334d9a2b52c0da3ed38634a2a57914ccd83dd0f",
                    "002b74ef5a2e9df8a8d341b550a6a0589abee8328e53a712bca81435ddf172ed"
                ),
                shader(
                    "effects/godrays_gaussian",
                    "75a88386248e3e1995b31a5af99b4a04ab1738e69ed41b45b3c55530b46e4b2c",
                    "godrays_gaussian",
                    "2dd9ea4aa249da323c04da933cc170ecdd68ae60a94ab55dfc5e95c24e6c007e",
                    "ad060b8decd09d2eea9ab733b4e55d7ad51e9b617618fc06069a2ac3b2b0df63"
                ),
                shader(
                    "effects/godrays_combine",
                    "a539aa3325bb479c7bb41c4566fdf3a7c917f4097cda99593e5667cfe27eadc1",
                    "godrays_combine",
                    "411d41b5b01173fdf4eca49d1280a8e468afb1b9c49f7e1128abde81cc50f0f7",
                    "6e5f78c5befcb092db0866e9c4b879ec25238ba57d3fa3e7f571934bee8221af"
                ),
            ]
        ),
    ]

    private nonisolated static func shader(
        _ identity: String,
        _ canonicalSHA256: String,
        _ basename: String,
        _ vertexSHA256: String,
        _ fragmentSHA256: String
    ) -> ShaderFingerprint {
        ShaderFingerprint(
            identity: identity,
            canonicalSHA256: canonicalSHA256,
            stages: [
                .init(
                    kind: .vertex,
                    path: "shaders/effects/\(basename).vert",
                    rawSHA256: vertexSHA256
                ),
                .init(
                    kind: .fragment,
                    path: "shaders/effects/\(basename).frag",
                    rawSHA256: fragmentSHA256
                ),
            ]
        )
    }

    private nonisolated static func normalized(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "/").lowercased()
    }

    private nonisolated static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
