#!/usr/bin/env python3

"""Cursor owners use exact typed identity while sharing layer hit state."""

from __future__ import annotations

import json
from pathlib import Path
import subprocess
import tempfile
import unittest

try:
    from .scene_vector_vm_test_support import compile_vector_harness
except ImportError:
    from scene_vector_vm_test_support import compile_vector_harness


HARNESS = r'''
@main
enum Harness {
    static func main() throws {
        let descriptor = SceneRenderDescriptor(layers: [
            layer(id: 10, index: 0, name: "standalone-borrowed"),
            layer(id: 20, index: 1, name: "borrowed-borrowed"),
            layer(id: 30, index: 2, name: "standalone-only"),
            layer(id: 40, index: 3, name: "borrowed-only"),
            layer(id: 50, index: 4, name: "defaulted-borrowed"),
        ])
        let bindings = [
            standaloneBinding(layerID: 10, index: 0),
            vectorBinding(layerID: 10, index: 0, field: "origin"),
            vectorBinding(layerID: 20, index: 1, field: "origin"),
            vectorBinding(layerID: 20, index: 1, field: "scale"),
            standaloneBinding(layerID: 30, index: 2),
            vectorBinding(layerID: 40, index: 3, field: "origin"),
            visibilityBinding(layerID: 50, index: 4),
        ]
        let projection = SceneScriptVectorProgram.project(
            descriptor: descriptor,
            scriptBindings: bindings
        )
        let candidate = try SceneScriptQuickJSProgramCandidate.compile(
            authoredDescriptor: descriptor,
            runtimeDescriptor: descriptor,
            scriptBindings: bindings,
            vectorProjection: projection,
            userPropertyDefinitions: [],
            timelineTargets: [],
            scalarExcludedTargets: [],
            stringExcludedTargets: [],
            admittedVectorPassTargets: [],
            generation: 41
        )
        let report = candidate.constructionReport
        let preflight = SceneScriptCursorProgram.compileCandidate(
            domain: candidate.domain,
            descriptor: descriptor,
            scriptBindings: bindings,
            borrowedOwners: candidate.vectorProgram.cursorOwnerRegistrations,
            claimedTargets: candidate.vectorProgram.inputTargets,
            rejectedTargets: [],
            generation: 41
        )
        let frame = SceneScriptFrameInput(
            timing: .init(
                wallDate: Date(timeIntervalSince1970: 0),
                simulationFrameTime: 1.0 / 60.0,
                sceneTime: 2
            ),
            timeZone: TimeZone(secondsFromGMT: 0)!
        )
        let cursorResult = candidate.cursorProgram.dispatch(
            batch: .init(samples: [.init(
                hits: [
                    30: hit(layerID: 30),
                    40: hit(layerID: 40),
                ],
                pointerPosition: .init(0.5, 0.5),
                primaryButtonIsDown: false
            )], overflowed: false),
            frame: frame,
            userPropertiesJSON: "{}"
        )
        var parallaxDescriptor = descriptor
        parallaxDescriptor.camera.parallaxEnabled = true
        let parallaxProgram = SceneScriptCursorProgram.compile(
            domain: try SceneScriptQuickJSDomain(), descriptor: parallaxDescriptor,
            scriptBindings: [standaloneBinding(layerID: 30, index: 2)], generation: 42)
        let mixedStandaloneBindings = [standaloneBinding(
            layerID: 30, index: 2, source: """
            export function update(value) { return value; }
            export function cursorEnter(event) { return; }
            """
        )]
        let mixedStandaloneProjection = SceneScriptVectorProgram.project(
            descriptor: descriptor, scriptBindings: mixedStandaloneBindings
        )
        let mixedStandaloneCandidate = try SceneScriptQuickJSProgramCandidate.compile(
            authoredDescriptor: descriptor, runtimeDescriptor: descriptor,
            scriptBindings: mixedStandaloneBindings,
            vectorProjection: mixedStandaloneProjection,
            userPropertyDefinitions: [], timelineTargets: [],
            scalarExcludedTargets: [], stringExcludedTargets: [],
            admittedVectorPassTargets: [], generation: 43
        )
        let duplicateRegistration = candidate.vectorProgram
            .cursorOwnerRegistrations.first { $0.layerID == 40 }!
        let duplicatePreflight = SceneScriptCursorProgram.compileCandidate(
            domain: candidate.domain,
            descriptor: descriptor,
            scriptBindings: [],
            borrowedOwners: [duplicateRegistration, duplicateRegistration],
            rejectedTargets: [],
            generation: 44
        )
        let peerDescriptor = SceneRenderDescriptor(layers: [
            layer(id: 60, index: 0, name: "same-layer-peer-isolation"),
        ])
        let peerBindings = [
            vectorBinding(
                layerID: 60, index: 0, field: "scale",
                source: successSource(x: 1)
            ),
            visibilityBinding(
                layerID: 60, index: 0, source: failureSource
            ),
            vectorBinding(
                layerID: 60, index: 0, field: "angles",
                source: successSource(x: 2)
            ),
        ]
        let peerProjection = SceneScriptVectorProgram.project(
            descriptor: peerDescriptor, scriptBindings: peerBindings
        )
        let peerCandidate = try SceneScriptQuickJSProgramCandidate.compile(
            authoredDescriptor: peerDescriptor,
            runtimeDescriptor: peerDescriptor,
            scriptBindings: peerBindings,
            vectorProjection: peerProjection,
            userPropertyDefinitions: [], timelineTargets: [],
            scalarExcludedTargets: [], stringExcludedTargets: [],
            admittedVectorPassTargets: [], generation: 45
        )
        let peerInitialOwnerCount = peerCandidate.cursorProgram.ownerCount
        let peerResult = peerCandidate.cursorProgram.dispatch(
            batch: .init(samples: [
                .init(
                    hits: [60: hit(layerID: 60)],
                    pointerPosition: .zero,
                    primaryButtonIsDown: false
                ),
                .init(
                    hits: [60: hit(layerID: 60)],
                    pointerPosition: .zero,
                    primaryButtonIsDown: true
                ),
                .init(
                    hits: [:],
                    ownerProjections: [60: hit(layerID: 60)],
                    pointerPosition: .init(0.5, 0),
                    primaryButtonIsDown: true
                ),
                .init(
                    hits: [:],
                    ownerProjections: [60: hit(layerID: 60)],
                    pointerPosition: .init(0.5, 0),
                    primaryButtonIsDown: false
                ),
            ], overflowed: false),
            frame: frame,
            userPropertiesJSON: "{}"
        )
        let peerCapturedAfterRelease = peerCandidate.cursorProgram
            .capturedOwnerLayerIDs.count
        let peerNextFrame = peerCandidate.cursorProgram.dispatch(
            batch: .init(samples: [
                .init(
                    hits: [60: hit(layerID: 60)],
                    pointerPosition: .init(0.5, 0),
                    primaryButtonIsDown: false
                ),
                .init(
                    hits: [60: hit(layerID: 60)],
                    pointerPosition: .init(0.5, 0),
                    primaryButtonIsDown: true
                ),
            ], overflowed: false),
            frame: frame,
            userPropertiesJSON: "{}"
        )
        let payload: [String: Any] = [
            "fullscreen": try fullscreenCases(frame: frame),
            "mixedStandaloneVectorTargets": mixedStandaloneProjection.targets.count,
            "mixedStandaloneCursorFailure": mixedStandaloneCandidate
                .constructionReport.cursorFailures[
                    .layer(layerID: 30, field: .visibility)
                ]?.code ?? "missing",
            "mixedStandaloneCursorOwners": mixedStandaloneCandidate
                .cursorProgram.ownerCount,
            "enabledParallaxOwners": parallaxProgram.ownerCount,
            "domainCommitted": candidate.domain != nil,
            "preflightRequiresReconstruction": preflight.requiresDomainReconstruction,
            "complete": report.isComplete,
            "vectorInstantiated": report.instantiatedVectorTargets.count,
            "cursorExpected": report.expectedCursorTargets.count,
            "cursorInstantiated": report.instantiatedCursorTargets.count,
            "cursorFailures": report.cursorFailures.keys.map {
                targetName($0)
            }.sorted(),
            "cursorOwners": candidate.cursorProgram.ownerLayerIDs.sorted(),
            "cursorOwnerCount": candidate.cursorProgram.ownerCount,
            "dispatchFailures": cursorResult.failures.keys.map {
                targetName($0)
            }.sorted(),
            "duplicateRequested": duplicatePreflight.requestedTargets.count,
            "duplicateInstantiated": duplicatePreflight.instantiatedTargets.count,
            "duplicateFailure": duplicatePreflight.failures[
                .layer(layerID: 40, field: .origin)
            ]?.code ?? "missing",
            "duplicateRequiresReconstruction": duplicatePreflight
                .requiresDomainReconstruction,
            "peerInitialOwners": peerInitialOwnerCount,
            "peerOwners": peerCandidate.cursorProgram.ownerCount,
            "peerVectorTargets": peerProjection.targets.count,
            "peerVectorExpected": peerCandidate.constructionReport
                .expectedVectorTargets.count,
            "peerVectorFailures": peerCandidate.constructionReport
                .vectorFailures.values.map(\.code).sorted(),
            "peerCursorExpected": peerCandidate.constructionReport
                .expectedCursorTargets.count,
            "peerCursorFailures": peerCandidate.constructionReport
                .cursorFailures.values.map(\.code).sorted(),
            "peerFailureVisibility": peerResult.failures[
                .layer(layerID: 60, field: .visibility)
            ]?.code ?? "missing",
            "peerMutationX": peerResult.layerMutations.map(\.origin.x),
            "peerOwnerOrder": peerResult.ownerEffects.map {
                targetName($0.ownerTarget)
            },
            "peerCapturedAfterRelease": peerCapturedAfterRelease,
            "peerNextFrameFailures": peerNextFrame.failures.count,
            "peerNextFrameMutationX": peerNextFrame.layerMutations.map(\.origin.x),
        ]
        let data = try JSONSerialization.data(
            withJSONObject: payload,
            options: [.sortedKeys]
        )
        print(String(decoding: data, as: UTF8.self))
    }

    static func fullscreenCases(frame: SceneScriptFrameInput) throws -> [[String: Any]] {
        try (0..<2).map { variant in
            let base = 610 + variant * 500
            let mirrorName = variant == 0 ? "mirror" : "renamed-capture"
            let stripName = variant == 0 ? "strip" : "renamed-output"
            let pointName = variant == 0 ? "point" : "cursorPosition"
            let replacement = variant == 0
                ? "new Vec3(\(pointName).x, event.worldPosition.y, event.localPosition.x)"
                : "{x: \(pointName).x, y: event.worldPosition.y, z: event.localPosition.x}"
            let source = """
            shared.fullscreenConstructions = (shared.fullscreenConstructions || 0) + 1;
            export function cursorMove(event) {
                if (shared.fullscreenConstructions !== 1) throw Error('duplicate fullscreen owner');
                const \(pointName) = input.cursorWorldPosition;
                if (\(pointName).x !== event.worldPosition.x ||
                    input.cursorScreenPosition.x !== event.localPosition.x ||
                    input.cursorScreenPosition.y !== event.localPosition.y) throw Error('changed event input');
                thisScene.getLayer('\(mirrorName)').origin = \(replacement);
                thisScene.getLayer('\(stripName)').origin =
                    new Vec3(event.worldPosition.x, \(pointName).y, event.localPosition.y);
            }
            """
            let peerSource = """
            export function cursorMove(event) {
                thisLayer.origin = new Vec3(event.localPosition.x, event.localPosition.y, 9);
            }
            """
            var layers = (0..<9).map { index -> SceneRenderDescriptor.Layer in
                .init(id: base + index, layerIndex: index,
                    name: index == 7 ? mirrorName : index == 8 ? stripName : "owner-\(variant)-\(index)",
                    visible: true, originXYZ: index == 0 ? nil : [0, 0, 0],
                    scaleXYZ: index == 0 ? nil : [1, 1, 1], scaleHasScript: false,
                    alpha: 1, effects: [], contentKind: "image", sizeWH: [100, 100])
            }
            layers[0].contentKind = "fullscreen"
            layers[0].utilityLayer = .init(kind: .fullscreen, copyBackground: false, passthrough: false)
            layers[0].imagePath = "models/renamed/viewport-\(variant).json"
            layers[0].sizeWH = nil
            layers[2].sizeWH = nil
            layers[3].sizeWH = [0, 100]
            layers[4].contentKind = "composition"
            layers[4].utilityLayer = .init(kind: .composition, copyBackground: true, passthrough: false)
            layers[4].sizeWH = nil
            layers[5].contentKind = "project"
            layers[5].utilityLayer = .init(kind: .project, copyBackground: true, passthrough: false)
            layers[5].sizeWH = nil
            layers[6].contentKind = "fullscreen"
            layers[6].imagePath = "models/util/fullscreenlayer.json"
            layers[6].sizeWH = nil
            let descriptor = SceneRenderDescriptor(layers: layers)
            let bindings = (0...6).map { index in
                standaloneBinding(layerID: base + index, index: index,
                    source: index == 0 ? source : peerSource)
            }
            let standalone = SceneScriptCursorProgram.compileCandidate(
                domain: try SceneScriptQuickJSDomain(), descriptor: descriptor,
                scriptBindings: bindings, rejectedTargets: [], generation: UInt64(base))
            let candidate = try SceneScriptQuickJSProgramCandidate.compile(
                authoredDescriptor: descriptor, runtimeDescriptor: descriptor,
                scriptBindings: bindings,
                vectorProjection: SceneScriptVectorProgram.project(
                    descriptor: descriptor, scriptBindings: bindings),
                userPropertyDefinitions: [], timelineTargets: [], scalarExcludedTargets: [],
                stringExcludedTargets: [], admittedVectorPassTargets: [], generation: UInt64(base + 1))
            func move(_ program: SceneScriptCursorProgram) -> [String: Any] {
                let hits = Dictionary(uniqueKeysWithValues: (0...6).map { index in
                    let id = base + index
                    return (id, SceneScriptCursorHit(layerID: id,
                        worldPosition: .init(8612, 1980, 0), localPosition: .init(2153, 45, 0)))
                })
                let surface = SceneScriptSurfaceInput(canvasSize: .init(10_240, 2160),
                    screenSize: .init(2560, 1440), cursorWorldPosition: .init(8612, 1980, 0),
                    cursorScreenPosition: .init(2153, 45), cursorLeftDown: false)
                let result = program.dispatch(batch: .init(samples: [
                    .init(hits: hits, pointerPosition: .zero, primaryButtonIsDown: false,
                          surface: surface, surfaceID: 71),
                    .init(hits: hits, pointerPosition: .init(0.5, 0), primaryButtonIsDown: false,
                          surface: surface, surfaceID: 71),
                ], overflowed: false), frame: frame, userPropertiesJSON: "{}")
                return [
                    "failures": result.failures.values.map(\.code).sorted(),
                    "mutations": result.layerMutations.sorted { $0.layerID < $1.layerID }.map {
                        [Double($0.layerID), $0.origin.x, $0.origin.y, $0.origin.z]
                    },
                ]
            }
            return [
                "base": base,
                "standaloneOwners": standalone.program.ownerLayerIDs.sorted(),
                "standaloneOwned": standalone.program.bindings.allSatisfy { $0.ownsOwner },
                "standaloneFailures": standalone.failures.values.map(\.code).sorted(),
                "standaloneReconstructed": standalone.requiresDomainReconstruction,
                "standaloneDispatch": move(standalone.program),
                "borrowedOwners": candidate.cursorProgram.ownerLayerIDs.sorted(),
                "borrowedOnly": candidate.cursorProgram.bindings.allSatisfy { !$0.ownsOwner },
                "borrowedVectorOwners": candidate.vectorProgram.inputTargets.count,
                "borrowedFailures": candidate.constructionReport.cursorFailures.keys.map {
                    targetName($0)
                }.sorted(),
                "borrowedFailureCodes": candidate.constructionReport.cursorFailures.values.map(\.code).sorted(),
                "borrowedComplete": candidate.constructionReport.isComplete,
                "borrowedDispatch": move(candidate.cursorProgram),
            ]
        }
    }

    static func layer(
        id: Int,
        index: Int,
        name: String
    ) -> SceneRenderDescriptor.Layer {
        .init(
            id: id,
            layerIndex: index,
            name: name,
            visible: true,
            originXYZ: id == 50 ? nil : [0, 0, 0],
            scaleXYZ: id == 50 ? nil : [1, 1, 1],
            anglesXYZ: id == 50 ? nil : [0, -0.0, 0],
            scaleHasScript: false,
            alpha: 1,
            effects: id == 30 ? [.init(name: "authored-effect")] : [],
            contentKind: [30, 50, 60].contains(id) ? "image" : "composition",
            sizeWH: [100, 100],
            utilityLayer: id == 50 || id == 60 ? nil : .init(
                kind: .composition, copyBackground: false, passthrough: false
            ),
            parentID: id == 30 ? 10 : nil,
            parallaxDepthXY: id == 50 ? nil : [1, 1]
        )
    }

    static func standaloneBinding(
        layerID: Int,
        index: Int,
        source: String = standaloneSource
    ) -> SceneScriptBindingIR {
        .init(
            source: source,
            owner: .init(
                kind: .object,
                objectIndex: index,
                objectID: layerID,
                effectIndex: nil,
                effectID: nil,
                passIndex: nil,
                passID: nil
            ),
            targetPath: [
                .key("objects"), .index(index), .key("visible"),
            ],
            properties: [:],
            authoredValue: .bool(true),
            valueType: .boolean,
            wrapperKeys: ["script", "value"]
        )
    }

    static func vectorBinding(
        layerID: Int,
        index: Int,
        field: String,
        source: String = borrowedSource
    ) -> SceneScriptBindingIR {
        .init(
            source: source,
            owner: .init(
                kind: .object,
                objectIndex: index,
                objectID: layerID,
                effectIndex: nil,
                effectID: nil,
                passIndex: nil,
                passID: nil
            ),
            targetPath: [
                .key("objects"), .index(index), .key(field),
            ],
            properties: [:],
            authoredValue: .string(
                field == "scale" ? "1 1 1"
                    : field == "angles" ? "0 -0 0" : "0 0 0"
            ),
            valueType: .string,
            wrapperKeys: ["script", "value"]
        )
    }

    static func visibilityBinding(
        layerID: Int,
        index: Int,
        source: String = borrowedSource
    ) -> SceneScriptBindingIR {
        .init(
            source: source,
            owner: .init(
                kind: .object,
                objectIndex: index,
                objectID: layerID,
                effectIndex: nil,
                effectID: nil,
                passIndex: nil,
                passID: nil
            ),
            targetPath: [
                .key("objects"), .index(index), .key("visible"),
            ],
            properties: [:],
            authoredValue: .bool(true),
            valueType: .boolean,
            wrapperKeys: ["script", "value"]
        )
    }

    static func hit(layerID: Int) -> SceneScriptCursorHit {
        .init(
            layerID: layerID,
            worldPosition: .init(1, 2, 0),
            localPosition: .init(0.5, 0.5, 0)
        )
    }

    static func targetName(_ target: SceneDynamicTarget) -> String {
        if case let .layer(layerID, field) = target {
            return "\(layerID):\(field.rawValue)"
        }
        return String(describing: target)
    }

    static func successSource(x: Int) -> String {
        """
        export function cursorDown(event) {
            thisLayer.origin = new Vec3(\(x), 0, 0);
        }
        export function cursorMove(event) {
            thisLayer.origin = new Vec3(\(x + 2), 0, 0);
        }
        export function cursorUp(event) {
            thisLayer.origin = new Vec3(\(x + 4), 0, 0);
        }
        export function update(value) { return value; }
        """
    }

    static let standaloneSource = """
    export function cursorEnter(event) {}
    """

    static let borrowedSource = """
    export function cursorEnter(event) {}
    export function update(value) { return value }
    """

    static let failureSource = """
    export function cursorDown(event) { throw new Error("peer failure"); }
    export function update(value) { return value; }
    """
}
'''


class SceneCursorCandidateCollisionTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.temp_dir = tempfile.TemporaryDirectory(
            prefix="mwx-cursor-candidate-collision-"
        )
        cls.binary = compile_vector_harness(
            temporary_directory=Path(cls.temp_dir.name),
            harness_source=HARNESS,
            binary_name="scene-cursor-candidate-collision",
        )

    @classmethod
    def tearDownClass(cls) -> None:
        cls.temp_dir.cleanup()

    def test_enabled_parallax_uses_runtime_camera_projection_for_hit_testing(self):
        result = json.loads(subprocess.run([str(self.binary)], check=True,
            capture_output=True, text=True).stdout)
        self.assertEqual(result["enabledParallaxOwners"], 1)
        self.assertEqual(result["cursorOwners"], [10, 20, 30, 40, 50])

    def test_borrowed_child_owner_accepts_authored_transform_defaults(self):
        result = json.loads(subprocess.run([str(self.binary)], check=True,
            capture_output=True, text=True).stdout)
        self.assertIn(50, result["cursorOwners"])

    def test_sizeless_fullscreen_cursor_moves_dispatch_once_in_both_owner_routes(self):
        result = json.loads(subprocess.run([str(self.binary)], check=True,
            capture_output=True, text=True).stdout)
        self.assertEqual(len(result["fullscreen"]), 2)
        for case in result["fullscreen"]:
            base = case["base"]
            with self.subTest(base=base):
                self.assertEqual(case["standaloneOwners"], [base, base + 1])
                self.assertTrue(case["standaloneOwned"])
                self.assertEqual(case["standaloneFailures"], [])
                self.assertFalse(case["standaloneReconstructed"])
                self.assertEqual(case["borrowedOwners"], [base, base + 1])
                self.assertTrue(case["borrowedOnly"])
                self.assertEqual(case["borrowedVectorOwners"], 7)
                self.assertTrue(case["borrowedComplete"])
                for route in ("standaloneDispatch", "borrowedDispatch"):
                    self.assertEqual(case[route]["failures"], [], case)
                    self.assertEqual(case[route]["mutations"], [
                        [base + 1, 2153, 45, 9],
                        [base + 7, 8612, 1980, 2153],
                        [base + 8, 8612, 1980, 45],
                    ])

    def test_fullscreen_admission_keeps_other_sizeless_and_invalid_cards_local(self):
        result = json.loads(subprocess.run([str(self.binary)], check=True,
            capture_output=True, text=True).stdout)
        for case in result["fullscreen"]:
            base = case["base"]
            with self.subTest(base=base):
                self.assertEqual(case["borrowedFailures"], [
                    f"{base + offset}:visibility" for offset in range(2, 7)
                ])
                self.assertEqual(case["borrowedFailureCodes"], ["invalid-argument"] * 5)
                for route in ("standaloneDispatch", "borrowedDispatch"):
                    self.assertEqual([row[0] for row in case[route]["mutations"]],
                                     [base + 1, base + 7, base + 8])

    def test_same_layer_different_targets_coexist_and_exact_duplicates_fail(
        self,
    ) -> None:
        result = json.loads(subprocess.run(
            [str(self.binary)],
            check=True,
            capture_output=True,
            text=True,
        ).stdout)
        self.assertTrue(result["domainCommitted"])
        self.assertFalse(result["preflightRequiresReconstruction"])
        self.assertTrue(result["complete"])
        # Utility composition layers without dependency metadata now own
        # their scripted visibility in the vector lane (the standalone cursor
        # route orphaned frame-evaluating scripts — 3357627941 layer 55);
        # their cursor exports ride the borrowed-owner channel, so the total
        # cursor count is unchanged.
        self.assertEqual(result["vectorInstantiated"], 7)
        self.assertEqual(result["cursorExpected"], 7)
        self.assertEqual(result["cursorInstantiated"], 7)
        self.assertEqual(result["cursorFailures"], [])
        self.assertEqual(result["cursorOwners"], [10, 20, 30, 40, 50])
        self.assertEqual(result["cursorOwnerCount"], 7)
        self.assertEqual(result["dispatchFailures"], [])
        self.assertEqual(result["duplicateRequested"], 1)
        self.assertEqual(result["duplicateInstantiated"], 0)
        self.assertEqual(result["duplicateFailure"], "invalid-argument")
        self.assertFalse(result["duplicateRequiresReconstruction"])
        # A frame-evaluating visibility script on a utility composition layer
        # now owns in the vector lane instead of failing the event-only
        # cursor guard (the 3357627941 layer 55 shape); its cursor exports
        # ride the borrowed channel.
        self.assertEqual(result["mixedStandaloneVectorTargets"], 1)
        self.assertEqual(result["mixedStandaloneCursorFailure"], "missing")
        self.assertEqual(result["mixedStandaloneCursorOwners"], 1)

    def test_same_layer_peer_failure_keeps_authored_order_and_prior_mutations(
        self,
    ) -> None:
        result = json.loads(subprocess.run(
            [str(self.binary)], check=True, capture_output=True, text=True,
        ).stdout)
        self.assertEqual(result["peerInitialOwners"], 3)
        self.assertEqual(result["peerOwners"], 2)
        self.assertEqual(result["peerFailureVisibility"], "exception")
        self.assertEqual(result["peerMutationX"], [5, 6])
        self.assertEqual(result["peerOwnerOrder"], ["60:scale", "60:angles"])
        self.assertEqual(result["peerCapturedAfterRelease"], 0)
        self.assertEqual(result["peerNextFrameFailures"], 0)
        self.assertEqual(result["peerNextFrameMutationX"], [1, 2])


if __name__ == "__main__":
    unittest.main()
