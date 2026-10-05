import Metal

extension SceneResolvedMaterialExecutionCapabilityCatalog {
    func launchPipelineWarmupPlans(
        device: MTLDevice
    ) -> [SceneResolvedMaterialPassEncoder.WarmupPlan] {
        launchPipelineWarmupCapabilities.flatMap { capability in
            Array(capability.materials.values).sorted {
                identity($0.key) < identity($1.key)
            }.flatMap { material -> [SceneResolvedMaterialPassEncoder.WarmupPlan] in
                let snapshot = material.variants.launchEnvelopeCapabilitySnapshot()
                guard snapshot.allEntriesReady, !snapshot.variants.isEmpty else {
                    return []
                }
                let writeMask: MTLColorWriteMask = switch material.attachmentStorage {
                case .color: .all
                case .scalarRedUnorm, .scalarRedFloat16: .red
                case .redGreenUnorm, .redGreenFloat16: [.red, .green]
                case .preservedRGBAUnorm: .all
                }
                return snapshot.variants.flatMap { variant in
                    func plan(_ format: MTLPixelFormat,
                              _ role: SceneResolvedMaterialProgram.PassRole)
                        -> SceneResolvedMaterialPassEncoder.WarmupPlan? {
                        .init(identity: identity(material.key),
                              preparedKey: variant.preparedShader.cacheKey,
                              frontend: variant.frontendProgram,
                              renderState: material.template.renderState,
                              frontendSchemaVersion:
                                variant.preparedShader.vertex.frontendSchemaVersion,
                              pixelFormat: format, writeMask: writeMask,
                              passRole: role, device: device)
                    }
                    var plans = [plan(material.targetFormat.metalPixelFormat,
                                      .offscreenOverwrite)].compactMap { $0 }
                    let fields = variant.frontendProgram.uniformLayout.fields
                    if capability.supportsTerminalMaterialReplay,
                       variant.frontendProgram.supportsTerminalMaterialReplay,
                       material.attachmentStorage == .color,
                       fields.contains(where: {
                           $0.authoredName == "mwxRenderSize" && $0.type == .float2
                       }), fields.contains(where: {
                           $0.authoredName == "g_ModelViewProjectionMatrix"
                               && $0.type == .float4x4
                       }) {
                        plans += [MTLPixelFormat.bgra8Unorm, .rgba16Float]
                            .compactMap { plan($0, .terminalSourceOver) }
                    }
                    return plans
                }
            }
        }
    }

    private func identity(_ key: MaterialKey) -> String {
        "\(key.effect.layerID):\(key.effect.effectIndex):"
            + "\(key.effect.descriptorID.utf8.count)#"
            + "\(key.effect.descriptorID):\(key.nodeIndex)"
    }
}
