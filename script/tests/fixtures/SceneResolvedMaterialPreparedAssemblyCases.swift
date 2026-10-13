import Foundation
import Metal

/// Self-authored ABI/frame cases shared with the existing Program harness.
/// No compiler source text, fixture name or resource path selects a route.
func scenePreparedAssemblyRegressionCases(
    baseline: SceneResolvedMaterialProgram
) -> [String: Bool] {
    typealias Program = SceneResolvedMaterialProgram
    let route = SceneGenericShaderRouteDecision(
        profile: "self-authored-prepared-assembly",
        state: "fixture", fallbackOwner: "none"
    )
    let frontend = baseline.frontendProgram
    func prepare(_ candidate: SceneAuthoredShaderProgram) -> Program.PreparedAssembly? {
        try? Program.PreparedAssembly(
            preparedShader: baseline.preparedShader,
            frontend: candidate, renderState: baseline.renderState,
            runtimeLoopBounds: baseline.runtimeLoopBounds,
            hasEffectContext: false,
            conditionalGeneratedRGBInputContract: nil,
            associatedOverOverlaySlot: nil, premultipliedColorInputSlots: []
        )
    }
    guard let prepared = prepare(frontend),
          let scalarIndex = baseline.resolvedUniforms.firstIndex(where: {
              $0.field.type == .float && $0.field.arrayCount == nil
          }), let originalSlot = baseline.textureSlots[0] else {
        return ["preparedAssemblyFixtureReady": false]
    }
    let originalUniform = baseline.resolvedUniforms[scalarIndex]
    let target = SceneDynamicTarget.effectConstant(
        layerID: 71, effectIndex: 2, passIndex: 3,
        name: originalUniform.field.name
    )
    func uniforms(_ gain: Float, source: SceneDynamicSource = .timeline)
        -> [Program.ResolvedUniform] {
        var value = gain
        var result = baseline.resolvedUniforms
        result[scalarIndex] = .init(
            field: originalUniform.field,
            source: .dynamic(declared: .timeline, target: target,
                             resolvedSource: source, scriptAttachments: []),
            encodedValue: withUnsafeBytes(of: &value) { Data($0) }
        )
        return result
    }
    func frame(
        _ values: [Program.ResolvedUniform],
        slots: [Program.TextureSlot?]? = nil
    ) -> Program.FrameAssemblyInput {
        .init(
            textureSlots: slots ?? baseline.textureSlots,
            resolvedUniforms: values,
            graphRole: baseline.semanticIdentity.graphRole,
            outputStorage: .color
        )
    }
    func assemble(_ input: Program.FrameAssemblyInput) -> Program? {
        Program.assemblePrepared(input, prepared: prepared, routeDecision: route)
    }
    guard let first = assemble(frame(uniforms(0.25))),
          let second = assemble(frame(uniforms(0.75))),
          let authored = assemble(frame(uniforms(0.25, source: .authored))) else {
        return ["preparedAssemblyFixtureFramesReady": false]
    }
    let candidate = originalSlot.resource.publication.candidate
    func replacement(
        content: SceneTextureContent? = nil,
        purpose: SceneTextureLoadPurpose? = nil,
        generation: UInt64 = 2,
        publishedGeneration: UInt64 = 2,
        mappedSize: CGSize? = nil,
        uv: SceneTextureUVTransform? = nil
    ) -> Program.TextureSlot {
        .init(
            index: originalSlot.index, reference: originalSlot.reference,
            registryIdentity: originalSlot.registryIdentity,
            diagnosticSelectionProvenance: originalSlot.diagnosticSelectionProvenance,
            graphInputSourceFact: originalSlot.graphInputSourceFact,
            expectedPurpose: originalSlot.expectedPurpose,
            resource: .init(
                publication: .init(
                    requestIdentity: originalSlot.registryIdentity,
                    candidate: .init(
                        texture: candidate.texture, identity: candidate.identity,
                        generation: .provider(contentGeneration: generation),
                        purpose: purpose ?? candidate.purpose,
                        content: content ?? candidate.content,
                        physicalSize: candidate.physicalSize,
                        mappedSize: mappedSize ?? candidate.mappedSize,
                        uvTransform: uv ?? candidate.uvTransform,
                        sampling: candidate.sampling
                    ),
                    contentGeneration: publishedGeneration
                ),
                resourceGeneration: originalSlot.resource.resourceGeneration + 1
            )
        )
    }
    func textureFrame(_ slot: Program.TextureSlot?) -> Program.FrameAssemblyInput {
        var slots = baseline.textureSlots
        slots[0] = slot
        return frame(uniforms(0.25), slots: slots)
    }
    let renewed = assemble(textureFrame(replacement()))
    let opaque = assemble(textureFrame(replacement(content: .color(.resolved(.opaque)))))
    let mapped = assemble(textureFrame(replacement(
        mappedSize: CGSize(width: 1, height: 1),
        uv: .init(origin: .zero, xAxis: SIMD2(0.5, 0), yAxis: SIMD2(0, 0.5))
    )))
    let raw = Program.assembleCompiled(.init(
        preparedShader: baseline.preparedShader,
        textureSlots: baseline.textureSlots,
        resolvedUniforms: uniforms(0.25),
        renderState: baseline.renderState,
        graphRole: baseline.semanticIdentity.graphRole
    ), frontend: frontend, routeDecision: route,
       conditionalGeneratedRGBInputContract: nil)

    func alteredFrontend(
        layout: SceneAuthoredShaderUniformLayout? = nil,
        bindings: [SceneAuthoredShaderProgram.TextureBinding]? = nil
    ) -> SceneAuthoredShaderProgram {
        .init(
            metalSource: frontend.metalSource,
            vertexFunctionName: frontend.vertexFunctionName,
            fragmentFunctionName: frontend.fragmentFunctionName,
            uniformBufferIndex: frontend.uniformBufferIndex,
            uniformLayout: layout ?? frontend.uniformLayout,
            textureBindings: bindings ?? frontend.textureBindings,
            staticLoopWork: frontend.staticLoopWork,
            colorTransfer: frontend.colorTransfer,
            fragmentOutputChannelUse: frontend.fragmentOutputChannelUse,
            backend: frontend.backend,
            vertexPositionInput: frontend.vertexPositionInput,
            colorBoundary: frontend.colorBoundary
        )
    }
    let field = frontend.uniformLayout.fields[0]
    let firstBinding = frontend.textureBindings[0]
    let duplicateLayout = alteredFrontend(layout: .init(
        fields: [field, field], byteSize: frontend.uniformLayout.byteSize
    ))
    let unalignedLayout = alteredFrontend(layout: .init(
        fields: [.init(name: field.name, type: field.type, offset: 1)],
        byteSize: frontend.uniformLayout.byteSize
    ))
    let duplicateBindings = alteredFrontend(bindings: [firstBinding, firstBinding])
    let invalidBindings = alteredFrontend(bindings: [
        .init(name: firstBinding.name, slot: 8, channelUse: firstBinding.channelUse)
    ])
    let unsortedBindings = alteredFrontend(bindings: [
        .init(name: "fixtureSecondSampler", slot: 1, channelUse: .wholeVector),
        firstBinding
    ])
    func renamedResource(_ path: String) -> Program? {
        guard let path = SceneVFSAssetPath(path) else { return nil }
        let identity = SceneFrameTextureIdentity.asset(.init(
            path: path, purpose: originalSlot.expectedPurpose
        ))
        var slots = baseline.textureSlots
        slots[0] = .init(
            index: 0, reference: .asset(path), registryIdentity: identity,
            diagnosticSelectionProvenance: .authored(.material),
            expectedPurpose: originalSlot.expectedPurpose,
            resource: .init(publication: .init(
                requestIdentity: identity, candidate: candidate,
                contentGeneration: originalSlot.resource.publication.contentGeneration
            ), resourceGeneration: originalSlot.resource.resourceGeneration)
        )
        let role = baseline.semanticIdentity.graphRole
        return assemble(.init(
            textureSlots: slots, resolvedUniforms: uniforms(0.25),
            graphRole: .init(effectInput: role.effectInput, effectOutput: role.effectOutput,
                             nodeTarget: role.nodeTarget, bindings: []),
            outputStorage: .color
        ))
    }
    let resourceA = renamedResource("self-fixture/first-texture")
    let resourceB = renamedResource("renamed-input/second-texture")
    let device = candidate.texture.device
    let firstKey = first.metalCompileStateKey(
        attachmentPixelFormat: .bgra8Unorm, sampleCount: 1, device: device
    )
    return [
        "preparedFactoryRejectsDuplicateLayout": prepare(duplicateLayout) == nil,
        "preparedFactoryRejectsUnalignedLayout": prepare(unalignedLayout) == nil,
        "preparedFactoryRejectsDuplicateSlots": prepare(duplicateBindings) == nil,
        "preparedFactoryRejectsOutOfRangeSlot": prepare(invalidBindings) == nil,
        "preparedFactoryRejectsUnsortedSlots": prepare(unsortedBindings) == nil,
        "preparedRawAndFrameAssemblyAgree": raw?.exactIdentity == first.exactIdentity,
        "preparedSerialFramesKeepStaticShaderAndState": (1 ... 60).allSatisfy {
            guard let next = assemble(frame(uniforms(Float($0) / 100))) else { return false }
            return next.semanticIdentity.shader == prepared.shaderIdentity
                && next.semanticIdentity.renderState == prepared.renderStateIdentity
                && next.exactIdentity.prepared == prepared.preparedIdentity
        },
        "preparedUniformValueChangesExact": first.semanticIdentity == second.semanticIdentity
            && first.uniformBytes != second.uniformBytes && first.exactIdentity != second.exactIdentity,
        "preparedResolvedSourceStillChangesExact": authored.semanticIdentity == first.semanticIdentity
            && authored.exactIdentity != first.exactIdentity,
        "preparedWrongDynamicSourceRejected": assemble(frame(uniforms(0.25, source: .userProperty))) == nil,
        "preparedCurrentGenerationChangesExact": renewed?.semanticIdentity == first.semanticIdentity
            && renewed != nil && renewed?.exactIdentity != first.exactIdentity,
        "preparedCurrentContentChangesSemanticAndOutput": opaque != nil
            && opaque?.semanticIdentity.textureSlots != first.semanticIdentity.textureSlots
            && opaque?.outputContract != first.outputContract,
        "preparedCurrentExtentAndUVChangeExact": mapped != nil
            && mapped?.exactIdentity.textureSlots != renewed?.exactIdentity.textureSlots,
        "preparedStalePublicationRejected": assemble(textureFrame(replacement(publishedGeneration: 1))) == nil,
        "preparedWrongPurposeRejected": assemble(textureFrame(replacement(purpose: .mask))) == nil,
        "preparedMissingActiveSlotRejected": assemble(textureFrame(nil)) == nil,
        "preparedFailureThenCurrentRecovers": assemble(frame(uniforms(0.25)))?.exactIdentity == first.exactIdentity,
        "preparedResourceRenamePreservesSemanticAndChangesExact": resourceA != nil
            && resourceB != nil && resourceA?.semanticIdentity == resourceB?.semanticIdentity
            && resourceA?.exactIdentity != resourceB?.exactIdentity,
        "preparedPipelineKeyUsesCurrentStaticIdentity": firstKey != nil
            && firstKey?.shader == first.semanticIdentity.shader
            && firstKey?.renderState == first.semanticIdentity.renderState
            && firstKey == second.metalCompileStateKey(
                attachmentPixelFormat: .bgra8Unorm, sampleCount: 1, device: device
            ),
        "preparedPipelineRejectsAttachmentAndSample": first.metalCompileStateKey(
            attachmentPixelFormat: .invalid, sampleCount: 1, device: device
        ) == nil && first.metalCompileStateKey(
            attachmentPixelFormat: .bgra8Unorm, sampleCount: 0, device: device
        ) == nil && first.metalCompileStateKey(
            attachmentPixelFormat: .bgra8Unorm, sampleCount: 1,
            colorWriteMask: [], device: device
        ) == nil,
    ]
}
