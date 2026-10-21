#!/usr/bin/env python3

import json
import hashlib
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
SCENE_ROOT = REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene"
sys.path.insert(0, str(REPOSITORY_ROOT / "script"))

from scene_swift_source_sets import scene_swift_sources


SWIFT_SOURCES = [
    *scene_swift_sources("authored_shader_frontend_core"),
    *scene_swift_sources("shader_variant_environment"),
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Compilation/Graph/SceneAuthoredEffectRenderPlan.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Runtime/Frame/SceneMaterialRenderState.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Compilation/Material/SceneMaterialRenderState+Compilation.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Resources/Textures/SceneTextureSampling.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Resources/Textures/SceneTextureUVTransform.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Resources/Textures/SceneTextureCandidate.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Resources/Textures/SceneTextureSlotBinding.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Resources/Textures/SceneNamedTextureReference.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Resources/Textures/SceneTextureProviderPublication.swift",
    *scene_swift_sources("resolved_material_program_model"),
]


SUPPORT = r'''
import Foundation
import Metal

nonisolated enum SceneTextureLoadPurpose: Hashable, Sendable {
    case premultipliedColor
    case straightAlbedo
    case preservedChannels
    case mask
    case noise
    case flow
    case phase
    case normal
    case depth
    case lookupTable

    var requiresVolumeTexture: Bool { self == .lookupTable }
}

nonisolated struct SceneResolvedMaterialNode {
    enum TextureProvenance: String, Hashable {
        case material
        case instance
        case userTexture
        case explicitBinding
    }
}

nonisolated enum SceneDynamicTarget: Hashable {
    case effectConstant(layerID: Int, effectIndex: Int, passIndex: Int, name: String)
}

nonisolated enum SceneDynamicSource: Hashable {
    case authored
    case userProperty
    case timeline
    case sceneScript
}

nonisolated struct SceneSystemProviderTextureIdentity: Hashable {
    let name: String
    let purpose: SceneTextureLoadPurpose
}

nonisolated enum SceneFrameTextureIdentity: Hashable {
    case sceneEnvironment
    case layerSource(Int)
    case namedLayerTarget(SceneNamedTextureReference)
    case sceneBackground(Int)
    case graph(SceneAuthoredEffectRenderPlan.TextureIdentity)
    case asset(SceneAssetTextureIdentity)
    case userProperty(String)
    case materialUserProperty(SceneUserPropertyTextureIdentity)
    case system(SceneSystemProviderTextureIdentity)
}
'''


