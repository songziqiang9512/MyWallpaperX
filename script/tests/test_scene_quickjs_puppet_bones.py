"""Execute the real QuickJS host through its Swift ABI, not source-string checks."""
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from .scene_vector_vm_test_support import compile_vector_harness

HARNESS = r'''
import Foundation

@main enum Harness {
    static func main() throws {
        let domain = try SceneScriptQuickJSDomain()
        try domain.configureLayerCatalog(.init(layers: [.init(
            id: 42, layerIndex: 0, name: "puppet", visible: true,
            originXYZ: [0,0,0], scaleXYZ: [1,1,1], scaleHasScript: nil,
            alpha: 1, effects: []
        )]))
        let owner = try SceneScriptVectorOwner(
            domain: domain,
            source: """
            let dragging = false, start, offset;
            export function cursorDown(e) {
                const root = thisLayer.getBoneTransform(0).translation();
                const distance = root.copy().subtract(input.cursorWorldPosition);
                if (distance.length() < 10) { start = root; offset = distance; dragging = true; }
            }
            export function cursorUp(e) { dragging = false; }
            export function update(v) {
                if (v.x === 5 && dragging) {
                    const delta = input.cursorWorldPosition.subtract(start);
                    const distance = delta.length();
                    const point = start.add(delta.divide(distance).multiply(Math.min(10,distance))).add(offset);
                    thisLayer.setBoneTransform(1, thisLayer.getBoneTransform(1).translation(point));
                }
                if (v.x === 1) {
                    thisLayer.setBoneTransform(0, Mat4.fromTranslation(new Vec3(20,0,0)));
                    thisLayer.setBoneTransform(1, Mat4.fromTranslation(new Vec3(31,0,0)));
                }
                if (v.x === 4) {
                    const delta = new Vec3(3,4,12);
                    const translated = thisLayer.getBoneTransform(1).translation(delta.copy());
                    return new Vec3(translated.translation().length(),
                        delta.normalize().length(), new Vec3().normalize().length());
                }
                if (v.x === 3) {
                    const m = Mat4.identity(); m.m[0] = 0;
                    thisLayer.setLocalBoneTransform(0, m);
                    thisLayer.setBoneTransform(1, Mat4.identity());
                }
                return new Vec3(thisLayer.getBoneTransform(1).translation().x,
                    thisLayer.getLocalBoneTransform(1).translation().x,
                    thisLayer.getBoneTransform(2).translation().x);
            }
            """,
            target: .layer(layerID: 42, field: .origin),
            effectNames: [], generation: 1, budget: .default)
        func matrix(_ x: Double) -> [Double] {
            [1,0,0,0, 0,1,0,0, 0,0,1,0, x,0,0,1]
        }
        try owner.configurePuppetBones(layerID: 42,
            worldMatrices: matrix(12) + matrix(15) + matrix(17),
            localMatrices: matrix(2) + matrix(3) + matrix(5),
            names: ["root", "left", "right"], parents: [-1,0,0],
            layerToWorld: matrix(10))
        var pointerX = 14.0
        func frame() -> SceneScriptFrameInput {
            .init(timing: .init(wallDate: Date(timeIntervalSince1970: 0),
                simulationFrameTime: 1/60, sceneTime: 0), surface: .init(
                canvasSize: .init(100,100), screenSize: .init(100,100),
                cursorWorldPosition: .init(pointerX,0,0), cursorScreenPosition: .zero,
                cursorLeftDown: true))
        }
        func run(_ mode: Double) -> Result<SceneScriptVectorEvaluation, SceneScriptScalarRuntimeFailure> {
            owner.evaluate(input: .vector3(mode,0,0),
                frame: frame(),
                scriptPropertiesJSON: "", userPropertiesJSON: "{}", expectedGeneration: 1, interruptBudget: nil)
        }
        func values(_ result: Result<SceneScriptVectorEvaluation, SceneScriptScalarRuntimeFailure>) throws -> [Double] {
            let evaluation = try result.get()
            if case let .vector3(x,y,z) = evaluation.value { return [x,y,z] }
            return []
        }
        let changed = run(1)
        let mutations = try changed.get().puppetBoneMutations
        owner.discardLayerMutations()
        let rolledBack = try values(run(0))
        owner.commitLayerMutations()
        let changedAgain = try values(run(1))
        owner.commitLayerMutations()
        let committed = try values(run(0))
        owner.commitLayerMutations()
        let vectorMethods = try values(run(4))
        owner.commitLayerMutations()
        try owner.configurePuppetBones(layerID: 42,
            worldMatrices: matrix(12) + matrix(15) + matrix(17),
            localMatrices: matrix(2) + matrix(3) + matrix(5), names: [],
            parents: [-1,0,0], layerToWorld: matrix(10))
        func cursor(_ kind: SceneScriptCursorEventKind) throws {
            _ = try owner.dispatchCursor(.init(kind: kind, layerID: 42,
                worldPosition: .init(pointerX,0,0), localPosition: .zero),
                frame: frame(), userPropertiesJSON: "{}").get()
        }
        try cursor(.down)
        pointerX = 30
        let clamped = try values(run(5))
        owner.commitLayerMutations()
        try cursor(.up)
        pointerX = 60
        let released = try run(5).get()
        owner.commitLayerMutations()
        try cursor(.down) // Outside the authored radius must not capture.
        pointerX = 14
        let outside = try run(5).get()
        owner.commitLayerMutations()
        let singular = run(3)
        let rejected: Bool
        if case .failure = singular { rejected = true } else { rejected = false }
        owner.discardLayerMutations()
        let result: [String: Any] = [
            "clamped": clamped, "releasedWrites": released.puppetBoneMutations.count,
            "outsideWrites": outside.puppetBoneMutations.count,
            "vectorMethods": vectorMethods,
            "changed": try values(changed), "rollback": rolledBack,
            "retry": changedAgain, "committed": committed,
            "canonicalLocal": mutations.allSatisfy(\.localSpace),
            "localWrites": mutations.map { $0.matrix[12] }, "singularRejected": rejected
        ]
        print(String(data: try JSONSerialization.data(withJSONObject: result), encoding: .utf8)!)
    }
}
'''

class QuickJSPuppetBoneBehaviorTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.directory = tempfile.TemporaryDirectory(prefix="mwx-b9-host-")
        cls.addClassCleanup(cls.directory.cleanup)
        binary = compile_vector_harness(Path(cls.directory.name), HARNESS, "bone-host")
        run = subprocess.run([str(binary)], capture_output=True, text=True)
        if run.returncode:
            raise AssertionError(run.stderr[:5000])
        cls.result = json.loads(run.stdout.strip().splitlines()[-1])

    def test_world_setters_update_descendants_and_derive_local_journal(self):
        self.assertEqual(self.result['changed'], [31,11,25])
        self.assertTrue(self.result['canonicalLocal'])
        self.assertEqual(self.result['localWrites'], [10,11])

    def test_owner_discard_restores_pose_and_commit_preserves_it(self):
        self.assertEqual(self.result['rollback'], [15,3,17])
        self.assertEqual(self.result['retry'], [31,11,25])
        self.assertEqual(self.result['committed'], [31,11,25])

    def test_matrix_translation_returns_complete_drag_vector(self):
        for actual, expected in zip(self.result['vectorMethods'], [13, 1, 0]):
            self.assertAlmostEqual(actual, expected)

    def test_same_owner_cursor_drag_clamps_and_release_or_outside_stops_writes(self):
        self.assertEqual(self.result['clamped'], [20,8,17])
        self.assertEqual(self.result['releasedWrites'], 0)
        self.assertEqual(self.result['outsideWrites'], 0)

    def test_singular_parent_rejects_world_write(self):
        self.assertTrue(self.result['singularRejected'])

if __name__ == '__main__':
    unittest.main()
