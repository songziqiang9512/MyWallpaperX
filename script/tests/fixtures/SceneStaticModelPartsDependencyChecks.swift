import Foundation

/// Actual Builder and Root stage. The native target uses the same owned tree
/// with its preexisting descriptor/texture transport and explicit fields below.
@main enum PartsDependencies {
    static func main() throws {
        let input = try JSONSerialization.jsonObject(with: Data(contentsOf:
            URL(fileURLWithPath: CommandLine.arguments[1]))) as! [String: String]
        let root = URL(fileURLWithPath: input["root"]!)
        let names = input["names"]?.components(separatedBy: ",") ?? ["parts5", "parts8", "parts64", "bad8"]
        var rows: [[String: Any]] = []
        for name in names {
            let model = try SceneRuntimeModelBuilder().build(rootURL: root.appendingPathComponent(name))
            let descriptor = model.renderDescriptor
            let modelPath = descriptor.layers.first { $0.id == 2 }?.staticModelPath ?? "models/parts.mdl"
            let links = descriptor.modelMaterialLinks.filter { $0.modelPath == modelPath }.compactMap(\.materialPath)
            let allPasses = try descriptor.materialPasses.map { pass -> [String: Any] in
                let material = try model.resourceView.resolvedResource(relativePath: pass.materialPath)!.readBytes()
                let textureBytes = try pass.texturePaths.map { path in
                    [UInt8](try model.resourceView.resolvedResource(relativePath: path)!.readBytes())
                }
                return ["material": pass.materialPath, "passIndex": pass.passIndex,
                    "textures": pass.textureSlots.map { value -> Any in value.map { $0 as Any } ?? NSNull() },
                    "combos": pass.combos, "constants": pass.constantShaderValues.mapValues(\.components),
                    "shaderPath": pass.shaderPath ?? "", "cullMode": pass.cullMode ?? "",
                    "depthWrite": pass.depthWrite ?? "", "blending": pass.blending ?? "",
                    "defaultAlbedo": pass.staticModelDefaultAlbedoAssetPath ?? "",
                    "bindingState": pass.staticModelMaterialBindings?.state.rawValue ?? "none",
                    "materialBytes": [UInt8](material), "textureBytes": textureBytes]
            }
            let layers = descriptor.layers.compactMap { layer -> [String: Any]? in
                guard let path = layer.staticModelPath else { return nil }
                return ["id": layer.id, "modelPath": path, "origin": layer.originXYZ ?? [0, 0, 0],
                    "scale": layer.scaleXYZ ?? [1, 1, 1], "castsShadow": layer.modelShadowCastIntent != .disabled]
            }
            rows.append(["name": name, "modelPath": modelPath, "links": links,
                "passes": allPasses.filter { links.contains($0["material"] as! String) },
                "allPasses": allPasses, "layers": layers,
                "canvasHeight": Int(descriptor.camera.orthoHeight ?? 128)])
        }
        print(String(decoding: try JSONSerialization.data(withJSONObject: ["rows": rows],
            options: [.sortedKeys]), as: UTF8.self))
    }
}
