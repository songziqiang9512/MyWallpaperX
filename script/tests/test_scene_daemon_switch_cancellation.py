"""Execute the real Scene client cancellation and first-present admission methods."""
from pathlib import Path
import json
import subprocess
import tempfile
import unittest

from script.tests.test_scene_wallpaper_async_launch import function_body


ROOT = Path(__file__).resolve().parents[2]
IPC = ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Runtime/IPC"


def method(source: str, signature: str) -> str:
    return signature.removeprefix("private ") + " " + function_body(source, signature)


SUPPORT = r'''
import Foundation
struct ScenePlaybackLoadRequest { let recordID:String?;var rootURL=URL(fileURLWithPath:"/version") }
final class PlaybackResourceLifetime {}
struct Reachability {}
struct SceneWallpaperLaunchState {
    enum Phase { case cancelled }
    let requestID:UUID;let recordID:String?;let phase:Phase;let message:String
}
struct SceneFramePresentation { let requestID:UUID;let recordID:String?;let uptimeMicros:UInt64 }
extension Notification.Name {
    static let sceneWallpaperLaunchStateDidChange=Notification.Name("state")
    static let sceneWallpaperFirstFrameDidPresent=Notification.Name("frame")
}
struct Backoff { var resets=0;mutating func reset(){resets += 1} }
enum Outcome { case superseded }
enum SceneDaemonProtocol { static let version=1 }
@MainActor final class SceneDaemonClient {
    struct Lifetime {
        let lifetime:PlaybackResourceLifetime
        var rootURL=URL(fileURLWithPath:"/version")
        var recordID:String?
        init(lifetime:PlaybackResourceLifetime,recordID:String?=nil) {self.lifetime=lifetime;self.recordID=recordID}
    }
    struct Facts { let transportGeneration:UInt64;let requestID:UUID;let recordID:String?;let reachability:Reachability }
    var activeIntent:ScenePlaybackLoadRequest?
    var pendingIntent:ScenePlaybackLoadRequest?
    var activeResourceLifetime:Lifetime?
    var pendingResourceLifetime:Lifetime?
    var activeRecordID:String?
    var activeRequestID:UUID?
    var pendingRequestID:UUID?
    var pendingPresentationRequestID:UUID?
    var pendingPresentationReachability:Reachability?
    var activeCallbackPropertyFacts:Facts?
    var requestResourceLifetimes:[UUID:PlaybackResourceLifetime]=[:]
    var pendingPropertyRevisions:[UInt64:String]=[:]
    var endpointReady=false
    var warmSessionPending=false
    var lastPropertyRevision:UInt64=0
    var latestTextureRevisions:[String:UInt64]=[:]
    var restartWorkItem:DispatchWorkItem?
    var sessionGeneration:UInt64=7
    var launchState:SceneWallpaperLaunchState?
    var sent:[[String:Any]]=[]
    var stopped=false
    var retiredLeases:[PlaybackResourceLifetime]=[]
    var restartBackoff=Backoff()
    var resumed:[UUID]=[]
    func send(_ value:[String:Any]) { sent.append(value) }
    func finishPendingTextureUpdates(_ result:Outcome) {}
    func stop() {
        stopped=true;endpointReady=false
        retiredLeases += requestResourceLifetimes.values
        if let pendingResourceLifetime { retiredLeases.append(pendingResourceLifetime.lifetime) }
        requestResourceLifetimes=[:];pendingIntent=nil;pendingResourceLifetime=nil
        pendingRequestID=nil;pendingPresentationRequestID=nil;pendingPresentationReachability=nil
    }
    func fallbackReplayIntent(requestID:UUID)->ScenePlaybackLoadRequest? { nil }
    func ensureSession()->Bool {false}
    func replayPendingIntent() {}
    func resumeDeferredTextureUpdates(recordID:String?,requestID:UUID) { resumed.append(requestID) }
    static func double(_ raw:Any?)->Double? { raw as? Double }
'''

