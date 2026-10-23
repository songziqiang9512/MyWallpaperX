import Foundation

func referenceToken(_ value: SceneResolvedMaterialTemplate.TextureReference) -> String {
    switch value {
    case let .asset(request): return "asset:\(request.value)"
    case let .userProperty(request): return "property:\(request.key)"
    case let .provider(identity):
        switch identity {
        case let .system(name): return "system:\(name)"
        case let .namedLayerTarget(reference):
            return "named:\(reference.providerLayerID):\(reference.variant.rawValue)"
        case let .sceneBackground(consumerLayerID):
            return "scene-background:\(consumerLayerID)"
        case .sceneEnvironment: return "scene-environment"
        }
    case let .graph(identity): return "graph:\(identity.kind.rawValue):\(identity.layerID)"
    }
}

/// The preparation ingress changes identity only; Resolver/Template retain
/// their real candidate precedence and existing provider/path admission.
func declaredTextureInputChecks(shader: SceneShaderContract) -> [String: Bool] {
    typealias Input = SceneEffectTextureInput
    let declared: Set<String> = ["_1", "_renamedCover", "photo", "path.png",
        "folder/cover", "_rt_FullFrameBuffer", "_RT_FullFrameBuffer", "_rt_unknown"]
    func parse(_ raw: Any, keys: Set<String>? = nil) -> Input? {
        Input.parse(raw, declaredTexturePropertyKeys: keys ?? declared)
    }
    func reference(_ raw: Any, keys: Set<String>? = nil) -> String? {
        let pass = SceneRenderDescriptor.MaterialPassDescriptor(
            id: "materials/renamed.json#0", materialPath: "materials/renamed.json",
            shaderPath: shader.identity, textureSlots: ["textures/renamed.png"],
            userTextureInputs: [parse(raw, keys: keys)], combos: [:],
            constantShaderValues: [:], userShaderValues: [:], blending: "normal",
            depthTest: "disabled", depthWrite: "disabled", cullMode: "nocull",
            alphaWriting: nil)
        guard let node = SceneAuthoredMaterialResolver.resolveSourceMaterial(material: pass).node,
              case let .success(template) = SceneResolvedMaterialTemplateCompiler.compileSourceMaterial(
                material: node, layerID: 909, materialPath: pass.materialPath, passIndex: 0,
                shaderContract: shader, renderState: .init(
                    rawValues: .init(blending: "normal", depthTest: "disabled",
                        depthWrite: "disabled", cullMode: "nocull", alphaWriting: nil),
                    blending: .normal, depthTest: .disabled, depthWrite: .disabled,
                    cullMode: .noCull, alphaWriting: .unspecified)),
              let input = template.textureSlots[0]?.candidates.last?.reference else { return nil }
        switch input {
        case let .userProperty(value): return "property:" + value.key
        case let .asset(value): return "asset:" + value.value
        case .provider(.sceneBackground): return "background"
        default: return "other"
        }
    }
    return [
        "declaredUnderscoreReachesTemplate": reference("_1") == "property:_1",
        "declaredRenamedKeyReachesTemplate": reference("_renamedCover") == "property:_renamedCover",
        "declaredBareKeyUnchanged": reference("photo") == "property:photo",
        "undeclaredUnderscoreStaysAsset": reference("_1", keys: []) == "asset:_1",
        "declarationIsCaseSensitive": reference("_RenamedCover") == "asset:_renamedcover",
        "declaredDotPathStaysAsset": reference("path.png") == "asset:path.png",
        "declaredSlashPathStaysAsset": reference("folder/cover") == "asset:folder/cover",
        "declaredBackslashStaysPath": parse("folder\\cover")?.kind == .path,
        "declaredInternalRTKeepsVocabulary": ["_rt_FullFrameBuffer", "_RT_FullFrameBuffer", "_rt_unknown"].allSatisfy {
            parse($0)?.kind == .path && reference($0) == reference($0, keys: [])
        },
        "explicitUserKeepsIdentity": reference(["user": "_1"], keys: []) == "property:_1",
        "explicitSystemKeepsIdentity": parse(["type": "system", "name": "_1"])?.kind == .system,
        "explicitShortcutKeepsIdentity": parse(["type": "usershortcut", "name": "_1"])?.kind == .userShortcut,
        "explicitUnknownStaysUnknown": parse(["type": "future", "name": "_1"])?.kind == .unknown,
        "explicitMalformedSystemStaysUnknown": parse(["type": "system", "name": "_1", "extra": true])?.kind == .unknown,
        "emptyAndNullRemainAbsent": parse("") == nil && parse(NSNull()) == nil,
    ]
}
