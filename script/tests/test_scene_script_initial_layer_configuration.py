"""Authored initial configuration through the production QuickJS and Swift bridge.

The descriptor preamble supplies external metadata only. Catalog admission,
serialization, callbacks and create/destroy rollback use production sources.
Dynamic snapshots are deliberately unavailable; creating a dynamic layer must
not inspect unknown nested values as a side effect of this API.
"""
from __future__ import annotations

import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

from .scene_vector_vm_test_support import (
    C_SOURCES, QUICKJS, ROOT, VM, compile_vector_harness,
)


HARNESS = r'''
import Foundation

@main enum Harness {
    static func descriptor(_ configuration: SceneJSONValue) -> SceneRenderDescriptor {
        .init(layers: [
            .init(id: 17, layerIndex: 0, name: "anchor", visible: true,
                originXYZ: [1, 2, 3], scaleXYZ: [1, 1, 1], alpha: 1,
                effects: [], initialConfiguration: configuration),
            .init(id: 18, layerIndex: 1, name: "nil-config", visible: true,
                originXYZ: [0, 0, 0], scaleXYZ: [1, 1, 1], alpha: 1, effects: [])
        ])
    }
    static func main() throws {
        let json = #"{"id":17,"name":"anchor","origin":{"value":"1 2 3","script":"export function update(v){return v;}","scriptproperties":{"bias":{"value":2,"user":"slider"}}},"nested":{"id":77,"parts":[{"id":88,"name":"虹"}]},"flags":[true,null,3]}"#
        let configuration = try JSONDecoder().decode(SceneJSONValue.self, from: Data(json.utf8))
        let authored = descriptor(configuration)
        let domain = try SceneScriptQuickJSDomain()
        try domain.configureLayerCatalog(authored)
        try domain.publishLayerSnapshot(.empty(frameIndex: 1), descriptor: authored)
        var result: [String: Any] = [:]
        guard case let .object(fields) = configuration else { fatalError("fixture JSON") }
        let reordered = descriptor(.object(Dictionary(uniqueKeysWithValues:
            Array(fields).reversed().map { ($0.key, $0.value) })))
        result["signatureOrderIndependent"] = try
            SceneScriptQuickJSDomain.catalogSignature(for: authored)
            == SceneScriptQuickJSDomain.catalogSignature(for: reordered)
        try domain.configureLayerCatalog(reordered)
        result["sameCatalogAccepted"] = true
        var changedFields = fields
        changedFields["nested"] = .object(["id": .number(99)])
        let changed = descriptor(.object(changedFields))
        result["differentConfigurationChangesSignature"] = try
            SceneScriptQuickJSDomain.catalogSignature(for: authored)
            != SceneScriptQuickJSDomain.catalogSignature(for: changed)
        do {
            try domain.configureLayerCatalog(changed)
            result["differentCatalogRejected"] = false
        } catch {
            result["differentCatalogRejected"] = true
        }
        let nonfinite = descriptor(.object(["nested": .number(.infinity)]))
        do {
            _ = try SceneScriptQuickJSDomain.catalogSignature(for: nonfinite)
            result["invalidJSONSignatureRejected"] = false
        } catch {
            result["invalidJSONSignatureRejected"] = true
        }
        let source = """
        function verify(c) {
            if (!c || 'id' in c || c.nested.id !== 77 || c.nested.parts[0].id !== 88 ||
                c.nested.parts[0].name !== '虹' || c.origin.value !== '1 2 3' ||
                c.origin.script !== 'export function update(v){return v;}' ||
                c.origin.scriptproperties.bias.user !== 'slider' ||
                c.origin.scriptproperties.bias.value !== 2 ||
                c.flags.length !== 3 || c.flags[0] !== true || c.flags[1] !== null)
                throw Error('raw configuration');
        }
        export function update(v) {
            for (const q of ['anchor', 0, thisScene.getLayer('anchor')]) {
                const a = thisScene.getInitialLayerConfig(q); verify(a);
                a.nested.parts[0].name = 'modified'; a.flags.push(9);
                a.origin.scriptproperties.bias.value = 99;
                const b = thisScene.getInitialLayerConfig(q); verify(b);
                if (a === b || a.nested === b.nested || a.flags === b.flags)
                    throw Error('not independent');
            }
            if (thisScene.getInitialLayerConfig('nil-config') !== null)
                throw Error('unavailable authored config');
            if (thisLayer.origin.x !== (v.x === 0 ? 1 : 9)) throw Error('current origin');
            const c = thisScene.getInitialLayerConfig(thisLayer);
            return new Vec3(c.nested.id, c.flags.length, thisLayer.origin.x);
        }
        """
        let owner = try SceneScriptValueOwner(domain: domain, source: source,
            target: .layer(layerID: 17, field: .color), valueType: .vector3,
            effectNames: [], allowsStatefulLayerSideEffects: true,
            generation: 1, budget: .default)
        var values: [[Double]] = []
        for input in [0.0, 1.0] {
            if input == 1 {
                let target = SceneDynamicTarget.layer(layerID: 17, field: .origin)
                let published = SceneDynamicSnapshotResolver().resolve(
                    frameIndex: 2, generation: 2,
                    definitions: [.init(target: target, valueType: .vector3,
                        authoredValue: .vector3(1, 2, 3))],
                    sceneScriptValues: [target: .vector3(9, 8, 7)]).snapshot
                try domain.publishLayerSnapshot(published, descriptor: authored)
            }
            let evaluation = try owner.evaluate(input: .vector3(input, 0, 0),
                frame: .init(timing: .init(wallDate: Date(timeIntervalSince1970: 0),
                    simulationFrameTime: 1.0 / 60, sceneTime: input)),
                scriptPropertiesJSON: "", userPropertiesJSON: "{}",
                expectedGeneration: 1, interruptBudget: nil).get()
            guard case let .vector3(x, y, z) = evaluation.value else { fatalError("vector result") }
            values.append([x, y, z])
            owner.commitLayerMutations()
        }
        result["callbackValuesAfterCatalogRejectionAndCurrentPublication"] = values
        print(String(decoding: try JSONSerialization.data(withJSONObject: result,
            options: [.sortedKeys]), as: UTF8.self))
    }
}
'''


class SceneScriptInitialLayerConfigurationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.temporary = tempfile.TemporaryDirectory(prefix="scene-initial-config-")
        cls.addClassCleanup(cls.temporary.cleanup)
        directory = Path(cls.temporary.name)
        binary = compile_vector_harness(directory, HARNESS, "initial-configuration")
        clang = shutil.which("clang")
        if clang is None:
            raise RuntimeError("clang is required")
        c_binary = directory / "initial-configuration-c"
        fixture = ROOT / "script/tests/fixtures/SceneInitialLayerConfigurationQuickJSCases.c"
        compiled = subprocess.run([
            clang, "-std=c11", "-O0", "-I", str(VM), "-I", str(QUICKJS),
            str(fixture), *(str(directory / f"{source.stem}.o") for source in C_SOURCES),
            "-lm", "-o", str(c_binary),
        ], capture_output=True, text=True)
        if compiled.returncode:
            raise AssertionError(compiled.stdout + compiled.stderr)
        cls.swift_result = cls.run_binary(binary)
        cls.c_result = cls.run_binary(c_binary)

    @staticmethod
    def run_binary(binary: Path) -> dict:
        completed = subprocess.run([str(binary)], capture_output=True, text=True)
        if completed.returncode:
            raise AssertionError(completed.stdout + completed.stderr)
        return json.loads(completed.stdout.strip().splitlines()[-1])

    def test_authored_raw_config_deep_copy_and_dynamic_unavailability(self) -> None:
        self.assertEqual(self.c_result["failures"], 0)
        self.assertGreaterEqual(self.c_result["facts"], 30)

    def test_swift_catalog_identity_and_actual_callbacks(self) -> None:
        for key in ("signatureOrderIndependent", "sameCatalogAccepted",
                    "differentConfigurationChangesSignature", "differentCatalogRejected",
                    "invalidJSONSignatureRejected"):
            with self.subTest(key=key):
                self.assertIs(self.swift_result[key], True)
        self.assertEqual(
            self.swift_result["callbackValuesAfterCatalogRejectionAndCurrentPublication"],
            [[77, 3, 1], [77, 3, 9]],
        )


if __name__ == "__main__":
    unittest.main()
