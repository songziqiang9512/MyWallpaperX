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
        checkCancellation: (() throws -> Void)? = nil,
        willReadResourceRoots: (([URL]) -> Void)? = nil
    ) rethrows -> SceneRuntimeSourceFacts {
        try checkCancellation?()
        let project = try? SceneProjectLoader().load(from: rootURL)
        try checkCancellation?()
#if DEBUG
        let resourceIndex = SceneResourceIndexBuilder().build(rootURL: rootURL)
        try checkCancellation?()
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
        // Cancellation remains outside optional-load failure handling so it
        // cannot become a missing resource or a visual compatibility fallback.
        try checkCancellation?()
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
        try checkCancellation?()
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
        try checkCancellation?()
        let assetCatalog = project.flatMap { project in
            try? SceneAssetCatalogLoader().load(
                resourceView: resourceView,
                referencedResourcePaths:
                    sceneDocument?.referencedResourcePaths ?? []
            )
        }
        try checkCancellation?()
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
        try checkCancellation?()
#else
        let resourceReferences: SceneResourceReferenceIndex? = nil
        let capabilityProfile: SceneCapabilityProfile? = nil
#endif
        let renderDescriptor: SceneRenderDescriptor?
        if let project, let sceneDocument, let assetCatalog {
            let directMaterialLinks = try directStaticModelMaterialLinks(
                document: sceneDocument,
                resourceView: resourceView,
                checkCancellation: checkCancellation
            )
            renderDescriptor = try SceneRenderDescriptorBuilder().build(
                project: project,
                sceneDocument: sceneDocument,
                assetCatalog: assetCatalog,
                resourceReferences: resourceReferences,
                capabilityProfile: capabilityProfile,
                directStaticModelMaterialLinks: directMaterialLinks,
                checkCancellation: checkCancellation
            )
        } else {
            renderDescriptor = nil
        }
        try checkCancellation?()

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
        resourceView: SceneResourceView,
        checkCancellation: (() throws -> Void)? = nil
    ) rethrows -> [SceneRenderDescriptor.ModelMaterialLink] {
        var seen: Set<String> = []
        return try document.objects.flatMap { object -> [SceneRenderDescriptor.ModelMaterialLink] in
            try checkCancellation?()
            guard let modelPath = object.staticModelPath else { return [] }
            let identity = modelPath.replacingOccurrences(of: "\\", with: "/")
                .localizedLowercase
            guard seen.insert(identity).inserted,
                  let modelURL = resourceView.resource(
                    relativePath: modelPath
                  )?.url else {
                return []
            }
            let data = try? Data(contentsOf: modelURL, options: .mappedIfSafe)
            try checkCancellation?()
            guard let data else { return [] }
            let materialPaths = try? SceneMdlStaticModelReader
                .readMaterialPathsMetadata(data: data)
            try checkCancellation?()
            guard let materialPaths else {
                return []
            }
            return materialPaths.map {
                .init(modelPath: modelPath, materialPath: $0)
            }
        }
    }
}
