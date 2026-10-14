import Darwin
import Foundation
import Metal

enum SceneTextureLoadOutcome {
    case loaded(MTLTexture)
    case decodeFailed(String)
    case textureAllocationFailed(width: Int, height: Int)
}

private typealias Snapshot = SceneFrameTextureRegistrySnapshot
private typealias Identity = SceneFrameTextureIdentity
private typealias Status = SceneFrameTextureLookupStatus
private typealias GraphID = SceneAuthoredEffectRenderPlan.TextureIdentity
private typealias Resource = SceneFrameTextureResource
private let epoch: UInt64 = 41

private func texture(_ device: MTLDevice) -> MTLTexture {
    let descriptor = MTLTextureDescriptor.texture2DDescriptor(
        pixelFormat: .bgra8Unorm, width: 3, height: 2, mipmapped: false)
    descriptor.usage = [.shaderRead, .renderTarget]
    return device.makeTexture(descriptor: descriptor)!
}

private func identity(_ index: Int, prefix: String = "buffer") -> GraphID {
    .init(kind: .framebuffer, layerID: index,
        effect: .init(layerID: index, effectIndex: 0, descriptorID: "renamable-effect"),
        name: "\(prefix)-\(index)")
}

private func resource(_ key: GraphID, texture: MTLTexture, generation: UInt64 = 77,
    purpose: SceneTextureLoadPurpose = .premultipliedColor,
    content: SceneTextureContent = .color(.resolved(.premultipliedAlpha))) -> Resource {
    let size = CGSize(width: texture.width, height: texture.height)
    let candidate = SceneTextureCandidate(texture: texture,
        identity: .provider(.graph(allocationGeneration: 9, physicalToken: "allocation")),
        generation: .provider(contentGeneration: generation), purpose: purpose,
        content: content, physicalSize: size, mappedSize: size,
        uvTransform: .identity, sampling: .linearClamp)
    return .init(publication: .init(requestIdentity: .graph(key), candidate: candidate,
        contentGeneration: generation), resourceGeneration: generation)
}

private func snapshot(_ entries: [Identity: Status]) -> Snapshot {
    .init(frameEpoch: epoch, frameIndex: 9001, entries: entries)
}

private func same(_ lhs: Status?, _ rhs: Status?) -> Bool {
    switch (lhs, rhs) {
    case (nil, nil), (.absent?, .absent?), (.pending?, .pending?),
         (.unavailable?, .unavailable?): return true
    case let (.ready(a)?, .ready(b)?):
        return a.resourceGeneration == b.resourceGeneration
            && a.publication.isSameAtom(as: b.publication)
    case let (.incomplete(.bare(a, ag))?, .incomplete(.bare(b, bg))?):
        return a === b && ag == bg
    case let (.incomplete(.publication(a, ag))?, .incomplete(.publication(b, bg))?):
        return ag == bg && a.isSameAtom(as: b)
    default: return false
    }
}

/// The expected table is authored separately from the snapshot operations.
/// Folding the whole expected table is an oracle for incremental digest updates.
private func matches(_ value: Snapshot, _ expected: [Identity: Status]) -> Bool {
    value.frameEpoch == epoch && value.frameIndex == 9001
        && value.selectionDigest == SceneFrameTextureSelectionDigest(expected)
        && expected.allSatisfy { key, atom in same(value.lookup(key), atom) }
        && value.lookup(.userProperty("never-registered")) == nil
}

