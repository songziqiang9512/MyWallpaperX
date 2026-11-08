import Foundation
import simd

extension SceneDefault2DCameraInputChecks {
    private static let generalZoomTarget = SceneDynamicTarget.camera(.generalZoom)

    private static func generalZoomScene(_ zoom: Any? = nil, variant: Int = 0) -> [String: Any] {
        var scene = root(variant: variant, scripted: false, direct: false)
        scene["camera"] = ["center": "49.04232 -716.01788 -1.00000",
                           "eye": "49.04232 -716.01788 0.00000", "up": "0 1 0"]
        var general = scene["general"] as! [String: Any]
        general["orthogonalprojection"] = ["width": 6080, "height": 3420]
        general["camerapreview"] = true; general["camerafade"] = true
        general["cameraparallax"] = false; general["camerashake"] = false
        general["bloom"] = false; general["hdr"] = false
        general["zoom"] = zoom
        scene["general"] = general
        scene["objects"] = [["id": variant == 0 ? 8 : 808,
            "name": variant == 0 ? "healthy zoom peer" : "renamed independent peer",
            "image": "models/util/solidlayer.json", "origin": "3040 1710 0",
            "size": "486.4 342", "alpha": 0.5]]
        return scene
    }

    private static func generalZoomAnimation() -> [String: Any] {
        var animation = single([[3, 1]], fps: 30, length: 450)
        animation.removeValue(forKey: "relative")
        animation["options"] = ["fps": 30, "length": 450, "mode": "single", "wraploop": NSNull()]
        animation["c0"] = [(0, 3), (300, 3), (450, 1)].map { frame, value in
            ["frame": frame, "value": value, "lockangle": true, "locklength": true,
             "back": ["enabled": true, "x": -1, "y": 0],
             "front": ["enabled": true, "x": 1, "y": 0]] as [String: Any]
        }
        return animation
    }

    private static func generalZoomReachesFrame(_ snapshot: SceneDynamicSnapshot,
                                               in fixture: Fixture, value: Double, manual: Double = 1) -> Bool {
        let camera = fixture.camera(snapshot)
        let point = projected(camera, SIMD3(3344, 1881, 0))
        let effective = Float(value * manual)
        return snapshot.cameraTransform().generalZoom == Float(value)
            && snapshot[zoomTarget]?.value == .scalar(manual)
            && camera.cameraOrigin == .zero
            && near(camera.coverHalfExtents.x * effective, 3040)
            && near(camera.coverHalfExtents.y * effective, 1710)
            && near(point.x, effective * 0.1) && near(point.y, effective * -0.1)
    }

    private static func generalZoomStatics() throws -> [String: Any] {
        var values: [Double] = [], facts: [String: Bool] = [:]
        let cases: [(String, Double?, Double)] = [("absent", nil, 1), ("static", 3, 3),
                                                ("zero", 0, 1), ("negative", -3, 1)]
        for (name, input, expected) in cases {
            let fixture = try Fixture(generalZoomScene(input), key: "unusedZoom")
            let (snapshot, _) = try fixture.frame(sceneTime: 0)
            let authored = input.map { Float($0) }
            let accepted: Float? = expected == 3 ? 3 : nil
            values.append(Double(snapshot.cameraTransform().generalZoom))
            facts[name + "-real-camera"] = generalZoomReachesFrame(snapshot, in: fixture, value: expected)
                && snapshot[zoomTarget]?.source == .authored
                && fixture.timeline.bindings.isEmpty && fixture.scalarProgram.bindings.isEmpty
                && fixture.property.program.instructions.isEmpty
                && fixture.definitions.filter { $0.target == generalZoomTarget }.count == (accepted == nil ? 0 : 1)
                && (accepted == nil ? snapshot[generalZoomTarget] == nil : snapshot[generalZoomTarget]?.source == .authored)
            facts[name + "-authored-fallback"] = fixture.document.general.zoom == authored
                && fixture.descriptor.camera.generalZoom == accepted
        }
        return ["facts": facts, "zooms": values]
    }

