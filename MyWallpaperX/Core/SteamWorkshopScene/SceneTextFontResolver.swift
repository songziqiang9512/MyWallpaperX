import CoreText
import Foundation

nonisolated enum SceneTextFontResolver {
    struct Resolution {
        let font: CTFont
        let source: String
        let diagnostic: String?
        let requestedPath: String?
        let postScriptName: String

        var summary: String {
            var value = "font=\(postScriptName) source=\(source)"
            if let requestedPath {
                value += " requested=\(requestedPath)"
            }
            if let diagnostic {
                value += " diagnostic=\(diagnostic)"
            }
            return value
        }
    }

    private struct SystemAlias {
        let family: String
        let fallbackFamily: String
    }

    private static let aliases: [String: SystemAlias] = [
        "systemfont_arial": SystemAlias(family: "Arial", fallbackFamily: "Helvetica"),
        "systemfont_cambria": SystemAlias(family: "Cambria", fallbackFamily: "Times New Roman"),
        "systemfont_comicsans": SystemAlias(family: "Comic Sans MS", fallbackFamily: "Helvetica"),
        "systemfont_verdana": SystemAlias(family: "Verdana", fallbackFamily: "Helvetica")
    ]
    private static let installedFontFamilies: Set<String> = {
        let names = CTFontManagerCopyAvailableFontFamilyNames() as? [String] ?? []
        return Set(names.map { $0.lowercased() })
    }()

    nonisolated static func resolve(
        path: String?,
        size: CGFloat,
        cacheDirectory: URL
    ) -> Resolution {
        let clampedSize = max(1, size)
        guard let path, !path.isEmpty else {
            return fallback(
                size: clampedSize,
                requestedPath: nil,
                diagnostic: nil
            )
        }

        let normalizedPath = path.replacingOccurrences(of: "\\", with: "/")
        let basename = ((normalizedPath as NSString).lastPathComponent as NSString)
            .deletingPathExtension
            .lowercased()
        if basename.hasPrefix("systemfont_") {
            return resolveSystemAlias(
                basename,
                requestedPath: path,
                size: clampedSize
            )
        }

        guard let fontURL = bundledFontURL(path: normalizedPath, cacheDirectory: cacheDirectory) else {
            return fallback(
                size: clampedSize,
                requestedPath: path,
                diagnostic: "unsafeFontPath"
            )
        }
        guard FileManager.default.fileExists(atPath: fontURL.path) else {
            return fallback(
                size: clampedSize,
                requestedPath: path,
                diagnostic: "missingBundledFont"
            )
        }
        guard let data = try? Data(contentsOf: fontURL),
              let provider = CGDataProvider(data: data as CFData),
              let graphicsFont = CGFont(provider) else {
            return fallback(
                size: clampedSize,
                requestedPath: path,
                diagnostic: "invalidBundledFont"
            )
        }
        let font = CTFontCreateWithGraphicsFont(graphicsFont, clampedSize, nil, nil)
        return resolution(
            font: font,
            source: "embedded",
            diagnostic: nil,
            requestedPath: path
        )
    }

    nonisolated private static func resolveSystemAlias(
        _ aliasName: String,
        requestedPath: String,
        size: CGFloat
    ) -> Resolution {
        guard let alias = aliases[aliasName] else {
            return fallback(
                size: size,
                requestedPath: requestedPath,
                diagnostic: "systemAliasUnavailable"
            )
        }
        if isInstalledFontFamily(alias.family) {
            let font = CTFontCreateWithName(alias.family as CFString, size, nil)
            return resolution(
                font: font,
                source: "systemAlias",
                diagnostic: nil,
                requestedPath: requestedPath
            )
        }
        let fallbackFamily = isInstalledFontFamily(alias.fallbackFamily)
            ? alias.fallbackFamily
            : "Helvetica"
        let font = CTFontCreateWithName(fallbackFamily as CFString, size, nil)
        return resolution(
            font: font,
            source: "fallback",
            diagnostic: "systemAliasUnavailable",
            requestedPath: requestedPath
        )
    }

    nonisolated private static func fallback(
        size: CGFloat,
        requestedPath: String?,
        diagnostic: String?
    ) -> Resolution {
        let font = CTFontCreateWithName("Helvetica" as CFString, size, nil)
        return resolution(
            font: font,
            source: requestedPath == nil ? "default" : "fallback",
            diagnostic: diagnostic,
            requestedPath: requestedPath
        )
    }

    nonisolated private static func resolution(
        font: CTFont,
        source: String,
        diagnostic: String?,
        requestedPath: String?
    ) -> Resolution {
        Resolution(
            font: font,
            source: source,
            diagnostic: diagnostic,
            requestedPath: requestedPath,
            postScriptName: CTFontCopyPostScriptName(font) as String
        )
    }

    nonisolated private static func bundledFontURL(path: String, cacheDirectory: URL) -> URL? {
        guard !path.hasPrefix("/") else { return nil }
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        guard !components.contains(".."), !components.contains("") else { return nil }
        let root = cacheDirectory.standardizedFileURL.resolvingSymlinksInPath()
        let candidate = root.appendingPathComponent(path)
            .standardizedFileURL
            .resolvingSymlinksInPath()
        guard candidate.path.hasPrefix(root.path + "/") else { return nil }
        return candidate
    }

    nonisolated private static func isInstalledFontFamily(_ name: String) -> Bool {
        installedFontFamilies.contains(name.lowercased())
    }
}