private func valueChecks(_ device: MTLDevice) -> [String: Bool] {
    let firstTexture = texture(device), secondTexture = texture(device)
    let a = identity(1), b = identity(2), c = identity(3)
    let first = resource(a, texture: firstTexture)
    let second = resource(a, texture: secondTexture, generation: 78)
    var expected: [Identity: Status] = [
        .graph(a): .ready(first), .userProperty("absent"): .absent,
        .userProperty("pending"): .pending, .userProperty("unavailable"): .unavailable,
        .userProperty("incomplete"): .incomplete(.bare(texture: firstTexture,
            resourceGeneration: 0)), .graph(b): .unavailable,
    ]
    let base = snapshot(expected)
    let original = expected
    var checks = ["initialStatesAndDigest": matches(base, expected),
        "missingIsDifferentFromAbsent": base.lookup(.userProperty("absent")) != nil
            && base.lookup(.userProperty("missing")) == nil]
    let one = base.overlayingGraphResources([a: second])!
    expected[.graph(a)] = .ready(second)
    checks["sameSelectionNewPhysicalAtom"] = base.selectionDigest == one.selectionDigest
        && one.resource(for: .graph(a))?.publication.texture === secondTexture
        && one.resource(for: .graph(a))?.publication.contentGeneration == 78
        && matches(one, expected) && matches(base, original)
    let third = resource(b, texture: firstTexture, generation: 91)
    let two = one.overlayingGraphResources([b: third])!
    expected[.graph(b)] = .ready(third)
    checks["readyShadowsUnavailableAndGenerationIsNotEpoch"] = matches(two, expected)
        && third.resourceGeneration != epoch
    let data = resource(a, texture: firstTexture, generation: 92,
        purpose: .preservedChannels, content: .data)
    let three = two.overlayingGraphResources([a: data])!
    expected[.graph(a)] = .ready(data)
    checks["repeatedReplacementUsesCurrentDigestFact"] = matches(three, expected)
        && three.selectionDigest != two.selectionDigest
    let branch = base.overlayingGraphResources([b: third, a: data])!
    checks["independentBranchAndEquivalentBatch"] = matches(branch, expected)
        && matches(base, original)
    checks["emptyOverlayPreservesAllFacts"] = matches(three.overlayingGraphResources([:])!, expected)

    let bad = Resource(publication: third.publication, resourceGeneration: 0)
    checks["mixedBatchRejectsAtomically"] = three.overlayingGraphResources([c: bad, a: first]) == nil
        && matches(three, expected)
    checks["requestIdentityMismatchRejects"] = three.overlayingGraphResources([c: third]) == nil
    let wrongPurpose = resource(a, texture: firstTexture, purpose: .straightAlbedo)
    checks["wrongPurposeDoesNotEnterColorSnapshot"] = three.overlayingGraphResources([a: wrongPurpose]) == nil
        && matches(three, expected)
    let renamed = identity(15, prefix: "重新命名")
    let renamedAtom = resource(renamed, texture: secondTexture)
    let renamedView = three.overlayingGraphResources([renamed: renamedAtom])!
    expected[.graph(renamed)] = .ready(renamedAtom)
    checks["renamedResourceUsesSameValueSemantics"] = matches(renamedView, expected)

    let reference = SceneNamedTextureReference(providerLayerID: 200, variant: .primary)
    let named = Resource.reservedNamedLayerTarget(reference: reference,
        frameEpoch: epoch, texture: firstTexture)!
    // Storage generations need not equal the publication's frame epoch.
    let storedNamed = Resource(publication: named.publication, resourceGeneration: 500)
    let namedView = renamedView.overlayingNamedLayerTarget(reference, resource: storedNamed)!
    expected[.namedLayerTarget(reference)] = .ready(storedNamed)
    checks["namedKeepsGraphOverlayAndStorageGeneration"] = matches(namedView, expected)
    let background = Resource.sameFrameSceneBackground(consumerLayerID: 300,
        frameEpoch: epoch, texture: secondTexture)!
    let storedBackground = Resource(publication: background.publication, resourceGeneration: 501)
    let backgroundView = namedView.overlayingSceneBackground(consumerLayerID: 300,
        resource: storedBackground)!
    expected[.sceneBackground(300)] = .ready(storedBackground)
    checks["backgroundKeepsOtherOverlayKinds"] = matches(backgroundView, expected)
    let stale = Resource.reservedNamedLayerTarget(reference: reference,
        frameEpoch: epoch - 1, texture: firstTexture)!
    checks["staleNamedAndWrongBackgroundReject"] = backgroundView.overlayingNamedLayerTarget(
        reference, resource: stale) == nil
        && backgroundView.overlayingSceneBackground(consumerLayerID: 301,
            resource: background) == nil && matches(backgroundView, expected)

    let sourceID = 400
    let sourceCandidate = SceneTextureCandidate(texture: firstTexture,
        identity: .provider(.materialSource(layerID: sourceID, frameEpoch: epoch,
            allocationGeneration: 600)), generation: .provider(contentGeneration: epoch),
        purpose: .premultipliedColor, content: .color(.resolved(.premultipliedAlpha)),
        physicalSize: .init(width: 3, height: 2), mappedSize: .init(width: 3, height: 2),
        uvTransform: .identity, sampling: .linearClamp)
    let sourcePublication = SceneTextureProviderPublication(requestIdentity: .layerSource(sourceID),
        candidate: sourceCandidate, contentGeneration: epoch)
    let source = SceneLayerSourcePublication(layerID: sourceID, publication: sourcePublication)!
    let sourceView = backgroundView.overlayingLayerSources([sourceID: source])!
    expected[.layerSource(sourceID)] = .ready(.init(publication: sourcePublication,
        resourceGeneration: epoch))
    checks["layerSourceKeepsAllPreviousKinds"] = matches(sourceView, expected)
    checks["wrongLayerSourceKeyRejectsAtomically"] = sourceView.overlayingLayerSources([
        sourceID + 1: source]) == nil && matches(sourceView, expected)
    return checks
}

