import Foundation

struct SceneDocument {
    // Camera node from scene.json. eye/center/up are in world coords; defaults
    // match Wallpaper Engine's typical layout (look along -Z, Y up).
    struct CameraDescriptor: Codable {
        let eye: [Float]      // [x, y, z], default [0, 0, 0]
        let center: [Float]   // [x, y, z], default [0, 0, -1]
        let up: [Float]       // [x, y, z], default [0, 1, 0]
    }

    // general.* — only fields we currently consume.
    struct GeneralDescriptor: Codable {
        let orthoWidth: Float?     // general.orthogonalprojection.width
        let orthoHeight: Float?    // general.orthogonalprojection.height
        let clearColor: [Float]?   // [r, g, b] in 0..1, from general.clearcolor
        let clearEnabled: Bool
        let nearZ: Float?
        let farZ: Float?
        let cameraParallaxEnabled: Bool
        let cameraParallaxAmount: Float
        let cameraParallaxDelay: Float
        let cameraParallaxMouseInfluence: Float
    }

    struct ShaderValue: Codable {
        let rawValue: String
        let valueKind: String
        let userBinding: String?
        let components: [Double]?
    }

    struct SceneEffect: Identifiable {
        struct Pass: Identifiable {
            let id: Int?
            let textures: [String]
            let textureSlots: [String?]
            let combos: [String: Int]
            let constantShaderValues: [String: ShaderValue]
            let constantShaderValueKeys: [String]
        }

        let id: Int?
        let name: String?
        let file: String
        let visible: Bool?
        let passes: [Pass]
    }

    struct SceneObject: Identifiable {
        let id: Int
        let name: String?
        let imagePath: String?
        let particlePath: String?
        let particleInstanceOverride: SceneParticleInstanceOverride?
        let parentID: Int?
        let visible: Bool?
        let alpha: Double?
        let colorBlendMode: Int?
        let origin: String?
        let size: String?
        let scale: String?
        let angles: String?
        let parallaxDepth: String?
        let disablesParallaxPropagation: Bool
        let text: String?
        let textStyle: SceneTextDescriptor?
        let hasInlineScript: Bool
        let effects: [SceneEffect]
        let effectFiles: [String]
        let texturePaths: [String]
    }

    let sourceURL: URL
    let version: Int?
    let camera: CameraDescriptor
    let general: GeneralDescriptor
    let objectCount: Int
    let effectCount: Int
    let referencedResourcePaths: [String]
    let objects: [SceneObject]
    let userPropertyResolution: SceneUserPropertyResolution
}

struct SceneDocumentLoader {
    enum LoadError: LocalizedError {
        case missingSceneJSON
        case invalidSceneJSON(URL)

        var errorDescription: String? {
            switch self {
            case .missingSceneJSON:
                return "未找到可解析的 scene.json。"
            case let .invalidSceneJSON(url):
                return "无法解析 Scene 入口文件：\(url.path)"
            }
        }
    }

    nonisolated func load(
        project: SceneProject,
        packageReport: ScenePkgExtractionReport?,
        propertyOverrides: [String: SceneUserPropertyValue] = [:]
    ) throws -> SceneDocument {
        let candidates = [
            packageReport?.outputURL?.appendingPathComponent(project.entryPath),
            project.entryURL
        ].compactMap { $0 }

        guard let sourceURL = candidates.first(where: { FileManager.default.fileExists(atPath: $0.path) }) else {
            throw LoadError.missingSceneJSON
        }
        return try load(from: sourceURL, propertyCatalog: project.userProperties, propertyOverrides: propertyOverrides)
    }

    nonisolated func load(
        from sourceURL: URL,
        propertyCatalog: SceneUserPropertyCatalog = .empty,
        propertyOverrides: [String: SceneUserPropertyValue] = [:]
    ) throws -> SceneDocument {
        let data = try Data(contentsOf: sourceURL)
        guard let sourceRoot = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw LoadError.invalidSceneJSON(sourceURL)
        }
        let propertyResolution = SceneUserPropertyDocumentResolver().resolve(
            root: sourceRoot,
            catalog: propertyCatalog,
            overrides: propertyOverrides
        )
        let root = propertyResolution.root

        let rawObjects = root["objects"] as? [[String: Any]] ?? []
        let objects = rawObjects.compactMap(Self.parseObject)
        let referencedPaths = Set(objects.flatMap { object in
            [object.imagePath, object.particlePath].compactMap { $0 } + object.effectFiles + object.texturePaths
        })

