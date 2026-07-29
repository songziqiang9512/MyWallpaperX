import Metal
import simd

/// Small draw loop shared by the production Metal path and its encoding test.
///
/// The same texture value is deliberately forwarded to every draw, while the
/// pipeline binding happens exactly once for the complete 64-instance batch.
nonisolated enum SceneScriptAudioBarsDrawLoop {
    static func encode<Texture>(
        texture: Texture,
        matrices: [simd_float4x4],
        uniforms: SceneLayerFragmentUniforms,
        bind: () -> Void,
        draw: (Texture, simd_float4x4, SceneLayerFragmentUniforms) -> Void
    ) -> Bool {
        guard matrices.count == SceneScriptAudioBarsGeometry.instanceBudget else {
            return false
        }
        bind()
        for matrix in matrices {
            draw(texture, matrix, uniforms)
        }
        return true
    }
}

extension SceneMetalRenderer {
    /// Encodes a verified SceneScript audio-bars plan into the main source-over
    /// image pass. The supplied pipeline must use its source-over blend state.
    ///
    /// Only the owner origin and model size survive script initialization.
    /// Authored scale and angles are intentionally not read here because both
    /// verified profiles replace them for every generated bar.
    func renderSceneScriptAudioBars(
        plan: SceneScriptAudioBarsPlan,
        layer: SceneRenderDescriptor.Layer,
        texture: MTLTexture,
        pipeline: SceneImageLayerPipeline,
        frameContext: SceneFrameContext,
        sceneOrthoHeight: Float?,
        viewProjection: simd_float4x4,
        mainPass: SceneMainPassEncoder
    ) -> Bool {
        guard plan.layerID == layer.id,
              let originValues = layer.originXYZ,
              originValues.count == 3,
              let sizeValues = layer.sizeWH,
              sizeValues.count == 2,
              frameContext.sceneTime.isFinite,
              let instances = SceneScriptAudioBarsGeometry.instances(
                  plan: plan,
                  spectrum: frameContext.audioSpectrum
              ) else {
            return false
        }

        let baseOrigin = SIMD3<Float>(
            originValues[0],
            originValues[1],
            originValues[2]
        )
        let baseSize = SIMD2<Float>(sizeValues[0], sizeValues[1])
        guard let sceneOrthoHeight else {
            return false
        }
        var matrices: [simd_float4x4] = []
        matrices.reserveCapacity(instances.count)
        for instance in instances {
            guard let model = SceneScriptAudioBarsGeometry.modelMatrix(
                authoredBaseOrigin: baseOrigin,
                sceneOrthoHeight: sceneOrthoHeight,
                baseSize: baseSize,
                instance: instance
            ) else {
                return false
            }
            let mvp = viewProjection * model
            guard Self.sceneScriptAudioBarsMatrixIsFinite(mvp) else {
                return false
            }
            matrices.append(mvp)
        }

        let time = Float(frameContext.sceneTime)
        guard time.isFinite, let encoder = mainPass.encoder() else {
            return false
        }
        var uniforms = SceneLayerFragmentUniforms.neutral(
            alpha: SceneDynamicLayerValues.alpha(
                layerID: layer.id,
                authoredValue: layer.alpha,
                snapshot: frameContext.dynamicValues
            )
        )
        uniforms.time = time
        let tint = SceneDynamicLayerValues.color(
            layerID: layer.id,
            authoredValue: layer.colorRGB,
            snapshot: frameContext.dynamicValues
        )
        uniforms.tint = SIMD4(tint.x, tint.y, tint.z, 1)

        return SceneScriptAudioBarsDrawLoop.encode(
            texture: texture,
            matrices: matrices,
            uniforms: uniforms,
            bind: {
                pipeline.bind(encoder: encoder)
            },
            draw: { texture, mvp, uniforms in
                pipeline.drawLayer(
                    texture: texture,
                    shakeMaskTexture: nil,
                    waterMaskTexture: nil,
                    foliageMaskTexture: nil,
                    auxMaskTexture: nil,
                    dependencyTexture: nil,
                    mvp: mvp,
                    uniforms: uniforms,
                    encoder: encoder
                )
            }
        )
    }

    private static func sceneScriptAudioBarsMatrixIsFinite(
        _ matrix: simd_float4x4
    ) -> Bool {
        (0..<4).allSatisfy { column in
            let value = matrix[column]
            return value.x.isFinite
                && value.y.isFinite
                && value.z.isFinite
                && value.w.isFinite
        }
    }
}
