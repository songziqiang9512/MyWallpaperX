@main
private enum Harness {
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
            maskState: .ready(.data),
            samplerFailureCheck: checkDefaultSamplerFailure
        )
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        FileHandle.standardOutput.write(data)
    }
}
