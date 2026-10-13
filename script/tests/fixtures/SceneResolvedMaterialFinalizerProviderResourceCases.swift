// Complete providers cases; state remains owned by the single fixture.
import Foundation
import Metal
import simd

func mixedSystemNamedProviderTokens(
    _ device: MTLDevice
) -> [String: Any] {
    let shader = contract(
        revision: "mixed-system-named-overlay",
        secondSamplerMetadata: #"{"mode":"rgbmask","default":"util/white"}"#,
        overlayAlphaBlend: true
    )
    let namedReference = SceneNamedTextureReference(
        providerLayerID: 879,
        variant: .primary
    )
    let systemName = "$mediaThumbnail"
    let candidates: [Template.TextureCandidate] = [
        .init(
            reference: .provider(.namedLayerTarget(namedReference)),
            provenance: .material
        ),
        .init(
            reference: .provider(.system(systemName)),
            provenance: .userTexture
        ),
    ]
    let admitted = template(
        shader,
        includePrimaryCandidate: false,
        secondCandidates: candidates
    )
    let cache: SceneResolvedMaterialVariantCache
    switch SceneResolvedMaterialVariantCache.launchValidated(
        template: admitted,
        maximumVariantCount: 16
    ) {
    case let .success(value): cache = value
    case let .failure(failure):
        return ["setup": "cache:\(failure.phase.rawValue)/\(failure.code.rawValue)"]
    }
    switch cache.precompileLaunchEnvelope(
        implicitFramebufferIdentity: graphTexture()
    ) {
    case .success: break
    case .failure(.capacity): return ["setup": "launch:capacity"]
    case let .failure(.material(failure)):
        return [
            "setup": "launch:\(failure.phase.rawValue)/\(failure.code.rawValue)",
            "details": failure.boundedDetails.joined(separator: ","),
        ]
    }
    let namedDescriptor = MTLTextureDescriptor.texture2DDescriptor(
        pixelFormat: .bgra8Unorm,
        width: 2,
        height: 2,
        mipmapped: false
    )
    namedDescriptor.storageMode = .shared
    namedDescriptor.usage = [.shaderRead, .renderTarget]
    guard let namedResource = SceneFrameTextureResource
            .reservedNamedLayerTarget(
                reference: namedReference,
                frameEpoch: 1,
                texture: device.makeTexture(descriptor: namedDescriptor)!
            ) else { return ["setup": "named-resource"] }

    let namedIdentity = SceneFrameTextureIdentity.namedLayerTarget(
        namedReference
    )
    let systemIdentity = SceneFrameTextureIdentity.system(.init(
        name: systemName,
        purpose: .preservedChannels
    ))
    let namedEntry = SceneFrameTextureLookupStatus.ready(namedResource)
    let systemReady = SceneFrameTextureLookupStatus.ready(.init(
        publication: publication(
            device,
            requestIdentity: systemIdentity,
            purpose: .preservedChannels,
            content: .data,
            candidateGeneration: 7,
            contentGeneration: 7,
            candidateIdentity: .provider(.mediaThumbnailCurrent)
        ),
        resourceGeneration: 7
    ))
    func finalized(
        systemStatus: SceneFrameTextureLookupStatus?
    ) -> Result<Program, SceneResolvedMaterialFailure> {
        var entries = [namedIdentity: namedEntry]
        if let systemStatus { entries[systemIdentity] = systemStatus }
        return finalize(
            shader: shader,
            device: device,
            includePrimaryCandidate: false,
            secondCandidates: candidates,
            additionalEntries: entries,
            implicitFramebufferIdentity: graphTexture(),
            variantCache: cache
        )
    }
    func selectionToken(
        _ result: Result<Program, SceneResolvedMaterialFailure>
    ) -> String {
        guard case let .success(program) = result,
              let slot = program.textureSlots[1] else {
            return failureToken(result)
        }
        let source: String = switch slot.reference {
        case .provider(.system): "system"
        case .provider(.namedLayerTarget): "named"
        default: "other"
        }
        return "\(source):\(slot.expectedPurpose.reportToken)"
    }

    let countersBefore = cache.counters
    let ready = finalized(systemStatus: systemReady)
    let absent = finalized(systemStatus: .absent)
    let readyAgain = finalized(systemStatus: systemReady)
    let pending = finalized(systemStatus: .pending)
    let unavailable = finalized(systemStatus: .unavailable)
    let missing = finalized(systemStatus: nil)
    let incomplete = finalized(systemStatus: .incomplete(.bare(
        texture: namedResource.publication.texture,
        resourceGeneration: 7
    )))
    let countersAfter = cache.counters
    let snapshot = cache.launchEnvelopeCapabilitySnapshot()
    return [
        "variantCount": snapshot.variants.count,
        "allReady": snapshot.allEntriesReady,
        "abiSlots": snapshot.variants.map {
            $0.premultipliedColorInputSlots.sorted()
        }.sorted { $0.lexicographicallyPrecedes($1) },
        "profiles": Array(Set(snapshot.variants.map {
            $0.routeDecision.profile
        })).sorted(),
        "ready": selectionToken(ready),
        "absent": selectionToken(absent),
        "readyAgain": selectionToken(readyAgain),
        "pending": selectionToken(pending),
        "pendingVisualFallback": visualFallbackToken(pending),
        "unavailable": selectionToken(unavailable),
        "missing": failureToken(missing),
        "incomplete": failureToken(incomplete),
        "cacheStable": countersBefore.cachedVariantCount
            == countersAfter.cachedVariantCount
            && countersBefore.shaderPreparationCount
                == countersAfter.shaderPreparationCount
            && countersBefore.frontendCompilationCount
                == countersAfter.frontendCompilationCount,
    ]
}