HARNESS = r'''
import Foundation

private typealias Derivation = SceneResolvedMaterialProgramDerivation
private typealias Fact = Derivation.ColorTextureFact

private func facts(_ content: [Int: SceneTextureContent]) -> [Fact?] {
    (0 ..< 8).map { slot in
        content[slot].map {
            .init(
                isGraphReference: true,
                isFramebufferInput: true,
                content: $0
            )
        }
    }
}

private func independentAuxiliaryProfiles() -> [String: Bool] {
    let signal = SceneTextureContent.color(.resolved(.independentAlphaSignal))
    let opaque = SceneTextureContent.color(.resolved(.opaque))
    let pma = SceneTextureContent.color(.resolved(.premultipliedAlpha))
    let straight = SceneTextureContent.color(.resolved(.straightAlpha))
    let unresolved = SceneTextureContent.color(.unresolved)
    let transfer = SceneShaderColorTransfer.independentAlphaSignalCompositing(
        signalSlot: 0, colorSlot: 1)
    let boundary = SceneShaderColorBoundary(colorInputSlots: [1],
        outputRepresentation: .premultipliedAlpha)
    var result: [String: Bool] = [:]
    let vertex = """
    attribute vec3 a_Position;
    attribute vec2 a_TexCoord;
    varying vec2 v_Point;
    void main(){v_Point=a_TexCoord;gl_Position=vec4(a_Position,1.0);}
    """
    // These numerical vector producers establish opaque by their output
    // alpha, independent of resource paths or the consumer's vector formula.
    for (name, slot, sample, component, local, output) in [
        ("own-vector", 2, "texSample2D", "a", "height", "vec4(axis*0.5+vec3(0.5),1.0)"),
        ("relocated-field", 5, "texture2D", "w", "amount", "vec4(0.5*axis+vec3(0.5),1.0)")
    ] {
        let source = """
        varying vec2 v_Point;
        uniform sampler2D g_Texture\(slot);
        void main(){
            float \(local)=\(sample)(g_Texture\(slot),v_Point).\(component);
            vec3 axis=normalize(vec3(\(local)-0.25,0.5,1.0));
            gl_FragColor=\(output);
        }
        """
        let compiled = SceneAuthoredShaderFrontend.compile(vertexSource: vertex, fragmentSource: source)
        result["opaque-vector-source-" + name] = compiled.program?.colorTransfer == .opaque
            && compiled.program?.textureBindings.map(\.slot) == [slot]
            && compiled.program?.textureBindings.first?.channelUse == .alphaOnly
    }
    for (leftName, left) in [("data", SceneTextureContent.data), ("opaque", opaque)] {
        for (rightName, right) in [("data", SceneTextureContent.data), ("opaque", opaque)] {
            for (label, adapter) in [("native", Optional<SceneShaderColorBoundary>.none),
                                     ("boundary", boundary)] {
                result["signalAux-" + label + "-" + leftName + "-" + rightName] =
                    Derivation.resolveColor(transfer: transfer,
                        textureFacts: facts([0: signal, 1: pma, 2: left, 3: right]),
                        colorBoundary: adapter) == .init(
                            framebufferInput: adapter == nil ? .premultipliedAlpha : .straightAlpha,
                            fragmentOutput: .premultipliedAlpha)
            }
        }
    }
    for (label, adapter) in [("native", Optional<SceneShaderColorBoundary>.none),
                             ("boundary", boundary)] {
        for (name, value) in [("pma", pma), ("straight", straight),
                              ("signal", signal), ("unresolved", unresolved)] {
            result["signalAux-" + label + "-reject-" + name] = Derivation.resolveColor(
                transfer: transfer, textureFacts: facts([0: signal, 1: pma, 2: value, 3: .data]),
                colorBoundary: adapter) == nil
        }
        for (name, value) in [("data", SceneTextureContent.data), ("opaque", opaque),
                              ("pma", pma), ("straight", straight), ("unresolved", unresolved)] {
            result["signalCarrier-" + label + "-reject-" + name] = Derivation.resolveColor(
                transfer: transfer, textureFacts: facts([0: value, 1: pma, 2: .data]),
                colorBoundary: adapter) == nil
        }
        for (name, value) in [("data", SceneTextureContent.data),
                              ("signal", signal), ("unresolved", unresolved)] {
            result["colorCarrier-" + label + "-reject-" + name] = Derivation.resolveColor(
                transfer: transfer, textureFacts: facts([0: signal, 1: value, 2: .data]),
                colorBoundary: adapter) == nil
        }
        result["signalCarrier-" + label + "-missing"] = Derivation.resolveColor(
            transfer: transfer, textureFacts: facts([1: pma, 2: .data]), colorBoundary: adapter) == nil
        result["colorCarrier-" + label + "-missing"] = Derivation.resolveColor(
            transfer: transfer, textureFacts: facts([0: signal, 2: .data]), colorBoundary: adapter) == nil
    }
    result["colorCarrier-straight-requires-boundary"] = Derivation.resolveColor(
        transfer: transfer, textureFacts: facts([0: signal, 1: straight, 2: .data])) == nil
    result["colorCarrier-straight-adapted"] = Derivation.resolveColor(transfer: transfer,
        textureFacts: facts([0: signal, 1: straight, 2: opaque]), colorBoundary: boundary) != nil
    let underlay = SceneShaderColorTransfer.independentAlphaSignalUnderlayCompositing(
        signalSlot: 0, colorSlot: 1, underlaySlot: 4)
    let underlayBoundary = SceneShaderColorBoundary(colorInputSlots: [1, 4],
        outputRepresentation: .premultipliedAlpha)
    result["underlay-opaque-auxiliary"] = Derivation.resolveColor(transfer: underlay,
        textureFacts: facts([0: signal, 1: pma, 2: opaque, 3: .data, 4: pma])) != nil
    result["underlay-mixed-color-without-boundary-rejected"] = Derivation.resolveColor(
        transfer: underlay, textureFacts: facts([0: signal, 1: pma, 2: .data, 4: opaque])) == nil
    result["underlay-mixed-color-with-boundary"] = Derivation.resolveColor(transfer: underlay,
        textureFacts: facts([0: signal, 1: pma, 2: opaque, 3: .data, 4: opaque]),
        colorBoundary: underlayBoundary) != nil
    result["underlay-data-color-carrier-rejected"] = Derivation.resolveColor(transfer: underlay,
        textureFacts: facts([0: signal, 1: pma, 2: .data, 4: .data]),
        colorBoundary: underlayBoundary) == nil
    result["underlay-unresolved-color-carrier-rejected"] = Derivation.resolveColor(transfer: underlay,
        textureFacts: facts([0: signal, 1: pma, 2: .data, 4: unresolved]),
        colorBoundary: underlayBoundary) == nil
    result["preserving-opaque-auxiliary-stays-rejected"] = Derivation.resolveColor(
        transfer: .independentAlphaSignalPreserving(textureSlot: 0),
        textureFacts: facts([0: signal, 2: opaque])) == nil
    result["signal-passthrough-opaque-auxiliary-stays-rejected"] = Derivation.resolveColor(
        transfer: .passthrough(textureSlot: 0), textureFacts: facts([0: signal, 2: opaque]),
        colorBoundary: .init(colorInputSlots: [0], outputRepresentation: .independentAlphaSignal,
            signalPassthroughSlot: 0)) == nil
    return result
}

@main
private enum Harness {
    static func main() throws {
        let premultiplied = SceneTextureContent.color(
            .resolved(.premultipliedAlpha)
        )
        let opaque = SceneTextureContent.color(.resolved(.opaque))
        let independent = SceneTextureContent.color(
            .resolved(.independentAlphaSignal)
        )
        let unresolved = SceneTextureContent.color(.unresolved)
        let conditionalContract =
            Derivation.ConditionalGeneratedRGBInputContract(
                alphaCarrierSlot: 2,
                generatedOpaqueColorSlots: [0],
                scalarRedSlots: [],
                scalarGreenSlots: [],
                scalarBlueSlots: [],
                scalarAlphaSlots: []
            )
        let reconstructedContract =
            Derivation.SameAlphaReconstructedRGBInputContract(
                sourceSlot: 0,
                dataSlots: [1]
            )

        var result: [String: Bool] = [
            "twoPremultipliedAccepted":
                Derivation.hasResolvedColorSampleContract(
                    colorSlots: [0, 2],
                    textureFacts: facts([0: premultiplied, 2: premultiplied])
                ),
            "sampleGateAcceptsSupportedRepresentationsPerSlot":
                Derivation.hasResolvedColorSampleContract(
                    colorSlots: [0, 2],
                    textureFacts: facts([0: opaque, 2: premultiplied])
                ),
            "dataReferenceRejected":
                !Derivation.hasResolvedColorSampleContract(
                    colorSlots: [0, 2],
                    textureFacts: facts([0: .data, 2: premultiplied])
                ),
            "r8ReferenceRejected":
                !Derivation.hasResolvedColorSampleContract(
                    colorSlots: [0, 2],
                    textureFacts: facts([0: .scalarRedUnorm, 2: premultiplied])
                ),
            "rgReferenceRejected":
                !Derivation.hasResolvedColorSampleContract(
                    colorSlots: [0, 2],
                    textureFacts: facts([0: .redGreenFloat16, 2: premultiplied])
                ),
            "independentSignalRejected":
                !Derivation.hasResolvedColorSampleContract(
                    colorSlots: [0, 2],
                    textureFacts: facts([0: independent, 2: premultiplied])
                ),
            "unresolvedColorRejected":
                !Derivation.hasResolvedColorSampleContract(
                    colorSlots: [0, 2],
                    textureFacts: facts([0: unresolved, 2: premultiplied])
                ),
            "missingReferenceRejected":
                !Derivation.hasResolvedColorSampleContract(
                    colorSlots: [0, 2],
                    textureFacts: facts([2: premultiplied])
                ),
            "emptyFactAccepted":
                Derivation.hasResolvedColorSampleContract(
                    colorSlots: [],
                    textureFacts: facts([0: .data])
                ),
            "wrongTextureArityRejected":
                !Derivation.hasResolvedColorSampleContract(
                    colorSlots: [0],
                    textureFacts: Array(facts([0: premultiplied]).prefix(7))
                ),
            "generatedOpaqueAccepted":
                Derivation.hasResolvedOpaqueColorSampleContract(
                    colorSlots: [0],
                    textureFacts: facts([0: opaque, 2: premultiplied])
                ),
            "generatedPremultipliedRejected":
                !Derivation.hasResolvedOpaqueColorSampleContract(
                    colorSlots: [0],
                    textureFacts: facts([0: premultiplied, 2: premultiplied])
                ),
            "generatedDataRejected":
                !Derivation.hasResolvedOpaqueColorSampleContract(
                    colorSlots: [0],
                    textureFacts: facts([0: .data, 2: premultiplied])
                ),
            "generatedMissingRejected":
                !Derivation.hasResolvedOpaqueColorSampleContract(
                    colorSlots: [0],
                    textureFacts: facts([2: premultiplied])
                ),
            "emptyGeneratedSetAccepted":
                Derivation.hasResolvedOpaqueColorSampleContract(
                    colorSlots: [],
                    textureFacts: facts([2: premultiplied])
                ),
            "nonConditionalMixedRepresentationRejected":
                Derivation.resolveColor(
                    transfer: .straightAlphaPreserving(textureSlot: 2),
                    textureFacts: facts([0: opaque, 2: premultiplied])
                ) == nil,
            "conditionalProjectionAcceptsOpaqueGeneratedRGB":
                Derivation.resolveColor(
                    transfer: .straightAlphaPreserving(textureSlot: 2),
                    textureFacts: facts([0: opaque, 2: premultiplied]),
                    conditionalGeneratedRGBInputContract: conditionalContract
                ) == .init(
                    framebufferInput: .premultipliedAlpha,
                    fragmentOutput: .premultipliedAlpha
                ),
            "conditionalProjectionRejectsPremultipliedGeneratedRGB":
                Derivation.resolveColor(
                    transfer: .straightAlphaPreserving(textureSlot: 2),
                    textureFacts: facts([
                        0: premultiplied,
                        2: premultiplied,
                    ]),
                    conditionalGeneratedRGBInputContract: conditionalContract
                ) == nil,
            "conditionalProjectionAcceptsLoweredPremultipliedGeneratedRGB":
                Derivation.resolveColor(
                    transfer: .straightAlphaPreserving(textureSlot: 2),
                    textureFacts: facts([
                        0: premultiplied,
                        2: premultiplied,
                    ]),
                    conditionalGeneratedRGBInputContract: conditionalContract,
                    premultipliedColorInputSlots: [0]
                ) == .init(
                    framebufferInput: .premultipliedAlpha,
                    fragmentOutput: .premultipliedAlpha
                ),
            "conditionalProjectionAcceptsLoweredOpaqueGeneratedRGB":
                Derivation.resolveColor(
                    transfer: .straightAlphaPreserving(textureSlot: 2),
                    textureFacts: facts([
                        0: opaque,
                        2: premultiplied,
                    ]),
                    conditionalGeneratedRGBInputContract: conditionalContract,
                    premultipliedColorInputSlots: [0]
                ) == .init(
                    framebufferInput: .premultipliedAlpha,
                    fragmentOutput: .premultipliedAlpha
                ),
            "conditionalProjectionRejectsLoweredCarrierInsteadOfGeneratedRGB":
                Derivation.resolveColor(
                    transfer: .straightAlphaPreserving(textureSlot: 2),
                    textureFacts: facts([
                        0: premultiplied,
                        2: premultiplied,
                    ]),
                    conditionalGeneratedRGBInputContract: conditionalContract,
                    premultipliedColorInputSlots: [2]
                ) == nil,
            "conditionalProjectionRejectsUnresolvedCarrier":
                Derivation.resolveColor(
                    transfer: .straightAlphaPreserving(textureSlot: 2),
                    textureFacts: facts([0: opaque, 2: unresolved]),
                    conditionalGeneratedRGBInputContract: conditionalContract
                ) == nil,
            "scalarRedAcceptsR8":
                Derivation.hasResolvedConditionalGeneratedRGBInputContract(
                    .init(
                        alphaCarrierSlot: 2,
                        generatedOpaqueColorSlots: [],
                        scalarRedSlots: [1],
                        scalarGreenSlots: [],
                        scalarBlueSlots: [],
                        scalarAlphaSlots: []
                    ),
                    textureFacts: facts([1: .scalarRedUnorm])
                ),
            "scalarGreenRejectsR8":
                !Derivation.hasResolvedConditionalGeneratedRGBInputContract(
                    .init(
                        alphaCarrierSlot: 2,
                        generatedOpaqueColorSlots: [],
                        scalarRedSlots: [],
                        scalarGreenSlots: [1],
                        scalarBlueSlots: [],
                        scalarAlphaSlots: []
                    ),
                    textureFacts: facts([1: .scalarRedUnorm])
                ),
            "scalarGreenAcceptsRG":
                Derivation.hasResolvedConditionalGeneratedRGBInputContract(
                    .init(
                        alphaCarrierSlot: 2,
                        generatedOpaqueColorSlots: [],
                        scalarRedSlots: [],
                        scalarGreenSlots: [1],
                        scalarBlueSlots: [],
                        scalarAlphaSlots: []
                    ),
                    textureFacts: facts([1: .redGreenFloat16])
                ),
            "scalarBlueRejectsRG":
                !Derivation.hasResolvedConditionalGeneratedRGBInputContract(
                    .init(
                        alphaCarrierSlot: 2,
                        generatedOpaqueColorSlots: [],
                        scalarRedSlots: [],
                        scalarGreenSlots: [],
                        scalarBlueSlots: [1],
                        scalarAlphaSlots: []
                    ),
                    textureFacts: facts([1: .redGreenFloat16])
                ),
            "scalarRGBRejectsPremultipliedColor":
                !Derivation.hasResolvedConditionalGeneratedRGBInputContract(
                    .init(
                        alphaCarrierSlot: 2,
                        generatedOpaqueColorSlots: [],
                        scalarRedSlots: [1],
                        scalarGreenSlots: [],
                        scalarBlueSlots: [],
                        scalarAlphaSlots: []
                    ),
                    textureFacts: facts([1: premultiplied])
                ),
            "scalarAlphaAcceptsPremultipliedColor":
                Derivation.hasResolvedConditionalGeneratedRGBInputContract(
                    .init(
                        alphaCarrierSlot: 2,
                        generatedOpaqueColorSlots: [],
                        scalarRedSlots: [],
                        scalarGreenSlots: [],
                        scalarBlueSlots: [],
                        scalarAlphaSlots: [1]
                    ),
                    textureFacts: facts([1: premultiplied])
                ),
            "scalarAlphaRejectsR8BackendDefault":
                !Derivation.hasResolvedConditionalGeneratedRGBInputContract(
                    .init(
                        alphaCarrierSlot: 2,
                        generatedOpaqueColorSlots: [],
                        scalarRedSlots: [],
                        scalarGreenSlots: [],
                        scalarBlueSlots: [],
                        scalarAlphaSlots: [1]
                    ),
                    textureFacts: facts([1: .scalarRedUnorm])
                ),
            "reconstructedAcceptsPremultipliedSourceAndData":
                Derivation.hasResolvedSameAlphaReconstructedRGBInputContract(
                    reconstructedContract,
                    textureFacts: facts([0: premultiplied, 1: .data])
                ),
            "reconstructedAcceptsOpaqueSourceAndData":
                Derivation.hasResolvedSameAlphaReconstructedRGBInputContract(
                    reconstructedContract,
                    textureFacts: facts([0: opaque, 1: .data])
                ),
            "reconstructedRejectsColorAuxiliary":
                !Derivation.hasResolvedSameAlphaReconstructedRGBInputContract(
                    reconstructedContract,
                    textureFacts: facts([0: premultiplied, 1: opaque])
                ),
            "reconstructedRejectsScalarAuxiliary":
                !Derivation.hasResolvedSameAlphaReconstructedRGBInputContract(
                    reconstructedContract,
                    textureFacts: facts([
                        0: premultiplied,
                        1: .redGreenUnorm,
                    ])
                ),
            "reconstructedRejectsMissingAuxiliary":
                !Derivation.hasResolvedSameAlphaReconstructedRGBInputContract(
                    reconstructedContract,
                    textureFacts: facts([0: premultiplied])
                ),
            "reconstructedRejectsUnresolvedSource":
                !Derivation.hasResolvedSameAlphaReconstructedRGBInputContract(
                    reconstructedContract,
                    textureFacts: facts([0: unresolved, 1: .data])
                ),
            "reconstructedRejectsOverlappingRoles":
                !Derivation.hasResolvedSameAlphaReconstructedRGBInputContract(
                    .init(sourceSlot: 0, dataSlots: [0]),
                    textureFacts: facts([0: premultiplied])
                ),
        ]
        result.merge(independentAuxiliaryProfiles()) { _, new in new }
        FileHandle.standardOutput.write(try JSONEncoder().encode(result))
    }
}
'''


