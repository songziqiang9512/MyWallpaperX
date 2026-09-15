//
//  AppKitSteamWorkshopDownloadsView.swift
//  MyWallpaperX
//

import AppKit
import Combine

final class AppKitSteamWorkshopDownloadsView: NSView {
    private let service = SteamWorkshopService.shared
    private var cancellables = Set<AnyCancellable>()
    private var inspectorDetailView: AppKitSteamWorkshopItemDetailView?
    private var lastRequestedCardID: String?
    private var visibleCardID: String?
    private var latestInspectorItem: SteamWorkshopBrowserItem?
    private var isHandlingHostClose = false
    private var isShowingDownloadError = false

    private lazy var gridView = AppKitSteamWorkshopDownloadsContainerView(
        service: service,
        onOpen: { [weak self] item in
            self?.service.presentItemDetail(item)
        },
        onSetAsWallpaper: { [weak self] record in
            self?.service.setAsWallpaper(record)
        }
    )

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
        observeService()
        observeInspectorHost()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            InspectorHostActions.postClose(module: .steamWorkshop)
            service.dismissDownloadInspector()
            return
        }

        if service.downloads.isEmpty {
            service.reloadInstalledItems()
        }
        presentPendingDownloadErrorIfNeeded()
        syncSelectedInspectorItem(service.selectedDownloadInspectorItem)
    }

    private func setup() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        translatesAutoresizingMaskIntoConstraints = false

        gridView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(gridView)
        NSLayoutConstraint.activate([
            gridView.leadingAnchor.constraint(equalTo: leadingAnchor),
            gridView.trailingAnchor.constraint(equalTo: trailingAnchor),
            gridView.topAnchor.constraint(equalTo: topAnchor),
            gridView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    private func observeService() {
        service.$selectedDownloadInspectorItem
            .receive(on: DispatchQueue.main)
            .sink { [weak self] item in self?.syncSelectedInspectorItem(item) }
            .store(in: &cancellables)

        service.$downloadError
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.presentPendingDownloadErrorIfNeeded() }
            .store(in: &cancellables)
    }

    private func observeInspectorHost() {
        NotificationCenter.default.publisher(for: .inspectorHostDidPresent)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in self?.handleInspectorDidPresent(notification) }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .inspectorHostDidClose)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in self?.handleInspectorDidClose(notification) }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .inspectorHostCloseRequested)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in self?.handleInspectorCloseRequested(notification) }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .moduleDidBecomeActive)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in self?.handleModuleActivation(notification) }
            .store(in: &cancellables)
    }

    private func syncSelectedInspectorItem(_ item: SteamWorkshopBrowserItem?) {
        latestInspectorItem = item
        guard !isHandlingHostClose else { return }

        guard let item else {
            if let cardID = visibleCardID ?? lastRequestedCardID {
                InspectorHostActions.postClose(module: .steamWorkshop, cardID: cardID)
            } else {
                removeInspectorContent()
            }
            return
        }

        let presentation = makePresentation(for: item)
        lastRequestedCardID = presentation.cardID
        if visibleCardID == presentation.cardID {
            installInspectorContent(for: item)
            return
        }
        InspectorHostActions.postOpen(module: .steamWorkshop, presentation: presentation)
    }

    private func makePresentation(for item: SteamWorkshopBrowserItem) -> InspectorHostPresentation {
        .infoPanel(
            cardID: item.id,
            title: item.title,
            subtitle: item.author.isEmpty ? "Steam 下载" : item.author,
            preferredWidth: 356,
            focusPolicy: .preserveCurrentResponder
        )
    }

    private func handleInspectorDidPresent(_ notification: Notification) {
        guard let request = InspectorHostRequest(userInfo: notification.userInfo),
              request.token.module == .steamWorkshop,
              let item = latestInspectorItem,
              request.token.cardID == makePresentation(for: item).cardID else {
            return
        }

        visibleCardID = request.token.cardID
        installInspectorContent(for: item)
    }

    private func handleInspectorCloseRequested(_ notification: Notification) {
        let dismissRequest = InspectorHostDismissRequest(userInfo: notification.userInfo)
        if let requestedModule = dismissRequest?.module, requestedModule != .steamWorkshop {
            return
        }
        if let visibleCardID,
           dismissRequest?.cardID == nil || dismissRequest?.cardID == visibleCardID {
            self.visibleCardID = nil
        }
    }

    private func handleInspectorDidClose(_ notification: Notification) {
        guard let request = InspectorHostRequest(userInfo: notification.userInfo),
              request.token.module == .steamWorkshop else {
            return
        }

        isHandlingHostClose = true
        visibleCardID = nil
        lastRequestedCardID = nil
        removeInspectorContent()
        service.dismissDownloadInspector()
        isHandlingHostClose = false
    }

    private func handleModuleActivation(_ notification: Notification) {
        guard let moduleRawValue = notification.userInfo?["module"] as? String,
              moduleRawValue != ModuleIdentifier.steamWorkshop.rawValue,
              latestInspectorItem != nil else {
            return
        }

        InspectorHostActions.postClose(module: .steamWorkshop, cardID: visibleCardID ?? lastRequestedCardID)
        visibleCardID = nil
        lastRequestedCardID = nil
        removeInspectorContent()
        service.dismissDownloadInspector()
    }

    private func installInspectorContent(for item: SteamWorkshopBrowserItem) {
        let detailView: AppKitSteamWorkshopItemDetailView
        if let existing = inspectorDetailView {
            existing.configure(item: item)
            detailView = existing
        } else {
            let created = AppKitSteamWorkshopItemDetailView(item: item)
            inspectorDetailView = created
            detailView = created
        }

        InspectorHostActions.postMount(
            module: .steamWorkshop,
            cardID: makePresentation(for: item).cardID,
            hostedView: detailView
        )
    }

    private func removeInspectorContent() {
        inspectorDetailView?.removeFromSuperview()
        inspectorDetailView = nil
    }

    private func presentPendingDownloadErrorIfNeeded() {
        guard let message = service.downloadError, !message.isEmpty else { return }
        guard !isShowingDownloadError else { return }
        guard let window else { return }

        isShowingDownloadError = true
        let alert = NSAlert()
        alert.messageText = "下载失败"
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "确定")
        alert.beginSheetModal(for: window) { [weak self] _ in
            guard let self else { return }
            self.service.downloadError = nil
            self.isShowingDownloadError = false
        }
    }
}
