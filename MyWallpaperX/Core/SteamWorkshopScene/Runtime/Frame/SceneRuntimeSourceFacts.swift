import Foundation

nonisolated extension SceneMdlStaticModel {
    /// This launch's decoded CPU input. Material discovery and GPU preparation
    /// consume the same parts; raw author bytes do not cross that handoff.
    struct PreparedSource {
        let parts: [SceneMdlStaticModel]
        let animations: Result<SceneMdlPuppetAnimationSet?, Error>?
        let attachments: Result<[SceneMdlPuppetAttachment], Error>
    }
}

/// Immutable source facts shared by playback preparation and explicit inspection.
/// Debug attaches report-only projections; Release builds only playback/property facts.
struct SceneRuntimeSourceFacts {
    let project: SceneProject?
    let sceneDocument: SceneDocument?
    let assetCatalog: SceneAssetCatalog?
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
        source: ScenePlaybackSource? = nil,
        propertyOverrides: [String: SceneUserPropertyValue] = [:],
        checkCancellation: (() throws -> Void)? = nil,
        preparedStaticModel: (String, SceneMdlStaticModel.PreparedSource) -> Void = { _, _ in },
        preparedParticleDefinition: (String, SceneParticleAssetGraphLoader.PreparedDefinition) -> Void = { _, _ in },
        willReadResourceRoots: (([URL]) -> Void)? = nil
    ) throws -> SceneRuntimeSourceFacts {
        try checkCancellation?()
        let selected = source ?? ScenePlaybackSource(rootURL: rootURL)
        guard selected.rootURL.resolvingSymlinksInPath().standardizedFileURL.path
                == rootURL.resolvingSymlinksInPath().standardizedFileURL.path else {
            throw SceneResourceView.ReadError.invalidHandle
        }
        // Library bookkeeping and old import digests do not authorize playback.
        // Build the current lookup namespace; actual reads own their FD checks.
        let looseRoot = SceneResourceView.Root(source: .loose, url: selected.rootURL.standardizedFileURL)
        let projectData: Data?
        do {
            projectData = try looseRoot.existingLiteralHandle(relativePath: "project.json")?
                .readBytes(checkCancellation: checkCancellation)
        } catch let error as SceneResourceView.ReadError {
            switch error {
            case .sourceChanged, .invalidHandle: throw error
            case .missing, .invalidPath, .symlinkEscape, .unreadable, .fileTooLarge: projectData = nil
            }
        }
        let project: SceneProject?
        do {
            project = try projectData.map {
                try SceneProjectLoader().load(data: $0, from: rootURL, packageExists: { name in
                    try looseRoot.existingLiteralHandle(relativePath: name) != nil
                })
            }
        } catch let error as SceneResourceView.ReadError {
            switch error {
            case .sourceChanged, .invalidHandle: throw error
            case .missing, .invalidPath, .symlinkEscape, .unreadable, .fileTooLarge: project = nil
            }
        } catch { project = nil }
        try checkCancellation?()
#if DEBUG
        let resourceIndex = looseRoot.index
        try checkCancellation?()
#endif
        let packageRoot: SceneResourceView.Root?
        if let packageURL = project?.packageURL {
            do {
                guard let handle = try looseRoot.existingLiteralHandle(relativePath: packageURL.lastPathComponent) else {
                    throw SceneResourceView.ReadError.missing
                }
                // Parse once, retaining the format's existing structural limits.
                // Logical names and actual reads stay with this opened package.
                let package = try looseRoot.openPackage(handle, limits: .compatibility,
                    checkCancellation: checkCancellation)
                packageRoot = try .package(openedPackage: package, checkCancellation: checkCancellation)
            } catch let error as ScenePkgReader.ReadError {
                switch error {
                case .sourceChanged:
                    throw error
                case .fileTooSmall, .invalidMagic, .truncatedTable, .invalidPathData,
                     .limitExceeded, .invalidSource:
                    // The malformed package is unusable. A complete loose scene
                    // can still play; never mount a stale extraction directory.
                    packageRoot = nil
                }
            } catch let error as SceneResourceView.ReadError {
                switch error {
                case .sourceChanged, .invalidHandle:
                    throw error
                case .missing, .invalidPath, .symlinkEscape, .unreadable, .fileTooLarge:
                    packageRoot = nil
                }
            }
        } else {
            packageRoot = nil
        }
        // Cancellation remains outside optional-load failure handling so it
        // cannot become a missing resource or a visual compatibility fallback.
        try checkCancellation?()
        // Inspect the selected resource roots before consumers read them. Callers
        // separately cover the preceding project/index/package reads.
        willReadResourceRoots?(
            [packageRoot?.directoryURL, rootURL, SceneResourceView.defaultStockAssetsRootURL()]
                .compactMap { $0 }
        )
        let resourceView = SceneResourceView(
            projectRoot: looseRoot,
            packageRoot: packageRoot
        )
        try checkCancellation?()
        var sceneDocumentLoadError: Error?
        let documentInput: (data: Data, path: String)?
        do {
            documentInput = try project.flatMap { project in
                guard let entry = try resourceView.literalEntry(relativePath: project.entryPath) else { return nil }
                return (try entry.readBytes(checkCancellation: checkCancellation), entry.diagnosticPath)
            }
        } catch let error as SceneResourceView.ReadError {
            switch error {
            case .sourceChanged, .invalidHandle: throw error
            case .missing, .invalidPath, .symlinkEscape, .unreadable, .fileTooLarge:
                sceneDocumentLoadError = error
                documentInput = nil
            }
        }
        let sceneDocument = project.flatMap { project -> SceneDocument? in
            guard let input = documentInput else {
                if sceneDocumentLoadError == nil {
                    sceneDocumentLoadError = SceneDocumentLoader.LoadError.missingSceneJSON
                }
                return nil
            }
            do {
                return try SceneDocumentLoader().load(
                    data: input.data,
                    sourcePath: input.path,
                    propertyCatalog: project.userProperties,
                    propertyOverrides: propertyOverrides
                )
            } catch {
                sceneDocumentLoadError = error
                return nil
            }
        }
        try checkCancellation?()
        let directMaterialLinks = try sceneDocument.map {
            try directStaticModelMaterialLinks(document: $0, resourceView: resourceView,
                checkCancellation: checkCancellation, preparedStaticModel: preparedStaticModel)
        } ?? []
        let assetCatalog = try project.map { project in
            try SceneAssetCatalogLoader().load(
                resourceView: resourceView,
                referencedResourcePaths: sceneDocument?.referencedResourcePaths ?? [],
                propertyCatalog: project.userProperties,
                scriptSources: sceneDocument?.scriptBindings.map(\.source) ?? [],
                additionalModelPaths: directMaterialLinks.map(\.modelPath),
                additionalMaterialPaths: directMaterialLinks.compactMap(\.materialPath),
                particlePaths: sceneDocument?.objects.compactMap(\.particlePath) ?? [],
                preparedParticleDefinition: preparedParticleDefinition,
                checkCancellation: checkCancellation
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
        checkCancellation: (() throws -> Void)? = nil,
        preparedStaticModel: (String, SceneMdlStaticModel.PreparedSource) -> Void
    ) throws -> [SceneRenderDescriptor.ModelMaterialLink] {
        var seen: Set<String> = []
        func identity(_ path: String) -> String {
            path.replacingOccurrences(of: "\\", with: "/").localizedLowercase
        }
        let animationDemands = Set(document.objects.compactMap { object in
            object.puppetAnimationLayers.isEmpty ? nil : object.staticModelPath.map(identity)
        })
        return try document.objects.flatMap { object -> [SceneRenderDescriptor.ModelMaterialLink] in
            try checkCancellation?()
            guard let modelPath = object.staticModelPath else { return [] }
            let modelIdentity = identity(modelPath)
            guard seen.insert(modelIdentity).inserted,
                  let model = resourceView.resolvedResource(
                    relativePath: modelPath
                  ) else {
                return []
            }
            let data: Data
            do {
                data = try model.readSnapshot(checkCancellation: checkCancellation).data
            } catch let error as SceneResourceView.ReadError {
                switch error {
                case .sourceChanged, .invalidHandle: throw error
                case .missing, .invalidPath, .symlinkEscape, .unreadable, .fileTooLarge:
                    return []
                }
            }
            try checkCancellation?()
            let parts = try? SceneMdlStaticModelReader.readParts(data: data)
            try checkCancellation?()
            guard let parts else {
                return []
            }
            let animations: Result<SceneMdlPuppetAnimationSet?, Error>? =
                animationDemands.contains(modelIdentity) && parts.contains(where: { $0.rig != nil })
                ? Result { try SceneMdlPuppetAnimationReader.read(data: data) } : nil
            let attachments: Result<[SceneMdlPuppetAttachment], Error> = animations != nil
                ? Result { try SceneMdlPuppetAttachmentReader.read(data: data) } : .success([])
            try checkCancellation?()
            preparedStaticModel(modelIdentity, .init(parts: parts, animations: animations,
                attachments: attachments))
            return parts.map {
                .init(modelPath: modelPath, materialPath: $0.materialPath)
            }
        }
    }
}