func namedProviderRuntimePurposeTokens(
    _ device: MTLDevice
) -> [String: String] {
    let reference = SceneNamedTextureReference(
        providerLayerID: 879,
        variant: .primary
    )
    let shader = contract(
        revision: "named-provider-runtime-purpose",
        secondSamplerMetadata: ""
    )
    let admitted = template(
        shader,
        includePrimaryCandidate: false,
        secondReference: .provider(.namedLayerTarget(reference))
    )
    guard let slot = admitted.textureSlots[1] else {
        return ["setup": "slot"]
    }
    func selected(
        content: SceneTextureContent,
        mode: SceneResolvedMaterialShaderSchema.TextureMode = .regular
    ) -> String {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: 2,
            height: 2,
            mipmapped: false
        )
        descriptor.usage = [.shaderRead, .renderTarget]
        guard let texture = device.makeTexture(descriptor: descriptor),
              let resource = SceneFrameTextureResource.reservedNamedLayerTarget(
                reference: reference,
                frameEpoch: 1,
                texture: texture,
                content: content
              ) else { return "resource-rejected" }
        let frame = SceneResolvedMaterialFrameSnapshot.validated(
            textureSnapshot: snapshot(
                device,
                additionalEntries: [
                    .namedLayerTarget(reference): .ready(resource),
                ]
            ),
            dynamicSnapshot: dynamicSnapshot(frameIndex: 1, source: nil),
            frameInputs: frameInputs(frameIndex: 1)
        )
        guard case let .success(snapshot) = frame else {
            return "frame-rejected"
        }
        let input = snapshot.finalizationInput(
            template: admitted,
                        layerID: 9001,
                        renderSize: CGSize(width: 2, height: 2),
            modelViewProjection: matrix_identity_float4x4,
            layerModelMatrix: matrix_identity_float4x4,
            effectOutputModelViewProjection: matrix_identity_float4x4,
            effectTextureProjectionMatrixInverse: matrix_identity_float4x4,
            implicitFramebufferIdentity: graphTexture()
        )
        let sampler = SceneResolvedMaterialShaderSchema.Sampler(
            name: "g_Texture1",
            slot: 1,
            mode: mode,
            materialKey: nil,
            isHidden: false,
            defaultTexture: nil,
            readinessCombo: nil,
            channelUse: .wholeVector
        )
        return SceneResolvedMaterialTextureResolver.selectionPurpose(
            in: slot,
            candidateOrdinal: 0,
            activeSampler: sampler,
            reachableSamplers: [sampler],
            channelUse: .wholeVector,
            input: input
        )?.reportToken ?? "unproven"
    }
    return [
        "color": selected(
            content: .color(.resolved(.premultipliedAlpha))
        ),
        "data": selected(content: .data),
        "dataMaskRejected": selected(content: .data, mode: .opacityMask),
    ]
}

func inputAssociationMask(_ program: Program) -> UInt32? {
    guard let uniform = program.resolvedUniforms.first(where: {
        if case .host(.premultipliedColorInputMask) = $0.source { return true }
        return false
    }), uniform.encodedValue.count == 4 else { return nil }
    return uniform.encodedValue.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }
}

