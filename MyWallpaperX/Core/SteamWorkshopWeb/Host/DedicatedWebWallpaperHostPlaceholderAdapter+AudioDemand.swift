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
              let active = payload["active"] as? Bool,
              let adapter,
              adapter.surfaces[screenID]?.audioDemandMessageHandler === self else {
            return
        }
        adapter.setAudioSpectrumDemand(active, for: screenID)
    }
}

extension DedicatedWebWallpaperHostPlaceholderAdapter {
    func setAudioSpectrumDemand(_ active: Bool, for screenID: CGDirectDisplayID) {
        let wasActive = !audioSpectrumDemandScreenIDs.isEmpty
        let didChange: Bool
        if active {
            didChange = audioSpectrumDemandScreenIDs.insert(screenID).inserted
        } else {
            didChange = audioSpectrumDemandScreenIDs.remove(screenID) != nil
        }
        guard didChange else { return }

        let isActive = !audioSpectrumDemandScreenIDs.isEmpty
#if DEBUG
        recordDiagnostic(
            type: "web.audio-demand",
            severity: .info,
            message: "active=\(isActive) surfaces=\(audioSpectrumDemandScreenIDs.count)",
            screenID: screenID,
            url: surfaces[screenID]?.webView.url?.absoluteString
        )
#endif
        if wasActive != isActive, let requestID = currentRequest?.id {
            eventHandler?(.audioSpectrumDemandChanged(isActive, requestID: requestID))
        }
    }

    func clearAudioSpectrumDemand() {
        guard !audioSpectrumDemandScreenIDs.isEmpty else { return }
        audioSpectrumDemandScreenIDs.removeAll()
#if DEBUG
        recordDiagnostic(
            type: "web.audio-demand",
            severity: .info,
            message: "active=false surfaces=0",
            screenID: nil,
            url: nil
        )
#endif
        if let requestID = currentRequest?.id {
            eventHandler?(.audioSpectrumDemandChanged(false, requestID: requestID))
        }
    }
}
