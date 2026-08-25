import Foundation

extension SceneDesktopWallpaperHost {
#if DEBUG
    static let debugWallDateOverride: Date? = {
        guard usesDebugEvidenceWindow,
              let rawValue = ProcessInfo.processInfo.environment[
                "MYWALLPAPERX_SCENE_DEBUG_WALL_DATE"
              ] else { return nil }
        return ISO8601DateFormatter().date(from: rawValue)
    }()
#endif

    static func appendTimeOfDayEffectScriptReport(
        to logURL: URL?,
        program: SceneTimeOfDayEffectScriptProgram,
        admissionDiagnostic: String?
    ) {
        guard let logURL else { return }
        var lines = [
            "timeOfDayEffectScriptBindingCount: \(program.bindings.count)",
            admissionDiagnostic.map {
                "timeOfDayEffectScriptAdmission: status=budget-rejected reason=\($0)"
            } ?? "timeOfDayEffectScriptAdmission: status=admitted reason=none",
        ]
#if DEBUG
        if let wallDate = debugWallDateOverride {
            lines.append(
                "timeOfDayEffectScriptDebugWallDate: "
                    + ISO8601DateFormatter().string(from: wallDate)
            )
        }
#endif
        for binding in program.bindings {
            guard case let .effectConstant(layerID, effectIndex, passIndex, name) =
                    binding.definition.target else { continue }
            lines.append(
                "time-of-day effect script: layer=\(layerID) effect=\(effectIndex) "
                    + "pass=\(passIndex) constant=\(name)"
            )
        }
        guard let handle = try? FileHandle(forWritingTo: logURL) else { return }
        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        let payload = "\n" + lines.joined(separator: "\n") + "\n"
        try? handle.write(contentsOf: Data(payload.utf8))
    }
}
