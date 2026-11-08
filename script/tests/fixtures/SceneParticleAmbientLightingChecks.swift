import Foundation
import Metal
import simd

extension Harness {
    static func ambientLightingProfiles(device: MTLDevice, loader: SceneTextureLoader,
                                        directory: URL) throws -> [String: Any] {
        let renamedColor = directory.appendingPathComponent("renamed-light-color.tex")
        try Data(contentsOf: directory.appendingPathComponent("opaque-albedo.tex")).write(to: renamedColor)
        let colored = directory.appendingPathComponent("ambient-channel-color.tex")
        try makeRawTex(pixel: [128, 64, 192, 255]).write(to: colored)
        let unlit = try preparedRefraction("unlit-neighbor", device: device, loader: loader,
            directory: directory, lighting: 0)
        let lit = try preparedRefraction("ambient-color", device: device, loader: loader, directory: directory)
        let renamed = try preparedRefraction("another-material", device: device, loader: loader,
            directory: directory, color: renamedColor.lastPathComponent)
        let equivalent = try preparedRefraction("half-ambient-double-overbright", device: device, loader: loader,
            directory: directory, overbright: 2)
        let channel = try preparedRefraction("channel-tint", device: device, loader: loader,
            directory: directory, color: colored.lastPathComponent)
        let high = try preparedRefraction("high-light-quarter-overbright", device: device, loader: loader,
            directory: directory, overbright: 0.25)
        let fractional = try preparedRefraction("fractional-light", device: device, loader: loader,
            directory: directory, color: "fractional-albedo.tex", overbright: 0.25)
        let normalLit = try preparedRefraction("normal-lit", device: device, loader: loader,
            directory: directory, normal: "packed-normal.tex", amount: 0.25)
        let normalUnlit = try preparedRefraction("normal-unlit", device: device, loader: loader,
            directory: directory, lighting: 0, normal: "packed-normal.tex", amount: 0.25)
        var rows: [String: Any] = [
            "unlitIgnoresAmbientHDR": try refractionPixel(device: device, unlit, ambient: SIMD3(4, 2, 1.5), hdr: true),
            "ambient": try refractionPixel(device: device, lit, ambient: SIMD3(0.25, 0.5, 0.75)),
            "blackAmbientKeepsAlpha": try refractionPixel(device: device, lit, ambient: .zero),
            "renamed": try refractionPixel(device: device, renamed, ambient: SIMD3(0.25, 0.5, 0.75)),
            "equivalent": try refractionPixel(device: device, equivalent, ambient: SIMD3(0.125, 0.25, 0.375)),
            "channelTint": try refractionPixel(device: device, channel, ambient: SIMD3(2, 1, 0.5), tint: SIMD3(0.5, 2, 1)),
            "highSDR": try refractionPixel(device: device, high, ambient: SIMD3(4, 2, 1.5), tint: SIMD3(0.5, 1, 2)),
            "highHDR": try refractionPixel(device: device, high, ambient: SIMD3(4, 2, 1.5), hdr: true, tint: SIMD3(0.5, 1, 2)),
            "normalLit": try refractionPixel(device: device, normalLit, ambient: SIMD3(repeating: 1), gradient: true),
            "normalUnlit": try refractionPixel(device: device, normalUnlit, ambient: nil, gradient: true),
            "missingAmbientKeepsPeer": try refractionPixel(device: device, unlit, ambient: nil, rejectFirst: lit.binding),
            "productionLightingFlag": lit.binding.usesAmbientLighting && !unlit.binding.usesAmbientLighting,
        ]
        for (name, mode) in [("translucent", SceneParticlePipelineBlendMode.translucent),
                             ("additive", SceneParticlePipelineBlendMode.additive)] {
            rows[name + "SDR"] = try refractionPixel(device: device, fractional, ambient: SIMD3(4, 2, 1.5),
                alpha: 0.5, tint: SIMD3(0.5, 1, 2), mode: mode)
            rows[name + "HDR"] = try refractionPixel(device: device, fractional, ambient: SIMD3(4, 2, 1.5), hdr: true,
                alpha: 0.5, tint: SIMD3(0.5, 1, 2), mode: mode)
        }
        return rows
    }

