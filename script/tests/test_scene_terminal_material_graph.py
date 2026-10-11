"""Production terminal replay retains the last active material's real input."""
import hashlib
import json
import os
from pathlib import Path
import shutil
import unittest
from script.tests import test_scene_offscreen_texture_pool as pool_fixture
from script.tests import test_scene_resolved_material_graph_executor as graph_fixture


# Reuse the graph/compiler scaffold. Only the input shader and extent change.
HELPERS = graph_fixture.HARNESS.split('@main', 1)[0]
HELPERS = HELPERS.replace('Plan.PixelExtent(width: 2, height: 2)',
                          'Plan.PixelExtent(width: 10, height: 10)')
HELPERS = HELPERS.replace('precondition(graph.effects.count >= 2)',
                          'precondition(!graph.effects.isEmpty)', 1)
HELPERS = HELPERS.replace('private let vertexSource = """\n',
    'private let vertexSource = """\nuniform mat4 g_ModelViewProjectionMatrix;\n', 1)
HELPERS = HELPERS.replace('gl_Position = vec4(a_Position, 1.0);',
    'gl_Position = mul(vec4(a_Position, 1.0), g_ModelViewProjectionMatrix);', 1)
HELPERS = HELPERS.replace('explicitPreviousSampler: explicitPreviousSampler\n    )', r'''
        explicitPreviousSampler: explicitPreviousSampler,
        fragmentOverride: """
        varying vec2 v_TexCoord;
        uniform sampler2D g_Texture0;
        void main() {
            vec4 color = texSample2D(g_Texture0, v_TexCoord);
            \(node.nodeIndex == 0
                ? "color.rgb *= step(0.5, fract(v_TexCoord.x * 64.0));" : "")
            gl_FragColor = color;
        }
        """
    )''', 1)

# Replace publication-only adapters with the production pool/cache/residency.
PUBLICATION_SUPPORT = graph_fixture.PUBLICATION_FIXTURE['SUPPORT']
SUPPORT = graph_fixture.SUPPORT.replace(PUBLICATION_SUPPORT,
    PUBLICATION_SUPPORT.rsplit('final class SceneOffscreenTexturePool {', 1)[0], 1)
SUPPORT = SUPPORT.replace('''final class SceneGraphRenderTargetResidencyPin {
    func release() {}
}
''', '', 1)
SUPPORT = SUPPORT.replace(SUPPORT[SUPPORT.index('final class ScenePreparedPersistentGraphTargets {'):
    SUPPORT.index('extension SceneResolvedMaterialExecutionCapabilityCatalog {')], '', 1)

