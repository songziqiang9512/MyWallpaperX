import Foundation
import Metal

// Exercise the real store publications through the frame registry and material
// slot metadata. Mask views must share the preserved upload, never PMA pixels.
func checkMediaThumbnailMasks(
    device: MTLDevice,
    snapshots: [String: SceneMediaThumbnailTextureStore.Snapshot]
) -> [String: Bool] {
    let current = SceneSystemProviderTextureIdentity(
        name: SceneBaseMaterialProviderBindingProgram.currentIdentity, purpose: .mask)
    let previous = SceneSystemProviderTextureIdentity(
        name: SceneBaseMaterialProviderBindingProgram.previousIdentity, purpose: .mask)
    func state(_ stage: String, _ identity: SceneSystemProviderTextureIdentity,
               is expected: SceneTextureProviderState) -> Bool {
        switch (snapshots[stage]?.providerStates[identity], expected) {
        case (.absent?, .absent), (.pending?, .pending), (.unavailable?, .unavailable): true
        default: false
        }
    }
    func ready(_ stage: String, _ identity: SceneSystemProviderTextureIdentity) -> Bool {
        guard let snapshot = snapshots[stage],
              let atom = snapshot.publications[identity],
              case let .ready(stateAtom)? = snapshot.providerStates[identity] else { return false }
        let preserved = identity == current ? snapshot.preservedCurrent : snapshot.preservedPrevious
        let provider: SceneTextureProviderIdentity = identity == current
            ? .mediaThumbnailCurrent : .mediaThumbnailPrevious
        let registry = SceneFrameTextureRegistry()
        registry.beginFrame(frameIndex: snapshot.generation, layerSources: [:],
            systemProviderStates: snapshot.providerStates)
        guard case let .ready(resource)? = registry.lookup(.system(identity)),
              let binding = SceneTextureSlotBinding(slotIndex: 2, candidate: resource.publication.candidate)
        else { return false }
        return atom.requestIdentity == .system(identity) && atom.isComplete
            && atom.generationIsCurrent && atom.contentGeneration == snapshot.generation
            && atom.candidate.identity == .provider(provider)
            && atom.candidate.generation == .provider(contentGeneration: snapshot.generation)
            && atom.candidate.purpose == .mask && atom.candidate.content == .data
            && atom.texture === preserved?.texture
            && snapshot.systemTextures[identity] === atom.texture
            && stateAtom.isSameAtom(as: atom)
            && resource.publication.isSameAtom(as: atom)
            && binding.axisAlignedUVScale(expectedSlotIndex: 2, expectedPurpose: .mask,
                allowedPixelFormats: [.rgba8Unorm], requiresIdentityUV: true) == SIMD2(repeating: 1)
    }
    var checks: [String: Bool] = [
        "empty": state("empty", current, is: .absent) && state("empty", previous, is: .absent),
        "initialPending": state("initialPending", current, is: .pending)
            && state("initialPending", previous, is: .absent),
        "firstCurrent": ready("first", current) && state("first", previous, is: .absent),
        "hiddenRGB": pixel(snapshots["first"]?.publications[current]?.texture) == [231, 17, 149, 0],
        "replacementPending": ready("replacementPending", current)
            && state("replacementPending", previous, is: .pending),
        "rotated": ready("rotated", current) && ready("rotated", previous),
        "previousHiddenRGB": pixel(snapshots["rotated"]?.publications[previous]?.texture)
            == [231, 17, 149, 0],
        "failedDecode": state("failed", current, is: .unavailable)
            && state("failed", previous, is: .unavailable),
        "recoveryPending": state("recoveryPending", current, is: .pending)
            && state("recoveryPending", previous, is: .pending),
        "recovered": ready("recovered", current) && ready("recovered", previous),
        "clear": state("clear", current, is: .absent) && state("clear", previous, is: .absent)
            && snapshots["clear"]?.publications[current] == nil
            && snapshots["clear"]?.publications[previous] == nil,
        "firstFailure": state("firstFailure", current, is: .unavailable)
            && state("firstFailure", previous, is: .absent),
        "firstRecoveryPending": state("firstRecoveryPending", current, is: .pending)
            && state("firstRecoveryPending", previous, is: .absent),
        "firstRecovery": ready("firstRecovery", current)
            && state("firstRecovery", previous, is: .absent),
        "colorOnly": ready("colorOnlySecond", current)
            && snapshots["colorOnlyFirst"]?.publications[current]?.texture
                === snapshots["colorOnlySecond"]?.publications[current]?.texture
            && snapshots["colorOnlySecond"]?.pendingIdentities.isEmpty == true,
    ]
    guard let atom = snapshots["rotated"]?.publications[previous] else {
        checks["maskPublicationExistsForIntegrityChecks"] = false
        return checks
    }
    func incomplete(_ publication: SceneTextureProviderPublication?, bare: Bool = false) -> Bool {
        let registry = SceneFrameTextureRegistry()
        registry.beginFrame(frameIndex: atom.contentGeneration, layerSources: [:],
            systemProviderStates: publication.map { [previous: .ready($0)] } ?? [:])
        if bare { registry.set(.ready(atom.texture), for: .system(previous)) }
        guard case .incomplete? = registry.lookup(.system(previous)) else { return false }
        return true
    }
    for (name, provider, generation) in [
        ("wrongCurrentLifecycle", SceneTextureProviderIdentity.mediaThumbnailCurrent, atom.contentGeneration),
        ("staleCandidate", .mediaThumbnailPrevious, atom.contentGeneration + 1),
    ] {
        let candidate = SceneTextureCandidate(texture: atom.texture, identity: .provider(provider),
            generation: .provider(contentGeneration: generation), purpose: .mask, content: .data,
            physicalSize: atom.candidate.physicalSize, mappedSize: atom.candidate.mappedSize,
            uvTransform: .identity, sampling: .linearClamp)
        checks[name] = incomplete(.init(requestIdentity: .system(previous), candidate: candidate,
            contentGeneration: atom.contentGeneration))
    }
    let wrongRequestRegistry = SceneFrameTextureRegistry()
    wrongRequestRegistry.beginFrame(frameIndex: atom.contentGeneration, layerSources: [:],
        systemProviderStates: [previous: .ready(atom.publication(for: .system(current)))])
    checks["wrongRequest"] = wrongRequestRegistry.lookup(.system(previous)) == nil
    checks["bareTexture"] = incomplete(nil, bare: true)
    let preserved = snapshots["rotated"]!.preservedPrevious!
    checks["preservedPurposeCannotMasqueradeAsMask"] = SceneTextureSlotBinding(
        slotIndex: 2, candidate: preserved.candidate)?.axisAlignedUVScale(
            expectedSlotIndex: 2, expectedPurpose: .mask,
            allowedPixelFormats: [.rgba8Unorm]) == nil
    let inbox = SceneMediaThumbnailInbox()
    let store = SceneMediaThumbnailTextureStore(device: device)
    _ = inbox.publish(png(red: 9, green: 17, blue: 25))
    store.update(from: inbox.latest())
    _ = waitFor(store, generation: 1)
    let pinned = store.prepareFrame()
    let decoded = DispatchSemaphore(value: 0)
    store.setPublicationHandler { decoded.signal() }
    _ = inbox.publish(png(red: 31, green: 47, blue: 63))
    store.update(from: inbox.latest())
    checks["replacementDecodeCompleted"] = decoded.wait(timeout: .now() + 2) == .success
    let duringPin = store.snapshot()
    checks["pinnedGenerationAndMask"] = duringPin.generation == pinned.generation
        && duringPin.publications[current]?.isSameAtom(as: pinned.publications[current]!) == true
        && duringPin.publications[previous] == nil
    store.commitPreparedFrame()
    let replaced = store.prepareFrame()
    checks["commitReleasesPinnedMask"] = replaced.generation == 2
        && pixel(replaced.publications[current]?.texture) == [31, 47, 63, 255]
        && pixel(replaced.publications[previous]?.texture) == [9, 17, 25, 255]
    inbox.clear()
    store.update(from: inbox.latest())
    checks["clearDecodeCompleted"] = decoded.wait(timeout: .now() + 2) == .success
    checks["clearCannotChangePinnedMask"] = store.snapshot().publications[current]?
        .isSameAtom(as: replaced.publications[current]!) == true
    store.discardPreparedFrame()
    let afterDiscard = store.snapshot()
    checks["discardReleasesPinnedMask"] = afterDiscard.generation == 3
        && providerStateIsAbsent(afterDiscard, current) && providerStateIsAbsent(afterDiscard, previous)
    return checks
}
