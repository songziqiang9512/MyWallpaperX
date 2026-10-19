import Foundation
import Metal

/// Resource preparation only: no command buffer, draw, or replacement parser.
enum SceneStaticModelAnimationAttachmentChecks {
    static func run(root: URL, device: MTLDevice) throws -> [[String: Any]] {
        var rows: [[String: Any]] = []
        for mode in ["absent", "nonempty", "empty", "bad-count", "bad-name", "bad-bone", "bad-matrix"] {
            let directory = root.appendingPathComponent("attachment-" + mode)
            let data = try Data(contentsOf: directory.appendingPathComponent("models/parts.mdl"))
            // Establish that each negative reaches attachment preparation with
            // the same independently valid mesh, required Rig and animation.
            let parts = try SceneMdlStaticModelReader.readParts(data: data)
            let set = try SceneMdlPuppetAnimationReader.read(data: data)
            let parsed = Result { try SceneMdlPuppetAttachmentReader.read(data: data) }
            var layer = SceneRenderDescriptor.Layer(id: 2, staticModelPath: "models/parts.mdl")
            layer.puppetAnimationLayers = ScenePuppetAnimationLayer.parse([
                ["id": 71, "animation": 7, "name": "Motion Ω", "additive": false,
                 "blend": 1, "rate": 1, "visible": true]
            ])
            let peer = SceneRenderDescriptor.Layer(id: 1, staticModelPath: "models/peer.mdl")
            let passes = ["part000", "peer"].map { name in
                SceneRenderDescriptor.MaterialPassDescriptor(
                    materialPath: "materials/" + name + ".json",
                    textureSlots: ["materials/" + name + ".png"],
                    combos: ["LIGHTING": 0], constantShaderValues: [:]
                )
            }
            let descriptor = SceneRenderDescriptor(lighting: nil, layers: [peer, layer],
                renderOrderLayerIDs: [1, 2], materialPasses: passes)
            let loader = try SceneTextureLoader(root: directory, device: device)
            let resources = try ScenePreparedStaticModelResources.prepare(
                descriptor: descriptor, resourceView: .init(root: directory),
                device: device, textureLoader: loader, cancellationCheck: {}
            )
            let attachmentError: String
            switch parsed {
            case .success: attachmentError = ""
            case let .failure(error): attachmentError = String(describing: error)
            }
            rows.append([
                "mode": mode,
                "readerParts": parts.count,
                "readerBones": parts.first?.rig?.bones.count ?? 0,
                "readerClips": set?.animations.count ?? 0,
                "attachmentParseOK": attachmentError.isEmpty,
                "attachmentError": attachmentError,
                "bindParts": resources[2]?.count ?? 0,
                "bindIndices": resources[2]?.first?.mesh.indexCount ?? 0,
                "peerParts": resources[1]?.count ?? 0,
                "peerIndices": resources[1]?.first?.mesh.indexCount ?? 0,
                "peerMaterial": resources[1]?.first?.materialPath ?? "",
                "animationPrepared": resources.animation(for: 2) != nil,
                "retainedAttachmentNames": resources.animation(for: 2)?.attachments.map(\.name) ?? []
            ])
        }
        return rows
    }
}
