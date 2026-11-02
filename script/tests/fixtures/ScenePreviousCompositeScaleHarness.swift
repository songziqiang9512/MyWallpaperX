// Appended to the existing self-authored coordinate/Program harness. This
// fixture is a color ruler, not a Blur kernel or a stock shader reconstruction.
private func scaleRulerFixture(_ variant: Int) -> (CoordinateFixture, String) {
    let parameter = variant == 0 ? "authoredAmount" : "independentDistance"
    let varying = variant == 0 ? "rulerUV" : "renamedCoordinate"
    let slot = variant == 0 ? 0 : 3
    let coordinate = variant == 0
        ? "(\(parameter) + vec2(0.5)) / 128.0"
        : "vec2(((\(parameter).x + 0.0) + 0.5) / 128.0, (\(parameter).y * 1.0 + 0.5) / 128.0)"
    return (.init(name: variant == 0 ? "own/ruler" : "moved/equivalent-resource",
        vertex: """
        attribute vec3 a_Position;
        attribute vec2 a_TexCoord;
        uniform vec2 \(parameter);
        varying vec2 \(varying);
        void main() {
            \(varying) = \(coordinate);
            gl_Position = vec4(a_Position, 1.0);
        }
        """, fragment: """
        varying vec2 \(varying);
        uniform sampler2D g_Texture\(slot);
        void main() { gl_FragColor = texSample2D(g_Texture\(slot), \(varying)); }
        """, slot: slot), parameter)
}

private func rulerTexture(_ device: MTLDevice, generation: UInt64) -> MTLTexture {
    let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm,
        width: 128, height: 128, mipmapped: false)
    descriptor.storageMode = .shared; descriptor.usage = [.shaderRead]
    let value = device.makeTexture(descriptor: descriptor)!
    var bytes: [UInt8] = []
    for row in 0 ..< 128 {
        for column in 0 ..< 128 {
            bytes += [UInt8(column + (generation == 2 ? 9 : 0)), UInt8(row), 33, 255]
        }
    }
    bytes.withUnsafeBytes { value.replace(region: MTLRegionMake2D(0, 0, 128, 128),
        mipmapLevel: 0, withBytes: $0.baseAddress!, bytesPerRow: 512) }
    return value
}

private func rulerSlot(_ fixture: CoordinateFixture, device: MTLDevice,
                       generation: UInt64, content: SceneTextureContent = .color(.resolved(.opaque))) -> Program.TextureSlot {
    let effect = Graph.EffectKey(layerID: 731, effectIndex: 0, descriptorID: "independent-ruler")
    let identity = Graph.TextureIdentity(kind: .framebuffer, layerID: 731,
        effect: effect, name: fixture.name)
    let candidate = SceneTextureCandidate(texture: rulerTexture(device, generation: generation),
        identity: .provider(.graph(allocationGeneration: generation, physicalToken: fixture.name)),
        generation: .provider(contentGeneration: generation), purpose: .premultipliedColor,
        content: content, physicalSize: CGSize(width: 128, height: 128),
        mappedSize: CGSize(width: 128, height: 128), uvTransform: .identity, sampling: .init(texFlags: 3))
    return .init(index: fixture.slot, reference: .graph(identity), registryIdentity: .graph(identity),
        diagnosticSelectionProvenance: .authored(.explicitBinding), expectedPurpose: .premultipliedColor,
        resource: .init(publication: .init(requestIdentity: .graph(identity), candidate: candidate,
            contentGeneration: generation), resourceGeneration: generation))
}

private func rulerAssembly(_ fixture: CoordinateFixture, parameter: String,
                           frontend: SceneAuthoredShaderProgram, selected: Program.TextureSlot?,
                           value: [Double], generation: UInt64) -> (frame: Program.FrameAssemblyInput, prepared: Program.PreparedAssembly)? {
    var slots = Array<Program.TextureSlot?>(repeating: nil, count: 8)
    slots[fixture.slot] = selected
    var uniforms: [Program.ResolvedUniform] = []
    var bindings: [SceneResolvedMaterialPreparedUniformBinding] = []
    for field in frontend.uniformLayout.fields {
        let encoded: Data?
        let source: SceneResolvedMaterialPreparedUniformBinding.Source
        if field.authoredName == parameter {
            encoded = SceneResolvedMaterialUniformEncoder.encodeComponents(value, as: field.type)
            guard let encoded else { return nil }
            source = .staticValue(encoded)
        } else if let host = SceneResolvedMaterialUniformEncoder.hostUniform(field, slots: slots) {
            encoded = SceneResolvedMaterialUniformEncoder.encodeHost(host, type: field.type,
                inputs: inputs(generation: generation), slots: slots)
            source = .host(host)
        } else { return nil }
        guard let encoded else { return nil }
        bindings.append(.init(field: field, source: source))
        uniforms.append(.init(encodedValue: encoded))
    }
    guard let assembly = try? Program.PreparedAssembly(
        preparedShader: prepared(fixture), frontend: frontend,
        renderState: SceneMaterialRenderState.compile(blending: "normal", depthTest: "disabled",
            depthWrite: "disabled", cullMode: "nocull", alphaWriting: nil)!,
        runtimeLoopBounds: .none, preparedUniformBindings: bindings,
        conditionalGeneratedRGBInputContract: nil, associatedOverOverlaySlot: nil,
        premultipliedColorInputSlots: []
    ) else { return nil }
    return (.init(textureSlots: slots, resolvedUniforms: uniforms,
        graphRole: .init(effectInput: .layerSource, effectOutput: .effectOutput,
            nodeTarget: .framebuffer, bindings: [.init(slot: fixture.slot, texture: .framebuffer)]),
        outputStorage: .color), assembly)
}

