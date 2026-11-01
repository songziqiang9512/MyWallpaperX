#!/usr/bin/env python3

"""Shared source set and fail-soft contract for the material graph GPU gate."""

from __future__ import annotations

import os
import json
from pathlib import Path
import runpy
import shutil
import subprocess
import tempfile
import unittest

from script.tests.scene_harness_io import separate_graph_debug_output

REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
SCENE_ROOT = REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene"
PUBLICATION_GATE = Path(__file__).with_name(
    "test_scene_graph_texture_publication.py"
)
MAIN_GATE = Path(__file__).with_name(
    "test_scene_resolved_material_graph_executor.py"
)
PUBLICATION_FIXTURE = runpy.run_path(str(PUBLICATION_GATE))
RESOURCE_ENCODER_SOURCE = REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Graph/SceneGraphResourcePassEncoder.swift"
EXECUTOR_SOURCE = REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Graph/SceneResolvedMaterialGraphExecutor.swift"
PROGRAM_FIRST_STAGES_SOURCE = REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Compilation/Material/SceneResolvedMaterialExecutionCapability+ProgramFirstStages.swift"
PROGRAM_FIRST_STAGES_INPUT_CONTRACTS_SOURCE = REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Compilation/Material/SceneResolvedMaterialExecutionCapability+ProgramFirstStages+InputContracts.swift"
PROGRAM_FIRST_STAGES_BACKGROUND_SOURCE = REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Compilation/Material/SceneResolvedMaterialExecutionCapability+ProgramFirstStagesBackground.swift"
VISUAL_FAILURE_TOPOLOGY_SOURCE = REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Compilation/Material/SceneResolvedMaterialVisualFailureTopology.swift"
VISUAL_FAILURE_PASSTHROUGH_SOURCE = REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Graph/SceneResolvedMaterialGraphExecutor+VisualFailurePassthrough.swift"
# Composed source groups can overlap; keep each Path once in dependency order.
SWIFT_SOURCES = list(dict.fromkeys([
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Composition/SceneMainPassEncoder.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Diagnostics/ScenePerformanceCounterHub.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Diagnostics/SceneGPUCensus.swift",
    SCENE_ROOT / "Diagnostics/SceneFramePerformanceTelemetry.swift",
    SCENE_ROOT / "Diagnostics/SceneGPUStageTimestampObservation.swift",
    *PUBLICATION_FIXTURE["SWIFT_SOURCES"],
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Graph/SceneResolvedMaterialAttachmentKind.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Graph/SceneResolvedMaterialAttachmentStorage.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Graph/SceneResolvedMaterialPassEncoder+Failure.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Graph/SceneResolvedMaterialPipelineBinaryArchive.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Graph/SceneResolvedMaterialPassEncoder+Warmup.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Graph/SceneResolvedMaterialPassEncoder.swift",
    REPOSITORY_ROOT / "script/tests/fixtures/SceneMaterialPipelinePreparation.swift",
    RESOURCE_ENCODER_SOURCE,
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Targets/SceneOffscreenResolutionPolicy.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Compilation/Graph/SceneGraphConditionAdmission.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Compilation/Graph/SceneGraphAdmissionCompiler.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Compilation/Material/SceneResolvedMaterialExecutionCapabilityAdmission.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Compilation/Material/SceneDirectBoolEffectVisibilityRouteAdmission.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Compilation/Material/SceneResolvedMaterialExecutionCapability+DependencyOwnership.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Compilation/Material/SceneResolvedMaterialExecutionCapability.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Compilation/Material/SceneResolvedMaterialExecutionCapability+DynamicUniformRejection.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Compilation/Material/SceneResolvedMaterialExecutionCapability+Material.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Compilation/Material/SceneResolvedMaterialExecutionCapability+PipelineWarmup.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Compilation/Material/SceneResolvedMaterialExecutionCapability+PreservedChannels.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Compilation/Material/SceneResolvedMaterialExecutionCapability+Stages.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Graph/SceneResolvedMaterialStageActivation.swift",
    PROGRAM_FIRST_STAGES_SOURCE,
    PROGRAM_FIRST_STAGES_INPUT_CONTRACTS_SOURCE,
    PROGRAM_FIRST_STAGES_BACKGROUND_SOURCE,
    VISUAL_FAILURE_TOPOLOGY_SOURCE,
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Compilation/Material/SceneResolvedMaterialExecutionCapabilityTemplateAdmission.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Compilation/Material/SceneResolvedMaterialExecutionCapability+EnvelopeDiagnostics.swift",
    EXECUTOR_SOURCE,
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Graph/SceneResolvedMaterialGraphExecutor+Attachment.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Graph/SceneResolvedMaterialGraphExecutor+Preparation.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Graph/SceneResolvedMaterialGraphExecutor+DynamicUniformDiagnostics.swift",
    VISUAL_FAILURE_PASSTHROUGH_SOURCE,
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Graph/SceneResolvedMaterialGraphExecutor+Validation.swift",
]))

