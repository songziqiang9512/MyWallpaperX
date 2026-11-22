//
//  SteamWorkshopToolbarController+Configuration.swift
//  MyWallpaperX
//

import AppKit

extension SteamWorkshopToolbarController {
    var accountActionsEnabled: Bool {
        switch SteamWorkshopService.shared.steamAuth.displayState {
        case .connecting, .awaitingInput: return false
        default: return true
        }
    }

    func focusSearch() {
        guard isSteamWorkshopMode else { return }
        searchToolbarItem.beginSearchInteraction()
    }

    func configureZoom(preferredColumns: Int, clipWidth: CGFloat) {
        zoomControl.update(preferredColumns: preferredColumns, clipWidth: clipWidth, canDispatch: makeZoomAction != nil)
        zoomToolbarItem.isEnabled = zoomControl.isEnabled
        zoomToolbarItem.menuFormRepresentation = zoomControl.menuRepresentation()
    }

    func configureAuthItems() {
        let service = SteamWorkshopService.shared
        let auth = service.steamAuth
        let requiresLoginAttention = service.browsingNeedsSignIn

        // SK2.2：账号按钮状态由新登录路线驱动（§3.1）。
        let symbolName: String
        let tint: NSColor
        let tooltip: String
        switch auth.displayState {
        case .online:
            symbolName = "person.crop.circle.badge.checkmark"
            tint = .controlAccentColor
            tooltip = String(localized: "Steam Account Menu")
        case .connecting, .awaitingInput:
            symbolName = "hourglass"
            tint = .secondaryLabelColor
            tooltip = String(localized: "Signing in to Steam…")
        case .expired:
            symbolName = "person.crop.circle.badge.exclamationmark"
            tint = .systemOrange
            tooltip = String(localized: "Sign In Again")
        case .failed:
            symbolName = "person.crop.circle.badge.exclamationmark"
            tint = .systemOrange
            tooltip = String(localized: "Something went wrong signing in. Click to sign in again.")
        case .signedOut:
            symbolName = "person.crop.circle"
            tint = requiresLoginAttention ? .systemOrange : .labelColor
            tooltip = String(localized: "Sign in to Steam")
        }
        accountButton.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: String(localized: "Steam Account"))
        accountButton.contentTintColor = tint
        accountButton.toolTip = tooltip
        accountButton.setAccessibilityLabel(String(localized: "Steam account, \(tooltip)"))
        let canExecute = accountActionsEnabled
        accountButton.isEnabled = canExecute
        accountToolbarItem.isEnabled = canExecute
        accountToolbarItem.toolTip = accountButton.toolTip
        accountToolbarItem.menuFormRepresentation = ToolbarMenu.menuRepresentation(title: String(localized: "Steam Account"), rows: accountRows())
        accountToolbarItem.menuFormRepresentation?.isEnabled = canExecute
        accountToolbarItem.visibilityPriority = .low
    }

    func configureAuthorBackItem() {
        let service = SteamWorkshopService.shared
        let canReturn = service.canReturnFromBrowse
        authorBackToolbarItem.isEnabled = canReturn
        authorBackButton.isEnabled = canReturn
        authorBackButton.alphaValue = canReturn ? 1.0 : 0.45
        authorBackButton.toolTip = canReturn
            ? (service.isBrowsingAuthorWorkshop ? service.authorWorkshopReturnDestination?.title ?? String(localized: "Back to Workshop") : String(localized: "Back to Workshop"))
            : String(localized: "Not on a secondary browse page")
        authorBackToolbarItem.toolTip = authorBackButton.toolTip
        let back = ActionMenuItem(title: authorBackButton.toolTip ?? String(localized: "Back to Workshop"), symbol: "chevron.backward") { [weak self] in self?.handleBackToDiscovery() }
        back.isEnabled = canReturn
        authorBackToolbarItem.menuFormRepresentation = back
    }

    func syncSortPopup() {
        let service = SteamWorkshopService.shared
        let source = service.source
        let isEnabled = !service.isBrowsingAuthorWorkshop
        sortToolbarItem.isEnabled = isEnabled
        sortButton.isEnabled = isEnabled
        sortToolbarItem.label = source.isPersonal ? String(localized: "Sort") : String(localized: "Browse Sources")
        sortToolbarItem.paletteLabel = sortToolbarItem.label
        sortToolbarItem.toolTip = isEnabled
            ? (source.isPersonal ? String(localized: "Current personal library sort: \(service.personalSort.displayName)") : String(localized: "Current browsing source: \(source.displayName)"))
            : String(localized: "Author Workshop mode doesn’t support switching the browsing source yet")
        sortButton.toolTip = sortToolbarItem.toolTip
        sortButton.sizeToFit()
        sortToolbarItem.menuFormRepresentation = ToolbarMenu.menuRepresentation(title: sortToolbarItem.label, rows: sortRows())
    }

    func syncPersonalListPopup() {
        let service = SteamWorkshopService.shared
        let isEnabled = service.source.isPersonal && !service.isBrowsingAuthorWorkshop
        personalListButton.title = service.source == .myFavorites ? String(localized: "Steam Favorites") : service.source.toolbarDisplayName
        personalListToolbarItem.isEnabled = isEnabled
        personalListButton.isEnabled = isEnabled
        personalListToolbarItem.toolTip = isEnabled
            ? String(localized: "Current personal list: \(service.source.displayName)")
            : String(localized: "In “My Subscriptions”, select a personal list")
        personalListButton.toolTip = personalListToolbarItem.toolTip
        personalListButton.sizeToFit()
        personalListToolbarItem.menuFormRepresentation = ToolbarMenu.menuRepresentation(title: String(localized: "Personal List"), rows: personalListRows())
    }

    func syncTrendingWindowPopup() {
        trendingWindowButton.title = SteamWorkshopService.shared.trendingWindow.displayName
        let isEnabled =
            SteamWorkshopService.shared.source.supportsTimeRange
            && !SteamWorkshopService.shared.isBrowsingAuthorWorkshop
        trendingWindowToolbarItem.isEnabled = isEnabled
        trendingWindowButton.isEnabled = isEnabled
        trendingWindowButton.sizeToFit()
        trendingWindowToolbarItem.menuFormRepresentation = ToolbarMenu.menuRepresentation(title: String(localized: "Time Range"), rows: trendingWindowRows())
    }

    func configureFilterItem() {
        let service = SteamWorkshopService.shared
        filterButton.title = String(localized: "Filter")
        let isEnabled = !service.isBrowsingAuthorWorkshop
        filterButton.toolTip = service.isBrowsingAuthorWorkshop
            ? String(localized: "Author Workshop mode doesn’t support sorting or filtering yet")
            : String(localized: "Content: \(service.browserContentMode.displayName) · Filter: \(service.activeFilterSummary)")
        filterToolbarItem.isEnabled = isEnabled
        filterButton.isEnabled = isEnabled
        filterToolbarItem.toolTip = filterButton.toolTip
        let filter = ActionMenuItem(title: String(localized: "Filter"), symbol: WallpaperLibraryControlStyle.filterSymbol) { [weak self] in self?.handleFilterMenu() }
        filter.isEnabled = isEnabled
        filterToolbarItem.menuFormRepresentation = filter
    }

    func syncSearchField() {
        let service = SteamWorkshopService.shared
        if let input = pendingSearchInput,
           input.navigation != service.navigationVersion || input.account != service.steamAuth.steamId {
            discardPendingSearch()
        }
        let text = pendingSearchInput?.text ?? service.browserQuery
        if searchField.stringValue.trimmingCharacters(in: .whitespaces) != text { searchField.stringValue = text }
        searchToolbarItem.isEnabled = true
        searchField.isEnabled = true
        searchField.placeholderString = SteamWorkshopService.shared.isBrowsingAuthorWorkshop
            ? String(localized: "Search Loaded Artworks") : String(localized: "Search in \(SteamWorkshopService.shared.browserSectionTitle)")
        searchField.setAccessibilityLabel(searchField.placeholderString)
    }

    func syncBrowserContextControls() {
        guard isSteamWorkshopMode else { return }
        titleUpdateHandler?(SteamWorkshopService.shared.browserSectionTitle)
        configureAuthorBackItem()
        syncSortPopup()
        syncPersonalListPopup()
        syncTrendingWindowPopup()
        configureFilterItem()
        syncSearchField()
        refreshToolbarContextViews()
    }

    func refreshToolbarContextViews() {
        let views: [NSView] = [
            authorBackButton,
            sortButton,
            personalListButton,
            trendingWindowButton,
            filterButton,
            searchField
        ]
        views.forEach {
            $0.needsLayout = true
            $0.needsDisplay = true
        }
        toolbar?.items.forEach { item in
            item.view?.needsLayout = true
            item.view?.needsDisplay = true
        }
    }

}