        return SceneDocument(
            sourceURL: sourceURL,
            version: root["version"] as? Int,
            camera: Self.parseCamera(root["camera"] as? [String: Any]),
            general: Self.parseGeneral(root["general"] as? [String: Any]),
            objectCount: rawObjects.count,
            effectCount: objects.reduce(0) { $0 + $1.effectFiles.count },
            referencedResourcePaths: referencedPaths.sorted {
                $0.localizedStandardCompare($1) == .orderedAscending
            },
            objects: objects,
            userPropertyResolution: propertyResolution
        )
    }

    nonisolated private static func parseCamera(_ root: [String: Any]?) -> SceneDocument.CameraDescriptor {
        let eye = floatVector(root?["eye"]) ?? [0, 0, 0]
        let center = floatVector(root?["center"]) ?? [0, 0, -1]
        let up = floatVector(root?["up"]) ?? [0, 1, 0]
        return SceneDocument.CameraDescriptor(eye: eye, center: center, up: up)
    }

    nonisolated private static func parseGeneral(_ root: [String: Any]?) -> SceneDocument.GeneralDescriptor {
        let ortho = root?["orthogonalprojection"] as? [String: Any]
        let width = ortho?["width"].flatMap { Self.floatValue($0) }
        let height = ortho?["height"].flatMap { Self.floatValue($0) }
        let clearColor = floatVector(root?["clearcolor"])
        let clearEnabled = (root?["clearenabled"] as? Bool) ?? true
        let nearZ = root?["nearz"].flatMap { Self.floatValue($0) }
        let farZ = root?["farz"].flatMap { Self.floatValue($0) }
        let cameraParallaxEnabled = visibleValue(root?["cameraparallax"]) ?? false
        return SceneDocument.GeneralDescriptor(
            orthoWidth: width,
            orthoHeight: height,
            clearColor: clearColor,
            clearEnabled: clearEnabled,
            nearZ: nearZ,
            farZ: farZ,
            cameraParallaxEnabled: cameraParallaxEnabled,
            cameraParallaxAmount: root?["cameraparallaxamount"].flatMap(Self.floatValue) ?? 0,
            cameraParallaxDelay: root?["cameraparallaxdelay"].flatMap(Self.floatValue) ?? 0,
            cameraParallaxMouseInfluence: root?["cameraparallaxmouseinfluence"].flatMap(Self.floatValue) ?? 0
        )
    }

    nonisolated private static func parseObject(_ root: [String: Any]) -> SceneDocument.SceneObject? {
        guard let id = root["id"] as? Int else { return nil }
        let effects = root["effects"] as? [[String: Any]] ?? []
        let parsedEffects = effects.compactMap(Self.parseEffect)
        let effectFiles = parsedEffects.map(\.file)
        let texturePaths = effects.flatMap(Self.effectTexturePaths)
        let text = textValue(root["text"])
        let imagePath = normalizedPath(root["image"] as? String)
        let parallaxDepth = stringValue(root["parallaxDepth"])
            ?? (imagePath?.lowercased() == "models/util/composelayer.json" ? "1 1" : nil)

        return SceneDocument.SceneObject(
            id: id,
            name: root["name"] as? String,
            imagePath: imagePath,
            particlePath: normalizedPath(root["particle"] as? String),
            particleInstanceOverride: SceneParticleDefinitionParser().parseInstanceOverride(
                root["instanceoverride"]
            ),
            parentID: root["parent"] as? Int,
            visible: visibleValue(root["visible"]),
            alpha: doubleValue(root["alpha"]),
            colorBlendMode: root["colorBlendMode"] as? Int,
            origin: stringValue(root["origin"]),
            size: stringValue(root["size"]),
            scale: stringValue(root["scale"]),
            angles: stringValue(root["angles"]),
            parallaxDepth: parallaxDepth,
            disablesParallaxPropagation: visibleValue(root["disablepropagation"]) ?? false,
            text: text,
            textStyle: text == nil ? nil : SceneTextDescriptor.parse(root),
            hasInlineScript: containsInlineScript(root),
            effects: parsedEffects,
            effectFiles: uniqueSorted(effectFiles),
            texturePaths: uniqueSorted(texturePaths)
        )
    }

    nonisolated private static func parseEffect(_ root: [String: Any]) -> SceneDocument.SceneEffect? {
        guard let file = normalizedPath(root["file"] as? String) else { return nil }
        let passes = (root["passes"] as? [[String: Any]] ?? []).map { pass in
            SceneDocument.SceneEffect.Pass(
                id: pass["id"] as? Int,
                textures: texturePaths(in: pass),
                textureSlots: (pass["textures"] as? [Any] ?? []).map { normalizedPath($0 as? String) },
                combos: pass["combos"] as? [String: Int] ?? [:],
                constantShaderValues: constantShaderValues(in: pass),
                constantShaderValueKeys: constantShaderValueKeys(in: pass)
            )
        }

        return SceneDocument.SceneEffect(
            id: root["id"] as? Int,
            name: root["name"] as? String,
            file: file,
            visible: visibleValue(root["visible"]),
            passes: passes
        )
    }

    nonisolated private static func visibleValue(_ value: Any?) -> Bool? {
        if let bool = value as? Bool {
            return bool
        }
        if let keyed = value as? [String: Any] {
            return keyed["value"] as? Bool
        }
        return nil
    }

    nonisolated private static func doubleValue(_ value: Any?) -> Double? {
        if let double = value as? Double {
            return double
        }
        if let int = value as? Int {
            return Double(int)
        }
        return nil
    }

    nonisolated private static func stringValue(_ value: Any?) -> String? {
        if let string = value as? String {
            return string
        }
        if let keyed = value as? [String: Any] {
            return keyed["value"] as? String
        }
        return nil
    }

    nonisolated private static func textValue(_ value: Any?) -> String? {
        if let string = value as? String {
            return string
        }
        if let keyed = value as? [String: Any] {
            return keyed["value"] as? String
        }
        return nil
    }

    nonisolated private static func containsInlineScript(_ value: Any?) -> Bool {
        if let keyed = value as? [String: Any],
           keyed["script"] is String {
            return true
        }
        if let array = value as? [Any] {
            return array.contains { containsInlineScript($0) }
        }
        if let keyed = value as? [String: Any] {
            return keyed.values.contains { containsInlineScript($0) }
        }
        return false
    }

    nonisolated private static func effectTexturePaths(in effect: [String: Any]) -> [String] {
        let passes = effect["passes"] as? [[String: Any]] ?? []
        return passes.flatMap { pass in
            guard let textures = pass["textures"] as? [Any] else { return [String]() }
            return textures.compactMap { normalizedPath($0 as? String) }
        }
    }

    nonisolated private static func texturePaths(in pass: [String: Any]) -> [String] {
        guard let textures = pass["textures"] as? [Any] else { return [] }
        return textures.compactMap { normalizedPath($0 as? String) }
    }

    nonisolated private static func constantShaderValueKeys(in pass: [String: Any]) -> [String] {
        guard let values = pass["constantshadervalues"] as? [String: Any] else { return [] }
        return uniqueSorted(Array(values.keys))
    }

    nonisolated private static func constantShaderValues(in pass: [String: Any]) -> [String: SceneDocument.ShaderValue] {
        guard let values = pass["constantshadervalues"] as? [String: Any] else { return [:] }
        return values.reduce(into: [String: SceneDocument.ShaderValue]()) { result, pair in
            result[pair.key] = shaderValue(from: pair.value)
        }
    }

    nonisolated private static func shaderValue(from value: Any) -> SceneDocument.ShaderValue {
        if let double = value as? Double {
            return SceneDocument.ShaderValue(
                rawValue: String(double),
                valueKind: "number",
                userBinding: nil,
                components: [double]
            )
        }
        if let int = value as? Int {
            return SceneDocument.ShaderValue(
                rawValue: String(int),
                valueKind: "number",
                userBinding: nil,
                components: [Double(int)]
            )
        }
        if let string = value as? String {
            let components = numericComponents(in: string)
            return SceneDocument.ShaderValue(
                rawValue: string,
                valueKind: components.count > 1 ? "vector" : "string",
                userBinding: nil,
                components: components.isEmpty ? nil : components
            )
        }
        if let keyed = value as? [String: Any] {
            let rawValue = stringValue(keyed["value"]) ?? "\(keyed)"
            let components = numericComponents(in: rawValue)
            return SceneDocument.ShaderValue(
                rawValue: rawValue,
                valueKind: "binding",
                userBinding: keyed["user"] as? String,
                components: components.isEmpty ? nil : components
            )
        }
        return SceneDocument.ShaderValue(
            rawValue: "\(value)",
            valueKind: "unknown",
            userBinding: nil,
            components: nil
        )
    }

    nonisolated private static func numericComponents(in string: String) -> [Double] {
        string
            .split(whereSeparator: { $0 == " " || $0 == "," || $0 == "\t" })
            .compactMap { Double($0) }
    }

    nonisolated private static func normalizedPath(_ path: String?) -> String? {
        guard let path else { return nil }
        let normalized = path
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\", with: "/")
        return normalized.isEmpty ? nil : normalized
    }

    nonisolated private static func uniqueSorted(_ values: [String]) -> [String] {
        Array(Set(values)).sorted {
            $0.localizedStandardCompare($1) == .orderedAscending
        }
    }
}
