#!/usr/bin/env python3

"""Captured-main preflight visual-failure containment contracts."""

from __future__ import annotations

import importlib.util
import json
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
BRIDGE_TEST = Path(__file__).with_name(
    "test_scene_resolved_material_runtime_bridge.py"
)
COORDINATOR = (
    REPOSITORY_ROOT
    / "MyWallpaperX/Core/SteamWorkshopScene/Runtime/ResolvedMaterialExecution"
    / "SceneResolvedMaterialSubmissionCoordinator.swift"
)
COMPOSITION = (
    REPOSITORY_ROOT
    / "MyWallpaperX/Core/SteamWorkshopScene/Rendering"
    / "SceneResolvedMaterialGraphComposition.swift"
)
EXECUTOR_VALIDATION = (
    REPOSITORY_ROOT
    / "MyWallpaperX/Core/SteamWorkshopScene/RenderGraph/EffectExecution"
    / "SceneResolvedMaterialGraphExecutor+Validation.swift"
)


def load_bridge_fixture_module():
    spec = importlib.util.spec_from_file_location(
        "scene_runtime_bridge_fixture",
        BRIDGE_TEST,
    )
    if spec is None or spec.loader is None:
        raise RuntimeError("runtime bridge fixture module unavailable")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def augmented_harness(source: str) -> str:
    replacements = {
        (
            "        var isColorContractVisualRejection: Bool { false }"
        ): (
            "        case colorContractVisual =\n"
            '            "fixture-finalizer-color-colorContractUnproven"\n'
            "        var isColorContractVisualRejection: Bool {\n"
            "            self == .colorContractVisual\n"
            "        }"
        ),
        (
            "    static var preparedByToken: [Int: PreparedGraph] = [:]\n"
            "    static var preparedDependencyTextureByToken:"
        ): (
            "    static var preparedByToken: [Int: PreparedGraph] = [:]\n"
            "    static var failureByToken: [Int: Failure] = [:]\n"
            "    static var preparedDependencyTextureByToken:"
        ),
        (
            "        Self.prepareCallCount += 1\n"
            "        Self.prepareTokens.append(token.value)\n"
            "        if let texture = frameInputs.dependencyEffect?.texture {"
        ): (
            "        Self.prepareCallCount += 1\n"
            "        Self.prepareTokens.append(token.value)\n"
            "        if let failure = Self.failureByToken[token.value] {\n"
            "            return .failure(failure)\n"
            "        }\n"
            "        if let texture = frameInputs.dependencyEffect?.texture {"
        ),
    }
    for old, new in replacements.items():
        if source.count(old) != 1:
            raise AssertionError(f"fixture replacement count != 1: {old[:80]}")
        source = source.replace(old, new)

    insertion = r'''
        func capability(
            layerID: Int,
            sourceRoute: SceneResolvedMaterialAdmittedLayer.SourceRoute,
            dependencyOwnership: SceneResolvedMaterialDependencyOwnership = .none
        ) -> SceneResolvedMaterialExecutionCapabilityCatalog.ChainCapability {
            let catalog = makeCapabilities(
                layerIDs: [layerID],
                dependencyOwnershipByLayerID: [layerID: dependencyOwnership]
            )
            guard let original = catalog.capabilitiesByLayerID[layerID] else {
                fatalError("capability unavailable")
            }
            return .init(
                layerID: original.layerID,
                pairPlan: original.pairPlan,
                admittedProducts: original.admittedProducts,
                stages: original.stages,
                fullFrameExtentPolicy: original.fullFrameExtentPolicy,
                dependencyOwnership: original.dependencyOwnership,
                sourceRoute: sourceRoute
            )
        }

        do {
            SceneResolvedMaterialGraphExecutor.prepareCallCount = 0
            SceneResolvedMaterialGraphExecutor.prepareTokens = []
            SceneResolvedMaterialGraphExecutor.failureByToken = [
                7: .colorContractVisual,
            ]
            let prepared8 = makeAtomicPrepared(
                device: device, layerID: 8, generation: 2
            )
            SceneResolvedMaterialGraphExecutor.preparedByToken = [8: prepared8]
            SceneResolvedMaterialGraphExecutor.encodeSucceeds = true
            let recorder = LogRecorder()
            let capabilities = SceneResolvedMaterialExecutionCapabilityCatalog(
                capability: capability(
                    layerID: 7,
                    sourceRoute: .capturedMainTargetTexture
                ),
                additionalCapabilities: [capability(
                    layerID: 8,
                    sourceRoute: .capturedLayerTexture
                )]
            )
            let coordinator = Coordinator(
                device: device,
                capabilities: capabilities,
                logSink: recorder.append
            )
            let buffer = queue.makeCommandBuffer()!
            coordinator.beginFrame(
                textureSnapshot: .init(frameIndex: 73, valid: true),
                dynamicSnapshot: .init(),
                frameInputs: .init()
            )
            func preflightClaim(_ layerID: Int) ->
                SceneResolvedMaterialRuntimeBridge.ClaimedExecution {
                switch coordinator.preflightClaim(layerID: layerID) {
                case let .claimed(value): return value
                case let .rejected(reasonCode): fatalError(reasonCode)
                case .notMigrated: fatalError("claim unavailable")
                }
            }
            let claims = [7, 8].map(preflightClaim)
            let targets7 = makeAtomicTargets(layerID: 7, generation: 1)
            let targets8 = makeAtomicTargets(layerID: 8, generation: 2)
            let pool = SceneOffscreenTexturePool(factory: { plan in
                plan.graphPlan.key.layerID == 7
                    ? targets7.prepared : targets8.prepared
            })
            let preparation = coordinator.prepareFrame(
                claims.map { claim in
                    .init(
                        claim: claim,
                        targetPlan: .init(
                            token: claim.token,
                            allocation: .init(graphPlan: .init(
                                key: .init(layerID: claim.layerID)
                            ))
                        ),
                        sourceTexture: makeTexture(
                            device, "local-preflight-source-\(claim.layerID)"
                        ),
                        sourceUniforms: .init(),
                        sourcePipeline: .init(),
                        frameInputs: .fixture
                    )
                },
                pool: pool,
                commandBuffer: buffer
            )
            let preparationReady: Bool
            if case .ready = preparation { preparationReady = true }
            else { preparationReady = false }
            let outputs = coordinator.preparedOutputTexturesByLayerID()
            let outputSetIsIndependent = outputs?.count == 1
                && outputs?[7] == nil
                && outputs?[8].map { $0 === prepared8.finalTexture } == true
            let failedUtilityIsLocal: Bool
            switch coordinator.claim(layerID: 7) {
            case let .rejected(reasonCode):
                failedUtilityIsLocal = reasonCode
                    == "captured-main-color-contract-unproven"
            case .claimed, .notMigrated:
                failedUtilityIsLocal = false
            }
            let independentCompleted: Bool
            switch coordinator.claim(layerID: 8) {
            case let .claimed(claim):
                switch coordinator.executeClaimed(
                    claim: claim,
                    dependencyEffect: nil,
                    commandBuffer: buffer
                ) {
                case let .encoded(texture, ticket):
                    if case .consumed = coordinator.markComposite(
                        ticket, texture: texture, consumed: true
                    ) {
                        independentCompleted = true
                    } else {
                        independentCompleted = false
                    }
                case .failed:
                    independentCompleted = false
                }
            case .rejected, .notMigrated:
                independentCompleted = false
            }
            let sealed = coordinator.sealFrame(on: buffer)
            buffer.commit()
            buffer.waitUntilCompleted()
            coordinator.completeCommandBuffer(
                identity: ObjectIdentifier(buffer),
                status: buffer.status == .completed && buffer.error == nil
                    ? .completed : .failed
            )
            let audit = coordinator.endFrame().first ?? ""
            let fallbackDiagnostics = recorder.lines.filter {
                $0.contains(
                    "layer-local-fallback count=1 entries=7:"
                        + "captured-main-color-contract-unproven"
                )
            }
            results[
                "capturedMainColorFailurePreservesIndependentFrameWork"
            ] = preparationReady
                && SceneResolvedMaterialGraphExecutor.prepareTokens == [7, 8]
                && failedUtilityIsLocal
                && outputSetIsIndependent
                && independentCompleted
                && sealed
                && buffer.status == .completed
                && buffer.error == nil
                && pool.batchCommitCount == 1
                && targets7.commit.submissionPin.releaseCount == 0
                && targets8.commit.submissionPin.releaseCount == 1
                && coordinator.activeByID.isEmpty
                && coordinator.pendingSubmissions.isEmpty
                && audit.contains("failures=0")
                && audit.contains("localFallbacks=1")
                && fallbackDiagnostics.count == 1
                && fallbackDiagnostics[0].contains(
                    "preflight=fixture-finalizer-color-"
                        + "colorContractUnproven"
                )
            targets7.commit.releaseAll()
            SceneResolvedMaterialGraphExecutor.failureByToken = [:]
            SceneResolvedMaterialGraphExecutor.preparedByToken = [:]
        }

        do {
            SceneResolvedMaterialGraphExecutor.prepareCallCount = 0
            SceneResolvedMaterialGraphExecutor.prepareTokens = []
            SceneResolvedMaterialGraphExecutor.failureByToken = [
                7: .colorContractVisual,
            ]
            let binding = externalPrimaryBinding(
                consumerLayerID: 8, providerLayerID: 7
            )
            let capabilities = SceneResolvedMaterialExecutionCapabilityCatalog(
                capability: capability(
                    layerID: 7,
                    sourceRoute: .capturedMainTargetTexture
                ),
                additionalCapabilities: [capability(
                    layerID: 8,
                    sourceRoute: .capturedLayerTexture,
                    dependencyOwnership: .externalPrimary(binding)
                )]
            )
            let coordinator = Coordinator(
                device: device,
                capabilities: capabilities,
                logSink: { _ in }
            )
            let buffer = queue.makeCommandBuffer()!
            coordinator.beginFrame(
                textureSnapshot: .init(frameIndex: 74, valid: true),
                dynamicSnapshot: .init(),
                frameInputs: .init()
            )
            func dependentClaim(_ layerID: Int) ->
                SceneResolvedMaterialRuntimeBridge.ClaimedExecution {
                switch coordinator.preflightClaim(layerID: layerID) {
                case let .claimed(value): return value
                case let .rejected(reasonCode): fatalError(reasonCode)
                case .notMigrated: fatalError("claim unavailable")
                }
            }
            let claim7 = dependentClaim(7)
            let claim8 = dependentClaim(8)
            let targets7 = makeAtomicTargets(layerID: 7, generation: 1)
            let targets8 = makeAtomicTargets(layerID: 8, generation: 2)
            let dependency = dependencyInput(
                binding: binding,
                texture: makeTexture(device, "dependent-reservation"),
                frameEpoch: 74
            )
            let pool = SceneOffscreenTexturePool(factory: { plan in
                plan.graphPlan.key.layerID == 7
                    ? targets7.prepared : targets8.prepared
            })
            let preparation = coordinator.prepareFrame(
                [
                    .init(
                        claim: claim7,
                        targetPlan: .init(
                            token: claim7.token,
                            allocation: .init(graphPlan: .init(
                                key: .init(layerID: 7)
                            ))
                        ),
                        sourceTexture: makeTexture(
                            device, "dependent-provider-source"
                        ),
                        sourceUniforms: .init(),
                        sourcePipeline: .init(),
                        frameInputs: .fixture
                    ),
                    .init(
                        claim: claim8,
                        targetPlan: .init(
                            token: claim8.token,
                            allocation: .init(graphPlan: .init(
                                key: .init(layerID: 8)
                            ))
                        ),
                        sourceTexture: makeTexture(
                            device, "dependent-consumer-source"
                        ),
                        sourceUniforms: .init(),
                        sourcePipeline: .init(),
                        frameInputs: .fixture
                            .replacingDependencyEffect(dependency)
                    ),
                ],
                pool: pool,
                commandBuffer: buffer
            )
            let reason: String
            switch preparation {
            case let .rejected(value): reason = value
            case .ready: reason = "ready"
            }
            results[
                "capturedMainProviderColorFailureRemainsAtomic"
            ] = reason == "graph-preflight-fixture-finalizer-color-"
                + "colorContractUnproven"
                && SceneResolvedMaterialGraphExecutor.prepareTokens == [7]
                && pool.batchCommitCount == 0
                && coordinator.frameRequiresDrop
                && !coordinator.framePreparationComplete
                && coordinator.frameLocalFallbacks.isEmpty
            targets7.commit.releaseAll()
            targets8.commit.releaseAll()
            SceneResolvedMaterialGraphExecutor.failureByToken = [:]
            SceneResolvedMaterialGraphExecutor.preparedByToken = [:]
        }

'''
    marker = "        let payload: [String: Any] = ["
    if source.count(marker) != 1:
        raise AssertionError("payload insertion point is not unique")
    return source.replace(marker, insertion + marker)


