import Foundation

private nonisolated struct SceneScriptQuickJSCandidateBoundaryInterruption: Error {}

private nonisolated final class SceneScriptQuickJSCandidateControl:
    @unchecked Sendable {
    private let cancellationCheck: @Sendable () throws -> Void
    private var pendingCancellation: Error?

    init(cancellationCheck: @escaping @Sendable () throws -> Void) {
        self.cancellationCheck = cancellationCheck
    }

    func checkBoundary() throws {
        if let pendingCancellation { throw pendingCancellation }
        try cancellationCheck()
    }

    func checkOwnerBoundary() throws {
        if pendingCancellation != nil {
            throw SceneScriptQuickJSCandidateBoundaryInterruption()
        }
        do {
            try cancellationCheck()
        } catch {
            if pendingCancellation == nil { pendingCancellation = error }
            throw SceneScriptQuickJSCandidateBoundaryInterruption()
        }
    }
}

nonisolated struct SceneScriptQuickJSProgramConstructionReport: Sendable {
    let expectedVectorTargets: Set<SceneDynamicTarget>
    let instantiatedVectorTargets: Set<SceneDynamicTarget>
    let vectorFailures: [SceneDynamicTarget: SceneScriptScalarRuntimeFailure]
    let expectedScalarTargets: Set<SceneDynamicTarget>
    let instantiatedScalarTargets: Set<SceneDynamicTarget>
    let scalarFailures: [SceneDynamicTarget: SceneScriptScalarRuntimeFailure]
    let expectedStringTargets: Set<SceneDynamicTarget>
    let instantiatedStringTargets: Set<SceneDynamicTarget>
    let stringFailures: [SceneDynamicTarget: SceneScriptScalarRuntimeFailure]
    let expectedCursorLayerIDs: Set<Int>
    let instantiatedCursorLayerIDs: Set<Int>
    let cursorFailures: [Int: SceneScriptScalarRuntimeFailure]

    var isComplete: Bool {
        Self.isComplete(
            expectedVectorTargets,
            instantiatedVectorTargets,
            Set(vectorFailures.keys)
        ) && Self.isComplete(
            expectedScalarTargets,
            instantiatedScalarTargets,
            Set(scalarFailures.keys)
        ) && Self.isComplete(
            expectedStringTargets,
            instantiatedStringTargets,
            Set(stringFailures.keys)
        ) && Self.isComplete(
            expectedCursorLayerIDs,
            instantiatedCursorLayerIDs,
            Set(cursorFailures.keys)
        )
    }

    private static func isComplete<Identity: Hashable>(
        _ expected: Set<Identity>,
        _ instantiated: Set<Identity>,
        _ failed: Set<Identity>
    ) -> Bool {
        instantiated.isDisjoint(with: failed)
            && instantiated.union(failed) == expected
    }
}

