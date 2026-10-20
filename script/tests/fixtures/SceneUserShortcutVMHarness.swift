import Foundation

@main enum SceneUserShortcutVMHarness {
    final class NativeProbe: @unchecked Sendable {
        var requests: [(ScenePlaybackShortcutGesture, String)] = []
        let results: [Int32]
        init(_ results: [Int32] = [1]) { self.results = results }
        var dispatch: SceneScriptUserShortcutDispatch {
            { [self] gesture, key in
                requests.append((gesture, key))
                return results[min(requests.count - 1, results.count - 1)]
            }
        }
    }

    static let target = SceneDynamicTarget.layer(layerID: 17, field: .origin)
    static let frame = SceneScriptFrameInput(timing: .init(
        wallDate: Date(timeIntervalSince1970: 0), simulationFrameTime: 0.016, sceneTime: 1))
    static let grant = ScenePlaybackShortcutGesture(
        requestID: UUID(uuidString: "FA17C1A4-AC48-4903-AB3B-F095619AA177")!,
        configurationRevision: 19, gestureID: 71)

    static func make(_ source: String) throws -> (SceneScriptCursorProgram, SceneScriptValueOwner) {
        let domain = try SceneScriptQuickJSDomain()
        try domain.configureLayerCatalog(.init(layers: [.init(
            id: 17, layerIndex: 0, name: "owned button", visible: true,
            originXYZ: [0,0,0], scaleXYZ: [1,1,1], scaleHasScript: nil, alpha: 1, effects: [])]))
        let owner = try SceneScriptValueOwner(domain: domain, source: source, target: target,
            effectNames: [], allowsStatefulLayerSideEffects: true, generation: 1, budget: .default)
        let binding = SceneScriptCursorBinding(layerID: 17, authoredOrdinal: 0, owner: owner,
            events: owner.exportedCursorEvents, ownsOwner: true, scriptProperties: [:],
            ownerSeedValue: .vector3(0,0,0))
        return (.init(bindings: [binding], generation: 1), owner)
    }

    static func sample(_ down: Bool, gesture: ScenePlaybackShortcutGesture?) -> SceneScriptCursorFrameSample {
        let hit = SceneScriptCursorHit(layerID: 17, worldPosition: .zero, localPosition: .zero)
        return .init(hits: [17: hit], pointerPosition: .zero, primaryButtonIsDown: down,
            nativeShortcutGesture: gesture)
    }

    static func dispatch(_ program: SceneScriptCursorProgram,
                         probe: NativeProbe?, gesture: ScenePlaybackShortcutGesture? = grant,
                         samples: [SceneScriptCursorFrameSample]? = nil) -> SceneScriptCursorFrameResult {
        program.dispatch(batch: .init(samples: samples ?? [sample(false, gesture: nil),
            sample(true, gesture: gesture), sample(false, gesture: gesture)], overflowed: false),
            frame: frame, userPropertiesJSON: "{}", userShortcutDispatch: probe?.dispatch)
    }

    static func origin(_ result: SceneScriptCursorFrameResult) -> [Double] {
        guard let value = result.layerMutations.last else { return [] }
        return [value.origin.x, value.origin.y, value.origin.z]
    }

    static func positive(_ key: String, expression: String, result: Int32) throws -> [String: Any] {
        let (program, _) = try make("""
            export function cursorClick(event) {
                const chosen = \(expression);
                const actual = engine.openUserShortcut(chosen);
                thisLayer.origin = new Vec3(actual === true ? 1 : actual === false ? 0 : 9, 2, 3);
            }
            """)
        let probe = NativeProbe([result])
        let output = dispatch(program, probe: probe)
        return ["failures": output.failures.count, "origin": origin(output),
            "calls": probe.requests.count, "keyExact": probe.requests.first?.1 == key,
            "grantExact": probe.requests.first?.0 == grant]
    }

    static func rejection(_ statement: String, gesture: ScenePlaybackShortcutGesture? = grant,
                          native: Bool = true, result: Int32 = 1) throws -> [String: Any] {
        let (program, _) = try make("export function cursorClick(e){ \(statement) }")
        let probe = NativeProbe([result])
        let output = dispatch(program, probe: native ? probe : nil, gesture: gesture)
        return ["failures": output.failures.count, "calls": probe.requests.count,
            "mutations": output.layerMutations.count]
    }