class SceneCapturedMainPreflightFallbackTests(unittest.TestCase):
    def test_product_contract_is_typed_bounded_and_compositor_visible(self) -> None:
        coordinator = COORDINATOR.read_text(encoding="utf-8")
        composition = COMPOSITION.read_text(encoding="utf-8")
        validation = EXECUTOR_VALIDATION.read_text(encoding="utf-8")
        self.assertIn("failure.isColorContractVisualRejection", coordinator)
        self.assertIn("case .capturedMainTargetTexture", coordinator)
        self.assertIn("claim.dependencyOwnership == .none", coordinator)
        self.assertIn("externallyConsumedProviderLayerIDs", coordinator)
        self.assertIn(
            '"captured-main-color-contract-unproven"',
            coordinator,
        )
        self.assertIn(
            'reasonCode == "captured-main-color-contract-unproven"',
            composition,
        )
        self.assertIn("failure.phase == .color", validation)
        self.assertIn("failure.code == .colorContractUnproven", validation)
        self.assertNotIn("sampleID", coordinator + composition)

    @unittest.skipUnless(shutil.which("swiftc"), "swiftc is required")
    def test_visual_failure_is_local_but_provider_failure_is_atomic(self) -> None:
        bridge = load_bridge_fixture_module()
        source = augmented_harness(bridge.SUBMISSION_COORDINATOR_FIXTURE)
        with tempfile.TemporaryDirectory(
            prefix="mwx-captured-main-preflight-fallback-"
        ) as directory:
            root = Path(directory)
            harness = root / "Harness.swift"
            binary = root / "captured-main-preflight-fallback"
            harness.write_text(source, encoding="utf-8")
            compilation = subprocess.run(
                [
                    "xcrun",
                    "--sdk",
                    "macosx",
                    "swiftc",
                    "-parse-as-library",
                    *(str(path) for path in bridge.SUBMISSION_SWIFT_SOURCES),
                    str(harness),
                    "-framework",
                    "Metal",
                    "-module-cache-path",
                    str(root / "module-cache"),
                    "-o",
                    str(binary),
                ],
                capture_output=True,
                text=True,
            )
            self.assertEqual(compilation.returncode, 0, compilation.stderr)
            completed = subprocess.run(
                [str(binary)],
                check=True,
                capture_output=True,
                text=True,
            )
            result = json.loads(completed.stdout)
            if not result["metalAvailable"]:
                self.skipTest("Metal device unavailable")
            self.assertTrue(
                result["results"][
                    "capturedMainColorFailurePreservesIndependentFrameWork"
                ],
                result,
            )
            self.assertTrue(
                result["results"][
                    "capturedMainProviderColorFailureRemainsAtomic"
                ],
                result,
            )


if __name__ == "__main__":
    unittest.main()
