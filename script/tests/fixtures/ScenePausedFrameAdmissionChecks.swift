extension Harness {
    static func activeAdmission(_ scenario: String) {
        let owner = SceneDesktopWallpaperSession()
        let first = owner.attach(1), second = owner.attach(2)
        var simulations: [TimeInterval] = []
        owner.activeSimulationProbe = { [unowned owner] in
            simulations.append(TransportTime.now)
            return owner.renderSurfaces()
        }
        owner.startFrameDriver()
        first.metalView.submissions.blocked = true
        second.metalView.submissions.blocked = scenario != "activeAdmissionMixed"
        let scheduled = owner.frameDriverDeadline!
        precondition(RunLoop.main.fireNext())
        if scenario == "activeAdmissionMixed" {
            precondition(simulations == [100, scheduled] && second.metalView.commits == 2)
            second.metalView.submissions.blocked = true
            precondition(RunLoop.main.fireNext() && simulations.count == 2)
            _ = owner.attach(1)
            first.metalView.submissions.complete()
            precondition(simulations.count == 2)
            owner.setPlaybackPaused(true)
            second.metalView.submissions.complete()
            precondition(simulations.count == 2)
            stopped(owner)
            return
        }
        precondition(simulations == [100] && RunLoop.main.activeCount == 1)
        if scenario == "activeAdmissionWake" {
            TransportTime.now += 0.004
            second.metalView.submissions.complete()
            precondition(simulations == [100, TransportTime.now] && second.metalView.commits == 2)
            first.metalView.submissions.complete()
            precondition(simulations.count == 2 && RunLoop.main.activeCount == 1)
        } else {
            TransportTime.now = owner.frameDriverDeadline! + 0.04
            for _ in 0..<2 {
                precondition(RunLoop.main.fireNext())
                precondition(simulations == [100], "GPU admission timeout advanced simulation while every surface was blocked")
                precondition(RunLoop.main.activeCount == 1)
                precondition(abs(owner.frameDriverDeadline! - TransportTime.now - 1.0 / 60) < 0.000001)
            }
            TransportTime.now += 0.004
            first.metalView.submissions.complete()
            precondition(simulations == [100, TransportTime.now] && first.metalView.commits == 2)
            second.metalView.submissions.complete()
            precondition(simulations.count == 2 && RunLoop.main.activeCount == 1)
        }
        precondition(abs(owner.frameDriverDeadline! - TransportTime.now - 1.0 / 60) < 0.000001)
        owner.setPlaybackPaused(true)
        stopped(owner)
    }
    static func rasterSamples() {
        var status = SceneDesktopWallpaperSession.SurfaceQualityStatus()
        let initial = status.observe(4)!
        precondition(status.complete(initial, succeeded: true) && status.observe(4) == nil)
        let compositionFallback = status.observe(1)!
        let abandonedPreparation = status.observe(1, didFailPreparation: true)!
        precondition(status.complete(compositionFallback, succeeded: true))
        precondition(!status.complete(abandonedPreparation, succeeded: false))
        precondition(status.completed?.samples == 1 && status.completed?.didFailPreparation == false)

        let preparationFallback = status.observe(1, didFailPreparation: true)!
        let earlierView = status.observe(1)!
        let newer = status.observe(1, didFailPreparation: true)!
        precondition(status.complete(newer, succeeded: true))
        precondition(!status.complete(earlierView, succeeded: true))
        precondition(!status.complete(preparationFallback, succeeded: true))
        precondition(status.completed?.samples == 1 && status.completed?.didFailPreparation == true)
        precondition(status.observe(1, didFailPreparation: true) == nil)

        let success = status.observe(4, didFailPreparation: true)!
        precondition(status.complete(success, succeeded: true))
        precondition(status.completed?.samples == 4 && status.completed?.didFailPreparation == false)
        precondition(status.observe(4) == nil)

        let texture = SceneTextureUseSample(revision: 0, bindings: .init(reduced:
            .init(width: 1024, height: 512, baseMip: 1, mipCount: 2, reason: .authoredMip)))
        let observedTexture = status.observe(4, textures: texture)!
        let unrelatedChange = status.observe(1)!
        precondition(status.complete(observedTexture, succeeded: true))
        precondition(status.complete(unrelatedChange, succeeded: true))
        precondition(status.completed?.textures == texture && status.observe(1) == nil)
        let noBinding = SceneTextureUseSample(revision: 1)
        let failedObservation = status.observe(1, textures: noBinding)!
        precondition(!status.complete(failedObservation, succeeded: false) && status.completed?.textures == texture)
        let retry = status.observe(1, textures: noBinding)!
        precondition(status.complete(retry, succeeded: true) && status.completed?.textures == noBinding)

        let owner = SceneDesktopWallpaperSession()
        let surface = owner.attach()
        var changes = 0
        owner.onDisplayQualityChanged = { changes += 1 }
        let view = surface.metalView
        let shadow: SceneShadowUse = .active([.init(family: .point, face: 1024, limit: .lightFamily)])
        view.renderQuality = (4, shadow)
        view.renderTextureUse = .init(revision: 0)
        view.hasPreparedOrdinaryTexture = true
        _ = owner.renderSurfaces()
        precondition(view.requestedTextureUseRevisions == [0])
        precondition(changes == 0 && surface.qualityStatus.completed == nil)
        complete(view, 0, true)
        precondition(changes == 1 && surface.qualityStatus.completed?.textures?.bindings == .init())

        // A prepared image can become visible without replacing its texture. An
        // original binding in the earlier frame must not hide the later smaller one.
        let retained = SceneTextureUseSample(revision: 0, bindings: .init(retained:
            .init(width: 2048, height: 1024, baseMip: 0, mipCount: 3, reason: .preservedPixels)))
        view.renderTextureUse = retained
        view.hasPreparedSmallerTexture = true
        _ = owner.renderSurfaces()
        complete(view, 1, true)
        precondition(changes == 2 && surface.qualityStatus.completed?.textures == retained)
        view.renderTextureUse = texture
        _ = owner.renderSurfaces()
        precondition(view.requestedTextureUseRevisions == [0, 0, 0])
        complete(view, 2, true)
        precondition(changes == 3 && surface.qualityStatus.completed?.textures == texture)

        // Retained color has no new quality observations.
        view.renderQuality = (nil, nil)
        view.renderTextureUse = nil
        _ = owner.renderSurfaces()
        precondition(view.requestedTextureUseRevisions == [0, 0, 0, nil])
        view.ordinaryTextureRevision = 1
        complete(view, 3, true)
        precondition(changes == 3 && surface.qualityStatus.completed?.shadow == shadow)

        view.renderQuality = (4, .noReceiver)
        _ = owner.renderSurfaces()
        precondition(view.requestedTextureUseRevisions.last == 1)
        complete(view, 4, false)
        precondition(changes == 3 && surface.qualityStatus.completed?.shadow == shadow)
        _ = owner.renderSurfaces()
        let replacement = owner.attach()
        complete(view, 5, true)
        precondition(changes == 3 && replacement.qualityStatus.completed == nil)

        owner.shadowsDisabled = true
        replacement.metalView.renderQuality = (1, .noReceiver)
        _ = owner.renderSurfaces()
        complete(replacement.metalView, 0, true)
        precondition(changes == 4 && replacement.qualityStatus.completed?.shadow == .disabled)
    }
}
