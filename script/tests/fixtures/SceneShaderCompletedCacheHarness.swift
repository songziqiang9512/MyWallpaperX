import Foundation

private func cacheRetentionInput(fragmentSource: String) ->
    SceneResolvedMaterialGenericShaderResolutionCache.Input
{
    .init(
        vertexSource: "vertex",
        fragmentSource: fragmentSource,
        alphaAttenuationSourceSlot: nil,
        colorBlendSourceSlot: nil,
        previousBlurredCompositeBlurredSlot: nil,
        previousBlurredCompositePreviousSlot: nil,
        previousBlurredCompositeMaskSlot: nil,
        hasExternalProviderTexture: false,
        producesScalarRedOutput: false,
        producesRedGreenUnormOutput: false,
        hasOnlyScalarDataInputs: false,
        isSourceIndependentPremultipliedOutput: false,
        graphTextureSlots: [],
        graphInputTextureSlots: [],
        graphDataTextureSlots: [],
        activeTextureSlots: [],
        activeOpacityMaskSlots: [],
        typedStaticDataAuxiliarySlots: [],
        preservedChannelsExternalProviderTextureSlots: [],
        premultipliedColorAuxiliarySlots: [],
        sceneBackgroundColorSlots: [],
        spatialWeightedColorBlendSourceSlot: nil,
        spatialWeightedColorBlendActiveSlots: [],
        spatialWeightedColorBlendTypedAuxiliarySlots: [],
        spatialWeightedColorBlendExternalColorSlot: nil,
        r8TextureSlots: [],
        hasDefaultedOpacityMaskSampler: false,
        hasOnlyTypedOpacityMaskAuxiliary: false,
        hasOnlyGraphInputSampler: false,
        outputIsRGBA8Unorm: false,
        sourceColorTransfer: nil,
        outputSemantics: .color,
        runtimeLoopBounds: .none
    )
}

private func retainedResolution(_ marker: String, payloadBytes: Int = 0)
    -> SceneResolvedMaterialGenericShaderArtifactCache.Resolution {
    let program = SceneAuthoredShaderProgram(
        metalSource: marker + String(repeating: "m", count: payloadBytes),
        vertexFunctionName: "vertex", fragmentFunctionName: "fragment",
        uniformLayout: .init(fields: [], byteSize: 0), textureBindings: [],
        staticLoopWork: 0, colorTransfer: .opaque)
    return .accepted(program: program, premultipliedColorInputSlots: [],
        requestKey: marker, routeDecision: .init(profile: "fixture",
            state: "generic-only", fallbackOwner: "none"))
}

private func isAcceptedResolution(
    _ value: SceneResolvedMaterialGenericShaderArtifactCache.Resolution
) -> Bool {
    if case .accepted = value { return true }
    return false
}

#if !CACHE_RETENTION_BASELINE
private final class RetentionCallCounts: @unchecked Sendable {
    private let lock = NSLock()
    private var calls = 0
    private var accepted = 0
    func nextOperation() -> Int {
        lock.lock(); defer { lock.unlock() }
        calls += 1
        return calls
    }
    func record(accepted value: Bool) {
        lock.lock(); defer { lock.unlock() }
        if value { accepted += 1 }
    }
    var snapshot: (operations: Int, accepted: Int) {
        lock.lock(); defer { lock.unlock() }
        return (calls, accepted)
    }
}

