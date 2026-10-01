"""Real launch stage behavior for unsupported optional/named candidate chains."""
import json
import os
from pathlib import Path
import runpy
import subprocess
import tempfile
import unittest


GRAPH = runpy.run_path(str(Path(__file__).with_name("test_scene_resolved_material_graph_executor.py")))
BUILDER = runpy.run_path(str(Path(__file__).with_name("test_scene_alpha_display_builder_fixture.py")))
PRODUCER = BUILDER["HARNESS_SOURCE"].split("@main", 1)[0].replace(
    "struct SceneAuthoredEffectRenderPlan: Codable, Equatable {}", ""
) + r'''
@main
enum Producer {
    static func main() throws {
        let model = try SceneRuntimeModelBuilder().build(rootURL: URL(fileURLWithPath: CommandLine.arguments[1]))
        let descriptor = model.renderDescriptor
        let layer = descriptor.layers.first { $0.id == 22 }!
        let authoredEffect = layer.effects[0]
        let material = descriptor.materialPasses.first { $0.materialPath == "materials/own_sample.json" }!
        typealias G = SceneAuthoredEffectRenderPlan
        let key = G.EffectKey(layerID: 22, effectIndex: 0, descriptorID: authoredEffect.id)
        let input = G.TextureIdentity(kind: .layerSource, layerID: 22, effect: nil, name: nil)
        let output = G.TextureIdentity(kind: .effectOutput, layerID: 22, effect: key, name: nil)
        let node = G.Node(nodeIndex: 0, effect: key, definitionPassIndex: 0,
            materialOrdinal: 0, instancePassIndex: 0, kind: .material,
            materialPath: material.materialPath, materialPassID: material.id,
            target: output, bindings: [], commandSource: nil, commandTarget: nil,
            compose: nil, conditions: nil)
        let graph = G(layerID: 22, effects: [.init(key: key, definitionPath: authoredEffect.file,
            input: input, output: output, nodeIndices: [0])], renderTargets: [], nodes: [node],
            finalOutput: output, blockers: [])
        let resolved = SceneAuthoredMaterialResolver.resolve(node: node, graph: graph, descriptor: descriptor)
        guard let material = resolved.node, resolved.issues.isEmpty else { fatalError("real material producer failed") }
        let tokens = material.textureSlots[1]!.candidates.map { candidate -> String in
            let source: String
            switch candidate.source {
            case let .asset(path): source = path
            case let .userTexture(value): source = value.kind.rawValue + ":" + value.value
            case .graph: source = "graph"
            }
            return candidate.provenance.rawValue + ":" + source
        }
        print(String(data: try JSONSerialization.data(withJSONObject: tokens), encoding: .utf8)!)
    }
}
'''
HARNESS = GRAPH["HARNESS"].split("@main", 1)[0] + r'''

private func changed(_ original: Template, candidates: [Template.TextureCandidate], overrideSlot: Bool = false) -> Template {
    var slots = original.textureSlots
    slots[1] = .init(index: 1, candidates: candidates + (overrideSlot
        ? [.init(reference: .graph(input), provenance: .explicitBinding)] : []))
    return Template.validated(textureSlots: slots, combos: original.combos,
        uniformDeclarations: original.uniformDeclarations, renderState: original.renderState,
        graphRole: .init(effectInput: original.graphRole.effectInput,
            effectOutput: original.graphRole.effectOutput, nodeTarget: original.graphRole.nodeTarget,
            bindings: original.graphRole.bindings + (overrideSlot ? [.init(slot: 1, texture: role(input))] : [])),
        shaderContract: original.shaderContract,
        diagnosticProvenance: original.diagnosticProvenance)!
}

@main
private enum Harness {
    static func main() throws {
        setenv("MWX_SCENE_GENERIC_SHADER_ROUTE", "disable-generic", 1)
        let named = SceneNamedTextureReference(providerLayerID: 879, variant: .primary)
        let raw = graph(targets: [], nodes: [material(0, ordinal: 0, target: output, read: input)])
        let chain = admittedGraph(raw)
        let node = raw.nodes[0]
        let base = template(for: node, systemProvider: "$mediaThumbnail",
            systemProviderLowerReference: .provider(.namedLayerTarget(named)))
        let pair = base.textureSlots[1]!.candidates
        let triple = [pair[0], Template.TextureCandidate(reference: pair[0].reference, provenance: .instance), pair[1]]
        let dependencyBinding = SceneDependencyRenderPlan.Binding(consumerLayerID: layerID,
            providerLayerID: named.providerLayerID,
            slot: .init(effectID: effect.descriptorID, passIndex: 0, slotIndex: 1),
            blendMode: 0, kind: .imageLayerBlend, requiresResolvedMaterialProgram: true)
        func value(_ candidates: [Template.TextureCandidate], reference: SceneNamedTextureReference = named) -> Capabilities.LayerCapability? {
            let catalog = SceneResolvedMaterialRuntimeCatalog(entries: [
                .init(effect: effect, nodeIndex: 0): .template(changed(base, candidates: candidates))
            ])
            let caps = capabilities(chain, catalog: catalog, namedProvider: reference,
                dependencyBinding: dependencyBinding, potentialOptionalNamedFallback: true)
            return caps.claim(chain).flatMap { caps.resolve($0.token, for: chain) }
        }
        let unsupported = value(triple)
        let supported = value(pair)
        let secondary = SceneNamedTextureReference(providerLayerID: 879, variant: .secondary)
        let other = SceneNamedTextureReference(providerLayerID: 880, variant: .primary)
        let different = value([pair[0], .init(reference: .provider(.namedLayerTarget(other)), provenance: .instance), pair[1]])
        let secondaryValue = value([.init(reference: .provider(.namedLayerTarget(secondary)), provenance: .material), pair[1]])
        let chained = chainedGraph()
        let chainedAdmission = orderedLayerGraph(chained)
        let entries = Dictionary(uniqueKeysWithValues: chained.nodes.map { node -> (Capabilities.MaterialKey, SceneResolvedMaterialRuntimeCatalog.Entry) in
            let ordinary = template(for: node)
            let value: Template
            if node.nodeIndex == 0 {
                let mixed = template(for: node, systemProvider: "$mediaThumbnail",
                    systemProviderLowerReference: .provider(.namedLayerTarget(named)))
                value = changed(mixed, candidates: triple)
            } else { value = ordinary }
            return (.init(effect: node.effect, nodeIndex: node.nodeIndex), .template(value))
        })
        let chainedCaps = capabilities(chainedAdmission, catalog: .init(entries: entries))
        let chainedValue = chainedCaps.claim(chainedAdmission).flatMap { chainedCaps.resolve($0.token, for: chainedAdmission) }
        // A history read-before-write requires the existing stricter dependency
        // topology. Unsupported visual code must not erase its lifetime.
        let history = graph(targets: [rawTarget(first, unique: true)], nodes: [
            material(0, ordinal: 0, target: output, read: first),
            command(1, kind: .copy, source: input, target: first),
        ])
        let historyAdmission = admittedGraph(history)
        let historyTemplate = template(for: history.nodes[0], systemProvider: "$mediaThumbnail",
            systemProviderLowerReference: .provider(.namedLayerTarget(named)))
        let historyCaps = capabilities(historyAdmission, catalog: .init(entries: [
            .init(effect: effect, nodeIndex: 0): .template(changed(historyTemplate, candidates: triple))
        ]))
        func plainValue(_ graph: Graph, _ template: Template) -> Capabilities.LayerCapability? {
            let admitted = admittedGraph(graph)
            let caps = capabilities(admitted, catalog: .init(entries: [
                .init(effect: effect, nodeIndex: 0): .template(template)
            ]), assetStates: [systemProviderFallbackIdentity: .ready(.data)],
                assetFormatFacts: [systemProviderFallbackIdentity.reportToken:
                    SceneShaderTextureFormat.r8.macroValue])
            fputs("PLAIN-VALUE\n" + caps.reportLines.joined(separator: "\n") + "\n", stderr)
            return caps.claim(admitted).flatMap { caps.resolve($0.token, for: admitted) }
        }
        let inactive = plainValue(raw, changed(template(for: node), candidates: triple))
        let shadowed = plainValue(raw, changed(template(for: node, systemProvider: "$mediaThumbnail"), candidates: triple + [
            .init(reference: .asset(systemProviderFallbackPath), provenance: .instance)
        ]))
        let overrideGraph = graph(targets: [], nodes: [material(0, ordinal: 0,
            target: output, read: input, additionalBindings: [binding(input, slot: 1)])])
        let overridden = plainValue(overrideGraph, changed(template(for: node, namedProvider: named), candidates: triple, overrideSlot: true))
        let functionGraph = materialFunctionGraph()
        let functionAdmission = admittedGraph(functionGraph)
        let functionControl = capabilities(functionAdmission, catalog: catalog(for: functionGraph),
            functionsByEffect: [effect: materialFunctionRegistry()])
        let functionControlValue = functionControl.claim(functionAdmission).flatMap {
            functionControl.resolve($0.token, for: functionAdmission)
        }
        let functionEntries = Dictionary(uniqueKeysWithValues: functionGraph.nodes.map { node -> (Capabilities.MaterialKey, SceneResolvedMaterialRuntimeCatalog.Entry) in
            let value = node.nodeIndex == 0
                ? changed(template(for: node, systemProvider: "$mediaThumbnail",
                    systemProviderLowerReference: .provider(.namedLayerTarget(named))), candidates: triple)
                : template(for: node)
            return (.init(effect: node.effect, nodeIndex: node.nodeIndex), .template(value))
        })
        let functionFailure = capabilities(functionAdmission, catalog: .init(entries: functionEntries),
            functionsByEffect: [effect: materialFunctionRegistry()])
        let reason = "material-optional-named-fallback-unproven"
        let result: [String: Bool] = [
            "threeCandidatesLocal": unsupported?.stages.first?.visualFailureReasonCode == reason,
            "unsupportedMaterialsEmpty": unsupported?.materials.isEmpty == true,
            "unsupportedHasNoDependencyClaims": unsupported?.dependencyOwnership == SceneResolvedMaterialDependencyOwnership.none
                && unsupported?.dependencyOwnership.referenceCount == 0,
            "inactiveSlotNotRejected": inactive?.materials.count == 1
                && inactive?.stages.first?.visualFailureReasonCode == nil,
            "terminalAssetShadowsOptional": shadowed?.materials.count == 1
                && shadowed?.stages.first?.visualFailureReasonCode == nil,
            "authoritativeGraphOverrideWins": overridden?.materials.count == 1
                && overridden?.stages.first?.visualFailureReasonCode == nil,
            "exactTwoStillExecutable": supported?.stages.first?.visualFailureReasonCode == nil && supported?.materials.count == 1,
            "differentProvidersNotNormalized": different?.stages.first?.visualFailureReasonCode == reason,
            "secondaryNotPromoted": secondaryValue?.stages.first?.visualFailureReasonCode == reason,
            "adjacentEffectsRemainExecutable": chainedValue?.stages.count == 3
                && chainedValue?.stages[0].visualFailureReasonCode == reason
                && chainedValue?.stages[1].visualFailureReasonCode == nil
                && chainedValue?.stages[2].visualFailureReasonCode == nil
                && chainedValue?.materials.count == 2,
            "historyTopologyNotSoftened": historyCaps.claim(historyAdmission) == nil,
            "clearFunctionControlActuallyAdmitted": functionControlValue?.admittedProducts.first?
                .clearFunctions.function(named: "reset")?.targets == [first, first],
            "clearFunctionFailureNotSoftened": functionFailure.claim(functionAdmission) == nil
                && functionFailure.reportLines.contains { $0.contains(reason) },
        ]
        print(String(data: try JSONSerialization.data(withJSONObject: result, options: .sortedKeys), encoding: .utf8)!)
    }
}
'''


