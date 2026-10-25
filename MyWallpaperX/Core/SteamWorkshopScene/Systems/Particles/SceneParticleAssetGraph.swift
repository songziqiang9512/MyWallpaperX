import Foundation

nonisolated struct SceneParticleMaterialPass: Equatable, Sendable {
    let materialPath: String
    let passIndex: Int
    let shaderPath: String?
    let texturePaths: [String]
    let textureSlots: [String?]
    let blending: String?
    let combos: [String: Int]
    let constantValues: [String: SceneParticleMaterialConstant]
    let hasUserTextureInputs: Bool
    let hasUserShaderValues: Bool
    let depthTest: String?
    let depthWrite: String?
    let cullMode: String?
    let alphaWriting: String?

    init(
        materialPath: String,
        passIndex: Int = 0,
        shaderPath: String?,
        texturePaths: [String],
        textureSlots: [String?]? = nil,
        blending: String?,
        combos: [String: Int] = [:],
        constantValues: [String: SceneParticleMaterialConstant] = [:],
        hasUserTextureInputs: Bool = false,
        hasUserShaderValues: Bool = false,
        depthTest: String? = "disabled",
        depthWrite: String? = "disabled",
        cullMode: String? = "nocull",
        alphaWriting: String? = nil
    ) {
        self.materialPath = materialPath
        self.passIndex = passIndex
        self.shaderPath = shaderPath
        self.texturePaths = texturePaths
        self.textureSlots = textureSlots ?? texturePaths.map(Optional.some)
        self.blending = blending
        self.combos = combos
        self.constantValues = constantValues
        self.hasUserTextureInputs = hasUserTextureInputs
        self.hasUserShaderValues = hasUserShaderValues
        self.depthTest = depthTest
        self.depthWrite = depthWrite
        self.cullMode = cullMode
        self.alphaWriting = alphaWriting
    }
}

nonisolated struct SceneParticleAsset: Sendable {
    let relativePath: String
    let definition: SceneParticleDefinition
    let materialPass: SceneParticleMaterialPass?
    let supportsBuiltInShaderExecution: Bool
    let textureSource: SceneParticleTextureSource?
    let refraction: SceneParticleRefractionDeclaration?
    let renderState: SceneMaterialRenderState?
    let pipelineState: SceneParticlePipelineRenderState?
    let childPaths: [String]
}

nonisolated struct SceneParticleAssetGraph: Sendable {
    let rootPaths: [String]
    let assetsByPath: [String: SceneParticleAsset]
    let diagnostics: [SceneParticleAssetDiagnostic]
}

nonisolated struct SceneParticleAssetDiagnostic: Codable, Equatable, Hashable, Sendable {
    enum Kind: String, Codable, Sendable {
        case missingDefinition
        case invalidDefinition
        case cyclicChildReference
        case missingMaterial
        case unsupportedShader
        case missingTextureReference
        case missingTextureFile
        case builtInTextureUnavailable
        case unsupportedBlendMode
        case unsupportedRenderState
        case refractionUnsupported
    }

    let kind: Kind
    let assetPath: String
    let detail: String?
}

