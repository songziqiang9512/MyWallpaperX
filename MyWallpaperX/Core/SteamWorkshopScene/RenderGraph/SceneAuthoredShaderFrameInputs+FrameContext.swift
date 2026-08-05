import Foundation

extension SceneAuthoredShaderFrameInputs {
    init(frameContext: SceneFrameContext) {
        let components = Calendar.current.dateComponents(
            [.hour, .minute, .second, .nanosecond],
            from: frameContext.wallDate
        )
        let elapsedSeconds = Double((components.hour ?? 0) * 3_600)
            + Double((components.minute ?? 0) * 60)
            + Double(components.second ?? 0)
            + Double(components.nanosecond ?? 0) / 1_000_000_000
        frameIndex = frameContext.frameIndex
        screenSize = frameContext.screenSize
        sceneTime = Float(frameContext.sceneTime)
        dayTime = Float(elapsedSeconds / 86_400)
        frameTime = Float(frameContext.frameTime)
        pointerCurrentNDC = frameContext.pointerCurrent
        pointerPreviousNDC = frameContext.pointerPrevious
        let spectrum = frameContext.audioSpectrum
        audioSpectrum = .init(
            left16: spectrum.left,
            right16: spectrum.right,
            left32: spectrum.left32,
            right32: spectrum.right32,
            left64: spectrum.left64,
            right64: spectrum.right64
        )
    }
}