    private static func generalZoomTimeline(_ variant: Int) throws -> [String: Any] {
        let hdr = variant == 1
        var scene = generalZoomScene(["value": 3.0, "animation": generalZoomAnimation()], variant: variant)
        var general = scene["general"] as! [String: Any]
        general["hdr"] = hdr; general["bloom"] = true
        general["bloomstrength"] = ["value": 0.35,
            "animation": single([[0.2, 0.8]], fps: 30, length: 450)]
        scene["general"] = general
        let fixture = try Fixture(scene, key: variant == 0 ? "lensScale" : "renamedMagnification")
        let binding = fixture.timeline.bindings.first { $0.target == generalZoomTarget }
        let bloom = SceneDynamicTarget.scene(.bloomStrength)
        var facts: [String: Bool] = [
            "general-timeline-parser-preserved": fixture.document.general.timelines?.contains {
                $0.host == .zoom && $0.animation.options.durationSeconds == 15
            } == true,
            "one-zoom-clock": fixture.timeline.bindings.filter { $0.target == generalZoomTarget }.count == 1
                && binding?.playbackOwnerTarget == generalZoomTarget
                && binding?.animation.options.durationSeconds == 15,
            "hdr-only-limits-bloom": fixture.timeline.bindings.contains { $0.target == bloom } == !hdr
                && (fixture.descriptor.camera.bloom.hdr != nil) == hdr
                && fixture.timeline.diagnostics.contains { $0.hasPrefix("general bloomstrength:") } == hdr,
        ]
        var values: [Double] = []
        for (time, expected) in [(0.0, 3.0), (10, 3), (15, 1), (16, 1)] {
            let (snapshot, _) = try fixture.frame(sceneTime: time)
            values.append(scalar(snapshot[generalZoomTarget]?.value))
            facts["time-\(time)-typed-frame"] = snapshot[generalZoomTarget]?.source == .timeline
                && generalZoomReachesFrame(snapshot, in: fixture, value: expected)
        }
        return ["facts": facts, "zooms": values]
    }

    private static func generalZoomUser(_ variant: Int) throws -> [String: Any] {
        let key = variant == 0 ? "lensScale" : "renamedMagnification"
        let fixture = try Fixture(generalZoomScene(["value": 3.0, "user": key], variant: variant),
                                  key: key, schemaDefault: 2)
        var facts: [String: Bool] = [
            "author-seed-is-not-effective-property": fixture.document.general.zoom == 3
                && fixture.descriptor.camera.generalZoom == 3,
            "direct-user-target": fixture.property.diagnostics.isEmpty
                && fixture.property.program.instructions.map(\.target) == [generalZoomTarget]
                && fixture.property.program.rebuildRequiredPropertyKeys.isEmpty
                && fixture.definitions.filter { $0.target == generalZoomTarget }.count == 1,
        ]
        let (first, _) = try fixture.frame(sceneTime: 0)
        facts["initial-user-reaches-frame"] = first[generalZoomTarget]?.source == .userProperty
            && generalZoomReachesFrame(first, in: fixture, value: 2)
        facts["hot-update-accepted"] = fixture.live.apply(.number(4), forPropertyKey: key)
        let (next, _) = try fixture.frame(sceneTime: 1)
        facts["hot-update-reaches-frame"] = next[generalZoomTarget]?.source == .userProperty
            && generalZoomReachesFrame(next, in: fixture, value: 4)
        let before = fixture.live
        for (index, invalid) in [0.0, -1, 101, .nan, .infinity].enumerated() {
            facts["invalid-user-atomic-\(index)"] = !fixture.live.apply(.number(invalid), forPropertyKey: key)
                && fixture.live.effectiveValues == before.effectiveValues
                && fixture.live.userValues == before.userValues && fixture.live.revision == before.revision
        }
        let (after, _) = try fixture.frame(sceneTime: 2)
        facts["invalid-user-keeps-current-camera"] = generalZoomReachesFrame(after, in: fixture, value: 4)
            && first[generalZoomTarget]?.value == .scalar(2)
        return ["facts": facts, "zooms": [scalar(first[generalZoomTarget]?.value),
            scalar(next[generalZoomTarget]?.value), scalar(after[generalZoomTarget]?.value)]]
    }

