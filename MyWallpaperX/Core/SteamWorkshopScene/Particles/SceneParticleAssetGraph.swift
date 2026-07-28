import Foundation

nonisolated enum SceneParticleMaterialBlendMode: String, Codable, Sendable {
    case translucent
    case additive
}

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
    let definitionURL: URL
    let definition: SceneParticleDefinition
    let materialPass: SceneParticleMaterialPass?
    let textureSource: SceneParticleTextureSource?
    let refraction: SceneParticleRefractionDeclaration?
    let blendMode: SceneParticleMaterialBlendMode
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
        case refractionUnsupported
    }

    let kind: Kind
    let assetPath: String
    let detail: String?
}

nonisolated struct SceneParticleAssetGraphLoader {
    private let stockTextureResolver: SceneStockTextureResolver?
    private let resourceView: SceneResourceView?

    init(
        resourceView: SceneResourceView? = nil,
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
        cacheDirectory: URL
    ) -> SceneParticleAssetGraph {
        let index = SceneResourceIndexBuilder().build(rootURL: cacheDirectory)
        let filesByPath = Dictionary(
            index.resources.map { (Self.normalizedPath($0.relativePath), $0.url) },
            uniquingKeysWith: { first, _ in first }
        )
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

        func visit(_ rawPath: String) {
            let path = Self.normalizedPath(rawPath)
            if visiting.contains(path) {
                diagnose(.cyclicChildReference, path)
                return
            }
            guard attempted.insert(path).inserted else { return }
            guard let definitionURL = filesByPath[path] else {
                diagnose(.missingDefinition, path)
                return
            }
            guard let data = try? Data(contentsOf: definitionURL),
                  let definition = try? SceneParticleDefinitionParser().parse(data: data) else {
                diagnose(.invalidDefinition, path)
                return
            }

            let materialPath = definition.materialPath.map(Self.normalizedPath)
            let materialPass = materialPath.flatMap { path in
                Self.preferredPass(in: passesByMaterial[path] ?? [])
            }
            if materialPass == nil {
                diagnose(.missingMaterial, path, materialPath)
            } else if !Self.isGenericParticleShader(materialPass?.shaderPath) {
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
            var textureSource = textureName.flatMap {
                resolveTextureSource(named: $0, filesByPath: filesByPath)
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
                   let normal = resolveTextureSource(
                       named: refractionPlan.normalReference,
                       filesByPath: filesByPath
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

            let blendMode: SceneParticleMaterialBlendMode
            switch materialPass?.blending?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            case "additive":
                blendMode = .additive
            case nil, "", "translucent":
                blendMode = .translucent
            case let value?:
                blendMode = .translucent
                diagnose(.unsupportedBlendMode, path, value)
            }

            let childPaths = Self.unique(definition.children.compactMap(\.path).map(Self.normalizedPath))
            assets[path] = SceneParticleAsset(
                relativePath: path,
                definitionURL: definitionURL,
                definition: definition,
                materialPass: materialPass,
                textureSource: textureSource,
                refraction: refraction,
                blendMode: blendMode,
                childPaths: childPaths
            )
            visiting.insert(path)
            for childPath in childPaths { visit(childPath) }
            visiting.remove(path)
        }

        for root in roots { visit(root) }
        return SceneParticleAssetGraph(
            rootPaths: roots,
            assetsByPath: assets,
            diagnostics: diagnostics.sorted {
                ($0.assetPath, $0.kind.rawValue, $0.detail ?? "")
                    < ($1.assetPath, $1.kind.rawValue, $1.detail ?? "")
            }
        )
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

    private func resolveTextureSource(
        named rawName: String,
        filesByPath: [String: URL]
    ) -> SceneParticleTextureSource? {
        let name = Self.normalizedPath(rawName)
        let bases = name.hasPrefix("materials/") ? [name] : ["materials/\(name)", name]
        var candidates = bases.flatMap { [$0, "\($0).tex"] }
        if URL(fileURLWithPath: name).pathExtension.isEmpty {
            candidates += bases.flatMap { ["\($0).png", "\($0).jpg", "\($0).jpeg"] }
        }
        if let localURL = candidates.lazy.compactMap({ filesByPath[$0] }).first {
            return .file(localURL)
        }
        if let resource = candidates.lazy.compactMap({
            resourceView?.resource(relativePath: $0)
        }).first {
            return .file(resource.url)
        }
        if let stockURL = stockTextureResolver?.textureURL(for: name) {
            return .file(stockURL)
        }
        return SceneParticleTextureSource(reference: name)
    }

    private static func isBuiltInTexture(_ rawName: String) -> Bool {
        let name = normalizedPath(rawName)
        return name.hasPrefix("particle/") || name.hasPrefix("materials/particle/")
    }

    static func normalizedPath(_ rawPath: String) -> String {
        var value = rawPath
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\", with: "/")
        while value.hasPrefix("./") { value.removeFirst(2) }
        return value.lowercased()
    }

    private static func unique(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        return values.filter { seen.insert($0).inserted }
    }
}
