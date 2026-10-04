import Foundation
import Metal

struct SceneUtilityLayerRuntimePlan {
    enum Disposition: String {
        case capture
        case skippedHidden
        case skippedNoEffect
        case unsupportedDependencies
        case unsupportedChildren
        case unsupportedEffects
    }

    let layerID: Int
    let kind: SceneUtilityLayer.Kind
    let disposition: Disposition
    let requiresNamedTarget: Bool
    let triggerLayerID: Int
    /// Descendants in authored relative order. Empty still denotes the
    /// transparent source of a childless composition with copybackground=false.
    var isolatedGroupMembers: [Int]? = nil

    var shouldCapture: Bool { disposition == .capture }
    var usesIsolatedGroupTarget: Bool { isolatedGroupMembers != nil }
}

enum SceneUtilityLayerRuntimePlanner {
    struct Execution {
        let orderedLayerIDs: [Int]
        let plansByTriggerLayerID: [Int: [SceneUtilityLayerRuntimePlan]]
        let captureLayerIDs: Set<Int>
        let memberRootsByLayerID: [Int: Int]
        let membersByRootID: [Int: [Int]]
        let orderedRootIDs: [Int]
        let copyBackgroundRootIDs: Set<Int>
    }

    /// Prepared once per descriptor/topology revision. Members execute at
    /// their root's authored position; preparation and encode share this order.
    static func execution(
        in descriptor: SceneRenderDescriptor,
        plans: [Int: SceneUtilityLayerRuntimePlan]
    ) -> Execution {
        let values = Array(plans.values)
        let membership = SceneCompositionGroupFrameRuntime.membership(of: values)
        // A no-effect group needs only ordering: its children draw directly to
        // the enclosing pass, without an extra target or graph transaction.
        let orderMembership = SceneCompositionGroupFrameRuntime.membership(
            of: values, includesNoEffectGroups: true
        )
        var ordered: [Int] = []
        func append(_ layerID: Int) {
            if let members = orderMembership.membersByRootID[layerID] {
                for memberID in members where
                    orderMembership.memberRootsByLayerID[memberID] == layerID {
                    append(memberID)
                }
            }
            ordered.append(layerID)
        }
        for layerID in descriptor.renderOrderLayerIDs where
            orderMembership.memberRootsByLayerID[layerID] == nil {
            append(layerID)
        }
        let captures = values.filter(\.shouldCapture)
        return Execution(
            orderedLayerIDs: ordered,
            plansByTriggerLayerID: Dictionary(grouping: captures, by: \.triggerLayerID),
            captureLayerIDs: Set(captures.map(\.layerID)),
            memberRootsByLayerID: membership.memberRootsByLayerID,
            membersByRootID: membership.membersByRootID,
            orderedRootIDs: ordered.filter { membership.membersByRootID[$0] != nil },
            copyBackgroundRootIDs: Set(descriptor.layers.compactMap { layer in
                membership.membersByRootID[layer.id] != nil
                    && layer.utilityLayer?.copyBackground == true ? layer.id : nil
            })
        )
    }

    static func plans(
        in descriptor: SceneRenderDescriptor,
        resolvedMaterialLayerIDs: Set<Int> = [],
        admittedResolvedMaterialReferences:
            Set<SceneDependencyRenderPlan.Reference> = []
    ) -> [Int: SceneUtilityLayerRuntimePlan] {
        let dependencyPlan = SceneDependencyRenderPlan(
            descriptor: descriptor,
            visibleLayerIDs: SceneLayerVisibility.visibleLayerIDs(in: descriptor),
            executableUtilityConsumerLayerIDs: executableUtilityConsumerLayerIDs(
                in: descriptor,
                resolvedMaterialLayerIDs: resolvedMaterialLayerIDs
            ),
            admittedResolvedMaterialReferences: admittedResolvedMaterialReferences
        )
        return plans(
            in: descriptor,
            dependencyPlan: dependencyPlan,
            resolvedMaterialLayerIDs: resolvedMaterialLayerIDs
        )
    }

