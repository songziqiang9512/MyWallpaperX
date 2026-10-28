"""Authored MDLS constraints and deterministic translation spring dynamics."""
import json
import math
from pathlib import Path
import struct
import subprocess
import tempfile
import unittest
from .test_scene_puppet_playback import SCENE_ROOT, SWIFT_SOURCES
from .test_scene_puppet_rig import build_rig_mdl

HARNESS = r'''
import Foundation
import simd
@main enum Harness {
    static func main() throws {
        let metadata = Data(#"{"se":true,"t":true,"ts":300,"tf":8,"ti":30,"tm":200}"#.utf8)
        let config = try SceneMdlPuppetRig.TranslationPhysics.read(metadata: metadata)!
        func read(_ json: String) throws -> SceneMdlPuppetRig.TranslationPhysics {
            try SceneMdlPuppetRig.TranslationPhysics.read(metadata: Data(json.utf8))!
        }
        let gravity = try read(#"{"se":true,"t":true,"ge":true,"m":5,"gd":"0 -1 0","ts":150,"tf":20,"ti":0,"tm":1000}"#)
        let equivalentGravity = try read(#"{"se":true,"t":true,"ge":true,"m":5e0,"gd":" 0e0\t-1e0  +0.0 ","ts":1.5e2,"tf":2e1,"ti":0,"tm":1e3}"#)
        let disabledGravity = try read(#"{"re":true,"t":true,"ge":false,"m":"unused","gd":[1,2]}"#)
        let large = try read(#"{"se":true,"t":true,"ts":1500000,"tf":2000000,"ti":3000000,"tm":4000000}"#)
        func rejectsGravity(_ fields: String, missing: Bool = false) -> Bool {
            do {
                _ = try read("{\"se\":true,\"t\":true,\"ge\":true," + fields + "}")
                return false
            } catch SceneMdlPuppetRigReadError.unsupportedPhysicsMode { return true }
            catch { return !missing }
        }
        let rejectedGravity = [
            "missingMass": rejectsGravity(#""gd":"0 -1 0""#, missing: true),
            "missingDirection": rejectsGravity(#""m":5"#, missing: true),
            "negativeMass": rejectsGravity(#""m":-1,"gd":"0 -1 0""#),
            "booleanMass": rejectsGravity(#""m":true,"gd":"0 -1 0""#),
            "overflowMass": rejectsGravity(#""m":1e100,"gd":"0 -1 0""#),
            "nonfiniteDirection": rejectsGravity(#""m":5,"gd":"0 nan 0""#),
            "shortDirection": rejectsGravity(#""m":5,"gd":"0 -1""#),
            "rotation": rejectsGravity(#""m":5,"gd":"0 -1 0","r":true"#),
            "ik": rejectsGravity(#""m":5,"gd":"0 -1 0","ik":true"#),
        ]
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
        // Independent free-motion oracle: a world delta-velocity of 6 units/s
        // travels .6 world units in .1s regardless of the parent's basis.
        let free = SceneMdlPuppetRig.TranslationPhysics(spring: false, stiffness: 0,
            friction: 0, inertia: 0, maxDistance: 1000)
        var carrier = matrix_identity_float4x4
        carrier.columns.0 = SIMD4(0,2,0,0)
        carrier.columns.1 = SIMD4(-3,0,0,0)
        carrier.columns.2 = SIMD4(0,0,0.5,0)
        carrier.columns.3 = SIMD4(10,-4,2,1)
        func xyz(_ value: SIMD3<Float>) -> [Double] { [Double(value.x),Double(value.y),Double(value.z)] }
        func world(_ local: SIMD3<Float>, _ matrix: simd_float4x4) -> SIMD3<Float> {
            let point = matrix * SIMD4(local,1)
            return SIMD3(point.x,point.y,point.z)
        }
        func gravityRun(_ c: SceneMdlPuppetRig.TranslationPhysics, hz: Int, seconds: Int) -> [Double] {
            var motion = ScenePuppetTranslationMotion()
            var position = SIMD3<Float>.zero
            for _ in 0..<(hz * seconds) {
                position = motion.advance(position: position, target: .zero,
                    deltaTime: 1 / Double(hz), configuration: c)
            }
            return xyz(position) + xyz(motion.velocity)
        }
        let falling = SceneMdlPuppetRig.TranslationPhysics(spring: false, stiffness: 0,
            friction: 0, inertia: 0, maxDistance: 1000, gravity: SIMD3(0,-10,0))
        let dampedFall = SceneMdlPuppetRig.TranslationPhysics(spring: false, stiffness: 0,
            friction: 4, inertia: 0, maxDistance: 1000, gravity: SIMD3(0,-10,0))
        let tinySpring = SceneMdlPuppetRig.TranslationPhysics(spring: true, stiffness: 1e-12,
            friction: 0, inertia: 0, maxDistance: 1000, gravity: SIMD3(0,-10,0))
        var gravityKick = ScenePuppetTranslationMotion()
        gravityKick.addImpulse(SIMD3(6,0,0))
        let gravityZero = gravityKick.advance(position: .zero, target: .zero,
            deltaTime: 0, configuration: falling, parentToWorld: carrier)
        let gravityFirst = gravityKick.advance(position: gravityZero, target: .zero,
            deltaTime: 0.2, configuration: falling, parentToWorld: carrier)
        let gravitySecond = gravityKick.advance(position: gravityFirst, target: .zero,
            deltaTime: 0.2, configuration: falling, parentToWorld: carrier)
        var gravityLimit = ScenePuppetTranslationMotion()
        let gravityLimited = gravityLimit.advance(position: .zero, target: .zero, deltaTime: 0.2,
            configuration: .init(spring: false, stiffness: 0, friction: 0, inertia: 0,
                maxDistance: 0.05, gravity: falling.gravity), parentToWorld: carrier)
        var kicked = ScenePuppetTranslationMotion()
        kicked.addImpulse(SIMD3(6,0,0))
        let zeroStep = kicked.advance(position: .zero, target: .zero, deltaTime: 0,
            configuration: free, parentToWorld: carrier)
        let firstKick = kicked.advance(position: zeroStep, target: .zero, deltaTime: 0.1,
            configuration: free, parentToWorld: carrier)
        let firstWorldDelta = world(firstKick,carrier)-world(.zero,carrier)
        let secondKick = kicked.advance(position: firstKick, target: .zero, deltaTime: 0.1,
            configuration: free, parentToWorld: carrier)
        let secondWorldDelta = world(secondKick,carrier)-world(.zero,carrier)
        var movingCarrier = ScenePuppetTranslationMotion()
        movingCarrier.addImpulse(SIMD3(6,0,0))
        let beforeCarrierChange = movingCarrier.advance(position: .zero, target: .zero,
            deltaTime: 0.1, configuration: free)
        let afterCarrierChange = movingCarrier.advance(position: beforeCarrierChange,
            target: .zero, deltaTime: 0.1, configuration: free, parentToWorld: carrier)
        var beforeSetter = ScenePuppetTranslationMotion()
        beforeSetter.addImpulse(SIMD3(20,0,0));beforeSetter.reset()
        let discardedKick = beforeSetter.advance(position: SIMD3(5,0,0), target: SIMD3(5,0,0),
            deltaTime: 0.1, configuration: free)
        var afterSetter = ScenePuppetTranslationMotion()
        afterSetter.reset();afterSetter.addImpulse(SIMD3(20,0,0))
        let retainedKick = afterSetter.advance(position: SIMD3(5,0,0), target: SIMD3(5,0,0),
            deltaTime: 0.1, configuration: free)
        var constrained = ScenePuppetTranslationMotion()
        constrained.addImpulse(SIMD3(6,0,0))
        let localLimited = constrained.advance(position: .zero, target: .zero, deltaTime: 0.1,
            configuration: .init(spring: false, stiffness: 0, friction: 0, inertia: 0,
                maxDistance: 0.1), parentToWorld: carrier)
        var overflow = ScenePuppetTranslationMotion()
        overflow.addImpulse(SIMD3(Float.greatestFiniteMagnitude,0,0))
        overflow.addImpulse(SIMD3(Float.greatestFiniteMagnitude,0,0))
        let overflowStep = overflow.advance(position: .zero, target: .zero, deltaTime: 0.1,
            configuration: free)
        let overflowRecovery = overflow.advance(position: overflowStep, target: .zero,
            deltaTime: 0.1, configuration: free)
        var rigReports: [[String:Any]] = []
        for path in CommandLine.arguments.dropFirst() {
            let data = try Data(contentsOf: URL(fileURLWithPath: path))
            var row: [String:Any] = ["file": (path as NSString).lastPathComponent]
            do {
                let mesh = try SceneMdlPuppetMeshReader.read(data: data)
                let rig = try SceneMdlPuppetRigReader.read(data: data, mesh: mesh)
                row["names"] = rig.bones.map(\.name)
                row["parents"] = rig.bones.map(\.parentIndex)
                row["bindTranslations"] = rig.bones.map {
                    Array($0.bindLocalMatrixColumnMajor[12...14]).map(Double.init)
                }
                row["diagnostics"] = rig.bones.map { $0.physicsDiagnostic ?? "" }
                row["configured"] = rig.bones.map { $0.translationPhysics != nil }
                row["gravity"] = rig.bones.map { xyz($0.translationPhysics?.gravity ?? .zero) }
                row["weightIndices"] = rig.vertexWeights.map { weights in
                    (0..<4).map { Int(weights.boneIndices[$0]) }
                }
                row["weights"] = rig.vertexWeights.map { weights in
                    (0..<4).map { Double(weights.boneWeights[$0]) }
                }
            } catch let error as SceneMdlPuppetRigReadError {
                row["error"] = error.description
                if case let .invalidBoneRecord(index) = error { row["invalidBoneRecord"] = index }
            }
            rigReports.append(row)
        }
        let payload: [String:Any] = ["stiffnessResponse": [response(stiffness: 100, inertia: 0, moving: false), response(stiffness: 400, inertia: 0, moving: false)],
            "inertiaResponse": [response(stiffness: 300, inertia: 0, moving: true), response(stiffness: 300, inertia: 30, moving: true)],
            "slow": simulate(hz: 15), "fast": simulate(hz: 120),
            "rigid": simulate(hz: 60, spring: false), "damped": simulate(hz: 30, friction: 40),
            "clamped": Double(simd_length(clamped)), "invalid": invalid,
            "parameters": [config.stiffness, config.friction, config.inertia, config.maxDistance],
            "gravityDeclaration": ["value":xyz(gravity.gravity),
                "equivalent":gravity == equivalentGravity,
                "disabled":xyz(disabledGravity.gravity),"legacy":xyz(config.gravity),
                "largeParameters":[large.stiffness,large.friction,large.inertia,large.maxDistance],
                "rejected":rejectedGravity] as [String:Any],
            "gravityMotion": ["ballistic":gravityRun(falling,hz:4,seconds:1),
                "terminal":gravityRun(dampedFall,hz:30,seconds:4),
                "equilibrium30":gravityRun(gravity,hz:30,seconds:4),
                "equilibrium120":gravityRun(gravity,hz:120,seconds:4),
                "tinySpring":gravityRun(tinySpring,hz:120,seconds:1),
                "zeroStep":xyz(gravityZero),"firstLocal":xyz(gravityFirst),
                "firstWorldDelta":xyz(world(gravityFirst,carrier)-world(.zero,carrier)),
                "secondWorldDelta":xyz(world(gravitySecond,carrier)-world(.zero,carrier)),
                "velocity":xyz(gravityKick.velocity),"limitedLocal":xyz(gravityLimited),
                "limitedVelocity":xyz(gravityLimit.velocity)] as [String:[Double]],
            "worldImpulse": ["zeroStep":xyz(zeroStep),"firstLocal":xyz(firstKick),
                "firstWorldDelta":xyz(firstWorldDelta),"secondWorldDelta":xyz(secondWorldDelta),
                "velocity":xyz(kicked.velocity),"changedCarrierWorld":xyz(world(afterCarrierChange,carrier))],
            "impulseOrder": [xyz(discardedKick),xyz(retainedKick)],
            "localConstraint":xyz(localLimited),
            "rigMetadata":rigReports,
            "overflow": [xyz(overflowStep),xyz(overflowRecovery),xyz(overflow.velocity)]]
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
        fixtures = {'baseline.mdl': build_rig_mdl()}
        healthy = b'{"re":true,"t":true,"ge":true,"m":5,"gd":"0 -1 0"}'
        for name, broken in {
            'bad-direction': b'{"se":true,"t":true,"ge":true,"m":5,"gd":"0 bad 0"}',
            'negative-mass': b'{"se":true,"t":true,"ge":true,"m":-5,"gd":"0 -1 0"}',
            'bad-json': b'{"se":true,"t":true',
            'bad-stiffness': b'{"se":true,"t":true,"ts":-1}',
        }.items():
            original = build_rig_mdl()
            start = original.index(b'MDLS0004\0')
            end = struct.unpack_from('<I', original, start + 9)[0]
            skeleton = original[start:end]
            for metadata in (broken, healthy):
                skeleton = skeleton.replace(b'{}\0', metadata + b'\0', 1)
            patched = bytearray(original[:start] + skeleton + original[end:])
            struct.pack_into('<I', patched, start + 9, start + len(skeleton))
            fixtures[name + '.mdl'] = bytes(patched)
        truncated = bytearray(build_rig_mdl())
        start = truncated.index(b'MDLS0004\0')
        end = struct.unpack_from('<I', truncated, start + 9)[0]
        struct.pack_into('<I', truncated, start + 9, end - 1)
        fixtures['short-bone-record.mdl'] = bytes(truncated)
        paths = []
        for name, data in fixtures.items():
            path = folder / name
            path.write_bytes(data)
            paths.append(str(path))
        subprocess.run(['swiftc', '-parse-as-library', *map(str,SWIFT_SOURCES),
            str(SCENE_ROOT/'Systems/Puppet/ScenePuppetTranslationMotion.swift'),str(source),'-o',str(binary)],
            check=True, capture_output=True, text=True)
        cls.result = json.loads(subprocess.run([str(binary), *paths], check=True,
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

    def test_world_impulse_keeps_direction_through_rotated_nonuniform_parent(self):
        facts = self.result['worldImpulse']
        for key, expected in [('firstLocal', [0, -.2, 0]),
                              ('firstWorldDelta', [.6, 0, 0]),
                              ('secondWorldDelta', [1.2, 0, 0]),
                              ('velocity', [6, 0, 0]),
                              ('changedCarrierWorld', [1.2, 0, 0])]:
            for actual, wanted in zip(facts[key], expected):
                self.assertAlmostEqual(actual, wanted, places=5, msg=key)

    def test_zero_delta_retains_impulse_and_next_positive_steps_consume_it_once(self):
        self.assertEqual(self.result['worldImpulse']['zeroStep'], [0, 0, 0])
        self.assertAlmostEqual(self.result['worldImpulse']['secondWorldDelta'][0], 1.2, places=5)

    def test_setter_clears_preceding_impulse_and_retains_following_impulse(self):
        self.assertEqual(self.result['impulseOrder'][0], [5, 0, 0])
        self.assertAlmostEqual(self.result['impulseOrder'][1][0], 7, places=5)

    def test_world_motion_keeps_local_distance_limit_and_overflow_does_not_stick(self):
        self.assertAlmostEqual(self.result['localConstraint'][1], -.1, places=5)
        self.assertEqual(self.result['overflow'], [[0, 0, 0]] * 3)

    def test_gravity_declaration_preserves_units_variants_and_disabled_metadata(self):
        facts = self.result['gravityDeclaration']
        self.assertEqual(facts['value'], [0, -5000, 0])
        self.assertTrue(facts['equivalent'])
        self.assertEqual(facts['disabled'], [0, 0, 0])
        self.assertEqual(facts['legacy'], [0, 0, 0])
        self.assertEqual(facts['largeParameters'], [1500000, 2000000, 3000000, 4000000])
        for name, rejected in facts['rejected'].items():
            with self.subTest(metadata=name):
                self.assertTrue(rejected)

    def test_bad_physics_metadata_is_local_but_bone_record_bounds_stay_required(self):
        rows = {row['file']: row for row in self.result['rigMetadata']}
        baseline = rows['baseline.mdl']
        self.assertEqual(baseline['names'], ['root', 'MouseBone'])
        self.assertEqual(baseline['parents'], [-1, 0])
        self.assertEqual(len(baseline['weights']), 3)
        for name in ('bad-direction', 'negative-mass', 'bad-json', 'bad-stiffness'):
            with self.subTest(metadata=name):
                row = rows[name + '.mdl']
                self.assertNotIn('error', row)
                for field in ('names', 'parents', 'bindTranslations', 'weightIndices', 'weights'):
                    self.assertEqual(row[field], baseline[field], field)
                self.assertEqual(row['configured'], [False, True])
                self.assertTrue(row['diagnostics'][0])
                self.assertEqual(row['diagnostics'][1], '')
                self.assertEqual(row['gravity'][1], [0, -5000, 0])
        self.assertEqual(rows['short-bone-record.mdl']['invalidBoneRecord'], 1)

    def test_free_gravity_matches_ballistic_and_drag_analytic_solutions(self):
        facts = self.result['gravityMotion']
        # Constant acceleration from rest: y=g*t*t/2 and v=g*t.
        for actual, expected in zip(facts['ballistic'], [0, -5, 0, 0, -10, 0]):
            self.assertAlmostEqual(actual, expected, delta=0.0001)
        # With linear drag f=4, integrate v=(g/f)*(1-exp(-f*t)).
        decay = math.exp(-4 * 4)
        expected = [0, -2.5 * (4 - (1 - decay) / 4), 0, 0, -2.5 * (1 - decay), 0]
        for actual, wanted in zip(facts['terminal'], expected):
            self.assertAlmostEqual(actual, wanted, delta=0.0001)

    def test_gravity_spring_settles_at_force_balance_at_both_cadences(self):
        for cadence in ('equilibrium30', 'equilibrium120'):
            for actual, expected in zip(self.result['gravityMotion'][cadence],
                                        [0, -5000 / 150, 0, 0, 0, 0]):
                self.assertAlmostEqual(actual, expected, delta=0.003, msg=cadence)

    def test_tiny_spring_keeps_the_free_gravity_limit(self):
        # At k=1e-12 over one second, the spring correction is below Float
        # resolution; subtracting two g/k-sized positions must not erase motion.
        for actual, expected in zip(self.result['gravityMotion']['tinySpring'], [0, -5, 0, 0, -10, 0]):
            self.assertAlmostEqual(actual, expected, delta=0.0001)

    def test_gravity_and_once_only_kick_use_world_axes_and_local_constraint(self):
        facts = self.result['gravityMotion']
        self.assertEqual(facts['zeroStep'], [0, 0, 0])
        for key, expected in [('firstLocal', [-.1, -.4, 0]),
                              ('firstWorldDelta', [1.2, -.2, 0]),
                              ('secondWorldDelta', [2.4, -.8, 0]),
                              ('velocity', [6, -4, 0]),
                              ('limitedLocal', [-.05, 0, 0]),
                              ('limitedVelocity', [0, 0, 0])]:
            for actual, wanted in zip(facts[key], expected):
                self.assertAlmostEqual(actual, wanted, places=5, msg=key)
