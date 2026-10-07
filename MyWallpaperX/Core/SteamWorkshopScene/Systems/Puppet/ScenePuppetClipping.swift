import Metal
import simd

/// Geometry-only auxiliaries. Color stays in the ordinary image/compositor
/// pipeline; allocation is delegated to the view's existing target pool.
final class ScenePuppetClipping {
    struct Allocation {
        let texture: MTLTexture
        let release: () -> Void
    }
    typealias Allocator = (Int, Int, Int, MTLCommandBuffer) -> Allocation?
    static func makePipeline(device: MTLDevice) -> MTLRenderPipelineState? {
        guard let library = try? device.makeLibrary(source: shaderSource, options: nil),
              let vertex = library.makeFunction(name: "puppetMaskVertex"),
              let fragment = library.makeFunction(name: "puppetMaskFragment") else { return nil }
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertex
        descriptor.fragmentFunction = fragment
        let color = descriptor.colorAttachments[0]!
        color.pixelFormat = .r8Unorm
        color.isBlendingEnabled = true
        // Opaque overlapping providers form a coverage union: the fixed
        // official two-source / gray-mask control excludes over/add buildup.
        color.rgbBlendOperation = .max
        color.alphaBlendOperation = .max
        color.sourceRGBBlendFactor = .one
        color.destinationRGBBlendFactor = .one
        color.sourceAlphaBlendFactor = .one
        color.destinationAlphaBlendFactor = .one
        return try? device.makeRenderPipelineState(descriptor: descriptor)
    }

    private static let shaderSource = """
    #include <metal_stdlib>
    using namespace metal;
    struct Vertex { float2 position; float2 uv; float coverage; };
    struct Varyings { float4 position [[position]]; float2 uv; float2 local; };
    vertex Varyings puppetMaskVertex(uint id [[vertex_id]],
        constant Vertex *vertices [[buffer(0)]], constant float4 &roi [[buffer(1)]]) {
        Varyings out;
        out.local = vertices[id].position;
        out.uv = vertices[id].uv;
        float2 uv = out.local * roi.zw + roi.xy;
        out.position = float4(uv.x * 2 - 1, 1 - uv.y * 2, 0, 1);
        return out;
    }
    fragment float puppetMaskFragment(Varyings in [[stage_in]],
        texture2d<float> paint [[texture(0)]], texture2d<float> parent [[texture(1)]],
        constant float4 &parentROI [[buffer(0)]]) {
        constexpr sampler linearZero(filter::linear, address::clamp_to_zero);
        float coverage = paint.sample(linearZero, in.uv).r;
        if (parentROI.z != 0) {
            coverage *= parent.sample(linearZero, in.local * parentROI.zw + parentROI.xy).r;
        }
        return coverage;
    }
    """

    private struct Mask {
        let texture: MTLTexture
        let transform: SIMD4<Float>
    }
    private let mesh: SceneMdlPuppetMesh
    private let pipeline: MTLRenderPipelineState?
    private let paintTextures: [Int: MTLTexture]
    private let allocate: Allocator
    private let recordByTarget: [Int: Int]
    private let preparationOrder: [Int]
    private let sourceParts: [[Int]]
    private var prepared: [Int: Mask] = [:]
    private var opaqueSources: [Int: Bool] = [:]