    static func plans(
        in descriptor: SceneRenderDescriptor,
        dependencyPlan: SceneDependencyRenderPlan,
        resolvedMaterialLayerIDs: Set<Int>
    ) -> [Int: SceneUtilityLayerRuntimePlan] {
        let visibleLayerIDs = SceneLayerVisibility.visibleLayerIDs(in: descriptor)
        let namedTargetLayerIDs = Set(descriptor.layers.flatMap(\.dependencyLayerIDs))
        return Dictionary(uniqueKeysWithValues: descriptor.layers.compactMap { layer in
            guard let utility = layer.utilityLayer else { return nil }
            let sourceRoute = try? SceneUtilityLayerSourceRoute.resolve(
                layer: layer,
                descriptor: descriptor
            ).get()
            let hasVisibleEffects = layer.effects.contains { $0.visible != false }
            let disposition: SceneUtilityLayerRuntimePlan.Disposition
            // Admission may prepare a dynamically visible fullscreen while
            // its layer or effect seed is hidden. Keep its capture route;
            // the committed frame's target plans still gate actual encoding.
            let preparedFullscreen = utility.kind == .fullscreen
                && layer.contentKind == "fullscreen"
                && resolvedMaterialLayerIDs.contains(layer.id)
                && layer.parentID == nil && layer.childLayerIDs.isEmpty
                && layer.dependencyLayerIDs.isEmpty && sourceRoute != nil
            let isolatedComposition = utility.kind == .composition
                && sourceRoute?.usesIsolatedGroupTarget == true
            let preparedComposition = utility.kind == .composition
                && !utility.passthrough && sourceRoute != nil
                && layer.dependencyLayerIDs.isEmpty && layer.authoredDependencies.isEmpty
                && resolvedMaterialLayerIDs.contains(layer.id)
            let preparedUtility = preparedFullscreen || preparedComposition
            // Hidden prepared groups retain their source plan. No-effect
            // groups retain only ordering and allocate no capture target.
            if !visibleLayerIDs.contains(layer.id) && !preparedUtility
                && !(isolatedComposition && !hasVisibleEffects) {
                disposition = .skippedHidden
            } else if !layer.dependencyLayerIDs.isEmpty {
                let binding = dependencyPlan.bindingsByConsumerLayerID[layer.id]
                let isAggregate = dependencyPlan
                    .multiProviderAggregatesByConsumerLayerID[layer.id] != nil
                let isLegacyExecutable = binding != nil
                    && dependencyPlan.executableUtilityConsumerLayerIDs.contains(layer.id)
                // A dependency-bearing utility captures only with an exact
                // aggregate owner or the legacy single-provider binding. A
                // missing binding is not evidence that an effect was safely
                // replaced; treating it as capture would publish a base image
                // under an unowned named target.
                if utility.kind == .composition,
                   sourceRoute?.capturesCompositionSubtree == false,
                   resolvedMaterialLayerIDs.contains(layer.id),
                   (isAggregate || isLegacyExecutable) {
                    disposition = .capture
                } else {
                    disposition = .unsupportedDependencies
                }
            } else if !hasVisibleEffects && !preparedUtility {
                disposition = .skippedNoEffect
            } else if sourceRoute == nil, !layer.childLayerIDs.isEmpty {
                disposition = .unsupportedChildren
            } else if sourceRoute != nil,
                      resolvedMaterialLayerIDs.contains(layer.id) {
                disposition = .capture
            } else {
                disposition = .unsupportedEffects
            }
            return (
                layer.id,
                SceneUtilityLayerRuntimePlan(
                    layerID: layer.id,
                    kind: utility.kind,
                    disposition: disposition,
                    requiresNamedTarget: namedTargetLayerIDs.contains(layer.id),
                    triggerLayerID: sourceRoute?.triggerLayerID ?? layer.id,
                    isolatedGroupMembers: sourceRoute?.usesIsolatedGroupTarget
                        == true
                        ? sourceRoute?.orderedCompositionSubtreeLayerIDs : nil
                )
            )
        })
    }

