// Reuses the existing real launch producer and GPU renderer. No compiled
// variant, resolver, color-boundary set or output pixel is forged by the probe.
extension BackgroundColorABIHarness {
    static func namedProviderColorBoundary(_ name: String, mixed: Bool, regular: Bool = false,
        selfReference: Bool = false, defaultAsset: Bool = false, graphAlias: Bool = false,
        hasEffectContext: Bool = true, conditional: Bool = false) throws -> [String: Any] {
        let fallback = defaultAsset ? SceneVFSAssetPath("own/named-default")! : nil
        var metadata: [String: String] = regular ? [:] : ["mode": "rgbmask", "material": "namedInput"]
        if let fallback { metadata["default"] = fallback.value; metadata["material"] = "albedo" }
        if graphAlias { metadata["material"] = "framebuffer" }
        if conditional { metadata["combo"] = "HasExternalAudioBuffer" }
        let annotation = String(data: try JSONSerialization.data(withJSONObject: metadata,
            options: [.sortedKeys]), encoding: .utf8)!
        let fragment = """
        varying vec2 v_TexCoord;
        uniform sampler2D g_Texture0; // {"hidden":true,"material":"framebuffer"}
        uniform sampler2D g_Texture1; // \(annotation)
        void main() {
            vec4 base = texSample2D(g_Texture0, v_TexCoord);
        \(conditional ? "#if HasExternalAudioBuffer" : "")
            vec4 provider = texSample2D(g_Texture1, v_TexCoord);
            gl_FragColor = vec4(mix(base.rgb, provider.rgb, provider.a), 1.0);
        \(conditional ? "#else\ngl_FragColor = vec4(base.rgb, 1.0);\n#endif" : "")
        }
        """
        let shader = contract(fragment)
        let input = Graph.TextureIdentity(kind: .layerSource, layerID: 42, effect: nil, name: nil)
        let named = SceneNamedTextureReference(providerLayerID: selfReference ? 42 : 879, variant: .primary)
        var candidates: [Template.TextureCandidate] = [
            .init(reference: .provider(.namedLayerTarget(named)), provenance: .material)
        ]
        if mixed {
            candidates.append(.init(reference: .provider(.system("$own-preserved-data")), provenance: .userTexture))
        }
        var slots = [Template.TextureSlot?](repeating: nil, count: 8)
        slots[1] = .init(index: 1, candidates: candidates)
        let template = Template.validated(textureSlots: slots, combos: [], uniformDeclarations: [],
            renderState: SceneMaterialRenderState.compile(blending: "normal", depthTest: "disabled",
                depthWrite: "disabled", cullMode: "nocull", alphaWriting: nil)!,
            graphRole: .init(effectInput: .layerSource, effectOutput: .effectOutput, nodeTarget: .effectOutput, bindings: []),
            effectContext: hasEffectContext
                ? .init(key: .init(layerID: 42, effectIndex: 0, descriptorID: name), input: input) : nil,
            compatibilityTarget: .windowsDX11ShaderModel4, shaderContract: shader,
            diagnosticProvenance: .init(nodeIndex: 0, authoredShaderPath: shader.identity,
                contractIdentity: shader.identity, contractCanonicalSHA256: shader.canonicalSHA256,
                textureSources: [], uniformSources: []))!
        let cache = try SceneResolvedMaterialVariantCache.launchValidated(template: template, maximumVariantCount: 16).get()
        let launch = cache.precompileLaunchEnvelope(implicitFramebufferIdentity: input, outputStorage: .color,
            assetStates: fallback.map { [.init(path: $0, purpose: .straightAlbedo):
                SceneAssetTextureLaunchState.ready(.color(.resolved(.straightAlpha)))] } ?? [:])
        let snapshot = cache.launchEnvelopeCapabilitySnapshot()
        let variants = try snapshot.variants.map { variant -> [String: Any] in
            let program = variant.frontendProgram
            var row: [String: Any] = [
                "isRGBMask": variant.activeSamplers[1]?.mode == .rgbMask,
                "profilePMASlots": variant.premultipliedColorInputSlots.sorted(),
                "preservedSlots": variant.preservedChannelsProviderInputSlots.sorted(),
                "colorSlots": program.colorBoundary?.colorInputSlots.sorted() ?? [],
                "profile": variant.routeDecision.profile,
                "backend": program.backend.rawValue,
                "activeSlots": program.textureBindings.map(\.slot).sorted(),
                "metalSHA256": SceneShaderStableDigest.hash(Data(program.metalSource.utf8))
            ]
            // Ordinary bounded profiles deliberately exclude mixed inputs
            // from their auxiliary PMA set. The typed data selection remains
            // authoritative for this known two-purpose candidate envelope.
            if !regular && variant.preservedChannelsProviderInputSlots.isEmpty {
                row["pmaPixels"] = try render(program, providerSlot: 1,
                    inputMask: (1 << 0) | (1 << 1))
                row["straightPixels"] = try render(program, providerPixel: [0.2, 0.6, 0.4, 0.5],
                    providerSlot: 1, inputMask: 1 << 0)
            } else if !regular && variant.preservedChannelsProviderInputSlots == [1] {
                // Even an association mask cannot turn a typed data slot into
                // color. Literal provider RGB and alpha enter authored math.
                row["dataPixels"] = try render(program, providerSlot: 1,
                    inputMask: (1 << 0) | (1 << 1))
            }
            return row
        }
        var result: [String: Any] = ["launch": String(describing: launch), "ready": snapshot.allEntriesReady,
            "candidateCount": candidates.count, "variants": variants]
        if regular && !selfReference && hasEffectContext && snapshot.allEntriesReady {
            result["selections"] = try regularNamedProviderSelections(template, cache: cache,
                input: input, named: named, fallback: fallback)
        }
        return result
    }

