#!/usr/bin/env python3

"""Real stock Standard Blur unit-composite default eligibility."""

from __future__ import annotations

import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
SCENE_ROOT = REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene"
STOCK_ROOT = (
    REPOSITORY_ROOT / "MyWallpaperX/Resources/SceneStockAssets.bundle/assets"
)
sys.path.insert(0, str(REPOSITORY_ROOT / "script"))

from scene_swift_source_sets import scene_swift_sources


SWIFT_SOURCES = list(dict.fromkeys([
    *scene_swift_sources("shader_contract_resource_resolution"),
    *scene_swift_sources("authored_shader_frontend_core"),
    *scene_swift_sources("authored_shader_preparation_implementation"),
    SCENE_ROOT / "Resources/SceneTextureSampling.swift",
    SCENE_ROOT / "RenderGraph/AuthoredGraph/SceneAuthoredEffectRenderPlan.swift",
    SCENE_ROOT
    / "RenderGraph/MaterialProgram/SceneResolvedMaterialShaderSchema.swift",
    SCENE_ROOT
    / "RenderGraph/MaterialProgram/SceneResolvedMaterialUnitPreviousBlurredCompositeEligibility.swift",
    SCENE_ROOT
    / "RenderGraph/MaterialProgram/SceneResolvedMaterialGenericShaderProgramArtifact.swift",
    *scene_swift_sources("generic_shader_compiler_preparation_implementation"),
]))

GLSLANG = REPOSITORY_ROOT / "MyWallpaperX/Resources/SceneShaderCompilerTools/glslang"
SPIRV_CROSS = (
    REPOSITORY_ROOT / "MyWallpaperX/Resources/SceneShaderCompilerTools/spirv-cross"
)


SUPPORT = r'''
import Foundation

nonisolated enum SceneEffectStageCompilerBackend { case authoredShader }
nonisolated struct SceneEffectStageCompilerFailure {
    enum Phase: String { case shaderPreprocessor = "shader-preprocessor"; case invariant }
    enum Code: String {
        case shaderStageMissing = "shader-stage-missing"
        case shaderSourceGraphMissing = "shader-source-graph-missing"
        case shaderSourceIdentityMismatch = "shader-source-identity-mismatch"
        case shaderVariantInvalid = "shader-variant-invalid"
        case shaderIncludeMissing = "shader-include-missing"
        case shaderIncludeAmbiguous = "shader-include-ambiguous"
        case shaderIncludeCycle = "shader-include-cycle"
        case shaderDirectiveUnsupported = "shader-directive-unsupported"
        case shaderModuleResolutionRejected = "shader-module-resolution-rejected"
        case shaderConditionInvalid = "shader-condition-invalid"
        case shaderPreprocessorBudgetExceeded = "shader-preprocessor-budget-exceeded"
        case shaderPreprocessorDiagnostic = "shader-preprocessor-diagnostic"
        case shaderPreparationInvariant = "shader-preparation-invariant"
    }
    let backend: SceneEffectStageCompilerBackend
    let phase: Phase
    let code: Code
    let details: [String]
}
nonisolated enum SceneEffectStageBackendCompileResult<Value> {
    case notApplicable, rejected(SceneEffectStageCompilerFailure), accepted(Value)
}
nonisolated struct SceneResolvedMaterialNode {
    enum TextureProvenance: Hashable { case explicitBinding }
}
nonisolated enum SceneDynamicTarget: Hashable {
    case effectConstant(layerID: Int, effectIndex: Int, passIndex: Int, name: String)
}
nonisolated struct SceneVFSAssetPath: Hashable, Sendable {
    let value: String
    init?(_ value: String) {
        guard !value.isEmpty else { return nil }
        self.value = value
    }
}
nonisolated struct SceneResolvedMaterialTemplate {
    typealias Graph = SceneAuthoredEffectRenderPlan
    struct EffectContext: Hashable {
        let key: Graph.EffectKey
        let input: Graph.TextureIdentity
    }
    enum TextureReference: Hashable {
        case asset(SceneVFSAssetPath)
        case graph(Graph.TextureIdentity)
    }
    struct TextureCandidate: Hashable {
        let reference: TextureReference
        let provenance: SceneResolvedMaterialNode.TextureProvenance
    }
    struct TextureSlot: Hashable {
        let index: Int
        let candidates: [TextureCandidate]
    }
    struct StaticUniformValue: Hashable {
        let valueKind: String
        let componentBitPatterns: [UInt64]
        let authoredBindingKeys: [String]
    }
    enum DynamicUniformSource: Hashable { case sceneScript }
    enum DynamicUniformScriptAttachment: Hashable { case unproven }
    struct DynamicUniform: Hashable {
        let target: SceneDynamicTarget
        let valueContributors: [DynamicUniformSource]
        let scriptAttachments: [DynamicUniformScriptAttachment]
        let authoredFallback: StaticUniformValue?
        let authoredBindingKeys: [String]
    }
    enum UniformValue: Hashable {
        case staticExact(StaticUniformValue)
        case dynamic(DynamicUniform)
    }
    struct UniformDeclaration: Hashable {
        let name: String
        let value: UniformValue
    }
    let textureSlots: [TextureSlot?]
    let uniformDeclarations: [UniformDeclaration]
    let unitPreviousBlurredCompositeGenericOwnerEligible: Bool
    let effectContext: EffectContext?
    let shaderContract: SceneShaderContract
}
'''


