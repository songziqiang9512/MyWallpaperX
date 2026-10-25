import AppKit

/// A transparent, full-size child host. Providers keep their existing browser
/// and scroll behavior; local pages receive the shared grid controller.
final class AppKitDetailHostViewController: NSViewController {
    private(set) var hostedController: NSViewController?

    override func loadView() { view = NSView() }

    func present(_ controller: NSViewController) {
        loadViewIfNeeded()
        guard hostedController !== controller else { return }
        hostedController?.view.removeFromSuperview()
        hostedController?.removeFromParent()
        hostedController = controller
        addChild(controller)
        let child = controller.view
        child.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(child)
        NSLayoutConstraint.activate([
            child.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            child.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            child.topAnchor.constraint(equalTo: view.topAnchor),
            child.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }
}

final class WallpaperLibraryViewController: NSViewController {
    init(_ content: NSView) { super.init(nibName: nil, bundle: nil); view = content }
    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }
}
