// Shared template, texture publication, frame, and finalization builders.
import Foundation
import Metal
import simd

func graphTexture() -> Graph.TextureIdentity {
    .init(kind: .layerSource, layerID: fixtureLayerID, effect: nil, name: nil)
}

func framebufferTexture() -> Graph.TextureIdentity {
    .init(
        kind: .framebuffer,
        layerID: fixtureLayerID,
        effect: .init(
            layerID: fixtureLayerID,
            effectIndex: 0,
            descriptorID: "fixture-scalar-producer"
        ),
        name: nil
    )
}

func effectOutputTexture(_ descriptorID: String) -> Graph.TextureIdentity {
    .init(
        kind: .effectOutput,
        layerID: fixtureLayerID,
        effect: .init(
            layerID: fixtureLayerID,
            effectIndex: descriptorID == "fixture-prior" ? 0 : 1,
            descriptorID: descriptorID
        ),
        name: nil
    )
}

func namedFramebufferTexture() -> Graph.TextureIdentity {
    .init(
        kind: .framebuffer,
        layerID: fixtureLayerID,
        effect: .init(
            layerID: fixtureLayerID,
            effectIndex: 1,
            descriptorID: "fixture-current"
        ),
        name: "fixture-history-target"
    )
}

func state(blending: String = "normal") -> SceneMaterialRenderState {
    SceneMaterialRenderState.compile(
        blending: blending,
        depthTest: "disabled",
        depthWrite: "disabled",
        cullMode: "nocull",
        alphaWriting: nil
    )!
}

func candidates(
    _ count: Int,
    primaryReference: Template.TextureReference = .graph(graphTexture())
) -> [Template.TextureCandidate] {
    (0 ..< count).map { index in
        .init(
            reference: index == count - 1
                ? primaryReference
                : .asset(SceneVFSAssetPath("textures/overridden-\(index).tex")!),
            provenance: index == count - 1 ? .explicitBinding : .instance
        )
    }
}

func staticValue(
    _ components: [Double],
    scalarProjectionProven: Bool = false
) -> Template.StaticUniformValue {
    .init(
        valueKind: "fixture",
        componentBitPatterns: components.map(\.bitPattern),
        authoredBindingKeys: [],
        authoredScalarProjectionProven: scalarProjectionProven
    )
}

func staticDeclaration(
    _ name: String,
    components: [Double],
    scalarProjectionProven: Bool = false
) -> Template.UniformDeclaration {
    .init(name: name, value: .staticExact(staticValue(
        components,
        scalarProjectionProven: scalarProjectionProven
    )))
}

func dynamicDeclaration(
    _ valueContributors: [Template.DynamicUniformSource],
    attachments: [Template.DynamicUniformScriptAttachment] = []
) -> Template.UniformDeclaration {
    .init(
        name: "Tint",
        value: .dynamic(.init(
            target: .effectConstant(
                layerID: fixtureLayerID,
                effectIndex: 0,
                passIndex: 0,
                name: "Tint"
            ),
            valueContributors: valueContributors,
            scriptAttachments: attachments,
            authoredFallback: staticValue([1, 0.5, 0.25]),
            authoredBindingKeys: ["animation", "script", "value"]
        ))
    )
}

func dynamicAlphaDeclaration(
    _ valueContributors: [Template.DynamicUniformSource]
) -> Template.UniformDeclaration {
    .init(
        name: "alpha",
        value: .dynamic(.init(
            target: .effectConstant(
                layerID: fixtureLayerID,
                effectIndex: 0,
                passIndex: 0,
                name: "alpha"
            ),
            valueContributors: valueContributors,
            scriptAttachments: [],
            authoredFallback: staticValue([1]),
            authoredBindingKeys: ["value"]
        ))
    )
}

func directUserAlphaDeclaration(
    fallback: Double = 0.75
) -> Template.UniformDeclaration {
    .init(
        name: "alpha",
        value: .dynamic(.init(
            target: .effectConstant(
                layerID: fixtureLayerID,
                effectIndex: 0,
                passIndex: 0,
                name: "alpha"
            ),
            valueContributors: [.userProperty("opacity")],
            scriptAttachments: [],
            authoredFallback: .init(
                valueKind: "binding",
                componentBitPatterns: [fallback.bitPattern],
                authoredBindingKeys: ["user", "value"]
            ),
            authoredBindingKeys: ["user", "value"]
        ))
    )
}

