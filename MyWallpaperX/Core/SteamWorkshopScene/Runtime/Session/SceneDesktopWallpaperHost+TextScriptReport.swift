import Foundation

extension SceneDesktopWallpaperHost {
    nonisolated static func textScriptReportLines(
        program: SceneTextScriptProgram
    ) -> [String] {
        var lines = [
            "textScriptBindingCount: \(program.bindings.count)",
            "textScriptDiagnosticCount: \(program.diagnostics.count)",
        ]
        let fixtureDate = Date(timeIntervalSince1970: 1_785_280_025)
        let fixtureValues = SceneTextScriptRuntime.values(
            program: program,
            wallDate: fixtureDate,
            timeZone: TimeZone(secondsFromGMT: 0)!,
            mediaProperties: .init(
                title: "Fixture Media Title",
                artist: "Fixture Media Artist",
                generation: 1
            )
        )
        for binding in program.bindings.sorted(by: { $0.layerID < $1.layerID }) {
            let value: String
            if case let .string(content)? = fixtureValues[binding.target] {
                value = content
            } else {
                value = "<unavailable>"
            }
            lines.append(
                "textScript layer \(binding.layerID) content:"
                    + " profile=\(binding.profile.rawValue)"
                    + " value@fixture=\(value.debugDescription)"
            )
        }
        for diagnostic in program.diagnostics.sorted(by: { $0.layerID < $1.layerID }) {
            lines.append(
                "textScript diagnostic: layer=\(diagnostic.layerID)"
                    + " code=\(diagnostic.code.rawValue)"
                    + " sha256=\(diagnostic.sourceSHA256)"
            )
        }
        return lines
    }

    nonisolated static func appendTextScriptReport(
        to logURL: URL?,
        program: SceneTextScriptProgram
    ) {
        guard let logURL,
              let existing = try? String(contentsOf: logURL, encoding: .utf8) else {
            return
        }
        let separator = existing.isEmpty || existing.hasSuffix("\n") ? "" : "\n"
        let lines = textScriptReportLines(program: program)
        try? (existing + separator + lines.joined(separator: "\n") + "\n")
            .write(to: logURL, atomically: true, encoding: .utf8)
    }
}
