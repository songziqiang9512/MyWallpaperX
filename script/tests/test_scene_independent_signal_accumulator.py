#!/usr/bin/env python3
"""Source-proven affine independent-signal accumulator contract."""

from __future__ import annotations

import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
SCENE_ROOT = REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene"
STOCK_ROOT = (
    REPOSITORY_ROOT
    / "MyWallpaperX/Resources/SceneStockAssets.bundle/assets/effects/shine"
)
sys.path.insert(0, str(REPOSITORY_ROOT / "script"))

from scene_swift_source_sets import scene_swift_sources  # noqa: E402


def unique_sources(*groups: tuple[Path, ...] | list[Path]) -> list[Path]:
    result: list[Path] = []
    seen: set[Path] = set()
    for group in groups:
        for source in group:
            if source not in seen:
                seen.add(source)
                result.append(source)
    return result


PREPROCESSOR_SOURCES = [
    SCENE_ROOT / "Format/SceneJSONValue.swift",
    SCENE_ROOT / "Resources/SceneResourceIndex.swift",
    SCENE_ROOT / "Resources/SceneResourceView.swift",
    SCENE_ROOT / "RenderGraph/ShaderContract/SceneShaderSourceGraph.swift",
    SCENE_ROOT / "RenderGraph/ShaderContract/SceneShaderLegacyAnnotationJSON.swift",
    SCENE_ROOT / "RenderGraph/ShaderContract/SceneShaderContract.swift",
    SCENE_ROOT / "Resources/SceneTextureSampling.swift",
    *scene_swift_sources("shader_preprocessing_and_variant_implementation"),
    SCENE_ROOT / "Resources/SceneShaderSourceResolver.swift",
    SCENE_ROOT / "Resources/SceneShaderSourceGraphBuilder.swift",
]
ANALYZER = (
    SCENE_ROOT
    / "RenderGraph/ShaderFrontend/SceneAuthoredShaderIndependentSignalAccumulatorAnalyzer.swift"
)
SWIFT_SOURCES = unique_sources(
    tuple(PREPROCESSOR_SOURCES),
    scene_swift_sources("authored_shader_frontend_core"),
    (ANALYZER,),
)


