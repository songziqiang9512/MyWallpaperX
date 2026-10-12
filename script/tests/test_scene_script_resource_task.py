"""CPU-only original resource-task condition/handoff lifecycle.

The actual task class is compiled with a controlled preparation backend. No
Metal device, upload, texture decoder or draw is used by this gate.
"""
from pathlib import Path
import json
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Runtime/Session/ScenePreparedDeviceResources.swift"

STUBS = r'''
import Foundation
struct MTLDevice {}
struct SceneResourceView {}
struct SceneAssetCatalog { struct ModelAsset {} }
struct SceneTextureUploadCommandQueue {}
struct SceneTextureDecodeCacheBudget { init(maximumBytes: Int) {} }
struct SceneRenderDescriptor {
    struct Layer { let contentKind: String; let colorBlendMode: Int? }
    struct Format { var metalPixelFormat: Int { 0 } }
    var layers: [Layer] = []
    var colorTargetFormat = Format()
}
enum SceneDesktopWallpaperHostLaunchError: Error { case requiredImagePipelineUnavailable }
struct SceneImageLayerPipeline {
    init?(device: MTLDevice, pixelFormat: Int) { if Backend.rejectPipeline { return nil } }
}
struct SceneImageEffectPipelineRepository {
    init(device: MTLDevice, pixelFormat: Int) {}
    func prepareDirectDraw() -> Bool { true }
    func layerColorBlendState() -> Int { 0 }
}
struct SceneMultiImageSpriteTextureLoader {}
struct Loader { func evictDecodedCaches() {} }
struct ScenePreparedBaseImageResources {
    let textureLoader = Loader()
    let models: Set<String>
    static func prepare(descriptor: SceneRenderDescriptor, resourceView: SceneResourceView,
        device: MTLDevice, spriteTextureLoader: SceneMultiImageSpriteTextureLoader,
        sceneGeneration: UInt64, dynamicImageModelPathsProvider: (() throws -> Set<String>)?,
        deferredBaseImageLayerIDs: Set<Int>, imageGeometryModels: [SceneAssetCatalog.ModelAsset],
        geometryPrepared: ([Int: [Float]]) -> Void, uploadCommandQueue: SceneTextureUploadCommandQueue,
        decodeCacheBudget: SceneTextureDecodeCacheBudget, cancellationCheck: () throws -> Void) throws -> Self {
        geometryPrepared([17:[200,100]])
        Backend.entered.signal()
        let models = try dynamicImageModelPathsProvider!()
        try cancellationCheck()
        return .init(models: models)
    }
}
struct ScenePreparedStaticModelResources {
    static func prepare(descriptor: SceneRenderDescriptor, resourceView: SceneResourceView,
        device: MTLDevice, textureLoader: Loader, cancellationCheck: () throws -> Void) throws -> Self {
        try cancellationCheck(); return .init()
    }
}
struct ScenePreparedDeviceResources {
    let pipelineRepository: SceneImageEffectPipelineRepository
    let imageLayerPipeline: SceneImageLayerPipeline
    let spriteTextureLoader: SceneMultiImageSpriteTextureLoader
    let baseImages: ScenePreparedBaseImageResources
    let staticModels: ScenePreparedStaticModelResources
}
enum Backend { static var rejectPipeline = false; static let entered = DispatchSemaphore(value: 0) }
'''

HARNESS = r'''
@main enum Harness {
    static func task(_ waiting: Bool = true, models: Set<String> = []) -> ScenePreparedDeviceResourcesTask {
        .init(descriptor: .init(), resourceView: .init(), device: .init(), sceneGeneration: 1,
            dynamicImageModelPaths: models, awaitsScriptResourcePlanning: waiting, cancellationCheck: {})
    }
    static func main() throws {
        var out: [String: Any] = [:]
        let t = task(); t.start()
        out["metadata"] = try t.preparedImageGeometry()[17] == [200,100]
        out["waitingReached"] = Backend.entered.wait(timeout: .now()+2) == .success
        t.completeScriptResourcePlanning(["models/a.json", "models/b.json"])
        out["plannedModels"] = try t.value().baseImages.models.sorted()
        let empty = task(); empty.start()
        _ = try empty.preparedImageGeometry(); _ = Backend.entered.wait(timeout: .now()+2)
        empty.completeScriptResourcePlanning([])
        out["emptyCompleted"] = try empty.value().baseImages.models.isEmpty
        let failedProgram = task(); failedProgram.start()
        _ = try failedProgram.preparedImageGeometry(); _ = Backend.entered.wait(timeout: .now()+2)
        failedProgram.cancel()
        do { _ = try failedProgram.value(); out["cancelJoined"] = false }
        catch is CancellationError { out["cancelJoined"] = true }
        let early = task(); Backend.rejectPipeline = true; early.start()
        do { _ = try early.preparedImageGeometry(); out["earlyMetadataFailure"] = false }
        catch { out["earlyMetadataFailure"] = true }
        do { _ = try early.value(); out["earlyJoinFailure"] = false }
        catch { out["earlyJoinFailure"] = true }
        Backend.rejectPipeline = false
        let legacy = task(false, models: ["models/legacy.json"]); legacy.start()
        _ = try legacy.preparedImageGeometry(); _ = Backend.entered.wait(timeout: .now()+2)
        out["existingPreplannedModels"] = try legacy.value().baseImages.models.sorted()
        print(String(decoding: try JSONSerialization.data(withJSONObject: out, options:[.sortedKeys]), as:UTF8.self))
    }
}
'''

class SceneScriptResourceTaskTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        work = tempfile.TemporaryDirectory(prefix="mwx-resource-task-cpu-")
        cls.addClassCleanup(work.cleanup)
        root = Path(work.name)
        task = SOURCE.read_text().split("final class ScenePreparedDeviceResourcesTask {",1)[1].split("/// Prepares exactly one surface-scoped",1)[0]
        source = root / "Task.swift"
        source.write_text(STUBS+"\nfinal class ScenePreparedDeviceResourcesTask {"+task+HARNESS)
        compile = subprocess.run(["xcrun","swiftc","-swift-version","5","-parse-as-library",str(source),"-o",str(root/"task")],
            capture_output=True,text=True,timeout=60)
        if compile.returncode:
            raise AssertionError(compile.stdout+compile.stderr)
        run = subprocess.run([str(root/"task")],capture_output=True,text=True,timeout=10)
        if run.returncode:
            raise AssertionError(run.stdout+run.stderr)
        cls.facts=json.loads(run.stdout)

    def test_same_worker_receives_successful_final_demand_after_metadata(self):
        self.assertTrue(self.facts["metadata"])
        self.assertTrue(self.facts["waitingReached"])
        self.assertEqual(self.facts["plannedModels"],["models/a.json","models/b.json"])
        self.assertEqual(self.facts["existingPreplannedModels"],["models/legacy.json"])

    def test_empty_final_program_demand_completes_without_waiting_forever(self):
        self.assertTrue(self.facts["emptyCompleted"])

    def test_program_failure_cancel_and_pipeline_early_failure_release_original_join(self):
        for key in ("cancelJoined","earlyMetadataFailure","earlyJoinFailure"):
            self.assertTrue(self.facts[key],key)