/// Owns no compiler or scheduler: calls the real two cache owners with a
/// replaceable compiler operation, isolating completed-result retention.
private func completedCacheRetentionChecks() -> [String: Any] {
    let outer = SceneResolvedMaterialGenericShaderResolutionCache()
    let inner = SceneResolvedMaterialGenericShaderCompilationCoordinator()
    let key = cacheRetentionInput(fragmentSource: "repairable-compiler-input")
    var outerCalls = 0
    var compilerCalls = 0
    var compilerRepaired = false
    func composedAttempt() -> SceneResolvedMaterialGenericShaderResolutionCache.Outcome {
        outer.perform(key: key) {
            outerCalls += 1
            let result = inner.perform(key: "repairable-compiler-key") {
                compilerCalls += 1
                return compilerRepaired
                    ? .success(URL(fileURLWithPath: "/tmp/repaired-fixture-artifact"))
                    : .failure(.workspace)
            }
            switch result.result {
            case .success: return retainedResolution("repaired")
            case .failure:
                return .unavailable(code: "compiler-workspace", requestKey: "repairable",
                    permitsBoundedFrontend: false, routeDecision: .init(profile: "fixture",
                        state: "generic-only", fallbackOwner: "none"))
            }
        }
    }
    let first = composedAttempt()
    compilerRepaired = true
    let repaired = composedAttempt()

    // Same count, very different payload sizes: entry count is not a byte bound.
    func distinctPayloads(payloadBytes: Int) -> [String: Int] {
        let cache = SceneResolvedMaterialGenericShaderResolutionCache()
        let count = 96
        var operations = 0
        var hits = 0
        for index in 0..<count {
            _ = cache.perform(key: cacheRetentionInput(fragmentSource: "distinct-\(index)")) {
                operations += 1
                return retainedResolution("distinct-\(index)", payloadBytes: payloadBytes)
            }
        }
        for index in 0..<count {
            let outcome = cache.perform(key: cacheRetentionInput(fragmentSource: "distinct-\(index)")) {
                operations += 1
                return retainedResolution("distinct-\(index)", payloadBytes: payloadBytes)
            }
            if outcome.cacheHit { hits += 1 }
        }
        return ["distinctInputs": count, "payloadBytesPerInput": payloadBytes,
            "operations": operations, "revisitHits": hits,
            "requestedMSLPayloadBytes": count * payloadBytes]
    }

    // The first operation stays open while all callers enter the call boundary.
    // This is a storage-free scheduling oracle, not a CPU timing benchmark.
    func concurrentResult(retainAccepted: Bool) -> [String: Any] {
        let cache = SceneResolvedMaterialGenericShaderResolutionCache(maximumBytes: 1)
        let counts = RetentionCallCounts()
        let group = DispatchGroup()
        let started = DispatchSemaphore(value: 0)
        let ownerStarted = DispatchSemaphore(value: 0)
        let releaseOwner = DispatchSemaphore(value: 0)
        let callers = 8
        let input = cacheRetentionInput(fragmentSource: "concurrent-identical-input")
        func work() {
            let result = cache.perform(key: input) {
                let ordinal = counts.nextOperation()
                if ordinal == 1 {
                    ownerStarted.signal()
                    _ = releaseOwner.wait(timeout: .now() + 10)
                }
                if retainAccepted {
                    // A future low-budget test uses this result above its cap.
                    return retainedResolution("large-result", payloadBytes: 512 * 1024)
                }
                return .ownerDeferred(code: "not-retained", requestKey: "identical",
                    routeDecision: .init(profile: "fixture", state: "generic-only",
                        fallbackOwner: "none"))
            }
            counts.record(accepted: isAcceptedResolution(result.resolution))
        }
        group.enter()
        DispatchQueue.global().async { work(); group.leave() }
        let ownerReady = ownerStarted.wait(timeout: .now() + 10) == .success
        for _ in 1..<callers {
            group.enter()
            DispatchQueue.global().async {
                started.signal()
                work()
                group.leave()
            }
        }
        var allStarted = true
        for _ in 1..<callers {
            if started.wait(timeout: .now() + 10) != .success { allStarted = false }
        }
        let deadline = Date().addingTimeInterval(10)
        while cache.snapshot.waitingCallers != callers - 1, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.001)
        }
        let allJoined = cache.snapshot.waitingCallers == callers - 1
        releaseOwner.signal()
        let completed = group.wait(timeout: .now() + 10) == .success
        let snapshot = counts.snapshot
        return ["callers": callers, "ownerReady": ownerReady, "allStarted": allStarted,
            "allJoined": allJoined, "completed": completed, "operations": snapshot.operations,
            "acceptedResults": snapshot.accepted, "retainedBytes": cache.snapshot.retainedBytes,
            "retainedEntries": cache.snapshot.completedEntries]
    }
    return [
        "composedRepair": ["outerOperations": outerCalls, "compilerOperations": compilerCalls,
            "firstAccepted": isAcceptedResolution(first.resolution),
            "repairedAccepted": isAcceptedResolution(repaired.resolution),
            "firstOuterCacheHit": first.cacheHit, "repairedOuterCacheHit": repaired.cacheHit],
        "smallDistinct": distinctPayloads(payloadBytes: 1024),
        "largeDistinct": distinctPayloads(payloadBytes: 128 * 1024),
        "largeAcceptedConcurrent": concurrentResult(retainAccepted: true),
        "uncachedConcurrent": concurrentResult(retainAccepted: false),
        "compilerFailedConcurrent": compilerFailureFlight(),
    ]
}

