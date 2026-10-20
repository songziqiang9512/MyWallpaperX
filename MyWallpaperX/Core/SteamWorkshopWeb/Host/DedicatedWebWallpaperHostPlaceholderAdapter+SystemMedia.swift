//
//  DedicatedWebWallpaperHostPlaceholderAdapter+SystemMedia.swift
//  MyWallpaperX
//

import Foundation
import WebKit

extension DedicatedWebWallpaperHostPlaceholderAdapter {
    func handleSystemMediaDemand(_ body: [String: Any], nonce: String, webView: WKWebView) {
        guard currentRequest != nil,
              let token = body["token"] as? String,
              let active = body["active"] as? Bool,
              let needsMedia = body["needsMedia"] as? Bool,
              let endpoint = frameEndpointRegistry.endpoints(in: webView).first(where: {
                  $0.token == token && $0.documentNonce == nonce
              }), isSystemMediaEndpointCurrent(endpoint, in: webView) else { return }
        let needsContent = active && needsMedia
        let changed = endpoint.mediaDemandActive != active || endpoint.mediaDemandNeedsContent != needsContent
        endpoint.mediaDemandActive = active
        endpoint.mediaDemandNeedsContent = needsContent
        if changed {
            endpoint.deliveredMediaEpoch = nil
            endpoint.deliveredMediaRevision = nil
            endpoint.deliveredMediaArtworkKey = nil
            endpoint.pendingMediaSnapshot = nil
        }
        refreshSystemMediaSubscription()
        // An additional listener/frame may attach while the service subscription
        // stays unchanged. Replay the current snapshot without restarting capture.
        if active {
            let snapshot = systemMediaDemandHandler == nil
                ? SystemMediaService.shared.currentSnapshot : currentSystemMediaSnapshot
            if let snapshot { deliverSystemMedia(snapshot, to: endpoint, webView: webView) }
        }
    }

    func refreshSystemMediaSubscription() {
        let endpoints = surfaces.values.flatMap { frameEndpointRegistry.endpoints(in: $0.webView) }
        let now = ProcessInfo.processInfo.systemUptime
        let demanded = endpoints.filter { $0.mediaDemandActive && $0.isLeaseValid(now: now) }
        guard let requestID = currentRequest?.id, !demanded.isEmpty else {
            if systemMediaSubscriptionNeedsContent != nil {
                if let systemMediaDemandHandler, let requestID = currentRequest?.id {
                    systemMediaDemandHandler(nil, requestID)
                } else if systemMediaDemandHandler == nil {
                    SystemMediaService.shared.unsubscribe(systemMediaConsumerID)
                }
            }
            systemMediaSubscriptionNeedsContent = nil
            currentSystemMediaSnapshot = nil
            return
        }
        let needsContent = demanded.contains { $0.mediaDemandNeedsContent }
        guard systemMediaSubscriptionNeedsContent != needsContent else { return }
        systemMediaSubscriptionNeedsContent = needsContent
        if let systemMediaDemandHandler {
            systemMediaDemandHandler(needsContent, requestID)
            return
        }
        SystemMediaService.shared.subscribe(systemMediaConsumerID, needsMedia: needsContent,
                                           needsWebArtwork: needsContent) { [weak self] snapshot in
            guard let self, self.currentRequest?.id == requestID,
                  self.systemMediaSubscriptionNeedsContent != nil else { return }
            self.receiveSystemMediaSnapshot(snapshot)
        }
    }

    func receiveSystemMediaSnapshot(_ snapshot: SystemMediaSnapshot) {
        guard currentRequest != nil, systemMediaSubscriptionNeedsContent != nil else { return }
        currentSystemMediaSnapshot = snapshot
        forEachWebView { webView in
            for endpoint in self.frameEndpointRegistry.endpoints(in: webView) where endpoint.mediaDemandActive {
                deliverSystemMedia(snapshot, to: endpoint, webView: webView)
            }
        }
    }

    func isSystemMediaEndpointCurrent(_ endpoint: WebWallpaperFrameEndpointRegistry.Endpoint, in webView: WKWebView) -> Bool {
        currentRequest != nil && screenID(for: webView) != nil
            && endpoint.isLeaseValid(now: ProcessInfo.processInfo.systemUptime)
            && frameEndpointRegistry.endpoints(in: webView).contains { $0 === endpoint }
    }

