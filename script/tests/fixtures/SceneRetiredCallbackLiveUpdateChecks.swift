import Foundation

/// Exercises the live-state boundary with already prepared typed inputs and
/// callback identities. Lifecycle/tombstone discovery remains a session test.
enum SceneRetiredCallbackLiveUpdateChecks {
    static func run() -> [String: Bool] {
        var facts: [String: Bool] = [:]
        for (key, inputName, layerID, replacement) in [
            ("palette", "tone", 41, "0.2 0.4 0.8"),
            ("renamed_ink", "pigment", 802, "  .20   .40  .80  ")
        ] {
            let direct = SceneDynamicTarget.layer(layerID: layerID, field: .color)
            let shared = SceneDynamicTarget.scriptInstanceProperty(
                layerID: layerID, path: ["color", "scriptproperties", inputName])
            let retired = SceneDynamicTarget.layer(layerID: layerID + 1, field: .visibility)
            let live = SceneDynamicTarget.layer(layerID: layerID + 2, field: .visibility)
            let failed = SceneDynamicTarget.layer(layerID: layerID + 3, field: .visibility)
            let peer = SceneDynamicTarget.layer(layerID: layerID + 4, field: .color)
            let producerTargets: Set<SceneDynamicTarget> = [direct, shared]
            let program = Harness.program(bindings: [
                (key, direct, .vector3, .vector3(1, 1, 1)),
                (key, shared, .vector3, .vector3(1, 1, 1)),
                ("peer", peer, .vector3, .vector3(1, 1, 1))])
            let values: [String: SceneUserPropertyValue] = [
                key: .string("1 1 1"), "peer": .string("1 1 1")]
            func state(callbacks: Set<SceneDynamicTarget>,
                       active: Set<SceneDynamicTarget>? = nil) -> ScenePropertyLiveUpdateState {
                ScenePropertyLiveUpdateState(program: program, effectiveValues: values,
                    activeConsumerTargets: active ?? producerTargets.union([peer, live, failed]),
                    scriptUserPropertyConsumerTargetsByKey: [key: callbacks, "peer": [failed]])
            }
            func record(_ name: String, _ value: Bool) {
                facts["retired-callback-\(key)-\(name)"] = value
            }

            // A retired event alone cannot revoke two surviving typed lanes.
            var typed = state(callbacks: [retired])
            let beforeTyped = typed
            record("no-tombstone-still-rejects", !typed.apply(.string(replacement),
                forPropertyKey: key, unavailableConsumerTargets: [retired])
                && unchanged(typed, beforeTyped))
            record("typed-lanes-survive", typed.apply(.string(replacement),
                forPropertyKey: key, unavailableConsumerTargets: [retired],
                retiredScriptCallbackTargets: [retired])
                && typed.revision == 1
                && typed.effectiveValues[key] == .string(replacement)
                && typed.userValues[direct] == .vector3(0.2, 0.4, 0.8)
                && typed.userValues[shared] == .vector3(0.2, 0.4, 0.8)
                && typed.effectiveValues["peer"] == values["peer"])
            let beforeRepeat = typed
            record("known-resend-noop", typed.apply(.string(replacement),
                forPropertyKey: key, unavailableConsumerTargets: producerTargets.union([retired]),
                retiredScriptCallbackTargets: [retired]) && unchanged(typed, beforeRepeat))
            for invalid in ["oops", "0.2 0.4", "nan 0.4 0.8"] {
                let before = typed
                record("rgb-\(invalid)", !typed.apply(.string(invalid), forPropertyKey: key,
                    unavailableConsumerTargets: [retired], retiredScriptCallbackTargets: [retired])
                    && unchanged(typed, before))
            }
            let beforeWrongKind = typed
            record("typed-kind-kept", !typed.apply(.number(0.4), forPropertyKey: key,
                unavailableConsumerTargets: [retired], retiredScriptCallbackTargets: [retired])
                && unchanged(typed, beforeWrongKind))

            // Other keys' failed callbacks do not contaminate a requested key.
            var mixed = state(callbacks: [retired, live])
            record("other-key-failure-isolated", mixed.apply(replacements: [key: .string(replacement)],
                changedPropertyKeys: [key], unavailableConsumerTargets: [retired, failed],
                retiredScriptCallbackTargets: [retired]) && mixed.revision == 1)
            let beforeBulk = mixed
            record("whole-key-batch-atomic", !mixed.apply(
                replacements: [key: .string("0.9 0.7 0.5"), "peer": .string("0.4 0.5 0.6")],
                changedPropertyKeys: [key, "peer"], unavailableConsumerTargets: [retired, failed],
                retiredScriptCallbackTargets: [retired]) && unchanged(mixed, beforeBulk))
            var disabled = state(callbacks: [retired, failed])
            let beforeDisabled = disabled
            record("failed-peer-not-retired", !disabled.apply(.string(replacement),
                forPropertyKey: key, unavailableConsumerTargets: [retired, failed],
                retiredScriptCallbackTargets: [retired]) && unchanged(disabled, beforeDisabled))
            var inactive = state(callbacks: [retired, live], active: producerTargets.union([peer]))
            let beforeInactive = inactive
            record("inactive-peer-not-retired", !inactive.apply(.string(replacement),
                forPropertyKey: key, unavailableConsumerTargets: [retired],
                retiredScriptCallbackTargets: [retired]) && unchanged(inactive, beforeInactive))

            // Even if a callback identity also names an instruction, retiring
            // the event cannot remove that instruction's consumer/type checks.
            for target in [direct, shared] {
                let name = target == direct ? "direct" : "shared-input"
                var overlap = state(callbacks: [target], active: producerTargets.union([peer]))
                let before = overlap
                record("\(name)-unavailable", !overlap.apply(.string(replacement),
                    forPropertyKey: key, unavailableConsumerTargets: [target],
                    retiredScriptCallbackTargets: [target]) && unchanged(overlap, before))
                var absent = state(callbacks: [target], active: producerTargets.subtracting([target]))
                let beforeAbsent = absent
                record("\(name)-inactive", !absent.apply(.string(replacement),
                    forPropertyKey: key, retiredScriptCallbackTargets: [target])
                    && unchanged(absent, beforeAbsent))
                record("\(name)-available", overlap.apply(.string(replacement),
                    forPropertyKey: key, retiredScriptCallbackTargets: [target])
                    && overlap.userValues[target] == .vector3(0.2, 0.4, 0.8)
                    && overlap.revision == 1)
                let beforeInvalid = overlap
                record("\(name)-still-typed", !overlap.apply(.string("bad"),
                    forPropertyKey: key, retiredScriptCallbackTargets: [target])
                    && unchanged(overlap, beforeInvalid))
            }

            // Event-only edits still require at least one surviving consumer.
            let empty = Harness.program(bindings: [])
            var events = ScenePropertyLiveUpdateState(program: empty,
                effectiveValues: [key: .string("1 1 1")], activeConsumerTargets: [live],
                scriptUserPropertyConsumerTargetsByKey: [key: [retired, live]])
            record("live-event-remains", events.apply(.string(replacement), forPropertyKey: key,
                unavailableConsumerTargets: [retired], retiredScriptCallbackTargets: [retired])
                && events.revision == 1 && events.userValues.isEmpty)
            let beforeDeleted = events
            record("all-events-retired-reject-change", !events.apply(.string("0.3 0.5 0.7"),
                forPropertyKey: key, unavailableConsumerTargets: [retired, live],
                retiredScriptCallbackTargets: [retired, live]) && unchanged(events, beforeDeleted))
            record("all-events-retired-allow-noop", events.apply(.string(replacement),
                forPropertyKey: key, unavailableConsumerTargets: [retired, live],
                retiredScriptCallbackTargets: [retired, live]) && unchanged(events, beforeDeleted))
            record("retired-does-not-authorize-unknown", !events.apply(.string("1 1 1"),
                forPropertyKey: "unknown", retiredScriptCallbackTargets: [retired, live])
                && unchanged(events, beforeDeleted))

            let toggle = key + "_enabled"
            let panelOnly = key + "_panel"
            let definitions = [toggle, panelOnly].map { name in
                SceneUserPropertyDefinition(key: name, title: name, kind: .bool,
                    runtimeType: "bool", order: 0, index: nil,
                    minimumValue: nil, maximumValue: nil, stepValue: nil,
                    allowsFractionalValues: false, fractionalPrecision: nil,
                    displayCondition: nil, defaultValue: .bool(true), options: [])
            }
            var boolEvents = ScenePropertyLiveUpdateState(program: empty,
                effectiveValues: [toggle: .bool(true), panelOnly: .bool(true)],
                activeConsumerTargets: [],
                scriptUserPropertyConsumerTargetsByKey: [toggle: [retired]],
                propertyDefinitions: definitions)
            let beforeBool = boolEvents
            record("retired-bool-callback-is-not-unbound", !boolEvents.apply(.bool(false),
                forPropertyKey: toggle, unavailableConsumerTargets: [retired],
                retiredScriptCallbackTargets: [retired]) && unchanged(boolEvents, beforeBool))
            record("retired-bool-resend-noop", boolEvents.apply(.bool(true),
                forPropertyKey: toggle, unavailableConsumerTargets: [retired],
                retiredScriptCallbackTargets: [retired]) && unchanged(boolEvents, beforeBool))
            record("actual-unbound-panel-bool-live", boolEvents.apply(.bool(false),
                forPropertyKey: panelOnly, unavailableConsumerTargets: [retired],
                retiredScriptCallbackTargets: [retired])
                && boolEvents.effectiveValues[panelOnly] == .bool(false)
                && boolEvents.effectiveValues[toggle] == .bool(true)
                && boolEvents.userValues.isEmpty && boolEvents.revision == 1)
        }
        return facts
    }

    private static func unchanged(_ state: ScenePropertyLiveUpdateState,
                                  _ before: ScenePropertyLiveUpdateState) -> Bool {
        state.effectiveValues == before.effectiveValues && state.userValues == before.userValues
            && state.revision == before.revision
    }
}
