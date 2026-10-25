import AppKit

extension OnlineLibraryService {
    /// Pixabay documents this stable source-page form; media URLs still come
    /// exclusively from its API item and the original download owner.
    /// https://pixabay.com/api/docs/#api_search_videos
    static func videoSourcePageURL(id: Int) -> URL? {
        guard id > 0 else { return nil }
        return URL(string: "https://pixabay.com/videos/id-\(id)/")
    }

    func openVideoSourcePage(id: Int) {
        guard let url = Self.videoSourcePageURL(id: id) else { return }
        NSWorkspace.shared.open(url)
    }
}
