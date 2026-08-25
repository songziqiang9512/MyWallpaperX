#!/usr/bin/env python3

from __future__ import annotations

import json
import os
from pathlib import Path
import runpy
import subprocess
import tempfile
import unittest


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
CAPABILITY_FIXTURE = runpy.run_path(
    str(REPOSITORY_ROOT / "script/tests/test_scene_resolved_material_execution_capability.py")
)
SWIFT_SOURCES = CAPABILITY_FIXTURE["ENVELOPE_SWIFT_SOURCES"]
SUPPORT = CAPABILITY_FIXTURE["ENVELOPE_SUPPORT"]
BASE_HARNESS = CAPABILITY_FIXTURE["ENVELOPE_HARNESS"]
HARNESS_ANCHOR = "@main\nprivate enum EnvelopeHarness"
HARNESS_PREFIX, anchor, _ = BASE_HARNESS.partition(HARNESS_ANCHOR)
if anchor != HARNESS_ANCHOR:
    raise RuntimeError("captured-main fixture anchor changed")


HARNESS = HARNESS_PREFIX + r'''
private enum ConservationShape: Equatable {
    case positive
    case dormantSource
    case activeNonColorSource
    case dormantWrongSource
    case noSource
    case additionalSource
    case wrongSource
    case wrongEffectIdentity
    case internalTargetMismatch
    case effectOutputInput
    case unitProviderOverride
    case unitWrongProvider
    case unitProviderAfterGraph
    case unitWrongBindingName
    case unitBlurredProvider
}

private func isUnitComposite(_ shape: ConservationShape) -> Bool {
    switch shape {
    case .unitProviderOverride, .unitWrongProvider, .unitProviderAfterGraph,
         .unitWrongBindingName, .unitBlurredProvider:
        true
    default:
        false
    }
}

private let foreignEffectKey = Graph.EffectKey(
    layerID: layerID,
    effectIndex: 1,
    descriptorID: "foreign-envelope"
)

private func framebuffer(
    _ name: String,
    effect: Graph.EffectKey = effectKey
) -> Graph.TextureIdentity {
    .init(
        kind: .framebuffer,
        layerID: effect.layerID,
        effect: effect,
        name: name
    )
}

private func graphBinding(
    _ slot: Int,
    _ name: String,
    _ texture: Graph.TextureIdentity
) -> Graph.Binding {
    .init(
        slot: slot,
        authoredName: name,
        texture: texture,
        conditions: nil
    )
}

private func conservationNode(
    index: Int,
    target: Graph.TextureIdentity,
    bindings: [Graph.Binding]
) -> Graph.Node {
    .init(
        nodeIndex: index,
        effect: effectKey,
        definitionPassIndex: index,
        materialOrdinal: index,
        instancePassIndex: index,
        kind: .material,
        materialPath: "materials/conservation-\(index).json",
        materialPassID: "conservation-\(index)",
        target: target,
        bindings: bindings,
        commandSource: nil,
        commandTarget: nil,
        compose: nil,
        conditions: nil
    )
}

private func conservationGraph(_ shape: ConservationShape) -> Graph {
    let first = framebuffer("first")
    let second = framebuffer("second")
    let foreign = framebuffer("foreign", effect: foreignEffectKey)
    let wrongSource = Graph.TextureIdentity(
        kind: .layerSource,
        layerID: layerID + 1,
        effect: nil,
        name: nil
    )
    let previous = previousOutput()
    let firstTarget = shape == .internalTargetMismatch ? output() : second
    let firstBindings: [Graph.Binding]
    switch shape {
    case .dormantSource, .activeNonColorSource:
        firstBindings = [
            graphBinding(0, "first", first),
            graphBinding(1, "previous", source()),
        ]
    case .dormantWrongSource:
        firstBindings = [
            graphBinding(0, "first", first),
            graphBinding(1, "previous", wrongSource),
        ]
    default:
        firstBindings = [graphBinding(0, "first", first)]
    }
    let firstNode = conservationNode(
        index: 0,
        target: firstTarget,
        bindings: firstBindings
    )
    let middleBindings: [Graph.Binding]
    switch shape {
    case .noSource:
        middleBindings = [graphBinding(0, "second", second)]
    default:
        middleBindings = [
            graphBinding(0, "previous", source()),
            graphBinding(1, "second", second),
        ]
    }
    let middleNode = conservationNode(
        index: 1,
        target: first,
        bindings: middleBindings
    )
    let terminalBindings: [Graph.Binding]
    switch shape {
    case .noSource:
        terminalBindings = [graphBinding(0, "first", first)]
    case .additionalSource:
        terminalBindings = [
            graphBinding(0, "previous", source()),
            graphBinding(1, "also-previous", source()),
        ]
    case .wrongSource:
        terminalBindings = [graphBinding(0, "previous", wrongSource)]
    case .wrongEffectIdentity:
        terminalBindings = [
            graphBinding(0, "previous", source()),
            graphBinding(2, "foreign", foreign),
        ]
    case .effectOutputInput:
        terminalBindings = [graphBinding(0, "previous", previous)]
    case .unitProviderOverride, .unitWrongProvider, .unitProviderAfterGraph,
         .unitBlurredProvider:
        terminalBindings = [
            graphBinding(0, "blurred", first),
            graphBinding(2, "previous", source()),
        ]
    case .unitWrongBindingName:
        terminalBindings = [
            graphBinding(0, "blurred", first),
            graphBinding(2, "not-previous", source()),
        ]
    default:
        terminalBindings = [
            graphBinding(0, "previous", source()),
            graphBinding(2, "first", first),
        ]
    }
    let terminalNode = conservationNode(
        index: 2,
        target: output(),
        bindings: terminalBindings
    )
    return .init(
        layerID: layerID,
        effects: [.init(
            key: effectKey,
            definitionPath: "effects/conservation/effect.json",
            input: source(),
            output: output(),
            nodeIndices: [0, 1, 2]
        )],
        renderTargets: (
            [first, second] + (shape == .wrongEffectIdentity ? [foreign] : [])
        ).map {
            .init(
                texture: $0,
                extent: .init(kind: .input, first: nil, second: nil),
                format: "rgba8888",
                declaredUnique: true,
                clear: .array([
                    .number(0), .number(0), .number(0), .number(0),
                ]),
                uvs: nil,
                conditions: nil
            )
        },
        nodes: [firstNode, middleNode, terminalNode],
        finalOutput: output(),
        blockers: []
    )
}

private func graphRole(
    _ identity: Graph.TextureIdentity
) -> Template.GraphTextureRole {
    switch identity.kind {
    case .layerSource: .layerSource
    case .effectOutput: .effectOutput
    case .framebuffer: .framebuffer
    case .unresolved: fatalError("unresolved fixture identity")
    }
}

private func unitCompositeContract() -> SceneShaderContract {
    let revision = "captured-main-unit-provider-override"
    let inherited = contract(revision)
    let fragmentSource = """
    varying vec2 v_TexCoord;
    uniform sampler2D g_Texture0;
    uniform sampler2D g_Texture2;
    uniform vec3 g_CompositeColor; // {"material":"compositecolor","default":"1 1 1"}
    vec4 identityComposite(vec4 oldColor, vec4 effectColor) {
        return effectColor;
    }
    vec4 compositeCarrier(vec4 oldColor, vec4 effectColor) {
        effectColor.rgb *= g_CompositeColor;
        return identityComposite(oldColor, effectColor);
    }
    void main() {
        vec4 blurred = texSample2D(g_Texture0, v_TexCoord);
        vec4 previous = texSample2D(g_Texture2, v_TexCoord.xy);
        float mask = 1.0;
        float divisor = mix(blurred.a, 1, step(blurred.a, 0));
        blurred = compositeCarrier(
            previous, vec4(blurred.rgb / divisor, blurred.a)
        );
        blurred = mix(previous, blurred, mask);
        gl_FragColor = blurred;
    }
    """
    let path = "\(revision)/root.frag"
    let parsed = SceneShaderContractSourceParser().parse(
        fragmentSource,
        stageRelativePath: path
    )
    let fragment = SceneShaderContract.Stage(
        kind: .fragment,
        relativePath: path,
        source: fragmentSource,
        rawSHA256: SceneShaderStableDigest.hash(Data(fragmentSource.utf8)),
        includes: parsed.includes,
        annotations: parsed.annotations,
        declarations: parsed.declarations
    )
    let stages = [inherited.stages.first { $0.kind == .vertex }!, fragment]
    return .init(
        identity: "fixture/\(revision)",
        sourceKind: .authoredSource,
        stages: stages,
        diagnostics: [],
        canonicalSHA256: "fixture-contract-\(revision)",
        sourceGraph: .init(
            roots: [
                .init(label: "vertex", virtualPath: stages[0].relativePath),
                .init(label: "fragment", virtualPath: fragment.relativePath),
            ],
            nodes: stages.map {
                .init(
                    virtualPath: $0.relativePath,
                    provenance: .package,
                    source: $0.source,
                    rawSHA256: $0.rawSHA256,
                    byteCount: $0.source.utf8.count
                )
            },
            edges: [],
            diagnostics: [],
            dependencySHA256: "fixture-dependency-\(revision)"
        )
    )
}

private func conservationTemplate(
    graph: Graph,
    nodeIndex: Int,
    shape: ConservationShape,
    externalCandidate: Template.TextureCandidate? = nil,
    userCandidate: Template.TextureCandidate? = nil,
    variantDivergence: Bool = false
) -> Template {
    let node = graph.nodes[nodeIndex]
    var textureSlots = Array<Template.TextureSlot?>(repeating: nil, count: 8)
    for binding in node.bindings {
        textureSlots[binding.slot!] = .init(
            index: binding.slot!,
            candidates: [.init(
                reference: .graph(binding.texture),
                provenance: .explicitBinding
            )]
        )
    }
    if nodeIndex == 2, isUnitComposite(shape),
       let sourceSlot = textureSlots[2], shape != .unitBlurredProvider {
        let provider = namedTargetCandidate(
            providerLayerID: shape == .unitWrongProvider
                ? layerID - 1 : layerID
        )
        let graph = sourceSlot.candidates[0]
        textureSlots[2] = .init(
            index: 2,
            candidates: shape == .unitProviderAfterGraph
                ? [graph, provider] : [provider, graph]
        )
    }
    if nodeIndex == 2, shape == .unitBlurredProvider,
       let blurredSlot = textureSlots[0] {
        textureSlots[0] = .init(
            index: 0,
            candidates: [
                namedTargetCandidate(providerLayerID: layerID),
                blurredSlot.candidates[0],
            ]
        )
    }
    if nodeIndex == 2, textureSlots[1] == nil {
        let fog = SceneVFSAssetPath("particle/fog/fog2")!
        textureSlots[1] = .init(
            index: 1,
            candidates: [.init(reference: .asset(fog), provenance: .material)]
        )
    }
    if let externalCandidate {
        textureSlots[3] = .init(index: 3, candidates: [externalCandidate])
    }
    if let userCandidate {
        textureSlots[4] = .init(index: 4, candidates: [userCandidate])
    }
    let hasSecondGraphBinding = node.bindings.contains { $0.slot == 1 }
    let shader: SceneShaderContract
    if nodeIndex == 2, isUnitComposite(shape) {
        shader = unitCompositeContract()
    } else if variantDivergence && nodeIndex == 2 {
        shader = contract(
            "conservation-variant-divergence",
            secondMetadata: #"{"mode":"flowmask","combo":"EXTRA"}"#,
            variantMixedSource: true
        )
    } else if nodeIndex == 0 {
        switch shape {
        case .dormantSource, .dormantWrongSource:
            shader = contract(
                "conservation-\(nodeIndex)-dormant-source",
                secondMetadata: "{}",
                samplesSecond: false
            )
        case .activeNonColorSource:
            shader = contract(
                "conservation-\(nodeIndex)-active-noncolor-source",
                secondMetadata: "{}",
                observesSecond: true
            )
        default:
            shader = contract("conservation-\(nodeIndex)")
        }
    } else if hasSecondGraphBinding {
        shader = contract(
            "conservation-\(nodeIndex)",
            secondMetadata: "{}",
            observesSecond: true
        )
    } else if textureSlots[1] != nil {
        shader = contract(
            "conservation-\(nodeIndex)",
            secondMetadata: #"{"mode":"flowmask"}"#,
            observesSecond: true
        )
    } else {
        shader = contract("conservation-\(nodeIndex)")
    }
    return Template.validated(
        textureSlots: textureSlots,
        combos: [],
        uniformDeclarations: [],
        renderState: state(),
        graphRole: .init(
            effectInput: .layerSource,
            effectOutput: .effectOutput,
            nodeTarget: graphRole(node.target!),
            bindings: node.bindings.map {
                .init(slot: $0.slot!, texture: graphRole($0.texture))
            }
        ),
        unitPreviousBlurredCompositeGenericOwnerEligible:
            nodeIndex == 2 && isUnitComposite(shape),
        effectContext: .init(key: effectKey, input: graph.effects[0].input),
        shaderContract: shader,
        diagnosticProvenance: .init(
            nodeIndex: node.nodeIndex,
            authoredShaderPath: shader.identity,
            contractIdentity: shader.identity,
            contractCanonicalSHA256: shader.canonicalSHA256,
            textureSources: [],
            uniformSources: []
        )
    )!
}

private func unitCompositePreviousSlot(_ shape: ConservationShape) -> Int? {
    let graph = conservationGraph(shape)
    let template = conservationTemplate(
        graph: graph,
        nodeIndex: 2,
        shape: shape
    )
    let prepared: SceneShaderPreparedProgram
    switch SceneAuthoredShaderPreparation.prepareShaderStages(
        contract: template.shaderContract,
        combos: template.comboValues,
        inactiveComboProviders: Set(template.inheritedInactiveCombos),
        textureReadiness: [0: true, 2: true]
    ) {
    case let .accepted(value): prepared = value
    case .notApplicable, .rejected: return nil
    }
    let sources = SceneAuthoredShaderBackendCanonicalizer.canonicalize(
        vertex: prepared.vertex.source,
        fragment: prepared.fragment.source
    )
    guard let samplers = try? SceneResolvedMaterialShaderSchema.activeSamplers(
        prepared
    ) else { return nil }
    let identities = Dictionary(uniqueKeysWithValues: graph.nodes[2].bindings.map {
        ($0.slot!, $0.texture)
    })
    return SceneResolvedMaterialUnitPreviousBlurredCompositeEligibility.slots(
        fragmentSource: sources.fragment,
        prepared: prepared,
        samplers: samplers,
        template: template,
        implicitFramebufferIdentity: graph.effects[0].input,
        activeGraphTextureIdentities: identities
    )?.previous
}

private func conservationCatalog(
    _ shape: ConservationShape,
    externalProvider: Bool = false,
    userPropertyAuxiliary: Bool = false,
    variantDivergence: Bool = false
) -> Catalog {
    let graph = conservationGraph(shape)
    let templates = Dictionary(uniqueKeysWithValues: graph.nodes.map { node in
        (
            node.nodeIndex,
            conservationTemplate(
                graph: graph,
                nodeIndex: node.nodeIndex,
                shape: shape,
                externalCandidate: externalProvider && node.nodeIndex == 0
                    ? namedTargetCandidate(providerLayerID: layerID - 1) : nil,
                userCandidate: userPropertyAuxiliary && node.nodeIndex == 0
                    ? userPropertyCandidate("optional-texture") : nil,
                variantDivergence: variantDivergence
            )
        )
    })
    return catalog(
        graph: graph,
        templates: templates,
        sourceRoute: .capturedMainTargetTexture,
        assetStates: [
            .init(
                path: SceneVFSAssetPath("particle/fog/fog2")!,
                purpose: .flow
            ): .ready(.data),
        ]
    )
}

private func claim(_ catalog: Catalog) -> Bool {
    catalog.claim(layerID: layerID) != nil
}

@main
private enum CapturedMainSourceConservationHarness {
    static func main() throws {
        setenv("MWX_SCENE_GENERIC_SHADER_ROUTE", "disable-generic", 1)
        let positive = conservationCatalog(.positive)
        let dormantSource = conservationCatalog(.dormantSource)
        let userPropertyAuxiliary = conservationCatalog(
            .positive,
            userPropertyAuxiliary: true
        )
        let externalProviderAuxiliary = conservationCatalog(
            .positive,
            externalProvider: true
        )
        let negatives: [(String, Catalog)] = [
            ("noSource", conservationCatalog(.noSource)),
            ("activeNonColorSource", conservationCatalog(.activeNonColorSource)),
            ("dormantWrongSource", conservationCatalog(.dormantWrongSource)),
            ("additionalSource", conservationCatalog(.additionalSource)),
            ("wrongSource", conservationCatalog(.wrongSource)),
            ("wrongEffectIdentity", conservationCatalog(.wrongEffectIdentity)),
            ("internalTargetMismatch", conservationCatalog(.internalTargetMismatch)),
            ("effectOutputInput", conservationCatalog(.effectOutputInput)),
            ("variantDivergence", conservationCatalog(.positive, variantDivergence: true)),
        ]
        var result: [String: Any] = [
            "positiveClaim": claim(positive),
            "positiveFailure": rejection(positive),
            "positiveMaterialCount": positive.claim(layerID: layerID)
                .flatMap { positive.resolve($0.token) }?.materials.count ?? -1,
            "dormantSourceClaim": claim(dormantSource),
            "dormantSourceFailure": rejection(dormantSource),
            "dormantSourceMaterialCount": dormantSource.claim(layerID: layerID)
                .flatMap { dormantSource.resolve($0.token) }?.materials.count ?? -1,
            "userPropertyAuxiliaryClaim": claim(userPropertyAuxiliary),
            "userPropertyAuxiliaryFailure": rejection(userPropertyAuxiliary),
            "externalProviderAuxiliaryClaim": claim(externalProviderAuxiliary),
            "externalProviderAuxiliaryFailure": rejection(externalProviderAuxiliary),
            "unitProviderOverrideSourceSlot":
                unitCompositePreviousSlot(.unitProviderOverride) ?? -1,
            "unitWrongProviderRejected":
                unitCompositePreviousSlot(.unitWrongProvider) == nil,
            "unitProviderAfterGraphRejected":
                unitCompositePreviousSlot(.unitProviderAfterGraph) == nil,
            "unitWrongBindingNameRejected":
                !claim(conservationCatalog(.unitWrongBindingName)),
            "unitBlurredProviderRejected":
                unitCompositePreviousSlot(.unitBlurredProvider) == nil,
        ]
        for (name, catalog) in negatives {
            result["\(name)Claim"] = claim(catalog)
            result["\(name)Failure"] = rejection(catalog)
            result["\(name)Attribution"] = attribution(catalog)
        }
        let data = try JSONSerialization.data(
            withJSONObject: result,
            options: [.sortedKeys]
        )
        print(String(decoding: data, as: UTF8.self))
    }
}
'''


