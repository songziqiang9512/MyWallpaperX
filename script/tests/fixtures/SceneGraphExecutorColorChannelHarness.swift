
@main private enum ColorChannelHarness {
    static func main() throws {
        setenv("MWX_SCENE_GENERIC_SHADER_ROUTE", "disable-generic", 1)
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else {
            print("{\"metalAvailable\":false}"); return
        }
        var reports: [String: Any] = [:]
        for probe in ["r", "g", "rg"] {
            reports[probe] = runStraightColorContinuityScenario(device: device, queue: queue, colorProbe: probe)
        }
        print(String(decoding: try JSONSerialization.data(withJSONObject:
            ["metalAvailable": true, "channels": reports], options: [.sortedKeys]), as: UTF8.self))
    }
}
