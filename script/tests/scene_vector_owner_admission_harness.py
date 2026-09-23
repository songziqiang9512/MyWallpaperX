#!/usr/bin/env python3

"""Swift harness for G->C vector admission and fresh-domain publication."""


HARNESS = r'''
@main
enum Harness {
    static func main() throws {
        let descriptor = SceneRenderDescriptor(layers: [
            .init(
                id: 10,
                layerIndex: 0,
                name: "owner",
                visible: true,
                originXYZ: [0, 0, 0],
                scaleXYZ: [1, 1, 1],
                scaleHasScript: false,
                alpha: nil,
                effects: [.init(
                    name: "history",
                    effectID: 100,
                    passes: [.init(
                        passIndex: 0,
                        id: 200,
                        constantShaderValues: [
                            "claimed": .init(
                                scriptSource: claimedSource,
                                components: [1, 1]
                            ),
                            "unclaimed": .init(
                                scriptSource: unclaimedSource,
                                components: [1, 1]
                            ),
                            "failedClaimed": .init(
                                scriptSource: passFailedSource,
                                components: [1, 1]
                            ),
                            "enginePoison": .init(
                                scriptSource: enginePoisonSource,
                                components: [1, 1]
                            ),
                            "handleGuard": .init(
                                scriptSource: handleGuardSource,
                                components: [1, 1]
                            ),
                        ]
                    )]
                )]
            ),
            .init(
                id: 20,
                layerIndex: 1,
                name: "cursor-failure",
                visible: true,
                originXYZ: [0, 0, 0],
                scaleXYZ: [1, 1, 1],
                scaleHasScript: false,
                alpha: 1,
                effects: [],
                contentKind: "composition",
                sizeWH: [100, 100],
                utilityLayer: .init(
                    kind: .composition,
                    copyBackground: false,
                    passthrough: false
                )
            ),
            .init(
                id: 30,
                layerIndex: 2,
                name: "text-failures",
                visible: true,
                originXYZ: [0, 0, 0],
                scaleXYZ: [1, 1, 1],
                scaleHasScript: false,
                alpha: 1,
                effects: [],
                contentKind: "text",
                textScript: .init(source: stringFailedSource),
                text: "authored",
                textStyle: .init(
                    fontPath: nil,
                    colorRGB: [1, 1, 1],
                    pointSize: 48
                )
            )
        ])
        let frame = SceneScriptFrameInput(
            timing: .init(
                wallDate: Date(timeIntervalSince1970: 0),
                simulationFrameTime: 1.0 / 60.0,
                sceneTime: 2
            ),
            timeZone: TimeZone(secondsFromGMT: 0)!
        )
        let claimedTarget = target("claimed")
        let unclaimedTarget = target("unclaimed")
        let failedTarget = target("failedClaimed")
        let enginePoisonTarget = target("enginePoison")
        let handleGuardTarget = target("handleGuard")
        let bindings = [
            objectVectorBinding(source: vectorFailedSource),
            cursorBinding(source: cursorFailedSource),
            scalarBinding(source: scalarFailedSource),
            stringBinding(source: stringFailedSource),
            passBinding(key: "claimed", source: claimedSource),
            passBinding(key: "unclaimed", source: unclaimedSource),
            passBinding(key: "failedClaimed", source: passFailedSource),
            passBinding(key: "enginePoison", source: enginePoisonSource),
            passBinding(key: "handleGuard", source: handleGuardSource),
        ]
        let projection = SceneScriptVectorProgram.project(
            descriptor: descriptor,
            scriptBindings: bindings
        )
        let consumerTargets: Set<SceneDynamicTarget> = [
            claimedTarget, failedTarget, enginePoisonTarget, handleGuardTarget,
        ]

        let candidate = try SceneScriptQuickJSProgramCandidate.compile(
            authoredDescriptor: descriptor,
            runtimeDescriptor: descriptor,
            scriptBindings: bindings,
            vectorProjection: projection,
            userPropertyDefinitions: [],
            timelineTargets: [],
            scalarExcludedTargets: [],
            stringExcludedTargets: [],
            admittedVectorPassTargets: consumerTargets,
            generation: 31
        )
        precondition(candidate.constructionReport.isComplete)
        let committedProgram = candidate.vectorProgram
        let result = committedProgram.evaluate(
            inputs: [
                claimedTarget: .vector2(1, 1),
                unclaimedTarget: .vector2(1, 1),
                failedTarget: .vector2(1, 1),
                enginePoisonTarget: .vector2(1, 1),
                handleGuardTarget: .vector2(1, 1),
            ],
            effectivePropertyValues: [:],
            frame: frame
        )
        let duplicateProjection = SceneScriptVectorProgram.project(
            descriptor: descriptor,
            scriptBindings: [bindings[0], bindings[0]]
        )
        let aggregateCandidate = try aggregateBudgetCandidate()
        let overlapSource = "export function cursorMove(event) { return; }"
        let overlapDescriptor = SceneRenderDescriptor(layers: [.init(
            id: 50,
            layerIndex: 0,
            name: "claimed-cursor-overlap",
            visible: true,
            originXYZ: [0, 0, 0],
            scaleXYZ: [1, 1, 1],
            scaleHasScript: false,
            alpha: 1,
            effects: [],
            contentKind: "image",
            sizeWH: [100, 100]
        )])
        let overlapBindings = [overlapVisibleBinding(source: overlapSource)]
        let overlapProjection = SceneScriptVectorProgram.project(
            descriptor: overlapDescriptor,
            scriptBindings: overlapBindings
        )
        let overlapBudget = SceneScriptScalarBudget(
            heapBytes: 2 * 1024 * 1024,
            stackBytes: 512 * 1024,
            interruptBudget: 100_000,
            maximumOwnerSourceBytes: overlapSource.utf8.count,
            maximumCandidateSourceBytes: overlapSource.utf8.count
        )
        let overlapCandidate = try SceneScriptQuickJSProgramCandidate.compile(
            authoredDescriptor: overlapDescriptor,
            runtimeDescriptor: overlapDescriptor,
            scriptBindings: overlapBindings,
            vectorProjection: overlapProjection,
            userPropertyDefinitions: [],
            timelineTargets: [],
            scalarExcludedTargets: [],
            stringExcludedTargets: [],
            admittedVectorPassTargets: [],
            generation: 42,
            budget: overlapBudget
        )
        let mixedSource = """
        export function update(value) { return value; }
        export function cursorMove(event) { return; }
        """
        let mixedBindings = [overlapVisibleBinding(source: mixedSource)]
        let mixedProjection = SceneScriptVectorProgram.project(
            descriptor: overlapDescriptor,
            scriptBindings: mixedBindings
        )
        let mixedBudget = SceneScriptScalarBudget(
            heapBytes: 2 * 1024 * 1024,
            stackBytes: 512 * 1024,
            interruptBudget: 100_000,
            maximumOwnerSourceBytes: mixedSource.utf8.count,
            maximumCandidateSourceBytes: mixedSource.utf8.count
        )
        let mixedCandidate = try SceneScriptQuickJSProgramCandidate.compile(
            authoredDescriptor: overlapDescriptor,
            runtimeDescriptor: overlapDescriptor,
            scriptBindings: mixedBindings,
            vectorProjection: mixedProjection,
            userPropertyDefinitions: [],
            timelineTargets: [],
            scalarExcludedTargets: [],
            stringExcludedTargets: [],
            admittedVectorPassTargets: [],
            generation: 46,
            budget: mixedBudget
        )
        let constSource = """
        // export function update(value) { return value; }
        const text = "export function destroy() {}";
        export const cursorMove = (event) => {
            thisLayer.origin = new Vec3(47, 0, 0);
        }
        """
        let constCandidate = try cursorAdmissionCandidate(
            descriptor: overlapDescriptor,
            source: constSource,
            generation: 47
        )
        let asyncSource = """
        export async function cursorMove(event) {
            thisLayer.origin = new Vec3(48, 0, 0);
        }
        """
        let asyncCandidate = try cursorAdmissionCandidate(
            descriptor: overlapDescriptor,
            source: asyncSource,
            generation: 48
        )
        let namedSource = """
        function cursorMove(event) {
            thisLayer.origin = new Vec3(49, 0, 0);
        }
        export { cursorMove };
        """
        let namedCandidate = try cursorAdmissionCandidate(
            descriptor: overlapDescriptor,
            source: namedSource,
            generation: 49
        )
        let constDispatch = dispatchCursorMove(constCandidate, frame: frame)
        let asyncDispatch = dispatchCursorMove(asyncCandidate, frame: frame)
        let namedDispatch = dispatchCursorMove(namedCandidate, frame: frame)
        let propertyCursorSource = """
        export var scriptProperties = createScriptProperties();
        export function cursorMove(event) {
            thisLayer.origin = new Vec3(scriptProperties.step, 0, 0);
        }
        """
        let propertyCursorBindings = [overlapVisiblePropertyBinding(
            source: propertyCursorSource, userPropertyKey: "cursorStep"
        )]
        let propertyCursorProjection = SceneScriptVectorProgram.project(
            descriptor: overlapDescriptor,
            scriptBindings: propertyCursorBindings
        )
        let propertyCursorCandidate = try SceneScriptQuickJSProgramCandidate.compile(
            authoredDescriptor: overlapDescriptor,
            runtimeDescriptor: overlapDescriptor,
            scriptBindings: propertyCursorBindings,
            vectorProjection: propertyCursorProjection,
            userPropertyDefinitions: [],
            timelineTargets: [],
            scalarExcludedTargets: [],
            stringExcludedTargets: [],
            admittedVectorPassTargets: [],
            generation: 61
        )
        let propertyFirst = dispatchCursorMove(
            propertyCursorCandidate, frame: frame, propertyRevision: 1
        )
        let propertyLive = propertyCursorCandidate.cursorProgram.dispatch(
            batch: .init(samples: [.init(
                hits: [50: .init(layerID: 50,
                    worldPosition: .init(1, 2, 0),
                    localPosition: .init(0.75, 0.5, 0))],
                pointerPosition: .init(0.75, 0.5),
                primaryButtonIsDown: false
            )], overflowed: false),
            frame: frame, userPropertiesJSON: "{}",
            effectivePropertyValues: ["cursorStep": .number(5)],
            propertyRevision: 2
        )
        let reexportSource = "export { cursorMove } from \"other\";"
        let reexportCandidate = try cursorAdmissionCandidate(
            descriptor: overlapDescriptor,
            source: reexportSource,
            generation: 50
        )
        let mediaMixedSource = """
        export function cursorMove(event) { return; }
        export function mediaPlaybackChanged(event) { return; }
        """
        let mediaMixedCandidate = try cursorAdmissionCandidate(
            descriptor: overlapDescriptor,
            source: mediaMixedSource,
            generation: 51
        )
        let destroyMixedSource = """
        export function cursorMove(event) { return; }
        export function destroy() { return; }
        """
        let destroyMixedCandidate = try cursorAdmissionCandidate(
            descriptor: overlapDescriptor,
            source: destroyMixedSource,
            generation: 52
        )
        let audioMixedSource = """
        export function cursorMove(event) {
            if (false) { engine.registerAudioBuffers(); }
        }
        """
        let audioMixedCandidate = try cursorAdmissionCandidate(
            descriptor: overlapDescriptor,
            source: audioMixedSource,
            generation: 53
        )
        let nonFunctionCandidate = try cursorAdmissionCandidate(
            descriptor: overlapDescriptor,
            source: "export const cursorMove = 42",
            generation: 56
        )
        let regexLiteralCandidate = try cursorAdmissionCandidate(
            descriptor: overlapDescriptor,
            source: "const pattern = /export function cursorMove\\(/;",
            generation: 57
        )
        let duplicateBindings = [
            overlapVisibleBinding(source: overlapSource),
            overlapVisibleBinding(source: overlapSource),
        ]
        let duplicateCursorProjection = SceneScriptVectorProgram.project(
            descriptor: overlapDescriptor,
            scriptBindings: duplicateBindings
        )
        let duplicateCursorCandidate = try SceneScriptQuickJSProgramCandidate.compile(
            authoredDescriptor: overlapDescriptor,
            runtimeDescriptor: overlapDescriptor,
            scriptBindings: duplicateBindings,
            vectorProjection: duplicateCursorProjection,
            userPropertyDefinitions: [],
            timelineTargets: [],
            scalarExcludedTargets: [],
            stringExcludedTargets: [],
            admittedVectorPassTargets: [],
            generation: 54
        )
        let mixedDuplicateBindings = [
            overlapVisibleBinding(source: overlapSource),
            overlapVisiblePropertyBinding(source: overlapSource),
        ]
        let mixedDuplicateProjection = SceneScriptVectorProgram.project(
            descriptor: overlapDescriptor,
            scriptBindings: mixedDuplicateBindings
        )
        let mixedDuplicateCandidate = try SceneScriptQuickJSProgramCandidate.compile(
            authoredDescriptor: overlapDescriptor,
            runtimeDescriptor: overlapDescriptor,
            scriptBindings: mixedDuplicateBindings,
            vectorProjection: mixedDuplicateProjection,
            userPropertyDefinitions: [],
            timelineTargets: [],
            scalarExcludedTargets: [],
            stringExcludedTargets: [],
            admittedVectorPassTargets: [],
            generation: 58
        )
        let routedSource = """
        export function update(value) { return value; }
        export function mediaPlaybackChanged(event) { return; }
        export function cursorMove(event) {
            thisLayer.origin = new Vec3(59, 0, 0);
        }
        """
        let routedBindings = [overlapVisibleBinding(source: routedSource)]
        let routedProjection = SceneScriptVectorProgram.project(
            descriptor: overlapDescriptor,
            scriptBindings: routedBindings
        )
        let routedGeneric = try SceneScriptVectorMediaRouteCandidate.compile(
            initialPassTargets: [], route: .genericOnly,
            cancellationCheck: {},
            builder: { _, excluded in
                try routedCursorCandidate(
                    descriptor: overlapDescriptor, bindings: routedBindings,
                    projection: routedProjection, excluded: excluded,
                    generation: 59
                )
            }
        )!
        let routedDisabled = try SceneScriptVectorMediaRouteCandidate.compile(
            initialPassTargets: [], route: .disableGeneric,
            cancellationCheck: {},
            builder: { _, excluded in
                try routedCursorCandidate(
                    descriptor: overlapDescriptor, bindings: routedBindings,
                    projection: routedProjection, excluded: excluded,
                    generation: 60
                )
            }
        )!
        let vectorCursorCollisionSource = """
        export function update(value) { return value; }
        export function cursorMove(event) { return; }
        """
        let vectorCursorCollisionBindings = [
            overlapVisibleBinding(source: overlapSource),
            overlapOriginBinding(source: vectorCursorCollisionSource),
        ]
        let vectorCursorCollisionProjection = SceneScriptVectorProgram.project(
            descriptor: overlapDescriptor,
            scriptBindings: vectorCursorCollisionBindings
        )
        let vectorCursorCollisionCandidate = try SceneScriptQuickJSProgramCandidate.compile(
            authoredDescriptor: overlapDescriptor,
            runtimeDescriptor: overlapDescriptor,
            scriptBindings: vectorCursorCollisionBindings,
            vectorProjection: vectorCursorCollisionProjection,
            userPropertyDefinitions: [],
            timelineTargets: [],
            scalarExcludedTargets: [],
            stringExcludedTargets: [],
            admittedVectorPassTargets: [],
            generation: 55
        )
        let effectCursorTarget = SceneDynamicTarget.effectVisibility(
            layerID: 10, effectIndex: 0
        )
        let effectCursorBindings = [SceneScriptBindingIR(
            source: overlapSource,
            owner: .init(kind: .effect, objectIndex: 0, objectID: 10,
                         effectIndex: 0, effectID: 100,
                         passIndex: nil, passID: nil),
            targetPath: [.key("objects"), .index(0), .key("effects"),
                         .index(0), .key("visible")],
            properties: [:], authoredValue: .bool(true),
            valueType: .boolean, wrapperKeys: ["script", "value"]
        )]
        let effectCursorProjection = SceneScriptVectorProgram.project(
            descriptor: descriptor, scriptBindings: effectCursorBindings
        )
        let effectCursorCandidate = try SceneScriptQuickJSProgramCandidate.compile(
            authoredDescriptor: descriptor, runtimeDescriptor: descriptor,
            scriptBindings: effectCursorBindings,
            vectorProjection: effectCursorProjection,
            userPropertyDefinitions: [], timelineTargets: [],
            scalarExcludedTargets: [], stringExcludedTargets: [],
            admittedVectorPassTargets: [], generation: 62
        )
        let textCursorDescriptor = SceneRenderDescriptor(layers: [.init(
            id: 70, layerIndex: 0, name: "text-cursor", visible: true,
            originXYZ: [0, 0, 0], scaleXYZ: [1, 1, 1],
            colorRGB: [1, 1, 1], scaleHasScript: false, alpha: 1,
            effects: [], contentKind: "text",
            text: "authored", textStyle: .init(
                fontPath: nil, colorRGB: [1, 1, 1], pointSize: 24
            ), sizeWH: [100, 100]
        )])
        let textCursorSource = """
        export function update(value) { return value; }
        export function cursorMove(event) {
            thisLayer.origin = new Vec3(68, 0, 0);
        }
        """
        let textCursorBinding = SceneScriptBindingIR(
            source: textCursorSource,
            owner: .init(kind: .object, objectIndex: 0, objectID: 70,
                         effectIndex: nil, effectID: nil,
                         passIndex: nil, passID: nil),
            targetPath: [.key("objects"), .index(0), .key("color")],
            properties: [:], authoredValue: .string("1 1 1"),
            valueType: .string, wrapperKeys: ["script", "value"]
        )
        let textCursorProjection = SceneScriptVectorProgram.project(
            descriptor: textCursorDescriptor,
            scriptBindings: [textCursorBinding],
            admittedLayerColorConsumerIDs: [70]
        )
        let textCursorCandidate = try SceneScriptQuickJSProgramCandidate.compile(
            authoredDescriptor: textCursorDescriptor,
            runtimeDescriptor: textCursorDescriptor,
            scriptBindings: [textCursorBinding],
            vectorProjection: textCursorProjection,
            userPropertyDefinitions: [], timelineTargets: [],
            scalarExcludedTargets: [], stringExcludedTargets: [],
            admittedVectorPassTargets: [], generation: 63
        )
        let textCursorDispatch = textCursorCandidate.cursorProgram.dispatch(
            batch: .init(samples: [
                .init(hits: [70: .init(layerID: 70,
                       worldPosition: .init(1, 2, 0),
                       localPosition: .init(0.5, 0.5, 0))],
                      pointerPosition: .zero, primaryButtonIsDown: false),
                .init(hits: [70: .init(layerID: 70,
                       worldPosition: .init(1, 2, 0),
                       localPosition: .init(0.5, 0.5, 0))],
                      pointerPosition: .init(0.5, 0.5),
                      primaryButtonIsDown: false),
            ], overflowed: false), frame: frame, userPropertiesJSON: "{}"
        )
        let unhitDescriptor = SceneRenderDescriptor(layers: [.init(
            id: 80, layerIndex: 0, name: "unhit-visible", visible: true,
            originXYZ: [0, 0, 0], scaleXYZ: [1, 1, 1],
            scaleHasScript: false, alpha: 1, effects: [],
            contentKind: "container"
        )])
        let unhitBindings = [SceneScriptBindingIR(
            source: overlapSource,
            owner: .init(kind: .object, objectIndex: 0, objectID: 80,
                         effectIndex: nil, effectID: nil,
                         passIndex: nil, passID: nil),
            targetPath: [.key("objects"), .index(0), .key("visible")],
            properties: [:], authoredValue: .bool(true),
            valueType: .boolean, wrapperKeys: ["script", "value"]
        )]
        let unhitProjection = SceneScriptVectorProgram.project(
            descriptor: unhitDescriptor, scriptBindings: unhitBindings
        )
        let unhitCandidate = try SceneScriptQuickJSProgramCandidate.compile(
            authoredDescriptor: unhitDescriptor,
            runtimeDescriptor: unhitDescriptor,
            scriptBindings: unhitBindings,
            vectorProjection: unhitProjection,
            userPropertyDefinitions: [], timelineTargets: [],
            scalarExcludedTargets: [], stringExcludedTargets: [],
            admittedVectorPassTargets: [], generation: 64
        )
        let unhitMixedBindings = [SceneScriptBindingIR(
            source: """
            export function update(value) { return !value; }
            export function cursorMove(event) { return; }
            """,
            owner: .init(kind: .object, objectIndex: 0, objectID: 80,
                         effectIndex: nil, effectID: nil,
                         passIndex: nil, passID: nil),
            targetPath: [.key("objects"), .index(0), .key("visible")],
            properties: [:], authoredValue: .bool(true),
            valueType: .boolean, wrapperKeys: ["script", "value"]
        )]
        let unhitMixedProjection = SceneScriptVectorProgram.project(
            descriptor: unhitDescriptor, scriptBindings: unhitMixedBindings
        )
        let unhitMixedCandidate = try SceneScriptQuickJSProgramCandidate.compile(
            authoredDescriptor: unhitDescriptor,
            runtimeDescriptor: unhitDescriptor,
            scriptBindings: unhitMixedBindings,
            vectorProjection: unhitMixedProjection,
            userPropertyDefinitions: [], timelineTargets: [],
            scalarExcludedTargets: [], stringExcludedTargets: [],
            admittedVectorPassTargets: [], generation: 65
        )
        let unhitMixedValue = unhitMixedCandidate.vectorProgram.evaluate(
            inputs: [.layer(layerID: 80, field: .visibility): .bool(true)],
            effectivePropertyValues: [:], frame: frame
        )
        let initCursorDescriptor = SceneRenderDescriptor(layers: [.init(
            id: 90, layerIndex: 0, name: "init-before-cursor", visible: true,
            originXYZ: [0, 0, 0], scaleXYZ: [1, 1, 1], scaleHasScript: true,
            alpha: 1, effects: [], contentKind: "image", sizeWH: [100, 100]
        )])
        let initCursorSource = """
        let initScale;
        export function init(value) {
            initScale = new Vec3(value.x + 10, value.y, value.z);
            return initScale;
        }
        export function update(value) {
            thisLayer.origin = new Vec3(value.x + 100, 0, 0);
            return value;
        }
        export function cursorEnter(event) {
            thisLayer.origin = new Vec3(initScale.x + 1, 0, 0);
        }
        """
        let initCursorBindings = [scaleBinding(
            layerID: 90, index: 0, source: initCursorSource
        )]
        let initCursorProjection = SceneScriptVectorProgram.project(
            descriptor: initCursorDescriptor,
            scriptBindings: initCursorBindings
        )
        let initCursorCandidate = try SceneScriptQuickJSProgramCandidate.compile(
            authoredDescriptor: initCursorDescriptor,
            runtimeDescriptor: initCursorDescriptor,
            scriptBindings: initCursorBindings,
            vectorProjection: initCursorProjection,
            userPropertyDefinitions: [], timelineTargets: [],
            scalarExcludedTargets: [], stringExcludedTargets: [],
            admittedVectorPassTargets: [], generation: 66
        )
        let initCursorHit = SceneScriptCursorHit(
            layerID: 90, worldPosition: .init(1, 2, 0),
            localPosition: .init(0.5, 0.5, 0)
        )
        let initCursorResult = initCursorCandidate.cursorProgram.dispatch(
            batch: .init(samples: [
                .init(hits: [90: initCursorHit], pointerPosition: .zero,
                      primaryButtonIsDown: false),
            ], overflowed: false),
            frame: frame,
            userPropertiesJSON: "{}"
        )
        let initCursorUpdate = initCursorCandidate.vectorProgram.evaluate(
            inputs: [.layer(layerID: 90, field: .scale): .vector3(1, 1, 1)],
            effectivePropertyValues: [:], frame: frame
        )
        // An `init`-only borrowed owner has no value hook of its own, so the
        // frame evaluation must still run it once to publish the value its
        // `init` produced; the cursor route alone cannot deliver it.
        let initOnlyDescriptor = SceneRenderDescriptor(layers: [.init(
            id: 91, layerIndex: 0, name: "init-only-cursor", visible: true,
            originXYZ: [0, 0, 0], scaleXYZ: [1, 1, 1], scaleHasScript: true,
            alpha: 1, effects: [], contentKind: "image", sizeWH: [100, 100]
        )])
        let initOnlySource = """
        export function init(value) {
            return new Vec3(value.x + 10, value.y, value.z);
        }
        export function cursorEnter(event) { return; }
        """
        let initOnlyBindings = [scaleBinding(
            layerID: 91, index: 0, source: initOnlySource
        )]
        let initOnlyProjection = SceneScriptVectorProgram.project(
            descriptor: initOnlyDescriptor,
            scriptBindings: initOnlyBindings
        )
        let initOnlyCandidate = try SceneScriptQuickJSProgramCandidate.compile(
            authoredDescriptor: initOnlyDescriptor,
            runtimeDescriptor: initOnlyDescriptor,
            scriptBindings: initOnlyBindings,
            vectorProjection: initOnlyProjection,
            userPropertyDefinitions: [], timelineTargets: [],
            scalarExcludedTargets: [], stringExcludedTargets: [],
            admittedVectorPassTargets: [], generation: 67
        )
        let initOnlyResult = initOnlyCandidate.cursorProgram.dispatch(
            batch: .init(samples: [
                .init(
                    hits: [91: SceneScriptCursorHit(
                        layerID: 91, worldPosition: .init(1, 2, 0),
                        localPosition: .init(0.5, 0.5, 0)
                    )],
                    pointerPosition: .zero, primaryButtonIsDown: false
                ),
            ], overflowed: false),
            frame: frame,
            userPropertiesJSON: "{}"
        )
        let initOnlyUpdate = initOnlyCandidate.vectorProgram.evaluate(
            inputs: [.layer(layerID: 91, field: .scale): .vector3(1, 1, 1)],
            effectivePropertyValues: [:], frame: frame
        )
        let initOnlyAfterPublish = initOnlyCandidate.vectorProgram.evaluate(
            inputs: [.layer(layerID: 91, field: .scale): .vector3(1, 1, 1)],
            effectivePropertyValues: [:], frame: frame
        )
        let retryAggregateCandidate = try retryAggregateBudgetCandidate(
            ownerCount: 260,
            invalidPrefixCount: 20,
            generation: 43
        )
        let localPreflightCandidate = try localPreflightPeerCandidate(
            generation: 45
        )
        let hardAggregateCandidate = try aggregateBudgetCandidate(
            ownerCount: 4_097,
            generation: 41
        )
        var oversizedCancellationEscaped = false
        do {
            _ = try aggregateBudgetCandidate(
                ownerCount: 4_097,
                generation: 44,
                cancellationCheck: {
                    throw CancellationProbe.Interruption.cancelled
                }
            )
        } catch CancellationProbe.Interruption.cancelled {
            oversizedCancellationEscaped = true
        }
        let plannedFamilySources = [
            vectorFailedSource, cursorFailedSource, scalarFailedSource,
            stringFailedSource, claimedSource, passFailedSource,
            enginePoisonSource, handleGuardSource,
        ]
        let maximumFamilySourceBytes = plannedFamilySources
            .map { $0.utf8.count }.max()!
        let aggregateFamilySourceBytes = plannedFamilySources
            .map { $0.utf8.count }.reduce(0, +)
        let exactSourceBoundaryCandidate = try familyCandidate(
            descriptor: descriptor,
            bindings: bindings,
            projection: projection,
            consumerTargets: consumerTargets,
            generation: 34,
            budget: sourceBudget(
                maximumOwnerBytes: maximumFamilySourceBytes,
                maximumCandidateBytes: aggregateFamilySourceBytes
            )
        )
        let ownerSourceProbe = BoundaryProbe()
        let ownerSourceRejectedCandidate = try familyCandidate(
            descriptor: descriptor,
            bindings: bindings,
            projection: projection,
            consumerTargets: consumerTargets,
            generation: 35,
            budget: sourceBudget(
                maximumOwnerBytes: maximumFamilySourceBytes - 1,
                maximumCandidateBytes: aggregateFamilySourceBytes
            ),
            cancellationCheck: { ownerSourceProbe.check() }
        )
        let aggregateSourceProbe = BoundaryProbe()
        let aggregateSourceRejectedCandidate = try familyCandidate(
            descriptor: descriptor,
            bindings: bindings,
            projection: projection,
            consumerTargets: consumerTargets,
            generation: 36,
            budget: sourceBudget(
                maximumOwnerBytes: maximumFamilySourceBytes,
                maximumCandidateBytes: aggregateFamilySourceBytes - 1
            ),
            cancellationCheck: { aggregateSourceProbe.check() }
        )
        let repeatedSource = "export function update(value) { return value }"
        let repeatedSourceProbe = BoundaryProbe()
        let repeatedSourceRejectedCandidate = try aggregateBudgetCandidate(
            ownerCount: 2,
            source: repeatedSource,
            generation: 37,
            budget: sourceBudget(
                maximumOwnerBytes: repeatedSource.utf8.count,
                maximumCandidateBytes: repeatedSource.utf8.count * 2 - 1
            ),
            cancellationCheck: { repeatedSourceProbe.check() }
        )
        let oomPolluterCandidate = try sharedMemoryCandidate(
            [("polluter", oomPolluterSource)], generation: 38
        )
        let oomFollowerCandidate = try sharedMemoryCandidate(
            [("follower", oomFollowerSource)], generation: 39
        )
        let oomCombinedCandidate = try sharedMemoryCandidate(
            [
                ("polluter", oomPolluterSource),
                ("follower", oomFollowerSource),
            ],
            generation: 40
        )
        let cancellationProbe = CancellationProbe()
        let infiniteSource = "for (;;) {}\nexport function update(value) { return value }"
        var cancellationEscaped = false
        do {
            _ = try aggregateBudgetCandidate(
                ownerCount: 1,
                source: infiniteSource,
                generation: 32,
                budget: sourceBudget(
                    maximumOwnerBytes: infiniteSource.utf8.count,
                    maximumCandidateBytes: infiniteSource.utf8.count,
                    interruptBudget: 32
                ),
                cancellationCheck: { try cancellationProbe.check() }
            )
        } catch CancellationProbe.Interruption.cancelled {
            cancellationEscaped = true
        }
        let payload: [String: Any] = [
            "projected": projection.targets.count,
            "consumers": consumerTargets.count,
            "domainCommitted": candidate.domain != nil,
            "vectorExpected": candidate.constructionReport.expectedVectorTargets.count,
            "vectorInstantiated": candidate.constructionReport
                .instantiatedVectorTargets.count,
            "vectorRejected": candidate.constructionReport.vectorFailures.count,
            "vectorFailureCodes": candidate.constructionReport.vectorFailures
                .values.map(\.code).sorted(),
            "cursorExpected": candidate.constructionReport
                .expectedCursorTargets.count,
            "cursorRejected": candidate.constructionReport.cursorFailures.count,
            "scalarExpected": candidate.constructionReport.expectedScalarTargets.count,
            "scalarRejected": candidate.constructionReport.scalarFailures.count,
            "stringExpected": candidate.constructionReport.expectedStringTargets.count,
            "stringRejected": candidate.constructionReport.stringFailures.count,
            "passRequested": candidate.vectorPassCompilation.requestedTargets.count,
            "passInstantiated": candidate.vectorPassCompilation
                .instantiatedTargets.count,
            "passRejected": candidate.vectorPassCompilation.failures.count,
            "definitions": committedProgram.definitions.count,
            "claimedValue": vector2(result.values[claimedTarget]),
            "claimedFailures": result.failures.count,
            "unclaimedPublished": result.values[unclaimedTarget] != nil,
            "failedPublished": result.values[failedTarget] != nil,
            "enginePoisonRejected": candidate.constructionReport
                .vectorFailures[enginePoisonTarget]?.code == "exception",
            "enginePoisonPublished": result.values[enginePoisonTarget] != nil,
            "handleGuardValue": vector2(result.values[handleGuardTarget]),
            "duplicates": duplicateProjection.duplicateTargets.count,
            "duplicateProjected": duplicateProjection.targets.count,
            "aggregateDomainCommitted": aggregateCandidate.domain != nil,
            "aggregateFailures": aggregateCandidate.constructionReport
                .vectorFailures.count,
            "aggregateFailureCodes": Array(Set(
                aggregateCandidate.constructionReport.vectorFailures
                    .values.map(\.code)
            )).sorted(),
            "claimedCursorOverlapCommitted": overlapCandidate.domain != nil,
            "claimedCursorOverlapStaticProjection": overlapProjection.targets.count,
            "claimedCursorOverlapVectorExpected": overlapCandidate
                .constructionReport.expectedVectorTargets.count,
            "claimedCursorOverlapVectorInstantiated": overlapCandidate
                .constructionReport.instantiatedVectorTargets.count,
            "claimedCursorOverlapCursorExpected": overlapCandidate
                .constructionReport.expectedCursorTargets.count,
            "claimedCursorOverlapCursorOwnerCount": overlapCandidate
                .cursorProgram.ownerCount,
            "claimedCursorOverlapCursorOwnsOwner": overlapCandidate.cursorProgram
                .bindings.first?.ownsOwner ?? false,
            "mixedCursorCommitted": mixedCandidate.domain != nil,
            "mixedCursorStaticProjection": mixedProjection.targets.count,
            "mixedCursorVectorExpected": mixedCandidate.constructionReport
                .expectedVectorTargets.count,
            "mixedCursorVectorInstantiated": mixedCandidate.constructionReport
                .instantiatedVectorTargets.count,
            "mixedCursorCursorExpected": mixedCandidate.constructionReport
                .expectedCursorTargets.count,
            "mixedCursorOwnerCount": mixedCandidate.cursorProgram.ownerCount,
            "mixedCursorBorrowed": mixedCandidate.cursorProgram.bindings
                .first?.ownsOwner == false,
            "constCursorVectorExpected": constCandidate.constructionReport
                .expectedVectorTargets.count,
            "constCursorExpected": constCandidate.constructionReport
                .expectedCursorTargets.count,
            "constCursorOwnerCount": constCandidate.cursorProgram.ownerCount,
            "constCursorBorrowed": constCandidate.cursorProgram.bindings
                .first?.ownsOwner == false,
            "constCursorMoveX": cursorMutationX(constDispatch),
            "constCursorMoveFailures": constDispatch.failures.count,
            "asyncCursorVectorExpected": asyncCandidate.constructionReport
                .expectedVectorTargets.count,
            "asyncCursorExpected": asyncCandidate.constructionReport
                .expectedCursorTargets.count,
            "asyncCursorMoveX": cursorMutationX(asyncDispatch),
            "asyncCursorMoveFailures": asyncDispatch.failures.count,
            "namedCursorVectorExpected": namedCandidate.constructionReport
                .expectedVectorTargets.count,
            "namedCursorExpected": namedCandidate.constructionReport
                .expectedCursorTargets.count,
            "namedCursorMoveX": cursorMutationX(namedDispatch),
            "namedCursorMoveFailures": namedDispatch.failures.count,
            "propertyCursorVectorOwners": propertyCursorCandidate.vectorProgram.definitions.count,
            "propertyCursorBorrowed": propertyCursorCandidate.cursorProgram.bindings
                .first?.ownsOwner == false,
            "propertyCursorFirstX": cursorMutationX(propertyFirst),
            "propertyCursorFirstFailures": propertyFirst.failures.count,
            "propertyCursorLiveX": cursorMutationX(propertyLive),
            "propertyCursorLiveFailures": propertyLive.failures.count,
            "reexportCursorVectorExpected": reexportCandidate.constructionReport
                .expectedVectorTargets.count,
            "reexportCursorExpected": reexportCandidate.constructionReport
                .expectedCursorTargets.count,
            "mediaMixedVectorExpected": mediaMixedCandidate.constructionReport
                .expectedVectorTargets.count,
            "mediaMixedCursorExpected": mediaMixedCandidate.constructionReport
                .expectedCursorTargets.count,
            "destroyMixedVectorExpected": destroyMixedCandidate.constructionReport
                .expectedVectorTargets.count,
            "destroyMixedCursorExpected": destroyMixedCandidate.constructionReport
                .expectedCursorTargets.count,
            "audioMixedVectorExpected": audioMixedCandidate.constructionReport
                .expectedVectorTargets.count,
            "audioMixedCursorExpected": audioMixedCandidate.constructionReport
                .expectedCursorTargets.count,
            "nonFunctionVectorExpected": nonFunctionCandidate.constructionReport
                .expectedVectorTargets.count,
            "nonFunctionCursorExpected": nonFunctionCandidate.constructionReport
                .expectedCursorTargets.count,
            "regexLiteralVectorExpected": regexLiteralCandidate.constructionReport
                .expectedVectorTargets.count,
            "regexLiteralCursorExpected": regexLiteralCandidate.constructionReport
                .expectedCursorTargets.count,
            "duplicateCursorVectorExpected": duplicateCursorCandidate
                .constructionReport.expectedVectorTargets.count,
            "duplicateCursorExpected": duplicateCursorCandidate
                .constructionReport.expectedCursorTargets.count,
            "duplicateCursorStaticProjection": duplicateCursorProjection.targets.count,
            "duplicateCursorDuplicates": duplicateCursorProjection.duplicateTargets.count,
            "mixedDuplicateTargets": mixedDuplicateProjection.duplicateTargets.count,
            "mixedDuplicateVectorExpected": mixedDuplicateCandidate.constructionReport
                .expectedVectorTargets.count,
            "mixedDuplicateCursorExpected": mixedDuplicateCandidate.constructionReport
                .expectedCursorTargets.count,
            "mixedDuplicateCursorOwners": mixedDuplicateCandidate.cursorProgram.ownerCount,
            "routedGenericMediaTargets": routedGeneric.mediaOwnerTargets.count,
            "routedGenericVectorOwners": routedGeneric.programs.vectorProgram.definitions.count,
            "routedGenericCursorOwners": routedGeneric.programs.cursorProgram.ownerCount,
            "routedDisabledMediaTargets": routedDisabled.mediaOwnerTargets.count,
            "routedDisabledVectorOwners": routedDisabled.programs.vectorProgram.definitions.count,
            "routedDisabledCursorOwners": routedDisabled.programs.cursorProgram.ownerCount,
            "vectorCursorCollisionVectorExpected": vectorCursorCollisionCandidate
                .constructionReport.expectedVectorTargets.count,
            "vectorCursorCollisionCursorExpected": vectorCursorCollisionCandidate
                .constructionReport.expectedCursorTargets.count,
            "effectCursorProjected": effectCursorProjection.targets.count,
            "effectCursorFailureCode": effectCursorCandidate.constructionReport
                .vectorFailures[effectCursorTarget]?.code ?? "missing",
            "effectCursorOwners": effectCursorCandidate.cursorProgram.ownerCount,
            "textCursorProjected": textCursorProjection.targets.count,
            "textCursorOwners": textCursorCandidate.cursorProgram.ownerCount,
            "textCursorDispatchFailures": textCursorDispatch.failures.count,
            "textCursorMutationX": cursorMutationX(textCursorDispatch),
            "unhitVectorOwners": unhitCandidate.vectorProgram.definitions.count,
            "unhitCursorExpected": unhitCandidate.constructionReport
                .expectedCursorTargets.count,
            "unhitCursorFailure": unhitCandidate.constructionReport
                .cursorFailures[.layer(layerID: 80, field: .visibility)]?.code
                    ?? "missing",
            "unhitCursorOwners": unhitCandidate.cursorProgram.ownerCount,
            "unhitMixedCursorFailure": unhitMixedCandidate.constructionReport
                .cursorFailures[.layer(layerID: 80, field: .visibility)]?.code
                    ?? "missing",
            "unhitMixedVectorValue": unhitMixedValue.values[
                .layer(layerID: 80, field: .visibility)
            ] == .bool(false),
            "initCursorOwners": initCursorCandidate.cursorProgram.ownerCount,
            "initCursorBorrowed": initCursorCandidate.cursorProgram.bindings
                .first?.ownsOwner == false,
            "initCursorFailures": initCursorResult.failures.count,
            "initCursorMutationX": cursorMutationX(initCursorResult),
            "initCursorUpdateFailures": initCursorUpdate.failures.count,
            "initCursorUpdateOriginX": initCursorUpdate.layerMutations
                .first?.origin.x ?? -1,
            "initCursorPublishedX": vectorX(initCursorUpdate.values[
                .layer(layerID: 90, field: .scale)
            ]),
            "initOnlyOwners": initOnlyCandidate.cursorProgram.ownerCount,
            "initOnlyCursorFailures": initOnlyResult.failures.count,
            "initOnlyUpdateFailures": initOnlyUpdate.failures.count,
            "initOnlyPublished": initOnlyUpdate.values[
                .layer(layerID: 91, field: .scale)
            ] != nil,
            "initOnlyPublishedX": vectorX(initOnlyUpdate.values[
                .layer(layerID: 91, field: .scale)
            ]),
            "initOnlyAfterPublishPublished": initOnlyAfterPublish.values[
                .layer(layerID: 91, field: .scale)
            ] != nil,
            "retryAggregateCommitted": retryAggregateCandidate.domain != nil,
            "retryAggregateVectorExpected": retryAggregateCandidate
                .constructionReport.expectedVectorTargets.count,
            "retryAggregateVectorInstantiated": retryAggregateCandidate
                .constructionReport.instantiatedVectorTargets.count,
            "retryAggregateVectorRejected": retryAggregateCandidate
                .constructionReport.vectorFailures.count,
            "localPreflightDomainCommitted": localPreflightCandidate.candidate.domain != nil,
            "localPreflightVectorExpected": localPreflightCandidate.candidate
                .constructionReport.expectedVectorTargets.count,
            "localPreflightVectorInstantiated": localPreflightCandidate.candidate
                .constructionReport.instantiatedVectorTargets.count,
            "localPreflightVectorRejected": localPreflightCandidate.candidate
                .constructionReport.vectorFailures.count,
            "localPreflightVectorFailureCodes": Array(Set(
                localPreflightCandidate.candidate.constructionReport.vectorFailures
                    .values.map(\.code)
            )).sorted(),
            "localPreflightBoundaryChecks": localPreflightCandidate.boundaryChecks,
            "hardAggregateDomainCommitted": hardAggregateCandidate.domain != nil,
            "hardAggregateFailures": hardAggregateCandidate.constructionReport
                .vectorFailures.count,
            "hardAggregateFailureCodes": Array(Set(
                hardAggregateCandidate.constructionReport.vectorFailures
                    .values.map(\.code)
            )).sorted(),
            "oversizedCancellationEscaped": oversizedCancellationEscaped,
            "exactSourceBoundaryCommitted": exactSourceBoundaryCandidate.domain != nil,
            "ownerSourceRejected": ownerSourceRejectedCandidate.domain == nil,
            "ownerSourceFailureCodes": failureCodes(
                ownerSourceRejectedCandidate
            ),
            "ownerSourceBoundaryChecks": ownerSourceProbe.count,
            "aggregateSourceRejected": aggregateSourceRejectedCandidate.domain == nil,
            "aggregateSourceFailureCodes": failureCodes(
                aggregateSourceRejectedCandidate
            ),
            "aggregateSourceBoundaryChecks": aggregateSourceProbe.count,
            "repeatedSourceRejected": repeatedSourceRejectedCandidate.domain == nil,
            "repeatedSourceFailureCodes": failureCodes(
                repeatedSourceRejectedCandidate
            ),
            "repeatedSourceBoundaryChecks": repeatedSourceProbe.count,
            "oomPolluterCommitted": oomPolluterCandidate.domain != nil,
            "oomFollowerCommitted": oomFollowerCandidate.domain != nil,
            "oomCombinedCommitted": oomCombinedCandidate.domain != nil,
            "oomCombinedExpected": oomCombinedCandidate.constructionReport
                .expectedVectorTargets.count,
            "oomCombinedInstantiated": oomCombinedCandidate.constructionReport
                .instantiatedVectorTargets.count,
            "oomCombinedFailureCodes": failureCodes(oomCombinedCandidate),
            "oomCombinedFailures": oomCombinedCandidate.constructionReport
                .vectorFailures.count,
            "oomCombinedPassInstantiated": oomCombinedCandidate
                .vectorPassCompilation.instantiatedTargets.count,
            "oomCombinedPassFailures": oomCombinedCandidate
                .vectorPassCompilation.failures.count,
            "cancellationChecks": cancellationProbe.count,
            "cancellationEscaped": cancellationEscaped,
            "routeDefault": SceneScriptVectorMediaRouteState.resolve(nil)?.rawValue
                ?? "invalid",
            "routeDisable": SceneScriptVectorMediaRouteState.resolve(
                "disable-generic"
            )?.rawValue ?? "invalid",
            "routeRestore": SceneScriptVectorMediaRouteState.resolve(nil)?.rawValue
                ?? "invalid",
            "routePrefer": SceneScriptVectorMediaRouteState.resolve(
                "prefer-generic"
            )?.rawValue ?? "invalid",
            "routeInvalid": SceneScriptVectorMediaRouteState.resolve("unknown") == nil,
            "routeObserveRejected": SceneScriptVectorMediaRouteState.resolve(
                "observe-only"
            ) == nil,
        ]
        let data = try JSONSerialization.data(
            withJSONObject: payload,
            options: [.sortedKeys]
        )
        print(String(decoding: data, as: UTF8.self))
    }

    static func target(_ name: String) -> SceneDynamicTarget {
        .effectConstant(
            layerID: 10,
            effectIndex: 0,
            passIndex: 0,
            name: name
        )
    }

    static func passBinding(key: String, source: String) -> SceneScriptBindingIR {
        .init(
            source: source,
            owner: .init(
                kind: .pass,
                objectIndex: 0,
                objectID: 10,
                effectIndex: 0,
                effectID: 100,
                passIndex: 0,
                passID: 200
            ),
            targetPath: [
                .key("objects"),
                .index(0),
                .key("effects"),
                .index(0),
                .key("passes"),
                .index(0),
                .key("constantshadervalues"),
                .key(key),
            ],
            properties: [:],
            authoredValue: .string("1 1"),
            valueType: .string,
            wrapperKeys: ["script", "value"]
        )
    }

    static func cursorAdmissionCandidate(
        descriptor: SceneRenderDescriptor,
        source: String,
        generation: UInt64
    ) throws -> SceneScriptQuickJSProgramCandidate {
        let bindings = [overlapVisibleBinding(source: source)]
        let projection = SceneScriptVectorProgram.project(
            descriptor: descriptor,
            scriptBindings: bindings
        )
        let budget = SceneScriptScalarBudget(
            heapBytes: 2 * 1024 * 1024,
            stackBytes: 512 * 1024,
            interruptBudget: 100_000,
            maximumOwnerSourceBytes: max(source.utf8.count, 1),
            maximumCandidateSourceBytes: max(source.utf8.count, 1)
        )
        return try SceneScriptQuickJSProgramCandidate.compile(
            authoredDescriptor: descriptor,
            runtimeDescriptor: descriptor,
            scriptBindings: bindings,
            vectorProjection: projection,
            userPropertyDefinitions: [],
            timelineTargets: [],
            scalarExcludedTargets: [],
            stringExcludedTargets: [],
            admittedVectorPassTargets: [],
            generation: generation,
            budget: budget
        )
    }

    static func routedCursorCandidate(
        descriptor: SceneRenderDescriptor,
        bindings: [SceneScriptBindingIR],
        projection: SceneScriptVectorCandidateCatalog,
        excluded: Set<SceneDynamicTarget>,
        generation: UInt64
    ) throws -> SceneScriptQuickJSProgramCandidate {
        try SceneScriptQuickJSProgramCandidate.compile(
            authoredDescriptor: descriptor,
            runtimeDescriptor: descriptor,
            scriptBindings: bindings,
            vectorProjection: projection.excludingTargets(excluded),
            routeExcludedTargets: excluded,
            userPropertyDefinitions: [],
            timelineTargets: [],
            scalarExcludedTargets: [],
            stringExcludedTargets: [],
            admittedVectorPassTargets: [],
            generation: generation
        )
    }

    static func overlapVisiblePropertyBinding(
        source: String,
        userPropertyKey: String? = nil
    ) -> SceneScriptBindingIR {
        .init(
            source: source,
            owner: .init(
                kind: .object, objectIndex: 0, objectID: 50,
                effectIndex: nil, effectID: nil, passIndex: nil, passID: nil
            ),
            targetPath: [.key("objects"), .index(0), .key("visible")],
            properties: ["step": userPropertyKey.map { key in .object([
                "user": .string(key), "value": .number(3)
            ]) } ?? .number(3)],
            authoredValue: .bool(true),
            valueType: .boolean,
            wrapperKeys: ["script", "scriptproperties", "value"]
        )
    }

    static func dispatchCursorMove(
        _ candidate: SceneScriptQuickJSProgramCandidate,
        frame: SceneScriptFrameInput,
        propertyRevision: UInt64? = nil
    ) -> SceneScriptCursorFrameResult {
        let hit = SceneScriptCursorHit(
            layerID: 50,
            worldPosition: .init(1, 2, 0),
            localPosition: .init(0.5, 0.5, 0)
        )
        return candidate.cursorProgram.dispatch(
            batch: .init(samples: [
                .init(hits: [50: hit], pointerPosition: .zero,
                      primaryButtonIsDown: false),
                .init(hits: [50: hit], pointerPosition: .init(0.5, 0.5),
                      primaryButtonIsDown: false),
            ], overflowed: false),
            frame: frame,
            userPropertiesJSON: "{}",
            propertyRevision: propertyRevision
        )
    }

    static func cursorMutationX(_ result: SceneScriptCursorFrameResult) -> Double {
        result.layerMutations.first?.origin.x ?? -1
    }

    static func vectorX(_ value: SceneDynamicValue?) -> Double {
        guard case let .vector3(x, _, _)? = value else { return -1 }
        return x
    }

    static func scaleBinding(
        layerID: Int,
        index: Int,
        source: String
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
            targetPath: [.key("objects"), .index(index), .key("scale")],
            properties: [:],
            authoredValue: .string("1 1 1"),
            valueType: .string,
            wrapperKeys: ["script", "value"]
        )
    }

    static func overlapOriginBinding(source: String) -> SceneScriptBindingIR {
        .init(
            source: source,
            owner: .init(
                kind: .object,
                objectIndex: 0,
                objectID: 50,
                effectIndex: nil,
                effectID: nil,
                passIndex: nil,
                passID: nil
            ),
            targetPath: [.key("objects"), .index(0), .key("origin")],
            properties: [:],
            authoredValue: .string("0 0 0"),
            valueType: .string,
            wrapperKeys: ["script", "value"]
        )
    }

    static func overlapVisibleBinding(source: String) -> SceneScriptBindingIR {
        .init(
            source: source,
            owner: .init(
                kind: .object,
                objectIndex: 0,
                objectID: 50,
                effectIndex: nil,
                effectID: nil,
                passIndex: nil,
                passID: nil
            ),
            targetPath: [.key("objects"), .index(0), .key("visible")],
            properties: [:],
            authoredValue: .bool(true),
            valueType: .boolean,
            wrapperKeys: ["script", "value"]
        )
    }

    static func objectVectorBinding(source: String) -> SceneScriptBindingIR {
        .init(
            source: source,
            owner: .init(
                kind: .object,
                objectIndex: 0,
                objectID: 10,
                effectIndex: nil,
                effectID: nil,
                passIndex: nil,
                passID: nil
            ),
            targetPath: [.key("objects"), .index(0), .key("origin")],
            properties: [:],
            authoredValue: .string("0 0 0"),
            valueType: .string,
            wrapperKeys: ["script", "value"]
        )
    }

    static func cursorBinding(source: String) -> SceneScriptBindingIR {
        .init(
            source: source,
            owner: .init(
                kind: .object,
                objectIndex: 1,
                objectID: 20,
                effectIndex: nil,
                effectID: nil,
                passIndex: nil,
                passID: nil
            ),
            targetPath: [.key("objects"), .index(1), .key("visible")],
            properties: [:],
            authoredValue: .bool(true),
            valueType: .boolean,
            wrapperKeys: ["script", "value"]
        )
    }

    static func scalarBinding(source: String) -> SceneScriptBindingIR {
        .init(
            source: source,
            owner: .init(
                kind: .object,
                objectIndex: 2,
                objectID: 30,
                effectIndex: nil,
                effectID: nil,
                passIndex: nil,
                passID: nil
            ),
            targetPath: [.key("objects"), .index(2), .key("pointsize")],
            properties: [:],
            authoredValue: .number(48),
            valueType: .number,
            wrapperKeys: ["script", "value"]
        )
    }

    static func stringBinding(source: String) -> SceneScriptBindingIR {
        .init(
            source: source,
            owner: .init(
                kind: .object,
                objectIndex: 2,
                objectID: 30,
                effectIndex: nil,
                effectID: nil,
                passIndex: nil,
                passID: nil
            ),
            targetPath: [.key("objects"), .index(2), .key("text")],
            properties: [:],
            authoredValue: .string("authored"),
            valueType: .string,
            wrapperKeys: ["script", "value"]
        )
    }

    static func vector2(_ value: SceneDynamicValue?) -> [Double] {
        guard case let .vector2(x, y)? = value else { return [] }
        return [x, y]
    }

    static func sourceBudget(
        maximumOwnerBytes: Int,
        maximumCandidateBytes: Int,
        interruptBudget: UInt64 = 100_000
    ) -> SceneScriptScalarBudget {
        .init(
            heapBytes: 2 * 1024 * 1024,
            stackBytes: 512 * 1024,
            interruptBudget: interruptBudget,
            maximumOwnerSourceBytes: maximumOwnerBytes,
            maximumCandidateSourceBytes: maximumCandidateBytes
        )
    }

    static func familyCandidate(
        descriptor: SceneRenderDescriptor,
        bindings: [SceneScriptBindingIR],
        projection: SceneScriptVectorCandidateCatalog,
        consumerTargets: Set<SceneDynamicTarget>,
        generation: UInt64,
        budget: SceneScriptScalarBudget,
        cancellationCheck: @escaping @Sendable () throws -> Void = {}
    ) throws -> SceneScriptQuickJSProgramCandidate {
        try SceneScriptQuickJSProgramCandidate.compile(
            authoredDescriptor: descriptor,
            runtimeDescriptor: descriptor,
            scriptBindings: bindings,
            vectorProjection: projection,
            userPropertyDefinitions: [],
            timelineTargets: [],
            scalarExcludedTargets: [],
            stringExcludedTargets: [],
            admittedVectorPassTargets: consumerTargets,
            generation: generation,
            budget: budget,
            cancellationCheck: cancellationCheck
        )
    }

    static func failureCodes(
        _ candidate: SceneScriptQuickJSProgramCandidate
    ) -> [String] {
        let report = candidate.constructionReport
        var codes = report.vectorFailures.values.map(\.code)
        codes.append(contentsOf: report.cursorFailures.values.map(\.code))
        codes.append(contentsOf: report.scalarFailures.values.map(\.code))
        codes.append(contentsOf: report.stringFailures.values.map(\.code))
        return Array(Set(codes)).sorted()
    }

    static func aggregateBudgetCandidate(
        ownerCount: Int = 90,
        source: String = "export function update(value) { return value }",
        generation: UInt64 = 33,
        budget: SceneScriptScalarBudget = .default,
        cancellationCheck: @escaping @Sendable () throws -> Void = {}
    ) throws -> SceneScriptQuickJSProgramCandidate {
        var shaderValues: [String: SceneRenderDescriptor.ShaderValue] = [:]
        var bindings: [SceneScriptBindingIR] = []
        var admittedTargets: Set<SceneDynamicTarget> = []
        for index in 0..<ownerCount {
            let name = "value\(index)"
            shaderValues[name] = .init(
                scriptSource: source,
                components: [1, 1]
            )
            bindings.append(passBinding(key: name, source: source))
            admittedTargets.insert(target(name))
        }
        let descriptor = SceneRenderDescriptor(layers: [.init(
            id: 10,
            layerIndex: 0,
            name: "aggregate-budget",
            visible: true,
            originXYZ: [0, 0, 0],
            scaleXYZ: [1, 1, 1],
            scaleHasScript: false,
            alpha: 1,
            effects: [.init(
                name: "aggregate",
                effectID: 100,
                passes: [.init(
                    passIndex: 0,
                    id: 200,
                    constantShaderValues: shaderValues
                )]
            )]
        )])
        let projection = SceneScriptVectorProgram.project(
            descriptor: descriptor,
            scriptBindings: bindings
        )
        return try SceneScriptQuickJSProgramCandidate.compile(
            authoredDescriptor: descriptor,
            runtimeDescriptor: descriptor,
            scriptBindings: bindings,
            vectorProjection: projection,
            userPropertyDefinitions: [],
            timelineTargets: [],
            scalarExcludedTargets: [],
            stringExcludedTargets: [],
            admittedVectorPassTargets: admittedTargets,
            generation: generation,
            budget: budget,
            cancellationCheck: cancellationCheck
        )
    }

    static func retryAggregateBudgetCandidate(
        ownerCount: Int,
        invalidPrefixCount: Int,
        generation: UInt64
    ) throws -> SceneScriptQuickJSProgramCandidate {
        let validSource = "export function update(value) { return value }"
        var layers: [SceneRenderDescriptor.Layer] = []
        var bindings: [SceneScriptBindingIR] = []
        for index in 0..<ownerCount {
            let source = index < invalidPrefixCount ? passFailedSource : validSource
            let layerID = 1_000 + index
            layers.append(.init(
                id: layerID,
                layerIndex: index,
                name: "retry-\(index)",
                visible: true,
                originXYZ: [0, 0, 0],
                scaleXYZ: [1, 1, 1],
                scaleHasScript: false,
                alpha: 1,
                effects: [],
                contentKind: "image",
                sizeWH: [100, 100]
            ))
            bindings.append(retryVisibilityBinding(
                objectIndex: index,
                layerID: layerID,
                source: source
            ))
        }
        let descriptor = SceneRenderDescriptor(layers: layers)
        let projection = SceneScriptVectorProgram.project(
            descriptor: descriptor,
            scriptBindings: bindings
        )
        let sourceBytes = bindings.map(\.source.utf8.count)
        let budget = SceneScriptScalarBudget(
            heapBytes: 8 * 1024 * 1024,
            stackBytes: 512 * 1024,
            interruptBudget: 100_000,
            maximumOwnerSourceBytes: sourceBytes.max()!,
            maximumCandidateSourceBytes: sourceBytes.reduce(0, +)
        )
        return try familyCandidate(
            descriptor: descriptor,
            bindings: bindings,
            projection: projection,
            consumerTargets: [],
            generation: generation,
            budget: budget
        )
    }

    static func localPreflightPeerCandidate(
        generation: UInt64
    ) throws -> (
        candidate: SceneScriptQuickJSProgramCandidate,
        boundaryChecks: Int
    ) {
        let validSource = "export function update(value) { return value }"
        let bindings = [
            retryVisibilityBinding(objectIndex: 0, layerID: 2, source: ""),
            retryVisibilityBinding(objectIndex: 1, layerID: 3, source: validSource),
        ]
        let descriptor = SceneRenderDescriptor(layers: [
            .init(
                id: 2, layerIndex: 0, name: "local-preflight-empty",
                visible: true, originXYZ: [0, 0, 0], scaleXYZ: [1, 1, 1],
                scaleHasScript: false, alpha: 1, effects: [],
                contentKind: "image", sizeWH: [100, 100]
            ),
            .init(
                id: 3, layerIndex: 1, name: "local-preflight-peer",
                visible: true, originXYZ: [0, 0, 0], scaleXYZ: [1, 1, 1],
                scaleHasScript: false, alpha: 1, effects: [],
                contentKind: "image", sizeWH: [100, 100]
            ),
        ])
        let projection = SceneScriptVectorProgram.project(
            descriptor: descriptor,
            scriptBindings: bindings
        )
        let sourceBytes = bindings.map(\.source.utf8.count)
        let probe = BoundaryProbe()
        let candidate = try familyCandidate(
            descriptor: descriptor,
            bindings: bindings,
            projection: projection,
            consumerTargets: [],
            generation: generation,
            budget: sourceBudget(
                maximumOwnerBytes: sourceBytes.max()!,
                maximumCandidateBytes: sourceBytes.reduce(0, +)
            ),
            cancellationCheck: { probe.check() }
        )
        return (candidate, probe.count)
    }

    static func retryVisibilityBinding(
        objectIndex: Int,
        layerID: Int,
        source: String
    ) -> SceneScriptBindingIR {
        .init(
            source: source,
            owner: .init(
                kind: .object,
                objectIndex: objectIndex,
                objectID: layerID,
                effectIndex: nil,
                effectID: nil,
                passIndex: nil,
                passID: nil
            ),
            targetPath: [
                .key("objects"), .index(objectIndex), .key("visible")
            ],
            properties: [:],
            authoredValue: .bool(true),
            valueType: .boolean,
            wrapperKeys: ["script", "value"]
        )
    }

    static func sharedMemoryCandidate(
        _ entries: [(String, String)],
        generation: UInt64
    ) throws -> SceneScriptQuickJSProgramCandidate {
        var shaderValues: [String: SceneRenderDescriptor.ShaderValue] = [:]
        var bindings: [SceneScriptBindingIR] = []
        var admittedTargets: Set<SceneDynamicTarget> = []
        for (name, source) in entries {
            shaderValues[name] = .init(
                scriptSource: source,
                components: [1, 1]
            )
            bindings.append(passBinding(key: name, source: source))
            admittedTargets.insert(target(name))
        }
        let descriptor = SceneRenderDescriptor(layers: [.init(
            id: 10,
            layerIndex: 0,
            name: "shared-memory",
            visible: true,
            originXYZ: [0, 0, 0],
            scaleXYZ: [1, 1, 1],
            scaleHasScript: false,
            alpha: 1,
            effects: [.init(
                name: "shared-memory",
                effectID: 100,
                passes: [.init(
                    passIndex: 0,
                    id: 200,
                    constantShaderValues: shaderValues
                )]
            )]
        )])
        let projection = SceneScriptVectorProgram.project(
            descriptor: descriptor,
            scriptBindings: bindings
        )
        let sourceBytes = entries.map { $0.1.utf8.count }
        let budget = SceneScriptScalarBudget(
            heapBytes: 700 * 1024,
            stackBytes: 256 * 1024,
            interruptBudget: 100_000,
            maximumOwnerSourceBytes: sourceBytes.max()!,
            maximumCandidateSourceBytes: sourceBytes.reduce(0, +)
        )
        return try familyCandidate(
            descriptor: descriptor,
            bindings: bindings,
            projection: projection,
            consumerTargets: admittedTargets,
            generation: generation,
            budget: budget
        )
    }

    final class BoundaryProbe: @unchecked Sendable {
        private(set) var count = 0

        func check() {
            count += 1
        }
    }

    final class CancellationProbe: @unchecked Sendable {
        enum Interruption: Error {
            case cancelled
        }

        private(set) var count = 0

        func check() throws {
            count += 1
            if count == 4 { throw Interruption.cancelled }
        }
    }

    static let claimedSource = """
    if (globalThis.__mwxVectorPoison === true ||
        globalThis.__mwxCursorPoison === true ||
        globalThis.__mwxScalarPoison === true ||
        globalThis.__mwxStringPoison === true ||
        globalThis.__mwxPassPoison === true) {
      throw new Error("failed family contaminated the committed domain")
    }
    if (globalThis.__mwxUnclaimedConstructed === true) {
      throw new Error("non-consumer pass owner executed")
    }
    globalThis.__mwxClaimedConstructionCount =
      (globalThis.__mwxClaimedConstructionCount || 0) + 1
    if (globalThis.__mwxClaimedConstructionCount !== 1) {
      throw new Error("committed owner was constructed more than once")
    }
    export function update(value) {
      if (globalThis.__mwxVectorPoison === true ||
          globalThis.__mwxCursorPoison === true ||
          globalThis.__mwxScalarPoison === true ||
          globalThis.__mwxStringPoison === true ||
          globalThis.__mwxPassPoison === true ||
          globalThis.__mwxUnclaimedConstructed === true) {
        throw new Error("discarded candidate state escaped")
      }
      return value.multiply(2)
    }
    export function destroy() {
      throw new Error("candidate discard must not invoke authored destroy")
    }
    """

    static let unclaimedSource = """
    globalThis.__mwxUnclaimedConstructed = true
    throw new Error("non-consumer pass owner must remain cold")
    export function update(value) { return value }
    """

    static let vectorFailedSource = """
    globalThis.__mwxVectorPoison = true
    throw new Error("vector non-pass owner construction failed")
    export function update(value) { return value }
    """

    static let cursorFailedSource = """
    globalThis.__mwxCursorPoison = true
    throw new Error("cursor owner construction failed")
    export function cursorMove(event) {}
    """

    static let scalarFailedSource = """
    globalThis.__mwxScalarPoison = true
    throw new Error("scalar owner construction failed")
    export function update(value) { return value }
    """

    static let stringFailedSource = """
    globalThis.__mwxStringPoison = true
    throw new Error("string owner construction failed")
    export function update(value) { return value }
    """

    static let passFailedSource = """
    globalThis.__mwxPassPoison = true
    throw new Error("claimed pass owner construction failed")
    export function update(value) { return value }
    """

    static let enginePoisonSource = """
    Object.defineProperty(globalThis, "engine", {
      get() { throw new Error("poisoned engine") }, set(_) {}
    })
    export function update(value) { return value }
    """

    static let handleGuardSource = """
    for (const name of ["thisLayer", "thisScene", "thisObject"]) {
      let replaced = false
      try { Object.defineProperty(globalThis, name, {get() { return null }}); replaced = true } catch (_) {}
      if (replaced) throw new Error("replaceable owner handle")
    }
    export function update(value) {
      for (const name of ["thisLayer", "thisScene", "thisObject"]) {
        try { globalThis[name] = null } catch (_) {}
        if (globalThis[name] === null) throw new Error("mutable owner handle")
      }
      return value.multiply(2)
    }
    """

    static let oomPolluterSource = """
    globalThis.__mwxRetainedOOMPolluter = new ArrayBuffer(320 * 1024)
    export function update(value) { return value }
    """

    static let oomFollowerSource = """
    globalThis.__mwxRetainedOOMFollower = new ArrayBuffer(320 * 1024)
    export function update(value) { return value }
    """
}
'''