    static func executableUtilityConsumerLayerIDs(
        in descriptor: SceneRenderDescriptor,
        resolvedMaterialLayerIDs: Set<Int> = []
    ) -> Set<Int> {
        let visibleLayerIDs = SceneLayerVisibility.visibleLayerIDs(in: descriptor)
        let referencesByConsumer = Dictionary(
            grouping: SceneDependencyGraphAnalysis.references(in: descriptor.layers),
            by: \.consumerLayerID
        )
        return Set(descriptor.layers.compactMap { layer in
            let multiProvider = SceneDependencyRenderPlan
                .isMultiProviderUtilityCandidate(
                    layer: layer,
                    references: referencesByConsumer[layer.id] ?? []
                )
            guard visibleLayerIDs.contains(layer.id),
                  resolvedMaterialLayerIDs.contains(layer.id),
                  layer.utilityLayer?.kind == .composition,
                  layer.contentKind == "composition",
                  layer.childLayerIDs.isEmpty,
                  (layer.dependencyLayerIDs.count == 1 || multiProvider),
                  layer.effects.contains(where: { $0.visible != false }) else {
                return nil
            }
            return layer.id
        })
    }

    static func reportLines(
        descriptor: SceneRenderDescriptor,
        resolvedMaterialLayerIDs: Set<Int> = [],
        admittedResolvedMaterialReferences:
            Set<SceneDependencyRenderPlan.Reference> = [],
        propertyVisibilityOwnedLayerIDs: Set<Int> = []
    ) -> [String] {
        let executableConsumers = executableUtilityConsumerLayerIDs(
            in: descriptor,
            resolvedMaterialLayerIDs: resolvedMaterialLayerIDs
        )
        let dependencyPlan = SceneDependencyRenderPlan(
            descriptor: descriptor,
            visibleLayerIDs: SceneLayerVisibility.visibleLayerIDs(in: descriptor),
            executableUtilityConsumerLayerIDs: executableConsumers,
            admittedResolvedMaterialReferences: admittedResolvedMaterialReferences
        )
        let plans = plans(
            in: descriptor,
            dependencyPlan: dependencyPlan,
            resolvedMaterialLayerIDs: resolvedMaterialLayerIDs
        )
        let ordered = descriptor.layers.compactMap { plans[$0.id] }
        let dependencyEdges = descriptor.layers.flatMap(\.dependencyLayerIDs).count
        // These diagnostics describe utility/effect consumers only. Static
        // model material inputs share the named target runtime, but are not
        // utility layers and may be dynamically inactive for the entire run.
        let namedTargetProviderIDs = Set(
            dependencyPlan.bindingsByConsumerLayerID.values.map(\.providerLayerID)
        )
        let layersByID = Dictionary(
            uniqueKeysWithValues: descriptor.layers.map { ($0.id, $0) }
        )
        // A binding is conditional when either endpoint's visibility is owned
        // by a script anywhere up its parent chain: launch admission planned
        // it optimistically (the authored value is only the seed), so the
        // binding may legitimately stay idle until the owning script shows
        // the layer.
        func endpointIsScriptOwnedVisible(_ layerID: Int) -> Bool {
            var current = layersByID[layerID]
            var visited: Set<Int> = []
            while let candidate = current {
                if candidate.displayScriptOwnership?.visible == true {
                    return true
                }
                guard visited.insert(candidate.id).inserted else { break }
                current = candidate.parentID.flatMap { layersByID[$0] }
            }
            return false
        }
        // A consumer endpoint that launch admission already left hidden, or
        // whose visibility a property owner can flip at runtime, can keep its
        // planned binding legitimately idle: the authored-visible seed only
        // optimistically plans it. Providers are excluded on purpose - a
        // hidden provider still publishes through the forward prepass, so its
        // consumer binding remains an execution requirement.
        let launchVisibleLayerIDs = SceneLayerVisibility.visibleLayerIDs(
            in: descriptor
        )
        func consumerIsConditionallyIdle(_ layerID: Int) -> Bool {
            !launchVisibleLayerIDs.contains(layerID)
                || propertyVisibilityOwnedLayerIDs.contains(layerID)
        }
        func bindingIsConditional(_ binding: SceneDependencyRenderPlan.Binding)
            -> Bool {
            endpointIsScriptOwnedVisible(binding.consumerLayerID)
                || endpointIsScriptOwnedVisible(binding.providerLayerID)
                || consumerIsConditionallyIdle(binding.consumerLayerID)
        }
        let namedBindingConditionalCount = dependencyPlan
            .bindingsByConsumerLayerID.values
            .filter(bindingIsConditional).count
        let namedBindingConditionalLayerIDs = dependencyPlan
            .bindingsByConsumerLayerID
            .filter { bindingIsConditional($0.value) }
            .keys
            .sorted()
            .map(String.init)
            .joined(separator: ",")
        let namedBindingConsumerLayerIDs = dependencyPlan
            .bindingsByConsumerLayerID.keys
            .sorted()
            .map(String.init)
            .joined(separator: ",")
        let namedTargetGaps = ordered.filter {
            $0.requiresNamedTarget && !namedTargetProviderIDs.contains($0.layerID)
        }
        var lines = [
            "utilityLayerCount: \(ordered.count)",
            "utilityCapturePlannedCount: \(ordered.filter(\.shouldCapture).count)",
            "utilityDependencyEdgeCount: \(dependencyEdges)",
            "utilityNamedConsumerCount: \(dependencyPlan.namedReferenceConsumerLayerIDs.count)",
            "utilityNamedTargetPlannedCount: \(namedTargetProviderIDs.count)",
            "utilityNamedBindingPlannedCount: \(dependencyPlan.bindingsByConsumerLayerID.count)",
            "utilityNamedBindingConditionalCount: \(namedBindingConditionalCount)",
            "utilityNamedBindingConditionalLayerIDs: \(namedBindingConditionalLayerIDs)",
            "utilityNamedBindingConsumerLayerIDs: \(namedBindingConsumerLayerIDs)",
            "utilityNamedTargetGapCount: \(namedTargetGaps.count)",
            "utilityDependencyIssueCount: \(dependencyPlan.issues.count)",
        ]
        for issue in dependencyPlan.issues {
            let provider = issue.providerLayerID.map(String.init) ?? "-"
            lines.append(
                "utilityDependencyIssue: kind=\(issue.kind.rawValue) "
                    + "layer=\(issue.layerID) provider=\(provider)"
            )
        }
        for plan in ordered {
            let namedTarget: String
            if namedTargetProviderIDs.contains(plan.layerID) {
                namedTarget = "; named target planned"
            } else if plan.requiresNamedTarget {
                namedTarget = "; named target unsupported"
            } else {
                namedTarget = ""
            }
            lines.append(
                "utility layer \(plan.layerID): \(plan.disposition.rawValue) "
                    + "kind=\(plan.kind.rawValue) "
                    + "trigger=\(plan.triggerLayerID)\(namedTarget)"
            )
        }
        return lines
    }
}

