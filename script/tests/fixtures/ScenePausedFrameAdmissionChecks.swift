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
        var status = SceneDesktopWallpaperSession.RasterSampleStatus()
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
    }
}
