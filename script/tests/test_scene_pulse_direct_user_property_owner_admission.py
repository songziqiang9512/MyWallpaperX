#!/usr/bin/env python3
"""Executable owner partition for Pulse direct user-property uniforms."""

from __future__ import annotations

import json
import os
from pathlib import Path
import runpy
import shutil
import subprocess
import tempfile
import unittest


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
SCENE_ROOT = REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene"
STOCK_ROOT = (
    REPOSITORY_ROOT
    / "MyWallpaperX/Resources/SceneStockAssets.bundle/assets"
)
FINALIZER_FIXTURE = runpy.run_path(
    str(
        REPOSITORY_ROOT
        / "script/tests/test_scene_resolved_material_program_finalizer.py"
    )
)
PULSE_FIXTURE = runpy.run_path(
    str(REPOSITORY_ROOT / "script/tests/test_scene_pulse_planner.py")
)
DEDICATED_COMPILERS_SOURCE = (
    SCENE_ROOT
    / "RenderGraph/EffectCompilation/SceneEffectStageDedicatedCompilers.swift"
)


def unique_sources(paths: list[Path]) -> list[Path]:
    return list(dict.fromkeys(paths))


def product_pulse_compiler_source() -> str:
    """Compile the exact production protocols and Pulse compiler extension."""
    source = DEDICATED_COMPILERS_SOURCE.read_text(encoding="utf-8")
    standard_blur = source.index("extension SceneAuthoredStandardBlurPlanner")
    pulse = source.index("extension SceneAuthoredPulsePlanner")
    return source[:standard_blur] + source[pulse:]


SWIFT_SOURCES = unique_sources([
    *FINALIZER_FIXTURE["SWIFT_SOURCES"],
    *PULSE_FIXTURE["SWIFT_SOURCES"],
    SCENE_ROOT / "Format/SceneDocument+ShaderValue.swift",
    SCENE_ROOT / "RenderGraph/SceneEffectTextureInput.swift",
    SCENE_ROOT
    / "RenderGraph/MaterialProgram/SceneResolvedMaterialScriptBindingClassifier.swift",
    SCENE_ROOT
    / "RenderGraph/MaterialProgram/SceneResolvedMaterialTemplateCompiler.swift",
    SCENE_ROOT
    / "RenderGraph/EffectCompilation/SceneEffectStageCompileModel.swift",
])


SUPPORT = r'''
import Foundation

struct SceneDocument {}
struct SceneTimelineAnimation: Codable {}

struct SceneRenderDescriptor {
    struct EffectDescriptor {
        struct PassDescriptor {
            let passIndex: Int
            let texturePaths: [String]
            let textureSlots: [String?]
            let userTextureInputs: [SceneEffectTextureInput?]
            let combos: [String: Int]
            let constantShaderValues: [String: SceneDocument.ShaderValue]
        }

        let id: String
        let file: String
        let visible: Bool?
        let passes: [PassDescriptor]
    }

    struct Layer {
        let id: Int
        let contentKind: String
        let effects: [EffectDescriptor]
    }

    struct MaterialPassDescriptor {
        let id: String
        let materialPath: String
        let materialRawSHA256: String
        let passIndex: Int
        let shaderPath: String?
        let texturePaths: [String]
        let textureSlots: [String?]
        let userTextureInputs: [SceneEffectTextureInput?]
        let combos: [String: Int]
        let constantShaderValues: [String: SceneDocument.ShaderValue]
        let userShaderValues: [String: String]
        let blending: String?
        let depthTest: String?
        let depthWrite: String?
        let cullMode: String?
        let alphaWriting: String?
    }

    let layers: [Layer]
    let materialPasses: [MaterialPassDescriptor]
    let effectDefinitions: [SceneEffectDefinition]
}
'''


