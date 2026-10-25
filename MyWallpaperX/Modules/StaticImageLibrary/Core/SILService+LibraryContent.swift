import Foundation

extension SILService {
    func libraryContentItems(from values: [SILWallpaper], reusing previous: [WallpaperContentItem],
                             refreshAvailability: Bool = false) async -> [WallpaperContentItem] {
        let old = Dictionary(previous.map { ($0.providerReference, $0) }, uniquingKeysWith: { first, _ in first })
        // SILWallpaper remains the source model on its current actor. Only
        // immutable references, paths and the prior result cross to the worker.
        let inputs = values.map { value in
            let reference = WallpaperReference(provider: .staticImageLibrary, sourceID: value.id)
            let reuse = old[reference].flatMap { item -> Bool? in
                guard !refreshAvailability,
                      item.locator.path?.utf8.elementsEqual(value.path.utf8) == true else { return nil }
                return item.publishedAvailability.isAvailable
            }
            return (reference, value.path, reuse)
        }
        let worker = Task.detached(priority: .utility) {
            var facts: [WallpaperReference: WallpaperContentLocalFacts] = [:]
            for (reference, path, reuse) in inputs {
                guard !Task.isCancelled else { return facts }
                let available: Bool
                if let reuse { available = reuse }
                else {
                    var directory: ObjCBool = false
                    available = FileManager.default.fileExists(atPath: path, isDirectory: &directory)
                        && !directory.boolValue && FileManager.default.isReadableFile(atPath: path)
                }
                facts[reference] = WallpaperContentLocalFacts(isPublishedLocally: true,
                    isAvailable: available, canPlay: available, canDelete: true,
                    canQuickLook: true, localURL: URL(fileURLWithPath: path))
            }
            return facts
        }
        let facts = await withTaskCancellationHandler { await worker.value } onCancel: { worker.cancel() }
        guard !Task.isCancelled else { return [] }
        return values.compactMap { value in
            let reference = WallpaperReference(provider: .staticImageLibrary, sourceID: value.id)
            return facts[reference].map { StaticImageLibraryContentProjection.project(value, facts: $0) }
        }
    }
}
