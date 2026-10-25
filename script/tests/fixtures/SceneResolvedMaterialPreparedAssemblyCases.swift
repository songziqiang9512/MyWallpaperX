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
        uniformBufferIndex: Int? = nil,
        bindings: [SceneAuthoredShaderProgram.TextureBinding]? = nil
    ) -> SceneAuthoredShaderProgram {
        .init(
            metalSource: frontend.metalSource,
            vertexFunctionName: frontend.vertexFunctionName,
            fragmentFunctionName: frontend.fragmentFunctionName,
            uniformBufferIndex: uniformBufferIndex ?? frontend.uniformBufferIndex,
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
    var results = [
        "preparedAssemblyRejectsOutOfRangeUniformBuffer": prepare(alteredFrontend(uniformBufferIndex: -1)) == nil
            && prepare(alteredFrontend(uniformBufferIndex: 31)) == nil,
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
    results.merge(sceneShaderIdentityHashRegressionCases(first.semanticIdentity.shader)) { _, new in new }
    return results
}

/// Reconstruct the real value through its production initializer, with one
/// input changed. The identity's hashing/equality implementation is not copied.
func sceneCopiedShaderIdentity(
    _ base: Program.ShaderSemanticIdentity,
    changing field: String = "",
    source: String? = nil
) -> Program.ShaderSemanticIdentity {
    let fields = base.uniformFields.enumerated().map { index, value in
        Program.ShaderSemanticIdentity.UniformField(
            name: index == 0 && field == "fieldName" ? value.name + "_renamed" : value.name,
            valueType: index == 0 && field == "fieldType" ? value.valueType + "2" : value.valueType,
            arrayCount: index == 0 && field == "arrayCount" ? (value.arrayCount ?? 0) + 1 : value.arrayCount,
            offset: index == 0 && field == "fieldOffset" ? value.offset + 16 : value.offset
        )
    }
    return .init(
        frontendSchemaVersion: base.frontendSchemaVersion + (field == "schema" ? 1 : 0),
        backend: field == "backend"
            ? (base.backend == .boundedSwift ? .genericCompilerArtifact : .boundedSwift) : base.backend,
        metalSource: source ?? (field == "source" ? base.metalSource + "\n// changed source"
            : String(decoding: Array(base.metalSource.utf8), as: UTF8.self)),
        vertexFunctionName: field == "vertexEntry" ? base.vertexFunctionName + "_other" : base.vertexFunctionName,
        fragmentFunctionName: field == "fragmentEntry" ? base.fragmentFunctionName + "_other" : base.fragmentFunctionName,
        uniformBufferIndex: base.uniformBufferIndex + (field == "buffer" ? 1 : 0),
        uniformFields: fields,
        textureSlots: field == "slots" ? base.textureSlots + [7] : base.textureSlots.map { $0 },
        textureChannelUses: field == "channels" ? base.textureChannelUses + [.unproven] : base.textureChannelUses.map { $0 },
        colorTransfer: field == "transfer" ? (base.colorTransfer == .opaque ? .unresolved : .opaque) : base.colorTransfer,
        colorBoundary: field == "boundary" ? (base.colorBoundary == nil
            ? .init(colorInputSlots: [0], outputRepresentation: .straightAlpha) : nil) : base.colorBoundary,
        vertexPositionInput: field == "position" ? (base.vertexPositionInput == nil ? .targetPixels : nil) : base.vertexPositionInput,
        fragmentOutputChannelUse: field == "output" ? (base.fragmentOutputChannelUse == .redDefined ? .unproven : .redDefined)
            : base.fragmentOutputChannelUse
    )
}

private struct SceneConstantHashShaderKey: Hashable {
    let value: Program.ShaderSemanticIdentity
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.value == rhs.value }
    func hash(into hasher: inout Hasher) { hasher.combine(0) }
}

private func sceneShaderIdentityHashRegressionCases(
    _ base: Program.ShaderSemanticIdentity
) -> [String: Bool] {
    let copy = sceneCopiedShaderIdentity(base)
    let names = ["schema", "backend", "source", "vertexEntry", "fragmentEntry", "buffer",
                 "fieldName", "fieldType", "arrayCount", "fieldOffset", "slots", "channels",
                 "transfer", "boundary", "position", "output"]
    let variants = names.map { sceneCopiedShaderIdentity(base, changing: $0) }
    let all = [base] + variants
    let independent = all.map { sceneCopiedShaderIdentity($0) }
    let dictionary = Dictionary(uniqueKeysWithValues: all.enumerated().map { ($0.element, $0.offset) })
    let set = Set(all)
    let collisionDictionary = Dictionary(uniqueKeysWithValues: all.enumerated().map {
        (SceneConstantHashShaderKey(value: $0.element), $0.offset)
    })
    let collisionSet = Set(all.map { SceneConstantHashShaderKey(value: $0) })
    // Standard String equality includes canonical Unicode equivalence. Derived
    // cached hashes must preserve that contract across independent construction.
    let composed = sceneCopiedShaderIdentity(base, source: base.metalSource + "\n// caf\u{e9}")
    let decomposed = sceneCopiedShaderIdentity(base, source: base.metalSource + "\n// cafe\u{301}")
    return [
        "shaderIndependentConstructionEqualAndHashConsistent": base == copy && base.hashValue == copy.hashValue,
        "shaderEachSemanticFieldRemainsDistinct": !base.uniformFields.isEmpty
            && variants.allSatisfy { $0 != base } && set.count == all.count,
        "shaderIndependentSetAndDictionaryLookup": independent.enumerated().allSatisfy {
            set.contains($0.element) && dictionary[$0.element] == $0.offset
        },
        // This forces container collisions, not a collision in a private cached Int.
        "shaderForcedContainerCollisionRetainsStructuralEquality": collisionSet.count == all.count
            && independent.enumerated().allSatisfy {
                collisionSet.contains(.init(value: $0.element))
                    && collisionDictionary[.init(value: $0.element)] == $0.offset
            },
        "shaderCanonicalUnicodeEqualityAndLookup": composed == decomposed
            && composed.hashValue == decomposed.hashValue
            && Set([composed]).contains(decomposed) && [composed: 37][decomposed] == 37,
    ]
}
