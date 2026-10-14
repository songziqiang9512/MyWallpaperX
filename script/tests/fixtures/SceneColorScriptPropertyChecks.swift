@main
enum SceneColorScriptPropertyChecks {
    static let edited = "0.25 0.5 0.75"
    static let frame = SceneScriptFrameInput(timing: .init(
        wallDate: Date(timeIntervalSince1970: 0), simulationFrameTime: 1 / 60, sceneTime: 1))

    static func main() throws {
        var facts: [String: Bool] = [:]
        // Same Color input domain, different actual builder values. Native
        // vector3 validation must never determine the VM slot's runtime type.
        for (name, key, slot, layerID, host, builder, body, tail) in [
            ("color", "color", "textColor_chTime", 31, "visible", "addColor", vec3Body, 0.75),
            ("renamed", "accentTone", "ink", 908, "origin", "addColor", vec3Body, 0.75),
            ("text", "rgbText", "caption", 42, "origin", "addText", stringBody, 0.75),
            ("vec2", "palette", "coordinates", 65, "origin", "addText", vec2Body, 7.0)
        ] {
            try positive(name: name, key: key, slot: slot, layerID: layerID,
                         host: host, builder: builder, body: body, tail: tail, facts: &facts)
        }
        for (name, fallback, defaultValue) in [
            ("two-components", "0.1 0.2" as Any, "1 1 1" as Any),
            ("extra-components", "0.1 0.2 0.3 0.4", "1 1 1"),
            ("nonfinite-fallback", "0.1 nan 0.3", "1 1 1"),
            ("wrong-fallback-type", 1.0, "1 1 1"),
            ("invalid-default", "0.1 0.2 0.3", "red"),
            ("nonfinite-default", "0.1 0.2 0.3", "1 inf 1"),
            ("wrong-default-type", "0.1 0.2 0.3", 1.0)
        ] {
            let document = root(layerID: 70, host: "origin", slot: "tint",
                input: ["user": "tone", "value": fallback], source: "export function update(v){return v;}")
            let catalog = catalog(key: "tone", value: defaultValue)
            let program = ScenePropertyBindingCompiler().compile(
                report: SceneUserPropertyBindingParser().parse(root: document), catalog: catalog).program
            var state = ScenePropertyLiveUpdateState(program: program,
                effectiveValues: catalog.defaultValues,
                activeConsumerTargets: Set(program.instructions.map(\.target)))
            let before = state
            facts[name + "-not-admitted"] = program.instructions.isEmpty
                && program.rebuildRequiredPropertyKeys.contains("tone")
                && !state.apply(.string(edited), forPropertyKey: "tone") && unchanged(state, before)
        }
        let encoded = try JSONSerialization.data(withJSONObject: facts, options: [.sortedKeys])
        print(String(decoding: encoded, as: UTF8.self))
    }

    static let vec3Body = """
        if (!(c instanceof Vec3) || c instanceof Vec2) throw new Error('Vec3 type changed');
        const p = new Vec3(c.x, c.y, c.z);
        """
    static let stringBody = """
        if (typeof c !== 'string') throw new Error('String type changed');
        const parts = c.split(/\\s+/).map(Number);
        const p = new Vec3(parts[0], parts[1], parts[2]);
        """
    static let vec2Body = """
        if (!(c instanceof Vec2) || c instanceof Vec3 || 'z' in c) throw new Error('Vec2 type changed');
        const p = new Vec3(c.x, c.y, 7);
        """

