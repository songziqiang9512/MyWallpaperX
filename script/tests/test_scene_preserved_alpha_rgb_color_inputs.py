#!/usr/bin/env python3

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
sys.path.insert(0, str(REPOSITORY_ROOT / "script"))

from scene_swift_source_sets import scene_swift_sources


SWIFT_SOURCES = [
    *scene_swift_sources("authored_shader_frontend_core"),
    *scene_swift_sources("shader_variant_environment"),
    SCENE_ROOT / "RenderGraph/AuthoredGraph/SceneAuthoredEffectRenderPlan.swift",
    SCENE_ROOT / "RenderGraph/SceneMaterialRenderState.swift",
    SCENE_ROOT / "Resources/SceneTextureSampling.swift",
    SCENE_ROOT / "Resources/SceneTextureUVTransform.swift",
    SCENE_ROOT / "Resources/SceneTextureCandidate.swift",
    SCENE_ROOT / "Resources/SceneTextureSlotBinding.swift",
    SCENE_ROOT / "Resources/SceneNamedTextureReference.swift",
    SCENE_ROOT / "Resources/SceneTextureProviderPublication.swift",
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

nonisolated enum SceneFrameTextureIdentity: Hashable {
    case layerSource(Int)
    case namedLayerTarget(SceneNamedTextureReference)
    case sceneBackground(Int)
    case graph(SceneAuthoredEffectRenderPlan.TextureIdentity)
    case asset(SceneAssetTextureIdentity)
    case userProperty(String)
    case materialUserProperty(SceneUserPropertyTextureIdentity)
    case system(String)
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

        let result: [String: Bool] = [
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
        ]
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
            subprocess.run(
                [
                    swiftc,
                    "-parse-as-library",
                    *(str(path) for path in SWIFT_SOURCES),
                    str(support),
                    str(harness),
                    "-o", str(binary),
                ],
                cwd=REPOSITORY_ROOT,
                env=environment,
                check=True,
                capture_output=True,
                text=True,
            )
            completed = subprocess.run(
                [str(binary)],
                cwd=REPOSITORY_ROOT,
                check=True,
                capture_output=True,
                text=True,
            )
        self.assertTrue(all(json.loads(completed.stdout).values()))


if __name__ == "__main__":
    unittest.main()
