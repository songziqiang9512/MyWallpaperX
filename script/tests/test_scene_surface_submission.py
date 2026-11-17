"""Real Metal independent display submission and coordinator cancellation behavior."""
import json
from pathlib import Path
import struct
import subprocess
import tempfile
import unittest

from .test_scene_resolved_material_runtime_bridge import (
    REPOSITORY_ROOT, SUBMISSION_COORDINATOR_FIXTURE, SUBMISSION_SWIFT_SOURCES,
    SCENE_DEPENDENCY_BINDING_SUPPORT,
    RESOURCE_PHASE_UNAVAILABLE_SUPPORT,
)

MAIN = r'''
struct SceneMetalRenderer {}
@main enum Harness {
 static func main() throws {
  guard let device=MTLCreateSystemDefaultDevice(), let queue=device.makeCommandQueue() else {
   print("{\"metalAvailable\":false}"); return
  }
  typealias Renderer=SceneMetalRenderer
  var result:[String:Bool]=[:]
  var events:[Int]=[]
  func candidate(_ id:Int, _ buffer:MTLCommandBuffer)->Renderer.PreparedFrame {
   Renderer.PreparedFrame(commandBuffer:buffer,submit:{_ in events.append(id);buffer.commit()},
                          cancel:{events.append(-id)})
  }
  let a=queue.makeCommandBuffer()!, b=queue.makeCommandBuffer()!
  let output=device.makeBuffer(length:16,options:.storageModeShared)!
  memset(output.contents(),0,16)
  for (buffer,value):(MTLCommandBuffer,UInt8) in [(a,11),(b,22)] {
   let encoder=buffer.makeBlitCommandEncoder()!
   encoder.fill(buffer:output,range:buffer === a ? 0..<8:8..<16,value:value)
   encoder.endEncoding()
  }
  let first=candidate(1,a), second=candidate(2,b)
  result["preparationDoesNotSubmit"] = a.status == .notEnqueued && b.status == .notEnqueued
    && output.contents().load(as:UInt8.self)==0 && events.isEmpty
  let outcomeA=Renderer.submitPreparedFrame(.prepared(first))
  let unavailable=Renderer.submitPreparedFrame(.deferred(reasonCode:"drawable-unavailable"))
  a.waitUntilCompleted()
  result["healthyScreenCompletesWhilePeerMissing"] = outcomeA.isSubmitted && unavailable.isDeferred
    && a.status == .completed && b.status == .notEnqueued
    && output.contents().load(as:UInt8.self)==11 && events == [1]
  let outcomeB=Renderer.submitPreparedFrame(.prepared(second))
  b.waitUntilCompleted()
  result["recoveredScreenCompletes"] = outcomeB.isSubmitted && b.status == .completed
    && output.contents().advanced(by:8).load(as:UInt8.self)==22 && events == [1,2]
  result["cannotSubmitTwice"] = !Renderer.submitPreparedFrame(.prepared(first)).isSubmitted
    && !Renderer.submitPreparedFrame(.prepared(second)).isSubmitted && events == [1,2]
  result["dropRemainsLocal"] = Renderer.submitPreparedFrame(.dropped(reasonCode:"target-rejected"))
    == .dropped(reasonCode:"target-rejected") && events == [1,2]
  events=[]
  var abandoned:Renderer.PreparedFrame?=candidate(9,queue.makeCommandBuffer()!)
  var cancelledCompletion=false
  abandoned!.whenCompleted { _ in cancelledCompletion=true }
  result["abandonedWasReady"] = abandoned!.isReady
  abandoned=nil
  result["deinitCancelsSynchronously"] = events == [-9] && !cancelledCompletion

  let pool=SceneParticleDepthTargetPool()
  let fifo=SceneSourceUpdateStateFIFO(initial:0)
  var producerOK=true
  var expected=0
  for frame in 0..<16 {
   for screen in 0..<3 {
    let transaction=SceneSourceUpdateTransaction(), buffer=queue.makeCommandBuffer()!
    guard case let .acquired(lease)=pool.acquire(device:device,width:8,height:8,on:buffer)
    else {producerOK=false;break}
    let next=fifo.update(transaction:transaction){$0 += 1;return $0}
    producerOK = next == expected+1 && producerOK
    let candidate=Renderer.PreparedFrame(commandBuffer:buffer,submit:{_ in
     transaction.arm(on:buffer);lease.arm(on:buffer);buffer.commit();transaction.didSubmit()
    },cancel:{transaction.cancel();lease.cancel()})
    if screen == 1 && frame < 8 {
     candidate.cancel()
    } else {
     producerOK = Renderer.submitPreparedFrame(.prepared(candidate)).isSubmitted && producerOK
     buffer.waitUntilCompleted()
     producerOK = buffer.status == .completed && producerOK
     expected += 1
    }
   }
   let probe=SceneSourceUpdateTransaction()
   producerOK = fifo.update(transaction:probe){$0} == expected && producerOK
   probe.cancel()
  }
  result["independentCancelRetainsSubmittedSourcesAndReclaimsDepth"] = producerOK && expected == 40

  let sourceA=UUID(uuidString:"00000000-0000-0000-0000-000000000001")!
  let sourceB=UUID(uuidString:"00000000-0000-0000-0000-000000000002")!
  let sourceC=UUID(uuidString:"00000000-0000-0000-0000-000000000003")!
  let choice=Renderer.PreparedFrame(commandBuffer:queue.makeCommandBuffer()!,submit:{_ in},cancel:{})
  var deadline:TimeInterval?
  result["startupPendingDoesNotBorrowPreviousFrame"] = choice.shouldPresentVideoFrame(
   readySources:[],pendingSources:[sourceB],lastSubmittedPresentationSources:[],switchDeadline:&deadline,hostTime:10)
   && deadline == nil
  result["sameSourceNewLogicalIDDoesNotWait"] = choice.shouldPresentVideoFrame(
   readySources:[],pendingSources:[sourceA],lastSubmittedPresentationSources:[sourceA],switchDeadline:&deadline,hostTime:10)
   && deadline == nil
  result["optionalSourceAdditionDoesNotWait"] = choice.shouldPresentVideoFrame(
   readySources:[sourceA],pendingSources:[sourceB],lastSubmittedPresentationSources:[sourceA],switchDeadline:&deadline,hostTime:10)
   && deadline == nil
  result["sourceReplacementWaitsOnce"] = !choice.shouldPresentVideoFrame(
   readySources:[],pendingSources:[sourceB],lastSubmittedPresentationSources:[sourceA],switchDeadline:&deadline,hostTime:10)
   && deadline == 10.250
  result["continuingSelectionDoesNotRenewWindow"] = !choice.shouldPresentVideoFrame(
   readySources:[],pendingSources:[sourceC],lastSubmittedPresentationSources:[sourceA],switchDeadline:&deadline,hostTime:10.20)
   && deadline == 10.250
  result["exactDeadlinePresents"] = choice.shouldPresentVideoFrame(
   readySources:[],pendingSources:[sourceB],lastSubmittedPresentationSources:[sourceA],switchDeadline:&deadline,hostTime:10.250)
  result["spentWindowCannotRestartBeforeCompletion"] = choice.shouldPresentVideoFrame(
   readySources:[],pendingSources:[sourceC],lastSubmittedPresentationSources:[sourceA],switchDeadline:&deadline,hostTime:10.251)
   && deadline == 10.250
  result["readyReplacementClearsWait"] = choice.shouldPresentVideoFrame(
   readySources:[sourceB],pendingSources:[],lastSubmittedPresentationSources:[sourceA],switchDeadline:&deadline,hostTime:10.252)
   && deadline == nil
  _=choice.shouldPresentVideoFrame(readySources:[],pendingSources:[sourceB],lastSubmittedPresentationSources:[sourceA],
   switchDeadline:&deadline,hostTime:20)
  let failedChoice=Renderer.PreparedFrame(commandBuffer:queue.makeCommandBuffer()!,
   initialVideoPresentation:.init(hasUnavailableVideo:true),submit:{_ in},cancel:{})
  result["unavailableReplacementEndsWait"] = failedChoice.shouldPresentVideoFrame(
   readySources:[],pendingSources:[sourceB],lastSubmittedPresentationSources:[sourceA],switchDeadline:&deadline,hostTime:20.1)
   && deadline == nil
  result["oneRetiredSourceAmongLivePeersStillWaitsForItsReplacement"] = !choice.shouldPresentVideoFrame(
   readySources:[sourceC],pendingSources:[sourceB],lastSubmittedPresentationSources:[sourceA,sourceC],
   switchDeadline:&deadline,hostTime:30) && deadline == 30.250
  let startupFacts=Renderer.InitialVideoPresentation(readyLayerIDs:[7],pendingLayerIDs:[8],
   pendingSurfaceLayerIDs:[],hasUnavailableVideo:false)
  result["startupReadinessRetainsGroupPendingFacts"] = !startupFacts.isComplete
   && startupFacts.readyLayerIDs == [7] && startupFacts.pendingSurfaceLayerIDs.isEmpty
  choice.cancel();failedChoice.cancel()

  // A withheld presentation still submits real encoded GPU/source work.
  let heldBuffer=queue.makeCommandBuffer()!,heldMarker=device.makeBuffer(length:4,options:.storageModeShared)!
  memset(heldMarker.contents(),0,4)
  let heldBlit=heldBuffer.makeBlitCommandEncoder()!
  heldBlit.fill(buffer:heldMarker,range:0..<4,value:91);heldBlit.endEncoding()
  let heldTransaction=SceneSourceUpdateTransaction(),heldFIFO=SceneSourceUpdateStateFIFO(initial:0)
  let heldDepth:SceneParticleDepthTargetLease
  guard case let .acquired(lease)=pool.acquire(device:device,width:8,height:8,on:heldBuffer) else {fatalError("held depth")}
  heldDepth=lease
  _=heldFIFO.update(transaction:heldTransaction){$0=4;return $0}
  var presentationFlags:[Bool]=[]
  let held=Renderer.PreparedFrame(commandBuffer:heldBuffer,submit:{present in
   presentationFlags.append(present);heldTransaction.arm(on:heldBuffer);heldDepth.arm(on:heldBuffer)
   heldBuffer.commit();heldTransaction.didSubmit()
  },cancel:{heldTransaction.cancel();heldDepth.cancel()})
  let heldOutcome=Renderer.submitPreparedFrame(.prepared(held),present:false)
  heldBuffer.waitUntilCompleted()
  let afterHeld=SceneSourceUpdateTransaction()
  result["withheldFrameCommitsGPUAndSourceWork"] = heldOutcome.isSubmitted && heldBuffer.status == .completed
   && heldMarker.contents().load(as:UInt8.self)==91 && presentationFlags == [false]
   && heldFIFO.update(transaction:afterHeld){$0} == 4
  afterHeld.cancel()
  result["withheldFrameCannotSubmitAgain"] = !Renderer.submitPreparedFrame(.prepared(held),present:true).isSubmitted
   && presentationFlags == [false]

  // A missing diagnostic program label must not change product publication.
  // Use the production observation builder, coordinator and real Metal buffer.
  for capture in [false, true] {
   for damagedObservation in [false, true] {
    let recorder=LogRecorder()
    let observed=Coordinator(device:device,capabilities:makeCapabilities(),
     capturesExecutionObservations:capture,logSink:recorder.append)
    let stage=makeObservationTransition(device:device,
     programCacheKeys:damagedObservation ? [] : ["fixture-program"])
    let graph=SceneResolvedMaterialGraphExecutor.PreparedGraph(stages:[stage],
     finalResource:stage.effectOutputResource,finalTexture:stage.effectOutputResource.publication.texture,
     historyTokensByEffect:[:])
    let buffer=queue.makeCommandBuffer()!, pins=makeCommit(generation:3)
    let marker=device.makeBuffer(length:4,options:.storageModeShared)!
    memset(marker.contents(),0,4)
    let encoder=buffer.makeBlitCommandEncoder()!
    encoder.fill(buffer:marker,range:0..<4,value:37);encoder.endEncoding()
    _ = observed.observeCommandBufferLocked(buffer)
    observed.frameIsActive=true;observed.frame = .init(frameIndex:1)
    let historyPin=SceneGraphRenderTargetResidencyPin(purpose:.history(effect,[.init(rawValue:"observed")]),generation:3)
    let tail=makeTail(device:device,token:"observed",generation:3,pin:historyPin)
    observed.activeByID[1]=makeLedger(coordinator:observed,identity:1,commandBuffer:buffer,
     prepared:graph,commit:pins,
     blueprint:.init(states:[effect:stage.transition.nextState],resources:[:],mappingGenerations:[effect:1],resetReasons:[:]),
     candidate:[effect:tail],phase:.outputConsumed,consumed:true)
    observed.activeTransactions=[1];observed.scheduledTails=[effect:tail]
    let sealed=observed.sealFrame(on:buffer)
    result["diagnosticModesSeal-\(capture)-\(damagedObservation)"]=sealed
    result["noSuccessEvidenceBeforeGPU-\(capture)-\(damagedObservation)"] = !recorder.lines.contains{$0.contains("outcome=succeeded")}
    _ = observed.endFrame()
    if sealed {
     let withheld=Renderer.PreparedFrame(commandBuffer:buffer,submit:{present in
      result["graphSubmissionWithholdsOnlyPresentation-\(capture)-\(damagedObservation)"] = !present
      buffer.commit()
     },cancel:{observed.cancelUnsubmittedFrame(on:buffer)})
     result["withheldGraphStillSubmits-\(capture)-\(damagedObservation)"] =
      Renderer.submitPreparedFrame(.prepared(withheld),present:false).isSubmitted
     buffer.waitUntilCompleted()
     observed.completeCommandBuffer(identity:ObjectIdentifier(buffer),
      observationID:observed.commandBufferRecords[ObjectIdentifier(buffer)]?.observationID ?? 0,status:.completed)
     result["diagnosticModesPublishAndRelease-\(capture)-\(damagedObservation)"] = buffer.status == .completed
      && marker.contents().load(as:UInt8.self)==37 && pins.submissionPin.releaseCount==1
      && observed.activeByID.isEmpty && observed.pendingSubmissions.isEmpty
      && observed.committedTails[effect]?.historyPin === historyPin && historyPin.active
      && !observed.shouldDeferFrame
     result["successEvidenceMatchesCapture-\(capture)-\(damagedObservation)"] = recorder.lines.contains{$0.contains("outcome=succeeded")} == (capture && !damagedObservation)
     if capture && damagedObservation {
      result["failedObservationIsExplicit"] = recorder.lines.contains{$0.contains("success-observation-invalidProgram")}
      result["failedObservationIsNotSuccess"] = !recorder.lines.contains{$0.contains("outcome=succeeded")}
     }
     let next=queue.makeCommandBuffer()!
     observed.frameIsActive=true;observed.frameSealed=false;observed.frame = .init(frameIndex:2)
     result["nextFrameAfterObservation-\(capture)-\(damagedObservation)"] = observed.sealFrame(on:next)
     _ = observed.endFrame()
     next.commit();next.waitUntilCompleted()
     result["nextFrameGPUCompleted-\(capture)-\(damagedObservation)"] = next.status == .completed
      && observed.committedTails[effect]?.historyPin === historyPin
     observed.invalidate(reason:.surfaceStop)
     result["historyRetiresAfterObservation-\(capture)-\(damagedObservation)"] = historyPin.releaseCount==1
    }
   }
   let unsafe=Coordinator(device:device,capabilities:makeCapabilities(),capturesExecutionObservations:capture,logSink:{_ in})
   let buffer=queue.makeCommandBuffer()!, pins=makeCommit(generation:1)
   _ = unsafe.observeCommandBufferLocked(buffer)
   unsafe.frameIsActive=true;unsafe.frame = .init(frameIndex:1)
   unsafe.activeByID[1]=makeLedger(coordinator:unsafe,identity:1,commandBuffer:buffer,
    prepared:makePrepared(device:device),commit:pins,blueprint:nil,candidate:[:],phase:.outputConsumed,consumed:true)
   unsafe.activeTransactions=[1]
   result["missingBlueprintStillRejects-\(capture)"] = !unsafe.sealFrame(on:buffer)
    && buffer.status == .notEnqueued && pins.submissionPin.releaseCount==1
  }

  let coordinator=makeCoordinator(device)
  let priorBuffer=queue.makeCommandBuffer()!, priorCommit=makeCommit(generation:1)
  seedPendingSuccess(coordinator:coordinator,identity:50,commandBuffer:priorBuffer,tail:nil,commit:priorCommit)
  priorBuffer.commit()
  let cancelBuffer=queue.makeCommandBuffer()!
  _ = coordinator.observeCommandBufferLocked(cancelBuffer)
  coordinator.frameIsActive=true;coordinator.frame = .init(frameIndex:51)
  let cancelledCommit=makeCommit(generation:1)
  coordinator.activeByID[51]=makeLedger(coordinator:coordinator,identity:51,commandBuffer:cancelBuffer,
   prepared:makePrepared(device:device),commit:cancelledCommit,
   blueprint:.init(states:[:],resources:[:],mappingGenerations:[:],resetReasons:[:]),
   candidate:[:],phase:.outputConsumed,consumed:true)
  coordinator.activeTransactions=[51]
  let sealed=coordinator.sealFrame(on:cancelBuffer)
  _ = coordinator.endFrame()
  coordinator.cancelUnsubmittedFrame(on:cancelBuffer)
  coordinator.cancelUnsubmittedFrame(on:cancelBuffer)
  result["sealedCancelPreservesSubmittedAncestor"] = sealed && cancelBuffer.status == .notEnqueued
   && coordinator.pendingSubmissions.count==1 && coordinator.pendingSubmissions[0].ledgerIDs==[50]
   && coordinator.activeByID[51]==nil && coordinator.activeByID[50] != nil
   && cancelledCommit.submissionPin.releaseCount==1 && priorCommit.submissionPin.releaseCount==0
   && coordinator.commandBufferRecords[ObjectIdentifier(cancelBuffer)]==nil
   && !coordinator.shouldDeferFrame
  coordinator.cancelUnsubmittedFrame(on:priorBuffer)
  result["cannotCancelSubmittedBuffer"] = priorCommit.submissionPin.releaseCount==0
  coordinator.completeCommandBuffer(identity:ObjectIdentifier(priorBuffer),observationID:UInt64.max,status:.failed)
  result["staleObservationCannotTerminalizeExistingIdentity"] = coordinator.pendingSubmissions.count==1
   && coordinator.pendingSubmissions[0].gpuStatus==nil
   && coordinator.commandBufferRecords[ObjectIdentifier(priorBuffer)]?.terminalStatus==nil
   && priorCommit.submissionPin.releaseCount==0 && coordinator.activeByID[50] != nil
  priorBuffer.waitUntilCompleted()
  coordinator.completeCommandBuffer(identity:ObjectIdentifier(priorBuffer), observationID: coordinator.commandBufferRecords[ObjectIdentifier(priorBuffer)]?.observationID ?? 0,status:.completed)
  result["ancestorCompletesNormally"] = coordinator.pendingSubmissions.isEmpty
   && coordinator.activeByID.isEmpty && priorCommit.submissionPin.releaseCount==1
  // Actual committed history must survive a newer unsubmitted suffix.
  let historyPin=SceneGraphRenderTargetResidencyPin(purpose:.history(effect,[.init(rawValue:"base")]),generation:1)
  let tail=makeTail(device:device,token:"base",generation:1,pin:historyPin)
  coordinator.committedTails=[effect:tail];coordinator.scheduledTails=[effect:tail]
  let suffix=queue.makeCommandBuffer()!, suffixCommit=makeCommit(generation:1)
  seedPendingSuccess(coordinator:coordinator,identity:60,commandBuffer:suffix,tail:nil,commit:suffixCommit)
  coordinator.cancelUnsubmittedFrame(on:suffix)
  result["cancelPreservesCommittedHistory"] = historyPin.active && historyPin.releaseCount==0
   && coordinator.scheduledTails[effect]?.historyPin === historyPin && suffixCommit.submissionPin.releaseCount==1
  let reused=queue.makeCommandBuffer()!, oldCommit=makeCommit(generation:1)
  seedPendingSuccess(coordinator:coordinator,identity:70,commandBuffer:reused,tail:nil,commit:oldCommit)
  let staleID=coordinator.commandBufferRecords[ObjectIdentifier(reused)]!.observationID
  coordinator.cancelUnsubmittedFrame(on:reused)
  let newCommit=makeCommit(generation:1)
  seedPendingSuccess(coordinator:coordinator,identity:71,commandBuffer:reused,tail:nil,commit:newCommit)
  let currentID=coordinator.commandBufferRecords[ObjectIdentifier(reused)]!.observationID
  coordinator.completeCommandBuffer(identity:ObjectIdentifier(reused),observationID:staleID,status:.failed)
  result["sameBufferNewRegistrationRejectsOldCallback"] = currentID>staleID
    && coordinator.pendingSubmissions.count==1 && coordinator.pendingSubmissions[0].gpuStatus==nil
    && coordinator.commandBufferRecords[ObjectIdentifier(reused)]?.terminalStatus==nil
    && newCommit.submissionPin.releaseCount==0 && oldCommit.submissionPin.releaseCount==1
  coordinator.completeCommandBuffer(identity:ObjectIdentifier(reused),observationID:currentID,status:.completed)
  result["newRegistrationCompletesAfterStaleCallback"] = newCommit.submissionPin.releaseCount==1
    && coordinator.pendingSubmissions.isEmpty && coordinator.activeByID.isEmpty
  let exhausted=makeCoordinator(device), finalBuffer=queue.makeCommandBuffer()!
  exhausted.nextCommandBufferObservationID=UInt64.max-1
  let finalIssued=exhausted.observeCommandBufferLocked(finalBuffer)
  let repeated=exhausted.observeCommandBufferLocked(finalBuffer)
  result["observationCounterNeverWraps"] = finalIssued && repeated
    && !exhausted.observeCommandBufferLocked(queue.makeCommandBuffer()!)
    && exhausted.commandBufferRecords.count==1 && exhausted.nextCommandBufferObservationID==UInt64.max
    && exhausted.commandBufferRecords[ObjectIdentifier(finalBuffer)]?.observationID==UInt64.max
  exhausted.pruneCommandBufferRecordsLocked()
  let beforeInvalidation=coordinator.nextCommandBufferObservationID
  coordinator.invalidate(reason:.surfaceStop)
  result["historyReleasedAtStop"] = historyPin.releaseCount==1
  let afterStop=queue.makeCommandBuffer()!
  result["invalidationDoesNotReuseObservationIdentity"] = coordinator.observeCommandBufferLocked(afterStop)
    && coordinator.nextCommandBufferObservationID>beforeInvalidation
  coordinator.pruneCommandBufferRecordsLocked()
  print(String(decoding:try JSONSerialization.data(withJSONObject:["metalAvailable":true,"results":result]),as:UTF8.self))
 }
}
'''


class SceneSurfaceSubmissionTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temp=tempfile.TemporaryDirectory(prefix="scene-surface-submission-")
        root=Path(cls.temp.name);source=root/"Harness.swift";binary=root/"harness"
        source.write_text(SUBMISSION_COORDINATOR_FIXTURE.split("@main",1)[0]
                          +SCENE_DEPENDENCY_BINDING_SUPPORT+RESOURCE_PHASE_UNAVAILABLE_SUPPORT+MAIN)
        scene=REPOSITORY_ROOT/"MyWallpaperX/Core/SteamWorkshopScene"
        sources=[
    Path(__file__).resolve().parents[2] / "MyWallpaperX/Core/SteamWorkshopScene/Resources/Textures/SceneResourceBudget.swift",*SUBMISSION_SWIFT_SOURCES,scene/"Rendering/Frame/SceneMetalRenderer+FrameOutcome.swift",
                 scene/"Rendering/Frame/SceneSourceUpdateTransaction.swift",
                 scene/"Rendering/Particles/SceneParticleDepthTargetPool.swift",
                 scene/"Rendering/Targets/SceneCommandBufferOrdering.swift"]
        built=subprocess.run(["xcrun","--sdk","macosx","swiftc","-parse-as-library","-D","DEBUG",*map(str,sources),
                              str(source),"-framework","Metal","-module-cache-path",str(root/"cache"),"-o",str(binary)],capture_output=True,text=True)
        if built.returncode:raise AssertionError(built.stdout+built.stderr)
        run=subprocess.run([str(binary)],capture_output=True,text=True,timeout=30)
        if run.returncode:raise AssertionError(run.stdout+run.stderr)
        cls.result=json.loads(run.stdout.strip().splitlines()[-1])

    @classmethod
    def tearDownClass(cls):cls.temp.cleanup()

    def test_real_metal_surface_barrier_and_cancellation(self):
        self.assertTrue(self.result["metalAvailable"],"This gate requires real Metal")
        for name,passed in self.result["results"].items():
            with self.subTest(name=name):self.assertTrue(passed,name)


class SceneDepthTargetOrderingTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temp=tempfile.TemporaryDirectory(prefix="scene-depth-target-ordering-")
        cls.addClassCleanup(cls.temp.cleanup)
        root=Path(cls.temp.name);source=root/"Main.swift";binary=root/"depth-ordering"
        source.write_text(r'''import Foundation
import Metal
@main enum Main {
 static func main() throws {
  guard let device=MTLCreateSystemDefaultDevice() else {
   print("{\"metalAvailable\":false}");return
  }
  let rows=try SceneDepthTargetOrderingChecks.run(device:device)
  print(String(decoding:try JSONSerialization.data(withJSONObject:["metalAvailable":true,
   "depthOrdering":rows]),as:UTF8.self))
 }
}
''')
        scene=REPOSITORY_ROOT/"MyWallpaperX/Core/SteamWorkshopScene"
        sources=[scene/"Resources/Textures/SceneResourceBudget.swift",
                 scene/"Rendering/Particles/SceneParticleDepthTargetPool.swift",
                 scene/"Rendering/Targets/SceneCommandBufferOrdering.swift",
                 Path(__file__).with_name("fixtures")/"SceneDepthTargetOrderingChecks.swift"]
        built=subprocess.run(["xcrun","--sdk","macosx","swiftc","-parse-as-library","-D","DEBUG",
            *map(str,sources),str(source),"-framework","Metal","-module-cache-path",str(root/"cache"),
            "-o",str(binary)],capture_output=True,text=True)
        if built.returncode:raise AssertionError(built.stdout+built.stderr)
        run=subprocess.run([str(binary)],capture_output=True,text=True,timeout=30)
        if run.returncode:raise AssertionError(run.stdout+run.stderr)
        cls.result=json.loads(run.stdout.strip().splitlines()[-1])
        if not cls.result["metalAvailable"]:raise unittest.SkipTest("Metal is unavailable")

    def test_tracked_depth_reuses_queue_order_without_merging_live_passes(self):
        rows={row["name"]:row for row in self.result["depthOrdering"]}
        literals={
            "ordered":[.75,.25], "same-buffer-pass-isolation":[.625,.375],
            "cross-queue-isolation":[.75,.25], "not-enqueued-predecessor":[.75,.25],
            "cancel-new-preserves-old":[.75,.25],
            "old-completion-preserves-pending":[.75,.25,.5,.875],
            "global-three-reservations":[.125,.5,.875], "resize-and-warm":[.75,.25,.5],
        }
        self.assertEqual(set(rows),set(literals)|{"three-buffers-three-passes","invalid-extent"})
        self.assertEqual(sum(row["completedCBs"] for row in rows.values()),24)
        for name,row in rows.items():
            with self.subTest(case=name):
                self.assertEqual(row["completedCBs"],row["commandBuffers"])
                self.assertTrue(row["allTracked"])
                self.assertTrue(row["allDepth32PrivateRenderTarget"])
                if name in literals:
                    self.assertEqual([v["value"] for v in row["readbacks"]],literals[name])
                    self.assertEqual([v["bits"] for v in row["readbacks"]],
                                     [struct.unpack("<I",struct.pack("<f",v))[0] for v in literals[name]])
        for name in ["ordered","global-three-reservations"]:
            self.assertEqual(rows[name]["uniqueTextureCount"],1)
            self.assertEqual(rows[name]["logicalResidentBytes"],64*64*4)
        self.assertEqual(rows["ordered"]["beforeCommitStatuses"],[1,0])
        self.assertEqual(rows["ordered"]["commitOrder"],[2,1])
        for name in ["same-buffer-pass-isolation","cross-queue-isolation","not-enqueued-predecessor"]:
            self.assertEqual(rows[name]["uniqueTextureCount"],2)
            self.assertEqual(rows[name]["logicalResidentBytes"],2*64*64*4)
        self.assertTrue(rows["cancel-new-preserves-old"]["oldAndCrossQueueDistinct"])
        self.assertTrue(rows["cancel-new-preserves-old"]["cancelledStatusWasNotEnqueued"])
        completed=rows["old-completion-preserves-pending"]
        self.assertEqual(completed["uniqueTextureCount"],3)
        self.assertEqual(completed["fourthSameBuffer"],"currentFrameCapacityExceeded")
        self.assertEqual(rows["global-three-reservations"]["fourthOtherBuffer"],"busyOtherFrame")
        mixed=rows["three-buffers-three-passes"]
        self.assertEqual(mixed["acquisitionOutcomes"],[["acquired"]*3]*3)
        self.assertEqual(mixed["leasesByBuffer"],[3,3,3])
        self.assertEqual([len(set(group)) for group in mixed["passTextureGroups"]],[3,3,3])
        self.assertEqual(mixed["uniqueTextureCount"],3)
        self.assertEqual(mixed["logicalResidentBytes"],3*64*64*4)
        expected=[[.125,.25,.375],[.5,.625,.75],[.875,.25,.5]]
        self.assertEqual([[v["value"] for v in group] for group in mixed["readbackGroups"]],expected)
        self.assertEqual(mixed["fourthSameBuffer"],"currentFrameCapacityExceeded")
        self.assertEqual(mixed["fourthOtherBuffer"],"busyOtherFrame")
        invalid=rows["invalid-extent"]
        self.assertEqual(invalid["outcomes"],["invalidExtent"]*4)
        self.assertEqual((invalid["logicalResidentBytes"],invalid["uniqueTextureCount"]),(0,0))
        resize=rows["resize-and-warm"]
        self.assertTrue(resize["inflightDifferentExtentDistinct"])
        self.assertTrue(resize["warmMatchingTextureReused"])
        self.assertEqual(resize["dimensions"],[[64,64],[128,64],[128,64]])
        self.assertEqual(resize["logicalResidentBytes"],64*64*4+128*64*4)