func dynamicScaleDeclaration(
    fallback: [Double] = [0.6],
    contributors: [Template.DynamicUniformSource] = [
        .userProperty("unseenScaleProperty"),
    ],
    bindingKeys: [String] = ["user", "value"]
) -> Template.UniformDeclaration {
    .init(
        name: "scale",
        value: .dynamic(.init(
            target: .effectConstant(
                layerID: fixtureLayerID,
                effectIndex: 0,
                passIndex: 0,
                name: "scale"
            ),
            valueContributors: contributors,
            scriptAttachments: [],
            authoredFallback: .init(
                valueKind: "binding",
                componentBitPatterns: fallback.map(\.bitPattern),
                authoredBindingKeys: bindingKeys
            ),
            authoredBindingKeys: bindingKeys
        ))
    )
}

func dynamicScalarDeclaration(_ name: String) -> Template.UniformDeclaration {
    .init(
        name: name,
        value: .dynamic(.init(
            target: .effectConstant(
                layerID: fixtureLayerID,
                effectIndex: 0,
                passIndex: 0,
                name: name
            ),
            valueContributors: [.timeline],
            scriptAttachments: [],
            authoredFallback: staticValue([5]),
            authoredBindingKeys: ["value"]
        ))
    )
}

func template(
    _ shader: SceneShaderContract,
    slot: Int = 0,
    candidateCount: Int = 1,
    includePrimaryCandidate: Bool = true,
    primaryReference: Template.TextureReference = .graph(graphTexture()),
    effectInputGraphTextureRole: Template.GraphTextureRole = .layerSource,
    primaryGraphTextureRole: Template.GraphTextureRole = .layerSource,
    graphBindingsOverride: [Template.GraphBindingRole]? = nil,
    secondReference: Template.TextureReference? = nil,
    secondCandidates: [Template.TextureCandidate]? = nil,
    comboValues: [String: Int] = [:],
    inheritedInactiveCombos: Set<String> = [],
    previousBlurredCompositeGenericOwnerEligible: Bool = false,
    uniformDeclarations: [Template.UniformDeclaration] = [],
    renderState: SceneMaterialRenderState = state(),
    textureSlotsOverride: [Template.TextureSlot?]? = nil,
    effectContext: Template.EffectContext? = nil,
    compatibilityTarget: SceneShaderCompatibilityTarget = .unprofiledMetal
) -> Template {
    var slots = Array<Template.TextureSlot?>(repeating: nil, count: 8)
    if includePrimaryCandidate {
        slots[slot] = .init(
            index: slot,
            candidates: candidates(
                candidateCount,
                primaryReference: primaryReference
            )
        )
    }
    if let secondCandidates {
        slots[1] = .init(index: 1, candidates: secondCandidates)
    } else if let secondReference {
        slots[1] = .init(index: 1, candidates: [
            .init(reference: secondReference, provenance: .instance),
        ])
    }
    if let textureSlotsOverride {
        slots = textureSlotsOverride
    }
    return Template.validated(
        textureSlots: slots,
        combos: comboValues.map { .init(name: $0.key, value: $0.value) },
        inheritedInactiveCombos: inheritedInactiveCombos,
        uniformDeclarations: uniformDeclarations,
        renderState: renderState,
        graphRole: .init(
            effectInput: effectInputGraphTextureRole,
            effectOutput: .effectOutput,
            nodeTarget: .effectOutput,
            bindings: graphBindingsOverride ?? (includePrimaryCandidate
                ? [.init(slot: slot, texture: primaryGraphTextureRole)] : [])
        ),
        previousBlurredCompositeGenericOwnerEligible:
            previousBlurredCompositeGenericOwnerEligible,
        effectContext: effectContext,
        compatibilityTarget: compatibilityTarget,
        shaderContract: shader,
        diagnosticProvenance: .init(
            nodeIndex: 0,
            authoredShaderPath: shader.identity,
            contractIdentity: shader.identity,
            contractCanonicalSHA256: shader.canonicalSHA256,
            textureSources: [],
            uniformSources: []
        )
    )!
}

