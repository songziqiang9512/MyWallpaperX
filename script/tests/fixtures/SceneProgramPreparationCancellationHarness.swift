// Appended to the graph executor's existing declarations. Capability, stage,
// material and variant preparation are production code; only catalog lookup
// is a controlled leaf. This executable creates no Metal device or commands.
private final class CancellationEntryProbe {
    private let lock = NSLock()
    private var entries: [String] = []
    let onRead: ((Graph.Node) -> Void)?

    init(onRead: ((Graph.Node) -> Void)? = nil) { self.onRead = onRead }

    func read(_ node: Graph.Node) {
        lock.withLock { entries.append("\(node.effect.layerID):\(node.nodeIndex)") }
        onRead?(node)
    }

    var reads: [String] { lock.withLock { entries.sorted() } }
}

private final class CancellationCompletion {
    private let lock = NSLock()
    private var value = "not-returned"
    func finish(_ result: String) { lock.withLock { value = result } }
    var result: String { lock.withLock { value } }
}

@main private enum ProgramPreparationCancellationHarness {
    typealias Admission = SceneResolvedMaterialExecutionCapabilityAdmission

    static func materialGraph(layer: Int, count: Int) -> Graph {
        let key = Graph.EffectKey(layerID: layer, effectIndex: 0,
            descriptorID: "cancel-\(layer)")
        let source = Graph.TextureIdentity(kind: .layerSource,
            layerID: layer, effect: nil, name: nil)
        let output = Graph.TextureIdentity(kind: .effectOutput,
            layerID: layer, effect: key, name: nil)
        var nodes: [Graph.Node] = [], targets: [Graph.RenderTarget] = []
        var previous = source
        for index in 0..<count {
            let target = index == count - 1 ? output : Graph.TextureIdentity(
                kind: .framebuffer, layerID: layer, effect: key,
                name: "material-\(index)")
            if target != output { targets.append(rawTarget(target)) }
            nodes.append(material(index, ordinal: index, target: target,
                read: previous, owner: key))
            previous = target
        }
        return .init(layerID: layer, effects: [.init(key: key,
            definitionPath: "effects/cancel-\(layer)/effect.json",
            input: source, output: output, nodeIndices: nodes.map(\.nodeIndex))],
            renderTargets: targets, nodes: nodes, finalOutput: output, blockers: [])
    }

    static func candidates(_ graphs: [Graph]) -> [Admission.Candidate] {
        graphs.flatMap { graph in
            let descriptor = SceneRenderDescriptor(
                layers: [.init(id: graph.layerID, effects: graph.effects.map { effect in
                    .init(id: effect.key.descriptorID, file: effect.definitionPath,
                        visible: true, passes: graph.nodes.filter {
                            $0.effect == effect.key
                        }.map { .init(passIndex: $0.instancePassIndex!, combos: [:]) })
                })],
                materialPasses: graph.nodes.map { .init(id: $0.materialPassID!,
                    materialPath: $0.materialPath!, combos: [:]) },
                effectDefinitions: graph.effects.map {
                    .init(relativePath: $0.definitionPath, functions: nil)
                })
            return Admission.compile(descriptor: descriptor, authoredPlans: [graph])
        }
    }

    static func observedCatalog(_ graphs: [Graph], _ probe: CancellationEntryProbe)
        -> SceneResolvedMaterialRuntimeCatalog {
        var entries: [SceneResolvedMaterialRuntimeCatalog.Key:
            SceneResolvedMaterialRuntimeCatalog.Entry] = [:]
        for graph in graphs {
            entries.merge(catalog(for: graph).entries) { _, _ in
                fatalError("fixture material identities must be unique")
            }
        }
        return .init(entries: entries, entryObserver: probe.read)
    }

