"""Exercise the shipped Help pages in a native WebKit document."""
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

from script.governance.check_help_bundle import HELP, LANGS


PROBE = r'''
import AppKit
import WebKit

@MainActor
final class Book: NSObject, WKNavigationDelegate {
    private let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
    private var languages = Array(CommandLine.arguments.dropFirst(2))
    private var language = ""
    private let view: WKWebView = {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        return WKWebView(frame: .zero, configuration: configuration)
    }()

    func next() {
        if languages.isEmpty { exit(EXIT_SUCCESS) }
        language = languages.removeFirst()
        view.navigationDelegate = self
        let page = root.appendingPathComponent("\(language).lproj/index.html")
        view.loadFileURL(page, allowingReadAccessTo: root)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task {
            do {
                _ = try await view.callAsyncJavaScript("""
                    const search = document.querySelector('#help-search');
                    if (search.closest('label').hidden) throw new Error('Search did not initialize');
                    const scene = document.querySelector('#scene');
                    const video = document.querySelector('#video');
                    search.value = 'MSAA';
                    search.dispatchEvent(new Event('input', { bubbles: true }));
                    if (scene.hidden || !video.hidden) throw new Error('Search did not filter chapters');
                    const navigated = new Promise(resolve => {
                      window.addEventListener('hashchange', resolve, { once: true });
                      setTimeout(resolve, 500);
                    });
                    scene.querySelector('a[href="#wallpaper-quality"]').click();
                    await navigated;
                    if (location.hash !== '#wallpaper-quality' || search.value || video.hidden) {
                      throw new Error('Chapter link did not restore the book and navigate');
                    }
                    """, arguments: [:], in: nil, contentWorld: .page)
                next()
            } catch {
                fail(error)
            }
        }
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        fail(error)
    }

    private func fail(_ error: Error) -> Never {
        FileHandle.standardError.write(Data("\(language): \(error)\n".utf8))
        exit(EXIT_FAILURE)
    }
}

@main struct Probe {
    @MainActor static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        let book = Book()
        book.next()
        withExtendedLifetime(book) { app.run() }
    }
}
'''


@unittest.skipUnless(sys.platform == "darwin" and shutil.which("xcrun"), "requires macOS WebKit and Xcode")
class HelpBookTests(unittest.TestCase):
    def test_localized_search_filters_chapters_and_links_restore_the_book(self):
        with tempfile.TemporaryDirectory(prefix="mwx-help-test-") as directory:
            root = Path(directory)
            source = root / "HelpBookProbe.swift"
            executable = root / "help-book-probe"
            source.write_text(PROBE)
            subprocess.run(["xcrun", "swiftc", "-parse-as-library", source, "-o", executable],
                           check=True, timeout=60)
            env = {**os.environ, "HOME": directory, "CFFIXED_USER_HOME": directory}
            result = subprocess.run([executable, HELP, *LANGS], env=env, capture_output=True, text=True, timeout=20)
            self.assertEqual(result.returncode, 0, result.stderr)