private func compilerFailureFlight() -> [String: Any] {
    let compiler = SceneResolvedMaterialGenericShaderCompilationCoordinator()
    let counts = RetentionCallCounts()
    let group = DispatchGroup()
    let ownerStarted = DispatchSemaphore(value: 0)
    let releaseOwner = DispatchSemaphore(value: 0)
    let callers = 8
    func work() {
        let result = compiler.perform(key: "shared-failure") {
            let ordinal = counts.nextOperation()
            if ordinal == 1 {
                ownerStarted.signal()
                _ = releaseOwner.wait(timeout: .now() + 10)
            }
            return .failure(.workspace)
        }
        if case .failure = result.result { counts.record(accepted: true) }
    }
    group.enter()
    DispatchQueue.global().async { work(); group.leave() }
    let ownerReady = ownerStarted.wait(timeout: .now() + 10) == .success
    for _ in 1..<callers {
        group.enter()
        DispatchQueue.global().async { work(); group.leave() }
    }
    let deadline = Date().addingTimeInterval(10)
    while compiler.snapshot.waitingCallers != callers - 1, Date() < deadline {
        Thread.sleep(forTimeInterval: 0.001)
    }
    let allJoined = compiler.snapshot.waitingCallers == callers - 1
    releaseOwner.signal()
    let completed = group.wait(timeout: .now() + 10) == .success
    let shared = counts.snapshot
    let emptyAfterFailure = compiler.snapshot.completedEntries == 0
    let repaired = compiler.perform(key: "shared-failure") {
        _ = counts.nextOperation()
        return .success(URL(fileURLWithPath: "/tmp/repaired-flight-artifact"))
    }
    let repairedSucceeded: Bool
    if case .success = repaired.result { repairedSucceeded = true }
    else { repairedSucceeded = false }
    return ["ownerReady": ownerReady, "allJoined": allJoined, "completed": completed,
        "callers": callers, "failureResults": shared.accepted,
        "sharedOperations": shared.operations, "failureNotRetained": emptyAfterFailure,
        "operationsAfterRepair": counts.snapshot.operations,
        "repairSource": repaired.source.rawValue, "repairSucceeded": repairedSucceeded]
}


private final class CacheKeyHashCalls {
    var count = 0
}

private struct CountingCacheKey: Hashable {
    let id: Int
    let calls: CacheKeyHashCalls
    static func == (left: Self, right: Self) -> Bool { left.id == right.id }
    func hash(into hasher: inout Hasher) {
        calls.count += 1
        hasher.combine(id)
    }
}

private func completedCacheTrimHashChecks() -> [String: Any] {
    let calls = CacheKeyHashCalls()
    func key(_ id: Int) -> CountingCacheKey { .init(id: id, calls: calls) }
    var cache = SceneShaderCompletedCacheStorage<CountingCacheKey, Int>(
        maximumBytes: 4, maximumEntries: 4)
    for id in 0..<4 { cache.insert(id, for: key(id), cost: 1) }
    _ = cache.value(for: key(0)) // 1 is now the least recently used entry.
    calls.count = 0
    cache.insert(4, for: key(4), cost: 1)
    let trimHashCalls = calls.count
    let correctLRU = cache.value(for: key(1)) == nil
        && [0, 2, 3, 4].allSatisfy { cache.value(for: key($0)) == $0 }
    // Four-item comparison sorting requires at least three comparisons. A
    // key-lookup comparator adds at least six hashes to insertion/removal.
    // Leave room for Dictionary collision repair; do not prescribe its exact
    // hash count or inspect the storage implementation's source text.
    return ["trimHashCalls": trimHashCalls, "hashCallLimit": 8,
        "correctLRU": correctLRU, "completedEntries": cache.count,
        "retainedBytes": cache.retainedBytes]
}

