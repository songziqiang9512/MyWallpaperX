import AppKit

/// First-item background consumer; PreviewState remains the static preview owner.
@MainActor enum SteamWorkshopListThumbnailTint {
    /// A separate consumer of the same static preview pipeline; no animation/playback.
    static func publish(to source: ListThumbnailTintSource, item: SteamWorkshopBrowserItem?,
                                         record: SteamWorkshopDownloadRecord?, refreshToken: Int) {
        let urls = item.map { steamWorkshopPreviewSources(item: $0, record: record) }
        // Progress timestamps are not image revisions. Ready records carry the
        // installed file's version; queued/downloading progress must not recolor.
        let fileRevision = record.flatMap { $0.status == .ready ? String($0.updatedAt.timeIntervalSince1970) : nil } ?? ""
        let assets = [urls?.primary?.absoluteString ?? "", urls?.fallback?.absoluteString ?? "",
                      record?.exportedVideoURL?.absoluteString ?? "", record?.sourceVideoURL?.absoluteString ?? "", fileRevision, String(refreshToken)]
        source.update(id: item?.id, assets: assets) { completion in
            let state = SteamWorkshopPreviewState(loaders: .live(priority: .prefetch))
            state.onChange = { [weak state] in
                if let image = state?.image { completion(image) }
            }
            state.configure(previewURL: urls?.primary, fallbackImageURL: urls?.fallback,
                            fallbackVideoURL: record?.videoURL, maxPixelSize: 256)
            return { state.onChange = nil; state.reset() }
        }
    }

}