    private static func generalZoomScript(_ variant: Int, initialization: Bool) throws -> [String: Any] {
        let input = variant == 0 ? "value" : "initialMagnification"
        let counter = variant == 0 ? "calls" : "completedUpdates"
        let expression = variant == 0 ? "\(input)+1" : "1+(\(input)*2)/2"
        let source: String
        if initialization {
            source = variant == 0
                ? "let \(counter)=0;export function init(\(input)){if(++\(counter)!==1)throw Error('repeated init');return \(expression);}"
                : "let \(counter)=0;function prepare(\(input)){if(++\(counter)!==1)throw Error('repeated init');return \(expression);}export {prepare as init};"
        } else {
            source = variant == 0
                ? "let \(counter)=0;export function update(\(input)){return ++\(counter)+1;}"
                : "let \(counter)=0;function advance(\(input)){\(counter)+=1;return 1+(2*\(counter))/2;}export {advance as update};"
        }
        let fixture = try Fixture(generalZoomScene(["value": 2.0, "script": source], variant: variant),
                                  key: variant == 0 ? "lensScale" : "renamedMagnification")
        let (first, _) = try fixture.frame(sceneTime: 0)
        let (next, _) = try fixture.frame(sceneTime: 1)
        let expected = initialization ? 3.0 : 2.0
        return ["facts": [
            "scene-owner-not-layer-alias": fixture.document.scriptBindings.contains {
                $0.owner.kind == .scene && $0.owner.objectID == nil
                    && $0.targetPath == [.key("general"), .key("zoom")]
            } && fixture.scalarProgram.bindings.map(\.target) == [generalZoomTarget]
                && fixture.vector.bindings.isEmpty && fixture.timeline.bindings.isEmpty,
            "one-typed-zoom-definition": fixture.definitions.filter { $0.target == generalZoomTarget }.count == 1,
            "first-real-camera": first[generalZoomTarget]?.source == .sceneScript
                && generalZoomReachesFrame(first, in: fixture, value: expected),
            "next-real-camera": next[generalZoomTarget]?.source == .sceneScript
                && generalZoomReachesFrame(next, in: fixture, value: 3),
        ], "zooms": [scalar(first[generalZoomTarget]?.value), scalar(next[generalZoomTarget]?.value)]]
    }

    private static func generalZoomScriptFailures() throws -> [String: Bool] {
        var facts: [String: Bool] = [:]
        for (index, ending) in ["throw Error('local zoom failure');", "return 0;", "return NaN;"].enumerated() {
            var scene = generalZoomScene(["value": 2.0, "script": """
                export function init(value){
                    thisScene.getLayerByID(8).alpha=0.2;
                    \(ending)
                }
                """])
            var objects = scene["objects"] as! [[String: Any]]
            objects[0]["alpha"] = ["value": 0.5, "script": "export function update(value){return 0.6;}"]
            scene["objects"] = objects
            let fixture = try Fixture(scene, key: "unusedZoom")
            let (snapshot, _) = try fixture.frame(sceneTime: 0)
            let (next, _) = try fixture.frame(sceneTime: 1)
            facts["failure-\(index)-owner-was-instantiated"] = fixture.scalarProgram.bindings.contains {
                $0.target == generalZoomTarget
            }
            facts["failure-\(index)-local-authored-fallback"] = snapshot[generalZoomTarget]?.source == .authored
                && generalZoomReachesFrame(snapshot, in: fixture, value: 2)
                && generalZoomReachesFrame(next, in: fixture, value: 2)
            facts["failure-\(index)-peer-and-journal"] = snapshot[.layer(layerID: 8, field: .alpha)]?.value == .scalar(0.6)
                && next[.layer(layerID: 8, field: .alpha)]?.source == .sceneScript
                && fixture.layers.snapshot().authoredLayerValues[.layer(layerID: 8, field: .alpha)] == nil
        }
        return facts
    }