class SceneCapturedMainSourceConservationTests(unittest.TestCase):
    def test_graph_level_source_conservation_is_exact_and_fail_closed(self) -> None:
        with tempfile.TemporaryDirectory(
            prefix="mwx-captured-main-conservation-"
        ) as directory:
            root = Path(directory)
            support = root / "Support.swift"
            harness = root / "Harness.swift"
            binary = root / "captured-main-conservation"
            support.write_text(SUPPORT, encoding="utf-8")
            harness.write_text(HARNESS, encoding="utf-8")
            environment = os.environ.copy()
            environment["CLANG_MODULE_CACHE_PATH"] = str(root / "clang-cache")
            environment["SWIFT_MODULECACHE_PATH"] = str(root / "swift-cache")
            completed = subprocess.run(
                [
                    "xcrun", "--sdk", "macosx", "swiftc", "-parse-as-library",
                    str(support),
                    *(str(path) for path in SWIFT_SOURCES),
                    str(harness),
                    "-module-cache-path", str(root / "module-cache"),
                    "-o", str(binary),
                ],
                cwd=REPOSITORY_ROOT,
                env=environment,
                capture_output=True,
                text=True,
            )
            self.assertEqual(completed.returncode, 0, completed.stderr)
            completed = subprocess.run(
                [str(binary)],
                cwd=REPOSITORY_ROOT,
                env=environment,
                capture_output=True,
                text=True,
            )
            self.assertEqual(completed.returncode, 0, completed.stderr)

        payload = json.loads(completed.stdout)
        self.assertTrue(payload["positiveClaim"], payload)
        self.assertEqual(payload["positiveFailure"], "", payload)
        self.assertEqual(payload["positiveMaterialCount"], 3, payload)
        self.assertTrue(payload["dormantSourceClaim"], payload)
        self.assertEqual(payload["dormantSourceFailure"], "", payload)
        self.assertEqual(payload["dormantSourceMaterialCount"], 3, payload)
        self.assertTrue(payload["userPropertyAuxiliaryClaim"], payload)
        self.assertEqual(payload["userPropertyAuxiliaryFailure"], "", payload)
        self.assertFalse(payload["externalProviderAuxiliaryClaim"], payload)
        self.assertIn(
            "execution-stage-conservation",
            payload["externalProviderAuxiliaryFailure"],
            payload,
        )
        self.assertNotIn(
            "utility-source-program-unsupported",
            payload["externalProviderAuxiliaryFailure"],
            payload,
        )
        self.assertEqual(payload["unitProviderOverrideSourceSlot"], 2, payload)
        self.assertTrue(payload["unitWrongProviderRejected"], payload)
        self.assertTrue(payload["unitProviderAfterGraphRejected"], payload)
        self.assertTrue(payload["unitWrongBindingNameRejected"], payload)
        self.assertTrue(payload["unitBlurredProviderRejected"], payload)
        for name in (
            "noSource",
            "activeNonColorSource",
            "dormantWrongSource",
            "additionalSource",
            "wrongSource",
            "wrongEffectIdentity",
            "internalTargetMismatch",
            "effectOutputInput",
            "variantDivergence",
        ):
            self.assertFalse(payload[f"{name}Claim"], payload)
            self.assertIn(
                "utility-source-program-unsupported",
                payload[f"{name}Failure"],
                payload,
            )
            self.assertIn("schema=program-failure-attribution-v1", payload[f"{name}Attribution"])
            self.assertIn("layer=981", payload[f"{name}Attribution"])

        self.assertIn("node=2", payload["noSourceAttribution"], payload)
        self.assertIn("node=0", payload["activeNonColorSourceAttribution"], payload)
        self.assertIn("node=0", payload["dormantWrongSourceAttribution"], payload)
        self.assertIn("node=2", payload["additionalSourceAttribution"], payload)
        self.assertIn("node=2", payload["wrongSourceAttribution"], payload)
        self.assertIn("node=2", payload["wrongEffectIdentityAttribution"], payload)
        self.assertIn("node=0", payload["internalTargetMismatchAttribution"], payload)
        self.assertIn("node=2", payload["effectOutputInputAttribution"], payload)
        self.assertIn("node=2", payload["variantDivergenceAttribution"], payload)

    def test_active_variant_and_exact_identity_contract_is_present(self) -> None:
        source = (
            REPOSITORY_ROOT
            / "MyWallpaperX/Core/SteamWorkshopScene/RenderGraph/MaterialProgram/"
            "SceneResolvedMaterialExecutionCapabilityVariant+CapturedMainSourceConservation.swift"
        ).read_text(encoding="utf-8")
        for contract in (
            "Set(roles).count == 1",
            "snapshot.inputIdentity == effect.input",
            "identity.effect == effect",
            "Provider candidates are auxiliary resource provenance",
            "sourceBindings.count <= 1",
            "capturedMainUnitCompositePreviousSlot(",
            "SceneResolvedMaterialUnitPreviousBlurredCompositeEligibility.slots(",
            ")?.previous",
        ):
            self.assertIn(contract, source)

        selection = (
            REPOSITORY_ROOT
            / "MyWallpaperX/Core/SteamWorkshopScene/RenderGraph/MaterialProgram/"
            "SceneResolvedMaterialTextureSelection.swift"
        ).read_text(encoding="utf-8")
        dependency = (
            REPOSITORY_ROOT
            / "MyWallpaperX/Core/SteamWorkshopScene/RenderGraph/EffectExecution/"
            "SceneResolvedMaterialExecutionCapability+DependencyOwnership.swift"
        ).read_text(encoding="utf-8")
        self.assertIn("preserveAbsentOverride: terminalGraphOverride", selection)
        self.assertIn("isShadowedInputProvenance", dependency)
        self.assertIn('matches[0].authoredName == "previous"', dependency)


if __name__ == "__main__":
    unittest.main()
