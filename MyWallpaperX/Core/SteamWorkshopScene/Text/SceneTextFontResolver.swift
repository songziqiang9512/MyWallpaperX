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

    /// 官方客户端自带字体的形态类别。作者写 `fonts/X` 时官方先找包内文件，找不到再用
    /// 客户端 `assets/fonts` 里的 stock 字体；本项目不搬运官方字体文件，只保留名字与
    /// 类别，并用最接近的本机家族近似。
    private enum StockCategory: String {
        case display
        case emoji
        case mono
        case sans

        var approximationFamily: String {
            switch self {
            case .display: "Helvetica"
            case .emoji: "Apple Color Emoji"
            case .mono: "Menlo"
            case .sans: "Noto Sans"
            }
        }
    }

    /// 官方 `systemfont_*` 别名共 8 个（安装目录内各出现 6~8 次）。Windows 家族在 macOS
    /// 缺失时退到形态最接近的本机家族：`consolas` 必须退到等宽家族，否则语料里引用最多的
    /// 别名会从等宽退化成比例字体；`sansserif` 是通用 sans 请求，macOS 的通用 sans 即
    /// Helvetica，因此算别名命中而不是 fallback。
    private static let aliases: [String: SystemAlias] = [
        "systemfont_arial": SystemAlias(family: "Arial", fallbackFamily: "Helvetica"),
        "systemfont_calibri": SystemAlias(family: "Calibri", fallbackFamily: "Helvetica"),
        "systemfont_cambria": SystemAlias(family: "Cambria", fallbackFamily: "Times New Roman"),
        "systemfont_comicsans": SystemAlias(family: "Comic Sans MS", fallbackFamily: "Helvetica"),
        "systemfont_consolas": SystemAlias(family: "Consolas", fallbackFamily: "Menlo"),
        "systemfont_sansserif": SystemAlias(family: "Helvetica", fallbackFamily: "Helvetica"),
        "systemfont_segoe": SystemAlias(family: "Segoe UI", fallbackFamily: "Helvetica"),
        "systemfont_verdana": SystemAlias(family: "Verdana", fallbackFamily: "Helvetica")
    ]
    /// 官方客户端 `assets/fonts` 下的 15 个 stock 字体（另有 4 个 license `.txt`）。
    /// 类别由本机对安装目录的只读 CoreText 实测得出，不是按字体名猜：emoji 看 color 位与
    /// COLR/sbix/CBDT 表，mono 看 fixed-pitch trait 或数字与字母 advance 是否一致，
    /// 其余比例字体按有无常规西文正文形态分成 sans / display。
    private static let stockFonts: [String: StockCategory] = [
        "8bitoperatorplus8-regular": .display,
        "alcubierre": .display,
        "atami-regular": .display,
        "blackout 2 am": .display,
        "cursedtimerulil-aznm": .mono,
        "kust": .display,
        "lazer84": .display,
        "monofur-pk7og": .mono,
        "notosans-regular": .sans,
        "opensticks": .mono,
        "robotomono-regular": .mono,
        "segment7standard": .mono,
        "spincycle_3d_ot": .display,
        "summer85": .display,
        "twemojimozilla": .emoji
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
            // 包内没有这个文件时才认 stock：`fonts/X` 的官方语义是先包内、后客户端自带。
            if let category = stockFonts[basename] {
                return resolveStockFont(
                    category,
                    requestedPath: path,
                    size: clampedSize
                )
            }
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
            // 官方只定义 8 个别名；表外的名字与“认识但本机缺字体”是两种不同的运维动作，
            // 诊断必须可区分，否则补全别名表这件事在报告里不可观察。
            return fallback(
                size: size,
                requestedPath: requestedPath,
                diagnostic: "systemAliasUnknown"
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

    nonisolated private static func resolveStockFont(
        _ category: StockCategory,
        requestedPath: String,
        size: CGFloat
    ) -> Resolution {
        let preferred = category.approximationFamily
        let family = isInstalledFontFamily(preferred) ? preferred : "Helvetica"
        let font = CTFontCreateWithName(family as CFString, size, nil)
        return resolution(
            font: font,
            source: "stockApproximation",
            diagnostic: "stockFontApproximated:\(category.rawValue)",
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