func effectProjectionRequirementToken(
    _ hostUniform: String
) -> String {
    let shader = contract(
        revision: "effect-projection-requirement-\(hostUniform)",
        uniformMetadata: nil,
        semanticProbes: false,
        vertexSourceOverride: """
        attribute vec3 a_Position;
        attribute vec2 a_TexCoord;
        varying vec2 v_TexCoord;
        uniform mat4 \(hostUniform);
        void main() {
            v_TexCoord = a_TexCoord;
            gl_Position = mul(vec4(a_Position, 1.0), \(hostUniform));
        }
        """
    )
    let admitted = template(shader)
    let cache: SceneResolvedMaterialVariantCache
    switch SceneResolvedMaterialVariantCache.launchValidated(
        template: admitted,
        maximumVariantCount: 1
    ) {
    case let .success(value):
        cache = value
    case let .failure(failure):
        return "launch-failed:\(String(describing: failure))"
    }
    switch cache.precompileLaunchEnvelope(
        implicitFramebufferIdentity: nil
    ) {
    case .success:
        break
    case let .failure(failure):
        return "precompile-failed:\(String(describing: failure))"
    }
    return cache.requiresInvertibleEffectTextureProjection
        ? "required"
        : "unrequired"
}

func compatibilityTargetTextureCandidateTokens() -> [String: Any] {
    let shader = contract(
        revision: "compatibility-target-texture-candidate",
        vertexSourceOverride: """
        #if HLSL
        attribute vec3 a_Position;
        attribute vec2 a_TexCoord;
        varying vec2 v_TexCoord;
        void main() {
            v_TexCoord = a_TexCoord;
            gl_Position = vec4(a_Position, 1.0);
        }
        #elif GLSL
        attribute vec3 a_Position;
        void main() { gl_Position = vec4(a_Position.xy, 0.0, 1.0); }
        #endif
        """,
        fragmentSourceOverride: """
        #if HLSL
        varying vec2 v_TexCoord;
        uniform sampler2D g_Texture0; // {"material":"framebuffer"}
        void main() {
            gl_FragColor = texSample2D(g_Texture0, v_TexCoord);
        }
        #elif GLSL
        varying vec2 v_TexCoord;
        uniform sampler2D g_Texture7; // {"material":"mobile"}
        void main() {
            gl_FragColor = texSample2D(g_Texture7, v_TexCoord);
        }
        #endif
        """
    )
    let unprofiled = template(shader)
    let unprofiledReachabilityRejected: Bool
    do {
        _ = try SceneResolvedMaterialShaderSchema.reachableSamplers(
            unprofiled,
            implicitFramebufferIdentity: graphTexture()
        )
        unprofiledReachabilityRejected = false
    } catch {
        unprofiledReachabilityRejected = true
    }

    let target = SceneShaderCompatibilityTarget.windowsDX11ShaderModel4
    let profiled = template(shader, compatibilityTarget: target)
    guard let bootstrap = try? SceneResolvedMaterialShaderSchema
            .bootstrapSamplers(profiled),
          let reachable = try? SceneResolvedMaterialShaderSchema
            .reachableSamplers(
                profiled,
                implicitFramebufferIdentity: graphTexture()
            ),
          case let .success(cache) = SceneResolvedMaterialVariantCache
            .launchValidated(template: profiled, maximumVariantCount: 8),
          case .success = cache.precompileLaunchEnvelope(
            implicitFramebufferIdentity: graphTexture()
          ) else {
        return ["setup": "failed"]
    }
    let snapshot = cache.launchEnvelopeCapabilitySnapshot()
    let dependencies = Set(snapshot.variants.flatMap {
        $0.preparedShader.all.flatMap(\.compatibilityMacroDependencies)
    })
    let targets = Set(snapshot.variants.flatMap {
        $0.preparedShader.all.map(\.compatibilityTarget)
    })

    let branchInsensitive = template(
        contract(revision: "branch-insensitive-water-wave-sibling"),
        compatibilityTarget: target
    )
    guard case let .success(branchInsensitiveCache) =
            SceneResolvedMaterialVariantCache.launchValidated(
                template: branchInsensitive,
                maximumVariantCount: 8
            ),
          case .success = branchInsensitiveCache.precompileLaunchEnvelope(
            implicitFramebufferIdentity: graphTexture()
          ) else {
        return ["setup": "branch-insensitive-failed"]
    }
    let branchInsensitiveDependencies = branchInsensitiveCache
        .launchEnvelopeCapabilitySnapshot().variants.flatMap {
            $0.preparedShader.all.flatMap(\.compatibilityMacroDependencies)
        }
    return [
        "unprofiledReachabilityRejected": unprofiledReachabilityRejected,
        "bootstrapSlots": bootstrap.keys.sorted(),
        "reachableSlots": reachable.keys.sorted(),
        "programVariantCount": snapshot.variants.count,
        "targets": targets.map(\.rawValue).sorted(),
        "dependencies": dependencies.sorted(),
        "branchInsensitiveDependencies": branchInsensitiveDependencies,
    ]
}

