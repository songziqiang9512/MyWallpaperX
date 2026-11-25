import Darwin
import Foundation

extension WallpaperManager {
    /// Resolve only changed local resources off the main actor. Existing catalog
    /// values are the previous projection, not another persistent file index.
    func libraryContentItems(from values: [VideoWallpaper], reusing previous: [WallpaperContentItem],
                             refreshAvailability: Bool = false) async -> [WallpaperContentItem] {
        let old = Dictionary(previous.map { ($0.providerReference, $0) }, uniquingKeysWith: { first, _ in first })
        let inputs = values.map { value in
            let reference = WallpaperReference(provider: .videoLibrary, sourceID: value.id)
            let reuse = old[reference].flatMap { item -> (available: Bool, revision: String?)? in
                guard !refreshAvailability,
                      item.locator.path?.utf8.elementsEqual(value.path.utf8) == true else { return nil }
                return (item.publishedAvailability.isAvailable, item.metadata.resourceRevision)
            }
            return (reference, value.path, reuse)
        }
        let worker = Task.detached(priority: .utility) {
            var facts: [WallpaperReference: WallpaperContentLocalFacts] = [:]
            for (reference, path, reuse) in inputs {
                guard !Task.isCancelled else { return facts }
                let available: Bool
                let revision: String?
                if let reuse {
                    (available, revision) = reuse
                } else {
                    var file = stat()
                    available = stat(path, &file) == 0 && file.st_mode & S_IFMT != S_IFDIR
                        && FileManager.default.isReadableFile(atPath: path)
                    revision = available
                        ? "\(file.st_dev):\(file.st_ino):\(file.st_size):\(file.st_mtimespec.tv_sec):\(file.st_mtimespec.tv_nsec)"
                        : nil
                }
                facts[reference] = WallpaperContentLocalFacts(isPublishedLocally: true,
                    isAvailable: available, canPlay: available, canDelete: true, canQuickLook: true,
                    localURL: URL(fileURLWithPath: path), resourceRevision: revision)
            }
            return facts
        }
        let facts = await withTaskCancellationHandler { await worker.value } onCancel: { worker.cancel() }
        guard !Task.isCancelled else { return [] }
        return values.compactMap { value in
            let reference = WallpaperReference(provider: .videoLibrary, sourceID: value.id)
            return facts[reference].map { VideoLibraryContentProjection.project(value, facts: $0) }
        }
    }
}
