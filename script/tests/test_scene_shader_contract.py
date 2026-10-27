#!/usr/bin/env python3

import hashlib
import json
import sys
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import textwrap
import unittest


SOURCE_SET_SCRIPT_ROOT = Path(__file__).resolve().parents[1]
if str(SOURCE_SET_SCRIPT_ROOT) not in sys.path:
    sys.path.insert(0, str(SOURCE_SET_SCRIPT_ROOT))

from scene_swift_source_sets import scene_swift_sources


REPO_ROOT = Path(__file__).resolve().parents[2]
SCENE_ROOT = REPO_ROOT / "MyWallpaperX/Core/SteamWorkshopScene"
SHADER_CONTRACT_RESOURCE_RESOLUTION_SOURCES = scene_swift_sources(
    "shader_contract_resource_resolution"
)
SWIFT_SOURCES = [
    *SHADER_CONTRACT_RESOURCE_RESOLUTION_SOURCES,
]

HARNESS = r"""
import Foundation

private struct Output: Codable {
    let contracts: [SceneShaderContract]
    let mixedContract: SceneShaderContract?
    let packageVertexContract: SceneShaderContract?
    let largeRawStageCount: Int
    let largeDiagnosticCodes: [String]
    let largeGraphBudgetExceeded: Bool
    let hiddenRawStageCount: Int
    let hiddenGraphNodeCount: Int
    let reversedCanonical: [String: String]
    let reversedDependency: [String: String]
    let roundTripEqual: Bool
    let finiteCanonicalDigest: String?
    let repeatedCanonicalDigest: String?
    let nonFiniteCanonicalDigest: String?
    let nonFiniteDigestIsAbsent: Bool
    let nonFiniteDigestMatchesProfileSentinel: Bool
}

// The pre-P13 implementation is a test-only oracle for exact lexical output.
// It returns the current value type but retains its original accumulation code.
private enum OriginalShaderLexicalScanner {
    static func scan(_ line: String, inBlockComment: inout Bool) -> SceneShaderLexicalLine {
        var segments: [SceneShaderLexicalLine.Segment] = []
        func append(_ kind: SceneShaderLexicalLine.SegmentKind, _ text: String) {
            guard !text.isEmpty else { return }
            if let last = segments.last, last.kind == kind {
                segments[segments.count - 1] = .init(kind: kind, text: last.text + text)
            } else {
                segments.append(.init(kind: kind, text: text))
            }
        }

        var index = line.startIndex
        while index < line.endIndex {
            let next = line.index(after: index)
            let pair = next < line.endIndex ? String(line[index ... next]) : ""
            if inBlockComment {
                append(.blockComment, String(line[index]))
                index = next
                if pair == "*/" {
                    append(.blockComment, "/")
                    index = line.index(after: next)
                    inBlockComment = false
                }
                continue
            }
            if pair == "//" {
                append(.lineComment, String(line[index...]))
                break
            }
            if pair == "/*" {
                append(.blockComment, "/*")
                index = line.index(after: next)
                inBlockComment = true
                continue
            }
            let character = line[index]
            if character == "\"" || character == "'" {
                let start = index
                let quote = character
                var escaped = false
                repeat {
                    let value = line[index]
                    index = line.index(after: index)
                    if escaped { escaped = false }
                    else if value == "\\" { escaped = true }
                    else if value == quote, index > line.index(after: start) { break }
                } while index < line.endIndex
                append(.quoted, String(line[start ..< index]))
                continue
            }
            append(.code, String(character))
            index = next
        }
        return .init(segments: segments)
    }
}

private struct LexicalInput: Decodable {
    struct Case: Decodable {
        let name: String
        let lines: [String]
        let initialBlockComment: Bool
    }
    let cases: [Case]
}
private struct LexicalSnapshot: Codable {
    struct Segment: Codable { let kind: String; let text: String }
    let segments: [Segment]
    let code: String
    let raw: String?
    let inBlockComment: Bool
    init(_ value: SceneShaderLexicalLine, inBlockComment: Bool) {
        segments = value.segments.map { Segment(kind: String(describing: $0.kind), text: $0.text) }
        code = value.code
        raw = value.lineCommentRaw
        self.inBlockComment = inBlockComment
    }
}
private struct LexicalRow: Codable {
    let name: String
    let actual: [LexicalSnapshot]
    let oracle: [LexicalSnapshot]
}
private func lexicalRows(_ url: URL) throws -> [LexicalRow] {
    let input = try JSONDecoder().decode(LexicalInput.self, from: Data(contentsOf: url))
    return input.cases.map { item in
        var actualState = item.initialBlockComment
        var oracleState = item.initialBlockComment
        var actual: [LexicalSnapshot] = [], oracle: [LexicalSnapshot] = []
        for line in item.lines {
            let current = SceneShaderLexicalScanner.scan(line, inBlockComment: &actualState)
            let previous = OriginalShaderLexicalScanner.scan(line, inBlockComment: &oracleState)
            actual.append(LexicalSnapshot(current, inBlockComment: actualState))
            oracle.append(LexicalSnapshot(previous, inBlockComment: oracleState))
        }
        return LexicalRow(name: item.name, actual: actual, oracle: oracle)
    }
}

@main
private struct ShaderContractHarness {
    static func main() throws {
        if CommandLine.arguments[1] == "--path-names" {
            let root = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
            let references = try JSONDecoder().decode([String].self,
                from: Data(CommandLine.arguments[3].utf8))
            let contracts = try SceneShaderContractLoader().load(shaderReferences: references, rootURL: root)
            FileHandle.standardOutput.write(try JSONEncoder().encode(contracts))
            return
        }
        if CommandLine.arguments[1] == "--lexical" {
            let rows = try lexicalRows(URL(fileURLWithPath: CommandLine.arguments[2]))
            FileHandle.standardOutput.write(try JSONEncoder().encode(rows))
            return
        }
        let rootURL = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let references = [
            "effects/good",
            "effects/good.vert",
            "effects/missing",
            "effects/fragonly",
            "effects/malformed",
            "effects/stageskip",
            "effects/malformedforms",
            "effects/legacynumber",
            "effects/malformednumeric",
            "effects/legacyoversized",
            "effects/prosemarker",
            "effects/invalid",
            "effects/unreadable",
            "effects/symlink",
            "effects/includeescape",
            "effects/includesymlink",
            "../outside/escape",
            "",
            "genericimage2",
            "genericimage4.json",
            "genericparticle",
            "foo/genericimage2"
        ]
        let loader = SceneShaderContractLoader()
        let contracts = try loader.load(shaderReferences: references, rootURL: rootURL)
        let reversed = try loader.load(shaderReferences: references.reversed(), rootURL: rootURL)
        let reversedCanonical = Dictionary(
            uniqueKeysWithValues: reversed.map { ($0.identity, $0.canonicalSHA256) }
        )
        let reversedDependency = Dictionary(
            uniqueKeysWithValues: reversed.compactMap { contract in
                contract.sourceGraph.map {
                    (contract.identity, $0.dependencySHA256)
                }
            }
        )
        let encodedContracts = try JSONEncoder().encode(contracts)
        let decodedContracts = try JSONDecoder().decode(
            [SceneShaderContract].self,
            from: encodedContracts
        )
        let mixedContract = try loader.load(
            shaderReferences: ["effects/mixed"],
            resourceView: SceneResourceView(
                projectRootURL: rootURL.appendingPathComponent("mixed-loose"),
                packageRootURL: rootURL.appendingPathComponent("mixed-package"),
                stockAssetsRootURL: nil
            )
        ).first
        let packageVertexContract = try loader.load(
            shaderReferences: ["effects/packagevertex"],
            resourceView: SceneResourceView(
                projectRootURL: rootURL.appendingPathComponent("mixed-loose"),
                packageRootURL: rootURL.appendingPathComponent("mixed-package"),
                stockAssetsRootURL: nil
            )
        ).first
        let large = try loader.load(
            shaderReferences: ["effects/large"],
            rootURL: rootURL
        ).first
        let largeGraphBudgetExceeded = large?.sourceGraph?.edges.contains { edge in
            guard edge.parentVirtualPath == nil else { return false }
            switch edge.outcome {
            case .graphBudgetExceeded, .failed(.fileTooLarge): return true
            default: return false
            }
        } ?? false
        let hidden = try loader.load(
            shaderReferences: [".hidden/effects/foo"],
            resourceView: SceneResourceView(
                projectRootURL: rootURL.appendingPathComponent("hidden-loose"),
                packageRootURL: rootURL.appendingPathComponent("hidden-package"),
                stockAssetsRootURL: nil
            )
        ).first
        // Boundary probe for the shared canonical projection: an authored
        // numeric value that cannot be encoded must yield no digest at all, so
        // the recomputation in the stock identity comparison fails closed.
        func canonicalDigestProbe(numberLiteral: Double) -> String? {
            let annotation = SceneShaderContract.Annotation(
                marker: "[RANGE]",
                value: .number(numberLiteral),
                raw: "// [RANGE] \(numberLiteral)",
                line: 1
            )
            let stage = SceneShaderContract.Stage(
                kind: .fragment,
                relativePath: "shaders/effects/probe.frag",
                source: "void main() {}",
                rawSHA256: String(repeating: "a", count: 64),
                includes: [],
                annotations: [annotation],
                declarations: []
            )
            return SceneShaderContractLoader.canonicalHash(
                SceneShaderContract(
                    identity: "effects/probe",
                    sourceKind: .authoredSource,
                    stages: [stage],
                    diagnostics: [],
                    canonicalSHA256: ""
                )
            )
        }
        let finiteCanonicalDigest = canonicalDigestProbe(numberLiteral: 1.5)
        let repeatedCanonicalDigest = canonicalDigestProbe(numberLiteral: 1.5)
        let nonFiniteCanonicalDigest = canonicalDigestProbe(numberLiteral: .infinity)
        let profileSentinel = String(repeating: "0", count: 64)
        let output = Output(
            contracts: contracts,
            mixedContract: mixedContract,
            packageVertexContract: packageVertexContract,
            largeRawStageCount: large?.stages.count ?? 0,
            largeDiagnosticCodes: large?.diagnostics.map(\.code.rawValue) ?? [],
            largeGraphBudgetExceeded: largeGraphBudgetExceeded,
            hiddenRawStageCount: hidden?.stages.count ?? 0,
            hiddenGraphNodeCount: hidden?.sourceGraph?.nodes.count ?? 0,
            reversedCanonical: reversedCanonical,
            reversedDependency: reversedDependency,
            roundTripEqual: decodedContracts == contracts,
            finiteCanonicalDigest: finiteCanonicalDigest,
            repeatedCanonicalDigest: repeatedCanonicalDigest,
            nonFiniteCanonicalDigest: nonFiniteCanonicalDigest,
            nonFiniteDigestIsAbsent: nonFiniteCanonicalDigest == nil,
            nonFiniteDigestMatchesProfileSentinel:
                nonFiniteCanonicalDigest == profileSentinel
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        FileHandle.standardOutput.write(try encoder.encode(output))
    }
}
"""


class SceneShaderContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        swiftc = shutil.which("swiftc")
        if swiftc is None:
            raise unittest.SkipTest("swiftc is unavailable")
        cls.build_directory = tempfile.TemporaryDirectory()
        build_root = Path(cls.build_directory.name)
        harness = build_root / "ShaderContractHarness.swift"
        harness.write_text(HARNESS, encoding="utf-8")
        cls.binary = build_root / "shader-contract-harness"
        subprocess.run(
            [
                swiftc,
                *(str(path) for path in SWIFT_SOURCES),
                str(harness),
                "-o",
                str(cls.binary),
            ],
            cwd=REPO_ROOT,
            check=True,
            capture_output=True,
            text=True,
        )

    @classmethod
    def tearDownClass(cls):
        cls.build_directory.cleanup()

    def test_lexical_segments_match_original_function_and_keep_projection(self):
        cases = []

        def add(name, *lines, initial=False):
            cases.append(dict(name=name, lines=lines, initialBlockComment=initial))

        add("empty", "")
        add("ordinary", "float value = left / right + 2.0;")
        add("line-comment", "// /* is text, not a block")
        add("block-and-tail", "before/* hidden */after // tail")
        add("quotes", '\"/* quoted */ // still quoted\" + \'/\' // actual')
        add("escaped-quote", r'"quote\" // inside" /* outside */ tail')
        add("adjacent-quotes", '\"a\"\'b\'\"c\"')
        add("cross-line", "prefix/* hidden", '\" // #define still hidden', "*/real // tail")
        add("initial-comment", "", "inside*/next", initial=True)
        add("unterminated-comment", "code /* comment", "still hidden")
        add("unterminated-quote", '\"not closed /* still quoted')
        add("unicode", 'α = "e\u0301👩‍🚀 //"; /*e\u0301👩‍🚀*/ β //尾')
        add("directive", '#define VALUE 1 // [COMBO] {"combo":"LEVEL","default":1}')
        add("carriage-return", "\t#define FLAG 1\r")
        for text in ("/", "//", "/*", "*/", "**/", "/*/**/*/x"):
            add("delimiter-" + text, text)
        add("long-code", "value_" + "a" * 8192)
        add("long-comment", "/*" + "x" * 8192 + "*/ tail")
        add("long-unicode-comment", "/*" + "e\u0301👩‍🚀" * 512 + "*/ next")
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "lexical-input.json"
            path.write_text(json.dumps(dict(cases=cases), ensure_ascii=False))
            completed = subprocess.run([str(self.binary), "--lexical", str(path)],
                                       cwd=REPO_ROOT, check=True, capture_output=True, text=True)
        rows = json.loads(completed.stdout)
        self.assertEqual([row["name"] for row in rows], [item["name"] for item in cases])
        for row in rows:
            with self.subTest(case=row["name"]):
                self.assertEqual(row["actual"], row["oracle"])
        observed = {row["name"]: row["actual"] for row in rows}
        self.assertEqual(observed["empty"][0], dict(segments=[], code="", inBlockComment=False))
        quoted = observed["quotes"][0]
        self.assertEqual([part["kind"] for part in quoted["segments"]],
                         ["quoted", "code", "quoted", "code", "lineComment"])
        self.assertEqual(quoted["code"], '\"/* quoted */ // still quoted\" + \'/\' ')
        self.assertEqual(quoted["raw"], "// actual")
        adjacent = observed["adjacent-quotes"][0]
        self.assertEqual(adjacent["segments"], [dict(kind="quoted", text='\"a\"\'b\'\"c\"')])
        self.assertEqual([line["inBlockComment"] for line in observed["cross-line"]], [True, True, False])
        self.assertEqual(observed["cross-line"][-1]["code"], "  real ")
        self.assertEqual([line["inBlockComment"] for line in observed["initial-comment"]], [True, False])
        self.assertTrue(observed["unterminated-comment"][-1]["inBlockComment"])
        self.assertFalse(observed["unterminated-quote"][0]["inBlockComment"])
        unicode = observed["unicode"][0]
        self.assertEqual(unicode["code"], 'α = "e\u0301👩‍🚀 //"; ' + " " * 6 + " β ")
        self.assertEqual(unicode["raw"], "//尾")
        self.assertEqual(observed["carriage-return"][0]["code"], "\t#define FLAG 1\r")
        self.assertEqual(observed["long-code"][0]["code"], "value_" + "a" * 8192)
        self.assertEqual(observed["long-comment"][0]["code"], " " * 8196 + " tail")

    def test_canonical_digest_boundary_yields_no_digest(self):
        """Shared canonical projection boundary.

        The X-Ray stock identity comparison recomputes this projection, so a
        payload that cannot be encoded must produce no digest at all. The
        verifier's own guard chain (nil digest => unverified identity) is
        structural and is not exercised here.
        """
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory) / "wallpaper"
            root.mkdir(parents=True)
            completed = subprocess.run(
                [str(type(self).binary), str(root)],
                cwd=REPO_ROOT,
                check=True,
                capture_output=True,
                text=True,
            )
        payload = json.loads(completed.stdout)
        finite = payload["finiteCanonicalDigest"]
        self.assertIsInstance(finite, str)
        self.assertEqual(64, len(finite))
        self.assertTrue(
            all(character in "0123456789abcdef" for character in finite),
            f"digest must be lowercase hex: {finite}",
        )
        self.assertEqual(
            finite,
            payload["repeatedCanonicalDigest"],
            "the canonical projection must stay deterministic",
        )
        # The projection is a stored contract: the X-Ray stock profiles compare
        # authored contracts against digests produced by this exact encoding, so
        # this constant is their cross-check against an accidental shape change.
        self.assertEqual(
            "643b1ae1f73d790d3ba989b07fd7e6662993ab5d417c93bc442f8c54a8c54eef",
            finite,
            "canonical projection changed; re-derive the stock identity profiles first",
        )
        self.assertNotIn(
            "nonFiniteCanonicalDigest",
            payload,
            "a payload that cannot be encoded must yield no digest instead of a collapsed constant",
        )
        self.assertTrue(payload["nonFiniteDigestIsAbsent"])
        self.assertFalse(
            payload["nonFiniteDigestMatchesProfileSentinel"],
            "a contract without a digest can never satisfy the stock identity comparison",
        )

    def test_posix_colon_shader_names_and_includes_keep_actual_root_boundaries(self):
        with tempfile.TemporaryDirectory() as temporary:
            base = Path(temporary)
            root = base / "wallpaper"
            shaders = root / "shaders"
            for identity in ("C:/probe", "中:/probe", "ordinary/probe", "entry/colon", "entry/parent"):
                for suffix in (".vert", ".frag"):
                    path = shaders / (identity + suffix)
                    path.parent.mkdir(parents=True, exist_ok=True)
                    path.write_text("void main() {}\n", encoding="utf-8")
            for name in ("C:/common.glsl", "中:/common.glsl", "ordinary/common.glsl"):
                path = shaders / name
                path.write_text("uniform float contained;\n", encoding="utf-8")
            (shaders / "entry/colon.vert").write_text(
                '#include "C:/common.glsl"\n#include "中:/common.glsl"\n'
                '#include "ordinary/common.glsl"\nvoid main() {}\n', encoding="utf-8")
            outside = base / "outside.glsl"
            outside.write_text("uniform float outside;\n", encoding="utf-8")
            (shaders / "entry/parent.vert").write_text(
                '#include "../../../outside.glsl"\nvoid main() {}\n', encoding="utf-8")
            (shaders / "C:/symlink.vert").symlink_to(outside)
            references = ["C:/probe", "中:/probe", "ordinary/probe", "entry/colon",
                          "entry/parent", "C:/symlink", "../outside/escape", "/outside/absolute", "C:/nul\0probe"]
            completed = subprocess.run(
                [str(self.binary), "--path-names", str(root), json.dumps(references)],
                cwd=REPO_ROOT, check=True, capture_output=True, text=True)
            rows = {row["identity"]: row for row in json.loads(completed.stdout)}
        for identity in ("C:/probe", "中:/probe", "ordinary/probe", "entry/colon"):
            row = rows[identity]
            self.assertEqual(row["diagnostics"], [], row)
            self.assertEqual(len(row["stages"]), 2, row)
            self.assertEqual(row["sourceGraph"]["diagnostics"], [], row)
        colon = rows["entry/colon"]["sourceGraph"]
        paths = {node["virtualPath"] for node in colon["nodes"]}
        self.assertTrue({"shaders/C:/common.glsl", "shaders/中:/common.glsl",
                         "shaders/ordinary/common.glsl"}.issubset(paths), colon)
        self.assertIn("pathEscape", self._diagnostic_codes(rows["entry/parent"]))
        self.assertIn("symlinkEscape", self._diagnostic_codes(rows["C:/symlink"]))
        for identity in ("../outside/escape", "/outside/absolute"):
            self.assertIn("pathEscape", self._diagnostic_codes(rows[identity]))
        self.assertIn("invalidReference", self._diagnostic_codes(rows["C:/nul\0probe"]))
        for row in rows.values():
            self.assertFalse(any("outside.glsl" in node["virtualPath"]
                                 for node in row["sourceGraph"]["nodes"]), row)

    def test_loss_preserving_contract_and_fail_closed_boundaries(self):
        with tempfile.TemporaryDirectory() as temporary_directory:
            base = Path(temporary_directory)
            root = base / "wallpaper"
            shaders = root / "shaders"
            effects = shaders / "effects"
            headers = shaders / "headers"
            includes = shaders / "includes"
            outside = base / "outside"
            for directory in (effects, headers, includes, outside):
                directory.mkdir(parents=True, exist_ok=True)

            vertex_source = (
                '#include "../headers/common.h"\r\n'
                "attribute highp vec3 a_Position;\r\n"
                "#if ENABLE_SPECTRUM\r\n"
                "uniform float g_AudioSpectrum64Right[64];\r\n"
                "#endif\r\n"
                "varying vec2 v_TexCoord[4];\r\n"
                "uniform float u_Strength; // prefix [COMBO] "
                '{ "material": "strength", "default": 1, "options": [0, 1] }\r\n'
            )
            fragment_source = (
                "#version 330\n"
                "varying vec2 v_TexCoord[4];\n"
                "uniform sampler2D g_Texture0; // [COMBO_OFF] "
                '{ "combo": "MASK", "default": 0 }\n'
                "uniform float u_Other; // OFF_COMBO "
                '{ "combo": "ALT", "default": 1 }\n'
                "uniform vec4 u_Color; // [OFF_COMBO] "
                '{ "combo": "COLOR", "meta": { "label": "Tint Value" } }\n'
                "uniform vec4 u_Tint; // "
                '{ "material": "tint", "default": [1, 0.5, 0, 1] }\n'
                "// [COMBO_DISABLED] "
                '{ "combo": "DOUBLESIDED", "default": 0 }\n'
                "// [PASS] shadow shadowcasterdemo\n"
                "//{\n"
                "// commented shader block, not an annotation\n"
                "//}\n"
            )
            vertex_bytes = vertex_source.encode("utf-8")
            fragment_bytes = fragment_source.encode("utf-8")
            (effects / "good.vert").write_bytes(vertex_bytes)
            (effects / "good.frag").write_bytes(fragment_bytes)
            (headers / "common.h").write_text("#define COMMON 1\n", encoding="utf-8")

            # A root-level decoy proves authored sources are rooted under root/shaders.
            (root / "effects").mkdir(parents=True)
            (root / "effects/good.vert").write_text("decoy", encoding="utf-8")
            (root / "effects/good.frag").write_text("decoy", encoding="utf-8")

            (effects / "missing.vert").write_text("uniform float u_Missing;\n", encoding="utf-8")
            (effects / "fragonly.frag").write_text("varying vec2 v_UV;\n", encoding="utf-8")
            (effects / "malformed.vert").write_text(
                'uniform float u_Broken; // [COMBO] { "combo": }\n',
                encoding="utf-8",
            )
            (effects / "malformed.frag").write_text("void main() {}\n", encoding="utf-8")
            (effects / "stageskip.vert").write_text(
                '// [COMBO] {"combo":"CATEGORY","type":"options","default":0,'
                '"options":{"Color":0,"UV":1}}\nvoid main() {}\n',
                encoding="utf-8",
            )
            (effects / "stageskip.frag").write_text(
                '// [COMBO] {"combo":"CATEGORY","type":"options","default":0,'
                '"options":{Color:0,"UV":1}}\nvoid main() {}\n',
                encoding="utf-8",
            )
            (effects / "malformedforms.vert").write_text(
                '// [COMBO] {"value":broken}\n'
                '// [COMBO] {hyphen-key:1}\n'
                '// [COMBO] {"range":[0,01.0]}\n',
                encoding="utf-8",
            )
            (effects / "malformedforms.frag").write_text(
                "void main() {}\n", encoding="utf-8"
            )
            (effects / "legacynumber.vert").write_text(
                'uniform float u_Speed; // {"material":"Speed","default":1,'
                '"range":[0,01]}\n'
                'uniform float u_Label; // {"material":"Label","default":"01"}\n',
                encoding="utf-8",
            )
            (effects / "legacynumber.frag").write_text(
                "void main() {}\n", encoding="utf-8"
            )
            (effects / "malformednumeric.vert").write_text(
                '// [COMBO] {"range":[0,01.0]}\n'
                '// [COMBO] {"range":[0,01e2]}\n'
                '// [COMBO] {"range":[0,+01]}\n'
                '// [COMBO] {"range":[0,01}\n',
                encoding="utf-8",
            )
            (effects / "malformednumeric.frag").write_text(
                "void main() {}\n", encoding="utf-8"
            )
            (effects / "legacyoversized.vert").write_text(
                '// [COMBO] {"padding":"' + ("x" * 16_384) + '","range":[0,01]}\n',
                encoding="utf-8",
            )
            (effects / "legacyoversized.frag").write_text(
                "void main() {}\n", encoding="utf-8"
            )
            (effects / "prosemarker.vert").write_text(
                '// [COMBO] {"combo":"BLENDMODE","type":"imageblending","default":0}\n'
                "// BLENDMODE 是由顶部的 [COMBO] 宏生成的\n"
                "uniform float u_Opacity;\n"
                "void main() {}\n",
                encoding="utf-8",
            )
            (effects / "prosemarker.frag").write_text(
                "// see also [PASS] in the docs\n"
                "void main() {}\n",
                encoding="utf-8",
            )
            (effects / "invalid.vert").write_bytes(b"\xff\xfeinvalid")
            (effects / "invalid.frag").write_text("void main() {}\n", encoding="utf-8")
            (effects / "unreadable.vert").mkdir()
            (effects / "unreadable.frag").write_text("void main() {}\n", encoding="utf-8")

            (outside / "symlink.vert").write_text("uniform float escaped;\n", encoding="utf-8")
            (effects / "symlink.vert").symlink_to(outside / "symlink.vert")
            (effects / "symlink.frag").write_text("void main() {}\n", encoding="utf-8")

            (effects / "includeescape.vert").write_text(
                '#include "../../../outside/common.glsl"\n',
                encoding="utf-8",
            )
            (effects / "includeescape.frag").write_text("void main() {}\n", encoding="utf-8")
            (outside / "common.glsl").write_text("uniform float escaped;\n", encoding="utf-8")
            (includes / "outside.glsl").symlink_to(outside / "common.glsl")
            (effects / "includesymlink.vert").write_text(
                '#include "../includes/outside.glsl"\n',
                encoding="utf-8",
            )
            (effects / "includesymlink.frag").write_text("void main() {}\n", encoding="utf-8")

            mixed_package = root / "mixed-package/shaders/effects"
            mixed_loose = root / "mixed-loose/shaders/effects"
            mixed_package.mkdir(parents=True)
            mixed_loose.mkdir(parents=True)
            (mixed_package / "mixed.frag").write_text(
                "// package fragment\nvoid main() {}\n", encoding="utf-8"
            )
            (mixed_loose / "mixed.vert").write_text(
                "// loose vertex\nvoid main() {}\n", encoding="utf-8"
            )
            (mixed_loose / "mixed.frag").write_text(
                "// loose fragment\nvoid main() {}\n", encoding="utf-8"
            )
            (mixed_package / "packagevertex.vert").write_text(
                "// package vertex\nvoid main() {}\n", encoding="utf-8"
            )
            (mixed_loose / "packagevertex.vert").write_text(
                "// loose vertex\nvoid main() {}\n", encoding="utf-8"
            )
            (mixed_loose / "packagevertex.frag").write_text(
                "// loose fragment\nvoid main() {}\n", encoding="utf-8"
            )

            (effects / "large.vert").write_text(
                "//" + ("x" * 530_000) + "\nvoid main() {}\n",
                encoding="utf-8",
            )
            (effects / "large.frag").write_text("void main() {}\n", encoding="utf-8")

            hidden_package = root / "hidden-package"
            hidden_loose = root / "hidden-loose/shaders/.hidden/effects"
            hidden_package.mkdir()
            hidden_loose.mkdir(parents=True)
            (hidden_loose / "foo.vert").write_text("void main() {}\n", encoding="utf-8")
            (hidden_loose / "foo.frag").write_text("void main() {}\n", encoding="utf-8")

            completed = subprocess.run(
                [str(self.binary), str(root)],
                cwd=REPO_ROOT,
                check=True,
                capture_output=True,
                text=True,
            )
            output = json.loads(completed.stdout)

            unsafe_root = base / "unsafe-wallpaper"
            unsafe_root.mkdir()
            (unsafe_root / "shaders").symlink_to(shaders, target_is_directory=True)
            unsafe_completed = subprocess.run(
                [str(self.binary), str(unsafe_root)],
                cwd=REPO_ROOT,
                check=True,
                capture_output=True,
                text=True,
            )
            unsafe_output = json.loads(unsafe_completed.stdout)

        contracts = output["contracts"]
        identities = [contract["identity"] for contract in contracts]
        self.assertEqual(identities, sorted(identities))
        self.assertEqual(len(identities), len(set(identities)))
        by_identity = {contract["identity"]: contract for contract in contracts}
        mixed = output["mixedContract"]
        self.assertEqual(self._diagnostic_codes(mixed), [])
        self.assertEqual(
            [stage["source"].splitlines()[0] for stage in mixed["stages"]],
            ["// loose vertex", "// loose fragment"],
        )
        self.assertEqual(
            {node["provenance"] for node in mixed["sourceGraph"]["nodes"]},
            {"package", "loose"},
        )
        package_vertex = output["packageVertexContract"]
        self.assertIn("missingFragmentStage", self._diagnostic_codes(package_vertex))
        self.assertEqual(
            [stage["source"].splitlines()[0] for stage in package_vertex["stages"]],
            ["// package vertex"],
        )
        self.assertEqual(output["largeRawStageCount"], 2)
        self.assertEqual(output["largeDiagnosticCodes"], [])
        self.assertTrue(output["largeGraphBudgetExceeded"])
        self.assertEqual(output["hiddenRawStageCount"], 0)
        self.assertEqual(output["hiddenGraphNodeCount"], 2)

        good = by_identity["effects/good"]
        self.assertEqual(good["sourceKind"], "authoredSource")
        self.assertEqual([stage["kind"] for stage in good["stages"]], ["vertex", "fragment"])
        vertex, fragment = good["stages"]
        self.assertEqual(vertex["relativePath"], "shaders/effects/good.vert")
        self.assertEqual(vertex["source"], vertex_source)
        self.assertEqual(fragment["source"], fragment_source)
        self.assertEqual(vertex["rawSHA256"], hashlib.sha256(vertex_bytes).hexdigest())
        self.assertEqual(fragment["rawSHA256"], hashlib.sha256(fragment_bytes).hexdigest())
        self.assertEqual(vertex["includes"], [{
            "line": 1,
            "raw": '#include "../headers/common.h"',
            "relativePath": "../headers/common.h",
        }])
        source_graph = good["sourceGraph"]
        self.assertEqual(
            [root["virtualPath"] for root in source_graph["roots"]],
            ["shaders/effects/good.frag", "shaders/effects/good.vert"],
        )
        nodes_by_path = {
            node["virtualPath"]: node for node in source_graph["nodes"]
        }
        self.assertEqual(
            set(nodes_by_path),
            {
                "shaders/effects/good.frag",
                "shaders/effects/good.vert",
                "shaders/headers/common.h",
            },
        )
        self.assertEqual(nodes_by_path["shaders/effects/good.vert"]["provenance"], "loose")
        self.assertEqual(
            nodes_by_path["shaders/headers/common.h"]["rawSHA256"],
            hashlib.sha256(b"#define COMMON 1\n").hexdigest(),
        )
        self.assertEqual(len(source_graph["edges"]), 3)
        self.assertRegex(source_graph["dependencySHA256"], re.compile(r"^[0-9a-f]{64}$"))

        vertex_declarations = {value["name"]: value for value in vertex["declarations"]}
        self.assertEqual(vertex_declarations["a_Position"]["kind"], "attribute")
        self.assertEqual(vertex_declarations["a_Position"]["type"], "highp vec3")
        self.assertEqual(vertex_declarations["g_AudioSpectrum64Right"]["arraySuffix"], "[64]")
        self.assertEqual(vertex_declarations["g_AudioSpectrum64Right"]["arraySize"], 64)
        self.assertEqual(vertex_declarations["g_AudioSpectrum64Right"]["line"], 4)
        self.assertEqual(vertex_declarations["v_TexCoord"]["kind"], "varying")
        self.assertEqual(vertex_declarations["v_TexCoord"]["arraySuffix"], "[4]")
        self.assertEqual(vertex_declarations["v_TexCoord"]["arraySize"], 4)

        self.assertEqual(vertex["annotations"][0]["marker"], "[COMBO]")
        self.assertEqual(vertex["annotations"][0]["line"], 7)
        self.assertTrue(vertex["annotations"][0]["raw"].startswith("// prefix [COMBO]"))
        self.assertEqual(vertex["annotations"][0]["value"]["options"], [0, 1])
        self.assertEqual(
            [annotation.get("marker") for annotation in fragment["annotations"]],
            ["[COMBO_OFF]", "OFF_COMBO", "[OFF_COMBO]", None, "[COMBO_DISABLED]", "[PASS]"],
        )
        self.assertEqual(fragment["annotations"][2]["value"]["meta"]["label"], "Tint Value")
        self.assertEqual(fragment["annotations"][3]["value"]["default"], [1, 0.5, 0, 1])
        # Stock assets spell the disabled-combo marker three ways; all three must round-trip
        # as structured payload, and [PASS] keeps its non-JSON operand verbatim.
        self.assertEqual(fragment["annotations"][4]["value"]["combo"], "DOUBLESIDED")
        self.assertEqual(fragment["annotations"][5]["value"], "shadow shadowcasterdemo")
        self.assertEqual(self._diagnostic_codes(good), ["duplicateIdentity"])

        self.assertIn("missingFragmentStage", self._diagnostic_codes(by_identity["effects/missing"]))
        self.assertIn("missingVertexStage", self._diagnostic_codes(by_identity["effects/fragonly"]))
        malformed = by_identity["effects/malformed"]
        self.assertIn("malformedAnnotation", self._diagnostic_codes(malformed))
        self.assertEqual(malformed["stages"][0]["annotations"], [])
        stageskip = by_identity["effects/stageskip"]
        self.assertEqual(
            self._diagnostic_codes(stageskip),
            ["malformedAnnotation"],
        )
        self.assertEqual(len(stageskip["stages"][0]["annotations"]), 1)
        self.assertEqual(stageskip["stages"][1]["annotations"], [])
        self.assertIn('"options":{Color:0', stageskip["stages"][1]["source"])
        malformedforms = by_identity["effects/malformedforms"]
        self.assertEqual(
            self._diagnostic_codes(malformedforms),
            ["malformedAnnotation", "malformedAnnotation", "malformedAnnotation"],
        )
        self.assertEqual(malformedforms["stages"][0]["annotations"], [])
        legacynumber = by_identity["effects/legacynumber"]
        self.assertEqual(self._diagnostic_codes(legacynumber), [])
        legacy_vertex = legacynumber["stages"][0]
        self.assertEqual(legacy_vertex["annotations"][0]["value"]["range"], [0, 1])
        self.assertIn('"range":[0,01]', legacy_vertex["annotations"][0]["raw"])
        self.assertEqual(legacy_vertex["annotations"][1]["value"]["default"], "01")
        malformednumeric = by_identity["effects/malformednumeric"]
        self.assertEqual(
            self._diagnostic_codes(malformednumeric),
            ["malformedAnnotation"] * 4,
        )
        self.assertEqual(malformednumeric["stages"][0]["annotations"], [])
        legacyoversized = by_identity["effects/legacyoversized"]
        self.assertEqual(
            self._diagnostic_codes(legacyoversized),
            ["malformedAnnotation"],
        )
        self.assertEqual(legacyoversized["stages"][0]["annotations"], [])
        prosemarker = by_identity["effects/prosemarker"]
        self.assertEqual(self._diagnostic_codes(prosemarker), [])
        self.assertEqual(len(prosemarker["stages"][0]["annotations"]), 1)
        self.assertEqual(prosemarker["stages"][0]["annotations"][0]["marker"], "[COMBO]")
        self.assertEqual(prosemarker["stages"][0]["annotations"][0]["line"], 1)
        self.assertEqual(prosemarker["stages"][1]["annotations"], [])
        self.assertIn("invalidUTF8", self._diagnostic_codes(by_identity["effects/invalid"]))
        self.assertIn("unreadableSource", self._diagnostic_codes(by_identity["effects/unreadable"]))
        self.assertIn("symlinkEscape", self._diagnostic_codes(by_identity["effects/symlink"]))
        self.assertIn("pathEscape", self._diagnostic_codes(by_identity["effects/includeescape"]))
        self.assertIn("symlinkEscape", self._diagnostic_codes(by_identity["effects/includesymlink"]))
        self.assertEqual(self._diagnostic_codes(by_identity["../outside/escape"]), ["pathEscape"])
        self.assertEqual(self._diagnostic_codes(by_identity["<empty>"]), ["invalidReference"])

        for identity in ("genericimage2", "genericimage4", "genericparticle"):
            contract = by_identity[identity]
            self.assertEqual(contract["sourceKind"], "hostBuiltin")
            self.assertEqual(contract["stages"], [])
            self.assertEqual(contract["diagnostics"], [])
        nested_builtin_name = by_identity["foo/genericimage2"]
        self.assertEqual(nested_builtin_name["sourceKind"], "authoredSource")
        self.assertEqual(
            set(self._diagnostic_codes(nested_builtin_name)),
            {"missingVertexStage", "missingFragmentStage"},
        )
        unsafe_good = {
            contract["identity"]: contract for contract in unsafe_output["contracts"]
        }["effects/good"]
        self.assertEqual(unsafe_good["stages"], [])
        self.assertIn("symlinkEscape", self._diagnostic_codes(unsafe_good))

        self.assertTrue(output["roundTripEqual"])
        canonical_by_identity = {
            contract["identity"]: contract["canonicalSHA256"] for contract in contracts
        }
        self.assertEqual(output["reversedCanonical"], canonical_by_identity)
        dependency_by_identity = {
            contract["identity"]: contract["sourceGraph"]["dependencySHA256"]
            for contract in contracts
            if contract.get("sourceGraph") is not None
        }
        self.assertEqual(output["reversedDependency"], dependency_by_identity)
        for canonical in canonical_by_identity.values():
            self.assertRegex(canonical, re.compile(r"^[0-9a-f]{64}$"))
        self.assertNotEqual(good["canonicalSHA256"], vertex["rawSHA256"])
        self.assertNotEqual(good["canonicalSHA256"], fragment["rawSHA256"])

    @staticmethod
    def _diagnostic_codes(contract):
        return [diagnostic["code"] for diagnostic in contract["diagnostics"]]


if __name__ == "__main__":
    unittest.main()
