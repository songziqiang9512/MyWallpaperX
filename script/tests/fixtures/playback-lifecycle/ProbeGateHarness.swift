import AppKit
import Foundation
import WebKit

@main enum Harness {
    @MainActor static func main() {
        let rect = PlaybackSurfaceVisibility.Rect(CGRect(x: -1920, y: -900, width: 1920, height: 1080))
        func evidence(pid: Int32? = 42, alpha: Double? = 1, level: Int? = 7,
                      onscreen: Bool? = true, activeSpace: Bool = true,
                      serverRect: PlaybackSurfaceVisibility.Rect? = nil) -> PlaybackSurfaceVisibility.Evidence {
            .init(displayID: 4, windowID: 21, expectedPID: 42, expectedLevel: 7, displayExists: true,
                localFrame: rect, screenFrame: rect, displayFrame: rect, localLevel: 7, localAlpha: 1,
                visible: true, miniaturized: false, onActiveSpace: activeSpace, serverPID: pid,
                serverFrame: serverRect ?? rect, serverLevel: level, serverAlpha: alpha, onscreen: onscreen)
        }
        precondition(PlaybackSurfaceVisibility.evaluate(evidence()) == .confirmed)
        precondition(PlaybackSurfaceVisibility.evaluate(evidence(pid: 43)) == .retry("window-identity-unavailable"))
        precondition(PlaybackSurfaceVisibility.evaluate(evidence(alpha: 0.1)) == .retry("window-alpha-insufficient"))
        precondition(PlaybackSurfaceVisibility.evaluate(evidence(level: 8)) == .retry("window-level-mismatch"))
        precondition(PlaybackSurfaceVisibility.evaluate(evidence(onscreen: false)) == .retry("window-not-onscreen"))
        precondition(PlaybackSurfaceVisibility.evaluate(evidence(onscreen: false, activeSpace: false)) == .deferredOffSpace)
        precondition(PlaybackSurfaceVisibility.evaluate(evidence(serverRect: .init(CGRect(x: 0, y: 0, width: 1920, height: 1080)))) == .retry("window-target-geometry-mismatch"))
        precondition(try! JSONDecoder().decode(PlaybackSurfaceVisibility.Evidence.self,
            from: JSONEncoder().encode(evidence())) == evidence())
        var calls: [Bool] = []
        var callbacks: [() -> Void] = []
        var results: [String] = []
        let gate = WebMediaPlaybackGate { value, completion in calls.append(value); callbacks.append(completion) }
        gate.setSuspended(false) { results.append("A:\($0)") }
        gate.setSuspended(true) { results.append("B:\($0)") }
        precondition(calls == [false] && results == ["A:false"])
        callbacks.removeFirst()()
        precondition(calls == [false, true] && results == ["A:false"])
        gate.setSuspended(false) { results.append("C:\($0)") }
        callbacks.removeFirst()()
        precondition(calls == [false, true, false] && results == ["A:false", "B:false"])
        gate.resetForNavigation()
        precondition(results.last == "C:false" && calls.count == 3)
        gate.setSuspended(false) { results.append("D:\($0)") }
        callbacks.removeFirst()()
        precondition(calls.count == 4 && results.last == "C:false")
        callbacks.removeFirst()()
        precondition(results.last == "D:true")
        gate.setSuspended(true) { results.append("E:\($0)") }
        gate.invalidate()
        callbacks.removeFirst()()
        precondition(results.last == "E:false" && calls.count == 5)
        print("pure-probe-and-media-gate-pass")

        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        let view = WKWebView(frame: NSRect(x: 0, y: 0, width: 2, height: 2))
        var nativeCalls: [Bool] = []
        let nativeGate = WebMediaPlaybackGate { suspended, completion in
            nativeCalls.append(suspended)
            view.setAllMediaPlaybackSuspended(suspended, completionHandler: completion)
        }
        var nativeDone = false
        nativeGate.setSuspended(true) { accepted in
            precondition(accepted)
            nativeGate.setSuspended(false) { accepted in precondition(accepted); nativeDone = true }
        }
        let deadline = Date().addingTimeInterval(8)
        while !nativeDone && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.01)) }
        precondition(nativeDone && nativeCalls == [true, false], "native media completion did not settle")
        nativeGate.invalidate()
        print("native-webkit-media-completion-pass")
    }
}
