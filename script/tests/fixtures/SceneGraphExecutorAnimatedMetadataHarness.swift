private func checkAnimatedSamplerFailure(
    _ device: MTLDevice, _ queue: MTLCommandQueue,
    _ source: MTLTexture, _ sourcePipeline: SceneImageLayerPipeline,
    _ samplerClaim: Capabilities.ClaimedLayer?, _ samplerCapability: Capabilities.LayerCapability?, _ samplerCapabilities: Capabilities,
    _ colorClaim: Capabilities.ClaimedLayer?, _ colorCapability: Capabilities.LayerCapability?, _ colorCapabilities: Capabilities
) -> (prepared: Bool, encoded: Bool, gpuCompleted: Bool, continued: Bool, failureCode: String) {
    executeVisualFailurePassthrough(
        device: device, queue: queue, source: source, sourcePipeline: sourcePipeline,
        claim: colorClaim, capability: colorCapability, capabilities: colorCapabilities,
        generation: 8, reason: "material-variant-envelope-animated-frame-metadata"
    )
}

@main
private enum AnimatedMetadataHarness {
    static func main() throws {
        setenv("MWX_SCENE_GENERIC_SHADER_ROUTE", "disable-generic", 1)
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue() else {
            print("{\"metalAvailable\":false}")
            return
        }
        let payload = try runExecutorHarness(
            device: device, queue: queue,
            activationGraphInput: makeDefaultActivationGraph,
            activationLeaseFactory: makeDefaultActivationLeases,
            maskState: .effectLocalUnavailable(.animatedFrameMetadataInvalid),
            samplerFailureCheck: checkAnimatedSamplerFailure
        )
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        FileHandle.standardOutput.write(data)
    }
}
