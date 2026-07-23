import Foundation

// Resolves an image layer's primary texture file URL by walking the render descriptor:
//   layer.imagePath (e.g. "models/foo.json")
//     -> modelMaterialLinks: model -> material
//     -> materialPasses: material -> first texture name (no extension/path prefix)
//     -> probes common Wallpaper Engine path/extension patterns
struct SceneTexturePathResolver {
    let cacheDirectory: URL
    let descriptor: SceneRenderDescriptor

    private static let candidatePathTemplates: [String] = [
        "materials/%@.tex",
        "materials/%@.png",
        "materials/%@.jpg",
        "materials/%@.jpeg",
        "%@.tex",
        "%@.png",
        "%@.jpg",
        "%@.jpeg"
    ]

    func resolvePrimaryTexture(for layer: SceneRenderDescriptor.Layer) -> URL? {
        guard let modelPath = layer.imagePath else { return nil }
        guard let materialPath = descriptor.modelMaterialLinks
            .first(where: { $0.modelPath == modelPath })?
            .materialPath else { return nil }
        guard let textureName = descriptor.materialPasses
            .first(where: { $0.materialPath == materialPath })?
            .texturePaths.first else { return nil }
        return resolveTextureFile(named: textureName)
    }

    func resolveTextureFile(named textureName: String) -> URL? {
        let fileManager = FileManager.default
        for template in Self.candidatePathTemplates {
            let relative = String(format: template, textureName)
            let url = cacheDirectory.appendingPathComponent(relative)
            if fileManager.fileExists(atPath: url.path) {
                return url
            }
        }
        return nil
    }
}
