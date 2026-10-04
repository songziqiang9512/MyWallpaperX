
@main
enum SeedHarness {
    static func effectVisibilityBinding() -> SceneScriptBindingIR {
        SceneScriptBindingIR(
            source: """
            export function mediaThumbnailChanged(event)
            { thisObject.visible = event.hasThumbnail; }
            """,
            owner: .init(
                kind: .effect, objectIndex: 0, objectID: 10,
                effectIndex: 0, effectID: 100,
                passIndex: nil, passID: nil
            ),
            targetPath: [
                .key("objects"), .index(0), .key("effects"), .index(0),
                .key("visible"),
            ],
            properties: [:],
            authoredValue: .bool(true),
            valueType: .boolean,
            wrapperKeys: ["script", "value"]
        )
    }

    static func descriptor(effectVisible: Bool?, effectID: Int = 100)
        -> SceneRenderDescriptor {
        SceneRenderDescriptor(layers: [
            .init(
                id: 10,
                layerIndex: 0,
                name: "cover",
                visible: true,
                originXYZ: [0, 0, 0],
                scaleXYZ: [1, 1, 1],
                scaleHasScript: false,
                alpha: 1,
                effects: [.init(
                    name: "toggle",
                    effectID: effectID,
                    visible: effectVisible
                )]
            )
        ])
    }

    @discardableResult
    static func check(
        _ condition: Bool, _ label: String, _ failures: inout Int
    ) -> Bool {
        if !condition { failures += 1 }
        return condition
    }

    static func main() throws {
        var failures = 0
        let authored = descriptor(effectVisible: true)
        let binding = effectVisibilityBinding()

        // Baseline: no prepared descriptor - the definition seed is the
        // binding's authored seed (pre-D1 behavior preserved).
        let baselineProjection = SceneScriptVectorProgram.project(
            descriptor: authored,
            scriptBindings: [binding]
        )
        let baselineCandidate = baselineProjection.uniqueCandidates.first {
            if case .effectVisibility = $0.definition.target { return true }
            return false
        }
        check(baselineCandidate != nil, "baseline candidate admitted", &failures)
        check(
            baselineCandidate?.definition.authoredValue == .bool(true),
            "baseline definition seed is the authored true", &failures
        )
        check(
            baselineCandidate?.effectVisibilityGetterSeed == true,
            "baseline getter seed is the authored seed", &failures
        )

        // Prepared: the media matcher flipped the runtime effect to hidden.
        // The candidate still admits (the guard reads the authored state),
        // but the definition seed - the frame snapshot's initial value - is
        // the prepared hidden state.
        let prepared = descriptor(effectVisible: false)
        let preparedProjection = SceneScriptVectorProgram.project(
            descriptor: authored,
            scriptBindings: [binding],
            preparedDescriptor: prepared
        )
        let preparedCandidate = preparedProjection.uniqueCandidates.first {
            if case .effectVisibility = $0.definition.target { return true }
            return false
        }
        check(preparedCandidate != nil, "prepared candidate admitted", &failures)
        check(
            preparedCandidate?.definition.authoredValue == .bool(false),
            "prepared definition seed is the prepared false", &failures
        )
        check(
            preparedCandidate?.effectVisibilityGetterSeed == true,
            "prepared getter seed stays the authored seed", &failures
        )

        // Identity mismatch in the prepared tree falls back to the authored
        // seed instead of inventing a state.
        let mismatched = descriptor(effectVisible: false, effectID: 999)
        let mismatchedProjection = SceneScriptVectorProgram.project(
            descriptor: authored,
            scriptBindings: [binding],
            preparedDescriptor: mismatched
        )
        let mismatchedCandidate = mismatchedProjection.uniqueCandidates.first {
            if case .effectVisibility = $0.definition.target { return true }
            return false
        }
        check(
            mismatchedCandidate?.definition.authoredValue == .bool(true),
            "identity mismatch falls back to the authored seed", &failures
        )

        // Snapshot seeding: the resolver seeds the frame value from the
        // definition, so the prepared projection resolves hidden.
        let target = SceneDynamicTarget.effectVisibility(
            layerID: 10, effectIndex: 0
        )
        let baselineResolution = SceneDynamicSnapshotResolver().resolve(
            frameIndex: 1, generation: 1,
            definitions: baselineProjection.definitions
        )
        check(
            baselineResolution.snapshot[target]?.value == .bool(true),
            "baseline snapshot seeds visible true", &failures
        )
        let preparedResolution = SceneDynamicSnapshotResolver().resolve(
            frameIndex: 2, generation: 2,
            definitions: preparedProjection.definitions
        )
        check(
            preparedResolution.snapshot[target]?.value == .bool(false),
            "prepared snapshot seeds hidden", &failures
        )
        check(
            preparedResolution.snapshot[target]?.source == .authored,
            "prepared snapshot seed stays on the authored lane", &failures
        )

        let payload: [String: Any] = [
            "failures": failures,
            "baselineAdmitted": baselineCandidate != nil,
            "preparedAdmitted": preparedCandidate != nil,
            "preparedSeedHidden": preparedCandidate?.definition
                .authoredValue == .bool(false),
        ]
        let data = try JSONSerialization.data(
            withJSONObject: payload, options: [.sortedKeys]
        )
        print(String(decoding: data, as: UTF8.self))
        if failures > 0 { exit(1) }
    }
}
