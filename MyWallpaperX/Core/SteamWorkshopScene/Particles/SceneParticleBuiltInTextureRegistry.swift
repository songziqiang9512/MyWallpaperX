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
            width: size.width,
            height: size.height,
            mipmapped: false
        )
        descriptor.usage = .shaderRead
        descriptor.storageMode = .shared
        guard let texture = device.makeTexture(descriptor: descriptor) else {
            return nil
        }
        texture.label = "Scene particle generated \(builtInTexture.rawValue)"

        var pixels = [UInt8](repeating: 0, count: size.width * size.height * 4)
        for y in 0..<size.height {
            for x in 0..<size.width {
                let normalizedX = (Float(x) + 0.5) / Float(size.width) * 2 - 1
                let normalizedY = (Float(y) + 0.5) / Float(size.height) * 2 - 1
                let onBorder = x == 0 || y == 0 || x == size.width - 1 || y == size.height - 1
                let alpha = onBorder
                    ? 0
                    : alpha(
                        for: builtInTexture,
                        x: normalizedX,
                        y: normalizedY
                    )
                // 粒子混合管线用 sourceRGB = .one，纹理需自带预乘 alpha，
                // 因此 RGB 与 alpha 同值即预乘后的白色。
                let component = UInt8((alpha * 255).rounded())
                let offset = (y * size.width + x) * 4
                pixels[offset] = component
                pixels[offset + 1] = component
                pixels[offset + 2] = component
                pixels[offset + 3] = component
            }
        }

        pixels.withUnsafeBytes { bytes in
            guard let address = bytes.baseAddress else { return }
            texture.replace(
                region: MTLRegionMake2D(0, 0, size.width, size.height),
                mipmapLevel: 0,
                withBytes: address,
                bytesPerRow: size.width * 4
            )
        }
        return texture
    }

    /// 尺寸对齐官方 .tex 的 imageWidth/imageHeight；序列帧图集按单帧方形近似。
    private func textureSize(
        for builtInTexture: SceneParticleBuiltInTexture
    ) -> (width: Int, height: Int) {
        switch builtInTexture {
        case .drop, .beam1:
            return (width: 32, height: 128)
        case .chromaticDot, .halo, .halo2, .halo3, .star,
             .leaves7, .leaves8, .snow, .rippleSingle, .rosePetals:
            return (width: 64, height: 64)
        case .halo4, .halo6, .fire1, .fog1, .fog3, .lightning3, .smoke2:
            return (width: 128, height: 128)
        case .flare1:
            return (width: 256, height: 256)
        case .lightShafts6:
            return (width: 128, height: 512)
        case .lightShafts0:
            return (width: 256, height: 512)
        }
    }

    private func alpha(
        for builtInTexture: SceneParticleBuiltInTexture,
        x: Float,
        y: Float
    ) -> Float {
        switch builtInTexture {
        case .beam1:
            // 官方 32x128 是上下对称的椭圆径向光斑：横向铺满全幅、纵向到 ±0.85 收敛，
            // 峰值落在正中心，并不是沿某一轴的纺锤。
            let radius = hypot(x / 0.95, y / 1.02)
            return 0.92 * pow(smooth(1 - radius), 0.9)
        case .chromaticDot:
            let radius = hypot(x, y)
            return pow(smooth(1 - radius), 1.35)
        case .drop:
            return dropAlpha(x: x, y: y)
        case .fire1:
            return fireAlpha(x: x, y: y)
        case .fog1:
            let wave = 0.08 * sin(x * 7.1) + 0.05 * sin(x * 13.7 + 0.8)
            let radius = sqrt(x * x + pow((y - wave) / 0.48, 2))
            return 0.72 * pow(smooth(1 - radius), 0.72)
        case .fog3:
            return fogAlpha(x: x, y: y)
        case .leaves7:
            return leafAlpha(x: x, y: y, rotation: -0.48, bend: 0.16, width: 0.42)
        case .leaves8:
            return leafAlpha(x: x, y: y, rotation: 0.62, bend: -0.13, width: 0.32)
        case .snow:
            return snowAlpha(x: x, y: y)
        case .lightShafts0:
            // 官方 256x512 是单柱居中（质心恒在 x≈0.055），峰值在 y≈-0.7 后向下渐淡。
            let envelope = min(
                smooth((y + 1) / 0.28),
                pow(smooth((1.1 - y) / 2.2), 1.3)
            )
            return 0.92 * envelope * pow(smooth(1 - abs(x - 0.055) / 0.75), 1.6)
        case .lightShafts6:
            return lightShafts6Alpha(x: x, y: y)
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
        case .halo3:
            let radius = sqrt(x * x + y * y)
            let core = 0.14 * pow(smooth(1 - radius), 1.45)
            let shoulder = 0.08 * pow(smooth(1 - abs(radius - 0.44) / 0.36), 1.8)
            return clamp(core + shoulder)
        case .halo4:
            // 官方是极小亮核叠一层覆盖整幅的低幅外晕；旧实现在 r>0.14 归零，
            // 把占绝大部分面积的外晕整个丢了。
            let radius = sqrt(x * x + y * y)
            let core = 0.70 * smooth(1 - radius / 0.14)
            let halo = 0.20 * pow(clamp(1 - radius), 1.5)
            return clamp(core + halo)
        case .halo6:
            return halo6Alpha(x: x, y: y)
        case .star:
            return starAlpha(x: x, y: y)
        case .flare1:
            return flareAlpha(x: x, y: y)
        case .rippleSingle:
            let radius = sqrt(x * x + pow(y / 0.56, 2))
            return pow(smooth(1 - abs(radius - 0.66) / 0.13), 1.6)
        case .rosePetals:
            return rosePetalAlpha(x: x, y: y)
        case .smoke2:
            return smokeAlpha(x: x, y: y)
        }
    }

    private func dropAlpha(x: Float, y: Float) -> Float {
        // 官方 32x128 是头部在上、尾迹向下的彗形：峰值在 y≈-0.65 处半宽约 0.72，
        // 尾迹收敛到 0.5 后等宽淡出，而非首尾对称的泪滴。
        let axial = (y + 0.62) / 1.52
        let envelope = min(
            smooth((y + 1) / 0.32),
            pow(smooth((0.95 - y) / 1.57), 1.1)
        )
        let halfWidth = 0.50 + 0.22 * smooth(1 - abs(axial) / 0.38)
        return envelope * pow(smooth(1 - abs(x) / halfWidth), 0.55)
    }

    private func lightShafts6Alpha(x: Float, y: Float) -> Float {
        // 官方 128x512 是一对竖柱且整幅在 y>0.2 已归零：主柱在 x≈0.34（峰值 y≈-0.6），
        // 次柱在 x≈-0.33 且幅度更低。
        let mainEnvelope = min(
            smooth((y + 1) / 0.28),
            pow(smooth((0.55 - y) / 1.1), 1.3)
        )
        let main = 0.60 * mainEnvelope * pow(smooth(1 - abs(x - 0.344) / 0.70), 2.7)
        let sideEnvelope = smooth((y + 1) / 0.5) * pow(smooth((0.35 - y) / 0.9), 1.2)
        let side = 0.35 * sideEnvelope * pow(smooth(1 - abs(x + 0.328) / 0.60), 1.6)
        return clamp(main + side)
    }

    private func halo6Alpha(x: Float, y: Float) -> Float {
        // 共享 halo_6 实测校准曲线：纯白盘，仅 alpha 随半径衰减。
        let stops: [(Float, Float)] = [
            (0.50, 1.000),
            (0.625, 0.969),
            (0.750, 0.588),
            (0.875, 0.114),
            (1.000, 0.000),
        ]
        let radius = hypot(x, y)
        if radius <= stops[0].0 { return stops[0].1 }
        for index in 1..<stops.count where radius <= stops[index].0 {
            let lower = stops[index - 1]
            let upper = stops[index]
            let t = (radius - lower.0) / (upper.0 - lower.0)
            return lower.1 + (upper.1 - lower.1) * smooth(t)
        }
        return 0
    }

    private func starAlpha(x: Float, y: Float) -> Float {
        // 官方是手绘不规则星芒：主体为一团偏心实心亮斑，外围挂几条低幅碎芒，
        // 亮向没有周期性，无法用 N 芒星公式表达，只能做形态近似。
        let deltaX = x + 0.05
        let deltaY = y + 0.05
        let radius = hypot(deltaX, deltaY)
        let core = pow(smooth((0.54 - radius) / 0.52), 0.5)
        let angle = atan2(deltaY, deltaX)
        let spikeAngles: [Float] = [0.52, 1.05, 1.83, 2.09, 2.36, 2.88, 3.14]
        var spikes: Float = 0
        for base in spikeAngles {
            var delta = abs(angle - base)
            if delta > .pi { delta = 2 * .pi - delta }
            let angular = pow(smooth(1 - delta / 0.30), 2)
            spikes = max(spikes, 0.45 * angular * pow(smooth(1 - radius / 0.95), 1.4))
        }
        return clamp(core + spikes)
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

    private func fogAlpha(x: Float, y: Float) -> Float {
        let wave = 0.07 * sin(x * 5.3 + 0.4) + 0.035 * sin(x * 11.1 - 0.7)
        let primary = sqrt(pow((x + 0.08) / 0.92, 2) + pow((y - wave) / 0.62, 2))
        let secondary = sqrt(pow((x - 0.34) / 0.62, 2) + pow((y + 0.11) / 0.48, 2))
        let body = pow(smooth(1 - primary), 1.1)
        let lobe = 0.55 * pow(smooth(1 - secondary), 1.5)
        return 0.008 * clamp(body + lobe)
    }

    private func flareAlpha(x: Float, y: Float) -> Float {
        // 官方 256x256 是水平细长光斑：横向按 exp(-9|x|) 衰减并在 |x|≈0.25 后截止，
        // 纵向是 σ≈0.065 的高斯，并没有等长的十字光芒。
        let horizontal = exp(-9 * abs(x)) * smooth((0.25 - abs(x)) / 0.25)
        let normalizedY = y / 0.065
        let vertical = exp(-normalizedY * normalizedY)
        return clamp(horizontal * vertical)
    }

    private func snowAlpha(x: Float, y: Float) -> Float {
        let radius = hypot(x, y)
        guard radius < 0.82 else { return 0 }
        let angle = atan2(y, x)
        let armDistance = radius * abs(sin(angle * 3))
        let arms = smooth(1 - armDistance / 0.055)
            * smooth((radius - 0.08) * 12)
            * smooth((0.82 - radius) * 6)
        let core = pow(smooth(1 - radius / 0.3), 1.6)
        return 0.52 * clamp(arms + 0.65 * core)
    }

    private func smokeAlpha(x: Float, y: Float) -> Float {
        let waveX = x + 0.07 * sin(y * 7.3) + 0.035 * sin(y * 13.1 + 0.4)
        let waveY = y + 0.06 * sin(x * 6.1 - 0.7)
        let primary = sqrt(pow(waveX / 0.92, 2) + pow(waveY / 0.72, 2))
        let secondary = sqrt(pow((waveX - 0.38) / 0.58, 2) + pow((waveY + 0.12) / 0.5, 2))
        let body = pow(smooth(1 - primary), 0.82)
        let lobe = 0.45 * pow(smooth(1 - secondary), 1.3)
        return 0.045 * clamp(body + lobe)
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
