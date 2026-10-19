import Foundation
import CoreGraphics
import ImageIO
import Metal

/// Preparation-only inputs. No pipeline, command buffer, encoder or GPU draw is
/// created here; the independent rendering gate owns coverage pixel behavior.
enum SceneParticleMaterialCoverageHarness {
    static func profiles() throws -> [String: Any] {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "mwx-particle-coverage-profiles-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Harness.writePNG(root.appendingPathComponent("materials/source.png"))
        try Harness.writePNG(root.appendingPathComponent("materials/renamed-source.png"))
        var rows: [String: Any] = [:]
        func inspect(
            _ name: String, renderers: [[String: Any]] = [["name": "sprite"]],
            material: String = "materials/shared.json", texture: String = "source.png",
            blend: String = "alphatocoverage", passIndex: Int = 0,
            shader: String = "genericparticle", combos: [String: Int] = [:],
            constants: [String: SceneParticleMaterialConstant] = [:],
            userTexture: Bool = false, userValue: Bool = false,
            cull: String = "nocull", test: String = "disabled",
            write: String = "disabled", alpha: String? = nil
        ) throws {
            let path = "particles/\(name).json"
            try Harness.writeJSON([
                "material": material, "renderer": renderers,
                "emitter": [["name": "sphererandom", "rate": 0]],
            ], to: root.appendingPathComponent(path))
            let pass = SceneParticleMaterialPass(
                materialPath: material, passIndex: passIndex, shaderPath: shader,
                texturePaths: [texture], blending: blend, combos: combos,
                constantValues: constants, hasUserTextureInputs: userTexture,
                hasUserShaderValues: userValue, depthTest: test, depthWrite: write,
                cullMode: cull, alphaWriting: alpha)
            let graph = SceneParticleAssetGraphLoader(stockTextureBundleURL: nil).load(
                rootPaths: [path], materialPasses: [pass], cacheDirectory: root)
            guard let asset = graph.assetsByPath[SceneParticleAssetGraphLoader.normalizedPath(path)]
            else { throw Harness.HarnessError.missingPath }
            let state = asset.pipelineState
            let shared = SceneMaterialRenderState.compile(
                blending: blend, depthTest: test, depthWrite: write,
                cullMode: cull, alphaWriting: alpha)
            rows[name] = [
                "sharedBlend": shared?.blending.rawValue ?? "unavailable",
                "pipelineBlend": state?.blendMode.rawValue ?? "unavailable",
                "executable": state != nil && asset.supportsBuiltInShaderExecution
                    && asset.textureSource != nil,
                "shaderSupported": asset.supportsBuiltInShaderExecution,
                "textureAvailable": asset.textureSource != nil,
                "hasRenderState": asset.renderState != nil,
                "sceneCamera": state?.usesSceneCamera ?? false,
                "depthAttachment": state?.requiresDepthAttachment ?? false,
                "cull": state?.cullMode.rawValue ?? "unavailable",
                "overbright": state?.overbright ?? -1,
                "diagnostics": graph.diagnostics.map { $0.kind.rawValue },
            ]
        }
        let overbright = "ui_editor_properties_overbright"
        func constant(_ values: [Double], _ isStatic: Bool = true)
            -> [String: SceneParticleMaterialConstant] {
            [overbright: .init(components: values, isStatic: isStatic)]
        }
        try inspect("sprite")
        try inspect("renamed", renderers: [["name": "sprite", "id": 72]],
                    material: "materials/renamed-receiver.json", texture: "renamed-source.png")
        try inspect("screen", renderers: [["name": "sprite", "orientation": "screen"]])
        try inspect("rendererFlagOne", renderers: [["name": "sprite", "flags": 1]])
        try inspect("normalizedBlend", blend: "  AlphaToCoverage\n")
        try inspect("defaultAlpha", alpha: "default")
        try inspect("knownZeroCombos", combos: ["REFRACT": 0, "CUTOUT": 0, "LIGHTING": 0])
        try inspect("overbrightZero", constants: constant([0]))
        try inspect("overbrightFraction", constants: constant([1.19]))
        try inspect("overbrightLimit", constants: constant([64]))
        for renderer in ["spritetrail", "rope", "ropetrail"] {
            try inspect(renderer, renderers: [["name": renderer]])
        }
        for orientation in ["fixed", "upright"] {
            try inspect(orientation, renderers: [["name": "sprite", "orientation": orientation]])
        }
        try inspect("axis", renderers: [["name": "sprite", "axis": [0, 1, 0]]])
        try inspect("rendererFlags", renderers: [["name": "sprite", "flags": 2]])
        try inspect("malformedRenderer", renderers: [["name": "sprite", "flags": "invalid"]])
        try inspect("unknownRendererField", renderers: [["name": "sprite", "future": 1]])
        try inspect("twoRenderers", renderers: [["name": "sprite"], ["name": "sprite"]])
        try inspect("passOne", passIndex: 1)
        try inspect("passNegative", passIndex: -1)
        try inspect("normalCull", cull: "normal")
        try inspect("depthTest", test: "enabled")
        try inspect("depthWrite", write: "enabled")
        try inspect("bothDepth", test: "enabled", write: "enabled")
        for combo in ["REFRACT", "CUTOUT", "LIGHTING"] {
            try inspect(combo.lowercased(), combos: [combo: 1])
        }
        try inspect("unknownComboZero", combos: ["FUTURE": 0])
        try inspect("unknownComboOne", combos: ["FUTURE": 1])
        try inspect("userTexture", userTexture: true)
        try inspect("userValue", userValue: true)
        try inspect("alphaEnabled", alpha: "enabled")
        try inspect("alphaUnknown", alpha: "future")
        try inspect("negativeOverbright", constants: constant([-0.01]))
        try inspect("largeOverbright", constants: constant([64.01]))
        try inspect("nonfiniteOverbright", constants: constant([.infinity]))
        try inspect("emptyOverbright", constants: constant([]))
        try inspect("vectorOverbright", constants: constant([1, 1]))
        try inspect("dynamicOverbright", constants: constant([1], false))
        try inspect("unknownConstant", constants: ["future": .init(components: [1], isStatic: true)])
        try inspect("customShader", shader: "workshop/own-shader")
        try inspect("unknownBlend", blend: "future")
        try inspect("normalBlend", blend: "normal")
        try inspect("oldAdditiveRope", renderers: [["name": "rope"]], blend: "additive")
        try inspect("oldTranslucentTrail", renderers: [["name": "spritetrail"]], blend: "translucent")
        try inspect("oldFixedTranslucent", renderers: [["name": "sprite", "orientation": "fixed"]],
                    blend: "translucent")
        try inspect("oldSpriteDepthCull", blend: "translucent", cull: "normal",
                    test: "enabled", write: "enabled")
        return rows
    }

