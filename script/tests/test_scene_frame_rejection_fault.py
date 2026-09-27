"""Real coordinator seal rejection is one-shot and absent from release builds."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

from .test_scene_resolved_material_runtime_bridge import (
    SUBMISSION_COORDINATOR_FIXTURE, SUBMISSION_SWIFT_SOURCES, SCENE_DEPENDENCY_BINDING_SUPPORT,
)

MAIN = r'''
final class FaultLogs: @unchecked Sendable {
    let lock=NSLock();var lines:[String]=[]
    func append(_ line:String){lock.lock();lines.append(line);lock.unlock()}
    func snapshot()->[String]{lock.lock();defer{lock.unlock()};return lines}
}
@main enum Harness {
    static func main() throws {
        guard let device=MTLCreateSystemDefaultDevice(),
              let queue=device.makeCommandQueue() else {
            print("{\"metalAvailable\":false}");return
        }
        let logs=FaultLogs()
        let coordinator=makeCoordinator(device,logSink:{logs.append($0)})
        var accepted:[Bool]=[], unsubmitted:[Bool]=[], retryable:[Bool]=[]
        for index:UInt64 in [0,0,1,2,2,3] {
            let buffer=queue.makeCommandBuffer()!
            coordinator.beginFrame(textureSnapshot:.init(frameIndex:index,valid:true),
                dynamicSnapshot:.init(),frameInputs:.init())
            _ = coordinator.prepareFrame([],pool:nil,commandBuffer:buffer)
            accepted.append(coordinator.sealFrame(on:buffer))
            unsubmitted.append(buffer.status == .notEnqueued)
            _ = coordinator.endFrame()
            retryable.append(!coordinator.shouldDeferFrame && coordinator.activeByID.isEmpty
                && coordinator.pendingSubmissions.isEmpty)
            if accepted.last == true {buffer.commit();buffer.waitUntilCompleted()}
        }
        print(String(decoding:try JSONSerialization.data(withJSONObject:[
            "metalAvailable":true,"accepted":accepted,"unsubmitted":unsubmitted,
            "retryable":retryable,"diagnostics":logs.snapshot()]),as:UTF8.self))
    }
}
'''


class SceneFrameRejectionFaultTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temp = tempfile.TemporaryDirectory(prefix="scene-frame-rejection-")
        root=Path(cls.temp.name)
        source=root/"Harness.swift"
        source.write_text(SUBMISSION_COORDINATOR_FIXTURE.split("@main",1)[0]+SCENE_DEPENDENCY_BINDING_SUPPORT+MAIN)
        cls.binaries={}
        for mode in ("debug","release"):
            binary=root/mode
            command=["xcrun","--sdk","macosx","swiftc","-parse-as-library"]
            if mode=="debug": command += ["-DDEBUG"]
            command += [*map(str,SUBMISSION_SWIFT_SOURCES),str(source),"-framework","Metal",
                        "-module-cache-path",str(root/"module-cache"),"-o",str(binary)]
            result=subprocess.run(command,capture_output=True,text=True)
            if result.returncode: raise AssertionError(result.stdout+result.stderr)
            cls.binaries[mode]=binary

    @classmethod
    def tearDownClass(cls): cls.temp.cleanup()

    def run_case(self, request, evidence=True, mode="debug"):
        env=os.environ.copy()
        env.pop("MWX_SCENE_DEBUG_REJECT_FRAME_ONCE",None)
        if request is not None: env["MWX_SCENE_DEBUG_REJECT_FRAME_ONCE"]=request
        args=[str(self.binaries[mode])]
        if evidence: args += ["--mwx-debug-scene-evidence-dir",self.temp.name]
        result=subprocess.run(args,env=env,capture_output=True,text=True,timeout=30)
        self.assertEqual(result.returncode,0,result.stdout+result.stderr)
        value=json.loads(result.stdout.strip().splitlines()[-1])
        if not value["metalAvailable"]: self.skipTest("Metal device unavailable")
        self.assertEqual(value["unsubmitted"],[True]*6)
        self.assertEqual(value["retryable"],[True]*6)
        fault_lines=[line for line in value["diagnostics"] if "phase=frame-seal-fault" in line]
        if request in ("0","2") and evidence and mode=="debug":
            self.assertEqual(len(fault_lines),5)
            self.assertEqual(sum("state=rejected" in line for line in fault_lines),1)
            self.assertEqual(sum("state=retry-sealed" in line for line in fault_lines),1)
            self.assertEqual(sum(f"state=retry-completed frame={request} gpu=completed" in line for line in fault_lines),1)
            self.assertEqual(sum(f"state=next-frame-completed frame={int(request)+1} gpu=completed" in line for line in fault_lines),1)
            self.assertEqual(sum("state=next-frame-sealed" in line for line in fault_lines),1)
        else: self.assertEqual(fault_lines,[])
        return value["accepted"]

    def test_rejection_consumes_request_before_same_index_retry(self):
        self.assertEqual(self.run_case("2"),[True,True,True,False,True,True])

    def test_first_frame_zero_can_be_rejected(self):
        self.assertEqual(self.run_case("0"),[False,True,True,True,True,True])

    def test_missing_evidence_window_cannot_activate_fault(self):
        self.assertEqual(self.run_case("2",evidence=False),[True]*6)

    def test_release_build_ignores_fault_request(self):
        self.assertEqual(self.run_case("2",mode="release"),[True]*6)

    def test_absent_or_invalid_requests_do_not_reject_frames(self):
        for request in (None,"-1","bad","18446744073709551616"):
            with self.subTest(request=request):
                self.assertEqual(self.run_case(request),[True]*6)

    def test_other_frame_index_does_not_reject_earlier_frames(self):
        self.assertEqual(self.run_case("4"),[True]*6)
