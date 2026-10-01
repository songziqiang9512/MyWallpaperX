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
 static func main() throws {
  let device = MTLCreateSystemDefaultDevice()!
  var result:[String:Bool] = [:]
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
  var cache:CVMetalTextureCache?
  CVMetalTextureCacheCreate(nil,nil,device,nil,&cache)
  let importedBudget=SceneResourceBudget(maximumBytes:1_048_576)
  autoreleasepool {
   var pixel:CVPixelBuffer?
   CVPixelBufferCreate(nil,64,64,kCVPixelFormatType_32BGRA,
      [kCVPixelBufferMetalCompatibilityKey:true,kCVPixelBufferIOSurfacePropertiesKey:[:]] as CFDictionary,&pixel)
   let first=SceneResourceAllocation.importVideo(pixel!,cache:cache!,budget:importedBudget)!
   let before=importedBudget.snapshot.residentBytes
   let second=SceneResourceAllocation.importVideo(pixel!,cache:cache!,budget:importedBudget)!
   result["sharedVideoBackingCountedOnce"] = CVMetalTextureGetTexture(first) != nil && CVMetalTextureGetTexture(second) != nil
     && before == importedBudget.snapshot.residentBytes
  }
  CVMetalTextureCacheFlush(cache!,0);cache=nil
  result["importedBackingReleased"] = importedBudget.snapshot.residentBytes == 0
  print(String(data:try JSONSerialization.data(withJSONObject:result,options:.sortedKeys),encoding:.utf8)!)
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
            for name,passed in json.loads(run.stdout).items():
                with self.subTest(name=name):self.assertTrue(passed)
