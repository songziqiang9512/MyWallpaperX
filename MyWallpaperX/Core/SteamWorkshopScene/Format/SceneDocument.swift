import Foundation

struct SceneDocument {
    // Camera node from scene.json; defaults look along -Z with Y up.
    struct CameraDescriptor: Codable {
        let eye: [Float]      // [x, y, z], default [0, 0, 0]
        let center: [Float]   // [x, y, z], default [0, 0, -1]
        let up: [Float]       // [x, y, z], default [0, 1, 0]
    }

    struct SceneEffect: Identifiable {
        struct Pass: Identifiable {
            let id: Int?
            let textures: [String]
            let textureSlots: [String?]
            let userTextureInputs: [SceneEffectTextureInput?]
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

    let sourceURL: URL
    let declaredVersion: SceneDeclaredInteger
    let camera: CameraDescriptor
    let general: GeneralDescriptor
    let objectCount: Int
    let effectCount: Int
    let referencedResourcePaths: [String]
    let objects: [SceneObject]
    let scriptBindings: [SceneScriptBindingIR]
    let scriptBindingDiagnostics: [SceneScriptBindingDiagnostic]
    let scriptSourceEvidence: [SceneScriptSourceEvidenceIR]
    let userPropertyResolution: SceneUserPropertyResolution
}

extension SceneDocument {
    var materialInstancesByLayerID: [Int: SceneLayerMaterialInstance] {
        Dictionary(uniqueKeysWithValues: objects.compactMap { object in
            object.materialInstance.map { (object.id, $0) }
        })
    }
}

struct SceneDocumentLoader {
    enum LoadError: LocalizedError {
        case missingSceneJSON
        case invalidSceneJSON(URL)
        case duplicateObjectIDs(URL, [Int])