    static func cutoutProfiles(device: MTLDevice, loader: SceneTextureLoader,
                               directory: URL) throws -> [String: Any] {
        func constants(_ values: SIMD3<Double>) -> [String: SceneParticleMaterialConstant] {
            Dictionary(uniqueKeysWithValues: zip(["start", "end", "opacity"],
                [values.x, values.y, values.z]).map {
                    ("ui_editor_properties_cutout_" + $0.0,
                     SceneParticleMaterialConstant(components: [$0.1], isStatic: true)) })
        }
        try makeRawTex(pixel: [255, 128, 0, 255]).write(
            to: directory.appendingPathComponent("cutout-normal.tex"))
        try makeTex(format: 8, payload: Data((0..<16).flatMap { _ in [UInt8(255), 128] })).write(
            to: directory.appendingPathComponent("cutout-la8.tex"))
        let renamedColor = directory.appendingPathComponent("another-cutout-albedo.tex")
        try Data(contentsOf: directory.appendingPathComponent("opaque-albedo.tex")).write(to: renamedColor)
        let defaults = try preparedRefraction("cutout-default", device: device, loader: loader,
            directory: directory, lighting: 0, cutout: 1)
        let explicit = try preparedRefraction("renamed-cutout", device: device, loader: loader,
            directory: directory, lighting: 0, color: renamedColor.lastPathComponent,
            cutout: 1, constants: constants(SIMD3(0.1, 0.2, 1)))
        let ordered = try preparedRefraction("ordered-cutout", device: device, loader: loader,
            directory: directory, lighting: 0, cutout: 1, constants: constants(SIMD3(0.25, 0.75, 0.5)))
        let raw = try preparedRefraction("raw-two-cutout", device: device, loader: loader,
            directory: directory, lighting: 0, cutout: 1, constants: constants(SIMD3(1, 3, 0.5)))
        let negative = try preparedRefraction("negative-edges", device: device, loader: loader,
            directory: directory, lighting: 0, normal: "cutout-normal.tex", amount: 0.125,
            cutout: 1, constants: constants(SIMD3(-0.2, -0.1, 1)))
        let normal = try preparedRefraction("normal-cutout", device: device, loader: loader,
            directory: directory, lighting: 0, normal: "cutout-normal.tex", amount: 0.125,
            cutout: 1, constants: constants(SIMD3(0.1, 0.2, 0.5)))
        let la8 = try preparedRefraction("la8-cutout", device: device, loader: loader,
            directory: directory, lighting: 0, color: "cutout-la8.tex", cutout: 1,
            constants: constants(SIMD3(0, 256.0 / 255.0, 0.5)))
        let lit = try preparedRefraction("lit-double-cutout", device: device, loader: loader,
            directory: directory, overbright: 0.25, cutout: 1, doubleSided: 1,
            constants: constants(SIMD3(0.25, 0.75, 1)))
        let inactive = try preparedRefraction("inactive-cutout", device: device, loader: loader,
            directory: directory, lighting: 0, cutout: 0, constants: [
                "ui_editor_properties_cutout_start": .init(components: [.nan, 4], isStatic: false)])
        let transparent = try preparedRefraction("zero-opacity", device: device, loader: loader,
            directory: directory, lighting: 0, cutout: 1, constants: constants(SIMD3(0.1, 0.2, 0)))
        var rows: [String: Any] = [
            "productionCutout": defaults.binding.cutout == SIMD3<Float>(0.1, 0.2, 1)
                && explicit.binding.cutout == defaults.binding.cutout && inactive.binding.cutout == nil,
            "renamedExplicit": try refractionPixel(device: device, explicit, ambient: nil, alpha: 0.15),
            "la8": try refractionPixel(device: device, la8, ambient: nil),
            "rawTwo": try refractionPixel(device: device, raw, ambient: nil, alpha: 2),
            "zeroAlphaNegativeEdges": try refractionPixel(device: device, negative, ambient: nil,
                alpha: 0, gradient: true),
            "normalHalfAlpha": try refractionPixel(device: device, normal, ambient: nil,
                alpha: 0.5, gradient: true),
            "normalFullAlpha": try refractionPixel(device: device, normal, ambient: nil, gradient: true),
            "inactive": try refractionPixel(device: device, inactive, ambient: nil, alpha: 0.15),
            "zeroOpacity": try refractionPixel(device: device, transparent, ambient: nil),
        ]
        for (name, alpha) in [("below", Float(0.05)), ("mid", 0.15), ("above", 0.25)] {
            rows["default-" + name] = try refractionPixel(device: device, defaults, ambient: nil, alpha: alpha)
        }
        for (name, alpha) in [("below", Float(0.125)), ("mid", 0.5), ("above", 0.875)] {
            rows["ordered-" + name] = try refractionPixel(device: device, ordered, ambient: nil, alpha: alpha)
        }
        for (name, mode) in [("translucent", SceneParticlePipelineBlendMode.translucent),
                             ("additive", SceneParticlePipelineBlendMode.additive)] {
            rows[name + "SDR"] = try refractionPixel(device: device, lit, ambient: SIMD3(4, 2, 1.5),
                alpha: 0.5, tint: SIMD3(0.5, 1, 2), mode: mode)
            rows[name + "HDR"] = try refractionPixel(device: device, lit, ambient: SIMD3(4, 2, 1.5), hdr: true,
                alpha: 0.5, tint: SIMD3(0.5, 1, 2), mode: mode)
        }
        return rows
    }

