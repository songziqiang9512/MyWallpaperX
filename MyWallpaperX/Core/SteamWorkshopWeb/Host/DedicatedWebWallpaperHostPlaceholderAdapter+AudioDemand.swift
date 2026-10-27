//
//  DedicatedWebWallpaperHostPlaceholderAdapter+AudioDemand.swift
//  MyWallpaperX
//

import Foundation
import WebKit
import CoreGraphics

final class WebAudioDemandMessageHandler: NSObject, WKScriptMessageHandler {
    weak var adapter: DedicatedWebWallpaperHostPlaceholderAdapter?
    let screenID: CGDirectDisplayID

    init(adapter: DedicatedWebWallpaperHostPlaceholderAdapter, screenID: CGDirectDisplayID) {
        self.adapter = adapter
        self.screenID = screenID
    }

    func userContentController(
        _: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard message.name == "wallpaperHostAudioDemand",
              let payload = message.body as? [String: Any],
              let nonce = payload["nonce"] as? String,
              let adapter,
              adapter.surfaces[screenID]?.audioDemandMessageHandler === self else {
            return
        }
        guard let webView = adapter.surfaces[screenID]?.webView else { return }
        adapter.handleAudioSpectrumDemand(payload, nonce: nonce, webView: webView)
    }
}

extension DedicatedWebWallpaperHostPlaceholderAdapter {
    func handleAudioSpectrumDemand(_ body: [String: Any], nonce: String, webView: WKWebView) {
        guard currentRequest != nil, screenID(for: webView) != nil,
              let token = body["token"] as? String,
              let active = body["active"] as? Bool,
              let endpoint = frameEndpointRegistry.endpoints(in: webView).first(where: {
                  $0.token == token && $0.documentNonce == nonce
              }), endpoint.isLeaseValid(now: ProcessInfo.processInfo.systemUptime) else { return }
        let wasActive = endpoint.audioDemandActive
        endpoint.audioDemandActive = active
        if !active { endpoint.pendingSpectrumPush = nil }
        refreshAudioSpectrumDemand()
        if wasActive && !active && lastPublishedAudioSpectrumDemand {
            clearAudioSpectrum(to: endpoint, webView: webView)
        }
    }

    /// Endpoint registration is the only per-document demand owner. This bool
    /// only deduplicates publication of the aggregate to the shared capture owner.
    func refreshAudioSpectrumDemand() {
        let now = ProcessInfo.processInfo.systemUptime
        let demandedScreens = surfaces.values.lazy.filter { surface in
            self.frameEndpointRegistry.endpoints(in: surface.webView).contains {
                $0.audioDemandActive && $0.isLeaseValid(now: now)
            }
        }
        let active = !demandedScreens.isEmpty
        guard lastPublishedAudioSpectrumDemand != active else { return }
        lastPublishedAudioSpectrumDemand = active
        if !active {
            // Retained documents may still display the last bars (including
            // passive DOM observers). Preserve one ordered silence barrier;
            // their registration alone does not retain the capture consumer.
            for surface in surfaces.values {
                for endpoint in frameEndpointRegistry.endpoints(in: surface.webView) {
                    clearAudioSpectrum(to: endpoint, webView: surface.webView)
                }
            }
        }
#if DEBUG
        recordDiagnostic(
            type: "web.audio-demand", severity: .info,
            message: "active=\(active) surfaces=\(demandedScreens.count)",
            screenID: nil, url: nil
        )
#endif
        if let requestID = currentRequest?.id {
            eventHandler?(.audioSpectrumDemandChanged(active, requestID: requestID))
        }
    }

    /// Navigation and surface teardown withdraw only this display's documents;
    /// another display's valid endpoints must retain their shared capture lease.
    func clearAudioSpectrumDemand(for screenID: CGDirectDisplayID) {
        let surface = surfaces[screenID]
        let endpoints = surface.map { frameEndpointRegistry.endpoints(in: $0.webView) } ?? []
        let withdrawn = endpoints.filter { $0.audioDemandActive }
        for endpoint in endpoints {
            endpoint.audioDemandActive = false
            endpoint.pendingSpectrumPush = nil
        }
        refreshAudioSpectrumDemand()
        if let surface, lastPublishedAudioSpectrumDemand {
            for endpoint in withdrawn { clearAudioSpectrum(to: endpoint, webView: surface.webView) }
        }
    }

    func clearAudioSpectrumDemand() {
        for surface in surfaces.values {
            for endpoint in frameEndpointRegistry.endpoints(in: surface.webView) {
                endpoint.audioDemandActive = false
                endpoint.pendingSpectrumPush = nil
            }
        }
        refreshAudioSpectrumDemand()
    }
}
