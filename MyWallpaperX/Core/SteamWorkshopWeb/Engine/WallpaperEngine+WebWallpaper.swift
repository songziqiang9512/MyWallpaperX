//
//  WallpaperEngine+WebWallpaper.swift
//  MyWallpaperX
//

import AppKit
import Foundation
import QuartzCore

extension WallpaperEngine {
    func setWebWallpaper(
        requestID: UUID = UUID(),
        entryURL: URL,
        rootURL: URL,
        propertiesJSON: String?,
        recordID: String? = nil,
        language: String,
        runtimeProfile: WebRuntimeProfile = .standard,
        multiDisplayEnabled: Bool,
        resourceLifetime: PlaybackResourceLifetime? = nil,
        resourceGrants: [WebWallpaperResourceGrant] = []
    ) {
        launchWebWallpaper(
            WebWallpaperLaunchRequest(
                id: requestID,
                entryURL: entryURL,
                rootURL: rootURL,
                propertiesJSON: propertiesJSON ?? "{}",
                source: .steamWorkshop,
                recordID: recordID,
                language: language,
                runtimeProfile: runtimeProfile,
                multiDisplayEnabled: multiDisplayEnabled,
                resourceLifetime: resourceLifetime,
                resourceGrants: resourceGrants
            )
        )
    }

    func updateWebDisplayConfiguration(multiDisplayEnabled: Bool) {
        guard (dedicatedWebHostAdapter as? WebDaemonHostAdapter)?.hasLivePlayback == true else { return }
        if currentPlaybackContentKind == .web { currentMultiDisplayEnabled = multiDisplayEnabled }
        dedicatedWebHostAdapter.updateDisplayConfiguration(multiDisplayEnabled: multiDisplayEnabled)
    }

    var currentWebResourceRootURL: URL? {
        guard let requestID = currentWebRequestID else { return nil }
        return (dedicatedWebHostAdapter as? WebDaemonHostAdapter)?.propertyUpdateSession(for: requestID)?.request.rootURL
    }

    var currentWebResourceGrants: [WebWallpaperResourceGrant] {
        guard let requestID = currentWebRequestID else { return [] }
        return (dedicatedWebHostAdapter as? WebDaemonHostAdapter)?.propertyUpdateSession(for: requestID)?.resourceGrants ?? []
    }

    func updateCurrentWebWallpaperProperties(_ propertiesJSON: String?, resourceGrants: [WebWallpaperResourceGrant],
                                             resourcesChanged: Bool = false) {
        guard currentPlaybackContentKind == .web,
              let requestID = currentWebRequestID,
              let request = (dedicatedWebHostAdapter as? WebDaemonHostAdapter)?
                .propertyUpdateSession(for: requestID)?.executionRequest else { return }
        currentWebPropertiesJSON = mergedWebPropertiesJSON(
            baseJSON: currentWebPropertiesJSON,
            deltaJSON: propertiesJSON
        )
        // 推合并后的完整属性袋而非原始单键 delta：页面侧
        // __myWallpaperApplyProperties 对镜像做整体替换，推 delta 会把全量镜像
        // 覆盖成单键——此后 listener 晚注册/错误重放只交付不完整属性袋，与
        // WE「每次变更交付完整 userProperties」契约相悖。完整袋签名不变时
        // 页面侧去重自然短路。镜像 nil（理论不可达）不推，避免清空页面镜像。
        guard let mergedPropertiesJSON = currentWebPropertiesJSON else { return }
        dispatchWebRuntimeCommand(.applyProperties(.init(requestID: request.id,
            revision: request.propertyRevision &+ 1,
            resourceRevision: request.resourceRevision &+ ((resourcesChanged || resourceGrants != request.resourceGrants) ? 1 : 0),
            propertiesJSON: mergedPropertiesJSON,
            resourceGrants: resourceGrants)))
    }

    func launchWebWallpaper(_ request: WebWallpaperLaunchRequest) {
        beginPlaybackIntent()
        prepareWebSwitch(ticket: .init(epoch: playbackIntentEpoch, id: UUID(), runtime: .web),
            requestID: request.id, entryURL: request.entryURL, rootURL: request.rootURL,
            propertiesJSON: request.propertiesJSON, recordID: request.recordID,
            language: request.language, runtimeProfile: request.runtimeProfile,
            multiDisplayEnabled: request.multiDisplayEnabled, resourceLifetime: request.resourceLifetime,
            resourceGrants: request.resourceGrants)
    }

    func prepareWebSwitch(ticket: PlaybackSwitchTicket, requestID: UUID,
                          entryURL: URL, rootURL: URL, propertiesJSON: String?,
                          recordID: String?, language: String, runtimeProfile: WebRuntimeProfile,
                          multiDisplayEnabled: Bool, resourceLifetime: PlaybackResourceLifetime?,
                          resourceGrants: [WebWallpaperResourceGrant] = []) {
        guard ticket.runtime == .web, let adapter = dedicatedWebHostAdapter as? WebDaemonHostAdapter else {
            switchFailed?(ticket, "Web execution endpoint is unavailable"); return
        }
        adoptIntentEpoch(ticket.epoch)
        let request = WebWallpaperLaunchRequest(id: requestID, entryURL: entryURL,
            rootURL: rootURL, propertiesJSON: propertiesJSON ?? "{}", source: .steamWorkshop,
            recordID: recordID, language: language, runtimeProfile: runtimeProfile,
            multiDisplayEnabled: multiDisplayEnabled, resourceLifetime: resourceLifetime,
            resourceGrants: resourceGrants)
        adapter.prepareSwitch(ticket: ticket, request: request, runtimeState: webWallpaperRuntimeState())
    }