HARNESS = r'''
import Foundation

private typealias Graph = SceneAuthoredEffectRenderPlan
private typealias Constant = ScenePulseExecutionPlan.Constant

private let layerID = 20
private let effectKey = Graph.EffectKey(
    layerID: layerID,
    effectIndex: 0,
    descriptorID: "20#effect#21"
)
private let definitionPath = "effects/pulse/effect.json"
private let materialPath = "materials/effects/pulse.json"
private let shaderIdentity = "effects/pulse"

private func value(
    _ components: [Double],
    propertyKey: String
) -> SceneDocument.ShaderValue {
    .init(
        rawValue: components.map { String($0) }.joined(separator: " "),
        valueKind: "binding",
        userBinding: propertyKey,
        userValueKind: .string,
        components: components,
        bindingKeys: ["user", "value"]
    )
}

private func definition() -> SceneEffectDefinition {
    .init(
        relativePath: definitionPath,
        version: 1,
        replacementKey: "pulse",
        name: "ui_editor_effect_pulse_title",
        description: "ui_editor_effect_pulse_description",
        group: "animate",
        performance: nil,
        previewPath: "preview/project.json",
        editable: nil,
        passes: [.init(
            passIndex: 0,
            materialPath: materialPath,
            target: nil,
            bindings: [],
            compose: nil,
            command: nil,
            source: nil,
            conditions: nil,
            extraFields: [:]
        )],
        framebuffers: [],
        dependencies: [
            materialPath,
            "shaders/effects/pulse.frag",
            "shaders/effects/pulse.vert",
        ],
        functions: nil,
        gizmos: nil,
        extraFields: [:],
        unknownFieldPaths: []
    )
}

private func descriptor(
    bindings: [Constant: String]
) -> SceneRenderDescriptor {
    let constants = Dictionary(uniqueKeysWithValues: bindings.map {
        constant, propertyKey in
        let components = constant.defaultComponents(for: .stock2842)
        return (constant.rawValue, value(components, propertyKey: propertyKey))
    })
    let pass = SceneRenderDescriptor.EffectDescriptor.PassDescriptor(
        passIndex: 0,
        texturePaths: [],
        textureSlots: [],
        userTextureInputs: [],
        combos: [:],
        constantShaderValues: constants
    )
    return .init(
        layers: [.init(
            id: layerID,
            contentKind: "image",
            effects: [.init(
                id: effectKey.descriptorID,
                file: definitionPath,
                visible: true,
                passes: [pass]
            )]
        )],
        materialPasses: [.init(
            id: "\(materialPath)#0",
            materialPath: materialPath,
            materialRawSHA256:
                "76a64c2e4e0b72c056b7dc3e35f333ca5fbc3b04b345b3bdccbedd3f2334deee",
            passIndex: 0,
            shaderPath: shaderIdentity,
            texturePaths: [],
            textureSlots: [],
            userTextureInputs: [],
            combos: [:],
            constantShaderValues: [:],
            userShaderValues: [:],
            blending: "normal",
            depthTest: "disabled",
            depthWrite: "disabled",
            cullMode: "nocull",
            alphaWriting: nil
        )],
        effectDefinitions: [definition()]
    )
}

private func texture(
    _ kind: Graph.TextureKind,
    effect: Graph.EffectKey? = nil
) -> Graph.TextureIdentity {
    .init(kind: kind, layerID: layerID, effect: effect, name: nil)
}

private func graph() -> Graph {
    let input = texture(.layerSource)
    let output = texture(.effectOutput, effect: effectKey)
    return .init(
        layerID: layerID,
        effects: [.init(
            key: effectKey,
            definitionPath: definitionPath,
            input: input,
            output: output,
            nodeIndices: [0]
        )],
        renderTargets: [],
        nodes: [.init(
            nodeIndex: 0,
            effect: effectKey,
            definitionPassIndex: 0,
            materialOrdinal: 0,
            instancePassIndex: 0,
            kind: .material,
            materialPath: materialPath,
            materialPassID: "\(materialPath)#0",
            target: output,
            bindings: [],
            commandSource: nil,
            commandTarget: nil,
            compose: nil,
            conditions: nil
        )],
        finalOutput: output,
        blockers: []
    )
}

private func producer(
    _ constant: Constant,
    propertyKey: String,
    valueType: SceneDynamicValueType? = nil
) -> SceneDynamicUserPropertyProducer {
    .init(
        propertyKey: propertyKey,
        target: .effectConstant(
            layerID: layerID,
            effectIndex: 0,
            passIndex: 0,
            name: constant.rawValue
        ),
        valueType: valueType ?? constant.valueType
    )
}

private func compileInput(
    contracts: [SceneShaderContract],
    bindings: [Constant: String],
    producers: Set<SceneDynamicUserPropertyProducer>? = nil
) -> SceneEffectStageCompileInput {
    let actualProducers = producers ?? Set(bindings.map {
        producer($0.key, propertyKey: $0.value)
    })
    return .init(
        stageGraph: graph(),
        effectKey: effectKey,
        definitionPath: definitionPath,
        inputRole: .layerSource,
        descriptor: descriptor(bindings: bindings),
        shaderContracts: contracts,
        userPropertyProducers: actualProducers
    )
}

private func outcome(_ input: SceneEffectStageCompileInput) -> String {
    switch SceneAuthoredPulsePlanner.compile(input) {
    case .notApplicable: return "not-applicable"
    case .accepted: return "incumbent"
    case .rejected(let failure):
        return "revoked:\(failure.details.first ?? "")"
    }
}

private func plan(
    contracts: [SceneShaderContract],
    bindings: [Constant: String]
) -> ScenePulseExecutionPlan {
    let input = compileInput(contracts: contracts, bindings: bindings)
    return SceneAuthoredPulsePlanner.plan(
        graph: input.stageGraph,
        descriptor: input.descriptor,
        shaderContracts: input.shaderContracts,
        inputRole: input.inputRole
    )!
}

private func prepared(_ contract: SceneShaderContract) -> SceneShaderPreparedProgram {
    let readiness = Dictionary(uniqueKeysWithValues: (0 ..< 8).map { ($0, false) })
    switch SceneAuthoredShaderPreparation.prepareShaderStages(
        contract: contract,
        combos: [
            "AUDIOPROCESSING": 0,
            "BLENDMODE": 9,
            "PULSEALPHA": 0,
            "PULSECOLOR": 1,
        ],
        inactiveComboProviders: [],
        textureReadiness: readiness
    ) {
    case .accepted(let value): return value
    case .notApplicable, .rejected:
        preconditionFailure("stock Pulse preparation failed")
    }
}

private func copy(
    _ source: SceneShaderPreparedSource,
    declarations: [SceneShaderActiveDeclaration]? = nil,
    annotations: [SceneShaderActiveAnnotation]? = nil
) -> SceneShaderPreparedSource {
    .init(
        frontendSchemaVersion: source.frontendSchemaVersion,
        sourceDialect: source.sourceDialect,
        backend: source.backend,
        stage: source.stage,
        rootRelativePath: source.rootRelativePath,
        source: source.source,
        sourceMap: source.sourceMap,
        activeAnnotations: annotations ?? source.activeAnnotations,
        activeDeclarations: declarations ?? source.activeDeclarations,
        dependencies: source.dependencies,
        dependencySHA256: source.dependencySHA256,
        moduleDependencies: source.moduleDependencies,
        moduleDependencySHA256: source.moduleDependencySHA256,
        variantSHA256: source.variantSHA256,
        preparedSHA256: source.preparedSHA256
    )
}

private func copy(
    _ program: SceneShaderPreparedProgram,
    vertex: SceneShaderPreparedSource? = nil,
    fragment: SceneShaderPreparedSource? = nil
) -> SceneShaderPreparedProgram {
    .init(
        vertex: vertex ?? program.vertex,
        fragment: fragment ?? program.fragment,
        colorContract: program.colorContract,
        cacheKey: program.cacheKey
    )
}

private func declaration(
    _ active: SceneShaderActiveDeclaration,
    type: String? = nil,
    arraySuffix: String? = nil,
    arraySize: Int? = nil,
    line: Int? = nil
) -> SceneShaderActiveDeclaration {
    let original = active.declaration
    return .init(
        sourcePath: active.sourcePath,
        declaration: .init(
            kind: original.kind,
            type: type ?? original.type,
            name: original.name,
            arraySuffix: arraySuffix,
            arraySize: arraySize,
            raw: original.raw,
            line: line ?? original.line
        )
    )
}

private func materialAnnotation(
    materialKey: String,
    range: ClosedRange<Double>,
    line: Int,
    sourcePath: String
) -> SceneShaderActiveAnnotation {
    let value = SceneJSONValue.object([
        "material": .string(materialKey),
        "default": .number(range.lowerBound),
        "range": .array([.number(range.lowerBound), .number(range.upperBound)]),
    ])
    return .init(
        sourcePath: sourcePath,
        annotation: .init(
            marker: nil,
            value: value,
            raw: "// synthetic owner-admission fixture",
            line: line
        )
    )
}

private func replacingRange(
    _ source: SceneShaderPreparedSource,
    name: String,
    range: ClosedRange<Double>
) -> SceneShaderPreparedSource {
    let declaration = source.activeDeclarations.first {
        $0.declaration.name == name
    }!
    let annotations = source.activeAnnotations.map { active in
        guard active.sourcePath == declaration.sourcePath,
              active.annotation.line == declaration.declaration.line,
              case var .object(object) = active.annotation.value else {
            return active
        }
        object["range"] = .array([
            .number(range.lowerBound), .number(range.upperBound),
        ])
        let value = SceneJSONValue.object(object)
        return .init(
            sourcePath: active.sourcePath,
            annotation: .init(
                marker: active.annotation.marker,
                value: value,
                raw: active.annotation.raw,
                line: active.annotation.line
            )
        )
    }
    return copy(source, annotations: annotations)
}

private func ownerDisposition(
    _ plan: ScenePulseExecutionPlan,
    _ preparedVariants: [SceneShaderPreparedProgram]
) -> String {
    SceneAuthoredPulsePlanner.directUserPropertyOwnerDisposition(
        plan: plan,
        preparedVariants: preparedVariants
    ).rawValue
}

@main
enum Harness {
    static func main() throws {
        let root = URL(
            fileURLWithPath: CommandLine.arguments[1],
            isDirectory: true
        )
        let contracts = SceneShaderContractLoader().load(
            shaderReferences: [shaderIdentity],
            rootURL: root
        )
        precondition(contracts.count == 1)
        let stock = prepared(contracts[0])
        let speedPlan = plan(
            contracts: contracts,
            bindings: [.speed: "pulseSpeed"]
        )
        let noisePlan = plan(
            contracts: contracts,
            bindings: [.noiseAmount: "pulseNoise"]
        )
        let phasePlan = plan(
            contracts: contracts,
            bindings: [.phase: "pulsePhase"]
        )
        let boundsPlan = plan(
            contracts: contracts,
            bindings: [.bounds: "pulseBounds"]
        )

        let missingVertexSpeed = copy(
            stock.vertex,
            declarations: stock.vertex.activeDeclarations.filter {
                $0.declaration.name != "g_PulseSpeed"
            }
        )

        let noiseTemplate = stock.fragment.activeDeclarations.first {
            $0.declaration.name == "g_NoiseAmount"
        }!
        let extraNoiseLine = 9_991
        let extraNoise = SceneShaderActiveDeclaration(
            sourcePath: stock.vertex.rootRelativePath,
            declaration: .init(
                kind: .uniform,
                type: "float",
                name: "g_ExtraNoiseAmount",
                arraySuffix: nil,
                arraySize: nil,
                raw: noiseTemplate.declaration.raw,
                line: extraNoiseLine
            )
        )
        let extraStageVertex = copy(
            stock.vertex,
            declarations: stock.vertex.activeDeclarations + [extraNoise],
            annotations: stock.vertex.activeAnnotations + [materialAnnotation(
                materialKey: "noiseamount",
                range: 0 ... 2,
                line: extraNoiseLine,
                sourcePath: stock.vertex.rootRelativePath
            )]
        )

        let speedTemplate = stock.fragment.activeDeclarations.first {
            $0.declaration.name == "g_PulseSpeed"
        }!
        let duplicateLine = 9_992
        let duplicateSpeed = declaration(speedTemplate, line: duplicateLine)
        let duplicateFragment = copy(
            stock.fragment,
            declarations: stock.fragment.activeDeclarations + [duplicateSpeed],
            annotations: stock.fragment.activeAnnotations + [materialAnnotation(
                materialKey: "speed",
                range: 0 ... 10,
                line: duplicateLine,
                sourcePath: speedTemplate.sourcePath
            )]
        )

        let arrayVertex = copy(
            stock.vertex,
            declarations: stock.vertex.activeDeclarations.map {
                $0.declaration.name == "g_PulseSpeed"
                    ? declaration($0, arraySuffix: "[2]", arraySize: 2)
                    : $0
            }
        )
        let wrongTypeVertex = copy(
            stock.vertex,
            declarations: stock.vertex.activeDeclarations.map {
                $0.declaration.name == "g_PulseSpeed"
                    ? declaration($0, type: "vec2")
                    : $0
            }
        )
        let wrongRangeVertex = replacingRange(
            stock.vertex,
            name: "g_PulseSpeed",
            range: 0 ... 9
        )

        let result: [String: Any] = [
            "productSpeed": outcome(compileInput(
                contracts: contracts,
                bindings: [.speed: "pulseSpeed"]
            )),
            "productAmount": outcome(compileInput(
                contracts: contracts,
                bindings: [.amount: "pulseAmount"]
            )),
            "productCombined": outcome(compileInput(
                contracts: contracts,
                bindings: [
                    .speed: "pulseValue",
                    .amount: "pulseValue",
                    .noiseAmount: "pulseValue",
                ]
            )),
            "productPhase": outcome(compileInput(
                contracts: contracts,
                bindings: [.phase: "pulsePhase"]
            )),
            "productBounds": outcome(compileInput(
                contracts: contracts,
                bindings: [.bounds: "pulseBounds"]
            )),
            "productMissingProducer": outcome(compileInput(
                contracts: contracts,
                bindings: [.speed: "pulseSpeed"],
                producers: []
            )),
            "productWrongProducerType": outcome(compileInput(
                contracts: contracts,
                bindings: [.speed: "pulseSpeed"],
                producers: [producer(
                    .speed,
                    propertyKey: "pulseSpeed",
                    valueType: .vector2
                )]
            )),
            "stockSpeedDisposition": ownerDisposition(
                speedPlan,
                [stock, stock]
            ),
            "missingStage": ownerDisposition(
                speedPlan,
                [stock, copy(stock, vertex: missingVertexSpeed)]
            ),
            "extraStage": ownerDisposition(
                noisePlan,
                [stock, copy(stock, vertex: extraStageVertex)]
            ),
            "sameStageDuplicate": ownerDisposition(
                speedPlan,
                [stock, copy(stock, fragment: duplicateFragment)]
            ),
            "arrayDrift": ownerDisposition(
                speedPlan,
                [stock, copy(stock, vertex: arrayVertex)]
            ),
            "typeDrift": ownerDisposition(
                speedPlan,
                [stock, copy(stock, vertex: wrongTypeVertex)]
            ),
            "rangeDrift": ownerDisposition(
                speedPlan,
                [stock, copy(stock, vertex: wrongRangeVertex)]
            ),
            "phaseDisposition": ownerDisposition(
                phasePlan,
                [stock, stock]
            ),
            "boundsDisposition": ownerDisposition(
                boundsPlan,
                [stock, stock]
            ),
        ]
        let data = try JSONSerialization.data(
            withJSONObject: result,
            options: [.sortedKeys]
        )
        print(String(decoding: data, as: UTF8.self))
    }
}
'''


