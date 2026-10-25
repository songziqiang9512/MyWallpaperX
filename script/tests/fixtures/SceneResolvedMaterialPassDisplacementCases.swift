import CoreGraphics
import Foundation
import Metal
import simd

// CPU sampling oracles and authored flow/shimmer GPU cases share one contract.
private func fract(_ value: Float) -> Float {
    value - floor(value)
}

private func clamp01(_ value: Float) -> Float {
    min(1, max(0, value))
}

private func smoothstep(_ low: Float, _ high: Float, _ value: Float) -> Float {
    let unit = clamp01((value - low) / (high - low))
    return unit * unit * (3 - 2 * unit)
}

private func addressedIndex(_ index: Int, count: Int, repeats: Bool) -> Int {
    guard repeats else { return min(count - 1, max(0, index)) }
    let remainder = index % count
    return remainder >= 0 ? remainder : remainder + count
}

private func quantized(_ values: [SIMD4<Float>]) -> [UInt8] {
    values.flatMap { value in
        (0 ..< 4).map { component in
            UInt8((clamp01(value[component]) * 255).rounded())
        }
    }
}

private func linearAxis(
    coordinate: Float,
    count: Int,
    repeats: Bool
) -> (lower: Int, upper: Int, weight: Float) {
    let position = coordinate * Float(count) - 0.5
    let rawLower = Int(floor(position))
    return (
        addressedIndex(rawLower, count: count, repeats: repeats),
        addressedIndex(rawLower + 1, count: count, repeats: repeats),
        position - floor(position)
    )
}

private func nearestAxis(
    coordinate: Float,
    count: Int,
    repeats: Bool
) -> Int {
    addressedIndex(
        Int(floor(coordinate * Float(count))),
        count: count,
        repeats: repeats
    )
}

private func sampleColor2D(
    _ source: [UInt8],
    width: Int,
    height: Int,
    coordinate: SIMD2<Float>,
    linear: Bool
) -> SIMD4<Float> {
    func value(x: Int, y: Int) -> SIMD4<Float> {
        let bytes = pixel(source, at: y * width + x)!
        return SIMD4<Float>(
            Float(bytes[0]) / 255,
            Float(bytes[1]) / 255,
            Float(bytes[2]) / 255,
            Float(bytes[3]) / 255
        )
    }
    guard linear else {
        return value(
            x: nearestAxis(coordinate: coordinate.x, count: width, repeats: false),
            y: nearestAxis(coordinate: coordinate.y, count: height, repeats: false)
        )
    }
    let x = linearAxis(coordinate: coordinate.x, count: width, repeats: false)
    let y = linearAxis(coordinate: coordinate.y, count: height, repeats: false)
    let top = value(x: x.lower, y: y.lower)
        + x.weight * (value(x: x.upper, y: y.lower) - value(x: x.lower, y: y.lower))
    let bottom = value(x: x.lower, y: y.upper)
        + x.weight * (value(x: x.upper, y: y.upper) - value(x: x.lower, y: y.upper))
    return top + y.weight * (bottom - top)
}

private func sampleRG8(
    _ source: [UInt8],
    width: Int,
    height: Int,
    coordinate: SIMD2<Float>
) -> SIMD2<Float> {
    func value(x: Int, y: Int) -> SIMD2<Float> {
        let start = (y * width + x) * 2
        return SIMD2(
            Float(source[start]) / 255,
            Float(source[start + 1]) / 255
        )
    }
    let x = linearAxis(coordinate: coordinate.x, count: width, repeats: false)
    let y = linearAxis(coordinate: coordinate.y, count: height, repeats: false)
    let top = value(x: x.lower, y: y.lower)
        + x.weight * (value(x: x.upper, y: y.lower) - value(x: x.lower, y: y.lower))
    let bottom = value(x: x.lower, y: y.upper)
        + x.weight * (value(x: x.upper, y: y.upper) - value(x: x.lower, y: y.upper))
    return top + y.weight * (bottom - top)
}

