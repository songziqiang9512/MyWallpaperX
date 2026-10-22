import Foundation

extension SceneDesktopWallpaperSession {
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
#if DEBUG
    func logDebugDynamicLayerVisibilityIfChanged(
        descriptor: SceneRenderDescriptor,
        snapshot: SceneDynamicSnapshot,
        destroyedAuthoredLayerIDs: Set<Int>
    ) {
        guard SceneDesktopWallpaperHost.usesDebugEvidenceWindow else { return }
        let visibleLayerIDs = SceneLayerVisibility.visibleLayerIDs(
            in: descriptor,
            snapshot: snapshot
        ).subtracting(destroyedAuthoredLayerIDs)
        let records = descriptor.layers.compactMap { layer -> String? in
            let resolved = snapshot[.layer(layerID: layer.id, field: .visibility)]
            let value: Bool
            if let resolved, case let .bool(current) = resolved.value {
                value = current
            } else {
                value = layer.visible ?? true
            }
            return "layer=\(layer.id) source=\(resolved?.source.rawValue ?? "authored")"
                + " value=\(value)"
                + " effective=\(visibleLayerIDs.contains(layer.id))"
        }
        let signature = records.joined(separator: "|")
        guard signature != debugDynamicLayerVisibilitySignature else { return }
        debugDynamicLayerVisibilitySignature = signature
        for record in records {
            NSLog(
                "MWX dynamic layer visibility: schema=dynamic-layer-visibility-v1 frame=%llu generation=%llu %@",
                snapshot.frameIndex,
                snapshot.generation,
                record
            )
        }
    }
#endif
}