func texture(
    _ device: MTLDevice,
    pixelFormat: MTLPixelFormat = .rgba8Unorm,
    size: CGSize = CGSize(width: 2, height: 2)
) -> MTLTexture {
    let descriptor = MTLTextureDescriptor.texture2DDescriptor(
        pixelFormat: pixelFormat,
        width: Int(size.width),
        height: Int(size.height),
        mipmapped: false
    )
    descriptor.storageMode = .shared
    descriptor.usage = .shaderRead
    return device.makeTexture(descriptor: descriptor)!
}

func publication(
    _ device: MTLDevice,
    requestIdentity: SceneFrameTextureIdentity,
    purpose: SceneTextureLoadPurpose = .premultipliedColor,
    content: SceneTextureContent = .color(.resolved(.premultipliedAlpha)),
    candidateGeneration: UInt64 = 1,
    contentGeneration: UInt64 = 1,
    sampling: SceneTextureSampling = .directImageFallback,
    pixelFormat: MTLPixelFormat = .rgba8Unorm,
    authoredFormat: SceneShaderTextureFormat? = nil,
    physicalSize: CGSize = CGSize(width: 2, height: 2),
    mappedSize: CGSize = CGSize(width: 2, height: 2),
    uvTransform: SceneTextureUVTransform = .identity,
    candidateIdentity: SceneTextureResourceIdentity = .provider(.video(
        layerID: fixtureLayerID,
        lifecycleEpoch: 1
    ))
) -> SceneTextureProviderPublication {
    .init(
        requestIdentity: requestIdentity,
        candidate: .init(
            texture: texture(
                device,
                pixelFormat: pixelFormat,
                size: physicalSize
            ),
            identity: candidateIdentity,
            generation: .provider(contentGeneration: candidateGeneration),
            purpose: purpose,
            content: content,
            physicalSize: physicalSize,
            mappedSize: mappedSize,
            uvTransform: uvTransform,
            sampling: sampling,
            authoredFormat: authoredFormat
        ),
        contentGeneration: contentGeneration
    )
}

enum SnapshotKind {
    case ready
    case absent
    case missing
    case pending
    case unavailable
    case incomplete
    case straightGraphColor
    case purposeMismatch
    case unresolvedColor
    case data
    case unsupportedSampler
}

func snapshot(
    _ device: MTLDevice,
    kind: SnapshotKind = .ready,
    frameIndex: UInt64 = 1,
    additionalEntries: [
        SceneFrameTextureIdentity: SceneFrameTextureLookupStatus
    ] = [:]
) -> SceneFrameTextureRegistrySnapshot {
    let identity = SceneFrameTextureIdentity.graph(graphTexture())
    let status: SceneFrameTextureLookupStatus?
    switch kind {
    case .ready:
        status = .ready(.init(
            publication: publication(device, requestIdentity: identity),
            resourceGeneration: 1
        ))
    case .absent:
        status = .absent
    case .missing:
        status = nil
    case .pending:
        status = .pending
    case .unavailable:
        status = .unavailable
    case .incomplete:
        status = .incomplete(.publication(
            publication(
                device,
                requestIdentity: identity,
                candidateGeneration: 1,
                contentGeneration: 2
            ),
            resourceGeneration: 1
        ))
    case .straightGraphColor:
        status = .ready(.init(
            publication: publication(
                device,
                requestIdentity: identity,
                purpose: .straightAlbedo,
                content: .color(.resolved(.straightAlpha))
            ),
            resourceGeneration: 1
        ))
    case .purposeMismatch:
        // A supported straight graph must carry its matching purpose.
        // Relabeling those bytes as PMA is incomplete publication metadata.
        status = .ready(.init(
            publication: publication(
                device,
                requestIdentity: identity,
                purpose: .premultipliedColor,
                content: .color(.resolved(.straightAlpha))
            ),
            resourceGeneration: 1
        ))
    case .unresolvedColor:
        status = .incomplete(.publication(
            publication(
                device,
                requestIdentity: identity,
                content: .color(.unresolved)
            ),
            resourceGeneration: 1
        ))
    case .data:
        status = .ready(.init(
            publication: publication(
                device,
                requestIdentity: identity,
                purpose: .noise,
                content: .data
            ),
            resourceGeneration: 1
        ))
    case .unsupportedSampler:
        status = .ready(.init(
            publication: publication(
                device,
                requestIdentity: identity,
                sampling: .init(texFlags: 8)
            ),
            resourceGeneration: 1
        ))
    }
    var entries = additionalEntries
    if let status { entries[identity] = status }
    return .init(
        frameEpoch: 1,
        frameIndex: frameIndex,
        entries: entries
    )
}