private func lifetimeChecks(_ device: MTLDevice, keepBranch: Bool) -> Bool {
    weak var a: MTLTexture?, b: MTLTexture?, c: MTLTexture?
    var branch: Snapshot?, final: Snapshot?
    autoreleasepool {
        let first = texture(device), second = texture(device), third = texture(device)
        a = first; b = second; c = third
        let key = identity(800)
        let base = snapshot([.graph(key): .ready(resource(key, texture: first))])
        let middle = base.overlayingGraphResources([key: resource(key, texture: second)])!
        final = middle.overlayingGraphResources([key: resource(key, texture: third)])!
        if keepBranch { branch = middle }
    }
    // The final view may share the original base A. It must not retain B
    // through an overlay chain unless the caller explicitly keeps that branch.
    let valuesAlive = withExtendedLifetime((final, branch)) {
        c != nil && (b != nil) == keepBranch
    }
    guard valuesAlive else { return false }
    branch = nil
    guard withExtendedLifetime(final, { b == nil }) else { return false }
    final = nil
    return a == nil && b == nil && c == nil
}

private func cpuNanoseconds() -> UInt64 {
    var usage = rusage()
    getrusage(RUSAGE_SELF, &usage)
    return UInt64(usage.ru_utime.tv_sec + usage.ru_stime.tv_sec) * 1_000_000_000
        + UInt64(usage.ru_utime.tv_usec + usage.ru_stime.tv_usec) * 1_000
}

private func benchmark(_ device: MTLDevice) -> [[String: Any]] {
    let shared = texture(device)
    // Keep the original fresh-overlay cases, and also measure copying an
    // accumulated replacement table. Both arms receive the same effective
    // entries; disjoint updates add keys rather than merely replacing them.
    let scenarios: [(count: Int, changed: Int, accumulated: Int, disjoint: Bool)] = [
        (8, 2, 0, false), (8, 8, 0, false), (256, 16, 0, false),
        (2048, 8, 0, false), (1024, 256, 0, false),
        (2048, 8, 256, false), (2048, 8, 256, true),
        (256, 128, 128, false), (256, 128, 128, true),
    ]
    return scenarios.map { count, changed, accumulated, disjoint in
        let entries = Dictionary(uniqueKeysWithValues: (0..<count).map { i in
            (Identity.graph(identity(i)), Status.ready(resource(identity(i), texture: shared)))
        })
        let accumulatedUpdates = Dictionary(uniqueKeysWithValues: (0..<accumulated).map { i in
            (identity(i), resource(identity(i), texture: shared, generation: 78))
        })
        let base = snapshot(entries).overlayingGraphResources(accumulatedUpdates)!
        let firstUpdated = disjoint ? count : 0
        let updates = Dictionary(uniqueKeysWithValues: (0..<changed).map { i in
            (identity(firstUpdated + i), resource(identity(firstUpdated + i), texture: shared, generation: 91))
        })
        let iterations = 1200
        var checksum: UInt64 = 0
        let cpuStart = cpuNanoseconds(), wallStart = DispatchTime.now().uptimeNanoseconds
        for _ in 0..<iterations {
            let next = base.overlayingGraphResources(updates)!
            checksum &+= next.selectionDigest.mixA
            checksum &+= next.resource(for: .graph(identity(firstUpdated + changed - 1)))!.publication.contentGeneration
        }
        let wall = DispatchTime.now().uptimeNanoseconds - wallStart
        let cpu = cpuNanoseconds() - cpuStart
        return ["baseEntries": count, "updatedEntries": changed, "iterations": iterations,
            "accumulatedReplacements": accumulated, "disjointUpdates": disjoint,
            "processCPUNanoseconds": cpu, "wallNanoseconds": wall, "checksum": checksum]
    }
}

@main
private enum Harness {
    static func main() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            print("{\"metalAvailable\":false}"); return
        }
        let result: [String: Any]
        if CommandLine.arguments.contains("--benchmark") {
            result = ["metalAvailable": true, "measurements": benchmark(device)]
        } else {
            var checks = valueChecks(device)
            checks["finalViewDoesNotRetainIntermediateAtom"] = lifetimeChecks(device, keepBranch: false)
            checks["explicitBranchRetiresAtLastValue"] = lifetimeChecks(device, keepBranch: true)
            result = ["metalAvailable": true, "checks": checks]
        }
        let data = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }
}
