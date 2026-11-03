#!/usr/bin/env python3

"""Real stock Standard Blur previous/blurred composite eligibility."""

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
from script.tests.test_scene_prepared_script_resource_catalog import swift_declaration


SWIFT_SOURCES = list(dict.fromkeys([
    *scene_swift_sources("shader_contract_resource_resolution"),
    *scene_swift_sources("authored_shader_frontend_core"),
    *scene_swift_sources("authored_shader_preparation_implementation"),
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Resources/Textures/SceneTextureSampling.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Resources/Textures/SceneNamedTextureReference.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Compilation/Graph/SceneAuthoredEffectRenderPlan.swift",
    SCENE_ROOT / "Compilation/Material/SceneRenderTargetVocabulary.swift",
    SCENE_ROOT / "Resources/Textures/SceneTextureLookupIdentity.swift",
    SCENE_ROOT / "Runtime/Frame/SceneResolvedMaterialPreparedSamplerSchema.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Compilation/Material/SceneResolvedMaterialShaderSchema.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Resources/Assets/SceneStockTextureSemanticRegistry.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Bindings/SceneResolvedMaterialRuntimeLoopBoundResolver.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Compilation/Material/SceneResolvedMaterialPreviousBlurredCompositeEligibility.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Compilation/Material/SceneResolvedMaterialGenericShaderProgramArtifact.swift",
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
    enum TextureProvenance: Hashable { case explicitBinding, instance }
}
nonisolated enum SceneDynamicTarget: Hashable {
    case effectConstant(layerID: Int, effectIndex: Int, passIndex: Int, name: String)
}
nonisolated struct SceneResolvedMaterialTemplate {
    typealias Graph = SceneAuthoredEffectRenderPlan
    enum KnownProviderRequest: Hashable {
        case namedLayerTarget(SceneNamedTextureReference)
        case sceneBackground, sceneEnvironment, system
    }
    struct GraphRole: Hashable { let bindings: [Int] = [] }
    struct EffectContext: Hashable {
        let key: Graph.EffectKey
        let input: Graph.TextureIdentity
    }
    enum TextureReference: Hashable {
        case asset(SceneVFSAssetPath)
        case provider(KnownProviderRequest)
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
    let comboValues: [String: Int]
    let inheritedInactiveCombos: [String]
    let uniformDeclarations: [UniformDeclaration]
    let effectContext: EffectContext?
    let shaderContract: SceneShaderContract
    let compatibilityTarget: SceneShaderCompatibilityTarget = .unprofiledMetal
    let graphRole = GraphRole()
}
'''


HARNESS = r'''
import Foundation

private typealias Graph = SceneAuthoredEffectRenderPlan
private typealias Template = SceneResolvedMaterialTemplate

private struct Output: Codable {
    let stockFact: Bool
    let stockTypedDefault: Bool
    let maskedFact: Bool
    let previousInputShadowCases: [String: Bool]
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
    throws -> (SceneShaderContract, SceneShaderPreparedProgram)? {
    let contracts = try SceneShaderContractLoader().load(
        shaderReferences: ["effects/blur_combine"], rootURL: root
    )
    guard contracts.count == 1, let contract = contracts.first,
          contract.diagnostics.isEmpty else { return nil }
    guard case let .accepted(prepared) =
        SceneAuthoredShaderPreparation.prepareShaderStages(
            contract: contract,
            compatibilityTarget: .windowsDX11ShaderModel4,
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

private func template(
    contract: SceneShaderContract,
    input: Graph.TextureIdentity = previous,
    consumer: Graph.EffectKey = effectKey,
    blurTarget: Graph.TextureIdentity = blurred,
    inputProvenance: [Template.TextureCandidate] = []
) -> Template {
    var slots = Array<Template.TextureSlot?>(repeating: nil, count: 8)
    slots[0] = .init(index: 0, candidates: [
        .init(reference: .graph(blurTarget), provenance: .explicitBinding),
    ])
    slots[2] = .init(index: 2, candidates: inputProvenance + [
        .init(reference: .graph(input), provenance: .explicitBinding),
    ])
    return .init(
        textureSlots: slots,
        comboValues: [:],
        inheritedInactiveCombos: [],
        uniformDeclarations: [],
        effectContext: .init(key: consumer, input: input),
        shaderContract: contract
    )
}

private func previousInputShadowCases(
    _ stock: (SceneShaderContract, SceneShaderPreparedProgram)?
) -> [String: Bool] {
    guard let (contract, _) = stock else { return ["prepared": false] }
    var checks: [String: Bool] = [:]
    for (layer, index, descriptor, target) in [
        (721, 4, "unseen-structural-effect", "unseen-quarter-target"),
        (938, 7, "renamed-composite", "renamed-half-target"),
    ] {
        let consumer = Graph.EffectKey(layerID: layer, effectIndex: index,
                                       descriptorID: descriptor)
        let producer = Graph.EffectKey(layerID: layer, effectIndex: index - 1,
                                       descriptorID: "prior-" + descriptor)
        let immediate = Graph.TextureIdentity(kind: .effectOutput, layerID: layer,
                                               effect: producer, name: nil)
        let source = Graph.TextureIdentity(kind: .layerSource, layerID: layer,
                                            effect: nil, name: nil)
        let blurTarget = Graph.TextureIdentity(kind: .framebuffer, layerID: layer,
                                                effect: consumer, name: target)
        func lower(
            _ variant: SceneNamedTextureReference.Variant,
            layerID: Int? = nil,
            provenance: SceneResolvedMaterialNode.TextureProvenance = .instance
        ) -> [Template.TextureCandidate] {
            [.init(reference: .provider(.namedLayerTarget(.init(
                providerLayerID: layerID ?? layer, variant: variant
            ))), provenance: provenance)]
        }
        let earlier = Graph.EffectKey(layerID: layer, effectIndex: index - 2,
                                      descriptorID: "earlier-" + descriptor)
        let foreign = Graph.EffectKey(layerID: layer + 1, effectIndex: index - 1,
                                      descriptorID: "foreign-" + descriptor)
        let cases: [(String, Graph.TextureIdentity, [Template.TextureCandidate], Bool)] = [
            ("immediate-no-shadow", immediate, [], true),
            ("immediate-primary", immediate, lower(.primary), true),
            ("immediate-secondary", immediate, lower(.secondary), true),
            ("source-primary", source, lower(.primary), true),
            ("source-secondary", source, lower(.secondary), false),
            ("unspecified", immediate, lower(.unspecified), false),
            ("foreign-reference", immediate, lower(.primary, layerID: layer + 1), false),
            ("foreign-input", .init(kind: .effectOutput, layerID: layer + 1,
                effect: producer, name: nil), lower(.primary), false),
            ("foreign-producer", .init(kind: .effectOutput, layerID: layer,
                effect: foreign, name: nil), lower(.primary), false),
            ("nonimmediate", .init(kind: .effectOutput, layerID: layer,
                effect: earlier, name: nil), lower(.primary), false),
            ("named-input", .init(kind: .effectOutput, layerID: layer,
                effect: producer, name: target), lower(.primary), false),
            ("wrong-kind", .init(kind: .framebuffer, layerID: layer,
                effect: producer, name: nil), lower(.primary), false),
            ("missing-producer", .init(kind: .effectOutput, layerID: layer,
                effect: nil, name: nil), lower(.primary), false),
            ("source-with-producer", .init(kind: .layerSource, layerID: layer,
                effect: producer, name: nil), lower(.primary), false),
            ("multiple-lower", immediate, lower(.primary) + lower(.secondary), false),
            ("noninstance-lower", immediate,
                lower(.primary, provenance: .explicitBinding), false),
            ("asset-lower", immediate,
                [.init(reference: .asset(maskPath), provenance: .instance)], false),
        ]
        for (name, input, provenance, expected) in cases {
            let label = "\(layer)/\(name)"
            let candidate = template(contract: contract, input: input, consumer: consumer,
                                     blurTarget: blurTarget, inputProvenance: provenance)
            checks[label + "/override"] =
                SceneResolvedMaterialPreviousBlurredCompositeEligibility.exactGraphOverride(
                    slot: 2, identity: input, template: candidate,
                    allowsNamedInputProvenance: true
                ) == expected
        }
        checks["\(layer)/primary-predicate"] =
            SceneResolvedMaterialExactPreviousInputShadow.accepts(
                .init(providerLayerID: layer, variant: .primary),
                input: immediate, consumer: consumer
            )
    }
    return checks
}

@main
private struct Harness {
    static func main() throws {
        let arguments = Array(CommandLine.arguments.dropFirst())
        if arguments.first == "export-compiler-input" {
            let stockRoot = URL(fileURLWithPath: arguments[1], isDirectory: true)
            let outputRoot = URL(fileURLWithPath: arguments[2], isDirectory: true)
            let maskReady = arguments.count > 3 && arguments[3] == "mask"
            guard let prepared = try prepare(stockRoot, maskReady: maskReady)?.1,
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
                    SceneGenericShaderPreviousBlurredCompositeLowering.lower(
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
                    SceneGenericShaderPreviousBlurredCompositeLowering.lower(
                        raw, expectedBlurredSlot: 1, expectedPreviousSlot: 2,
                        expectedMaskSlot: maskSlot
                    ) == nil,
                extraSampleRejected:
                    SceneGenericShaderPreviousBlurredCompositeLowering.lower(
                        extraSample, expectedBlurredSlot: 0,
                        expectedPreviousSlot: 2, expectedMaskSlot: maskSlot
                    ) == nil,
                spacedExtraSampleRejected:
                    SceneGenericShaderPreviousBlurredCompositeLowering.lower(
                        spacedExtraSample,
                        expectedBlurredSlot: 0, expectedPreviousSlot: 2,
                        expectedMaskSlot: maskSlot
                    ) == nil,
                discardRejected:
                    SceneGenericShaderPreviousBlurredCompositeLowering.lower(
                        discard, expectedBlurredSlot: 0,
                        expectedPreviousSlot: 2, expectedMaskSlot: maskSlot
                    ) == nil,
                extraCarrierUseRejected:
                    SceneGenericShaderPreviousBlurredCompositeLowering.lower(
                        extraUse, expectedBlurredSlot: 0,
                        expectedPreviousSlot: 2, expectedMaskSlot: maskSlot
                    ) == nil,
                doubleBoundaryRejected:
                    SceneGenericShaderPreviousBlurredCompositeLowering.lower(
                        lowered, expectedBlurredSlot: 0,
                        expectedPreviousSlot: 2, expectedMaskSlot: maskSlot
                    ) == nil,
                renamedSlotsAccepted:
                    SceneGenericShaderPreviousBlurredCompositeLowering.lower(
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
        let stock = try prepare(roots[0])
        let mask = try prepare(roots[0], maskReady: true)
        let fact = stock.flatMap {
            SceneAuthoredShaderPreviousBlurredCompositeAnalyzer.analyze(
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
                maskSlot: nil
            ),
            stockTypedDefault: schema?.materialKeys == [
                "g_CompositeColor", "compositecolor",
            ] && defaultBits.map { Double(bitPattern: $0) } == [1, 1, 1],
            maskedFact: mask.flatMap {
                SceneAuthoredShaderPreviousBlurredCompositeAnalyzer.analyze(
                    fragmentSource: $0.1.fragment.source)
            } == .init(blurredSlot: 0, previousSlot: 2, maskSlot: 1),
            previousInputShadowCases: previousInputShadowCases(stock)
        )
        FileHandle.standardOutput.write(try JSONEncoder().encode(output))
    }
}
'''


@unittest.skipUnless(shutil.which("xcrun"), "Xcode toolchain is required")
class StandardBlurPreviousCompositeTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.directory = tempfile.TemporaryDirectory(
            prefix="mwx-standard-blur-previous-composite-"
        )
        cls.root = Path(cls.directory.name)
        support = cls.root / "Support.swift"
        harness = cls.root / "Harness.swift"
        purpose = cls.root / "SamplerPurpose.swift"
        # Compile the real purpose projection rather than a manually synced
        # subset. Graph-input finalization belongs to a separate harness.
        purpose_source = (SCENE_ROOT / "Compilation/Material/SceneResolvedMaterialShaderSchema+SamplerPurpose.swift").read_text()
        purpose_projection, marker, _ = purpose_source.partition(
            "\nextension SceneResolvedMaterialShaderSchema {\n    typealias GraphInputFact ="
        )
        if not marker:
            raise RuntimeError("Sampler purpose projection boundary was not found")
        purpose.write_text(purpose_projection, encoding="utf-8")
        frame_input = (SCENE_ROOT / "Runtime/Frame/SceneResolvedMaterialPreparedFrameInput.swift").read_text()
        uniform_schema, schema_boundary, _ = frame_input.partition(
            "\n/// Immutable identity of one admitted material node."
        )
        if not schema_boundary:
            raise RuntimeError("Prepared uniform schema declaration boundary was not found")
        program_source = (SCENE_ROOT / "Compilation/Material/SceneResolvedMaterialProgram.swift").read_text()
        failure = swift_declaration(
            program_source, "nonisolated struct SceneResolvedMaterialFailure:"
        )
        support.write_text(SUPPORT + "\n" + uniform_schema + "\n" + failure, encoding="utf-8")
        harness.write_text(HARNESS, encoding="utf-8")
        cls.binary = cls.root / "standard-blur-previous-composite"
        subprocess.run([
            "xcrun", "swiftc", "-o", str(cls.binary),
            *[str(path) for path in SWIFT_SOURCES],
            str(support), str(purpose), str(harness), "-framework", "Security",
            "-framework", "Metal",
        ], check=True, cwd=REPOSITORY_ROOT)

    @classmethod
    def tearDownClass(cls) -> None:
        cls.directory.cleanup()

    def stock_root(self, name: str) -> Path:
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
        return root


    def test_stock_sampler_defaults_and_previous_input_identity(self) -> None:
        roots = [self.stock_root("stock")]
        completed = subprocess.run(
            [str(self.binary), *map(str, roots)], check=True,
            cwd=REPOSITORY_ROOT, capture_output=True, text=True,
        )
        output = json.loads(completed.stdout)
        for case, passed in output.pop("previousInputShadowCases").items():
            with self.subTest(shadow_case=case):
                self.assertTrue(passed)
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
