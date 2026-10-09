import Foundation

extension SteamWorkshopService {
    static let webStaticAnalysisMaximumFileBytes = 128 * 1024

    nonisolated static func webStaticAnalysisContent(from fileURL: URL) -> (content: String, isTruncated: Bool)? {
        guard let handle = try? FileHandle(forReadingFrom: fileURL) else { return nil }
        defer { try? handle.close() }

        guard let fileSize = try? handle.seekToEnd(),
              (try? handle.seek(toOffset: 0)) != nil else {
            return nil
        }

        let maximumBytes = webStaticAnalysisMaximumFileBytes
        if fileSize <= UInt64(maximumBytes) {
            guard let data = try? handle.readToEnd(),
                  let content = String(data: data, encoding: .utf8) else {
                return nil
            }
            return (content, false)
        }

        let segmentBytes = maximumBytes / 2
        guard let prefix = try? handle.read(upToCount: segmentBytes),
              (try? handle.seek(toOffset: fileSize - UInt64(segmentBytes))) != nil,
              let suffix = try? handle.read(upToCount: segmentBytes) else {
            return nil
        }
        let content = String(decoding: prefix, as: UTF8.self)
            + "\n/* static analysis truncated */\n"
            + String(decoding: suffix, as: UTF8.self)
        return (content, true)
    }

    nonisolated static func webFileContainsServiceWorkerRegistration(_ fileURL: URL) -> Bool {
        WebStaticFileSignalScanner.containsServiceWorkerRegistration(in: fileURL)
    }

    nonisolated static func webContentUsesWebMResource(_ content: String) -> Bool {
        let lowered = content.lowercased()
        return lowered.contains(".webm")
            || lowered.contains("video/webm")
    }

    nonisolated static func webContentUsesHoverOnlyInteraction(_ content: String) -> Bool {
        let lowered = content.lowercased()
        guard lowered.contains(":hover") else { return false }
        let pointerMarkers = [
            "mousemove", "mousedown", "mouseup",
            "pointermove", "pointerdown", "pointerup",
            "mouseenter", "mouseleave", "mouseover", "mouseout"
        ]
        return !pointerMarkers.contains { lowered.contains($0) }
    }

    nonisolated static func webContentUsesApplyGeneralProperties(_ content: String) -> Bool {
        let lowered = content.lowercased()
        return lowered.contains("applygeneralproperties")
    }

    nonisolated static func webContentUsesGeneralFPS(_ content: String) -> Bool {
        let lowered = content.lowercased()
        return lowered.contains("properties.fps") || lowered.contains("fps:")
    }

    nonisolated static func webContentReferencesSchemeColorUserProperty(_ content: String) -> Bool {
        let lowered = content.lowercased()
        let patterns = [
            #"\.\s*schemecolor\b"#,
            #"\[\s*['"]schemecolor['"]\s*\]"#
        ]
        return patterns.contains { pattern in
            guard let expression = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
                return true
            }
            let range = NSRange(lowered.startIndex..<lowered.endIndex, in: lowered)
            return expression.firstMatch(in: lowered, options: [], range: range) != nil
        }
    }

    nonisolated static func webContentHasUncertainUserPropertyUsage(_ content: String) -> Bool {
        let lowered = content.lowercased()
        guard lowered.contains("applyuserproperties") else {
            return false
        }
        if lowered.contains("object.keys(properties)")
            || lowered.contains("object.values(properties)")
            || lowered.contains("object.entries(properties)") {
            return true
        }

        let patterns = [
            #"\bproperties\s*\[\s*(?!['\"])"#,
            #"\bfor\s*\([^)]*\bin\s*properties\b"#,
            #"\bfor\s*\([^)]*\bof\s*(?:object\.(?:keys|values|entries)\s*\(\s*)?properties\b"#
        ]
        return patterns.contains { pattern in
            guard let expression = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
                return true
            }
            let range = NSRange(lowered.startIndex..<lowered.endIndex, in: lowered)
            return expression.firstMatch(in: lowered, options: [], range: range) != nil
        }
    }

    nonisolated static func webDisplayConditionRequiresFallback(_ condition: String?) -> Bool {
        guard let condition,
              condition.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            return false
        }
        let trimmed = condition.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.contains("?")
            || Self.webDisplayConditionUsesOnlySupportedOperators(trimmed) == false
            || Self.canTokenizeWebDisplayCondition(trimmed) == false
    }

    nonisolated static func webContentUsesPluginBridge(_ content: String) -> Bool {
        let lowered = content.lowercased()
        return lowered.contains("wallpaperpluginlistener")
            || lowered.contains("onpluginloaded")
            || lowered.contains("wpplugins")
    }

    nonisolated static func webContentUsesPersistentBrowserStorage(_ content: String) -> Bool {
        let lowered = content.lowercased()
        return lowered.contains("localstorage")
            || lowered.contains("indexeddb")
            || lowered.contains("sessionstorage")
    }

    nonisolated static func webContentUsesServiceWorkerRegistration(_ content: String) -> Bool {
        let lowered = content.lowercased()
        return lowered.contains("serviceworker.register")
            || lowered.contains("navigator.serviceworker")
    }

    nonisolated static func webContentUsesESModuleDependency(_ content: String) -> Bool {
        let lowered = content.lowercased()
        return lowered.contains("type=\"module\"")
            || lowered.contains("type='module'")
            || lowered.contains(".mjs")
    }

    nonisolated static func webContentUsesDynamicImport(_ content: String) -> Bool {
        let lowered = content.lowercased()
        return lowered.contains("import(")
    }

    nonisolated static func webContentUsesWASMResource(_ content: String) -> Bool {
        let lowered = content.lowercased()
        return lowered.contains(".wasm")
            || lowered.contains("application/wasm")
            || lowered.contains("webassembly.")
    }

    nonisolated static func webContentUsesWASMStreaming(_ content: String) -> Bool {
        let lowered = content.lowercased()
        return lowered.contains("webassembly.instantiatestreaming")
            || lowered.contains("webassembly.compilestreaming")
    }

    nonisolated static func webContentUsesCustomSchemeSensitiveWebGL(_ content: String) -> Bool {
        let lowered = content.lowercased()
        let usesWebGLContext = lowered.contains("getcontext(\"webgl")
            || lowered.contains("getcontext('webgl")
            || lowered.contains("webgl2renderingcontext")
        let uploadsExternalTexture = lowered.contains("teximage2d")
            || lowered.contains("createimagebitmap")
            || lowered.contains("texture.from(")
        return (usesWebGLContext && uploadsExternalTexture)
            || lowered.contains("pixi.")
            || lowered.contains("pixi.min.js")
            || lowered.contains("pixi-live2d")
            || lowered.contains("live2d")
            || lowered.contains("texture.from(")
            || lowered.contains("canvas.todataurl")
            || lowered.contains("readpixels(")
    }

    nonisolated static func webContentUsesIframeCrossFrameAccess(_ content: String) -> Bool {
        let lowered = content.lowercased()
        let hasIframe = lowered.contains("<iframe")
            || lowered.contains("createelement('iframe")
            || lowered.contains("createelement(\"iframe")
            || lowered.contains("createelement(`iframe")
        guard hasIframe else { return false }

        return lowered.contains("contentdocument")
            || lowered.contains("contentwindow.document")
            || lowered.contains("window.frames[")
            || lowered.contains("frames[")
    }
}
