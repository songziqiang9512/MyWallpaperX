//
//  WallpaperEngine+WebWallpaper.swift
//  MyWallpaperX
//

import Foundation
import QuartzCore

extension WallpaperEngine {
    func setWebWallpaper(
        entryURL: URL,
        rootURL: URL,
        propertiesJSON: String?,
        recordID: String? = nil,
        language: String,
        runtimeProfile: WebRuntimeProfile = .standard,
        multiDisplayEnabled: Bool,
        resourceLifetime: PlaybackResourceLifetime? = nil
    ) {
        postWallpaperRuntimeWillSwitch(to: .web, recordID: recordID)
        currentWebPropertiesJSON = propertiesJSON ?? "{}"
        currentWebRecordID = recordID
        launchWebWallpaper(
            WebWallpaperLaunchRequest(
                entryURL: entryURL,
                rootURL: rootURL,
                propertiesJSON: currentWebPropertiesJSON,
                source: .steamWorkshop,
                recordID: recordID,
                language: language,
                runtimeProfile: runtimeProfile,
                multiDisplayEnabled: multiDisplayEnabled,
                resourceLifetime: resourceLifetime
            )
        )
    }

    func updateWebDisplayConfiguration(multiDisplayEnabled: Bool) {
        guard currentPlaybackContentKind == .web else { return }
        currentMultiDisplayEnabled = multiDisplayEnabled
        dedicatedWebHostAdapter.updateDisplayConfiguration(multiDisplayEnabled: multiDisplayEnabled)
    }

    public func updateCurrentWebWallpaperProperties(_ propertiesJSON: String?) {
        guard currentPlaybackContentKind == .web else { return }
        currentWebPropertiesJSON = mergedWebPropertiesJSON(
            baseJSON: currentWebPropertiesJSON,
            deltaJSON: propertiesJSON
        )
        dispatchWebRuntimeCommand(.applyProperties(propertiesJSON ?? "{}"))
    }

    func launchWebWallpaper(_ request: WebWallpaperLaunchRequest) {
        beginPlaybackIntent()
        if currentPlaybackContentKind == .web {
            setWebAudioSpectrumRequested(false)
        }
        PlaybackPolicyController.shared.refresh()
        let runtimeState = webWallpaperRuntimeState()
        currentMultiDisplayEnabled = request.multiDisplayEnabled
        currentWebRecordID = request.recordID
        currentWebRequestID = request.id
        // E2a-4: prepare-then-commit——video 会话与真值保留到 web `.ready`
        // 才退场（retire）；web 失败时 video 仍在原处，旧可见输出保留。
        // 旧实现在此处先行 terminate 全部 session 并清真值（stop-then-start
        // 无回滚）。
        pendingVideoRetirementOnWebReady = currentPlaybackContentKind == .video
        if pendingVideoRetirementOnWebReady {
            retainedVideoWallpaper = currentWallpaper
            retainedVideoContentPath = currentContentPath
            retainedVideoMultiDisplayEnabled = currentMultiDisplayEnabled
        }

        currentWallpaper = nil
        currentContentPath = request.entryURL.resolvingSymlinksInPath().standardizedFileURL.path
        currentPlaybackContentKind = .web
        currentWebPropertiesJSON = request.propertiesJSON ?? "{}"
        currentWebLaunchSource = request.source
        dedicatedWebHostAdapter.launch(request, runtimeState: runtimeState)
    }

    private func webWallpaperRuntimeState() -> WebWallpaperRuntimeState {
        WebWallpaperRuntimeState(
            paused: playbackPaused,
            volume: effectiveVolumeNormalized,
            playbackRate: targetPlaybackRate,
            spectrumLevels: currentWebSpectrumSnapshot()
        )
    }

    func handleWebHostEvent(_ event: WebWallpaperHostEvent) {
        switch event {
        case let .accepted(requestID):
            guard currentWebRequestID == requestID else { return }
            break
        case let .ready(requestID):
            guard currentWebRequestID == requestID else { return }
            lastFailureVideoPath = nil
            lastFailureAt = 0
            // E2a-4: web 已就绪——现在退场被保留的 video runtime（提交点）。
            if pendingVideoRetirementOnWebReady {
                pendingVideoRetirementOnWebReady = false
                for displayID in Array(displaySessions.keys) {
                    terminateSession(for: displayID)
                }
                currentWallpaper = nil
                currentContentPath = nil
                retainedVideoWallpaper = nil
                retainedVideoContentPath = nil
                retainedVideoMultiDisplayEnabled = nil
            }
            // 启动重放/准备窗口内投影的暂停意图会早于 host 存在——
            // 广播当时被丢弃；就绪后补发一次，避免"恢复为暂停"泄漏成播放。
            if playbackPaused {
                dispatchWebRuntimeCommand(.pause)
            }
        case let .audioSpectrumDemandChanged(active, requestID):
            guard currentWebRequestID == requestID else { return }
            setWebAudioSpectrumRequested(active)
        case let .failed(message, requestID):
            guard currentPlaybackContentKind == .web,
                  currentWebRequestID == requestID else { return }
            let failedRecordID = currentWebRecordID
            let failedPath = currentContentPath
            beginPlaybackIntent()
            setWebAudioSpectrumRequested(false)
            lastFailureVideoPath = failedPath
            lastFailureAt = CACurrentMediaTime()
            // E2a-4: web 准备失败——被保留的 video runtime 原样恢复，
            // 旧可见输出不受影响；video 真值不清。
            if pendingVideoRetirementOnWebReady {
                pendingVideoRetirementOnWebReady = false
                currentPlaybackContentKind = .video
                currentWallpaper = retainedVideoWallpaper
                currentContentPath = retainedVideoContentPath
                if let retainedMultiDisplay = retainedVideoMultiDisplayEnabled {
                    currentMultiDisplayEnabled = retainedMultiDisplay
                }
                retainedVideoWallpaper = nil
                retainedVideoContentPath = nil
                retainedVideoMultiDisplayEnabled = nil
            } else {
                currentWallpaper = nil
                currentContentPath = nil
                currentPlaybackContentKind = nil
            }
            currentWebPropertiesJSON = nil
            currentWebRecordID = nil
            currentWebRequestID = nil
            currentWebLaunchSource = nil
            NotificationCenter.default.post(
                name: Self.playbackFailedNotification,
                object: nil,
                userInfo: [
                    "recordID": failedRecordID as Any,
                    "path": failedPath as Any,
                    "message": message,
                    "contentKind": PlaybackContentKind.web.rawValue,
                    "requestID": requestID.uuidString
                ]
            )
        case let .stopped(requestID):
            guard currentWebRequestID == requestID else { return }
            setWebAudioSpectrumRequested(false)
        }
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
