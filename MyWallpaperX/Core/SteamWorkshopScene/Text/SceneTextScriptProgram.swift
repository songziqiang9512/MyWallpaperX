import Foundation

nonisolated struct SceneTextScriptProgram: Equatable, Sendable {
    nonisolated enum Profile: String, Codable, Equatable, Sendable {
        case workshop2981960200Clock
        case workshop2981960200SpacedDay
        case workshop2981960200Date
        case workshop3732231168CompactDay
        case workshop3732231168LongMonthDate
        case workshop3732231168Clock
        case workshop3732231168Greeting
    }

    nonisolated enum Configuration: Equatable, Sendable {
        case clock(use24Hour: Bool, showSeconds: Bool, delimiter: String)
        case clockWithPeriod(
            use24Hour: Bool,
            showSeconds: Bool,
            displayDate: Bool,
            delimiter: String
        )
        case timeOfDayGreeting(
            dayText: String,
            nightText: String,
            schedule: SceneTimeOfDaySchedule
        )
        case date(
            monthFormat: Int,
            dayFormat: Int,
            showDay: Bool,
            alignVertical: Bool,
            useDelimiter: Bool,
            delimiter: String
        )
    }

    nonisolated struct Binding: Equatable, Sendable {
        let layerID: Int
        let profile: Profile
        let configuration: Configuration
        let definition: SceneDynamicTargetDefinition

        nonisolated var target: SceneDynamicTarget { definition.target }
    }

    nonisolated struct Diagnostic: Equatable, Sendable {
        enum Code: String {
            case unknownProfile
            case invalidProperties
            case missingSharedState
        }

        let layerID: Int
        let code: Code
        let sourceSHA256: String
    }

    let bindings: [Binding]
    let diagnostics: [Diagnostic]

    nonisolated static let empty = SceneTextScriptProgram(bindings: [], diagnostics: [])
}
