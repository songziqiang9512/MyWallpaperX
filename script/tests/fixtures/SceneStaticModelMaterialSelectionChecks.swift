import Foundation
import Metal

/// Real Reader -> resource preparation. Only descriptor/texture transport is
/// supplied by the enclosing parts fixture; selection remains production code.
enum SceneStaticModelMaterialSelectionChecks {
    static func run(root: URL, device: MTLDevice) throws -> [String: Bool] {
        let directory = root.appendingPathComponent("parts8")
        var bytes = try Data(contentsOf: directory.appendingPathComponent("models/parts.mdl"))
        let original = Data("materials/part007.json".utf8)
        let invalidTypedPath = Data("materials/part\u{7f}07.json".utf8)
        precondition(original.count == invalidTypedPath.count)
        bytes.replaceSubrange(bytes.range(of: original)!, with: invalidTypedPath)
        let parts = try SceneMdlStaticModelReader.readParts(data: bytes)
        let peer = try SceneMdlStaticModelReader.readParts(
            data: Data(contentsOf: directory.appendingPathComponent("models/peer.mdl")))
        precondition(parts.count == 8 && parts[7].materialPath.contains("\u{7f}"))
        var checks: [String: Bool] = [:]
        for reversed in [false, true] {
            let mode = reversed ? "reordered" : "first"
            let result = try autoreleasepool {
                try prepare(directory: directory, parts: parts, peer: peer,
                            reversed: reversed, device: device)
            }
            checks.merge(result.map { (mode + ":" + $0.key, $0.value) }, uniquingKeysWith: { $1 })
        }
        return checks
    }

    private static func pass(
        _ path: String, texture: String = "materials/part000.png",
        index: Int = 0, color: [Double] = [1, 1, 1], alpha: Double = 1,
        rejected: Bool = false, depth: String? = nil
    ) -> SceneRenderDescriptor.MaterialPassDescriptor {
        var value = SceneRenderDescriptor.MaterialPassDescriptor(
            materialPath: path, textureSlots: [texture], combos: ["LIGHTING": 0],
            constantShaderValues: ["color": .init(components: color), "alpha": .init(components: [alpha])],
            passIndex: index, depthWrite: depth)
        if rejected {
            value.staticModelMaterialBindings = .init(
                state: .rejected, bindings: [], rejectionReason: "selection-fixture")
        }
        return value
    }

    private static func prepare(
        directory: URL, parts: [SceneMdlStaticModel], peer: [SceneMdlStaticModel],
        reversed: Bool, device: MTLDevice
    ) throws -> [String: Bool] {
        let winner = pass("./MATERIALS/Part000.JSON", color: [0.25, 0.5, 0.75],
                          alpha: 0.375, depth: "disabled")
        let duplicate = pass("materials\\part000.json", texture: "materials/peer.png",
                             color: [0.75, 0.25, 0.5], alpha: 0.625)
        let rejected = pass("materials/part002.json", rejected: true)
        let admitted = pass("./materials/part002.json", texture: "materials/part002.png")
        let missing = pass("materials/part003.json", texture: "materials/absent.png")
        let available = pass("./materials/part003.json", texture: "materials/part003.png")
        let passes = [pass("/materials/part000.json"), pass("materials/part000.json", index: 2)]
            + (reversed ? [duplicate, winner] : [winner, duplicate])
            + [pass("materials/part001.json", index: 1),
               pass("materials\\part001.json", texture: "materials/part001.png", alpha: 0.5)]
            + (reversed ? [admitted, rejected, available, missing] : [rejected, admitted, missing, available])
            + [pass("materials/part004.json", index: 3), pass("materials//part005.json"),
               pass("materials/part006.json", texture: "materials/part006.png"),
               pass(parts[7].materialPath), pass("materials/peer.json", texture: "materials/peer.png")]
        let layers = [SceneRenderDescriptor.Layer(id: 2, staticModelPath: "models/parts.mdl"),
                      .init(id: 1, staticModelPath: "models/peer.mdl")]
        let descriptor = SceneRenderDescriptor(lighting: nil, layers: layers,
            renderOrderLayerIDs: [2, 1], materialPasses: passes)
        var sources: [String: SceneMdlStaticModel.PreparedSource] = [
            "models/parts.mdl": .init(parts: parts, animations: nil, attachments: .success([])),
            "models/peer.mdl": .init(parts: peer, animations: nil, attachments: .success([]))]
        let loader = try SceneTextureLoader(root: directory, device: device)
        let resources = try ScenePreparedStaticModelResources.prepare(
            descriptor: descriptor, resourceView: .init(root: directory), device: device,
            textureLoader: loader, preparedSources: &sources, cancellationCheck: {})
        let entries = resources[2] ?? []
        let expected = reversed ? [0, 1, 2, 3, 6] : [0, 1, 6]
        let selected = entries.first
        let expectedColor = reversed ? SIMD3<Float>(0.75, 0.25, 0.5) : SIMD3<Float>(0.25, 0.5, 0.75)
        let expectedTexture = reversed ? "peer.png" : "part000.png"
        let expectedAlbedo = loader.candidates[directory.appendingPathComponent("materials/" + expectedTexture)
            .resolvingSymlinksInPath().path]
        return [
            "paths-and-part-order": entries.map(\.materialPath) == expected.map { String(format: "materials/part%03d.json", $0) },
            "first-alias-wins-color-alpha-depth": selected?.material.color == expectedColor
                && selected?.material.opacity == (reversed ? 0.625 : 0.375)
                && selected?.writesDepth == reversed,
            "first-alias-wins-texture": expectedAlbedo != nil && selected?.albedo?.texture === expectedAlbedo?.texture,
            "nonzero-pass-does-not-shadow-zero": entries.first { $0.materialPath == "materials/part001.json" }?.material.opacity == 0.5,
            "invalid-missing-rejected-stay-local": entries.count == expected.count && resources[1]?.count == 1,
            "all-real-meshes": entries.allSatisfy { $0.mesh.indexCount == 6 && $0.mesh.vertexCount == 4 },
            "prepared-sources-consumed": sources.isEmpty
        ]
    }
}
