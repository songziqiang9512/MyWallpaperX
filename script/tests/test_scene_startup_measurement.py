"""Execute the DEBUG product-startup evidence reducer with hostile event order."""
from pathlib import Path
import json
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "MyWallpaperX/App/Debug/DebugSceneStartupMeasurement.swift"


HARNESS = r'''
import Foundation

@main enum Harness {
    static func main() throws {
        let ticket=UUID(),request=UUID(),execution=UUID()
        func selected() -> DebugSceneStartupMeasurement {
            var value=DebugSceneStartupMeasurement(index:0,recordID:"A",rootPath:"/isolated/A",entryUptimeMicros:1000)
            value.bindSelection(ticketID:ticket,intentEpoch:4)
            return value
        }
        func accepted(_ value:inout DebugSceneStartupMeasurement) {
            value.observePhase("accepted",recordID:"A",ticketID:ticket,intentEpoch:4,
                requestID:request,uptimeMicros:1100)
        }
        func endpoint(_ value:inout DebugSceneStartupMeasurement,_ phase:String,_ time:UInt64,
                      generation:UInt64=3,pid:Int32=42) {
            value.observeEndpoint(phase,ticketID:ticket,intentEpoch:4,requestID:request,
                executionID:execution,daemonGeneration:generation,daemonPID:pid,uptimeMicros:time)
        }
        func passed(_ value:DebugSceneStartupMeasurement)->Bool {value.report["passed"] as? Bool == true}
        func contains(_ value:DebugSceneStartupMeasurement,_ reason:String)->Bool {
            (value.report["failures"] as? [String] ?? []).contains(reason)
        }
        var checks:[String:Bool]=[:]
        var earlyFinalize=selected();accepted(&earlyFinalize);endpoint(&earlyFinalize,"prepared",1200)
        endpoint(&earlyFinalize,"parentFinalized",1300)
        earlyFinalize.observePresentation(requestID:request,recordID:"A",
            presentedUptimeMicros:1250,observedUptimeMicros:1400)
        checks["finalizeBeforeNotificationUsesPresentedClock"]=earlyFinalize.isComplete && passed(earlyFinalize)
            && earlyFinalize.report["entryToPresentedMs"] as? Double == 0.25
            && earlyFinalize.report["entryToPresentedObservedMs"] as? Double == 0.4
        var lateFinalize=selected();accepted(&lateFinalize);endpoint(&lateFinalize,"prepared",1200)
        lateFinalize.observePresentation(requestID:request,recordID:"A",
            presentedUptimeMicros:1250,observedUptimeMicros:1300)
        endpoint(&lateFinalize,"parentFinalized",1500)
        checks["asynchronousRetirementCanFinalizeAfterNotification"]=passed(lateFinalize)
        var missing=selected();accepted(&missing);endpoint(&missing,"prepared",1200)
        endpoint(&missing,"parentFinalized",1300)
        checks["readyAndFinalizeDoNotInventPresented"] = !missing.isComplete && !passed(missing)
            && contains(missing,"presented-missing") && missing.report["entryToPresentedMs"] is NSNull
        var stale=selected()
        stale.observePhase("accepted",recordID:"A",ticketID:UUID(),intentEpoch:4,
            requestID:UUID(),uptimeMicros:1100)
        stale.observePhase("accepted",recordID:"foreign",ticketID:ticket,intentEpoch:4,
            requestID:UUID(),uptimeMicros:1100)
        stale.observeEndpoint("prepared",ticketID:ticket,intentEpoch:99,requestID:UUID(),
            executionID:UUID(),daemonGeneration:3,daemonPID:42,uptimeMicros:1200)
        checks["wrongSelectionCannotBindRequest"]=stale.requestID == nil
        accepted(&stale);endpoint(&stale,"prepared",1200)
        stale.observePresentation(requestID:UUID(),recordID:"A",
            presentedUptimeMicros:1250,observedUptimeMicros:1300)
        checks["wrongRequestCannotPresent"]=stale.presentedUptimeMicros == nil
        var duplicate=earlyFinalize
        duplicate.observePresentation(requestID:request,recordID:"A",
            presentedUptimeMicros:1250,observedUptimeMicros:1400)
        checks["duplicatePresentationInvalidatesResult"] = !passed(duplicate)
            && contains(duplicate,"duplicate-presented")
        var backwards=selected();accepted(&backwards);endpoint(&backwards,"prepared",1200)
        backwards.observePresentation(requestID:request,recordID:"A",
            presentedUptimeMicros:1199,observedUptimeMicros:1300)
        endpoint(&backwards,"parentFinalized",1400)
        checks["clockOrderMustBePlausible"] = !passed(backwards)
            && contains(backwards,"event-clock-order-invalid")
        var restarted=selected();accepted(&restarted);endpoint(&restarted,"prepared",1200)
        endpoint(&restarted,"parentFinalized",1300,generation:4,pid:43)
        checks["recoveryCannotMasqueradeAsSameExecution"] = !passed(restarted)
            && contains(restarted,"daemon-generation-changed")
        var cancelled=earlyFinalize;cancelled.fail("launch-cancelled")
        checks["terminalFailureCannotBecomeSuccessful"] = !passed(cancelled)
        func prefix(_ value:inout DebugSceneStartupMeasurement,_ phase:String,_ time:UInt64,
                    generation:UInt64=3,pid:Int32?=42,requestID:UUID?=nil,
                    childStartupUptimes:[String:UInt64]?=nil) {
            value.observePrefix(phase,ticketID:ticket,intentEpoch:4,requestID:requestID,
                daemonGeneration:generation,daemonPID:pid,uptimeMicros:time,
                childStartupUptimes:childStartupUptimes)
        }
        func diagnostic(_ value:DebugSceneStartupMeasurement)->[String:Any] {
            value.report["parentPrefixObservation"] as! [String:Any]
        }
        func prefixPassed(_ value:DebugSceneStartupMeasurement)->Bool {
            diagnostic(value)["passed"] as? Bool == true
        }
        func cold()->DebugSceneStartupMeasurement {
            var value=earlyFinalize
            prefix(&value,"preparationReceived",1010,generation:0,pid:nil)
            prefix(&value,"processStartBegan",1020,pid:nil)
            prefix(&value,"processStartReturned",1040)
            prefix(&value,"helloObserved",1050)
            prefix(&value,"loadEnqueueAttempted",1060,requestID:request)
            return value
        }
        let coldValue=cold()
        let coldIntervals=diagnostic(coldValue)["intervalsMs"] as! [String:Any]
        checks["coldPrefixUsesParentClockAndActualIntervals"]=prefixPassed(coldValue)
            && coldIntervals["entryToPreparationReceived"] as? Double == 0.01
            && coldIntervals["processStartCall"] as? Double == 0.02
            && coldIntervals["loadEnqueueAttemptedToAcceptedObserved"] as? Double == 0.04
        var warm=earlyFinalize
        prefix(&warm,"preparationReceived",1010)
        prefix(&warm,"loadEnqueueAttempted",1060,requestID:request)
        let warmIntervals=diagnostic(warm)["intervalsMs"] as! [String:Any]
        checks["warmDoesNotInventPriorSpawnOrHello"]=prefixPassed(warm)
            && warmIntervals["processStartCall"] is NSNull
            && warmIntervals["processStartReturnedToHelloObserved"] is NSNull
            && diagnostic(warm)["notObservedAfterSelection"] as? [String]
                == ["processStartBegan","processStartReturned","helloObserved"]
        var handshaking=earlyFinalize
        prefix(&handshaking,"preparationReceived",1010)
        prefix(&handshaking,"helloObserved",1050)
        prefix(&handshaking,"loadEnqueueAttempted",1060,requestID:request)
        checks["alreadyRunningButNotReadyMayObserveHelloOnly"]=prefixPassed(handshaking)
        var foreignPrefix=selected()
        for (id,epoch) in [(UUID(),UInt64(4)),(ticket,UInt64(99))] {
            foreignPrefix.observePrefix("loadEnqueueAttempted",ticketID:id,intentEpoch:epoch,
                requestID:UUID(),daemonGeneration:999,daemonPID:99,uptimeMicros:1060)
        }
        checks["foreignPrefixCannotBindOrPolluteSelection"]=foreignPrefix.requestID == nil
            && (diagnostic(foreignPrefix)["events"] as! [String:Any]).isEmpty
        checks["missingDiagnosticCannotChangeOriginalTimingQualification"]=passed(earlyFinalize)
            && !prefixPassed(earlyFinalize)
            && earlyFinalize.report["entryToPresentedMs"] as? Double == 0.25
        var duplicatePrefix=coldValue
        prefix(&duplicatePrefix,"helloObserved",1051)
        checks["duplicateHelloInvalidatesOnlyDiagnostic"] = !prefixPassed(duplicatePrefix) && passed(duplicatePrefix)
            && ((diagnostic(duplicatePrefix)["events"] as! [String:[String:Any]])["helloObserved"]?["uptimeMicros"] as? UInt64 == 1050)
        var wrongGeneration=earlyFinalize
        prefix(&wrongGeneration,"preparationReceived",1010)
        prefix(&wrongGeneration,"loadEnqueueAttempted",1060,generation:4,requestID:request)
        checks["restartedTransportCannotBorrowOldExecution"] = !prefixPassed(wrongGeneration) && passed(wrongGeneration)
        var wrongPID=earlyFinalize
        prefix(&wrongPID,"preparationReceived",1010)
        prefix(&wrongPID,"loadEnqueueAttempted",1060,pid:43,requestID:request)
        checks["prefixPIDMustMatchPreparedExecution"] = !prefixPassed(wrongPID)
        var wrongRequest=earlyFinalize
        prefix(&wrongRequest,"preparationReceived",1010)
        prefix(&wrongRequest,"loadEnqueueAttempted",1060,requestID:UUID())
        checks["wrongLoadRequestDoesNotRebindOriginal"] = !prefixPassed(wrongRequest) && wrongRequest.requestID == request
        var noRequest=earlyFinalize
        prefix(&noRequest,"preparationReceived",1010)
        prefix(&noRequest,"loadEnqueueAttempted",1060)
        checks["missingLoadRequestIsNotAnAcknowledgement"] = !prefixPassed(noRequest)
        var halfStart=earlyFinalize
        prefix(&halfStart,"preparationReceived",1010)
        prefix(&halfStart,"processStartBegan",1020,pid:nil)
        prefix(&halfStart,"loadEnqueueAttempted",1060,requestID:request)
        checks["failedStartCannotInventReturnOrHello"] = !prefixPassed(halfStart)
        var reordered=earlyFinalize
        prefix(&reordered,"loadEnqueueAttempted",1060,requestID:request)
        prefix(&reordered,"preparationReceived",1010)
        checks["arrivalOrderCannotBeSortedIntoSuccess"] = !prefixPassed(reordered)
        var backwardsPrefix=earlyFinalize
        prefix(&backwardsPrefix,"preparationReceived",999)
        prefix(&backwardsPrefix,"loadEnqueueAttempted",1101,requestID:request)
        checks["prefixMustRemainInsideEntryAcceptedWindow"] = !prefixPassed(backwardsPrefix)
        var unbound=selected()
        prefix(&unbound,"preparationReceived",1010)
        prefix(&unbound,"loadEnqueueAttempted",1060,requestID:request)
        checks["attemptDoesNotBindRequestOrCreateAccepted"]=unbound.requestID == nil
            && !unbound.isComplete && !prefixPassed(unbound)
        let childValues:[String:UInt64] = ["schemaVersion":1,"pid":42,"entryObserved":1025,
            "appKitBegin":1026,"appKitReturned":1030,"runtimeBegin":1031,
            "runtimeReturned":1045,"helloSnapshotCaptured":1049]
        func child(_ value:DebugSceneStartupMeasurement)->[String:Any] {
            value.report["childStartupObservation"] as! [String:Any]
        }
        func childPassed(_ value:DebugSceneStartupMeasurement)->Bool {
            child(value)["passed"] as? Bool == true
        }
        func withChild(_ values:[String:UInt64]?,fresh:Bool=true)->DebugSceneStartupMeasurement {
            var value=earlyFinalize
            prefix(&value,"preparationReceived",1010,generation:0,pid:nil)
            if fresh {
                prefix(&value,"processStartBegan",1020,pid:nil)
                prefix(&value,"processStartReturned",1040)
            }
            prefix(&value,"helloObserved",1050,childStartupUptimes:values)
            prefix(&value,"loadEnqueueAttempted",1060,requestID:request)
            return value
        }
        let fresh=withChild(childValues)
        let freshChild=child(fresh),freshIdentity=freshChild["identity"] as! [String:Any]
        let childIntervals=freshChild["intervalsMs"] as! [String:Any]
        checks["childEntryMayPrecedeProcessRunReturn"]=childPassed(fresh) && passed(fresh)
            && prefixPassed(fresh) && freshChild["applicable"] as? Bool == true
            && freshChild["status"] as? String == "observed"
            && childIntervals["processStartBeganToEntryObserved"] as? Double == 0.005
            && childIntervals["appKitCall"] as? Double == 0.004
            && childIntervals["runtimeConstruction"] as? Double == 0.014
            && childIntervals["helloSnapshotCapturedToParentHelloObserved"] as? Double == 0.001
        checks["childIdentityUsesExactPreparedAndLoadRequest"]=freshIdentity["ticketID"] as? String == ticket.uuidString
            && freshIdentity["intentEpoch"] as? UInt64 == 4
            && freshIdentity["requestID"] as? String == request.uuidString
            && freshIdentity["executionID"] as? String == execution.uuidString
            && freshIdentity["transportGeneration"] as? UInt64 == 3
            && freshIdentity["daemonPID"] as? Int32 == 42
            && freshIdentity["reportedPID"] as? UInt64 == 42
        checks["childReportCarriesOnlySixObservedPoints"]=(freshChild["events"] as? [String:UInt64])
            == childValues.filter { $0.key != "schemaVersion" && $0.key != "pid" }
        let warmChild=child(warm)
        checks["warmChildIsNotApplicableWithoutBorrowingHello"]=childPassed(warm)
            && warmChild["applicable"] as? Bool == false
            && warmChild["status"] as? String == "notApplicable"
            && warmChild["events"] is NSNull
            && (warmChild["identity"] as! [String:Any])["reportedPID"] is NSNull
            && (warmChild["intervalsMs"] as! [String:Any]).values.allSatisfy { $0 is NSNull }
        var beforeSelection=childValues
        for key in childValues.keys where key != "schemaVersion" && key != "pid" {
            beforeSelection[key]! -= 100
        }
        let prewarmed=withChild(beforeSelection,fresh:false)
        checks["prewarmedChildMayBeginBeforeSelectionEntry"]=childPassed(prewarmed)
            && (child(prewarmed)["intervalsMs"] as! [String:Any])["processStartBeganToEntryObserved"] is NSNull
        let noChild=withChild(nil)
        checks["missingChildTelemetryOnlyFailsChildQualification"] = !childPassed(noChild)
            && passed(noChild) && prefixPassed(noChild) && noChild.isComplete
            && noChild.report["entryToPresentedMs"] as? Double == 0.25
        var bad=childValues;bad["pid"]=43
        checks["childSelfReportedPIDMustMatchActualTransport"] = !childPassed(withChild(bad))
        bad=childValues;bad["schemaVersion"]=2
        checks["childSchemaIsExplicit"] = !childPassed(withChild(bad))
        bad=childValues;bad.removeValue(forKey:"runtimeBegin")
        checks["childMissingPointCannotBeInvented"] = !childPassed(withChild(bad))
        bad=childValues;bad["extra"]=1
        checks["childUnknownPointCannotExpandSchema"] = !childPassed(withChild(bad))
        bad=childValues;bad["appKitReturned"]=1025
        checks["childPointOrderCannotBeSortedIntoSuccess"] = !childPassed(withChild(bad))
        bad=childValues;bad["entryObserved"]=0
        checks["childZeroClockIsInvalid"] = !childPassed(withChild(bad))
        bad=childValues;bad["entryObserved"]=1019
        checks["freshChildCannotPrecedeProcessStartBegan"] = !childPassed(withChild(bad))
        bad=childValues;bad["helloSnapshotCaptured"]=1051
        checks["childSnapshotCannotFollowParentHello"] = !childPassed(withChild(bad))
        bad=childValues;bad["appKitBegin"]=1025;bad["appKitReturned"]=1025
        checks["equalChildMicrosecondPointsAreLegal"]=childPassed(withChild(bad))
        var childDuplicate=fresh
        prefix(&childDuplicate,"helloObserved",1051,childStartupUptimes:bad)
        checks["duplicateChildHelloKeepsFirstAndFailsOnlyDiagnostics"] = !childPassed(childDuplicate)
            && passed(childDuplicate) && (child(childDuplicate)["events"] as? [String:UInt64])
                == childValues.filter { $0.key != "schemaVersion" && $0.key != "pid" }
        var foreignChild=warm
        foreignChild.observePrefix("helloObserved",ticketID:UUID(),intentEpoch:4,requestID:nil,
            daemonGeneration:3,daemonPID:42,uptimeMicros:1050,childStartupUptimes:childValues)
        foreignChild.observePrefix("helloObserved",ticketID:ticket,intentEpoch:99,requestID:nil,
            daemonGeneration:3,daemonPID:42,uptimeMicros:1050,childStartupUptimes:childValues)
        checks["foreignChildTicketOrEpochCannotPolluteWarmSelection"]=childPassed(foreignChild)
            && child(foreignChild)["status"] as? String == "notApplicable"
        var changedTransport=earlyFinalize
        prefix(&changedTransport,"preparationReceived",1010)
        prefix(&changedTransport,"helloObserved",1050,generation:4,pid:43,childStartupUptimes:childValues)
        prefix(&changedTransport,"loadEnqueueAttempted",1060,requestID:request)
        checks["childCannotBorrowDifferentTransportGeneration"] = !childPassed(changedTransport) && passed(changedTransport)
        checks["childCannotBorrowWrongLoadRequest"] = !childPassed(wrongRequest) && passed(wrongRequest)
        checks["childCannotQualifyIncompleteSpawnWithoutHello"] = !childPassed(halfStart) && passed(halfStart)
        checks["childCannotQualifyUnboundExecution"] = !childPassed(unbound)
        print(String(data:try JSONSerialization.data(withJSONObject:checks,options:.sortedKeys),encoding:.utf8)!)
    }
}
'''


class SceneStartupMeasurementTests(unittest.TestCase):
    def test_exact_identity_event_order_missing_and_failure_results(self):
        with tempfile.TemporaryDirectory(prefix="mwx-scene-startup-measurement-") as directory:
            root = Path(directory)
            harness = root / "Harness.swift"
            harness.write_text(HARNESS)
            binary = root / "measurement"
            compiled = subprocess.run(
                ["xcrun", "swiftc", "-D", "DEBUG", "-parse-as-library", str(SOURCE),
                 str(harness), "-o", str(binary)],
                capture_output=True, text=True, timeout=60,
            )
            self.assertEqual(compiled.returncode, 0, compiled.stderr)
            result = subprocess.run([str(binary)], capture_output=True, text=True, timeout=10)
            self.assertEqual(result.returncode, 0, result.stderr)
            checks = json.loads(result.stdout)
            self.assertEqual(len(checks), 44)
            for name, passed in checks.items():
                with self.subTest(name=name):
                    self.assertTrue(passed)


if __name__ == "__main__":
    unittest.main()
