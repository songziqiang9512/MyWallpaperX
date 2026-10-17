import Foundation

// The document parser links Sound's named-input boundary. No named Sound
// script is present here: reaching that peripheral owner must fail this gate.
enum SceneScriptUserPropertyInputContract {
    static func validName(_ value: String) -> Bool {
        preconditionFailure("Named Sound inputs are outside the solid fixture")
    }
}

// Owned inputs and observations only: production parsing, descriptor projection
// and VFS texture resolution decide every result.
func sceneUserShortcutFallbackChecks(project: SceneProject) throws -> [String: [String: Any]] {
    let shortcut: [String: Any] = ["type": "usershortcut", "name": "ownedShortcut"]
    let system: [String: Any] = ["type": "system", "name": "$mediaThumbnail"]
    let property: [String: Any] = ["user": "cover"]
    let null = NSNull()
    func instance(_ inputs: Any, textures: Any = ["custom/carrier"]) -> [String: Any] {
        ["textures": textures, "usertextures": inputs]
    }
    let cases: [(String, Any, String)] = [
        ("plain", ["textures": ["custom/carrier"]], "solid"),
        ("null", instance([null]), "solid"),
        ("shortcut", instance([shortcut]), "solid"),
        ("registered-solid", ["id": 317, "textures": ["custom/carrier"],
            "usertextures": [shortcut], "combos": ["version": 2]], "registered"),
        ("renamed", instance([["type": "usershortcut", "name": " renamedKey "]],
            textures: [" renamed\\icons\\brush "]), "solid"),
        ("type-case", instance([["type": "UsErShOrTcUt", "name": "otherKey"]]), "solid"),
        ("empty-tail", instance([shortcut, null, null]), "solid"),
        ("unknown-type", instance([["type": "future", "name": "ownedShortcut"]]), "solid"),
        ("extra-key", instance([["type": "usershortcut", "name": "ownedShortcut", "future": true]]), "solid"),
        ("extra-user", instance([["type": "usershortcut", "name": "ownedShortcut", "user": "cover"]]), "solid"),
        ("missing-name", instance([["type": "usershortcut"]]), "solid"),
        ("empty-name", instance([["type": "usershortcut", "name": " \n "]]), "solid"),
        ("nonstring-name", instance([["type": "usershortcut", "name": 42]]), "solid"),
        ("nonstring-type", instance([["type": 42, "name": "ownedShortcut"]]), "solid"),
        ("malformed-users", instance(shortcut), "solid"),
        ("malformed-textures", instance([shortcut], textures: "custom/carrier"), "solid"),
        ("malformed-instance", 42, "solid"),
        ("multi-texture", instance([shortcut], textures: ["custom/carrier", "mask"]), "solid"),
        ("extra-null-texture", instance([shortcut], textures: ["custom/carrier", null]), "solid"),
        ("nonzero-shortcut", instance([null, shortcut]), "solid"),
        ("two-shortcuts", instance([shortcut, shortcut]), "solid"),
        ("mixed-system", instance([shortcut, system]), "solid"),
        ("mixed-property", instance([shortcut, property]), "solid"),
        ("known-system", instance([system]), "solid"),
        ("known-property", instance([property]), "solid"),
        ("unknown-instance-key", ["textures": ["custom/carrier"], "usertextures": [shortcut],
            "futureFlag": true], "solid"),
        ("allnil-unknown-key", ["textures": ["custom/carrier"], "usertextures": [null],
            "futureFlag": true], "solid"),
        ("ordinary-image", instance([shortcut]), "image"),
        ("puppet-solid", instance([shortcut]), "puppet"),
        ("model", instance([shortcut]), "model"),
        ("no-texture", instance([shortcut], textures: [] as [String]), "solid"),
        ("empty-texture", instance([shortcut], textures: [""]), "solid"),
        ("null-texture", instance([shortcut], textures: [null]), "solid"),
        ("missing-asset", instance([shortcut], textures: ["custom/missing"]), "solid"),
    ]
    let objects: [[String: Any]] = cases.enumerated().map { index, item in
        var object: [String: Any] = ["id": 500 + index, "name": item.0,
            "size": "90 60", "alpha": 0.35, "color": "0.2 0.4 0.6", "instance": item.1]
        switch item.2 {
        case "image": object["image"] = "models/owned/image.json"
        case "puppet": object["image"] = "models/owned/puppet-solid.json"
        case "registered": object["image"] = "models/owned/registered-solid.json"
        case "model": object["model"] = "models/owned/static.mdl"
        default: object["image"] = "models/util/solidlayer.json"
        }
        return object
    }
    let sceneURL = project.rootURL.appendingPathComponent("owned-user-shortcuts.json")
    try JSONSerialization.data(withJSONObject: ["objects": objects]).write(to: sceneURL)
    let renamedAsset = project.rootURL.appendingPathComponent("materials/renamed/icons/brush.tex")
    try FileManager.default.createDirectory(at: renamedAsset.deletingLastPathComponent(),
                                            withIntermediateDirectories: true)
    try Data("owned renamed resolver fixture".utf8).write(to: renamedAsset)
    let document = try SceneDocumentLoader().load(from: sceneURL)
    let catalog = SceneAssetCatalog(models: [.init(relativePath: "models/owned/registered-solid.json",
        materialPath: nil, cropOffsetXY: nil, isSolidLayer: true, declaredSizeWH: nil,
        puppetPath: nil, puppetAttachments: []), .init(relativePath: "models/owned/puppet-solid.json",
        materialPath: nil, cropOffsetXY: nil, isSolidLayer: true, declaredSizeWH: nil,
        puppetPath: "models/owned/rig.mdl", puppetAttachments: [])], materials: [],
        effectDefinitions: [], effectDefinitionDiagnostics: [], shaderReferences: [], textureReferences: [])
    let descriptor = SceneRenderDescriptorBuilder().build(project: project, sceneDocument: document,
        assetCatalog: catalog, resourceReferences: .init(missingReferences: [],
            builtInReferenceCount: 0, runtimeProvidedReferenceCount: 0),
        capabilityProfile: .init(firstStageRendererGaps: []))!
    let resolver = SceneTexturePathResolver(cacheDirectory: project.rootURL, descriptor: descriptor)
    return Dictionary(uniqueKeysWithValues: zip(document.objects, descriptor.layers).map { object, layer -> (String, [String: Any]) in
        let row: [String: Any] = ["staticPath": layer.staticBaseTexturePath ?? "",
            "resolvedFile": resolver.resolvePrimaryTexture(for: layer)?.lastPathComponent ?? "",
            "contentKind": layer.contentKind, "puppet": layer.puppetMeshPath != nil,
            "catalogHasModel": catalog.models.contains { $0.relativePath == layer.imagePath },
            "userKinds": object.materialInstance?.userTextureInputs.map { $0?.kind.rawValue ?? "nil" } ?? [],
            "userValues": object.materialInstance?.userTextureInputs.map { $0?.value ?? "nil" } ?? [],
            "malformed": object.materialInstance?.isMalformed ?? false,
            "unknownKeys": object.materialInstance?.unknownKeys ?? [],
            "size": layer.sizeWH ?? [], "alpha": layer.alpha ?? -1, "color": layer.colorRGB ?? []]
        return (object.name!, row)
    })
}
