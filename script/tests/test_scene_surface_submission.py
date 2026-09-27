"""Real Metal submission barrier and sealed coordinator cancellation behavior."""
import json
from pathlib import Path
import subprocess
import tempfile
import unittest

from .test_scene_resolved_material_runtime_bridge import (
    REPOSITORY_ROOT, SUBMISSION_COORDINATOR_FIXTURE, SUBMISSION_SWIFT_SOURCES,
    SCENE_DEPENDENCY_BINDING_SUPPORT,
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
   Renderer.PreparedFrame(commandBuffer:buffer,submit:{events.append(id);buffer.commit()},
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
  var prepared:[Renderer.FrameOutcome]=[.prepared(candidate(1,a)),.prepared(candidate(2,b))]
  result["preparationDoesNotSubmit"] = a.status == .notEnqueued && b.status == .notEnqueued
    && output.contents().load(as:UInt8.self)==0 && events.isEmpty
  result["allReadySubmit"] = Renderer.submitPreparedFrames(&prepared,expectedCount:2)
  a.waitUntilCompleted();b.waitUntilCompleted()
  result["bothGPUResults"] = a.status == .completed && b.status == .completed
    && output.contents().load(as:UInt8.self)==11
    && output.contents().advanced(by:8).load(as:UInt8.self)==22
    && prepared.allSatisfy(\.isSubmitted) && events == [1,2]
  result["cannotSubmitTwice"] = !Renderer.submitPreparedFrames(&prepared,expectedCount:2) && events == [1,2]

  events=[]
  let c=queue.makeCommandBuffer()!, d=queue.makeCommandBuffer()!
  var rejected:[Renderer.FrameOutcome]=[.prepared(candidate(1,c)),.prepared(candidate(2,d)),.dropped(reasonCode:"sibling")]
  result["siblingFailureSubmitsNothing"] = !Renderer.submitPreparedFrames(&rejected,expectedCount:3)
    && c.status == .notEnqueued && d.status == .notEnqueued && events == [-2,-1]
  rejected=[]
  result["cancelledCandidatesDoNotResolveAgain"] = events == [-2,-1]
  events=[]
  var missing:[Renderer.FrameOutcome]=[.prepared(candidate(1,queue.makeCommandBuffer()!))]
  result["missingSurfaceCancels"] = !Renderer.submitPreparedFrames(&missing,expectedCount:2) && events == [-1]
  events=[]
  var abandoned:Renderer.PreparedFrame?=candidate(9,queue.makeCommandBuffer()!)
  result["abandonedWasReady"] = abandoned!.isReady
  abandoned=nil
  result["deinitCancelsSynchronously"] = events == [-9]
  events=[]
  let duplicate=candidate(5,queue.makeCommandBuffer()!)
  var duplicates:[Renderer.FrameOutcome]=[.prepared(duplicate),.prepared(duplicate)]
  result["duplicateCandidateRejectedOnce"] = !Renderer.submitPreparedFrames(&duplicates,expectedCount:2) && events == [-5]

  events=[]
  let aliasBuffer=queue.makeCommandBuffer()!
  var aliases:[Renderer.FrameOutcome]=[.prepared(candidate(6,aliasBuffer)),.prepared(candidate(7,aliasBuffer))]
  result["aliasedBufferRejectedBeforeAnyCommit"] = !Renderer.submitPreparedFrames(&aliases,expectedCount:2)
    && aliasBuffer.status == .notEnqueued && events == [-7,-6]

  let pool=SceneParticleDepthTargetPool()
  let fifo=SceneSourceUpdateStateFIFO(initial:0)
  var producerOK=true
  for _ in 0..<16 {
   var candidates:[Renderer.FrameOutcome]=[]
   for _ in 0..<3 {
    guard let lease=pool.acquire(device:device,width:8,height:8) else {producerOK=false;break}
    let transaction=SceneSourceUpdateTransaction(), buffer=queue.makeCommandBuffer()!
    fifo.update(transaction:transaction){$0 += 1}
    candidates.append(.prepared(.init(commandBuffer:buffer,submit:{
     transaction.arm(on:buffer);lease.arm(on:buffer);buffer.commit();transaction.didSubmit()
    },cancel:{transaction.cancel();lease.cancel()})))
   }
   candidates.append(.deferred(reasonCode:"last-drawable"))
   producerOK = !Renderer.submitPreparedFrames(&candidates,expectedCount:4) && producerOK
   let probe=SceneSourceUpdateTransaction()
   producerOK = fifo.update(transaction:probe){$0} == 0 && producerOK
   probe.cancel()
  }
  result["cancelReclaimsDepthAndSourceInReverseOrder"] = producerOK

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
        source.write_text(SUBMISSION_COORDINATOR_FIXTURE.split("@main",1)[0]+SCENE_DEPENDENCY_BINDING_SUPPORT+MAIN)
        scene=REPOSITORY_ROOT/"MyWallpaperX/Core/SteamWorkshopScene"
        sources=[*SUBMISSION_SWIFT_SOURCES,scene/"Rendering/Frame/SceneMetalRenderer+FrameOutcome.swift",
                 scene/"Rendering/Frame/SceneSourceUpdateTransaction.swift",
                 scene/"Rendering/Particles/SceneParticleDepthTargetPool.swift"]
        built=subprocess.run(["xcrun","--sdk","macosx","swiftc","-parse-as-library",*map(str,sources),
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