/// Composition-group frame runtime. Members draw into a private source
/// initialized from the enclosing background or transparent clear, then
/// composite once at their root's authored position. A target
/// allocation failure degrades the whole group to previous-current: members
/// are skipped entirely and never leak uncomposited content into the parent
/// target. Nested groups resolve innermost-first; an inner group whose
/// parent pass is degraded skips its own composite for the same reason.
final class SceneCompositionGroupFrameRuntime {
    private let parentPass: SceneMainPassEncoder
    private let commandBuffer: MTLCommandBuffer
    private let offscreenTexturePool: SceneOffscreenTexturePool
    private let memberRootsByLayerID: [Int: Int]
    private let membersByRootID: [Int: [Int]]
    private let copyBackgroundRootIDs: Set<Int>
    private let viewportSize: CGSize
    private var passesByRootID: [Int: SceneMainPassEncoder] = [:]
    private var texturesByRootID: [Int: MTLTexture] = [:]
    private var degradedRootIDs: Set<Int> = []
    private var sourcePins: [SceneGraphRenderTargetResidencyPin] = []
    private var initializedRootIDs: Set<Int> = []
    private let resetEpoch: UUID

    init(
        parentPass: SceneMainPassEncoder,
        commandBuffer: MTLCommandBuffer,
        offscreenTexturePool: SceneOffscreenTexturePool,
        memberRootsByLayerID: [Int: Int],
        membersByRootID: [Int: [Int]],
        viewportSize: CGSize,
        copyBackgroundRootIDs: Set<Int> = []
    ) {
        self.parentPass = parentPass
        self.commandBuffer = commandBuffer
        self.offscreenTexturePool = offscreenTexturePool
        self.memberRootsByLayerID = memberRootsByLayerID
        self.membersByRootID = membersByRootID
        self.copyBackgroundRootIDs = copyBackgroundRootIDs
        self.viewportSize = viewportSize
        self.resetEpoch = offscreenTexturePool.sceneColorResetEpoch
    }

