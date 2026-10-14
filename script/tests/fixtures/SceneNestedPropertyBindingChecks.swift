import Foundation

@main
enum SceneNestedPropertyBindingChecks {
    static func main() throws {
        var facts: [String: Bool] = [:]
        for (key, oldKey, inputName, layerID) in [
            ("formatChoice", "legacyFormat", "format", 282),
            ("captionPattern", "retiredPattern", "style", 904)
        ] {
            positive(key: key, oldKey: oldKey, inputName: inputName,
                     layerID: layerID, depth: 2, facts: &facts)
        }
        positive(key: "primitive", oldKey: "unused", inputName: "pattern",
                 layerID: 51, depth: 1, facts: &facts)
        positive(key: "limit", oldKey: "legacy", inputName: "label",
                 layerID: 52, depth: 16, facts: &facts)
        let repeated: [String: Any] = ["user": "repeat", "value": [
            "user": "retired", "value": ["user": "repeat", "value": "MM|dd"]]]
        let repeatedReport = SceneUserPropertyBindingParser().parse(root: root(
            input: repeated, inputName: "pattern", layerID: 53,
            script: "export function update(value) { return scriptProperties.pattern; }", host: "text"))
        let repeatedCatalog = propertyCatalog(key: "repeat", oldKey: "retired")
        let repeatedProgram = ScenePropertyBindingCompiler().compile(
            report: repeatedReport, catalog: repeatedCatalog).program
        var repeatedState = ScenePropertyLiveUpdateState(program: repeatedProgram,
            effectiveValues: repeatedCatalog.defaultValues,
            activeConsumerTargets: Set(repeatedProgram.instructions.map(\.target)),
            propertyDefinitions: repeatedCatalog.definitions)
        facts["rebound-same-key-single-owner"] = repeatedReport.bindings.count == 1
            && repeatedReport.bindings.first?.reference.key == "repeat"
        facts["rebound-same-key-live"] = !repeatedProgram.rebuildRequiredPropertyKeys.contains("repeat")
            && repeatedState.apply(.string("yyyy-MM"), forPropertyKey: "repeat")
            && repeatedState.revision == 1
        conditionalBooleanChecks(facts: &facts)

        let nested: [String: Any] = ["user": "outer", "value": ["user": "old", "value": "MM|dd"]]
        var extra = nested
        extra["unexpected"] = true
        rejected("extra-provider-field", input: extra, facts: &facts)
        rejected("extra-inner-field", input: ["user": "outer", "value": [
            "user": "old", "value": "MM|dd", "unexpected": true]], facts: &facts)
        rejected("over-depth", input: provider(key: "outer", oldKey: "old", depth: 17), facts: &facts)
        rejected("missing-terminal", input: ["user": "outer", "value": ["user": "old"]], facts: &facts)
        rejected("array-terminal", input: ["user": "outer", "value": ["MM|dd"]], facts: &facts)
        rejected("null-terminal", input: ["user": "outer", "value": NSNull()], facts: &facts)
        rejected("conditional-string", input: ["user": ["name": "outer", "condition": "1"],
                                                "value": "MM|dd"], facts: &facts)
        rejected("missing-script", input: nested, script: nil, facts: &facts)
        rejected("empty-script", input: nested, script: " ", facts: &facts)
        rejected("unsupported-host", input: nested, host: "font", facts: &facts)
        rejected("wrong-default-type", input: nested, defaultValue: 3.0, facts: &facts)
        // A generic nested wrapper is not a new direct-text/resource binding.
        for (host, kind) in [("text", "textinput"), ("image", "scenetexture")] {
            let root: [String: Any] = ["objects": [["id": 61, host: nested]]]
            let catalog = propertyCatalog(key: "outer", oldKey: "old", kind: kind)
            let program = ScenePropertyBindingCompiler().compile(
                report: SceneUserPropertyBindingParser().parse(root: root), catalog: catalog).program
            facts["direct-\(host)-not-flattened"] = program.instructions.isEmpty
                && program.rebuildRequiredPropertyKeys.contains("outer")
        }
        let data = try JSONSerialization.data(withJSONObject: facts, options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }

    static func provider(key: String, oldKey: String, depth: Int) -> [String: Any] {
        var value: Any = "MM|dd"
        for _ in 1..<depth { value = ["user": oldKey, "value": value] }
        return ["user": key, "value": value]
    }

    static func conditionalBooleanChecks(facts: inout [String: Bool]) {
        let catalog = SceneUserPropertyDefinitionParser().parse(properties: [
            "mode": ["type": "combo", "text": "Mode", "value": "off", "options": [
                ["label": "Off", "value": "off"], ["label": "On", "value": "on"]]]
        ])
        for (name, condition, terminal) in [
            ("valid", "on", false as Any),
            ("outside-domain", "other", false as Any),
            ("wrong-terminal", "on", "false" as Any)
        ] {
            let input: [String: Any] = [
                "user": ["name": "mode", "condition": condition],
                "value": ["user": "mode", "value": terminal]]
            let report = SceneUserPropertyBindingParser().parse(root: root(
                input: input, inputName: "selected", layerID: 63,
                script: "export function update(value) { return value; }", host: "text"))
            let program = ScenePropertyBindingCompiler().compile(report: report, catalog: catalog).program
            let targets = Set(program.instructions.map(\.target))
            var state = ScenePropertyLiveUpdateState(program: program,
                effectiveValues: catalog.defaultValues, activeConsumerTargets: targets,
                propertyDefinitions: catalog.definitions)
            if name != "valid" {
                let before = state
                facts["conditional-\(name)-rejected"] = !state.apply(.string("on"), forPropertyKey: "mode")
                    && unchanged(state, before) && program.instructions.isEmpty
                continue
            }
            facts["conditional-bool-single-outer-owner"] = report.bindings.count == 1
                && report.bindings.first?.reference.key == "mode"
                && report.bindings.first?.reference.condition == .string("on")
                && report.bindings.first?.fallbackValue == .bool(false)
            let target = program.instructions.first?.target
            facts["conditional-bool-live-on"] = state.apply(.string("on"), forPropertyKey: "mode")
                && target.map { state.userValues[$0] == .bool(true) } == true && state.revision == 1
            let selected = state
            facts["conditional-bool-domain-atomic"] = !state.apply(.string("other"), forPropertyKey: "mode")
                && unchanged(state, selected)
            facts["conditional-bool-type-atomic"] = !state.apply(.number(1), forPropertyKey: "mode")
                && unchanged(state, selected)
            if let raw = SceneJSONValue(jsonObject: input),
               let codec = SceneScriptPropertyInputCodec.propertyInput(raw) {
                facts["conditional-bool-runtime-input"] = codec.userPropertyKey == "mode"
                    && codec.resolve(effectiveValues: state.effectiveValues) == .bool(true)
            } else { facts["conditional-bool-runtime-input"] = false }
            facts["conditional-bool-live-off"] = state.apply(.string("off"), forPropertyKey: "mode")
                && target.map { state.userValues[$0] == .bool(false) } == true && state.revision == 2
        }
    }

    static func propertyCatalog(key: String, oldKey: String, kind: String = "textinput",
                                defaultValue: Any = "HH:mm") -> SceneUserPropertyCatalog {
        SceneUserPropertyDefinitionParser().parse(properties: [
            key: ["type": kind, "value": defaultValue, "text": "Pattern"],
            oldKey: ["type": "textinput", "value": "ignored", "text": "Retired"]
        ])
    }

    static func root(input: Any, inputName: String, layerID: Int,
                     script: String?, host: String) -> [String: Any] {
        var wrapper: [String: Any] = ["value": "Text", "scriptproperties": [inputName: input]]
        if let script { wrapper["script"] = script }
        return ["objects": [["id": layerID, host: wrapper]]]
    }

    static func positive(key: String, oldKey: String, inputName: String, layerID: Int,
                         depth: Int, facts: inout [String: Bool]) {
        let input = provider(key: key, oldKey: oldKey, depth: depth)
        let document = root(input: input, inputName: inputName, layerID: layerID,
                            script: "export function update(value) { return scriptProperties.\(inputName); }",
                            host: "text")
        let catalog = propertyCatalog(key: key, oldKey: oldKey)
        let report = SceneUserPropertyBindingParser().parse(root: document)
        facts[key + "-single-outer-binding"] = report.bindings.count == 1
            && report.bindings.first?.reference.key == key
        let binding = report.bindings.first { $0.reference.key == key }
        facts[key + "-terminal-fallback"] = binding?.fallbackValue == .string("MM|dd")
        let program = ScenePropertyBindingCompiler().compile(report: report, catalog: catalog).program
        facts[key + "-outer-instruction"] = program.instructions.count == 1
            && program.instructions.first?.propertyKey == key
            && !program.rebuildRequiredPropertyKeys.contains(key)
        guard let binding, case let .scriptProperty(id, path) = binding.target else {
            facts[key + "-real-script-target"] = false
            return
        }
        let target = SceneDynamicTarget.scriptInstanceProperty(layerID: id, path: path)
        var state = ScenePropertyLiveUpdateState(program: program,
            effectiveValues: catalog.defaultValues, activeConsumerTargets: [target],
            propertyDefinitions: catalog.definitions)
        let changed = state.apply(.string("yyyy-MM"), forPropertyKey: key)
        facts[key + "-live-edit"] = changed && state.revision == 1
            && state.userValues[target] == .string("yyyy-MM")
            && state.effectiveValues[key] == .string("yyyy-MM")
            && state.effectiveValues[oldKey] == .string("ignored")
        let before = state
        facts[key + "-wrong-type-atomic"] = !state.apply(.number(7), forPropertyKey: key)
            && unchanged(state, before)
        facts[key + "-old-provider-not-owner"] = !state.apply(.string("old"), forPropertyKey: oldKey)
            && unchanged(state, before)
        facts[key + "-unavailable-owner-atomic"] = !state.apply(
            replacements: [key: .string("ss")], changedPropertyKeys: [key],
            unavailableConsumerTargets: [target]) && unchanged(state, before)
        var noOwner = ScenePropertyLiveUpdateState(program: program,
            effectiveValues: catalog.defaultValues, activeConsumerTargets: [],
            propertyDefinitions: catalog.definitions)
        facts[key + "-missing-owner-rejected"] = !noOwner.apply(.string("ss"), forPropertyKey: key)
            && noOwner.revision == 0
        if let raw = SceneJSONValue(jsonObject: input),
           let codecInput = SceneScriptPropertyInputCodec.propertyInput(raw),
           let json = SceneScriptPropertyInputCodec.scriptPropertiesJSON(
               [inputName: codecInput], effectiveValues: state.effectiveValues),
           let data = json.data(using: .utf8),
           let output = try? JSONSerialization.jsonObject(with: data) as? [String: String] {
            facts[key + "-runtime-input-json"] = output[inputName] == "yyyy-MM"
                && codecInput.userPropertyKey == key && codecInput.fallback == .string("MM|dd")
        } else { facts[key + "-runtime-input-json"] = false }
    }

    static func rejected(_ name: String, input: Any, script: String? = "export function update(value) { return value; }",
                         host: String = "text", defaultValue: Any = "HH:mm",
                         facts: inout [String: Bool]) {
        let report = SceneUserPropertyBindingParser().parse(root: root(
            input: input, inputName: "pattern", layerID: 62, script: script, host: host))
        let catalog = propertyCatalog(key: "outer", oldKey: "old", defaultValue: defaultValue)
        let program = ScenePropertyBindingCompiler().compile(report: report, catalog: catalog).program
        let targets = Set(program.instructions.map(\.target))
        var state = ScenePropertyLiveUpdateState(program: program,
            effectiveValues: catalog.defaultValues, activeConsumerTargets: targets,
            propertyDefinitions: catalog.definitions)
        let before = state
        facts[name + "-rejected"] = !state.apply(.string("yyyy"), forPropertyKey: "outer")
            && unchanged(state, before) && program.instructions.isEmpty
    }

    static func unchanged(_ value: ScenePropertyLiveUpdateState,
                          _ before: ScenePropertyLiveUpdateState) -> Bool {
        value.effectiveValues == before.effectiveValues && value.userValues == before.userValues
            && value.revision == before.revision
    }
}
