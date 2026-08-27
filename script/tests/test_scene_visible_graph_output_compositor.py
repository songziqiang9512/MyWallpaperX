#!/usr/bin/env python3

from __future__ import annotations

import json
from pathlib import Path
import runpy
import shutil
import subprocess
import tempfile
import unittest


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
BASE_FIXTURE = runpy.run_path(
    str(Path(__file__).with_name("test_scene_framebuffer_capture.py"))
)
SWIFT_SOURCES = BASE_FIXTURE["SWIFT_SOURCES"]
BASE_HARNESS_PREFIX = BASE_FIXTURE["HARNESS_SOURCE"].split("@main", 1)[0]

SOURCE_PREPARATION = '''
        guard requests.count == 1 else {
            return .rejected(reasonCode: "fixture-frame-preparation-invalid")
        }
        preparedTexture = requests[0].sourceTexture
        return .ready
'''
DISTINCT_FINAL_PREPARATION = '''
        guard requests.count == 1 else {
            return .rejected(reasonCode: "fixture-frame-preparation-invalid")
        }
        let source = requests[0].sourceTexture
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: source.pixelFormat,
            width: source.width,
            height: source.height,
            mipmapped: false
        )
        descriptor.usage = [.shaderRead, .renderTarget]
        descriptor.storageMode = .shared
        guard let graphFinal = source.device.makeTexture(descriptor: descriptor) else {
            return .rejected(reasonCode: "fixture-graph-final-unavailable")
        }
        graphFinal.label = "fixture-distinct-graph-final"
        preparedTexture = graphFinal
        return .ready
'''
if BASE_HARNESS_PREFIX.count(SOURCE_PREPARATION) != 1:
    raise AssertionError("resolved-material preparation fixture changed")
DISTINCT_HARNESS_PREFIX = BASE_HARNESS_PREFIX.replace(
    SOURCE_PREPARATION,
    DISTINCT_FINAL_PREPARATION,
)