    /// Reserve the selected sources before graph preparation. No encoder is
    /// created until the layer loop writes or consumes a source.
    func reserveSources(orderedRootIDs: [Int], visibleLayerIDs: Set<Int>) {
        for rootID in orderedRootIDs {
            if visibleLayerIDs.contains(rootID) {
                _ = reservePass(forRootID: rootID)
            } else {
                degradedRootIDs.insert(rootID)
            }
        }
    }

    func sourceIsAvailable(forLayerID layerID: Int) -> Bool {
        var current: Int? = membersByRootID[layerID] == nil
            ? memberRootsByLayerID[layerID] : layerID
        while let rootID = current {
            if degradedRootIDs.contains(rootID) { return false }
            current = memberRootsByLayerID[rootID]
        }
        return true
    }

    func preparedSource(forLayerID layerID: Int, mainTarget: MTLTexture) -> MTLTexture? {
        guard sourceIsAvailable(forLayerID: layerID) else { return nil }
        let rootID = membersByRootID[layerID] == nil
            ? memberRootsByLayerID[layerID] : layerID
        return rootID.flatMap { texturesByRootID[$0] } ?? (rootID == nil ? mainTarget : nil)
    }

    func cancel() {
        sourcePins.forEach { $0.release() }
        sourcePins.removeAll()
    }

    func arm() {
        let pins = sourcePins
        sourcePins.removeAll()
        commandBuffer.addCompletedHandler { _ in pins.forEach { $0.release() } }
    }

    /// Static membership for one render descriptor: every layer maps to its
    /// nearest admitted group root. A root nested inside another group maps
    /// to the enclosing root, so its composite draws into the enclosing
    /// group's pass.
    static func membership(
        of plans: [SceneUtilityLayerRuntimePlan],
        includesNoEffectGroups: Bool = false
    ) -> (memberRootsByLayerID: [Int: Int], membersByRootID: [Int: [Int]]) {
        let admitted = plans.filter {
            $0.usesIsolatedGroupTarget && ($0.shouldCapture
                || (includesNoEffectGroups && $0.disposition == .skippedNoEffect))
        }
        let membersByRootID = Dictionary(
            uniqueKeysWithValues: admitted.map { ($0.layerID, $0.isolatedGroupMembers ?? []) }
        )
        let memberSetsByRootID = membersByRootID.mapValues(Set.init)
        var memberRootsByLayerID: [Int: Int] = [:]
        for (rootID, members) in memberSetsByRootID {
            for memberID in members where memberID != rootID {
                // Nearest root wins: replace a previously mapped root only
                // when its subtree strictly contains this one (larger member
                // set), so nesting resolves innermost-first.
                if let existing = memberRootsByLayerID[memberID],
                   (memberSetsByRootID[existing]?.count ?? Int.max)
                       <= members.count {
                    continue
                }
                memberRootsByLayerID[memberID] = rootID
            }
        }
        return (memberRootsByLayerID, membersByRootID)
    }

    /// The render pass a layer's content must encode into: its nearest
    /// admitted group's pass, or the frame's main pass for non-members.
    /// `nil` means the group is degraded this frame and the layer must be
    /// skipped so uncomposited content cannot reach the parent target.
    func renderPass(
        forLayerID layerID: Int,
        beginsRendering: Bool = false
    ) -> SceneMainPassEncoder? {
        guard let rootID = memberRootsByLayerID[layerID] else {
            return parentPass
        }
        return beginsRendering ? beginGroup(forRootID: rootID) : reservePass(forRootID: rootID)
    }

    /// The composited output target of one group, creating the group pass on
    /// first use. A freshly created target is transparently cleared.
    func groupTexture(forRootID rootID: Int) -> MTLTexture? {
        guard resetEpoch == offscreenTexturePool.sceneColorResetEpoch,
              sourceIsAvailable(forLayerID: rootID),
              let pass = beginGroup(forRootID: rootID) else { return nil }
        // A frame with no member draw must still initialize the reused source.
        return pass.withReadableTarget { texture, _ in texture }
    }

