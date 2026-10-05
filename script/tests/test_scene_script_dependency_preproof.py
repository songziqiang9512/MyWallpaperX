"""CPU proof regression for script-gated exact optional named dependencies.

Compiles the production proof functions against prepared dependency atoms. It
does not prove the frontend/variant producer, GPU sampling, or media delivery.
"""
import json
from pathlib import Path
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]
SCENE = ROOT / "MyWallpaperX/Core/SteamWorkshopScene"
PROGRAM = SCENE / "Compilation/Material/SceneResolvedMaterialExecutionCapability+ProgramFirstStages.swift"
OWNERSHIP = SCENE / "Compilation/Material/SceneResolvedMaterialExecutionCapability+DependencyOwnership.swift"


def declaration(source: str, signature: str) -> str:
    """Extract a complete production declaration, including its signature."""
    start = source.index(signature)
    body = source.index("{", start)
    depth = 0
    for index in range(body, len(source)):
        if source[index] == "{":
            depth += 1
        elif source[index] == "}":
            depth -= 1
            if depth == 0:
                return source[start:index + 1]
    raise AssertionError(f"unterminated declaration: {signature}")


SUPPORT = r'''
import Foundation
struct SceneDependencyRenderPlan {}
struct PreparedGraph { let layerID: Int; let renderTargets: [Int] }
struct SceneGraphAdmissionProduct {
    let graph: PreparedGraph
    let dependencies: SceneResolvedMaterialExecutionCapabilityCatalog.ResolvedExternalDependencyAnalysis
}
enum SceneResolvedMaterialExecutionCapabilityCatalog {
    typealias MaterialKey = Int
    enum StageCapability {
        case resolved(product: SceneGraphAdmissionProduct, materials: [Int: Bool],
            activation: SceneResolvedMaterialStageActivationPolicy?)
    }
    // These adapters expose fixture metadata. They do not produce dependency
    // proofs or normalize candidate/provider/slot identities.
    static func resolvedExternalDependencies(in stage: StageCapability) -> ResolvedExternalDependencyAnalysis {
        switch stage { case let .resolved(product, _, _): return product.dependencies }
    }
    static func visualFailureExternalDependencies(in stage: StageCapability,
        binding: SceneDependencyRenderPlan.Binding) -> [BindingDependency] { [] }
    static func aggregateStageDependencies(_ stages: [StageCapability],
        aggregate: SceneDependencyRenderPlan.MultiProviderAggregate) -> [BindingDependency]? {
        fatalError("aggregate finalization is outside this fixture")
    }
    static func aggregateDependenciesMatch(_ dependencies: [BindingDependency],
        aggregate: SceneDependencyRenderPlan.MultiProviderAggregate) -> Bool {
        fatalError("aggregate finalization is outside this fixture")
    }
}
'''

