import Foundation
import Metal
import simd

private typealias Graph = SceneAuthoredEffectRenderPlan
private typealias Plan = SceneGraphRenderTargetPlan
private typealias State = SceneGraphExecutionState
private typealias Template = SceneResolvedMaterialTemplate

private let layerID = 42
private let effect = Graph.EffectKey(
    layerID: layerID, effectIndex: 0, descriptorID: "fixture-effect"
)
private let input = Graph.TextureIdentity(
    kind: .layerSource, layerID: layerID, effect: nil, name: nil
)
private let output = Graph.TextureIdentity(
    kind: .effectOutput, layerID: layerID, effect: effect, name: nil
)
private let first = Graph.TextureIdentity(
    kind: .framebuffer, layerID: layerID, effect: effect, name: "first"
)
private let second = Graph.TextureIdentity(
    kind: .framebuffer, layerID: layerID, effect: effect, name: "second"
)
private let extent = Plan.PixelExtent(width: 2, height: 2)

private func logical(
    _ identity: Graph.TextureIdentity,
    format: Plan.TextureFormat = .rgbaBackbuffer,
    addressMode: Plan.UVAddressMode = .clampToEdge
) -> Plan.LogicalTarget {
    .init(
        identity: identity,
        extent: extent,
        format: format,
        addressMode: addressMode,
        isUnique: false,
        lifetime: .init(
            firstWriteNodeIndex: 0,
            lastWriteNodeIndex: 3,
            firstReadNodeIndex: 1,
            lastReadNodeIndex: 3
        ),
        initialClear: nil
    )
}

private func targetPlan(
    format: Plan.TextureFormat = .rgbaBackbuffer,
    addressMode: Plan.UVAddressMode = .clampToEdge
) -> Plan {
    .testingPlan(
        layerID: layerID,
        input: input,
        output: output,
        inputExtent: extent,
        logicalTargets: [
            logical(first, format: format, addressMode: addressMode),
            logical(second, format: format, addressMode: addressMode),
        ]
    )
}

private func makeLease(
    _ device: MTLDevice,
    format: Plan.TextureFormat = .rgbaBackbuffer,
    addressMode: Plan.UVAddressMode = .clampToEdge
) -> SceneGraphRenderTargetLease {
    let table: SceneGraphRenderTargetTable
    switch SceneGraphRenderTargetTable.make(
        plan: targetPlan(format: format, addressMode: addressMode),
        device: device,
        byteBudget: 1_024
    ) {
    case .success(let value): table = value
    case .failure(let failure):
        fatalError("table failed: \(failure.rawValue)")
    }
    var ordinal = 0
    switch SceneGraphRenderTargetLease.make(
        table: table,
        generation: 7,
        tokenForTexture: { _ in
            defer { ordinal += 1 }
            return .init(rawValue: "physical-\(ordinal)")
        }
    ) {
    case .success(let value): return value
    case .failure(let failure):
        fatalError("lease failed: \(failure.rawValue)")
    }
}

private func require(
    _ result: Result<SceneFrameTextureResource, SceneGraphRenderTargetLease.PublicationFailure>,
    line: Int = #line
) -> SceneFrameTextureResource {
    switch result {
    case .success(let value): return value
    case .failure(let failure):
        fatalError("publication failed at fixture line \(line): \(failure.rawValue)")
    }
}

private func failure(
    _ result: Result<SceneFrameTextureResource, SceneGraphRenderTargetLease.PublicationFailure>
) -> String {
    switch result {
    case .success: return "success"
    case .failure(let value): return value.rawValue
    }
}

private func forgedGraphResource(
    _ resource: SceneFrameTextureResource,
    purpose: SceneTextureLoadPurpose,
    authoredFormat: SceneShaderTextureFormat?
) -> SceneFrameTextureResource {
    let candidate = resource.publication.candidate
    return .init(
        publication: .init(
            requestIdentity: resource.publication.requestIdentity,
            candidate: .init(
                texture: candidate.texture,
                identity: candidate.identity,
                generation: candidate.generation,
                purpose: purpose,
                content: candidate.content,
                physicalSize: candidate.physicalSize,
                mappedSize: candidate.mappedSize,
                uvTransform: candidate.uvTransform,
                sampling: candidate.sampling,
                authoredFormat: authoredFormat
            ),
            contentGeneration: resource.publication.contentGeneration
        ),
        resourceGeneration: resource.resourceGeneration
    )
}

private let vertexSource = """
attribute vec3 a_Position;
attribute vec2 a_TexCoord;
varying vec2 v_TexCoord;
void main() {
    v_TexCoord = a_TexCoord;
    gl_Position = vec4(a_Position, 1.0);
}
"""