    static func unavailable(gesture: ScenePlaybackShortcutGesture?, native: Bool) throws -> [String: Any] {
        let (program, owner) = try make("""
            export function cursorEnter(e){thisLayer.scale=new Vec3(1.25,1.25,1.25);}
            export function cursorClick(e){
                const result=engine.openUserShortcut('folder');
                thisLayer.origin=new Vec3(result===false?0:9,0,0);
            }
            export function cursorMove(e){
                thisLayer.scale=new Vec3(1,1,1);thisLayer.origin=new Vec3(7,0,0);
            }
            export function update(value){return new Vec3(8,0,0);}
            """)
        let probe = NativeProbe()
        let output = dispatch(program, probe: native ? probe : nil, gesture: gesture)
        program.finalizeLayerMutations(committing: true)
        let hit = SceneScriptCursorHit(layerID: 17, worldPosition: .zero, localPosition: .zero)
        let hover = dispatch(program, probe: native ? probe : nil, samples: [
            .init(hits: [17:hit], pointerPosition: .init(0.25,0), primaryButtonIsDown: false)])
        program.finalizeLayerMutations(committing: true)
        let update = try owner.evaluate(input: .vector3(0,0,0), frame: frame,
            scriptPropertiesJSON: "", userPropertiesJSON: "{}", expectedGeneration: 1,
            interruptBudget: nil).get()
        let scale = hover.layerMutations.last?.scale
        return ["failures": output.failures.count, "origin": origin(output),
            "hoverFailures": hover.failures.count, "hoverOrigin": origin(hover),
            "hoverScale": scale.map { [$0.x,$0.y,$0.z] } ?? [],
            "updateHealthy": update.value == .vector3(8,0,0), "calls": probe.requests.count]
    }

    static func scopes() throws -> [String: Any] {
        var report: [String: Any] = [:]
        for callback in ["cursorEnter", "cursorMove", "cursorLeave"] {
            let (program, _) = try make("""
                export function \(callback)(e) {
                    let caught=false; try {engine.openUserShortcut('folder');}catch(error){caught=true;}
                    thisLayer.origin=new Vec3(caught?4:9,0,0);
                }
                """)
            let probe = NativeProbe()
            let hit = SceneScriptCursorHit(layerID: 17, worldPosition: .zero, localPosition: .zero)
            let samples: [SceneScriptCursorFrameSample] = [
                .init(hits: [17:hit], pointerPosition: .init(0,0), primaryButtonIsDown: false,
                    nativeShortcutGesture: grant),
                .init(hits: [17:hit], pointerPosition: .init(0.5,0), primaryButtonIsDown: false,
                    nativeShortcutGesture: grant),
                .init(hits: [:], pointerPosition: .init(1,0), primaryButtonIsDown: false,
                    nativeShortcutGesture: grant)]
            let output = dispatch(program, probe: probe, samples: samples)
            report[callback] = ["failures": output.failures.count, "calls": probe.requests.count,
                "origin": origin(output)]
        }
        for callback in ["cursorDown", "cursorUp"] {
            let (program, _) = try make("""
                export function \(callback)(e){
                    thisLayer.origin=new Vec3(engine.openUserShortcut('folder')?1:0,0,0);
                }
                """)
            let probe = NativeProbe()
            let output = dispatch(program, probe: probe)
            report[callback] = ["failures": output.failures.count, "calls": probe.requests.count,
                "origin": origin(output), "grantExact": probe.requests.first?.0 == grant]
        }
        let (program, owner) = try make("""
            let retained;
            export function cursorClick(e){retained=engine.openUserShortcut;retained('folder');}
            export function update(value){
                if (!retained) return value;
                try {retained('folder');return new Vec3(9,0,0);}
                catch(error){return new Vec3(5,0,0);}
            }
            """)
        let probe = NativeProbe()
        _ = dispatch(program, probe: probe)
        program.finalizeLayerMutations(committing: true)
        let value = try owner.evaluate(input: .vector3(0,0,0), frame: frame,
            scriptPropertiesJSON: "", userPropertiesJSON: "{}", expectedGeneration: 1,
            interruptBudget: nil).get()
        report["retainedAfterCursor"] = ["value": value.value == .vector3(5,0,0),
            "calls": probe.requests.count]
        let (timerProgram, timerOwner) = try make("""
            export function init(value){
                engine.setTimeout(()=>{try{engine.openUserShortcut('timer');}
                    catch(error){shared.timerDenied=true;}},0); return value;
            }
            export function cursorClick(e){
                thisLayer.origin=new Vec3(engine.openUserShortcut('cursor')?1:0,
                    shared.timerDenied?1:0,0);
            }
            """)
        // The maintained Timer owner advances once per distinct runtime.
        // Initialize earlier so this cursor dispatch actually runs the timer.
        let initialFrame = SceneScriptFrameInput(timing: .init(
            wallDate: Date(timeIntervalSince1970: 0), simulationFrameTime: 0.016, sceneTime: 0))
        _ = try timerOwner.evaluate(input: .vector3(0,0,0), frame: initialFrame,
            scriptPropertiesJSON: "", userPropertiesJSON: "{}", expectedGeneration: 1,
            interruptBudget: nil).get()
        let timerProbe = NativeProbe()
        let timerOutput = dispatch(timerProgram, probe: timerProbe)
        report["dueTimer"] = ["calls": timerProbe.requests.count,
            "keys": timerProbe.requests.map(\.1), "origin": origin(timerOutput),
            "failures": timerOutput.failures.count]
        let (jobProgram, _) = try make("""
            export function cursorClick(e){
                engine.openUserShortcut('cursor');
                Promise.resolve().then(()=>{try{engine.openUserShortcut('job');}
                    catch(error){thisLayer.origin=new Vec3(6,0,0);}});
            }
            """)
        let jobProbe = NativeProbe()
        let jobOutput = dispatch(jobProgram, probe: jobProbe)
        report["laterJob"] = ["calls": jobProbe.requests.count,
            "keys": jobProbe.requests.map(\.1), "origin": origin(jobOutput),
            "failures": jobOutput.failures.count]
        return report
    }

