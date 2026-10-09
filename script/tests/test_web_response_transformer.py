from __future__ import annotations

import shutil
import subprocess
import tempfile
import textwrap
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
# 转换器 + mwx-local resolve：两类断言共用一次 swiftc 编译，覆盖 Support 层
# 的响应改写与受控读取解析（resolve 百分号合同见 harness 末段）。
TRANSFORMER_SOURCES = [
    ROOT / "MyWallpaperX/Core/SteamWorkshopWeb/Host/WebRuntimeDiagnosticsStore.swift",
    ROOT / "MyWallpaperX/Core/SteamWorkshopWeb/Support/WebWallpaperLocalSchemeHandler.swift",
    ROOT / "MyWallpaperX/Core/SteamWorkshopWeb/Support/WebWallpaperLocalSchemeHandler+Resolve.swift",
    ROOT / "MyWallpaperX/Core/SteamWorkshopWeb/Support/WebWallpaperLocalSchemeHandler+IO.swift",
    ROOT / "MyWallpaperX/Core/SteamWorkshopWeb/Support/WebWallpaperResponseTransformer.swift",
    ROOT / "MyWallpaperX/Core/SteamWorkshopWeb/Support/WebWallpaperHTMLTransformer.swift",
    ROOT / "MyWallpaperX/Core/SteamWorkshopWeb/Support/WebWallpaperCSSImportTransformer.swift",
]