func readyStatus(
    _ device: MTLDevice,
    identity: SceneFrameTextureIdentity,
    purpose: SceneTextureLoadPurpose,
    content: SceneTextureContent,
    physicalSize: CGSize = CGSize(width: 2, height: 2),
    mappedSize: CGSize = CGSize(width: 2, height: 2),
    uvTransform: SceneTextureUVTransform = .identity
) -> SceneFrameTextureLookupStatus {
    .ready(.init(
        publication: publication(
            device,
            requestIdentity: identity,
            purpose: purpose,
            content: content,
            candidateGeneration: 7,
            contentGeneration: 7,
            physicalSize: physicalSize,
            mappedSize: mappedSize,
            uvTransform: uvTransform
        ),
        resourceGeneration: 7
    ))
}

func uniformInputs(parallax: SIMD2<Float> = SIMD2(0.5, -0.25)) -> SceneAuthoredShaderUniformInputs {
    .init(
        frameIndex: 1,
        renderSize: CGSize(width: 640, height: 360),
        screenSize: CGSize(width: 1920, height: 1080),
        modelViewProjection: matrix_identity_float4x4,
        layerModelMatrix: layerModelMatrix,
        effectOutputModelViewProjection: effectOutputModelViewProjection,
        effectTextureProjectionMatrix: effectProjectionInverse.inverse,
        effectTextureProjectionMatrixInverse: effectProjectionInverse,
        sceneTime: 2,
        dayTime: 0.5,
        frameTime: 1 / 60,
        pointerCurrentNDC: SIMD2(0.25, -0.5),
        pointerPreviousNDC: SIMD2.zero,
        parallaxPositionNDC: parallax
    )
}

func frameInputs(
    frameIndex: UInt64,
    primaryButtonIsDown: Bool = false,
    audioSpectrum: SceneAuthoredShaderAudioSpectrumInputs = .silent
) -> SceneAuthoredShaderFrameInputs {
    .init(
        frameIndex: frameIndex,
        screenSize: CGSize(width: 1920, height: 1080),
        sceneTime: 2,
        dayTime: 0.5,
        frameTime: 1 / 60,
        pointerCurrentNDC: SIMD2(0.25, -0.5),
        pointerPreviousNDC: .zero,
        pointerPrimaryButtonDown: primaryButtonIsDown,
        parallaxPositionNDC: SIMD2(0.5, -0.25),
        audioSpectrum: audioSpectrum
    )
}