HARNESS = HELPERS + r'''
private func terminalChain(_ count: Int) -> Graph {
    let full = chainedGraph()
    let effects = Array(full.effects.prefix(count))
    return .init(layerID: full.layerID, effects: effects, renderTargets: [],
        nodes: Array(full.nodes.prefix(count)), finalOutput: effects.last!.output, blockers: [])
}

private func terminalCase(
    device: MTLDevice, queue: MTLCommandQueue, count: Int,
    inactive: Set<Int> = [], failed: Set<Int> = [], budget: Int = 4096
) throws -> [String: Any] {
    let graph = terminalChain(count), admitted = orderedLayerGraph(graph)
    let targets = graph.effects.map {
        SceneDynamicTarget.effectVisibility(layerID: layerID, effectIndex: $0.key.effectIndex)
    }
    let caps = capabilities(admitted, catalog: catalog(for: graph), dynamicProducers: .init(
        userProperties: Set(targets.enumerated().map {
            SceneDynamicUserPropertyProducer(propertyKey: "show\($0.offset)",
                target: $0.element, valueType: .bool)
        }), authoredFallbackTargets: Set(targets), timelineTargets: [], sceneScriptTargets: []))
    guard let claim = caps.claim(admitted), let capability = caps.resolve(claim.token),
          let executor = Executor(device: device, capabilities: caps),
          let leases = makeChainedLeases(capability, device: device) else {
        throw NSError(domain: "terminal-fixture", code: 1)
    }
    let source = makeSource(device), pipeline = makeSourcePipeline(device)
    let target = makeSource(device, width: 256, height: 64, usage: [.renderTarget])
    let pool = SceneOffscreenTexturePool(device: device, pixelFormat: .bgra8Unorm,
        residentByteBudget: budget)
    func prepare(_ command: MTLCommandBuffer, active: Bool) throws -> Executor.PreparedGraph {
        let dynamic = SceneDynamicSnapshotResolver().resolve(frameIndex: 1, generation: 1,
            definitions: targets.map { .init(target: $0, valueType: .bool, authoredValue: .bool(true)) },
            userValues: Dictionary(uniqueKeysWithValues: targets.enumerated().map {
                ($0.element, SceneDynamicValue.bool(active || !inactive.contains($0.offset)))
            })).snapshot
        return try executor.prepare(token: claim.token, leases: leases,
            historyRehydrateCopiesByEffect: [:], frame: frame(1), sourceTexture: source,
            sourceUniforms: .neutral(), sourcePipeline: pipeline, terminalReplayTarget: target,
            pool: pool, frameInputs: .init(dynamicValues: dynamic), commandBuffer: command,
            previousStates: [:], previousGraphResources: [:], effectGeneration: 1,
            resetGeneration: 1).get()
    }
    if !failed.isEmpty {
        let warm = try prepare(queue.makeCommandBuffer()!, active: true)
        for index in failed {
            executor.materialEncoder.installTestingPreparationFailure(
                .libraryCompilationRejected(diagnostic: "terminal tail regression"),
                preparedKey: warm.stages[index].programCacheKeys[0])
        }
    }
    let command = queue.makeCommandBuffer()!, prepared = try prepare(command, active: false)
    let main = SceneMainPassEncoder(commandBuffer: command, target: target,
        clearColor: .init(red: 0, green: 0, blue: 1, alpha: 1), clearEnabled: true)
    let lastActive = (0..<count).last { !inactive.contains($0) && !failed.contains($0) }
    var originalReadback: Readback?
    let copyBefore = ScenePerformanceCounterHub.shared.snapshot()[.textureCopyPasses]!
    let encoded = executor.encode(prepared, commandBuffer: command,
        stageBoundaryObserver: { index, _, buffer in
            if index == lastActive {
                originalReadback = appendReadback(leases[index].table.inputTexture, commandBuffer: buffer)
            }
            return true
        })
    let copyCount = ScenePerformanceCounterHub.shared.snapshot()[.textureCopyPasses]! - copyBefore
    let snapshotTexture: MTLTexture? = pool.allocationCache.locked {
        guard let entry = pool.allocationCache.residents[.current(.terminalInput(
            layerID: layerID, slot: 0, width: 10, height: 10))],
              case let .composition(texture, _) = entry.allocation else { return nil }
        return texture
    }
    let snapshotReadback = snapshotTexture.flatMap { appendReadback($0, commandBuffer: command) }
    let pinsBeforeCompletion = pool.allocationCache.locked {
        pool.allocationCache.residents.values.reduce(0) { $0 + $1.submissionPins.count }
    }
    let wrongCommandRejected = !executor.encodeTerminalReplay(prepared,
        mainPass: main, commandBuffer: queue.makeCommandBuffer()!)
    let hasReplay = prepared.terminalMaterialReplay != nil
    let replayEncoded = hasReplay ? executor.encodeTerminalReplay(prepared,
        mainPass: main, commandBuffer: command) : main.encodePreparedDraw { _, _ in
            { encoder in
                pipeline.bind(encoder: encoder)
                pipeline.drawLayer(texture: prepared.finalTexture, mvp: matrix_identity_float4x4,
                    uniforms: .neutral(), encoder: encoder)
            }
        }
    let finished = main.finishEnsuringClear()
    command.commit(); command.waitUntilCompleted()
    var bytes = [UInt8](repeating: 0, count: 256 * 64 * 4)
    target.getBytes(&bytes, bytesPerRow: 256 * 4,
        from: MTLRegionMake2D(0, 0, 256, 64), mipmapLevel: 0)
    let red = (64..<192).map { Int(bytes[(32 * 256 + $0) * 4 + 2]) }
    let transitions = zip(red, red.dropFirst()).filter { ($0 > 127) != ($1 > 127) }.count
    let bypassCount = inactive.union(failed).count
    let expectedPins = lastActive != nil && bypassCount > 0 && budget > 0 ? 1 : 0
    let highDensity = lastActive == 0 && hasReplay
    let snapshotMatches = expectedPins == 0 || (snapshotReadback != nil && originalReadback != nil
        && snapshotReadback!.allPixels == originalReadback!.allPixels)
    let snapshotDistinct: Bool
    if let snapshotTexture, let lastActive {
        snapshotDistinct = snapshotTexture !== leases[lastActive].table.inputTexture
            && snapshotTexture.pixelFormat == .bgra8Unorm && snapshotTexture.width == 10
            && snapshotTexture.height == 10 && snapshotTexture.mipmapLevelCount == 1
    } else { snapshotDistinct = expectedPins == 0 }
    prepared.terminalInputPins.forEach { $0.release() }

    // The same still-unsubmitted buffer/main pass isolates reset rejection.
    let staleCommand = queue.makeCommandBuffer()!
    let stale = try prepare(staleCommand, active: true)
    let staleMain = SceneMainPassEncoder(commandBuffer: staleCommand, target: target,
        clearColor: .init(red: 0, green: 0, blue: 1, alpha: 1), clearEnabled: true)
    executor.reset()
    let staleRejected = !executor.encodeTerminalReplay(stale, mainPass: staleMain,
        commandBuffer: staleCommand)
    stale.terminalInputPins.forEach { $0.release() }
    return ["transitions": transitions, "copyCount": copyCount,
        "pinCount": prepared.terminalInputPins.count, "snapshotPixels": snapshotReadback?.allPixels ?? [],
        "results": ["chainAdmitted": capability.supportsTerminalMaterialReplay,
            "sourceRemainsTenPixels": prepared.stages.allSatisfy {
                $0.inputWidth == 10 && $0.inputHeight == 10
            } && prepared.finalTexture.width == 10 && prepared.finalTexture.height == 10,
            "lastActiveDensity": lastActive == nil ? transitions == 0
                : highDensity ? transitions >= 120 : (1...20).contains(transitions),
            "sourceOrStripesPresent": lastActive == nil ? red.allSatisfy { $0 == 255 }
                : red.min()! < 16 && red.max()! > 239,
            "noActiveMaterialUsesGraph": lastActive != nil || (!hasReplay
                && prepared.terminalInputPins.isEmpty && snapshotTexture == nil),
            "necessaryCopiesOnly": copyCount == UInt64(bypassCount + expectedPins),
            "necessaryPinsOnly": prepared.terminalInputPins.count == expectedPins,
            "snapshotIsExactRealInput": snapshotMatches && snapshotDistinct,
            "pinHeldUntilCompletion": pinsBeforeCompletion == expectedPins,
            "budgetFailureUsesGraph": budget > 0 || (!hasReplay && expectedPins == 0),
            "activationIsLocal": inactive.allSatisfy {
                prepared.stages[$0].effectLocalActivationBypassReasonCode != nil
            }, "failureIsLocal": failed.allSatisfy {
                prepared.stages[$0].effectLocalFailureReasonCode == "material-pass-preparation-library-compilation"
            }, "graphEncoded": encoded, "terminalOrFallbackEncoded": replayEncoded,
            "mainFinished": finished, "gpuCompleted": command.status == .completed && command.error == nil,
            "outsideBackgroundPreserved": bytes[(32*256 + 10)*4] == 255
                && bytes[(32*256 + 10)*4 + 2] == 0,
            "wrongCommandRejected": wrongCommandRejected, "stalePreparationRejected": staleRejected]]
}

@main struct TerminalRasterHarness {
 static func main() throws {
    guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else {
        print("{\"metalAvailable\":false}"); return
    }
    let rows: [String: [String: Any]] = [
        "single": try terminalCase(device: device, queue: queue, count: 1),
        "singleInactive": try terminalCase(device: device, queue: queue, count: 1, inactive: [0]),
        "active": try terminalCase(device: device, queue: queue, count: 2),
        "inactive": try terminalCase(device: device, queue: queue, count: 2, inactive: [1]),
        "failed": try terminalCase(device: device, queue: queue, count: 2, failed: [1]),
        "twoInactive": try terminalCase(device: device, queue: queue, count: 3, inactive: [1,2]),
        "identityThenInactive": try terminalCase(device: device, queue: queue, count: 3, inactive: [2]),
        "snapshotBudgetRejected": try terminalCase(device: device, queue: queue, count: 2,
            inactive: [1], budget: 0)]
    let data = try JSONSerialization.data(withJSONObject:
        ["metalAvailable": true, "rows": rows], options: [.sortedKeys])
    FileHandle.standardOutput.write(data)
 }
}
'''


