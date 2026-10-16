import Foundation

/// Real typed Bool Program/ValueOwner callbacks: return acceptance, continued
/// events/timers, and the independent failure/transaction boundaries.
enum SceneScriptBooleanReturnChecks {
    static let target = SceneDynamicTarget.layer(layerID: 73, field: .visibility)

    static func descriptor(_ name: String = "own-return-probe") -> SceneRenderDescriptor {
        var layer = SceneRenderDescriptor.Layer(id: 73, layerIndex: 0, name: name,
            visible: false, originXYZ: [0, 0, 0], scaleXYZ: [1, 1, 1],
            alpha: 1, effects: [], sizeWH: [80, 80])
        layer.imagePath = "models/\(name).json"
        return .init(layers: [layer])
    }

    static func program(_ source: String, name: String = "own-return-probe") throws
        -> SceneScriptVectorProgram {
        let domain = try SceneScriptQuickJSDomain()
        let scene = descriptor(name)
        try domain.configureLayerCatalog(scene)
        try domain.configureLayerRuntimeFields(scene)
        return .compile(domain: domain, descriptor: scene, scriptBindings: [
            .init(source: source,
                owner: .init(kind: .object, objectIndex: 0, objectID: 73,
                    effectIndex: nil, effectID: nil, passIndex: nil, passID: nil),
                targetPath: [.key("objects"), .index(0), .key("visible")],
                properties: [:], authoredValue: .bool(false), valueType: .boolean,
                wrapperKeys: ["script", "value"])
        ], userPropertyDefinitions: [], generation: 61)
    }

    static func frame(_ time: Double) -> SceneScriptFrameInput {
        .init(timing: .init(wallDate: Date(timeIntervalSince1970: 0),
            simulationFrameTime: 0.05, sceneTime: time))
    }

    static func evaluate(_ program: SceneScriptVectorProgram, input: Bool,
                         time: Double = 1, budget: UInt64? = nil) -> SceneScriptVectorFrameResult {
        program.evaluate(inputs: [target: .bool(input)], effectivePropertyValues: [:],
            frame: frame(time), interruptBudget: budget)
    }

    static func value(_ result: SceneScriptVectorFrameResult) -> Bool? {
        guard case let .bool(value)? = result.values[target] else { return nil }
        return value
    }

    static func run() throws -> [String: Bool] {
        var facts: [String: Bool] = [:]
        // Opposite input makes accidental truthiness observable. These are
        // independent self-authored expressions, never a Workshop module.
        let cases: [(String, String, Bool, Bool)] = [
            ("native-true", "true", false, true),
            ("native-false", "false", true, false),
            ("undefined", "undefined", true, true),
            ("zero", "2 - 2", true, true),
            ("negative", "-(1 + 1)", false, false),
            ("nan", "0 / 0", true, true),
            ("null", "null", true, true),
            ("empty-string", "''", true, true),
            ("nonempty-string", "'not-a-boolean'", false, false),
            ("vector", "new Vec3(0, 0, 0)", false, false),
            ("object", "({})", false, false),
            ("array", "[]", false, false),
            ("conversion-hooks", "({[Symbol.toPrimitive](){throw Error('coercion');},valueOf(){throw Error('coercion');},toString(){throw Error('coercion');}})", false, false),
        ]
        for phase in ["init", "update"] {
            for (label, expression, input, expected) in cases {
                let source = """
                    export function \(phase)(incoming) {
                        engine.setTimeout(() => { thisLayer.origin = new Vec3(71, 2, 3); }, 0);
                        return \(expression);
                    }
                    """ + (phase == "init" ? "\nexport function update(current){return current;}" : "")
                let owner = try program(source)
                let first = evaluate(owner, input: input)
                owner.finalizeLayerMutations(committing: true)
                let second = evaluate(owner, input: input, time: 2)
                facts["\(phase)-\(label)-typed-return"] = owner.definitions.count == 1
                    && first.failures.isEmpty && second.failures.isEmpty
                    && value(first) == expected && value(second) == (phase == "init" ? input : expected)
                facts["\(phase)-\(label)-timer-side-effect"] = (first.layerMutations + second.layerMutations)
                    .contains { $0.layerID == 73 && $0.fields.contains(.origin) && $0.origin == .init(71, 2, 3) }
                owner.finalizeLayerMutations(committing: true)
            }
        }

        for (index, counter) in ["launchCount", "起動回数", "starts"].enumerated() {
            let returns = ["new Vec3(0, 0, 0)", "({})", "0 / 0"]
            let owner = try program("""
                let \(counter)=0, presses=0, ticks=0;
                export function init(seed) {
                    ++\(counter); engine.setTimeout(() => { ++ticks; }, 0);
                    return \(returns[index]);
                }
                export function cursorClick(event) { presses = presses + 1; }
                export function update(current) {
                    thisLayer.origin = new Vec3(\(counter), presses, ticks);
                    return \(returns[(index + 1) % returns.count]);
                }
                """, name: "renamed-resource-\(index)")
            let first = evaluate(owner, input: false)
            owner.finalizeLayerMutations(committing: true)
            guard let cursor = owner.cursorOwnerRegistrations.first else {
                facts["continuity-\(index)-cursor-registration"] = false
                continue
            }
            let clicked = try cursor.owner.dispatchCursor(
                .init(kind: .click, layerID: 73, worldPosition: .zero, localPosition: .zero),
                frame: frame(2), scriptPropertiesJSON: "", userPropertiesJSON: "{}").get()
            let second = evaluate(owner, input: true, time: 2)
            owner.finalizeLayerMutations(committing: true)
            let third = evaluate(owner, input: false, time: 3)
            facts["continuity-\(index)-init-once-cursor-and-timer"] = first.failures.isEmpty
                && clicked.layers.isEmpty && second.failures.isEmpty && third.failures.isEmpty
                && value(first) == false && value(second) == true && value(third) == false
                && [second, third].allSatisfy { result in result.layerMutations.contains {
                    $0.fields.contains(.origin) && $0.origin == .init(1, 1, 1)
                } }
            owner.finalizeLayerMutations(committing: true)
            let stale = cursor.owner.evaluate(input: .bool(false), frame: frame(4),
                scriptPropertiesJSON: "", userPropertiesJSON: "{}", expectedGeneration: 62,
                interruptBudget: nil)
            if case let .failure(error) = stale {
                facts["continuity-\(index)-stale-still-rejected"] = error == .staleOwner
            } else { facts["continuity-\(index)-stale-still-rejected"] = false }
        }

        for (label, body, budget) in [
            ("throw", "throw Error('independent exception');", Optional<UInt64>.none),
            ("budget", "while(true){}", Optional<UInt64>.some(100)),
        ] {
            let owner = try program("""
                export function update(current) {
                    thisLayer.origin = new Vec3(9, 9, 9); \(body)
                }
                """)
            let rejected = evaluate(owner, input: true, budget: budget)
            facts["\(label)-keeps-atomic-failure"] = rejected.values.isEmpty
                && rejected.layerMutations.isEmpty && rejected.failures.count == 1
                && rejected.failures[target]?.code == (label == "throw" ? "exception" : "budget-exceeded")
            owner.finalizeLayerMutations(committing: false)
            let peer = try program("export function update(current){return false;}")
            let healthy = evaluate(peer, input: true)
            facts["\(label)-healthy-peer"] = healthy.failures.isEmpty && value(healthy) == false
            peer.finalizeLayerMutations(committing: true)
        }
        return facts
    }
}
