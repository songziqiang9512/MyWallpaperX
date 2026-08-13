#!/usr/bin/env python3

import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import textwrap
import unittest


REPO_ROOT = Path(__file__).resolve().parents[2]
SCENE_ROOT = REPO_ROOT / "MyWallpaperX/Core/SteamWorkshopScene"
SWIFT_SOURCES = [
    SCENE_ROOT / "Format/SceneJSONValue.swift",
    SCENE_ROOT / "RenderGraph/ShaderContract/SceneShaderSourceGraph.swift",
    SCENE_ROOT / "RenderGraph/ShaderContract/SceneShaderContract.swift",
    SCENE_ROOT / "Resources/SceneShaderSourceGraphBuilder.swift",
    SCENE_ROOT / "Resources/SceneShaderSourceResolver.swift",
    SCENE_ROOT / "Resources/SceneResourceView.swift",
    SCENE_ROOT / "Resources/SceneResourceIndex.swift",
    SCENE_ROOT / "RenderGraph/ShaderContract/SceneShaderContractLoader.swift",
    SCENE_ROOT / "RenderGraph/ShaderContract/SceneShaderContractLoader+SourceGraph.swift",
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
}

@main
private struct ShaderContractHarness {
    static func main() throws {
        let rootURL = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let references = [
            "effects/good",
            "effects/good.vert",
            "effects/missing",
            "effects/fragonly",
            "effects/malformed",
            "effects/stageskip",
            "effects/malformedforms",
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
        let contracts = loader.load(shaderReferences: references, rootURL: rootURL)
        let reversed = loader.load(shaderReferences: references.reversed(), rootURL: rootURL)
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
        let mixedContract = loader.load(
            shaderReferences: ["effects/mixed"],
            resourceView: SceneResourceView(
                projectRootURL: rootURL.appendingPathComponent("mixed-loose"),
                packageRootURL: rootURL.appendingPathComponent("mixed-package"),
                stockAssetsRootURL: nil
            )
        ).first
        let packageVertexContract = loader.load(
            shaderReferences: ["effects/packagevertex"],
            resourceView: SceneResourceView(
                projectRootURL: rootURL.appendingPathComponent("mixed-loose"),
                packageRootURL: rootURL.appendingPathComponent("mixed-package"),
                stockAssetsRootURL: nil
            )
        ).first
        let large = loader.load(
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
        let hidden = loader.load(
            shaderReferences: [".hidden/effects/foo"],
            resourceView: SceneResourceView(
                projectRootURL: rootURL.appendingPathComponent("hidden-loose"),
                packageRootURL: rootURL.appendingPathComponent("hidden-package"),
                stockAssetsRootURL: nil
            )
        ).first
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
            roundTripEqual: decodedContracts == contracts
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
                '// [COMBO] {"range":[0,01]}\n',
                encoding="utf-8",
            )
            (effects / "malformedforms.frag").write_text(
                "void main() {}\n", encoding="utf-8"
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