    private static func generalZoomRejections() throws -> [String: Bool] {
        var facts: [String: Bool] = [:]
        let script = "export function update(value){return value+1;}"
        var parent = generalZoomAnimation(), child = generalZoomAnimation(), relative = generalZoomAnimation()
        var parentOptions = parent["options"] as! [String: Any]
        parentOptions["parent"] = ["key": "bloomstrength"]; parent["options"] = parentOptions
        var childOptions = child["options"] as! [String: Any]
        childOptions["children"] = [["key": "bloomstrength"]]; child["options"] = childOptions
        relative["relative"] = true
        let cases: [(String, [String: Any])] = [
            ("parent", ["value": 3.0, "animation": parent]),
            ("children", ["value": 3.0, "animation": child]),
            ("relative", ["value": 3.0, "animation": relative]),
            ("animation-script", ["value": 3.0, "animation": generalZoomAnimation(), "script": script]),
            ("animation-user", ["value": 3.0, "animation": generalZoomAnimation(), "user": "lensScale"]),
            ("script-user", ["value": 3.0, "script": script, "user": "lensScale"]),
        ]
        for (name, wrapper) in cases {
            let fixture = try Fixture(generalZoomScene(wrapper), key: "lensScale", schemaDefault: 2)
            let (snapshot, _) = try fixture.frame(sceneTime: 16)
            facts[name + "-not-split-into-independent-producers"] =
                !fixture.timeline.bindings.contains { $0.target == generalZoomTarget }
                && !fixture.scalarProgram.bindings.contains { $0.target == generalZoomTarget }
                && !fixture.property.program.instructions.contains { $0.target == generalZoomTarget }
                && snapshot[generalZoomTarget]?.source == .authored
                && generalZoomReachesFrame(snapshot, in: fixture, value: 3)
            if name != "script-user" {
                facts[name + "-visible-timeline-rejection"] = fixture.timeline.diagnostics.contains {
                    $0.hasPrefix("general zoom:")
                }
            }
            if name == "parent" || name == "children" {
                let options = fixture.document.general.timelines?.first { $0.host == .zoom }?.animation.options
                facts[name + "-parser-keeps-relation"] = name == "parent"
                    ? options?.parent?.key == "bloomstrength"
                    : options?.children.map(\.key) == ["bloomstrength"]
            }
        }
        let incomingCases: [(String, String)] = ["parent", "children"].flatMap { reference in
            ["valid", "fps0", "badmode", "emptylane"].map { (reference, $0) }
        } + [("unrelated", "fps0")]
        for (reference, error) in incomingCases {
            var scene = generalZoomScene(["value": 3.0, "animation": generalZoomAnimation()])
            var general = scene["general"] as! [String: Any]
            var peer = single([[0.2, 0.8]], fps: 30, length: 450)
            var options = peer["options"] as! [String: Any]
            if reference == "parent" { options[reference] = ["key": "zoom"] }
            else if reference == "children" { options[reference] = [["key": "zoom"]] }
            switch error {
            case "fps0": options["fps"] = 0
            case "badmode": options["mode"] = "unknown"
            case "emptylane": peer["c0"] = [] as [Any]
            default: break
            }
            peer["options"] = options
            general["bloomstrength"] = ["value": 0.35, "animation": peer]
            scene["general"] = general
            let fixture = try Fixture(scene, key: "unusedZoom")
            _ = try fixture.frame(sceneTime: 0)
            let (snapshot, _) = try fixture.frame(sceneTime: 16)
            let linked = reference != "unrelated", prefix = "incoming-\(reference)-\(error)"
            facts[prefix + "-keeps-the-affected-clock-boundary"] = fixture.timeline.bindings.map(\.target)
                == (linked ? [] : [generalZoomTarget])
                && snapshot[generalZoomTarget]?.source == (linked ? .authored : .timeline)
                && generalZoomReachesFrame(snapshot, in: fixture, value: linked ? 3 : 1)
                && fixture.timeline.diagnostics.contains { $0.hasPrefix("general zoom:") } == linked
            if error != "valid" {
                facts[prefix + "-keeps-original-peer-parse-error"] =
                    fixture.document.general.timelineDiagnostics?.contains { $0.hasPrefix("bloomstrength:") } == true
                    && fixture.document.general.timelines?.contains { $0.host == .bloomStrength } == false
            }
        }
        for (name, value) in [("static", 3.0 as Any),
                               ("user", ["value": 3.0, "user": "lensScale"]),
                               ("script", ["value": 3.0, "script": script]),
                               ("animation", ["value": 3.0, "animation": generalZoomAnimation()])] {
            var scene = generalZoomScene(value)
            var general = scene["general"] as! [String: Any]
            general.removeValue(forKey: "orthogonalprojection"); scene["general"] = general
            let fixture = try Fixture(scene, key: "lensScale")
            let (snapshot, _) = try fixture.frame(sceneTime: 0)
            facts[name + "-nonorthographic-keeps-old-camera"] = fixture.descriptor.camera.generalZoom == nil
                && hasOnlyAuthoredUnitZoom(snapshot, in: fixture)
                && !fixture.scalarProgram.bindings.contains { $0.target == generalZoomTarget }
                && snapshot[generalZoomTarget] == nil
                && snapshot.cameraTransform().zoom == 1 && snapshot.cameraTransform().generalZoom == 1
        }
        return facts
    }

