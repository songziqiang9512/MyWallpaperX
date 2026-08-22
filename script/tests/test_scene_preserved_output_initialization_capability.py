#!/usr/bin/env python3

from __future__ import annotations

import json
import os
from pathlib import Path
import runpy
import subprocess
import tempfile
import unittest


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
CAPABILITY_FIXTURE = runpy.run_path(
    str(
        REPOSITORY_ROOT
        / "script/tests/test_scene_resolved_material_execution_capability.py"
    )
)
SWIFT_SOURCES = CAPABILITY_FIXTURE["ENVELOPE_SWIFT_SOURCES"]
SUPPORT = CAPABILITY_FIXTURE["ENVELOPE_SUPPORT"]
BASE_HARNESS = CAPABILITY_FIXTURE["ENVELOPE_HARNESS"]
HARNESS_ANCHOR = "@main\nprivate enum EnvelopeHarness"
HARNESS_PREFIX, anchor, _ = BASE_HARNESS.partition(HARNESS_ANCHOR)
if anchor != HARNESS_ANCHOR:
    raise RuntimeError("preserved-output fixture anchor changed")


HARNESS = HARNESS_PREFIX + r'''
private func outputInitializationContract(
    _ revision: String,
    body: String
) -> SceneShaderContract {
    func stage(
        _ kind: SceneShaderContract.StageKind,
        path: String,
        source: String
    ) -> SceneShaderContract.Stage {
        let parsed = SceneShaderContractSourceParser().parse(
            source,
            stageRelativePath: path
        )
        return .init(
            kind: kind,
            relativePath: path,
            source: source,
            rawSHA256: SceneShaderStableDigest.hash(Data(source.utf8)),
            includes: parsed.includes,
            annotations: parsed.annotations,
            declarations: parsed.declarations
        )
    }
    let fragment = """
    varying vec2 v_TexCoord;
    uniform sampler2D g_Texture0;
    uniform float g_Gain;
    uniform vec2 g_Offset;
    void main() {
        \(body)
    }
    """
    let stages = [
        stage(
            .vertex,
            path: "\(revision)/root.vert",
            source: vertexSource()
        ),
        stage(
            .fragment,
            path: "\(revision)/root.frag",
            source: fragment
        ),
    ]
    return .init(
        identity: "fixture/\(revision)",
        sourceKind: .authoredSource,
        stages: stages,
        diagnostics: [],
        canonicalSHA256: "fixture-contract-\(revision)",
        sourceGraph: .init(
            roots: [
                .init(label: "vertex", virtualPath: "\(revision)/root.vert"),
                .init(label: "fragment", virtualPath: "\(revision)/root.frag"),
            ],
            nodes: stages.map {
                .init(
                    virtualPath: $0.relativePath,
                    provenance: .package,
                    source: $0.source,
                    rawSHA256: $0.rawSHA256,
                    byteCount: $0.source.utf8.count
                )
            },
            edges: [],
            diagnostics: [],
            dependencySHA256: "fixture-dependency-\(revision)"
        )
    )
}

private func preservedOutputEnvelopeToken(
    _ body: String,
    revision: String
) -> String {
    let fixtureGraph = graph(withPrimaryBinding: true)
    let template = materialTemplate(
        graph: fixtureGraph,
        shader: outputInitializationContract(revision, body: body),
        slots: slots(primary: graphCandidate())
    )
    let cache: SceneResolvedMaterialVariantCache
    switch SceneResolvedMaterialVariantCache.launchValidated(
        template: template,
        maximumVariantCount: 16
    ) {
    case let .success(value): cache = value
    case let .failure(failure): return materialFailureToken(failure)
    }
    switch cache.precompileLaunchEnvelope(
        implicitFramebufferIdentity: source(),
        outputStorage: .redGreenFloat16
    ) {
    case .success: return "success"
    case .failure(.capacity): return "capacity"
    case let .failure(.material(failure)):
        return materialFailureToken(failure)
    }
}

@main
private enum PreservedOutputInitializationHarness {
    static func main() throws {
        setenv("MWX_SCENE_GENERIC_SHADER_ROUTE", "disable-generic", 1)
        let result = [
            "wholeThenXYCompound": preservedOutputEnvelopeToken("""
                vec4 initialized = texSample2D(g_Texture0, v_TexCoord);
                gl_FragColor = initialized;
                gl_FragColor.xy += g_Offset;
                """, revision: "whole-then-xy-compound"),
            "unseenWholeThenConditionalRG": preservedOutputEnvelopeToken("""
                gl_FragColor = vec4(0.25, 0.5, 0.75, 1.0);
                if (g_Gain > 0.0) { gl_FragColor.r *= g_Gain; }
                gl_FragColor.g = g_Offset.y;
                """, revision: "unseen-whole-then-conditional-rg"),
            "componentBeforeWhole": preservedOutputEnvelopeToken("""
                gl_FragColor.xy += g_Offset;
                gl_FragColor = vec4(0.5);
                """, revision: "component-before-whole"),
            "componentOnly": preservedOutputEnvelopeToken(
                "gl_FragColor.r = g_Gain;",
                revision: "component-only"
            ),
            "secondWholeWrite": preservedOutputEnvelopeToken("""
                gl_FragColor = vec4(0.25);
                gl_FragColor = vec4(0.5);
                """, revision: "second-whole-write"),
            "laterReadOutsideMutation": preservedOutputEnvelopeToken("""
                gl_FragColor = vec4(0.25);
                float copy = gl_FragColor.r;
                gl_FragColor.r = copy;
                """, revision: "later-read-outside-mutation"),
            "blueMutationOutsideProfile": preservedOutputEnvelopeToken("""
                gl_FragColor = vec4(0.25);
                gl_FragColor.b += g_Gain;
                """, revision: "blue-mutation-outside-profile"),
            "conditionalInitialization": preservedOutputEnvelopeToken("""
                if (g_Gain > 0.0) { gl_FragColor = vec4(0.25); }
                gl_FragColor.r += g_Gain;
                """, revision: "conditional-initialization"),
            "earlyReturn": preservedOutputEnvelopeToken("""
                gl_FragColor = vec4(0.25);
                if (g_Gain < 0.0) { return; }
                gl_FragColor.r += g_Gain;
                """, revision: "early-return"),
        ]
        let data = try JSONSerialization.data(
            withJSONObject: result,
            options: [.sortedKeys]
        )
        FileHandle.standardOutput.write(data)
    }
}
'''