    static func regularNamedProviderSelections(_ template: Template,
        cache: SceneResolvedMaterialVariantCache, input: Graph.TextureIdentity,
        named: SceneNamedTextureReference, fallback: SceneVFSAssetPath? = nil) throws -> [String: Any] {
        let device = MTLCreateSystemDefaultDevice()!
        func texture(_ values: [Float]) -> MTLTexture {
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: .rgba16Float, width: 1, height: 1, mipmapped: false)
            descriptor.storageMode = .shared
            descriptor.usage = [.shaderRead, .renderTarget]
            let result = device.makeTexture(descriptor: descriptor)!
            values.map(Float16.init).withUnsafeBytes {
                result.replace(region: MTLRegionMake2D(0, 0, 1, 1), mipmapLevel: 0,
                    withBytes: $0.baseAddress!, bytesPerRow: 8)
            }
            return result
        }
        let primary = texture([0.25, 0.125, 0.0625, 0.5])
        let candidate = SceneTextureCandidate(texture: primary,
            identity: .provider(.graph(allocationGeneration: 1, physicalToken: "own-primary")),
            generation: .provider(contentGeneration: 1), purpose: .premultipliedColor,
            content: .color(.resolved(.premultipliedAlpha)), physicalSize: .init(width: 1, height: 1),
            mappedSize: .init(width: 1, height: 1), uvTransform: .identity, sampling: .linearClamp)
        let primaryResource = SceneFrameTextureResource(publication: .init(
            requestIdentity: .graph(input), candidate: candidate, contentGeneration: 1),
            resourceGeneration: 1)
        precondition(primaryResource.isCompleteGraphResource)
        let defaultResource: SceneFrameTextureResource? = fallback.map { path in
            let candidate = SceneTextureCandidate(texture: texture([0.75, 0.125, 0.5, 0.25]),
                identity: .builtIn(name: path.value), generation: .immutable(revision: 1),
                purpose: .straightAlbedo, content: .color(.resolved(.straightAlpha)),
                physicalSize: .init(width: 1, height: 1), mappedSize: .init(width: 1, height: 1),
                uvTransform: .identity, sampling: .linearClamp)
            return .init(publication: .init(requestIdentity: .asset(.init(path: path, purpose: .straightAlbedo)),
                candidate: candidate, contentGeneration: 1), resourceGeneration: 1)
        }
        func finalized(_ status: SceneFrameTextureLookupStatus?) throws -> [String: Any] {
            var entries: [SceneFrameTextureIdentity: SceneFrameTextureLookupStatus] = [
                .graph(input): .ready(primaryResource)]
            if let fallback, let defaultResource {
                entries[.asset(.init(path: fallback, purpose: .straightAlbedo))] = .ready(defaultResource)
            }
            var textures = SceneFrameTextureRegistrySnapshot(frameEpoch: 1, frameIndex: 1, entries: entries)
            if case let .ready(resource)? = status {
                // This is the production publication boundary. A stale atom
                // never enters the frame snapshot or reaches finalization.
                guard let published = textures.overlayingNamedLayerTarget(named, resource: resource) else {
                    return ["status": "publication-rejected"]
                }
                textures = published
            } else if let status {
                entries[.namedLayerTarget(named)] = status
                textures = .init(frameEpoch: 1, frameIndex: 1, entries: entries)
            }
            let snapshot = try SceneResolvedMaterialFrameSnapshot.validated(
                textureSnapshot: textures,
                dynamicSnapshot: .empty(frameIndex: 1),
                frameInputs: .init(frameIndex: 1, screenSize: .init(width: 8, height: 8),
                    sceneTime: 0, dayTime: 0, frameTime: 0, pointerCurrentNDC: .zero,
                    pointerPreviousNDC: .zero)).get()
            let frameInput = snapshot.finalizationInput(template: template, layerID: 42,
                renderSize: .init(width: 8, height: 8), modelViewProjection: matrix_identity_float4x4,
                layerModelMatrix: matrix_identity_float4x4,
                effectOutputModelViewProjection: matrix_identity_float4x4,
                effectTextureProjectionMatrixInverse: matrix_identity_float4x4,
                implicitFramebufferIdentity: input)
            switch SceneResolvedMaterialProgramFinalizer.finalize(frameInput, variantCache: cache) {
            case let .success(program):
                return ["status": "ready", "purpose": program.textureSlots[1]?.expectedPurpose.reportToken ?? "inactive",
                    "backend": program.frontendProgram.backend.rawValue,
                    "activeSlots": program.frontendProgram.textureBindings.map(\.slot).sorted(),
                    "colorSlots": program.frontendProgram.colorBoundary?.colorInputSlots.sorted() ?? [],
                    "pixels": try render(program.frontendProgram, finalized: program)]
            case let .failure(failure):
                return ["status": "failed", "phase": failure.phase.rawValue, "code": failure.code.rawValue,
                    "details": failure.boundedDetails]
            }
        }
        func ready(_ content: SceneTextureContent, _ values: [Float]) throws -> [String: Any] {
            guard let resource = SceneFrameTextureResource.reservedNamedLayerTarget(
                reference: named, frameEpoch: 1, texture: texture(values), content: content) else {
                return ["status": "resource-rejected"]
            }
            return try finalized(.ready(resource))
        }
        let before = cache.counters
        var result: [String: Any] = [:]
        for (label, values, alpha) in [
            ("half", [Float(0.25), 0.75, 0.5], Float(0.5)),
            ("quarter", [Float(0.75), 0.125, 0.5], Float(0.25))] {
            result["pma-\(label)"] = try ready(.color(.resolved(.premultipliedAlpha)),
                values.map { $0 * alpha } + [alpha])
            result["straight-\(label)"] = try ready(.color(.resolved(.straightAlpha)), values + [alpha])
        }
        result["data-half"] = try ready(.data, [0.125, 0.375, 0.25, 0.5])
        result["data-quarter"] = try ready(.data, [0.75, 0.125, 0.5, 0.25])
        result["pending"] = try finalized(.pending)
        result["unavailable"] = try finalized(.unavailable)
        result["absent"] = try finalized(.absent)
        result["missing"] = try finalized(nil)
        let stale = SceneFrameTextureResource.reservedNamedLayerTarget(reference: named, frameEpoch: 2,
            texture: texture([0.125, 0.375, 0.25, 0.5]))!
        result["stale"] = try finalized(.ready(stale))
        result["data-ready-again"] = try ready(.data, [0.125, 0.375, 0.25, 0.5])
        let after = cache.counters
        result["cacheStable"] = before.cachedVariantCount == after.cachedVariantCount
            && before.shaderPreparationCount == after.shaderPreparationCount
            && before.frontendCompilationCount == after.frontendCompilationCount
        return result
    }
}
