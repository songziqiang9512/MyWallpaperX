
@main
private enum SelfCompositeHarness {
    static func main() throws {
        setenv("MWX_SCENE_GENERIC_SHADER_ROUTE", "disable-generic", 1)
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else {
            print("{\"metalAvailable\":false}"); return
        }
        var results: [String: Bool] = [:]
        for status in [SystemProviderFixtureStatus.ready, .absent, .pending, .unavailable] {
            for (name, value) in runSelfMixedCurrentScenario(device: device, queue: queue,
                sourcePipeline: makeSourcePipeline(device), status: status) {
                results["mixed-\(status)-" + name] = value
            }
        }
        for count in 2 ... 4 {
            for variant in [SceneNamedTextureReference.Variant.primary, .secondary] {
                for usesDefault in [false, true] {
                    let label = "stage\(count)-\(variant)-default\(usesDefault)-"
                    for (name, value) in runSelfCompositeCurrentScenario(device: device, queue: queue,
                        sourcePipeline: makeSourcePipeline(device), stageCount: count,
                        variant: variant, usesDefault: usesDefault) { results[label + name] = value }
                }
            }
        }
        let data = try JSONSerialization.data(withJSONObject: ["metalAvailable": true, "results": results], options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }
}