    func configureWebSwitchCallbacks() {
        guard let adapter = dedicatedWebHostAdapter as? WebDaemonHostAdapter else { return }
        adapter.switchPrepared = { [weak self] ticket, endpoint in
            guard let self else { endpoint.cancel({}); return }
            if let switchPrepared = self.switchPrepared { switchPrepared(ticket, endpoint) }
            else { endpoint.activate() }
        }
        adapter.switchVisible = { [weak self, weak adapter] ticket, executionID in
            guard let self else { return }
            if let switchVisible = self.switchVisible { switchVisible(ticket, executionID) }
            else if let session = adapter?.candidate,
                    session.executionID == executionID, let identity = session.activationIdentity {
                adapter?.finalizeSession(session, identity: identity)
                // Standalone debug has no product transaction to retire its old endpoint.
                if let adapter { for previous in Array(adapter.standby.values) { adapter.retireEndpoint(previous, completion: {}) } }
            }
        }
        adapter.switchFailed = { [weak self] ticket, message in self?.switchFailed?(ticket, message) }
        adapter.switchLost = { [weak self] ticket, message in self?.switchLost?(ticket, message) }
    }

    private func webWallpaperRuntimeState() -> WebWallpaperRuntimeState {
        .init(paused: playbackPaused, volume: effectiveVolumeNormalized,
              playbackRate: targetPlaybackRate, spectrumLevels: currentWebSpectrumSnapshot())
    }

    func handleWebHostEvent(_ event: WebWallpaperHostEvent) {
        switch event {
        case .accepted: break
        case let .ready(requestID):
            guard let request = (dedicatedWebHostAdapter as? WebDaemonHostAdapter)?.activeRequest,
                  request.id == requestID else { return }
            // This is an engine fact emitted only after Manager.finalize.
            currentWallpaper = nil
            currentContentPath = request.entryURL.resolvingSymlinksInPath().standardizedFileURL.path
            currentPlaybackContentKind = .web
            currentWebRequestID = requestID; currentWebRecordID = request.recordID
            currentWebPropertiesJSON = request.propertiesJSON
            currentMultiDisplayEnabled = request.multiDisplayEnabled
            lastFailureVideoPath = nil; lastFailureAt = 0
            // Demand may arrive during preparation, before this committed ID
            // exists. Refresh after adoption even if the demand bit is unchanged.
            refreshSystemAudioSpectrumCapture()
            NotificationCenter.default.post(name: Self.webPlaybackReadyNotification,
                object: self, userInfo: ["requestID": requestID])
        case let .audioSpectrumDemandChanged(active, _): setWebAudioSpectrumRequested(active)
        case let .failed(message, requestID):
            NotificationCenter.default.post(name: Self.playbackFailedNotification, object: self,
                userInfo: ["requestID": requestID.uuidString, "message": message, "contentKind": "web"])
        case let .stopped(requestID):
            if currentWebRequestID == requestID {
                currentWebRequestID = nil
                currentWebRecordID = nil
                currentWebPropertiesJSON = nil
                if currentPlaybackContentKind == .web {
                    currentPlaybackContentKind = nil
                    currentContentPath = nil
                    currentWallpaper = nil
                }
            }
            // Retiring A must not tear down the shared capture already serving
            // visible B. Live endpoint demand is independent of UI adoption.
            setWebAudioSpectrumRequested((dedicatedWebHostAdapter as? WebDaemonHostAdapter)?.audioSpectrumRequested == true)
            refreshSystemAudioSpectrumCapture()
        }
    }

    func captureWebWallpaperFrame(completion: @escaping (AppKit.NSImage?) -> Void) {
        guard let adapter = dedicatedWebHostAdapter as? WebDaemonHostAdapter else { completion(nil); return }
        adapter.captureSurfaceFrame(completion: completion)
    }

    /// Revoke execution candidates without changing committed engine facts.
    /// Manager cancellation barriers remain the only activation authority.
    func cancelPreparationRetainingActivePlayback(preservingPreparedRequestID: UUID? = nil) {
        cancelVideoPreparationRetainingActivePlayback()
        (dedicatedWebHostAdapter as? WebDaemonHostAdapter)?
            .cancelPreparation(preservingPreparedRequestID: preservingPreparedRequestID)
    }

    private func mergedWebPropertiesJSON(baseJSON: String?, deltaJSON: String?) -> String {
        guard let deltaJSON,
              let deltaRoot = jsonObjectDictionary(from: deltaJSON) else {
            return baseJSON ?? "{}"
        }

        var merged = jsonObjectDictionary(from: baseJSON) ?? [:]
        for (key, value) in deltaRoot {
            merged[key] = value
        }

        guard JSONSerialization.isValidJSONObject(merged),
              let data = try? JSONSerialization.data(withJSONObject: merged),
              let json = String(data: data, encoding: .utf8) else {
            return baseJSON ?? deltaJSON
        }
        return json
    }

    private func jsonObjectDictionary(from json: String?) -> [String: Any]? {
        guard let json,
              let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return object
    }
}
