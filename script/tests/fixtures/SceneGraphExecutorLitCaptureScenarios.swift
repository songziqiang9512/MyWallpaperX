private func runLitCaptureScenarios(
    device: MTLDevice,
    queue: MTLCommandQueue,
    sourcePipeline: SceneImageLayerPipeline
) -> [String: Any] {
    var results: [String: Bool] = [:]
    var diagnostics: [String: Any] = [:]
    let litWidth = 8
    let litHeight = 8
    // A square card is retained here for graph handoff checks; the dedicated
    // lighting harness checks rectangular, rotated and normal-basis cases.
    let layerMatrix = simd_float4x4(diagonal: SIMD4<Float>(100, 100, 1, 1))
    let albedo: Float = 100 / 255

    func pixel(_ pixels: [[UInt8]]?, x: Int, y: Int) -> Int {
        guard let pixels, y < pixels.count, x * 4 + 3 < pixels[y].count else {
            return -1
        }
        return Int(pixels[y][x * 4])
    }
    func blue(_ pixels: [[UInt8]]?, x: Int, y: Int) -> Int {
        pixel(pixels, x: x, y: y)
    }
    func exactlyEqual(_ left: [[UInt8]]?, _ right: [[UInt8]]?) -> Bool {
        guard let left, let right, left.count == right.count else {
            return false
        }
        return zip(left, right).allSatisfy { $0 == $1 }
    }

    let litGraph = graph(
        targets: [],
        nodes: [material(0, ordinal: 0, target: output, read: input)]
    )
    let litChain = admittedGraph(litGraph)
    let litCapabilities = capabilities(
        litChain,
        catalog: catalog(for: litGraph)
    )
    guard let litClaim = litCapabilities.claim(litChain),
          let litCapability = litCapabilities.resolve(
              litClaim.token,
              for: litChain
          ) else {
        diagnostics["litClaimFailure"] = "claim-or-capability-unavailable"
        diagnostics["results"] = results
        return diagnostics
    }

    func makeLitLeases(
        generation: UInt64
    ) -> (leases: [SceneGraphRenderTargetLease], baseTarget: MTLTexture)? {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: litWidth,
            height: litHeight,
            mipmapped: false
        )
        descriptor.storageMode = .private
        descriptor.usage = [.renderTarget, .shaderRead]
        guard let zero = device.makeTexture(descriptor: descriptor),
              let one = device.makeTexture(descriptor: descriptor) else {
            return nil
        }
        let zeroToken = Executor.State.PhysicalToken(rawValue: "lit-zero")
        let oneToken = Executor.State.PhysicalToken(rawValue: "lit-one")
        func texture(_ member: SceneLayerFullFramePairPlan.Member) -> MTLTexture {
            member == .zero ? zero : one
        }
        var leases: [SceneGraphRenderTargetLease] = []
        for index in litCapability.admittedProducts.indices {
            let graph = litCapability.admittedProducts[index].graph
            let role: SceneAuthoredEffectInputRole = index == 0
                ? .layerSource : .priorEffectOutput
            let plan: Plan
            switch Plan.make(
                graph: graph,
                inputRole: role,
                inputWidth: litWidth,
                inputHeight: litHeight
            ) {
            case let .success(value): plan = value
            case .failure: return nil
            }
            let step = litCapability.pairPlan.effects[index]
            let mapped: SceneGraphRenderTargetTable
            switch SceneGraphRenderTargetTable.makeMapped(
                plan: plan,
                device: device,
                texturesByIdentity: [
                    plan.input: texture(step.inputMember),
                    plan.output: texture(step.outputMember),
                ],
                fullFramePair: .init(first: zero, second: one),
                expectsInputOutputAlias: step.inputMember == step.outputMember,
                makeInputsDigest: 0
            ) {
            case let .success(value): mapped = value
            case .failure: return nil
            }
            let lease: SceneGraphRenderTargetLease
            switch SceneGraphRenderTargetLease.make(
                table: mapped,
                generation: generation,
                tokenForTexture: { object in
                    object === zero ? zeroToken : oneToken
                },
                fullFramePairGeneration: generation,
                tokenForPairTexture: { object in
                    object === zero ? zeroToken : oneToken
                }
            ) {
            case let .success(value): lease = value
            case .failure: return nil
            }
            leases.append(lease)
        }
        return (
            leases,
            texture(litCapability.pairPlan.baseCaptureMember)
        )
    }

    let source = makeSource(
        device,
        width: litWidth,
        height: litHeight,
        bgra: [100, 100, 100, 255]
    )
    // Tangent-space normal points toward +X. In this 8-bit data map,
    // R=255 and G/B=128 decode to (1, 1/255, 1/255) before basis transform.
    let normalTexture = makeSource(
        device,
        width: litWidth,
        height: litHeight,
        bgra: [255, 128, 128, 255],
        pixelFormat: .rgba8Unorm
    )

    let litPipeline = SceneLitImageLayerPipeline(
        device: device,
        pixelFormat: .bgra8Unorm
    )
    results["litPipelineAvailable"] = litPipeline != nil

    func payload(
        points: [SceneBaseMaterialLitCapturePayload.PointLight] = [],
        spots: [SceneBaseMaterialLitCapturePayload.SpotLight] = [],
        ambient: SIMD3<Float>,
        normal: MTLTexture? = nil
    ) -> SceneBaseMaterialLitCapturePayload? {
        litPipeline.flatMap { pipeline in
            SceneBaseMaterialLitCapturePayload.packLights(
                pointLights: points,
                spotLights: spots,
                ambient: ambient,
                material: nil, view: SIMD4(0,0,1,0),
                layerModelMatrix: layerMatrix,
                normalModelMatrix: matrix_identity_float4x4
            ).flatMap { lights in
                SceneBaseMaterialLitCapturePayload(
                    pipeline: pipeline,
                    lights: lights,
                    normal: normal.map { texture in
                        .resolve(SceneTextureCandidate(texture: texture,
                            identity: .builtIn(name: "lit-test-normal"),
                            generation: .immutable(revision: 1), purpose: .normal, content: .data,
                            physicalSize: CGSize(width: texture.width, height: texture.height),
                            mappedSize: CGSize(width: texture.width, height: texture.height),
                            uvTransform: .identity, sampling: .directImageFallback, authoredFormat: nil))
                    } ?? .disabled
                )
            }
        }
    }

    func executeLitRun(
        generation: UInt64,
        lighting: SceneBaseMaterialLitCapturePayload?
    ) -> (
        prepared: Bool,
        encoded: Bool,
        gpu: Bool,
        base: [[UInt8]]?,
        final: [[UInt8]]?
    ) {
        guard let leasePair = makeLitLeases(generation: generation),
              let executor = Executor(
                  device: device,
                  capabilities: litCapabilities
              ),
              let command = queue.makeCommandBuffer() else {
            return (false, false, false, nil, nil)
        }
        let preparation = executor.prepare(
            token: litClaim.token,
            leases: leasePair.leases,
            historyRehydrateCopiesByEffect: [:],
            frame: frame(generation),
            sourceTexture: source,
            sourceUniforms: .neutral(),
            sourcePipeline: sourcePipeline,
            sourceLighting: lighting,
            frameInputs: .init(),
            commandBuffer: command,
            previousStates: [:],
            previousGraphResources: [:],
            effectGeneration: generation,
            resetGeneration: generation
        )
        guard case let .success(preparedGraph) = preparation else {
            return (false, false, false, nil, nil)
        }
        let encoded = executor.encode(
            preparedGraph,
            commandBuffer: command
        )
        guard encoded,
              let baseReadback = appendReadback(
                  leasePair.baseTarget,
                  commandBuffer: command
              ),
              let finalReadback = appendReadback(
                  preparedGraph.finalTexture,
                  commandBuffer: command
              ) else {
            command.commit()
            command.waitUntilCompleted()
            return (
                true,
                encoded,
                command.status == .completed && command.error == nil,
                nil,
                nil
            )
        }
        command.commit()
        command.waitUntilCompleted()
        return (
            true,
            true,
            command.status == .completed && command.error == nil,
            baseReadback.allPixels,
            finalReadback.allPixels
        )
    }

    // World-space oracle independent of the payload packer: texture row 4
    // has world Y=-6.25. Z and radius stay in authored world units.
    let centerLight = SceneBaseMaterialLitCapturePayload.PointLight(
        position: SIMD3(6.25, -6.25, 50),
        color: SIMD3(1, 1, 1), intensity: 2 / (0.9 * 0.9), radius: 500
    )
    // Official 2D lit-image contract (own-fixture, 2026-10-06): planar X/Y
    // falloff (1-d/R)^2 with the energy scale 1.85; NdotL keeps the 3D
    // direction, and the receiver exactly under the light is the maximum.
    func cornerExpectation(_ corner: SIMD2<Float>) -> Int {
        let delta = centerLight.position - SIMD3(corner.x, corner.y, 0)
        let planar = simd_length(SIMD2(delta.x, delta.y))
        let distance = simd_length(delta)
        let amount = centerLight.intensity
            * pow(max(0, 1-planar/centerLight.radius), 2)
            * 1.85 * delta.z / distance
        return Int((albedo * amount * 255).rounded())
    }
    let expectedCorner00 = cornerExpectation(SIMD2(-43.75, 43.75))
    let expectedCorner77 = cornerExpectation(SIMD2(43.75, -43.75))

    let litRun = executeLitRun(
        generation: 60,
        lighting: payload(points: [centerLight], ambient: .zero)
    )
    let noLightRun = executeLitRun(
        generation: 61,
        lighting: payload(ambient: SIMD3(1, 1, 1))
    )
    results["litCaptureResponds"] = litRun.prepared && litRun.encoded
        && litRun.gpu
        && blue(litRun.base, x: 4, y: 4) > blue(noLightRun.base, x: 4, y: 4)
        && blue(litRun.base, x: 4, y: 4) >= 254
        && abs(blue(noLightRun.base, x: 4, y: 4) - 100) <= 2
        && abs(blue(litRun.base, x: 0, y: 0) - expectedCorner00) <= 2
        && abs(blue(litRun.base, x: 7, y: 7) - expectedCorner77) <= 2

    let unlitRunA = executeLitRun(generation: 62, lighting: nil)
    let unlitRunB = executeLitRun(generation: 63, lighting: nil)
    results["plainCaptureWithoutPayloadIsBitwiseStable"] =
        unlitRunA.prepared && unlitRunA.encoded && unlitRunA.gpu
        && unlitRunB.gpu
        && exactlyEqual(unlitRunA.base, unlitRunB.base)
        && abs(blue(unlitRunA.base, x: 4, y: 4) - 100) <= 2

    let zeroIntensityRun = executeLitRun(
        generation: 64,
        lighting: payload(
            points: [
                SceneBaseMaterialLitCapturePayload.PointLight(
                    position: SIMD3(6.25, -6.25, 0),
                    color: SIMD3(1, 1, 1),
                    intensity: 0,
                    radius: 100
                )
            ],
            ambient: SIMD3(1, 1, 1)
        )
    )
    results["zeroIntensityAndAmbientFallbackEqualUnlitExactly"] =
        zeroIntensityRun.prepared && zeroIntensityRun.encoded
        && zeroIntensityRun.gpu
        && exactlyEqual(zeroIntensityRun.base, unlitRunA.base)

    // Lit PSO failure stays fail-soft and the unlit path keeps the frame
    // complete; the recovered pipeline lights again (litCaptureResponds).
    let functionlessLibrary = try? device.makeLibrary(
        source: """
        #include <metal_stdlib>
        using namespace metal;
        kernel void unusedFixtureKernel() {}
        """,
        options: nil
    )
    let brokenLitPipeline = functionlessLibrary.flatMap {
        SceneLitImageLayerPipeline(
            device: device,
            pixelFormat: .bgra8Unorm,
            library: $0
        )
    }
    results["litPSOFunctionMissingFailsSoft"] = brokenLitPipeline == nil
    results["litPSOFailureKeepsUnlitFrameComplete"] =
        unlitRunA.prepared && unlitRunA.encoded && unlitRunA.gpu

    // Normal directionality: N tilts toward +x, so the lit side of a light
    // is the pixels left of it (direction toward the light dots with N).
    let leftLight = SceneBaseMaterialLitCapturePayload.PointLight(
        position: SIMD3(-25, 0, 50),
        color: SIMD3(1, 1, 1),
        intensity: 2,
        radius: 100
    )
    let rightLight = SceneBaseMaterialLitCapturePayload.PointLight(
        position: SIMD3(25, 0, 50),
        color: SIMD3(1, 1, 1),
        intensity: 2,
        radius: 100
    )
    let normalLeftRun = executeLitRun(
        generation: 65,
        lighting: payload(points: [leftLight], ambient: .zero, normal: normalTexture)
    )
    let normalRightRun = executeLitRun(
        generation: 66,
        lighting: payload(points: [rightLight], ambient: .zero, normal: normalTexture)
    )
    let flatLeftRun = executeLitRun(
        generation: 67,
        lighting: payload(points: [leftLight], ambient: .zero)
    )
    let flatRightRun = executeLitRun(
        generation: 68,
        lighting: payload(points: [rightLight], ambient: .zero)
    )
    results["normalDirectionChangesResponse"] =
        normalLeftRun.gpu && flatLeftRun.gpu
        && abs(
            blue(normalLeftRun.base, x: 4, y: 4)
                - blue(flatLeftRun.base, x: 4, y: 4)
        ) >= 10
    results["normalHotspotShiftsWithLightPosition"] =
        normalRightRun.gpu
        && blue(normalRightRun.base, x: 4, y: 4)
            > blue(normalLeftRun.base, x: 4, y: 4) + 10
        && blue(normalRightRun.base, x: 4, y: 4)
            > blue(normalRightRun.base, x: 7, y: 4) + 10
    results["normalRunDiffersFromFlatReference"] =
        abs(
            blue(normalRightRun.base, x: 5, y: 4)
                - blue(flatRightRun.base, x: 5, y: 4)
        ) >= 10

    // The snapshot owns authored admission; a direct caller exceeding the
    // payload capacity gets bounded truncation to the four ABI slots.
    var fiveAuthorOrdered: [
        SceneBaseMaterialLitCapturePayload.PointLight
    ] = (0 ..< 4).map { index in
        SceneBaseMaterialLitCapturePayload.PointLight(
            position: SIMD3(Float(index) * 10 - 20, 0, 0),
            color: SIMD3(1, 1, 1),
            intensity: 0,
            radius: 50
        )
    }
    fiveAuthorOrdered.append(centerLight)
    let packedFive = SceneBaseMaterialLitCapturePayload.packLights(
        pointLights: fiveAuthorOrdered,
        spotLights: [],
        ambient: SIMD3(1, 1, 1),
        material: nil, view: SIMD4(0,0,1,0),
        layerModelMatrix: layerMatrix,
        normalModelMatrix: matrix_identity_float4x4
    )
    // >4 combined image lights truncate to the four ABI slots in authored
    // order (bounded admission) instead of rejecting the whole payload.
    results["overCapacityPayloadTruncatesToFourSlots"] =
        packedFive != nil && packedFive?.lightCounts.x == 4
    let fiveLightRun = executeLitRun(
        generation: 69,
        lighting: payload(points: fiveAuthorOrdered, ambient: SIMD3(1, 1, 1))
    )
    let fourLightRun = executeLitRun(
        generation: 70,
        lighting: payload(
            points: Array(fiveAuthorOrdered.prefix(4)),
            ambient: SIMD3(1, 1, 1)
        )
    )
    let controlFifthRun = executeLitRun(
        generation: 71,
        lighting: payload(points: [centerLight], ambient: SIMD3(1, 1, 1))
    )
    results["overCapacityPayloadTruncationMatchesAuthoredPrefixRun"] =
        fiveLightRun.gpu && fourLightRun.gpu && controlFifthRun.gpu
        && exactlyEqual(fiveLightRun.base, fourLightRun.base)
        && blue(controlFifthRun.base, x: 4, y: 4)
            != blue(fourLightRun.base, x: 4, y: 4)

    // Spot cone: the spot points along +x, so only the downstream half of
    // the row receives light inside the cone.
    let downstreamSpot = SceneBaseMaterialLitCapturePayload.SpotLight(
        position: SIMD3(-25, 0, 50),
        direction: SIMD3(1, 0, -1),
        color: SIMD3(1, 1, 1),
        intensity: 5,
        radius: 200,
        innerConeCosine: 0.95,
        outerConeCosine: 0.6
    )
    let spotRun = executeLitRun(
        generation: 72,
        lighting: payload(spots: [downstreamSpot], ambient: .zero)
    )
    results["spotConeLightsOnlyDownstreamHalf"] =
        spotRun.gpu
        && blue(spotRun.base, x: 7, y: 4) > 60
        && blue(spotRun.base, x: 0, y: 4) == 0
        && blue(spotRun.base, x: 7, y: 4)
            > blue(spotRun.base, x: 0, y: 4) + 40

    // The lit result lands in the pair base capture target itself, which
    // the effect stages then consume (encode order: source capture first).
    results["litCaptureLandsInBaseTargetBeforeEffects"] =
        litRun.prepared && litRun.encoded && litRun.gpu
        && litRun.base != nil && litRun.final != nil
        && blue(litRun.base, x: 4, y: 4)
            != blue(unlitRunA.base, x: 4, y: 4)
        && blue(litRun.final, x: 4, y: 4) >= 254

    diagnostics["results"] = results
    let litCenterPixel = pixel(litRun.base, x: 4, y: 4)
    let noLightCenterPixel = pixel(noLightRun.base, x: 4, y: 4)
    let unlitCenterPixel = pixel(unlitRunA.base, x: 4, y: 4)
    let litCornerPixel = pixel(litRun.base, x: 0, y: 0)
    let normalLeftEdgePixel = pixel(normalLeftRun.base, x: 0, y: 4)
    let normalRightEdgePixel = pixel(normalLeftRun.base, x: 7, y: 4)
    let flatLeftEdgePixel = pixel(flatLeftRun.base, x: 7, y: 4)
    let flatRightHotspotPixel = pixel(flatRightRun.base, x: 5, y: 4)
    let normalRightHotspotPixel = pixel(normalRightRun.base, x: 5, y: 4)
    let spotDownstreamPixel = pixel(spotRun.base, x: 7, y: 4)
    let spotUpstreamPixel = pixel(spotRun.base, x: 0, y: 4)
    diagnostics["pixels"] = [
        "litCenter": litCenterPixel,
        "noLightCenter": noLightCenterPixel,
        "unlitCenter": unlitCenterPixel,
        "expectedCorner00": expectedCorner00,
        "expectedCorner77": expectedCorner77,
        "litCorner": litCornerPixel,
        "normalLeftEdge": normalLeftEdgePixel,
        "normalRightEdgeLeftLight": normalRightEdgePixel,
        "flatLeftEdge": flatLeftEdgePixel,
        "flatRightHotspot": flatRightHotspotPixel,
        "normalRightHotspot": normalRightHotspotPixel,
        "spotDownstream": spotDownstreamPixel,
        "spotUpstream": spotUpstreamPixel,
    ]
    return diagnostics
}
