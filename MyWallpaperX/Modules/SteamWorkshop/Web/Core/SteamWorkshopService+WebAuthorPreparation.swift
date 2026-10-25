import Foundation

extension SteamWorkshopService {
    struct WebAuthorPreparationAdmission {
        let inputs: WebRuntimeCacheManifestInputs
        let lifetime: PlaybackResourceLifetime?
    }

    func admitWebAuthorPreparation(for record: SteamWorkshopDownloadRecord) -> WebAuthorPreparationAdmission? {
        guard !Task.isCancelled, record.contentType == .web else { return nil }
        let source = webPropertyDefinitionSource(for: record)
        let ids = [record.id, source?.id, record.dependencyItemID].compactMap { $0 }
        guard ids.allSatisfy({ !removingDownloadIDs.contains($0) }) else { return nil }
        let inputs = webRuntimeCacheManifestInputs(for: record, source: source)
        guard inputs.authorSourceAvailable else { return nil }
        // Each consumed tree is protected once. Entry/project paths inside these
        // roots do not need to reopen and decode the same version marker again.
        let roots = Set([inputs.ownFolderURL, source?.folderURL, inputs.rootURL].compactMap { $0 })
        let distinctTrees = roots.filter { candidate in
            !roots.contains { other in other != candidate && candidate.path.hasPrefix(other.path + "/") }
        }
        do {
            let lifetime = try libraryVersionLifetime(recordID: record.id, consumedRoots: Array(distinctTrees))
            return WebAuthorPreparationAdmission(inputs: inputs, lifetime: lifetime)
        } catch { return nil }
    }

    private func webAuthorPreparationIsCurrent(_ inputs: WebRuntimeCacheManifestInputs) -> Bool {
        !Task.isCancelled && !removingDownloadIDs.contains(inputs.recordID)
            && !removingDownloadIDs.contains(inputs.propertySource?.id ?? inputs.recordID)
            && !removingDownloadIDs.contains(inputs.dependencyItemID ?? inputs.recordID)
            && inputs.authorLanguageKeys == WorkshopPropertyDisplayResolver.languageVersion
            && inputs.language == Self.resolvedWebWallpaperLanguage()
    }

    func resolvedWebAuthorProduct(for record: SteamWorkshopDownloadRecord,
        admission: WebAuthorPreparationAdmission) async -> WebProjectDescriptorParseProduct? {
        let inputs = admission.inputs
        let memo = webProjectDescriptorCache[record.id]
        let publication = SteamWorkshopWebRuntimeCachePublication.shared.begin(key: inputs.analysisFileURL.path)
        let work = Task.detached(priority: .userInitiated) { [weak self] () -> CachedWebProjectDescriptor? in
            guard let self, !Task.isCancelled else { return nil }
            if let memo, memo.matches(inputs) { return memo }
            if let cached = Self.loadCachedAnalysisDescriptor(inputs: inputs) { return cached }
            let reader = WebAuthorFileReader()
            guard let captured = self.captureWebAuthorInput(record: record, source: inputs.propertySource,
                    inputs: inputs, reader: reader),
                  let product = self.parseWebProjectDescriptorCore(record: record, captured: captured),
                  !Task.isCancelled else { return nil }
            let author = reader.cachedProduct(product, inputs: inputs)
            Self.saveWebAnalysisCache(author, inputs: inputs, publication: publication)
            return author
        }
        // Even cancellation waits for the actual reader to finish before the
        // caller's single version lifetime can be released.
        let author = await withTaskCancellationHandler { await work.value } onCancel: { work.cancel() }
        guard let author, webAuthorPreparationIsCurrent(inputs) else { return nil }
        if author.isReusable, SteamWorkshopWebRuntimeCachePublication.shared.isCurrent(publication) {
            webProjectDescriptorCache[record.id] = author
        }
        return author.product
    }
}