    private static func generalZoomPathNeighbors(_ variant: Int) throws -> [String: Bool] {
        var facts: [String: Bool] = [:]
        let key = variant == 0 ? "lensScale" : "renamedMagnification"
        let pathID = variant == 0 ? 7 : 709
        for (name, zoom) in [("static", 3.0 as Any),
                              ("animation", ["value": 3.0, "animation": generalZoomAnimation()]),
                              ("user", ["value": 3.0, "user": key]),
                              ("script", ["value": 3.0, "script": "export function update(v){return 3;}"])] {
            var scene = animated(variant, origin: false)
            var general = scene["general"] as! [String: Any]
            general["zoom"] = zoom; scene["general"] = general
            let fixture = try Fixture(scene, key: key, schemaDefault: 4)
            let (first, _) = try fixture.frame(sceneTime: 1)
            let (next, _) = try fixture.frame(sceneTime: 2)
            _ = try fixture.frame(sceneTime: 2, commands: [.init(target: zoomTarget, command: .pause)])
            let (held, _) = try fixture.frame(sceneTime: 3)
            facts[name + "-one-old-path-clock"] = fixture.descriptor.camera.default2DInputLayerID == pathID
                && fixture.descriptor.camera.generalZoom == nil && fixture.timeline.bindings.count == 1
                && fixture.timeline.bindings.first?.target == zoomTarget
                && fixture.timeline.bindings.first?.playbackOwnerTarget == zoomTarget
                && fixture.timeline.bindings.first?.animation.options.durationSeconds == 4
                && !fixture.scalarProgram.bindings.contains { $0.target == zoomTarget }
                && !fixture.property.program.instructions.contains { $0.target == zoomTarget }
                && held[generalZoomTarget] == nil && held.cameraTransform().generalZoom == 1
            facts[name + "-old-path-value-pause-and-frame"] = first[zoomTarget]?.value == .scalar(1.25)
                && next[zoomTarget]?.value == .scalar(1.5) && held[zoomTarget]?.value == .scalar(1.5)
                && held[zoomTarget]?.source == .timeline
                && near(fixture.camera(next).coverHalfExtents.x * 1.5, 1920)
        }
        return facts
    }