    static func demand() throws -> [String: Any] {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "mwx-particle-coverage-demand-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        // One pixel has one mip level, so real texture preparation needs no
        // GPU mip-generation command. The upload queue observation below locks it.
        let imageURL = root.appendingPathComponent("materials/source.png")
        try FileManager.default.createDirectory(at: imageURL.deletingLastPathComponent(),
                                               withIntermediateDirectories: true)
        guard let context = CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8,
            bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let destination = CGImageDestinationCreateWithURL(
                imageURL as CFURL, "public.png" as CFString, 1, nil)
        else { throw Harness.HarnessError.imageWrite }
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
        guard let image = context.makeImage() else { throw Harness.HarnessError.imageWrite }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw Harness.HarnessError.imageWrite }
        func particle(_ name: String, _ material: String, renderer: String = "sprite",
                      rate: Double = 0, children: [[String: Any]] = []) throws {
            try Harness.writeParticle("particles/\(name).json", material: material,
                renderer: renderer, startTime: 0, rate: rate, instantaneous: 0,
                children: children, under: root)
        }
        try particle("plain", "materials/plain.json")
        try particle("covered", "materials/covered.json", rate: 1)
        try particle("rejected", "materials/rejected.json", renderer: "spritetrail", rate: 1)
        try particle("parent", "materials/plain.json", children: [
            ["name": "particles/covered.json", "type": "eventspawn"]])
        try particle("rejected-parent", "materials/plain.json", children: [
            ["name": "particles/rejected.json", "type": "eventspawn"]])
        guard let device = MTLCreateSystemDefaultDevice() else { throw Harness.HarnessError.noMetal }
        func pass(_ path: String, _ blend: String,
                  value: SceneDocument.ShaderValue? = nil, shader: String = "genericparticle")
            -> SceneRenderDescriptor.MaterialPassDescriptor {
            .init(materialPath: path, shaderPath: shader, texturePaths: ["source.png"],
                constantShaderValues: value.map { ["ui_editor_properties_overbright": $0] } ?? [:],
                blending: blend)
        }
        let plain = pass("materials/plain.json", "additive")
        let covered = pass("materials/covered.json", "alphatocoverage")
        let rejected = pass("materials/rejected.json", "alphatocoverage")
        let uploadQueue = SceneTextureUploadCommandQueue()
        let loader = SceneTextureLoader(uploadCommandQueue: uploadQueue)
        var rows: [String: Any] = [:]
        func inspect(_ name: String, _ layers: [SceneRenderDescriptor.Layer],
                     passes: [SceneRenderDescriptor.MaterialPassDescriptor] = [],
                     prepared: Set<Int> = []) {
            let runtime = SceneParticleRuntime(descriptor: .init(
                layers: layers, renderOrderLayerIDs: layers.map(\.id),
                materialPasses: passes.isEmpty ? [plain, covered, rejected] : passes),
                cacheDirectory: root, device: device, stockTextureBundleURL: nil, textureLoader: loader,
                preparedParticleVisibilityLayerIDs: prepared)
            let lifecycle = runtime.lifecycleSnapshot
            rows[name] = [
                "required": runtime.requiresAlphaToCoverage,
                "activeLayerIDs": runtime.activeLayerIDs,
                "rootSystems": lifecycle.rootSystemCount,
                "childSystems": lifecycle.childSystemCount,
                "rootParticles": lifecycle.rootParticleCount,
                "childParticles": lifecycle.childParticleCount,
                "diagnostics": runtime.diagnostics.map { $0.kind.rawValue },
                "diagnosticDetails": runtime.diagnostics.compactMap(\.detail),
                "uploadQueueCreations": uploadQueue.creationAttemptCount,
            ]
        }
        inspect("empty", [])
        inspect("ordinary", [Harness.layer(1, "particles/plain.json")])
        inspect("rootNoBirth", [Harness.layer(2, "particles/covered.json")])
        inspect("hidden", [Harness.layer(3, "particles/covered.json", visible: false)])
        inspect("preparedHidden", [Harness.layer(4, "particles/covered.json", visible: false)],
                prepared: [4])
        inspect("childNoBirth", [Harness.layer(5, "particles/parent.json")])
        inspect("rejectedChild", [Harness.layer(6, "particles/rejected-parent.json")])
        inspect("ordinaryWithRejectedPeer", [Harness.layer(7, "particles/plain.json"),
            Harness.layer(8, "particles/rejected.json")])
        inspect("customShader", [Harness.layer(9, "particles/covered.json")],
                passes: [pass("materials/covered.json", "alphatocoverage", shader: "own/custom")])
        func value(kind: String = "number", bindingKeys: [String] = [],
                   script: String? = nil, user: String? = nil, userKind: String? = nil,
                   timeline: Bool = false, diagnostics: [String] = []) throws -> SceneDocument.ShaderValue {
            var result = SceneDocument.ShaderValue(rawValue: "1.19", valueKind: kind,
                components: [1.19], userBinding: user,
                timeline: timeline ? try JSONDecoder().decode(SceneJSONPresence.self,
                    from: Data("{}".utf8)) : nil, timelineDiagnostics: diagnostics)
            result.scriptSource = script
            result.userValueKind = userKind.flatMap { SceneShaderUserValueKind(rawValue: $0) }
            result.bindingKeys = bindingKeys
            return result
        }
        let wrappers: [(String, SceneDocument.ShaderValue)] = [
            ("primitive", try value()),
            ("primitiveString", try value(kind: "string")),
            ("valueOnly", try value(kind: "binding", bindingKeys: ["value"])),
            ("nullUser", try value(kind: "binding", bindingKeys: ["user", "value"], userKind: "null")),
            ("emptyStringUser", try value(kind: "binding", bindingKeys: ["user", "value"], userKind: "string")),
            ("nullUserAnimation", try value(kind: "binding", bindingKeys: ["animation", "user", "value"], userKind: "null")),
            ("scriptWrapper", try value(kind: "binding", bindingKeys: ["value", "script"], script: "return 1.19;")),
            ("emptyScript", try value(script: "")),
            ("objectUser", try value(kind: "binding", bindingKeys: ["value", "user"], userKind: "object")),
            ("boundUser", try value(user: "gain")),
            ("animation", try value(kind: "binding", bindingKeys: ["value", "animation"], timeline: true)),
            ("unparsedAnimation", try value(kind: "binding", bindingKeys: ["animation", "value"])),
            ("timelineDiagnostic", try value(diagnostics: ["rejected timeline"])),
            ("unknownWrapper", try value(kind: "binding", bindingKeys: ["value", "future"])),
            ("emptyBinding", try value(kind: "binding")),
            ("primitiveWithBinding", try value(bindingKeys: ["value"])),
            ("unknownKind", try value(kind: "object")),
        ]
        for (name, value) in wrappers {
            inspect(name, [Harness.layer(20, "particles/covered.json")],
                    passes: [pass("materials/covered.json", "alphatocoverage", value: value)])
        }
        inspect("ordinaryNullUser", [Harness.layer(21, "particles/plain.json")],
                passes: [pass("materials/plain.json", "translucent",
                    value: try value(kind: "binding", bindingKeys: ["user", "value"], userKind: "null"))])
        return rows
    }
}
