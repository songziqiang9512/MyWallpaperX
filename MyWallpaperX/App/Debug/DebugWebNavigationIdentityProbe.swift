//
//  DebugWebNavigationIdentityProbe.swift
//  MyWallpaperX
//

#if DEBUG
import Foundation
import WebKit

@MainActor
enum DebugWebNavigationIdentityProbe {
    struct Result {
        let currentRecoveryNavigationFinished: Bool
        let pageNavigationFinished: Bool
        let staleRecoveryNavigationIgnored: Bool
        let staleSurfaceNavigationIgnored: Bool
        let terminalNavigation: WKNavigation
        let terminalWebView: WKWebView
    }

    static func run(
        host: DedicatedWebWallpaperHostPlaceholderAdapter,
        engine: WallpaperEngine,
        requestID: UUID,
        staleNavigation: WKNavigation,
        staleWebView: WKWebView,
        expectedPath: String,
        baselineSurfaceCount: Int,
        failureCount: () -> Int
    ) -> Result? {
        guard let surface = host.surfaces.values.first,
              surface.webView !== staleWebView,
              let currentNavigation = host.navigationOwnershipByScreen[surface.screenID]?.navigation,
              currentNavigation !== staleNavigation else {
            return nil
        }

        host.handleNavigationFailure(
            NSError(domain: NSURLErrorDomain, code: NSURLErrorCannotConnectToHost),
            navigation: staleNavigation,
            webView: staleWebView
        )
        let staleSurfaceNavigationIgnored = ownsCurrentRequest(
            host: host,
            engine: engine,
            requestID: requestID,
            expectedPath: expectedPath,
            baselineSurfaceCount: baselineSurfaceCount,
            navigation: currentNavigation,
            surface: surface,
            failureCount: failureCount
        )

        host.handleWebContentTermination(for: surface.webView)
        guard let recoveryWorkItem = host.webContentRecoveryWorkItems[surface.screenID] else { return nil }
        recoveryWorkItem.perform()
        recoveryWorkItem.cancel()
        guard let recoveryNavigation = host.navigationOwnershipByScreen[surface.screenID]?.navigation,
              recoveryNavigation !== currentNavigation else {
            return nil
        }

        host.setAudioSpectrumDemand(true, for: surface.screenID)
        host.webView(surface.webView, didStartProvisionalNavigation: currentNavigation)
        host.webView(surface.webView, didFinish: currentNavigation)
        host.handleNavigationFailure(
            NSError(domain: NSURLErrorDomain, code: NSURLErrorCannotConnectToHost),
            navigation: currentNavigation,
            webView: surface.webView
        )
        let staleRecoveryNavigationIgnored = ownsCurrentRequest(
            host: host,
            engine: engine,
            requestID: requestID,
            expectedPath: expectedPath,
            baselineSurfaceCount: baselineSurfaceCount,
            navigation: recoveryNavigation,
            surface: surface,
            failureCount: failureCount
        )
            && host.recoveringWebContentScreenIDs.contains(surface.screenID)
            && !host.readyScreenIDs.contains(surface.screenID)
            && host.audioSpectrumDemandScreenIDs.contains(surface.screenID)

        host.webView(surface.webView, didFinish: recoveryNavigation)
        let currentRecoveryNavigationFinished = ownsCurrentRequest(
            host: host,
            engine: engine,
            requestID: requestID,
            expectedPath: expectedPath,
            baselineSurfaceCount: baselineSurfaceCount,
            navigation: recoveryNavigation,
            surface: surface,
            failureCount: failureCount
        )
            && !host.recoveringWebContentScreenIDs.contains(surface.screenID)
            && host.readyScreenIDs.contains(surface.screenID)

        guard let pageNavigation = surface.webView.reload(),
              pageNavigation !== recoveryNavigation else {
            return nil
        }
        host.webView(surface.webView, didStartProvisionalNavigation: pageNavigation)
        let pageNavigationStarted = host.phase == .launching
            && !host.readyScreenIDs.contains(surface.screenID)
            && host.navigationOwnershipByScreen[surface.screenID]?.navigation === pageNavigation
        host.webView(surface.webView, didFinish: pageNavigation)
        let pageNavigationFinished = pageNavigationStarted
            && ownsCurrentRequest(
                host: host,
                engine: engine,
                requestID: requestID,
                expectedPath: expectedPath,
                baselineSurfaceCount: baselineSurfaceCount,
                navigation: pageNavigation,
                surface: surface,
                failureCount: failureCount
            )
            && host.readyScreenIDs.contains(surface.screenID)

        guard let terminalNavigation = surface.webView.reload(),
              terminalNavigation !== pageNavigation else {
            return nil
        }
        host.webView(surface.webView, didStartProvisionalNavigation: terminalNavigation)
        guard host.phase == .launching,
              !host.readyScreenIDs.contains(surface.screenID),
              host.navigationOwnershipByScreen[surface.screenID]?.navigation === terminalNavigation else {
            return nil
        }

        return Result(
            currentRecoveryNavigationFinished: currentRecoveryNavigationFinished,
            pageNavigationFinished: pageNavigationFinished,
            staleRecoveryNavigationIgnored: staleRecoveryNavigationIgnored,
            staleSurfaceNavigationIgnored: staleSurfaceNavigationIgnored,
            terminalNavigation: terminalNavigation,
            terminalWebView: surface.webView
        )
    }

    private static func ownsCurrentRequest(
        host: DedicatedWebWallpaperHostPlaceholderAdapter,
        engine: WallpaperEngine,
        requestID: UUID,
        expectedPath: String,
        baselineSurfaceCount: Int,
        navigation: WKNavigation,
        surface: DedicatedWebWallpaperHostPlaceholderAdapter.HostSurface,
        failureCount: () -> Int
    ) -> Bool {
        engine.currentWebRequestID == requestID
            && engine.currentContentPath == expectedPath
            && engine.currentPlaybackContentKind == .web
            && host.currentRequest?.id == requestID
            && host.phase == .ready
            && host.surfaces.count == baselineSurfaceCount
            && host.navigationOwnershipByScreen[surface.screenID]?.navigation === navigation
            && failureCount() == 0
    }
}
#endif
