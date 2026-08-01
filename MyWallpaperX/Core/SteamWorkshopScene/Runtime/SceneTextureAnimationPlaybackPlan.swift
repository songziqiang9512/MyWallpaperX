import Foundation

nonisolated struct SceneTimeOfDaySchedule: Equatable, Sendable {
    nonisolated enum State: Equatable, Sendable {
        case day
        case night
    }

    let dayStartHour: Int
    let nightStartHour: Int

    nonisolated func state(
        at wallDate: Date,
        timeZone: TimeZone = .autoupdatingCurrent
    ) -> State? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let components = calendar.dateComponents(
            [.hour, .minute, .second, .nanosecond],
            from: wallDate
        )
        guard let hour = components.hour,
              let minute = components.minute,
              let second = components.second else {
            return nil
        }
        let hourOfDay = Double(hour)
            + Double(minute) / 60
            + Double(second) / 3_600
            + Double(components.nanosecond ?? 0) / 3_600_000_000_000
        return hourOfDay >= Double(dayStartHour)
            && hourOfDay < Double(nightStartHour) ? .day : .night
    }
}

/// Strict native plan for a verified texture-animation SceneScript profile.
nonisolated struct SceneTextureAnimationPlaybackPlan: Equatable, Sendable {
    nonisolated enum Mode: Equatable, Sendable {
        case delayedLoop(initialDelay: Float, minimumDelay: Float, maximumDelay: Float)
        case timeOfDay(SceneTimeOfDaySchedule)
    }

    let layerID: Int
    let sourceSHA256: String
    let mode: Mode
}
