import CoreGraphics
import Foundation
import Metal

/// Deterministic stock noise textures for shader-declared sampler defaults
/// (user-directed 2026-09-26). Wallpaper Engine ships engine assets like
/// `util/clouds_256` that samples never carry in their pkg; without a
/// deterministic substitute those samplers sampled an unbound slot (the
/// 3750813609 clock rendered black-and-white instead of pure white). Each
/// registered stock noise name maps to one per-device R8 texture generated
/// from a fixed seed; shipped pkg assets always win over this substitute.
nonisolated final class SceneStockNoiseTextureStore: @unchecked Sendable {
    nonisolated struct Demand: Hashable, Sendable {
        let name: String
        let purpose: SceneTextureLoadPurpose
        let content: SceneTextureContent
    }

    private let lock = NSLock()
    private var texturesByDemand: [Demand: MTLTexture] = [:]
    private static let side = 256

    nonisolated static let demands: [Demand] = SceneStockTextureSemanticRegistry
        .noiseTexturePaths.map { path in
            Demand(name: path, purpose: .noise, content: .data)
        }

    nonisolated func texture(
        for demand: Demand,
        device: MTLDevice
    ) -> MTLTexture? {
        lock.lock()
        if let cached = texturesByDemand[demand],
            cached.device.registryID == device.registryID {
            lock.unlock()
            return cached
        }
        lock.unlock()
        guard let texture = Self.makeTexture(
            name: demand.name,
            device: device
        ) else { return nil }
        lock.lock()
        texturesByDemand[demand] = texture
        lock.unlock()
        return texture
    }

    /// Complete publication for the frame registry; mirrors the media
    /// thumbnail store's candidate shape (identity UV, linear clamp).
    nonisolated func publication(
        for demand: Demand,
        device: MTLDevice
    ) -> SceneTextureProviderPublication? {
        guard let texture = texture(for: demand, device: device) else {
            return nil
        }
        let identity = SceneSystemProviderTextureIdentity(
            name: demand.name,
            purpose: demand.purpose
        )
        let size = CGSize(width: texture.width, height: texture.height)
        return SceneTextureProviderPublication(
            requestIdentity: .system(identity),
            candidate: SceneTextureCandidate(
                texture: texture,
                identity: .builtIn(name: demand.name),
                generation: .immutable(revision: 1),
                purpose: demand.purpose,
                content: demand.content,
                physicalSize: size,
                mappedSize: size,
                uvTransform: .identity,
                sampling: .linearClamp
            ),
            contentGeneration: 1
        )
    }

    // MARK: - Generation

    private static func makeTexture(
        name: String,
        device: MTLDevice
    ) -> MTLTexture? {
        let side = Self.side
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .r8Unorm,
            width: side,
            height: side,
            mipmapped: true
        )
        descriptor.usage = [.shaderRead]
        // replace(region:) requires CPU-visible storage; private textures
        // reject the upload (AGX driver crash observed 2026-09-26).
        descriptor.storageMode = .managed
        guard let texture = device.makeTexture(descriptor: descriptor),
            let commandQueue = device.makeCommandQueue(),
            let commandBuffer = commandQueue.makeCommandBuffer()
        else { return nil }

        var pixels = [UInt8](repeating: 0, count: side * side)
        let seed = Self.seed(for: name)
        if name.contains("clouds") {
            fillCloudNoise(&pixels, side: side, seed: seed)
        } else if name.contains("perlin") {
            fillCloudNoise(&pixels, side: side, seed: seed, octaves: 5)
        } else if name.contains("voronoi") {
            fillVoronoi(&pixels, side: side, seed: seed)
        } else {
            fillUniformNoise(&pixels, seed: seed)
        }

        pixels.withUnsafeBytes { raw in
            texture.replace(
                region: MTLRegion(
                    origin: .init(x: 0, y: 0, z: 0),
                    size: .init(width: side, height: side, depth: 1)
                ),
                mipmapLevel: 0,
                withBytes: raw.baseAddress!,
                bytesPerRow: side
            )
        }
        if let blit = commandBuffer.makeBlitCommandEncoder() {
            blit.generateMipmaps(for: texture)
            blit.endEncoding()
            commandBuffer.commit()
            commandBuffer.waitUntilCompleted()
        }
        return texture
    }

    private static func seed(for name: String) -> UInt64 {
        var seed: UInt64 = 0x9E37_79B9_7F4A_7C15
        for byte in name.utf8 {
            seed = (seed ^ UInt64(byte)) &* 0xBF58_476D_1CE4_E5B9
            seed = (seed << 7) | (seed >> 57)
        }
        return seed
    }

    private static func next(_ seed: inout UInt64) -> Float {
        seed = seed &* 6364136223846793005 &+ 1442695040888963407
        let bits = UInt32(truncatingIfNeeded: seed >> 33)
        return Float(bits) / Float(UInt32.max)
    }

    /// Tileable multi-octave value noise. Stock noise must wrap at the
    /// edges: authored shaders scroll these textures indefinitely
    /// (`coords + time * speed`), and a non-wrapping texture would show a
    /// visible seam band crossing the layer every cycle.
    private static func fillCloudNoise(
        _ pixels: inout [UInt8],
        side: Int,
        seed: UInt64,
        octaves: Int = 4
    ) {
        var state = seed
        var grids: [[Float]] = []
        for octave in 0..<octaves {
            let resolution = 1 << (octave + 2) // 4, 8, 16, 32
            var grid = [Float](repeating: 0, count: resolution * resolution)
            for index in grid.indices {
                grid[index] = next(&state)
            }
            grids.append(grid)
        }
        func smooth(_ value: Float) -> Float {
            value * value * (3 - 2 * value)
        }
        func sampleGrid(
            _ grid: [Float],
            resolution: Int,
            x: Float,
            y: Float
        ) -> Float {
            let fx = x * Float(resolution)
            let fy = y * Float(resolution)
            let x0 = Int(fx) % resolution
            let y0 = Int(fy) % resolution
            let x1 = (x0 + 1) % resolution
            let y1 = (y0 + 1) % resolution
            let tx = smooth(fx - fx.rounded(.down))
            let ty = smooth(fy - fy.rounded(.down))
            let top = grid[y0 * resolution + x0]
                * (1 - tx) + grid[y0 * resolution + x1] * tx
            let bottom = grid[y1 * resolution + x0]
                * (1 - tx) + grid[y1 * resolution + x1] * tx
            return top * (1 - ty) + bottom * ty
        }
        for y in 0..<side {
            for x in 0..<side {
                let nx = Float(x) / Float(side)
                let ny = Float(y) / Float(side)
                var value = 0.0
                var weight = 0.0
                var amplitude = 1.0
                for grid in grids {
                    value += Double(
                        sampleGrid(
                            grid, resolution: Int(Double(grid.count).squareRoot()), x: nx, y: ny
                        )
                    ) * amplitude
                    weight += amplitude
                    amplitude *= 0.5
                }
                value /= weight
                pixels[y * side + x] = UInt8(
                    min(255, max(0, value * 255))
                )
            }
        }
    }

    private static func fillVoronoi(
        _ pixels: inout [UInt8],
        side: Int,
        seed: UInt64
    ) {
        var state = seed
        let pointCount = 24
        var points: [(Float, Float)] = []
        for _ in 0..<pointCount {
            points.append((next(&state), next(&state)))
        }
        for y in 0..<side {
            for x in 0..<side {
                let nx = Float(x) / Float(side)
                let ny = Float(y) / Float(side)
                var best = Float.greatestFiniteMagnitude
                var second = Float.greatestFiniteMagnitude
                for (px, py) in points {
                    // wrap distance for tileability
                    for dx in [-1.0, 0.0, 1.0] {
                        for dy in [-1.0, 0.0, 1.0] {
                            let dxp = nx - (px + Float(dx))
                            let dyp = ny - (py + Float(dy))
                            let distance = (dxp * dxp + dyp * dyp).squareRoot()
                            if distance < best {
                                second = best
                                best = distance
                            } else if distance < second {
                                second = distance
                            }
                        }
                    }
                }
                let edge = min(1, max(0, (second - best) * 4))
                pixels[y * side + x] = UInt8(edge * 255)
            }
        }
    }

    private static func fillUniformNoise(
        _ pixels: inout [UInt8],
        seed: UInt64
    ) {
        var state = seed
        let side = Self.side
        for index in pixels.indices {
            pixels[index] = UInt8(next(&state) * 255)
        }
        _ = side
    }
}
