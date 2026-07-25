import Foundation
import Metal

final class SceneParticleBuiltInTextureRegistry {
    private let device: MTLDevice
    private var textures: [SceneParticleBuiltInTexture: MTLTexture] = [:]

    init(device: MTLDevice) {
        self.device = device
    }

    func texture(for builtInTexture: SceneParticleBuiltInTexture) -> MTLTexture? {
        if let texture = textures[builtInTexture] {
            return texture
        }
        guard let texture = makeTexture(for: builtInTexture) else { return nil }
        textures[builtInTexture] = texture
        return texture
    }

    private func makeTexture(for builtInTexture: SceneParticleBuiltInTexture) -> MTLTexture? {
        let size = textureSize(for: builtInTexture)
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm,
            width: size,
            height: size,
            mipmapped: false
        )
        descriptor.usage = .shaderRead
        descriptor.storageMode = .shared
        guard let texture = device.makeTexture(descriptor: descriptor) else {
            return nil
        }
        texture.label = "Scene particle generated \(builtInTexture.rawValue)"

        var pixels = [UInt8](repeating: 0, count: size * size * 4)
        for y in 0..<size {
            for x in 0..<size {
                let normalizedX = (Float(x) + 0.5) / Float(size) * 2 - 1
                let normalizedY = (Float(y) + 0.5) / Float(size) * 2 - 1
                let alpha = (x == 0 || y == 0 || x == size - 1 || y == size - 1)
                    ? 0
                    : alpha(
                        for: builtInTexture,
                        x: normalizedX,
                        y: normalizedY
                    )
                let component = UInt8((alpha * 255).rounded())
                let offset = (y * size + x) * 4
                pixels[offset] = component
                pixels[offset + 1] = component
                pixels[offset + 2] = component
                pixels[offset + 3] = component
            }
        }

