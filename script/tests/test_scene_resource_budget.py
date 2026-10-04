"""Behavior of the shared resident account, including actual Metal retention."""
from pathlib import Path
import json
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / 'MyWallpaperX/Core/SteamWorkshopScene/Resources/Textures/SceneResourceBudget.swift'
HARNESS = r'''
@main enum Harness {
 static func pixel(_ blue: UInt8) throws -> CVPixelBuffer {
  var value:CVPixelBuffer?
  let status=CVPixelBufferCreate(nil,64,64,kCVPixelFormatType_32BGRA,
   [kCVPixelBufferMetalCompatibilityKey:true,kCVPixelBufferIOSurfacePropertiesKey:[:]] as CFDictionary,&value)
  guard status == kCVReturnSuccess, let value,
        CVPixelBufferLockBaseAddress(value,[]) == kCVReturnSuccess,
        let base=CVPixelBufferGetBaseAddress(value) else { throw NSError(domain:"pixel",code:Int(status)) }
  defer { CVPixelBufferUnlockBaseAddress(value,[]) }
  let bytes=base.assumingMemoryBound(to:UInt8.self), stride=CVPixelBufferGetBytesPerRow(value)
  for y in 0..<64 { for x in 0..<64 {
   let offset=y*stride+x*4
   bytes[offset]=blue;bytes[offset+1]=33;bytes[offset+2]=65;bytes[offset+3]=255
  } }
  return value
 }
 static func cache(_ device:MTLDevice) throws -> CVMetalTextureCache {
  var value:CVMetalTextureCache?
  let status=CVMetalTextureCacheCreate(nil,nil,device,nil,&value)
  guard status == kCVReturnSuccess, let value else { throw NSError(domain:"cache",code:Int(status)) }
  return value
 }
 static func copy(_ texture:MTLTexture, to buffer:MTLBuffer, command:MTLCommandBuffer) {
  let blit=command.makeBlitCommandEncoder()!
  blit.copy(from:texture,sourceSlice:0,sourceLevel:0,sourceOrigin:MTLOrigin(x:0,y:0,z:0),
   sourceSize:MTLSize(width:64,height:64,depth:1),to:buffer,destinationOffset:0,
   destinationBytesPerRow:256,destinationBytesPerImage:16_384)
  blit.endEncoding()
 }
 static func hasPixels(_ buffer:MTLBuffer, blue:UInt8) -> Bool {
  let bytes=buffer.contents().assumingMemoryBound(to:UInt8.self)
  return (0..<4096).allSatisfy { offset in
   let index=offset*4
   return bytes[index] == blue && bytes[index+1] == 33 && bytes[index+2] == 65 && bytes[index+3] == 255
  }
 }
 static func main() throws {
  let device = MTLCreateSystemDefaultDevice()!
  var result:[String:Bool] = [:]
  var diagnostics:[String:Int] = [:]
  let concurrent = SceneResourceBudget(maximumBytes: 1024)
  DispatchQueue.concurrentPerform(iterations: 100) { _ in
   _ = concurrent.reserve(64, kind: .gpu)
  }
  result["concurrentAdmissionIsAtomic"] = concurrent.snapshot.residentBytes == 1024 && concurrent.snapshot.rejectionCount == 84
  concurrent.release(1024, kind: .gpu)
  result["negativeAndOverflowRejected"] = !concurrent.reserve(-1, kind: .gpu) && !concurrent.reserve(Int.max, kind: .gpu)
  result["decodedSharesParent"] = concurrent.reserve(256, kind: .decoded)
      && !concurrent.reserve(1, kind: .decoded) && !concurrent.reserve(769, kind: .gpu)
      && concurrent.reserve(768, kind: .gpu)
  concurrent.release(768, kind: .gpu); concurrent.release(256, kind: .decoded)
  result["decodedReleaseBalances"] = concurrent.snapshot.residentBytes == 0 && concurrent.snapshot.decodedBytes == 0
  let failed:MTLBuffer? = SceneResourceAllocation.make(bytes:64,budget:concurrent) { nil }
  result["failedNativeAllocationReturnsReservation"] = failed == nil && concurrent.snapshot.residentBytes == 0
  let byteCost = device.heapBufferSizeAndAlign(length:4096,options:.storageModeShared).size
  let budget = SceneResourceBudget(maximumBytes:byteCost)
  let queue = device.makeCommandQueue()!
  let event = device.makeSharedEvent()!
  var command:MTLCommandBuffer?
  autoreleasepool {
   let buffer = device.makeSceneBuffer(length:4096,options:.storageModeShared,budget:budget)!
   result["secondSurfaceCannotMultiplyBudget"] = device.makeSceneBuffer(length:4096,options:.storageModeShared,budget:budget) == nil
   command=queue.makeCommandBuffer()!
   command!.encodeWaitForEvent(event,value:1)
   let blit=command!.makeBlitCommandEncoder()!
   blit.fill(buffer:buffer,range:0..<4096,value:29);blit.endEncoding()
   command!.commit()
  }
  result["ownerRemovalDoesNotReleaseInFlightResource"] = budget.snapshot.residentBytes == byteCost
  event.signaledValue=1
  command!.waitUntilCompleted()
  result["realGPUCompleted"] = command!.status == .completed
  command=nil
  result["terminalFinalReleaseReturnsBudget"] = budget.snapshot.residentBytes == 0
  autoreleasepool {
   let next=device.makeSceneBuffer(length:4096,options:.storageModeShared,budget:budget)
   result["recoveryAfterRelease"] = next != nil
  }
  result["allReleased"] = budget.snapshot.residentBytes == 0
  let importedCache=try cache(device)
  let importedBudget=SceneResourceBudget(maximumBytes:1_048_576)
  try autoreleasepool {
   let backing=try pixel(17)
   let first=SceneResourceAllocation.importVideo(backing,cache:importedCache,budget:importedBudget)!
   let before=importedBudget.snapshot.residentBytes
   let second=SceneResourceAllocation.importVideo(backing,cache:importedCache,budget:importedBudget)!
   withExtendedLifetime((first,second)) {
    result["sharedVideoBackingCountedOnce"] = before == CVPixelBufferGetDataSize(backing)
      && before == importedBudget.snapshot.residentBytes
   }
  }
  CVMetalTextureCacheFlush(importedCache,0)
  result["importedBackingReleasedWithCacheAlive"] = withExtendedLifetime(importedCache) { importedBudget.snapshot.residentBytes == 0 }
  let frameBytes=try autoreleasepool { CVPixelBufferGetDataSize(try pixel(0)) }
  diagnostics["videoFrameBytes"]=frameBytes
  for flush in [false,true] {
   let videoCache=try cache(device), videoBudget=SceneResourceBudget(maximumBytes:frameBytes*4)
   var current:MTLTexture?, accepted=0, firstFailure=0, peak=0
   for index in 0..<100 {
    let next=try autoreleasepool { () -> MTLTexture? in
     if flush { CVMetalTextureCacheFlush(videoCache,0) }
     let next=SceneResourceAllocation.importVideo(try pixel(UInt8(index)),cache:videoCache,budget:videoBudget)
     peak=max(peak,videoBudget.snapshot.residentBytes)
     return next
    }
    guard let next else { firstFailure=index+1;break }
    current=next;accepted+=1
   }
   let label=flush ? "videoStreamFlush" : "videoStreamDefault"
   diagnostics[label+"Accepted"]=accepted;diagnostics[label+"FirstFailure"]=firstFailure;diagnostics[label+"Peak"]=peak
   withExtendedLifetime(current) { result[label+"CurrentRetained"] = videoBudget.snapshot.residentBytes == frameBytes }
   current=nil;CVMetalTextureCacheFlush(videoCache,0)
   result[label+"AllFramesAdmitted"] = accepted == 100 && firstFailure == 0 && peak <= videoBudget.maximumBytes
   result[label+"RetiredFramesReleasedWithCacheAlive"] = withExtendedLifetime(videoCache) { videoBudget.snapshot.residentBytes == 0 }
  }
  let heldCache=try cache(device), heldBudget=SceneResourceBudget(maximumBytes:frameBytes*4)
  let oldReadback=device.makeBuffer(length:16_384,options:.storageModeShared)!
  let currentReadback=device.makeBuffer(length:16_384,options:.storageModeShared)!
  let videoEvent=device.makeSharedEvent()!
  var blocked:MTLCommandBuffer?, current:MTLTexture?
  try autoreleasepool {
   let old=SceneResourceAllocation.importVideo(try pixel(17),cache:heldCache,budget:heldBudget)!
   blocked=queue.makeCommandBuffer()!
   blocked!.encodeWaitForEvent(videoEvent,value:1)
   copy(old,to:oldReadback,command:blocked!);blocked!.commit()
  }
  defer { videoEvent.signaledValue=1;blocked?.waitUntilCompleted() }
  CVMetalTextureCacheFlush(heldCache,0)
  result["videoGPUBlockedOwnerRetainsBacking"] = heldBudget.snapshot.residentBytes == frameBytes
  var accepted=0, firstFailure=0, peak=heldBudget.snapshot.residentBytes
  for index in 0..<100 {
   let next=try autoreleasepool { () -> MTLTexture? in
    CVMetalTextureCacheFlush(heldCache,0)
    let next=SceneResourceAllocation.importVideo(try pixel(UInt8(index)),cache:heldCache,budget:heldBudget)
    peak=max(peak,heldBudget.snapshot.residentBytes)
    return next
   }
   guard let next else { firstFailure=index+1;break }
   current=next;accepted+=1
  }
  diagnostics["videoBlockedAccepted"]=accepted;diagnostics["videoBlockedFirstFailure"]=firstFailure;diagnostics["videoBlockedPeak"]=peak
  result["videoBlockedStreamAllFramesAdmitted"] = accepted == 100 && firstFailure == 0 && peak <= heldBudget.maximumBytes
  withExtendedLifetime(current) { result["videoOnlyCurrentAndGPUOldRemain"] = heldBudget.snapshot.residentBytes == frameBytes*2 }
  try autoreleasepool {
   let first=SceneResourceAllocation.importVideo(try pixel(201),cache:heldCache,budget:heldBudget)!
   let second=SceneResourceAllocation.importVideo(try pixel(202),cache:heldCache,budget:heldBudget)!
   let rejectedBacking=try pixel(203), priorRejections=heldBudget.snapshot.rejectionCount
   withExtendedLifetime((current,first,second)) {
    result["videoFullBudgetRejectsExtraFrame"] = heldBudget.snapshot.residentBytes == frameBytes*4
      && SceneResourceAllocation.importVideo(rejectedBacking,cache:heldCache,budget:heldBudget) == nil
      && heldBudget.snapshot.residentBytes == frameBytes*4
      && heldBudget.snapshot.rejectionCount == priorRejections+1
   }
  }
  CVMetalTextureCacheFlush(heldCache,0)
  result["videoRejectedAdmissionPreservesExistingOwners"] = heldBudget.snapshot.residentBytes == frameBytes*2
  var finalCommand:MTLCommandBuffer?
  autoreleasepool {
   finalCommand=queue.makeCommandBuffer()!
   if let current { copy(current,to:currentReadback,command:finalCommand!) }
   finalCommand!.commit();videoEvent.signaledValue=1
   blocked!.waitUntilCompleted();finalCommand!.waitUntilCompleted()
   result["videoGPUCommandsCompleted"] = blocked!.status == .completed && finalCommand!.status == .completed
   result["videoBudgetRejectionDidNotDamageGPUOldPixels"] = hasPixels(oldReadback,blue:17)
   result["videoCurrentPixelsSurviveRepeatedFlush"] = accepted == 100 && hasPixels(currentReadback,blue:99)
  }
  blocked=nil;finalCommand=nil;CVMetalTextureCacheFlush(heldCache,0)
  withExtendedLifetime(current) { result["videoGPUCompletionRetiresOnlyOldFrame"] = heldBudget.snapshot.residentBytes == frameBytes }
  current=nil;CVMetalTextureCacheFlush(heldCache,0)
  result["videoAllOwnersReleasedWithCacheAlive"] = withExtendedLifetime(heldCache) { heldBudget.snapshot.residentBytes == 0 }
  print(String(data:try JSONSerialization.data(withJSONObject:["checks":result,"diagnostics":diagnostics],options:.sortedKeys),encoding:.utf8)!)
 }
}
'''

class SceneResourceBudgetTests(unittest.TestCase):
    def test_atomic_admission_and_real_gpu_lifetime(self):
        with tempfile.TemporaryDirectory(prefix='mwx-resource-budget-') as temp:
            path=Path(temp); source=path/'Harness.swift';binary=path/'test'
            source.write_text(SOURCE.read_text()+HARNESS)
            compiled=subprocess.run(['xcrun','swiftc','-parse-as-library',str(source),'-o',str(binary)],capture_output=True,text=True)
            self.assertEqual(compiled.returncode,0,compiled.stderr)
            run=subprocess.run([str(binary)],capture_output=True,text=True,timeout=30)
            self.assertEqual(run.returncode,0,run.stderr)
            output=json.loads(run.stdout)
            print('Scene video residency diagnostics: '+json.dumps(output['diagnostics'],sort_keys=True))
            for name,passed in output['checks'].items():
                with self.subTest(name=name):self.assertTrue(passed,json.dumps(output['diagnostics'],sort_keys=True))