class ScenePreservedAlphaRGBColorInputTests(unittest.TestCase):
    def test_all_source_fact_color_slots_are_typed_color(self):
        swiftc = shutil.which("swiftc")
        if swiftc is None:
            self.skipTest("swiftc is unavailable")
        with tempfile.TemporaryDirectory(
            prefix="mwx-scene-preserved-rgb-color-"
        ) as directory:
            root = Path(directory)
            support = root / "Support.swift"
            support.write_text(SUPPORT, encoding="utf-8")
            harness = root / "Harness.swift"
            harness.write_text(HARNESS, encoding="utf-8")
            binary = root / "preserved-rgb-color-input-harness"
            environment = os.environ.copy()
            environment["CLANG_MODULE_CACHE_PATH"] = str(
                root / "clang-module-cache"
            )
            environment["SWIFT_MODULECACHE_PATH"] = str(
                root / "swift-module-cache"
            )
            sources = []
            hashes = {}
            for index, path in enumerate(dict.fromkeys(SWIFT_SOURCES)):
                data = path.read_bytes()
                hashes[str(path)] = hashlib.sha256(data).hexdigest()
                frozen = root / f"source-{index}-{path.name}"
                frozen.write_bytes(data)
                sources.append(frozen)
            compilation = subprocess.run(
                [
                    swiftc,
                    "-parse-as-library",
                    *(str(path) for path in sources),
                    str(support),
                    str(harness),
                    "-o", str(binary),
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
                check=True,
                capture_output=True,
                text=True,
            )
            result = json.loads(completed.stdout)
            evidence = os.environ.get("MWX_OPAQUE_AUX_EVIDENCE")
            if evidence:
                destination = Path(evidence)
                destination.mkdir(parents=True, exist_ok=True)
                (destination / "profiles.json").write_text(json.dumps(result, indent=2) + "\n")
                (destination / "inputs.json").write_text(json.dumps(hashes, indent=2) + "\n")
                (destination / "compile.log").write_text(compilation.stdout + compilation.stderr)
        failed = {name: passed for name, passed in result.items() if not passed}
        self.assertFalse(failed, failed)


if __name__ == "__main__":
    unittest.main()
