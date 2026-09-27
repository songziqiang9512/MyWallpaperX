"""Run the production pause script in real WKWebView documents and child frames."""
from pathlib import Path
import subprocess
import base64
import io
import wave
import tempfile
import unittest
from script.tests.test_steam_library_interactions import method

ROOT = Path(__file__).resolve().parents[2]
HARNESS = r'''
import AppKit
import WebKit

enum WallpaperEngine { struct WebWallpaperLaunchRequest { var propertiesJSON: String? } }
enum WebWallpaperHostSupport {
    static func javaScriptQuotedString(_ value: String) -> String {
        String(data: try! JSONEncoder().encode(value), encoding: .utf8)!
    }
}
final class Adapter {
    func applyGeneralProperties(to webView: WKWebView) {}
    // ADAPTER_METHODS
}
@main enum Harness {
    @MainActor static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        config.mediaTypesRequiringUserActionForPlayback = []
        config.userContentController.addUserScript(WKUserScript(
            source: webWallpaperPlaybackScript.replacingOccurrences(of: "__MWX_INITIAL_PAUSED__", with: "true"),
            injectionTime: .atDocumentStart, forMainFrameOnly: false))
        config.userContentController.addUserScript(WKUserScript(
            source: Adapter.webCompatibilityScript(for: nil, generalPropertiesJSON: "{}",
                volume: 0, playbackRate: 1, paused: true),
            injectionTime: .atDocumentStart, forMainFrameOnly: true))
        let adapter = Adapter()
        let view = WKWebView(frame: NSRect(x: 0, y: 0, width: 320, height: 200), configuration: config)
        view.setAllMediaPlaybackSuspended(true, completionHandler: nil)
        let window = NSWindow(contentRect: view.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = view
        window.orderFrontRegardless()
        let page = #"""
        <style>@keyframes move {to {transform:translateX(100px)}}
        #animated {animation:move 2s linear infinite; width:10px; height:10px; background:red}</style>
        <div id=animated></div><div id=wa></div>
        <audio id=media muted autoplay loop src="data:audio/wav;base64,__MEDIA__"></audio>
        <script>
        window.framesSeen=0; window.ticks=0; window.timeouts=0; window.cancelled=0; window.correctThis=0;
        const frame=()=>{framesSeen++;requestAnimationFrame(frame)};requestAnimationFrame(frame);
        setInterval(()=>ticks++,20);setTimeout(()=>timeouts++,250);
        const cancelledID=setTimeout(()=>cancelled++,50);clearInterval(String(cancelledID));
        setTimeout(function(value){if(this===window && value===7) correctThis++}, 0, 7);
        requestAnimationFrame(function(){if(this===window) correctThis++});
        window.wa= document.getElementById('wa').animate([{opacity:0},{opacity:1}],{duration:2000,iterations:Infinity});
        window.authorPaused=document.body.animate([{opacity:1},{opacity:1}],{duration:2000,iterations:Infinity});
        authorPaused.pause();
        </script>
        """#
        let escaped = page.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "\"", with: "&quot;")
        view.loadHTMLString(page + "<iframe srcdoc=\"" + escaped + "\"></iframe>", baseURL: nil)
        Task { @MainActor in
            do {
                func wait(_ seconds: Double) async throws { try await Task.sleep(for: .seconds(seconds)) }
                func js(_ script: String) async throws -> Any { try await view.evaluateJavaScript(script) as Any }
                func counters() async throws -> [Double] {
                    let result = try await js("[framesSeen,ticks,timeouts,cancelled,wa.currentTime,document.getElementById('animated').getAnimations()[0].currentTime,frames[0].framesSeen,frames[0].ticks,document.getElementById('media').currentTime]")
                    return (result as! [NSNumber]).map(\.doubleValue)
                }
                try await wait(1.5)
                let initial = try await counters()
                precondition(initial[0] == 0 && initial[1] == 0 && initial[2] == 0)
                precondition(initial[6] == 0 && initial[7] == 0, "Initially paused iframe ran")
                adapter.applyPausedState(false, to: view)
                try await wait(0.6)
                let running = try await counters()
                precondition(running[0] > 3 && running[1] > 3 && running[2] == 1 && running[3] == 0)
                precondition(running[6] > 3 && running[7] > 3)
                precondition(running[8] > 0.1, "Native WebKit media did not start")
                let callbackSemantics = try await js("correctThis") as? Int
                precondition(callbackSemantics == 2, "Native callback this/arguments semantics changed")
                adapter.applyPausedState(true, to: view)
                try await wait(0.15) // Child postMessage and compositor settle.
                let frozen = try await counters()
                try await wait(0.4)
                let still = try await counters()
                precondition(zip(frozen, still).allSatisfy { abs($0 - $1) < 0.01 }, "Paused RAF/timer/CSS/WA/iframe advanced: \(frozen) -> \(still)")
                // Work scheduled while paused must wait, and cancelled work must stay cancelled.
                _ = try await js("setTimeout(()=>timeouts++,50); wa.play(); document.getElementById('animated').style.animationPlayState='paused'; void document.getElementById('media').play().catch(()=>{});")
                try await wait(0.2)
                let held = try await counters()
                precondition(held[2] == 1)
                precondition(abs(held[8] - still[8]) < 0.01, "Media restarted while native gate was suspended")
                adapter.applyPausedState(false, to: view)
                var resumed = try await counters()
                for _ in 0..<20 where resumed[8] <= held[8] + 0.05 {
                    try await wait(0.1)
                    resumed = try await counters()
                }
                precondition(resumed[0] > still[0] && resumed[1] > still[1] && resumed[2] == 2)
                precondition(resumed[6] > still[6] && resumed[7] > still[7])
                let authoredState = try await js("authorPaused.playState") as? String
                precondition(authoredState == "paused")
                precondition(abs(resumed[5] - still[5]) < 0.01, "Author CSS pause was overridden")
                precondition(resumed[8] > held[8] + 0.05, "Native media failed to resume: held=\(held), resumed=\(resumed)")
                print("webkit-pause-pass: initial pause, RAF, timers, CSS, Web Animations, iframe, resume")
                window.orderOut(nil)
                exit(0)
            } catch { print("webkit-pause-failed: \(error)"); exit(1) }
        }
        app.run()
    }
}
'''


