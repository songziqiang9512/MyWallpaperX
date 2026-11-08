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
        func prepared(_ name: String, lighting: Int = 1, color: String = "opaque-albedo.tex",
                      normal: String? = nil, amount: Double = 0, overbright: Double = 1)
            throws -> SceneParticleRefractionTextureLoader.Loaded {
            let path = "particles/\(name).json", material = "materials/\(name).json"
            let file = directory.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(),
                withIntermediateDirectories: true)
            let data = try JSONSerialization.data(withJSONObject: ["material": material,
                "maxcount": 1, "emitter": [["name": "boxRandom"]], "renderer": [["name": "sprite"]]])
            try data.write(to: file)
            let view = SceneResourceView(projectRootURL: directory, packageRootURL: nil, stockAssetsRootURL: nil)
            let pass = SceneParticleMaterialPass(materialPath: material, shaderPath: "genericparticle",
                texturePaths: [color] + (normal.map { [$0] } ?? []), blending: "translucent",
                combos: ["REFRACT": 1, "LIGHTING": lighting], constantValues: [
                    "ui_editor_properties_refract_amount": .init(components: [amount], isStatic: true),
                    "ui_editor_properties_overbright": .init(components: [overbright], isStatic: true)])
            let graph = try SceneParticleAssetGraphLoader(resourceView: view, stockTextureBundleURL: nil)
                .load(rootPaths: [path], materialPasses: [pass], supportsAmbientLighting: true)
            guard let asset = graph.assetsByPath[path], let source = asset.textureSource,
                  let declaration = asset.refraction,
                  declaration.usesAmbientLighting == (lighting == 1),
                  let loaded = try SceneParticleRefractionTextureLoader.load(colorSource: source,
                    declaration: declaration, textureLoader: loader, device: device),
                  loaded.binding.usesAmbientLighting == declaration.usesAmbientLighting else {
                throw HarnessError.texture
            }
            return loaded
        }
        func pixel(_ value: SceneParticleRefractionTextureLoader.Loaded, ambient: SIMD3<Float>?,
                   hdr: Bool = false, alpha: Float = 1, tint: SIMD3<Float> = SIMD3(repeating: 1),
                   mode: SceneParticlePipelineBlendMode = .translucent, gradient: Bool = false,
                   rejectFirst: SceneParticleRefractionBinding? = nil) throws -> [Int] {
            let pixels = try drawPixels(device: device, refraction: value, particleAlpha: alpha,
                blendMode: mode, gradientBackground: gradient,
                instance: .init(position: .zero, size: 2, rotation: .zero, color: tint, alpha: alpha),
                ambient: ambient, hdrEnabled: hdr, rejectFirst: rejectFirst)
            return pixels[(16 * 32 + 16) * 4 ..< (16 * 32 + 16) * 4 + 4].map(Int.init)
        }
        let unlit = try prepared("unlit-neighbor", lighting: 0)
        let lit = try prepared("ambient-color")
        let renamed = try prepared("another-material", color: renamedColor.lastPathComponent)
        let equivalent = try prepared("half-ambient-double-overbright", overbright: 2)
        let channel = try prepared("channel-tint", color: colored.lastPathComponent)
        let high = try prepared("high-light-quarter-overbright", overbright: 0.25)
        let fractional = try prepared("fractional-light", color: "fractional-albedo.tex", overbright: 0.25)
        let normalLit = try prepared("normal-lit", normal: "packed-normal.tex", amount: 0.25)
        let normalUnlit = try prepared("normal-unlit", lighting: 0, normal: "packed-normal.tex", amount: 0.25)
        var rows: [String: Any] = [
            "unlitIgnoresAmbientHDR": try pixel(unlit, ambient: SIMD3(4, 2, 1.5), hdr: true),
            "ambient": try pixel(lit, ambient: SIMD3(0.25, 0.5, 0.75)),
            "blackAmbientKeepsAlpha": try pixel(lit, ambient: .zero),
            "renamed": try pixel(renamed, ambient: SIMD3(0.25, 0.5, 0.75)),
            "equivalent": try pixel(equivalent, ambient: SIMD3(0.125, 0.25, 0.375)),
            "channelTint": try pixel(channel, ambient: SIMD3(2, 1, 0.5), tint: SIMD3(0.5, 2, 1)),
            "highSDR": try pixel(high, ambient: SIMD3(4, 2, 1.5), tint: SIMD3(0.5, 1, 2)),
            "highHDR": try pixel(high, ambient: SIMD3(4, 2, 1.5), hdr: true, tint: SIMD3(0.5, 1, 2)),
            "normalLit": try pixel(normalLit, ambient: SIMD3(repeating: 1), gradient: true),
            "normalUnlit": try pixel(normalUnlit, ambient: nil, gradient: true),
            "missingAmbientKeepsPeer": try pixel(unlit, ambient: nil, rejectFirst: lit.binding),
            "productionLightingFlag": lit.binding.usesAmbientLighting && !unlit.binding.usesAmbientLighting,
        ]
        for (name, mode) in [("translucent", SceneParticlePipelineBlendMode.translucent),
                             ("additive", SceneParticlePipelineBlendMode.additive)] {
            rows[name + "SDR"] = try pixel(fractional, ambient: SIMD3(4, 2, 1.5),
                alpha: 0.5, tint: SIMD3(0.5, 1, 2), mode: mode)
            rows[name + "HDR"] = try pixel(fractional, ambient: SIMD3(4, 2, 1.5), hdr: true,
                alpha: 0.5, tint: SIMD3(0.5, 1, 2), mode: mode)
        }
        return rows
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