private func sampleR8(
    _ source: [UInt8],
    width: Int,
    height: Int,
    coordinate: SIMD2<Float>,
    repeats: Bool
) -> Float {
    func value(x: Int, y: Int) -> Float {
        Float(source[y * width + x]) / 255
    }
    let x = linearAxis(coordinate: coordinate.x, count: width, repeats: repeats)
    let y = linearAxis(coordinate: coordinate.y, count: height, repeats: repeats)
    let top = value(x: x.lower, y: y.lower)
        + x.weight * (value(x: x.upper, y: y.lower) - value(x: x.lower, y: y.lower))
    let bottom = value(x: x.lower, y: y.upper)
        + x.weight * (value(x: x.upper, y: y.upper) - value(x: x.lower, y: y.upper))
    return top + y.weight * (bottom - top)
}

private func flowOracle2D(
    source: [UInt8],
    width: Int,
    height: Int,
    flow: [UInt8],
    flowWidth: Int,
    flowHeight: Int,
    phase: [UInt8],
    phaseWidth: Int,
    phaseHeight: Int,
    time: Float,
    rate: Float,
    magnitude: Float,
    feather: Float,
    phaseTiling: Float,
    linearSource: Bool = true,
    saturatesFlowAmount: Bool = false
) -> [UInt8] {
    let clock = time * rate
    let cycle = SIMD4<Float>(
        fract(clock),
        fract(clock + 0.5),
        fract(clock + 0.25),
        fract(clock + 0.75)
    )
    let signed = cycle - SIMD4<Float>(repeating: 0.5)
    let firstBlend = smoothstep(
        0.5 - feather,
        0.5 + feather,
        2 * abs(cycle.x - 0.5)
    )
    let secondBlend = smoothstep(
        0.5 - feather,
        0.5 + feather,
        2 * abs(cycle.z - 0.5)
    )
    var result: [SIMD4<Float>] = []
    result.reserveCapacity(width * height)
    for y in 0 ..< height {
        for x in 0 ..< width {
            let coordinate = SIMD2<Float>(
                (Float(x) + 0.5) / Float(width),
                (Float(y) + 0.5) / Float(height)
            )
            let rawFlow = sampleRG8(
                flow,
                width: flowWidth,
                height: flowHeight,
                coordinate: coordinate
            )
            let vector = 2 * (rawFlow - SIMD2<Float>(repeating: 0.498))
            let offset = 0.1 * magnitude * vector
            let base = sampleColor2D(
                source,
                width: width,
                height: height,
                coordinate: coordinate,
                linear: linearSource
            )
            func shifted(_ amount: Float) -> SIMD4<Float> {
                sampleColor2D(
                    source,
                    width: width,
                    height: height,
                    coordinate: coordinate + offset * amount,
                    linear: linearSource
                )
            }
            let firstStart = shifted(signed.x)
            let first = firstStart
                + firstBlend * (shifted(signed.y) - firstStart)
            let secondStart = shifted(signed.z)
            let second = secondStart
                + secondBlend * (shifted(signed.w) - secondStart)
            let phaseValue = sampleR8(
                phase,
                width: phaseWidth,
                height: phaseHeight,
                coordinate: coordinate * phaseTiling,
                repeats: true
            )
            let selector = smoothstep(0.2, 0.8, phaseValue)
            let displaced = first + selector * (second - first)
            let rawAmount = simd_length(vector)
            let flowAmount = saturatesFlowAmount ? min(1, rawAmount) : rawAmount
            result.append(base + flowAmount * (displaced - base))
        }
    }
    return quantized(result)
}

private func excessCentroid(
    _ values: [UInt8],
    width: Int,
    height: Int,
    channel: Int,
    baseline: UInt8
) -> SIMD2<Float>? {
    var weighted = SIMD2<Float>(repeating: 0)
    var total: Float = 0
    for y in 0 ..< height {
        for x in 0 ..< width {
            let value = values[(y * width + x) * 4 + channel]
            let weight = Float(max(0, Int(value) - Int(baseline)))
            weighted += weight * SIMD2(Float(x), Float(y))
            total += weight
        }
    }
    return total > 0 ? weighted / total : nil
}