class ScenePreservedOutputInitializationCapabilityTests(unittest.TestCase):
    def test_launch_envelope_uses_dominating_source_fact(self) -> None:
        with tempfile.TemporaryDirectory(
            prefix="mwx-preserved-output-capability-"
        ) as temporary:
            root = Path(temporary)
            support = root / "Support.swift"
            harness = root / "Harness.swift"
            binary = root / "preserved-output-capability"
            support.write_text(SUPPORT, encoding="utf-8")
            harness.write_text(HARNESS, encoding="utf-8")
            environment = os.environ.copy()
            environment["CLANG_MODULE_CACHE_PATH"] = str(root / "clang-cache")
            environment["SWIFT_MODULECACHE_PATH"] = str(root / "swift-cache")
            compilation = subprocess.run(
                [
                    "xcrun",
                    "--sdk",
                    "macosx",
                    "swiftc",
                    *(str(path) for path in SWIFT_SOURCES),
                    str(support),
                    str(harness),
                    "-o",
                    str(binary),
                ],
                cwd=REPOSITORY_ROOT,
                env=environment,
                capture_output=True,
                text=True,
            )
            self.assertEqual(compilation.returncode, 0, compilation.stderr)
            completed = subprocess.run(
                [str(binary)],
                cwd=REPOSITORY_ROOT,
                env=environment,
                check=True,
                capture_output=True,
                text=True,
            )
            result = json.loads(completed.stdout)

        self.assertEqual(result["wholeThenXYCompound"], "success")
        self.assertEqual(result["unseenWholeThenConditionalRG"], "success")
        for key in (
            "componentBeforeWhole",
            "componentOnly",
            "secondWholeWrite",
            "laterReadOutsideMutation",
            "blueMutationOutsideProfile",
            "conditionalInitialization",
            "earlyReturn",
        ):
            with self.subTest(key=key):
                self.assertIn("color:colorContractUnproven", result[key])
                self.assertIn("scalar-output-channel-unproven", result[key])


if __name__ == "__main__":
    unittest.main()
