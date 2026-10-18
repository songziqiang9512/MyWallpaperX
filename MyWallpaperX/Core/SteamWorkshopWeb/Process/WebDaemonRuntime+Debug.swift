#if DEBUG
import Foundation
import WebKit

@MainActor
extension WebDaemonRuntime {
    func measureDebugContinuity() {
        guard !debugContinuityInFlight, let webView = host.surfaces.values.first?.webView else { return }
        debugContinuityInFlight = true
        let script = """
        (() => {
        window.__mwxProcessProbe = {frames:0, maxGapMs:0, previous:performance.now(), active:true,
            pageSpectrumFrames:0, changedSpectrumFrames:0, spectrumDelta:0};
        const probe = window.__mwxProcessProbe;
        let previousSpectrum;
        probe.audioListener = event => {
            const levels = event.detail;
            probe.pageSpectrumFrames++;
            if (previousSpectrum && levels.length === previousSpectrum.length) {
                const delta = levels.reduce((sum,x,i)=>sum+Math.abs(x-previousSpectrum[i]),0)/levels.length;
                probe.spectrumDelta = Math.max(probe.spectrumDelta, delta);
                if (delta > 0.00001) probe.changedSpectrumFrames++;
            }
            previousSpectrum = levels.slice();
        };
        window.addEventListener('wallpaper-audio-spectrum', probe.audioListener);
        (function tick(now) {
            const s = probe;
            if (!s.active) return;
            s.frames++; s.maxGapMs = Math.max(s.maxGapMs, now-s.previous); s.previous=now;
            requestAnimationFrame(tick);
        })(performance.now()); return true;
        })();
        """
        webView.evaluateJavaScript(script) { [weak self, weak webView] _, error in
            guard let self else { return }
            guard let webView, error == nil else { self.debugContinuityInFlight = false; return }
            let startPauseTransitions = self.debugPauseTransitions
            let initiallyPaused = self.host.paused
            let startSpectrum = self.debugSpectrumFrames
            let startNonSilent = self.debugNonSilentSpectrumFrames
            var previous = ProcessInfo.processInfo.systemUptime
            var maximumGap: Double = 0
            let timer = Timer(timeInterval: 0.01, repeats: true) { _ in
                let now = ProcessInfo.processInfo.systemUptime
                maximumGap = max(maximumGap, (now - previous) * 1_000)
                previous = now
            }
            RunLoop.main.add(timer, forMode: .common)
            self.emit(.debugContinuityStarted)
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                timer.invalidate()
                webView.evaluateJavaScript("window.__mwxProcessProbe.active=false; window.removeEventListener('wallpaper-audio-spectrum', window.__mwxProcessProbe.audioListener); JSON.stringify(window.__mwxProcessProbe)") { value, _ in
                    defer { self.debugContinuityInFlight = false }
                    guard let json = value as? String, let data = json.data(using: .utf8),
                          let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                        self.emit(.debugContinuity([:])); return
                    }
                    var result = raw.filter { $0.key != "active" }.compactMapValues { ($0 as? NSNumber)?.doubleValue }
                    result["pauseTransitions"] = Double(self.debugPauseTransitions - startPauseTransitions)
                    result["initiallyPaused"] = initiallyPaused ? 1 : 0
                    result["finallyPaused"] = self.host.paused ? 1 : 0
                    result["nativeMaxGapMs"] = maximumGap
                    result["spectrumFrames"] = Double(self.debugSpectrumFrames - startSpectrum)
                    result["nonSilentSpectrumFrames"] = Double(self.debugNonSilentSpectrumFrames - startNonSilent)
                    let endpoints = self.host.frameEndpointRegistry.endpoints(in: webView)
                    result["frameEndpoints"] = Double(endpoints.count)
                    result["spectrumInFlight"] = Double(endpoints.filter(\.isSpectrumDeliveryInFlight).count)
                    self.emit(.debugContinuity(result))
                }
            }
        }
    }

    func exerciseDebugFailure() {
        guard let request = host.currentRequest,
              let surface = host.surfaces.values.first,
              let navigation = host.navigationOwnershipByScreen[surface.screenID]?.navigation else { return }
        let oldWebView = surface.webView
        let state = WallpaperEngine.WebWallpaperRuntimeState(paused: host.paused,
            volume: host.currentVolume, playbackRate: host.currentPlaybackRate,
            spectrumLevels: host.currentSpectrumLevels)
        host.teardownHostSurfaces()
        host.launch(request, runtimeState: state)
        waitForDebugReplacement(oldWebView: oldWebView, navigation: navigation, attempt: 0)
    }

    private func waitForDebugReplacement(oldWebView: WKWebView, navigation: WKNavigation, attempt: Int) {
        guard host.phase == .ready,
              let current = host.surfaces.values.first,
              current.webView !== oldWebView else {
            guard attempt < 100 else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                self?.waitForDebugReplacement(oldWebView: oldWebView, navigation: navigation, attempt: attempt + 1)
            }
            return
        }
        guard let result = DebugWebNavigationIdentityProbe.run(
            host: host, isCurrentRequest: { self.host.currentRequest?.id == self.requestID },
            requestID: requestID, staleNavigation: navigation, staleWebView: oldWebView,
            baselineSurfaceCount: host.surfaces.count, failureCount: { self.debugFailureCount }) else { return }
        emit(.debugNavigationChecks([
            "staleNavigationIgnored": result.staleSurfaceNavigationIgnored,
            "staleRecoveryNavigationIgnored": result.staleRecoveryNavigationIgnored,
            "currentRecoveryNavigationFinished": result.currentRecoveryNavigationFinished,
            "pageNavigationFinished": result.pageNavigationFinished
        ]))
        host.handleNavigationFailure(NSError(domain: "MWX.DebugFailure", code: 1,
            userInfo: [NSLocalizedDescriptionKey: "debug-terminal-failure"]),
            navigation: result.terminalNavigation, webView: result.terminalWebView)
    }
}
#endif
