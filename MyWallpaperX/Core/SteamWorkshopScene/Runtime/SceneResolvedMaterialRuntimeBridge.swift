import CoreGraphics
import Foundation
import Metal
import simd

/// Per-surface CPU audit; R4 replaces it at the same graph-node boundary.
final class SceneResolvedMaterialRuntimeBridge {
    typealias Graph = SceneAuthoredEffectRenderPlan
    typealias Failure = SceneResolvedMaterialFailure
    typealias LogSink = (String) -> Void

    private enum Outcome {
        case accepted
        case failure(Failure, disposition: String)
    }

    private let catalog: SceneResolvedMaterialRuntimeCatalog
    private let assets: SceneMaterialAssetTextureCatalog
    private let logSink: LogSink
    private var frame: SceneResolvedMaterialFrameSnapshot?
    private var frameFailure: Failure?
    private var outcomes: [SceneResolvedMaterialRuntimeCatalog.Key: Outcome] = [:]
    private var finalizationAttemptedKeys: Set<
        SceneResolvedMaterialRuntimeCatalog.Key
    > = []
    private var lastReportSignature: String?
    private var frameIsActive = false
    private var launchAuditCompleted = false

    init(
        catalog: SceneResolvedMaterialRuntimeCatalog,
        assets: SceneMaterialAssetTextureCatalog,
        logSink: @escaping LogSink = { NSLog("%@", $0) }
    ) {
        self.catalog = catalog
        self.assets = assets
        self.logSink = logSink
    }

    var assetStates: [SceneAssetTextureIdentity: SceneTextureProviderState] {
        assets.states
    }

    var userPropertyDemands: Set<SceneUserPropertyTextureIdentity> {
        catalog.userPropertyDemands
    }

    func userPropertyDemands(
        including declaredPropertyKeys: [String]
    ) -> Set<SceneUserPropertyTextureIdentity> {
        catalog.userPropertyDemands.union(declaredPropertyKeys.compactMap {
            SceneUserPropertyTextureIdentity(
                propertyKey: $0,
                purpose: .premultipliedColor
            )
        })
    }

    func systemProviderBlocks(
        for snapshot: SceneMediaThumbnailTextureStore.Snapshot
    ) -> [String: SceneFrameTextureRegistry.ProviderStatus] {
        let grouped = Dictionary(grouping: catalog.systemProviderDemands) {
            $0.name
        }
        var blocks: [String: SceneFrameTextureRegistry.ProviderStatus] = [:]
        for name in grouped.keys.sorted() {
            guard let demands = grouped[name],
                  demands.count == 1,
                  let demand = demands.first,
                  let publication = snapshot.publications[name],
                  let texture = snapshot.systemTextures[name],
                  publication.requestIdentity == .system(name),
                  publication.texture === texture,
                  publication.candidate.purpose == demand.purpose,
                  publication.isComplete else {
                blocks[name] = .unavailable
                continue
            }
        }
        return blocks
    }

    func beginFrame(
        textureSnapshot: SceneFrameTextureRegistrySnapshot,
        dynamicSnapshot: SceneDynamicSnapshot,
        frameInputs: SceneAuthoredShaderFrameInputs
    ) {
        guard !launchAuditCompleted else {
            frameIsActive = false
            return
        }
        frameIsActive = true
        outcomes.removeAll(keepingCapacity: true)
        finalizationAttemptedKeys.removeAll(keepingCapacity: true)
        switch SceneResolvedMaterialFrameSnapshot.validated(
            textureSnapshot: textureSnapshot,
            dynamicSnapshot: dynamicSnapshot,
            frameInputs: frameInputs
        ) {
        case let .success(snapshot):
            frame = snapshot
            frameFailure = nil
        case let .failure(failure):
            frame = nil
            frameFailure = failure
        }
        for (key, entry) in catalog.entries {
            if let frameFailure {
                outcomes[key] = .failure(
                    frameFailure,
                    disposition: "frame-envelope-invalid"
                )
            } else if case let .failure(failure) = entry {
                outcomes[key] = .failure(
                    failure,
                    disposition: "template-unavailable"
                )
            } else {
                outcomes[key] = .failure(
                    .init(
                        phase: .graph,
                        code: .graphNodeInvalid,
                        details: ["audit-render-path-unavailable"]
                    ),
                    disposition: "render-path-unavailable"
                )
            }
        }
    }