private func positiveDeltaCentroid(
    output: [UInt8],
    baseline: [UInt8],
    width: Int,
    height: Int
) -> SIMD2<Float>? {
    guard output.count == baseline.count else { return nil }
    var weighted = SIMD2<Float>(repeating: 0)
    var total: Float = 0
    for y in 0 ..< height {
        for x in 0 ..< width {
            let start = (y * width + x) * 4
            let weight = Float((0 ..< 3).reduce(0) { partial, component in
                partial + max(
                    0,
                    Int(output[start + component]) - Int(baseline[start + component])
                )
            })
            weighted += weight * SIMD2(Float(x), Float(y))
            total += weight
        }
    }
    return total > 0 ? weighted / total : nil
}




struct SceneResolvedMaterialPassDisplacementResult {
    let facts: [String: Bool]
    let flow2DVector: SIMD2<Float>
    let flow2DSampleOffset: SIMD2<Float>
    let flow2DVisibleShift: SIMD2<Float>
    let shimmer2DCentroidShift: SIMD2<Float>
}

func runSceneResolvedMaterialPassDisplacementCases(
    device: MTLDevice,
    queue: MTLCommandQueue,
    encoder: SceneResolvedMaterialPassEncoder
) -> SceneResolvedMaterialPassDisplacementResult {
    let flowRate: Float = 0.33
    let flowMagnitude: Float = 0.45
    let flowFeather: Float = 0.159
    let phaseTiling: Float = 2
    let flow2DWidth = 48
    let flow2DHeight = 36
    var flow2DSourceBytes: [UInt8] = []
    flow2DSourceBytes.reserveCapacity(flow2DWidth * flow2DHeight * 4)
    for y in 0 ..< flow2DHeight {
        for x in 0 ..< flow2DWidth {
            let primary = max(
                0,
                140 - 18 * abs(x - 27) - 22 * abs(y - 17)
            )
            let tail = max(
                0,
                72 - 20 * abs(x - 20) - 24 * abs(y - 22)
            )
            let alpha = 96 + (7 * x + 11 * y) % 160
            let red = min(240, 20 + primary + tail / 2)
            let green = min(220, 12 + primary / 3 + tail)
            let blue = min(180, 8 + primary / 5 + tail / 2)
            flow2DSourceBytes.append(contentsOf: [
                UInt8(red * alpha / 255),
                UInt8(green * alpha / 255),
                UInt8(blue * alpha / 255),
                UInt8(alpha),
            ])
        }
    }
    let flow2DSource = texture(
        device: device,
        width: flow2DWidth,
        height: flow2DHeight,
        fill: flow2DSourceBytes
    )
    let flow2DRaw = Array(
        repeating: [UInt8(255), UInt8(224)],
        count: flow2DWidth * flow2DHeight
    ).flatMap { $0 }
    let flow2DMap = texture(
        device: device,
        format: .rg8Unorm,
        width: flow2DWidth,
        height: flow2DHeight,
        fill: flow2DRaw
    )
    let flow2DPhaseWidth = 2
    let flow2DPhaseHeight = 2
    let flow2DPhaseBytes = [UInt8](repeating: 0, count: 4)
    let flow2DPhase = texture(
        device: device,
        format: .r8Unorm,
        width: flow2DPhaseWidth,
        height: flow2DPhaseHeight,
        fill: flow2DPhaseBytes
    )
    let flow2DSlot = slot(
        device: device,
        index: 1,
        texture: flow2DMap,
        content: .data,
        purpose: .flow,
        sampling: .init(texFlags: 2),
        marker: 60
    )
    let flow2DPhaseSlot = slot(
        device: device,
        index: 2,
        texture: flow2DPhase,
        content: .data,
        purpose: .phase,
        sampling: .init(texFlags: 0),
        marker: 61
    )
    func flow2DProgram(marker: Int, time: Float) -> Program? {
        program(
            device: device,
            marker: marker,
            outputSlot: 0,
            slot0Texture: flow2DSource,
            fragmentSource: boundedFlowFragment,
            additionalSlots: [flow2DSlot, flow2DPhaseSlot],
            uniformValues: [
                "g_Time": bytes(time),
                "g_Rate": bytes(flowRate),
                "g_Magnitude": bytes(flowMagnitude),
                "g_Feather": bytes(flowFeather),
                "g_PhaseTiling": bytes(phaseTiling),
            ],
            slot0Sampling: .init(texFlags: 2)
        )
    }
    let flow2DClock: Float = 0.16
    let flow2DTime = flow2DClock / flowRate
    let flow2DOtherTime: Float = 0.39 / flowRate
    let flow2DAtTime = render(
        flow2DProgram(marker: 62, time: flow2DTime),
        encoder: encoder,
        queue: queue,
        target: target(
            device: device,
            width: flow2DWidth,
            height: flow2DHeight
        )
    )
    let flow2DAtOtherTime = render(
        flow2DProgram(marker: 63, time: flow2DOtherTime),
        encoder: encoder,
        queue: queue,
        target: target(
            device: device,
            width: flow2DWidth,
            height: flow2DHeight
        )
    )
    let expectedFlow2D = flowOracle2D(
        source: flow2DSourceBytes,
        width: flow2DWidth,
        height: flow2DHeight,
        flow: flow2DRaw,
        flowWidth: flow2DWidth,
        flowHeight: flow2DHeight,
        phase: flow2DPhaseBytes,
        phaseWidth: flow2DPhaseWidth,
        phaseHeight: flow2DPhaseHeight,
        time: flow2DTime,
        rate: flowRate,
        magnitude: flowMagnitude,
        feather: flowFeather,
        phaseTiling: phaseTiling
    )
    let expectedOtherFlow2D = flowOracle2D(
        source: flow2DSourceBytes,
        width: flow2DWidth,
        height: flow2DHeight,
        flow: flow2DRaw,
        flowWidth: flow2DWidth,
        flowHeight: flow2DHeight,
        phase: flow2DPhaseBytes,
        phaseWidth: flow2DPhaseWidth,
        phaseHeight: flow2DPhaseHeight,
        time: flow2DOtherTime,
        rate: flowRate,
        magnitude: flowMagnitude,
        feather: flowFeather,
        phaseTiling: phaseTiling
    )
    let saturatedFlow2D = flowOracle2D(
        source: flow2DSourceBytes,
        width: flow2DWidth,
        height: flow2DHeight,
        flow: flow2DRaw,
        flowWidth: flow2DWidth,
        flowHeight: flow2DHeight,
        phase: flow2DPhaseBytes,
        phaseWidth: flow2DPhaseWidth,
        phaseHeight: flow2DPhaseHeight,
        time: flow2DTime,
        rate: flowRate,
        magnitude: flowMagnitude,
        feather: flowFeather,
        phaseTiling: phaseTiling,
        saturatesFlowAmount: true
    )
    let flow2DVector = 2 * (
        SIMD2<Float>(1, Float(224) / 255)
            - SIMD2<Float>(repeating: 0.498)
    )
    // At clock 0.16 the blend selects the +0.16 cycle. The shader samples
    // source UV in +F, so the visible authored feature must move toward -F.
    let flow2DSampleOffset = 0.1 * flowMagnitude * flow2DClock * flow2DVector
    let flow2DSourceCentroid = excessCentroid(
        flow2DSourceBytes,
        width: flow2DWidth,
        height: flow2DHeight,
        channel: 0,
        baseline: 20
    )
    let flow2DOutputCentroid = excessCentroid(
        flow2DAtTime.pixels,
        width: flow2DWidth,
        height: flow2DHeight,
        channel: 0,
        baseline: 20
    )
    let flow2DVisibleShift = if let source = flow2DSourceCentroid,
                                let output = flow2DOutputCentroid {
        output - source
    } else {
        SIMD2<Float>(repeating: 0)
    }
    let flow2DMatchesOracle = closePixels(
        flow2DAtTime.pixels,
        expectedFlow2D
    ) && closePixels(flow2DAtOtherTime.pixels, expectedOtherFlow2D)
    let flow2DRejectsWrongOracle = !closePixels(
        flow2DAtTime.pixels,
        saturatedFlow2D
    )
    let flow2DTimeChanges = flow2DAtTime.pixels != flow2DAtOtherTime.pixels
    let flow2DAlphaMoves = stride(
        from: 3, to: flow2DSourceBytes.count, by: 4
    ).contains { flow2DAtTime.pixels[$0] != flow2DSourceBytes[$0] }
    let flow2DDirection = flow2DVector.x > 0 && flow2DVector.y > 0
        && simd_length(flow2DVector) > 1
        && flow2DSampleOffset.x > 0 && flow2DSampleOffset.y > 0
        && flow2DVisibleShift.x < -0.05
        && flow2DVisibleShift.y < -0.05
    let boundedFlow2DPixels = flow2DMatchesOracle
        && flow2DRejectsWrongOracle
        && flow2DTimeChanges
        && flow2DAlphaMoves
        && flow2DDirection

    let shimmerSpeed: Float = 0.18
    let shimmerAmount: Float = 1.51
    let shimmerDirection: Float = 0.13290171
    let shimmerGranularity: Float = 1
    let shimmerDelay: Float = 1.04
    let shimmerColor = SIMD3<Float>(repeating: 1)
    let shimmer2DWidth = 64
    let shimmer2DHeight = 64
    let shimmer2DSourcePixel = [UInt8(48), 36, 24, 160]
    let shimmer2DSourceBytes = Array(
        repeating: shimmer2DSourcePixel,
        count: shimmer2DWidth * shimmer2DHeight
    ).flatMap { $0 }
    let shimmer2DSource = texture(
        device: device,
        width: shimmer2DWidth,
        height: shimmer2DHeight,
        fill: shimmer2DSourceBytes
    )
    var shimmer2DMaskBytes: [UInt8] = []
    shimmer2DMaskBytes.reserveCapacity(shimmer2DWidth * shimmer2DHeight)
    for y in 0 ..< shimmer2DHeight {
        for x in 0 ..< shimmer2DWidth {
            let dx = (Float(x) - 31) / 25
            let dy = (Float(y) - 30) / 23
            let radial = max(0, 1 - dx * dx - dy * dy)
            let horizontalSkew = 0.88 + 0.12 * Float(x) / 63
            let cutCorner: Float = x < 25 && y < 27 ? 0.78 : 1
            shimmer2DMaskBytes.append(UInt8(
                (255 * radial * horizontalSkew * cutCorner).rounded()
            ))
        }
    }
    let shimmer2DMask = texture(
        device: device,
        format: .r8Unorm,
        width: shimmer2DWidth,
        height: shimmer2DHeight,
        fill: shimmer2DMaskBytes
    )
    let shimmer2DZeroMask = texture(
        device: device,
        format: .r8Unorm,
        width: shimmer2DWidth,
        height: shimmer2DHeight,
        fill: [UInt8](repeating: 0, count: shimmer2DWidth * shimmer2DHeight)
    )
    let shimmer2DGradientWidth = 64
    let shimmer2DGradientHeight = 8
    var shimmer2DGradientBytes: [UInt8] = []
    shimmer2DGradientBytes.reserveCapacity(
        shimmer2DGradientWidth * shimmer2DGradientHeight * 4
    )
    for y in 0 ..< shimmer2DGradientHeight {
        for x in 0 ..< shimmer2DGradientWidth {
            let u = (Float(x) + 0.5) / Float(shimmer2DGradientWidth)
            let peak: Float = 0.35
            let distance = u < peak
                ? (peak - u) / 0.055
                : (u - peak) / 0.09
            let band = max(0, 1 - distance)
            let rowScale = 0.86
                + 0.14 * Float(y) / Float(shimmer2DGradientHeight - 1)
            shimmer2DGradientBytes.append(contentsOf: [
                UInt8((255 * band * rowScale).rounded()),
                UInt8((220 * band * rowScale).rounded()),
                UInt8((180 * band * rowScale).rounded()),
                255,
            ])
        }
    }
    let shimmer2DGradient = texture(
        device: device,
        width: shimmer2DGradientWidth,
        height: shimmer2DGradientHeight,
        fill: shimmer2DGradientBytes
    )
    let shimmer2DMaskSlot = slot(
        device: device,
        index: 1,
        texture: shimmer2DMask,
        content: .data,
        purpose: .mask,
        sampling: .init(texFlags: 2),
        marker: 70
    )
    let shimmer2DZeroMaskSlot = slot(
        device: device,
        index: 1,
        texture: shimmer2DZeroMask,
        content: .data,
        purpose: .mask,
        sampling: .init(texFlags: 2),
        marker: 73
    )
    func shimmer2DProgram(
        marker: Int,
        time: Float,
        maskSlot: Program.TextureSlot
    ) -> Program? {
        program(
            device: device,
            marker: marker,
            outputSlot: 0,
            slot0Texture: shimmer2DSource,
            slot3Texture: shimmer2DGradient,
            slot3Content: .data,
            slot3Purpose: .preservedChannels,
            slot3Sampling: .init(texFlags: 2),
            fragmentSource: boundedShimmerFragment,
            additionalSlots: [maskSlot],
            uniformValues: [
                "g_Time": bytes(time),
                "g_Speed": bytes(shimmerSpeed),
                "g_Amount": bytes(shimmerAmount),
                "g_Direction": bytes(shimmerDirection),
                "g_Granularity": bytes(shimmerGranularity),
                "g_Delay": bytes(shimmerDelay),
                "g_Color": bytes(shimmerColor),
            ],
            slot0Sampling: .init(texFlags: 2)
        )
    }
    let shimmer2DFirstTime: Float = 4
    let shimmer2DSecondTime: Float = 4.4
    let shimmer2DFirst = render(
        shimmer2DProgram(
            marker: 71,
            time: shimmer2DFirstTime,
            maskSlot: shimmer2DMaskSlot
        ),
        encoder: encoder,
        queue: queue,
        target: target(
            device: device,
            width: shimmer2DWidth,
            height: shimmer2DHeight
        )
    )
    let shimmer2DSecond = render(
        shimmer2DProgram(
            marker: 72,
            time: shimmer2DSecondTime,
            maskSlot: shimmer2DMaskSlot
        ),
        encoder: encoder,
        queue: queue,
        target: target(
            device: device,
            width: shimmer2DWidth,
            height: shimmer2DHeight
        )
    )
    let shimmer2DZeroMaskOutput = render(
        shimmer2DProgram(
            marker: 73,
            time: shimmer2DFirstTime,
            maskSlot: shimmer2DZeroMaskSlot
        ),
        encoder: encoder,
        queue: queue,
        target: target(
            device: device,
            width: shimmer2DWidth,
            height: shimmer2DHeight
        )
    )
    let shimmer2DFirstCentroid = positiveDeltaCentroid(
        output: shimmer2DFirst.pixels,
        baseline: shimmer2DSourceBytes,
        width: shimmer2DWidth,
        height: shimmer2DHeight
    )
    let shimmer2DSecondCentroid = positiveDeltaCentroid(
        output: shimmer2DSecond.pixels,
        baseline: shimmer2DSourceBytes,
        width: shimmer2DWidth,
        height: shimmer2DHeight
    )
    let shimmer2DCentroidShift = if let first = shimmer2DFirstCentroid,
                                    let second = shimmer2DSecondCentroid {
        second - first
    } else {
        SIMD2<Float>(repeating: 0)
    }
    let shimmer2DAlphaPreserved = stride(
        from: 3,
        to: shimmer2DSourceBytes.count,
        by: 4
    ).allSatisfy {
        shimmer2DFirst.pixels[$0] == shimmer2DSourceBytes[$0]
            && shimmer2DSecond.pixels[$0] == shimmer2DSourceBytes[$0]
    }
    let shimmer2DMaskAsymmetric = shimmer2DMaskBytes[20 * shimmer2DWidth + 20]
        != shimmer2DMaskBytes[20 * shimmer2DWidth + 43]
    let shimmer2DGradientAsymmetric = shimmer2DGradientBytes[
        (shimmer2DGradientWidth / 3) * 4
    ] != shimmer2DGradientBytes[
        ((shimmer2DGradientHeight - 1) * shimmer2DGradientWidth
            + shimmer2DGradientWidth / 3) * 4
    ]
    // The fullscreen wrapper maps increasing texture v to increasing
    // readback rows. For the current +v convention the authored linear
    // band therefore moves mostly down and slightly left as time advances.
    let boundedShimmer2DCentroid = shimmer2DMaskAsymmetric
        && shimmer2DGradientAsymmetric
        && shimmer2DFirst.pixels != shimmer2DSourceBytes
        && shimmer2DSecond.pixels != shimmer2DSourceBytes
        && shimmer2DFirst.pixels != shimmer2DSecond.pixels
        && shimmer2DAlphaPreserved
        && shimmer2DZeroMaskOutput.pixels == shimmer2DSourceBytes
        && shimmer2DCentroidShift.x < -0.05
        && shimmer2DCentroidShift.y > 0.25
        && shimmer2DCentroidShift.y > 3 * abs(shimmer2DCentroidShift.x)

    let facts: [String: Bool] = [
        "boundedFlow2DPrepared": flow2DAtTime.prepared
            && flow2DAtOtherTime.prepared,
        "boundedFlow2DEncoded": flow2DAtTime.encoded
            && flow2DAtOtherTime.encoded,
        "boundedFlow2DGPUCompleted": flow2DAtTime.completed
            && flow2DAtOtherTime.completed,
        "boundedFlow2DMatchesLinearUnclampedOracle": flow2DMatchesOracle,
        "boundedFlow2DRejectsSaturatedAmount": flow2DRejectsWrongOracle,
        "boundedFlow2DChangesAtNonPeriodTime": flow2DTimeChanges,
        "boundedFlow2DDisplacesAlpha": flow2DAlphaMoves,
        "boundedFlow2DSamplesPlusFAndMovesVisibleMinusF": flow2DDirection,
        "boundedFlow2DPixelsMatch": boundedFlow2DPixels,
        "boundedShimmer2DPrepared": shimmer2DFirst.prepared
            && shimmer2DSecond.prepared && shimmer2DZeroMaskOutput.prepared,
        "boundedShimmer2DEncoded": shimmer2DFirst.encoded
            && shimmer2DSecond.encoded && shimmer2DZeroMaskOutput.encoded,
        "boundedShimmer2DGPUCompleted": shimmer2DFirst.completed
            && shimmer2DSecond.completed && shimmer2DZeroMaskOutput.completed,
        "boundedShimmer2DZeroMaskIdentity": shimmer2DZeroMaskOutput.pixels
            == shimmer2DSourceBytes,
        "boundedShimmer2DDownLeftCentroid": boundedShimmer2DCentroid,
    ]
    return .init(facts: facts, flow2DVector: flow2DVector,
        flow2DSampleOffset: flow2DSampleOffset,
        flow2DVisibleShift: flow2DVisibleShift,
        shimmer2DCentroidShift: shimmer2DCentroidShift)
}