    static func positive(name: String, key: String, slot: String, layerID: Int,
                         host: String, builder: String, body: String, tail: Double,
                         facts: inout [String: Bool]) throws {
        let seed = name == "text" ? "'builder text'" : name == "vec2" ? "new Vec2(0, 0)" : "new Vec3(0, 0, 0)"
        let source = """
            export var scriptProperties = createScriptProperties()
                ['\(builder)']({name: '\(slot)', value: \(seed)}).finish();
            export function update(value) {
                const c = scriptProperties['\(slot)'];
                \(body)
                if (p.x === 0.9) throw new Error('controlled owner failure');
                \(host == "visible" ? "shared.currentTone = c; return p.x < 0.5;" : "return p;")
            }
            """
        let input: [String: Any] = ["user": key, "value": "0.1 0.2 0.3"]
        let document = root(layerID: layerID, host: host, slot: slot, input: input, source: source)
        let catalog = catalog(key: key)
        let report = SceneUserPropertyBindingParser().parse(root: document)
        let compilation = ScenePropertyBindingCompiler().compile(report: report, catalog: catalog)
        let program = compilation.program
        facts[name + "-parsed-color-string"] = report.bindings.count == 1
            && report.bindings.first?.reference.key == key
            && report.bindings.first?.fallbackValue == .string("0.1 0.2 0.3")
        facts[name + "-native-color-domain"] = compilation.diagnostics.isEmpty
            && program.instructions.count == 1 && program.instructions.first?.valueType == .vector3
            && !program.rebuildRequiredPropertyKeys.contains(key)
        let scripts = SceneScriptBindingIRParser.parse(document: document)
        let descriptor = descriptor(layerID: layerID)
        let runtime = SceneScriptVectorProgram.compile(domain: try SceneScriptQuickJSDomain(),
            descriptor: descriptor, scriptBindings: scripts.bindings,
            userPropertyDefinitions: catalog.definitions, generation: 1)
        let output: SceneDynamicTarget = .layer(layerID: layerID,
            field: host == "visible" ? .visibility : .origin)
        let seedValue: SceneDynamicValue = host == "visible" ? .bool(true) : .vector3(0, 0, 0)
        let liveTargets = runtime.activeLivePropertyInputTargets
        facts[name + "-actual-prepared-owner"] = scripts.diagnostics.isEmpty
            && runtime.bindings.count == 1 && runtime.inputTargets.contains(output)
            && liveTargets.count == 1
        var state = ScenePropertyLiveUpdateState(program: program,
            effectiveValues: catalog.defaultValues, activeConsumerTargets: liveTargets,
            propertyDefinitions: catalog.definitions)
        let cold = runtime.evaluate(inputs: [output: seedValue],
            effectivePropertyValues: state.effectiveValues, frame: frame, propertyRevision: state.revision)
        let coldExpected: SceneDynamicValue = host == "visible" ? .bool(false)
            : .vector3(1, 1, name == "vec2" ? 7 : 1)
        facts[name + "-cold-vm-type-retained"] = cold.failures.isEmpty && cold.values[output] == coldExpected
        facts[name + "-live-apply"] = state.apply(.string(edited), forPropertyKey: key)
            && state.revision == 1 && state.effectiveValues[key] == .string(edited)
            && program.instructions.first.map { state.userValues[$0.target] == .vector3(0.25, 0.5, 0.75) } == true
        let hot = runtime.evaluate(inputs: [output: seedValue],
            effectivePropertyValues: state.effectiveValues, frame: frame, propertyRevision: state.revision)
        let hotExpected: SceneDynamicValue = host == "visible" ? .bool(true) : .vector3(0.25, 0.5, tail)
        facts[name + "-hot-vm-type-and-value-retained"] = hot.failures.isEmpty && hot.values[output] == hotExpected
        if let raw = SceneJSONValue(jsonObject: input),
           let codec = SceneScriptPropertyInputCodec.propertyInput(raw),
           let json = SceneScriptPropertyInputCodec.scriptPropertiesJSON(
               [slot: codec], effectiveValues: state.effectiveValues),
           let data = json.data(using: .utf8),
           let values = try JSONSerialization.jsonObject(with: data) as? [String: String] {
            facts[name + "-wire-stays-string"] = values == [slot: edited]
        } else { facts[name + "-wire-stays-string"] = false }
        let before = state
        for (invalidName, value) in [
            ("short", SceneUserPropertyValue.string("0.2 0.3")),
            ("long", .string("0.2 0.3 0.4 0.5")), ("nan", .string("nan 0 0")),
            ("infinity", .string("0 0 inf")), ("word", .string("blue")),
            ("number", .number(2)), ("bool", .bool(true))
        ] {
            facts[name + "-" + invalidName + "-atomic"] = !state.apply(value, forPropertyKey: key)
                && unchanged(state, before)
        }
        facts[name + "-missing-value-atomic"] = !state.apply(
            replacements: [:], changedPropertyKeys: [key]) && unchanged(state, before)
        let absentRuntime = SceneScriptVectorProgram.compile(domain: nil, descriptor: descriptor,
            scriptBindings: scripts.bindings, userPropertyDefinitions: catalog.definitions, generation: 2)
        var missing = ScenePropertyLiveUpdateState(program: program,
            effectiveValues: catalog.defaultValues, activeConsumerTargets: absentRuntime.activeLivePropertyInputTargets)
        let missingBefore = missing
        facts[name + "-missing-owner-atomic"] = absentRuntime.activeLivePropertyInputTargets.isEmpty
            && !missing.apply(.string(edited), forPropertyKey: key) && unchanged(missing, missingBefore)
        // A real QuickJS exception disables this owner. Feed the resulting
        // unavailable targets into the same atomic guard used by the Host.
        let failed = runtime.evaluate(inputs: [output: seedValue],
            effectivePropertyValues: [key: .string("0.9 0.2 0.3")], frame: frame,
            propertyRevision: state.revision + 1)
        let unavailable = liveTargets.subtracting(runtime.activeLivePropertyInputTargets)
        facts[name + "-disabled-owner-atomic"] = failed.failures[output] != nil
            && runtime.disabledTargets.contains(output) && unavailable == liveTargets && !unavailable.isEmpty
            && !state.apply(.string("0.4 0.5 0.6"), forPropertyKey: key,
                            unavailableConsumerTargets: unavailable) && unchanged(state, before)
    }

    static func root(layerID: Int, host: String, slot: String, input: Any, source: String) -> [String: Any] {
        ["objects": [["id": layerID, host: ["script": source,
            "value": host == "visible" ? true as Any : "0 0 0" as Any,
            "scriptproperties": [slot: input]]]]]
    }

    static func catalog(key: String, value: Any = "1 1 1") -> SceneUserPropertyCatalog {
        SceneUserPropertyDefinitionParser().parse(properties: [
            key: ["type": "color", "text": "Color", "value": value]])
    }

    static func descriptor(layerID: Int) -> SceneRenderDescriptor {
        .init(layers: [.init(id: layerID, layerIndex: 0, name: "controlled color consumer",
            visible: true, originXYZ: [0, 0, 0], scaleXYZ: [1, 1, 1], alpha: 1, effects: [])])
    }

    static func unchanged(_ state: ScenePropertyLiveUpdateState, _ before: ScenePropertyLiveUpdateState) -> Bool {
        state.effectiveValues == before.effectiveValues && state.userValues == before.userValues
            && state.revision == before.revision
    }
}