    func auditResolvedMaterials(
        graph: Graph,
        targets: SceneGraphRenderTargetTable
    ) {
        guard frameIsActive else { return }
        let materials = graph.nodes.filter { $0.kind == .material }
        let commandStateUnavailable = graph.nodes.contains {
            $0.kind == .copy || $0.kind == .swap
        }
        for node in materials {
            let key = SceneResolvedMaterialRuntimeCatalog.Key(
                effect: node.effect,
                nodeIndex: node.nodeIndex
            )
            let result: Result<SceneResolvedMaterialProgram, Failure>
            let disposition: String
            if let failure = frameFailure {
                result = .failure(failure)
                disposition = "frame-envelope-invalid"
            } else if commandStateUnavailable {
                result = .failure(.init(
                    phase: .graph,
                    code: .graphNodeInvalid,
                    details: ["audit-command-state-unavailable"]
                ))
                disposition = "command-state-unavailable"
            } else if case let .failure(failure)? = catalog.entry(for: node) {
                result = .failure(failure)
                disposition = "template-unavailable"
            } else if case let .template(template)? = catalog.entry(for: node),
                      let frame,
                      let targetIdentity = node.target,
                      let target = targets.texture(for: targetIdentity),
                      target.width > 0,
                      target.height > 0 {
                let width = Float(target.width)
                let height = Float(target.height)
                finalizationAttemptedKeys.insert(key)
                result = SceneResolvedMaterialProgramFinalizer.finalize(
                    frame.finalizationInput(
                        template: template,
                        renderSize: CGSize(
                            width: target.width,
                            height: target.height
                        ),
                        modelViewProjection: simd_float4x4(diagonal: SIMD4(
                            2 / width,
                            2 / height,
                            1,
                            1
                        ))
                    )
                )
                disposition = "finalization-failed"
            } else {
                result = .failure(.init(
                    phase: .graph,
                    code: .graphNodeInvalid
                ))
                disposition = "render-target-unavailable"
            }
            switch result {
            case .success:
                outcomes[key] = .accepted
            case let .failure(failure):
                outcomes[key] = .failure(failure, disposition: disposition)
            }
        }
    }

    @discardableResult
    func endFrame() -> [String] {
        guard frameIsActive else {
            return [
                "resolved material runtime audit:"
                    + " schema=r3-finalization-audit-v1 state=inactive"
                    + " gpuEncoded=0"
            ]
        }
        let failures = outcomes.values.compactMap { outcome -> Failure? in
            guard case let .failure(failure, _) = outcome else { return nil }
            return failure
        }
        let dispositions = outcomes.values.compactMap { outcome -> String? in
            guard case let .failure(_, disposition) = outcome else { return nil }
            return disposition
        }
        var lines = [
            "resolved material runtime audit: schema=r3-finalization-audit-v1"
                + " mode=first-active-frame"
                + " nodes=\(outcomes.count)"
                + " finalizationAttempted=\(finalizationAttemptedKeys.count)"
                + " accepted=\(outcomes.count - failures.count)"
                + " failures=\(failures.count) gpuEncoded=0"
        ]
        let grouped = Dictionary(grouping: failures) {
            "\($0.phase.rawValue):\($0.code.rawValue)"
        }
        lines += grouped.keys.sorted().map {
            "resolved material runtime failure: \($0)"
                + " count=\(grouped[$0]?.count ?? 0)"
        }
        let dispositionGroups = Dictionary(grouping: dispositions) { $0 }
        lines += dispositionGroups.keys.sorted().map {
            "resolved material runtime disposition: code=\($0)"
                + " count=\(dispositionGroups[$0]?.count ?? 0)"
        }
        let signature = lines.joined(separator: "\n")
        if signature != lastReportSignature {
            lastReportSignature = signature
            lines.forEach(logSink)
        }
        frame = nil
        frameFailure = nil
        outcomes.removeAll(keepingCapacity: true)
        finalizationAttemptedKeys.removeAll(keepingCapacity: true)
        frameIsActive = false
        launchAuditCompleted = true
        return lines
    }
}