/// Builds every per-scene QuickJS owner family in a fresh candidate domain.
/// Any evaluated module that does not become an owner rejects that whole
/// domain; the failed identity is excluded before the complete family is
/// rebuilt. Shared-domain OOM rejects the entire candidate instead of blaming
/// one identity. Only a clean, conservation-checked domain reaches the frame
/// path.
nonisolated struct SceneScriptQuickJSProgramCandidate: @unchecked Sendable {
    let domain: SceneScriptQuickJSDomain?
    let vectorProgram: SceneScriptVectorProgram
    let cursorProgram: SceneScriptCursorProgram
    let scalarProgram: SceneScriptScalarProgram
    let stringProgram: SceneScriptStringProgram
    let vectorPassCompilation: SceneScriptVectorPassCompilation
    let constructionReport: SceneScriptQuickJSProgramConstructionReport

    static func compile(
        authoredDescriptor: SceneRenderDescriptor,
        runtimeDescriptor: SceneRenderDescriptor,
        scriptBindings: [SceneScriptBindingIR],
        vectorProjection: SceneScriptVectorCandidateCatalog,
        userPropertyDefinitions: [SceneUserPropertyDefinition],
        timelineTargets: Set<SceneDynamicTarget>,
        scalarExcludedTargets: Set<SceneDynamicTarget>,
        stringExcludedTargets: Set<SceneDynamicTarget>,
        admittedVectorPassTargets: Set<SceneDynamicTarget>,
        generation: UInt64,
        budget: SceneScriptScalarBudget = .default,
        storageSession: SceneScriptLocalStorageSession? = nil,
        cancellationCheck: @escaping @Sendable () throws -> Void = {}
    ) throws -> Self {
        let expectedVectorTargets = vectorProjection.nonPassTargets.union(
            admittedVectorPassTargets
        )
        let expectedScalarTargets = SceneScriptScalarProgram.projectedTargets(
            descriptor: authoredDescriptor,
            scriptBindings: scriptBindings,
            timelineTargets: timelineTargets
        ).subtracting(scalarExcludedTargets)
        let expectedStringTargets = SceneScriptStringProgram.projectedTargets(
            descriptor: runtimeDescriptor,
            scriptBindings: scriptBindings,
            excludedTargets: stringExcludedTargets
        )
        let projectedCursorLayerIDs =
            SceneScriptCursorProgram.projectedStandaloneLayerIDs(
                descriptor: authoredDescriptor,
                scriptBindings: scriptBindings
            )
        let makeUnavailable: (SceneScriptScalarRuntimeFailure) -> Self = { failure in
            unavailable(
                authoredDescriptor: authoredDescriptor,
                runtimeDescriptor: runtimeDescriptor,
                scriptBindings: scriptBindings,
                vectorProjection: vectorProjection,
                userPropertyDefinitions: userPropertyDefinitions,
                timelineTargets: timelineTargets,
                stringExcludedTargets: stringExcludedTargets,
                expectedVectorTargets: expectedVectorTargets,
                expectedScalarTargets: expectedScalarTargets,
                expectedStringTargets: expectedStringTargets,
                expectedCursorLayerIDs: projectedCursorLayerIDs,
                admittedVectorPassTargets: admittedVectorPassTargets,
                generation: generation,
                budget: budget,
                failure: failure
            )
        }
        let expectedOwnerCount = expectedVectorTargets.count
            + expectedScalarTargets.count + expectedStringTargets.count
            + projectedCursorLayerIDs.count
        let aggregateConstructionWorkLimit = 4_096
        try cancellationCheck()
        let plannedVectorTargets = vectorProjection.nonPassTargets.union(
            admittedVectorPassTargets.intersection(vectorProjection.passTargets)
        )
        var plannedOwnerSources = vectorProjection.uniqueCandidates.compactMap {
            plannedVectorTargets.contains($0.definition.target) ? $0.source : nil
        }
        plannedOwnerSources.append(contentsOf:
            SceneScriptCursorProgram.projectedStandaloneOwnerSources(
                descriptor: authoredDescriptor,
                scriptBindings: scriptBindings
            )
        )
        plannedOwnerSources.append(contentsOf:
            SceneScriptScalarProgram.projectedOwnerSources(
                descriptor: authoredDescriptor,
                scriptBindings: scriptBindings,
                timelineTargets: timelineTargets,
                excludedTargets: scalarExcludedTargets
            )
        )
        plannedOwnerSources.append(contentsOf:
            SceneScriptStringProgram.projectedOwnerSources(
                descriptor: runtimeDescriptor,
                scriptBindings: scriptBindings,
                excludedTargets: stringExcludedTargets
            )
        )
        if let failure = budget.candidateSourceFailure(plannedOwnerSources) {
            return makeUnavailable(failure)
        }
        let maximumAttempts = expectedVectorTargets.count
            + expectedScalarTargets.count + expectedStringTargets.count
            + projectedCursorLayerIDs.count + 1
        var rejectedVectorTargets: Set<SceneDynamicTarget> = []
        var rejectedScalarTargets: Set<SceneDynamicTarget> = []
        var rejectedStringTargets: Set<SceneDynamicTarget> = []
        var rejectedCursorLayerIDs: Set<Int> = []
        var vectorFailures: [
            SceneDynamicTarget: SceneScriptScalarRuntimeFailure
        ] = [:]
        var vectorPassFailures: [
            SceneDynamicTarget: SceneScriptScalarRuntimeFailure
        ] = [:]
        var scalarFailures: [
            SceneDynamicTarget: SceneScriptScalarRuntimeFailure
        ] = [:]
        var stringFailures: [
            SceneDynamicTarget: SceneScriptScalarRuntimeFailure
        ] = [:]
        var cursorFailures: [Int: SceneScriptScalarRuntimeFailure] = [:]
        var expectedCursorLayerIDs: Set<Int> = []
        var aggregateConstructionWork = 0
        let control = SceneScriptQuickJSCandidateControl(
            cancellationCheck: cancellationCheck
        )

        for _ in 0...maximumAttempts {
            let rejectedOwnerCount = rejectedVectorTargets.count
                + rejectedScalarTargets.count + rejectedStringTargets.count
                + rejectedCursorLayerIDs.count
            let remainingOwnerCount = expectedOwnerCount - rejectedOwnerCount
            guard remainingOwnerCount >= 0,
                  remainingOwnerCount <= aggregateConstructionWorkLimit
                    - aggregateConstructionWork else {
                return makeUnavailable(.budgetExceeded(
                    "SceneScript candidate aggregate construction work exceeds 4096"
                ))
            }
            aggregateConstructionWork += remainingOwnerCount
            try control.checkBoundary()
            let domain: SceneScriptQuickJSDomain
            do {
                domain = try SceneScriptQuickJSDomain(budget: budget)
                domain.installConstructionBoundaryCheck {
                    try control.checkOwnerBoundary()
                }
                try domain.configureLayerRuntimeFields(authoredDescriptor)
            } catch {
                return makeUnavailable(typedFailure(error))
            }
            let vectorConstruction =
                SceneScriptVectorProgram.compileNonPassCandidate(
                    domain: domain,
                    descriptor: authoredDescriptor,
                    projection: vectorProjection,
                    userPropertyDefinitions: userPropertyDefinitions,
                    rejectedTargets: rejectedVectorTargets,
                    generation: generation,
                    budget: budget
                )
            try control.checkBoundary()
            if let failure = domainFatalFailure(vectorConstruction.failures) {
                return makeUnavailable(failure)
            }
            guard valid(
                vectorConstruction.requestedTargets,
                vectorConstruction.instantiatedTargets,
                vectorConstruction.failures,
                vectorConstruction.deferredTargets
            ) else {
                return unavailable(
                    authoredDescriptor: authoredDescriptor,
                    runtimeDescriptor: runtimeDescriptor,
                    scriptBindings: scriptBindings,
                    vectorProjection: vectorProjection,
                    userPropertyDefinitions: userPropertyDefinitions,
                    timelineTargets: timelineTargets,
                    stringExcludedTargets: stringExcludedTargets,
                    expectedVectorTargets: expectedVectorTargets,
                    expectedScalarTargets: expectedScalarTargets,
                    expectedStringTargets: expectedStringTargets,
                    expectedCursorLayerIDs: projectedCursorLayerIDs,
                    admittedVectorPassTargets: admittedVectorPassTargets,
                    generation: generation,
                    budget: budget,
                    failure: .invalidArgument(
                        "SceneScript vector candidate ownership mismatch"
                    )
                )
            }
            if !vectorConstruction.failures.isEmpty {
                record(
                    vectorConstruction.failures,
                    family: "vector-nonpass",
                    failures: &vectorFailures,
                    rejected: &rejectedVectorTargets
                )
                // The next iteration reconstructs every surviving owner in a clean domain.
                continue
            }
            guard vectorConstruction.deferredTargets.isEmpty else {
                return unavailable(
                    authoredDescriptor: authoredDescriptor,
                    runtimeDescriptor: runtimeDescriptor,
                    scriptBindings: scriptBindings,
                    vectorProjection: vectorProjection,
                    userPropertyDefinitions: userPropertyDefinitions,
                    timelineTargets: timelineTargets,
                    stringExcludedTargets: stringExcludedTargets,
                    expectedVectorTargets: expectedVectorTargets,
                    expectedScalarTargets: expectedScalarTargets,
                    expectedStringTargets: expectedStringTargets,
                    expectedCursorLayerIDs: projectedCursorLayerIDs,
                    admittedVectorPassTargets: admittedVectorPassTargets,
                    generation: generation,
                    budget: budget,
                    failure: .invalidArgument(
                        "SceneScript vector candidate deferred without failure"
                    )
                )
            }
            let cursorConstruction = SceneScriptCursorProgram.compileCandidate(
                domain: domain,
                descriptor: authoredDescriptor,
                scriptBindings: scriptBindings,
                borrowedOwners:
                    vectorConstruction.program.cursorOwnerRegistrations,
                rejectedLayerIDs: rejectedCursorLayerIDs,
                generation: generation,
                budget: budget
            )
            try control.checkBoundary()
            if let failure = domainFatalFailure(cursorConstruction.failures) {
                return makeUnavailable(failure)
            }
            expectedCursorLayerIDs.formUnion(
                cursorConstruction.requestedLayerIDs
            )
            guard valid(
                cursorConstruction.requestedLayerIDs,
                cursorConstruction.instantiatedLayerIDs,
                cursorConstruction.failures,
                cursorConstruction.deferredLayerIDs
            ) else {
                return unavailable(
                    authoredDescriptor: authoredDescriptor,
                    runtimeDescriptor: runtimeDescriptor,
                    scriptBindings: scriptBindings,
                    vectorProjection: vectorProjection,
                    userPropertyDefinitions: userPropertyDefinitions,
                    timelineTargets: timelineTargets,
                    stringExcludedTargets: stringExcludedTargets,
                    expectedVectorTargets: expectedVectorTargets,
                    expectedScalarTargets: expectedScalarTargets,
                    expectedStringTargets: expectedStringTargets,
                    expectedCursorLayerIDs: projectedCursorLayerIDs,
                    admittedVectorPassTargets: admittedVectorPassTargets,
                    generation: generation,
                    budget: budget,
                    failure: .invalidArgument(
                        "SceneScript cursor candidate ownership mismatch"
                    )
                )
            }
            if !cursorConstruction.failures.isEmpty {
                record(
                    cursorConstruction.failures,
                    family: "cursor",
                    failures: &cursorFailures,
                    rejected: &rejectedCursorLayerIDs
                )
                continue
            }
            guard cursorConstruction.deferredLayerIDs.isEmpty else {
                return unavailable(
                    authoredDescriptor: authoredDescriptor,
                    runtimeDescriptor: runtimeDescriptor,
                    scriptBindings: scriptBindings,
                    vectorProjection: vectorProjection,
                    userPropertyDefinitions: userPropertyDefinitions,
                    timelineTargets: timelineTargets,
                    stringExcludedTargets: stringExcludedTargets,
                    expectedVectorTargets: expectedVectorTargets,
                    expectedScalarTargets: expectedScalarTargets,
                    expectedStringTargets: expectedStringTargets,
                    expectedCursorLayerIDs: projectedCursorLayerIDs,
                    admittedVectorPassTargets: admittedVectorPassTargets,
                    generation: generation,
                    budget: budget,
                    failure: .invalidArgument(
                        "SceneScript cursor candidate deferred without failure"
                    )
                )
            }
            let scalarConstruction = SceneScriptScalarProgram.compileCandidate(
                domain: domain,
                descriptor: authoredDescriptor,
                scriptBindings: scriptBindings,
                userPropertyDefinitions: userPropertyDefinitions,
                timelineTargets: timelineTargets,
                excludedTargets: scalarExcludedTargets,
                rejectedTargets: rejectedScalarTargets,
                generation: generation,
                budget: budget
            )
            try control.checkBoundary()
            if let failure = domainFatalFailure(scalarConstruction.failures) {
                return makeUnavailable(failure)
            }
            guard valid(
                scalarConstruction.requestedTargets,
                scalarConstruction.instantiatedTargets,
                scalarConstruction.failures,
                scalarConstruction.deferredTargets
            ) else {
                return unavailable(
                    authoredDescriptor: authoredDescriptor,
                    runtimeDescriptor: runtimeDescriptor,
                    scriptBindings: scriptBindings,
                    vectorProjection: vectorProjection,
                    userPropertyDefinitions: userPropertyDefinitions,
                    timelineTargets: timelineTargets,
                    stringExcludedTargets: stringExcludedTargets,
                    expectedVectorTargets: expectedVectorTargets,
                    expectedScalarTargets: expectedScalarTargets,
                    expectedStringTargets: expectedStringTargets,
                    expectedCursorLayerIDs: projectedCursorLayerIDs,
                    admittedVectorPassTargets: admittedVectorPassTargets,
                    generation: generation,
                    budget: budget,
                    failure: .invalidArgument(
                        "SceneScript scalar candidate ownership mismatch"
                    )
                )
            }
            if !scalarConstruction.failures.isEmpty {
                record(
                    scalarConstruction.failures,
                    family: "scalar",
                    failures: &scalarFailures,
                    rejected: &rejectedScalarTargets
                )
                continue
            }
            guard scalarConstruction.deferredTargets.isEmpty else {
                return unavailable(
                    authoredDescriptor: authoredDescriptor,
                    runtimeDescriptor: runtimeDescriptor,
                    scriptBindings: scriptBindings,
                    vectorProjection: vectorProjection,
                    userPropertyDefinitions: userPropertyDefinitions,
                    timelineTargets: timelineTargets,
                    stringExcludedTargets: stringExcludedTargets,
                    expectedVectorTargets: expectedVectorTargets,
                    expectedScalarTargets: expectedScalarTargets,
                    expectedStringTargets: expectedStringTargets,
                    expectedCursorLayerIDs: projectedCursorLayerIDs,
                    admittedVectorPassTargets: admittedVectorPassTargets,
                    generation: generation,
                    budget: budget,
                    failure: .invalidArgument(
                        "SceneScript scalar candidate deferred without failure"
                    )
                )
            }
            let stringConstruction = SceneScriptStringProgram.compileCandidate(
                domain: domain,
                descriptor: runtimeDescriptor,
                scriptBindings: scriptBindings,
                timelineTargets: timelineTargets,
                excludedTargets: stringExcludedTargets,
                rejectedTargets: rejectedStringTargets,
                generation: generation,
                budget: budget
            )
            try control.checkBoundary()
            if let failure = domainFatalFailure(stringConstruction.failures) {
                return makeUnavailable(failure)
            }
            guard valid(
                stringConstruction.requestedTargets,
                stringConstruction.instantiatedTargets,
                stringConstruction.failures,
                stringConstruction.deferredTargets
            ) else {
                return unavailable(
                    authoredDescriptor: authoredDescriptor,
                    runtimeDescriptor: runtimeDescriptor,
                    scriptBindings: scriptBindings,
                    vectorProjection: vectorProjection,
                    userPropertyDefinitions: userPropertyDefinitions,
                    timelineTargets: timelineTargets,
                    stringExcludedTargets: stringExcludedTargets,
                    expectedVectorTargets: expectedVectorTargets,
                    expectedScalarTargets: expectedScalarTargets,
                    expectedStringTargets: expectedStringTargets,
                    expectedCursorLayerIDs: projectedCursorLayerIDs,
                    admittedVectorPassTargets: admittedVectorPassTargets,
                    generation: generation,
                    budget: budget,
                    failure: .invalidArgument(
                        "SceneScript string candidate ownership mismatch"
                    )
                )
            }
            if !stringConstruction.failures.isEmpty {
                record(
                    stringConstruction.failures,
                    family: "string",
                    failures: &stringFailures,
                    rejected: &rejectedStringTargets
                )
                continue
            }
            guard stringConstruction.deferredTargets.isEmpty else {
                return unavailable(
                    authoredDescriptor: authoredDescriptor,
                    runtimeDescriptor: runtimeDescriptor,
                    scriptBindings: scriptBindings,
                    vectorProjection: vectorProjection,
                    userPropertyDefinitions: userPropertyDefinitions,
                    timelineTargets: timelineTargets,
                    stringExcludedTargets: stringExcludedTargets,
                    expectedVectorTargets: expectedVectorTargets,
                    expectedScalarTargets: expectedScalarTargets,
                    expectedStringTargets: expectedStringTargets,
                    expectedCursorLayerIDs: projectedCursorLayerIDs,
                    admittedVectorPassTargets: admittedVectorPassTargets,
                    generation: generation,
                    budget: budget,
                    failure: .invalidArgument(
                        "SceneScript string candidate deferred without failure"
                    )
                )
            }
            let requestedPassTargets = admittedVectorPassTargets.subtracting(
                rejectedVectorTargets
            )
            let passConstruction = vectorConstruction.program
                .instantiatePassOwners(
                    projection: vectorProjection,
                    admittedTargets: requestedPassTargets,
                    budget: budget
                )
            try control.checkBoundary()
            if let failure = domainFatalFailure(passConstruction.failures) {
                return makeUnavailable(failure)
            }
            guard valid(
                passConstruction.requestedTargets,
                passConstruction.instantiatedTargets,
                passConstruction.failures,
                passConstruction.deferredTargets
            ) else {
                return unavailable(
                    authoredDescriptor: authoredDescriptor,
                    runtimeDescriptor: runtimeDescriptor,
                    scriptBindings: scriptBindings,
                    vectorProjection: vectorProjection,
                    userPropertyDefinitions: userPropertyDefinitions,
                    timelineTargets: timelineTargets,
                    stringExcludedTargets: stringExcludedTargets,
                    expectedVectorTargets: expectedVectorTargets,
                    expectedScalarTargets: expectedScalarTargets,
                    expectedStringTargets: expectedStringTargets,
                    expectedCursorLayerIDs: projectedCursorLayerIDs,
                    admittedVectorPassTargets: admittedVectorPassTargets,
                    generation: generation,
                    budget: budget,
                    failure: .invalidArgument(
                        "SceneScript vector pass ownership mismatch"
                    )
                )
            }
            if !passConstruction.failures.isEmpty {
                vectorPassFailures.merge(
                    passConstruction.failures,
                    uniquingKeysWith: { first, _ in first }
                )
                record(
                    passConstruction.failures,
                    family: "vector-pass",
                    failures: &vectorFailures,
                    rejected: &rejectedVectorTargets
                )
                continue
            }
            guard passConstruction.deferredTargets.isEmpty else {
                return unavailable(
                    authoredDescriptor: authoredDescriptor,
                    runtimeDescriptor: runtimeDescriptor,
                    scriptBindings: scriptBindings,
                    vectorProjection: vectorProjection,
                    userPropertyDefinitions: userPropertyDefinitions,
                    timelineTargets: timelineTargets,
                    stringExcludedTargets: stringExcludedTargets,
                    expectedVectorTargets: expectedVectorTargets,
                    expectedScalarTargets: expectedScalarTargets,
                    expectedStringTargets: expectedStringTargets,
                    expectedCursorLayerIDs: projectedCursorLayerIDs,
                    admittedVectorPassTargets: admittedVectorPassTargets,
                    generation: generation,
                    budget: budget,
                    failure: .invalidArgument(
                        "SceneScript vector pass deferred without failure"
                    )
                )
            }
            let report = SceneScriptQuickJSProgramConstructionReport(
                expectedVectorTargets: expectedVectorTargets,
                instantiatedVectorTargets:
                    Set(vectorConstruction.program.definitions.map(\.target)),
                vectorFailures: vectorFailures,
                expectedScalarTargets: expectedScalarTargets,
                instantiatedScalarTargets: scalarConstruction.instantiatedTargets,
                scalarFailures: scalarFailures,
                expectedStringTargets: expectedStringTargets,
                instantiatedStringTargets: stringConstruction.instantiatedTargets,
                stringFailures: stringFailures,
                expectedCursorLayerIDs: expectedCursorLayerIDs,
                instantiatedCursorLayerIDs: cursorConstruction.instantiatedLayerIDs,
                cursorFailures: cursorFailures
            )
            guard report.isComplete else {
                return unavailable(
                    authoredDescriptor: authoredDescriptor,
                    runtimeDescriptor: runtimeDescriptor,
                    scriptBindings: scriptBindings,
                    vectorProjection: vectorProjection,
                    userPropertyDefinitions: userPropertyDefinitions,
                    timelineTargets: timelineTargets,
                    stringExcludedTargets: stringExcludedTargets,
                    expectedVectorTargets: expectedVectorTargets,
                    expectedScalarTargets: expectedScalarTargets,
                    expectedStringTargets: expectedStringTargets,
                    expectedCursorLayerIDs: projectedCursorLayerIDs,
                    admittedVectorPassTargets: admittedVectorPassTargets,
                    generation: generation,
                    budget: budget,
                    failure: .invalidArgument(
                        "SceneScript candidate publication mismatch"
                    )
                )
            }
            domain.clearConstructionBoundaryCheck()
            if let storageSession {
                do {
                    try domain.configureStorage(storageSession)
                } catch {
                    NSLog(
                        "MWX SceneScript VM: localStorage provider unavailable failure=%@ fallback=owner-local",
                        String(describing: error)
                    )
                }
            }
            return .init(
                domain: domain,
                vectorProgram: vectorConstruction.program,
                cursorProgram: cursorConstruction.program,
                scalarProgram: scalarConstruction.program,
                stringProgram: stringConstruction.program,
                vectorPassCompilation: .init(
                    requestedTargets: admittedVectorPassTargets,
                    instantiatedTargets: passConstruction.instantiatedTargets,
                    failures: vectorPassFailures
                ),
                constructionReport: report
            )
        }
        return unavailable(
            authoredDescriptor: authoredDescriptor,
            runtimeDescriptor: runtimeDescriptor,
            scriptBindings: scriptBindings,
            vectorProjection: vectorProjection,
            userPropertyDefinitions: userPropertyDefinitions,
            timelineTargets: timelineTargets,
            stringExcludedTargets: stringExcludedTargets,
            expectedVectorTargets: expectedVectorTargets,
            expectedScalarTargets: expectedScalarTargets,
            expectedStringTargets: expectedStringTargets,
            expectedCursorLayerIDs: projectedCursorLayerIDs,
            admittedVectorPassTargets: admittedVectorPassTargets,
            generation: generation,
            budget: budget,
            failure: .invalidArgument("SceneScript candidate retry exhausted")
        )
    }

    private static func unavailable(
        authoredDescriptor: SceneRenderDescriptor,
        runtimeDescriptor: SceneRenderDescriptor,
        scriptBindings: [SceneScriptBindingIR],
        vectorProjection: SceneScriptVectorCandidateCatalog,
        userPropertyDefinitions: [SceneUserPropertyDefinition],
        timelineTargets: Set<SceneDynamicTarget>,
        stringExcludedTargets: Set<SceneDynamicTarget>,
        expectedVectorTargets: Set<SceneDynamicTarget>,
        expectedScalarTargets: Set<SceneDynamicTarget>,
        expectedStringTargets: Set<SceneDynamicTarget>,
        expectedCursorLayerIDs: Set<Int>,
        admittedVectorPassTargets: Set<SceneDynamicTarget>,
        generation: UInt64,
        budget: SceneScriptScalarBudget,
        failure: SceneScriptScalarRuntimeFailure
    ) -> Self {
        NSLog(
            "MWX SceneScript VM: ownerDomain=failed failure=%@ code=%@ fallback=current-frame-lower-priority",
            String(describing: failure), failure.code
        )
        let vectorProgram = SceneScriptVectorProgram.compileNonPass(
            domain: nil,
            descriptor: authoredDescriptor,
            projection: vectorProjection,
            userPropertyDefinitions: userPropertyDefinitions,
            generation: generation,
            budget: budget
        )
        let vectorFailures = Dictionary(uniqueKeysWithValues:
            expectedVectorTargets.map { ($0, failure) }
        )
        let scalarFailures = Dictionary(uniqueKeysWithValues:
            expectedScalarTargets.map { ($0, failure) }
        )
        let stringFailures = Dictionary(uniqueKeysWithValues:
            expectedStringTargets.map { ($0, failure) }
        )
        let cursorFailures = Dictionary(uniqueKeysWithValues:
            expectedCursorLayerIDs.map { ($0, failure) }
        )
        let report = SceneScriptQuickJSProgramConstructionReport(
            expectedVectorTargets: expectedVectorTargets,
            instantiatedVectorTargets: [],
            vectorFailures: vectorFailures,
            expectedScalarTargets: expectedScalarTargets,
            instantiatedScalarTargets: [],
            scalarFailures: scalarFailures,
            expectedStringTargets: expectedStringTargets,
            instantiatedStringTargets: [],
            stringFailures: stringFailures,
            expectedCursorLayerIDs: expectedCursorLayerIDs,
            instantiatedCursorLayerIDs: [],
            cursorFailures: cursorFailures
        )
        return .init(
            domain: nil,
            vectorProgram: vectorProgram,
            cursorProgram: SceneScriptCursorProgram.compile(
                domain: nil,
                descriptor: authoredDescriptor,
                scriptBindings: scriptBindings,
                generation: generation,
                budget: budget
            ),
            scalarProgram: .unavailable(generation: generation),
            stringProgram: SceneScriptStringProgram.compile(
                domain: nil,
                descriptor: runtimeDescriptor,
                scriptBindings: scriptBindings,
                timelineTargets: timelineTargets,
                excludedTargets: stringExcludedTargets,
                generation: generation,
                budget: budget
            ),
            vectorPassCompilation: .init(
                requestedTargets: admittedVectorPassTargets,
                instantiatedTargets: [],
                failures: Dictionary(uniqueKeysWithValues:
                    admittedVectorPassTargets.map { ($0, failure) }
                )
            ),
            constructionReport: report
        )
    }

    private static func valid<Identity: Hashable>(
        _ requested: Set<Identity>,
        _ instantiated: Set<Identity>,
        _ failures: [Identity: SceneScriptScalarRuntimeFailure],
        _ deferred: Set<Identity>
    ) -> Bool {
        let failed = Set(failures.keys)
        return instantiated.isDisjoint(with: failed)
            && instantiated.isDisjoint(with: deferred)
            && failed.isDisjoint(with: deferred)
            && instantiated.union(failed).union(deferred) == requested
    }

    private static func typedFailure(_ error: Error) ->
        SceneScriptScalarRuntimeFailure {
        (error as? SceneScriptScalarRuntimeFailure)
            ?? .invalidArgument(String(describing: error))
    }

    private static func domainFatalFailure<Identity: Hashable>(
        _ failures: [Identity: SceneScriptScalarRuntimeFailure]
    ) -> SceneScriptScalarRuntimeFailure? {
        failures.values.first {
            if case .memoryExceeded = $0 { return true }
            return false
        }
    }

    private static func record<Identity: Hashable>(
        _ additions: [Identity: SceneScriptScalarRuntimeFailure],
        family: String,
        failures: inout [Identity: SceneScriptScalarRuntimeFailure],
        rejected: inout Set<Identity>
    ) {
        for (identity, failure) in additions {
            NSLog(
                "MWX SceneScript VM: family=%@ ownerConstruction=failed identity=%@ failure=%@ code=%@ fallback=current-frame-lower-priority",
                family,
                String(describing: identity),
                String(describing: failure),
                failure.code
            )
        }
        failures.merge(additions, uniquingKeysWith: { first, _ in first })
        rejected.formUnion(additions.keys)
    }
}
