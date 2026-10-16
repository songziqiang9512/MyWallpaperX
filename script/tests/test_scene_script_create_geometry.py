"""Creation geometry through the real QuickJS callbacks and typed Swift ABI.

The compiler helper supplies external descriptor metadata; no geometry parser,
mutation transaction, or callback result is substituted. Render consumers are
covered by the descriptor and layer-source publication fixtures.
"""
from __future__ import annotations

import json
from pathlib import Path
import subprocess
import tempfile
import unittest

from .scene_vector_vm_test_support import compile_vector_harness


HARNESS = r'''
import Foundation

@main enum Harness {
    static func authoredAliases(_ filename: String, _ variable: String) throws -> [String: Any] {
        let rawPath = "models/\(filename).json"
        let models = ["models/workshop/111/\(filename).json", "models/workshop/222/\(filename).json"]
        let layers = [17,18].enumerated().map { offset, id in
            SceneRenderDescriptor.Layer(id: id, layerIndex: offset, name: "anchor\(id)", visible: true,
                originXYZ: [0,0,0], scaleXYZ: [1,1,1], alpha: 1, effects: [])
        }
        var descriptor = SceneRenderDescriptor(layers: layers)
        descriptor.modelMaterialLinks = models.map { .init(modelPath: $0, materialPath: "material") }
        let domain = try SceneScriptQuickJSDomain()
        try domain.configureLayerCatalog(descriptor)
        try domain.configurePreparedResourceLayerCatalog([
            models[0].lowercased(): .init(modelPath: models[0], renderSizeWH: [200,100], autosize: true),
            models[1].lowercased(): .init(modelPath: models[1], renderSizeWH: [320,160], autosize: true)])
        try domain.publishLayerSnapshot(.empty(frameIndex: 1), descriptor: descriptor)
        var owners: [SceneScriptValueOwner] = []
        var canonicalMutations: [String] = []
        var dimensions: [[Double]] = []
        var laterPreserved = true
        for index in 0..<2 {
            let source = """
                export let __workshopId = '\(index == 0 ? 111 : 222)';
                \(filename == "Ä" ? "String.prototype.toLowerCase = function(){throw Error('author-normalization-poison');};" : "")
                let \(variable), direct, updates = 0;
                export function init(v) {
                    \(variable) = thisScene.createLayer('\(rawPath)');
                    direct = thisScene.createLayer({image:'\(models[index])'.normalize('NFC'),size:new Vec2(60*2,30+30)});
                    if (!\(variable) || !direct || \(variable).size.x !== direct.size.x)
                        throw Error('prepared authored alias did not create: \(variable)');
                    \(variable).scale = new Vec3(2,3,1);
                    return true;
                }
                export function update(v) {
                    \(variable).alpha = ++updates === 1 ? 0.5 : 0.25;
                    return true;
                }
                """
            guard let references = SceneScriptDynamicImageReferenceAnalysis.references(in: source, descriptor: descriptor) else {
                fatalError("actual prepared reference analysis failed")
            }
            let paths = Dictionary(uniqueKeysWithValues: references.map { ($0.authoredPath.lowercased(),$0.modelPath) })
            let owner = try SceneScriptValueOwner(domain: domain, source: source,
                target: .layer(layerID: 17+index, field: .visibility), valueType: .bool,
                effectNames: [], dynamicImagePathsByAuthoredIdentity: paths,
                generation: 1, budget: .default)
            owners.append(owner)
            func evaluate() throws -> SceneScriptValueEvaluation {
                try owner.evaluate(input: .bool(true), frame: .init(timing: .init(
                    wallDate: Date(timeIntervalSince1970: 0), simulationFrameTime: 1/60, sceneTime: 0)),
                    scriptPropertiesJSON: "", userPropertiesJSON: "{}", expectedGeneration: 1,
                    interruptBudget: nil).get()
            }
            let created = try evaluate()
            let dynamic = created.layerMutations.filter(\.isDynamic)
            guard dynamic.count == 2, let size = dynamic.first?.size else { fatalError("alias typed admission") }
            canonicalMutations += dynamic.compactMap(\.assetPath)
            dimensions.append([size.x,size.y])
            owner.commitLayerMutations()
            let later = try evaluate().layerMutations.filter(\.isDynamic)
            laterPreserved = laterPreserved && later.count == 1 && later[0].assetPath == models[index]
                && later[0].size == size && later[0].alpha == 0.25
            owner.discardLayerMutations()
        }
        let failingSource = """
            export let __workshopId = '111';
            export function update(v) {
                thisScene.createLayer({name:'alias-failed',image:'\(rawPath)'});
                thisLayer.alpha = 0.2;
                throw Error('alias-owner-failure');
            }
            """
        let failingReferences = SceneScriptDynamicImageReferenceAnalysis.references(in: failingSource, descriptor: descriptor)!
        let failing = try SceneScriptValueOwner(domain: domain, source: failingSource,
            target: .layer(layerID: 17, field: .visibility), valueType: .bool, effectNames: [],
            dynamicImagePathsByAuthoredIdentity: Dictionary(uniqueKeysWithValues: failingReferences.map {
                ($0.authoredPath.lowercased(),$0.modelPath)
            }), generation: 1, budget: .default)
        let failure = failing.evaluate(input: .bool(true), frame: .init(timing: .init(
            wallDate: Date(timeIntervalSince1970: 0), simulationFrameTime: 1/60, sceneTime: 0)),
            scriptPropertiesJSON: "", userPropertiesJSON: "{}", expectedGeneration: 1, interruptBudget: nil)
        var failurePreserved = false
        if case let .failure(error) = failure {
            failurePreserved = String(describing: error).contains("alias-owner-failure")
        }
        let adjacent = try SceneScriptValueOwner(domain: domain, source: """
            export function update(v) {
                if (thisScene.getLayer('alias-failed') !== null || thisLayer.alpha !== 1)
                    throw Error('alias owner rollback leaked');
                const missing = '\(rawPath)';
                if (thisScene.createLayer(missing) !== null) throw Error('global alias escaped owner');
                if (thisScene.createLayer('models/unknown.json') !== null) throw Error('unknown alias');
                const healthy = thisScene.createLayer({image:'\(models[0])'});
                if (!healthy || healthy.size.x !== 200) throw Error('canonical neighbor rejected');
                thisLayer.alpha = 0.75;
                return new Vec3(healthy.size.x,healthy.size.y,1);
            }
            """, target: .layer(layerID: 17, field: .color), valueType: .vector3,
            effectNames: [], allowsStatefulLayerSideEffects: true, generation: 1, budget: .default)
        let healthy = try adjacent.evaluate(input: .vector3(0,0,0), frame: .init(timing: .init(
            wallDate: Date(timeIntervalSince1970: 0), simulationFrameTime: 1/60, sceneTime: 0)),
            scriptPropertiesJSON: "", userPropertiesJSON: "{}", expectedGeneration: 1, interruptBudget: nil).get()
        let healthyCount = healthy.layerMutations.filter(\.isDynamic).count
        adjacent.discardLayerMutations()
        withExtendedLifetime(owners) {}
        return ["canonicalMutations":canonicalMutations,"dimensions":dimensions,
            "laterPreserved":laterPreserved,"healthyCount":healthyCount,"failurePreserved":failurePreserved]
    }

    static func policyAndExceptions() throws -> [String: Any] {
        var first = SceneRenderDescriptor.Layer(id: 17, layerIndex: 0, name: "anchor", visible: true,
            originXYZ: [0, 0, 0], scaleXYZ: [1, 1, 1], alpha: 1, effects: [])
        first.sizeWH = [333, 222]; first.imagePath = "models/auto.json"
        var second = SceneRenderDescriptor.Layer(id: 18, layerIndex: 1, name: "same-resource", visible: true,
            originXYZ: [0, 0, 0], scaleXYZ: [1, 1, 1], alpha: 1, effects: [])
        second.sizeWH = [888, 444]
        second.imagePath = "models/auto.json"
        let descriptor = SceneRenderDescriptor(layers: [first, second])
        let domain = try SceneScriptQuickJSDomain()
        try domain.configureLayerCatalog(descriptor)
        let catalog: [String: SceneScriptPreparedResourceLayerTemplate] = [
            "models/auto.json": .init(modelPath: "models/auto.json", renderSizeWH: [200, 100], autosize: true),
            "models/manual.json": .init(modelPath: "models/manual.json", renderSizeWH: [200, 100])]
        try domain.configurePreparedResourceLayerCatalog(catalog)
        try domain.configurePreparedResourceLayerCatalog(catalog)
        var changed = catalog
        changed["models/auto.json"] = .init(modelPath: "models/auto.json", renderSizeWH: [300, 150], autosize: true)
        var identityRejected = false
        do { try domain.configurePreparedResourceLayerCatalog(changed) }
        catch { identityRejected = true }
        try domain.publishLayerSnapshot(.empty(frameIndex: 1), descriptor: descriptor)
        func owner(_ source: String) throws -> SceneScriptValueOwner {
            try .init(domain: domain, source: source, target: .layer(layerID: 17, field: .color),
                valueType: .vector3, effectNames: [], allowsStatefulLayerSideEffects: true,
                generation: 1, budget: .default)
        }
        func evaluate(_ value: SceneScriptValueOwner) throws -> SceneScriptValueEvaluation {
            try value.evaluate(input: .vector3(0,0,0), frame: .init(timing: .init(
                wallDate: Date(timeIntervalSince1970: 0), simulationFrameTime: 1/60,
                sceneTime: 0)), scriptPropertiesJSON: "", userPropertiesJSON: "{}",
                expectedGeneration: 1, interruptBudget: nil).get()
        }
        var exceptions = 0
        for input in ["{get value(){throw Error('geometry-getter');}}",
                      "new Proxy({}, {getPrototypeOf(){throw Error('geometry-proxy');}})"] {
            let failing = try owner("""
                export function update(v) {
                    thisScene.createLayer({name:'provisional',image:'models/manual.json',size:'10 20'});
                    thisLayer.alpha = 0.25;
                    thisScene.createLayer({image:'models/manual.json',size:\(input)});
                    thisLayer.alpha = 0.1; return v;
                }
                """)
            do { _ = try evaluate(failing) }
            catch { if String(describing: error).contains("geometry-") { exceptions += 1 } }
        }
        let healthy = try owner("""
            export function update(v) {
                if (thisScene.getLayer('provisional') !== null || thisLayer.alpha !== 1)
                    throw Error('failed geometry leaked transaction');
                const auto = thisScene.createLayer({name:'auto-policy',image:'models/auto.json',size:new Vec2(120,60),angles:'0 0.6 0'});
                const autoSigned = thisScene.createLayer({image:'models/auto.json',size:'-120 0'});
                const manual = thisScene.createLayer({name:'manual-policy',image:'models/manual.json'});
                if (auto.size.x !== 200 || autoSigned.size.x !== 200 ||
                    manual.size.x !== 1 || Math.abs(auto.angles.y - 0.6 * 180 / Math.PI) > 1e-9)
                    throw Error('prepared model geometry policy');
                thisLayer.alpha = 0.75;
                return new Vec3(auto.size.x,auto.size.y,manual.size.x);
            }
            """)
        let admitted = try evaluate(healthy)
        let dynamic = admitted.layerMutations.filter(\.isDynamic)
        let radians = dynamic.first?.angles.y ?? -1
        healthy.commitLayerMutations()
        let after = try owner("""
            export function update(v) {
                const auto = thisScene.getLayer('auto-policy'), manual = thisScene.getLayer('manual-policy');
                return new Vec3(auto.size.x,auto.size.y,manual.size.x);
            }
            """)
        let read = try evaluate(after)
        return ["identityRejected": identityRejected, "exceptionsPreserved": exceptions == 2,
            "healthyDynamicCount": dynamic.count, "anglesRadians": radians,
            "sameCallbackAndAfterCommitEqual": admitted.value == read.value]
    }

    static func run(path: String, variable: String, dimensions: String,
                    perspective: String) throws -> [String: Any] {
        let descriptor = SceneRenderDescriptor(layers: [
            .init(id: 17, layerIndex: 0, name: "anchor", visible: true,
                originXYZ: [0, 0, 0], scaleXYZ: [1, 1, 1], alpha: 1, effects: [])
        ])
        let domain = try SceneScriptQuickJSDomain()
        try domain.configureLayerCatalog(descriptor)
        try domain.configurePreparedResourceLayerCatalog([path.lowercased(): .init(
            modelPath: path, renderSizeWH: [640, 320])])
        try domain.publishLayerSnapshot(.empty(frameIndex: 1), descriptor: descriptor)
        let source = """
        let \(variable);
        export function update(v) {
            if (v.x === 0) {
                \(variable) = thisScene.createLayer({image:'\(path)',
                    size:\(dimensions), perspective:\(perspective),
                    origin:'10 20 30', scale:'2 3 4', color:'0.25 0.5 0.75'});
                const view = \(variable).size;
                view.x = 99;
                if (\(variable).size.x !== 200) throw Error('size alias');
                let locked = false;
                try { \(variable).size = new Vec2(9, 9); } catch(e) { locked = true; }
                if (!locked) throw Error('writable size');
                const text = thisScene.createLayer({text:'adjacent text',
                    size:'invalid unconsumed text dimensions'});
                if (text.size !== undefined) throw Error('text dimensions admitted');
                let rejected = 0;
                for (const size of ['200', '200 100 50', '200 nope',
                     new Vec2(0,100), new Vec2(-200,100),
                     new Vec2(Infinity,100), new Vec2(1e300,100),
                     {value:'200 100', script:'export function update(v){return v;}'},
                     {value:'200 100', user:'property'}]) {
                    if (thisScene.createLayer({image:'\(path)', size}) !== null)
                        throw Error('unsupported dimensions admitted');
                    rejected++;
                }
                for (const value of [1, 'true', null]) {
                    const peer = thisScene.createLayer({image:'\(path)', perspective:value});
                    if (!peer || peer.perspective !== false || peer.size.x !== 1)
                        throw Error('constructor perspective fallback');
                }
                for (const size of [[200,100], {x:200,y:100}, null, undefined]) {
                    const defaulted = thisScene.createLayer({image:'\(path)', size});
                    if (!defaulted || defaulted.size.x !== 1 || defaulted.size.y !== 1)
                        throw Error('nominal vector/default size');
                }
                const scalar = thisScene.createLayer({image:'\(path)', size:5});
                const staticValue = thisScene.createLayer({image:'\(path)', size:{value:'80 40'}});
                if (scalar.size.x !== 5 || scalar.size.y !== 5 ||
                    staticValue.size.x !== 80 || staticValue.size.y !== 40)
                    throw Error('static scalar/value size');
                if (thisScene.createLayer({image:'models/unprepared.json',size:'200 100'}) !== null)
                    throw Error('unknown prepared resource');
                const wrapped = thisScene.createLayer({text:{value:'wrapped',
                    script:'export function init(){return "x";}'}});
                if (wrapped.text === 'wrapped' || wrapped.text === 'x' ||
                    wrapped.size !== undefined) throw Error('text wrapper interpreted');
                if (rejected !== 9) throw Error('unsupported neighbor admitted: '+rejected);
            }
            if (v.x === 1) {
                \(variable).alpha = 0.25;
                \(variable).origin = new Vec3(40, 50, 60);
                thisScene.sortLayer(\(variable), 0);
            }
            if (v.x === 2 && (\(variable).alpha !== 1 ||
                \(variable).origin.x !== 10)) throw Error('mutation rollback');
            return new Vec3(\(variable).size.x, \(variable).size.y,
                \(variable).perspective ? 1 : 0);
        }
        """
        let owner = try SceneScriptValueOwner(domain: domain, source: source,
            target: .layer(layerID: 17, field: .color), valueType: .vector3,
            effectNames: [], allowsStatefulLayerSideEffects: true,
            generation: 1, budget: .default)
        func evaluate(_ input: Double) throws -> SceneScriptValueEvaluation {
            try owner.evaluate(input: .vector3(input, 0, 0),
                frame: .init(timing: .init(wallDate: Date(timeIntervalSince1970: 0),
                    simulationFrameTime: 1.0 / 60, sceneTime: input)),
                scriptPropertiesJSON: "", userPropertiesJSON: "{}",
                expectedGeneration: 1, interruptBudget: nil).get()
        }
        let first = try evaluate(0)
        guard let image = first.layerMutations.first(where: { $0.assetPath == path }),
              let text = first.layerMutations.first(where: { $0.assetPath == nil }),
              let size = image.size else { fatalError("missing typed creation geometry") }
        let copied = image.owned(by: .layer(layerID: 17, field: .origin))
            .resolvingAssetPath(to: "models/renamed.json")
        owner.commitLayerMutations()
        let changed = try evaluate(1)
        guard let later = changed.layerMutations.first(where: { $0.layerID == image.layerID })
            else { fatalError("missing full dynamic upsert") }
        owner.discardLayerMutations()
        let restored = try evaluate(2)
        func vector(_ value: SceneDynamicValue) -> [Double] {
            guard case let .vector3(x,y,z) = value else { fatalError("vector result") }
            return [x,y,z]
        }
        return ["createdCount": first.layerMutations.count,
            "sameCallback": vector(first.value), "afterCommit": vector(changed.value),
            "afterDiscard": vector(restored.value),
            "typedSize": [size.x,size.y], "typedPerspective": image.perspective as Any,
            "typedOrigin": [image.origin.x,image.origin.y,image.origin.z],
            "typedScale": [image.scale.x,image.scale.y,image.scale.z],
            "copyPreservesGeometry": copied.size == size && copied.perspective == image.perspective,
            "textSizeAbsent": text.size == nil,
            "laterSizePreserved": later.size == size,
            "laterPerspectivePreserved": later.perspective == image.perspective,
            "laterOrder": later.orderIndex]
    }
    static func main() throws {
        let runs = try [
            run(path: "models/plain.json", variable: "clone", dimensions: "'200 100'", perspective: "true"),
            run(path: "models/renamed-resource.json", variable: "shadowCopy",
                dimensions: "new Vec2(100 * 2, 250 - 150)", perspective: "!false"),
            run(path: "models/another.json", variable: "createdGeometry",
                dimensions: "new Vec2(200, 100)", perspective: "false")
        ]
        print(String(decoding: try JSONSerialization.data(withJSONObject: ["runs": runs,
            "policy": policyAndExceptions(),
            "aliases": [authoredAliases("common", "aliasCopy"), authoredAliases("renamed", "renamedCopy"),
                authoredAliases("Ä", "unicodeCopy"), authoredAliases("e\u{0301}", "equivalentCopy"),
                authoredAliases(Array(repeating: String(repeating: "İ", count: 120), count: 4).joined(separator: "/"), "expandedCopy")]],
            options: [.sortedKeys]), as: UTF8.self))
    }
}
'''


class SceneScriptCreateGeometryTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.temporary = tempfile.TemporaryDirectory(prefix="scene-create-geometry-")
        cls.addClassCleanup(cls.temporary.cleanup)
        binary = compile_vector_harness(Path(cls.temporary.name), HARNESS, "create-geometry")
        completed = subprocess.run([str(binary)], capture_output=True, text=True)
        if completed.returncode:
            raise AssertionError(completed.stdout + completed.stderr)
        result = json.loads(completed.stdout.strip().splitlines()[-1])
        cls.runs, cls.policy, cls.aliases = result["runs"], result["policy"], result["aliases"]

    def test_prepared_authored_aliases_are_owner_local_and_canonical_in_typed_upserts(self) -> None:
        for name, case in zip(("common", "renamed", "Ä", "e\u0301", "/".join(["İ" * 120] * 4)), self.aliases):
            with self.subTest(name=name):
                self.assertEqual(case["canonicalMutations"], [
                    f"models/workshop/111/{name}.json", f"models/workshop/111/{name}.json",
                    f"models/workshop/222/{name}.json", f"models/workshop/222/{name}.json"])
                self.assertEqual(case["dimensions"], [[200,100],[320,160]])
                self.assertIs(case["laterPreserved"], True)
                self.assertIs(case["failurePreserved"], True)
                self.assertEqual(case["healthyCount"], 1)

    def test_prepared_policy_identity_actual_exceptions_and_healthy_peer(self) -> None:
        for key in ("identityRejected", "exceptionsPreserved", "sameCallbackAndAfterCommitEqual"):
            self.assertIs(self.policy[key], True, key)
        self.assertEqual(self.policy["healthyDynamicCount"], 3)
        self.assertAlmostEqual(self.policy["anglesRadians"], 0.6)

    def test_string_vec2_renamed_and_equivalent_constructor_inputs(self) -> None:
        for index, run in enumerate(self.runs):
            with self.subTest(index=index):
                self.assertEqual(run["typedSize"], [200, 100])
                self.assertEqual(run["typedOrigin"], [10, 20, 30])
                self.assertEqual(run["typedScale"], [2, 3, 4])
                self.assertEqual(run["typedPerspective"], index != 2)
                expected = [200, 100, int(index != 2)]
                for phase in ("sameCallback", "afterCommit", "afterDiscard"):
                    self.assertEqual(run[phase], expected)

    def test_full_upsert_copy_and_rollback_preserve_readonly_geometry(self) -> None:
        for run in self.runs:
            for key in ("copyPreservesGeometry", "laterSizePreserved", "laterPerspectivePreserved"):
                self.assertIs(run[key], True, key)
            self.assertEqual(run["laterOrder"], 0)

    def test_unsupported_geometry_is_local_and_text_wrapper_remains_unconsumed(self) -> None:
        for run in self.runs:
            self.assertEqual(run["createdCount"], 12)
            self.assertIs(run["textSizeAbsent"], True)


if __name__ == "__main__":
    unittest.main()