TAIL = r'''
}
@main enum Harness {
    @MainActor static func main() throws {
        let a=UUID(),b=UUID()
        let lifetime=PlaybackResourceLifetime()
        func pending(_ client:SceneDaemonClient) {
            client.pendingIntent = .init(recordID:"B")
            client.pendingRequestID=b
            client.pendingResourceLifetime = .init(lifetime:lifetime)
            client.requestResourceLifetimes[b]=lifetime
        }
        var checks:[String:Bool]=[:]
        let cold=SceneDaemonClient();pending(cold)
        cold.cancelPreparationForRuntimeSwitch()
        checks["coldCancellationRetiresBeforeHello"] = cold.stopped && cold.pendingIntent == nil && cold.pendingRequestID == nil
        checks["coldCancellationPinsLeaseUntilExit"] = cold.retiredLeases.contains { $0 === lifetime }
        cold.handleCandidatePrepared(["requestID":b.uuidString])
        checks["latePreparedCannotReplayColdLaunch"] = cold.sent.isEmpty
        let beforeHello=SceneDaemonClient();pending(beforeHello);beforeHello.pendingRequestID=nil
        beforeHello.cancelPreparationForRuntimeSwitch()
        checks["beforeHelloCancellationPublishesTerminalRecord"] = beforeHello.stopped
            && beforeHello.pendingIntent == nil && beforeHello.launchState?.recordID == "B"

        let client=SceneDaemonClient();client.endpointReady=true
        client.activeIntent = .init(recordID:"A");client.activeRecordID="A";client.activeRequestID=a
        pending(client)
        client.handleCandidatePrepared(["requestID":UUID().uuidString])
        checks["wrongPreparedCannotCommit"] = client.sent.isEmpty
        client.handleCandidatePrepared(["requestID":b.uuidString])
        checks["matchingPreparedRequestsCommit"] = client.sent.last?["cmd"] as? String == "commitCandidate"
        client.pendingPresentationRequestID=b;client.pendingPresentationReachability=Reachability()
        client.cancelPreparationForRuntimeSwitch()
        checks["cancelAfterChildCommitKeepsPreviousTruth"] = !client.stopped && client.activeRequestID == a && client.pendingIntent == nil
        checks["cancelCommandsExactCandidate"] = client.sent.last?["cmd"] as? String == "cancelCandidate" && client.sent.last?["requestID"] as? String == b.uuidString
        checks["cancelledLeaseAwaitsChildDrain"] = client.requestResourceLifetimes[b] === lifetime
        let count=client.sent.count
        client.handleFirstFrame(["requestID":b.uuidString,"recordID":"B","uptimeMs":1.0])
        client.handleCandidatePrepared(["requestID":b.uuidString])
        checks["latePresentationCannotCommitRevokedCandidate"] = client.activeRequestID == a && client.sent.count == count && client.resumed.isEmpty

        pending(client);client.pendingPresentationRequestID=b;client.pendingPresentationReachability=Reachability()
        client.handleFirstFrame(["requestID":b.uuidString,"recordID":"B","uptimeMs":2.0])
        checks["realPresentationCommitsMatchingPending"] = client.activeRequestID == b && client.activeRecordID == "B" && client.pendingIntent == nil && client.pendingRequestID == nil
        checks["realPresentationFinalizesStandby"] = client.sent.last?["cmd"] as? String == "finalizeCandidate" && client.resumed == [b]
        let confirmedCount=client.sent.count
        client.cancelPreparationForRuntimeSwitch()
        checks["newIntentRetainsAlreadyConfirmedScene"] = client.activeRequestID == b && client.sent.count == confirmedCount && !client.stopped
        client.activeResourceLifetime = .init(lifetime:lifetime,recordID:"B")
        client.requestLaunch(.init(recordID:"B"))
        checks["sameVersionRebuildInheritsActiveLease"] = client.pendingResourceLifetime?.lifetime === lifetime
        client.cancelPreparationForRuntimeSwitch()
        var foreign=ScenePlaybackLoadRequest(recordID:"C");foreign.rootURL=URL(fileURLWithPath:"/foreign")
        client.requestLaunch(foreign)
        checks["foreignVersionDoesNotBorrowActiveLease"] = client.pendingResourceLifetime == nil
        print(String(data:try JSONSerialization.data(withJSONObject:checks,options:.sortedKeys),encoding:.utf8)!)
    }
}
'''


class SceneDaemonSwitchCancellationTests(unittest.TestCase):
    def test_pending_revoke_before_hello_after_commit_and_real_presentation(self):
        client = (IPC / "SceneDaemonClient.swift").read_text()
        events = (IPC / "SceneDaemonClient+Events.swift").read_text()
        methods = [
            method(client, "func cancelPreparationForRuntimeSwitch()"),
            method(client, "func requestLaunch(_ request: ScenePlaybackLoadRequest)"),
            method(events, "private func handleCandidatePrepared(_ payload: [String: Any])"),
            method(events, "private func handleFirstFrame(_ payload: [String: Any])"),
        ]
        with tempfile.TemporaryDirectory(prefix="mwx-scene-switch-cancel-") as directory:
            root = Path(directory)
            source = root / "Harness.swift"
            source.write_text(SUPPORT + "\n".join(methods) + TAIL)
            binary = root / "harness"
            compilation = subprocess.run(
                ["xcrun", "swiftc", "-parse-as-library", str(source), "-o", str(binary)],
                capture_output=True, text=True, timeout=60,
            )
            self.assertEqual(compilation.returncode, 0, compilation.stderr)
            result = subprocess.run([str(binary)], capture_output=True, text=True, timeout=10)
            self.assertEqual(result.returncode, 0, result.stderr)
            checks = json.loads(result.stdout)
            for name, passed in checks.items():
                with self.subTest(name=name):
                    self.assertTrue(passed)


if __name__ == "__main__":
    unittest.main()