HARNESS = r'''
import Foundation

private struct Output: Codable {
    let actualWasPreprocessed: Bool
    let actualLoopWork: Int?
    let inlineWasPreprocessed: Bool
    let inlineLoopWork: Int?
    let structuralLoopWork: Int?
    let oversizedLoopWork: Int?
    let positive: [String: String]
    let negative: [String: String]
    let inlinePositive: [String: String]
    let inlineNegative: [String: String]
}

private func transfer(_ source: String) -> String {
    switch SceneAuthoredShaderIndependentSignalAccumulatorAnalyzer.analyze(
        fragmentSource: source
    ) {
    case let .independentAlphaSignalPreserving(slot):
        return "signal-preserving:\(slot)"
    case nil:
        return "nil"
    default:
        return "other"
    }
}

private func fixture(
    helper: String = "gatherRay",
    helperAccumulator: String = "sum",
    sample: String = "tap",
    loopIndex: String = "index",
    bound: String = "sampleCount",
    denominator: String = "sampleDrop",
    rootAccumulator: String = "result",
    normalization: String = "normalization",
    gain: String = "g_Gain",
    tint: String = "g_Tint",
    alphaClamp: String = "saturate"
) -> String {
    """
    uniform sampler2D g_Texture0;
    uniform float \(gain);
    uniform vec3 \(tint);
    varying vec4 v_TexCoord01;
    varying vec4 v_TexCoord23;

    vec4 \(helper)(vec2 coordinate, vec2 direction) {
        vec4 \(helperAccumulator) = CAST4(0.0);
        const int \(bound) = 8;
        float distanceValue = length(direction);
        direction /= distanceValue;
        distanceValue *= 0.25;
        coordinate += direction * distanceValue;
        const float \(denominator) = \(bound) - 1;
        direction = direction * distanceValue / \(denominator);
        for (int \(loopIndex) = 0; \(loopIndex) < \(bound); ++\(loopIndex)) {
            vec4 \(sample) = texSample2D(g_Texture0, coordinate);
            coordinate -= direction;
            \(helperAccumulator) += \(sample) * (\(loopIndex) / \(denominator));
        }
        return \(helperAccumulator);
    }

    void main() {
        vec2 coordinate = v_TexCoord01.xy;
        vec4 \(rootAccumulator) = CAST4(0.0);
        \(rootAccumulator) += \(helper)(coordinate, v_TexCoord01.zw);
        \(rootAccumulator) += \(helper)(coordinate, v_TexCoord23.xy);
        const float \(normalization) = 0.1 * (30 / 8.0);
        \(rootAccumulator).rgb *= \(tint);
        gl_FragColor = vec4(
            \(gain) * \(normalization) * \(rootAccumulator).rgb,
            \(alphaClamp)(\(gain) * \(normalization) * \(rootAccumulator).a)
        );
    }
    """
}

private func preparedCast(stockRoot: URL) throws -> String {
    let path = "shaders/effects/shine_cast.frag"
    let globalStockRoot = stockRoot
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let view = SceneResourceView(
        projectRootURL: stockRoot,
        packageRootURL: nil,
        stockAssetsRootURL: globalStockRoot
    )
    let graph = SceneShaderSourceGraphBuilder().build(
        roots: [.init(label: "fragment", virtualPath: path)],
        resourceView: view
    )
    let environment = try SceneShaderVariantEnvironment(
        stage: .fragment,
        combos: [
            .init(name: "SAMPLES", definition: .defined(.integer(1))),
            .init(name: "EDGES", definition: .defined(.integer(4))),
        ]
    )
    switch SceneShaderPreprocessor().preprocess(
        rootRelativePath: path,
        graph: graph,
        environment: environment
    ) {
    case let .success(prepared):
        return prepared.source
    case let .failure(failure):
        throw NSError(
            domain: "prepared-shine-cast",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "\(failure.diagnostics)"]
        )
    }
}

private func preparedInlineCast(stockRoot: URL) throws -> String {
    let path = "shaders/effects/godrays_cast.frag"
    let globalStockRoot = stockRoot
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let view = SceneResourceView(
        projectRootURL: stockRoot,
        packageRootURL: nil,
        stockAssetsRootURL: globalStockRoot
    )
    let graph = SceneShaderSourceGraphBuilder().build(
        roots: [.init(label: "fragment", virtualPath: path)],
        resourceView: view
    )
    let environment = try SceneShaderVariantEnvironment(
        stage: .fragment,
        combos: [
            .init(name: "CASTER", definition: .defined(.integer(0))),
            .init(name: "SAMPLES", definition: .defined(.integer(0))),
        ]
    )
    switch SceneShaderPreprocessor().preprocess(
        rootRelativePath: path,
        graph: graph,
        environment: environment
    ) {
    case let .success(prepared):
        return prepared.source
    case let .failure(failure):
        throw NSError(
            domain: "prepared-godrays-cast",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "\(failure.diagnostics)"]
        )
    }
}

private func inlineFixture(
    accumulator: String = "signal",
    sample: String = "tap",
    loopIndex: String = "ordinal",
    bound: String = "tapCount",
    denominator: String = "tapDrop",
    gain: String = "g_Gain",
    tint: String = "g_Tint"
) -> String {
    """
    uniform sampler2D g_Texture0;
    uniform float \(gain);
    uniform vec3 \(tint);
    varying vec2 v_TexCoord;

    void main() {
        vec2 coordinate = v_TexCoord;
        vec2 direction = vec2(0.25, 0.5);
        vec4 \(accumulator) = CAST4(0.0);
        const int \(bound) = 8;
        const float \(denominator) = \(bound) - 1;
        direction /= \(denominator);
        for (int \(loopIndex) = 0; \(loopIndex) < \(bound); ++\(loopIndex)) {
            vec4 \(sample) = texSample2D(g_Texture0, coordinate);
            coordinate -= direction;
            \(accumulator) += \(sample) * (\(loopIndex) / \(denominator));
        }
        const float sharedScale = 0.1;
        \(accumulator).rgb *= \(tint);
        gl_FragColor = vec4(
            \(gain) * sharedScale * \(accumulator).rgb,
            saturate(\(gain) * sharedScale * \(accumulator).a)
        );
    }
    """
}

@main
enum Harness {
    static func main() throws {
        let stockRoot = URL(
            fileURLWithPath: CommandLine.arguments[1],
            isDirectory: true
        )
        let actual = try preparedCast(stockRoot: stockRoot)
        let godraysRoot = stockRoot.deletingLastPathComponent()
            .appendingPathComponent("godrays", isDirectory: true)
        let actualInline = try preparedInlineCast(stockRoot: godraysRoot)
        let structural = fixture()
        let renamed = fixture(
            helper: "collectDirection",
            helperAccumulator: "weightedSignal",
            sample: "sourceValue",
            loopIndex: "ordinal",
            bound: "tapLimit",
            denominator: "positiveDivisor",
            rootAccumulator: "combinedSignal",
            normalization: "sharedScale",
            gain: "g_SharedGain",
            tint: "g_RGBTint"
        )
        let clampEquivalent = fixture(alphaClamp: "clamp").replacingOccurrences(
            of: "clamp(g_Gain * normalization * result.a)",
            with: "clamp(g_Gain * normalization * result.a, 0.0, 1.0)"
        )

        let differentSlot = structural
            .replacingOccurrences(
                of: "uniform sampler2D g_Texture0;",
                with: "uniform sampler2D g_Texture0;\nuniform sampler2D g_Texture1;"
            )
            .replacingOccurrences(
                of: "coordinate -= direction;",
                with: "vec4 foreignTap = texSample2D(g_Texture1, coordinate);\ncoordinate -= direction;"
            )
        let secondWholeSampler = structural.replacingOccurrences(
            of: "coordinate -= direction;",
            with: "vec4 duplicateTap = texSample2D(g_Texture0, coordinate);\ncoordinate -= direction;"
        )
        let negativeWeight = structural.replacingOccurrences(
            of: "tap * (index / sampleDrop)",
            with: "tap * (-index / sampleDrop)"
        )
        let subtraction = structural.replacingOccurrences(
            of: "sum += tap * (index / sampleDrop)",
            with: "sum -= tap * (index / sampleDrop)"
        )
        let nonStaticLoop = structural
            .replacingOccurrences(
                of: "uniform float g_Gain;",
                with: "uniform float g_Gain;\nuniform int g_RuntimeCount;"
            )
            .replacingOccurrences(of: "const int sampleCount = 8;", with: "")
            .replacingOccurrences(of: "sampleCount", with: "g_RuntimeCount")
        let oversizedLoop = structural.replacingOccurrences(
            of: "const int sampleCount = 8;",
            with: "const int sampleCount = 65;"
        )
        let helperEscape = structural
            .replacingOccurrences(
                of: "vec4 gatherRay(vec2 coordinate, vec2 direction) {",
                with: "void mutate(inout vec4 value) { value = vec4(0.0); }\n"
                    + "vec4 gatherRay(vec2 coordinate, vec2 direction) {"
            )
            .replacingOccurrences(
                of: "coordinate -= direction;",
                with: "mutate(tap);\ncoordinate -= direction;"
            )
        let differentRGBSource = structural
            .replacingOccurrences(
                of: "uniform vec3 g_Tint;",
                with: "uniform vec3 g_Tint;\nuniform vec3 g_OtherRGB;"
            )
            .replacingOccurrences(
                of: "g_Gain * normalization * result.rgb",
                with: "g_Gain * normalization * g_OtherRGB"
            )
        let differentAlphaSource = structural
            .replacingOccurrences(
                of: "uniform float g_Gain;",
                with: "uniform float g_Gain;\nuniform float g_OtherAlpha;"
            )
            .replacingOccurrences(
                of: "g_Gain * normalization * result.a",
                with: "g_Gain * normalization * g_OtherAlpha"
            )
        let inconsistentScale = structural
            .replacingOccurrences(
                of: "uniform float g_Gain;",
                with: "uniform float g_Gain;\nuniform float g_AlphaGain;"
            )
            .replacingOccurrences(
                of: "saturate(g_Gain * normalization * result.a)",
                with: "saturate(g_AlphaGain * normalization * result.a)"
            )
        let unclampedAlpha = structural.replacingOccurrences(
            of: "saturate(g_Gain * normalization * result.a)",
            with: "g_Gain * normalization * result.a"
        )
        let inline = inlineFixture()
        let renamedInline = inlineFixture(
            accumulator: "weightedRGBA",
            sample: "sourceValue",
            loopIndex: "index",
            bound: "sampleCount",
            denominator: "sampleDrop",
            gain: "g_Intensity",
            tint: "g_ColorRays"
        )
        let inlineSecondSampler = inline
            .replacingOccurrences(
                of: "uniform sampler2D g_Texture0;",
                with: "uniform sampler2D g_Texture0;\nuniform sampler2D g_Texture1;"
            )
            .replacingOccurrences(
                of: "coordinate -= direction;",
                with: "vec4 hidden = texSample2D(g_Texture1, coordinate);\n"
                    + "coordinate -= direction;"
            )
        let inlineNegativeWeight = inline.replacingOccurrences(
            of: "tap * (ordinal / tapDrop)",
            with: "tap * (-ordinal / tapDrop)"
        )
        let inlineDynamicLoop = inline
            .replacingOccurrences(
                of: "uniform float g_Gain;",
                with: "uniform float g_Gain;\nuniform int g_RuntimeCount;"
            )
            .replacingOccurrences(of: "const int tapCount = 8;", with: "")
            .replacingOccurrences(of: "tapCount", with: "g_RuntimeCount")
        let inlineDifferentAlpha = inline
            .replacingOccurrences(
                of: "uniform float g_Gain;",
                with: "uniform float g_Gain;\nuniform float g_AlphaGain;"
            )
            .replacingOccurrences(
                of: "saturate(g_Gain * sharedScale * signal.a)",
                with: "saturate(g_AlphaGain * sharedScale * signal.a)"
            )
        let inlineUnclampedAlpha = inline.replacingOccurrences(
            of: "saturate(g_Gain * sharedScale * signal.a)",
            with: "g_Gain * sharedScale * signal.a"
        )
        let inlineBranch = inline.replacingOccurrences(
            of: "signal.rgb *= g_Tint;",
            with: "if (g_Gain > 0.0) { signal.rgb *= g_Tint; }"
        )
        let inlineDynamicHelperLoop = inline
            .replacingOccurrences(
                of: "void main() {",
                with: """
                vec2 resolveCoordinate(vec2 value, int limit) {
                    int index = 0;
                    while (index < limit) {
                        value.x += 0.0;
                        ++index;
                    }
                    return value;
                }
                void main() {
                """
            )
            .replacingOccurrences(
                of: "texSample2D(g_Texture0, coordinate)",
                with: "texSample2D(g_Texture0, resolveCoordinate(coordinate, int(g_Gain)))"
            )
        let inlineNegativeScale = inline.replacingOccurrences(
            of: "const float sharedScale = 0.1;",
            with: "const float sharedScale = -0.1;"
        )

        let output = Output(
            actualWasPreprocessed: !actual.contains("#if")
                && !actual.contains("#endif")
                && actual.contains("GatherDirection"),
            actualLoopWork:
                SceneAuthoredShaderIndependentSignalAccumulatorAnalyzer
                    .staticLoopWork(fragmentSource: actual),
            inlineWasPreprocessed: !actualInline.contains("#if")
                && !actualInline.contains("#endif")
                && actualInline.contains("sampleCount"),
            inlineLoopWork:
                SceneAuthoredShaderIndependentSignalAccumulatorAnalyzer
                    .staticLoopWork(fragmentSource: actualInline),
            structuralLoopWork:
                SceneAuthoredShaderIndependentSignalAccumulatorAnalyzer
                    .staticLoopWork(fragmentSource: structural),
            oversizedLoopWork:
                SceneAuthoredShaderIndependentSignalAccumulatorAnalyzer
                    .staticLoopWork(fragmentSource: oversizedLoop),
            positive: [
                "actual": transfer(actual),
                "structural": transfer(structural),
                "renamed": transfer(renamed),
                "clampEquivalent": transfer(clampEquivalent),
            ],
            negative: [
                "differentSlot": transfer(differentSlot),
                "secondWholeSampler": transfer(secondWholeSampler),
                "negativeWeight": transfer(negativeWeight),
                "subtraction": transfer(subtraction),
                "nonStaticLoop": transfer(nonStaticLoop),
                "oversizedLoop": transfer(oversizedLoop),
                "helperEscape": transfer(helperEscape),
                "differentRGBSource": transfer(differentRGBSource),
                "differentAlphaSource": transfer(differentAlphaSource),
                "inconsistentScale": transfer(inconsistentScale),
                "unclampedAlpha": transfer(unclampedAlpha),
            ],
            inlinePositive: [
                "actual": transfer(actualInline),
                "structural": transfer(inline),
                "renamed": transfer(renamedInline),
            ],
            inlineNegative: [
                "secondSampler": transfer(inlineSecondSampler),
                "negativeWeight": transfer(inlineNegativeWeight),
                "dynamicLoop": transfer(inlineDynamicLoop),
                "differentAlpha": transfer(inlineDifferentAlpha),
                "unclampedAlpha": transfer(inlineUnclampedAlpha),
                "branch": transfer(inlineBranch),
                "dynamicHelperLoop": transfer(inlineDynamicHelperLoop),
                "negativeScale": transfer(inlineNegativeScale),
            ]
        )
        FileHandle.standardOutput.write(try JSONEncoder().encode(output))
    }
}
'''


class SceneIndependentSignalAccumulatorTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        swiftc = shutil.which("swiftc")
        if swiftc is None:
            raise unittest.SkipTest("swiftc is unavailable")
        cls.temporary = tempfile.TemporaryDirectory(
            prefix="mwx-independent-signal-accumulator-"
        )
        root = Path(cls.temporary.name)
        harness = root / "main.swift"
        harness.write_text(HARNESS, encoding="utf-8")
        binary = root / "independent-signal-accumulator"
        environment = os.environ.copy()
        environment["CLANG_MODULE_CACHE_PATH"] = str(root / "clang-modules")
        environment["SWIFT_MODULECACHE_PATH"] = str(root / "swift-modules")
        compiled = subprocess.run(
            [
                swiftc,
                "-parse-as-library",
                *map(str, SWIFT_SOURCES),
                str(harness),
                "-o",
                str(binary),
            ],
            cwd=REPOSITORY_ROOT,
            env=environment,
            check=False,
            capture_output=True,
            text=True,
            timeout=240,
        )
        if compiled.returncode != 0:
            raise AssertionError(compiled.stderr)
        completed = subprocess.run(
            [str(binary), str(STOCK_ROOT)],
            cwd=REPOSITORY_ROOT,
            env=environment,
            check=True,
            capture_output=True,
            text=True,
            timeout=60,
        )
        cls.output = json.loads(completed.stdout)

    @classmethod
    def tearDownClass(cls) -> None:
        if hasattr(cls, "temporary"):
            cls.temporary.cleanup()

    def test_actual_and_structural_equivalents_are_signal_preserving(self) -> None:
        self.assertTrue(self.output["actualWasPreprocessed"])
        self.assertEqual(self.output["actualLoopWork"], 32)
        self.assertEqual(self.output["structuralLoopWork"], 16)
        self.assertIsNone(self.output.get("oversizedLoopWork"))
        self.assertEqual(
            self.output["positive"],
            {
                "actual": "signal-preserving:0",
                "structural": "signal-preserving:0",
                "renamed": "signal-preserving:0",
                "clampEquivalent": "signal-preserving:0",
            },
        )

    def test_unsafe_or_ambiguous_accumulators_fail_closed(self) -> None:
        self.assertEqual(
            self.output["negative"],
            {key: "nil" for key in self.output["negative"]},
        )

    def test_actual_and_renamed_inline_accumulators_are_signal_preserving(self) -> None:
        self.assertTrue(self.output["inlineWasPreprocessed"])
        self.assertEqual(self.output["inlineLoopWork"], 30)
        self.assertEqual(
            self.output["inlinePositive"],
            {
                "actual": "signal-preserving:0",
                "structural": "signal-preserving:0",
                "renamed": "signal-preserving:0",
            },
        )

    def test_unsafe_or_ambiguous_inline_accumulators_fail_closed(self) -> None:
        self.assertEqual(
            self.output["inlineNegative"],
            {key: "nil" for key in self.output["inlineNegative"]},
        )


if __name__ == "__main__":
    unittest.main()
