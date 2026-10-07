#!/usr/bin/env python3
"""Color providers preserve authored visibility without blocking legal peers."""

from __future__ import annotations

import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

try:
    from . import test_scene_user_properties as properties
    from . import test_scene_property_binding_program as bindings
    from . import test_scene_property_live_update_state as live
except ImportError:
    import test_scene_user_properties as properties
    import test_scene_property_binding_program as bindings
    import test_scene_property_live_update_state as live


ROOT = Path(__file__).resolve().parents[2]
SWIFT_SOURCES = list(dict.fromkeys(
    properties.SWIFT_SOURCES + bindings.SWIFT_SOURCES + live.SWIFT_SOURCES
))

HARNESS = r'''
import Foundation

@main enum Harness {
    struct Fixture {
        let root: [String: Any]
        let catalog: SceneUserPropertyCatalog
        let resolution: SceneUserPropertyResolution
        let compilation: ScenePropertyBindingCompilation
        let visible: SceneDynamicTarget
        let color: SceneDynamicTarget
        let material: SceneDynamicTarget
        let alpha: SceneDynamicTarget
    }

    static func property(_ key: String, _ kind: SceneUserPropertyKind,
        _ value: SceneUserPropertyValue?) -> SceneUserPropertyDefinition {
        .init(key: key, title: key, kind: kind, runtimeType: kind.rawValue,
            order: 0, index: nil, minimumValue: kind == .slider ? 0 : nil,
            maximumValue: kind == .slider ? 1 : nil, stepValue: nil,
            allowsFractionalValues: true, fractionalPrecision: nil,
            displayCondition: nil, defaultValue: value, options: [])
    }

    static func fixture(seed: Any = false, script: Bool = false, id: Int = 10,
        kind: SceneUserPropertyKind = .color, definitionCount: Int = 1,
        conditional: Bool = false, effect: Bool = false,
        defaultValue: SceneUserPropertyValue? = .string("0.4 0.8 0.2")) -> Fixture {
        var wrapper: [String: Any] = ["user": conditional
            ? ["name": "palette", "condition": "0.4 0.8 0.2"] : "palette", "value": seed]
        if script { wrapper["script"] = "export function update(value) {}" }
        var object: [String: Any] = ["id": id,
            "color": ["user": "palette", "value": "0.1 0.2 0.3"],
            "alpha": ["user": "opacity", "value": 0.5]]
        if effect {
            object["effects"] = [["file": "effects/unseen.json", "visible": wrapper]]
        } else { object["visible"] = wrapper }
        let root: [String: Any] = ["objects": [object]]
        let definitions = Array(repeating: property("palette", kind, defaultValue), count: definitionCount)
            + [property("opacity", .slider, .number(0.5))]
        let catalog = SceneUserPropertyCatalog(definitions: definitions)
        let resolution = SceneUserPropertyDocumentResolver().resolve(root: root, catalog: catalog,
            overrides: ["palette": .string("0.8 0.4 0.6")])
        // A prepared material declaration is an ordinary compiler input. Its
        // shader proof has a separate gate; no proof or conversion is mocked.
        let material = SceneDynamicTarget.materialConstant(layerID: id, passIndex: 0,
            name: "unseen-surface", materialPath: "materials/unseen.json")
        let materialBinding = SceneUserPropertyBinding(reference: .init(key: "palette", condition: nil),
            fallbackValue: .string("0.1 0.2 0.3"),
            path: .init(components: [.key("materials"), .key("materials/unseen.json"),
                .key("passes"), .index(0), .key("constantshadervalues"), .key("unseen-surface")]),
            target: .materialShaderValue(layerID: id, passIndex: 0, name: "unseen-surface",
                materialPath: "materials/unseen.json"))
        let report = resolution.bindingReport
        let compilation = ScenePropertyBindingCompiler().compile(report: .init(
            bindings: report.bindings + [materialBinding], diagnostics: report.diagnostics), catalog: catalog)
        return .init(root: root, catalog: catalog, resolution: resolution, compilation: compilation,
            visible: effect ? .effectVisibility(layerID: id, effectIndex: 0) : .layer(layerID: id, field: .visibility),
            color: .layer(layerID: id, field: .color), material: material,
            alpha: .layer(layerID: id, field: .alpha))
    }

    static func visibilityValue(_ resolution: SceneUserPropertyResolution) -> SceneUserPropertyValue? {
        let object = (resolution.root["objects"] as! [[String: Any]])[0]
        return SceneUserPropertyValue.parse((object["visible"] as? [String: Any])?["value"])
    }

    static func ignored(_ fixture: Fixture) -> [ScenePropertyBindingDiagnostic] {
        fixture.compilation.diagnostics.filter { $0.code == .ignoredIncompatibleVisibility }
    }

    static func startupChecks() -> [String: Bool] {
        var checks: [String: Bool] = [:]
        for seed in [false, true] {
            for script in [false, true] {
                let f = fixture(seed: seed, script: script)
                let object = (f.resolution.root["objects"] as! [[String: Any]])[0]
                let color = object["color"] as! [String: Any]
                let label = "\(seed)_\(script)"
                checks["preservedBool_\(label)"] = visibilityValue(f.resolution) == .bool(seed)
                checks["sameKeyColorStillResolved_\(label)"] = color["value"] as? String == "0.8 0.4 0.6"
                checks["originalBindingFallbackRetained_\(label)"] = f.resolution.bindingReport.bindings
                    .first(where: { $0.target == .layerVisibility(layerID: 10) })?.fallbackValue == .bool(seed)
                let ir = SceneScriptBindingIRParser.parse(document: f.root)
                checks["scriptAttachmentAndFallbackRetained_\(label)"] = script
                    ? ir.bindings.count == 1 && ir.bindings.first?.authoredValue?.boolValue == seed
                        && (object["visible"] as? [String: Any])?["script"] as? String != nil
                    : ir.bindings.isEmpty
                let effectiveOnly = SceneUserPropertyDocumentResolver().resolve(root: f.root,
                    effectiveValues: ["palette": .string("0.8 0.4 0.6")])
                checks["effectiveOnlyDoesNotInferColorKind_\(label)"] = visibilityValue(effectiveOnly) == .string("0.8 0.4 0.6")
            }
        }
        for raw in ["0 0 0", "1 1 1"] {
            let f = fixture(seed: false)
            let resolved = SceneUserPropertyDocumentResolver().resolve(root: f.root, catalog: f.catalog,
                overrides: ["palette": .string(raw)])
            checks["blackWhiteDoNotBecomeBool_\(raw)"] = visibilityValue(resolved) == .bool(false)
        }
        return checks
    }

    static func compilerChecks() throws -> [String: Bool] {
        var checks: [String: Bool] = [:]
        for seed in [false, true] {
            for script in [false, true] {
                let f = fixture(seed: seed, script: script), p = f.compilation.program
                let label = "\(seed)_\(script)"
                let diagnostics = ignored(f)
                checks["ignoreHasExplicitBindingDiagnostic_\(label)"] = diagnostics.count == 1
                    && diagnostics.first?.stage == .compile && diagnostics.first?.propertyKey == "palette"
                    && diagnostics.first?.path?.components == [.key("objects"), .index(0), .key("visible")]
                    && f.compilation.diagnostics.count == 1
                checks["onlyLegalPeersOwnValues_\(label)"] = Set(p.instructions.map(\.target)) == [f.color, f.material, f.alpha]
                    && p.instructions.filter { $0.propertyKey == "palette" }.allSatisfy { $0.valueType == .vector3 }
                    && !p.definitions.contains { $0.target == f.visible }
                    && p.rebuildRequiredPropertyKeys.isEmpty
                let data = try JSONEncoder().encode(p)
                checks["programRoundTripKeepsLocalIgnore_\(label)"] = try JSONDecoder().decode(ScenePropertyBindingProgram.self, from: data) == p
            }
        }
        let boundary: [(String, Fixture)] = [
            ("stringFallback", fixture(seed: "false")), ("numberFallback", fixture(seed: 0)),
            ("nullFallback", fixture(seed: NSNull())), ("negativeID", fixture(id: -1)),
            ("slider", fixture(kind: .slider, defaultValue: .number(0.5))),
            ("missingDefinition", fixture(definitionCount: 0)),
            ("duplicateDefinition", fixture(definitionCount: 2)),
            ("conditionalColor", fixture(conditional: true)), ("effectVisibility", fixture(effect: true)),
        ]
        for (name, f) in boundary {
            checks["boundaryDoesNotGainIgnore_\(name)"] = ignored(f).isEmpty
                && f.compilation.program.rebuildRequiredPropertyKeys.contains("palette")
        }
        for (name, value) in [("missingDefault", Optional<SceneUserPropertyValue>.none),
                              ("malformedDefault", .some(.string("bad color")))] {
            let f = fixture(defaultValue: value)
            checks["ignoreCannotHideBadPeer_\(name)"] = ignored(f).count == 1
                && f.compilation.program.rebuildRequiredPropertyKeys.contains("palette")
                && !f.compilation.program.instructions.contains { $0.propertyKey == "palette" }
        }
        let zero = fixture(id: 0)
        checks["zeroLayerIDIsLegal"] = ignored(zero).count == 1 && zero.compilation.program.rebuildRequiredPropertyKeys.isEmpty
        let bool = fixture(seed: false, kind: .bool, defaultValue: .bool(true))
        checks["realBoolWriterNotRetired"] = ignored(bool).isEmpty
            && bool.compilation.program.instructions.contains { $0.target == bool.visible && $0.valueType == .bool }
        let conditional = fixture(seed: false, conditional: true)
        checks["conditionalStartupRetainsExistingMatchSemantics"] = visibilityValue(conditional.resolution) == .bool(false)
        return checks
    }

    static func sameState(_ first: ScenePropertyLiveUpdateState, _ second: ScenePropertyLiveUpdateState) -> Bool {
        first.effectiveValues == second.effectiveValues && first.userValues == second.userValues
            && first.revision == second.revision
    }

    static func state(_ f: Fixture, active: Set<SceneDynamicTarget>? = nil) -> ScenePropertyLiveUpdateState {
        .init(program: f.compilation.program,
            effectiveValues: f.catalog.effectiveValues(overrides: [:]),
            activeConsumerTargets: active ?? Set(f.compilation.program.instructions.map(\.target)))
    }

    static func liveChecks() -> [String: Bool] {
        let f = fixture(seed: false, script: true)
        var state = state(f), checks: [String: Bool] = [:]
        for (index, pair) in [("0.4 0.8 0.2", SceneDynamicValue.vector3(0.4, 0.8, 0.2)),
                              ("0.8 0.4 0.6", .vector3(0.8, 0.4, 0.6)),
                              ("0 0 0", .vector3(0, 0, 0)), ("1 1 1", .vector3(1, 1, 1))].enumerated() {
            checks["legalColorUpdatesOnlyItsRealPeers_\(index)"] = state.apply(.string(pair.0), forPropertyKey: "palette")
                && state.userValues[f.color] == pair.1 && state.userValues[f.material] == pair.1
                // The first color equals the launch default and is a no-op.
                && state.userValues[f.visible] == nil && state.revision == UInt64(index)
        }
        let beforeSame = state
        checks["sameColorIsSuccessfulNoOp"] = state.apply(.string("1 1 1"), forPropertyKey: "palette") && sameState(state, beforeSame)
        for (name, bad) in [("malformed", SceneUserPropertyValue.string("0.2 0.4")),
                            ("nonfinite", .string("nan 0.4 0.6")), ("wrongType", .number(0.2))] {
            let before = state
            checks["invalidColorPreservesAll_\(name)"] = !state.apply(bad, forPropertyKey: "palette") && sameState(state, before)
            checks["invalidBulkPreservesBothKeys_\(name)"] = !state.apply(
                replacements: ["palette": bad, "opacity": .number(0.75)],
                changedPropertyKeys: ["palette", "opacity"]) && sameState(state, before)
        }
        let beforeMissing = state
        checks["missingBulkReplacementCannotPartiallyCommit"] = !state.apply(
            replacements: ["opacity": .number(0.75)], changedPropertyKeys: ["palette", "opacity"])
            && sameState(state, beforeMissing)
        checks["healthyBulkChangesAllRealPeers"] = state.apply(replacements: [
            "palette": .string("0.2 0.6 0.8"), "opacity": .number(0.75)
        ], changedPropertyKeys: ["palette", "opacity"])
            && state.userValues[f.material] == .vector3(0.2, 0.6, 0.8)
            && state.userValues[f.color] == .vector3(0.2, 0.6, 0.8)
            && state.userValues[f.alpha] == .scalar(0.75) && state.userValues[f.visible] == nil
        var partial = self.state(f, active: [f.color, f.alpha])
        let beforePartial = partial
        checks["inactiveLegalSiblingStillBlocksWholeKey"] = !partial.apply(.string("1 0 0"), forPropertyKey: "palette")
            && sameState(partial, beforePartial)
        let beforeUnavailable = state
        checks["unavailableLegalSiblingStillBlocksBulk"] = !state.apply(replacements: [
            "palette": .string("1 0 0"), "opacity": .number(0.25)
        ], changedPropertyKeys: ["palette", "opacity"], unavailableConsumerTargets: [f.material])
            && sameState(state, beforeUnavailable)
        var blocked = self.state(fixture(conditional: true))
        let beforeBlocked = blocked
        checks["unapprovedConditionalStillRebuildsAndRejects"] = !blocked.apply(.string("1 0 0"), forPropertyKey: "palette")
            && sameState(blocked, beforeBlocked)
        let onlyVisibility = ScenePropertyBindingCompiler().compile(report: .init(
            bindings: f.resolution.bindingReport.bindings.filter { $0.target == .layerVisibility(layerID: 10) },
            diagnostics: []), catalog: f.catalog)
        checks["onlyIgnoredVisibilityHasNoPublisher"] = onlyVisibility.diagnostics.count == 1
            && onlyVisibility.diagnostics.first?.code == .ignoredIncompatibleVisibility
            && onlyVisibility.program.instructions.isEmpty && onlyVisibility.program.definitions.isEmpty
            && onlyVisibility.program.rebuildRequiredPropertyKeys.isEmpty
        var withoutConsumer = ScenePropertyLiveUpdateState(program: onlyVisibility.program,
            effectiveValues: f.catalog.effectiveValues(overrides: [:]), activeConsumerTargets: [])
        let beforeNoConsumer = withoutConsumer
        checks["onlyIgnoredVisibilityRejectsChangedColor"] = !withoutConsumer.apply(.string("1 0 0"), forPropertyKey: "palette")
            && sameState(withoutConsumer, beforeNoConsumer)
        checks["onlyIgnoredVisibilityRejectsEvenSameColor"] = !withoutConsumer.apply(.string("0.4 0.8 0.2"), forPropertyKey: "palette")
            && sameState(withoutConsumer, beforeNoConsumer)
        return checks
    }

    static func main() throws {
        let payload = ["startup": startupChecks(), "compiler": try compilerChecks(), "live": liveChecks()]
        print(String(decoding: try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]), as: UTF8.self))
    }
}
'''


class SceneColorVisibilityBindingTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        if shutil.which("swiftc") is None:
            raise unittest.SkipTest("swiftc is unavailable")
        cls.temporary = tempfile.TemporaryDirectory(prefix="mwx-color-visibility-bindings-")
        cls.addClassCleanup(cls.temporary.cleanup)
        work = Path(cls.temporary.name)
        source = work / "Harness.swift"
        source.write_text(HARNESS, encoding="utf-8")
        binary = work / "color-visibility-bindings"
        compiled = subprocess.run([
            "swiftc", *map(str, SWIFT_SOURCES), str(source),
            "-module-cache-path", str(work / "cache"), "-o", str(binary),
        ], cwd=ROOT, capture_output=True, text=True, timeout=180)
        if compiled.returncode:
            raise AssertionError(compiled.stderr)
        cls.result = json.loads(subprocess.check_output([str(binary)], text=True, timeout=30))

    def assert_checks(self, group: str, prefix: str | None = None) -> None:
        checks = {key: value for key, value in self.result[group].items()
                  if prefix is None or key.startswith(prefix)}
        self.assertTrue(checks, (group, prefix))
        for key, passed in checks.items():
            with self.subTest(check=key):
                self.assertTrue(passed)

    def test_startup_preserves_both_boolean_seeds_and_script_metadata(self) -> None:
        self.assert_checks("startup")

    def test_compiler_diagnoses_local_ignore_and_preserves_real_material_peers(self) -> None:
        for prefix in ("ignoreHasExplicit", "onlyLegalPeers", "programRoundTrip", "zeroLayerID"):
            self.assert_checks("compiler", prefix)

    def test_unsupported_pairings_and_definition_errors_remain_bounded(self) -> None:
        for prefix in ("boundaryDoesNot", "ignoreCannot", "realBoolWriter", "conditionalStartup"):
            self.assert_checks("compiler", prefix)

    def test_live_colors_update_only_actual_publishers_without_a_boolean_writer(self) -> None:
        for prefix in ("legalColor", "sameColor", "healthyBulk"):
            self.assert_checks("live", prefix)

    def test_invalid_color_and_bulk_updates_preserve_the_committed_state(self) -> None:
        for prefix in ("invalidColor", "invalidBulk", "missingBulk"):
            self.assert_checks("live", prefix)

    def test_inactive_or_unavailable_real_consumers_still_reject_atomically(self) -> None:
        for prefix in ("inactiveLegal", "unavailableLegal", "unapprovedConditional"):
            self.assert_checks("live", prefix)

    def test_ignored_visibility_alone_does_not_authorize_a_live_update(self) -> None:
        self.assert_checks("live", "onlyIgnoredVisibility")


if __name__ == "__main__":
    unittest.main()
