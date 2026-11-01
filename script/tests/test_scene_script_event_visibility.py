#!/usr/bin/env python3
"""Event setter intent survives callbacks, owner admission and runtime commit."""
from __future__ import annotations

import json
from pathlib import Path
import subprocess
import tempfile
import unittest

from .scene_vector_vm_test_support import SCENE, SWIFT_PREAMBLE, compile_vector_harness
from .test_scene_prepared_script_resource_catalog import swift_declaration


# Data-only adapter for the shared VM fixture's descriptor carrier. Validation
# and prepared image construction below come unchanged from the production owner.
LAYER_CARRIER = r'''
extension SceneRenderDescriptor.Layer {
    init(id: Int, layerIndex: Int, name: String?, cameraPath: SceneRenderDescriptor.CameraPath?,
         contentKind: String, imagePath: String?, imageMaterialRenderState: SceneMaterialRenderState?,
         usesPerspective: Bool?, particlePath: String?, spotLight: Int?,
         particleInstanceOverride: SceneParticleInstanceOverride?, utilityLayer: SceneUtilityLayer?,
         dependencyLayerIDs: [Int], authoredDependencies: [Int], parentID: Int?, childLayerIDs: [Int],
         attachmentName: String?, parentAttachmentBindFrame: [Float]?,
         puppetAnimationLayers: [ScenePuppetAnimationLayer], solid: Bool, visible: Bool, alpha: Double,
         displayScriptOwnership: SceneLayerDisplayScriptOwnership?, colorRGB: [Float],
         colorBlendMode: Int?, brightness: Double?, imageAlignment: String?, origin: String?,
         size: String?, scale: String?, scaleHasScript: Bool, angles: String?, originXYZ: [Float],
         sizeWH: [Float], scaleXYZ: [Float], anglesXYZ: [Float], parallaxDepthXY: [Float],
         disablesParallaxPropagation: Bool, timelines: [SceneDocument.SceneObjectTimeline],
         timelineDiagnostics: [String], particleTimelines: [Int], particleTimelineDiagnostics: [String],
         modelCropOffsetXY: [Float]?, puppetMeshPath: String?, text: String?,
         textStyle: SceneRenderDescriptor.TextStyle?,
         scriptBindings: [SceneScriptBindingDefinition]?, textureAnimationScripts: [Int]?,
         hasInlineScript: Bool, effects: [SceneRenderDescriptor.EffectDescriptor],
         effectFiles: [String], texturePaths: [String]) {
        self.init(cameraPath: cameraPath, id: id, layerIndex: layerIndex, name: name, solid: solid,
            usesPerspective: usesPerspective, visible: visible, originXYZ: originXYZ,
            scaleXYZ: scaleXYZ, anglesXYZ: anglesXYZ, colorRGB: colorRGB,
            scaleHasScript: scaleHasScript, alpha: alpha, brightness: brightness, effects: effects,
            contentKind: contentKind, particleInstanceOverride: particleInstanceOverride,
            text: text, textStyle: textStyle, sizeWH: sizeWH,
            imagePath: imagePath, puppetMeshPath: puppetMeshPath, spotLight: spotLight,
            utilityLayer: utilityLayer, parentID: parentID, childLayerIDs: childLayerIDs,
            dependencyLayerIDs: dependencyLayerIDs, authoredDependencies: authoredDependencies,
            effectFiles: effectFiles, parallaxDepthXY: parallaxDepthXY,
            attachmentName: attachmentName, parentAttachmentBindFrame: parentAttachmentBindFrame,
            puppetAnimationLayers: puppetAnimationLayers)
        self.displayScriptOwnership = displayScriptOwnership
        self.imageMaterialRenderState = imageMaterialRenderState
    }
}
'''