class WebResponseTransformerTests(unittest.TestCase):
    def test_production_transformers(self) -> None:
        swiftc = shutil.which("swiftc")
        if swiftc is None:
            self.skipTest("swiftc is unavailable")

        harness = textwrap.dedent(
            r'''
            import Foundation

            func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
                guard condition() else {
                    FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
                    exit(1)
                }
            }

            func markerCount(_ value: String) -> Int {
                value.components(separatedBy: "data-mwx-deferred-stylesheet").count - 1
            }

            let googleLink = #"<link rel='stylesheet' href='http://fonts.googleapis.com/css2?family=Inter'>"#
            let transformedGoogleLink = WebWallpaperHTMLTransformer.transform(googleLink)
            expect(transformedGoogleLink.contains("rel='preload'"), "Google Fonts link should become a preload")
            expect(transformedGoogleLink.contains("href='https://fonts.googleapis.com/css2?family=Inter'"), "Google Fonts HTTP links should upgrade to HTTPS")
            expect(transformedGoogleLink.contains("as=\"style\""), "deferred link should identify a style preload")
            expect(transformedGoogleLink.contains("data-mwx-deferred-stylesheet=\"stylesheet\""), "original rel should be retained")

            let protocolRelativeLink = #"<link href="//fonts.googleapis.com/css2?family=Fira+Code" rel="stylesheet">"#
            let transformedProtocolRelativeLink = WebWallpaperHTMLTransformer.transform(protocolRelativeLink)
            expect(transformedProtocolRelativeLink.contains(#"href="https://fonts.googleapis.com/css2?family=Fira+Code""#), "protocol-relative Google Fonts links should become absolute HTTPS URLs")
            expect(transformedProtocolRelativeLink.contains(#"rel="preload""#), "href-before-rel links should still replace rel correctly")
            expect(markerCount(transformedProtocolRelativeLink) == 1, "protocol-relative Google Fonts links should transform once")

            let quotedGreaterThan = #"<link title='a > b' rel='stylesheet' href='https://fonts.googleapis.com/css2?family=Roboto'>"#
            let transformedQuotedGreaterThan = WebWallpaperHTMLTransformer.transform(quotedGreaterThan)
            expect(transformedQuotedGreaterThan.contains("title='a > b'"), "quoted greater-than should not truncate a tag")
            expect(markerCount(transformedQuotedGreaterThan) == 1, "quoted greater-than link should transform once")

            let rawText = #"""
            <!-- <link rel="stylesheet" href="https://fonts.googleapis.com/comment"> -->
            <script>const template = '<link rel="stylesheet" href="https://fonts.googleapis.com/script">';</script>
            <style>.sample::before { content: '<link rel="stylesheet" href="https://fonts.googleapis.com/style">'; }</style>
            <textarea><link rel="stylesheet" href="https://fonts.googleapis.com/textarea"></textarea>
            <title><link rel="stylesheet" href="https://fonts.googleapis.com/title"></title>
            <link rel="stylesheet" href="https://fonts.googleapis.com/real">
            """#
            expect(markerCount(WebWallpaperHTMLTransformer.transform(rawText)) == 1, "raw text and comments must remain untouched")

            let expandedRawText = #"""
            <xmp><link rel="stylesheet" href="https://fonts.googleapis.com/xmp"></xmp>
            <iframe><link rel="stylesheet" href="https://fonts.googleapis.com/iframe-fallback"></iframe>
            <noembed><link rel="stylesheet" href="https://fonts.googleapis.com/noembed"></noembed>
            <noframes><link rel="stylesheet" href="https://fonts.googleapis.com/noframes"></noframes>
            <noscript><link rel="stylesheet" href="https://fonts.googleapis.com/noscript"></noscript>
            <link rel="stylesheet" href="https://fonts.googleapis.com/after-raw-text">
            """#
            expect(markerCount(WebWallpaperHTMLTransformer.transform(expandedRawText)) == 1, "legacy raw-text and iframe fallback content must remain untouched")

            let plaintext = #"<link rel="stylesheet" href="https://fonts.googleapis.com/before-plaintext"><plaintext><link rel="stylesheet" href="https://fonts.googleapis.com/inside-plaintext"></plaintext><link rel="stylesheet" href="https://fonts.googleapis.com/after-plaintext-close">"#
            expect(markerCount(WebWallpaperHTMLTransformer.transform(plaintext)) == 1, "plaintext should consume the rest of its parent document")

            let iframeDocument = #"<link rel="stylesheet" href="https://fonts.googleapis.com/iframe-document">"#
            expect(markerCount(WebWallpaperHTMLTransformer.transform(iframeDocument)) == 1, "an independently loaded iframe document should still transform")

            let skippedLinks = [
                #"<link rel="alternate stylesheet" href="https://fonts.googleapis.com/a">"#,
                #"<link rel="stylesheet" href="https://fonts.googleapis.com/a" disabled>"#,
                #"<link rel="stylesheet" href="https://fonts.googleapis.com/a" media="print">"#,
                #"<link rel="stylesheet" href="https://fonts.googleapis.com/a" as="style">"#,
                #"<link rel="stylesheet" href="https://fonts.googleapis.com/a" onload="ready()">"#,
                #"<link rel="stylesheet" href="https://fonts.googleapis.com/a" data-mwx-deferred-stylesheet="stylesheet">"#,
                #"<link rel="stylesheet" data-href="https://fonts.googleapis.com/a">"#,
                #"<link data-rel="stylesheet" href="https://fonts.googleapis.com/a">"#,
                #"<link rel="stylesheet" href="https://cdn.example.com/business.css">"#,
                #"<link rel="stylesheet" href="https://fonts.googleapis.com/a" type="text/plain">"#,
            ]
            for (index, link) in skippedLinks.enumerated() {
                expect(WebWallpaperHTMLTransformer.transform(link) == link, "skip boundary \(index) should remain byte-for-byte unchanged")
            }

            let optedIn = #"<link rel="stylesheet" href="http://127.0.0.1:48765/slow.css" data-mwx-defer-stylesheet>"#
            let transformedOptedIn = WebWallpaperHTMLTransformer.transform(optedIn)
            expect(markerCount(transformedOptedIn) == 1, "explicit opt-in should defer a non-Google stylesheet")
            expect(transformedOptedIn.contains(#"href="http://127.0.0.1:48765/slow.css""#), "explicit non-Google opt-in should preserve its authored URL")

            let css = #"""
            @charset "UTF-8";
            /* leading comment */
            @layer reset;
            @import url("http://fonts.googleapis.com/css2?family=Inter");
            body { color: black; }
            @import "https://fonts.googleapis.com/css2?family=Late";
            """#
            let transformedCSS = WebWallpaperCSSImportTransformer.transform(css)
            expect(transformedCSS.contains(#"@import url("https://fonts.googleapis.com/css2?family=Inter") not all;"#), "eligible Google import should be deferred and upgraded to HTTPS")
            expect(transformedCSS.contains(#"@import "https://fonts.googleapis.com/css2?family=Late";"#), "late import should remain untouched")

            let supportedGoogleImports = [
                #"@import url(https://fonts.googleapis.com/css2?family=Roboto);"#,
                #"@import "//fonts.googleapis.com/css2?family=Lato";"#,
                #"@import url('//fonts.googleapis.com/css2?family=Nunito');"#,
                #"@import url(//fonts.googleapis.com/css2?family=Oswald);"#,
            ]
            for (index, statement) in supportedGoogleImports.enumerated() {
                let transformed = WebWallpaperCSSImportTransformer.transform(statement)
                expect(transformed.hasPrefix(#"@import url("https://fonts.googleapis.com/"#), "supported Google import \(index) should normalize to HTTPS")
                expect(transformed.hasSuffix(#"") not all;"#), "supported Google import \(index) should become nonblocking")
            }

            let cssStringOnly = #"body::before { content: '@import "https://fonts.googleapis.com/not-a-rule";'; }"#
            expect(WebWallpaperCSSImportTransformer.transform(cssStringOnly) == cssStringOnly, "CSS strings must remain untouched")
            let conditionalImport = #"@import url("https://fonts.googleapis.com/css2?family=Print") print;"#
            expect(WebWallpaperCSSImportTransformer.transform(conditionalImport) == conditionalImport, "conditional imports must retain their authored media semantics")
            let protocolRelativeConditionalImport = #"@import url(//fonts.googleapis.com/css2?family=Layered) layer(fonts);"#
            expect(WebWallpaperCSSImportTransformer.transform(protocolRelativeConditionalImport) == protocolRelativeConditionalImport, "protocol-relative imports with authored conditions must remain untouched")
            let compoundMediaImport = #"@import url("https://fonts.googleapis.com/css2?family=Wide") screen and (min-width:400px);"#
            expect(WebWallpaperCSSImportTransformer.transform(compoundMediaImport) == compoundMediaImport, "compound media imports must retain their authored media semantics")
            // 裸 screen 在壁纸 WKWebView 恒真：随 not all 丢弃无语义损失，
            // 必须与其他恒真形式一样改写为非阻塞。
            let screenQualifiedImport = #"@import url("https://fonts.googleapis.com/css2?family=ScreenOnly") screen;"#
            let transformedScreenQualified = WebWallpaperCSSImportTransformer.transform(screenQualifiedImport)
            expect(transformedScreenQualified == #"@import url("https://fonts.googleapis.com/css2?family=ScreenOnly") not all;"#, "bare screen qualifier is always true in the wallpaper webview and must defer like unqualified imports")
            let screenQualifiedQuotedImport = #"@import "https://fonts.googleapis.com/css2?family=ScreenQuoted" screen;"#
            let transformedScreenQuoted = WebWallpaperCSSImportTransformer.transform(screenQualifiedQuotedImport)
            expect(transformedScreenQuoted == #"@import url("https://fonts.googleapis.com/css2?family=ScreenQuoted") not all;"#, "quoted import with bare screen qualifier must defer and normalize to HTTPS")

            expect(WebWallpaperResponseTransformer.supportsTransformation(for: URL(fileURLWithPath: "/tmp/index.HTML")), "HTML should be transformable")
            expect(WebWallpaperResponseTransformer.supportsTransformation(for: URL(fileURLWithPath: "/tmp/site.css")), "CSS should be transformable")
            expect(!WebWallpaperResponseTransformer.supportsTransformation(for: URL(fileURLWithPath: "/tmp/video.mp4")), "binary media must not be transformed")

            // mwx-local resolve 百分号合同：三条生产路径（入口构造、
            // randomFile/__absolute__ 逐段编码、页面 encodeURIComponent）都
            // 恰好编码一次，自定义 scheme 的 URL.path 恰好解码一次——resolve
            // 侧不得再做第二次 removingPercentEncoding，否则字面 %XX 文件名
            // 解析到错误路径或 404，且缓存键互相碰撞会静默交付错内容。
            let resolveRoot = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
                .appendingPathComponent("mwx-web-scheme-resolve-\(UUID().uuidString)", isDirectory: true)
            let resolveAssets = resolveRoot.appendingPathComponent("assets", isDirectory: true)
            try FileManager.default.createDirectory(at: resolveAssets, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: resolveRoot) }
            for (name, payload) in [
                ("bg%20cover.png", Data("LITERAL".utf8)),
                ("bg cover.png", Data("SPACED".utf8)),
                ("sub%2Ffile.png", Data("SLASHY".utf8)),
                ("100%.png", Data("PCT".utf8)),
                ("plain.png", Data("PLAIN".utf8)),
            ] {
                try Data(payload).write(to: resolveAssets.appendingPathComponent(name))
            }
            let schemeHandler = WebWallpaperLocalSchemeHandler(rootURL: resolveRoot)
            func resolvedLastComponent(_ urlString: String) -> String? {
                guard let url = URL(string: urlString) else { return nil }
                return schemeHandler.resolveResource(for: url, allowsDirectoryIndexFallback: false).resource?.fileURL.lastPathComponent
            }
            expect(resolvedLastComponent("mwx-local://wallpaper/assets/bg%2520cover.png") == "bg%20cover.png",
                   "literal %20 filename must resolve to itself")
            expect(resolvedLastComponent("mwx-local://wallpaper/assets/bg%20cover.png") == "bg cover.png",
                   "space filename must resolve to itself")
            expect(resolvedLastComponent("mwx-local://wallpaper/assets/sub%252Ffile.png") == "sub%2Ffile.png",
                   "literal %2F filename must stay one path component")
            expect(resolvedLastComponent("mwx-local://wallpaper/assets/100%25.png") == "100%.png",
                   "invalid percent sequence filename must resolve to itself")
            expect(resolvedLastComponent("mwx-local://wallpaper/assets/plain.png") == "plain.png",
                   "plain filename must resolve to itself")
            expect(resolvedLastComponent("mwx-local://wallpaper/assets/bg%2520cover.png?cb=1") == "bg%20cover.png",
                   "literal %20 request with query must still resolve to the literal file")
            expect(resolvedLastComponent("mwx-local://wallpaper/assets/bg%20cover.png?cb=1") == "bg cover.png",
                   "space request with query must still resolve to the spaced file")

            print("Web response transformer tests passed")
            '''
        )

        with tempfile.TemporaryDirectory(prefix="mwx-web-transformer-tests-") as directory:
            temporary = Path(directory)
            harness_path = temporary / "main.swift"
            binary_path = temporary / "WebResponseTransformerTests"
            harness_path.write_text(harness, encoding="utf-8")
            subprocess.run(
                [swiftc, *(str(path) for path in TRANSFORMER_SOURCES), str(harness_path), "-o", str(binary_path)],
                cwd=ROOT,
                check=True,
            )
            completed = subprocess.run(
                [str(binary_path)],
                cwd=ROOT,
                check=True,
                capture_output=True,
                text=True,
            )
            self.assertIn("tests passed", completed.stdout)


if __name__ == "__main__":
    unittest.main()
