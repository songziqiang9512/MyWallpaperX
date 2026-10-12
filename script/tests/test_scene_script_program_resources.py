"""Common Program resource discovery through real QuickJS and typed mutations.

Only external prepared model/descriptor metadata is supplied by the shared fixture;
source projection, discovery, VM admission, owner aliases and callbacks are real.
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
    static let frame = SceneScriptFrameInput(timing: .init(
        wallDate: Date(timeIntervalSince1970: 0), simulationFrameTime: 1/60, sceneTime: 0))
    static func binding(_ source: String, _ field: String) -> SceneScriptBindingIR {
        let value: SceneJSONValue = field == "visible" ? .bool(true) : field == "alpha" ? .number(1)
            : .string(field == "origin" ? "0 0 0" : "authored")
        return .init(source: source, owner: .init(kind: .object, objectIndex: 0, objectID: 17,
            effectIndex: nil, effectID: nil, passIndex: nil, passID: nil),
            targetPath: [.key("objects"), .index(0), .key(field)], properties: [:], authoredValue: value,
            valueType: field == "visible" ? .boolean : field == "alpha" ? .number : .string,
            wrapperKeys: ["script", "value"])
    }
    static func descriptor(_ sources: [String], _ models: [String]) -> SceneRenderDescriptor {
        var result = SceneRenderDescriptor(layers: [.init(id: 17, layerIndex: 0, name: "anchor",
            visible: true, originXYZ: [0,0,0], scaleXYZ: [1,1,1], alpha: 1, effects: [],
            contentKind: "text", textScript: .init(source: sources[3]), text: "authored",
            textStyle: .init(fontPath: nil, colorRGB: [1,1,1], pointSize: 24))])
        result.modelMaterialLinks = models.map { .init(modelPath: $0, materialPath: "material") }
        return result
    }
    static func compile(_ d: SceneRenderDescriptor, _ bindings: [SceneScriptBindingIR],
        excluded: Set<SceneDynamicTarget> = []) throws -> SceneScriptQuickJSProgramCandidate {
        let projection = SceneScriptVectorProgram.project(descriptor: d, scriptBindings: bindings,
            excludedTargets: excluded)
        return try SceneScriptQuickJSProgramCandidate.compile(authoredDescriptor: d, runtimeDescriptor: d,
            scriptBindings: bindings, vectorProjection: projection, routeExcludedTargets: excluded, userPropertyDefinitions: [],
            timelineTargets: [], scalarExcludedTargets: excluded, stringExcludedTargets: excluded,
            admittedVectorPassTargets: [], generation: 1)
    }
    static func source(_ path: String, _ variable: String, _ equivalent: Bool, _ mixed: Bool) -> String {
        """
        export let __workshopId = '111';
        let \(variable);
        // thisScene.createLayer('models/comment.json');
        const fake = "thisScene.createLayer('models/string.json')";
        function request(x) { return thisScene.createLayer(x); }
        export function init(value) {
            \(mixed ? "if(request('models/unknown.json') !== null) throw Error('unknown');" : "")
            \(variable) = thisScene.createLayer({note: "image: 'models/fake.json'", image: '\(path)', size:'100 50',
                scale: new Vec3(\(equivalent ? "2/4" : "1/2"),1,1)});
            if (!\(variable)) throw Error('literal was not prepared');
            \(variable).alpha = 0.25;
            return value;
        }
        export function update(value) { \(variable).alpha = 0.5; return value; }
        """
    }
    static func families(_ filename: String, _ variable: String, _ equivalent: Bool, _ mixed: Bool) throws -> [String: Any] {
        let fields = ["visible", "alpha", "origin", "text"]
        let raw = fields.map { "models/\(filename)-\($0).json" }
        let models = raw.map { "models/workshop/111/" + $0.dropFirst(7) }
        let sources = raw.map { source($0, variable, equivalent, mixed) }
        let d = descriptor(sources, models)
        let bindings = zip(sources, fields).map(binding)
        let c = try compile(d, bindings)
        let domain = c.domain!
        let projection = SceneScriptVectorProgram.project(descriptor: d, scriptBindings: bindings)
        let planned = SceneScriptQuickJSProgramCandidate.plannedOwnerSources(authoredDescriptor: d,
            runtimeDescriptor: d, scriptBindings: bindings, vectorProjection: projection,
            plannedVectorTargets: projection.nonPassTargets, timelineTargets: [], scalarExcludedTargets: [],
            stringExcludedTargets: [], excludedStandaloneCursorLayerIDs: [], dynamicImageRequestsOnly: true)
        let upperBound = Set(planned.flatMap { SceneScriptDynamicImageReferenceAnalysis.references(in: $0, descriptor: d) ?? [] }.map(\.modelPath))
        try domain.configureDynamicImageCatalog(Dictionary(uniqueKeysWithValues: models.map {
            ($0.lowercased(), SceneScriptDynamicImageLayerTemplate(modelPath: $0, renderSizeWH: [200,100], autosize: false)) }))
        try domain.publishLayerSnapshot(.empty(frameIndex: 1), descriptor: d)
        let v = c.vectorProgram.evaluate(inputs: [.layer(layerID: 17, field: .visibility): .bool(true),
            .layer(layerID: 17, field: .origin): .vector3(0,0,0)], effectivePropertyValues: [:], frame: frame)
        let a = c.scalarProgram.evaluate(inputs: [.layer(layerID: 17, field: .alpha): .scalar(1)], frame: frame)
        let t = c.stringProgram.evaluate(inputs: [.text(layerID: 17, field: .content): .string("authored")], frame: frame)
        let mutations = v.layerMutations + a.layerMutations + t.layerMutations
        let dynamic = mutations.filter(\.isDynamic)
        return ["complete": c.constructionReport.isComplete, "requested": domain.dynamicImageRequestedModelPaths.sorted(),
            "expected": models.sorted(), "upperBound": upperBound.sorted(), "failures": v.failures.count+a.failures.count+t.failures.count,
            "createdPaths": dynamic.compactMap(\.assetPath).sorted(), "sizes": dynamic.map { [$0.size!.x,$0.size!.y] },
            "scales": dynamic.map { $0.scale.x }, "alpha": dynamic.map { $0.alpha }]
    }
    static func main() throws {
        var out: [String: Any] = [:]
        out["families"] = try families("asset", "created", false, false)
        out["variants"] = try families("renamed-resource", "renamedNode", true, true)
        out["unicode"] = try families("Ä-resource", "renamedUnicode", true, true)
        let sources = ["export function update(v){return v;}", "export function update(v){return v;}",
            "export function update(v){return v;}", "export function update(v){return v;}"]
        let available = ["models/real.json", "models/fake.json", "models/comment.json", "models/string.json"]
        let d = descriptor(sources, available)
        let forms = ["thisScene.createLayer('models/real.json')",
            "// fake\u{2028}thisScene.createLayer('models/real.json')",
            "// fake\u{2029}thisScene.createLayer({ /* image:'models/fake.json' */ image:'models/real.json' })",
            "thisScene.createLayer({ note: \"image:'models/fake.json'\", 'image':'models/real.json' })",
            "thisScene.createLayer(dynamic); thisScene.createLayer('models/missing.json'); thisScene.createLayer('models/real.json')"]
        out["literalForms"] = forms.map { SceneScriptDynamicImageReferenceAnalysis.references(in: $0, descriptor: d)?.map(\.modelPath) ?? [] }
        let nonrequests = ["// thisScene.createLayer('models/comment.json')", "\"thisScene.createLayer('models/string.json')\"",
            "thisScene.createLayer({text:'image: models/real.json'})", "const r=/thisScene.createLayer('models/real.json')/;",
            "const t=`thisScene.createLayer('models/real.json')`;", "other.thisScene.createLayer('models/real.json')"]
        out["nonrequests"] = nonrequests.dropLast().map { SceneScriptDynamicImageReferenceAnalysis.references(in: $0, descriptor: d)?.count ?? 0 }
        let healthy = source("models/real.json", "healthy", false, false)
        let bad = "thisLayer.name='evaluated but rejected'; " + source("models/fake.json", "failed", false, false) + " throw Error('reject module');"
        let rebuildD = descriptor([healthy,bad,sources[2],sources[3]], available)
        let rebuilt = try compile(rebuildD, [binding(healthy,"visible"), binding(bad,"alpha")])
        out["reconstruction"] = ["complete": rebuilt.constructionReport.isComplete,
            "requested": rebuilt.domain?.dynamicImageRequestedModelPaths.sorted() ?? []]
        let excluded = try compile(d, [binding(healthy,"alpha"),binding(healthy,"alpha")])
        out["duplicates"] = excluded.domain?.dynamicImageRequestedModelPaths.sorted() ?? []
        let routeSource = source("models/fake.json", "routedOut", false, false)
            + " export function mediaPlaybackChanged(event){}"
        let routed = try SceneScriptVectorMediaRouteCandidate.compile(initialPassTargets: [], route: .disableGeneric,
            cancellationCheck: {}, builder: { _, excluded in
                try compile(d, [binding(routeSource,"visible"), binding(healthy,"alpha")], excluded: excluded)
            })!
        out["finalRoute"] = ["requested": routed.programs.domain?.dynamicImageRequestedModelPaths.sorted() ?? [],
            "mediaOwnersObserved": routed.mediaOwnerTargets.count]
        let domain = try SceneScriptQuickJSDomain(); try domain.configureLayerCatalog(d)
        _ = try SceneScriptValueOwner(domain: domain, source: healthy, target: .layer(layerID:17,field:.visibility),
            valueType: .bool, effectNames: [], generation: 1, budget: .default)
        out["valueOnlyBool"] = domain.dynamicImageRequestedModelPaths.sorted()
        _ = try SceneScriptValueOwner(domain: domain, source: healthy,
            target: .effectVisibility(layerID:17,effectIndex:0), valueType: .bool, effectNames: ["effect"],
            allowsStatefulLayerSideEffects: true, generation: 1, budget: .default)
        out["effectBool"] = domain.dynamicImageRequestedModelPaths.sorted()

        var cursorD = d; cursorD.layers[0].sizeWH = [100,50]
        let cursorSource = """
            export function cursorEnter(e){
                const cursorNode=thisScene.createLayer({image:'models/real.json',size:'100 50'});
                if(!cursorNode) throw Error('cursor literal unprepared');
                cursorNode.alpha=0.75;
            }
            """
        let cursor = try SceneScriptQuickJSProgramCandidate.compile(authoredDescriptor: cursorD, runtimeDescriptor: cursorD,
            scriptBindings: [binding(cursorSource,"visible")], vectorProjection: .init(candidates:[],materialBindings:[]),
            userPropertyDefinitions: [], timelineTargets: [], scalarExcludedTargets: [], stringExcludedTargets: [],
            admittedVectorPassTargets: [], generation: 1)
        try cursor.domain!.configureDynamicImageCatalog(["models/real.json":
            .init(modelPath:"models/real.json",renderSizeWH:[200,100],autosize:false)])
        try cursor.domain!.publishLayerSnapshot(.empty(frameIndex: 1), descriptor: cursorD)
        let hit = SceneScriptCursorHit(layerID:17,worldPosition:.zero,localPosition:.zero)
        let cursorResult = cursor.cursorProgram.dispatch(batch:.init(samples:[.init(hits:[17:hit],primaryButtonIsDown:false)],overflowed:false),
            frame:frame,userPropertiesJSON:"{}")
        out["standaloneCursor"] = ["requested": cursor.domain!.dynamicImageRequestedModelPaths.sorted(),
            "failures":cursorResult.failures.count,"paths":cursorResult.layerMutations.filter(\.isDynamic).compactMap(\.assetPath),
            "alpha":cursorResult.layerMutations.filter(\.isDynamic).map(\.alpha)]
        let aliasModels = ["models/workshop/111/shared.json", "models/workshop/222/shared.json"]
        var aliasD = SceneRenderDescriptor(layers:[17,18].enumerated().map { i,id in
            .init(id:id,layerIndex:i,name:"text\(id)",visible:true,originXYZ:[0,0,0],scaleXYZ:[1,1,1],alpha:1,effects:[],
                contentKind:"text",text:"authored",textStyle:.init(fontPath:nil,colorRGB:[1,1,1],pointSize:24)) })
        aliasD.modelMaterialLinks = aliasModels.map { .init(modelPath:$0,materialPath:"material") }
        let aliasDomain = try SceneScriptQuickJSDomain(); try aliasDomain.configureLayerCatalog(aliasD)
        try aliasDomain.configureDynamicImageCatalog(Dictionary(uniqueKeysWithValues:aliasModels.enumerated().map {
            ($0.element,.init(modelPath:$0.element,renderSizeWH:$0.offset == 0 ? [200,100] : [320,160],autosize:true)) }))
        try aliasDomain.publishLayerSnapshot(.empty(frameIndex:1),descriptor:aliasD)
        var aliasPaths:[String] = [];var aliasSizes:[[Double]] = [];var aliasOwners:[SceneScriptValueOwner] = []
        for i in 0..<2 {
            let src = "export let __workshopId='\(i == 0 ? 111 : 222)'; export function init(v){thisScene.createLayer('models/shared.json');return v;} export function update(v){return v;}"
            let owner = try SceneScriptValueOwner(domain:aliasDomain,source:src,target:.text(layerID:17+i,field:.content),valueType:.string,
                effectNames:[],generation:1,budget:.default)
            aliasOwners.append(owner)
            let value = try owner.evaluate(input:.string("authored"),frame:frame,scriptPropertiesJSON:"",userPropertiesJSON:"{}",
                expectedGeneration:1,interruptBudget:nil).get()
            aliasPaths += value.layerMutations.compactMap(\.assetPath)
            aliasSizes += value.layerMutations.compactMap { $0.size.map { [$0.x,$0.y] } }
            owner.commitLayerMutations()
        }
        out["ownerAliases"] = ["paths":aliasPaths,"sizes":aliasSizes,"requested":aliasDomain.dynamicImageRequestedModelPaths.sorted()]
        print(String(decoding: try JSONSerialization.data(withJSONObject: out, options: [.sortedKeys]), as: UTF8.self))
    }
}
'''

class SceneScriptProgramResourceTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.work = tempfile.TemporaryDirectory(prefix="mwx-program-resource-vm-")
        cls.addClassCleanup(cls.work.cleanup)
        binary = compile_vector_harness(Path(cls.work.name), HARNESS, "program-resources")
        run = subprocess.run([str(binary)], capture_output=True, text=True, timeout=30)
        if run.returncode:
            raise AssertionError(run.stdout+run.stderr)
        cls.facts = json.loads(run.stdout)

    def test_four_families_share_actual_factory_alias_and_vm_mutation_consumers(self):
        for name in ("families", "variants", "unicode"):
            case = self.facts[name]
            self.assertTrue(case["complete"])
            self.assertEqual(case["failures"], 0)
            self.assertEqual(case["requested"], case["expected"])
            self.assertEqual(case["upperBound"], case["expected"])
            self.assertEqual(case["createdPaths"], case["expected"])
            self.assertEqual(case["sizes"], [[100,50]]*4)
            self.assertEqual(case["scales"], [0.5]*4)
            self.assertEqual(case["alpha"], [0.5]*4)

    def test_mixed_unknown_calls_and_lexical_neighbors_preserve_real_literal(self):
        self.assertEqual(self.facts["literalForms"], [["models/real.json"]]*5)
        self.assertEqual(self.facts["nonrequests"], [0]*5)

    def test_failed_candidate_reconstruction_and_duplicates_do_not_preload_rejected_sources(self):
        self.assertTrue(self.facts["reconstruction"]["complete"])
        self.assertEqual(self.facts["reconstruction"]["requested"], ["models/real.json"])
        self.assertEqual(self.facts["duplicates"], [])

    def test_final_media_route_domain_does_not_preload_removed_vector_owner(self):
        self.assertEqual(self.facts["finalRoute"]["requested"], ["models/real.json"])
        self.assertEqual(self.facts["finalRoute"]["mediaOwnersObserved"], 1)

    def test_automatic_discovery_does_not_upgrade_value_only_or_effect_boolean(self):
        self.assertEqual(self.facts["valueOnlyBool"], [])
        self.assertEqual(self.facts["effectBool"], [])

    def test_standalone_cursor_uses_shared_discovery_before_real_event(self):
        case = self.facts["standaloneCursor"]
        self.assertEqual(case["requested"], ["models/real.json"])
        self.assertEqual(case["failures"], 0)
        self.assertEqual(case["paths"], ["models/real.json"])
        self.assertEqual(case["alpha"], [0.75])

    def test_generic_string_owners_keep_same_raw_alias_in_separate_namespaces(self):
        case = self.facts["ownerAliases"]
        self.assertEqual(case["paths"], ["models/workshop/111/shared.json", "models/workshop/222/shared.json"])
        self.assertEqual(case["requested"], case["paths"])
        self.assertEqual(case["sizes"], [[200,100],[320,160]])