        var errorDescription: String? {
            switch self {
            case .missingSceneJSON:
                return "未找到可解析的 scene.json。"
            case let .invalidSceneJSON(url):
                return "无法解析 Scene 入口文件：\(url.path)"
            case let .duplicateObjectIDs(url, ids):
                let values = ids.map(String.init).joined(separator: ", ")
                return "Scene 入口包含重复对象 ID（\(values)）：\(url.path)"
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
        // Script IR 必须读取作者原始 wrapper；property resolver 会按运行覆盖改写 `value`，
        // 不能让当前用户值冒充 authored fallback。
        let scriptBindings = SceneScriptBindingIRParser.parse(document: sourceRoot)
        let scriptSourceEvidence = SceneScriptSourceEvidenceCollector.collect(
            document: sourceRoot
        )
        let propertyResolution = SceneUserPropertyDocumentResolver().resolve(
            root: sourceRoot,
            catalog: propertyCatalog,
            overrides: propertyOverrides
        )
        let root = propertyResolution.root

        let rawObjects = root["objects"] as? [[String: Any]] ?? []
        let authoredObjects = sourceRoot["objects"] as? [[String: Any]] ?? []
        let objects = rawObjects.enumerated().compactMap { index, object in
            Self.parseObject(
                object,
                authoredRoot: authoredObjects.indices.contains(index)
                    ? authoredObjects[index]
                    : object
            )
        }
        let duplicateObjectIDs = Dictionary(grouping: objects, by: \.id)
            .compactMap { id, matches in matches.count > 1 ? id : nil }
            .sorted()
        guard duplicateObjectIDs.isEmpty else {
            throw LoadError.duplicateObjectIDs(sourceURL, duplicateObjectIDs)
        }
        let referencedPaths = Set(objects.flatMap { object in
            [object.imagePath, object.staticModelPath, object.particlePath]
                .compactMap { $0 }
                + (object.sound?.paths ?? [])
                + object.effectFiles + object.texturePaths
        })

        return SceneDocument(
            sourceURL: sourceURL,
            declaredVersion: SceneDeclaredInteger.parse(root: sourceRoot, fieldName: "version"),
            camera: Self.parseCamera(root["camera"] as? [String: Any]),
            general: Self.parseGeneral(root["general"] as? [String: Any]),
            objectCount: rawObjects.count,
            effectCount: objects.reduce(0) { $0 + $1.effectFiles.count },
            referencedResourcePaths: referencedPaths.sorted {
                $0.localizedStandardCompare($1) == .orderedAscending
            },
            objects: objects,
            scriptBindings: scriptBindings.bindings,
            scriptBindingDiagnostics: scriptBindings.diagnostics,
            scriptSourceEvidence: scriptSourceEvidence,
            userPropertyResolution: propertyResolution
        )
    }

    nonisolated private static func parseCamera(_ root: [String: Any]?) -> SceneDocument.CameraDescriptor {
        let eye = floatVector(root?["eye"]) ?? [0, 0, 0]
        let center = floatVector(root?["center"]) ?? [0, 0, -1]
        let up = floatVector(root?["up"]) ?? [0, 1, 0]
        return SceneDocument.CameraDescriptor(eye: eye, center: center, up: up)
    }

    nonisolated private static func parseObject(
        _ root: [String: Any],
        authoredRoot: [String: Any]
    ) -> SceneDocument.SceneObject? {
        guard let id = root["id"] as? Int else { return nil }
        let effects = root["effects"] as? [[String: Any]] ?? []
        let parsedEffects = effects.compactMap(Self.parseEffect)
        let effectFiles = parsedEffects.map(\.file)
        let texturePaths = effects.flatMap(Self.effectTexturePaths)
        let text = textValue(root["text"])
        let imagePath = normalizedPath(root["image"] as? String)
        let timelines = objectTimelines(root)
        let particleTimelines = particleTimelines(root["instanceoverride"])
        let dependencies = SceneObjectDependencies(rawValue: root["dependencies"])

        return SceneDocument.SceneObject(
            id: id,
            name: root["name"] as? String,
            cameraPath: SceneDocument.Scene2DCameraPathDefinition.parse(root),
            imagePath: imagePath,
            staticModelPath: normalizedPath(root["model"] as? String),
            particlePath: normalizedPath(root["particle"] as? String),
            sound: SceneDocument.SceneSoundLayerDefinition.parse(
                resolvedObject: root,
                authoredObject: authoredRoot
            ),
            spotLight: SceneSpotLightDefinition.parse(root),
            directionalLight: SceneDirectionalLightDefinition.parse(root),
            particleInstanceOverride: SceneParticleDefinitionParser().parseInstanceOverride(
                root["instanceoverride"]
            ),
            materialInstance: SceneDocument.SceneLayerMaterialInstance.parse(
                root["instance"],
                authoredRaw: authoredRoot["instance"]
            ),
            utilityLayer: SceneUtilityLayer.parse(imagePath: imagePath, object: root),
            shape: stringValue(root["shape"])?.lowercased(),
            dependencyLayerIDs: dependencies.flatLayerIDs,
            authoredDependencies: dependencies.authored,
            parentID: root["parent"] as? Int,
            attachmentName: stringValue(root["attachment"]).flatMap { $0.isEmpty ? nil : $0 },
            puppetAnimationLayers: ScenePuppetAnimationLayer.parse(root["animationlayers"]),
            visible: visibleValue(root["visible"]),
            alpha: doubleValue(root["alpha"]),
            displayScriptOwnership: .parse(authoredObject: authoredRoot),
            colorRGB: floatVector(root["color"]),
            colorBlendMode: root["colorBlendMode"] as? Int,
            brightness: doubleValue(root["brightness"]),
            imageAlignment: stringValue(root["alignment"]),
            origin: stringValue(root["origin"]),
            size: stringValue(root["size"]),
            scale: stringValue(root["scale"]),
            scaleHasScript: (authoredRoot["scale"] as? [String: Any])?["script"]
                is String,
            angles: stringValue(root["angles"]),
            parallaxDepth: stringValue(root["parallaxDepth"]),
            disablesParallaxPropagation: visibleValue(root["disablepropagation"]) ?? false,
            usesPerspective: root["perspective"] as? Bool ?? false,
            text: text,
            textStyle: text == nil ? nil : SceneTextDescriptor.parse(root),
            textScript: SceneTextScriptDefinition.parse(root["text"]),
            scriptBindings: SceneScriptBindingDefinition.parseLayerProperties(in: root),
            textureAnimationScripts:
                SceneTextureAnimationScriptDefinition.parseLayerProperties(in: root),
            hasInlineScript: containsInlineScript(root),
            effects: parsedEffects,
            effectFiles: uniqueSorted(effectFiles),
            texturePaths: uniqueSorted(texturePaths),
            timelines: timelines.animations,
            timelineDiagnostics: timelines.diagnostics,
            particleTimelines: particleTimelines.animations,
            particleTimelineDiagnostics: particleTimelines.diagnostics
        )
    }

    nonisolated private static func parseEffect(_ root: [String: Any]) -> SceneDocument.SceneEffect? {
        guard let file = normalizedPath(root["file"] as? String) else { return nil }
        let passes = (root["passes"] as? [[String: Any]] ?? []).map { pass in
            SceneDocument.SceneEffect.Pass(
                id: pass["id"] as? Int,
                textures: texturePaths(in: pass),
                textureSlots: (pass["textures"] as? [Any] ?? []).map { normalizedPath($0 as? String) },
                userTextureInputs: (pass["usertextures"] as? [Any] ?? []).map(SceneEffectTextureInput.parse),
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

    nonisolated static func visibleValue(_ value: Any?) -> Bool? {
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
        if let keyed = value as? [String: Any] {
            return doubleValue(keyed["value"])
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
            let rawValue: String
            if let string = stringValue(keyed["value"]) { rawValue = string }
            else if let number = doubleValue(keyed["value"]) { rawValue = String(number) }
            else { rawValue = "\(keyed)" }
            let components = numericComponents(in: rawValue)
            let timeline = SceneTimelineAnimationParser.parse(host: keyed)
            return SceneDocument.ShaderValue(
                rawValue: rawValue,
                valueKind: "binding",
                userBinding: keyed["user"] as? String,
                userValueKind: keyed["user"].flatMap(
                    SceneShaderUserValueKind.init(jsonObject:)
                ),
                components: components.isEmpty ? nil : components,
                timeline: timeline.animation,
                timelineDiagnostics: timeline.diagnostics.map(\.token),
                scriptSource: keyed["script"] as? String,
                scriptProperties: scriptProperties(keyed["scriptproperties"]),
                bindingKeys: uniqueSorted(Array(keyed.keys))
            )
        }
        return SceneDocument.ShaderValue(
            rawValue: "\(value)",
            valueKind: "unknown",
            userBinding: nil,
            components: nil
        )
    }

    nonisolated private static func scriptProperties(
        _ value: Any?
    ) -> [String: SceneJSONValue]? {
        guard let object = value as? [String: Any] else { return nil }
        var result: [String: SceneJSONValue] = [:]
        for (key, value) in object {
            guard let parsed = SceneJSONValue(jsonObject: value) else {
                return nil
            }
            result[key] = parsed
        }
        return result
    }

    nonisolated private static func numericComponents(in string: String) -> [Double] {
        string
            .split(whereSeparator: { $0 == " " || $0 == "," || $0 == "\t" })
            .compactMap { Double($0) }
    }

    nonisolated private static func normalizedPath(_ path: String?) -> String? {
        guard let path else { return nil }
        let normalized = path.replacingOccurrences(of: "\\", with: "/")
        return normalized.isEmpty ? nil : normalized
    }

    nonisolated private static func uniqueSorted(_ values: [String]) -> [String] {
        Array(Set(values)).sorted {
            $0.localizedStandardCompare($1) == .orderedAscending
        }
    }
}
