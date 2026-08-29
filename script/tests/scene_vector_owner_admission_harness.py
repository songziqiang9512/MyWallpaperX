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
                .expectedCursorLayerIDs.count,
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
