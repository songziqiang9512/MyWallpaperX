import CoreGraphics
import Foundation
import Metal
import simd

// Explicit scalar-red carriers, channel consumers and attachment storage.
func runSceneResolvedMaterialPassScalarCases(
    device: MTLDevice,
    queue: MTLCommandQueue,
    encoder: SceneResolvedMaterialPassEncoder,
    authoredTexture: MTLTexture,
    baseline: Program,
    rgbaTarget: MTLTexture
) -> [String: Bool] {
    let r8Target = target(device: device, format: .r8Unorm)
    let formatRejected = encoder.prepare(
        program: baseline,
        target: r8Target
    ) == nil
    let scalarProducer = program(
        device: device,
        marker: 73,
        outputSlot: 0,
        slot0Texture: authoredTexture,
        fragmentSource: """
        varying vec2 v_TexCoord;
        uniform sampler2D g_Texture0;
        uniform float g_Gain;
        void main() {
            float signal = texSample2D(g_Texture0, v_TexCoord).r
                * g_Gain * 2.0;
            gl_FragColor = vec4(signal, signal * 0.5, 0.0, 0.0);
        }
        """,
        outputStorage: .scalarRedUnorm
    )!
    let explicitScalarPreparation = encoder.prepareResult(
        program: scalarProducer,
        target: r8Target,
        attachmentStorage: .scalarRedUnorm
    )
    var scalarProducerEncoded = false
    var scalarProducerCompleted = false
    var scalarProducerRedStorage = false
    if case let .success(prepared) = explicitScalarPreparation,
       let command = queue.makeCommandBuffer() {
        scalarProducerEncoded = encoder.encode(prepared, commandBuffer: command)
        command.commit()
        command.waitUntilCompleted()
        scalarProducerCompleted = command.status == .completed
            && command.error == nil
        scalarProducerRedStorage = channelPixels(r8Target, as: UInt8.self)
            == [255, 0, 0, 255]
    }
    let scalarConsumerFragment = """
    varying vec2 v_TexCoord;
    uniform sampler2D g_Texture0;
    void main() {
        float scalar = texSample2D(g_Texture0, v_TexCoord).r;
        gl_FragColor = vec4(scalar, scalar, scalar, 1.0);
    }
    """
    let scalarConsumer = program(
        device: device,
        marker: 74,
        outputSlot: 0,
        slot0Texture: r8Target,
        slot0Content: .scalarRedUnorm,
        slot0Purpose: .preservedChannels,
        fragmentSource: scalarConsumerFragment
    )
    let scalarOutput = target(device: device)
    let scalarRoundTrip = render(
        scalarConsumer,
        encoder: encoder,
        queue: queue,
        target: scalarOutput
    )
    let scalarRoundTripExpected: [UInt8] = [
        255, 255, 255, 255,
        0, 0, 0, 255,
        0, 0, 0, 255,
        255, 255, 255, 255,
    ]
    let scalarDirectWholeConsumerRejectedByColorContract = program(
        device: device, marker: 75, outputSlot: 0,
        slot0Texture: r8Target, slot0Content: .scalarRedUnorm,
        slot0Purpose: .preservedChannels,
        fragmentSource: """
        varying vec2 v_TexCoord;
        uniform sampler2D g_Texture0;
        void main() {
            gl_FragColor = texSample2D(g_Texture0, v_TexCoord);
        }
        """
    ) == nil
    let scalarAliasConsumerAcceptedUpstream = program(
        device: device, marker: 76, outputSlot: 0,
        slot0Texture: r8Target, slot0Content: .scalarRedUnorm,
        slot0Purpose: .preservedChannels,
        fragmentSource: """
        varying vec2 v_TexCoord;
        uniform sampler2D g_Texture0;
        void main() {
            vec4 sampleValue = texSample2D(g_Texture0, v_TexCoord);
            float scalar = sampleValue.r;
            gl_FragColor = vec4(scalar, scalar, scalar, 1.0);
        }
        """
    ) != nil
    let scalarGreenConsumerRejectedUpstream = program(
        device: device, marker: 77, outputSlot: 0,
        slot0Texture: r8Target, slot0Content: .scalarRedUnorm,
        slot0Purpose: .preservedChannels,
        fragmentSource: """
        varying vec2 v_TexCoord;
        uniform sampler2D g_Texture0;
        void main() {
            float scalar = texSample2D(g_Texture0, v_TexCoord).g;
            gl_FragColor = vec4(scalar, scalar, scalar, 1.0);
        }
        """
    ) == nil
    let r16Target = target(device: device, format: .r16Float)
    let scalarFloatProducer = program(
        device: device, marker: 78, outputSlot: 0,
        slot0Texture: authoredTexture,
        fragmentSource: scalarProducer.preparedShader.fragment.source,
        gain: 1, outputStorage: .scalarRedFloat16
    )!
    var scalarFloatCarrier = false
    if case let .success(prepared) = encoder.prepareResult(
        program: scalarFloatProducer, target: r16Target,
        attachmentStorage: .scalarRedFloat16
    ),
       let command = queue.makeCommandBuffer() {
        let encoded = encoder.encode(prepared, commandBuffer: command)
        command.commit()
        command.waitUntilCompleted()
        scalarFloatCarrier = prepared.storedContent == .scalarRedFloat16
            && encoded && command.status == .completed && command.error == nil
            && channelPixels(r16Target, as: UInt16.self)
                == [0x4000, 0, 0, 0x4000]
    }
    let scalarIntoColorTargetRejected = {
        if case .failure(.targetRejected) = encoder.prepareResult(
            program: scalarProducer, target: rgbaTarget,
            attachmentStorage: .scalarRedUnorm
        ) { return true }
        return false
    }()
    let facts: [String: Bool] = [
        "targetFormatRejected": formatRejected,
        "scalarProducerPreparedExplicitly": {
            if case let .success(prepared) = explicitScalarPreparation {
                return prepared.storedContent == .scalarRedUnorm
            }
            return false
        }(),
        "scalarProducerEncoded": scalarProducerEncoded,
        "scalarProducerGPUCompleted": scalarProducerCompleted,
        "scalarProducerStoresOnlyRed": scalarProducerRedStorage,
        "scalarRedConsumerPrepared": scalarRoundTrip.prepared,
        "scalarRedConsumerEncoded": scalarRoundTrip.encoded,
        "scalarRedConsumerGPUCompleted": scalarRoundTrip.completed,
        "scalarRedRoundTripMatches": scalarRoundTrip.pixels
            == scalarRoundTripExpected,
        "scalarDirectWholeConsumerRejectedByColorContract":
            scalarDirectWholeConsumerRejectedByColorContract,
        "scalarAliasConsumerAcceptedUpstream":
            scalarAliasConsumerAcceptedUpstream,
        "scalarGreenConsumerRejectedUpstream":
            scalarGreenConsumerRejectedUpstream,
        "scalarFloat16CarrierGPUCompleted": scalarFloatCarrier,
        "scalarIntoColorTargetRejected": scalarIntoColorTargetRejected,
    ]
    return facts
}