func rtDefaultAdmissionTokens(_ device: MTLDevice) -> [String: String] {
    var result: [String: String] = [:]
    for token in ["_rt_imageLayerComposite_42", "_rt_imageLayerComposite_42_a", "_rt_imageLayerComposite_42_b", "_rt_imageLayerComposite_43_a", "_rt_imagelayercomposite_42_a", "_rt_unknown", "_rt_imageLayerComposite_42_c", "_rt_imageLayerComposite_-1", "_RT_imageLayerComposite_42_a"] {
        let shader = contract(revision: "rt-default-\(token)", samplerMetadata: "{\"default\":\"\(token)\"}", uniformMetadata: nil, semanticProbes: false)
        let value = template(shader, includePrimaryCandidate: false)
        do {
            let samplers = try SceneResolvedMaterialShaderSchema.bootstrapSamplers(value)
            let facts = SceneResolvedMaterialShaderSchema.graphInputSourceSlotFacts(template: value, samplers: samplers, inputIdentity: graphTexture())
            let projection = SceneResolvedMaterialTextureResolver.launchReadinessProjection(template: value, samplers: samplers, implicitFramebufferIdentity: graphTexture(), assetStates: [:])
            switch projection {
            case let .success(mask): result[token] = "ready:\(mask.requiredMask):fact:\(facts[0] != nil)"
            case let .failure(failure): result[token] = "rejected:\(failure.code)"
            }
            let finalized = finalize(shader: shader, device: device, includePrimaryCandidate: false, implicitFramebufferIdentity: graphTexture())
            switch finalized {
            case let .success(program):
                result[token + ":binding"] = program.textureSlots[0]?.reference == .graph(graphTexture()) && program.textureSlots[0]?.graphInputSourceFact?.inputIdentity == graphTexture() ? "graph-ingress" : "wrong-reference"
            case let .failure(failure): result[token + ":binding"] = "rejected:\(failure.code)"
            }
            let override = finalize(shader: shader, device: device, implicitFramebufferIdentity: graphTexture())
            result[token + ":override"] = failureToken(override)
            if case let .internalTarget(target)? = samplers[0]?.defaultTexture {
                result[token + ":spelling"] = target.authoredName
                result[token + ":persistent"] = ScenePersistentSamplerRecord(sampler: samplers[0]!).rebuild() == samplers[0] ? "same" : "changed"
            }
            let straight = finalize(shader: shader, device: device, includePrimaryCandidate: false,
                snapshotKind: .straightGraphColor, implicitFramebufferIdentity: graphTexture())
            result[token + ":straight"] = failureToken(straight)
            if case let .success(program) = straight, let slot = program.textureSlots[0] {
                result[token + ":straightPurpose"] = slot.expectedPurpose.reportToken
                result[token + ":straightIngress"] = String(slot.reference == .graph(graphTexture())
                    && slot.registryIdentity == .graph(graphTexture())
                    && slot.resource.publication.candidate.content == .color(.resolved(.straightAlpha))
                    && program.frontendProgram.colorBoundary?.colorInputSlots == [0]
                    && inputAssociationMask(program) == 0)
            }
            for (label, kind) in [("missing", SnapshotKind.missing), ("stale", .incomplete), ("purpose", .purposeMismatch)] {
                result[token + ":" + label] = failureToken(finalize(shader: shader, device: device, includePrimaryCandidate: false, snapshotKind: kind, implicitFramebufferIdentity: graphTexture()))
            }

        } catch { result[token] = "schema-rejected" }
    }
    for (label, token, consumed) in [("dead-unknown", "_rt_unknown", false), ("active-presence", "_rt_imageLayerComposite_42_a", true)] {
        let shader = contract(revision: "rt-\(label)", uniformMetadata: nil, semanticProbes: false,
            fragmentSourceOverride: """
            varying vec2 v_TexCoord;
            uniform sampler2D g_Texture0; // {"default":"\(token)","combo":"INPUT"}
            void main() { gl_FragColor = \(consumed ? "texSample2D(g_Texture0, v_TexCoord)" : "vec4(0.0, 0.0, 1.0, 1.0)"); }
            """)
        result[label] = failureToken(finalize(shader: shader, device: device, includePrimaryCandidate: false, implicitFramebufferIdentity: graphTexture()))
    }
    let fallbackPath = SceneVFSAssetPath("textures/rt-optional.tex")!
    let fallbackIdentity = SceneAssetTextureIdentity(path: fallbackPath, purpose: .straightAlbedo)
    let fallbackShader = contract(revision: "rt-absent-candidate", samplerMetadata: #"{"material":"albedo","default":"_rt_imageLayerComposite_42_a"}"#, uniformMetadata: nil, semanticProbes: false)
    for (label, status, launch): (String, SceneFrameTextureLookupStatus, SceneAssetTextureLaunchState) in [
        ("absent-candidate", .absent, .absent),
        ("pending-candidate", .pending, .ready(.color(.resolved(.straightAlpha)))),
        ("unavailable-candidate", .unavailable, .ready(.color(.resolved(.straightAlpha)))),
        ("ready-candidate", readyStatus(device, identity: .asset(fallbackIdentity), purpose: .straightAlbedo, content: .color(.resolved(.straightAlpha))), .ready(.color(.resolved(.straightAlpha))))
    ] {
        let finalized = finalize(shader: fallbackShader, device: device, primaryReference: .asset(fallbackPath), graphBindingsOverride: [],
            additionalEntries: [.asset(fallbackIdentity): status], implicitFramebufferIdentity: graphTexture(),
            assetLaunchStatesOverride: [fallbackIdentity: launch])
        result[label] = failureToken(finalized)
        if case let .success(program) = finalized {
            result[label + ":identity"] = program.textureSlots[0]?.reference == .graph(graphTexture()) ? "graph" : "asset"
            result[label + ":purpose"] = program.textureSlots[0]?.expectedPurpose.reportToken
        }
    }
    let context = Template.EffectContext(key: .init(layerID: fixtureLayerID, effectIndex: 0, descriptorID: "rf01"), input: graphTexture())
    for token in ["_rt_FullFrameBuffer", "_RT_FULLFRAMEBUFFER", "_rt_fullframebuffer"] {
        let shader = contract(revision: "rt-full-\(token)", samplerMetadata: "{\"default\":\"\(token)\"}", uniformMetadata: nil, semanticProbes: false)
        let background = SceneFrameTextureIdentity.sceneBackground(fixtureLayerID)
        let finalized = finalize(shader: shader, device: device, includePrimaryCandidate: false,
            additionalEntries: [background: readyStatus(device, identity: background, purpose: .premultipliedColor, content: .color(.resolved(.premultipliedAlpha)))],
            implicitFramebufferIdentity: graphTexture(), effectContext: context)
        result[token] = failureToken(finalized)
        if case let .success(program) = finalized {
            result[token + ":identity"] = program.textureSlots[0]?.registryIdentity == background ? "background" : "wrong"
        }
    }
    return result
}


final class SceneResolvedMaterialFinalizerProviderResourceCases {
    unowned let fixture: SceneResolvedMaterialFinalizerFixture

    init(_ fixture: SceneResolvedMaterialFinalizerFixture) {
        self.fixture = fixture
    }

    lazy var overlayPath = SceneVFSAssetPath("textures/overlay-data.tex")!

    lazy var overlayIdentity = SceneFrameTextureIdentity.asset(.init(
        path: self.overlayPath,
        purpose: .preservedChannels
    ))

    lazy var overlayShader = contract(
        revision: "overlay-alpha-blend",
        secondSamplerMetadata: #"{"mode":"rgbmask"}"#,
        overlayAlphaBlend: true
    )

    lazy var overlayProgram = finalize(
        shader: self.overlayShader,
        device: self.fixture.device,
        includePrimaryCandidate: false,
        secondReference: .asset(self.overlayPath),
        additionalEntries: [
            overlayIdentity: readyStatus(
                self.fixture.device,
                identity: self.overlayIdentity,
                purpose: .preservedChannels,
                content: .data
            ),
        ],
        implicitFramebufferIdentity: graphTexture()
    )

    lazy var overlayDataTyped: Bool = {
        guard case let .success(program) = self.overlayProgram,
              let overlay = program.textureSlots[1],
              overlay.expectedPurpose == .preservedChannels,
              overlay.resource.publication.candidate.purpose
                == .preservedChannels,
              case .data = overlay.resource.publication.candidate.content,
              overlay.reference == .asset(self.overlayPath),
              program.frontendProgram.colorBoundary?.colorInputSlots == [0] else {
            return false
        }
        guard case let .color(contract) =
                program.semanticIdentity.outputContract else { return false }
        return program.frontendProgram.textureBindings.map(\.slot) == [0, 1]
            && contract.fragmentOutput == .straightAlpha
            && inputAssociationMask(program) == 1
    }()

    lazy var overlayColorAuxiliary = finalize(
        shader: self.overlayShader,
        device: self.fixture.device,
        includePrimaryCandidate: false,
        secondReference: .asset(self.overlayPath),
        additionalEntries: [
            overlayIdentity: readyStatus(
                self.fixture.device,
                identity: self.overlayIdentity,
                purpose: .preservedChannels,
                content: .color(.resolved(.premultipliedAlpha))
            ),
        ],
        implicitFramebufferIdentity: graphTexture()
    )

    lazy var optionalDefaultPath = SceneVFSAssetPath(
        "textures/optional-default-mask.tex"
    )!

    lazy var optionalDefaultIdentity = SceneFrameTextureIdentity.asset(.init(
        path: self.optionalDefaultPath,
        purpose: .mask
    ))

    lazy var optionalDefaultEntry = readyStatus(
        self.fixture.device,
        identity: self.optionalDefaultIdentity,
        purpose: .mask,
        content: .data
    )

    lazy var optionalMaskShader = contract(
        revision: "optional-mask-with-default",
        secondSamplerMetadata:
            #"{"mode":"opacitymask","combo":"MASK","default":"textures/optional-default-mask.tex"}"#,
        maskedAlpha: true,
        optionalMask: true,
        deadMaskCoordinates: true
    )

    lazy var optionalMaskProgram = finalize(
        shader: self.optionalMaskShader,
        device: self.fixture.device,
        includePrimaryCandidate: false,
        uniformDeclarations: [staticDeclaration("alpha", components: [0.5])],
        implicitFramebufferIdentity: graphTexture()
    )

    lazy var optionalMaskWithoutResourceAccepted: Bool = {
        guard case let .success(program) = self.optionalMaskProgram else {
            return false
        }
        return program.frontendProgram.textureBindings.map(\.slot) == [0]
            && program.textureSlots[0] != nil
            && program.textureSlots[1] == nil
            && !program.frontendProgram.uniformLayout.fields.contains {
                $0.name == "g_Texture1Resolution"
            }
    }()

    lazy var optionalMaskWithResource = finalize(
        shader: self.optionalMaskShader,
        device: self.fixture.device,
        includePrimaryCandidate: false,
        secondReference: .asset(self.fixture.uniforms.maskedPath),
        additionalEntries: [
            optionalDefaultIdentity: self.optionalDefaultEntry,
            self.fixture.uniforms.maskedIdentity: readyStatus(
                self.fixture.device,
                identity: self.fixture.uniforms.maskedIdentity,
                purpose: .mask,
                content: .data
            ),
        ],
        uniformDeclarations: [staticDeclaration("alpha", components: [0.5])],
        implicitFramebufferIdentity: graphTexture()
    )

    lazy var optionalMaskWithResourceAccepted: Bool = {
        guard case let .success(program) = self.optionalMaskWithResource,
              let mask = program.textureSlots[1],
              case let .asset(reference) = mask.reference,
              reference == self.fixture.uniforms.maskedPath,
              mask.diagnosticSelectionProvenance == .authored(.instance),
              mask.expectedPurpose == .mask,
              case .data = mask.resource.publication.candidate.content else {
            return false
        }
        return program.frontendProgram.textureBindings.map(\.slot) == [0, 1]
            && program.frontendProgram.uniformLayout.fields.contains {
                $0.name == "g_Texture1Resolution"
            }
    }()

    lazy var optionalMaskPending = finalize(
        shader: self.optionalMaskShader,
        device: self.fixture.device,
        includePrimaryCandidate: false,
        secondReference: .asset(self.fixture.uniforms.maskedPath),
        additionalEntries: [
            optionalDefaultIdentity: self.optionalDefaultEntry,
            self.fixture.uniforms.maskedIdentity: .pending,
        ],
        uniformDeclarations: [staticDeclaration("alpha", components: [0.5])],
        implicitFramebufferIdentity: graphTexture()
    )

    lazy var optionalMaskWrongPurpose = finalize(
        shader: self.optionalMaskShader,
        device: self.fixture.device,
        includePrimaryCandidate: false,
        secondReference: .asset(self.fixture.uniforms.maskedPath),
        additionalEntries: [
            optionalDefaultIdentity: self.optionalDefaultEntry,
            self.fixture.uniforms.maskedIdentity: readyStatus(
                self.fixture.device,
                identity: self.fixture.uniforms.maskedIdentity,
                purpose: .straightAlbedo,
                content: .color(.resolved(.straightAlpha))
            ),
        ],
        uniformDeclarations: [staticDeclaration("alpha", components: [0.5])],
        implicitFramebufferIdentity: graphTexture()
    )

    lazy var activeDefaultMaskShader = contract(
        revision: "active-default-mask-with-presence-combo",
        secondSamplerMetadata:
            #"{"mode":"opacitymask","combo":"MASK","default":"textures/optional-default-mask.tex"}"#,
        maskedAlpha: true
    )

    lazy var activeDefaultUniforms = [
        staticDeclaration("alpha", components: [0.5]),
    ]

    lazy var activeDefaultTemplate = template(
        self.activeDefaultMaskShader,
        includePrimaryCandidate: false,
        uniformDeclarations: self.activeDefaultUniforms
    )

    lazy var activeDefaultMaskCache: SceneResolvedMaterialVariantCache = {
        guard case let .success(activeDefaultMaskCache) =
                SceneResolvedMaterialVariantCache.launchValidated(
            template: self.activeDefaultTemplate,
            maximumVariantCount: 8
        ) else {
            fatalError("active default fixture cache rejected")
        }
        return activeDefaultMaskCache
    }()

    lazy var activeDefaultLaunch = self.activeDefaultMaskCache.precompileLaunchEnvelope(
        implicitFramebufferIdentity: graphTexture(),
        assetStates: [
            SceneAssetTextureIdentity(
                path: self.optionalDefaultPath,
                purpose: .mask
            ): .ready(.data),
        ]
    )

    lazy var activeDefaultLaunchMasks: [UInt8]? = switch self.activeDefaultLaunch {
    case let .success(masks): masks
    case .failure: nil
    }

    lazy var activeDefaultMaskProgram = finalize(
        shader: self.activeDefaultMaskShader,
        device: self.fixture.device,
        includePrimaryCandidate: false,
        additionalEntries: [
            optionalDefaultIdentity: self.optionalDefaultEntry,
        ],
        uniformDeclarations: self.activeDefaultUniforms,
        implicitFramebufferIdentity: graphTexture(),
        variantCache: self.activeDefaultMaskCache
    )

    lazy var activeDefaultMaskAccepted: Bool = {
        guard case let .success(program) = self.activeDefaultMaskProgram,
              let mask = program.textureSlots[1],
              case let .asset(reference) = mask.reference,
              reference == self.optionalDefaultPath,
              mask.diagnosticSelectionProvenance == .shaderDefault,
              mask.expectedPurpose == .mask,
              case .data = mask.resource.publication.candidate.content else {
            return false
        }
        guard case let .color(contract) =
                program.semanticIdentity.outputContract else { return false }
        return program.frontendProgram.textureBindings.map(\.slot) == [0, 1]
            && program.frontendProgram.colorBoundary?.colorInputSlots == [0]
            && contract.fragmentOutput == .straightAlpha
            && inputAssociationMask(program) == 1
    }()

    lazy var activeAuthoredMaskProgram = finalize(
        shader: self.activeDefaultMaskShader,
        device: self.fixture.device,
        includePrimaryCandidate: false,
        secondReference: .asset(self.optionalDefaultPath),
        additionalEntries: [
            optionalDefaultIdentity: self.optionalDefaultEntry,
        ],
        uniformDeclarations: self.activeDefaultUniforms,
        implicitFramebufferIdentity: graphTexture()
    )

    lazy var activeDefaultMaskMissing = finalize(
        shader: self.activeDefaultMaskShader,
        device: self.fixture.device,
        includePrimaryCandidate: false,
        uniformDeclarations: [staticDeclaration("alpha", components: [0.5])],
        implicitFramebufferIdentity: graphTexture()
    )

    lazy var optionalUntypedMask = finalize(
        shader: contract(
            revision: "optional-mask-with-untyped-resource",
            secondSamplerMetadata: #"{"combo":"MASK"}"#,
            maskedAlpha: true,
            optionalMask: true,
            deadMaskCoordinates: true
        ),
        device: self.fixture.device,
        includePrimaryCandidate: false,
        secondReference: .asset(self.fixture.uniforms.maskedPath),
        additionalEntries: [
            self.fixture.uniforms.maskedIdentity: readyStatus(
                self.fixture.device,
                identity: self.fixture.uniforms.maskedIdentity,
                purpose: .mask,
                content: .data
            ),
        ],
        uniformDeclarations: [staticDeclaration("alpha", components: [0.5])],
        implicitFramebufferIdentity: graphTexture()
    )

    lazy var maskedMissing = finalize(
        shader: self.fixture.uniforms.maskedShader,
        device: self.fixture.device,
        includePrimaryCandidate: false,
        secondReference: .asset(self.fixture.uniforms.maskedPath),
        uniformDeclarations: [staticDeclaration("alpha", components: [0.5])],
        implicitFramebufferIdentity: graphTexture()
    )

    lazy var maskedPending = finalize(
        shader: self.fixture.uniforms.maskedShader,
        device: self.fixture.device,
        includePrimaryCandidate: false,
        secondReference: .asset(self.fixture.uniforms.maskedPath),
        additionalEntries: [self.fixture.uniforms.maskedIdentity: .pending],
        uniformDeclarations: [staticDeclaration("alpha", components: [0.5])],
        implicitFramebufferIdentity: graphTexture()
    )

    lazy var maskedWrongPurpose = finalize(
        shader: self.fixture.uniforms.maskedShader,
        device: self.fixture.device,
        includePrimaryCandidate: false,
        secondReference: .asset(self.fixture.uniforms.maskedPath),
        additionalEntries: [
            self.fixture.uniforms.maskedIdentity: readyStatus(
                self.fixture.device,
                identity: self.fixture.uniforms.maskedIdentity,
                purpose: .straightAlbedo,
                content: .color(.resolved(.straightAlpha))
            ),
        ],
        uniformDeclarations: [staticDeclaration("alpha", components: [0.5])],
        implicitFramebufferIdentity: graphTexture()
    )

    lazy var maskedColorAuxiliary = finalize(
        shader: self.fixture.uniforms.maskedShader,
        device: self.fixture.device,
        includePrimaryCandidate: false,
        secondReference: .asset(self.fixture.uniforms.maskedPath),
        additionalEntries: [
            self.fixture.uniforms.maskedIdentity: readyStatus(
                self.fixture.device,
                identity: self.fixture.uniforms.maskedIdentity,
                purpose: .mask,
                content: .color(.resolved(.straightAlpha))
            ),
        ],
        uniformDeclarations: [staticDeclaration("alpha", components: [0.5])],
        implicitFramebufferIdentity: graphTexture()
    )

    lazy var propertyRequest = Template.UserPropertyRequest(key: "fixtureMask")

    lazy var propertyIdentity = SceneUserPropertyTextureIdentity(
        propertyKey: self.propertyRequest.key,
        purpose: .mask
    )!

    lazy var propertyProgram = finalize(
        shader: contract(
            revision: "property-reference",
            secondSamplerMetadata: self.fixture.uniforms.maskMetadata
        ),
        device: self.fixture.device,
        secondReference: .userProperty(self.propertyRequest),
        additionalEntries: [
            .materialUserProperty(self.propertyIdentity):
                readyStatus(
                    self.fixture.device,
                    identity: .materialUserProperty(self.propertyIdentity),
                    purpose: .mask,
                    content: .data
                ),
        ]
    )

    lazy var systemMaskIdentity = SceneSystemProviderTextureIdentity(
        name: "fixture-mask-provider",
        purpose: .mask
    )

    lazy var systemMaskRequest = SceneFrameTextureIdentity.system(
        self.systemMaskIdentity
    )

    lazy var providerProgram = finalize(
        shader: contract(
            revision: "provider-reference",
            secondSamplerMetadata: self.fixture.uniforms.maskMetadata
        ),
        device: self.fixture.device,
        secondReference: .provider(.system("fixture-mask-provider")),
        additionalEntries: [
            systemMaskRequest:
                readyStatus(
                    self.fixture.device,
                    identity: self.systemMaskRequest,
                    purpose: .mask,
                    content: .data
                ),
        ]
    )

    lazy var providerPending = finalize(
        shader: contract(
            revision: "provider-pending",
            secondSamplerMetadata: self.fixture.uniforms.maskMetadata
        ),
        device: self.fixture.device,
        secondReference: .provider(.system("fixture-mask-provider")),
        additionalEntries: [systemMaskRequest: .pending]
    )

    lazy var fallbackAssetPath = SceneVFSAssetPath("textures/fallback-mask.tex")!

    lazy var fallbackProperty = Template.UserPropertyRequest(key: "optionalMask")

    lazy var fallbackPropertyIdentity = SceneUserPropertyTextureIdentity(
        propertyKey: self.fallbackProperty.key,
        purpose: .mask
    )!

    lazy var providerUnavailableDoesNotFallback = finalize(
        shader: contract(
            revision: "provider-unavailable-fallback",
            secondSamplerMetadata: self.fixture.uniforms.maskMetadata
        ),
        device: self.fixture.device,
        secondCandidates: [
            .init(reference: .asset(self.fallbackAssetPath), provenance: .instance),
            .init(reference: .userProperty(self.fallbackProperty), provenance: .userTexture),
        ],
        additionalEntries: [
            .asset(.init(path: self.fallbackAssetPath, purpose: .mask)):
                readyStatus(
                    self.fixture.device,
                    identity: .asset(.init(
                        path: self.fallbackAssetPath,
                        purpose: .mask
                    )),
                    purpose: .mask,
                    content: .data
                ),
            .materialUserProperty(self.fallbackPropertyIdentity): .unavailable,
        ]
    )

    lazy var providerAbsentFallback = finalize(
        shader: contract(
            revision: "provider-absent-fallback",
            secondSamplerMetadata: self.fixture.uniforms.maskMetadata
        ),
        device: self.fixture.device,
        secondCandidates: [
            .init(reference: .asset(self.fallbackAssetPath), provenance: .instance),
            .init(reference: .userProperty(self.fallbackProperty), provenance: .userTexture),
        ],
        additionalEntries: [
            .asset(.init(path: self.fallbackAssetPath, purpose: .mask)):
                readyStatus(
                    self.fixture.device,
                    identity: .asset(.init(
                        path: self.fallbackAssetPath,
                        purpose: .mask
                    )),
                    purpose: .mask,
                    content: .data
                ),
            .materialUserProperty(self.fallbackPropertyIdentity): .absent,
        ]
    )

    lazy var providerMissingDoesNotFallback = finalize(
        shader: contract(
            revision: "provider-missing-no-fallback",
            secondSamplerMetadata: self.fixture.uniforms.maskMetadata
        ),
        device: self.fixture.device,
        secondCandidates: [
            .init(reference: .asset(self.fallbackAssetPath), provenance: .instance),
            .init(reference: .userProperty(self.fallbackProperty), provenance: .userTexture),
        ],
        additionalEntries: [
            .asset(.init(path: self.fallbackAssetPath, purpose: .mask)):
                readyStatus(
                    self.fixture.device,
                    identity: .asset(.init(
                        path: self.fallbackAssetPath,
                        purpose: .mask
                    )),
                    purpose: .mask,
                    content: .data
                ),
        ]
    )

    lazy var providerPendingDoesNotFallback = finalize(
        shader: contract(
            revision: "provider-pending-no-fallback",
            secondSamplerMetadata: self.fixture.uniforms.maskMetadata
        ),
        device: self.fixture.device,
        secondCandidates: [
            .init(reference: .asset(self.fallbackAssetPath), provenance: .instance),
            .init(reference: .userProperty(self.fallbackProperty), provenance: .userTexture),
        ],
        additionalEntries: [
            .asset(.init(path: self.fallbackAssetPath, purpose: .mask)):
                readyStatus(
                    self.fixture.device,
                    identity: .asset(.init(
                        path: self.fallbackAssetPath,
                        purpose: .mask
                    )),
                    purpose: .mask,
                    content: .data
                ),
            .materialUserProperty(self.fallbackPropertyIdentity): .pending,
        ]
    )

    lazy var shaderDefaultAfterUnavailableProvider = finalize(
        shader: contract(
            revision: "provider-unavailable-shader-default",
            secondSamplerMetadata:
                #"{"mode":"opacitymask","default":"textures/default-mask.tex"}"#
        ),
        device: self.fixture.device,
        secondCandidates: [
            .init(reference: .userProperty(self.fallbackProperty), provenance: .userTexture),
        ],
        additionalEntries: [
            .asset(.init(
                path: SceneVFSAssetPath("textures/default-mask.tex")!,
                purpose: .mask
            )): readyStatus(
                self.fixture.device,
                identity: .asset(.init(
                    path: SceneVFSAssetPath("textures/default-mask.tex")!,
                    purpose: .mask
                )),
                purpose: .mask,
                content: .data
            ),
            .materialUserProperty(self.fallbackPropertyIdentity): .unavailable,
        ]
    )

    lazy var shaderDefaultAfterAbsentProvider = finalize(
        shader: contract(
            revision: "provider-absent-shader-default",
            secondSamplerMetadata:
                #"{"mode":"opacitymask","default":"textures/default-mask.tex"}"#
        ),
        device: self.fixture.device,
        secondCandidates: [
            .init(reference: .userProperty(self.fallbackProperty), provenance: .userTexture),
        ],
        additionalEntries: [
            .asset(.init(
                path: SceneVFSAssetPath("textures/default-mask.tex")!,
                purpose: .mask
            )): readyStatus(
                self.fixture.device,
                identity: .asset(.init(
                    path: SceneVFSAssetPath("textures/default-mask.tex")!,
                    purpose: .mask
                )),
                purpose: .mask,
                content: .data
            ),
            .materialUserProperty(self.fallbackPropertyIdentity): .absent,
        ]
    )

}