HARNESS = r'''
@main enum Harness {
    static let target = SceneDynamicTarget.layer(layerID: 7, field: .visibility)
    static let origin = SceneDynamicTarget.layer(layerID: 7, field: .origin)
    static let property = SceneUserPropertyDefinition(
        key: "invert", title: "Invert", kind: .bool, runtimeType: "bool",
        order: 0, index: nil, minimumValue: nil, maximumValue: nil,
        stepValue: nil, allowsFractionalValues: false, fractionalPrecision: nil,
        displayCondition: nil, defaultValue: .bool(false), options: [])

    final class Context {
        let scene: SceneRenderDescriptor
        let program: SceneScriptVectorProgram
        let runtime: SceneScriptDynamicLayerRuntime
        let index: SceneDynamicSnapshotDefinitionIndex
        var frameIndex: UInt64 = 0

        init(_ source: String) throws {
            var layer = SceneRenderDescriptor.Layer(
                id: 7, layerIndex: 0, name: "event-leaf", visible: false,
                originXYZ: [0, 0, 0], scaleXYZ: [1, 1, 1], alpha: 1,
                effects: [], contentKind: "image")
            layer.displayScriptOwnership = .init(visible: true, alpha: false)
            scene = .init(layers: [layer])
            let binding = SceneScriptBindingIR(source: source,
                owner: .init(kind: .object, objectIndex: 0, objectID: 7,
                    effectIndex: nil, effectID: nil, passIndex: nil, passID: nil),
                targetPath: [.key("objects"), .index(0), .key("visible")],
                properties: [:], authoredValue: .bool(false), valueType: .boolean,
                wrapperKeys: ["script", "value"])
            program = SceneScriptVectorProgram.compile(
                domain: try SceneScriptQuickJSDomain(), descriptor: scene,
                scriptBindings: [binding], userPropertyDefinitions: [property], generation: 71)
            precondition(program.definitions.count == 1)
            runtime = .init(descriptor: scene, authoredMutationLayerIDs: [7])
            var definitions = program.definitions
            let targets = Set(definitions.map(\.target))
            definitions += runtime.authoredLayerDefinitions.filter { !targets.contains($0.target) }
            index = SceneDynamicSnapshotResolver.prepare(definitions: definitions)
        }

        func resolve(_ values: [SceneDynamicTarget: SceneDynamicValue],
                     user: [SceneDynamicTarget: SceneDynamicValue]) -> SceneDynamicSnapshotResolution {
            SceneDynamicSnapshotResolver().resolve(frameIndex: frameIndex, generation: 71,
                index: index, userValues: user, sceneScriptValues: values)
        }

        // These are the frame driver's public producers and commit order:
        // committed setters -> typed input -> real VM -> owner admission ->
        // typed output -> runtime/owner commit. No cached VM value is used to
        // hide loss of the event setter during an idle frame.
        func step(invert: Bool, revision: UInt64, time: Double,
                  userVisibility: Bool? = nil, reject: Bool = false) throws -> [String: Any] {
            frameIndex += 1
            let user: [SceneDynamicTarget: SceneDynamicValue] = userVisibility.map {
                [target: .bool($0)]
            } ?? [:]
            let committed = runtime.snapshot().authoredLayerValues
            let preliminary = resolve(committed, user: user)
            try program.domain?.publishLayerSnapshot(preliminary.snapshot, descriptor: scene)
            let before = program.frameStateSnapshot()
            let result = program.evaluate(
                inputs: preliminary.snapshot.typedValues(for: program.inputTargets,
                    valueTypes: program.inputValueTypes),
                effectivePropertyValues: ["invert": .bool(invert)],
                frame: .init(timing: .init(wallDate: Date(timeIntervalSince1970: 0),
                    simulationFrameTime: 1 / 60, sceneTime: time)), propertyRevision: revision)
            let admission = runtime.preflightOwnerEffectsToFixedPoint(
                result.ownerEffects, excludingOwners: Set(result.failures.keys)) { effects, _ in
                    reject ? Set(effects.map(\.ownerTarget)) : []
                }
            let rejected = admission.externallyRejectedOwners.union(
                admission.admission.rejectedOwners.compactMap(\.ownerTarget))
            var accepted = committed
            accepted.merge(result.values.filter { !rejected.contains($0.key) }) { _, current in current }
            let output = resolve(accepted, user: user)
            runtime.commit(admission.admission.layerPlan)
            if !rejected.isEmpty { program.restoreFrameState(before, rejectedOwnerTargets: rejected) }
            program.finalizeLayerMutations(committing: true, rejectedOwnerTargets: rejected)
            let state = runtime.snapshot().authoredLayerValues
            let visible = output.snapshot[target]?.value == .bool(true)
            var row: [String: Any] = [
                "visible": visible,
                "consumerVisible": SceneLayerVisibility.visibleLayerIDs(
                    in: scene, snapshot: output.snapshot).contains(7),
                "values": result.values.count, "effects": result.ownerEffects.count,
                "mutations": result.layerMutations.count, "failures": result.failures.count,
                "failureCode": result.failures[target]?.code ?? "none",
                "diagnostics": output.diagnostics.count, "rejected": rejected.contains(target),
                "persistentVisibility": state[target].map { $0 == .bool(true) } as Any? ?? NSNull(),
                "ownVisibilityWrites": result.layerMutations.filter {
                    $0.layerID == 7 && $0.fields.contains(.visibility)
                }.count]
            if case let .vector3(x, _, _)? = state[origin] { row["callbackCount"] = x }
            else { row["callbackCount"] = NSNull() }
            return row
        }
    }

    static let eventSource = """
        let calls = 0;
        export function applyUserProperties(properties) {
            calls += 1;
            thisLayer.origin = new Vec3(calls, 0, 0);
            if (Object.prototype.hasOwnProperty.call(properties, 'invert')) {
                thisLayer.visible = !properties.invert;
            }
        }
        """

    static func setterIntentCases() throws -> [String: Any] {
        let frame = SceneScriptFrameInput(timing: .init(wallDate: Date(timeIntervalSince1970: 0),
            simulationFrameTime: 1 / 60, sceneTime: 1))
        func scene(_ id: Int, _ name: String, visible: Bool = true,
                   kind: String = "text", perspective: Bool? = nil) -> SceneRenderDescriptor {
            .init(layers: [.init(id: id, layerIndex: 0, name: name, usesPerspective: perspective, visible: visible,
                originXYZ: [0, 0, 0], scaleXYZ: [1, 1, 1], alpha: 1, effects: [],
                contentKind: kind, text: "seed", textStyle: .init(fontPath: "Arial",
                    colorRGB: nil, pointSize: 32))])
        }
        func owner(_ domain: SceneScriptQuickJSDomain, _ id: Int, _ source: String,
                   field: SceneDynamicLayerField = .origin) throws -> SceneScriptValueOwner {
            try .init(domain: domain, source: source, target: .layer(layerID: id, field: field),
                valueType: .vector3, effectNames: [], allowsStatefulLayerSideEffects: true,
                generation: 1, budget: .default)
        }
        func evaluate(_ owner: SceneScriptValueOwner) throws -> SceneScriptValueEvaluation {
            try owner.evaluate(input: .vector3(0, 0, 0), frame: frame, scriptPropertiesJSON: "",
                userPropertiesJSON: "{}", expectedGeneration: 1, interruptBudget: nil).get()
        }
        func effects(_ owner: SceneScriptValueOwner, _ value: SceneScriptValueEvaluation) -> SceneScriptOwnerEffects {
            var effects = SceneScriptOwnerEffects(ownerTarget: owner.target, materialFunctionMutations: [],
                animationMutations: [], layerMutations: [], mediaPlaybackCommands: [])
            effects.append(value)
            return effects
        }
        func snapshot(_ runtime: SceneScriptDynamicLayerRuntime,
                      _ values: [SceneDynamicTarget: SceneDynamicValue]) -> SceneDynamicSnapshot {
            SceneDynamicSnapshotResolver().resolve(frameIndex: 0, generation: 1,
                definitions: runtime.authoredLayerDefinitions, sceneScriptValues: values).snapshot
        }
        var baselines: [[String: Any]] = [], callbacks: [[String: Any]] = []
        var interleaved: [[String: Any]] = [], immediate: [[String: Any]] = []
        var returnFallback: [[String: Any]] = []
        var perspectiveAdmission: [[String: Any]] = []
        let fields: [(String, SceneScriptLayerMutation.Fields)] = [
            ("origin", .origin), ("scale", .scale), ("angles", .angles),
            ("perspective", .perspective), ("visible", .visibility), ("solid", .solid),
            ("text", .text), ("font", .font), ("alpha", .alpha), ("color", .color),
            ("pointsize", .pointSize)]
        for (id, name, named) in [(7, "event-leaf", false), (27, "renamed-author", true)] {
            let destination = named ? "thisScene.getLayer('\(name)')" : "thisLayer"
            for (property, field) in fields {
                let descriptor = scene(id, name)
                let runtime = SceneScriptDynamicLayerRuntime(descriptor: descriptor, authoredMutationLayerIDs: [id])
                let domain = try SceneScriptQuickJSDomain()
                try domain.publishLayerSnapshot(snapshot(runtime, [:]), descriptor: descriptor)
                let writer = try owner(domain, id, "export function update(v){const ref=\(destination);ref['\(property)']=ref['\(property)'];return v;}")
                let value = try evaluate(writer)
                baselines.append(["name": name, "field": property, "mutationCount": value.layerMutations.count,
                    "recorded": value.layerMutations.contains { $0.layerID == id && $0.fields.contains(field) }])
                writer.discardLayerMutations()
            }
            for writes in [true, false] {
                let descriptor = scene(id, name)
                let runtime = SceneScriptDynamicLayerRuntime(descriptor: descriptor, authoredMutationLayerIDs: [id])
                let domain = try SceneScriptQuickJSDomain()
                try domain.publishLayerSnapshot(snapshot(runtime, [:]), descriptor: descriptor)
                let operation = writes ? "ref.origin=ref.origin;" : "const observed=ref.origin;"
                let writer = try owner(domain, id, "export function update(v){const ref=\(destination);\(operation)return 'text-payload';}")
                var row: [String: Any] = ["name": name, "writes": writes]
                switch writer.evaluate(input: .vector3(0, 0, 0), frame: frame,
                    scriptPropertiesJSON: "", userPropertiesJSON: "{}", expectedGeneration: 1, interruptBudget: nil) {
                case let .success(value):
                    row["accepted"] = true
                    row["keptTypedInput"] = value.value == .vector3(0, 0, 0)
                    row["ownSetter"] = value.layerMutations.contains { $0.layerID == id && $0.fields.contains(.origin) }
                case let .failure(failure):
                    row["accepted"] = false
                    row["failure"] = failure.code
                }
                row["retainedMutations"] = mwx_scene_quickjs_owner_layer_mutation_count(writer.handle)
                returnFallback.append(row)
                writer.discardLayerMutations()
            }
            for initial in [true, false] {
                let descriptor = scene(id, name, visible: initial)
                let runtime = SceneScriptDynamicLayerRuntime(descriptor: descriptor, authoredMutationLayerIDs: [id])
                let domain = try SceneScriptQuickJSDomain()
                let source = "export function mediaThumbnailChanged(e){\(destination).visible=\(initial ? "false" : "true");}export function update(v){\(destination).visible=\(initial ? "true" : "false");return v;}"
                let binding = SceneScriptBindingIR(source: source,
                    owner: .init(kind: .object, objectIndex: 0, objectID: id,
                        effectIndex: nil, effectID: nil, passIndex: nil, passID: nil),
                    targetPath: [.key("objects"), .index(0), .key("origin")], properties: [:],
                    authoredValue: .string("0 0 0"), valueType: .string, wrapperKeys: ["script", "value"])
                let program = SceneScriptVectorProgram.compile(domain: domain, descriptor: descriptor,
                    scriptBindings: [binding], userPropertyDefinitions: [], generation: 1)
                try domain.publishLayerSnapshot(snapshot(runtime, [:]), descriptor: descriptor)
                let result = program.evaluate(inputs: [.layer(layerID: id, field: .origin): .vector3(0, 0, 0)],
                    effectivePropertyValues: [:], frame: frame,
                    mediaThumbnailEvent: .init(hasThumbnail: true, generation: 1))
                let admission = runtime.preflightOwnerEffects(result.ownerEffects)
                let visibility = SceneDynamicTarget.layer(layerID: id, field: .visibility)
                let current = snapshot(runtime, admission.layerPlan.authoredLayerValues)
                runtime.commit(admission.layerPlan)
                program.finalizeLayerMutations(committing: true, rejectedOwnerTargets: [])
                let committed = snapshot(runtime, runtime.snapshot().authoredLayerValues)
                callbacks.append(["name": name, "initial": initial, "bindingCount": program.bindings.count,
                    "failures": result.failures.count, "mutationCount": result.layerMutations.count,
                    "current": current[visibility]?.value == .bool(true),
                    "committed": committed[visibility]?.value == .bool(true),
                    "consumer": SceneLayerVisibility.visibleLayerIDs(in: descriptor, snapshot: current).contains(id)])
            }
            for mode in ["aa", "ab", "aba"] {
                for rejection in mode == "aa" ? ["none"] : ["none", "a", "b", "both"] {
                    let descriptor = scene(id, name)
                    let runtime = SceneScriptDynamicLayerRuntime(descriptor: descriptor, authoredMutationLayerIDs: [id])
                    let domain = try SceneScriptQuickJSDomain()
                    try domain.publishLayerSnapshot(snapshot(runtime, [:]), descriptor: descriptor)
                    let a = try owner(domain, id, "let writes=0;export function update(v){writes++;\(destination).visible=writes!==1;return v;}")
                    let b = try owner(domain, id, "export function update(v){\(destination).visible=\(mode == "ab" ? "true" : "false");return v;}", field: .scale)
                    var bundles = [effects(a, try evaluate(a))]
                    if mode != "aa" { bundles.append(effects(b, try evaluate(b))) }
                    if mode != "ab" { bundles.append(effects(a, try evaluate(a))) }
                    let rejected: Set<SceneDynamicTarget> = rejection == "both" ? [a.target, b.target]
                        : rejection == "a" ? [a.target] : rejection == "b" ? [b.target] : []
                    let settled = runtime.preflightOwnerEffectsToFixedPoint(bundles) { _, _ in rejected }
                    let visibility = SceneDynamicTarget.layer(layerID: id, field: .visibility)
                    let current = snapshot(runtime, settled.admission.layerPlan.authoredLayerValues)
                    runtime.commit(settled.admission.layerPlan)
                    if rejected.contains(a.target) { a.discardLayerMutations() } else { a.commitLayerMutations() }
                    if rejected.contains(b.target) { b.discardLayerMutations() } else { b.commitLayerMutations() }
                    let committed = snapshot(runtime, runtime.snapshot().authoredLayerValues)
                    interleaved.append(["name": name, "mode": mode, "rejection": rejection,
                        "current": current[visibility]?.value == .bool(true),
                        "committed": committed[visibility]?.value == .bool(true),
                        "rejected": settled.externallyRejectedOwners.count,
                        "failures": settled.admission.rejectedOwners.count])
                }
            }
            let perspectiveCases: [(String, Bool?, String)] = [
                ("particle", false, "roundtrip"), ("particle", true, "roundtrip"),
                ("particle", false, "opposite"), ("particle", true, "opposite"),
                ("particle", nil, "explicit-false"), ("particle", nil, "explicit-true"),
                ("image", false, "opposite"), ("image", true, "opposite")]
            for (kind, seed, mode) in perspectiveCases {
                let descriptor = scene(id, name, kind: kind, perspective: seed)
                let runtime = SceneScriptDynamicLayerRuntime(descriptor: descriptor, authoredMutationLayerIDs: [id])
                let domain = try SceneScriptQuickJSDomain()
                try domain.publishLayerSnapshot(snapshot(runtime, [:]), descriptor: descriptor)
                let requested = mode == "roundtrip" ? "ref.perspective" : mode == "opposite"
                    ? "!ref.perspective" : mode == "explicit-true" ? "true" : "false"
                let writer = try owner(domain, id, "export function update(v){const ref=\(destination);ref.perspective=\(requested);ref.visible=false;return v;}")
                let value = try evaluate(writer)
                let admission = runtime.preflightOwnerEffects([effects(writer, value)])
                let visibility = SceneDynamicTarget.layer(layerID: id, field: .visibility)
                let perspective = SceneDynamicTarget.layer(layerID: id, field: .perspective)
                runtime.commit(admission.layerPlan)
                if admission.rejectedOwners.isEmpty { writer.commitLayerMutations() }
                else { writer.discardLayerMutations() }
                let committed = snapshot(runtime, runtime.snapshot().authoredLayerValues)
                perspectiveAdmission.append(["name": name, "kind": kind,
                    "seed": seed.map { $0 as Any } ?? NSNull(), "mode": mode,
                    "exportedPerspective": value.layerMutations.contains { $0.fields.contains(.perspective) },
                    "rejected": admission.rejectedOwners.count,
                    "committedVisibility": committed[visibility]?.value == .bool(true),
                    "candidatePerspective": admission.layerPlan.authoredLayerValues[perspective].map { $0 == .bool(true) } as Any? ?? NSNull(),
                    "committedPerspective": committed[perspective].map { $0.value == .bool(true) } as Any? ?? NSNull(),
                    "hasPerspectiveDefinition": runtime.authoredLayerDefinitions.contains { $0.target == perspective }])
            }
            let descriptor = scene(id, name)
            let runtime = SceneScriptDynamicLayerRuntime(descriptor: descriptor, authoredMutationLayerIDs: [id])
            let domain = try SceneScriptQuickJSDomain()
            try domain.publishLayerSnapshot(snapshot(runtime, [:]), descriptor: descriptor)
            let assignments = fields.map { "clone['\($0.0)']=clone['\($0.0)'];" }.joined()
            let dynamic = try owner(domain, id, "let clone;export function init(v){clone=thisScene.createLayer({name:'\(name)-clone',text:'seed',font:'Arial',pointsize:32});return v;}export function update(v){\(assignments)return v;}")
            let birth = try evaluate(dynamic)
            dynamic.commitLayerMutations()
            let unchanged = try evaluate(dynamic)
            immediate.append(["name": name, "path": "dynamic", "birth": birth.layerMutations.count,
                "unchanged": unchanged.layerMutations.count])
            dynamic.discardLayerMutations()

            let image = scene(id, name, kind: "image")
            let imageDomain = try SceneScriptQuickJSDomain()
            let imageRuntime = SceneScriptDynamicLayerRuntime(descriptor: image, authoredMutationLayerIDs: [])
            try imageDomain.publishLayerSnapshot(snapshot(imageRuntime, [:]), descriptor: image)
            let imageFont = try owner(imageDomain, id, "export function update(v){\(destination).font='image-state';if(\(destination).font!=='image-state')throw Error('font');return v;}")
            let changedFont = try evaluate(imageFont)
            imageFont.commitLayerMutations()
            let unchangedFont = try evaluate(imageFont)
            immediate.append(["name": name, "path": "image-font", "birth": changedFont.layerMutations.count,
                "unchanged": unchangedFont.layerMutations.count])
            imageFont.discardLayerMutations()
        }
        return ["baselines": baselines, "callbacks": callbacks, "interleaved": interleaved,
            "immediate": immediate, "returnFallback": returnFallback, "perspectiveAdmission": perspectiveAdmission]
    }

    static func capacityABICase() throws -> [String: Any] {
        let path = "models/abi-capacity.json"
        let descriptor = SceneRenderDescriptor(layers: [.init(id: 7, layerIndex: 0,
            name: "ABI", visible: true, originXYZ: [0,0,0], scaleXYZ: [1,1,1],
            alpha: 1, effects: [], contentKind: "image", sizeWH: [5,5])])
        let templates = [path: SceneScriptPreparedResourceLayerTemplate(modelPath: path,
            renderSizeWH: [5,5], autosize: true)]
        let domain = try SceneScriptQuickJSDomain()
        try domain.configurePreparedResourceLayerCatalog(templates)
        try domain.publishLayerSnapshot(.empty(frameIndex: 0), descriptor: descriptor)
        let owner = try SceneScriptValueOwner(domain: domain, source: """
            export function update(v){let n=0;for(let i=0;i<(v===1?4096:1);i++)
                if(thisScene.createLayer({image:'\(path)'}))n++;
                if(v===1)thisLayer.alpha=.5;return n;}
            """, target: .layer(layerID: 7, field: .alpha), valueType: .scalar,
            effectNames: [], dynamicImagePathsByAuthoredIdentity: [path: path],
            allowsStatefulLayerSideEffects: true, generation: 1, budget: .default)
        let frame = SceneScriptFrameInput(timing: .init(wallDate: Date(timeIntervalSince1970: 0),
            simulationFrameTime: 1/60, sceneTime: 0))
        let value = try owner.evaluate(input: .scalar(1), frame: frame,
            scriptPropertiesJSON: "", userPropertiesJSON: "{}", expectedGeneration: 1,
            interruptBudget: nil).get()
        var effect = SceneScriptOwnerEffects(ownerTarget: owner.target, materialFunctionMutations: [],
            animationMutations: [], layerMutations: [], mediaPlaybackCommands: [])
        effect.append(value)
        let runtime = SceneScriptDynamicLayerRuntime(descriptor: descriptor,
            authoredMutationLayerIDs: [7], preparedResourceLayerTemplates: templates,
            layerOrderProjection: { domain.projectPendingLayerOrder(accepting: $0) })
        let admission = runtime.preflightOwnerEffects([effect])
        runtime.commit(admission.layerPlan)
        owner.commitLayerMutations()
        domain.finalizeCommittedLayerSnapshot()
        let excess = try owner.evaluate(input: .scalar(2), frame: frame,
            scriptPropertiesJSON: "", userPropertiesJSON: "{}", expectedGeneration: 1,
            interruptBudget: nil).get()
        owner.discardLayerMutations()
        return ["raw": value.layerMutations.count, "accepted": admission.rejectedOwners.isEmpty,
            "creates4095": value.value == .scalar(4095), "excessIsNull": excess.value == .scalar(0),
            "layers": runtime.snapshot().dynamicLayers.count,
            "live": runtime.snapshot().renderOrderLayerIDs.count]
    }

    static func capacityCases() throws -> [[String: Any]] {
        var rows: [[String: Any]] = []
        for (id, name, path, variable) in [(7, "capacity", "models/capacity.json", "tiles"),
                (73, "renamed-capacity", "models/renamed-capacity.json", "nodes")] {
            for outcome in ["commit", "late", "cancel", "throw"] {
                var descriptor = SceneRenderDescriptor(layers: [.init(id: id, layerIndex: 0,
                    name: name, visible: true, originXYZ: [0,0,0], scaleXYZ: [1,1,1],
                    alpha: 1, effects: [], contentKind: "image", sizeWH: [5,5])])
                descriptor.modelMaterialLinks = [.init(modelPath: path, materialPath: "material")]
                let template = SceneScriptPreparedResourceLayerTemplate(modelPath: path,
                    renderSizeWH: [5,5], autosize: true)
                let templates = [path: template]
                let domain = try SceneScriptQuickJSDomain()
                try domain.configurePreparedResourceLayerCatalog(templates)
                let source = """
                    let \(variable)=[],old;
                    function build(){for(const p of \(variable))thisScene.destroyLayer(p);
                        \(variable)=[];for(let n=0;n<511;n++){
                            const p=thisScene.createLayer({image:'\(path)',name:'tile'+n});
                            if(!p)throw Error('birth '+n);\(variable).push(p);}}
                    export function init(v){build();thisLayer.alpha=.25;return v;}
                    export function update(v){if(engine.runtime===0){
                            for(const p of \(variable))p.scale=new Vec3(2);thisLayer.alpha=.5;}
                        if(engine.runtime===2||engine.runtime===3){old=\(variable)[0];
                            build();thisLayer.alpha=.75;
                            if(engine.runtime===3)throw Error('after rebuild');}
                        if(engine.runtime===4){let stale=false;try{old.visible;}catch(e){stale=true;}
                            thisLayer.origin=new Vec3(stale?1:0,thisScene.getLayerCount(),0);}
                        return v;}
                    """
                let binding = SceneScriptBindingIR(source: source,
                    owner: .init(kind: .object, objectIndex: 0, objectID: id,
                        effectIndex: nil, effectID: nil, passIndex: nil, passID: nil),
                    targetPath: [.key("objects"), .index(0), .key("visible")], properties: [:],
                    authoredValue: .bool(true), valueType: .boolean, wrapperKeys: ["script", "value"])
                let program = SceneScriptVectorProgram.compile(domain: domain, descriptor: descriptor,
                    scriptBindings: [binding], userPropertyDefinitions: [], generation: 1)
                let ownerTarget = SceneDynamicTarget.layer(layerID: id, field: .visibility)
                let runtime = SceneScriptDynamicLayerRuntime(descriptor: descriptor,
                    authoredMutationLayerIDs: [id], preparedResourceLayerTemplates: templates,
                    layerOrderProjection: { domain.projectPendingLayerOrder(accepting: $0) })
                func frame(_ time: Double) -> SceneScriptFrameInput {
                    .init(timing: .init(wallDate: Date(timeIntervalSince1970: 0),
                        simulationFrameTime: 1/60, sceneTime: time))
                }
                func publish(_ time: Double) throws {
                    let snapshot = SceneDynamicSnapshotResolver().resolve(frameIndex: UInt64(time),
                        generation: 1, definitions: runtime.authoredLayerDefinitions,
                        sceneScriptValues: runtime.snapshot().authoredLayerValues).snapshot
                    try domain.publishLayerSnapshot(snapshot, descriptor: descriptor)
                }
                try publish(0)
                let entry = program.initializationOwners.first!
                let initialization = try entry.owner.initializeIfNeeded(input: .bool(true), frame: frame(0),
                    scriptPropertiesJSON: "", userPropertiesJSON: "{}", expectedGeneration: 1,
                    interruptBudget: nil, retainsValueForNextUpdate: true).get()!
                var birth = SceneScriptOwnerEffects(ownerTarget: ownerTarget, materialFunctionMutations: [],
                    animationMutations: [], layerMutations: [], mediaPlaybackCommands: [])
                birth.append(initialization)
                // Initialization and ordinary update share one finalization barrier.
                let first = program.evaluate(inputs: [ownerTarget: .bool(true)],
                    effectivePropertyValues: [:], frame: frame(0))
                let initialAdmission = runtime.preflightOwnerEffects([birth] + first.ownerEffects)
                let unpublished = runtime.snapshot()
                runtime.commit(initialAdmission.layerPlan)
                program.finalizeLayerMutations(committing: true)
                domain.finalizeCommittedLayerSnapshot()
                let committed = runtime.snapshot()
                let originalIDs = committed.dynamicLayers.map(\.id)
                try publish(2)
                let saved = program.frameStateSnapshot()
                let rebuilt = program.evaluate(inputs: [ownerTarget: .bool(true)],
                    effectivePropertyValues: [:], frame: frame(outcome == "throw" ? 3 : 2))
                let rejected: Set<SceneDynamicTarget> = outcome == "late" ? [ownerTarget] : []
                let admission = runtime.preflightOwnerEffectsToFixedPoint(rebuilt.ownerEffects,
                    excludingOwners: Set(rebuilt.failures.keys)) { _, _ in rejected }
                if outcome == "cancel" {
                    program.restoreFrameState(saved)
                    program.finalizeLayerMutations(committing: false)
                    domain.discardCommittedLayerSnapshot()
                } else {
                    runtime.commit(admission.admission.layerPlan)
                    if !rejected.isEmpty { program.restoreFrameState(saved, rejectedOwnerTargets: rejected) }
                    program.finalizeLayerMutations(committing: true, rejectedOwnerTargets: rejected)
                    domain.finalizeCommittedLayerSnapshot()
                }
                let after = runtime.snapshot()
                var stale = false
                if outcome == "commit" {
                    try publish(4)
                    let probe = program.evaluate(inputs: [ownerTarget: .bool(true)],
                        effectivePropertyValues: [:], frame: frame(4))
                    let plan = runtime.preflightOwnerEffects(probe.ownerEffects)
                    runtime.commit(plan.layerPlan)
                    program.finalizeLayerMutations(committing: true)
                    domain.finalizeCommittedLayerSnapshot()
                    stale = runtime.snapshot().authoredLayerValues[.layer(layerID: id, field: .origin)]
                        == .vector3(1,512,0)
                }
                let observer = try SceneScriptValueOwner(domain: domain,
                    source: "export function update(v){return thisScene.getLayerCount();}",
                    target: .layer(layerID: id, field: .alpha), valueType: .scalar,
                    effectNames: [], generation: 1, budget: .default)
                let observed = try observer.evaluate(input: .scalar(1), frame: frame(5),
                    scriptPropertiesJSON: "", userPropertiesJSON: "{}", expectedGeneration: 1,
                    interruptBudget: nil).get()
                observer.discardLayerMutations()
                rows.append(["name": name, "outcome": outcome, "bindings": program.bindings.count,
                    "initialization": initialization.layerMutations.count, "update": first.layerMutations.count,
                    "initialFailures": first.failures.count, "initialRejected": initialAdmission.rejectedOwners.count,
                    "initialRejection": initialAdmission.rejectedOwners.map { String(describing: $0.failure) },
                    "noEarlyPublication": unpublished.dynamicLayers.isEmpty,
                    "births": committed.dynamicLayers.count, "live": committed.renderOrderLayerIDs.count,
                    "preparedImageConsumers": committed.dynamicLayers.allSatisfy {
                        $0.contentKind == "image" && $0.imagePath == path && $0.sizeWH == [5,5]
                            && $0.scaleXYZ == [2,2,2] && $0.visible == true
                    },
                    "rebuiltMutations": rebuilt.layerMutations.count, "failures": rebuilt.failures.count,
                    "externalOrFailed": admission.externallyRejectedOwners.count,
                    "remaining": after.dynamicLayers.count, "cLive512": observed.value == .scalar(512),
                    "replacedIDs": Set(after.dynamicLayers.map(\.id)).isDisjoint(with: originalIDs),
                    "preservedIDs": after.dynamicLayers.map(\.id) == originalIDs,
                    "preservedOrder": after.renderOrderLayerIDs == committed.renderOrderLayerIDs,
                    "preservedValues": after.authoredLayerValues == committed.authoredLayerValues,
                    "dynamicScale": after.dynamicLayers.allSatisfy {
                        $0.scaleXYZ == (outcome == "commit" ? [1,1,1] : [2,2,2])
                    },
                    "staleRetiredHandle": stale])
            }
        }
        return rows
    }

    static func main() throws {
        let event = try Context(eventSource)
        let events = try [
            event.step(invert: false, revision: 1, time: 0, userVisibility: false),
            event.step(invert: false, revision: 1, time: 1, userVisibility: false),
            event.step(invert: false, revision: 1, time: 1.5, userVisibility: false),
            event.step(invert: true, revision: 2, time: 2, userVisibility: true),
            event.step(invert: true, revision: 2, time: 3, userVisibility: true),
            event.step(invert: false, revision: 3, time: 4, userVisibility: false),
            event.step(invert: false, revision: 3, time: 5, userVisibility: false)]

        let retry = try Context(eventSource)
        let rejected = try [
            retry.step(invert: false, revision: 1, time: 0, userVisibility: false, reject: true),
            retry.step(invert: false, revision: 1, time: 1, userVisibility: false),
            retry.step(invert: false, revision: 1, time: 2, userVisibility: false),
            retry.step(invert: true, revision: 2, time: 3, userVisibility: true, reject: true),
            retry.step(invert: true, revision: 2, time: 4, userVisibility: true),
            retry.step(invert: true, revision: 2, time: 5, userVisibility: true)]

        let throwing = try Context("""
            let calls = 0;
            export function applyUserProperties(properties) {
                calls += 1;
                thisLayer.visible = !properties.invert;
                thisLayer.origin = new Vec3(calls, 0, 0);
                if (properties.invert) {
                    throw new Error('reject after setter');
                }
            }
            """)
        let thrown = try [
            throwing.step(invert: false, revision: 1, time: 0, userVisibility: false),
            throwing.step(invert: true, revision: 2, time: 1, userVisibility: true),
            throwing.step(invert: true, revision: 2, time: 2, userVisibility: true),
            throwing.step(invert: false, revision: 3, time: 3, userVisibility: false)]

        let noWrite = try Context("""
            export function applyUserProperties(properties) {
                // Reading a Boolean is not a setter and must not pin this input.
                const observed = thisLayer.visible;
            }
            """)
        let noWrites = try [
            noWrite.step(invert: false, revision: 1, time: 0, userVisibility: true),
            noWrite.step(invert: false, revision: 1, time: 1, userVisibility: false),
            noWrite.step(invert: true, revision: 2, time: 2, userVisibility: true),
            noWrite.step(invert: true, revision: 2, time: 3, userVisibility: false)]

        let update = try Context("""
            export function applyUserProperties(properties) { thisLayer.visible = true; }
            export function update(value) { return engine.runtime < 1; }
            """)
        let updates = try [
            update.step(invert: false, revision: 1, time: 0),
            update.step(invert: false, revision: 1, time: 2),
            update.step(invert: true, revision: 2, time: 0),
            update.step(invert: true, revision: 2, time: 2)]
        print(String(data: try JSONSerialization.data(withJSONObject: [
            "events": events, "rejected": rejected, "thrown": thrown,
            "noWrites": noWrites, "updates": updates,
            "setterIntents": try setterIntentCases(), "capacity": try capacityCases(),
            "capacityABI": try capacityABICase()
        ], options: [.sortedKeys]), encoding: .utf8)!)
    }
}
'''


class SceneScriptEventVisibilityTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.temporary = tempfile.TemporaryDirectory(prefix="mwx-event-visibility-")
        cls.addClassCleanup(cls.temporary.cleanup)
        # Extend only the descriptor carrier. Visibility, VM validation,
        # admission, runtime commit and resolver are production code.
        preamble = SWIFT_PREAMBLE.replace(
            "var particleInstanceOverride:",
            "var displayScriptOwnership: SceneLayerDisplayScriptOwnership? = nil\n"
            "        var imageMaterialRenderState: SceneMaterialRenderState? = nil\n"
            "        var particleInstanceOverride:")
        projection = (SCENE / "Systems/Script/SceneScriptLayerTopologyProjection.swift").read_text()
        preamble = preamble.replace(
            swift_declaration(preamble, "    static func preparedResourceLayer("),
            swift_declaration(projection, "    static func preparedResourceLayer("))
        preamble += LAYER_CARRIER + "\nextension SceneRenderDescriptor.Layer {\n" + swift_declaration(
            projection, "    private static func descriptorTransform(") + "\n}\n"
        binary = compile_vector_harness(Path(cls.temporary.name), HARNESS,
            "event-visibility", preamble=preamble,
            extra_swift_sources=(SCENE / "Rendering/Geometry/SceneLayerVisibility.swift",),
            whole_module_optimization=True,
        )
        result = subprocess.run([str(binary)], capture_output=True, text=True,
                                check=True, timeout=30)
        cls.value = json.loads(result.stdout.strip().splitlines()[-1])

    def test_capacity_program_bridge_and_frame_transactions(self) -> None:
        self.assertEqual(self.value["capacityABI"], {"raw": 4096, "accepted": True,
            "creates4095": True, "excessIsNull": True, "layers": 4095, "live": 4096})
        self.assertEqual(len(self.value["capacity"]), 8)
        for row in self.value["capacity"]:
            with self.subTest(name=row["name"], outcome=row["outcome"]):
                for key, expected in {"bindings": 1, "initialization": 512, "update": 512,
                        "initialFailures": 0, "initialRejected": 0, "noEarlyPublication": True,
                        "births": 511, "live": 512, "preparedImageConsumers": True,
                        "remaining": 511, "cLive512": True, "dynamicScale": True}.items():
                    self.assertEqual(row[key], expected, row)
                accepted = row["outcome"] == "commit"
                thrown = row["outcome"] == "throw"
                self.assertEqual(row["rebuiltMutations"], 0 if thrown else 1023, row)
                self.assertEqual(row["failures"], int(thrown), row)
                self.assertEqual(row["externalOrFailed"], int(row["outcome"] in ["late", "throw"]), row)
                self.assertEqual(row["replacedIDs"], accepted, row)
                for key in ["preservedIDs", "preservedOrder", "preservedValues"]:
                    self.assertEqual(row[key], not accepted, row)
                self.assertEqual(row["staleRetiredHandle"], accepted, row)

    def assert_valid_rows(self, rows: list[dict]) -> None:
        for row in rows:
            self.assertEqual(row["failures"], 0, row)
            self.assertEqual(row["diagnostics"], 0, row)
            self.assertEqual(row["consumerVisible"], row["visible"], row)

    def test_property_event_setter_survives_idle_and_live_toggles(self) -> None:
        rows = self.value["events"]
        self.assert_valid_rows(rows)
        self.assertEqual([r["visible"] for r in rows], [True, True, True, False, False, True, True])
        self.assertEqual([r["persistentVisibility"] for r in rows], [True, True, True, False, False, True, True])
        self.assertEqual([r["values"] for r in rows], [1, 0, 0, 1, 0, 1, 0])
        self.assertEqual([r["ownVisibilityWrites"] for r in rows], [1, 0, 0, 1, 0, 1, 0])
        self.assertEqual([r["callbackCount"] for r in rows], [1, 1, 1, 2, 2, 3, 3])

    def test_rejected_event_effects_do_not_commit_and_same_revision_retries(self) -> None:
        rows = self.value["rejected"]
        self.assert_valid_rows(rows)
        self.assertEqual([r["visible"] for r in rows], [False, True, True, True, False, False])
        self.assertEqual([r["persistentVisibility"] for r in rows], [None, True, True, True, False, False])
        self.assertEqual([r["rejected"] for r in rows], [True, False, False, True, False, False])
        self.assertEqual([r["values"] for r in rows], [1, 1, 0, 1, 1, 0])
        self.assertEqual([r["callbackCount"] for r in rows], [None, 2, 2, 2, 4, 4])

    def test_setter_then_vm_throw_keeps_previous_value_without_partial_commit(self) -> None:
        rows = self.value["thrown"]
        self.assert_valid_rows([rows[0], *rows[2:]])
        failed = rows[1]
        self.assertEqual(failed["failures"], 1, failed)
        self.assertEqual(failed["failureCode"], "exception", failed)
        self.assertEqual(failed["values"], 0, failed)
        self.assertEqual(failed["effects"], 0, failed)
        self.assertEqual(failed["mutations"], 0, failed)
        self.assertTrue(failed["rejected"], failed)
        # The failed revision stays fused; a later property revision can retry.
        # Neither the throw nor its same-revision idle frame publishes partial writes.
        self.assertEqual([r["visible"] for r in rows], [True, True, True, True])
        self.assertEqual([r["persistentVisibility"] for r in rows], [True, True, True, True])
        self.assertEqual([r["callbackCount"] for r in rows], [1, 1, 1, 3])
        self.assertEqual([r["values"] for r in rows], [1, 0, 0, 1])
        self.assertTrue(all(r["effects"] == r["mutations"] == 0 for r in rows[1:3]))
        self.assertEqual(rows[3]["effects"], 1, rows[3])
        self.assertEqual(rows[3]["mutations"], 1, rows[3])

    def test_no_write_event_callback_does_not_pin_current_input(self) -> None:
        rows = self.value["noWrites"]
        self.assert_valid_rows(rows)
        self.assertEqual([r["visible"] for r in rows], [True, False, True, False])
        self.assertEqual([r["values"] for r in rows], [1, 0, 1, 0])
        self.assertTrue(all(r["persistentVisibility"] is None for r in rows))
        self.assertTrue(all(r["effects"] == r["mutations"] == 0 for r in rows))

    def test_update_owner_own_setter_does_not_persist_over_later_return(self) -> None:
        rows = self.value["updates"]
        self.assert_valid_rows(rows)
        self.assertEqual([r["visible"] for r in rows], [True, False, True, False])
        self.assertEqual([r["values"] for r in rows], [1, 1, 1, 1])
        self.assertTrue(all(r["persistentVisibility"] is None for r in rows))
        self.assertTrue(all(r["ownVisibilityWrites"] == 0 for r in rows))

    def test_authored_roundtrip_setters_record_explicit_baseline_intent(self) -> None:
        rows = self.value["setterIntents"]["baselines"]
        self.assertEqual(len(rows), 22)
        for row in rows:
            with self.subTest(name=row["name"], field=row["field"]):
                self.assertEqual(row["mutationCount"], 1, row)
                self.assertTrue(row["recorded"], row)

    def test_event_then_update_can_restore_either_authored_visibility(self) -> None:
        rows = self.value["setterIntents"]["callbacks"]
        self.assertEqual(len(rows), 4)
        for row in rows:
            with self.subTest(name=row["name"], initial=row["initial"]):
                self.assertEqual(row["bindingCount"], 1, row)
                self.assertEqual(row["failures"], 0, row)
                self.assertEqual(row["mutationCount"], 1, row)
                self.assertEqual(row["current"], row["initial"], row)
                self.assertEqual(row["committed"], row["initial"], row)
                self.assertEqual(row["consumer"], row["initial"], row)

    def test_same_value_setter_retains_typed_fallback_but_getter_does_not(self) -> None:
        rows = self.value["setterIntents"]["returnFallback"]
        self.assertEqual(len(rows), 4)
        for row in rows:
            with self.subTest(name=row["name"], writes=row["writes"]):
                self.assertEqual(row["accepted"], row["writes"], row)
                if row["writes"]:
                    self.assertTrue(row["keptTypedInput"], row)
                    self.assertTrue(row["ownSetter"], row)
                    self.assertEqual(row["retainedMutations"], 1, row)
                else:
                    self.assertEqual(row["failure"], "bad-return", row)
                    self.assertEqual(row["retainedMutations"], 0, row)

    def test_baseline_writes_survive_owner_coalescing_and_rejection(self) -> None:
        rows = self.value["setterIntents"]["interleaved"]
        self.assertEqual(len(rows), 18)
        expected = {("aa", "none"): True,
                    ("ab", "none"): True, ("ab", "a"): True,
                    ("ab", "b"): False, ("ab", "both"): True,
                    ("aba", "none"): False, ("aba", "a"): False,
                    ("aba", "b"): True, ("aba", "both"): True}
        for row in rows:
            with self.subTest(name=row["name"], mode=row["mode"], rejection=row["rejection"]):
                self.assertEqual(row["failures"], 0, row)
                self.assertEqual(row["rejected"], {"none": 0, "a": 1, "b": 1, "both": 2}[row["rejection"]], row)
                self.assertEqual(row["current"], expected[row["mode"], row["rejection"]], row)
                self.assertEqual(row["committed"], row["current"], row)

    def test_dynamic_and_image_font_paths_do_not_export_unchanged_dirty_records(self) -> None:
        rows = self.value["setterIntents"]["immediate"]
        self.assertEqual(len(rows), 4)
        for row in rows:
            with self.subTest(name=row["name"], path=row["path"]):
                self.assertEqual(row["birth"], 1 if row["path"] == "dynamic" else 0, row)
                self.assertEqual(row["unchanged"], 0, row)

    def test_perspective_no_consumer_only_admits_explicit_prepared_noop(self) -> None:
        rows = self.value["setterIntents"]["perspectiveAdmission"]
        self.assertEqual(len(rows), 16)
        for row in rows:
            with self.subTest(name=row["name"], kind=row["kind"], seed=row["seed"], mode=row["mode"]):
                consumes = row["kind"] == "image"
                accepted = consumes or row["mode"] == "roundtrip"
                self.assertTrue(row["exportedPerspective"], row)
                self.assertEqual(row["rejected"], 0 if accepted else 1, row)
                self.assertEqual(row["committedVisibility"], not accepted, row)
                self.assertEqual(row["hasPerspectiveDefinition"], consumes, row)
                if consumes:
                    self.assertEqual(row["candidatePerspective"], not row["seed"], row)
                    self.assertEqual(row["committedPerspective"], not row["seed"], row)
                else:
                    self.assertIsNone(row["candidatePerspective"], row)
                    self.assertIsNone(row["committedPerspective"], row)


if __name__ == "__main__":
    unittest.main()
