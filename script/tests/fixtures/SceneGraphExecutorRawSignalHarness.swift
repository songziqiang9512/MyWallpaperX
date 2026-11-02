
@main private enum RawSignalPassthroughHarness {
    static func main() throws {
        setenv("MWX_SCENE_GENERIC_SHADER_ROUTE", "disable-generic", 1)
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else {
            print("{\"metalAvailable\":false}"); return
        }
        let report = runRawSignalPassthroughGraphScenario(device: device, queue: queue)
        print(String(decoding: try JSONSerialization.data(withJSONObject:
            ["metalAvailable": true, "rawSignal": report], options: [.sortedKeys]), as: UTF8.self))
    }
}