HARNESS = r'''
import Foundation

private typealias Graph = SceneAuthoredEffectRenderPlan
private typealias Template = SceneResolvedMaterialTemplate

private struct Output: Codable {
    let stockFact: Bool
    let stockTypedDefault: Bool
    let defaultEligible: Bool
    let explicitUnitEligible: Bool
    let explicitNonunitRejected: Bool
    let explicitDynamicRejected: Bool
    let ownerCohortRejected: Bool
    let duplicateAliasesRejected: Bool
    let wrongSlotRejected: Bool
    let maskCandidateAccepted: Bool
    let missingMaskCandidateRejected: Bool
    let wrongMaskPurposeRejected: Bool
    let nonAssetMaskCandidateRejected: Bool
    let maskSourceMismatchRejected: Bool
    let missingDefaultRejected: Bool
    let nonunitDefaultRejected: Bool
    let malformedDefaultRejected: Bool
    let duplicateDeclarationRejected: Bool
}

private struct CompilerOutput: Codable {
    let transferKind: String?
    let transferSlot: Int?
    let bindingSlots: [Int]
    let terminalPremultiplyCount: Int
    let helperCount: Int
    let wrongSlotRejected: Bool
    let extraSampleRejected: Bool
    let spacedExtraSampleRejected: Bool
    let discardRejected: Bool
    let extraCarrierUseRejected: Bool
    let doubleBoundaryRejected: Bool
    let renamedSlotsAccepted: Bool
    let ordinaryInterpolationUnchanged: Bool
}

private func write(_ value: String, to url: URL) throws {
    try Data(value.utf8).write(to: url, options: .atomic)
}

private func prepare(_ root: URL, maskReady: Bool = false)
    -> (SceneShaderContract, SceneShaderPreparedProgram)? {
    let contracts = SceneShaderContractLoader().load(
        shaderReferences: ["effects/blur_combine"], rootURL: root
    )
    guard contracts.count == 1, let contract = contracts.first,
          contract.diagnostics.isEmpty else { return nil }
    guard case let .accepted(prepared) =
        SceneAuthoredShaderPreparation.prepareShaderStages(
            contract: contract,
            combos: [:],
            textureReadiness: [0: true, 1: maskReady, 2: true]
        ) else { return nil }
    return (contract, prepared)
}

private let effectKey = Graph.EffectKey(
    layerID: 721, effectIndex: 4, descriptorID: "unseen-structural-effect"
)
private let previous = Graph.TextureIdentity(
    kind: .layerSource, layerID: 721, effect: nil, name: nil
)
private let blurred = Graph.TextureIdentity(
    kind: .framebuffer, layerID: 721, effect: effectKey,
    name: "unseen-quarter-target"
)
private let maskPath = SceneVFSAssetPath("unseen/masks/soft-edge.tex")!

private func staticValue(_ values: [Double]) -> Template.StaticUniformValue {
    .init(
        valueKind: "fixture",
        componentBitPatterns: values.map(\.bitPattern),
        authoredBindingKeys: []
    )
}

private func declaration(
    _ name: String, _ values: [Double]
) -> Template.UniformDeclaration {
    .init(name: name, value: .staticExact(staticValue(values)))
}

private let dynamicDeclaration = Template.UniformDeclaration(
    name: "compositecolor",
    value: .dynamic(.init(
        target: .effectConstant(
            layerID: 721, effectIndex: 4, passIndex: 3,
            name: "compositecolor"
        ),
        valueContributors: [.sceneScript],
        scriptAttachments: [], authoredFallback: staticValue([1, 1, 1]),
        authoredBindingKeys: []
    ))
)

private func template(
    contract: SceneShaderContract,
    declarations: [Template.UniformDeclaration] = [],
    ownerEligible: Bool = true,
    includeMask: Bool = false,
    maskReference: Template.TextureReference? = nil
) -> Template {
    var slots = Array<Template.TextureSlot?>(repeating: nil, count: 8)
    slots[0] = .init(index: 0, candidates: [
        .init(reference: .graph(blurred), provenance: .explicitBinding),
    ])
    slots[2] = .init(index: 2, candidates: [
        .init(reference: .graph(previous), provenance: .explicitBinding),
    ])
    if includeMask {
        slots[1] = .init(index: 1, candidates: [
            .init(
                reference: maskReference ?? .asset(maskPath),
                provenance: .explicitBinding
            ),
        ])
    }
    return .init(
        textureSlots: slots,
        uniformDeclarations: declarations,
        unitPreviousBlurredCompositeGenericOwnerEligible: ownerEligible,
        effectContext: .init(key: effectKey, input: previous),
        shaderContract: contract
    )
}

private func eligible(
    _ value: (SceneShaderContract, SceneShaderPreparedProgram)?,
    declarations: [Template.UniformDeclaration] = [],
    identities: [Int: Graph.TextureIdentity] = [0: blurred, 2: previous],
    ownerEligible: Bool = true,
    includeMask: Bool = false,
    maskReference: Template.TextureReference? = nil
) -> Bool {
    guard let (contract, prepared) = value,
          let samplers = try? SceneResolvedMaterialShaderSchema.activeSamplers(prepared)
    else { return false }
    return SceneResolvedMaterialUnitPreviousBlurredCompositeEligibility.slots(
        fragmentSource: prepared.fragment.source,
        prepared: prepared,
        samplers: samplers,
        template: template(
            contract: contract, declarations: declarations,
            ownerEligible: ownerEligible, includeMask: includeMask,
            maskReference: maskReference
        ),
        implicitFramebufferIdentity: previous,
        activeGraphTextureIdentities: identities
    ) == .init(
        blurred: 0,
        previous: 2,
        mask: includeMask ? 1 : nil
    )
}

@main
private struct Harness {
    static func main() throws {
        let arguments = Array(CommandLine.arguments.dropFirst())
        if arguments.first == "export-compiler-input" {
            let stockRoot = URL(fileURLWithPath: arguments[1], isDirectory: true)
            let outputRoot = URL(fileURLWithPath: arguments[2], isDirectory: true)
            let maskReady = arguments.count > 3 && arguments[3] == "mask"
            guard let prepared = prepare(stockRoot, maskReady: maskReady)?.1,
                  case let .success(normalized) =
                    SceneGenericShaderSourceNormalizer.normalize(
                        vertexSource: prepared.vertex.source,
                        fragmentSource: prepared.fragment.source,
                        maximumStageSourceBytes: 1_000_000
                    ) else { throw NSError(domain: "normalize", code: 1) }
            try write(prepared.vertex.source, to: outputRoot.appendingPathComponent(
                "authored.vert"
            ))
            try write(prepared.fragment.source, to: outputRoot.appendingPathComponent(
                "authored.frag"
            ))
            try write(normalized.vertex, to: outputRoot.appendingPathComponent("stage.vert"))
            try write(normalized.fragment, to: outputRoot.appendingPathComponent("stage.frag"))
            return
        }
        if arguments.first == "build-compiler-artifact" {
            let root = URL(fileURLWithPath: arguments[1], isDirectory: true)
            let maskSlot = arguments.count > 2 && arguments[2] == "mask"
                ? 1 : nil
            let stages = try [("vertex", "vert"), ("fragment", "frag")].map {
                name, suffix in
                SceneGenericShaderArtifactBuilder.Stage(
                    name: name,
                    source: try String(contentsOf: root.appendingPathComponent(
                        "stage.\(suffix)"
                    ), encoding: .utf8),
                    authoredSource: try String(contentsOf: root.appendingPathComponent(
                        "authored.\(suffix)"
                    ), encoding: .utf8),
                    msl: try String(contentsOf: root.appendingPathComponent(
                        "\(name).metal"
                    ), encoding: .utf8),
                    reflection: try Data(contentsOf: root.appendingPathComponent(
                        "\(name).reflection.json"
                    ))
                )
            }
            let result = SceneGenericShaderArtifactBuilder.build(
                requestKey: String(repeating: "u", count: 64),
                backendID: "glslang-spirv-cross-msl-v2",
                stages: stages,
                maximumArtifactBytes: 1_000_000
            )
            let raw = stages.first(where: { $0.name == "fragment" })!.msl
            guard case let .success(artifact) = result else {
                if case let .failure(failure) = result {
                    FileHandle.standardError.write(
                        Data("artifact failure: \(failure)\n\(raw)".utf8)
                    )
                }
                throw NSError(domain: "artifact", code: 2)
            }
            guard let lowered =
                    SceneGenericShaderUnitPreviousBlurredCompositeLowering.lower(
                        raw,
                        expectedBlurredSlot: 0,
                        expectedPreviousSlot: 2,
                        expectedMaskSlot: maskSlot
                    ) else {
                FileHandle.standardError.write(Data(raw.utf8))
                throw NSError(domain: "lowering", code: 3)
            }
            let extraSample = raw.replacingOccurrences(
                of: "    out.mwxFragColor = blurred;",
                with: "    float4 hidden = g_Texture0.sample(g_Texture0Smplr, in.v_TexCoord);\n"
                    + "    out.mwxFragColor = blurred;"
            )
            let extraUse = raw.replacingOccurrences(
                of: "    out.mwxFragColor = blurred;",
                with: "    float4 hidden = blurred;\n    out.mwxFragColor = blurred;"
            )
            let spacedExtraSample = raw.replacingOccurrences(
                of: "    out.mwxFragColor = blurred;",
                with: "    float4 hidden = g_Texture0 . sample (g_Texture0Smplr, in.v_TexCoord);\n"
                    + "    out.mwxFragColor = blurred;"
            )
            let discard = raw.replacingOccurrences(
                of: "    out.mwxFragColor = blurred;",
                with: "    discard_fragment();\n    out.mwxFragColor = blurred;"
            )
            let renamed = raw
                .replacingOccurrences(of: "g_Texture0", with: "g_Texture3")
                .replacingOccurrences(of: "g_Texture2", with: "g_Texture5")
            let ordinaryAuthored = """
            uniform sampler2D g_Texture1;
            uniform sampler2D g_Texture4;
            void main() {
                vec4 a = texSample2D(g_Texture1, vec2(0));
                vec4 b = texSample2D(g_Texture4, vec2(0));
                gl_FragColor = mix(a, b, 0.5);
            }
            """
            let ordinaryMSL = """
            out.mwxFragColor = mix(first, second, 0.5);
            """
            let ordinary = try SceneGenericShaderArtifactBuilder.prepareColorTransfer(
                msl: ordinaryMSL, authoredSource: ordinaryAuthored
            )
            let output = CompilerOutput(
                transferKind: artifact.program.colorTransfer.kind,
                transferSlot: artifact.program.colorTransfer.slot,
                bindingSlots: artifact.program.textureBindings.map(\.slot),
                terminalPremultiplyCount: lowered.components(
                    separatedBy: "out.mwxFragColor = mwxGenericPremultiply("
                ).count - 1,
                helperCount: lowered.components(
                    separatedBy: "static inline float4 mwxGenericPremultiply("
                ).count - 1,
                wrongSlotRejected:
                    SceneGenericShaderUnitPreviousBlurredCompositeLowering.lower(
                        raw, expectedBlurredSlot: 1, expectedPreviousSlot: 2,
                        expectedMaskSlot: maskSlot
                    ) == nil,
                extraSampleRejected:
                    SceneGenericShaderUnitPreviousBlurredCompositeLowering.lower(
                        extraSample, expectedBlurredSlot: 0,
                        expectedPreviousSlot: 2, expectedMaskSlot: maskSlot
                    ) == nil,
                spacedExtraSampleRejected:
                    SceneGenericShaderUnitPreviousBlurredCompositeLowering.lower(
                        spacedExtraSample,
                        expectedBlurredSlot: 0, expectedPreviousSlot: 2,
                        expectedMaskSlot: maskSlot
                    ) == nil,
                discardRejected:
                    SceneGenericShaderUnitPreviousBlurredCompositeLowering.lower(
                        discard, expectedBlurredSlot: 0,
                        expectedPreviousSlot: 2, expectedMaskSlot: maskSlot
                    ) == nil,
                extraCarrierUseRejected:
                    SceneGenericShaderUnitPreviousBlurredCompositeLowering.lower(
                        extraUse, expectedBlurredSlot: 0,
                        expectedPreviousSlot: 2, expectedMaskSlot: maskSlot
                    ) == nil,
                doubleBoundaryRejected:
                    SceneGenericShaderUnitPreviousBlurredCompositeLowering.lower(
                        lowered, expectedBlurredSlot: 0,
                        expectedPreviousSlot: 2, expectedMaskSlot: maskSlot
                    ) == nil,
                renamedSlotsAccepted:
                    SceneGenericShaderUnitPreviousBlurredCompositeLowering.lower(
                        renamed, expectedBlurredSlot: 3, expectedPreviousSlot: 5,
                        expectedMaskSlot: maskSlot
                    ) != nil,
                ordinaryInterpolationUnchanged:
                    ordinary.msl == ordinaryMSL
                        && ordinary.transfer.kind == "interpolated-color"
                        && ordinary.transfer.slots == [1, 4]
            )
            try write(
                artifact.program.metalSource,
                to: root.appendingPathComponent("final.metal")
            )
            FileHandle.standardOutput.write(try JSONEncoder().encode(output))
            return
        }
        let roots = arguments.map {
            URL(fileURLWithPath: $0, isDirectory: true)
        }
        let stock = prepare(roots[0])
        let mask = prepare(roots[0], maskReady: true)
        let wrongPurposeMask = prepare(roots[5], maskReady: true)
        let wrongSourceMask = prepare(roots[6], maskReady: true)
        let fact = stock.flatMap {
            SceneAuthoredShaderUnitPreviousBlurredCompositeAnalyzer.analyze(
                fragmentSource: $0.1.fragment.source
            )
        }
        let schema = stock.flatMap {
            SceneResolvedMaterialShaderSchema.uniqueActiveUniform(
                named: "g_CompositeColor", type: .float3,
                stage: .fragment, prepared: $0.1
            )
        }
        let defaultBits = schema?.defaultValue?.componentBitPatterns ?? []
        let output = Output(
            stockFact: fact == .init(
                blurredSlot: 0, previousSlot: 2,
                maskSlot: nil,
                unitColorUniform: "g_CompositeColor"
            ),
            stockTypedDefault: schema?.materialKeys == [
                "g_CompositeColor", "compositecolor",
            ] && defaultBits.map { Double(bitPattern: $0) } == [1, 1, 1],
            defaultEligible: eligible(stock),
            explicitUnitEligible: eligible(
                stock, declarations: [declaration("compositecolor", [1, 1, 1])]
            ),
            explicitNonunitRejected: !eligible(
                stock, declarations: [declaration("compositecolor", [0.5, 1, 1])]
            ),
            explicitDynamicRejected: !eligible(
                stock, declarations: [dynamicDeclaration]
            ),
            ownerCohortRejected: !eligible(stock, ownerEligible: false),
            duplicateAliasesRejected: !eligible(
                stock, declarations: [
                    declaration("g_CompositeColor", [1, 1, 1]),
                    declaration("compositecolor", [1, 1, 1]),
                ]
            ),
            wrongSlotRejected: !eligible(
                stock, identities: [1: blurred, 2: previous]
            ),
            maskCandidateAccepted: eligible(mask, includeMask: true),
            missingMaskCandidateRejected: !eligible(mask),
            wrongMaskPurposeRejected: !eligible(
                wrongPurposeMask, includeMask: true
            ),
            nonAssetMaskCandidateRejected: !eligible(
                mask,
                includeMask: true,
                maskReference: .graph(previous)
            ),
            maskSourceMismatchRejected: !eligible(
                wrongSourceMask, includeMask: true
            ),
            missingDefaultRejected: !eligible(prepare(roots[1])),
            nonunitDefaultRejected: !eligible(prepare(roots[2])),
            malformedDefaultRejected: !eligible(prepare(roots[3])),
            duplicateDeclarationRejected: !eligible(prepare(roots[4]))
        )
        FileHandle.standardOutput.write(try JSONEncoder().encode(output))
    }
}
'''


