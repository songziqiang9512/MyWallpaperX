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
]))


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
    enum TextureReference: Hashable { case graph(Graph.TextureIdentity) }
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
    let duplicateAliasesRejected: Bool
    let wrongSlotRejected: Bool
    let maskInputRejected: Bool
    let missingDefaultRejected: Bool
    let nonunitDefaultRejected: Bool
    let malformedDefaultRejected: Bool
    let duplicateDeclarationRejected: Bool
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
    declarations: [Template.UniformDeclaration] = []
) -> Template {
    var slots = Array<Template.TextureSlot?>(repeating: nil, count: 8)
    slots[0] = .init(index: 0, candidates: [
        .init(reference: .graph(blurred), provenance: .explicitBinding),
    ])
    slots[2] = .init(index: 2, candidates: [
        .init(reference: .graph(previous), provenance: .explicitBinding),
    ])
    return .init(
        textureSlots: slots,
        uniformDeclarations: declarations,
        effectContext: .init(key: effectKey, input: previous),
        shaderContract: contract
    )
}

private func eligible(
    _ value: (SceneShaderContract, SceneShaderPreparedProgram)?,
    declarations: [Template.UniformDeclaration] = [],
    identities: [Int: Graph.TextureIdentity] = [0: blurred, 2: previous]
) -> Bool {
    guard let (contract, prepared) = value,
          let samplers = try? SceneResolvedMaterialShaderSchema.activeSamplers(prepared)
    else { return false }
    return SceneResolvedMaterialUnitPreviousBlurredCompositeEligibility.slots(
        fragmentSource: prepared.fragment.source,
        prepared: prepared,
        samplers: samplers,
        template: template(contract: contract, declarations: declarations),
        implicitFramebufferIdentity: previous,
        activeGraphTextureIdentities: identities
    ) == .init(blurred: 0, previous: 2)
}

@main
private struct Harness {
    static func main() throws {
        let roots = CommandLine.arguments.dropFirst().map {
            URL(fileURLWithPath: $0, isDirectory: true)
        }
        let stock = prepare(roots[0])
        let mask = prepare(roots[0], maskReady: true)
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
            duplicateAliasesRejected: !eligible(
                stock, declarations: [
                    declaration("g_CompositeColor", [1, 1, 1]),
                    declaration("compositecolor", [1, 1, 1]),
                ]
            ),
            wrongSlotRejected: !eligible(
                stock, identities: [1: blurred, 2: previous]
            ),
            maskInputRejected: !eligible(mask),
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
            "xcrun", "swiftc", "-O", "-o", str(cls.binary),
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
        ]
        completed = subprocess.run(
            [str(self.binary), *map(str, roots)], check=True,
            cwd=REPOSITORY_ROOT, capture_output=True, text=True,
        )
        output = json.loads(completed.stdout)
        self.assertTrue(all(output.values()), output)


if __name__ == "__main__":
    unittest.main()