    init(mesh: SceneMdlPuppetMesh, pipeline: MTLRenderPipelineState?,
         paintTextures: [Int: MTLTexture], allocate: @escaping Allocator) {
        self.mesh = mesh
        self.pipeline = pipeline
        self.paintTextures = paintTextures
        self.allocate = allocate
        sourceParts = mesh.clipRecords.map { record in
            var seen: Set<Int> = []
            return record.sourcePartOrdinals.filter {
                $0 != record.targetPartOrdinal && mesh.drawParts[$0].indexCount > 0
                    && seen.insert($0).inserted
            }
        }
        // The reader admits one clip record per target. Self is a source
        // candidate in real exports, but the official renderer excludes it.
        let byTarget = Dictionary(uniqueKeysWithValues:
            mesh.clipRecords.enumerated().map { ($0.element.targetPartOrdinal, $0.offset) })
        recordByTarget = byTarget
        var indegrees = Array(repeating: 0, count: mesh.clipRecords.count)
        var consumers: [Int: [Int]] = [:]
        for index in mesh.clipRecords.indices {
            let dependencies = Set(sourceParts[index].compactMap { byTarget[$0] })
            indegrees[index] = dependencies.count
            for dependency in dependencies { consumers[dependency, default: []].append(index) }
        }
        // Iterative topological traversal bounds stack use by a constant even
        // for deeply nested authored inputs. Cycles and their dependents stay
        // unprepared; unrelated components still execute.
        var order = indegrees.indices.filter { indegrees[$0] == 0 }
        var cursor = 0
        while cursor < order.count {
            let producer = order[cursor]; cursor += 1
            for consumer in consumers[producer, default: []] {
                indegrees[consumer] -= 1
                if indegrees[consumer] == 0 { order.append(consumer) }
            }
        }
        preparationOrder = order
    }