HARNESS = DISTINCT_HARNESS_PREFIX + r'''
private typealias Graph = SceneAuthoredEffectRenderPlan

private enum TestFailure: Error {
    case metalUnavailable
    case drawRefused
}

private func texture(
    device: MTLDevice,
    size: Int,
    usage: MTLTextureUsage
) -> MTLTexture? {
    let descriptor = MTLTextureDescriptor.texture2DDescriptor(
        pixelFormat: .bgra8Unorm,
        width: size,
        height: size,
        mipmapped: false
    )
    descriptor.usage = usage
    descriptor.storageMode = .shared
    return device.makeTexture(descriptor: descriptor)
}

private func graph(layerID: Int) -> Graph {
    let effectKey = Graph.EffectKey(
        layerID: layerID,
        effectIndex: 0,
        descriptorID: "\(layerID)#effect#0"
    )
    let input = Graph.TextureIdentity(
        kind: .layerSource,
        layerID: layerID,
        effect: nil,
        name: nil
    )
    let output = Graph.TextureIdentity(
        kind: .effectOutput,
        layerID: layerID,
        effect: effectKey,
        name: nil
    )
    let node = Graph.Node(
        nodeIndex: 0,
        effect: effectKey,
        definitionPassIndex: 0,
        materialOrdinal: 0,
        instancePassIndex: 0,
        kind: .material,
        materialPath: "materials/effects/xray.json",
        materialPassID: "materials/effects/xray.json#0",
        target: output,
        bindings: [],
        commandSource: nil,
        commandTarget: nil,
        compose: nil,
        conditions: nil
    )
    let effect = Graph.Effect(
        key: effectKey,
        definitionPath: "effects/xray/effect.json",
        input: input,
        output: output,
        nodeIndices: [node.nodeIndex]
    )
    return .init(
        layerID: layerID,
        effects: [effect],
        renderTargets: [],
        nodes: [node],
        finalOutput: output,
        blockers: []
    )
}

@main
private enum VisibleGraphOutputCompositorHarness {
    static func main() throws {
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue(),
              let pipeline = SceneImageLayerPipeline(device: device) else {
            print("{\"metalAvailable\":false}")
            return
        }
        let layerID = 0
        let graph = graph(layerID: layerID)
        let pairPlan: SceneLayerFullFramePairPlan
        switch SceneLayerFullFramePairPlan.make(conditionPrunedGraphs: [graph]) {
        case let .success(value):
            pairPlan = value
        case .failure:
            throw TestFailure.drawRefused
        }
        let claim = SceneResolvedMaterialRuntimeBridge.ClaimedExecution(
            token: .init(rawValue: 1),
            layerID: layerID,
            admittedGraphs: [graph],
            targetExecutionPlans: [],
            pairPlan: pairPlan,
            fullFrameExtentPolicy: .standard,
            sourceRoute: .capturedLayerTexture,
            dependencyOwnership: .none
        )
        let size = 8
        guard let source = texture(
                  device: device,
                  size: size,
                  usage: .shaderRead
              ), let target = texture(
                  device: device,
                  size: size,
                  usage: [.renderTarget, .shaderRead]
              ), let commandBuffer = queue.makeCommandBuffer() else {
            throw TestFailure.metalUnavailable
        }
        source.label = "fixture-raw-source"
        let pool = SceneOffscreenTexturePool(device: device, maxDimension: size)
        let preflight = SceneResolvedMaterialGraphComposition.preflight(
            requests: [.init(
                claim: claim,
                fullFrameExtentPolicy: claim.fullFrameExtentPolicy,
                requestedWidth: size,
                requestedHeight: size
            )],
            pool: pool,
            commandBuffer: commandBuffer
        )
        guard case let .ready(plans, _) = preflight,
              let framePlan = plans[layerID] else {
            throw TestFailure.drawRefused
        }
        let runtime = SceneResolvedMaterialRuntimeBridge(
            claimedExecution: claim
        )
        guard case .ready = runtime.prepareFrame(
            [.init(
                claim: claim,
                targetPlan: framePlan,
                sourceTexture: source,
                sourceUniforms: .neutral(),
                sourcePipeline: pipeline
            )],
            pool: pool,
            commandBuffer: commandBuffer
        ) else {
            throw TestFailure.drawRefused
        }
        let layer = SceneRenderDescriptor.Layer(
            contentKind: "image",
            colorRGB: nil,
            colorBlendMode: nil,
            effects: []
        )
        let request = SceneImageLayerDrawRequest(
            layer: layer,
            texture: source,
            masks: .empty,
            textureFrame: .identity,
            mvp: SceneMatrix.scale(SIMD3<Float>(2, 2, 1)),
            uniforms: .init(time: 0, alpha: 1, cursorUV: .zero),
            offscreenTexturePool: pool,
            resolvedMaterialFrameTargetPlan: framePlan,
            offscreenSize: nil,
            requiresSourceCopy: false,
            finalCompositeAlpha: nil,
            dependencyEffect: nil
        )
        let compositor = SceneImageLayerCompositor(
            pipelineRepository: SceneImageEffectPipelineRepository(device: device),
            resolvedMaterialRuntime: runtime
        )
        let mainPass = SceneMainPassEncoder(
            commandBuffer: commandBuffer,
            target: target,
            clearColor: MTLClearColorMake(0, 0, 0, 0)
        )
        var publisherCallCount = 0
        var receivedDistinctGraphFinal = false
        let outcome = compositor.drawOutcome(
            request,
            explicitLayerSourcePublication: nil,
            resolvedMaterialGraphOutputPublisher: { published in
                publisherCallCount += 1
                receivedDistinctGraphFinal = published !== source
                    && published.label == "fixture-distinct-graph-final"
                return receivedDistinctGraphFinal
            },
            pipeline: pipeline,
            mainPass: mainPass
        )
        mainPass.finishEnsuringClear()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        let composited: Bool
        if case .normal(consumedDependency: false) = outcome {
            composited = true
        } else {
            composited = false
        }
        let result: [String: Any] = [
            "metalAvailable": true,
            "publisherCallCount": publisherCallCount,
            "receivedDistinctGraphFinal": receivedDistinctGraphFinal,
            "composited": composited,
            "compositeCallCount": runtime.markCompositeCallCount,
            "gpuCompleted": commandBuffer.status == .completed
                && commandBuffer.error == nil,
        ]
        let data = try JSONSerialization.data(
            withJSONObject: result,
            options: [.sortedKeys]
        )
        print(String(decoding: data, as: UTF8.self))
    }
}
'''


@unittest.skipUnless(shutil.which("swiftc"), "swiftc is required")
class SceneVisibleGraphOutputCompositorTests(unittest.TestCase):
    def test_publisher_receives_distinct_graph_final_instead_of_raw_source(
        self,
    ) -> None:
        with tempfile.TemporaryDirectory(
            prefix="mwx-visible-graph-output-compositor-"
        ) as directory:
            root = Path(directory)
            harness = root / "Harness.swift"
            binary = root / "visible-graph-output-compositor"
            harness.write_text(HARNESS, encoding="utf-8")
            compilation = subprocess.run(
                [
                    "xcrun",
                    "--sdk",
                    "macosx",
                    "swiftc",
                    *(str(path) for path in SWIFT_SOURCES),
                    str(harness),
                    "-framework",
                    "Metal",
                    "-o",
                    str(binary),
                ],
                cwd=REPOSITORY_ROOT,
                capture_output=True,
                text=True,
            )
            self.assertEqual(compilation.returncode, 0, compilation.stderr)
            completed = subprocess.run(
                [str(binary)],
                cwd=REPOSITORY_ROOT,
                check=True,
                capture_output=True,
                text=True,
            )
            result = json.loads(completed.stdout)
            if not result["metalAvailable"]:
                self.skipTest("Metal device unavailable")
            self.assertEqual(
                result,
                {
                    "metalAvailable": True,
                    "publisherCallCount": 1,
                    "receivedDistinctGraphFinal": True,
                    "composited": True,
                    "compositeCallCount": 1,
                    "gpuCompleted": True,
                },
            )


if __name__ == "__main__":
    unittest.main()
