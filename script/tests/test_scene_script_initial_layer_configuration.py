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
    C_SOURCES, QUICKJS, ROOT, VM, SWIFT_PREAMBLE, compile_vector_harness,
)


# Compile the actual configuration that the scalar projection now consults;
# this carrier supplies only the ordinary disabled configuration.
PREAMBLE = SWIFT_PREAMBLE.replace(
    "        var bloom = Bloom()", "        var bloom = SceneBloomConfiguration.disabled", 1)
EXTRA_SOURCES = (
    VM.parent.parent / "Rendering/Composition/SceneBloomPostProcess.swift",
    VM.parent.parent / "Resources/Textures/SceneResourceBudget.swift",
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
        // Both catalogs lack raw configuration: prepared kind must carry
        // the property capability identity, independently of that JSON.
        var imageCatalog = descriptor(.null)
        imageCatalog.layers[0].initialConfiguration = nil
        imageCatalog.layers[0].contentKind = "image"
        var containerCatalog = imageCatalog
        containerCatalog.layers[0].contentKind = "container"
        result["imageCapabilityChangesSignature"] = try
            SceneScriptQuickJSDomain.catalogSignature(for: imageCatalog)
            != SceneScriptQuickJSDomain.catalogSignature(for: containerCatalog)
        let imageCapabilityDomain = try SceneScriptQuickJSDomain()
        try imageCapabilityDomain.configureLayerCatalog(imageCatalog)
        do {
            try imageCapabilityDomain.configureLayerCatalog(containerCatalog)
            result["imageCapabilityDriftRejected"] = false
        } catch {
            result["imageCapabilityDriftRejected"] = true
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
        let imageDomain = try SceneScriptQuickJSDomain()
        try imageDomain.configureLayerCatalog(authored)
        let ordinary = SceneScriptPreparedResourceLayerTemplate(
            modelPath: "models/fresh-photo.json", renderSizeWH: [64, 48])
        let puppet = SceneScriptPreparedResourceLayerTemplate(
            modelPath: "models/fresh-rig.json", renderSizeWH: [64, 48],
            puppetMeshPath: "meshes/fresh-rig.mdl")
        try imageDomain.configurePreparedResourceLayerCatalog([
            ordinary.modelPath: ordinary, puppet.modelPath: puppet,
        ])
        do {
            var changed = puppet
            changed.puppetMeshPath = nil
            try imageDomain.configurePreparedResourceLayerCatalog([
                ordinary.modelPath: ordinary, changed.modelPath: changed,
            ])
            result["puppetCatalogMarkerDriftRejected"] = false
        } catch {
            result["puppetCatalogMarkerDriftRejected"] = true
        }
        try imageDomain.publishLayerSnapshot(.empty(frameIndex: 1), descriptor: authored)
        // These self-authored requests consume only typed prepared metadata;
        // the harness never opens the named model, mesh or texture files.
        let imageSource = """
        export function update(v) {
            const instance = thisScene.createLayer('models/fresh-rig.json');
            if (!instance) throw Error('prepared default');
            let rejected = 0;
            for (const key of ['animations', 'puppetAnimationLayers', 'effects']) {
                const request = {image:'models/fresh-rig.json'};
                request[key] = [];
                if (thisScene.createLayer(request) !== null) throw Error('unsupported field');
                rejected++;
            }
            const inherited = Object.create({effects:undefined});
            inherited.image = 'models/fresh-rig.json';
            if (thisScene.createLayer(inherited) !== null) throw Error('inherited field');
            rejected++;
            const photo = thisScene.createLayer({image:'models/fresh-photo.json',
                animations:[], puppetAnimationLayers:[], effects:[]});
            if (!photo) throw Error('ordinary regression');
            return new Vec3(1, 1, rejected);
        }
        """
        let imageOwner = try SceneScriptValueOwner(domain: imageDomain, source: imageSource,
            target: .layer(layerID: 17, field: .color), valueType: .vector3,
            effectNames: [], allowsStatefulLayerSideEffects: true,
            generation: 1, budget: .default)
        let imageEvaluation = try imageOwner.evaluate(input: .vector3(0, 0, 0),
            frame: .init(timing: .init(wallDate: Date(timeIntervalSince1970: 0),
                simulationFrameTime: 1.0 / 60, sceneTime: 0)),
            scriptPropertiesJSON: "", userPropertiesJSON: "{}",
            expectedGeneration: 1, interruptBudget: nil).get()
        guard case let .vector3(x, y, z) = imageEvaluation.value else { fatalError("image result") }
        result["puppetCatalogBridgeValues"] = [x, y, z]
        result["puppetCatalogBridgeMutationPaths"] = imageEvaluation.layerMutations.compactMap(\.assetPath).sorted()
        imageOwner.commitLayerMutations()
        let compositionDomain = try SceneScriptQuickJSDomain()
        try compositionDomain.configureLayerCatalog(authored)
        let compositionTemplate = SceneScriptPreparedResourceLayerTemplate(
            modelPath: "models/owned-composition.json", renderSizeWH: [640, 480], kind: .composition)
        try compositionDomain.configurePreparedResourceLayerCatalog([
            compositionTemplate.modelPath: compositionTemplate])
        try compositionDomain.publishLayerSnapshot(.empty(frameIndex: 1), descriptor: authored)
        let compositionSource = """
        let born;
        export function update(v) {
            if(v.x===0){
                const choices=[undefined,false,!!1];
                for(let i=0;i<choices.length;i++){
                    const request={image:'models/owned-composition.json',name:'own-composition-'+i,size:'18 9'};
                    if(i>0)request.perspective=choices[i];
                    const layer=thisScene.createLayer(request);
                    if(!layer)throw Error('prepared composition');
                    if(i===2)born=layer;
                }
                return new Vec3(3, born.perspective?1:0, born.size.x);
            }
            if(thisScene.getLayer('own-composition-2')!==null||thisScene.getInitialLayerConfig(born)!==null)
                throw Error('late rejection leaked');
            return new Vec3(7,8,9);
        }
        """
        let compositionOwner = try SceneScriptValueOwner(domain: compositionDomain,
            source: compositionSource, target: .layer(layerID: 17, field: .origin),
            valueType: .vector3, effectNames: [], allowsStatefulLayerSideEffects: true,
            generation: 1, budget: .default)
        let compositionStep = { (x: Double) throws in
            try compositionOwner.evaluate(input: .vector3(x,0,0),
                frame: .init(timing: .init(wallDate: Date(timeIntervalSince1970: 0),
                    simulationFrameTime: 1.0/60, sceneTime: x)),
                scriptPropertiesJSON: "", userPropertiesJSON: "{}",
                expectedGeneration: 1, interruptBudget: nil).get()
        }
        let compositionBorn = try compositionStep(0)
        result["compositionBridgeTriState"] = compositionBorn.layerMutations.map {
            $0.perspective.map { $0 ? 1 : 0 } ?? -1 }
        result["compositionBridgeSizes"] = compositionBorn.layerMutations.map { [$0.size!.x,$0.size!.y] }
        result["compositionBridgeOutput"] = compositionBorn.value == .vector3(3,1,18)
        compositionOwner.discardLayerMutations()
        result["compositionLateRejectNoResidue"] = try compositionStep(1).value == .vector3(7,8,9)
        compositionOwner.commitLayerMutations()
        let sourceLayer = SceneRenderDescriptor.Layer(id: 70, layerIndex: 0, name: "source-container",
            visible: true, originXYZ: [0,0,10], scaleXYZ: [1,1,1], alpha: 1,
            effects: [], contentKind: "composition", imagePath: compositionTemplate.modelPath,
            utilityLayer: .init(kind: .composition, copyBackground: true, passthrough: false))
        var sourceDescriptor = SceneRenderDescriptor(layers: [sourceLayer])
        sourceDescriptor.camera.orthoHeight = 600
        let setter = SceneScriptLayerMutation(kind: .upsert, isDynamic: false,
            fields: [.perspective], layerID: 70, orderIndex: 0, visible: true, alpha: 1,
            origin: .zero, scale: .init(repeating: 1), angles: .zero, color: .init(repeating: 1),
            pointSize: 32, text: "", font: "", assetPath: nil, perspective: true)
        let sourceRuntime = SceneScriptDynamicLayerRuntime(descriptor: sourceDescriptor,
            authoredMutationLayerIDs: [70])
        result["authoredCompositionOrthoSetter"] = (try? sourceRuntime.apply([setter]).get()) != nil
            && sourceRuntime.snapshot().authoredLayerValues[.layer(layerID: 70,field: .perspective)] == .bool(true)
        sourceDescriptor.camera.orthoHeight = nil
        let nativeRuntime = SceneScriptDynamicLayerRuntime(descriptor: sourceDescriptor,
            authoredMutationLayerIDs: [70])
        if case .failure = nativeRuntime.apply([setter]) { result["nativeCompositionSetterRejected"] = true }
        else { result["nativeCompositionSetterRejected"] = false }
        var grouped = sourceLayer; grouped.childLayerIDs = [71]
        sourceDescriptor.layers = [grouped]; sourceDescriptor.camera.orthoHeight = 600
        let groupedRuntime = SceneScriptDynamicLayerRuntime(descriptor: sourceDescriptor,
            authoredMutationLayerIDs: [70])
        if case .failure = groupedRuntime.apply([setter]) { result["groupedCompositionSetterRejected"] = true }
        else { result["groupedCompositionSetterRejected"] = false }
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
        binary = compile_vector_harness(directory, HARNESS, "initial-configuration",
            extra_swift_sources=EXTRA_SOURCES, preamble=PREAMBLE)
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
                    "invalidJSONSignatureRejected", "imageCapabilityChangesSignature",
                    "imageCapabilityDriftRejected"):
            with self.subTest(key=key):
                self.assertIs(self.swift_result[key], True)
        self.assertEqual(
            self.swift_result["callbackValuesAfterCatalogRejectionAndCurrentPublication"],
            [[77, 3, 1], [77, 3, 9]],
        )

    def test_empty_composition_tristate_reaches_swift_and_late_discard(self) -> None:
        self.assertGreaterEqual(self.c_result["compositionFacts"], 25)
        self.assertEqual(self.swift_result["compositionBridgeTriState"], [-1, 0, 1])
        self.assertEqual(self.swift_result["compositionBridgeSizes"], [[18, 9]] * 3)
        self.assertIs(self.swift_result["compositionBridgeOutput"], True)
        self.assertIs(self.swift_result["compositionLateRejectNoResidue"], True)
        for key in ("authoredCompositionOrthoSetter", "nativeCompositionSetterRejected",
                    "groupedCompositionSetterRejected"):
            with self.subTest(key=key):
                self.assertIs(self.swift_result[key], True)

    def test_prepared_puppet_marker_reaches_actual_create_admission(self) -> None:
        self.assertIs(self.swift_result["puppetCatalogMarkerDriftRejected"], True)
        self.assertEqual(self.swift_result["puppetCatalogBridgeValues"], [1, 1, 4])
        self.assertEqual(self.swift_result["puppetCatalogBridgeMutationPaths"], [
            "models/fresh-photo.json", "models/fresh-rig.json",
        ])


if __name__ == "__main__":
    unittest.main()