@unittest.skipUnless(shutil.which('swiftc'), 'swiftc is required')
class TerminalMaterialGraphTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        sources = graph_fixture.CONTRACT_FIXTURE['SWIFT_SOURCES']
        graph_fixture.CONTRACT_FIXTURE['SWIFT_SOURCES'] = list(dict.fromkeys(
            sources + pool_fixture.SWIFT_SOURCES))
        try:
            compilation, run = graph_fixture.compile_lit_harness(SUPPORT, HARNESS)
        finally:
            graph_fixture.CONTRACT_FIXTURE['SWIFT_SOURCES'] = sources
        if destination := os.environ.get('MWX_TERMINAL_GRAPH_EVIDENCE'):
            root = Path(destination)
            root.mkdir(parents=True, exist_ok=True)
            (root/'compile.log').write_text(compilation.stderr)
            if run is not None:
                (root/'result.json').write_text(run.stdout)
                (root/'runtime.log').write_text(run.stderr)
            (root/'source-sha.json').write_text(json.dumps({str(p): hashlib.sha256(p.read_bytes()).hexdigest()
                for p in [Path(__file__), *dict.fromkeys(sources + pool_fixture.SWIFT_SOURCES)]}, indent=2))
        if compilation.returncode:
            raise RuntimeError(compilation.stderr)
        if run is None or run.returncode:
            raise RuntimeError(run.stderr if run is not None else 'harness did not run')
        cls.result = json.loads(run.stdout)
        if not cls.result['metalAvailable']:
            raise unittest.SkipTest('Metal unavailable')

    def check_cases(self, names):
        for name in names:
            with self.subTest(case=name):
                row = self.result['rows'][name]
                self.assertEqual([k for k,v in row['results'].items() if not v], [], row)

    def test_active_identity_samples_the_small_graph_output(self):
        self.check_cases(['single', 'active'])

    def test_inactive_and_failed_suffix_retain_last_active_input(self):
        self.check_cases(['inactive', 'failed', 'twoInactive', 'identityThenInactive'])

    def test_no_active_material_or_snapshot_storage_uses_the_real_graph_route(self):
        self.check_cases(['singleInactive', 'snapshotBudgetRejected'])
