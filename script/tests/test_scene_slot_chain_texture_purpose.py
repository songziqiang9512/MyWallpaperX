#!/usr/bin/env python3

"""Ordinal-aware authored slot-chain purpose across catalog, launch and frame."""

from __future__ import annotations

import json
import os
from pathlib import Path
import runpy
import subprocess
import tempfile
import unittest


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
BASE = runpy.run_path(
    str(REPOSITORY_ROOT / "script/tests/test_scene_resolved_material_execution_capability.py")
)
SWIFT_SOURCES = BASE["CATALOG_DEMAND_SWIFT_SOURCES"]

_SLOT_ANCHOR = '''        var slots = Array<Template.TextureSlot?>(repeating: nil, count: 8)
        slots[0] = .init(index: 0, candidates: [
            .init(
                reference: .graph(effect.input),
                provenance: .explicitBinding
            ),
        ])'''
_SLOT_REPLACEMENT = '''        var slots = Array<Template.TextureSlot?>(repeating: nil, count: 8)
        slots[2] = .init(index: 2, candidates: [
            .init(
                reference: .asset(SceneVFSAssetPath("effects/waterflowphase")!),
                provenance: .material
            ),
            .init(
                reference: .asset(SceneVFSAssetPath("fixtures/unseen/phase-override")!),
                provenance: .instance
            ),
        ])'''
_BINDING_ANCHOR = '''                bindings: [.init(slot: 0, texture: .layerSource)]'''
_BINDING_REPLACEMENT = '''                bindings: []'''
SUPPORT = BASE["CATALOG_DEMAND_SUPPORT"]
assert _SLOT_ANCHOR in SUPPORT and _BINDING_ANCHOR in SUPPORT
SUPPORT = SUPPORT.replace(_SLOT_ANCHOR, _SLOT_REPLACEMENT).replace(
    _BINDING_ANCHOR, _BINDING_REPLACEMENT
)


