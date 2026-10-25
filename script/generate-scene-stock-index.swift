import Foundation

/// Build-only adapter. The resource index owns visibility, encoding and limits.
@main
struct GenerateSceneStockIndex {
    enum UsageError: LocalizedError {
        case arguments
        var errorDescription: String? {
            "Expected <destination assets directory> <output manifest file>."
        }
    }

    static func main() throws {
        guard CommandLine.arguments.count == 3 else { throw UsageError.arguments }
        let assets = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let output = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: false)
        let data = try SceneResourceIndexBuilder().bundledManifestData(rootURL: assets)
        try data.write(to: output, options: .atomic)
        print("Scene stock index: \(data.count) bytes")
    }
}
