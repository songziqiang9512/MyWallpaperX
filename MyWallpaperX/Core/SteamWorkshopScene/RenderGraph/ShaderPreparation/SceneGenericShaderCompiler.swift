import Foundation

/// Synchronous launch-preparation coordinator for one exact source pair. The
/// expensive work runs in signed helper processes; this type owns only bounded
/// normalization, reflection validation, and atomic cache publication.
nonisolated enum SceneGenericShaderCompiler {
    enum Failure: Error, Equatable {
        case configuration(String)
        case normalization(String)
        case workspace
        case tool(String)
        case artifact(String)
        case publication
    }

    private struct CompiledStage {
        let name: String
        let source: String
        let authoredSource: String
        let msl: String
        let reflection: Data
    }

    static func compile(
        requestKey: String,
        vertexSource: String,
        fragmentSource: String,
        outputSemantics: SceneGenericShaderOutputSemantics = .color,
        cacheRoot: URL,
        bundle: Bundle = .main
    ) -> Result<URL, Failure> {
        let configuration: SceneGenericShaderCompilerBundle.Configuration
        switch SceneGenericShaderCompilerBundle.resolve(bundle: bundle) {
        case let .success(value): configuration = value
        case let .failure(failure):
            return .failure(.configuration(String(describing: failure)))
        }
        let normalized: SceneGenericShaderSourceNormalizer.Pair
        switch SceneGenericShaderSourceNormalizer.normalize(
            vertexSource: vertexSource,
            fragmentSource: fragmentSource,
            maximumStageSourceBytes: configuration.limits.maximumStageSourceBytes
        ) {
        case let .success(value): normalized = value
        case let .failure(failure):
            return .failure(.normalization(String(describing: failure)))
        }
        let fileManager = FileManager.default
        let workspace = fileManager.temporaryDirectory.appendingPathComponent(
            "mwx-scene-shader-\(UUID().uuidString)",
            isDirectory: true
        )
        do {
            try fileManager.createDirectory(
                at: workspace,
                withIntermediateDirectories: false,
                attributes: [.posixPermissions: 0o700]
            )
        } catch {
            return .failure(.workspace)
        }
        defer { try? fileManager.removeItem(at: workspace) }
        let vertexURL = workspace.appendingPathComponent("author.vert")
        let fragmentURL = workspace.appendingPathComponent("author.frag")
        do {
            try boundedData(normalized.vertex, configuration: configuration)
                .write(to: vertexURL, options: [.atomic])
            try boundedData(normalized.fragment, configuration: configuration)
                .write(to: fragmentURL, options: [.atomic])
        } catch {
            return .failure(.workspace)
        }
        switch probe(
            configuration.glslang,
            phase: "glslang-version",
            contains: configuration.glslangVersionProbe,
            expectedExitCode: configuration.glslangVersionProbeExitCode,
            configuration: configuration,
            workspace: workspace
        ) {
        case .success: break
        case let .failure(failure): return .failure(failure)
        }
        switch probe(
            configuration.spirvCross,
            phase: "spirv-cross-version",
            contains: configuration.spirvCrossVersionProbe,
            expectedExitCode: configuration.spirvCrossVersionProbeExitCode,
            configuration: configuration,
            workspace: workspace
        ) {
        case .success: break
        case let .failure(failure): return .failure(failure)
        }
        switch run(
            configuration.glslang,
            arguments: [
                "-V", "--auto-map-bindings", "--auto-map-locations", "-l",
                vertexURL.path, fragmentURL.path,
            ],
            phase: "stage-link",
            configuration: configuration,
            workspace: workspace
        ) {
        case .success: break
        case let .failure(failure): return .failure(failure)
        }
        var compiled: [CompiledStage] = []
        for (name, suffix, source, sourceURL, entryPoint) in [
            ("vertex", "vert", normalized.vertex, vertexURL, "mwxGenericVertex"),
            ("fragment", "frag", normalized.fragment, fragmentURL, "mwxGenericFragment"),
        ] {
            let spirv = workspace.appendingPathComponent("\(name).spv")
            let msl = workspace.appendingPathComponent("\(name).metal")
            let reflection = workspace.appendingPathComponent("\(name).reflection.json")
            switch run(
                configuration.glslang,
                arguments: [
                    "-V", "--auto-map-bindings", "--auto-map-locations",
                    "-S", suffix, "-e", "main", "-o", spirv.path, sourceURL.path,
                ],
                phase: "\(name)-glslang",
                configuration: configuration,
                workspace: workspace
            ) {
            case .success: break
            case let .failure(failure): return .failure(failure)
            }
            guard validOutput(spirv, maximumBytes: configuration.limits.maximumArtifactBytes)
            else { return .failure(.artifact("\(name)-spirv")) }
            switch run(
                configuration.spirvCross,
                arguments: [
                    spirv.path, "--msl", "--msl-version", "20000",
                    "--msl-decoration-binding", "--rename-entry-point", "main",
                    entryPoint, suffix, "--output", msl.path,
                ],
                phase: "\(name)-msl",
                configuration: configuration,
                workspace: workspace
            ) {
            case .success: break
            case let .failure(failure): return .failure(failure)
            }
            switch run(
                configuration.spirvCross,
                arguments: [spirv.path, "--reflect", "--output", reflection.path],
                phase: "\(name)-reflection",
                configuration: configuration,
                workspace: workspace
            ) {
            case .success: break
            case let .failure(failure): return .failure(failure)
            }
            guard let mslData = boundedFile(
                    msl, maximumBytes: configuration.limits.maximumArtifactBytes
                  ),
                  let mslSource = String(data: mslData, encoding: .utf8),
                  let reflectionData = boundedFile(
                    reflection,
                    maximumBytes: configuration.limits.maximumArtifactBytes
                  ) else { return .failure(.artifact("\(name)-output")) }
            compiled.append(.init(
                name: name,
                source: source,
                authoredSource: name == "vertex" ? vertexSource : fragmentSource,
                msl: mslSource,
                reflection: reflectionData
            ))
        }
        let artifact: SceneGenericShaderProgramArtifact
        switch SceneGenericShaderArtifactBuilder.build(
            requestKey: requestKey,
            backendID: configuration.backendID,
            outputSemantics: outputSemantics,
            stages: compiled.map {
                .init(name: $0.name, source: $0.source,
                      authoredSource: $0.authoredSource, msl: $0.msl,
                      reflection: $0.reflection)
            },
            maximumArtifactBytes: configuration.limits.maximumArtifactBytes
        ) {
        case let .success(value): artifact = value
        case let .failure(failure):
            return .failure(.artifact(String(describing: failure)))
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(artifact),
              (1 ... configuration.limits.maximumArtifactBytes).contains(data.count)
        else { return .failure(.artifact("encoding")) }
        let target = cacheRoot.appendingPathComponent("\(requestKey).json")
        do {
            try data.write(to: target, options: [.atomic])
        } catch {
            return .failure(.publication)
        }
        return .success(target)
    }

    private static func probe(
        _ executable: URL,
        phase: String,
        contains expected: String,
        expectedExitCode: Int32,
        configuration: SceneGenericShaderCompilerBundle.Configuration,
        workspace: URL
    ) -> Result<Void, Failure> {
        guard !expected.isEmpty else {
            return .failure(.tool("\(phase):version-mismatch"))
        }
        switch SceneGenericShaderCompilerProcess.run(
            executable: executable,
            arguments: ["--version"],
            workingDirectory: workspace,
            timeoutMilliseconds: configuration.limits.timeoutMilliseconds,
            maximumDiagnosticBytes: configuration.limits.maximumDiagnosticBytes,
            maximumResidentBytes: configuration.limits.maximumResidentBytes,
            expectedExitCode: expectedExitCode
        ) {
        case let .success(output):
            let version = String(decoding: output.stdout + output.stderr, as: UTF8.self)
            return version.contains(expected)
                ? .success(())
                : .failure(.tool("\(phase):version-mismatch"))
        case let .failure(failure):
            return .failure(.tool("\(phase):\(failure)"))
        }
    }

    private static func run(
        _ executable: URL,
        arguments: [String],
        phase: String,
        configuration: SceneGenericShaderCompilerBundle.Configuration,
        workspace: URL
    ) -> Result<Void, Failure> {
        switch SceneGenericShaderCompilerProcess.run(
            executable: executable,
            arguments: arguments,
            workingDirectory: workspace,
            timeoutMilliseconds: configuration.limits.timeoutMilliseconds,
            maximumDiagnosticBytes: configuration.limits.maximumDiagnosticBytes,
            maximumResidentBytes: configuration.limits.maximumResidentBytes
        ) {
        case .success:
            return .success(())
        case let .failure(failure):
            return .failure(.tool("\(phase):\(failure)"))
        }
    }

    private static func boundedData(
        _ source: String,
        configuration: SceneGenericShaderCompilerBundle.Configuration
    ) throws -> Data {
        let data = Data(source.utf8)
        guard (1 ... configuration.limits.maximumStageSourceBytes).contains(data.count)
        else { throw Failure.workspace }
        return data
    }

    private static func validOutput(_ url: URL, maximumBytes: Int) -> Bool {
        boundedFile(url, maximumBytes: maximumBytes) != nil
    }

    private static func boundedFile(_ url: URL, maximumBytes: Int) -> Data? {
        let values = try? url.resourceValues(forKeys: [
            .isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey,
        ])
        guard values?.isRegularFile == true,
              values?.isSymbolicLink != true,
              let size = values?.fileSize,
              (1 ... maximumBytes).contains(size) else { return nil }
        return try? Data(contentsOf: url, options: .mappedIfSafe)
    }
}
