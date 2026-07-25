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

    /// 官方客户端自带字体的形态类别。作者写 `fonts/X` 时官方先找壁纸包内文件，找不到再用
    /// 客户端 `assets/fonts` 里的 stock 字体；本项目在 app bundle 内随包同名字体，缺字体
    /// 文件时才退到最接近的本机家族近似。
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
    /// stock 字体的字形来源。官方客户端有权随自己分发全部 15 个字体，这个权利不传递给
    /// MyWallpaperX，所以只有许可允许再分发的才搬原版文件，其余换成外形接近的自由字体。
    private enum StockGlyphSource {
        /// 官方原版字体文件，许可允许随 MyWallpaperX 再分发。
        case original(String)
        /// 原版禁止再分发，改用外形接近、许可明确的替代字体。
        case substitute(String)
    }

    private struct StockFont {
        let category: StockCategory
        let glyphs: StockGlyphSource
    }

    /// 官方客户端 `assets/fonts` 下的 15 个 stock 字体（另有 4 个 license `.txt`）。
    /// 类别由本机对安装目录的只读 CoreText 实测得出，不是按字体名猜：emoji 看 color 位与
    /// COLR/sbix/CBDT 表，mono 看 fixed-pitch trait 或数字与字母 advance 是否一致，
    /// 其余比例字体按有无常规西文正文形态分成 sans / display。替代字体是逐个渲染
    /// "Hamburg 0123" 与原版并排比对后选的，不是按名字或类别硬凑。键是作者路径的小写
    /// basename，括号里是 `SceneStockFonts.bundle/Fonts` 内的真实文件名。
    private static let stockFonts: [String: StockFont] = [
        "8bitoperatorplus8-regular": StockFont(
            category: .display,
            glyphs: .original("8bitOperatorPlus8-Regular.ttf")
        ),
        // 极细几何无衬线，Poppins ExtraLight 的单层 a、圆形 O 和线宽最接近。
        "alcubierre": StockFont(
            category: .display,
            glyphs: .substitute("Poppins-ExtraLight.ttf")
        ),
        // 语料里引用最多的 stock 字体（17 个去重 layer）。作者 EULA 明确禁止再分发，
        // 换成同为几何无衬线、字重与比例吻合的 Poppins Medium。
        "atami-regular": StockFont(
            category: .display,
            glyphs: .substitute("Poppins-Medium.ttf")
        ),
        // 内嵌 copyright 写 All rights reserved，但 The League of Moveable Type 以 OFL
        // 发布同一份文件（SHA-256 与官方客户端那份逐字节相同），因此是原版而不是替代。
        "blackout 2 am": StockFont(
            category: .display,
            glyphs: .original("Blackout 2 AM.ttf")
        ),
        // 同为七段数码管字体，直接复用已随包的 Segment7Standard。
        "cursedtimerulil-aznm": StockFont(
            category: .mono,
            glyphs: .substitute("Segment7Standard.otf")
        ),
        // 粗糙手绘大写，Bangers 是同类粗大写 display。
        "kust": StockFont(category: .display, glyphs: .substitute("Bangers-Regular.ttf")),
        // 80 年代粗斜笔刷，与 summer85 同属马克笔 display，共用 Permanent Marker。
        "lazer84": StockFont(
            category: .display,
            glyphs: .substitute("PermanentMarker-Regular.ttf")
        ),
        "monofur-pk7og": StockFont(
            category: .mono,
            glyphs: .original("Monofur-PK7og.ttf")
        ),
        "notosans-regular": StockFont(
            category: .sans,
            glyphs: .original("NotoSans-Regular.ttf")
        ),
        "opensticks": StockFont(category: .mono, glyphs: .original("opensticks.ttf")),
        "robotomono-regular": StockFont(
            category: .mono,
            glyphs: .original("RobotoMono-Regular.ttf")
        ),
        "segment7standard": StockFont(
            category: .mono,
            glyphs: .original("Segment7Standard.otf")
        ),
        // 立体描边字，Bungee Shade 的宽扁大写加阴影轮廓最接近。
        "spincycle_3d_ot": StockFont(
            category: .display,
            glyphs: .substitute("BungeeShade-Regular.ttf")
        ),
        "summer85": StockFont(
            category: .display,
            glyphs: .substitute("PermanentMarker-Regular.ttf")
        ),
        "twemojimozilla": StockFont(
            category: .emoji,
            glyphs: .original("TwemojiMozilla.ttf")
        )
    ]
    /// 随 app 分发的 stock 字体目录。命令行门禁没有 app bundle，此时 `resourceURL` 就是
    /// 可执行文件所在目录，把同名 bundle 放在 binary 旁边即可命中同一条真实加载路径。
    private static let stockFontsDirectory: URL? = Bundle.main.resourceURL?
        .appendingPathComponent("SceneStockFonts.bundle/Fonts", isDirectory: true)
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
            // 壁纸包内没有这个文件时才认 stock：`fonts/X` 的官方语义是先包内、后客户端自带。
            if let stock = stockFonts[basename] {
                return resolveStockFont(
                    stock,
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
        _ stock: StockFont,
        requestedPath: String,
        size: CGFloat
    ) -> Resolution {
        switch stock.glyphs {
        case let .original(fileName):
            if let font = stockFont(fileName: fileName, size: size) {
                return resolution(
                    font: font,
                    source: "stockBundled",
                    diagnostic: nil,
                    requestedPath: requestedPath
                )
            }
        case let .substitute(fileName):
            if let font = stockFont(fileName: fileName, size: size) {
                // 替代字形不是官方原版，必须一直可见，否则报告会把近似读成等价。
                return resolution(
                    font: font,
                    source: "stockSubstituted",
                    diagnostic: "stockFontSubstituted:\(stock.category.rawValue)",
                    requestedPath: requestedPath
                )
            }
        }
        return approximateStockFont(stock, requestedPath: requestedPath, size: size)
    }

    nonisolated private static func approximateStockFont(
        _ stock: StockFont,
        requestedPath: String,
        size: CGFloat
    ) -> Resolution {
        let preferred = stock.category.approximationFamily
        let family = isInstalledFontFamily(preferred) ? preferred : "Helvetica"
        let font = CTFontCreateWithName(family as CFString, size, nil)
        // 15 个 stock 字体都有随包文件，走到这里说明 app 包缺失或损坏，是运维问题，
        // 不能和正常的 stock 命中混成一种诊断。
        return resolution(
            font: font,
            source: "stockApproximation",
            diagnostic: "stockFontFileUnavailable:\(stock.category.rawValue)",
            requestedPath: requestedPath
        )
    }

    nonisolated private static func stockFont(fileName: String, size: CGFloat) -> CTFont? {
        guard let stockFontsDirectory else { return nil }
        let url = stockFontsDirectory.appendingPathComponent(fileName)
        guard let data = try? Data(contentsOf: url),
              let provider = CGDataProvider(data: data as CFData),
              let graphicsFont = CGFont(provider) else {
            return nil
        }
        return CTFontCreateWithGraphicsFont(graphicsFont, size, nil, nil)
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