CHECKS = r'''
@main
enum Checks {
    static func main() throws {
        typealias C = SceneResolvedMaterialExecutionCapabilityCatalog
        typealias B = SceneDependencyRenderPlan.Binding
        typealias D = C.ResolvedExternalDependency
        let consumer = 81, provider = 879
        let first = SceneEffectPassSlot(effectID: "961", passIndex: 0, slotIndex: 1)
        let second = SceneEffectPassSlot(effectID: "970", passIndex: 0, slotIndex: 1)
        let target = SceneDynamicTarget.effectVisibility(layerID: consumer, effectIndex: 1)
        let activation = SceneResolvedMaterialStageActivationPolicy(effectVisibilityTarget: target,
            requiresPointerPositionProvider: false, scalarMinimum: nil)
        func binding(_ slot: SceneEffectPassSlot, consumerID: Int = consumer,
            providerID: Int = provider, blend: Int = 0, kind: B.Kind = .resolvedMaterial,
            forward: Bool = false, program: Bool = true, slots: [SceneEffectPassSlot]? = nil) -> B {
            .init(consumerLayerID: consumerID, providerLayerID: providerID, slot: slot,
                referenceSlots: slots, blendMode: blend, kind: kind,
                requiresForwardCapture: forward, requiresResolvedMaterialProgram: program)
        }
        func dependency(_ slot: SceneEffectPassSlot, key: Int, consumerID: Int = consumer,
            providerID: Int = provider, origin: D.Origin) -> D {
            .init(materialKey: key, consumerLayerID: consumerID, providerLayerID: providerID,
                slot: slot, origin: origin)
        }
        func stage(_ dependencies: C.ResolvedExternalDependencyAnalysis,
            layerID: Int = consumer, fbo: Bool = false) -> C.StageCapability {
            .resolved(product: .init(graph: .init(layerID: layerID,
                renderTargets: fbo ? [1] : []), dependencies: dependencies),
                materials: [1: true], activation: activation)
        }
        func preproof(_ stage: C.StageCapability,
            ownership: SceneResolvedMaterialDependencyOwnership,
            potential: [B] = []) -> Bool {
            __PREPROOF_CALL__
        }
        let base = binding(first), optional = binding(second)
        let direct = dependency(first, key: 1, origin: .terminalNamed)
        let mixed = dependency(second, key: 2, origin: .exactMixedOptionalFallback)
        let baseStage = stage(.exact([direct])), mixedStage = stage(.exact([mixed]))
        var result: [String: Bool] = [:]
        result["exactMixedScriptStageStaysResolved"] = preproof(mixedStage,
            ownership: .externalPrimary(base), potential: [optional])
        result["terminalNamedExistingOwnerStaysResolved"] = preproof(baseStage,
            ownership: .externalPrimary(base))
        result["allOptionalStageStaysResolved"] = preproof(mixedStage,
            ownership: .none, potential: [optional])
        let finalized = C.finalizeDependencyOwnership(.externalPrimary(base),
            potentialBindings: [optional], layerID: consumer, stages: [baseStage, mixedStage])
        let expanded = binding(first, slots: [first, second])
        result["finalizerPreservesExactAuthoredSlotOrder"] = finalized == .externalPrimary(expanded)
        result["finalizerPromotesAllOptionalOwner"] = C.finalizeDependencyOwnership(.none,
            potentialBindings: [optional], layerID: consumer, stages: [mixedStage])
                == .externalPrimary(optional)
        let legacyBase = binding(first, kind: .imageLayerBlend, forward: true, program: false)
        let programOptional = binding(second, kind: .imageLayerBlend, forward: true)
        result["legacyDirectBaseAcceptsStricterProgramSibling"] = preproof(mixedStage,
            ownership: .externalPrimary(legacyBase), potential: [programOptional])
        result["expandedOwnerKeepsStricterProgramRequirement"] = C.finalizeDependencyOwnership(
            .externalPrimary(legacyBase), potentialBindings: [programOptional], layerID: consumer,
            stages: [baseStage, mixedStage]) == .externalPrimary(
                binding(first, kind: .imageLayerBlend, forward: true, slots: [first, second]))
        result["directOnlyOwnerRetainsAuthoredRequirement"] = C.finalizeDependencyOwnership(
            .externalPrimary(legacyBase), potentialBindings: [programOptional], layerID: consumer,
            stages: [baseStage]) == .externalPrimary(legacyBase)
        result["finalizerRejectsMissingDirectSlot"] = C.finalizeDependencyOwnership(.externalPrimary(base),
            potentialBindings: [optional], layerID: consumer, stages: [mixedStage]) == nil
        result["finalizerRejectsDuplicateOptionalSlot"] = C.finalizeDependencyOwnership(.externalPrimary(base),
            potentialBindings: [optional], layerID: consumer,
            stages: [baseStage, mixedStage, mixedStage]) == nil
        result["finalizerKeepsReverseAuthoredOrder"] = C.finalizeDependencyOwnership(.externalPrimary(base),
            potentialBindings: [optional], layerID: consumer, stages: [mixedStage, baseStage])
                == .externalPrimary(binding(first, slots: [second, first]))
        let bad: [(String, [B])] = [
            ("missingPotential", []),
            ("wrongConsumer", [binding(second, consumerID: consumer + 1)]),
            ("wrongProvider", [binding(second, providerID: provider + 1)]),
            ("wrongSlot", [binding(first)]),
            ("duplicatePotential", [optional, optional]),
            ("multipleReferenceSlots", [binding(second, slots: [first, second])]),
            ("blendMismatch", [binding(second, blend: 1)]),
            ("kindMismatch", [binding(second, kind: .solidLayer)]),
            ("captureMismatch", [binding(second, forward: true)]),
            ("unprovenProgram", [binding(second, program: false)]),
        ]
        for (name, potential) in bad {
            result["rejects_" + name] = !preproof(mixedStage,
                ownership: .externalPrimary(base), potential: potential)
            result["finalizerRejects_" + name] = C.finalizeDependencyOwnership(.externalPrimary(base),
                potentialBindings: potential, layerID: consumer, stages: [baseStage, mixedStage]) == nil
        }
        result["rejectsWrongGraphConsumer"] = !preproof(stage(.exact([mixed]), layerID: consumer + 1),
            ownership: .externalPrimary(base), potential: [optional])
        result["rejectsWrongDependencyConsumer"] = !preproof(stage(.exact([
            dependency(second, key: 2, consumerID: consumer + 1, origin: .exactMixedOptionalFallback)])),
            ownership: .externalPrimary(base), potential: [optional])
        result["rejectsWrongBaseConsumer"] = !preproof(mixedStage,
            ownership: .externalPrimary(binding(first, consumerID: consumer + 1)), potential: [optional])
        result["rejectsExternalFramebuffer"] = !preproof(stage(.exact([mixed]), fbo: true),
            ownership: .externalPrimary(base), potential: [optional])
        result["rejectsPromotedFramebuffer"] = !preproof(stage(.exact([mixed]), fbo: true),
            ownership: .none, potential: [optional])
        result["rejectsUnprovenDependency"] = !preproof(stage(.invalid),
            ownership: .externalPrimary(base), potential: [optional])
        result["noneRejectsTerminalNamed"] = !preproof(baseStage, ownership: .none, potential: [base])
        result["noneRejectsMixedProviders"] = !preproof(stage(.exact([mixed,
            dependency(first, key: 3, providerID: provider + 1, origin: .exactMixedOptionalFallback)])),
            ownership: .none, potential: [optional, binding(first, providerID: provider + 1)])
        result["dependencyFreeStageStaysResolved"] = preproof(stage(.none), ownership: .none)
        let active = SceneDynamicSnapshotResolver().resolve(frameIndex: 1, generation: 1,
            definitions: [.init(target: target, valueType: .bool, authoredValue: .bool(false))],
            sceneScriptValues: [target: .bool(true)]).snapshot
        let inactive = SceneDynamicSnapshotResolver().resolve(frameIndex: 2, generation: 1,
            definitions: [.init(target: target, valueType: .bool, authoredValue: .bool(false))],
            sceneScriptValues: [target: .bool(false)]).snapshot
        result["realActivationConsumesScriptTrue"] = preproof(mixedStage,
            ownership: .externalPrimary(base), potential: [optional])
            && activation.evaluate(dynamicValues: active, pointerIsInside: true) == .active
        result["realActivationConsumesScriptFalse"] = activation.evaluate(dynamicValues: inactive,
            pointerIsInside: true) == .inactive(reasonCode: "effect-activation-visibility-disabled")
        print(String(data: try JSONSerialization.data(withJSONObject: result, options: .sortedKeys),
            encoding: .utf8)!)
    }
}
'''


