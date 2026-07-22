import AppKit
import SwiftUI

@MainActor
final class ScenePropertyWindowController: NSWindowController, NSWindowDelegate {
    static let shared = ScenePropertyWindowController()

    private let initialContentSize = NSSize(width: 520, height: 640)
    private let contentController = NSHostingController(rootView: AnyView(EmptyView()))
    private var hasShownWindow = false

    private init() {
        let window = MainAppWindow(contentViewController: contentController)
        window.identifier = NSUserInterfaceItemIdentifier("ScenePropertyWindow")
        window.title = "Scene 属性调节"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.titleVisibility = .visible
        window.titlebarAppearsTransparent = false
        window.isOpaque = true
        window.backgroundColor = .windowBackgroundColor
        window.setContentSize(initialContentSize)
        window.minSize = NSSize(width: 440, height: 480)
        window.isReleasedWhenClosed = false
        window.isRestorable = false
        window.collectionBehavior.remove(.fullScreenAuxiliary)
        window.collectionBehavior.remove(.moveToActiveSpace)
        window.level = .normal

        super.init(window: window)
        shouldCascadeWindows = false
        self.window?.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func show(
        record: SteamWorkshopDownloadRecord,
        context: SteamWorkshopScenePropertyContext
    ) {
        contentController.rootView = AnyView(
            SteamWorkshopScenePropertyEditorView(record: record, context: context)
                .id(record.id)
        )

        guard let window else { return }
        window.title = "\(record.title) - Scene 属性"
        if !hasShownWindow {
            window.center()
            hasShownWindow = true
        }
        if window.isMiniaturized {
            window.deminiaturize(nil)
        }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}
