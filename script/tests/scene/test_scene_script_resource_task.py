"""CPU-only original resource-task condition/handoff lifecycle.

The actual task class is compiled with a controlled preparation backend. No
Metal device, upload, texture decoder or draw is used by this gate.
"""
from pathlib import Path
import hashlib
import json
import os
import subprocess
import tempfile
import unittest
from script.tests.scene.test_scene_prepared_script_resource_catalog import swift_declaration

ROOT = Path(__file__).resolve().parents[3]
SOURCE = ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Runtime/Session/ScenePreparedDeviceResourcesTask.swift"
QUALITY = ROOT / "MyWallpaperX/Core/PlaybackControl/PlaybackPerformanceProfile.swift"

STUBS = r'''
import Foundation
struct MTLDevice {}
struct SceneResourceView {}
enum SceneUserPropertyValue {}
struct SceneAssetCatalog { struct ModelAsset {} }
struct SceneTextureUploadCommandQueue {}
struct SceneTextureDecodeCacheBudget { init(maximumBytes: Int) {} }
struct SceneRenderDescriptor {
    struct Layer { let contentKind: String; let colorBlendMode: Int? }
    struct Format { var metalPixelFormat: Int { 0 } }
    var layers: [Layer] = []
    var colorTargetFormat = Format()
    var requiresImageDepthAttachment = false
    var requiresImageAdditiveRGB = false
    var requiresImageNormalDepth = false
}
enum SceneDesktopWallpaperHostLaunchError: Error { case requiredImagePipelineUnavailable }
struct SceneImageLayerPipeline {
    init?(device: MTLDevice, pixelFormat: Int, preparesDepth: Bool, preparesAdditive: Bool, preparesNormalDepth: Bool, rasterSampleCount: Int, preparesMultisampleSeed: Bool) {
        if Backend.rejectPipeline { return nil }
    }
}
struct SceneImageEffectPipelineRepository {
    init(device: MTLDevice, pixelFormat: Int, usesSixPointQuadrature: Bool) {}
    func prepareDirectDraw() -> Bool { true }
    func preparePuppetClipping() -> Bool {
        fatalError("resource handoff must not prepare unrelated Puppet pipelines")
    }
    func layerColorBlendState() -> Int { 0 }
}
struct SceneMultiImageSpriteTextureLoader {}
struct Loader { func evictDecodedCaches() {} }
struct ScenePreparedBaseImageResources {
    struct AutomaticMipConstraints { let exactSourceCount: Int }
    struct ImagePlanning {
        let models: Set<String>
        let retainsModelDefaultAliases: Bool
        let automaticMipConstraints: AutomaticMipConstraints?
        let scalableEffectColorLayerIDs: Set<Int>
    }
    let textureLoader = Loader()
    let models: Set<String>
    let retainsModelDefaultAliases: Bool
    let automaticMipSourceCount: Int?
    let puppetClipping: [String: Int] = [:]
    static func prepare(descriptor: SceneRenderDescriptor, resourceView: SceneResourceView,
        device: MTLDevice, spriteTextureLoader: SceneMultiImageSpriteTextureLoader,
        sceneGeneration: UInt64, cacheDirectory: URL, effectivePropertyValues: [String: SceneUserPropertyValue],
        dynamicImageRequestsProvider: (() throws -> ImagePlanning)?,
        deferredBaseImageLayerIDs: Set<Int>, imageGeometryModels: [SceneAssetCatalog.ModelAsset],
        ordinaryColorMipLongEdge: Int?, automaticMipDensity: Double?,
        geometryPrepared: ([Int: [Float]]) -> Void, uploadCommandQueue: SceneTextureUploadCommandQueue,
        decodeCacheBudget: SceneTextureDecodeCacheBudget, cancellationCheck: () throws -> Void) throws -> Self {
        geometryPrepared([17:[200,100]])
        Backend.entered.signal()
        let requests = try dynamicImageRequestsProvider!()
        try cancellationCheck()
        return .init(models: requests.models, retainsModelDefaultAliases: requests.retainsModelDefaultAliases,
            automaticMipSourceCount: requests.automaticMipConstraints?.exactSourceCount)
    }
}
enum SceneMdlStaticModel { struct PreparedSource {} }
struct SceneAssetTextureIdentity: Hashable { let token: Int }
enum SceneAssetTextureLaunchState: Equatable { case ready, preparedVideo, absent }
struct ScenePreparedStaticModelResources {
    struct MaterialPlan { let token: Int; static let empty = Self(token: 0) }
    let planToken: Int
    let states: [SceneAssetTextureIdentity: SceneAssetTextureLaunchState]
    let directionalShadowDimensionLimit: Int?
    let pointVolumeEnabled: Bool
    let modelReflectionsEnabled: Bool
    static func prepare(descriptor: SceneRenderDescriptor, directionalShadowDimensionLimit: Int?,
        pointVolumeEnabled: Bool, modelReflectionsEnabled: Bool, rasterSampleCount: Int, resourceView: SceneResourceView,
        device: MTLDevice, textureLoader: Loader,
        materialPlan: MaterialPlan, albedoStates: [SceneAssetTextureIdentity: SceneAssetTextureLaunchState],
        preparedSources: inout [String: SceneMdlStaticModel.PreparedSource],
        cancellationCheck: () throws -> Void) throws -> Self {
        try cancellationCheck(); return .init(planToken: materialPlan.token, states: albedoStates,
            directionalShadowDimensionLimit: directionalShadowDimensionLimit, pointVolumeEnabled: pointVolumeEnabled,
            modelReflectionsEnabled: modelReflectionsEnabled)
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
    static func task() -> ScenePreparedDeviceResourcesTask {
        .init(descriptor: .init(), directionalShadowDimensionLimit: 1024,
            pointVolumeQuality: .disabled, modelReflectionsEnabled: false, resourceView: .init(), device: .init(), sceneGeneration: 1,
            cacheDirectory: URL(fileURLWithPath: "/unused-resource-task-cache", isDirectory: true),
            cancellationCheck: {})
    }
    static func main() throws {
        var out: [String: Any] = [:]
        let t = task(); t.start()
        out["metadata"] = try t.preparedImageGeometry()[17] == [200,100]
        out["waitingReached"] = Backend.entered.wait(timeout: .now()+2) == .success
        let states: [SceneAssetTextureIdentity: SceneAssetTextureLaunchState] = [
            .init(token: 1): .ready, .init(token: 2): .preparedVideo, .init(token: 3): .absent]
        t.completeResourcePlanning(.init(dynamicImageModelPaths: ["models/a.json", "models/b.json"],
            hasStatefulLayerMutationOwner: true, automaticMipConstraints: .init(exactSourceCount: 4),
            modelMaterialPlan: .init(token: 73), modelAlbedoStates: states))
        let prepared = try t.value()
        out["plannedModels"] = prepared.baseImages.models.sorted()
        out["samePlanningPayload"] = prepared.baseImages.retainsModelDefaultAliases
            && prepared.baseImages.automaticMipSourceCount == 4
            && prepared.staticModels.planToken == 73 && prepared.staticModels.states == states
            && prepared.staticModels.directionalShadowDimensionLimit == 1024
            && !prepared.staticModels.pointVolumeEnabled && !prepared.staticModels.modelReflectionsEnabled
        let empty = task(); empty.start()
        _ = try empty.preparedImageGeometry(); _ = Backend.entered.wait(timeout: .now()+2)
        empty.completeResourcePlanning(.init(dynamicImageModelPaths: [], modelMaterialPlan: .empty, modelAlbedoStates: [:]))
        let emptyResult = try empty.value()
        out["emptyCompleted"] = emptyResult.baseImages.models.isEmpty
            && !emptyResult.baseImages.retainsModelDefaultAliases
            && emptyResult.staticModels.planToken == 0 && emptyResult.staticModels.states.isEmpty
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
        task = swift_declaration(SOURCE.read_text(), "final class ScenePreparedDeviceResourcesTask {")
        source = root / "Task.swift"
        source.write_text(STUBS+"\n"+task+HARNESS)
        evidence = Path(os.environ["MWX_RESOURCE_TASK_EVIDENCE"]) if os.environ.get("MWX_RESOURCE_TASK_EVIDENCE") else None
        identity = {str(path): hashlib.sha256(path.read_bytes()).hexdigest()
                    for path in [SOURCE, QUALITY, Path(__file__), Path(swift_declaration.__code__.co_filename)]}
        if evidence:
            evidence.mkdir(parents=True, exist_ok=True)
            (evidence / "Harness.swift").write_bytes(source.read_bytes())
            (evidence / "identity.json").write_text(json.dumps({"sources": identity,
                "harnessSHA256": hashlib.sha256(source.read_bytes()).hexdigest()}, indent=2))
        compile = subprocess.run(["xcrun","swiftc","-swift-version","5","-parse-as-library",str(source),str(QUALITY),"-o",str(root/"task")],
            capture_output=True,text=True,timeout=60)
        if evidence:
            (evidence / "compile.stderr").write_text(compile.stderr)
        if compile.returncode:
            raise AssertionError(compile.stdout+compile.stderr)
        run = subprocess.run([str(root/"task")],capture_output=True,text=True,timeout=10)
        if evidence:
            (evidence / "run.stdout").write_text(run.stdout)
            (evidence / "run.stderr").write_text(run.stderr)
            (evidence / "execution.json").write_text(json.dumps({"compileReturncode": compile.returncode,
                "runReturncode": run.returncode, "immutable": identity == {str(path):
                    hashlib.sha256(path.read_bytes()).hexdigest() for path in map(Path, identity)}}, indent=2))
        if run.returncode:
            raise AssertionError(run.stdout+run.stderr)
        cls.facts=json.loads(run.stdout)

    def test_same_worker_receives_successful_final_demand_after_metadata(self):
        self.assertTrue(self.facts["metadata"])
        self.assertTrue(self.facts["waitingReached"])
        self.assertEqual(self.facts["plannedModels"],["models/a.json","models/b.json"])
        self.assertTrue(self.facts["samePlanningPayload"])

    def test_empty_final_program_demand_completes_without_waiting_forever(self):
        self.assertTrue(self.facts["emptyCompleted"])

    def test_program_failure_cancel_and_pipeline_early_failure_release_original_join(self):
        for key in ("cancelJoined","earlyMetadataFailure","earlyJoinFailure"):
            self.assertTrue(self.facts[key],key)