func dynamicSnapshot(
    frameIndex: UInt64,
    source: SceneDynamicSource?,
    tintValue: SceneDynamicValue = .vector3(1, 0.5, 0.25),
    authoredTintValue: SceneDynamicValue = .vector3(1, 0.5, 0.25),
    alphaValue: SceneDynamicValue = .scalar(0.25),
    authoredAlphaValue: SceneDynamicValue = .scalar(1),
    scaleValue: SceneDynamicValue = .scalar(0.6),
    authoredScaleValue: SceneDynamicValue = .scalar(1),
    userPropertyScaleRange: ClosedRange<Double>? = nil
) -> SceneDynamicSnapshot {
    let tintTarget = SceneDynamicTarget.effectConstant(
        layerID: fixtureLayerID,
        effectIndex: 0,
        passIndex: 0,
        name: "Tint"
    )
    let alphaTarget = SceneDynamicTarget.effectConstant(
        layerID: fixtureLayerID,
        effectIndex: 0,
        passIndex: 0,
        name: "alpha"
    )
    let scaleTarget = SceneDynamicTarget.effectConstant(
        layerID: fixtureLayerID,
        effectIndex: 0,
        passIndex: 0,
        name: "scale"
    )
    var user: [SceneDynamicTarget: SceneDynamicValue] = [:]
    var timeline: [SceneDynamicTarget: SceneDynamicValue] = [:]
    var script: [SceneDynamicTarget: SceneDynamicValue] = [:]
    switch source {
    case .userProperty:
        user[tintTarget] = tintValue
        user[alphaTarget] = alphaValue
        user[scaleTarget] = scaleValue
    case .timeline:
        timeline[tintTarget] = tintValue
        timeline[alphaTarget] = alphaValue
        timeline[scaleTarget] = scaleValue
    case .sceneScript:
        script[tintTarget] = tintValue
        script[alphaTarget] = alphaValue
        script[scaleTarget] = scaleValue
    case .authored, nil: break
    }
    return SceneDynamicSnapshotResolver().resolve(
        frameIndex: frameIndex,
        generation: 1,
        definitions: [
            .init(
                target: tintTarget,
                valueType: authoredTintValue.valueType,
                authoredValue: authoredTintValue
            ),
            .init(
                target: alphaTarget,
                valueType: authoredAlphaValue.valueType,
                authoredValue: authoredAlphaValue
            ),
            .init(
                target: scaleTarget,
                valueType: authoredScaleValue.valueType,
                authoredValue: authoredScaleValue,
                userPropertyNumericRange: userPropertyScaleRange
            ),
        ],
        userValues: user,
        timelineValues: timeline,
        sceneScriptValues: script
    ).snapshot
}

