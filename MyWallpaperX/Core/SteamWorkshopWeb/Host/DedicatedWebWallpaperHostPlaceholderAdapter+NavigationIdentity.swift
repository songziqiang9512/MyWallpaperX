//
//  DedicatedWebWallpaperHostPlaceholderAdapter+NavigationIdentity.swift
//  MyWallpaperX
//

import Foundation
import AppKit
import WebKit

extension DedicatedWebWallpaperHostPlaceholderAdapter {
    @discardableResult
    func createAndLoadSurface(
        for screen: NSScreen,
        request: WallpaperEngine.WebWallpaperLaunchRequest,
        localEntryURL: URL,
        loadFailureMessage: String
    ) -> Bool {
        guard let screenID = Self.screenID(for: screen) else { return false }
        let surface = makeSurface(for: screen, screenID: screenID)
        surfaces[screenID] = surface
        setTransientMouseCaptureEnabled(false, for: surface)
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--mwx-debug-web-evidence-dir") {
            surface.window.makeKeyAndOrderFront(nil)
        } else {
            surface.window.orderFrontRegardless()
        }
        #else
        surface.window.orderFrontRegardless()
        #endif
        surface.window.level = Self.webWindowLevel
        loadTrackedNavigation(
            on: surface,
            request: request,
            localEntryURL: localEntryURL,
            stopCurrent: false
        ) { [weak self] didLoad in
            guard let self, didLoad == false else { return }
            self.failCurrentLaunch(message: loadFailureMessage)
        }
        return true
    }

    func reloadTrackedSurfaces(
        for request: WallpaperEngine.WebWallpaperLaunchRequest,
        localEntryURL: URL
    ) {
        for surface in Array(surfaces.values) {
            setTransientMouseCaptureEnabled(false, for: surface)
            surface.schemeHandler.updateAdditionalReadableRoots(accessibleResourceURLs(from: request.propertiesJSON))
            surface.window.orderFrontRegardless()
            surface.window.level = Self.webWindowLevel
            loadTrackedNavigation(
                on: surface,
                request: request,
                localEntryURL: localEntryURL,
                stopCurrent: true
            ) { [weak self] didLoad in
                guard let self, didLoad == false else { return }
                self.failCurrentLaunch(message: "dedicated_web_host_navigation_unavailable")
            }
        }
    }

    func loadTrackedNavigation(
        on surface: HostSurface,
        request: WallpaperEngine.WebWallpaperLaunchRequest,
        localEntryURL: URL,
        stopCurrent: Bool,
        completion: @escaping (Bool) -> Void
    ) {
        navigationOwnershipByScreen.removeValue(forKey: surface.screenID)
        if stopCurrent {
            surface.webView.stopLoading()
        }
        runtimeEntryURL(for: request, localEntryURL: localEntryURL, surface: surface) { [weak self] entryURL in
            // 等待 loopback 端口期间请求或 surface 已被替换：当前 owner 自行
            // 管理生命周期，静默放弃这次装载，不重复报失败。
            guard let self,
                  self.currentRequest?.id == request.id,
                  self.surfaces[surface.screenID]?.webView === surface.webView else {
                return
            }
            guard let navigation = surface.webView.load(URLRequest(url: entryURL)) else {
                completion(false)
                return
            }
            self.navigationOwnershipByScreen[surface.screenID] = NavigationOwnership(
                requestID: request.id,
                navigation: navigation
            )
            completion(true)
        }
    }

    func reloadTrackedNavigation(on surface: HostSurface, requestID: UUID) -> Bool {
        navigationOwnershipByScreen.removeValue(forKey: surface.screenID)
        guard let navigation = surface.webView.reload() else { return false }
        guard currentRequest?.id == requestID,
              surfaces[surface.screenID]?.webView === surface.webView else {
            return false
        }
        navigationOwnershipByScreen[surface.screenID] = NavigationOwnership(
            requestID: requestID,
            navigation: navigation
        )
        return true
    }

    func screenIDForCurrentNavigation(_ navigation: WKNavigation?, webView: WKWebView) -> CGDirectDisplayID? {
        guard let requestID = currentRequest?.id,
              let navigation,
              let screenID = screenID(for: webView),
              surfaces[screenID]?.webView === webView,
              let tracked = navigationOwnershipByScreen[screenID],
              tracked.requestID == requestID,
              tracked.navigation === navigation else {
            return nil
        }
        return screenID
    }

    func screenIDForStartedNavigation(_ navigation: WKNavigation?, webView: WKWebView) -> CGDirectDisplayID? {
        guard let requestID = currentRequest?.id,
              let navigation,
              let screenID = screenID(for: webView),
              surfaces[screenID]?.webView === webView else {
            return nil
        }
        if let ownership = navigationOwnershipByScreen[screenID],
           ownership.requestID == requestID,
           ownership.navigation === navigation {
            return screenID
        }
        guard !recoveringWebContentScreenIDs.contains(screenID),
              readyScreenIDs.contains(screenID) else {
            return nil
        }
        navigationOwnershipByScreen[screenID] = NavigationOwnership(
            requestID: requestID,
            navigation: navigation
        )
        readyScreenIDs.remove(screenID)
        phase = .launching
        return screenID
    }
}
