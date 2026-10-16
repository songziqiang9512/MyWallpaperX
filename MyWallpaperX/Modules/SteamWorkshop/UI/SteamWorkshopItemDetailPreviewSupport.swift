import AppKit

final class SteamWorkshopPreviewImageContainerView: NSView {
    private let imageView = NSImageView()
    private let placeholderView = SteamWorkshopPreviewPlaceholderView()
    let previewState = SteamWorkshopPreviewState(loaders: .live(priority: .userInitiated))

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.cornerRadius = 18
        layer?.masksToBounds = true
        layer?.borderWidth = 0.45
        layer?.borderColor = NSColor.white.withAlphaComponent(0.09).cgColor
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.imageAlignment = .alignCenter
        addSubview(imageView)
        addSubview(placeholderView)
        previewState.onChange = { [weak self] in self?.applyPreviewState() }
        previewState.setAnimationActive(true)
    }

    override func layout() {
        super.layout()
        updateImageFrame()
    }

    func configure(itemID: String, previewImageURL: URL?, fallbackImageURL: URL? = nil, fallbackVideoURL: URL?, refreshToken: Int) {
        previewState.configure(previewURL: previewImageURL, fallbackImageURL: fallbackImageURL, fallbackVideoURL: fallbackVideoURL, refreshToken: refreshToken)
    }

    private func applyPreviewState() {
        imageView.image = previewState.image
        imageView.animates = previewState.isAnimating
        placeholderView.setState(previewState.placeholder)
        updateImageFrame()
    }

    private func updateImageFrame() {
        let containerBounds = bounds
        guard containerBounds.width > 0, containerBounds.height > 0 else {
            imageView.frame = .zero
            placeholderView.frame = .zero
            return
        }
        placeholderView.frame = containerBounds
        guard let image = imageView.image, image.size.width > 0, image.size.height > 0 else {
            imageView.frame = containerBounds
            return
        }

        let widthScale = containerBounds.width / image.size.width
        let heightScale = containerBounds.height / image.size.height
        let scale = max(widthScale, heightScale)
        let fittedWidth = image.size.width * scale
        let fittedHeight = image.size.height * scale
        imageView.frame = CGRect(
            x: floor((containerBounds.width - fittedWidth) * 0.5),
            y: floor((containerBounds.height - fittedHeight) * 0.5),
            width: ceil(fittedWidth),
            height: ceil(fittedHeight)
        )
    }
}