func finalize(
    shader: SceneShaderContract,
    device: MTLDevice,
    slot: Int = 0,
    candidateCount: Int = 1,
    includePrimaryCandidate: Bool = true,
    primaryReference: Template.TextureReference = .graph(graphTexture()),
    primaryGraphTextureRole: Template.GraphTextureRole = .layerSource,
    graphBindingsOverride: [Template.GraphBindingRole]? = nil,
    secondReference: Template.TextureReference? = nil,
    secondCandidates: [Template.TextureCandidate]? = nil,
    additionalEntries: [
        SceneFrameTextureIdentity: SceneFrameTextureLookupStatus
    ] = [:],
    uniformDeclarations: [Template.UniformDeclaration] = [],
    snapshotKind: SnapshotKind = .ready,
    textureFrameIndex: UInt64 = 1,
    dynamicFrameIndex: UInt64 = 1,
    frameInputIndex: UInt64 = 1,
    primaryButtonIsDown: Bool = false,
    dynamicSource: SceneDynamicSource? = nil,
    dynamicTintValue: SceneDynamicValue = .vector3(1, 0.5, 0.25),
    authoredTintValue: SceneDynamicValue = .vector3(1, 0.5, 0.25),
    dynamicAlphaValue: SceneDynamicValue = .scalar(0.25),
    authoredAlphaValue: SceneDynamicValue = .scalar(1),
    dynamicScaleValue: SceneDynamicValue = .scalar(0.6),
    authoredScaleValue: SceneDynamicValue = .scalar(1),
    userPropertyScaleRange: ClosedRange<Double>? = nil,
    renderState: SceneMaterialRenderState = state(),
    resolvedLayerModelMatrix: simd_float4x4 = layerModelMatrix,
    implicitFramebufferIdentity: Graph.TextureIdentity? = nil,
    audioSpectrum: SceneAuthoredShaderAudioSpectrumInputs = .silent,
    variantCache: SceneResolvedMaterialVariantCache? = nil,
    outputStorage: Program.OutputStorage = .color,
    graphTextureFormatFacts: [
        Graph.TextureIdentity: SceneShaderTextureFormat
    ] = [:],
    textureSlotsOverride: [Template.TextureSlot?]? = nil,
    effectContext: Template.EffectContext? = nil,
    assetLaunchStatesOverride: [SceneAssetTextureIdentity: SceneAssetTextureLaunchState]? = nil
) -> Result<Program, SceneResolvedMaterialFailure> {
    let frame = SceneResolvedMaterialFrameSnapshot.validated(
        textureSnapshot: snapshot(
            device,
            kind: snapshotKind,
            frameIndex: textureFrameIndex,
            additionalEntries: additionalEntries
        ),
        dynamicSnapshot: dynamicSnapshot(
            frameIndex: dynamicFrameIndex,
            source: dynamicSource,
            tintValue: dynamicTintValue,
            authoredTintValue: authoredTintValue,
            alphaValue: dynamicAlphaValue,
            authoredAlphaValue: authoredAlphaValue,
            scaleValue: dynamicScaleValue,
            authoredScaleValue: authoredScaleValue,
            userPropertyScaleRange: userPropertyScaleRange
        ),
        frameInputs: frameInputs(
            frameIndex: frameInputIndex,
            primaryButtonIsDown: primaryButtonIsDown,
            audioSpectrum: audioSpectrum
        )
    )
    switch frame {
    case let .failure(failure):
        return .failure(failure)
    case let .success(frame):
        let input = frame.finalizationInput(
            template: template(
                shader,
                slot: slot,
                candidateCount: candidateCount,
                includePrimaryCandidate: includePrimaryCandidate,
                primaryReference: primaryReference,
                primaryGraphTextureRole: primaryGraphTextureRole,
                graphBindingsOverride: graphBindingsOverride,
                secondReference: secondReference,
                secondCandidates: secondCandidates,
                uniformDeclarations: uniformDeclarations,
                renderState: renderState,
                textureSlotsOverride: textureSlotsOverride,
                effectContext: effectContext
            ),
            layerID: 9001,
            renderSize: CGSize(width: 640, height: 360),
            modelViewProjection: matrix_identity_float4x4,
            layerModelMatrix: resolvedLayerModelMatrix,
            effectOutputModelViewProjection: effectOutputModelViewProjection,
            effectTextureProjectionMatrixInverse: effectProjectionInverse,
            implicitFramebufferIdentity: implicitFramebufferIdentity
        )
        let cache: SceneResolvedMaterialVariantCache
        if let variantCache {
            cache = variantCache
        } else {
            switch SceneResolvedMaterialVariantCache.launchValidated(
                template: input.template,
                maximumVariantCount: 16
            ) {
            case let .success(value): cache = value
            case let .failure(failure): return .failure(failure)
            }
            let assetStatePairs: [(
                SceneAssetTextureIdentity, SceneAssetTextureLaunchState
            )] = input.textureSnapshot.entries.compactMap { identity, status in
                    guard case let .asset(assetIdentity) = identity else { return nil }
                    _ = status
                    let content: SceneTextureContent = switch assetIdentity.purpose {
                    case .premultipliedColor:
                        .color(.resolved(.premultipliedAlpha))
                    case .straightAlbedo:
                        .color(.resolved(.straightAlpha))
                    case .preservedChannels, .mask, .noise, .flow, .phase,
                         .normal, .depth, .lookupTable:
                        .data
                    }
                    return (assetIdentity, .ready(content))
                }
            let assetStates = assetLaunchStatesOverride ?? Dictionary(uniqueKeysWithValues: assetStatePairs)
            switch cache.precompileLaunchEnvelope(
                implicitFramebufferIdentity: implicitFramebufferIdentity,
                outputStorage: outputStorage,
                graphTextureFormatFacts: graphTextureFormatFacts,
                assetStates: assetStates
            ) {
            case .success: break
            case .failure(.capacity):
                return .failure(.init(
                    phase: .preparation,
                    code: .shaderPreparationFailed,
                    details: ["variant-cache-capacity"]
                ))
            case let .failure(.material(failure)):
                return .failure(failure)
            }
        }
        return SceneResolvedMaterialProgramFinalizer.finalize(
            input,
            variantCache: cache,
            outputStorage: outputStorage
        )
    }
}

func failureToken(
    _ result: Result<Program, SceneResolvedMaterialFailure>
) -> String {
    switch result {
    case .success:
        return "success"
    case let .failure(failure):
        return "\(failure.phase.rawValue)/\(failure.code.rawValue)"
    }
}

func visualFallbackToken(
    _ result: Result<Program, SceneResolvedMaterialFailure>
) -> String {
    switch result {
    case .success:
        return "success"
    case let .failure(failure):
        return failure.effectLocalVisualFallback?.rawValue ?? "none"
    }
}

func sceneResolvedMaterialFixtureFloat(_ data: Data, at offset: Int) -> Float {
    data.withUnsafeBytes {
        $0.loadUnaligned(fromByteOffset: offset, as: Float.self)
    }
}