    /// The pass a group's single composite must encode into: the nearest
    /// enclosing group's pass, or the frame's main pass. `nil` when an
    /// enclosing group is degraded, in which case the composite is skipped.
    func compositeTargetPass(
        forRootID rootID: Int,
        beginsRendering: Bool = false
    ) -> SceneMainPassEncoder? {
        guard let enclosingRootID = memberRootsByLayerID[rootID] else {
            return parentPass
        }
        return beginsRendering
            ? beginGroup(forRootID: enclosingRootID) : reservePass(forRootID: enclosingRootID)
    }

    func closeAllGroupEncoders() {
        for pass in passesByRootID.values {
            pass.closeForOffscreen()
        }
    }

    private func beginGroup(forRootID rootID: Int) -> SceneMainPassEncoder? {
        guard sourceIsAvailable(forLayerID: rootID),
              let pass = reservePass(forRootID: rootID) else { return nil }
        if initializedRootIDs.contains(rootID) { return pass }
        // Initialize enclosing groups first. Reservation never samples pixels:
        // this background belongs to the root's actual authored position.
        guard let enclosingPass = compositeTargetPass(
            forRootID: rootID, beginsRendering: true
        ) else { return nil }
        closeAllGroupEncoders()
        parentPass.closeForOffscreen()
        let initialized: Bool
        if copyBackgroundRootIDs.contains(rootID) {
            initialized = enclosingPass.withReadableTarget { source, _ in
                pass.withReadableTarget { target, commandBuffer in
                    // Both targets come from the viewport-sized frame/pool
                    // producers; a resize or format mismatch cannot be blitted.
                    guard source.width == target.width,
                          source.height == target.height,
                          source.pixelFormat == target.pixelFormat else { return false }
                    guard let blit = commandBuffer.makeBlitCommandEncoder() else { return false }
                    blit.copy(from: source, sourceSlice: 0, sourceLevel: 0,
                        sourceOrigin: MTLOrigin(),
                        sourceSize: MTLSize(width: source.width, height: source.height, depth: 1),
                        to: target, destinationSlice: 0, destinationLevel: 0,
                        destinationOrigin: MTLOrigin())
                    blit.endEncoding()
                    SceneGPUCensus.recordTextureCopy(texture: target)
                    return true
                } ?? false
            } ?? false
        } else {
            initialized = pass.withReadableTarget { _, _ in true } ?? false
        }
        guard initialized else {
            degradedRootIDs.insert(rootID)
            return nil
        }
        initializedRootIDs.insert(rootID)
        return pass
    }

    private func reservePass(forRootID rootID: Int) -> SceneMainPassEncoder? {
        if degradedRootIDs.contains(rootID) { return nil }
        if let pass = passesByRootID[rootID] { return pass }
        let width = max(1, Int(viewportSize.width.rounded(.up)))
        let height = max(1, Int(viewportSize.height.rounded(.up)))
        guard let target = offscreenTexturePool.compositionGroupTarget(
            layerID: rootID,
            width: width,
            height: height,
            commandBuffer: commandBuffer
        ) else {
            degradedRootIDs.insert(rootID)
            return nil
        }
        let pass = SceneMainPassEncoder(
            commandBuffer: commandBuffer,
            target: target.texture,
            clearColor: MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0),
            clearEnabled: true,
            submissionOwner: parentPass
        )
        passesByRootID[rootID] = pass
        texturesByRootID[rootID] = target.texture
        sourcePins.append(target.pin)
        return pass
    }
}

extension SceneRenderDescriptor {
    func requiresReadableFramebuffer(
        sceneBackgroundLayerIDs: Set<Int>,
        utilityCaptureLayerIDs: Set<Int>,
        dependencyPlan: SceneDependencyRenderPlan
    ) -> Bool {
        if !sceneBackgroundLayerIDs.isEmpty || !utilityCaptureLayerIDs.isEmpty {
            return true
        }
        if materialPasses.contains(where: { $0.combos["REFRACT"] == 1 }) {
            return true
        }
        // Drawable usage is fixed at launch. A prepared layer can become
        // visible later, including through a parent, and then read the target.
        if layers.contains(where: { layer in
            ["image", "solid", "text"].contains(layer.contentKind)
                && (1 ... SceneBlendModeShaderSource.maximumMode).contains(
                    layer.colorBlendMode ?? 0
                )
        }) {
            return true
        }
        return !dependencyPlan.requiredProviderLayerIDs.isEmpty
    }
}