    static func projection(_ value: Capabilities, layers: [Int]) throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        var projected: [[String: Any]] = []
        for layer in layers {
            guard let claim = value.claim(layerID: layer),
                  let capability = value.resolve(claim.token) else {
                fatalError("fixture capability did not survive preparation: \(value.reportLines)")
            }
            let materials = try capability.materials.values.map { material -> String in
                let snapshot = material.variants.launchEnvelopeCapabilitySnapshot()
                let variants = try snapshot.variants.map { variant -> String in
                    let frontend = try encoder.encode(variant.frontendProgram).base64EncodedString()
                    let prepared = try encoder.encode(variant.preparedShader).base64EncodedString()
                    return "\(variant.readinessMask):\(frontend):\(prepared):\(variant.resolvedIntegerCombos.sorted { $0.key < $1.key })"
                }.sorted()
                return "\(material.key.effect.effectIndex):\(material.key.nodeIndex):\(material.template.shaderContract.canonicalSHA256):\(material.attachmentStorage):\(material.targetFormat):\(snapshot.allEntriesReady):\(variants)"
            }.sorted()
            projected.append([
                "layer": layer,
                "graphs": try capability.stages.map {
                    try encoder.encode($0.product.graph).base64EncodedString()
                },
                "families": capability.stages.map { $0.subject?.family ?? "missing" },
                "visual": capability.stages.map { $0.visualFailureReasonCode ?? "none" },
                "inactive": capability.stages.map { $0.initiallyInactivePassthroughReasonCode ?? "none" },
                "materials": materials,
            ])
        }
        return try JSONSerialization.data(withJSONObject: [
            "report": value.reportLines, "layers": projected,
        ], options: [.sortedKeys])
    }

    static func stages(_ admitted: SceneResolvedMaterialAdmittedLayer,
        catalog: SceneResolvedMaterialRuntimeCatalog, workers: Int = 1,
        check: (() throws -> Void)? = nil
    ) throws -> Result<Capabilities.CompiledStages, Capabilities.Rejection> {
        try Capabilities.compileProgramFirstStages(admitted, materialCatalog: catalog,
            demandIssues: [], dynamicProducers: .empty, assetFormatFacts: [:],
            assetStates: [:], maximumVariantsPerMaterial: 16,
            maximumStageWorkers: workers, cancellationCheck: check)
    }

    static func main() throws {
        setenv("MWX_SCENE_GENERIC_SHADER_ROUTE", "disable-generic", 1)
        let cache = FileManager.default.temporaryDirectory.appendingPathComponent(
            "mwx-program-cancellation-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: cache) }
        setenv("MWX_SCENE_GENERIC_SHADER_CACHE", cache.path, 1)
        let graphs = [108, 102, 107, 101, 106, 103, 105, 104].map {
            materialGraph(layer: $0, count: 2)
        }
        let admitted = candidates(graphs)
        precondition(admitted.count == graphs.count && admitted.allSatisfy {
            if case .success = $0.result { return true }; return false
        }, "fixture must reach capability preparation")
        let ordinaryProbe = CancellationEntryProbe()
        let ordinary = try Capabilities(admissionCandidates: admitted,
            materialCatalog: observedCatalog(graphs, ordinaryProbe))
        precondition(ordinaryProbe.reads.count == graphs.count * 2,
            "ordinary fixture must prepare every material")
        let expected = try projection(ordinary, layers: graphs.map(\.layerID))
        let noopProbe = CancellationEntryProbe()
        let noop = try Capabilities(admissionCandidates: admitted,
            materialCatalog: observedCatalog(graphs, noopProbe), cancellationCheck: {})
        var checks = ["noopPreservesProgramsStagesMaterialsAndReports":
            try projection(noop, layers: graphs.map(\.layerID)) == expected
                && noopProbe.reads == ordinaryProbe.reads]

        // Hold every entered layer's first material at the lookup leaf.
        // Cancellation must neither return ahead of these workers nor admit
        // their second materials or any later layers after they are released.
        let workers = max(1, min(4, ProcessInfo.processInfo.activeProcessorCount))
        let entered = DispatchSemaphore(value: 0), release = DispatchSemaphore(value: 0)
        let done = DispatchSemaphore(value: 0), completion = CancellationCompletion()
        let token = SceneWallpaperLaunchCancellation()
        let heldProbe = CancellationEntryProbe { _ in
            entered.signal()
            precondition(release.wait(timeout: .now() + 30) == .success)
        }
        let heldCatalog = observedCatalog(graphs, heldProbe)
        DispatchQueue.global().async {
            do {
                _ = try Capabilities(admissionCandidates: admitted,
                    materialCatalog: heldCatalog, cancellationCheck: { try token.check() })
                completion.finish("unexpected-success")
            } catch SceneDesktopWallpaperHostLaunchError.cancelled {
                completion.finish("cancelled")
            } catch { completion.finish("wrong-error:\(error)") }
            done.signal()
        }
        for _ in 0..<workers {
            precondition(entered.wait(timeout: .now() + 30) == .success)
        }
        token.cancel()
        checks["cancellationWaitsForEnteredWorkers"] = done.wait(timeout: .now() + 0.05) == .timedOut
        for _ in 0..<workers { release.signal() }
        precondition(done.wait(timeout: .now() + 30) == .success)
        checks["layerAndMaterialBatchesStopWithoutPassthrough"] = completion.result == "cancelled"
            && heldProbe.reads.count == workers
            && heldProbe.reads.allSatisfy { $0.hasSuffix(":0") }

        let chain = chainedGraph()
        guard let chainCandidate = candidates([chain]).first,
              case let .success(chainAdmitted) = chainCandidate.result else {
            fatalError("stage fixture admission failed")
        }
        let chainCatalog = observedCatalog([chain], CancellationEntryProbe())
        guard case let .success(serialStages) = try stages(chainAdmitted, catalog: chainCatalog),
              case let .success(parallelStages) = try stages(chainAdmitted,
                catalog: chainCatalog, workers: 2) else {
            fatalError("uncancelled stage fixture did not compile")
        }
        checks["uncancelledParallelStagesKeepAuthoredOrder"] = serialStages.stages.count == 3
            && serialStages.materials.count == 3
            && serialStages.stages.map(\.product.graph) == parallelStages.stages.map(\.product.graph)
            && serialStages.stages.map(\.subject) == parallelStages.stages.map(\.subject)
            && Set(serialStages.materials.keys) == Set(parallelStages.materials.keys)
        let stageToken = SceneWallpaperLaunchCancellation()
        let stageProbe = CancellationEntryProbe { _ in stageToken.cancel() }
        do {
            _ = try stages(chainAdmitted, catalog: observedCatalog([chain], stageProbe),
                check: { try stageToken.check() })
            checks["nextStageIsNotEntered"] = false
        } catch SceneDesktopWallpaperHostLaunchError.cancelled {
            checks["nextStageIsNotEntered"] = stageProbe.reads == ["81:0"]
        }

        let stageEntered = DispatchSemaphore(value: 0), stageRelease = DispatchSemaphore(value: 0)
        let stageDone = DispatchSemaphore(value: 0), stageCompletion = CancellationCompletion()
        let parallelToken = SceneWallpaperLaunchCancellation()
        let parallelProbe = CancellationEntryProbe { _ in
            stageEntered.signal()
            precondition(stageRelease.wait(timeout: .now() + 30) == .success)
        }
        let parallelCatalog = observedCatalog([chain], parallelProbe)
        DispatchQueue.global().async {
            do {
                _ = try stages(chainAdmitted, catalog: parallelCatalog, workers: 2,
                    check: { try parallelToken.check() })
                stageCompletion.finish("unexpected-success")
            } catch SceneDesktopWallpaperHostLaunchError.cancelled {
                stageCompletion.finish("cancelled")
            } catch { stageCompletion.finish("wrong-error:\(error)") }
            stageDone.signal()
        }
        for _ in 0..<2 {
            precondition(stageEntered.wait(timeout: .now() + 30) == .success)
        }
        parallelToken.cancel()
        let stagesStillJoined = stageDone.wait(timeout: .now() + 0.05) == .timedOut
        for _ in 0..<2 { stageRelease.signal() }
        precondition(stageDone.wait(timeout: .now() + 30) == .success)
        checks["parallelStagesJoinBeforeCancellationAndSkipNextStage"] = stagesStillJoined
            && stageCompletion.result == "cancelled" && parallelProbe.reads.count == 2
            && !parallelProbe.reads.contains("81:2")

        let multi = materialGraph(layer: 200, count: 3)
        guard let materialCandidate = candidates([multi]).first,
              case let .success(materialAdmitted) = materialCandidate.result else {
            fatalError("material fixture admission failed")
        }
        let baselineProbe = CancellationEntryProbe()
        var boundaryCount = 0
        guard case .success = try stages(materialAdmitted,
            catalog: observedCatalog([multi], baselineProbe), check: { boundaryCount += 1 }) else {
            fatalError("material fixture must compile successfully")
        }
        var everyBoundaryCancels = boundaryCount > 3
        for stopAt in 1...boundaryCount {
            let boundaryToken = SceneWallpaperLaunchCancellation()
            var reached = 0
            do {
                _ = try stages(materialAdmitted,
                    catalog: observedCatalog([multi], CancellationEntryProbe()), check: {
                        reached += 1
                        if reached == stopAt { boundaryToken.cancel() }
                        try boundaryToken.check()
                    })
                everyBoundaryCancels = false
            } catch SceneDesktopWallpaperHostLaunchError.cancelled {
                everyBoundaryCancels = everyBoundaryCancels && reached == stopAt
            }
        }
        checks["everySerialStageAndMaterialBoundaryKeepsCancellationType"] = everyBoundaryCancels
        let materialToken = SceneWallpaperLaunchCancellation()
        let materialProbe = CancellationEntryProbe { _ in materialToken.cancel() }
        do {
            _ = try stages(materialAdmitted, catalog: observedCatalog([multi], materialProbe),
                check: { try materialToken.check() })
            checks["nextMaterialIsNotEntered"] = false
        } catch SceneDesktopWallpaperHostLaunchError.cancelled {
            checks["nextMaterialIsNotEntered"] = materialProbe.reads == ["200:0"]
        }

        // A callback that throws only once must not lose its original error
        // when a joined sibling or the caller performs the next check.
        enum Sentinel: Error { case stop }
        let checkLock = NSLock(); var fired = false
        do {
            _ = try Capabilities(admissionCandidates: admitted,
                materialCatalog: observedCatalog(graphs, CancellationEntryProbe()), cancellationCheck: {
                    try checkLock.withLock {
                        if !fired { fired = true; throw Sentinel.stop }
                    }
                })
            checks["firstThrownErrorSurvivesParallelJoin"] = false
        } catch Sentinel.stop { checks["firstThrownErrorSurvivesParallelJoin"] = true }
        var stageFired = false
        do {
            _ = try stages(chainAdmitted,
                catalog: observedCatalog([chain], CancellationEntryProbe()), workers: 2, check: {
                    try checkLock.withLock {
                        if !stageFired { stageFired = true; throw Sentinel.stop }
                    }
                })
            checks["firstThrownStageErrorSurvivesParallelJoin"] = false
        } catch Sentinel.stop { checks["firstThrownStageErrorSurvivesParallelJoin"] = true }
        var materialWasRead = false, materialFired = false
        let onceProbe = CancellationEntryProbe { _ in
            checkLock.withLock { materialWasRead = true }
        }
        do {
            _ = try stages(materialAdmitted, catalog: observedCatalog([multi], onceProbe), check: {
                try checkLock.withLock {
                    if materialWasRead && !materialFired {
                        materialFired = true
                        throw Sentinel.stop
                    }
                }
            })
            checks["firstThrownMaterialErrorSurvivesStageJoin"] = false
        } catch Sentinel.stop {
            checks["firstThrownMaterialErrorSurvivesStageJoin"] = onceProbe.reads == ["200:0"]
        }
        let recoveredProbe = CancellationEntryProbe()
        let recovered = try Capabilities(admissionCandidates: admitted,
            materialCatalog: observedCatalog(graphs, recoveredProbe))
        checks["cancelledInvocationDoesNotPoisonNextCatalog"] =
            try projection(recovered, layers: graphs.map(\.layerID)) == expected
                && recoveredProbe.reads == ordinaryProbe.reads
        print(String(decoding: try JSONSerialization.data(withJSONObject: [
            "checks": checks, "workers": workers, "serialBoundaries": boundaryCount,
        ], options: [.sortedKeys]), as: UTF8.self))
    }
}