class WebPlaybackPauseTests(unittest.TestCase):
    def test_real_webkit_pause_resume(self):
        with tempfile.TemporaryDirectory(prefix="mwx-webkit-pause-") as directory:
            path = Path(directory)
            host = ROOT / "MyWallpaperX/Core/SteamWorkshopWeb/Host"
            adapter = method((host / "WebWallpaperHostTypes.swift").read_text(), "static func webCompatibilityScript(")
            adapter += "\n" + method((host / "DedicatedWebWallpaperHostPlaceholderAdapter+RuntimeBridge.swift").read_text(), "func applyPausedState(")
            audio = io.BytesIO()
            with wave.open(audio, "wb") as wav:
                wav.setnchannels(1); wav.setsampwidth(1); wav.setframerate(8000)
                wav.writeframes(bytes([128]) * 24000)
            harness = HARNESS.replace("// ADAPTER_METHODS", adapter).replace("__MEDIA__", base64.b64encode(audio.getvalue()).decode())
            (path / "Harness.swift").write_text(harness)
            source = host / "WebWallpaperPlaybackScript.swift"
            result = subprocess.run(["xcrun", "swiftc", "-parse-as-library", str(source),
                *map(str, sorted(host.glob("DedicatedWebWallpaperHostCompatibilityScript+*.swift"))),
                str(path / "Harness.swift"), "-o", str(path / "harness")],
                capture_output=True, text=True, timeout=90)
            self.assertEqual(result.returncode, 0, result.stderr)
            result = subprocess.run([str(path / "harness")], capture_output=True, text=True, timeout=30)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn("webkit-pause-pass", result.stdout)


if __name__ == "__main__":
    unittest.main()
