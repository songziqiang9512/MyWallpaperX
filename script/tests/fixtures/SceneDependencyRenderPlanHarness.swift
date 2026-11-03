@main
enum Harness {
    static func main() throws {
        var result = namedUtilityResults()
        result.merge(programProviderResults()) { _, value in value }
        result.merge(multiProviderResults()) { _, value in value }
        result.merge(xRayResults()) { _, value in value }
        result.merge(imageBlendResults()) { _, value in value }
        let data = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }
}
