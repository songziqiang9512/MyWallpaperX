import Foundation

nonisolated enum SceneParticleMaterialBlendMode: String, Codable, Sendable {
    case translucent
    case additive
}

nonisolated struct SceneParticleMaterialPass: Equatable, Sendable {
    let materialPath: String
    let shaderPath: String?
    let texturePaths: [String]
    let blending: String?
    let combos: [String: Int]

    init(
        materialPath: String,
        shaderPath: String?,
        texturePaths: [String],
        blending: String?,
        combos: [String: Int] = [:]
    ) {
        self.materialPath = materialPath
        self.shaderPath = shaderPath
        self.texturePaths = texturePaths
        self.blending = blending
        self.combos = combos
    }
}

nonisolated struct SceneParticleAsset: Sendable {
    let relativePath: String
    let definitionURL: URL
    let definition: SceneParticleDefinition
    let materialPass: SceneParticleMaterialPass?
    let textureSource: SceneParticleTextureSource?
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

            let textureName = materialPass?.texturePaths.first
            if textureName == nil {
                diagnose(.missingTextureReference, path, materialPath)
            }
            var textureSource = textureName.flatMap {
                Self.resolveTextureSource(named: $0, filesByPath: filesByPath)
            }
            if let textureName, textureSource == nil {
                diagnose(
                    Self.isBuiltInTexture(textureName) ? .builtInTextureUnavailable : .missingTextureFile,
                    path,
                    textureName
                )
            }
            // Refraction particles carry a blank color texture and rely on a
            // normal-map distortion of the backdrop; sampling the blank as a
            // color source paints solid white sprites. Fail closed until a
            // real refraction pass exists.
            if let refract = materialPass?.combos["REFRACT"], refract != 0 {
                diagnose(.refractionUnsupported, path, "REFRACT=\(refract)")
                textureSource = nil
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

    private static func resolveTextureSource(
        named rawName: String,
        filesByPath: [String: URL]
    ) -> SceneParticleTextureSource? {
        let name = normalizedPath(rawName)
        let bases = name.hasPrefix("materials/") ? [name] : ["materials/\(name)", name]
        var candidates = bases.flatMap { [$0, "\($0).tex"] }
        if URL(fileURLWithPath: name).pathExtension.isEmpty {
            candidates += bases.flatMap { ["\($0).png", "\($0).jpg", "\($0).jpeg"] }
        }
        if let localURL = candidates.lazy.compactMap({ filesByPath[$0] }).first {
            return .file(localURL)
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
