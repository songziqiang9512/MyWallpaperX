"""One runtime demand memo retains local deletion fallback and healthy demand."""
from pathlib import Path
import json
import shutil
import subprocess
import tempfile
import unittest

from . import test_scene_dependency_graph_output_runtime as support


# Reuse the existing runtime scaffold. Only the plan projection is instrumented;
# the production owner and its memo are compiled unchanged, without telemetry.
SCAFFOLD = support.GEOMETRY_HARNESS_SOURCE.split("@main", 1)[0].replace(
    "extension SceneDependencyRenderPlan {",
    "extension SceneDependencyRenderPlan {\n    static var demandProjectionCount = 0;", 1
).replace(
    "        var reachable = visibleRootLayerIDs.intersection(",
    "        Self.demandProjectionCount += 1\n"
    "        var reachable = visibleRootLayerIDs.intersection(", 1
)

HARNESS = r'''
@main enum Harness {
    static func main() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            print("{\"metalUnavailable\":true}"); return
        }
        func binding(_ consumer: Int, _ provider: Int) -> SceneDependencyRenderPlan.Binding {
            .init(consumerLayerID: consumer, providerLayerID: provider,
                slot: .init(effectID: "\(consumer)-\(provider)", passIndex: 0, slotIndex: 1),
                blendMode: 0, kind: .imageLayerBlend, requiresResolvedMaterialProgram: true)
        }
        let vector = [binding(22, 11), binding(22, 12)]
        let aggregate = SceneDependencyRenderPlan.MultiProviderAggregate(
            consumerLayerID: 22, bindings: vector)
        let live: Set<Int> = [11, 12, 22, 44, 55, 66, 77, 40]
        let available: Set<Int> = [11, 22, 44, 55, 66, 40]
        let visible: Set<Int> = [44, 55, 40]
        let runtime = SceneDependencyFrameRuntime(descriptor: .init(
            layers: live.map { .init(id: $0, contentKind: "image", utilityLayer: nil,
                alpha: 1, colorRGB: [1, 1, 1]) },
            bindings: [44: binding(44, 22), 55: binding(55, 11)],
            graphOutputProviderLayerIDs: [11, 22, 66], aggregates: [22: aggregate],
            staticModelConsumerProviders: [77: 66]),
            visibleLayerIDs: visible, executableUtilityConsumerLayerIDs: [], device: device)
        var rows: [String: [String: Any]] = [:]
        func query(_ label: String, roots: Set<Int>, liveIDs: Set<Int>, graph: Set<Int>,
                   models: Set<Int> = [], repetitions: Int = 1) {
            var demand: SceneDependencyFrameRuntime.ResolvedMaterialFrameDemand!
            for _ in 0..<repetitions {
                demand = runtime.resolvedMaterialFrameDemand(visibleRootLayerIDs: roots,
                    availableExecutionLayerIDs: graph, liveLayerIDs: liveIDs,
                    activeStaticModelConsumerLayerIDs: models)
            }
            rows[label] = ["active": demand.activeExecutionLayerIDs.sorted(),
                "projections": SceneDependencyRenderPlan.demandProjectionCount]
        }
        query("initial", roots: visible, liveIDs: live, graph: available)
        query("stable", roots: visible, liveIDs: live, graph: available, repetitions: 64)
        let deletedStatic = live.subtracting([12])
        query("staticDeleted", roots: visible, liveIDs: deletedStatic, graph: available)
        query("deletedStable", roots: visible, liveIDs: deletedStatic, graph: available, repetitions: 64)
        query("consumerHidden", roots: [55, 40], liveIDs: deletedStatic, graph: available)
        query("hiddenStable", roots: [55, 40], liveIDs: deletedStatic, graph: available, repetitions: 64)
        query("noDependentRoot", roots: [40], liveIDs: deletedStatic, graph: available)
        query("staticRestored", roots: visible, liveIDs: live, graph: available)
        query("graphUnavailable", roots: visible, liveIDs: live, graph: available.subtracting([11]))
        query("graphRestored", roots: visible, liveIDs: live, graph: available)
        query("modelUnprepared", roots: [77, 40], liveIDs: live, graph: available)
        query("modelPrepared", roots: [77, 40], liveIDs: live, graph: available, models: [77])
        query("modelStable", roots: [77, 40], liveIDs: live, graph: available, models: [77], repetitions: 64)
        query("modelHidden", roots: [40], liveIDs: live, graph: available, models: [77])
        query("modelProviderDeleted", roots: [77, 40], liveIDs: live.subtracting([66]),
              graph: available, models: [77])
        query("modelGraphUnavailable", roots: [77, 40], liveIDs: live,
              graph: available.subtracting([66]), models: [77])
        query("modelGraphRestored", roots: [77, 40], liveIDs: live, graph: available, models: [77])
        print(String(decoding: try JSONSerialization.data(withJSONObject: rows, options: [.sortedKeys]), as: UTF8.self))
    }
}
'''


class SceneDependencyFrameDemandTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if not shutil.which("swiftc"):
            raise unittest.SkipTest("swiftc required")
        directory = tempfile.TemporaryDirectory(prefix="mwx-dependency-frame-demand-")
        cls.addClassCleanup(directory.cleanup)
        root = Path(directory.name)
        source, binary = root / "Harness.swift", root / "demand"
        source.write_text(SCAFFOLD + HARNESS)
        compilation = subprocess.run([
            "xcrun", "--sdk", "macosx", "swiftc", str(support.PLAN_SOURCE), str(support.RUNTIME_SOURCE),
            str(support.AGGREGATE_VALIDATION_RUNTIME_SOURCE), str(support.GEOMETRY_RUNTIME_SOURCE),
            str(support.EFFECT_INPUT_RESOLUTION_RUNTIME_SOURCE), str(support.STATIC_MODEL_RUNTIME_SOURCE),
            str(support.GEOMETRY_PRODUCT_SOURCE),
            str(support.REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Diagnostics/ScenePerformanceCounterHub.swift"),
            str(support.REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Diagnostics/SceneGPUCensus.swift"),
            str(source), "-framework", "Metal", "-o", str(binary)
        ], capture_output=True, text=True, timeout=120)
        if compilation.returncode:
            raise AssertionError(compilation.stdout + compilation.stderr)
        result = subprocess.run([str(binary)], capture_output=True, text=True, timeout=30)
        if result.returncode:
            raise AssertionError(result.stdout + result.stderr)
        cls.rows = json.loads(result.stdout)
        if cls.rows.get("metalUnavailable"):
            raise unittest.SkipTest("Metal unavailable")

    def assert_row(self, name, active, projections):
        self.assertEqual(self.rows[name], {"active": active, "projections": projections})

    def test_stable_and_deleted_provider_frames_reuse_one_memo(self):
        for name in ("initial", "stable"):
            self.assert_row(name, [11, 22, 40, 44, 55], 1)
        for name in ("staticDeleted", "deletedStable"):
            self.assert_row(name, [11, 22, 40, 44, 55], 2)

    def test_missing_static_provider_keeps_consumer_and_healthy_dependency_demand(self):
        # A missing input is resolved by its operation. Consumer22, its
        # downstream44 and the healthy A-only55 must remain executable.
        self.assert_row("staticDeleted", [11, 22, 40, 44, 55], 2)
        self.assert_row("staticRestored", [11, 22, 40, 44, 55], 5)

    def test_visibility_changes_remove_orphan_demand(self):
        for name in ("consumerHidden", "hiddenStable"):
            self.assert_row(name, [11, 40, 55], 3)
        self.assert_row("noDependentRoot", [40], 4)

    def test_available_graph_changes_invalidate_and_restore(self):
        self.assert_row("graphUnavailable", [22, 40, 44, 55], 6)
        self.assert_row("graphRestored", [11, 22, 40, 44, 55], 7)

    def test_only_prepared_visible_models_activate_their_live_provider(self):
        self.assert_row("modelUnprepared", [40], 8)
        for name in ("modelPrepared", "modelStable"):
            self.assert_row(name, [40, 66], 9)
        self.assert_row("modelHidden", [40], 10)
        self.assert_row("modelProviderDeleted", [40], 11)
        self.assert_row("modelGraphUnavailable", [40], 12)
        self.assert_row("modelGraphRestored", [40, 66], 13)


if __name__ == "__main__":
    unittest.main()
