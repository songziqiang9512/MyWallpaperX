//
//  DedicatedWebWallpaperHostPlaceholderAdapter+FrameReply.swift
//  MyWallpaperX
//
//  跨源子 frame 回包定向投递（D5）：endpoint 租约、定向 evaluateJavaScript
//  推送面与网络桥接回包。自 RuntimeBridge.swift 拆出，逻辑未变。
//

import Foundation
import AppKit
import WebKit
import CoreGraphics
import Darwin

extension DedicatedWebWallpaperHostPlaceholderAdapter {
    /// 当前全量兼容状态脚本（D5：applyCompatibilityState 与 hello ack 快照
    /// 重放共用同一构造，杜绝两份计数/状态来源）。
    func compatibilityStateScript(for webView: WKWebView) -> String {
        let propertiesJSON = currentRequest?.propertiesJSON ?? "{}"
        let screenID = screenID(for: webView)
        let screen = screenID.flatMap { targetID in
            NSScreen.screens.first { Self.screenID(for: $0) == targetID }
        }
        let generalPropertiesJSON = currentGeneralPropertiesJSON(for: screen, screenID: screenID)
        let escapedProperties = WebWallpaperHostSupport.javaScriptQuotedString(propertiesJSON)
        let escapedGeneralProperties = WebWallpaperHostSupport.javaScriptQuotedString(generalPropertiesJSON)
        let volumeLiteral = String(format: "%.6f", currentVolume)
        let playbackRateLiteral = String(format: "%.6f", currentPlaybackRate)
        let pausedLiteral = paused ? "true" : "false"
        let spectrumLiteral: String
        if let levels = currentSpectrumLevels {
            let joinedLevels = levels.map { String(format: "%.6f", $0) }.joined(separator: ",")
            spectrumLiteral = "[\(joinedLevels)]"
        } else {
            spectrumLiteral = "null"
        }
        return """
        (() => {
          const properties = JSON.parse(\(escapedProperties));
          const generalProperties = JSON.parse(\(escapedGeneralProperties));
          window.__myWallpaperNotifyPluginLoaded('led');
          window.__myWallpaperNotifyPluginLoaded('rgb');
          if (typeof window.__myWallpaperApplyProperties === 'function') {
            window.__myWallpaperApplyProperties(properties);
          } else if (typeof window.__myWallpaperNormalizePropertyBag === 'function') {
            window.__myWallpaperLastUserProperties = window.__myWallpaperNormalizePropertyBag(properties);
          } else {
            window.__myWallpaperLastUserProperties = properties;
          }
          window.__myWallpaperApplyGeneralProperties(generalProperties);
          window.__myWallpaperSetGlobalVolume(\(volumeLiteral));
          window.__myWallpaperSetPlaybackRate(\(playbackRateLiteral));
          if (typeof window.__myWallpaperApplyInitialPausedState === 'function') {
            window.__myWallpaperApplyInitialPausedState(\(pausedLiteral));
          } else {
            window.__myWallpaperSetPaused(\(pausedLiteral));
          }
          const spectrum = \(spectrumLiteral);
          if (Array.isArray(spectrum)) {
            window.__myWallpaperPushAudioSpectrum(spectrum);
          }
        })();
        """
    }

    /// D5：hello ack 后向该 endpoint 重放全量快照（先快照后增量），带单调
    /// 序号供接收端丢弃乱序。
    func applyCompatibilitySnapshot(
        to endpoint: WebWallpaperFrameEndpointRegistry.Endpoint,
        webView: WKWebView
    ) {
        let sequence = endpoint.advancePushSequence()
        webView.evaluateJavaScript(
            sequencedPushScript(compatibilityStateScript(for: webView), sequence: sequence),
            in: endpoint.frameInfo,
            in: .page
        ) { _ in }
    }

    /// D5 唯一推送投递面：逐已注册 endpoint 定向 evaluateJavaScript（.page
    /// world，与注入面同 world）。请求回包不经此路（只回发送 frame）；单个
    /// endpoint 失败只丢弃该次投递，撤销权在租约 challenge（避免脚本瞬时
    /// 异常误杀 endpoint）。
    func deliverStatePush(
        to webView: WKWebView,
        scriptFor: (WebWallpaperFrameEndpointRegistry.Endpoint) -> String
    ) {
        let now = ProcessInfo.processInfo.systemUptime
        for endpoint in frameEndpointRegistry.endpoints(in: webView) {
            guard endpoint.isLeaseValid(now: now) else {
                frameEndpointRegistry.revoke(token: endpoint.token, in: webView)
                continue
            }
            webView.evaluateJavaScript(
                scriptFor(endpoint),
                in: endpoint.frameInfo,
                in: .page
            ) { _ in }
        }
    }

    /// 接收端单调序号包装：乱序/重复推送在 frame 内直接丢弃（属性/暂停保持
    /// 序号有序）。
    func sequencedPushScript(_ body: String, sequence: Int64) -> String {
        """
        (() => {
          const sequence = \(sequence);
          if (typeof window.__mwxHostPushSequence === 'number' && sequence <= window.__mwxHostPushSequence) return;
          window.__mwxHostPushSequence = sequence;
          \(body)
        })();
        """
    }