        pixels.withUnsafeBytes { bytes in
            guard let address = bytes.baseAddress else { return }
            texture.replace(
                region: MTLRegionMake2D(0, 0, size, size),
                mipmapLevel: 0,
                withBytes: address,
                bytesPerRow: size * 4
            )
        }
        return texture
    }

    private func textureSize(for builtInTexture: SceneParticleBuiltInTexture) -> Int {
        switch builtInTexture {
        case .drop:
            32
        case .chromaticDot, .leaves7, .leaves8, .halo, .halo2, .halo4,
             .rippleSingle, .rosePetals:
            64
        case .beam1, .fire1, .fog1, .lightShafts0, .lightShafts6, .lightning3:
            128
        }
    }

    private func alpha(
        for builtInTexture: SceneParticleBuiltInTexture,
        x: Float,
        y: Float
    ) -> Float {
        switch builtInTexture {
        case .beam1:
            let axial = pow(smooth(1 - abs(x)), 0.65)
            let core = pow(smooth(1 - abs(y) / 0.16), 1.4)
            let glow = 0.32 * pow(smooth(1 - abs(y) / 0.34), 2)
            return axial * clamp(core + glow)
        case .chromaticDot:
            let radius = hypot(x, y)
            return pow(smooth(1 - radius), 1.35)
        case .drop:
            let radiusSquared = x * x + y * y
            return smooth(1 - radiusSquared)
        case .fire1:
            return fireAlpha(x: x, y: y)
        case .fog1:
            let wave = 0.08 * sin(x * 7.1) + 0.05 * sin(x * 13.7 + 0.8)
            let radius = sqrt(x * x + pow((y - wave) / 0.48, 2))
            return 0.72 * pow(smooth(1 - radius), 0.72)
        case .leaves7:
            return leafAlpha(x: x, y: y, rotation: -0.48, bend: 0.16, width: 0.42)
        case .leaves8:
            return leafAlpha(x: x, y: y, rotation: 0.62, bend: -0.13, width: 0.32)
        case .lightShafts0:
            let progress = clamp((y + 1) * 0.5)
            let vertical = smooth(progress * 4) * smooth((1 - progress) * 3)
            let primaryCenter = -0.28 + progress * 0.18
            let primaryWidth = 0.055 + progress * 0.22
            let secondaryCenter = 0.28 + progress * 0.08
            let secondaryWidth = 0.035 + progress * 0.14
            let primary = pow(smooth(1 - abs(x - primaryCenter) / primaryWidth), 1.7)
            let secondary = pow(smooth(1 - abs(x - secondaryCenter) / secondaryWidth), 1.8)
            return 0.18 * vertical * clamp(primary + 0.55 * secondary)
        case .lightShafts6:
            let progress = clamp((y + 1) * 0.5)
            let width = 0.08 + progress * 0.52
            let distance = abs(x + 0.18 * y - 0.06)
            let horizontal = smooth(1 - distance / width)
            let vertical = smooth(progress) * smooth(1 - abs(y) * 0.82)
            return 0.72 * horizontal * vertical
        case .lightning3:
            return lightningAlpha(x: x, y: y)
        case .halo:
            let radius = sqrt(x * x + y * y)
            return pow(smooth(1 - radius), 2.2)
        case .halo2:
            let radius = sqrt(x * x + y * y)
            let core = 0.55 * pow(smooth(1 - radius), 1.4)
            let shoulder = 0.35 * smooth(1 - abs(radius - 0.42) / 0.42)
            return clamp(core + shoulder)
        case .halo4:
            let radius = sqrt(x * x + y * y)
            let core = pow(smooth(1 - radius / 0.055), 0.75)
            let glow = 0.38 * pow(smooth(1 - radius / 0.14), 2.2)
            return clamp(core + glow)
        case .rippleSingle:
            let radius = sqrt(x * x + pow(y / 0.56, 2))
            return pow(smooth(1 - abs(radius - 0.66) / 0.13), 1.6)
        case .rosePetals:
            return rosePetalAlpha(x: x, y: y)
        }
    }

    private func fireAlpha(x: Float, y: Float) -> Float {
        let progress = (y + 0.38) / 0.76
        guard progress > 0, progress < 1 else { return 0 }
        let center = 0.035 * sin(progress * 7.2) + 0.015 * sin(progress * 15)
        let halfWidth = 0.025 + 0.2 * pow(progress, 0.72)
        let body = smooth((1 - abs(x - center) / halfWidth) * 3.2)
        let tipFade = smooth(progress * 10)
        let baseFade = smooth((1 - progress) * 8)
        return 0.16 * body * tipFade * baseFade
    }

    private func rosePetalAlpha(x: Float, y: Float) -> Float {
        let rotation: Float = 0.36
        let cosine = cos(rotation)
        let sine = sin(rotation)
        let localX = x * cosine - y * sine
        let localY = x * sine + y * cosine
        let axial = (localY + 0.04) / 0.78
        guard abs(axial) < 1 else { return 0 }
        let profile = sqrt(max(1 - axial * axial, 0))
        let halfWidth = 0.54 * profile * (1 - 0.12 * max(axial, 0))
        let curvedX = localX + 0.1 * (1 - axial * axial)
        return smooth((1 - abs(curvedX) / max(halfWidth, 0.001)) * 4.5)
            * smooth((1 - abs(axial)) * 6)
    }

    private func leafAlpha(
        x: Float,
        y: Float,
        rotation: Float,
        bend: Float,
        width: Float
    ) -> Float {
        let cosine = cos(rotation)
        let sine = sin(rotation)
        let localX = x * cosine - y * sine
        let localY = x * sine + y * cosine
        let axial = localY / 0.82
        guard abs(axial) < 1 else { return 0 }
        let halfWidth = width * sqrt(max(1 - axial * axial, 0))
        let curvedX = localX - bend * (1 - axial * axial)
        return smooth((1 - abs(curvedX) / max(halfWidth, 0.001)) * 5)
            * smooth((1 - abs(axial)) * 7)
    }

    private func lightningAlpha(x: Float, y: Float) -> Float {
        let points: [(Float, Float)] = [
            (-0.22, -0.94), (-0.04, -0.55), (-0.18, -0.18),
            (0.12, 0.12), (-0.02, 0.45), (0.24, 0.92),
        ]
        var distance = Float.greatestFiniteMagnitude
        for index in 0..<(points.count - 1) {
            distance = min(
                distance,
                distanceToSegment(
                    x: x,
                    y: y,
                    start: points[index],
                    end: points[index + 1]
                )
            )
        }
        distance = min(
            distance,
            distanceToSegment(x: x, y: y, start: (-0.12, -0.31), end: (-0.52, -0.08))
        )
        distance = min(
            distance,
            distanceToSegment(x: x, y: y, start: (0.07, 0.22), end: (0.48, 0.46))
        )
        let core = smooth(1 - distance / 0.026)
        let glow = 0.48 * pow(smooth(1 - distance / 0.13), 2)
        return clamp(core + glow)
    }

    private func distanceToSegment(
        x: Float,
        y: Float,
        start: (Float, Float),
        end: (Float, Float)
    ) -> Float {
        let deltaX = end.0 - start.0
        let deltaY = end.1 - start.1
        let lengthSquared = deltaX * deltaX + deltaY * deltaY
        let projection = ((x - start.0) * deltaX + (y - start.1) * deltaY) / lengthSquared
        let amount = clamp(projection)
        let nearestX = start.0 + deltaX * amount
        let nearestY = start.1 + deltaY * amount
        return hypot(x - nearestX, y - nearestY)
    }

    private func smooth(_ value: Float) -> Float {
        let bounded = clamp(value)
        return bounded * bounded * (3 - 2 * bounded)
    }

    private func clamp(_ value: Float) -> Float {
        min(max(value, 0), 1)
    }
}