    static func replay() throws -> [String: Any] {
        let (program, _) = try make("""
            export function cursorClick(e){
                thisLayer.origin=new Vec3(engine.openUserShortcut('retained-key')?1:0,0,0);
            }
            """)
        let probe = NativeProbe([1,-1])
        let first = dispatch(program, probe: probe)
        program.finalizeLayerMutations(committing: true, rejectedOwnerTargets: [target])
        let second = dispatch(program, probe: probe, samples: [])
        return ["firstFailures": first.failures.count, "secondFailures": second.failures.count,
            "dispatchCalls": probe.requests.count,
            "capturedGrantRetained": probe.requests.count == 2 && probe.requests.allSatisfy { $0.0 == grant },
            "keys": probe.requests.map(\.1)]
    }

    static func main() throws {
        var output: [String: Any] = [:]
        output["true"] = try positive("local-folder", expression: "('local-'+'folder')", result: 1)
        output["false"] = try positive("renamedPage", expression: "(('renamedPage'))", result: 0)
        output["unicode"] = try positive("快捷项目", expression: "'快捷项目'", result: 1)
        var rejected: [String: Any] = [:]
        for (name, statement) in [
            ("number", "engine.openUserShortcut(1);"),
            ("boxed", "engine.openUserShortcut(new String('folder'));"),
            ("object", "engine.openUserShortcut({toString(){throw new Error('coercion');}});"),
            ("missing", "engine.openUserShortcut();"),
            ("extra", "engine.openUserShortcut('folder','other');")
        ] { rejected[name] = try rejection(statement) }
        rejected["noAdapterWrongType"] = try rejection("engine.openUserShortcut(1);", native: false)
        rejected["hostReject"] = try rejection("engine.openUserShortcut('folder');", result: -1)
        rejected["unknownHostResult"] = try rejection("engine.openUserShortcut('folder');", result: 2)
        rejected["throwAfterDispatch"] = try rejection(
            "engine.openUserShortcut('folder');throw new Error('after native');")
        output["rejected"] = rejected
        output["unavailable"] = [
            "noGesture": try unavailable(gesture: nil, native: true),
            "noAdapter": try unavailable(gesture: grant, native: false)]
        output["scopes"] = try scopes()
        output["pendingReplay"] = try replay()
        let encoded = SceneScriptPropertyInputCodec.userPropertiesJSON(values: [
            "action": .string(""), "renamedAction": .string("author-not-authority"),
            "level": .number(0.25), "enabled": .bool(true), "tint": .string("0.2 0.4 0.6")],
            kinds: ["action": .userShortcut, "renamedAction": .userShortcut,
                    "level": .slider, "enabled": .bool, "tint": .color])
        output["projection"] = try JSONSerialization.jsonObject(with: Data(encoded.utf8))
        output["changedShortcutProjection"] = SceneScriptPropertyInputCodec.changedUserPropertiesJSON(
            previous: ["action": .string("")], current: ["action": .string("new")],
            kinds: ["action": .userShortcut]) as Any? ?? NSNull()
        print(String(decoding: try JSONSerialization.data(withJSONObject: output, options: [.sortedKeys]),
                     as: UTF8.self))
    }
}