GRAPH_SWIFT_FLAGS = ("-D", "SCENE_GRAPH_TESTING", "-D", "DEBUG")

SOURCE_INDEPENDENT_GRAPH_HARNESS = r'''
@main private enum SourceIndependentGraphHarness {
    static func run(_ name: String, renamed: Bool = false) throws -> [String: Any] {
        let layer = renamed ? 947 : 42
        let firstIndex = renamed ? 43 : 0
        let owner = Graph.EffectKey(layerID: layer, effectIndex: 0,
            descriptorID: "generated-\(name)-\(layer)")
        let suffix = Graph.EffectKey(layerID: layer, effectIndex: 1,
            descriptorID: "suffix-\(name)-\(layer)")
        let input = Graph.TextureIdentity(kind: .layerSource, layerID: layer,
            effect: nil, name: nil)
        let output = Graph.TextureIdentity(kind: .effectOutput, layerID: layer,
            effect: owner, name: nil)
        let suffixOutput = Graph.TextureIdentity(kind: .effectOutput, layerID: layer,
            effect: suffix, name: nil)
        let seed = Graph.TextureIdentity(kind: .framebuffer, layerID: layer,
            effect: owner, name: renamed ? "renamed-seed" : "initial-color")
        let scratch = Graph.TextureIdentity(kind: .framebuffer, layerID: layer,
            effect: owner, name: renamed ? "renamed-scratch" : "working-color")
        let foreignOwner = Graph.EffectKey(layerID: layer + 1, effectIndex: 0,
            descriptorID: "unrelated-owner")
        let foreignOutput = Graph.TextureIdentity(kind: .effectOutput, layerID: layer + 1,
            effect: foreignOwner, name: nil)
        let coordinates = renamed ? "uvUnseen" : "v_TexCoord"
        let generated = renamed
            ? "vec3 shade = vec3(\(coordinates).xy * 1.0, 0.5 * 0.5); gl_FragColor = vec4(shade, 1.0);"
            : "vec3 paint = vec3(\(coordinates), 0.25); gl_FragColor = vec4(paint, 1.0);"
        let sampled = """
        varying vec2 \(coordinates);
        uniform sampler2D g_Texture0;
        void main() { gl_FragColor = texSample2D(g_Texture0, \(coordinates).xy); }
        """
        let generatedFragment = "varying vec2 \(coordinates); void main() { \(generated) }"
        let mixedFragment = """
        varying vec2 \(coordinates);
        uniform sampler2D g_Texture1; // {"mode":"opacitymask","combo":"USE_CAPTURE"}
        #if USE_CAPTURE
        uniform sampler2D g_Texture0; // {"material":"framebuffer","hidden":true}
        #endif
        void main() {
        #if USE_CAPTURE
            vec4 color = texSample2D(g_Texture0, \(coordinates));
            color.a *= texSample2D(g_Texture1, \(coordinates)).r;
            gl_FragColor = color;
        #else
            \(generated)
        #endif
        }
        """
        func node(_ index: Int, effect: Graph.EffectKey? = nil,
                  target: Graph.TextureIdentity, read: Graph.TextureIdentity? = nil,
                  ordinal: Int = 0) -> Graph.Node {
            .init(nodeIndex: index, effect: effect ?? owner, definitionPassIndex: ordinal,
                materialOrdinal: ordinal, instancePassIndex: ordinal, kind: .material,
                materialPath: "fixtures/\(name)/\(layer)-\(index).json",
                materialPassID: "\(name)#\(index)", target: target,
                bindings: read.map { [binding($0)] } ?? [], commandSource: nil,
                commandTarget: nil, compose: nil, conditions: nil)
        }
        let framebufferChain = ["seededFBO", "clearedFBO", "missingInitialization"].contains(name)
        let clearsSeed = name == "clearedFBO"
        var nodes: [Graph.Node]
        if framebufferChain {
            if name == "seededFBO" {
                nodes = [node(firstIndex, target: seed),
                    node(firstIndex + 1, target: scratch, read: seed, ordinal: 1),
                    node(firstIndex + 2, target: output, read: scratch, ordinal: 2)]
            } else {
                nodes = [node(firstIndex, target: scratch, read: seed),
                    node(firstIndex + 1, target: seed, read: scratch, ordinal: 1),
                    node(firstIndex + 2, target: output, read: seed, ordinal: 2)]
            }
        } else {
            nodes = [node(firstIndex,
                target: name == "foreignTarget" ? foreignOutput : output)]
        }
        var effects = [Graph.Effect(key: owner,
            definitionPath: "fixtures/\(name)/\(layer)-first.json", input: input,
            output: output, nodeIndices: nodes.map(\.nodeIndex))]
        if name == "generatedSuffix" {
            nodes.append(node(firstIndex + 1, effect: suffix, target: suffixOutput,
                read: output))
            effects.append(.init(key: suffix,
                definitionPath: "fixtures/\(name)/\(layer)-next.json", input: output,
                output: suffixOutput, nodeIndices: [firstIndex + 1]))
        }
        let graph = Graph(layerID: layer, effects: effects,
            renderTargets: framebufferChain ? [
                rawTarget(seed, clear: clearsSeed ? .string("0.1 0.2 0.3 1") : nil),
                rawTarget(scratch),
            ] : [], nodes: nodes, finalOutput: effects.last!.output, blockers: [])
        let optionalPath = SceneVFSAssetPath("fixtures/\(name)/\(layer)-mask.tex")!
        let optionalIdentity = SceneAssetTextureIdentity(path: optionalPath, purpose: .mask)
        var entries: [SceneResolvedMaterialRuntimeCatalog.Key: SceneResolvedMaterialRuntimeCatalog.Entry] = [:]
        for node in nodes {
            let effect = effects.first { $0.key == node.effect }!
            let fragment = name == "mixedVariants" ? mixedFragment
                : node.bindings.isEmpty ? generatedFragment : sampled
            let original = shaderContract(nodeIndex: node.nodeIndex, pass: false,
                fragmentOverride: fragment)
            let shader: SceneShaderContract
            if renamed {
                let stages = original.stages.map { stage -> SceneShaderContract.Stage in
                    let source = stage.source.replacingOccurrences(of: "v_TexCoord", with: coordinates)
                    let parsed = SceneShaderContractSourceParser().parse(source,
                        stageRelativePath: stage.relativePath)
                    return .init(kind: stage.kind, relativePath: stage.relativePath, source: source,
                        rawSHA256: SceneShaderStableDigest.hash(Data(source.utf8)), includes: parsed.includes,
                        annotations: parsed.annotations, declarations: parsed.declarations)
                }
                let sourceGraph = SceneShaderSourceGraph(roots: original.sourceGraph!.roots,
                    nodes: stages.map { .init(virtualPath: $0.relativePath, provenance: .package,
                        source: $0.source, rawSHA256: $0.rawSHA256, byteCount: $0.source.utf8.count) },
                    edges: [], diagnostics: [], dependencySHA256: SceneShaderStableDigest.hash(stages))
                shader = .init(identity: original.identity, sourceKind: .authoredSource, stages: stages,
                    diagnostics: [], canonicalSHA256: SceneShaderStableDigest.hash(stages), sourceGraph: sourceGraph)
            } else { shader = original }
            var slots = Array<Template.TextureSlot?>(repeating: nil, count: 8)
            for binding in node.bindings {
                slots[binding.slot!] = .init(index: binding.slot!, candidates: [
                    .init(reference: .graph(binding.texture), provenance: .explicitBinding),
                ])
            }
            if name == "foreignResource" {
                slots[0] = .init(index: 0, candidates: [
                    .init(reference: .graph(foreignOutput), provenance: .explicitBinding),
                ])
            }
            if name == "mixedVariants" {
                slots[1] = .init(index: 1, candidates: [
                    .init(reference: .asset(optionalPath), provenance: .instance),
                ])
            }
            let template = Template.validated(textureSlots: slots, combos: [], uniformDeclarations: [],
                renderState: SceneMaterialRenderState.compile(blending: "normal", depthTest: "disabled",
                    depthWrite: "disabled", cullMode: "nocull", alphaWriting: nil)!,
                graphRole: .init(effectInput: role(effect.input), effectOutput: .effectOutput,
                    nodeTarget: role(node.target!), bindings: node.bindings.map {
                        .init(slot: $0.slot!, texture: role($0.texture)) }),
                effectContext: .init(key: effect.key, input: effect.input), shaderContract: shader,
                diagnosticProvenance: .init(nodeIndex: node.nodeIndex, authoredShaderPath: shader.identity,
                    contractIdentity: shader.identity, contractCanonicalSHA256: shader.canonicalSHA256,
                    textureSources: [], uniformSources: []))!
            entries[.init(effect: node.effect, nodeIndex: node.nodeIndex)] = .template(template)
        }
        let descriptor = SceneRenderDescriptor(layers: [.init(id: layer, effects: effects.map { effect in
            .init(id: effect.key.descriptorID, file: effect.definitionPath, visible: true,
                passes: nodes.filter { $0.effect == effect.key }.map {
                    .init(passIndex: $0.instancePassIndex!, combos: [:]) })
        }, utilityLayer: .init(kind: .fullscreen))], materialPasses: nodes.map {
            .init(id: $0.materialPassID!, materialPath: $0.materialPath!, combos: [:])
        }, effectDefinitions: effects.map { .init(relativePath: $0.definitionPath, functions: nil) })
        let candidates = SceneResolvedMaterialExecutionCapabilityAdmission.compile(
            descriptor: descriptor, authoredPlans: [graph])
        var observed: [String: Any] = ["admitted": false, "resolved": false]
        guard let candidate = candidates.first else { return observed }
        guard case let .success(admitted) = candidate.result else {
            observed["admissionFailure"] = String(describing: candidate.result)
            return observed
        }
        observed["admitted"] = true
        observed["capturedIngress"] = admitted.sourceRoute == .capturedMainTargetTexture
        var plans: [String] = []
        var initializedReads = 0
        for product in admitted.products {
            let inputRole = SceneAuthoredEffectInputValidator.role(for: product.graph.effects[0].input,
                layerID: layer)!
            switch Plan.make(graph: product.graph, inputRole: inputRole,
                inputWidth: 8, inputHeight: 8) {
            case let .success(plan):
                plans.append("ready")
                initializedReads += plan.logicalTargets.filter {
                    $0.initialClear != nil && $0.lifetime.requiresHistorySeed
                }.count
            case let .failure(failure): plans.append(failure.rawValue)
            }
        }
        observed["plans"] = plans
        observed["initializedReads"] = initializedReads
        let result = try Capabilities.compileProgramFirstStages(admitted,
            materialCatalog: .init(entries: entries), demandIssues: [], dynamicProducers: .empty,
            assetFormatFacts: [:], assetStates: [optionalIdentity: .ready(.data)],
            maximumVariantsPerMaterial: 8)
        switch result {
        case let .failure(failure): observed["stageFailure"] = failure.code
        case let .success(compiled):
            observed["stages"] = compiled.stages.map { $0.subject?.family ?? "none" }
            observed["resolved"] = compiled.stages.count == effects.count
                && compiled.stages.allSatisfy { if case .resolved = $0 { return true }; return false }
            observed["materialCount"] = compiled.materials.count
            let first = compiled.materials[.init(effect: owner, nodeIndex: firstIndex)]!
            let snapshots = first.variants.launchEnvelopeCapabilitySnapshot()
            observed["allVariantsReady"] = snapshots.allEntriesReady
            observed["variantSourceReads"] = snapshots.variants.map {
                $0.frontendProgram.textureBindings.contains { $0.slot == 0 }
            }.sorted { !$0 && $1 }
        }
        return observed
    }

    static func main() throws {
        setenv("MWX_SCENE_GENERIC_SHADER_ROUTE", "disable-generic", 1)
        let cache = FileManager.default.temporaryDirectory.appendingPathComponent(
            "mwx-source-independent-stage-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: cache) }
        setenv("MWX_SCENE_GENERIC_SHADER_CACHE", cache.path, 1)
        var cases: [String: [String: Any]] = [:]
        for name in ["generatedSuffix", "seededFBO", "clearedFBO", "mixedVariants",
                     "missingInitialization", "foreignTarget", "foreignResource"] {
            cases[name] = try run(name)
        }
        cases["renamedSuffix"] = try run("generatedSuffix", renamed: true)
        let raw = SceneResolvedMaterialAttachmentStorage.storedOutput(.preservedRGBAUnorm,
            attachmentStorage: .preservedRGBAUnorm)
        let boundaries = [
            "dataKeepsTypedStorage": raw?.content == .data && raw?.colorRepresentation == nil,
            "dataCannotBecomeColorAttachment": SceneResolvedMaterialAttachmentStorage.storedOutput(
                .preservedRGBAUnorm, attachmentStorage: .color) == nil,
        ]
        print(String(decoding: try JSONSerialization.data(withJSONObject: [
            "cases": cases, "boundaries": boundaries,
        ], options: [.sortedKeys]), as: UTF8.self))
    }
}
'''