@unittest.skipUnless(shutil.which("xcrun"), "Xcode toolchain is required")
class StandardBlurUnitCompositeDefaultTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.directory = tempfile.TemporaryDirectory(
            prefix="mwx-standard-blur-unit-default-"
        )
        cls.root = Path(cls.directory.name)
        support = cls.root / "Support.swift"
        harness = cls.root / "Harness.swift"
        support.write_text(SUPPORT, encoding="utf-8")
        harness.write_text(HARNESS, encoding="utf-8")
        cls.binary = cls.root / "standard-blur-unit-default"
        subprocess.run([
            "xcrun", "swiftc", "-o", str(cls.binary),
            *[str(path) for path in SWIFT_SOURCES],
            str(support), str(harness), "-framework", "Security",
            "-framework", "Metal",
        ], check=True, cwd=REPOSITORY_ROOT)

    @classmethod
    def tearDownClass(cls) -> None:
        cls.directory.cleanup()

    def stock_root(self, name: str, mutation: str | None = None) -> Path:
        root = self.root / name
        copies = {
            STOCK_ROOT / "effects/blur/shaders/effects/blur_combine.vert":
                root / "shaders/effects/blur_combine.vert",
            STOCK_ROOT / "effects/blur/shaders/effects/blur_combine.frag":
                root / "shaders/effects/blur_combine.frag",
            STOCK_ROOT / "shaders/common_composite.h":
                root / "shaders/common_composite.h",
            STOCK_ROOT / "shaders/common.h": root / "shaders/common.h",
            STOCK_ROOT / "shaders/common_blending.h":
                root / "shaders/common_blending.h",
        }
        for source, destination in copies.items():
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source, destination)
        if mutation is not None:
            fragment = root / "shaders/effects/blur_combine.frag"
            if mutation == "wrong-mask-purpose":
                source = fragment.read_text(encoding="utf-8")
                marker = ',"mode":"opacitymask"'
                self.assertIn(marker, source)
                fragment.write_text(source.replace(marker, "", 1), encoding="utf-8")
                return root
            if mutation == "mask-green-channel":
                source = fragment.read_text(encoding="utf-8")
                marker = "texSample2D(g_Texture1, v_TexCoord.zw).r"
                self.assertIn(marker, source)
                fragment.write_text(
                    source.replace(marker, marker[:-1] + "g", 1),
                    encoding="utf-8",
                )
                return root
            header = root / "shaders/common_composite.h"
            source = header.read_text(encoding="utf-8")
            marker = '"default":"1 1 1"'
            self.assertIn(marker, source)
            if mutation == "missing":
                replacement = ""
            elif mutation == "nonunit":
                replacement = '"default":"0.5 1 1"'
            elif mutation == "malformed":
                replacement = '"default":"1 nope 1"'
            elif mutation == "duplicate":
                line = "uniform vec3 g_CompositeColor;"
                self.assertIn(line, source)
                header.write_text(source.replace(line, line + "\n" + line), encoding="utf-8")
                return root
            else:
                raise AssertionError(mutation)
            if mutation == "missing":
                source = source.replace("," + marker, replacement)
            else:
                source = source.replace(marker, replacement)
            header.write_text(source, encoding="utf-8")
        return root

    def test_stock_default_and_fail_closed_overrides(self) -> None:
        roots = [
            self.stock_root("stock"),
            self.stock_root("missing", "missing"),
            self.stock_root("nonunit", "nonunit"),
            self.stock_root("malformed", "malformed"),
            self.stock_root("duplicate", "duplicate"),
            self.stock_root("wrong-mask-purpose", "wrong-mask-purpose"),
            self.stock_root("mask-green-channel", "mask-green-channel"),
        ]
        completed = subprocess.run(
            [str(self.binary), *map(str, roots)], check=True,
            cwd=REPOSITORY_ROOT, capture_output=True, text=True,
        )
        output = json.loads(completed.stdout)
        self.assertTrue(all(output.values()), output)

    def compiler_output(
        self, stock: Path, label: str, *, masked: bool
    ) -> dict[str, object]:
        root = self.root / label
        root.mkdir()
        export = [
            str(self.binary), "export-compiler-input", str(stock), str(root),
        ]
        if masked:
            export.append("mask")
        subprocess.run(export, check=True, cwd=REPOSITORY_ROOT,
                       capture_output=True, text=True)
        subprocess.run([
            str(GLSLANG), "-V", "--auto-map-bindings", "--auto-map-locations",
            "-l", str(root / "stage.vert"), str(root / "stage.frag"),
        ], check=True, cwd=root, capture_output=True, text=True)
        for name, suffix in (("vertex", "vert"), ("fragment", "frag")):
            spirv = root / f"{name}.spv"
            subprocess.run([
                str(GLSLANG), "-V", "--auto-map-bindings",
                "--auto-map-locations", "-S", suffix, "-e", "main",
                "-o", str(spirv), str(root / f"stage.{suffix}"),
            ], check=True, cwd=root, capture_output=True, text=True)
            subprocess.run([
                str(SPIRV_CROSS), str(spirv), "--msl", "--msl-version", "20000",
                "--msl-decoration-binding", "--rename-entry-point", "main",
                "mwxGenericVertex" if name == "vertex" else "mwxGenericFragment",
                suffix, "--output", str(root / f"{name}.metal"),
            ], check=True, cwd=root, capture_output=True, text=True)
            subprocess.run([
                str(SPIRV_CROSS), str(spirv), "--reflect", "--output",
                str(root / f"{name}.reflection.json"),
            ], check=True, cwd=root, capture_output=True, text=True)
        build = [str(self.binary), "build-compiler-artifact", str(root)]
        if masked:
            build.append("mask")
        built = subprocess.run(build, cwd=REPOSITORY_ROOT,
                               capture_output=True, text=True)
        self.assertEqual(built.returncode, 0, built.stderr)
        output = json.loads(built.stdout)
        self.assertEqual(output["transferKind"], "straight-alpha-preserving")
        self.assertEqual(output["transferSlot"], 0)
        self.assertEqual(output["bindingSlots"], [0, 1, 2] if masked else [0, 2])
        self.assertEqual(output["terminalPremultiplyCount"], 1)
        self.assertEqual(output["helperCount"], 1)
        self.assertTrue(all(output[key] for key in (
            "wrongSlotRejected", "extraSampleRejected",
            "spacedExtraSampleRejected", "discardRejected",
            "extraCarrierUseRejected", "doubleBoundaryRejected",
            "renamedSlotsAccepted", "ordinaryInterpolationUnchanged",
        )), output)
        metal = subprocess.run([
            "xcrun", "metal", "-x", "metal", "-std=macos-metal2.4", "-c",
            str(root / "final.metal"), "-o", str(root / "final.air"),
        ], cwd=root, capture_output=True, text=True)
        self.assertEqual(metal.returncode, 0, metal.stderr)
        return output

    def test_stock_prepared_source_real_compiler_lowering_and_metal(self) -> None:
        stock = self.stock_root("compiler-stock")
        self.compiler_output(stock, "actual-compiler", masked=False)
        self.compiler_output(stock, "actual-masked-compiler", masked=True)


if __name__ == "__main__":
    unittest.main()
