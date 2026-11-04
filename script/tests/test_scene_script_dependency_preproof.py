"""CPU projection of actual named reads onto prepared source carriers.

The dependency records are typed fixture inputs. Program/variant production,
publication identity and GPU sampling remain covered by their real owner gates.
"""
import json
from pathlib import Path
import subprocess
import tempfile
import unittest

from script.tests.scene_dependency_binding_test_support import (
    SCENE_DEPENDENCY_AGGREGATE_SUPPORT,
    SCENE_DEPENDENCY_BINDING_SUPPORT,
)

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
enum SceneResolvedMaterialExecutionCapabilityCatalog {
    struct Rejection: Error { let code: String }
    struct CompiledStages {
        struct Stage { let dependencies: ResolvedExternalDependencyAnalysis }
    }
    // The real projection consumes the Program producer's typed records.
    // This passive seam does not reproduce shader or dependency analysis.
    static func resolvedExternalDependencies(in stage: CompiledStages.Stage) -> ResolvedExternalDependencyAnalysis {
        stage.dependencies
    }
    static func rejection(_ code: String) -> Rejection { .init(code: code) }
}
'''

CHECKS = r'''
@main
private enum Checks {
    static func main() throws {
        typealias C = SceneResolvedMaterialExecutionCapabilityCatalog
        typealias B = SceneDependencyRenderPlan.Binding
        typealias D = C.ResolvedExternalDependency
        let consumer = 81, provider = 879
        let first = SceneEffectPassSlot(effectID: "z-first", passIndex: 1, slotIndex: 2)
        let second = SceneEffectPassSlot(effectID: "a-next", passIndex: 0, slotIndex: 5)
        func binding(_ slot: SceneEffectPassSlot, consumerID: Int = consumer,
            providerID: Int = provider, blend: Int = 0, kind: B.Kind = .imageLayerBlend,
            forward: Bool = false, program: Bool = true, slots: [SceneEffectPassSlot]? = nil) -> B {
            .init(consumerLayerID: consumerID, providerLayerID: providerID, slot: slot,
                referenceSlots: slots, blendMode: blend, kind: kind,
                requiresForwardCapture: forward, requiresResolvedMaterialProgram: program)
        }
        func dependency(_ slot: SceneEffectPassSlot, providerID: Int = provider) -> D {
            .init(consumerLayerID: consumer, providerLayerID: providerID, slot: slot)
        }
        func project(_ dependencies: C.ResolvedExternalDependencyAnalysis,
            ownership: SceneResolvedMaterialDependencyOwnership = .none,
            sources: [B] = []) -> (bindings: [B], internalReferenceCount: Int)? {
            switch C.preparedNamedInputs(stage: .init(dependencies: dependencies),
                ownership: ownership, candidates: sources, layerID: consumer) {
            case let .success(value): return value
            case .failure: return nil
            }
        }
        let base = binding(first), optional = binding(second)
        let direct = dependency(first), mixed = dependency(second)
        let both = project(.exact([direct, mixed]), ownership: .externalPrimary(base), sources: [optional])
        var result: [String: Bool] = [:]
        result["preparedReadsConserveBothSameProviderSlots"] = both?.bindings == [base, optional]
        result["optionalOnlyUsesItsActualPreparedSource"] = project(.exact([mixed]), sources: [optional])?.bindings == [optional]
        result["sourceSupersetDoesNotInventDemand"] = project(.exact([direct]), sources: [base, optional])?.bindings == [base]
        result["authoredReadOrderIsNotLexicalEffectOrder"] = project(.exact([mixed, direct]),
            sources: [base, optional])?.bindings == [optional, base]
        let other = binding(second, providerID: 880)
        result["differentProvidersUseOneOrderedVector"] = project(.exact([direct,
            dependency(second, providerID: 880)]), sources: [base, other])?.bindings == [base, other]
        let legacy = binding(first, program: false)
        let projected = binding(first)
        result["legacyCarrierProjectsAProgramRequiredRead"] = project(.exact([direct]),
            ownership: .externalPrimary(legacy))?.bindings == [projected]
        let legacyVector = binding(first, slots: [first, second])
        result["legacySourceProjectsOnlyTheActualReadSlot"] = project(.exact([mixed]),
            ownership: .externalPrimary(legacyVector))?.bindings == [optional]
        result["unreadCandidateHasNoFinalDemand"] = project(.none, sources: [optional])?.bindings == []
        result["emptyProgramReadVectorHasNoFinalDemand"] = project(.exact([]), sources: [optional])?.bindings == []
        let own = project(.exact([dependency(first, providerID: consumer)]))
        result["selfReadRequiresNoExternalCarrier"] = own?.bindings == [] && own?.internalReferenceCount == 1
        result["invalidProducerAnalysisIsRejected"] = project(.invalid, sources: [base]) == nil
        result["missingActualSourceIsRejectedLocally"] = project(.exact([mixed]), sources: [base]) == nil
        for (name, source) in [
            ("wrongSourceConsumer", binding(second, consumerID: consumer + 1)),
            ("wrongSourceProvider", binding(second, providerID: provider + 1)),
            ("wrongSourceSlot", base),
        ] {
            result[name] = project(.exact([mixed]), sources: [source]) == nil
        }
        let target = SceneDynamicTarget.effectVisibility(layerID: consumer, effectIndex: 1)
        let activation = SceneResolvedMaterialStageActivationPolicy(effectVisibilityTarget: target,
            requiresPointerPositionProvider: false, scalarMinimum: nil)
        let active = SceneDynamicSnapshotResolver().resolve(frameIndex: 1, generation: 1,
            definitions: [.init(target: target, valueType: .bool, authoredValue: .bool(false))],
            sceneScriptValues: [target: .bool(true)]).snapshot
        let inactive = SceneDynamicSnapshotResolver().resolve(frameIndex: 2, generation: 1,
            definitions: [.init(target: target, valueType: .bool, authoredValue: .bool(false))],
            sceneScriptValues: [target: .bool(false)]).snapshot
        result["realActivationConsumesScriptTrue"] = both?.bindings == [base, optional]
            && activation.evaluate(dynamicValues: active, pointerIsInside: true) == .active
        result["realActivationConsumesScriptFalse"] = activation.evaluate(dynamicValues: inactive,
            pointerIsInside: true) == .inactive(reasonCode: "effect-activation-visibility-disabled")
        print(String(decoding: try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys]), as: UTF8.self))
    }
}
'''


def compile_proof(program_source: str):
    ownership_source = OWNERSHIP.read_text()
    support = SUPPORT + SCENE_DEPENDENCY_BINDING_SUPPORT + SCENE_DEPENDENCY_AGGREGATE_SUPPORT
    support += declaration(ownership_source, "nonisolated enum SceneResolvedMaterialDependencyOwnership:")
    support += "\nextension SceneResolvedMaterialExecutionCapabilityCatalog {\n"
    for signature in ("    struct ResolvedExternalDependency:", "    enum ResolvedExternalDependencyAnalysis"):
        support += declaration(ownership_source, signature) + "\n"
    support += declaration(program_source, "    private static func preparedNamedInputs(").replace(
        "private static func", "static func", 1)
    support += "\n}\n"
    with tempfile.TemporaryDirectory(prefix="mwx-script-dependency-proof-") as directory:
        root = Path(directory)
        source = root / "Proof.swift"
        source.write_text(support + CHECKS)
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