@unittest.skipUnless(shutil.which("swiftc"), "swiftc is required")
class ScenePulseDirectUserPropertyOwnerAdmissionTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.temporary_directory = tempfile.TemporaryDirectory(
            prefix="mwx-pulse-owner-admission-"
        )
        root = Path(cls.temporary_directory.name)
        support = root / "Support.swift"
        product_compiler = root / "ProductPulseCompiler.swift"
        harness = root / "Harness.swift"
        support.write_text(SUPPORT, encoding="utf-8")
        product_compiler.write_text(
            product_pulse_compiler_source(),
            encoding="utf-8",
        )
        harness.write_text(HARNESS, encoding="utf-8")

        cls.stock = root / "stock"
        (cls.stock / "shaders/effects").mkdir(parents=True)
        shutil.copy2(
            STOCK_ROOT / "effects/pulse/shaders/effects/pulse.vert",
            cls.stock / "shaders/effects/pulse.vert",
        )
        shutil.copy2(
            STOCK_ROOT / "effects/pulse/shaders/effects/pulse.frag",
            cls.stock / "shaders/effects/pulse.frag",
        )
        shutil.copy2(
            STOCK_ROOT / "shaders/common_blending.h",
            cls.stock / "shaders/common_blending.h",
        )

        binary = root / "pulse-owner-admission"
        environment = os.environ.copy()
        environment["HOME"] = str(root / "home")
        environment["CLANG_MODULE_CACHE_PATH"] = str(root / "clang-cache")
        environment["SWIFT_MODULECACHE_PATH"] = str(root / "swift-cache")
        compilation = subprocess.run(
            [
                "xcrun", "--sdk", "macosx", "swiftc", "-parse-as-library",
                str(support),
                *(str(path) for path in SWIFT_SOURCES),
                str(product_compiler),
                str(harness),
                "-framework", "Metal",
                "-framework", "CoreGraphics",
                "-framework", "ImageIO",
                "-module-cache-path", str(root / "module-cache"),
                "-o", str(binary),
            ],
            cwd=REPOSITORY_ROOT,
            env=environment,
            capture_output=True,
            text=True,
        )
        if compilation.returncode != 0:
            raise RuntimeError(compilation.stderr)
        completed = subprocess.run(
            [str(binary), str(cls.stock)],
            cwd=REPOSITORY_ROOT,
            env=environment,
            capture_output=True,
            text=True,
        )
        if completed.returncode != 0:
            raise RuntimeError(completed.stderr)
        cls.result = json.loads(completed.stdout)

    @classmethod
    def tearDownClass(cls) -> None:
        cls.temporary_directory.cleanup()

    def test_stock_direct_binding_cohort_revokes_the_incumbent(self) -> None:
        expected = "revoked:typed-user-property-rgb-owner-revoked-to-material-program"
        for key in ("productSpeed", "productAmount", "productCombined"):
            with self.subTest(key=key):
                self.assertEqual(self.result[key], expected)
        self.assertEqual(
            self.result["stockSpeedDisposition"],
            "revoke-dedicated-owner",
        )

    def test_non_cohort_bindings_retain_the_incumbent(self) -> None:
        for key in (
            "productPhase",
            "productBounds",
            "productMissingProducer",
            "productWrongProducerType",
        ):
            with self.subTest(key=key):
                self.assertEqual(self.result[key], "incumbent")
        self.assertEqual(self.result["phaseDisposition"], "retain-incumbent")
        self.assertEqual(self.result["boundsDisposition"], "retain-incumbent")

    def test_shader_schema_drift_retains_the_incumbent(self) -> None:
        for key in (
            "missingStage",
            "extraStage",
            "sameStageDuplicate",
            "arrayDrift",
            "typeDrift",
            "rangeDrift",
        ):
            with self.subTest(key=key):
                self.assertEqual(self.result[key], "retain-incumbent")


if __name__ == "__main__":
    unittest.main()
