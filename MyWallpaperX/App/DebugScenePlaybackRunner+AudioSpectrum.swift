#if DEBUG
import Foundation

extension DebugScenePlaybackRunner {
    static func scheduleRequestedAudioSpectrumFixture() {
        guard ProcessInfo.processInfo.arguments.contains(
            "--mwx-debug-scene-audio-spectrum-fixture"
        ) else { return }
        scheduleAudioSpectrumFixtureFrame(0)
    }

    private static func scheduleAudioSpectrumFixtureFrame(_ frame: Int) {
        let elapsed = Double(frame) * 0.25
        guard elapsed < requestedDuration - 0.25 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + (frame == 0 ? 0 : 0.25)) {
            let loud = frame.isMultiple(of: 2)
            let leftValue: Float = loud ? 1 : 0.1
            let rightValue: Float = loud ? 0.5 : 0.2
            SceneAudioSpectrumInbox.shared.publish(
                left: Array(repeating: leftValue, count: 16),
                right: Array(repeating: rightValue, count: 16)
            )
            NSLog(
                "MWX DEBUG SCENE AUDIO: frame=%d left=%.3f right=%.3f",
                frame,
                leftValue,
                rightValue
            )
            scheduleAudioSpectrumFixtureFrame(frame + 1)
        }
    }
}
#endif