def compile_harness(support_text: str, harness_text: str, additional_sources=()):
    # Graph fixtures assert Debug diagnostics as well as actual GPU results.
    with tempfile.TemporaryDirectory(
        prefix="mwx-resolved-material-graph-executor-"
    ) as directory:
        root = Path(directory)
        support = root / "Support.swift"
        harness = root / "Harness.swift"
        binary = root / "resolved-material-graph-executor-test"
        support.write_text(support_text, encoding="utf-8")
        harness.write_text(harness_text, encoding="utf-8")
        environment = os.environ.copy()
        environment["CLANG_MODULE_CACHE_PATH"] = str(root / "clang-cache")
        environment["SWIFT_MODULECACHE_PATH"] = str(root / "swift-cache")
        compilation = subprocess.run(
            [
                "xcrun",
                "--sdk",
                "macosx",
                "swiftc",
                "-parse-as-library",
                *GRAPH_SWIFT_FLAGS,
                str(support),
                *(str(path) for path in SWIFT_SOURCES),
                *(str(path) for path in additional_sources),
                str(harness),
                "-framework",
                "Metal",
                "-framework",
                "CoreGraphics",
                "-framework",
                "ImageIO",
                "-module-cache-path",
                str(root / "module-cache"),
                "-o",
                str(binary),
            ],
            cwd=REPOSITORY_ROOT,
            env=environment,
            capture_output=True,
            text=True,
        )
        if compilation.returncode != 0:
            return compilation, None
        completed = subprocess.run(
            [str(binary)],
            cwd=REPOSITORY_ROOT,
            env=environment,
            capture_output=True,
            text=True,
        )
        return compilation, separate_graph_debug_output(completed)


