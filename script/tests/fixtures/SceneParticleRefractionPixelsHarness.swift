import CoreGraphics
import Foundation
import ImageIO
import Metal
import simd

final class SceneVideoTextureSource {
    init?(
        layerID: Int,
        mp4PayloadData: Data,
        isWebM: Bool = false,
        cacheDirectory: URL,
        device: MTLDevice
    ) { return nil }
}

nonisolated struct SceneParticleRefractionDeclaration {
    let normalTextureSource: SceneParticleTextureSource?
    let amount: Float
    let overbright: Float
}

struct SceneSpriteAnimation {
    init(container: SceneTexContainer, sourceInput: SceneResourceView.FileInput) throws {}
}

@main
enum Harness {
    private static var readback: SceneTextureSamplingReadback!
    static func main() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            print("{\"available\":false}")
            return
        }
        readback = try SceneTextureSamplingReadback(device: device)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "mwx-refraction-pixels-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }

        let loader = SceneTextureLoader()
        let dxt5nURL = directory.appendingPathComponent("packed-normal.tex")
        try makeDXT5nTex().write(to: dxt5nURL)
        let directDXT5nURL = directory.appendingPathComponent(
            "packed-normal-multi-image.tex"
        )
        try makeDirectDXT5nTex().write(to: directDXT5nURL)
        let decodedTexture = try loaded(loader.load(
            from: dxt5nURL,
            purpose: .normal,
            device: device
        ))
        let decoded = try readPixel(decodedTexture)

        let rgbaURL = directory.appendingPathComponent("rgba-normal.tex")
        try makeRawTex(pixel: decoded).write(to: rgbaURL)

        let swappedURL = directory.appendingPathComponent("swapped-normal.tex")
        try makeRawTex(
            pixel: [decoded[0], decoded[3], decoded[2], decoded[1]]
        ).write(to: swappedURL)

        let neutralURL = directory.appendingPathComponent("neutral-normal.tex")
        try makeRawTex(pixel: [255, 128, 0, 128]).write(to: neutralURL)

        let opaqueURL = directory.appendingPathComponent("opaque-albedo.tex")
        try makeRawTex(pixel: [255, 255, 255, 255]).write(to: opaqueURL)

        let fractionalURL = directory.appendingPathComponent("fractional-albedo.tex")
        try makeRawTex(pixel: [255, 255, 255, 128]).write(to: fractionalURL)
        let dxt5n = try refraction(
            colorURL: opaqueURL,
            normalURL: dxt5nURL,
            amount: 0.25,
            loader: loader,
            device: device
        )
        let rgba = try refraction(
            colorURL: opaqueURL,
            normalURL: rgbaURL,
            amount: 0.25,
            loader: loader,
            device: device
        )
        let directDXT5n = try refraction(
            colorURL: opaqueURL,
            normalURL: directDXT5nURL,
            amount: 0.25,
            loader: loader,
            device: device
        )
        let swapped = try refraction(
            colorURL: opaqueURL,
            normalURL: swappedURL,
            amount: 0.25,
            loader: loader,
            device: device
        )
        let neutral = try refraction(
            colorURL: opaqueURL,
            normalURL: neutralURL,
            amount: 0.25,
            loader: loader,
            device: device
        )
        let flatDefault = try refraction(
            colorURL: opaqueURL,
            normalURL: nil,
            amount: 0.25,
            loader: loader,
            device: device
        )
        let fractional = try refraction(
            colorURL: fractionalURL,
            normalURL: neutralURL,
            amount: 0,
            loader: loader,
            device: device
        )
        let paddedURL = directory.appendingPathComponent("padded-normal.tex")
        try makePaddedRawNormalTex().write(to: paddedURL)
        let padded = try refraction(
            colorURL: opaqueURL,
            normalURL: paddedURL,
            amount: 0.25,
            loader: loader,
            device: device
        )
        let clampBorderURL = directory.appendingPathComponent(
            "clamp-border-normal.tex"
        )
        try makeRawTex(
            pixel: [255, 128, 0, 128],
            flags: 8
        ).write(to: clampBorderURL)
        let clampBorder = try refraction(
            colorURL: opaqueURL,
            normalURL: clampBorderURL,
            amount: 0.25,
            loader: loader,
            device: device
        )
        let sameFile = try refraction(
            colorURL: opaqueURL,
            normalURL: opaqueURL,
            amount: 0.25,
            loader: loader,
            device: device
        )
        let normalCopyURL = directory.appendingPathComponent("normal-copy.tex")
        try Data(contentsOf: opaqueURL).write(to: normalCopyURL)
        let separateFile = try refraction(colorURL: opaqueURL, normalURL: normalCopyURL,
            amount: 0.25, loader: loader, device: device)
        let sameFilePixels = try draw(device: device, refraction: sameFile,
            particleAlpha: 1, blendMode: .translucent, gradientBackground: true)
        let separateFilePixels = try draw(device: device, refraction: separateFile,
            particleAlpha: 1, blendMode: .translucent, gradientBackground: true)
        let sixteenURL = directory.appendingPathComponent("sixteen.tex")
        try makeTex(format: 0, textureWidth: 2, textureHeight: 2, imageWidth: 2, imageHeight: 2,
            payload: try makeOpaquePNG(width: 2, height: 2, straight16: true)).write(to: sixteenURL)
        let sixteenColor = try SceneParticleRefractionTextureLoader.load(
            colorSource: .file(.externalFile(sixteenURL)),
            declaration: SceneParticleRefractionDeclaration(normalTextureSource: nil,
                amount: 0.25, overbright: 1), textureLoader: loader, device: device)
        let sixteenNormal = try SceneParticleRefractionTextureLoader.load(
            colorSource: .file(.externalFile(sixteenURL)),
            declaration: SceneParticleRefractionDeclaration(normalTextureSource: .file(.externalFile(sixteenURL)),
                amount: 0.25, overbright: 1), textureLoader: loader, device: device)
        let oversizedSameSourceURL = directory.appendingPathComponent(
            "oversized-same-source.tex"
        )
        try makeTex(
            format: 0,
            textureWidth: 4_097,
            textureHeight: 2,
            imageWidth: 4_097,
            imageHeight: 2,
            payload: try makeOpaquePNG(width: 4_097, height: 2)
        ).write(to: oversizedSameSourceURL)
        let oversizedSameSourceRejected = try SceneParticleRefractionTextureLoader.load(
            colorSource: .file(.externalFile(oversizedSameSourceURL)),
            declaration: SceneParticleRefractionDeclaration(
                normalTextureSource: .file(.externalFile(oversizedSameSourceURL)),
                amount: 0.25,
                overbright: 1
            ),
            textureLoader: loader,
            device: device
        ) == nil
        let invalidMappedURL = directory.appendingPathComponent(
            "invalid-mapped-normal.tex"
        )
        try makeRawTex(
            pixel: [255, 128, 0, 128],
            textureWidth: 4,
            textureHeight: 4,
            imageWidth: 8,
            imageHeight: 4
        ).write(to: invalidMappedURL)
        let invalidMappedRejected = try SceneParticleRefractionTextureLoader.load(
            colorSource: .file(.externalFile(opaqueURL)),
            declaration: SceneParticleRefractionDeclaration(
                normalTextureSource: .file(.externalFile(invalidMappedURL)),
                amount: 0.25,
                overbright: 1
            ),
            textureLoader: loader,
            device: device
        ) == nil
        let dxt5nNormal = try normalArguments(dxt5n.binding)
        let paddedNormal = try normalArguments(padded.binding)
        let clampBorderNormal = try normalArguments(clampBorder.binding)
        let flatDefaultNormal = try normalArguments(flatDefault.binding)
        let wrongPurposeRejected = SceneParticleRefractionBinding(
            normalCandidate: candidate(
                texture: dxt5nNormal.texture,
                purpose: .flow
            ),
            amount: 0.25,
            overbright: 1,
            colorEncoding: .rgba
        ) == nil
        let clampBorderCandidateRejected = SceneParticleRefractionBinding(
            normalCandidate: candidate(
                texture: dxt5nNormal.texture,
                purpose: .normal,
                sampling: SceneTextureSampling(texFlags: 8)
            ),
            amount: 0.25,
            overbright: 1,
            colorEncoding: .rgba
        ) == nil
        let wrongUsageDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm,
            width: 4,
            height: 4,
            mipmapped: false
        )
        wrongUsageDescriptor.usage = .renderTarget
        let wrongTypeDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm,
            width: 4,
            height: 4,
            mipmapped: false
        )
        wrongTypeDescriptor.textureType = .type2DArray
        wrongTypeDescriptor.arrayLength = 2
        wrongTypeDescriptor.usage = .shaderRead
        guard let wrongUsageTexture = device.makeTexture(
                  descriptor: wrongUsageDescriptor
              ),
              let wrongTypeTexture = device.makeTexture(
                  descriptor: wrongTypeDescriptor
              ) else {
            throw HarnessError.texture
        }
        let wrongUsageRejected = SceneParticleRefractionBinding(
            normalCandidate: candidate(
                texture: wrongUsageTexture,
                purpose: .normal
            ),
            amount: 0.25,
            overbright: 1,
            colorEncoding: .rgba
        ) == nil
        let wrongTypeRejected = SceneParticleRefractionBinding(
            normalCandidate: candidate(
                texture: wrongTypeTexture,
                purpose: .normal
            ),
            amount: 0.25,
            overbright: 1,
            colorEncoding: .rgba
        ) == nil

        let directNormal = try normalArguments(directDXT5n.binding)
        let unknownFormatRejected = SceneParticleRefractionBinding(
            normalCandidate: candidate(texture: dxt5nNormal.texture, purpose: .normal, authoredFormat: nil),
            amount: 1, overbright: 1, colorEncoding: .rgba) == nil
        let unsupportedFormatRejected = SceneParticleRefractionBinding(
            normalCandidate: candidate(texture: dxt5nNormal.texture, purpose: .normal, authoredFormat: .rg88),
            amount: 1, overbright: 1, colorEncoding: .rgba) == nil
        let mismatchedFormatRejected = SceneParticleRefractionBinding(
            normalCandidate: candidate(texture: directNormal.texture, purpose: .normal, authoredFormat: .rgba8888),
            amount: 1, overbright: 1, colorEncoding: .rgba) == nil
        let sameFileDXT5n = try refraction(colorURL: dxt5nURL, normalURL: dxt5nURL,
            amount: 0.75, loader: loader, device: device)
        var sourceFormatPixels: [String: [Int]] = [:]
        for (name, url) in [("rgba", rgbaURL), ("singleImageBC3", dxt5nURL), ("nativeBC3", directDXT5nURL)] {
            let value = try refraction(colorURL: opaqueURL, normalURL: url, amount: 0.75,
                loader: loader, device: device)
            sourceFormatPixels[name] = try draw(device: device, refraction: value,
                particleAlpha: 1, blendMode: .translucent, gradientBackground: true)
        }
        let coloredURL = directory.appendingPathComponent("colored-albedo.tex")
        try makeRawTex(pixel: [64,192,128,128]).write(to: coloredURL)
        let rg88URL = directory.appendingPathComponent("rg88-albedo.tex")
        try makeTex(format: 8, payload: Data((0..<16).flatMap { _ in [UInt8(128),128] })).write(to: rg88URL)
        var absentPixels: [String: [[Int]]] = [:]
        for (name, url) in [("white",opaqueURL), ("colored",coloredURL), ("rg88",rg88URL)] {
            for (modeName, mode) in [("translucent",SceneParticlePipelineBlendMode.translucent),
                                     ("additive",SceneParticlePipelineBlendMode.additive)] {
                absentPixels[name + modeName] = try [Float(-1),0,1].map { amount in
                    let value = try refraction(colorURL: url, normalURL: nil, amount: amount,
                        loader: loader, device: device)
                    return try draw(device: device, refraction: value, particleAlpha: 0.5,
                        blendMode: mode, gradientBackground: true)
                }
            }
        }
        let explicitNeutral = try refraction(colorURL: opaqueURL, normalURL: neutralURL,
            amount: 1, loader: loader, device: device)
        let absentStrong = try refraction(colorURL: opaqueURL, normalURL: nil,
            amount: 1, loader: loader, device: device)
        let result: [String: Any] = [
            "available": true,
            "r8Color": try r8ColorProfiles(device: device, loader: loader, directory: directory),
            "displacementProfiles": try displacementProfiles(device: device,
                loader: loader, directory: directory, colorURL: opaqueURL),
            "sourceFormatPixels": sourceFormatPixels,
            "absentPixels": absentPixels,
            "explicitNeutral": try draw(device: device, refraction: explicitNeutral,
                particleAlpha: 1, blendMode: .translucent, gradientBackground: true),
            "absentStrong": try draw(device: device, refraction: absentStrong,
                particleAlpha: 1, blendMode: .translucent, gradientBackground: true),

            "decodedDXT5n": decoded.map(Int.init),
            "loadedDXT5nNormal": try readPixel(
                dxt5nNormal.texture
            ).map(Int.init),
            "normalPixels": [
                "dxt5n": try draw(
                    device: device,
                    refraction: dxt5n,
                    particleAlpha: 1,
                    blendMode: .translucent,
                    gradientBackground: true
                ),
                "rgba": try draw(
                    device: device,
                    refraction: rgba,
                    particleAlpha: 1,
                    blendMode: .translucent,
                    gradientBackground: true
                ),
                "dxt5nDirect": try draw(
                    device: device,
                    refraction: directDXT5n,
                    particleAlpha: 1,
                    blendMode: .translucent,
                    gradientBackground: true
                ),
                "swapped": try draw(
                    device: device,
                    refraction: swapped,
                    particleAlpha: 1,
                    blendMode: .translucent,
                    gradientBackground: true
                ),
                "neutral": try draw(
                    device: device,
                    refraction: neutral,
                    particleAlpha: 1,
                    blendMode: .translucent,
                    gradientBackground: true
                ),
                "flatDefault": try draw(
                    device: device,
                    refraction: flatDefault,
                    particleAlpha: 1,
                    blendMode: .translucent,
                    gradientBackground: true
                ),
                "padded": try draw(
                    device: device,
                    refraction: padded,
                    particleAlpha: 1,
                    blendMode: .translucent,
                    gradientBackground: true
                ),
            ],
            "normalRoutes": [
                "dxt5nStaticCandidate":
                    dxt5n.binding.usesStaticNormalCandidate,
                "rgbaStaticCandidate":
                    rgba.binding.usesStaticNormalCandidate,
                "paddedStaticCandidate":
                    padded.binding.usesStaticNormalCandidate,
                "paddedUVScale": [
                    paddedNormal.uvScale.x,
                    paddedNormal.uvScale.y,
                ],
                "multiImageLegacy":
                    !directDXT5n.binding.usesStaticNormalCandidate,
                "sameFilePixels": sameFilePixels,
                "separateFilePixels": separateFilePixels,
                "sixteenColorAccepted": sixteenColor != nil,
                "sixteenNormalRejected": sixteenNormal == nil,
                "singleImageBC3KeepsNativeStorage": dxt5nNormal.texture.pixelFormat
                    == (device.supportsBCTextureCompression ? .bc3_rgba : .rgba8Unorm),
                "directBC3IsNative": directNormal.texture.pixelFormat == .bc3_rgba,
                "decodedBC3Format": dxt5nNormal.authoredFormat?.rawValue ?? 999,
                "nativeBC3Format": directNormal.authoredFormat?.rawValue ?? 999,
                "sameFileBC3Format": try normalArguments(sameFileDXT5n.binding).authoredFormat?.rawValue ?? 999,
                "rgbaFormat": try normalArguments(rgba.binding).authoredFormat?.rawValue ?? 999,
                "absentFormat": flatDefaultNormal.authoredFormat == nil,
                "unknownFormatRejected": unknownFormatRejected,
                "unsupportedFormatRejected": unsupportedFormatRejected,
                "mismatchedFormatRejected": mismatchedFormatRejected,
                "oversizedSameSourceRejected": oversizedSameSourceRejected,
                "clampBorderLegacy":
                    !clampBorder.binding.usesStaticNormalCandidate
                        && clampBorderNormal.sampling.usesClampBorderFallback,
                "invalidMappedRejected": invalidMappedRejected,
                "wrongPurposeRejected": wrongPurposeRejected,
                "clampBorderCandidateRejected":
                    clampBorderCandidateRejected,
                "wrongUsageRejected": wrongUsageRejected,
                "wrongTypeRejected": wrongTypeRejected,
            ],
            "coveragePixels": [
                "translucent": try draw(
                    device: device,
                    refraction: fractional,
                    particleAlpha: 0.5,
                    blendMode: .translucent,
                    gradientBackground: false
                ),
                "additive": try draw(
                    device: device,
                    refraction: fractional,
                    particleAlpha: 0.5,
                    blendMode: .additive,
                    gradientBackground: false
                ),
                "albedo": try readPixel(fractional.color).map(Int.init),
            ],
        ]
        let output = try JSONSerialization.data(
            withJSONObject: result,
            options: [.sortedKeys]
        )
        print(String(decoding: output, as: UTF8.self))
    }

    private static func draw(
        device: MTLDevice,
        refraction: SceneParticleRefractionTextureLoader.Loaded,
        particleAlpha: Float,
        blendMode: SceneParticlePipelineBlendMode,
        gradientBackground: Bool
    ) throws -> [Int] {
        let pixels = try drawPixels(device: device, refraction: refraction,
            particleAlpha: particleAlpha, blendMode: blendMode,
            gradientBackground: gradientBackground)
        let offset = (16 * 32 + 16) * 4
        return pixels[offset ..< offset + 4].map(Int.init)
    }

    private static func drawPixels(
        device: MTLDevice,
        refraction: SceneParticleRefractionTextureLoader.Loaded,
        particleAlpha: Float,
        blendMode: SceneParticlePipelineBlendMode,
        gradientBackground: Bool,
        size: Int = 32,
        instance: SceneParticleGPUInstance? = nil,
        uniforms: SceneParticleLayerUniforms? = nil
    ) throws -> [UInt8] {
        guard let pipeline = SceneParticleMetalPipeline(device: device),
              let queue = device.makeCommandQueue(),
              let command = queue.makeCommandBuffer() else {
            throw HarnessError.gpu
        }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: size,
            height: size,
            mipmapped: false
        )
        descriptor.storageMode = .shared
        descriptor.usage = [.renderTarget, .shaderRead]
        guard let background = device.makeTexture(descriptor: descriptor),
              let target = device.makeTexture(descriptor: descriptor) else {
            throw HarnessError.gpu
        }
        var backgroundBytes = [UInt8](repeating: 0, count: size * size * 4)
        for y in 0 ..< size {
            for x in 0 ..< size {
                let offset = (y * size + x) * 4
                if gradientBackground {
                    backgroundBytes[offset] = UInt8(20 + x * (size == 32 ? 5 : 1))
                    backgroundBytes[offset + 1] = UInt8(30 + y * (size == 32 ? 3 : 1))
                    backgroundBytes[offset + 2] = 40
                } else {
                    backgroundBytes[offset] = 200
                    backgroundBytes[offset + 1] = 100
                    backgroundBytes[offset + 2] = 50
                }
                backgroundBytes[offset + 3] = 255
            }
        }
        background.replace(
            region: MTLRegionMake2D(0, 0, size, size),
            mipmapLevel: 0,
            withBytes: &backgroundBytes,
            bytesPerRow: size * 4
        )
        guard let captured = pipeline.snapshot(
            target: background,
            commandBuffer: command
        ) else {
            throw HarnessError.gpu
        }
        let instances = SceneParticleMetalInstanceBuffer()
        guard instances.update(device: device, instances: [
            instance ?? SceneParticleGPUInstance(
                position: .zero,
                size: 2,
                rotation: .zero,
                color: SIMD3(repeating: 1),
                alpha: particleAlpha
            ),
        ]) else {
            throw HarnessError.gpu
        }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = target
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0)
        pass.colorAttachments[0].storeAction = .store
        guard let encoder = command.makeRenderCommandEncoder(
            descriptor: pass
        ) else {
            throw HarnessError.gpu
        }
        let encoded = pipeline.drawRefraction(
            texture: refraction.color,
            binding: refraction.binding,
            background: captured,
            instances: instances,
            uniforms: uniforms ?? SceneParticleLayerUniforms(
                viewProjection: SceneMatrix.identity(),
                layerModel: SceneMatrix.identity(),
                basis: SceneParticleOrientation.screen.basis(
                    cameraRight: SIMD3(1, 0, 0),
                    cameraUp: SIMD3(0, 1, 0),
                    cameraForward: SIMD3(0, 0, -1)
                ),
                viewportSize: SIMD2(repeating: Float(size))
            ),
            renderState: SceneParticlePipelineRenderState(
                blendMode: blendMode,
                cullMode: .none
            ),
            colorUVScale: refraction.colorUVScale,
            colorSampling: refraction.colorSampling,
            encoder: encoder
        )
        encoder.endEncoding()
        guard encoded, instances.markSubmitted(on: command) else {
            throw HarnessError.gpu
        }
        command.commit()
        command.waitUntilCompleted()
        guard command.status == .completed else {
            throw HarnessError.gpu
        }
        var pixels = [UInt8](repeating: 0, count: size * size * 4)
        target.getBytes(
            &pixels,
            bytesPerRow: size * 4,
            from: MTLRegionMake2D(0, 0, size, size),
            mipmapLevel: 0
        )
        return pixels
    }

    /// Same world centerline in two local frames. No width solver is copied:
    /// a flat view-plane ribbon is the reference, while the ordinary local
    /// plane is exactly edge-on and must retain its different geometry.
    private static func displacementProfiles(device: MTLDevice, loader: SceneTextureLoader,
                                             directory: URL, colorURL: URL) throws -> [[String: Any]] {
        let size = 128
        let palette: [[UInt8]] = [[255, 64, 0, 192], [255, 192, 0, 224],
                                  [255, 224, 0, 64], [255, 32, 0, 96]]
        var payload = Data()
        for y in 0..<8 { for x in 0..<8 {
            payload.append(contentsOf: palette[(y / 4) * 2 + x / 4])
        } }
        let url = directory.appendingPathComponent("asymmetric-direction-field.tex")
        try makeTex(format: 0, textureWidth: 8, textureHeight: 8,
                    imageWidth: 8, imageHeight: 8, payload: payload).write(to: url)
        let refract = try refraction(colorURL: colorURL, normalURL: url,
            amount: 0.125, loader: loader, device: device)
        let roll = SceneMatrix.rotationZ(.pi / 6)
        let right = SIMD3(roll.columns.0.x, roll.columns.0.y, roll.columns.0.z)
        let up = SIMD3(roll.columns.1.x, roll.columns.1.y, roll.columns.1.z)
        let view = SceneMatrix.lookAt(eye: .zero, center: SIMD3(0, 0, -1), up: up)
        let vp = SceneMatrix.perspectiveRHMetal(fovYRadians: .pi / 2,
            aspect: 1, near: 0.1, far: 100) * view
        let endpoints = [SIMD4<Float>(-5, -5, -10, 1), SIMD4<Float>(5, -5, -10, 1)]
            .map { roll * $0 }
        let probes = [(48, 92), (80, 92), (48, 100), (80, 100)]
        var rows: [[String: Any]] = []
        for displacement in [true, false] {
            for tilted in [false, true] {
                let model = roll * (tilted ? SceneMatrix.rotationX(atan(Float(2)))
                    : SceneMatrix.identity()) * SceneMatrix.scale(SIMD3(repeating: 0.2))
                let inverse = simd_inverse(model)
                let first = inverse * endpoints[0], last = inverse * endpoints[1]
                let center = (first + last) * 0.5, delta = last - first
                let instance = SceneParticleGPUInstance(
                    position: SIMD3(center.x, center.y, center.z), size: 20,
                    rotation: .zero, color: SIMD3(repeating: 1), alpha: 1,
                    velocity: SIMD3(delta.x, delta.y, delta.z), trailStretch: 5,
                    trailUVRange: SIMD2(0, 1), usesTrailDisplacement: displacement,
                    trailHeadDirection: displacement ? SIMD3(delta.x, delta.y, delta.z) : nil,
                    trailTailDirection: displacement ? SIMD3(delta.x, delta.y, delta.z) : nil,
                    trailEndpointSizes: displacement ? SIMD2(20, 20) : nil)
                let basis = SceneParticleOrientationBasis(
                    right: simd_normalize(SIMD3(model.columns.0.x, model.columns.0.y, model.columns.0.z)),
                    up: simd_normalize(SIMD3(model.columns.1.x, model.columns.1.y, model.columns.1.z)),
                    localTrailNormal: SIMD3(0, 0, 1))
                let uniforms = SceneParticleLayerUniforms(viewProjection: vp, layerModel: model,
                    basis: basis, viewportSize: SIMD2(repeating: Float(size)),
                    viewBasis: .init(right: right, up: up))
                let pixels = try drawPixels(device: device, refraction: refract, particleAlpha: 1,
                    blendMode: .translucent, gradientBackground: true, size: size,
                    instance: instance, uniforms: uniforms)
                var visible = 0, outside = 0
                var bounds = [size, size, -1, -1]
                // 90-degree projection: endpoints (32,96)/(96,96), width 12.8px.
                // One-pixel raster pad; the original plane has zero projected area.
                for y in 0..<size { for x in 0..<size {
                    guard pixels[(y * size + x) * 4 + 3] > 20 else { continue }
                    visible += 1
                    bounds = [min(bounds[0], x), min(bounds[1], y),
                              max(bounds[2], x), max(bounds[3], y)]
                    if x < 31 || x > 96 || y < 88 || y > 103 { outside += 1 }
                } }
                let projected = endpoints.map { point -> [Float] in
                    let clip = vp * point
                    return [(clip.x / clip.w + 1) * 64, (1 - clip.y / clip.w) * 64]
                }
                let clipRight = vp * SIMD4(right, 0), clipUp = vp * SIMD4(up, 0)
                rows.append(["name": (displacement ? "displacement" : "ordinary")
                    + (tilted ? "-tilted" : "-flat"), "completed": true,
                    "inputFinite": instance.isFinite, "anchorPixels": projected,
                    "usesDisplacement": instance.frame1B.z > 0.5,
                    "joined": instance.frame1B.w > 0.5,
                    "viewRightProjection": [clipRight.x, clipRight.y, clipRight.w],
                    "viewUpProjection": [clipUp.x, clipUp.y, clipUp.w],
                    "visiblePixels": visible, "outsidePixels": outside, "bounds": bounds,
                    "probes": probes.map { x, y in
                        Array(pixels[(y * size + x) * 4 ..< (y * size + x) * 4 + 4]).map(Int.init)
                    }])
            }
        }
        return rows
    }

    private static func r8ColorProfiles(device: MTLDevice, loader: SceneTextureLoader,
                                        directory: URL) throws -> [String: Any] {
        var urls: [String: URL] = [:]
        var samples: [String: Any] = [:]
        let inputs: [(String, UInt32, [UInt8])] = [
            ("zero", 9, [0]), ("fractional", 9, [128]), ("renamed", 9, [128]),
            ("opaque", 9, [255]), ("rgba", 0, [255,255,255,128]),
            ("rg88", 8, [64,192]), ("rgEquivalent", 0, [64,64,64,192])
        ]
        for (name, format, pixel) in inputs {
            let url = directory.appendingPathComponent(name + "-unrelated-resource.tex")
            try makeTex(format: format, payload: Data((0..<16).flatMap { _ in pixel })).write(to: url)
            urls[name] = url
            for (modeName, mode) in [("translucent", SceneParticlePipelineBlendMode.translucent),
                                     ("additive", SceneParticlePipelineBlendMode.additive)] {
                let amounts = try [Float(-1),0,1].map { amount in
                    try draw(device: device, refraction: refraction(colorURL: url, normalURL: nil,
                        amount: amount, loader: loader, device: device), particleAlpha: 0.5,
                        blendMode: mode, gradientBackground: false)
                }
                samples[name + modeName] = ["amounts": amounts,
                    "overbright": try draw(device: device, refraction: refraction(colorURL: url,
                        normalURL: nil, amount: 0, overbright: 5, loader: loader, device: device),
                        particleAlpha: 0.5, blendMode: mode, gradientBackground: false)]
            }
        }
        let frames: [[Float]] = [[0,0,2,0,0,4], [2,0,2,0,0,4]]
        let atlasURL = directory.appendingPathComponent("another-alpha-atlas.tex")
        let bytes = makeTex(format: 9, flags: 2,
            payload: Data((0..<4).flatMap { _ in [UInt8(0),0,255,255] }),
            secondMip: Data([32,224,32,224]), frames: frames)
        try bytes.write(to: atlasURL)
        let atlas = try refraction(colorURL: atlasURL, normalURL: nil, amount: 1,
            loader: loader, device: device)
        let parsed = try SceneTexContainerReader().read(data: bytes).spriteFrames
        let transforms = parsed.map { SceneParticleFrameTransform(origin: $0.origin, xAxis: $0.xAxis, yAxis: $0.yAxis) }
        let atlasPixels = try [Float(0),0.5,1].map { mix in
            let instance = SceneParticleGPUInstance(position: .zero, size: 2, rotation: .zero,
                color: SIMD3(repeating: 1), alpha: 0.5, currentFrame: transforms[0],
                nextFrame: transforms[1], frameMix: mix)
            let pixels = try drawPixels(device: device, refraction: atlas, particleAlpha: 0.5,
                blendMode: .translucent, gradientBackground: false, instance: instance)
            return Array(pixels[((16 * 32 + 16) * 4)..<((16 * 32 + 16) * 4 + 4)]).map(Int.init)
        }
        let normalAtlasURL = directory.appendingPathComponent("different-normal-frames.tex")
        try makeTex(format: 0, payload: Data((0..<16).flatMap { _ in [UInt8(255),128,0,128] }),
            frames: frames).write(to: normalAtlasURL)
        var rejected: [String: Bool] = [:]
        for (name, normalURL) in [("normalR8Rejected", urls["fractional"]!),
                                   ("normalFramesMismatchRejected", normalAtlasURL)] {
            rejected[name] = try SceneParticleRefractionTextureLoader.load(
                colorSource: .file(.externalFile(urls["fractional"]!)),
                declaration: SceneParticleRefractionDeclaration(normalTextureSource: .file(.externalFile(normalURL)),
                    amount: 1, overbright: 1), textureLoader: loader, device: device) == nil
        }
        return ["samples": samples, "atlasPixels": atlasPixels,
            "gradientAmounts": try [Float(-1),0,1].map { amount in
                try draw(device: device, refraction: refraction(colorURL: urls["fractional"]!, normalURL: nil,
                    amount: amount, loader: loader, device: device), particleAlpha: 0.5,
                    blendMode: .translucent, gradientBackground: true) },
            "atlasMip": try readback.pixel(atlas.color, level: 1).map(Int.init),
            "atlasUVScale": [atlas.colorUVScale.x, atlas.colorUVScale.y],
            "nativeStorageAndMips": atlas.color.pixelFormat == .r8Unorm && atlas.color.mipmapLevelCount == 2,
            "rawNormalSample": try readPixel(loaded(loader.load(from: urls["fractional"]!,
                purpose: .normal, device: device))).map(Int.init),
            "normalR8Rejected": rejected["normalR8Rejected"]!,
            "normalFramesMismatchRejected": rejected["normalFramesMismatchRejected"]!]
    }

    private static func refraction(
        colorURL: URL,
        normalURL: URL?,
        amount: Float,
        overbright: Float = 1,
        loader: SceneTextureLoader,
        device: MTLDevice
    ) throws -> SceneParticleRefractionTextureLoader.Loaded {
        guard let loaded = try SceneParticleRefractionTextureLoader.load(
            colorSource: .file(.externalFile(colorURL)),
            declaration: SceneParticleRefractionDeclaration(
                normalTextureSource: normalURL.map { .file(.externalFile($0)) },
                amount: amount,
                overbright: overbright
            ),
            textureLoader: loader,
            device: device
        ) else {
            throw HarnessError.texture
        }
        return loaded
    }

    private static func makeDXT5nTex() -> Data {
        makeTex(
            format: 4,
            payload: dxt5nBlock()
        )
    }

    private static func makeDirectDXT5nTex() -> Data {
        var data = Data("TEXV0005\0TEXI0001\0".utf8)
        func append(_ value: UInt32) {
            var littleEndian = value.littleEndian
            withUnsafeBytes(of: &littleEndian) {
                data.append(contentsOf: $0)
            }
        }
        append(4)
        append(0)
        append(4)
        append(4)
        append(4)
        append(4)
        append(0)
        data.append(Data("TEXB0002\0".utf8))
        append(2)
        for _ in 0 ..< 2 {
            let block = dxt5nBlock()
            append(1)
            append(4)
            append(4)
            append(0)
            append(0)
            append(UInt32(block.count))
            data.append(block)
        }
        return data
    }

    private static func dxt5nBlock() -> Data {
        Data([
            64, 64, 0, 0, 0, 0, 0, 0,
            0x00, 0xFC, 0x00, 0xFC, 0, 0, 0, 0,
        ])
    }

    private static func makeRawTex(
        pixel: [UInt8],
        flags: UInt32 = 0,
        textureWidth: UInt32 = 4,
        textureHeight: UInt32 = 4,
        imageWidth: UInt32 = 4,
        imageHeight: UInt32 = 4
    ) -> Data {
        makeTex(
            format: 0,
            flags: flags,
            textureWidth: textureWidth,
            textureHeight: textureHeight,
            imageWidth: imageWidth,
            imageHeight: imageHeight,
            payload: Data(
                (0 ..< Int(textureWidth * textureHeight)).flatMap { _ in pixel }
            )
        )
    }

    private static func makePaddedRawNormalTex() -> Data {
        let mapped: [UInt8] = [255, 128, 0, 128]
        let padding: [UInt8] = [255, 255, 0, 0]
        let payload = Data((0 ..< 4).flatMap { _ in
            (0 ..< 4).flatMap { _ in mapped }
                + (0 ..< 4).flatMap { _ in padding }
        })
        return makeTex(
            format: 0,
            flags: 2,
            textureWidth: 8,
            textureHeight: 4,
            imageWidth: 4,
            imageHeight: 4,
            payload: payload
        )
    }

    private static func makeOpaquePNG(width: Int, height: Int, straight16: Bool = false) throws -> Data {
        let pixels = straight16
            ? Data((0 ..< width * height).flatMap { _ in [UInt8](arrayLiteral: 255,255,18,52,171,205,128,1) })
            : Data(repeating: 255, count: width * height * 4)
        guard let provider = CGDataProvider(data: pixels as CFData),
              let image = CGImage(
                  width: width,
                  height: height,
                  bitsPerComponent: straight16 ? 16 : 8,
                  bitsPerPixel: straight16 ? 64 : 32,
                  bytesPerRow: width * (straight16 ? 8 : 4),
                  space: CGColorSpaceCreateDeviceRGB(),
                  bitmapInfo: CGBitmapInfo(
                      rawValue: straight16 ? CGImageAlphaInfo.last.rawValue | CGBitmapInfo.byteOrder16Big.rawValue : CGImageAlphaInfo.noneSkipLast.rawValue
                  ),
                  provider: provider,
                  decode: nil,
                  shouldInterpolate: false,
                  intent: .defaultIntent
              ),
              let data = CFDataCreateMutable(nil, 0),
              let destination = CGImageDestinationCreateWithData(
                  data,
                  "public.png" as CFString,
                  1,
                  nil
              ) else {
            throw HarnessError.texture
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw HarnessError.texture
        }
        return data as Data
    }

    private static func makeTex(
        format: UInt32,
        flags: UInt32 = 0,
        textureWidth: UInt32 = 4,
        textureHeight: UInt32 = 4,
        imageWidth: UInt32 = 4,
        imageHeight: UInt32 = 4,
        payload: Data,
        secondMip: Data? = nil,
        frames: [[Float]] = []
    ) -> Data {
        var data = Data("TEXV0005\0TEXI0001\0".utf8)
        func append(_ value: UInt32) {
            var littleEndian = value.littleEndian
            withUnsafeBytes(of: &littleEndian) {
                data.append(contentsOf: $0)
            }
        }
        append(format)
        append(frames.isEmpty ? flags : flags | 4)
        append(textureWidth)
        append(textureHeight)
        append(imageWidth)
        append(imageHeight)
        append(0)
        data.append(Data("TEXB0002\0".utf8))
        append(1)
        append(secondMip == nil ? 1 : 2)
        append(textureWidth)
        append(textureHeight)
        append(0)
        append(0)
        append(UInt32(payload.count))
        data.append(payload)
        if let secondMip {
            append(max(1, textureWidth / 2)); append(max(1, textureHeight / 2))
            append(0); append(0); append(UInt32(secondMip.count)); data.append(secondMip)
        }
        if !frames.isEmpty {
            data.append(Data("TEXS0002\0".utf8)); append(UInt32(frames.count))
            for coordinates in frames {
                append(0); append(Float(0.1).bitPattern)
                for value in coordinates { append(value.bitPattern) }
            }
        }
        return data
    }

    private static func candidate(
        texture: MTLTexture,
        purpose: SceneTextureLoadPurpose,
        sampling: SceneTextureSampling = .linearClamp,
        authoredFormat: SceneShaderTextureFormat? = .rgba8888
    ) -> SceneTextureCandidate {
        let size = CGSize(width: texture.width, height: texture.height)
        let content: SceneTextureContent
        switch purpose {
        case .premultipliedColor:
            content = .color(.resolved(.premultipliedAlpha))
        case .straightAlbedo:
            content = .color(.resolved(.straightAlpha))
        default:
            content = .data
        }
        return SceneTextureCandidate(
            texture: texture,
            identity: .builtIn(name: "refraction-test"),
            generation: .immutable(revision: 1),
            purpose: purpose,
            content: content,
            physicalSize: size,
            mappedSize: size,
            uvTransform: .identity,
            sampling: sampling,
            authoredFormat: authoredFormat
        )
    }

    private static func normalArguments(
        _ binding: SceneParticleRefractionBinding
    ) throws -> SceneParticleRefractionBinding.NormalArguments {
        guard let arguments = binding.resolvedNormalArguments() else {
            throw HarnessError.texture
        }
        return arguments
    }

    private static func loaded(
        _ outcome: SceneTextureLoadOutcome
    ) throws -> MTLTexture {
        guard case let .loaded(texture) = outcome else {
            throw HarnessError.texture
        }
        return texture
    }

    private static func readPixel(_ texture: MTLTexture) throws -> [UInt8] {
        try readback.pixel(texture)
    }

    private enum HarnessError: Error {
        case gpu
        case texture
    }
}