private func rulerProgram(
    _ assembly: (frame: Program.FrameAssemblyInput, prepared: Program.PreparedAssembly)
) -> Program? {
    Program.assemblePrepared(assembly.frame, prepared: assembly.prepared,
        routeDecision: .init(profile: "ordinary-shader", state: "generic-only", fallbackOwner: "bounded-frontend"))
}

private func renderRuler(_ program: Program, device: MTLDevice,
                         queue: MTLCommandQueue, encoder: SceneResolvedMaterialPassEncoder) throws -> [Float] {
    let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba16Float,
        width: 2, height: 2, mipmapped: false)
    descriptor.storageMode = .shared; descriptor.usage = [.renderTarget, .shaderRead]
    let output = device.makeTexture(descriptor: descriptor)!
    prepareMaterialPipeline(program, encoder: encoder, target: output)
    let pass = try encoder.prepareResult(program: program, target: output, attachmentStorage: .color).get()
    let command = queue.makeCommandBuffer()!
    guard encoder.encode(pass, commandBuffer: command) else { fatalError("ruler encode failed") }
    command.commit(); command.waitUntilCompleted()
    guard command.status == .completed, command.error == nil else { fatalError("ruler GPU failed") }
    var pixels = [Float16](repeating: 0, count: 16)
    pixels.withUnsafeMutableBytes { output.getBytes($0.baseAddress!, bytesPerRow: 16,
        from: MTLRegionMake2D(0, 0, 2, 2), mipmapLevel: 0) }
    return pixels.map(Float.init)
}

@main private enum ScaleRulerMain {
    static func main() throws {
        let bundle = Bundle(path: CommandLine.arguments[1])!
        let cache = URL(fileURLWithPath: CommandLine.arguments[2])
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue(),
              let encoder = SceneResolvedMaterialPassEncoder(device: device) else { fatalError("Metal unavailable") }
        var observations: [[String: Any]] = []
        var negatives: [String: Bool] = [:]
        for variant in 0 ... 1 {
            let (fixture, parameter) = scaleRulerFixture(variant)
            let canonical = SceneAuthoredShaderBackendCanonicalizer.canonicalize(
                vertex: fixture.vertex, fragment: fixture.fragment, boundTextureSlots: [fixture.slot])
            let key = SceneResolvedMaterialGenericShaderRequest.key(vertexSource: canonical.vertex,
                fragmentSource: canonical.fragment, outputSemantics: .color,
                expectedColorTransfer: nil, premultipliedColorInputSlots: [])
            let path: URL
            switch SceneGenericShaderCompiler.compile(requestKey: key, vertexSource: canonical.vertex,
                fragmentSource: canonical.fragment, boundTextureSlots: [fixture.slot], cacheRoot: cache, bundle: bundle) {
            case let .success(value): path = value
            case let .failure(failure): throw NSError(domain: "self-ruler-compiler", code: 1,
                userInfo: [NSLocalizedDescriptionKey: String(describing: failure)])
            }
            let artifact = try JSONDecoder().decode(SceneGenericShaderProgramArtifact.self, from: Data(contentsOf: path))
            guard let frontend = artifact.makeProgram(expectedKey: key,
                expectedColorTransfer: .passthrough(textureSlot: fixture.slot), expectedFragmentOutputChannelUse: .redDefined)
            else { fatalError("ruler artifact rejected") }
            for value in [[12.0, 12.0], [32.0, 32.0], [73.0, 73.0], [12.0, 32.0]] {
                for generation: UInt64 in [1, 2] {
                    let slot = rulerSlot(fixture, device: device, generation: generation)
                    let assembly = rulerAssembly(fixture, parameter: parameter, frontend: frontend,
                        selected: slot, value: value, generation: generation)!
                    guard let program = rulerProgram(assembly) else { fatalError("ruler Program rejected") }
                    let index = assembly.prepared.preparedUniformBindings.firstIndex { $0.field.authoredName == parameter }!
                    let bytes = assembly.frame.resolvedUniforms[index].encodedValue
                    let encodedValues: [Float] = [0, 4].map { offset in bytes.withUnsafeBytes {
                        $0.loadUnaligned(fromByteOffset: offset, as: Float.self) } }
                    observations.append(["variant": variant, "resource": fixture.name, "parameter": parameter,
                        "slot": fixture.slot, "scale": value, "generation": generation, "encoded": encodedValues,
                        "backend": frontend.backend.rawValue, "pixels": try renderRuler(program, device: device,
                            queue: queue, encoder: encoder)])
                }
            }
            let selected = rulerSlot(fixture, device: device, generation: 1)
            for (name, value) in [("overflow", [1e40, 1e40]), ("nonfinite", [Double.nan, Double.infinity]),
                                  ("wrongShape", [12.0, 12.0, 12.0])] {
                negatives["\(variant)-\(name)"] = rulerAssembly(fixture, parameter: parameter,
                    frontend: frontend, selected: selected, value: value, generation: 1) == nil
            }
            let missing = rulerAssembly(fixture, parameter: parameter, frontend: frontend,
                selected: nil, value: [12, 12], generation: 1)
            negatives["\(variant)-missingRequiredSource"] = missing.flatMap { rulerProgram($0) } == nil
            let unknown = rulerSlot(fixture, device: device, generation: 1, content: .color(.unresolved))
            let unproven = rulerAssembly(fixture, parameter: parameter, frontend: frontend,
                selected: unknown, value: [12, 12], generation: 1)
            negatives["\(variant)-unknownColor"] = unproven.flatMap { rulerProgram($0) } == nil
        }
        print(String(decoding: try JSONSerialization.data(withJSONObject: ["observations": observations,
            "negatives": negatives], options: [.sortedKeys]), as: UTF8.self))
    }
}
