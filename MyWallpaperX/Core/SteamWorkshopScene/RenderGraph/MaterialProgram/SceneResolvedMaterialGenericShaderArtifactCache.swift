import Foundation

/// Product preparation cache for exact-source-keyed generic Program artifacts.
/// Cache misses may invoke the separately killable bundled compiler worker;
/// malformed or failed output is either an effect-local typed fallback or a
/// profile-local rejection after the bounded product owner has been revoked.
nonisolated enum SceneResolvedMaterialGenericShaderArtifactCache {
    enum Resolution {
        case accepted(program: SceneAuthoredShaderProgram, requestKey: String)
        case unavailable(
            code: String,
            requestKey: String,
            permitsBoundedFrontend: Bool
        )
    }

    private struct Request: Encodable {
        struct Stage: Encodable {
            let stage: String
            let entryPoint: String
            let source: String
        }

        let schemaVersion = 1
        let requestID: String
        let sourceDialect = "wallpaper-engine-glsl-like-v0"
        let defines: [String: Int] = [:]
        let stages: [Stage]
    }

    private static let routeEnvironment = "MWX_SCENE_GENERIC_SHADER_ROUTE"
    private static let cacheEnvironment = "MWX_SCENE_GENERIC_SHADER_CACHE"
    private static let requestEnvironment = "MWX_SCENE_GENERIC_SHADER_REQUESTS"
    private static let maximumArtifactBytes = 2 * 1_024 * 1_024
    private static let routeTelemetry = RouteTelemetry()
    private static let compilationCoordinator = CompilationCoordinator()

    private enum RouteState: String {
        case preferGeneric = "prefer-generic"
        case genericOnly = "generic-only"
        case observeOnly = "observe-only"
        case disableGeneric = "disable-generic"

        static func resolve(
            _ rawValue: String?,
            defaultState: RouteState
        ) -> RouteState? {
            guard let rawValue else { return defaultState }
            guard let requested = RouteState(rawValue: rawValue) else { return nil }
            switch requested {
            case .preferGeneric:
                // A migrated profile cannot silently regain a second product
                // owner. `disable-generic` is its explicit rollback switch.
                return defaultState == .genericOnly ? .genericOnly : .preferGeneric
            case .genericOnly:
                // Do not let an environment toggle broaden generic-only
                // authority to profiles that have not passed their owner gate.
                return defaultState == .genericOnly ? .genericOnly : nil
            case .observeOnly, .disableGeneric:
                return requested
            }
        }
    }

    private enum CapabilityProfile: String {
        case ordinaryShader = "ordinary-shader"
        case providerBackedScalarColorInterpolation =
            "provider-backed-scalar-color-interpolation"
        case sourceProvenScalarColorInterpolation =
            "source-proven-scalar-color-interpolation"
        case sourceProvenOpaqueScalarOutput =
            "source-proven-opaque-scalar-output"
        case sourceProvenStraightAlphaR8Signal =
            "source-proven-straight-alpha-r8-signal"
        case sourceProvenGraphTargetPassthrough =
            "source-proven-graph-target-passthrough"
        case sourceProvenGraphInputStraightAlpha =
            "source-proven-graph-input-straight-alpha"
        case sourceProvenGraphInputStraightAlphaPreserving =
            "source-proven-graph-input-straight-alpha-preserving"
        case sourceProvenGraphInputStageUniformPassthrough =
            "source-proven-graph-input-stage-uniform-passthrough"

        init(
            colorTransfer: SceneShaderColorTransfer,
            hasExternalProviderTexture: Bool,
            producesScalarRedOutput: Bool,
            graphTextureSlots: Set<Int>,
            graphInputTextureSlots: Set<Int>,
            r8TextureSlots: Set<Int>,
            hasStageScopedUniformBindings: Bool
        ) {
            if colorTransfer == .opaque, producesScalarRedOutput {
                self = .sourceProvenOpaqueScalarOutput
            } else if case let .straightAlphaPreserving(sourceSlot) = colorTransfer,
                      !producesScalarRedOutput,
                      r8TextureSlots.contains(where: { $0 != sourceSlot }) {
                self = .sourceProvenStraightAlphaR8Signal
            } else if case let .passthrough(sourceSlot) = colorTransfer,
                      !hasExternalProviderTexture,
                      !producesScalarRedOutput,
                      graphTextureSlots.contains(sourceSlot) {
                self = .sourceProvenGraphTargetPassthrough
            } else if case let .passthrough(sourceSlot) = colorTransfer,
                      !hasExternalProviderTexture,
                      !producesScalarRedOutput,
                      graphInputTextureSlots.contains(sourceSlot),
                      hasStageScopedUniformBindings {
                self = .sourceProvenGraphInputStageUniformPassthrough
            } else if case let .straightAlpha(sourceSlot) = colorTransfer,
                      !hasExternalProviderTexture,
                      !producesScalarRedOutput,
                      graphInputTextureSlots.contains(sourceSlot) {
                self = .sourceProvenGraphInputStraightAlpha
            } else if case let .straightAlphaPreserving(sourceSlot) = colorTransfer,
                      !hasExternalProviderTexture,
                      !producesScalarRedOutput,
                      graphInputTextureSlots.contains(sourceSlot) {
                self = .sourceProvenGraphInputStraightAlphaPreserving
            } else if case .interpolatedColor = colorTransfer,
               hasExternalProviderTexture {
                self = .providerBackedScalarColorInterpolation
            } else if case .interpolatedColor = colorTransfer {
                self = .sourceProvenScalarColorInterpolation
            } else {
                self = .ordinaryShader
            }
        }

        var defaultRouteState: RouteState {
            switch self {
            case .ordinaryShader,
                 .providerBackedScalarColorInterpolation: .preferGeneric
            case .sourceProvenScalarColorInterpolation,
                 .sourceProvenOpaqueScalarOutput,
                 .sourceProvenStraightAlphaR8Signal,
                 .sourceProvenGraphTargetPassthrough,
                 .sourceProvenGraphInputStraightAlpha,
                 .sourceProvenGraphInputStraightAlphaPreserving,
                 .sourceProvenGraphInputStageUniformPassthrough: .genericOnly
            }
        }
    }

    private final class RouteTelemetry: @unchecked Sendable {
        private let lock = NSLock()
        private var counts: [String: Int] = [:]
        private var executedIdentities = Set<String>()

        func record(
            state: RouteState,
            profile: CapabilityProfile,
            outcome: String,
            reason: String,
            requestKey: String
        ) {
            let count = lock.withLock {
                let identity = [
                    state.rawValue, profile.rawValue, outcome, reason,
                ].joined(separator: ":")
                let updated = counts[identity, default: 0] + 1
                counts[identity] = updated
                return updated
            }
            NSLog(
                "MWX generic shader route state=%@ profile=%@ outcome=%@ reason=%@ request=%@ count=%d",
                state.rawValue,
                profile.rawValue,
                outcome,
                reason,
                requestKey,
                count
            )
        }

        func recordExecution(
            state: RouteState,
            profile: CapabilityProfile,
            backend: SceneAuthoredShaderProgram.Backend,
            layerID: Int,
            effectIndex: Int,
            descriptorID: String,
            nodeIndex: Int,
            preparedKey: String
        ) {
            let identity = [
                String(layerID), String(effectIndex), descriptorID,
                String(nodeIndex), backend.rawValue, preparedKey,
            ].joined(separator: "|")
            guard lock.withLock({ executedIdentities.insert(identity).inserted }) else {
                return
            }
            NSLog(
                "MWX generic shader execution state=%@ profile=%@ layer=%d effect=%d descriptor=%@ node=%d backend=%@ prepared=%@",
                state.rawValue,
                profile.rawValue,
                layerID,
                effectIndex,
                descriptorID,
                nodeIndex,
                backend.rawValue,
                preparedKey
            )
        }

        func recordCompilerLifecycle(
            source: CompilationCoordinator.Source,
            outcome: String,
            reason: String,
            requestKey: String
        ) {
            let count = lock.withLock {
                let identity = "compiler:\(source.rawValue):\(outcome):\(reason)"
                let updated = counts[identity, default: 0] + 1
                counts[identity] = updated
                return updated
            }
            NSLog(
                "MWX generic shader compiler lifecycle phase=launch-preparation source=%@ outcome=%@ reason=%@ request=%@ count=%d",
                source.rawValue,
                outcome,
                reason,
                requestKey,
                count
            )
        }
    }

    final class CompilationCoordinator: @unchecked Sendable {
        enum Source: String {
            case spawn
            case launchResultCache = "launch-result-cache"
        }

        struct Outcome {
            let result: Result<URL, SceneGenericShaderCompiler.Failure>
            let source: Source
        }

        private let condition = NSCondition()
        private var active = Set<String>()
        private var completed: [String: Result<URL, SceneGenericShaderCompiler.Failure>] = [:]

        func perform(
            key: String,
            operation: () -> Result<URL, SceneGenericShaderCompiler.Failure>
        ) -> Outcome {
            condition.lock()
            while active.contains(key) {
                condition.wait()
            }
            if let result = completed[key] {
                condition.unlock()
                return .init(result: result, source: .launchResultCache)
            }
            active.insert(key)
            condition.unlock()
            let result = operation()
            condition.lock()
            completed[key] = result
            active.remove(key)
            condition.broadcast()
            condition.unlock()
            return .init(result: result, source: .spawn)
        }
    }

    static func resolve(
        vertexSource: String,
        fragmentSource: String,
        hasExternalProviderTexture: Bool = false,
        producesScalarRedOutput: Bool = false,
        graphTextureSlots: Set<Int> = [],
        graphInputTextureSlots: Set<Int> = [],
        r8TextureSlots: Set<Int> = []
    ) -> Resolution {
        let key = requestKey(
            vertexSource: vertexSource,
            fragmentSource: fragmentSource
        )
        let colorTransfer = SceneAuthoredShaderColorTransferAnalyzer.analyze(
            fragmentSource: fragmentSource
        )
        let profile = CapabilityProfile(
            colorTransfer: colorTransfer,
            hasExternalProviderTexture: hasExternalProviderTexture,
            producesScalarRedOutput: producesScalarRedOutput,
            graphTextureSlots: graphTextureSlots,
            graphInputTextureSlots: graphInputTextureSlots,
            r8TextureSlots: r8TextureSlots,
            hasStageScopedUniformBindings: hasStageScopedUniformBindings(
                vertexSource: vertexSource,
                fragmentSource: fragmentSource
            )
        )
        let environment = ProcessInfo.processInfo.environment
        guard let routeState = RouteState.resolve(
            environment[routeEnvironment],
            defaultState: profile.defaultRouteState
        ) else {
            return .unavailable(
                code: "route-invalid",
                requestKey: key,
                permitsBoundedFrontend:
                    profile.defaultRouteState != .genericOnly
            )
        }
        guard routeState != .disableGeneric else {
            routeTelemetry.record(
                state: routeState,
                profile: profile,
                outcome: "fallback",
                reason: "route-disabled",
                requestKey: key
            )
            return .unavailable(
                code: "route-disabled",
                requestKey: key,
                permitsBoundedFrontend: true
            )
        }
        exportRequest(
            key: key,
            vertexSource: vertexSource,
            fragmentSource: fragmentSource
        )
        guard routeState == .preferGeneric || routeState == .genericOnly else {
            return .unavailable(
                code: "route-observe-only",
                requestKey: key,
                permitsBoundedFrontend:
                    profile.defaultRouteState != .genericOnly
            )
        }
        guard let root = cacheDirectory(environment: environment) else {
            return fallback(
                state: routeState,
                profile: profile,
                code: "cache-unavailable",
                requestKey: key
            )
        }
        let artifactURL = root.appendingPathComponent("\(key).json", isDirectory: false)
        var data = regularFileData(artifactURL)
        if data == nil {
            let compilation = compilationCoordinator.perform(key: key) {
                if regularFileData(artifactURL) != nil {
                    return .success(artifactURL)
                }
                return SceneGenericShaderCompiler.compile(
                    requestKey: key,
                    vertexSource: vertexSource,
                    fragmentSource: fragmentSource,
                    cacheRoot: root
                )
            }
            switch compilation.result {
            case .success:
                routeTelemetry.recordCompilerLifecycle(
                    source: compilation.source,
                    outcome: "published",
                    reason: "-",
                    requestKey: key
                )
                data = regularFileData(artifactURL)
            case let .failure(failure):
                let code = compilerFallbackCode(failure)
                routeTelemetry.recordCompilerLifecycle(
                    source: compilation.source,
                    outcome: "failed",
                    reason: code,
                    requestKey: key
                )
                return fallback(
                    state: routeState,
                    profile: profile,
                    code: code,
                    requestKey: key
                )
            }
        }
        guard let data else {
            return fallback(
                state: routeState,
                profile: profile,
                code: "compiler-publication-missing",
                requestKey: key
            )
        }
        let artifact: SceneGenericShaderProgramArtifact
        do {
            artifact = try JSONDecoder().decode(
                SceneGenericShaderProgramArtifact.self,
                from: data
            )
        } catch {
            return fallback(
                state: routeState,
                profile: profile,
                code: "artifact-invalid-json",
                requestKey: key
            )
        }
        let fragmentOutputChannelUse = fragmentOutputChannelUse(fragmentSource)
        guard let program = artifact.makeProgram(
                  expectedKey: key,
                  expectedColorTransfer: colorTransfer,
                  expectedFragmentOutputChannelUse: fragmentOutputChannelUse
              ) else {
            return fallback(
                state: routeState,
                profile: profile,
                code: "artifact-contract-rejected",
                requestKey: key
            )
        }
        routeTelemetry.record(
            state: routeState,
            profile: profile,
            outcome: "accepted",
            reason: "-",
            requestKey: key
        )
        return .accepted(program: program, requestKey: key)
    }

    private static func fragmentOutputChannelUse(
        _ source: String
    ) -> SceneAuthoredShaderProgram.FragmentOutputChannelUse {
        let lexerOutput = SceneAuthoredShaderLexer.lex(
            source: source,
            stage: .fragment
        )
        let syntaxOutput = SceneAuthoredShaderSyntaxAnalyzer.analyze(
            lexerOutput: lexerOutput,
            stage: .fragment
        )
        guard syntaxOutput.diagnostics.isEmpty,
              let fragment = syntaxOutput.unit else { return .unproven }
        return SceneAuthoredShaderFragmentOutputAnalyzer.analyze(fragment)
    }

    private static func fallback(
        state: RouteState,
        profile: CapabilityProfile,
        code: String,
        requestKey: String
    ) -> Resolution {
        routeTelemetry.record(
            state: state,
            profile: profile,
            outcome: state == .genericOnly ? "rejected" : "fallback",
            reason: code,
            requestKey: requestKey
        )
        return .unavailable(
            code: code,
            requestKey: requestKey,
            permitsBoundedFrontend: state != .genericOnly
        )
    }

    static func recordExecution(
        backend: SceneAuthoredShaderProgram.Backend,
        colorTransfer: SceneShaderColorTransfer,
        hasExternalProviderTexture: Bool,
        producesScalarRedOutput: Bool,
        graphTextureSlots: Set<Int>,
        graphInputTextureSlots: Set<Int>,
        r8TextureSlots: Set<Int>,
        hasStageScopedUniformBindings: Bool,
        layerID: Int,
        effectIndex: Int,
        descriptorID: String,
        nodeIndex: Int,
        preparedKey: String
    ) {
        let environment = ProcessInfo.processInfo.environment
        let profile = CapabilityProfile(
            colorTransfer: colorTransfer,
            hasExternalProviderTexture: hasExternalProviderTexture,
            producesScalarRedOutput: producesScalarRedOutput,
            graphTextureSlots: graphTextureSlots,
            graphInputTextureSlots: graphInputTextureSlots,
            r8TextureSlots: r8TextureSlots,
            hasStageScopedUniformBindings: hasStageScopedUniformBindings
        )
        guard let state = RouteState.resolve(
                  environment[routeEnvironment],
                  defaultState: profile.defaultRouteState
              ), state != .observeOnly else {
            return
        }
        routeTelemetry.recordExecution(
            state: state,
            profile: profile,
            backend: backend,
            layerID: layerID,
            effectIndex: effectIndex,
            descriptorID: descriptorID,
            nodeIndex: nodeIndex,
            preparedKey: preparedKey
        )
    }

    private static func hasStageScopedUniformBindings(
        vertexSource: String,
        fragmentSource: String
    ) -> Bool {
        func activeUniforms(
            _ source: String,
            stage: SceneShaderContract.StageKind
        ) -> Set<String>? {
            let output = SceneAuthoredShaderSyntaxAnalyzer.analyze(
                lexerOutput: SceneAuthoredShaderLexer.lex(
                    source: source,
                    stage: stage
                ),
                stage: stage
            )
            guard output.diagnostics.isEmpty, let unit = output.unit else {
                return nil
            }
            return Set(unit.declarations.compactMap { declaration in
                guard declaration.storage == .uniform,
                      declaration.typeName != "sampler2D",
                      SceneAuthoredShaderGlobalReferenceAnalyzer.isReferenced(
                          declaration.name,
                          in: unit
                      ) else { return nil }
                return declaration.name
            })
        }
        guard let vertex = activeUniforms(vertexSource, stage: .vertex),
              let fragment = activeUniforms(fragmentSource, stage: .fragment) else {
            return false
        }
        return !vertex.isEmpty && !fragment.isEmpty
    }

    private static func requestKey(
        vertexSource: String,
        fragmentSource: String
    ) -> String {
        var data = Data()
        for value in [
            "mwx-generic-shader-request-v3",
            "wallpaper-engine-glsl-like-v0",
            vertexSource,
            fragmentSource,
            "{}",
        ] {
            let encoded = Data(value.utf8)
            var length = UInt64(encoded.count).bigEndian
            withUnsafeBytes(of: &length) { data.append(contentsOf: $0) }
            data.append(encoded)
        }
        return sha256(data)
    }

    private static func exportRequest(
        key: String,
        vertexSource: String,
        fragmentSource: String
    ) {
        let environment = ProcessInfo.processInfo.environment
        guard let rawRoot = environment[requestEnvironment],
              let root = validatedDirectory(rawRoot) else { return }
        let request = Request(
            requestID: key,
            stages: [
                .init(stage: "vertex", entryPoint: "main", source: vertexSource),
                .init(stage: "fragment", entryPoint: "main", source: fragmentSource),
            ]
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(request) else { return }
        let url = root.appendingPathComponent("\(key).json", isDirectory: false)
        if let existing = try? Data(contentsOf: url) {
            if existing != data {
                NSLog("MWX generic shader request collision request=%@", key)
            }
            return
        }
        do {
            try data.write(to: url, options: .atomic)
            NSLog("MWX generic shader request exported request=%@", key)
        } catch {
            NSLog("MWX generic shader request export failed request=%@", key)
        }
    }

    private static func validatedDirectory(_ rawPath: String) -> URL? {
        guard !rawPath.isEmpty else { return nil }
        let url = URL(fileURLWithPath: rawPath, isDirectory: true).standardizedFileURL
        let values = try? url.resourceValues(forKeys: [
            .isDirectoryKey, .isSymbolicLinkKey,
        ])
        guard values?.isDirectory == true, values?.isSymbolicLink != true else {
            return nil
        }
        return url
    }

    private static func cacheDirectory(
        environment: [String: String]
    ) -> URL? {
        if let rawRoot = environment[cacheEnvironment] {
            return validatedDirectory(rawRoot)
        }
        guard let caches = FileManager.default.urls(
            for: .cachesDirectory,
            in: .userDomainMask
        ).first else { return nil }
        let root = caches
            .appendingPathComponent("com.songziqiang.MyWallpaperX", isDirectory: true)
            .appendingPathComponent("SceneGenericShaderPrograms-v3", isDirectory: true)
            .standardizedFileURL
        do {
            try FileManager.default.createDirectory(
                at: root,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
        } catch {
            return nil
        }
        return validatedDirectory(root.path)
    }

    private static func compilerFallbackCode(
        _ failure: SceneGenericShaderCompiler.Failure
    ) -> String {
        switch failure {
        case let .configuration(reason):
            return "compiler-configuration-\(sanitize(reason))"
        case let .normalization(reason):
            return "compiler-normalization-\(sanitize(reason))"
        case .workspace:
            return "compiler-workspace"
        case let .tool(reason):
            return "compiler-tool-\(sanitize(reason))"
        case let .artifact(reason):
            return "compiler-artifact-\(sanitize(reason))"
        case .publication:
            return "compiler-publication"
        }
    }

    private static func sanitize(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        return value.unicodeScalars.map { allowed.contains($0) ? String($0) : "-" }
            .joined()
            .prefix(96)
            .lowercased()
    }

    private static func regularFileData(_ url: URL) -> Data? {
        let values = try? url.resourceValues(forKeys: [
            .isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey,
        ])
        guard values?.isRegularFile == true,
              values?.isSymbolicLink != true,
              let size = values?.fileSize,
              (1 ... maximumArtifactBytes).contains(size) else { return nil }
        return try? Data(contentsOf: url, options: .mappedIfSafe)
    }

    private static func sha256(_ data: Data) -> String {
        SceneGenericShaderProgramArtifact.sha256(data)
    }
}
