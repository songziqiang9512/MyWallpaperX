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
                case .scalarRedUnorm: .red
                case .redGreenUnorm: [.red, .green]
                }
                return snapshot.variants.compactMap { variant in
                    SceneResolvedMaterialPassEncoder.WarmupPlan(
                        identity: identity(material.key),
                        preparedKey: variant.preparedShader.cacheKey,
                        frontend: variant.frontendProgram,
                        renderState: material.template.renderState,
                        frontendSchemaVersion:
                            variant.preparedShader.vertex.frontendSchemaVersion,
                        pixelFormat: material.targetFormat.metalPixelFormat,
                        writeMask: writeMask,
                        device: device
                    )
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
