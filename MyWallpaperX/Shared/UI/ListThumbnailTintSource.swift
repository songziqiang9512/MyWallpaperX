import AppKit
import CoreImage.CIFilterBuiltins

/// A grid publishes its final first item, independently of visible cells or selection.
@MainActor protocol ListThumbnailTintProviding: AnyObject {
    var listThumbnailTintSource: ListThumbnailTintSource { get }
}

@MainActor final class ListThumbnailTintSource {
    typealias Cancellation = () -> Void
    typealias Loader = (@escaping (NSImage?) -> Void) -> Cancellation
    struct Identity: Equatable {
        let itemID: String
        let assets: [String]
    }
    struct Request {
        let identity: Identity
        let revision: UUID
        let load: Loader
    }

    private(set) var request: Request?
    private var observers: [UUID: () -> Void] = [:]
    private var stopForwarding: Cancellation?

    isolated deinit { stopForwarding?() }

    func update(id: String?, assets: [String] = [], load: Loader? = nil) {
        let identity = id.map { Identity(itemID: $0, assets: assets) }
        guard identity != request?.identity else { return }
        setRequest(identity.flatMap { identity in
            load.map { Request(identity: identity, revision: UUID(), load: $0) }
        })
    }

    func invalidate() {
        guard let request else { return }
        setRequest(Request(identity: request.identity, revision: UUID(), load: request.load))
    }

    /// Browser wrappers forward only their mounted grid, and clear login/error states.
    func forward(from source: ListThumbnailTintSource?) {
        stopForwarding?()
        stopForwarding = nil
        if let source {
            stopForwarding = source.observe { [weak self, weak source] in
                self?.setRequest(source?.request)
            }
        }
        setRequest(source?.request)
    }

    func observe(_ change: @escaping () -> Void) -> Cancellation {
        let id = UUID()
        observers[id] = change
        return { [weak self] in self?.observers.removeValue(forKey: id) }
    }

    private func setRequest(_ next: Request?) {
        guard request?.revision != next?.revision else { return }
        request = next
        // Observers may detach or replace a source while handling this event.
        for change in Array(observers.values) { change() }
    }

    static func mounted(in view: NSView) -> ListThumbnailTintSource? {
        if let provider = view as? ListThumbnailTintProviding { return provider.listThumbnailTintSource }
        return view.subviews.lazy.compactMap { mounted(in: $0) }.first
    }
}

nonisolated struct ListThumbnailTintColor: Equatable, Sendable {
    let red: CGFloat
    let green: CGFloat
    let blue: CGFloat
}

/// Static thumbnail pixels only. Core Image performs the reduction on a utility task.
nonisolated enum ListThumbnailTintSampler {
    private static let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    private static let context = CIContext(options: [.useSoftwareRenderer: true, .cacheIntermediates: false])

    static func average(_ image: CGImage) -> ListThumbnailTintColor? {
        let input = CIImage(cgImage: image)
        let scale = min(1, 32 / max(input.extent.width, input.extent.height))
        let small = input.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let filter = CIFilter.areaAverage()
        filter.inputImage = small
        filter.extent = small.extent
        guard let output = filter.outputImage else { return nil }
        var pixel = [Float](repeating: 0, count: 4)
        context.render(output, toBitmap: &pixel, rowBytes: 4 * MemoryLayout<Float>.size,
                       bounds: CGRect(x: 0, y: 0, width: 1, height: 1), format: .RGBAf, colorSpace: colorSpace)
        guard pixel.allSatisfy({ $0.isFinite }), pixel[3] > 0.01 else { return nil }
        let components = pixel.prefix(3).map { CGFloat(max(0, min(1, $0 / pixel[3]))) }
        return ListThumbnailTintColor(red: components[0], green: components[1], blue: components[2])
    }
}