    /// Always prepares against this consumer and submission. No cross-frame
    /// readiness memo can survive a cancelled or failed command buffer.
    func prepare(commandBuffer: MTLCommandBuffer, extent: SIMD2<Int>, mvp: simd_float4x4,
                 retainAuxiliary: SceneGeometryProduct.AuxiliaryRetainer,
                 vertices: [SceneQuadVertex], vertexBuffer: MTLBuffer, indexBuffer: MTLBuffer) {
        prepared.removeAll(keepingCapacity: true)
        opaqueSources.removeAll(keepingCapacity: true)
        guard let pipeline else { return }
        for index in preparationOrder {
            let record = mesh.clipRecords[index]
            let sources = sourceParts[index]
            // Reject a missing dependency before allocating any target, so
            // unavailable nested components cannot consume healthy parts' budget.
            guard let paint = paintTextures[index],
                  sources.allSatisfy({ recordByTarget[$0] == nil || prepared[$0] != nil }),
                  sources.allSatisfy({ ordinal in
                      if let opaque = opaqueSources[ordinal] { return opaque }
                      let part = mesh.drawParts[ordinal]
                      let opaque = (part.indexOffset ..< part.indexOffset + part.indexCount).allSatisfy {
                          abs(vertices[Int(mesh.indices[$0])].vertexCoverage - 1) <= 0.0001
                      }
                      opaqueSources[ordinal] = opaque
                      return opaque
                  }),
                  let roi = region(part: mesh.drawParts[record.targetPartOrdinal],
                                   vertices: vertices, extent: extent, mvp: mvp),
                  let allocation = allocate(index, roi.width, roi.height, commandBuffer) else { continue }
            let target = allocation.texture
            let pass = MTLRenderPassDescriptor()
            pass.colorAttachments[0].texture = target
            pass.colorAttachments[0].loadAction = .clear
            pass.colorAttachments[0].storeAction = .store
            pass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0)
            guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else {
                allocation.release()
                continue
            }
            retainAuxiliary(allocation.release)
            encoder.label = "Puppet part clipping \(record.targetPartOrdinal)"
            encoder.setRenderPipelineState(pipeline)
            encoder.setCullMode(.none)
            encoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
            var transform = roi.transform
            encoder.setVertexBytes(&transform, length: MemoryLayout<SIMD4<Float>>.stride, index: 1)
            encoder.setFragmentTexture(paint, index: 0)
            for ordinal in sources {
                let nested = prepared[ordinal]
                var nestedTransform = nested?.transform ?? .zero
                encoder.setFragmentTexture(nested?.texture ?? paint, index: 1)
                encoder.setFragmentBytes(&nestedTransform,
                    length: MemoryLayout<SIMD4<Float>>.stride, index: 0)
                let part = mesh.drawParts[ordinal]
                encoder.drawIndexedPrimitives(type: .triangle, indexCount: part.indexCount,
                    indexType: .uint16, indexBuffer: indexBuffer,
                    indexBufferOffset: part.indexOffset * MemoryLayout<UInt16>.stride)
            }
            encoder.endEncoding()
            prepared[record.targetPartOrdinal] = Mask(texture: target, transform: roi.transform)
        }
    }

    func draw(encoder: MTLRenderCommandEncoder, sourceTexture: MTLTexture, indexBuffer: MTLBuffer) {
        for part in mesh.drawParts where part.indexCount > 0 {
            let mask = prepared[part.ordinal]
            // Ordinary auxiliary failure hides only the dependent target.
            if recordByTarget[part.ordinal] != nil && mask == nil { continue }
            SceneImageLayerPipeline.bindClipMask(encoder: encoder,
                texture: mask?.texture ?? sourceTexture, transform: mask?.transform ?? .zero)
            encoder.drawIndexedPrimitives(type: .triangle, indexCount: part.indexCount,
                indexType: .uint16, indexBuffer: indexBuffer,
                indexBufferOffset: part.indexOffset * MemoryLayout<UInt16>.stride)
            ScenePerformanceCounterHub.shared.recordDraw(usesGeometry: true)
        }
        SceneImageLayerPipeline.bindClipMask(encoder: encoder, texture: sourceTexture)
    }

    private struct Region {
        let width: Int
        let height: Int
        /// UV = local position * zw + xy; model Y is up, texture Y down.
        let transform: SIMD4<Float>
    }

    private func region(part: SceneMdlPuppetMesh.DrawPart, vertices: [SceneQuadVertex],
                        extent: SIMD2<Int>, mvp: simd_float4x4) -> Region? {
        var low = SIMD2<Float>(repeating: .greatestFiniteMagnitude)
        var high = SIMD2<Float>(repeating: -.greatestFiniteMagnitude)
        for i in part.indexOffset ..< part.indexOffset + part.indexCount {
            let position = vertices[Int(mesh.indices[i])].position
            low = simd_min(low, position); high = simd_max(high, position)
        }
        let size = high - low
        guard size.x.isFinite, size.y.isFinite, size.x > 0, size.y > 0,
              extent.x > 0, extent.y > 0 else { return nil }
        // Conservative projected derivatives over all corners of this planar
        // ROI. A perspective horizon crossing is unavailable, never clamped.
        let corners = [low, SIMD2(low.x, high.y), SIMD2(high.x, low.y), high]
        var numerator = SIMD2<Float>.zero
        var minimumW = Float.greatestFiniteMagnitude
        for p in corners {
            let clip = mvp * SIMD4(p.x, p.y, 0, 1)
            guard clip.w.isFinite, clip.w > .ulpOfOne else { return nil }
            minimumW = min(minimumW, clip.w)
            let dx = (SIMD2(mvp.columns.0.x, mvp.columns.0.y) * clip.w
                      - SIMD2(clip.x, clip.y) * mvp.columns.0.w)
            let dy = (SIMD2(mvp.columns.1.x, mvp.columns.1.y) * clip.w
                      - SIMD2(clip.x, clip.y) * mvp.columns.1.w)
            let pixels = SIMD2(Float(extent.x), Float(extent.y)) * 0.5
            numerator = simd_max(numerator, SIMD2(simd_length(dx * pixels), simd_length(dy * pixels)))
        }
        // The numerator is affine over the planar ROI. Its corner maximum
        // divided by the minimum positive w squared bounds interior extrema.
        let density = numerator / (minimumW * minimumW)
        let projectedPixels = size * density
        let pixels = SIMD2(projectedPixels.x.rounded(.up), projectedPixels.y.rounded(.up))
        guard pixels.x.isFinite, pixels.y.isFinite,
              pixels.x >= 1, pixels.y >= 1,
              pixels.x < Float(Int32.max - 2), pixels.y < Float(Int32.max - 2) else { return nil }
        // One transparent border texel keeps linear filtering local without
        // stretching boundary coverage over outside geometry.
        let paddedLow = low - size / pixels
        let paddedSize = size * (pixels + 2) / pixels
        return Region(width: Int(pixels.x) + 2, height: Int(pixels.y) + 2,
            transform: SIMD4(-paddedLow.x / paddedSize.x,
                (paddedLow.y + paddedSize.y) / paddedSize.y,
                1 / paddedSize.x, -1 / paddedSize.y))
    }
}
