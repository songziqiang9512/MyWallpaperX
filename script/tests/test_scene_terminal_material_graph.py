"""Production graph capture and terminal raster use separate pixel domains."""
import json
import shutil
import unittest
from script.tests import test_scene_resolved_material_graph_executor as graph_fixture


HELPERS = graph_fixture.HARNESS.split('@main', 1)[0]
HELPERS = HELPERS.replace('Plan.PixelExtent(width: 2, height: 2)',
                          'Plan.PixelExtent(width: 10, height: 10)')
HELPERS = HELPERS.replace('private let vertexSource = """\n',
    'private let vertexSource = """\nuniform mat4 g_ModelViewProjectionMatrix;\n', 1)
HELPERS = HELPERS.replace('gl_Position = vec4(a_Position, 1.0);',
    'gl_Position = mul(vec4(a_Position, 1.0), g_ModelViewProjectionMatrix);', 1)
HELPERS = HELPERS.replace(
    '"gl_FragColor = texSample2D(g_Texture0, v_TexCoord);"',
    '"vec4 color = texSample2D(g_Texture0, v_TexCoord); '
    'color.rgb *= step(0.5, fract(v_TexCoord.x * 64.0)); gl_FragColor = color;"')

HARNESS = HELPERS + r'''
@main struct TerminalRasterHarness {
 static func main() throws {
  guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else {
   print("{\"metalAvailable\":false}"); return
  }
  let simple = graph(targets: [], nodes: [material(0, ordinal: 0, target: output, read: input)])
  let admitted = admittedGraph(simple)
  let visibleTarget = SceneDynamicTarget.effectVisibility(layerID: layerID, effectIndex: 0)
  let caps = capabilities(admitted, catalog: catalog(for: simple), dynamicProducers: .init(
   userProperties: [.init(propertyKey: "show", target: visibleTarget, valueType: .bool)],
   authoredFallbackTargets: [visibleTarget], timelineTargets: [], sceneScriptTargets: []))
  guard let claim = caps.claim(admitted), let capability = caps.resolve(claim.token),
    let executor = Executor(device: device, capabilities: caps),
    let leases = makeChainedLeases(capability, device: device),
    let command = queue.makeCommandBuffer() else { fatalError("fixture preparation") }
  var result: [String: Bool] = ["singlePassAdmitted": capability.supportsTerminalMaterialReplay]
  let target = makeSource(device, width: 256, height: 64, usage: [.renderTarget, .shaderRead])
  let main = SceneMainPassEncoder(commandBuffer: command, target: target,
    clearColor: .init(red: 0, green: 0, blue: 1, alpha: 1), clearEnabled: true)
  let prepared = try executor.prepare(token: claim.token, leases: leases,
    historyRehydrateCopiesByEffect: [:], frame: frame(1),
    sourceTexture: makeSource(device), sourceUniforms: .neutral(),
    sourcePipeline: makeSourcePipeline(device), terminalReplayTarget: target,
    frameInputs: .init(), commandBuffer: command, previousStates: [:],
    previousGraphResources: [:], effectGeneration: 1, resetGeneration: 1).get()
  result["sourceRemainsTenPixels"] = prepared.stages[0].inputWidth == 10
    && prepared.stages[0].inputHeight == 10 && prepared.finalTexture.width == 10
  result["preparedTerminal"] = prepared.terminalMaterialReplay != nil
  result["graphEncoded"] = executor.encode(prepared, commandBuffer: command)
  let wrongCommand = queue.makeCommandBuffer()!
  result["wrongCommandRejected"] = !executor.encodeTerminalReplay(prepared,
    mainPass: main, commandBuffer: wrongCommand)
  result["terminalEncoded"] = executor.encodeTerminalReplay(prepared,
    mainPass: main, commandBuffer: command)
  result["mainFinished"] = main.finishEnsuringClear()
  command.commit(); command.waitUntilCompleted()
  result["gpuCompleted"] = command.status == .completed
  var bytes = [UInt8](repeating: 0, count: 256 * 64 * 4)
  target.getBytes(&bytes, bytesPerRow: 256 * 4, from: MTLRegionMake2D(0, 0, 256, 64), mipmapLevel: 0)
  func red(_ x: Int) -> UInt8 { bytes[(32 * 256 + x) * 4 + 2] }
  let transitions = (65..<192).filter { (red($0) > 127) != (red($0-1) > 127) }.count
  result["screenPixelStripes"] = transitions >= 120
  result["outsideBackgroundPreserved"] = bytes[(32*256 + 10)*4] == 255 && red(10) == 0
  result["stalePreparationRejected"] = executor.reset() && !executor.encodeTerminalReplay(
    prepared, mainPass: main, commandBuffer: queue.makeCommandBuffer()!)
  // The same admitted material must not replay after an inactive effect bypass.
  let inactiveCommand = queue.makeCommandBuffer()!
  let dynamic = SceneDynamicSnapshotResolver().resolve(frameIndex: 2, generation: 2,
    definitions: [.init(target: visibleTarget, valueType: .bool, authoredValue: .bool(true))],
    userValues: [visibleTarget: .bool(false)]).snapshot
  let inactive = try executor.prepare(token: claim.token, leases: leases,
    historyRehydrateCopiesByEffect: [:], frame: frame(2),
    sourceTexture: makeSource(device), sourceUniforms: .neutral(), sourcePipeline: makeSourcePipeline(device),
    terminalReplayTarget: target, frameInputs: .init(dynamicValues: dynamic),
    commandBuffer: inactiveCommand, previousStates: [:], previousGraphResources: [:],
    effectGeneration: 2, resetGeneration: 2).get()
  result["inactiveKeepsTextureRoute"] = inactive.terminalMaterialReplay == nil
    && inactive.stages[0].effectLocalActivationBypassReasonCode != nil
  // A low-resolution texture route does not authorize multi-stage terminal
  // replay: inactive suffixes may overwrite an earlier Program's input member.
  let chain = chainedGraph()
  let admittedChain = orderedLayerGraph(chain)
  let chainCaps = capabilities(admittedChain, catalog: catalog(for: chain))
  let chainClaim = chainCaps.claim(admittedChain)!
  let chainCapability = chainCaps.resolve(chainClaim.token)!
  result["chainKeepsTextureRoute"] = chainCapability.supportsSourceSizedSolidEffects
    && !chainCapability.supportsTerminalMaterialReplay
  let payload: [String: Any] = ["metalAvailable": true, "results": result, "transitions": transitions]
  let data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
  FileHandle.standardOutput.write(data)
 }
}
'''


@unittest.skipUnless(shutil.which('swiftc'), 'swiftc is required')
class TerminalMaterialGraphTests(unittest.TestCase):
    def test_source_capture_and_terminal_raster_are_distinct(self):
        compile_result, run = graph_fixture.compile_lit_harness(graph_fixture.SUPPORT, HARNESS)
        self.assertEqual(compile_result.returncode, 0, compile_result.stderr)
        self.assertIsNotNone(run)
        self.assertEqual(run.returncode, 0, run.stderr)
        data = json.loads(run.stdout)
        if not data['metalAvailable']:
            self.skipTest('Metal unavailable')
        self.assertEqual([k for k, v in data['results'].items() if not v], [], data)
