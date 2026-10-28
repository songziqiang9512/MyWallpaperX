import CoreGraphics
import Foundation
import Metal
import simd

// Atomic pass admission, color/alpha association, formats and pixel output.
struct SceneResolvedMaterialPassColorResult {
    let facts: [String: Bool]
    let authoredTexture: MTLTexture
    let baseline: Program
    let rgbaTarget: MTLTexture
    let second: SceneResolvedMaterialPassEncoder.PreparedPass?
}

func runSceneResolvedMaterialPassColorCases(
    device: MTLDevice,
    queue: MTLCommandQueue,
    encoder: SceneResolvedMaterialPassEncoder
) -> SceneResolvedMaterialPassColorResult {
    // Four distinct quadrants keep a vertically mirrored pass from
    // satisfying a set-of-colors assertion.
    let color: [UInt8] = [
        255, 0, 0, 255, 0, 255, 0, 255,
        0, 0, 255, 255, 255, 255, 0, 255,
    ]
    let authoredTexture = texture(device: device, fill: color)
    let whiteMask = texture(
        device: device,
        fill: [UInt8](repeating: 255, count: 16)
    )
    let baseline = program(
        device: device,
        marker: 1,
        outputSlot: 3,
        slot0Texture: authoredTexture,
        slot3Texture: whiteMask
    )!
    let rgbaTarget = target(device: device)
    let first = encoder.prepare(program: baseline, target: rgbaTarget)
    let attemptsAfterFirst = encoder.pipelineCompilationAttemptCount
    let libraryAttemptsAfterFirst =
        encoder.metalLibraryCompilationAttemptCount
    let second = encoder.prepare(program: baseline, target: rgbaTarget)
    let pipelineCacheReused = second != nil
        && encoder.pipelineCompilationAttemptCount == attemptsAfterFirst

    let changedSampling = program(
        device: device,
        marker: 2,
        outputSlot: 3,
        slot3Sampling: .init(texFlags: 3)
    )!
    let samplingVariant = encoder.prepare(
        program: changedSampling,
        target: rgbaTarget
    )
    let cacheReusedAcrossResources = encoder.pipelineCompilationAttemptCount == 1

    var encoded = false
    var gpuCompleted = false
    var outputMatches = false
    var committedBufferRejected = false
    if let first, let command = queue.makeCommandBuffer() {
        encoded = encoder.encode(first, commandBuffer: command)
        command.commit()
        command.waitUntilCompleted()
        gpuCompleted = command.status == .completed && command.error == nil
        committedBufferRejected = !encoder.encode(
            first,
            commandBuffer: command
        )
        outputMatches = pixels(rgbaTarget) == color
    }

    var nonSquareColor: [UInt8] = []
    for index in 0 ..< 12 {
        nonSquareColor.append(UInt8(11 + index * 17))
        nonSquareColor.append(UInt8(7 + index * 13))
        nonSquareColor.append(UInt8(3 + index * 19))
        nonSquareColor.append(UInt8(96 + index * 11))
    }
    let nonSquareTexture = texture(
        device: device,
        width: 4,
        height: 3,
        fill: nonSquareColor
    )
    let nonSquareProgram = program(
        device: device,
        marker: 1001,
        outputSlot: 0,
        slot0Texture: nonSquareTexture
    )!
    let nonSquareTarget = target(device: device, width: 4, height: 3)
    let nonSquareResult = render(
        nonSquareProgram,
        encoder: encoder,
        queue: queue,
        target: nonSquareTarget
    )

    // The first sample is between texels; the second is outside [0, 1].
    // Actual pixels distinguish nearest/linear and repeat/clamp, rather than
    // inspecting a PreparedPass copy of the authored sampler declaration.
    let samplerTexture = texture(
        device: device, width: 2, height: 1,
        fill: [255, 0, 0, 255, 0, 255, 0, 255]
    )
    let samplerExpected: [[UInt8]] = [
        [191, 64, 0, 255, 191, 64, 0, 255],
        [255, 0, 0, 255, 255, 0, 0, 255],
        [191, 64, 0, 255, 0, 255, 0, 255],
        [255, 0, 0, 255, 0, 255, 0, 255],
    ]
    var samplerModesMatchPixels = true
    for flags in 0 ..< samplerExpected.count {
        let samplerProgram = program(
            device: device, marker: 1100 + flags, outputSlot: 0,
            slot0Texture: samplerTexture,
            fragmentSource: """
            varying vec2 v_TexCoord;
            uniform sampler2D g_Texture0;
            void main() {
                gl_FragColor = texSample2D(g_Texture0, vec2(v_TexCoord.x * 1.5, 0.5));
            }
            """,
            slot0Sampling: .init(texFlags: UInt32(flags))
        )
        let sampled = render(
            samplerProgram, encoder: encoder, queue: queue,
            target: target(device: device, width: 2, height: 1)
        )
        samplerModesMatchPixels = samplerModesMatchPixels
            && sampled.prepared && sampled.encoded && sampled.completed
            && closePixels(sampled.pixels, samplerExpected[flags], tolerance: 1)
    }

    let attemptsBeforeBGRA = encoder.pipelineCompilationAttemptCount
    let libraryAttemptsBeforeBGRA =
        encoder.metalLibraryCompilationAttemptCount
    let bgraTarget = target(device: device, format: .bgra8Unorm)
    let bgraPrepared = encoder.prepare(program: baseline, target: bgraTarget)
    let separateFormatPipeline = bgraPrepared != nil
        && encoder.pipelineCompilationAttemptCount == attemptsBeforeBGRA + 1
    let libraryReusedAcrossPipelineVariants =
        encoder.metalLibraryCompilationAttemptCount
            == libraryAttemptsBeforeBGRA

    let straight = program(
        device: device,
        marker: 3,
        outputSlot: 0,
        slot0Content: .color(.resolved(.straightAlpha)),
        slot0Purpose: .straightAlbedo
    )!
    let straightStoredWithoutAssociation = encoder.prepare(
        program: straight,
        target: rgbaTarget
    )?.fragmentOutput == .straightAlpha
    let unresolvedRejectedUpstream = program(
        device: device,
        marker: 4,
        outputSlot: 0,
        unresolved: true
    ) == nil

    let aliasTexture = target(device: device)
    let aliasProgram = program(
        device: device,
        marker: 5,
        outputSlot: 0,
        slot0Texture: aliasTexture
    )!
    let aliasRejected = encoder.prepare(
        program: aliasProgram,
        target: aliasTexture
    ) == nil

    let shortGraphTexture = texture(
        device: device,
        width: 1,
        height: 1,
        fill: [32, 64, 96, 128]
    )
    let shortGraph = program(
        device: device,
        marker: 6,
        outputSlot: 0,
        slot0Texture: shortGraphTexture
    )!
    let crossExtentTarget = target(device: device)
    let crossExtentPrepared = encoder.prepare(
        program: shortGraph,
        target: crossExtentTarget
    )
    var crossExtentEncoded = false
    var crossExtentGPUCompleted = false
    var crossExtentOutputMatches = false
    if let crossExtentPrepared, let command = queue.makeCommandBuffer() {
        crossExtentEncoded = encoder.encode(
            crossExtentPrepared,
            commandBuffer: command
        )
        command.commit()
        command.waitUntilCompleted()
        crossExtentGPUCompleted = command.status == .completed
            && command.error == nil
        let output = pixels(crossExtentTarget)
        crossExtentOutputMatches = stride(from: 0, to: 16, by: 4)
            .allSatisfy { Array(output[$0 ..< $0 + 4]) == [32, 64, 96, 128] }
    }

    let premultipliedPixel = texture(
        device: device,
        width: 1,
        height: 1,
        fill: [64, 32, 16, 128]
    )
    let straightCases: [(Float, [UInt8])] = [
        (0.0, [0, 0, 0, 0]),
        (0.5, [32, 16, 8, 64]),
        (1.0, [64, 32, 16, 128]),
    ]
    var straightBoundaryPrepared = true
    var straightBoundaryGPUCompleted = true
    var straightBoundaryPixelsMatch = true
    var straightBoundaryPremultiplied = true
    for (index, testCase) in straightCases.enumerated() {
        let straightProgram = program(
            device: device,
            marker: 20 + index,
            outputSlot: 0,
            slot0Texture: premultipliedPixel,
            slot3Content: .data,
            slot3Purpose: .mask,
            fragmentSource: straightAlphaFragment,
            gain: testCase.0
        )!
        let output = target(device: device, width: 1, height: 1)
        guard let prepared = encoder.prepare(program: straightProgram, target: output),
              prepared.fragmentOutput == .premultipliedAlpha,
              let command = queue.makeCommandBuffer() else {
            straightBoundaryPrepared = false
            continue
        }
        guard encoder.encode(prepared, commandBuffer: command) else {
            straightBoundaryPrepared = false
            continue
        }
        command.commit()
        command.waitUntilCompleted()
        straightBoundaryGPUCompleted = straightBoundaryGPUCompleted
            && command.status == .completed
            && command.error == nil
        let actual = pixels(output)
        straightBoundaryPixelsMatch = straightBoundaryPixelsMatch
            && zip(actual, testCase.1).allSatisfy {
                abs(Int($0.0) - Int($0.1)) <= 1
            }
        straightBoundaryPremultiplied = straightBoundaryPremultiplied
            && actual[0] <= actual[3]
            && actual[1] <= actual[3]
            && actual[2] <= actual[3]
    }

    let factoredAlphaProgram = program(
        device: device,
        marker: 29,
        outputSlot: 0,
        slot0Texture: premultipliedPixel,
        fragmentSource: straightRGBFactoredAlphaFragment,
        gain: 0.5
    )
    let factoredAlphaResult = render(
        factoredAlphaProgram,
        encoder: encoder,
        queue: queue,
        target: target(device: device, width: 1, height: 1)
    )
    let factoredAlphaPixelsMatch = closePixels(
        factoredAlphaResult.pixels,
        [32, 16, 8, 64]
    )

    let scanlineUniforms = [
        "g_Weight": bytes(Float(0.5)),
        "g_Tint": bytes(SIMD3<Float>(1, 0, 0)),
    ]
    let scanlineProgram = program(
        device: device,
        marker: 31,
        outputSlot: 0,
        slot0Texture: premultipliedPixel,
        fragmentSource: scanlineUniformRGBMixFragment,
        uniformValues: scanlineUniforms,
        slot0GraphKind: .layerSource
    )
    let scanlineResult = render(
        scanlineProgram,
        encoder: encoder,
        queue: queue,
        target: target(device: device, width: 1, height: 1)
    )
    // Stored source [64, 32, 16, 128] represents straight
    // [0.5, 0.25, 0.125, 0.5]. A 50% mix with straight red produces
    // [0.75, 0.125, 0.0625] before the final premultiply.
    let scanlinePixelsMatch = closePixels(
        scanlineResult.pixels,
        [96, 16, 8, 128]
    )

    let scanlineIdentityProgram = program(
        device: device,
        marker: 32,
        outputSlot: 0,
        slot0Texture: premultipliedPixel,
        fragmentSource: scanlineUniformRGBMixFragment,
        uniformValues: [
            "g_Weight": bytes(Float(0)),
            "g_Tint": bytes(SIMD3<Float>(0, 1, 0)),
        ],
        slot0GraphKind: .layerSource
    )
    let scanlineIdentityResult = render(
        scanlineIdentityProgram,
        encoder: encoder,
        queue: queue,
        target: target(device: device, width: 1, height: 1)
    )
    let scanlineIdentityMatches = closePixels(
        scanlineIdentityResult.pixels,
        [64, 32, 16, 128]
    )

    let scalarNoise = texture(
        device: device,
        width: 1,
        height: 1,
        fill: [128, 0, 0, 255]
    )
    let scalarNoiseSlot = slot(
        device: device,
        index: 1,
        texture: scalarNoise,
        content: .data,
        purpose: .noise,
        sampling: .init(texFlags: 3),
        marker: 29
    )
    let scalarAlphaUniforms = [
        "g_Time": bytes(Float(0)),
        "g_Amount": bytes(Float(1)),
        "g_NoiseAmount": bytes(Float(0.5)),
        "g_Power": bytes(Float(1)),
    ]
    let scalarAlphaProgram = program(
        device: device,
        marker: 28,
        outputSlot: 0,
        slot0Texture: premultipliedPixel,
        slot3Texture: texture(
            device: device, width: 1, height: 1, fill: [0, 0, 0, 255]
        ),
        slot3Content: .data,
        slot3Purpose: .mask,
        fragmentSource: straightRGBScalarAlphaFragment,
        additionalSlots: [scalarNoiseSlot],
        uniformValues: scalarAlphaUniforms
    )
    let scalarAlphaResult = render(
        scalarAlphaProgram,
        encoder: encoder,
        queue: queue,
        target: target(device: device, width: 1, height: 1)
    )
    let scalarAlphaPixelsMatch = closePixels(
        scalarAlphaResult.pixels,
        [48, 24, 12, 96]
    )
    let scalarNoiseColorSlot = slot(
        device: device,
        index: 1,
        texture: scalarNoise,
        content: .color(.resolved(.premultipliedAlpha)),
        purpose: .premultipliedColor,
        sampling: .init(texFlags: 3),
        marker: 30
    )
    let scalarAlphaColorAuxiliaryRejected = program(
        device: device,
        marker: 27,
        outputSlot: 0,
        slot0Texture: premultipliedPixel,
        slot3Texture: texture(
            device: device, width: 1, height: 1, fill: [0, 0, 0, 255]
        ),
        slot3Content: .data,
        slot3Purpose: .mask,
        fragmentSource: straightRGBScalarAlphaFragment,
        additionalSlots: [scalarNoiseColorSlot],
        uniformValues: scalarAlphaUniforms
    ) == nil

    let maskPixel = texture(
        device: device,
        width: 1,
        height: 1,
        fill: [128, 0, 0, 255]
    )
    let maskedProgram = program(
        device: device,
        marker: 30,
        outputSlot: 0,
        slot0Texture: premultipliedPixel,
        slot3Texture: maskPixel,
        slot3Content: .data,
        slot3Purpose: .mask,
        fragmentSource: maskedAlphaFragment,
        gain: 0.5
    )
    let secondColorRejected = program(
        device: device,
        marker: 31,
        outputSlot: 0,
        slot0Texture: premultipliedPixel,
        slot3Texture: maskPixel,
        slot3Content: .color(.resolved(.straightAlpha)),
        slot3Purpose: .straightAlbedo,
        fragmentSource: maskedAlphaFragment,
        gain: 0.5
    ) == nil
    var maskedBoundaryPrepared = false
    var maskedBoundaryGPUCompleted = false
    var maskedBoundaryPixelsMatch = false
    let maskedTarget = target(device: device, width: 1, height: 1)
    if let maskedProgram,
       let prepared = encoder.prepare(program: maskedProgram, target: maskedTarget),
       let command = queue.makeCommandBuffer() {
        maskedBoundaryPrepared = prepared.fragmentOutput == .premultipliedAlpha
        if encoder.encode(prepared, commandBuffer: command) {
            command.commit()
            command.waitUntilCompleted()
            maskedBoundaryGPUCompleted = command.status == .completed
                && command.error == nil
            maskedBoundaryPixelsMatch = zip(
                pixels(maskedTarget), [UInt8(16), 8, 4, 32]
            ).allSatisfy { abs(Int($0.0) - Int($0.1)) <= 1 }
        }
    }

    let overlayBase = texture(
        device: device,
        width: 1,
        height: 1,
        fill: [128, 0, 0, 128]
    )
    let overlayData = texture(
        device: device,
        width: 1,
        height: 1,
        fill: [0, 255, 0, 64]
    )
    let overlayDataSlot = slot(
        device: device,
        index: 1,
        texture: overlayData,
        content: .data,
        purpose: .preservedChannels,
        sampling: .directImageFallback,
        marker: 41
    )
    let overlayProgram = program(
        device: device,
        marker: 40,
        outputSlot: 0,
        slot0Texture: overlayBase,
        fragmentSource: overlayAlphaBlendFragment,
        additionalSlots: [overlayDataSlot],
        uniformValues: [
            "g_Multiply": bytes(Float(0.5)),
            "g_AlphaMultiply": bytes(Float(0.5)),
        ]
    )
    let overlayColorSlot = slot(
        device: device,
        index: 1,
        texture: overlayData,
        content: .color(.resolved(.premultipliedAlpha)),
        purpose: .premultipliedColor,
        sampling: .directImageFallback,
        marker: 42
    )
    let overlayPremultipliedColorRejected = program(
        device: device,
        marker: 43,
        outputSlot: 0,
        slot0Texture: overlayBase,
        fragmentSource: overlayAlphaBlendFragment,
        additionalSlots: [overlayColorSlot],
        uniformValues: [
            "g_Multiply": bytes(Float(0.5)),
            "g_AlphaMultiply": bytes(Float(0.5)),
        ]
    ) == nil
    let overlayResult = render(
        overlayProgram,
        encoder: encoder,
        queue: queue,
        target: target(device: device, width: 1, height: 1)
    )
    let overlayBoundaryPixelsMatch = closePixels(
        overlayResult.pixels,
        [28, 4, 0, 32]
    )
    let associatedOverProgram = program(
        device: device,
        marker: 44,
        outputSlot: 0,
        slot0Texture: overlayBase,
        fragmentSource: associatedOverBlendFragment,
        additionalSlots: [overlayDataSlot],
        uniformValues: ["g_ScalarWeight": bytes(Float(0.5))]
    )
    let associatedOverResult = render(
        associatedOverProgram,
        encoder: encoder,
        queue: queue,
        target: target(device: device, width: 1, height: 1)
    )
    let associatedOverPixelsMatch = closePixels(
        associatedOverResult.pixels,
        [50, 46, 0, 96]
    )

    // One row exercises opaque passthrough, offset shadow, and empty-offset
    // fallback with nearest sampling.
    let conditionalShadowSource = texture(
        device: device,
        width: 4,
        height: 1,
        fill: [
            128, 0, 0, 255,
            0, 0, 0, 0,
            0, 64, 0, 128,
            0, 0, 0, 0,
        ]
    )
    let conditionalShadowProgram = program(
        device: device,
        marker: 44,
        outputSlot: 0,
        slot0Texture: conditionalShadowSource,
        fragmentSource: conditionalShadowFragment,
        uniformValues: [
            "g_Border": bytes(Float(0.75)),
            "g_Weight": bytes(Float(0.5)),
            "g_Shadow": bytes(SIMD3<Float>(0, 0, 1)),
        ],
        slot0Sampling: .init(texFlags: 3),
        slot0GraphKind: .layerSource
    )
    let conditionalShadowResult = render(
        conditionalShadowProgram,
        encoder: encoder,
        queue: queue,
        target: target(device: device, width: 4, height: 1)
    )
    let conditionalShadowPixelsMatch = closePixels(
        conditionalShadowResult.pixels,
        [
            128, 0, 0, 255,
            0, 0, 32, 64,
            0, 64, 0, 128,
            0, 0, 0, 0,
        ]
    )

    let filterInputBytes: [UInt8] = [
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 128, 64, 32, 128, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    ]
    let filterInput = texture(
        device: device,
        width: 3,
        height: 3,
        fill: filterInputBytes
    )
    let whiteFilterMask = texture(
        device: device,
        width: 3,
        height: 3,
        fill: [UInt8](repeating: 255, count: 36)
    )
    let whiteFilterMaskSlot = slot(
        device: device,
        index: 1,
        texture: whiteFilterMask,
        content: .data,
        purpose: .mask,
        sampling: .init(texFlags: 3),
        marker: 51
    )
    let wholeFilterProgram = program(
        device: device,
        marker: 50,
        outputSlot: 0,
        slot0Texture: filterInput,
        fragmentSource: wholeColorFilterFragment,
        additionalSlots: [whiteFilterMaskSlot],
        uniformValues: [
            "g_TexelSize": bytes(SIMD2<Float>(repeating: 1.0 / 3.0)),
            "g_Strength": bytes(Float(1)),
        ],
        slot0Sampling: .init(texFlags: 3),
        slot0GraphKind: .layerSource
    )
    let wholeFilterResult = render(
        wholeFilterProgram,
        encoder: encoder,
        queue: queue,
        target: target(device: device, width: 3, height: 3)
    )
    var wholeFilterExpected = [UInt8](repeating: 0, count: 36)
    wholeFilterExpected.replaceSubrange(
        16 ..< 20,
        with: [UInt8(224), 196, 98, 224]
    )
    let wholeFilterPixelsMatch = closePixels(
        wholeFilterResult.pixels,
        wholeFilterExpected,
        tolerance: 1
    )

    let blackFilterMask = texture(
        device: device,
        width: 3,
        height: 3,
        fill: [UInt8](repeating: 0, count: 36)
    )
    let blackFilterMaskSlot = slot(
        device: device,
        index: 1,
        texture: blackFilterMask,
        content: .data,
        purpose: .mask,
        sampling: .init(texFlags: 3),
        marker: 53
    )
    let wholeFilterBlackMaskProgram = program(
        device: device,
        marker: 52,
        outputSlot: 0,
        slot0Texture: filterInput,
        fragmentSource: wholeColorFilterFragment,
        additionalSlots: [blackFilterMaskSlot],
        uniformValues: [
            "g_TexelSize": bytes(SIMD2<Float>(repeating: 1.0 / 3.0)),
            "g_Strength": bytes(Float(1)),
        ],
        slot0Sampling: .init(texFlags: 3),
        slot0GraphKind: .layerSource
    )
    let wholeFilterBlackMaskResult = render(
        wholeFilterBlackMaskProgram,
        encoder: encoder,
        queue: queue,
        target: target(device: device, width: 3, height: 3)
    )
    let wholeFilterBlackMaskIdentity = closePixels(
        wholeFilterBlackMaskResult.pixels,
        filterInputBytes,
        tolerance: 1
    )

    let facts: [String: Bool] = [
        "metalAvailable": true,
        "prepared": first != nil,
        "pipelineCompiledOnce": attemptsAfterFirst == 1,
        "metalLibraryCompiledOnce": libraryAttemptsAfterFirst == 1,
        "pipelineCacheReused": pipelineCacheReused,
        "cacheReusedAcrossResources": cacheReusedAcrossResources,
        "samplerModesMatchActualPixels": samplerModesMatchPixels,
        "baselineOutputPremultiplied": first?.fragmentOutput
            == .premultipliedAlpha,
        "premultipliedOutputPublished": crossExtentPrepared?.fragmentOutput
            == .premultipliedAlpha,
        "commandsEncoded": encoded,
        "gpuCompleted": gpuCompleted,
        "committedCommandBufferRejected": committedBufferRejected,
        "outputMatches": outputMatches,
        "directClipNonSquarePrepared": nonSquareResult.prepared,
        "directClipNonSquareEncoded": nonSquareResult.encoded,
        "directClipNonSquareGPUCompleted": nonSquareResult.completed,
        "directClipNonSquarePixelsMatch": nonSquareResult.pixels
            == nonSquareColor,
        "rgbaAndBgraSupported": separateFormatPipeline,
        "metalLibraryReusedAcrossPipelineVariants":
            libraryReusedAcrossPipelineVariants,
        "straightOutputStoredWithoutAssociation": straightStoredWithoutAssociation,
        "unresolvedOutputRejectedUpstream": unresolvedRejectedUpstream,
        "inputTargetAliasRejected": aliasRejected,
        "crossExtentGraphPrepared": crossExtentPrepared != nil,
        "crossExtentGraphEncoded": crossExtentEncoded,
        "crossExtentGraphGPUCompleted": crossExtentGPUCompleted,
        "crossExtentGraphOutputMatches": crossExtentOutputMatches,
        "straightBoundaryPrepared": straightBoundaryPrepared,
        "straightBoundaryGPUCompleted": straightBoundaryGPUCompleted,
        "straightBoundaryPixelsMatch": straightBoundaryPixelsMatch,
        "straightBoundaryPremultiplied": straightBoundaryPremultiplied,
        "factoredAlphaPrepared": factoredAlphaResult.prepared,
        "factoredAlphaEncoded": factoredAlphaResult.encoded,
        "factoredAlphaGPUCompleted": factoredAlphaResult.completed,
        "factoredAlphaPixelsMatch": factoredAlphaPixelsMatch,
        "scanlineUniformRGBMixPrepared": scanlineResult.prepared
            && scanlineIdentityResult.prepared,
        "scanlineUniformRGBMixEncoded": scanlineResult.encoded
            && scanlineIdentityResult.encoded,
        "scanlineUniformRGBMixGPUCompleted": scanlineResult.completed
            && scanlineIdentityResult.completed,
        "scanlineUniformRGBMixPixelsMatch": scanlinePixelsMatch,
        "scanlineUniformRGBMixWeightZeroIdentity": scanlineIdentityMatches,
        "scalarAlphaPrepared": scalarAlphaResult.prepared,
        "scalarAlphaEncoded": scalarAlphaResult.encoded,
        "scalarAlphaGPUCompleted": scalarAlphaResult.completed,
        "scalarAlphaPixelsMatch": scalarAlphaPixelsMatch,
        "scalarAlphaColorAuxiliaryRejected": scalarAlphaColorAuxiliaryRejected,
        "maskedBoundaryPrepared": maskedBoundaryPrepared,
        "maskedBoundaryGPUCompleted": maskedBoundaryGPUCompleted,
        "maskedBoundaryPixelsMatch": maskedBoundaryPixelsMatch,
        "secondColorRejected": secondColorRejected,
        "overlayBoundaryPrepared": overlayResult.prepared,
        "overlayBoundaryEncoded": overlayResult.encoded,
        "overlayBoundaryGPUCompleted": overlayResult.completed,
        "overlayBoundaryPixelsMatch": overlayBoundaryPixelsMatch,
        "associatedOverPrepared": associatedOverResult.prepared,
        "associatedOverEncoded": associatedOverResult.encoded,
        "associatedOverGPUCompleted": associatedOverResult.completed,
        "associatedOverPixelsMatch": associatedOverPixelsMatch,
        "conditionalShadowPrepared": conditionalShadowResult.prepared,
        "conditionalShadowEncoded": conditionalShadowResult.encoded,
        "conditionalShadowGPUCompleted": conditionalShadowResult.completed,
        "conditionalShadowPixelsMatch": conditionalShadowPixelsMatch,
        "wholeFilterPrepared": wholeFilterResult.prepared,
        "wholeFilterEncoded": wholeFilterResult.encoded,
        "wholeFilterGPUCompleted": wholeFilterResult.completed,
        "wholeFilterPixelsMatch": wholeFilterPixelsMatch,
        "wholeFilterBlackMaskPrepared": wholeFilterBlackMaskResult.prepared,
        "wholeFilterBlackMaskEncoded": wholeFilterBlackMaskResult.encoded,
        "wholeFilterBlackMaskGPUCompleted": wholeFilterBlackMaskResult.completed,
        "wholeFilterBlackMaskIdentity": wholeFilterBlackMaskIdentity,
        "overlayPremultipliedColorRejectedUpstream":
            overlayPremultipliedColorRejected,
    ]
    return .init(facts: facts, authoredTexture: authoredTexture,
        baseline: baseline, rgbaTarget: rgbaTarget, second: second)
}