    static func preparedRefraction(_ name: String, device: MTLDevice, loader: SceneTextureLoader,
                                   directory: URL, lighting: Int = 1, color: String = "opaque-albedo.tex",
                                   normal: String? = nil, amount: Double = 0, overbright: Double = 1,
                                   cutout: Int? = nil, doubleSided: Int? = nil,
                                   constants: [String: SceneParticleMaterialConstant] = [:])
        throws -> SceneParticleRefractionTextureLoader.Loaded {
        let path = "particles/\(name).json", material = "materials/\(name).json"
        let file = directory.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(),
            withIntermediateDirectories: true)
        let data = try JSONSerialization.data(withJSONObject: ["material": material,
            "maxcount": 1, "emitter": [["name": "boxRandom"]], "renderer": [["name": "sprite"]]])
        try data.write(to: file)
        let view = SceneResourceView(projectRootURL: directory, packageRootURL: nil, stockAssetsRootURL: nil)
        var combos = ["REFRACT": 1, "LIGHTING": lighting]
        if let cutout { combos["CUTOUT"] = cutout }
        if let doubleSided { combos["DOUBLESIDEDLIGHTING"] = doubleSided }
        var values = constants
        values["ui_editor_properties_refract_amount"] = .init(components: [amount], isStatic: true)
        values["ui_editor_properties_overbright"] = .init(components: [overbright], isStatic: true)
        let pass = SceneParticleMaterialPass(materialPath: material, shaderPath: "genericparticle",
            texturePaths: [color] + (normal.map { [$0] } ?? []), blending: "translucent",
            combos: combos, constantValues: values)
        let graph = try SceneParticleAssetGraphLoader(resourceView: view, stockTextureBundleURL: nil)
            .load(rootPaths: [path], materialPasses: [pass], supportsAmbientLighting: true)
        guard let asset = graph.assetsByPath[path], let source = asset.textureSource,
              let declaration = asset.refraction,
              declaration.usesAmbientLighting == (lighting == 1),
              let loaded = try SceneParticleRefractionTextureLoader.load(colorSource: source,
                declaration: declaration, textureLoader: loader, device: device),
              loaded.binding.usesAmbientLighting == declaration.usesAmbientLighting,
              loaded.binding.cutout == declaration.cutout else {
            throw HarnessError.texture
        }
        return loaded
    }

    static func refractionPixel(device: MTLDevice, _ value: SceneParticleRefractionTextureLoader.Loaded,
                                ambient: SIMD3<Float>?, hdr: Bool = false, alpha: Float = 1,
                                tint: SIMD3<Float> = SIMD3(repeating: 1),
                                mode: SceneParticlePipelineBlendMode = .translucent, gradient: Bool = false,
                                rejectFirst: SceneParticleRefractionBinding? = nil) throws -> [Int] {
        let pixels = try drawPixels(device: device, refraction: value, particleAlpha: alpha,
            blendMode: mode, gradientBackground: gradient,
            instance: .init(position: .zero, size: 2, rotation: .zero, color: tint, alpha: alpha),
            ambient: ambient, hdrEnabled: hdr, rejectFirst: rejectFirst)
        return pixels[(16 * 32 + 16) * 4 ..< (16 * 32 + 16) * 4 + 4].map(Int.init)
    }

    static func rejectMissingAmbient(pipeline: SceneParticleMetalPipeline, texture: MTLTexture,
                                     binding: SceneParticleRefractionBinding, background: MTLTexture,
                                     instances: SceneParticleMetalInstanceBuffer,
                                     uniforms: SceneParticleLayerUniforms,
                                     encoder: MTLRenderCommandEncoder) throws {
        let encoded = pipeline.drawRefraction(texture: texture, binding: binding, background: background,
            instances: instances, uniforms: uniforms,
            renderState: .init(blendMode: .translucent, cullMode: .none),
            colorUVScale: SIMD2(repeating: 1), colorSampling: .linearClamp, encoder: encoder)
        guard !encoded else { throw HarnessError.gpu }
    }
}
