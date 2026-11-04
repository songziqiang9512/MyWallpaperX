import CoreGraphics

nonisolated struct ThumbnailRequest: Hashable, Sendable {
    enum Mode: Hashable, Sendable { case fill, fit }
    let width: Int
    let height: Int
    let mode: Mode

    init(width: Int, height: Int, mode: Mode) {
        self.width = width
        self.height = height
        self.mode = mode
    }

    init?(size: CGSize, scale: CGFloat, mode: Mode) {
        let width = ceil(size.width * scale), height = ceil(size.height * scale)
        guard scale > 0, width.isFinite, height.isFinite, width > 0, height > 0,
              width < CGFloat(Int.max), height < CGFloat(Int.max) else { return nil }
        self.init(width: Int(width), height: Int(height), mode: mode)
    }

    func scale(for sourceSize: CGSize) -> CGFloat {
        let x = CGFloat(width) / sourceSize.width, y = CGFloat(height) / sourceSize.height
        return mode == .fill ? max(x, y) : min(x, y)
    }

    func decodedSize(for nativeSize: CGSize, minimumLongestSide: Int = 0) -> CGSize {
        let scale = min(1, max(self.scale(for: nativeSize),
            CGFloat(minimumLongestSide) / max(nativeSize.width, nativeSize.height)))
        return CGSize(width: ceil(nativeSize.width * scale), height: ceil(nativeSize.height * scale))
    }

    /// A prepared derivative's own dimensions do not establish the source's limit.
    func isCovered(by pixels: CGSize, nativeSize: CGSize? = nil) -> Bool {
        // AV/ImageIO may round a fitted edge down by one actual raster pixel.
        let rounded = CGSize(width: pixels.width + 1, height: pixels.height + 1)
        if scale(for: rounded) <= 1 { return true }
        guard let nativeSize else { return false }
        return rounded.width >= nativeSize.width && rounded.height >= nativeSize.height
    }

    func hasSameAspect(as other: ThumbnailRequest) -> Bool {
        Double(width) * Double(other.height) == Double(height) * Double(other.width)
    }

    func cropSize(in sourceSize: CGSize) -> CGSize {
        let scale = min(sourceSize.width / CGFloat(width), sourceSize.height / CGFloat(height))
        return CGSize(width: max(1, floor(CGFloat(width) * scale)),
                      height: max(1, floor(CGFloat(height) * scale)))
    }
}
