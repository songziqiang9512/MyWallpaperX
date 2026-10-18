"""Compile actual pure shader helpers across the App's default actor boundary."""
from pathlib import Path
import os
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
FRONTEND = ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Compilation/ShaderFrontend"
HARNESS = r'''
import Foundation
@main enum Harness {
    static func main() async {
        await Task.detached {
            for name in ["sourceValue", "renamedCarrier"] {
                let text = "float \(name) = 1;"
                let matches = SceneShaderSourceTextFacts.matches(#"float ([A-Za-z_]\w*)"#, in: text)
                precondition(matches.count == 1)
                precondition(SceneShaderSourceTextFacts.capture(matches[0], 1, in: text) == name)
                precondition(SceneShaderSourceTextFacts.containsWord(name, in: text))
                precondition(!SceneShaderSourceTextFacts.containsWord(name + "x", in: text))
                precondition(SceneShaderSourceTextFacts.textureSlot("g_Texture7") == 7)
                precondition(SceneShaderSourceTextFacts.textureSlot("g_Texture8") == nil)
                let values = ["(", name, ",", "(", "other", ",", "tail", ")", ")"]
                let tokens = values.enumerated().map { index, value in
                    SceneAuthoredShaderToken(kind: .symbol, text: value, line: 1, column: index + 1)
                }
                precondition(SceneAuthoredShaderTokenScanner.matchingParenthesis(tokens: tokens, opening: 0) == 8)
                precondition(SceneAuthoredShaderTokenScanner.split(1..<8, separator: ",", tokens: tokens) == [1..<2, 3..<8])
                precondition(SceneAuthoredShaderTokenScanner.commaRanges(0..<9, tokens: tokens) == [0..<9])
            }
        }.value
        print("shader-syntax-concurrency-ok")
    }
}
'''


class ShaderSyntaxConcurrencyTests(unittest.TestCase):
    def test_pure_helpers_compile_and_execute_from_detached_task_in_swift_5_and_6(self):
        # Keep complete product declarations and extension modifiers. Only the
        # unrelated frontend preparation graph above these helpers is omitted.
        syntax = (FRONTEND / "SceneAuthoredShaderSyntax.swift").read_text()
        syntax = syntax[syntax.index("nonisolated enum SceneShaderSourceTextFacts"):]
        model = (FRONTEND / "SceneAuthoredShaderFrontendModel.swift").read_text()
        token = model[model.index("nonisolated struct SceneAuthoredShaderToken: Hashable"):]
        with tempfile.TemporaryDirectory(prefix="mwx-syntax-concurrency-") as raw:
            directory = Path(raw)
            source = directory / "Helpers.swift"
            source.write_text("import Foundation\n" + token + "\n" + syntax)
            harness = directory / "Harness.swift"
            harness.write_text(HARNESS)
            env = os.environ.copy()
            env["CLANG_MODULE_CACHE_PATH"] = str(directory / "cache")
            for mode in ("5", "6"):
                with self.subTest(languageMode=mode):
                    binary = directory / ("harness-" + mode)
                    result = subprocess.run([
                        "swiftc", "-parse-as-library", "-swift-version", mode,
                        "-default-isolation", "MainActor", "-warnings-as-errors",
                        "-module-cache-path", str(directory / "cache"),
                        str(source), str(harness), "-o", str(binary),
                    ], env=env, capture_output=True, text=True, timeout=60)
                    self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                    run = subprocess.run([str(binary)], capture_output=True, text=True, timeout=10)
                    self.assertEqual(run.returncode, 0, run.stdout + run.stderr)
                    self.assertEqual(run.stdout.strip(), "shader-syntax-concurrency-ok")


if __name__ == "__main__":
    unittest.main()
