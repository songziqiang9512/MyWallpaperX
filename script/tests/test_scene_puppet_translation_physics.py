"""Authored MDLS constraints and deterministic translation spring dynamics."""
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from .test_scene_puppet_playback import SCENE_ROOT, SWIFT_SOURCES

HARNESS = r'''
import Foundation
import simd
@main enum Harness {
    static func main() throws {
        let metadata = Data(#"{"se":true,"t":true,"ts":300,"tf":8,"ti":30,"tm":200}"#.utf8)
        let config = try SceneMdlPuppetRig.TranslationPhysics.read(metadata: metadata)!
        func simulate(hz: Int, friction: Float = 8, spring: Bool = true) -> [Double] {
            var motion = ScenePuppetTranslationMotion()
            var position = SIMD3<Float>(60,0,0)
            var crossed = false
            let c = SceneMdlPuppetRig.TranslationPhysics(spring: spring, stiffness: 300,
                friction: friction, inertia: 30, maxDistance: 200)
            for _ in 0..<(hz * 4) {
                position = motion.advance(position: position, target: .zero,
                    deltaTime: 1 / Double(hz), configuration: c)
                crossed = crossed || position.x < 0
            }
            return [Double(position.x), Double(simd_length(motion.velocity)), crossed ? 1 : 0]
        }
        var limited = ScenePuppetTranslationMotion()
        let clamped = limited.advance(position: .init(300,0,0), target: .zero,
            deltaTime: 0.0001, configuration: config)
        let invalid: Bool
        do {
            _ = try SceneMdlPuppetRig.TranslationPhysics.read(
                metadata: Data(#"{"se":true,"t":true,"ts":-1}"#.utf8))
            invalid = false
        } catch { invalid = true }
        func response(stiffness: Float, inertia: Float, moving: Bool) -> Double {
            var motion = ScenePuppetTranslationMotion()
            motion.previousTarget = .zero
            let target = SIMD3<Float>(moving ? 10 : 0, 0, 0)
            let next = motion.advance(position: SIMD3<Float>(moving ? 0 : 60, 0, 0),
                target: target, deltaTime: 0.01,
                configuration: .init(spring: true, stiffness: stiffness, friction: 8,
                    inertia: inertia, maxDistance: 200))
            return Double(abs(next.x - target.x))
        }
        let payload: [String:Any] = ["stiffnessResponse": [response(stiffness: 100, inertia: 0, moving: false), response(stiffness: 400, inertia: 0, moving: false)],
            "inertiaResponse": [response(stiffness: 300, inertia: 0, moving: true), response(stiffness: 300, inertia: 30, moving: true)],
            "slow": simulate(hz: 15), "fast": simulate(hz: 120),
            "rigid": simulate(hz: 60, spring: false), "damped": simulate(hz: 30, friction: 40),
            "clamped": Double(simd_length(clamped)), "invalid": invalid,
            "parameters": [config.stiffness, config.friction, config.inertia, config.maxDistance]]
        print(String(data: try JSONSerialization.data(withJSONObject: payload), encoding:.utf8)!)
    }
}
'''

class PuppetTranslationPhysicsTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temp = tempfile.TemporaryDirectory(prefix='mwx-b9-physics-')
        cls.addClassCleanup(cls.temp.cleanup)
        folder = Path(cls.temp.name)
        source = folder / 'main.swift'; source.write_text(HARNESS)
        binary = folder / 'physics'
        subprocess.run(['swiftc', '-parse-as-library', *map(str,SWIFT_SOURCES),
            str(SCENE_ROOT/'Rendering/ScenePuppetTranslationMotion.swift'),str(source),'-o',str(binary)],
            check=True, capture_output=True, text=True)
        cls.result = json.loads(subprocess.run([str(binary)], check=True,
            capture_output=True,text=True).stdout)

    def test_authored_parameters_preserved_and_bad_numeric_rejected(self):
        self.assertEqual(self.result['parameters'], [300,8,30,200])
        self.assertTrue(self.result['invalid'])

    def test_spring_returns_with_overshoot_at_low_and_high_frame_rates(self):
        for key in ['slow','fast']:
            self.assertLess(abs(self.result[key][0]),0.001)
            self.assertLess(self.result[key][1],0.001)
            self.assertEqual(self.result[key][2],1)

    def test_rigid_holds_but_high_friction_removes_spring_overshoot(self):
        self.assertAlmostEqual(self.result['rigid'][0],60)
        self.assertEqual(self.result['damped'][2],0)

    def test_max_distance_limits_simulated_displacement(self):
        self.assertLessEqual(self.result['clamped'],200.001)

    def test_stiffness_and_inertia_change_their_respective_responses(self):
        self.assertLess(self.result['stiffnessResponse'][1], self.result['stiffnessResponse'][0])
        self.assertLess(self.result['inertiaResponse'][1], self.result['inertiaResponse'][0] / 20)