    // Late roundtrip and explicit2 outcomes remain project contracts, beyond the qualified official A early phase.
    private static func generalZoomRoundTrip(_ explicitZoom: Bool) throws -> [String: Any] {
        var scene = generalZoomScene(["value": 3.0, "animation": generalZoomAnimation()])
        var objects = scene["objects"] as! [[String: Any]]
        objects[0]["origin"] = ["value": "3040 1710 0", "script": """
            let updates=0;
            export function update(value){
                const c=thisScene.getCameraTransforms();
                const expected=\(explicitZoom ? "updates>0?2:1" : "1");
                if(c.zoom!==expected)throw Error('getter consumed General zoom');
                updates++;
                c.eye=c.eye.add(new Vec3(0,0,0));
                c.center=c.center.add(new Vec3(0,0,0));
                \(explicitZoom ? "c.zoom=2;" : "")
                thisScene.setCameraTransforms(c);
                if(thisScene.getCameraTransforms().zoom!==\(explicitZoom ? "2" : "1"))throw Error('manual readback');
                return value;
            }
            """]
        scene["objects"] = objects
        let fixture = try Fixture(scene, key: "unusedZoom")
        let controller = SceneDynamicTarget.layer(layerID: 8, field: .origin)
        let manual = explicitZoom ? 2.0 : 1.0
        var generals: [Double] = [], manuals: [Double] = []
        var facts: [String: Bool] = [
            "real-layer-origin-owner": fixture.vector.inputTargets == [controller]
                && fixture.scalarProgram.bindings.isEmpty
                && fixture.descriptor.camera.default2DInputLayerID == nil,
            "one-general-clock-and-independent-definitions": fixture.timeline.bindings.map(\.target) == [generalZoomTarget]
                && fixture.definitions.filter { $0.target == generalZoomTarget }.count == 1
                && fixture.definitions.filter { $0.target == zoomTarget }.count == 1,
        ]
        for (index, phase) in [(0.0, 3.0), (10, 3), (15, 1), (16, 1)].enumerated() {
            let (snapshot, evaluation) = try fixture.frame(sceneTime: phase.0)
            let commands = evaluation.ownerEffects.flatMap(\.cameraCommands)
            generals.append(scalar(snapshot[generalZoomTarget]?.value))
            manuals.append(scalar(snapshot[zoomTarget]?.value))
            facts["phase-\(index)-real-getter-and-command"] = evaluation.failures.isEmpty
                && fixture.rejectedOwners.isEmpty && commands.count == 1
                && commands[0].fields.rawValue == 15 && commands[0].zoom == manual
            facts["phase-\(index)-separate-input-sources"] = snapshot[generalZoomTarget]?.source == .timeline
                && snapshot[zoomTarget]?.source == .sceneScript
                && fixture.layers.snapshot().authoredLayerValues[generalZoomTarget] == nil
                && fixture.layers.snapshot().authoredLayerValues[zoomTarget] == .scalar(manual)
            facts["phase-\(index)-relative-camera-frame"] = generalZoomReachesFrame(
                snapshot, in: fixture, value: phase.1, manual: manual)
        }
        return ["facts": facts, "zooms": generals, "manualZooms": manuals]
    }

    static func generalZoom() throws -> [String: Any] {
        ["statics": try generalZoomStatics(),
         "timelines": try [generalZoomTimeline(0), generalZoomTimeline(1)],
         "users": try [generalZoomUser(0), generalZoomUser(1)],
         "initializers": try [generalZoomScript(0, initialization: true), generalZoomScript(1, initialization: true)],
         "updates": try [generalZoomScript(0, initialization: false), generalZoomScript(1, initialization: false)],
         "roundTrips": try [generalZoomRoundTrip(false), generalZoomRoundTrip(true)],
         "failures": try generalZoomScriptFailures(), "rejections": try generalZoomRejections(),
         "paths": try [generalZoomPathNeighbors(0), generalZoomPathNeighbors(1)]]
    }
}
