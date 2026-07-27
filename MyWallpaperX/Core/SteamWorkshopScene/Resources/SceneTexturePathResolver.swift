import Foundation

// Resolves an image layer's primary texture file URL by walking the render descriptor:
//   layer.imagePath (e.g. "models/foo.json")
//     -> modelMaterialLinks: model -> material
//     -> materialPasses: material -> first texture name (no extension/path prefix)
//     -> probes common Wallpaper Engine path/extension patterns
struct SceneTexturePathResolver {
    let resourceView: SceneResourceView
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

    init(resourceView: SceneResourceView, descriptor: SceneRenderDescriptor) {
        self.resourceView = resourceView
        self.descriptor = descriptor
    }

    init(cacheDirectory: URL, descriptor: SceneRenderDescriptor) {
        self.init(
            resourceView: SceneResourceView(
                projectRootURL: cacheDirectory,
                packageRootURL: nil
            ),
            descriptor: descriptor
        )
    }

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
        for template in Self.candidatePathTemplates {
            let relative = String(format: template, textureName)
            if let resource = resourceView.resource(relativePath: relative) {
                return resource.url
            }
        }
        return nil
    }
}
