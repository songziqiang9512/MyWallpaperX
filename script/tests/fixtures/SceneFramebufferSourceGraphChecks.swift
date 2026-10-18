@main private enum FramebufferSourceGraphChecks {
    static func main() throws {
        setenv("MWX_SCENE_GENERIC_SHADER_ROUTE", "disable-generic", 1)
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else {
            print("{\"metalAvailable\":false}"); return
        }
        let raw = graph(targets: [], nodes: [material(0, ordinal: 0, target: output, read: input)])
        let chain = admittedGraph(raw)
        let owners = capabilities(chain, catalog: catalog(for: raw, pixelTransformsByNode: [0: 1]),
                                  capturedMainTarget: true)
        guard let claim = owners.claim(chain), let capability = owners.resolve(claim.token),
              capability.sourceRoute == .capturedMainTargetTexture,
              let executor = Executor(device: device, capabilities: owners) else {
            print("{\"metalAvailable\":true,\"failure\":\"captured-main-admission\"}"); return
        }
        let original = template(for: raw.nodes[0])
        let contract = shaderContract(nodeIndex: 710, pass: false, fragmentOverride: """
        varying vec2 v_TexCoord;
        uniform sampler2D g_Texture0; // {"hidden":true}
        void main() {
            vec4 sampled = texSample2D(g_Texture0, v_TexCoord);
            sampled.rgb = sampled.rgb.bgr;
            sampled.a = 0.5;
            gl_FragColor = sampled;
        }
        """)
        var slots = Array<Template.TextureSlot?>(repeating: nil, count: 8)
        slots[0] = .init(index: 0, candidates: [.init(
            reference: .provider(.sceneBackground(consumerLayerID: layerID)), provenance: .material)])
        guard let sourceTemplate = Template.validated(textureSlots: slots, combos: [],
            uniformDeclarations: [], renderState: original.renderState,
            graphRole: .init(effectInput: .layerSource, effectOutput: .layerSource,
                nodeTarget: .layerSource, bindings: []),
            shaderContract: contract,
            diagnosticProvenance: .init(nodeIndex: 0, authoredShaderPath: contract.identity,
                contractIdentity: contract.identity, contractCanonicalSHA256: contract.canonicalSHA256,
                textureSources: [], uniformSources: [])),
              case let .success(variants) = SceneResolvedMaterialVariantCache.launchValidated(
                template: sourceTemplate, maximumVariantCount: 32, assetFormatFacts: [:]) else {
            print("{\"metalAvailable\":true,\"failure\":\"source-template\"}"); return
        }
        guard case .success = variants.precompileLaunchEnvelope(implicitFramebufferIdentity: nil,
            outputIsRGBA8Unorm: true, assetStates: [:]) else {
            print("{\"metalAvailable\":true,\"failure\":\"source-envelope\"}"); return
        }
        let pipeline = makeSourcePipeline(device)
        var rows: [[String: Any]] = []
        for (ordinal, name) in ["program", "wrong-epoch", "wrong-consumer", "wrong-texture", "fixed",
                                "bind-color", "bind-frame", "pass-color"].enumerated() {
            let epoch = UInt64(300 + ordinal)
            let lease = makeLease(requirePlan(raw), device: device, generation: epoch)
            guard clear(lease, queue: queue), let buffer = queue.makeCommandBuffer() else {
                rows.append(["name": name, "failure": "lease-clear"]); continue
            }
            let main = makeSource(device, width: 2, height: 2,
                usage: [.renderTarget, .shaderRead], bgra: [0, 0, 0, 255])
            let sampledTexture = name == "wrong-texture"
                ? makeSource(device, width: 2, height: 2, usage: [.renderTarget, .shaderRead]) : main
            guard let resource = SceneFrameTextureResource.sameFrameSceneBackground(
                consumerLayerID: name == "wrong-consumer" ? layerID + 1 : layerID,
                frameEpoch: name == "wrong-epoch" ? epoch + 1 : epoch, texture: main) else {
                rows.append(["name": name, "failure": "main-resource"]); continue
            }
            let injectedFailure: SceneResolvedMaterialFailure? = switch name {
            case "bind-color": .init(phase: .color, code: .colorContractUnproven,
                slot: 0, details: ["owned-source-color"])
            case "bind-frame": .init(phase: .invariant, code: .frameSnapshotMismatch,
                slot: 0, details: ["owned-source-frame"])
            default: nil
            }
            var injectedPassKey: String?
            let sourceMaterial = SceneResolvedMaterialRuntimeBridge.PreparedSourceMaterial(
                template: sourceTemplate,
                bindFrame: { input in
                    if let injectedFailure { return .failure(injectedFailure) }
                    let result = SceneResolvedMaterialProgramFinalizer.finalize(input, variantCache: variants)
                    // This exercises typed propagation through the real source
                    // preparation path, not a real shader proof failure.
                    if name == "pass-color", case let .success(program) = result {
                        injectedPassKey = program.preparedShader.cacheKey
                        executor.materialEncoder.installTestingPreparationFailure(
                            .fragmentOutputRejected, preparedKey: program.preparedShader.cacheKey)
                    }
                    return result
                }, pixelFormat: .bgra8Unorm, outputDomain: .capturedMain)
            let source = SceneResolvedMaterialRuntimeBridge.FramebufferSourceMaterial(
                material: sourceMaterial, source: resource, unitModelMatrix: matrix_identity_float4x4)
            let preparation = executor.prepare(token: claim.token, leases: [lease],
                historyRehydrateCopiesByEffect: [:], frame: frame(epoch),
                sourceTexture: sampledTexture, sourceUniforms: name == "fixed" ? .neutral() : nil,
                sourcePipeline: pipeline, framebufferSourceMaterial: name == "fixed" ? nil : source,
                frameInputs: .init(), commandBuffer: buffer, previousStates: [:], previousGraphResources: [:],
                effectGeneration: epoch, resetGeneration: 1)
            if name != "program" && name != "fixed" {
                let untouched = [lease.fullFramePair.first, lease.fullFramePair.second].compactMap { token in
                    lease.texturesByToken[token].flatMap { appendReadback($0, commandBuffer: buffer) }
                }
                guard untouched.count == 2, case let .failure(failure) = preparation else {
                    rows.append(["name": name, "failure": "rejection-readback"]); continue
                }
                let typed: Bool
                switch failure {
                case .captureRejected: typed = name.hasPrefix("wrong-")
                case let .sourceMaterialFinalizerRejected(original):
                    typed = injectedFailure.map { $0 == original } ?? false
                case let .sourceMaterialPassPreparationRejected(key, reason):
                    typed = name == "pass-color" && injectedPassKey.map { $0 == key } == true
                        && reason == .fragmentOutputRejected
                default: typed = false
                }
                buffer.commit(); buffer.waitUntilCompleted()
                rows.append(["name": name, "rejection": failureCode(preparation),
                    "typedFailurePreserved": typed,
                    "localizable": failure.isColorContractVisualRejection,
                    "gpu": buffer.status == .completed && buffer.error == nil,
                    "pairUntouched": untouched.allSatisfy { read in
                        read.allTexels.allSatisfy { matches($0, [255, 0, 0, 255]) }
                    }])
                continue
            }
            guard case let .success(prepared) = preparation else {
                rows.append(["name": name, "failure": failureCode(preparation)]); continue
            }
            let baseToken = capability.pairPlan.baseCaptureMember == .zero
                ? lease.fullFramePair.first : lease.fullFramePair.second
            guard let base = lease.texturesByToken[baseToken],
                  let before = appendReadback(base, commandBuffer: buffer) else {
                rows.append(["name": name, "failure": "before-readback"]); continue
            }
            // This is the actual earlier-main write. Preparation must not
            // sample/encode the old black main contents before this boundary.
            let pass = SceneMainPassEncoder(commandBuffer: buffer, target: main,
                clearColor: .init(red: 0.8, green: 0.4, blue: 0.2, alpha: 1), clearEnabled: true)
            guard pass.withReadableTarget({ $0 === main && $1 === buffer }) == true,
                  executor.encode(prepared, commandBuffer: buffer),
                  let baseRead = appendReadback(base, commandBuffer: buffer),
                  let finalRead = appendReadback(prepared.finalTexture, commandBuffer: buffer) else {
                rows.append(["name": name, "failure": "actual-encode"]); continue
            }
            buffer.commit(); buffer.waitUntilCompleted()
            let expectedBase: [UInt8] = name == "program" ? [204, 102, 51, 128] : [51, 102, 204, 255]
            let expectedFinal: [UInt8] = name == "program" ? [51, 204, 102, 128] : [204, 51, 102, 255]
            rows.append(["name": name,
                "gpu": buffer.status == .completed && buffer.error == nil,
                "prepareDidNotWrite": before.allTexels.allSatisfy { matches($0, [255, 0, 0, 255]) },
                "usesOriginalPair": [lease.fullFramePair.first, lease.fullFramePair.second].contains {
                    lease.texturesByToken[$0] === prepared.finalTexture
                },
                "basePixels": baseRead.allTexels, "effectPixels": finalRead.allTexels,
                "baseMatches": baseRead.allTexels.allSatisfy { matches($0, expectedBase) },
                "effectMatches": finalRead.allTexels.allSatisfy { matches($0, expectedFinal) },
                "finalIsStraight": prepared.finalResource.publication.candidate.content == .color(.resolved(.straightAlpha)),
                "effectProgramExecuted": prepared.stages.count == 1
                    && prepared.stages[0].programCacheKeys.count == 1
                    && prepared.stages[0].effectLocalFailureReasonCode == nil])
        }
        print(String(decoding: try JSONSerialization.data(withJSONObject:
            ["metalAvailable": true, "rows": rows], options: [.sortedKeys]), as: UTF8.self))
    }
}