def compile_proof(program_source: str):
    ownership_source = OWNERSHIP.read_text()
    plan_source = (SCENE / "Rendering/Dependencies/SceneDependencyRenderPlan.swift").read_text()
    aggregate_source = (SCENE / "Rendering/Dependencies/SceneDependencyRenderPlan+Aggregate.swift").read_text()
    support = SUPPORT + "\nextension SceneDependencyRenderPlan {\n" + declaration(
        plan_source, "nonisolated struct Binding:"
    ) + "\n" + declaration(aggregate_source, "nonisolated struct MultiProviderAggregate:").replace(
        declaration(aggregate_source, "        func admits("), ""
    ) + "\n}\n"
    support += declaration(ownership_source, "nonisolated enum SceneResolvedMaterialDependencyOwnership:")
    support += "\nextension SceneResolvedMaterialExecutionCapabilityCatalog {\n"
    for signature in ["    struct BindingDependency:", "    struct ResolvedExternalDependency:",
                      "    enum ResolvedExternalDependencyAnalysis"]:
        support += declaration(ownership_source, signature) + "\n"
    for name in ["dependencyPreproofMayStayResolved", "finalizeDependencyOwnership",
                 "expandedPotentialBinding", "exactPotentialBinding", "compatible",
                 "orderedStageDependencies", "matches"]:
        marker = f"    private static func {name}("
        position = 0
        while marker in program_source[position:]:
            position = program_source.index(marker, position)
            extracted = declaration(program_source[position:], marker)
            support += extracted.replace("private static func", "static func", 1) + "\n"
            position += len(extracted)
    support += "\n}\n"
    signature = declaration(program_source, "    private static func dependencyPreproofMayStayResolved(")
    call = "C.dependencyPreproofMayStayResolved(stage: stage, ownership: ownership"
    if "potentialBindings:" in signature.split("-> Bool", 1)[0]:
        call += ", potentialBindings: potential, layerID: consumer"
    harness = CHECKS.replace("__PREPROOF_CALL__", call + ")")
    with tempfile.TemporaryDirectory(prefix="mwx-script-dependency-proof-") as directory:
        root = Path(directory)
        source = root / "Proof.swift"
        source.write_text(support + harness)
        binary = root / "proof"
        compiled = subprocess.run(["xcrun", "swiftc", "-parse-as-library", str(source),
            str(SCENE / "Resources/Textures/SceneNamedTextureReference.swift"),
            str(SCENE / "Systems/Properties/SceneDynamicSnapshot.swift"),
            str(SCENE / "Rendering/Graph/SceneResolvedMaterialStageActivation.swift"),
            "-module-cache-path", str(root / "modules"), "-o", str(binary)],
            capture_output=True, text=True)
        if compiled.returncode:
            return compiled, None
        return compiled, subprocess.run([str(binary)], capture_output=True, text=True)


class SceneScriptDependencyPreproofTests(unittest.TestCase):
    source_override = None

    def test_exact_potential_dependencies_and_activation(self):
        compiled, ran = compile_proof(self.source_override or PROGRAM.read_text())
        self.assertEqual(compiled.returncode, 0, compiled.stderr)
        self.assertIsNotNone(ran)
        self.assertEqual(ran.returncode, 0, ran.stderr)
        results = json.loads(ran.stdout.strip())
        print(json.dumps(results, sort_keys=True), flush=True)
        for name, passed in results.items():
            with self.subTest(name=name):
                self.assertTrue(passed, name)


if __name__ == "__main__":
    unittest.main()
