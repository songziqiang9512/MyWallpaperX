import Foundation

nonisolated enum SceneTextScriptRuntime {
    nonisolated static func values(
        program: SceneTextScriptProgram,
        wallDate: Date,
        timeZone: TimeZone = .autoupdatingCurrent
    ) -> [SceneDynamicTarget: SceneDynamicValue] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let components = calendar.dateComponents(
            [.year, .month, .day, .weekday, .hour, .minute, .second],
            from: wallDate
        )
        return program.bindings.reduce(into: [:]) { values, binding in
            guard let content = content(binding: binding, components: components) else { return }
            values[binding.target] = .string(content)
        }
    }

    private nonisolated static func content(
        binding: SceneTextScriptProgram.Binding,
        components: DateComponents
    ) -> String? {
        switch binding.configuration {
        case let .clock(use24Hour, showSeconds, delimiter):
            guard var hour = components.hour,
                  let minute = components.minute,
                  let second = components.second else {
                return nil
            }
            if !use24Hour {
                hour %= 12
                if hour == 0 { hour = 12 }
            }
            var value = "-\(twoDigits(hour))\(delimiter)\(twoDigits(minute))-"
            if showSeconds {
                value += "\(delimiter)\(twoDigits(second))"
            }
            return value
        case let .date(
            monthFormat,
            dayFormat,
            showDay,
            alignVertical,
            useDelimiter,
            delimiter
        ):
            return dateContent(
                profile: binding.profile,
                components: components,
                monthFormat: monthFormat,
                dayFormat: dayFormat,
                showDay: showDay,
                alignVertical: alignVertical,
                delimiter: useDelimiter ? delimiter : " "
            )
        }
    }

    private nonisolated static func dateContent(
        profile: SceneTextScriptProgram.Profile,
        components: DateComponents,
        monthFormat: Int,
        dayFormat: Int,
        showDay: Bool,
        alignVertical: Bool,
        delimiter: String
    ) -> String? {
        guard let year = components.year,
              let month = components.month,
              let dayOfMonth = components.day,
              let weekday = components.weekday,
              (1...12).contains(month),
              (1...7).contains(weekday) else {
            return nil
        }
        switch profile {
        case .workshop2981960200Clock:
            return nil
        case .workshop2981960200SpacedDay:
            if showDay {
                let days = dayFormat == 1
                    ? ["S U N", "M O N", "T U E", "W E D", "T H U", "F R I", "S A T"]
                    : [
                        "S U N D A Y", "M O N D A Y", "T U E S D A Y",
                        "W E D N E S D A Y", "T H U R S D A Y",
                        "F R I D A Y", "S A T U R D A Y",
                    ]
                return days[weekday - 1]
            }
            let monthName = monthName(
                month, format: monthFormat, paddedAbbreviation: false
            )
            return "\(dayOfMonth)\(delimiter)\(monthName)\(delimiter)\(year)"
        case .workshop2981960200Date:
            let monthName = monthName(
                month, format: monthFormat, paddedAbbreviation: true
            )
            let date = "\(dayOfMonth)\(delimiter)\(monthName)\(delimiter)\(year)"
            guard showDay else { return date }
            let abbreviatedDays = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "\nSat"]
            let fullDays = [
                "Sunday", "Monday", "Tuesday", "Wednesday",
                "Thursday", "Friday", "\nSaturday",
            ]
            let dayName = (dayFormat == 1 ? abbreviatedDays : fullDays)[weekday - 1]
            return dayName + (alignVertical ? "\n" : "") + " " + date
        }
    }

    private nonisolated static func monthName(
        _ month: Int,
        format: Int,
        paddedAbbreviation: Bool
    ) -> String {
        switch format {
        case 1:
            return String(month)
        case 2:
            let months = [
                "JAN", "FEB", "MAR", "APR", "MAY", "JUN",
                "JUL", "AUG", "SEP", "OCT", "NOV", "DEC",
            ]
            let value = months[month - 1]
            return paddedAbbreviation ? " \(value) " : value
        default:
            return [
                "January", "February", "March", "April", "May", "June",
                "July", "August", "September", "October", "November", "December",
            ][month - 1]
        }
    }

    private nonisolated static func twoDigits(_ value: Int) -> String {
        String(format: "%02d", value)
    }
}