private func completedCacheBoundedChecks() -> [String: Bool] {
    let tiny = SceneResolvedMaterialGenericShaderResolutionCache(maximumBytes: 12 * 1024, maximumEntries: 2)
    var calls = 0
    func lookup(_ key: String) -> SceneResolvedMaterialGenericShaderResolutionCache.Outcome {
        tiny.perform(key: cacheRetentionInput(fragmentSource: key)) {
            calls += 1
            return retainedResolution(key, payloadBytes: 1024)
        }
    }
    let active = lookup("aaaa")
    _ = lookup("bbbb")
    let touch = lookup("aaaa")
    _ = lookup("cccc")
    let hit = lookup("aaaa")
    let evicted = lookup("bbbb")
    let snapshot = tiny.snapshot
    let activeStillUsable: Bool
    if case let .accepted(program, _, _, _) = active.resolution {
        activeStillUsable = program.metalSource == "aaaa" + String(repeating: "m", count: 1024)
    } else { activeStillUsable = false }

    var raw = SceneShaderCompletedCacheStorage<String, String>(maximumBytes: 10, maximumEntries: 10)
    raw.insert("a", for: "a", cost: 4)
    raw.insert("b", for: "b", cost: 4)
    _ = raw.value(for: "a")
    raw.insert("c", for: "c", cost: 4)
    let weightedVictim = raw.value(for: "b") == nil && raw.value(for: "a") == "a"
    let weightBound = raw.count == 2 && raw.retainedBytes == 8
    let oversizedRejected = !raw.insert("large", for: "large", cost: 11)
        && raw.count == 2 && raw.retainedBytes == 8
    var overflow = SceneShaderCacheCost()
    overflow.add(Int.max)
    overflow.add(1)
    let overflowRejected = !raw.insert("overflow", for: "overflow", cost: overflow.bytes)
        && raw.retainedBytes == 8

    let long = String(repeating: "x", count: 16 * 1024)
    func program(metal: String = "m", function: String = "v", field: String = "u", binding: String = "t") -> SceneAuthoredShaderProgram {
        .init(metalSource: metal, vertexFunctionName: function, fragmentFunctionName: function,
            uniformLayout: .init(fields: [.init(name: field, type: .float, offset: 0)], byteSize: 16),
            textureBindings: [.init(name: binding, slot: 0, channelUse: .wholeVector)],
            staticLoopWork: 0, colorTransfer: .opaque)
    }
    func programCost(_ program: SceneAuthoredShaderProgram) -> Int {
        var cost = SceneShaderCacheCost(); cost.program(program); return cost.bytes
    }
    let smallProgramCost = programCost(program())
    let decision = SceneGenericShaderRouteDecision(profile: "fixture", state: "generic-only", fallbackOwner: "none")
    func inputCost(_ source: String) -> Int {
        cacheRetentionInput(fragmentSource: source).retainedCost(program: program(),
            premultipliedColorInputSlots: [], requestKey: "key", decision: decision)
    }

    func source(_ stage: SceneShaderContract.StageKind,
        map: [SceneShaderSourceMapEntry] = [], annotations: [SceneShaderActiveAnnotation] = [],
        declarations: [SceneShaderActiveDeclaration] = []) -> SceneShaderPreparedSource {
        .init(frontendSchemaVersion: 1, sourceDialect: .wallpaperEngineGLSLLike, backend: .mwxMetal,
            stage: stage, rootRelativePath: "root", source: "source", sourceMap: map,
            activeAnnotations: annotations, activeDeclarations: declarations,
            dependencies: [], dependencySHA256: "dependency", variantSHA256: "variant", preparedSHA256: "prepared")
    }
    func preparationCost(_ vertex: SceneShaderPreparedSource) -> Int {
        var cost = SceneShaderCacheCost()
        cost.preparedProgram(.init(vertex: vertex, fragment: source(.fragment),
            colorContract: .unresolvedAuthoredPass, cacheKey: "prepared"))
        return cost.bytes
    }
    let smallPreparationCost = preparationCost(source(.vertex))
    let annotation = SceneShaderContract.Annotation(marker: long, value: .string(long),
        variantValue: .object([long: .string(long)]), raw: long, line: 1)
    let annotationCost = preparationCost(source(.vertex,
        annotations: [.init(sourcePath: long, annotation: annotation)]))
    let declaration = SceneShaderContract.Declaration(kind: .uniform, type: long,
        name: long, arraySuffix: long, arraySize: 1, raw: long, line: 1)
    let declarationCost = preparationCost(source(.vertex,
        declarations: [.init(sourcePath: long, declaration: declaration)]))
    return [
        "resolutionReusesAndEvictsLRU": touch.cacheHit && hit.cacheHit && !evicted.cacheHit && calls == 4,
        "resolutionCountAndByteBound": snapshot.completedEntries == 2 && snapshot.retainedBytes <= 12 * 1024,
        "evictedActiveProgramRemainsUsable": activeStillUsable,
        "payloadWeightedEviction": weightedVictim && weightBound,
        "oversizedInsertKeepsExistingEntries": oversizedRejected,
        "overflowWeightDeclinesRetention": overflow.bytes == Int.max && overflowRejected,
        "longGLSLKeyCharged": inputCost(long) - inputCost("x") >= long.utf8.count - 1,
        "longMSLCharged": programCost(program(metal: long)) - smallProgramCost >= long.utf8.count - 1,
        "longFunctionNamesCharged": programCost(program(function: long)) - smallProgramCost >= 2 * (long.utf8.count - 1),
        "longUniformNamesCharged": programCost(program(field: long)) - smallProgramCost >= 2 * (long.utf8.count - 1),
        "longBindingNameCharged": programCost(program(binding: long)) - smallProgramCost >= long.utf8.count - 1,
        "longSourceMapPathCharged": preparationCost(source(.vertex,
            map: [.init(outputLine: 1, sourcePath: long, sourceLine: 1)])) - smallPreparationCost >= long.utf8.count,
        "annotationBothTypedValuesCharged": annotationCost - smallPreparationCost >= 6 * long.utf8.count,
        "declarationVariableFieldsCharged": declarationCost - smallPreparationCost >= 5 * long.utf8.count,
    ]
}
#endif