class SceneOptionalNamedFailureTests(unittest.TestCase):
    def test_real_author_parser_preserves_three_candidate_provenances(self):
        from .test_scene_hidden_provider_integration import fixture_entries
        project, entries = fixture_entries(optional=True)
        material = json.loads(entries["materials/own_sample.json"])
        material["passes"][0]["textures"] = [None, "_rt_imageLayerComposite_11_a"]
        entries["materials/own_sample.json"] = json.dumps(material).encode()
        sources = BUILDER["SWIFT_SOURCES"] + [
            BUILDER["SOURCE_ROOT"] / "Compilation/Graph/SceneAuthoredEffectRenderPlan.swift",
            BUILDER["SOURCE_ROOT"] / "Compilation/Material/SceneAuthoredMaterialResolver.swift",
        ]
        with tempfile.TemporaryDirectory(prefix="mwx-optional-author-") as directory:
            root = Path(directory)
            content = root / "content"
            content.mkdir()
            for name, data in entries.items():
                path = content / name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes(data)
            (content / "project.json").write_text(json.dumps(project))
            harness = root / "Producer.swift"
            harness.write_text(PRODUCER)
            binary = root / "producer"
            compiled = subprocess.run(["xcrun", "swiftc", *map(str, sources), str(harness),
                "-framework", "Metal", "-module-cache-path", str(root / "modules"),
                "-o", str(binary)], capture_output=True, text=True)
            self.assertEqual(compiled.returncode, 0, compiled.stderr)
            ran = subprocess.run([str(binary), str(content)], capture_output=True, text=True)
            self.assertEqual(ran.returncode, 0, ran.stderr)
            self.assertEqual(json.loads(ran.stdout.strip().splitlines()[-1]), [
                "material:_rt_imageLayerComposite_11_a", "instance:_rt_imageLayerComposite_11_a",
                "userTexture:system:$mediaThumbnail",
            ])

    def test_unsupported_candidate_chain_is_an_effect_local_launch_failure(self):
        with tempfile.TemporaryDirectory(prefix="mwx-optional-named-cache-") as cache:
            old = os.environ.get("MWX_SCENE_GENERIC_SHADER_CACHE")
            os.environ["MWX_SCENE_GENERIC_SHADER_CACHE"] = cache
            try:
                compilation, completed = GRAPH["compile_harness"](GRAPH["SUPPORT"], HARNESS)
            finally:
                if old is None:
                    os.environ.pop("MWX_SCENE_GENERIC_SHADER_CACHE", None)
                else:
                    os.environ["MWX_SCENE_GENERIC_SHADER_CACHE"] = old
        self.assertEqual(compilation.returncode, 0, compilation.stderr)
        self.assertIsNotNone(completed)
        self.assertEqual(completed.returncode, 0, completed.stderr)
        result = json.loads(completed.stdout.strip().splitlines()[-1])
        for name, passed in result.items():
            with self.subTest(name=name):
                self.assertTrue(passed, (result, completed.stderr))
