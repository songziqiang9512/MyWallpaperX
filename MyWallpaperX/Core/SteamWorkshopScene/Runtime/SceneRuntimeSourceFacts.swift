import Foundation

/// Immutable source facts shared by playback preparation and explicit inspection.
/// This type contains no user-facing diagnostics and does not own product output.
struct SceneRuntimeSourceFacts {
    let project: SceneProject?
    let sceneDocument: SceneDocument?
    let assetCatalog: SceneAssetCatalog?
    let resourceReferences: SceneResourceReferenceIndex?
    let resourceIndex: SceneResourceIndex
    let packageReport: ScenePkgExtractionReport?
    let resourceView: SceneResourceView
    let sceneDocumentLoadErrorDescription: String?
    let capabilityProfile: SceneCapabilityProfile
    let renderDescriptor: SceneRenderDescriptor?
}

struct SceneRuntimeSourceFactsBuilder {
    func build(
        rootURL: URL,
        propertyOverrides: [String: SceneUserPropertyValue] = [:]
    ) -> SceneRuntimeSourceFacts {
        let project = try? SceneProjectLoader().load(from: rootURL)
        let resourceIndex = SceneResourceIndexBuilder().build(rootURL: rootURL)
        let packageReport: ScenePkgExtractionReport? = {
            guard let packageURL = project?.packageURL else { return nil }
            return try? ScenePkgExtractor(toolURL: nil).extract(
                packageURL: packageURL,
                outputURL: rootURL.appendingPathComponent(
                    ".scene-extracted",
                    isDirectory: true
                )
            )
        }()
        let resourceView = SceneResourceView(
            projectRootURL: rootURL,
            packageRootURL: packageReport?.outputURL
        )
        var sceneDocumentLoadError: Error?
        let sceneDocument = project.flatMap { project -> SceneDocument? in
            do {
                return try SceneDocumentLoader().load(
                    project: project,
                    packageReport: packageReport,
                    propertyOverrides: propertyOverrides
                )
            } catch {
                sceneDocumentLoadError = error
                return nil
            }
        }
        let assetCatalog = project.flatMap { project in
            try? SceneAssetCatalogLoader().load(
                resourceView: resourceView,
                referencedResourcePaths:
                    sceneDocument?.referencedResourcePaths ?? []
            )
        }
        let resourceReferences = sceneDocument.map {
            SceneResourceReferenceIndexBuilder().build(
                document: $0,
                resourceView: resourceView
            )
        }
        let capabilityProfile = SceneCapabilityProfileBuilder().build(
            project: project,
            sceneDocument: sceneDocument,
            assetCatalog: assetCatalog,
            resourceReferences: resourceReferences,
            resourceIndex: resourceIndex
        )
        let renderDescriptor: SceneRenderDescriptor? = {
            guard let project,
                  let sceneDocument,
                  let assetCatalog,
                  let resourceReferences else {
                return nil
            }

            return SceneRenderDescriptorBuilder().build(
                project: project,
                sceneDocument: sceneDocument,
                assetCatalog: assetCatalog,
                resourceReferences: resourceReferences,
                capabilityProfile: capabilityProfile,
                directStaticModelMaterialLinks: directStaticModelMaterialLinks(
                    document: sceneDocument,
                    resourceView: resourceView
                )
            )
        }()

        return SceneRuntimeSourceFacts(
            project: project,
            sceneDocument: sceneDocument,
            assetCatalog: assetCatalog,
            resourceReferences: resourceReferences,
            resourceIndex: resourceIndex,
            packageReport: packageReport,
            resourceView: resourceView,
            sceneDocumentLoadErrorDescription:
                sceneDocumentLoadError?.localizedDescription,
            capabilityProfile: capabilityProfile,
            renderDescriptor: renderDescriptor
        )
    }

    private func directStaticModelMaterialLinks(
        document: SceneDocument,
        resourceView: SceneResourceView
    ) -> [SceneRenderDescriptor.ModelMaterialLink] {
        var seen: Set<String> = []
        return document.objects.compactMap { object in
            guard let modelPath = object.staticModelPath else { return nil }
            let identity = modelPath.replacingOccurrences(of: "\\", with: "/")
                .localizedLowercase
            guard seen.insert(identity).inserted,
                  let modelURL = resourceView.resource(
                    relativePath: modelPath
                  )?.url,
                  let data = try? Data(
                    contentsOf: modelURL,
                    options: .mappedIfSafe
                  ),
                  let materialPath = try? SceneMdlStaticModelReader
                    .readMaterialPathMetadata(data: data) else {
                return nil
            }
            return .init(
                modelPath: modelPath,
                materialPath: materialPath
            )
        }
    }
}