    /// 频谱推送：每 endpoint 同时至多一个在途定向调用，期间只保留最新一份，
    /// 慢 frame 不形成无界积压（D5）。
    func pushAudioSpectrum(_ levels: [Float], to webView: WKWebView) {
        let now = ProcessInfo.processInfo.systemUptime
        for endpoint in frameEndpointRegistry.endpoints(in: webView) {
            guard endpoint.isLeaseValid(now: now) else {
                frameEndpointRegistry.revoke(token: endpoint.token, in: webView)
                continue
            }
            deliverAudioSpectrum(levels, to: endpoint, webView: webView)
        }
    }

    private func deliverAudioSpectrum(
        _ levels: [Float],
        to endpoint: WebWallpaperFrameEndpointRegistry.Endpoint,
        webView: WKWebView
    ) {
        guard endpoint.isSpectrumDeliveryInFlight == false else {
            endpoint.pendingSpectrumLevels = levels
            return
        }
        endpoint.beginSpectrumDelivery()
        let levelLiterals = levels.map { String(format: "%.6f", $0) }.joined(separator: ",")
        let script = sequencedPushScript(
            "window.__myWallpaperPushAudioSpectrum([\(levelLiterals)]);",
            sequence: endpoint.advancePushSequence()
        )
        webView.evaluateJavaScript(script, in: endpoint.frameInfo, in: .page) { _ in
            Task { @MainActor in
                endpoint.endSpectrumDelivery()
                if let pending = endpoint.pendingSpectrumLevels {
                    endpoint.pendingSpectrumLevels = nil
                    self.deliverAudioSpectrum(pending, to: endpoint, webView: webView)
                }
            }
        }
    }

    /// 租约续约心跳（宿主调度，暂停期间照常）：向每个 endpoint 发 token
    /// challenge，receiver 校验本地 token 后才续租；失效 frame（子导航/进程
    /// 退出）的 challenge 报错即撤销。无 endpoint 时停止心跳。
    func ensureFrameEndpointLeaseRenewalTimer() {
        guard frameEndpointLeaseRenewalTimer == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(
            deadline: .now() + WebWallpaperFrameEndpointRegistry.leaseRenewalInterval,
            repeating: WebWallpaperFrameEndpointRegistry.leaseRenewalInterval
        )
        timer.setEventHandler { [weak self] in
            self?.renewFrameEndpointLeases()
        }
        timer.resume()
        frameEndpointLeaseRenewalTimer = timer
    }

    func stopFrameEndpointLeaseRenewalTimer() {
        frameEndpointLeaseRenewalTimer?.cancel()
        frameEndpointLeaseRenewalTimer = nil
    }

    private func renewFrameEndpointLeases() {
        guard frameEndpointRegistry.hasAnyEndpoints else {
            stopFrameEndpointLeaseRenewalTimer()
            return
        }
        forEachWebView { webView in
            let now = ProcessInfo.processInfo.systemUptime
            for endpoint in self.frameEndpointRegistry.endpoints(in: webView) {
                guard endpoint.isLeaseValid(now: now) else {
                    self.frameEndpointRegistry.revoke(token: endpoint.token, in: webView)
                    continue
                }
                let tokenLiteral = WebWallpaperHostSupport.javaScriptQuotedString(endpoint.token)
                // 校验收口在 JS 侧唯一 helper（BootstrapFoundation）：token 不匹配
                // 直接抛错，宿主据失败撤销该 endpoint；helper 缺失同样抛错，仍按
                // 失败撤销，不放宽。
                webView.evaluateJavaScript(
                    "window.__myWallpaperHostFrameEndpointChallenge(\(tokenLiteral));",
                    in: endpoint.frameInfo,
                    in: .page
                ) { result in
                    Task { @MainActor in
                        switch result {
                        case .success:
                            self.frameEndpointRegistry.renewLease(token: endpoint.token, in: webView)
                        case .failure:
                            self.frameEndpointRegistry.revoke(token: endpoint.token, in: webView)
                        }
                    }
                }
            }
        }
    }

    /// 网络桥接回包：只回发送请求的那个 frame（D5）。`frameInfo` 是请求消息
    /// 捕获的发送时 frame 身份，body 自称的任何 frame ID 都不参与路由；frame
    /// 已失效（子导航/进程退出/surface 拆除）时回包就地取消，不改发主 frame，
    /// 迟到回包不得到达替代文档。
    func resolveNetworkRequest(
        requestID: String,
        payload: [String: Any],
        webView: WKWebView,
        frameInfo: WKFrameInfo
    ) {
        guard requestID.isEmpty == false else { return }
        var responsePayload = payload
        responsePayload["requestID"] = requestID
        guard JSONSerialization.isValidJSONObject(responsePayload),
              let data = try? JSONSerialization.data(withJSONObject: responsePayload),
              let json = String(data: data, encoding: .utf8) else {
            return
        }
        webView.evaluateJavaScript(
            "window.__myWallpaperResolveNetworkRequest(\(json));",
            in: frameInfo,
            in: .page
        ) { [weak self] result in
            guard let self, case let .failure(error) = result else { return }
            self.recordDiagnostic(
                type: "frame.reply.invalid",
                severity: .info,
                message: "network reply dropped: \(error.localizedDescription)",
                screenID: self.screenID(for: webView),
                url: webView.url?.absoluteString
            )
        }
    }
}
