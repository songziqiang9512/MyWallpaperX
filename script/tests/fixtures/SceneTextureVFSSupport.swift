import Foundation

struct SceneRenderDescriptor {
    struct Layer { let imagePath: String?
        var staticBaseTexturePath: String? = nil }
    struct ModelMaterialLink { let modelPath: String; let materialPath: String? }
    struct MaterialPassDescriptor { let materialPath: String; let texturePaths: [String] }
    let modelMaterialLinks: [ModelMaterialLink]
    let materialPasses: [MaterialPassDescriptor]
}

@main
enum Harness {
    static func main() throws {
        let package = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let loose = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
        let stock = URL(fileURLWithPath: CommandLine.arguments[3], isDirectory: true)
        let view = SceneResourceView(
            projectRootURL: loose,
            packageRootURL: package,
            stockAssetsRootURL: stock
        )
        let resolver = SceneTexturePathResolver(
            resourceView: view,
            descriptor: .init(modelMaterialLinks: [], materialPasses: [])
        )
        let output = [
            "shared": resolver.resolveTextureFile(named: "materials/shared.png")?.path ?? "",
            "bare": resolver.resolveTextureFile(named: "bare")?.path ?? "",
            "stock": resolver.resolveTextureFile(named: "assets/stock-only.png")?.path ?? "",
            "missing": resolver.resolveTextureFile(named: "missing")?.path ?? "",
        ]
        let data = try JSONSerialization.data(withJSONObject: output, options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }
}
