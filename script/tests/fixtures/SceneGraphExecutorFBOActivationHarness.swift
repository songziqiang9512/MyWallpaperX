private func makeFBOActivationGraph() -> Graph {
    graph(
        targets: [rawTarget(first)],
        nodes: [
            material(0, ordinal: 0, target: first, read: input),
            material(1, ordinal: 1, target: output, read: first),
        ]
    )
}

private func makeFBOActivationLeases(
    _ graph: Graph, _ capability: Capabilities.LayerCapability,
    _ device: MTLDevice, _ generation: UInt64
) -> [SceneGraphRenderTargetLease]? {
    [makeLease(requirePlan(graph), device: device, generation: generation)]
}

@main
private enum FBOActivationHarness {
    static func main() throws {
        setenv("MWX_SCENE_GENERIC_SHADER_ROUTE", "disable-generic", 1)
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue() else {
            print("{\"metalAvailable\":false}")
            return
        }
        let payload = try runExecutorHarness(
            device: device, queue: queue,
            activationGraphInput: makeFBOActivationGraph,
            activationLeaseFactory: makeFBOActivationLeases,
            maskState: .ready(.data),
            samplerFailureCheck: checkDefaultSamplerFailure
        )
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        FileHandle.standardOutput.write(data)
    }
}
