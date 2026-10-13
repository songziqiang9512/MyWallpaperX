import Foundation
import Metal

@main
enum Harness {
    static func main() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            print("{\"metalAvailable\":false}")
            return
        }
        let fixture = SceneResolvedMaterialFinalizerFixture(device: device)
        let result = try fixture.run()
        let data = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
        withExtendedLifetime(fixture) {
            FileHandle.standardOutput.write(data)
        }
    }
}