HARNESS = r'''
import Foundation
import Metal
import simd

private typealias Graph = SceneAuthoredEffectRenderPlan
private typealias Program = SceneResolvedMaterialProgram
private typealias Template = SceneResolvedMaterialTemplate
private let layerID = 987
private let effectKey = Graph.EffectKey(
    layerID: layerID, effectIndex: 0, descriptorID: "slot-chain-purpose"
)
private let materialPath = SceneVFSAssetPath("effects/waterflowphase")!
private let instancePath = SceneVFSAssetPath("fixtures/unseen/phase-override")!

private func source() -> Graph.TextureIdentity {
    .init(kind: .layerSource, layerID: layerID, effect: nil, name: nil)
}

private func output() -> Graph.TextureIdentity {
    .init(kind: .effectOutput, layerID: layerID, effect: effectKey, name: nil)
}

private func graph() -> Graph {
    let node = Graph.Node(
        nodeIndex: 0, effect: effectKey, definitionPassIndex: 0,
        materialOrdinal: 0, instancePassIndex: 0, kind: .material,
        materialPath: "materials/slot-chain-purpose.json",
        materialPassID: "slot-chain-purpose", target: output(), bindings: [],
        commandSource: nil, commandTarget: nil, compose: nil, conditions: nil
    )
    return .init(
        layerID: layerID,
        effects: [.init(
            key: effectKey, definitionPath: "effects/slot-chain-purpose/effect.json",
            input: source(), output: output(), nodeIndices: [0]
        )],
        renderTargets: [], nodes: [node], finalOutput: output(), blockers: []
    )
}

private func contract() -> SceneShaderContract {
    let vertex = """
    attribute vec3 a_Position;
    attribute vec2 a_TexCoord;
    varying vec2 v_TexCoord;
    void main() { v_TexCoord = a_TexCoord; gl_Position = vec4(a_Position, 1.0); }
    """
    let fragment = """
    varying vec2 v_TexCoord;
    uniform sampler2D g_Texture2;
    void main() {
        float phase = texSample2D(g_Texture2, v_TexCoord).r;
        gl_FragColor = vec4(phase);
    }
    """
    func stage(
        _ kind: SceneShaderContract.StageKind, _ path: String, _ source: String
    ) -> SceneShaderContract.Stage {
        let parsed = SceneShaderContractSourceParser().parse(
            source, stageRelativePath: path
        )
        return .init(
            kind: kind, relativePath: path, source: source,
            rawSHA256: SceneShaderStableDigest.hash(Data(source.utf8)),
            includes: parsed.includes, annotations: parsed.annotations,
            declarations: parsed.declarations
        )
    }
    let stages = [
        stage(.vertex, "fixture/slot.vert", vertex),
        stage(.fragment, "fixture/slot.frag", fragment),
    ]
    return .init(
        identity: "fixture/catalog-demand", sourceKind: .authoredSource,
        stages: stages, diagnostics: [], canonicalSHA256: "slot-chain-purpose",
        sourceGraph: .init(
            roots: [
                .init(label: "vertex", virtualPath: "fixture/slot.vert"),
                .init(label: "fragment", virtualPath: "fixture/slot.frag"),
            ],
            nodes: stages.map {
                .init(
                    virtualPath: $0.relativePath, provenance: .package,
                    source: $0.source, rawSHA256: $0.rawSHA256,
                    byteCount: $0.source.utf8.count
                )
            },
            edges: [], diagnostics: [], dependencySHA256: "slot-chain-dependency"
        )
    )
}

private func catalog(
    graph: Graph, contract: SceneShaderContract
) -> SceneResolvedMaterialRuntimeCatalog {
    .init(
        descriptor: .init(),
        admissionCandidates: [.init(result: .success(.init(
            products: [.init(graph: graph)]
        )))],
        shaderContracts: [contract]
    )
}

private func validatedTemplate(
    from template: Template,
    candidates: [Template.TextureCandidate]
) -> Template {
    var slots = template.textureSlots
    slots[2] = .init(index: 2, candidates: candidates)
    return Template.validated(
        textureSlots: slots, combos: template.combos,
        inheritedInactiveCombos: Set(template.inheritedInactiveCombos),
        uniformDeclarations: template.uniformDeclarations,
        renderState: template.renderState, graphRole: template.graphRole,
        shaderContract: template.shaderContract,
        diagnosticProvenance: template.diagnosticProvenance
    )!
}

private func sampler(
    _ template: Template
) -> SceneResolvedMaterialShaderSchema.Sampler {
    try! SceneResolvedMaterialShaderSchema.unconditionalSamplers(template)[2]!
}

private func purpose(
    _ template: Template,
    ordinal: Int,
    samplerOverride: SceneResolvedMaterialShaderSchema.Sampler? = nil
) -> SceneTextureLoadPurpose? {
    SceneResolvedMaterialTextureSlotPurpose.fact(
        in: template.textureSlots[2]!, candidateOrdinal: ordinal,
        sampler: samplerOverride ?? sampler(template)
    )?.purpose
}

private func sourceProvenSampler(
    _ template: Template,
    defaultPath: SceneVFSAssetPath? = nil
) -> SceneResolvedMaterialShaderSchema.Sampler {
    let base = sampler(template)
    return .init(
        name: base.name,
        slot: base.slot,
        mode: base.mode,
        materialKey: base.materialKey,
        isHidden: base.isHidden,
        defaultTexture: defaultPath.map {
            SceneResolvedMaterialShaderSchema.DefaultTexture.asset($0)
        } ?? base.defaultTexture,
        readinessCombo: base.readinessCombo,
        channelUse: base.channelUse,
        sourceProvenPurpose: .straightAlbedo
    )
}

private func launchToken(
    _ template: Template,
    states: [SceneAssetTextureIdentity: SceneAssetTextureLaunchState]
) -> String {
    do {
        switch try SceneResolvedMaterialTextureResolver.launchAuthoredReference(
            template: template, sampler: sampler(template), slot: 2,
            assetStates: states
        ) {
        case let .selected(reference, selectedPurpose):
            let path: String = if case let .asset(value) = reference {
                value.value
            } else { "not-asset" }
            return "selected:\(path):\(selectedPurpose?.reportToken ?? "nil")"
        case .none: return "none"
        case .deferred: return "deferred"
        }
    } catch let failure as SceneResolvedMaterialFailure {
        return "\(failure.phase.rawValue)/\(failure.code.rawValue)/\(failure.slot ?? -1)"
    } catch { return "unexpected" }
}

private func texture(_ device: MTLDevice) -> MTLTexture {
    let descriptor = MTLTextureDescriptor.texture2DDescriptor(
        pixelFormat: .rgba8Unorm, width: 2, height: 2, mipmapped: false
    )
    descriptor.storageMode = .shared
    descriptor.usage = .shaderRead
    return device.makeTexture(descriptor: descriptor)!
}

private func ready(
    _ device: MTLDevice,
    request: SceneFrameTextureIdentity,
    candidatePurpose: SceneTextureLoadPurpose = .phase,
    requestOverride: SceneFrameTextureIdentity? = nil,
    generationMismatch: Bool = false
) -> SceneFrameTextureLookupStatus {
    let revision = SceneTextureFileRevision(
        fileSystemID: 1, fileID: 2, statusChangedAtSeconds: 3,
        statusChangedAtNanoseconds: 4
    )
    let candidate = SceneTextureCandidate(
        texture: texture(device), identity: .file(path: instancePath.value),
        generation: generationMismatch
            ? .provider(contentGeneration: 9)
            : .file(byteCount: 16, modifiedAtBits: 5, revision: revision),
        purpose: candidatePurpose, content: .data,
        physicalSize: CGSize(width: 2, height: 2),
        mappedSize: CGSize(width: 2, height: 2), uvTransform: .identity,
        sampling: .directImageFallback
    )
    return .ready(.init(
        publication: .init(
            requestIdentity: requestOverride ?? request, candidate: candidate,
            contentGeneration: 1
        ),
        resourceGeneration: 1
    ))
}

private func input(
    _ template: Template,
    entries: [SceneFrameTextureIdentity: SceneFrameTextureLookupStatus]
) -> SceneResolvedMaterialFinalizationInput {
    let dynamic = SceneDynamicSnapshotResolver().resolve(
        frameIndex: 1, generation: 1, definitions: [], userValues: [:],
        timelineValues: [:], sceneScriptValues: [:]
    ).snapshot
    let frameInputs = SceneAuthoredShaderFrameInputs(
        frameIndex: 1, screenSize: CGSize(width: 2, height: 2), sceneTime: 0,
        dayTime: 0, frameTime: 1 / 60, pointerCurrentNDC: .zero,
        pointerPreviousNDC: .zero, pointerPrimaryButtonDown: false,
        parallaxPositionNDC: .zero, audioSpectrum: .silent
    )
    guard case let .success(frame) = SceneResolvedMaterialFrameSnapshot.validated(
        textureSnapshot: .init(frameEpoch: 1, frameIndex: 1, entries: entries),
        dynamicSnapshot: dynamic, frameInputs: frameInputs
    ) else { fatalError("frame") }
    return frame.finalizationInput(
        template: template, renderSize: CGSize(width: 2, height: 2),
        modelViewProjection: matrix_identity_float4x4,
        layerModelMatrix: matrix_identity_float4x4,
        effectTextureProjectionMatrixInverse: matrix_identity_float4x4
    )
}

private func resultToken(
    _ result: Result<Program, SceneResolvedMaterialFailure>
) -> String {
    switch result {
    case let .success(program):
        guard let slot = program.textureSlots[2],
              case let .asset(path) = slot.reference else { return "bad-program" }
        return "success:\(path.value):\(slot.expectedPurpose.reportToken):"
            + "\(program.semanticIdentity.textureSlots[2]!.purpose.reportToken):"
            + "\(program.exactIdentity.textureSlots[2]!.purpose.reportToken)"
    case let .failure(failure):
        return "\(failure.phase.rawValue)/\(failure.code.rawValue)/\(failure.slot ?? -1)"
    }
}

@main
private enum Main {
    static func main() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            print(#"{"metalAvailable":false}"#); return
        }
        let graph = graph()
        let catalog = catalog(graph: graph, contract: contract())
        let template: Template
        switch catalog.entry(for: graph.nodes[0]) {
        case let .template(value): template = value
        case let .failure(failure):
            fatalError(
                "catalog-template:\(failure.phase.rawValue)/"
                    + "\(failure.code.rawValue)/\(failure.boundedDetails)"
            )
        case nil: fatalError("catalog-template:nil")
        }
        let materialIdentity = SceneAssetTextureIdentity(
            path: materialPath, purpose: .phase
        )
        let instanceIdentity = SceneAssetTextureIdentity(
            path: instancePath, purpose: .phase
        )
        let launchReady: [SceneAssetTextureIdentity: SceneAssetTextureLaunchState] = [
            materialIdentity: .ready(.data), instanceIdentity: .ready(.data),
        ]
        let cache: SceneResolvedMaterialVariantCache
        guard case let .success(value) = SceneResolvedMaterialVariantCache
            .launchValidated(template: template, maximumVariantCount: 8) else {
            fatalError("launch-validation")
        }
        switch value.precompileLaunchEnvelope(
            implicitFramebufferIdentity: nil,
            outputStorage: .scalarRedUnorm,
            assetStates: launchReady
        ) {
        case .success: break
        case .failure(.capacity): fatalError("launch-envelope:capacity")
        case let .failure(.material(failure)):
            fatalError(
                "launch-envelope:\(failure.phase.rawValue)/"
                    + "\(failure.code.rawValue)/\(failure.boundedDetails)"
            )
        }
        cache = value

        let materialRequest = SceneFrameTextureIdentity.asset(materialIdentity)
        let instanceRequest = SceneFrameTextureIdentity.asset(instanceIdentity)
        let materialReady = ready(device, request: materialRequest)
        let instanceReady = ready(device, request: instanceRequest)
        func finalize(
            _ instance: SceneFrameTextureLookupStatus?
        ) -> String {
            var entries = [materialRequest: materialReady]
            if let instance { entries[instanceRequest] = instance }
            return resultToken(SceneResolvedMaterialProgramFinalizer.finalize(
                input(template, entries: entries), variantCache: cache,
                outputStorage: .scalarRedUnorm
            ))
        }

        let phase = Template.TextureCandidate(
            reference: .asset(materialPath), provenance: .material
        )
        let unknown = Template.TextureCandidate(
            reference: .asset(instancePath), provenance: .instance
        )
        let untypedLower = Template.TextureCandidate(
            reference: .asset(SceneVFSAssetPath("fixtures/untyped-lower")!),
            provenance: .material
        )
        let conflict = Template.TextureCandidate(
            reference: .asset(SceneVFSAssetPath("effects/waterripplenormal")!),
            provenance: .instance
        )
        let intervening = Template.TextureCandidate(
            reference: .asset(SceneVFSAssetPath("fixtures/intervening")!),
            provenance: .userTexture
        )
        let graphCandidate = Template.TextureCandidate(
            reference: .graph(source()), provenance: .explicitBinding
        )
        let providerCandidate = Template.TextureCandidate(
            reference: .provider(.system("fixture")), provenance: .userTexture
        )
        let userCandidate = Template.TextureCandidate(
            reference: .userProperty(.init(key: "fixture")),
            provenance: .userTexture
        )
        let wrongOrder = validatedTemplate(from: template, candidates: [
            .init(reference: .asset(materialPath), provenance: .instance),
            .init(reference: .asset(instancePath), provenance: .material),
        ])
        let wrongPublication = SceneFrameTextureIdentity.asset(materialIdentity)
        let provenSampler = sourceProvenSampler(template)
        let results: [String: Any] = [
            "metalAvailable": true,
            "catalog": [
                "material": catalog.assetDemands.contains(materialIdentity),
                "instance": catalog.assetDemands.contains(instanceIdentity),
                "issueCount": catalog.resourceDemandIssues.count,
            ],
            "purpose": [
                "positive": purpose(template, ordinal: 1)?.reportToken ?? "nil",
                "singleUnknown": purpose(
                    validatedTemplate(from: template, candidates: [unknown]),
                    ordinal: 0
                ) == nil,
                "untypedLower": purpose(
                    validatedTemplate(from: template, candidates: [untypedLower, unknown]),
                    ordinal: 1
                ) == nil,
                "conflict": purpose(
                    validatedTemplate(from: template, candidates: [phase, conflict]),
                    ordinal: 1
                ) == nil,
                "graph": purpose(
                    validatedTemplate(from: template, candidates: [graphCandidate, unknown]),
                    ordinal: 1
                ) == nil,
                "provider": purpose(
                    validatedTemplate(from: template, candidates: [providerCandidate, unknown]),
                    ordinal: 1
                ) == nil,
                "user": purpose(
                    validatedTemplate(from: template, candidates: [userCandidate, unknown]),
                    ordinal: 1
                ) == nil,
                "intervening": purpose(
                    validatedTemplate(
                        from: template, candidates: [phase, intervening, unknown]
                    ), ordinal: 2
                ) == nil,
                "wrongOrder": purpose(wrongOrder, ordinal: 1) == nil,
                "wrongOrdinal": SceneResolvedMaterialTextureSlotPurpose.fact(
                    in: template.textureSlots[2]!, candidateOrdinal: 7,
                    sampler: sampler(template)
                ) == nil,
                "sourceUnregistered": purpose(
                    validatedTemplate(from: template, candidates: [unknown]),
                    ordinal: 0,
                    samplerOverride: provenSampler
                )?.reportToken == "straight-albedo",
                "sourceUser": purpose(
                    validatedTemplate(from: template, candidates: [userCandidate]),
                    ordinal: 0,
                    samplerOverride: provenSampler
                )?.reportToken == "straight-albedo",
                "sourceCurrentRegistryConflict": purpose(
                    validatedTemplate(from: template, candidates: [conflict]),
                    ordinal: 0,
                    samplerOverride: provenSampler
                ) == nil,
                "sourceLowerRegistryConflict": purpose(
                    validatedTemplate(from: template, candidates: [phase, unknown]),
                    ordinal: 1,
                    samplerOverride: provenSampler
                ) == nil,
                "sourceUserLowerRegistryConflict": purpose(
                    validatedTemplate(from: template, candidates: [phase, userCandidate]),
                    ordinal: 1,
                    samplerOverride: provenSampler
                ) == nil,
                "sourceDefaultRegistryConflict": purpose(
                    validatedTemplate(from: template, candidates: [unknown]),
                    ordinal: 0,
                    samplerOverride: sourceProvenSampler(
                        template,
                        defaultPath: materialPath
                    )
                ) == nil,
            ],
            "launch": [
                "ready": launchToken(template, states: launchReady),
                "instanceAbsent": launchToken(template, states: [
                    materialIdentity: .ready(.data), instanceIdentity: .absent,
                ]),
                "pending": launchToken(template, states: [
                    materialIdentity: .ready(.data), instanceIdentity: .pending,
                ]),
                "missing": launchToken(template, states: [
                    materialIdentity: .ready(.data),
                ]),
                "unavailable": launchToken(template, states: [
                    materialIdentity: .ready(.data), instanceIdentity: .unavailable,
                ]),
            ],
            "frame": [
                "ready": finalize(instanceReady),
                "instanceAbsent": finalize(.absent),
                "pending": finalize(.pending),
                "missing": finalize(nil),
                "unavailable": finalize(.unavailable),
                "wrongPurpose": finalize(ready(
                    device, request: instanceRequest, candidatePurpose: .normal
                )),
                "wrongPublication": finalize(ready(
                    device, request: instanceRequest,
                    requestOverride: wrongPublication
                )),
                "wrongGeneration": finalize(ready(
                    device, request: instanceRequest, generationMismatch: true
                )),
            ],
        ]
        let data = try JSONSerialization.data(
            withJSONObject: results, options: [.sortedKeys]
        )
        FileHandle.standardOutput.write(data)
    }
}
'''


class SceneSlotChainTexturePurposeTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.temporary_directory = tempfile.TemporaryDirectory(
            prefix="mwx-slot-chain-texture-purpose-"
        )
        root = Path(cls.temporary_directory.name)
        support = root / "Support.swift"
        harness = root / "Harness.swift"
        binary = root / "slot-chain-texture-purpose-test"
        support.write_text(SUPPORT, encoding="utf-8")
        harness.write_text(HARNESS, encoding="utf-8")
        environment = os.environ.copy()
        environment["CLANG_MODULE_CACHE_PATH"] = str(root / "clang-cache")
        environment["SWIFT_MODULECACHE_PATH"] = str(root / "swift-cache")
        environment["MWX_SCENE_GENERIC_SHADER_ROUTE"] = "disable-generic"
        compilation = subprocess.run(
            [
                "xcrun", "--sdk", "macosx", "swiftc", "-parse-as-library",
                str(support), *(str(path) for path in SWIFT_SOURCES), str(harness),
                "-framework", "Metal", "-framework", "CoreGraphics",
                "-module-cache-path", str(root / "module-cache"), "-o", str(binary),
            ],
            cwd=REPOSITORY_ROOT, env=environment,
            capture_output=True, text=True,
        )
        if compilation.returncode != 0:
            raise RuntimeError(compilation.stderr)
        completed = subprocess.run(
            [str(binary)], cwd=REPOSITORY_ROOT, env=environment,
            capture_output=True, text=True,
        )
        if completed.returncode != 0:
            raise RuntimeError(completed.stderr or completed.stdout)
        cls.result = json.loads(completed.stdout)
        if not cls.result["metalAvailable"]:
            raise unittest.SkipTest("Metal is unavailable")

    @classmethod
    def tearDownClass(cls) -> None:
        cls.temporary_directory.cleanup()

    def test_slot_chain_fact_is_strict_and_shared(self) -> None:
        self.assertEqual(
            self.result["catalog"],
            {"material": True, "instance": True, "issueCount": 0},
            self.result,
        )
        self.assertEqual(self.result["purpose"].pop("positive"), "phase")
        self.assertTrue(all(self.result["purpose"].values()), self.result)

    def test_only_explicit_absent_falls_back_at_launch_and_frame(self) -> None:
        self.assertEqual(
            self.result["launch"],
            {
                "ready": "selected:fixtures/unseen/phase-override:phase",
                "instanceAbsent": "selected:effects/waterflowphase:phase",
                "pending": "texture/textureBindingInvalid/2",
                "missing": "texture/textureBindingInvalid/2",
                "unavailable": "texture/textureBindingInvalid/2",
            },
            self.result,
        )
        self.assertEqual(
            self.result["frame"],
            {
                "ready": "success:fixtures/unseen/phase-override:phase:phase:phase",
                "instanceAbsent": "success:effects/waterflowphase:phase:phase:phase",
                "pending": "texture/resourceSnapshotUnresolved/2",
                "missing": "texture/resourceSnapshotUnresolved/2",
                "unavailable": "texture/resourceSnapshotUnresolved/2",
                "wrongPurpose": "texture/textureMetadataIncomplete/2",
                "wrongPublication": "texture/textureMetadataIncomplete/2",
                "wrongGeneration": "texture/textureMetadataIncomplete/2",
            },
            self.result,
        )


if __name__ == "__main__":
    unittest.main()