private let fragmentSource = """
varying vec2 v_TexCoord;
uniform sampler2D g_Texture0;
void main() {
    gl_FragColor = texSample2D(g_Texture0, v_TexCoord);
}
"""

private func shaderContract() -> SceneShaderContract {
    func stage(
        _ kind: SceneShaderContract.StageKind,
        path: String,
        source: String
    ) -> SceneShaderContract.Stage {
        let parsed = SceneShaderContractSourceParser().parse(
            source, stageRelativePath: path
        )
        return .init(
            kind: kind,
            relativePath: path,
            source: source,
            rawSHA256: SceneShaderStableDigest.hash(Data(source.utf8)),
            includes: parsed.includes,
            annotations: parsed.annotations,
            declarations: parsed.declarations
        )
    }
    let stages = [
        stage(.vertex, path: "fixture/root.vert", source: vertexSource),
        stage(.fragment, path: "fixture/root.frag", source: fragmentSource),
    ]
    let sourceGraph = SceneShaderSourceGraph(
        roots: [
            .init(label: "vertex", virtualPath: "fixture/root.vert"),
            .init(label: "fragment", virtualPath: "fixture/root.frag"),
        ],
        nodes: stages.map {
            .init(
                virtualPath: $0.relativePath,
                provenance: .package,
                source: $0.source,
                rawSHA256: $0.rawSHA256,
                byteCount: $0.source.utf8.count
            )
        },
        edges: [],
        diagnostics: [],
        dependencySHA256: "fixture-dependency"
    )
    return .init(
        identity: "fixture/shader",
        sourceKind: .authoredSource,
        stages: stages,
        diagnostics: [],
        canonicalSHA256: "fixture-contract",
        sourceGraph: sourceGraph
    )
}

private func template() -> Template {
    let contract = shaderContract()
    var slots = Array<Template.TextureSlot?>(repeating: nil, count: 8)
    slots[0] = .init(index: 0, candidates: [
        .init(reference: .graph(input), provenance: .explicitBinding),
    ])
    return Template.validated(
        textureSlots: slots,
        combos: [],
        uniformDeclarations: [],
        renderState: SceneMaterialRenderState.compile(
            blending: "normal",
            depthTest: "disabled",
            depthWrite: "disabled",
            cullMode: "nocull",
            alphaWriting: nil
        )!,
        graphRole: .init(
            effectInput: .layerSource,
            effectOutput: .effectOutput,
            nodeTarget: .effectOutput,
            bindings: [.init(slot: 0, texture: .layerSource)]
        ),
        shaderContract: contract,
        diagnosticProvenance: .init(
            nodeIndex: 0,
            authoredShaderPath: contract.identity,
            contractIdentity: contract.identity,
            contractCanonicalSHA256: contract.canonicalSHA256,
            textureSources: [],
            uniformSources: []
        )
    )!
}

private func resolveProgram(
    snapshot: SceneFrameTextureRegistrySnapshot
) -> Result<SceneResolvedMaterialProgram, SceneResolvedMaterialFailure> {
    let frame = SceneResolvedMaterialFrameSnapshot.validated(
        textureSnapshot: snapshot,
        dynamicSnapshot: .empty(frameIndex: snapshot.frameIndex),
        frameInputs: .init(
            frameIndex: snapshot.frameIndex,
            screenSize: CGSize(width: 2, height: 2),
            sceneTime: 0,
            dayTime: 0,
            frameTime: 1 / 60,
            pointerCurrentNDC: .zero,
            pointerPreviousNDC: .zero
        )
    )
    guard case .success(let value) = frame else {
        fatalError("frame snapshot failed")
    }
    let input = value.finalizationInput(
        template: template(),
        layerID: 9001,
        renderSize: CGSize(width: 2, height: 2),
        modelViewProjection: matrix_identity_float4x4,
        layerModelMatrix: matrix_identity_float4x4,
        effectOutputModelViewProjection: matrix_identity_float4x4,
        effectTextureProjectionMatrixInverse: matrix_identity_float4x4
    )
    guard case let .success(cache) = SceneResolvedMaterialVariantCache.launchValidated(
        template: input.template,
        maximumVariantCount: 16
    ), case .success = cache.precompileLaunchEnvelope(
        implicitFramebufferIdentity: input.implicitFramebufferIdentity
    ) else {
        fatalError("launch envelope rejected")
    }
    return SceneResolvedMaterialProgramFinalizer.finalize(
        input,
        variantCache: cache
    )
}