@unittest.skipUnless(shutil.which("swiftc"), "swiftc is required")
class SceneResolvedMaterialGraphVisualFailureContractTests(unittest.TestCase):
    def test_captured_ingress_is_optional_for_prepared_graph_programs(self) -> None:
        from script.tests import test_scene_resolved_material_graph_executor as base

        prefix, marker, _ = base.HARNESS.partition("@main\nprivate enum Harness")
        self.assertTrue(marker)
        compilation, completed = base.compile_harness(
            base.SUPPORT, prefix + SOURCE_INDEPENDENT_GRAPH_HARNESS
        )
        self.assertEqual(compilation.returncode, 0, compilation.stderr)
        self.assertIsNotNone(completed)
        assert completed is not None
        self.assertEqual(completed.returncode, 0, completed.stderr)
        payload = json.loads(completed.stdout)
        cases = payload["cases"]
        for name in ("generatedSuffix", "renamedSuffix", "seededFBO", "clearedFBO", "mixedVariants"):
            with self.subTest(case=name):
                row = cases[name]
                self.assertTrue(row["admitted"], payload)
                self.assertTrue(row["capturedIngress"], payload)
                self.assertTrue(row["resolved"], payload)
                self.assertTrue(all(value == "ready" for value in row["plans"]), payload)
                self.assertTrue(row["allVariantsReady"], payload)
                expected_materials = 2 if name.endswith("Suffix") else 1 if name == "mixedVariants" else 3
                self.assertEqual(row["materialCount"], expected_materials, payload)
                if name == "clearedFBO":
                    self.assertEqual(row["initializedReads"], 1, payload)
                if name == "mixedVariants":
                    self.assertEqual(row["variantSourceReads"], [False, True], payload)
        self.assertEqual(cases["missingInitialization"]["plans"], ["historyRequired"], payload)
        self.assertFalse(cases["foreignTarget"]["admitted"], payload)
        self.assertEqual(cases["foreignResource"].get("stageFailure"), "material-template-unsupported", payload)
        self.assertTrue(all(payload["boundaries"].values()), payload)

    def test_program_preparation_cancellation_stops_batches_after_join(self) -> None:
        from script.tests import test_scene_resolved_material_graph_executor as base

        prefix, marker, _ = base.HARNESS.partition("@main\nprivate enum Harness")
        self.assertTrue(marker)
        fixture = Path(__file__).with_name("fixtures") / "SceneProgramPreparationCancellationHarness.swift"
        compilation, completed = base.compile_harness(
            base.SUPPORT, prefix + fixture.read_text(encoding="utf-8"),
            additional_sources=[SCENE_ROOT / "Runtime/Session/SceneDesktopWallpaperLaunchModels.swift"],
        )
        self.assertEqual(compilation.returncode, 0, compilation.stderr)
        self.assertIsNotNone(completed)
        assert completed is not None
        self.assertEqual(completed.returncode, 0, completed.stderr)
        payload = json.loads(completed.stdout)
        self.assertEqual(len(payload["checks"]), 12, payload)
        self.assertTrue(all(payload["checks"].values()), payload)

    def test_launch_texture_binding_failure_keeps_healthy_effect_stages(self) -> None:
        from script.tests import test_scene_resolved_material_graph_executor as base

        # Compile the shared fixture declarations with an admission-only main;
        # no Metal command, texture, pipeline or GPU readback is created here.
        prefix, marker, _ = base.HARNESS.partition("@main\nprivate enum Harness")
        self.assertTrue(marker)
        harness = prefix + r'''
@main private enum LaunchTextureFailureHarness {
    static func main() throws {
        setenv("MWX_SCENE_GENERIC_SHADER_ROUTE", "disable-generic", 1)
        let graph = chainedGraph()
        let chain = orderedLayerGraph(graph)
        let missing = capabilities(chain, catalog: catalog(
            for: graph, colorBlendNodes: [1]
        ))
        let claim = missing.claim(chain)
        let compiled = claim.flatMap { missing.resolve($0.token, for: chain) }
        let stages = compiled?.stages.map { $0.subject?.family ?? "none" } ?? []
        let reasons = compiled?.stages.map { $0.visualFailureReasonCode ?? "none" } ?? []
        let survivingMaterials = graph.nodes.map { node in
            compiled?.material(effect: node.effect, nodeIndex: node.nodeIndex) != nil
        }
        var strict: [String: Bool] = [:]
        for (name, phase, code) in [
            ("resource", SceneResolvedMaterialFailure.Phase.texture,
                SceneResolvedMaterialFailure.Code.resourceSnapshotUnresolved),
            ("identity", .invariant, .identityInvariant),
            ("reference", .texture, .textureReferenceInvalid),
            ("frame", .invariant, .frameSnapshotMismatch),
        ] {
            let key = SceneResolvedMaterialRuntimeCatalog.Key(
                effect: graph.nodes[1].effect, nodeIndex: graph.nodes[1].nodeIndex
            )
            var entries = catalog(for: graph).entries
            entries[key] = .failure(.init(phase: phase, code: code, slot: 1, details: []))
            let rejected = capabilities(chain, catalog: .init(entries: entries,
                resourceDemandIssues: []))
            strict[name] = rejected.claim(chain) == nil
        }
        let payload: [String: Any] = [
            "claimed": claim != nil, "stages": stages, "reasons": reasons,
            "survivingMaterials": survivingMaterials, "strict": strict,
            "report": missing.reportLines,
        ]
        print(String(decoding: try JSONSerialization.data(withJSONObject: payload,
            options: [.sortedKeys]), as: UTF8.self))
    }
}
'''
        compilation, completed = base.compile_harness(base.SUPPORT, harness)
        self.assertEqual(compilation.returncode, 0, compilation.stderr)
        self.assertIsNotNone(completed)
        assert completed is not None
        self.assertEqual(completed.returncode, 0, completed.stderr)
        payload = json.loads(completed.stdout)
        self.assertTrue(payload["claimed"], payload)
        self.assertEqual(payload["stages"], [
            "resolved-material", "visual-failure-passthrough", "resolved-material"
        ], payload)
        self.assertEqual(payload["reasons"], [
            "none", "material-variant-envelope-texture-binding", "none"
        ], payload)
        self.assertEqual(payload["survivingMaterials"], [True, False, True], payload)
        self.assertEqual(payload["strict"], {
            "resource": True, "identity": True, "reference": True, "frame": True
        }, payload)

    def test_visual_failure_passthrough_keeps_exact_reason_allowlist(self) -> None:
        for source in (
            PROGRAM_FIRST_STAGES_SOURCE,
            VISUAL_FAILURE_PASSTHROUGH_SOURCE,
        ):
            text = source.read_text(encoding="utf-8")
            for reason in (
                "material-variant-envelope-frontend",
                "material-variant-envelope-shader-preparation",
                "material-generic-owner-revoked",
                "material-variant-envelope-color-contract",
                "material-variant-envelope-uniform-schema",
            ):
                self.assertIn(f'"{reason}"', text)
            for reason in (
                "material-variant-envelope-texture",
                "material-variant-envelope-target",
                "material-variant-envelope-runtime-encode",
            ):
                self.assertNotIn(f'"{reason}"', text)
        visual_text = VISUAL_FAILURE_PASSTHROUGH_SOURCE.read_text(encoding="utf-8")
        self.assertIn(
            'reasonCode != "material-finalizer-color-contract"',
            visual_text,
        )
        self.assertIn("graph.renderTargets.isEmpty", visual_text)
        for reason in (
            "material-finalizer-dynamic-uniform-binding",
            "material-finalizer-static-uniform-binding",
            "material-finalizer-host-uniform-declaration-conflict",
            "material-finalizer-uniform-declaration-conflict",
            "material-finalizer-color-contract",
            "material-finalizer-optional-texture-unavailable",
            "material-finalizer-optional-texture-purpose-mismatch",
            "material-finalizer-optional-texture-content-mismatch",
            "material-finalizer-optional-texture-sampling-unresolved",
            "material-finalizer-system-provider-pending",
            "material-finalizer-system-provider-unavailable",
            "material-finalizer-system-provider-purpose-mismatch",
            "material-finalizer-system-provider-sampling-unresolved",
            "material-dynamic-uniform-contributor-policy",
            "material-dynamic-uniform-contributor-producer-unavailable",
            "material-dynamic-uniform-script-attachment-unproven",
            "material-dynamic-uniform-producer-unavailable",
        ):
            self.assertIn(f'"{reason}"', visual_text)
        for reason in (
            "material-finalizer-resource",
            "material-finalizer-texture",
            "material-finalizer-host-uniform-binding",
            "material-finalizer-active-uniform-schema",
        ):
            self.assertNotIn(f'"{reason}"', visual_text)
        self.assertNotIn(
            "SceneOffscreenEffectRenderer",
            EXECUTOR_SOURCE.read_text(encoding="utf-8"),
        )
        self.assertNotIn(
            "SceneOffscreenEffectRenderer",
            MAIN_GATE.read_text(encoding="utf-8"),
        )


if __name__ == "__main__":
    unittest.main()