nonisolated struct SceneParticleAssetGraphLoader {
    /// Captured once for this launch, including failed leaves. Discovery may
    /// inspect a hidden root; its hard read failure belongs to actual adoption.
    enum PreparedDefinition {
        case parsed(SceneParticleDefinition)
        case missing
        case invalid
        case readFailed(SceneResourceView.ReadError)

        func rethrowHardReadFailure() throws {
            if case let .readFailed(error) = self {
                switch error {
                case .sourceChanged, .invalidHandle: throw error
                default: break
                }
            }
        }
    }

    private let stockTextureResolver: SceneStockTextureResolver?
    private let resourceView: SceneResourceView

    init(
        resourceView: SceneResourceView,
        stockTextureBundleURL: URL? = SceneStockTextureResolver.defaultBundleRoot()
    ) {
        self.resourceView = resourceView
        stockTextureResolver = stockTextureBundleURL.flatMap {
            SceneStockTextureResolver(bundleRoot: $0)
        }
    }

    func load(
        rootPaths: [String],
        materialPasses: [SceneParticleMaterialPass],
        preparedDefinitions: [String: PreparedDefinition]? = nil,
        checkCancellation: (() throws -> Void)? = nil
    ) throws -> SceneParticleAssetGraph {
        try checkCancellation?()
        var definitions = preparedDefinitions ?? [:]
        if preparedDefinitions == nil {
            _ = try prepareDefinitions(rootPaths: rootPaths, checkCancellation: checkCancellation) { path, value in
                try value.rethrowHardReadFailure()
                definitions[path] = value
            }
        }
        let passesByMaterial = Dictionary(
            grouping: materialPasses,
            by: { Self.normalizedPath($0.materialPath) }
        )
        let roots = Self.unique(rootPaths.map(Self.normalizedPath).filter { !$0.isEmpty })
        var assets: [String: SceneParticleAsset] = [:]
        var diagnostics: [SceneParticleAssetDiagnostic] = []
        var attempted: Set<String> = []
        var visiting: Set<String> = []

        func diagnose(_ kind: SceneParticleAssetDiagnostic.Kind, _ path: String, _ detail: String? = nil) {
            let value = SceneParticleAssetDiagnostic(kind: kind, assetPath: path, detail: detail)
            if !diagnostics.contains(value) { diagnostics.append(value) }
        }

        func visit(_ rawPath: String) throws {
            try checkCancellation?()
            let path = Self.normalizedPath(rawPath)
            if visiting.contains(path) {
                diagnose(.cyclicChildReference, path)
                return
            }
            guard attempted.insert(path).inserted else { return }
            guard let prepared = definitions[path] else {
                diagnose(.missingDefinition, path)
                return
            }
            try prepared.rethrowHardReadFailure()
            if case .missing = prepared {
                diagnose(.missingDefinition, path)
                return
            }
            guard case let .parsed(definition) = prepared else {
                diagnose(.invalidDefinition, path)
                return
            }

            let materialPath = definition.materialPath.map(Self.normalizedPath)
            let materialPass = materialPath.flatMap { path in
                Self.preferredPass(in: passesByMaterial[path] ?? [])
            }
            let supportsShader = Self.isGenericParticleShader(materialPass?.shaderPath)
            if materialPass == nil {
                diagnose(.missingMaterial, path, materialPath)
            } else if !supportsShader {
                diagnose(.unsupportedShader, path, materialPass?.shaderPath)
            }

            let refractionPlan = materialPass.flatMap(
                SceneParticleRefractionPlanner.plan(for:)
            )
            let textureName = refractionPlan?.colorReference
                ?? materialPass?.textureSlots.first.flatMap { $0 }
                ?? materialPass?.texturePaths.first
            if textureName == nil {
                diagnose(.missingTextureReference, path, materialPath)
            }
            var textureSource = try textureName.flatMap {
                try resolveTextureSource(named: $0)
            }
            if let textureName, textureSource == nil {
                diagnose(
                    Self.isBuiltInTexture(textureName) ? .builtInTextureUnavailable : .missingTextureFile,
                    path,
                    textureName
                )
            }
            var refraction: SceneParticleRefractionDeclaration?
            if let refract = materialPass?.combos["REFRACT"], refract != 0 {
                if let refractionPlan,
                   refractionPlan.normalReference == nil {
                    refraction = SceneParticleRefractionDeclaration(
                        normalTextureSource: nil,
                        amount: refractionPlan.amount,
                        overbright: refractionPlan.overbright
                    )
                } else if let refractionPlan,
                          let normalReference = refractionPlan.normalReference,
                          let normal = try resolveTextureSource(
                              named: normalReference
                          ) {
                    refraction = SceneParticleRefractionDeclaration(
                        normalTextureSource: normal,
                        amount: refractionPlan.amount,
                        overbright: refractionPlan.overbright
                    )
                } else if refractionPlan == nil {
                    diagnose(.refractionUnsupported, path, "unsupportedMaterialProfile")
                    textureSource = nil
                } else if let normalReference = refractionPlan?.normalReference {
                    diagnose(
                        Self.isBuiltInTexture(normalReference)
                            ? .builtInTextureUnavailable : .missingTextureFile,
                        path,
                        normalReference
                    )
                    diagnose(.refractionUnsupported, path, "normalTextureUnavailable")
                    textureSource = nil
                }
            }

            let compiledRenderState = materialPass.flatMap {
                SceneMaterialRenderState.compile(
                    blending: $0.blending,
                    depthTest: $0.depthTest,
                    depthWrite: $0.depthWrite,
                    cullMode: $0.cullMode,
                    alphaWriting: $0.alphaWriting,
                    missingBlending: .translucent
                )
            }
            let pipelineState = compiledRenderState.flatMap {
                SceneParticlePipelineRenderStateCompiler.compile(
                    $0,
                    definition: definition,
                    materialPass: materialPass
                )
            }
            let renderState = pipelineState == nil ? nil : compiledRenderState
            switch pipelineState?.blendMode {
            case .additive, .translucent, .alphaToCoverage:
                break
            case nil where compiledRenderState?.blending == .normal:
                diagnose(.unsupportedBlendMode, path, "normal")
            case nil:
                if let materialPass {
                    switch SceneMaterialRenderState.compileBlending(
                        materialPass.blending, missing: .translucent
                    ) {
                    case .translucent, .additive, .alphaToCoverage:
                        diagnose(
                            .unsupportedRenderState,
                            path,
                            Self.renderStateSummary(materialPass)
                        )
                    case .normal, nil:
                        diagnose(.unsupportedBlendMode, path, materialPass.blending)
                    }
                }
            }

            let childPaths = Self.unique(definition.children.compactMap(\.path).map(Self.normalizedPath))
            assets[path] = SceneParticleAsset(
                relativePath: path,
                definition: definition,
                materialPass: materialPass,
                supportsBuiltInShaderExecution: supportsShader,
                textureSource: textureSource,
                refraction: refraction,
                renderState: renderState,
                pipelineState: pipelineState,
                childPaths: childPaths
            )
            visiting.insert(path)
            for childPath in childPaths { try visit(childPath) }
            visiting.remove(path)
        }

        for root in roots { try visit(root) }
        try checkCancellation?()
        return SceneParticleAssetGraph(
            rootPaths: roots,
            assetsByPath: assets,
            diagnostics: diagnostics.sorted {
                ($0.assetPath, $0.kind.rawValue, $0.detail ?? "")
                    < ($1.assetPath, $1.kind.rawValue, $1.detail ?? "")
            }
        )
    }

    /// The original definition owner discovers material/child dependencies.
    /// Raw bytes never cross the CPU preparation handoff and missing map rows
    /// at adoption never reopen the source.
    func prepareDefinitions(
        rootPaths: [String],
        checkCancellation: (() throws -> Void)? = nil,
        prepared: (String, PreparedDefinition) throws -> Void
    ) throws -> [String] {
        var seen: Set<String> = []
        var materials: [String] = []
        func visit(_ rawPath: String) throws {
            try checkCancellation?()
            let path = Self.normalizedPath(rawPath)
            guard !path.isEmpty, seen.insert(path).inserted else { return }
            let value: PreparedDefinition
            if let handle = resourceView.roots.first?.invariantHandle(relativePath: path) {
                do {
                    let data = try handle.readBytes(checkCancellation: checkCancellation)
                    try checkCancellation?()
                    let parsed = try? SceneParticleDefinitionParser().parse(data: data)
                    try checkCancellation?()
                    value = parsed.map(PreparedDefinition.parsed) ?? .invalid
                } catch let error as SceneResourceView.ReadError {
                    value = .readFailed(error)
                }
            } else { value = .missing }
            try prepared(path, value)
            guard case let .parsed(definition) = value else { return }
            if let material = definition.materialPath { materials.append(material) }
            for child in definition.children { if let path = child.path { try visit(path) } }
        }
        for root in rootPaths { try visit(root) }
        return Self.unique(materials)
    }

    private static func preferredPass(
        in passes: [SceneParticleMaterialPass]
    ) -> SceneParticleMaterialPass? {
        passes.first(where: { isGenericParticleShader($0.shaderPath) }) ?? passes.first
    }

    private static func isGenericParticleShader(_ rawPath: String?) -> Bool {
        guard let rawPath else { return false }
        let name = URL(fileURLWithPath: normalizedPath(rawPath)).deletingPathExtension().lastPathComponent
        return name == "genericparticle"
    }

    private func resolveTextureSource(named rawName: String) throws -> SceneParticleTextureSource? {
        let name = Self.normalizedPath(rawName)
        let bases = name.hasPrefix("materials/") ? [name] : ["materials/\(name)", name]
        var candidates = bases.flatMap { [$0, "\($0).tex"] }
        if URL(fileURLWithPath: name).pathExtension.isEmpty {
            candidates += bases.flatMap { ["\($0).png", "\($0).jpg", "\($0).jpeg"] }
        }
        // Preserve the old primary cache-root precedence across all texture
        // candidates, using its existing lookup instead of a second index.
        if let handle = candidates.lazy.compactMap({
            resourceView.roots.first?.invariantHandle(relativePath: $0)
        }).first {
            return .file(.resource(handle))
        }
        if let handle = candidates.lazy.compactMap({
            resourceView.resolvedResource(relativePath: $0)
        }).first {
            return .file(.resource(handle))
        }
        if let stock = try stockTextureResolver?.textureInput(for: name) {
            return .file(stock)
        }
        return SceneParticleTextureSource(reference: name)
    }

    private static func isBuiltInTexture(_ rawName: String) -> Bool {
        let name = normalizedPath(rawName)
        return name.hasPrefix("particle/") || name.hasPrefix("materials/particle/")
    }

    private static func renderStateSummary(
        _ pass: SceneParticleMaterialPass
    ) -> String {
        [
            pass.blending,
            pass.depthTest,
            pass.depthWrite,
            pass.cullMode,
            pass.alphaWriting,
        ].map { $0 ?? "<nil>" }.joined(separator: "/")
    }

    static func normalizedPath(_ rawPath: String) -> String {
        SceneResourceView.Root.invariantPathIdentity(rawPath)
    }

    private static func unique(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        return values.filter { seen.insert($0).inserted }
    }
}
