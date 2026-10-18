import Foundation

/// Immutable source facts shared by playback preparation and explicit inspection.
/// Debug attaches report-only projections; Release builds only playback/property facts.
struct SceneRuntimeSourceFacts {
    let project: SceneProject?
    let sceneDocument: SceneDocument?
    let assetCatalog: SceneAssetCatalog?
    let packageReport: ScenePkgExtractionReport?
    let resourceView: SceneResourceView
    let sceneDocumentLoadErrorDescription: String?
    let renderDescriptor: SceneRenderDescriptor?
#if DEBUG
    var resourceReferences: SceneResourceReferenceIndex? = nil
    var resourceIndex: SceneResourceIndex? = nil
    var capabilityProfile: SceneCapabilityProfile? = nil
#endif
}

struct SceneRuntimeSourceFactsBuilder {
    func build(
        rootURL: URL,
        propertyOverrides: [String: SceneUserPropertyValue] = [:],
        willReadResourceRoots: (([URL]) -> Void)? = nil
    ) -> SceneRuntimeSourceFacts {
        let project = try? SceneProjectLoader().load(from: rootURL)
#if DEBUG
        let resourceIndex = SceneResourceIndexBuilder().build(rootURL: rootURL)
#endif
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
        // Extraction has validated the package; inspect its resulting namespace
        // before ResourceView builds indexes or other consumers read it. Callers
        // separately cover the preceding project/index/package reads.
        willReadResourceRoots?(
            [packageReport?.outputURL, rootURL, SceneResourceView.defaultStockAssetsRootURL()]
                .compactMap { $0 }
        )
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
#if DEBUG
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
#else
        let resourceReferences: SceneResourceReferenceIndex? = nil
        let capabilityProfile: SceneCapabilityProfile? = nil
#endif
        let renderDescriptor: SceneRenderDescriptor? = {
            guard let project,
                  let sceneDocument,
                  let assetCatalog else {
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

        var facts = SceneRuntimeSourceFacts(
            project: project,
            sceneDocument: sceneDocument,
            assetCatalog: assetCatalog,
            packageReport: packageReport,
            resourceView: resourceView,
            sceneDocumentLoadErrorDescription:
                sceneDocumentLoadError?.localizedDescription,
            renderDescriptor: renderDescriptor
        )
#if DEBUG
        facts.resourceReferences = resourceReferences
        facts.resourceIndex = resourceIndex
        facts.capabilityProfile = capabilityProfile
#endif
        return facts
    }

    private func directStaticModelMaterialLinks(
        document: SceneDocument,
        resourceView: SceneResourceView
    ) -> [SceneRenderDescriptor.ModelMaterialLink] {
        var seen: Set<String> = []
        return document.objects.flatMap { object -> [SceneRenderDescriptor.ModelMaterialLink] in
            guard let modelPath = object.staticModelPath else { return [] }
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
                  let materialPaths = try? SceneMdlStaticModelReader
                    .readMaterialPathsMetadata(data: data) else {
                return []
            }
            return materialPaths.map {
                .init(modelPath: modelPath, materialPath: $0)
            }
        }
    }
}