/// Uses the original resolution owner and discards every external result before
/// the loaded/revisited holds. No input, closure, or Program array survives a call.
/// These synthetic MSL bytes are an ownership probe, not shader/GPU compilation.
private func completedCacheFootprint(count: Int, payloadBytes: Int, revisit: Int) throws {
    let cache = SceneResolvedMaterialGenericShaderResolutionCache()
    var operations = 0
    var hits = 0
    let started = ProcessInfo.processInfo.systemUptime
    func stage(_ phase: String) throws -> Bool {
        var output: [String: Any] = ["phase": phase, "pid": ProcessInfo.processInfo.processIdentifier,
            "distinctInputs": count, "payloadBytesPerInput": payloadBytes,
            "requestedMSLPayloadBytes": count * payloadBytes, "revisitInputs": revisit,
            "operations": operations, "revisitHits": hits,
            "elapsedSeconds": ProcessInfo.processInfo.systemUptime - started,
            "sampleScope": "synthetic-program-real-resolution-owner"]
#if CACHE_RETENTION_BASELINE
        output["implementation"] = "frozen-baseline"
#else
        output["implementation"] = "candidate"
        output["retainedEntries"] = cache.snapshot.completedEntries
        output["retainedWeightBytes"] = cache.snapshot.retainedBytes
#endif
        let data = try JSONSerialization.data(withJSONObject: output, options: [.sortedKeys])
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data([10]))
        return readLine() != nil
    }
    func visit(_ index: Int, revisiting: Bool) {
        let result = cache.perform(key: cacheRetentionInput(fragmentSource: "footprint-\(index)")) {
            operations += 1
            return retainedResolution("footprint-\(index)", payloadBytes: payloadBytes)
        }
        if revisiting && result.cacheHit { hits += 1 }
    }
    guard try stage("ready") else { return }
    for index in 0..<count { visit(index, revisiting: false) }
    guard try stage("loaded") else { return }
    for index in 0..<revisit { visit(index, revisiting: true) }
    _ = try stage("revisited")
    withExtendedLifetime(cache) {}
}

@main
struct SceneShaderCompletedCacheHarness {
    static func main() throws {
        let arguments = CommandLine.arguments
        if arguments.count == 5, arguments[1] == "--footprint",
            let count = Int(arguments[2]), let payload = Int(arguments[3]),
            let revisit = Int(arguments[4]), count > 0, payload >= 0,
            revisit >= 0, revisit <= count, count <= Int.max / max(1, payload) {
            try completedCacheFootprint(count: count, payloadBytes: payload, revisit: revisit)
            return
        }
#if !CACHE_RETENTION_BASELINE
        let output: [String: Any]
        switch arguments.dropFirst().first {
        case "--retention": output = completedCacheRetentionChecks()
        case "--bounds": output = completedCacheBoundedChecks()
        case "--trim-hash": output = completedCacheTrimHashChecks()
        default: fatalError("expected --retention, --bounds, or --footprint COUNT BYTES REVISIT")
        }
        FileHandle.standardOutput.write(try JSONSerialization.data(
            withJSONObject: output, options: [.sortedKeys]))
#else
        fatalError("baseline probe supports --footprint COUNT BYTES REVISIT")
#endif
    }
}

