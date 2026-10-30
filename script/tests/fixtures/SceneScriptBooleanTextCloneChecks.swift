import Foundation

// Reuse the prepared-text fixture's real C domain, journal and topology owner.
enum BooleanTextCloneChecks {
    static func run(_ renamed: Bool) throws -> [String: Any] {
        let fixture = try Harness.fixture(renamed: renamed)
        try fixture.domain.configurePreparedResourceLayerCatalog([:])
        let layers = Harness.runtime(fixture)
        let target = SceneDynamicTarget.layer(layerID: 110, field: .visibility)
        let name = renamed ? "renamed-watch" : "clock"
        let variable = renamed ? "replica" : "shadow"
        let owner = try SceneScriptValueOwner(
            domain: fixture.domain,
            source: """
                let \(variable);
                export function init(v) {
                    const config = thisScene.getInitialLayerConfig('\(name)');
                    \(variable) = thisScene.createLayer({text:config.text, pointsize:32});
                    return v;
                }
                export function update(v) {
                    thisLayer.angles = new Vec3(engine.runtime * 3, 0, 0);
                    if (engine.runtime === 4) thisScene.destroyLayer(\(variable));
                    else \(variable).visible = v;
                    return v;
                }
                """,
            target: target, valueType: .bool, effectNames: [],
            allowsStatefulLayerSideEffects: true, generation: 1, budget: .default
        )
        func evaluate(_ value: Bool, at time: Double)
            -> Result<SceneScriptValueEvaluation, SceneScriptScalarRuntimeFailure> {
            owner.evaluate(input: .bool(value), frame: Harness.frame(time),
                scriptPropertiesJSON: "", userPropertiesJSON: fixture.userJSON,
                expectedGeneration: 1, interruptBudget: nil)
        }
        let first = evaluate(true, at: 1)
        guard case let .success(evaluation) = first else {
            return ["status": Harness.status(first)]
        }
        // The Program validates the coalesced init+update journal a second time.
        let validated = try owner.validateBooleanFrame(value: evaluation.value,
            mutations: evaluation.layerMutations).get()
        let birth = layers.preflightOwnerEffects([Harness.effects(evaluation, owner)])
        guard birth.rejectedOwners.isEmpty else {
            owner.discardLayerMutations()
            return ["status": "topology-rejected"]
        }
        layers.commit(birth.layerPlan)
        owner.commitLayerMutations()
        let adopted = fixture.program.adoptCommittedPreparedTextClones(
            frame: Harness.frame(1),
            liveTextTemplates: birth.layerPlan.textTemplateIdentitiesByLayerID)
        let born = layers.snapshot().dynamicLayers
        let hidden = try evaluate(false, at: 2).get()
        let hiddenPlan = layers.preflightOwnerEffects([Harness.effects(hidden, owner)])
        // A rejected submission commits neither topology nor the C journal.
        owner.discardLayerMutations()
        let retained = hiddenPlan.rejectedOwners.isEmpty
            && layers.snapshot().dynamicLayers.first?.visible == true
        let destroyed = try evaluate(true, at: 4).get()
        let removal = layers.preflightOwnerEffects([Harness.effects(destroyed, owner)])
        layers.commit(removal.layerPlan)
        owner.commitLayerMutations()

        let missingImage = renamed ? "models/renamed-absent.json" : "models/unknown.json"
        let unknown = try SceneScriptValueOwner(domain: fixture.domain,
            source: """
                export function update(v) {
                    if (thisScene.createLayer({image:'\(missingImage)'}) !== null)
                        throw Error('missing image must not create a layer');
                    return v;
                }
                """,
            target: target, valueType: .bool, effectNames: [],
            allowsStatefulLayerSideEffects: true, generation: 1, budget: .default)
        let rejected = unknown.evaluate(input: .bool(true), frame: Harness.frame(5),
            scriptPropertiesJSON: "", userPropertiesJSON: "{}",
            expectedGeneration: 1, interruptBudget: nil)
        return ["status": "ok", "births": born.count,
            "rejected": birth.rejectedOwners.count,
            "adopted": adopted.definitions.count,
            "authoredAngles": validated.mutations.contains {
                !$0.isDynamic && $0.layerID == 110 && $0.fields.contains(.angles)
                    && $0.angles.x != 0
            },
            "discardRetainsVisible": retained,
            "afterDestroy": layers.snapshot().dynamicLayers.count,
            "unknownImage": Harness.status(rejected),
            "unknownImageMutations": (try? rejected.get().layerMutations.count) ?? -1]
    }
}
