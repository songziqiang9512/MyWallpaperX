import Metal

extension SceneOffscreenTexturePool {
    func authoredPairTextures(
        width requestedWidth: Int,
        height requestedHeight: Int,
        maximumDimension: Int
    ) -> Pair? {
        let (width, height) = SceneOffscreenResolutionPolicy.limitedDimensions(
            width: requestedWidth,
            height: requestedHeight,
            maximumDimension: maximumDimension
        )
        guard let candidate = pairCandidate(
            width: width,
            height: height,
            key: .authoredPair(width: width, height: height)
        ), allocationCache.commit([candidate]),
              case .pair(let pair, _) = candidate.allocation else { return nil }
        return pair
    }

    func pairCandidate(width: Int, height: Int) -> Candidate? {
        pairCandidate(
            width: width,
            height: height,
            key: .pair(width: width, height: height)
        )
    }

    func pairCandidate(
        width: Int,
        height: Int,
        key: CacheKey
    ) -> Candidate? {
        guard let resolvedKey: CacheKey = switch key {
        case .pair:
            .pair(width: width, height: height)
        case .authoredPair:
            .authoredPair(width: width, height: height)
        default:
            nil
        } else { return nil }
        guard let byteCost = byteCost(
            width: width,
            height: height,
            textureCount: 3
        ), byteCost <= residentByteBudget else { return nil }
        if let cached = allocationCache.allocation(for: resolvedKey) {
            guard case .pair = cached else { return nil }
            return .init(key: resolvedKey, allocation: cached, byteCost: byteCost)
        }

        let label = "pair:\(width)x\(height)"
        guard let primary = makeTexture(
            width: width, height: height, label: "SceneOffscreenA \(label)"
        ), let secondary = makeTexture(
            width: width, height: height, label: "SceneOffscreenB \(label)"
        ), let tertiary = makeTexture(
            width: width, height: height, label: "SceneOffscreenC \(label)"
        ), let physicalIdentity = allocationCache.issuePhysicalIdentity(
            textures: [primary, secondary, tertiary]
        ) else { return nil }
        return .init(
            key: resolvedKey,
            allocation: .pair(
                Pair(primary: primary, secondary: secondary, tertiary: tertiary),
                physicalIdentity
            ),
            byteCost: byteCost
        )
    }

    func usesPairOnlyLegacyTargets(
        for chain: SceneAuthoredEffectExecutionChain
    ) -> Bool {
        let stages = chain.executionStages
        return !stages.isEmpty && stages.allSatisfy {
            $0.logicalRenderTargetCount == 0
                && $0.renderGraph.renderTargets.isEmpty
        }
    }

    func graphTargets(
        for chain: SceneAuthoredEffectExecutionChain,
        requestedWidth: Int,
        requestedHeight: Int
    ) -> [SceneGraphRenderTargetTable]? {
        let stages = chain.executionStages
        guard pixelFormat == .bgra8Unorm,
              usesPairOnlyLegacyTargets(for: chain),
              let prepared = targetPlans(
                  stages: stages,
                  layerID: chain.layerID,
                  validatesChainOrder: true,
                  enforcesExactExtent: true,
                  requestedWidth: requestedWidth,
                  requestedHeight: requestedHeight
              ), prepared.plans.allSatisfy({ $0.logicalTargets.isEmpty }),
              prepared.plans.last?.output == chain.renderGraph.finalOutput,
              let pair = authoredPairTextures(
                  width: prepared.width,
                  height: prepared.height,
                  maximumDimension: max(prepared.width, prepared.height)
              ) else { return nil }

        let inputs = [pair.primary, pair.tertiary, pair.secondary]
        let outputs = [pair.secondary, pair.primary, pair.tertiary]
        var tables: [SceneGraphRenderTargetTable] = []
        tables.reserveCapacity(prepared.plans.count)
        for (index, plan) in prepared.plans.enumerated() {
            let rotation = index % inputs.count
            guard case .success(let table) = SceneGraphRenderTargetTable.makeBorrowed(
                plan: plan,
                inputTexture: inputs[rotation],
                outputTexture: outputs[rotation]
            ) else { return nil }
            tables.append(table)
        }
        return tables
    }
}