private func makeWrongTexture(_ device: MTLDevice) -> MTLTexture {
    let descriptor = MTLTextureDescriptor.texture2DDescriptor(
        pixelFormat: .bgra8Unorm,
        width: 2,
        height: 2,
        mipmapped: false
    )
    descriptor.usage = .shaderRead
    return device.makeTexture(descriptor: descriptor)!
}

private func issuerProjection(
    _ device: MTLDevice, table: SceneGraphRenderTargetTable
) -> (checks: [String: Bool], records: [[String: Any]]) {
    let textures = table.orderedPhysicalTextures
    let issuer = SceneOffscreenTextureIdentityIssuer()
    let emptyRejected = issuer.issue(textures: []) == nil
    let duplicateRejected = issuer.issue(textures: [textures[0], textures[0]]) == nil
    guard let initial = issuer.issue(textures: textures),
          let generationOnly = issuer.issueGeneration(),
          let reordered = issuer.issue(textures: Array(textures.reversed())),
          let independent = SceneOffscreenTextureIdentityIssuer().issue(textures: textures),
          case .success(let lease) = SceneGraphRenderTargetLease.make(
              table: table, generation: initial.generation,
              tokenForTexture: { initial.token(for: $0) }
          ) else { fatalError("physical issuer failed") }
    let initialTokens = textures.compactMap { initial.token(for: $0) }
    let reorderedTokens = textures.compactMap { reordered.token(for: $0) }
    let independentTokens = textures.compactMap { independent.token(for: $0) }
    let tokenGroups = [initialTokens, reorderedTokens, independentTokens]
    let checks = [
        "emptyRejected": emptyRejected,
        "duplicateObjectRejected": duplicateRejected,
        "rejectionsDoNotConsumeGeneration": initial.generation == 1,
        "generationOnlyIsOrdered": generationOnly == 2 && reordered.generation == 3,
        "independentGeneration": independent.generation == 1,
        "oneTokenPerObject": tokenGroups.allSatisfy {
            $0.count == textures.count && Set($0).count == textures.count
        },
        "generationsDoNotAlias": Set(initialTokens).isDisjoint(with: reorderedTokens),
        "issuersDoNotAlias": Set(initialTokens + reorderedTokens).isDisjoint(with: independentTokens),
        "unknownObjectHasNoToken": initial.token(for: makeWrongTexture(device)) == nil,
        "leasePreservesPhysicalAtoms": lease.generation == initial.generation
            && lease.fullFramePair.first != lease.fullFramePair.second
            && zip(textures, initialTokens).allSatisfy {
                lease.texturesByToken[$0.1] === $0.0
            },
    ]
    let records: [[String: Any]] = [initial, reordered, independent].enumerated().map { index, identity in
        ["issuer": index == 2 ? "independent" : "shared",
         "generation": identity.generation,
         "tokensInTextureOrder": textures.map { identity.token(for: $0)!.rawValue }]
    }
    return (checks, records)
}

