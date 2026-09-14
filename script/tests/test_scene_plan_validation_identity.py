"""Exercise the production validator with an altered plan sharing a lease identity.

GPU storage is represented by reference-identity doubles; the validator body and
its memo key come from production. This gate asserts admission, not rendering.
"""
from pathlib import Path
import json
import subprocess
import tempfile
import unittest
from script.tests.test_scene_wallpaper_async_launch import function_body

ROOT = Path(__file__).resolve().parents[2]
DIRECTORY = ROOT / 'MyWallpaperX/Core/SteamWorkshopScene/RenderGraph/EffectExecution'
SUPPORT = r'''
import Foundation
struct SceneAuthoredEffectRenderPlan {
    typealias EffectKey = Int
    typealias TextureIdentity = Int
    struct Effect { let key: Int }
    let effects: [Effect]
    let expectedPlan: SceneGraphRenderTargetPlan
}
enum SceneAuthoredEffectInputRole { case layerSource, priorEffectOutput }
struct SceneGraphRenderTargetPlan: Equatable {
    struct Extent: Equatable { let width: Int; let height: Int }
    let layerID: Int
    let input: Int
    let output: Int
    let inputRole: SceneAuthoredEffectInputRole
    let inputExtent: Extent
    let logicalTargets: [Int]
    let commands: [Int]
    static func make(graph: SceneAuthoredEffectRenderPlan,
        inputRole: SceneAuthoredEffectInputRole, inputWidth: Int, inputHeight: Int,
        materialFunctionTargets: Set<Int>) -> Result<Self, Failure> {
        .success(graph.expectedPlan)
    }
    enum Failure: Error { case invalid }
}
final class Texture {}
struct SceneGraphRenderTargetLease {
    struct Tokens { let first: Int; let second: Int }
    struct Textures { let first: Texture; let second: Texture }
    struct Table { let plan: SceneGraphRenderTargetPlan; let fullFramePair: Textures }
    struct Allocation { let resources: [Int: Int] }
    let generation: UInt64
    let fullFramePair: Tokens
    let texturesByToken: [Int: Texture]
    let table: Table
    let framebufferAllocation: Allocation
}
enum SceneResolvedMaterialExecutionCapabilityCatalog {
    final class LayerCapability {
        struct Product { let graph: SceneAuthoredEffectRenderPlan }
        struct Step { let effect: Int; let inputIdentity: Int; let outputIdentity: Int }
        struct Plan { let layerID: Int; let terminalMember: Int; let effects: [Step] }
        let admittedProducts: [Product]
        let pairPlan: Plan
        let layerID: Int
        init(graph: SceneAuthoredEffectRenderPlan) {
            layerID = graph.expectedPlan.layerID
            admittedProducts = [.init(graph: graph)]
            pairPlan = .init(layerID: layerID, terminalMember: 1,
                effects: [.init(effect: 7, inputIdentity: 10, outputIdentity: 11)])
        }
    }
}
'''
TAIL = r'''
@main enum Harness {
    static func main() throws {
        func plan(_ commands: [Int]) -> SceneGraphRenderTargetPlan {
            .init(layerID: 1, input: 10, output: 11, inputRole: .layerSource,
                inputExtent: .init(width: 16, height: 16), logicalTargets: [], commands: commands)
        }
        let expected = plan([])
        let capability = SceneResolvedMaterialExecutionCapabilityCatalog.LayerCapability(
            graph: .init(effects: [.init(key: 7)], expectedPlan: expected))
        let zero = Texture(), one = Texture()
        func lease(_ plan: SceneGraphRenderTargetPlan) -> SceneGraphRenderTargetLease {
            .init(generation: 3, fullFramePair: .init(first: 10, second: 11),
                texturesByToken: [10: zero, 11: one],
                table: .init(plan: plan, fullFramePair: .init(first: zero, second: one)),
                framebufferAllocation: .init(resources: [:]))
        }
        let valid = lease(expected), invalid = lease(plan([999]))
        let positiveFirst = SceneResolvedMaterialGraphExecutor()
        let validAccepted = positiveFirst.validate(capability: capability, leases: [valid])
        let invalidAccepted = positiveFirst.validate(capability: capability, leases: [invalid])
        let negativeFirst = SceneResolvedMaterialGraphExecutor()
        let invalidInitiallyAccepted = negativeFirst.validate(capability: capability, leases: [invalid])
        let validAfterInvalid = negativeFirst.validate(capability: capability, leases: [valid])
        let result = ["valid": validAccepted, "invalidAfterValid": invalidAccepted,
            "invalidInitially": invalidInitiallyAccepted, "validAfterInvalid": validAfterInvalid]
        print(String(data: try JSONEncoder().encode(result), encoding: .utf8)!)
    }
}
'''

class ScenePlanValidationIdentityTests(unittest.TestCase):
    def test_stored_plan_is_checked_even_when_identity_and_extent_match(self):
        source = (DIRECTORY / 'SceneResolvedMaterialGraphExecutor+Validation.swift').read_text()
        begin = source.index('    func validate(')
        body = function_body(source, '    func validate(')
        method = source[begin:source.index('{', begin)] + body
        executor = (DIRECTORY / 'SceneResolvedMaterialGraphExecutor.swift').read_text()
        key = ''
        memo = ''
        if 'nonisolated struct PlanValidationMemoKey:' in executor:
            start = executor.index('nonisolated struct PlanValidationMemoKey:')
            key = executor[start:executor.index('\nfinal class SceneResolvedMaterialGraphExecutor', start)]
            memo = 'var planValidationMemo: [PlanValidationMemoKey: Bool] = [:]'
        wrapper = '\nfinal class SceneResolvedMaterialGraphExecutor {\n'
        wrapper += 'typealias Graph = SceneAuthoredEffectRenderPlan\nenum Pair { static let fixedTerminalMember = 1 }\n'
        with tempfile.TemporaryDirectory(prefix='mwx-plan-validation-identity-') as directory:
            root = Path(directory); harness = root / 'Harness.swift'; binary = root / 'harness'
            harness.write_text(SUPPORT + key + wrapper + memo + '\n' + method + '\n}\n' + TAIL)
            compiled = subprocess.run(['xcrun','swiftc','-parse-as-library',str(harness),'-o',str(binary)],capture_output=True,text=True,timeout=60)
            self.assertEqual(compiled.returncode,0,compiled.stderr)
            result = subprocess.run([str(binary)],capture_output=True,text=True,check=True,timeout=10)
            self.assertEqual(json.loads(result.stdout), {'valid':True,'invalidAfterValid':False,'invalidInitially':False,'validAfterInvalid':True})
