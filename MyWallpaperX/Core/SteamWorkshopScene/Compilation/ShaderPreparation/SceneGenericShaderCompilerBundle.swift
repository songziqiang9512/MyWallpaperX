import Foundation
import Security

/// Resolves only the Developer-ID-signed helpers copied into this App bundle.
/// Environment variables and authored paths cannot replace these executables.
nonisolated enum SceneGenericShaderCompilerBundle {
    struct Limits: Decodable, Equatable {
        let maximumStageSourceBytes: Int
        let maximumDiagnosticBytes: Int
        let maximumArtifactBytes: Int
        let maximumResidentBytes: Int
        let timeoutMilliseconds: Int
    }

    struct Configuration {
        let backendID: String
        let glslang: URL
        let spirvCross: URL
        let glslangVersionProbe: String
        let glslangVersionProbeExitCode: Int32
        let spirvCrossVersionProbe: String
        let spirvCrossVersionProbeExitCode: Int32
        let limits: Limits
    }

    enum Failure: Error, Equatable {
        case licenseBundleUnavailable
        case manifestUnavailable
        case manifestInvalid
        case productExecutionUnauthorized
        case helperUnavailable(String)
        case helperInvalid(String)
        case helperSignatureInvalid(String)
    }

    private struct Manifest: Decodable {
        struct Helper: Decodable {
            let fileName: String
            let revision: String
            let versionProbeContains: String
            let versionProbeExitCode: Int32
            let sourceArtifactSHA256: String
        }

        struct Helpers: Decodable {
            let glslang: Helper
            let spirvCross: Helper
        }

        let schemaVersion: Int
        let backendID: String
        let productExecutionAuthorized: Bool
        let helpers: Helpers
        let limits: Limits
    }

    private static let expectedBackendID = "glslang-spirv-cross-msl-v2"
    private static let expectedTeamID = "H9QWU9XN8R"

    static func resolve(bundle: Bundle = .main) -> Result<Configuration, Failure> {
        guard let licenseBundleURL = bundle.url(
            forResource: "SceneShaderCompilerLicenses",
            withExtension: "bundle"
        ) else { return .failure(.licenseBundleUnavailable) }
        let manifestURL = licenseBundleURL
            .appendingPathComponent("Contents/Resources/product-manifest.json")
        guard let data = regularFileData(manifestURL) else {
            return .failure(.manifestUnavailable)
        }
        let manifest: Manifest
        do {
            manifest = try JSONDecoder().decode(Manifest.self, from: data)
        } catch {
            return .failure(.manifestInvalid)
        }
        guard valid(manifest) else { return .failure(.manifestInvalid) }
        guard manifest.productExecutionAuthorized else {
            return .failure(.productExecutionUnauthorized)
        }
        let helpersRoot = bundle.bundleURL
            .appendingPathComponent("Contents/Helpers", isDirectory: true)
            .standardizedFileURL
        let glslang = helpersRoot.appendingPathComponent(
            manifest.helpers.glslang.fileName,
            isDirectory: false
        )
        let spirvCross = helpersRoot.appendingPathComponent(
            manifest.helpers.spirvCross.fileName,
            isDirectory: false
        )
        for (name, url) in [("glslang", glslang), ("spirv-cross", spirvCross)] {
            guard validHelper(url, within: helpersRoot) else {
                return .failure(.helperUnavailable(name))
            }
            guard signedByProductTeam(url) else {
                return .failure(.helperSignatureInvalid(name))
            }
        }
        return .success(.init(
            backendID: manifest.backendID,
            glslang: glslang,
            spirvCross: spirvCross,
            glslangVersionProbe: manifest.helpers.glslang.versionProbeContains,
            glslangVersionProbeExitCode: manifest.helpers.glslang.versionProbeExitCode,
            spirvCrossVersionProbe: manifest.helpers.spirvCross.versionProbeContains,
            spirvCrossVersionProbeExitCode: manifest.helpers.spirvCross.versionProbeExitCode,
            limits: manifest.limits
        ))
    }

    private static func valid(_ manifest: Manifest) -> Bool {
        manifest.schemaVersion == 1
            && manifest.backendID == expectedBackendID
            && manifest.helpers.glslang.fileName == "glslang"
            && manifest.helpers.spirvCross.fileName == "spirv-cross"
            && manifest.helpers.glslang.revision.count == 40
            && manifest.helpers.spirvCross.revision.count == 40
            && manifest.helpers.glslang.sourceArtifactSHA256.count == 64
            && manifest.helpers.spirvCross.sourceArtifactSHA256.count == 64
            && (0 ... 1).contains(manifest.helpers.glslang.versionProbeExitCode)
            && (0 ... 1).contains(manifest.helpers.spirvCross.versionProbeExitCode)
            && (1_024 ... 4 * 1_024 * 1_024).contains(
                manifest.limits.maximumStageSourceBytes
            )
            && (1_024 ... 1_024 * 1_024).contains(
                manifest.limits.maximumDiagnosticBytes
            )
            && (1_024 ... 64 * 1_024 * 1_024).contains(
                manifest.limits.maximumArtifactBytes
            )
            && (64 * 1_024 * 1_024 ... 2 * 1_024 * 1_024 * 1_024).contains(
                manifest.limits.maximumResidentBytes
            )
            && (100 ... 30_000).contains(manifest.limits.timeoutMilliseconds)
    }

    private static func validHelper(_ url: URL, within root: URL) -> Bool {
        let standardized = url.standardizedFileURL
        guard standardized.deletingLastPathComponent() == root else { return false }
        let values = try? standardized.resourceValues(forKeys: [
            .isRegularFileKey, .isSymbolicLinkKey, .isExecutableKey,
        ])
        return values?.isRegularFile == true
            && values?.isSymbolicLink != true
            && values?.isExecutable == true
    }

    private static func signedByProductTeam(_ url: URL) -> Bool {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(
            url as CFURL,
            SecCSFlags(),
            &code
        ) == errSecSuccess, let code else { return false }
        var requirement: SecRequirement?
        let expression = "anchor apple generic and certificate leaf[subject.OU] = \"\(expectedTeamID)\""
        guard SecRequirementCreateWithString(
            expression as CFString,
            SecCSFlags(),
            &requirement
        ) == errSecSuccess, let requirement else { return false }
        let flags = SecCSFlags(rawValue: UInt32(
            kSecCSStrictValidate | kSecCSCheckAllArchitectures
        ))
        return SecStaticCodeCheckValidity(code, flags, requirement) == errSecSuccess
    }

    private static func regularFileData(_ url: URL) -> Data? {
        let values = try? url.resourceValues(forKeys: [
            .isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey,
        ])
        guard values?.isRegularFile == true,
              values?.isSymbolicLink != true,
              let size = values?.fileSize,
              (1 ... 64 * 1_024).contains(size) else { return nil }
        return try? Data(contentsOf: url, options: .mappedIfSafe)
    }
}
