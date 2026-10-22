import AppKit

struct InspectorHostPresentation {
    let cardID: String
    let title: String
    let subtitle: String?
    let preferredWidth: CGFloat
    let focusPolicy: InspectorHostFocusPolicy
    let chromeStyle: InspectorHostChromeStyle

    init(
        cardID: String,
        title: String,
        subtitle: String? = nil,
        preferredWidth: CGFloat = InspectorHostRequest.defaultPreferredWidth,
        focusPolicy: InspectorHostFocusPolicy = .preserveCurrentResponder,
        chromeStyle: InspectorHostChromeStyle = .standard
    ) {
        self.cardID = cardID
        self.title = title
        self.subtitle = subtitle
        self.preferredWidth = preferredWidth
        self.focusPolicy = focusPolicy
        self.chromeStyle = chromeStyle
    }
}
