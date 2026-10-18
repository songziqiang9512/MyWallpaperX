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
        resourceLifetime: PlaybackResourceLifetime? = nil
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
        // 推合并后的完整属性袋而非原始单键 delta：页面侧
        // __myWallpaperApplyProperties 对镜像做整体替换，推 delta 会把全量镜像
        // 覆盖成单键——此后 listener 晚注册/错误重放只交付不完整属性袋，与
        // WE「每次变更交付完整 userProperties」契约相悖。完整袋签名不变时
        // 页面侧去重自然短路。镜像 nil（理论不可达）不推，避免清空页面镜像。
        guard let mergedPropertiesJSON = currentWebPropertiesJSON else { return }
        dispatchWebRuntimeCommand(.applyProperties(mergedPropertiesJSON))
    }

    func launchWebWallpaper(_ request: WebWallpaperLaunchRequest) {
        cancelPreparationRetainingActivePlayback(preservingPreparedRequestID: request.id)
        beginPlaybackIntent()
        pendingWebRetirementOnVideoReady = false
        // The adapter aggregates demand from the retained active process and
        // its candidate. Preparing another page must not interrupt that tap.
        PlaybackPolicyController.shared.refresh()
        let runtimeState = webWallpaperRuntimeState()
        // E2a-4 保留块必须在 web 请求值写入前快照真值：video 仍在播放时的
        // 多屏拓扑是 currentMultiDisplayEnabled 的当前值，不是本请求的
        // multiDisplayEnabled——失败回滚要还原的是前者的真实拓扑。
        let multiDisplayEnabledAtLaunch = currentMultiDisplayEnabled
        currentMultiDisplayEnabled = request.multiDisplayEnabled
        currentWebRecordID = request.recordID
        currentWebRequestID = request.id
        // E2a-4: prepare-then-commit——video 会话与真值保留到 web `.ready`
        // 才退场（retire）；web 失败时 video 仍在原处，旧可见输出保留。
        // 旧实现在此处先行 terminate 全部 session 并清真值（stop-then-start
        // 无回滚）。保留标志跨 web 抢入存活：上一个未提交的 web 启动持有
        // video 保留时，新请求继承它——video 仍是引擎事实，直到某个 web
        // 请求真正提交（.ready）或失败回滚；旧请求的 .ready/.failed 由
        // requestID 代际守卫静默退役。
        if currentPlaybackContentKind == .video {
            pendingVideoRetirementOnWebReady = true
            retainedVideoWallpaper = currentWallpaper
            retainedVideoContentPath = currentContentPath
            retainedVideoMultiDisplayEnabled = multiDisplayEnabledAtLaunch
        }

        currentWallpaper = nil
        currentContentPath = request.entryURL.resolvingSymlinksInPath().standardizedFileURL.path
        currentPlaybackContentKind = .web
        currentWebPropertiesJSON = request.propertiesJSON ?? "{}"
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
            guard currentPlaybackContentKind == .web, currentWebRequestID == requestID,
                  runtimeCommitAdmission?(.web) != false else { return }
            postWallpaperRuntimeWillSwitch(to: .web, recordID: currentWebRecordID)
            NotificationCenter.default.post(name: Self.webPlaybackReadyNotification,
                object: self, userInfo: ["requestID": requestID])
            lastFailureVideoPath = nil
            lastFailureAt = 0
            // E2a-4: web 已就绪——现在退场被保留的 video runtime（提交点）。
            // currentWallpaper/currentContentPath 不在此清：launch 已无条件
            // 置好 web 侧真值（nil / entry 路径），清掉会让 video→web 提交后
            // isPlaying()（对 web 看 currentContentPath）误报未在播，
            // 与 web→web 提交路径不对称。
            if pendingVideoRetirementOnWebReady {
                pendingVideoRetirementOnWebReady = false
                activeVideoPlayback = nil
                for displayID in Array(displaySessions.keys) {
                    terminateSession(for: displayID)
                }
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
            if (dedicatedWebHostAdapter as? WebDaemonHostAdapter)?.activeRequest == nil {
                setWebAudioSpectrumRequested(false)
            }
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
                // The retained helper may have exited while Web prepared.
                // Use the same exact cancellation/recovery owner as a revoke.
                cancelVideoPreparationRetainingActivePlayback()
            } else if let retained = (dedicatedWebHostAdapter as? WebDaemonHostAdapter)?.activeRequest {
                restoreActiveWebRequest(retained)
            } else {
                currentWallpaper = nil
                currentContentPath = nil
                currentPlaybackContentKind = nil
            }
            if currentPlaybackContentKind != .web {
                currentWebPropertiesJSON = nil
                currentWebRecordID = nil
                currentWebRequestID = nil
            }
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

    func captureWebWallpaperFrame(completion: @escaping (AppKit.NSImage?) -> Void) {
        guard let adapter = dedicatedWebHostAdapter as? WebDaemonHostAdapter else {
            completion(nil); return
        }
        adapter.captureSurfaceFrame(completion: completion)
    }

    private func restoreActiveWebRequest(_ request: WebWallpaperLaunchRequest) {
        currentWallpaper = nil
        currentPlaybackContentKind = .web
        currentWebRequestID = request.id
        currentWebRecordID = request.recordID
        currentWebPropertiesJSON = request.propertiesJSON
        currentContentPath = request.entryURL.resolvingSymlinksInPath().standardizedFileURL.path
        currentMultiDisplayEnabled = request.multiDisplayEnabled
    }

    /// Revoke candidates independently of retiring committed output. Used by
    /// early Web preparation and Scene intents, including validation failures.
    func cancelPreparationRetainingActivePlayback(preservingPreparedRequestID: UUID? = nil) {
        cancelVideoPreparationRetainingActivePlayback()
        guard let adapter = dedicatedWebHostAdapter as? WebDaemonHostAdapter else { return }
        adapter.cancelPreparation(preservingPreparedRequestID: preservingPreparedRequestID)
        if let retained = adapter.activeRequest { restoreActiveWebRequest(retained) }
        else if pendingVideoRetirementOnWebReady {
            currentPlaybackContentKind = .video
            currentWallpaper = retainedVideoWallpaper
            currentContentPath = retainedVideoContentPath
            currentMultiDisplayEnabled = retainedVideoMultiDisplayEnabled ?? currentMultiDisplayEnabled
            currentWebRequestID = nil; currentWebRecordID = nil; currentWebPropertiesJSON = nil
        }
        if adapter.activeRequest == nil && !pendingVideoRetirementOnWebReady {
            currentWebRequestID = nil; currentWebRecordID = nil; currentWebPropertiesJSON = nil
            if currentPlaybackContentKind == .web {
                currentPlaybackContentKind = nil; currentContentPath = nil
            }
            setWebAudioSpectrumRequested(false)
        }
        pendingVideoRetirementOnWebReady = false
        pendingWebRetirementOnVideoReady = false
        retainedVideoWallpaper = nil; retainedVideoContentPath = nil; retainedVideoMultiDisplayEnabled = nil
    }

    @discardableResult
    func rollbackVideoPreparationToWeb() -> Bool {
        guard pendingWebRetirementOnVideoReady else { return false }
        beginPlaybackIntent()
        cancelPreparationRetainingActivePlayback()
        return currentPlaybackContentKind == .web
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
