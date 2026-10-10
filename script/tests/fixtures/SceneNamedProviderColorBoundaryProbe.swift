// Reuses the existing real launch producer and GPU renderer. No compiled
// variant, resolver, color-boundary set or output pixel is forged by the probe.
extension BackgroundColorABIHarness {
    static func namedProviderColorBoundary(_ name: String, mixed: Bool) throws -> [String: Any] {
        let fragment = """
        varying vec2 v_TexCoord;
        uniform sampler2D g_Texture0; // {"hidden":true,"material":"framebuffer"}
        uniform sampler2D g_Texture1; // {"mode":"rgbmask","material":"namedInput"}
        void main() {
            vec4 base = texSample2D(g_Texture0, v_TexCoord);
            vec4 provider = texSample2D(g_Texture1, v_TexCoord);
            gl_FragColor = vec4(mix(base.rgb, provider.rgb, provider.a), 1.0);
        }
        """
        let shader = contract(fragment)
        let input = Graph.TextureIdentity(kind: .layerSource, layerID: 42, effect: nil, name: nil)
        let named = SceneNamedTextureReference(providerLayerID: 879, variant: .primary)
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
            effectContext: .init(key: .init(layerID: 42, effectIndex: 0, descriptorID: name), input: input),
            compatibilityTarget: .windowsDX11ShaderModel4, shaderContract: shader,
            diagnosticProvenance: .init(nodeIndex: 0, authoredShaderPath: shader.identity,
                contractIdentity: shader.identity, contractCanonicalSHA256: shader.canonicalSHA256,
                textureSources: [], uniformSources: []))!
        let cache = try SceneResolvedMaterialVariantCache.launchValidated(template: template, maximumVariantCount: 16).get()
        let launch = cache.precompileLaunchEnvelope(implicitFramebufferIdentity: input, outputStorage: .color)
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
                "metalSHA256": SceneShaderStableDigest.hash(Data(program.metalSource.utf8))
            ]
            // Ordinary bounded profiles deliberately exclude mixed inputs
            // from their auxiliary PMA set. The typed data selection remains
            // authoritative for this known two-purpose candidate envelope.
            if variant.preservedChannelsProviderInputSlots.isEmpty {
                row["pmaPixels"] = try render(program, providerSlot: 1,
                    inputMask: (1 << 0) | (1 << 1))
                row["straightPixels"] = try render(program, providerPixel: [0.2, 0.6, 0.4, 0.5],
                    providerSlot: 1, inputMask: 1 << 0)
            } else if variant.preservedChannelsProviderInputSlots == [1] {
                // Even an association mask cannot turn a typed data slot into
                // color. Literal provider RGB and alpha enter authored math.
                row["dataPixels"] = try render(program, providerSlot: 1,
                    inputMask: (1 << 0) | (1 << 1))
            }
            return row
        }
        return ["launch": String(describing: launch), "ready": snapshot.allEntriesReady,
                "candidateCount": candidates.count, "variants": variants]
    }
}