@main
private enum Harness {
    static func main() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            print("{\"metalAvailable\":false}")
            return
        }
        let lease = makeLease(device)
        let issued = issuerProjection(device, table: lease.table)
        let r8Lease = makeLease(device, format: .r8)
        let rg88Lease = makeLease(device, format: .rg88)
        let r16Lease = makeLease(device, format: .r16f)
        let rg16Lease = makeLease(device, format: .rg1616f)
        let rgbaDataLease = makeLease(device, format: .rgba8888)
        let floatLease = makeLease(device, format: .rgba16f)
        let repeatLease = makeLease(device, addressMode: .repeatWrap)
        let r8RepeatLease = makeLease(
            device,
            format: .r8,
            addressMode: .repeatWrap
        )
        let aliasMapping: [Graph.TextureIdentity: MTLTexture] = [
            input: lease.table.inputTexture,
            first: lease.table.texture(for: first)!,
            second: lease.table.texture(for: second)!,
            output: lease.table.inputTexture,
        ]
        guard case .success(let aliasTable) = SceneGraphRenderTargetTable.makeMapped(
            plan: lease.table.plan,
            device: device,
            texturesByIdentity: aliasMapping,
            fullFramePair: .init(
                first: lease.table.inputTexture,
                second: lease.table.outputTexture
            ),
            expectsInputOutputAlias: true,
            makeInputsDigest: 0
        ) else { fatalError("alias table failed") }
        let aliasTokens = Dictionary(uniqueKeysWithValues:
            aliasTable.orderedPhysicalTextures.enumerated().map {
                (ObjectIdentifier($0.element), State.PhysicalToken(
                    rawValue: "alias-physical-\($0.offset)"
                ))
            }
        )
        guard case .success(let aliasLease) = SceneGraphRenderTargetLease.make(
            table: aliasTable,
            generation: 8,
            tokenForTexture: { aliasTokens[ObjectIdentifier($0)] }
        ), let aliasOutput = aliasLease.allocation.resources[output],
        let aliasInput = aliasLease.allocation.resources[input] else {
            fatalError("alias lease failed")
        }
        let aliasOutputResource = require(aliasLease.fullFrameResource(
            for: output,
            member: .zero,
            contentGeneration: 12,
            fragmentColorRepresentation: .resolved(.premultipliedAlpha)
        ))
        let aliasRotatedInputResource = require(aliasLease.fullFrameResource(
            for: input,
            member: .one,
            contentGeneration: 13,
            fragmentColorRepresentation: .resolved(.premultipliedAlpha)
        ))
        let aliasedEndpointPublication = aliasInput.token == aliasOutput.token
            && aliasLease.fullFramePair.first != aliasLease.fullFramePair.second
            && aliasOutputResource.publication.candidate.texture
                === aliasTable.inputTexture
            && aliasRotatedInputResource.publication.candidate.texture
                === aliasTable.fullFramePair.second
        var nonIdempotentOrdinal = 0
        guard case .success(let resolvedOnceLease) = SceneGraphRenderTargetLease.make(
            table: aliasTable,
            generation: 9,
            tokenForTexture: { _ in
                defer { nonIdempotentOrdinal += 1 }
                return .init(rawValue: "resolved-once-\(nonIdempotentOrdinal)")
            }
        ), let resolvedOnceInput = resolvedOnceLease.allocation.resources[input],
        let resolvedOnceOutput = resolvedOnceLease.allocation.resources[output] else {
            fatalError("non-idempotent token provider failed")
        }
        let nonIdempotentProviderResolvedOnce = nonIdempotentOrdinal
                == aliasTable.residentTextureCount
            && resolvedOnceInput.token == resolvedOnceOutput.token
            && resolvedOnceLease.fullFramePair.first == resolvedOnceInput.token
        let firstPhysical = lease.allocation.resources[first]!.versioned(10)
        let secondPhysical = lease.allocation.resources[second]!.versioned(11)
        let firstResource = require(lease.graphResource(
            for: first,
            versionedResource: firstPhysical,
            fragmentColorRepresentation: .resolved(.opaque)
        ))
        let secondResource = require(lease.graphResource(
            for: second,
            versionedResource: secondPhysical,
            fragmentColorRepresentation: .resolved(.premultipliedAlpha)
        ))
        let swappedFirst = require(lease.graphResource(
            for: first,
            versionedResource: secondPhysical,
            fragmentColorRepresentation: .resolved(.premultipliedAlpha)
        ))
        guard let baseInput = firstResource.rewrappedForGraphIdentity(input),
              let swappedInput = swappedFirst.rewrappedForGraphIdentity(input) else {
            fatalError("graph rewrap failed")
        }

        let swapPreservesPhysicalAtom =
            swappedFirst.publication.requestIdentity == .graph(first)
            && secondResource.publication.requestIdentity == .graph(second)
            && swappedFirst.publication.candidate.texture
                === secondResource.publication.candidate.texture
            && swappedFirst.publication.candidate.identity
                == secondResource.publication.candidate.identity
            && swappedFirst.publication.candidate.generation
                == secondResource.publication.candidate.generation
            && swappedFirst.publication.contentGeneration
                == secondResource.publication.contentGeneration
            && swappedFirst.resourceGeneration == secondResource.resourceGeneration

        let physicalIdentityCorrect: Bool
        switch secondResource.publication.candidate.identity {
        case let .provider(.graph(generation, token)):
            physicalIdentityCorrect = generation == lease.generation
                && token == secondPhysical.token.rawValue
        default:
            physicalIdentityCorrect = false
        }

        let base = SceneFrameTextureRegistrySnapshot(
            frameEpoch: 3,
            frameIndex: 9,
            entries: [
                .graph(input): .ready(baseInput),
                .graph(first): .absent,
            ]
        )
        guard let overlaid = base.overlayingGraphResources([
            input: swappedInput,
            first: swappedFirst,
        ]) else { fatalError("valid overlay failed") }
        let immutableOverlay = base.resource(for: .graph(input))?
                .publication.candidate.texture === firstResource.publication.candidate.texture
            && overlaid.resource(for: .graph(input))?
                .publication.candidate.texture === secondResource.publication.candidate.texture
            && overlaid.frameEpoch == base.frameEpoch
            && overlaid.frameIndex == base.frameIndex

        let programResolvedOverlay: Bool
        switch resolveProgram(snapshot: overlaid) {
        case .failure:
            programResolvedOverlay = false
        case .success(let program):
            let slot = program.textureSlots[0]
            programResolvedOverlay = slot?.registryIdentity == .graph(input)
                && slot?.resource.publication.candidate.texture
                    === secondResource.publication.candidate.texture
                && slot?.resource.publication.candidate.identity
                    == secondResource.publication.candidate.identity
                && slot?.resource.resourceGeneration
                    == secondPhysical.contentGeneration
                && slot?.resource.publication.contentGeneration
                    == secondPhysical.contentGeneration
        }

        let straightResource = try lease.graphResource(
            for: first,
            versionedResource: firstPhysical,
            fragmentColorRepresentation: .resolved(.straightAlpha)
        ).get()
        let straightRewrapped = straightResource.rewrappedForGraphIdentity(second)
        let straightPublicationPreservesRepresentation = straightResource.isCompleteGraphResource
            && straightResource.publication.candidate.purpose == .straightAlbedo
            && straightResource.publication.candidate.content == .color(.resolved(.straightAlpha))
            && straightRewrapped?.publication.candidate.content == straightResource.publication.candidate.content
            && straightRewrapped?.publication.candidate.purpose == straightResource.publication.candidate.purpose
            && straightRewrapped?.publication.texture === straightResource.publication.texture
            && straightRewrapped?.publication.candidate.identity == straightResource.publication.candidate.identity
            && straightRewrapped?.resourceGeneration == straightResource.resourceGeneration
            && straightRewrapped?.publication.requestIdentity == .graph(second)
        let straightFullFrame = try lease.fullFrameResource(
            for: input, member: .zero, contentGeneration: 1,
            fragmentColorRepresentation: .resolved(.straightAlpha)
        ).get()
        let straightNamedReference = SceneNamedTextureReference(providerLayerID: 91, variant: .primary)
        let straightNamed = SceneFrameTextureResource.reservedNamedLayerTarget(
            reference: straightNamedReference, frameEpoch: 1,
            texture: straightResource.publication.texture,
            content: .color(.resolved(.straightAlpha)))
        let unresolvedFailure = failure(lease.graphResource(
            for: first,
            versionedResource: firstPhysical,
            fragmentColorRepresentation: .unresolved
        ))
        let zeroGenerationFailure = failure(lease.graphResource(
            for: first,
            versionedResource: .init(
                token: firstPhysical.token,
                descriptor: firstPhysical.descriptor,
                contentGeneration: 0
            ),
            fragmentColorRepresentation: .resolved(.opaque)
        ))
        let unknownTokenFailure = failure(lease.graphResource(
            for: first,
            versionedResource: .init(
                token: .init(rawValue: "unknown-physical"),
                descriptor: firstPhysical.descriptor,
                contentGeneration: 1
            ),
            fragmentColorRepresentation: .resolved(.opaque)
        ))
        let wrongDescriptorFailure = failure(lease.graphResource(
            for: first,
            versionedResource: .init(
                token: secondPhysical.token,
                descriptor: .init(
                    extent: .init(width: 3, height: 2),
                    format: .rgbaBackbuffer,
                    addressMode: .clampToEdge,
                    isUnique: false,
                    initialClear: nil
                ),
                contentGeneration: 1
            ),
            fragmentColorRepresentation: .resolved(.opaque)
        ))
        let pairTokenFailure = failure(lease.graphResource(
            for: first,
            versionedResource: .init(
                token: lease.fullFramePair.first,
                descriptor: firstPhysical.descriptor,
                contentGeneration: 1
            ),
            fragmentColorRepresentation: .resolved(.opaque)
        ))
        let r8Physical = r8Lease.allocation.resources[first]!.versioned(14)
        let r8ScalarResource = require(r8Lease.graphResource(
            for: first,
            versionedResource: r8Physical,
            storedContent: .scalarRedUnorm
        ))
        let r8ScalarCandidate = r8ScalarResource.publication.candidate
        let r8ScalarPublication = r8ScalarResource.isCompleteGraphResource
            && r8ScalarCandidate.purpose == .preservedChannels
            && r8ScalarCandidate.content == .scalarRedUnorm
            && r8ScalarCandidate.pixelFormat == .r8Unorm
            && r8ScalarCandidate.authoredFormat == nil
            && r8ScalarCandidate.sampling == .directImageFallback
        let r8ScalarCannotRewrapAsLayerSource =
            r8ScalarResource.rewrappedForGraphIdentity(input) == nil
        let r8ScalarCannotRewrapAsEffectOutput =
            r8ScalarResource.rewrappedForGraphIdentity(output) == nil
        let forgedR8AuthoredFormat = forgedGraphResource(
            r8ScalarResource,
            purpose: .preservedChannels,
            authoredFormat: .r8
        )
        let forgedR8WrongAuthoredFormat = forgedGraphResource(
            r8ScalarResource,
            purpose: .preservedChannels,
            authoredFormat: .rgba8888
        )
        let forgedR8ColorPurpose = forgedGraphResource(
            r8ScalarResource,
            purpose: .premultipliedColor,
            authoredFormat: nil
        )
        let r8PublicationFailure = failure(r8Lease.graphResource(
            for: first,
            versionedResource: r8Physical,
            fragmentColorRepresentation: .resolved(.opaque)
        ))
        let channelCases: [(String, SceneGraphRenderTargetLease,
            SceneTextureContent, SceneTextureContent, MTLPixelFormat)] = [
            ("rg88", rg88Lease, .redGreenUnorm, .scalarRedUnorm, .rg8Unorm),
            ("r16", r16Lease, .scalarRedFloat16, .scalarRedUnorm, .r16Float),
            ("rg16", rg16Lease, .redGreenFloat16, .redGreenUnorm, .rg16Float),
        ]
        var channelPublicationContracts: [String: Bool] = [:]
        var channelWrongStorageFailures: [String: String] = [:]
        for (ordinal, item) in channelCases.enumerated() {
            let physical = item.1.allocation.resources[first]!
                .versioned(UInt64(16 + ordinal))
            let resource = require(item.1.graphResource(
                for: first, versionedResource: physical, storedContent: item.2
            ))
            let candidate = resource.publication.candidate
            channelPublicationContracts[item.0] = resource.isCompleteGraphResource
                && candidate.purpose == .preservedChannels
                && candidate.content == item.2 && candidate.pixelFormat == item.4
                && candidate.authoredFormat == nil
                && SceneGraphRenderTargetLease.graphSamplingMatches(
                    resource, descriptor: physical.descriptor
                )
            channelWrongStorageFailures[item.0] = failure(item.1.graphResource(
                for: first, versionedResource: physical, storedContent: item.3
            ))
        }
        let rgbaDataPhysical = rgbaDataLease.allocation.resources[first]!
            .versioned(17)
        let rgbaDataResource = require(rgbaDataLease.graphResource(
            for: first,
            versionedResource: rgbaDataPhysical,
            storedContent: .data
        ))
        let rgbaDataCandidate = rgbaDataResource.publication.candidate
        let rgbaDataPublicationContract = rgbaDataResource.isCompleteGraphResource
            && rgbaDataCandidate.purpose == .preservedChannels
            && rgbaDataCandidate.content == .data
            && rgbaDataCandidate.pixelFormat == .rgba8Unorm
            && rgbaDataCandidate.authoredFormat == nil
        let backbufferDataResource = require(lease.graphResource(
            for: first,
            versionedResource: firstPhysical,
            storedContent: .data
        ))
        let backbufferDataCandidate = backbufferDataResource.publication.candidate
        let backbufferDataPublicationContract =
            backbufferDataResource.isCompleteGraphResource
                && backbufferDataCandidate.purpose == .preservedChannels
                && backbufferDataCandidate.content == .data
                && backbufferDataCandidate.pixelFormat == .bgra8Unorm
                && backbufferDataCandidate.authoredFormat == nil
        let floatPhysical = floatLease.allocation.resources[first]!.versioned(18)
        let floatColor = require(floatLease.graphResource(
            for: first, versionedResource: floatPhysical,
            storedContent: .color(.resolved(.premultipliedAlpha))
        ))
        let floatData = require(floatLease.graphResource(
            for: first, versionedResource: floatPhysical, storedContent: .data
        ))
        let floatPublicationContract = floatColor.isCompleteGraphResource
            && floatData.isCompleteGraphResource
            && floatColor.publication.candidate.pixelFormat == .rgba16Float
            && floatData.publication.candidate.purpose == .preservedChannels
        let floatTexture = floatColor.publication.candidate.texture
        let floatBackground = SceneFrameTextureResource.sameFrameSceneBackground(
            consumerLayerID: layerID, frameEpoch: 19, texture: floatTexture
        )!
        let floatBackgroundContract = floatBackground.isCompleteSceneBackground(
            consumerLayerID: layerID, frameEpoch: 19
        ) && !floatBackground.isCompleteSceneBackground(
            consumerLayerID: layerID, frameEpoch: 20
        ) && !SceneFrameTextureResource(
            publication: floatColor.publication, resourceGeneration: 19
        ).isCompleteGraphResource
        let repeatPhysical = repeatLease.allocation.resources[first]!.versioned(15)
        let repeatResource = require(repeatLease.graphResource(
            for: first,
            versionedResource: repeatPhysical,
            fragmentColorRepresentation: .resolved(.opaque)
        ))
        let repeatPublicationContract = repeatResource.isCompleteGraphResource
            && repeatResource.publication.candidate.sampling == .linearRepeat
            && SceneGraphRenderTargetLease.graphSamplingMatches(
                repeatResource,
                descriptor: repeatPhysical.descriptor
            )
            && !SceneGraphRenderTargetLease.graphSamplingMatches(
                repeatResource,
                descriptor: firstPhysical.descriptor
            )
        let r8RepeatPhysical = r8RepeatLease.allocation.resources[first]!
            .versioned(16)
        let r8RepeatResource = require(r8RepeatLease.graphResource(
            for: first,
            versionedResource: r8RepeatPhysical,
            storedContent: .scalarRedUnorm
        ))
        let r8RepeatPublicationContract = r8RepeatResource.isCompleteGraphResource
            && r8RepeatResource.publication.candidate.sampling == .linearRepeat
            && SceneGraphRenderTargetLease.graphSamplingMatches(
                r8RepeatResource,
                descriptor: r8RepeatPhysical.descriptor
            )
            && !SceneGraphRenderTargetLease.graphSamplingMatches(
                r8RepeatResource,
                descriptor: r8Physical.descriptor
            )

        // Fixed token uniqueness belongs to the actual lease producer, rather
        // than a fabricated lease rechecked at every resource publication.
        let duplicateToken = State.PhysicalToken(rawValue: "duplicate-physical-token")
        let duplicateTokenFailure: String
        switch SceneGraphRenderTargetLease.make(
            table: lease.table,
            generation: lease.generation,
            tokenForTexture: { texture in
                if texture === firstResource.publication.texture
                    || texture === secondResource.publication.texture {
                    return duplicateToken
                }
                return lease.texturesByToken.first { $0.value === texture }?.key
            }
        ) {
        case .success: duplicateTokenFailure = "accepted"
        case .failure(let failure): duplicateTokenFailure = failure.rawValue
        }

        var wrongTextures = lease.texturesByToken
        wrongTextures[firstPhysical.token] = makeWrongTexture(device)
        let corruptLease = SceneGraphRenderTargetLease(
            table: lease.table,
            allocation: lease.allocation,
            texturesByToken: wrongTextures
        )
        let wrongTextureFailure = failure(corruptLease.graphResource(
            for: first,
            versionedResource: firstPhysical,
            fragmentColorRepresentation: .resolved(.opaque)
        ))
        let endpointViaFramebufferFailure = failure(aliasLease.graphResource(
            for: output,
            versionedResource: aliasOutput.versioned(12),
            fragmentColorRepresentation: .resolved(.premultipliedAlpha)
        ))
        let invalidFullFrameIdentityFailure = failure(aliasLease.fullFrameResource(
            for: first,
            member: .zero,
            contentGeneration: 1,
            fragmentColorRepresentation: .resolved(.opaque)
        ))
        let zeroFullFrameGenerationFailure = failure(aliasLease.fullFrameResource(
            for: input,
            member: .zero,
            contentGeneration: 0,
            fragmentColorRepresentation: .resolved(.opaque)
        ))
        let swappedPairLease = SceneGraphRenderTargetLease(
            table: aliasLease.table,
            allocation: aliasLease.allocation,
            texturesByToken: aliasLease.texturesByToken,
            fullFramePair: .init(
                first: aliasLease.fullFramePair.second,
                second: aliasLease.fullFramePair.first
            )
        )
        let wrongPairMemberFailure = failure(swappedPairLease.fullFrameResource(
            for: input,
            member: .zero,
            contentGeneration: 1,
            fragmentColorRepresentation: .resolved(.opaque)
        ))

        let incomplete = SceneFrameTextureResource(
            publication: .init(
                requestIdentity: swappedFirst.publication.requestIdentity,
                candidate: swappedFirst.publication.candidate,
                contentGeneration: swappedFirst.publication.contentGeneration + 1
            ),
            resourceGeneration: swappedFirst.resourceGeneration
        )
        let incompleteOverlayRejected = base.overlayingGraphResources([
            first: incomplete,
        ]) == nil
            && base.resource(for: .graph(input))?.publication.candidate.texture
                === firstResource.publication.candidate.texture
        let wrongRequestOverlayRejected = base.overlayingGraphResources([
            first: secondResource,
        ]) == nil
        let invalidGraphIdentity = Graph.TextureIdentity(
            kind: .framebuffer,
            layerID: layerID,
            effect: nil,
            name: nil
        )
        let invalidGraphRewrapRejected =
            secondResource.rewrappedForGraphIdentity(invalidGraphIdentity) == nil

        let output: [String: Any] = [
            "metalAvailable": true,
            "identityIssuer": ["checks": issued.checks, "records": issued.records],
            "positive": [
                "issuerPreservesPhysicalIdentity": issued.checks.values.allSatisfy { $0 },
                "opaquePublication": firstResource.isCompleteGraphResource,
                "premultipliedPublication": secondResource.isCompleteGraphResource,
                "straightPublicationPreservesRepresentation": straightPublicationPreservesRepresentation,
                "straightFullFramePublication": straightFullFrame.isCompleteGraphResource
                    && straightFullFrame.publication.candidate.purpose == .straightAlbedo,
                "straightNamedPublication": straightNamed?.isCompleteNamedLayerTarget(
                    reference: straightNamedReference, frameEpoch: 1) == true
                    && straightNamed?.publication.candidate.purpose == .straightAlbedo,
                "physicalIdentity": physicalIdentityCorrect,
                "swapPreservesPhysicalAtom": swapPreservesPhysicalAtom,
                "immutableOverlay": immutableOverlay,
                "programResolvedOverlay": programResolvedOverlay,
                "aliasedEndpointPublication": aliasedEndpointPublication,
                "nonIdempotentProviderResolvedOnce": nonIdempotentProviderResolvedOnce,
            "r8ScalarPublication": r8ScalarPublication,
            "rg88Publication": channelPublicationContracts["rg88"] ?? false,
            "r16Publication": channelPublicationContracts["r16"] ?? false,
                "rg16Publication": channelPublicationContracts["rg16"] ?? false,
                "rgbaDataPublication": rgbaDataPublicationContract,
                "floatPublication": floatPublicationContract,
                "floatBackgroundAndStaleRejection": floatBackgroundContract,
                "backbufferDataPublication": backbufferDataPublicationContract,
            "r8ScalarCannotRewrapAsLayerSource":
                r8ScalarCannotRewrapAsLayerSource,
                "r8ScalarCannotRewrapAsEffectOutput":
                r8ScalarCannotRewrapAsEffectOutput,
                "rgbaRepeatPublication": repeatPublicationContract,
                "r8RepeatPublication": r8RepeatPublicationContract,
                "fullFramePublicationRemainsClamp":
                    aliasOutputResource.publication.candidate.sampling
                        == .linearClamp
                    && aliasRotatedInputResource.publication.candidate.sampling
                        == .linearClamp,
            ],
            "failures": [
                "unresolved": unresolvedFailure,
                "zeroGeneration": zeroGenerationFailure,
                "unknownToken": unknownTokenFailure,
                "wrongDescriptor": wrongDescriptorFailure,
                "pairToken": pairTokenFailure,
                "r8Publication": r8PublicationFailure,
                "rg88WrongStorage": channelWrongStorageFailures["rg88"],
                "r16WrongStorage": channelWrongStorageFailures["r16"],
                "rg16WrongStorage": channelWrongStorageFailures["rg16"],
                "forgedR8AuthoredFormat": forgedR8AuthoredFormat
                    .isCompleteGraphResource ? "accepted" : "rejected",
                "forgedR8WrongAuthoredFormat": forgedR8WrongAuthoredFormat
                    .isCompleteGraphResource ? "accepted" : "rejected",
                "forgedR8ColorPurpose": forgedR8ColorPurpose
                    .isCompleteGraphResource ? "accepted" : "rejected",
                "duplicateTokenAtLeaseCreation": duplicateTokenFailure,
                "wrongTexture": wrongTextureFailure,
                "endpointViaFramebuffer": endpointViaFramebufferFailure,
                "invalidFullFrameIdentity": invalidFullFrameIdentityFailure,
                "zeroFullFrameGeneration": zeroFullFrameGenerationFailure,
                "wrongPairMember": wrongPairMemberFailure,
                "incompleteOverlay": incompleteOverlayRejected ? "rejected" : "accepted",
                "wrongRequestOverlay": wrongRequestOverlayRejected ? "rejected" : "accepted",
                "invalidGraphRewrap": invalidGraphRewrapRejected ? "rejected" : "accepted",
            ],
        ]
        let data = try JSONSerialization.data(
            withJSONObject: output,
            options: [.sortedKeys]
        )
        print(String(decoding: data, as: UTF8.self))
    }
}