    /// One in-flight call and one complete latest snapshot per endpoint. Pending
    /// snapshots retain all channels, including clear/artwork; only the encoding
    /// omits an artwork generation already acknowledged by this document.
    func deliverSystemMedia(
        _ snapshot: SystemMediaSnapshot,
        to endpoint: WebWallpaperFrameEndpointRegistry.Endpoint,
        webView: WKWebView
    ) {
        guard isSystemMediaEndpointCurrent(endpoint, in: webView) else { return }
        if endpoint.isMediaDeliveryInFlight {
            endpoint.pendingMediaSnapshot = snapshot
            return
        }
        guard endpoint.deliveredMediaEpoch != snapshot.epoch
            || endpoint.deliveredMediaRevision != snapshot.revision else { return }
        let artworkKey = WebWallpaperFrameEndpointRegistry.Endpoint.MediaArtworkKey(
            epoch: snapshot.epoch, sourceID: snapshot.sourceID, sessionID: snapshot.sessionID,
            sessionGeneration: snapshot.sessionGeneration, generation: snapshot.media.generation,
            hasThumbnail: snapshot.enabled && endpoint.mediaDemandNeedsContent && snapshot.webThumbnail != nil,
            needsContent: endpoint.mediaDemandNeedsContent
        )
        let includeArtwork = endpoint.deliveredMediaArtworkKey != artworkKey
        let needsContent = endpoint.mediaDemandNeedsContent
        var payload = Self.systemMediaPayload(snapshot, needsContent: needsContent, includeArtwork: includeArtwork)
        payload["deliverySequence"] = String(endpoint.advancePushSequence())
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let json = String(data: data, encoding: .utf8) else { return }
        let token = WebWallpaperHostSupport.javaScriptQuotedString(endpoint.token)
        let nonce = WebWallpaperHostSupport.javaScriptQuotedString(endpoint.documentNonce)
        let requestID = currentRequest?.id
        endpoint.isMediaDeliveryInFlight = true
        webView.evaluateJavaScript(
            "window.__myWallpaperApplySystemMedia(\(json), \(token), \(nonce));",
            in: endpoint.frameInfo, in: .page
        ) { [weak self, weak webView] result in
            Task { @MainActor in
                endpoint.isMediaDeliveryInFlight = false
                guard let self, let webView, self.currentRequest?.id == requestID,
                      self.isSystemMediaEndpointCurrent(endpoint, in: webView) else {
                    endpoint.pendingMediaSnapshot = nil
                    return
                }
                if case .success(let accepted) = result, accepted as? Bool == true,
                   endpoint.mediaDemandNeedsContent == needsContent {
                    endpoint.deliveredMediaEpoch = snapshot.epoch
                    endpoint.deliveredMediaRevision = snapshot.revision
                    endpoint.deliveredMediaArtworkKey = artworkKey
                }
                if let latest = endpoint.pendingMediaSnapshot {
                    endpoint.pendingMediaSnapshot = nil
                    self.deliverSystemMedia(latest, to: endpoint, webView: webView)
                }
            }
        }
    }

    static func systemMediaPayload(_ snapshot: SystemMediaSnapshot, needsContent: Bool, includeArtwork: Bool) -> [String: Any] {
        let media = snapshot.enabled && needsContent ? snapshot.media : .empty
        let properties = media.properties
        let timeline = media.timeline
        let available = snapshot.enabled && needsContent && snapshot.sourceID != nil && snapshot.sessionID != nil
        // Explicit enum mapping: STOPPED is zero and cannot be tested for truth.
        let playback: Int
        switch media.playbackState {
        case 1: playback = 1
        case 2: playback = 2
        default: playback = 0
        }
        var payload: [String: Any] = [
            "epoch": String(snapshot.epoch), "revision": String(snapshot.revision),
            "status": ["enabled": snapshot.enabled, "available": available ? "true" : "false", "state": playback],
            "properties": [
                "title": properties?.title ?? "", "artist": properties?.artist ?? "",
                "subTitle": properties?.subTitle ?? "", "albumTitle": properties?.albumTitle ?? "",
                "albumArtist": properties?.albumArtist ?? "", "genres": properties?.genres ?? "",
                "contentType": properties?.contentType ?? ""
            ],
            "timeline": ["position": timeline?.position ?? 0, "duration": timeline?.duration ?? 0,
                         "available": timeline == nil ? "false" : "true"],
            "playback": ["state": playback]
        ]
        if includeArtwork {
            let thumbnail = snapshot.enabled && needsContent ? snapshot.webThumbnail ?? "" : ""
            payload["thumbnail"] = [
                "thumbnail": thumbnail,
                "primaryColor": systemMediaCSSColor(media.primaryColor),
                "secondaryColor": systemMediaCSSColor(media.secondaryColor),
                "tertiaryColor": systemMediaCSSColor(media.tertiaryColor),
                "textColor": systemMediaCSSColor(media.textColor),
                "highContrastColor": systemMediaCSSColor(media.highContrastColor)
            ]
        }
        return payload
    }

    private static func systemMediaCSSColor(_ color: SIMD3<Double>?) -> String {
        guard let color, color.x.isFinite, color.y.isFinite, color.z.isFinite else { return "" }
        let channels = [color.x, color.y, color.z].map { Int((min(1, max(0, $0)) * 255).rounded()) }
        return String(format: "#%02x%02x%02x", channels[0], channels[1], channels[2])
    }
}
