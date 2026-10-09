"""Source upload color contract for the existing texture-candidate GPU harness.

Kept separate from identity/UV admission cases; uses their existing producers
and readback helpers, so the test still compiles and runs one frozen harness.
"""

HARNESS_EXTENSION = r'''
extension Harness {
    static func sourceContinuityProbe(
        directory: URL, pngURL: URL, loader: SceneTextureLoader,
        spriteTextureLoader: SceneMultiImageSpriteTextureLoader, device: MTLDevice
    ) throws -> [String: Any] {
        let library = try device.makeLibrary(source: """
            #include <metal_stdlib>
            using namespace metal;
            kernel void source_sample(texture2d<float> source [[texture(0)]],
                texture2d<float, access::write> target [[texture(1)]],
                constant float4& value [[buffer(0)]]) {
                constexpr sampler nearest(filter::nearest, mip_filter::nearest, address::clamp_to_edge);
                constexpr sampler linear(filter::linear, mip_filter::nearest, address::clamp_to_edge);
                float4 sampled = value.w == 0
                    ? source.sample(nearest, value.xy, level(value.z))
                    : source.sample(linear, value.xy, level(value.z));
                target.write(sampled, uint2(0));
            }
            """, options: nil)
        let pipeline = try device.makeComputePipelineState(
            function: library.makeFunction(name: "source_sample")!
        )
        func sample(_ texture: MTLTexture, uv: SIMD2<Float>, mip: Float = 0,
                    linear: Bool = false) throws -> [Int] {
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: .rgba8Unorm, width: 1, height: 1, mipmapped: false
            )
            descriptor.usage = [.shaderRead, .shaderWrite]
            guard let target = device.makeTexture(descriptor: descriptor),
                  let queue = device.makeCommandQueue(),
                  let command = queue.makeCommandBuffer(),
                  let encoder = command.makeComputeCommandEncoder() else {
                throw HarnessError.loadFailed
            }
            encoder.setComputePipelineState(pipeline)
            encoder.setTexture(texture, index: 0)
            encoder.setTexture(target, index: 1)
            var values = SIMD4<Float>(uv.x, uv.y, mip, linear ? 1 : 0)
            encoder.setBytes(&values, length: MemoryLayout<SIMD4<Float>>.stride, index: 0)
            encoder.dispatchThreads(.init(width: 1, height: 1, depth: 1),
                threadsPerThreadgroup: .init(width: 1, height: 1, depth: 1))
            encoder.endEncoding()
            command.commit()
            command.waitUntilCompleted()
            guard command.status == .completed else { throw HarnessError.loadFailed }
            return try readFirstPixel(texture: target, device: device)
        }
        let png = try baseLoaded(SceneBaseImageTextureLoad.load(
            from: pngURL, usesPuppet: false, loader: loader,
            spriteTextureLoader: spriteTextureLoader, device: device
        ))
        guard let pngCandidate = png.candidate,
              let pngSample = SceneBaseImageTextureCandidateResolver.sample(
                candidate: pngCandidate, sourceTexture: png.texture) else {
            throw HarnessError.loadFailed
        }
        let pngPMA = try candidate(loader.loadCandidate(
            from: pngURL, purpose: .premultipliedColor, device: device
        ))
        var result: [String: Any] = [
            "pngStraight": pngSample.representation == .straightAlpha,
            "pngHiddenRGB": try sample(png.texture, uv: SIMD2(0.25, 0.25)),
            "pngLinearEdge": try sample(png.texture, uv: SIMD2(0.5, 0.25), linear: true),
            "pngPMA": try sample(pngPMA.texture, uv: SIMD2(0.25, 0.25)),
            "defaultSamplePMA": SceneBaseImageTextureSample(
                textureFrame: .identity, sampling: .directImageFallback
            ).representation == .premultipliedAlpha,
            "rejectWrongTypedPairs": [
                copy(pngCandidate, purpose: .premultipliedColor),
                copy(pngCandidate, content: .color(.resolved(.premultipliedAlpha))),
                copy(pngCandidate, content: .color(.resolved(.opaque))),
                copy(pngCandidate, content: .color(.resolved(.independentAlphaSignal))),
                copy(pngCandidate, content: .color(.unresolved)),
                copy(pngCandidate, content: .data),
                copy(pngCandidate, isSpriteSheet: true),
            ].allSatisfy {
                SceneBaseImageTextureCandidateResolver.sample(
                    candidate: $0, sourceTexture: png.texture) == nil
            },
        ]
        let materialCandidate = SceneTextureCandidate(texture: png.texture,
            identity: .provider(.materialSource(layerID: 8, frameEpoch: 7, allocationGeneration: 2)),
            generation: .provider(contentGeneration: 7), purpose: pngCandidate.purpose,
            content: pngCandidate.content, physicalSize: pngCandidate.physicalSize,
            mappedSize: pngCandidate.mappedSize, uvTransform: pngCandidate.uvTransform,
            sampling: pngCandidate.sampling)
        let materialSample = SceneBaseImageTextureCandidateResolver.sample(
            candidate: materialCandidate, sourceTexture: png.texture)!
        let styledValues = SceneImageLayerUniformValues(time: 9, alpha: 0.5,
            cursorUV: SIMD2(0.2, 0.3), tint: SIMD3(0.5, 0.25, 0.75))
        func sourceUniforms(_ source: SceneBaseImageTextureSample) -> SceneLayerFragmentUniforms {
            SceneImageLayerCompositor().sourceFragmentUniforms(values: styledValues,
                layer: .init(contentKind: "image", brightness: 2), sourceSample: source,
                routesOffscreen: true, dependencyBlendMode: nil,
                sourceMaterialAlpha: 0.5, sourceMaterialColor: SIMD3(0.4, 0.8, 0.6))
        }
        let materialUniforms = sourceUniforms(materialSample)
        var replacedUniforms = sourceUniforms(pngSample)
        let rawAlpha = replacedUniforms.alpha
        replacedUniforms.consumeCompletedMaterialSource(materialCandidate.identity)
        result["completedMaterialStyle"] = materialUniforms.alpha == 1
            && materialUniforms.tint == SIMD4(repeating: 1)
            && materialUniforms.time == 9 && materialUniforms.cursorUV == styledValues.cursorUV
            && materialUniforms.textureFrame0 == pngSample.textureFrame.uniform0
            && materialUniforms.sourceSampling.y == 1
            && rawAlpha == 0.25 && replacedUniforms.alpha == materialUniforms.alpha
            && replacedUniforms.tint == materialUniforms.tint
        for (name, width, height, native) in [
            ("decodedBC3", UInt32(8), UInt32(4), false),
            // Above the existing 4096² CPU decode budget, with a compact
            // authored payload. No full decoded source copy is required.
            ("nativeBC3", UInt32(8192), UInt32(2052), true),
        ] {
            let url = directory.appendingPathComponent("\(name).tex")
            try hiddenColorBC3Tex(width: width, height: height).write(to: url)
            let ordinary = try baseLoaded(SceneBaseImageTextureLoad.load(
                from: url, usesPuppet: false, loader: loader,
                spriteTextureLoader: spriteTextureLoader, device: device
            ))
            let puppet = try baseLoaded(SceneBaseImageTextureLoad.load(
                from: url, usesPuppet: true, loader: loader,
                spriteTextureLoader: spriteTextureLoader, device: device
            ))
            guard let candidate = ordinary.candidate,
                  let boundary = SceneBaseImageTextureCandidateResolver.sample(
                    candidate: candidate, sourceTexture: ordinary.texture) else {
                throw HarnessError.loadFailed
            }
            let mappedUV = boundary.textureFrame.xAxis * 0.9
                + boundary.textureFrame.yAxis * 0.5
            result[name] = [
                "straightCandidate": boundary.representation == .straightAlpha
                    && candidate.purpose == .straightAlbedo && !candidate.isSpriteSheet
                    && ordinary.baseTextureSampling == nil,
                "format": ordinary.texture.pixelFormat == (native ? .bc3_rgba : .rgba8Unorm),
                "physicalAndMapped": candidate.physicalSize
                    == CGSize(width: Int(width), height: Int(height))
                    && candidate.mappedSize == CGSize(width: Int(width / 2), height: Int(height))
                    && boundary.textureFrame.xAxis == SIMD2(0.5, 0)
                    && boundary.textureFrame.yAxis == SIMD2(0, 1)
                    && ordinary.texture.mipmapLevelCount == 2,
                "puppetUsesSameCandidate": puppet.texture === ordinary.texture
                    && puppet.candidate?.content == candidate.content
                    && puppet.candidate?.uvTransform.xAxis == candidate.uvTransform.xAxis
                    && puppet.animation == nil && puppet.baseTextureSampling == nil,
                "mappedPixel": try sample(ordinary.texture, uv: mappedUV),
                "paddingPixel": try sample(ordinary.texture, uv: SIMD2(0.9, 0.5)),
                "authoredMip": try sample(ordinary.texture, uv: SIMD2(0.1, 0.5), mip: 1),
            ] as [String: Any]
        }
        return result
    }

    static func hiddenColorBC3Tex(width: UInt32, height: UInt32) -> Data {
        let red = Data([0, 0, 0, 0, 0, 0, 0, 0, 0, 0xF8, 0, 0, 0, 0, 0, 0])
        let blue = Data([255, 255, 0, 0, 0, 0, 0, 0, 0x1F, 0, 0, 0, 0, 0, 0, 0])
        let green = Data([128, 128, 0, 0, 0, 0, 0, 0, 0xE0, 0x07, 0, 0, 0, 0, 0, 0])
        var data = Data("TEXV0005\0TEXI0001\0".utf8)
        for value in [UInt32(4), 3, width, height, width / 2, height, 0] {
            append(value, to: &data)
        }
        data.append(Data("TEXB0002\0".utf8))
        append(1, to: &data)
        append(2, to: &data)
        for level in 0..<2 {
            let w = max(1, width >> level), h = max(1, height >> level)
            let columns = Int((w + 3) / 4), rows = Int((h + 3) / 4)
            var row = Data()
            for column in 0..<columns {
                row.append(level == 1 ? green : (column < columns / 2 ? red : blue))
            }
            var payload = Data(capacity: row.count * rows)
            for _ in 0..<rows { payload.append(row) }
            for value in [w, h, 0, 0, UInt32(payload.count)] { append(value, to: &data) }
            data.append(payload)
        }
        return data
    }

}
'''


def assert_source_color_upload(self, continuity):
    linear_edge = continuity.pop("pngLinearEdge")
    for actual, expected in zip(linear_edge, [216, 58, 100, 32], strict=True):
        self.assertLessEqual(abs(actual - expected), 1, linear_edge)
    bc3_expected = {
        "straightCandidate": True,
        "format": True,
        "physicalAndMapped": True,
        "puppetUsesSameCandidate": True,
        "mappedPixel": [255, 0, 0, 0],
        "paddingPixel": [0, 0, 255, 255],
        "authoredMip": [0, 255, 0, 128],
    }
    self.assertEqual(continuity, {
        "pngStraight": True,
        "pngHiddenRGB": [231, 17, 149, 0],
        "pngPMA": [0, 0, 0, 0],
        "defaultSamplePMA": True,
        "rejectWrongTypedPairs": True,
        "completedMaterialStyle": True,
        "decodedBC3": bc3_expected,
        "nativeBC3": bc3_expected,
    })
