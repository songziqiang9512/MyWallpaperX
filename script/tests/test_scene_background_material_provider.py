#!/usr/bin/env python3

"""Typed same-frame scene-background Program and route gate."""

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
FINALIZER_FIXTURE = runpy.run_path(
    str(Path(__file__).with_name("test_scene_resolved_material_program_finalizer.py"))
)

PROVIDER_SETUP = r'''
        func backgroundContract(_ revision: String) -> SceneShaderContract {
            let vertex = vertexSource(
                samplerMetadata: nil,
                deadMaskCoordinates: false,
                stageLocalUniforms: false
            )
            let fragment = """
            varying vec2 v_TexCoord;
            uniform sampler2D g_Texture1; // {"hidden":true,"default":"_rt_FullFrameBuffer"}
            void main() {
                gl_FragColor = texSample2D(g_Texture1, v_TexCoord);
            }
            """
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
            let stages = [
                stage(.vertex, path: "\(revision)/root.vert", source: vertex),
                stage(.fragment, path: "\(revision)/root.frag", source: fragment),
            ]
            let sourceGraph = SceneShaderSourceGraph(
                roots: [
                    .init(label: "vertex", virtualPath: "\(revision)/root.vert"),
                    .init(label: "fragment", virtualPath: "\(revision)/root.frag"),
                ],
                nodes: stages.map { value in
                    .init(
                        virtualPath: value.relativePath,
                        provenance: .package,
                        source: value.source,
                        rawSHA256: value.rawSHA256,
                        byteCount: value.source.utf8.count
                    )
                },
                edges: [],
                diagnostics: [],
                dependencySHA256: "fixture-dependency-\(revision)"
            )
            return .init(
                identity: "fixture/\(revision)",
                sourceKind: .authoredSource,
                stages: stages,
                diagnostics: [],
                canonicalSHA256: "fixture-contract-\(revision)",
                sourceGraph: sourceGraph
            )
        }
        func backgroundTexture(_ usage: MTLTextureUsage) -> MTLTexture {
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: .bgra8Unorm,
                width: 8,
                height: 8,
                mipmapped: false
            )
            descriptor.storageMode = .shared
            descriptor.usage = usage
            return device.makeTexture(descriptor: descriptor)!
        }
        let readableBackground = backgroundTexture([.shaderRead, .renderTarget])
        let backgroundResource = SceneFrameTextureResource.sameFrameSceneBackground(
            consumerLayerID: fixtureLayerID,
            frameEpoch: 1,
            texture: readableBackground
        )
        let backgroundReference = Template.TextureReference.provider(
            .sceneBackground(consumerLayerID: fixtureLayerID)
        )
        let backgroundEffectContext = Template.EffectContext(
            key: Graph.EffectKey(
                layerID: fixtureLayerID,
                effectIndex: 0,
                descriptorID: "scene-background-provider"
            ),
            input: graphTexture()
        )
        let backgroundProgram = finalize(
            shader: backgroundContract("scene-background-provider"),
            device: device,
            includePrimaryCandidate: false,
            secondReference: backgroundReference,
            additionalEntries: backgroundResource.map {
                [.sceneBackground(fixtureLayerID): .ready($0)]
            } ?? [:],
            effectContext: backgroundEffectContext
        )
        let missingBackgroundProgram = finalize(
            shader: backgroundContract("scene-background-missing"),
            device: device,
            includePrimaryCandidate: false,
            secondReference: backgroundReference,
            effectContext: backgroundEffectContext
        )
        let shaderDefaultBackgroundProgram = finalize(
            shader: backgroundContract("scene-background-shader-default"),
            device: device,
            includePrimaryCandidate: false,
            additionalEntries: backgroundResource.map {
                [.sceneBackground(fixtureLayerID): .ready($0)]
            } ?? [:],
            effectContext: backgroundEffectContext
        )
        let backgroundProgramIdentity: Bool = {
            guard case let .success(program) = backgroundProgram,
                  let slot = program.textureSlots[1] else { return false }
            return slot.reference == backgroundReference
                && slot.registryIdentity == .sceneBackground(fixtureLayerID)
                && slot.resource.publication.texture === readableBackground
                && slot.expectedPurpose == .premultipliedColor
        }()
        let staleBackground = SceneFrameTextureResource.sameFrameSceneBackground(
            consumerLayerID: fixtureLayerID,
            frameEpoch: 2,
            texture: readableBackground
        )
        let frameOne = snapshot(device, kind: .ready, frameIndex: 1)
        let staleOverlayRejected = staleBackground.map {
            frameOne.overlayingSceneBackground(
                consumerLayerID: fixtureLayerID,
                resource: $0
            ) == nil
        } ?? false
        let wrongLayerRejected = backgroundResource.map {
            frameOne.overlayingSceneBackground(
                consumerLayerID: fixtureLayerID + 1,
                resource: $0
            ) == nil
        } ?? false
        let unreadableRejected = SceneFrameTextureResource
            .sameFrameSceneBackground(
                consumerLayerID: fixtureLayerID,
                frameEpoch: 1,
                texture: backgroundTexture([.renderTarget])
            ) == nil
        let sceneBackgroundProvider: [String: Any] = [
            "programIdentity": backgroundProgramIdentity,
            "programFailure": failureToken(backgroundProgram),
            "shaderDefaultFailure": failureToken(shaderDefaultBackgroundProgram),
            "missingFailure": failureToken(missingBackgroundProgram),
            "staleOverlayRejected": staleOverlayRejected,
            "wrongLayerRejected": wrongLayerRejected,
            "unreadableRejected": unreadableRejected,
        ]
'''


def augmented_harness() -> str:
    harness = FINALIZER_FIXTURE["HARNESS"]
    result_marker = "        let result: [String: Any] = ["
    key_marker = '            "metalAvailable": true,'
    if harness.count(result_marker) != 1 or harness.count(key_marker) != 1:
        raise RuntimeError("finalizer harness insertion point changed")
    harness = harness.replace(result_marker, PROVIDER_SETUP + "\n" + result_marker)
    return harness.replace(
        key_marker,
        key_marker + '\n            "sceneBackgroundProvider": sceneBackgroundProvider,',
    )


@unittest.skipUnless(shutil.which("swiftc"), "swiftc is required")
class SceneBackgroundMaterialProviderTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.temporary_directory = tempfile.TemporaryDirectory(
            prefix="mwx-scene-background-provider-"
        )
        root = Path(cls.temporary_directory.name)
        support = root / "Support.swift"
        harness = root / "Harness.swift"
        binary = root / "scene-background-provider-test"
        support.write_text(FINALIZER_FIXTURE["SUPPORT"], encoding="utf-8")
        harness.write_text(augmented_harness(), encoding="utf-8")
        environment = os.environ.copy()
        environment["CLANG_MODULE_CACHE_PATH"] = str(root / "clang-cache")
        environment["SWIFT_MODULECACHE_PATH"] = str(root / "swift-cache")
        environment["MWX_SCENE_GENERIC_SHADER_ROUTE"] = "disable-generic"
        compilation = subprocess.run(
            [
                "xcrun", "--sdk", "macosx", "swiftc", "-parse-as-library",
                str(support),
                *(str(path) for path in FINALIZER_FIXTURE["SWIFT_SOURCES"]),
                str(harness),
                "-framework", "Metal", "-framework", "CoreGraphics",
                "-framework", "ImageIO", "-module-cache-path",
                str(root / "module-cache"), "-o", str(binary),
            ],
            cwd=REPOSITORY_ROOT,
            env=environment,
            capture_output=True,
            text=True,
        )
        if compilation.returncode != 0:
            raise RuntimeError(compilation.stderr)
        completed = subprocess.run(
            [str(binary)], cwd=REPOSITORY_ROOT, env=environment,
            capture_output=True, text=True,
        )
        if completed.returncode != 0:
            raise RuntimeError(completed.stderr or completed.stdout)
        cls.result = json.loads(completed.stdout)["sceneBackgroundProvider"]

    @classmethod
    def tearDownClass(cls) -> None:
        cls.temporary_directory.cleanup()

    def test_program_consumes_only_complete_same_frame_provider(self) -> None:
        self.assertTrue(self.result["programIdentity"], self.result)
        self.assertEqual(self.result["shaderDefaultFailure"], "success")
        self.assertEqual(
            self.result["missingFailure"],
            "texture/resourceSnapshotUnresolved",
        )
        self.assertTrue(self.result["staleOverlayRejected"], self.result)
        self.assertTrue(self.result["wrongLayerRejected"], self.result)
        self.assertTrue(self.result["unreadableRejected"], self.result)

    def test_route_is_exact_and_layer_ordered(self) -> None:
        compiler = (
            SCENE_ROOT / "RenderGraph/MaterialProgram/SceneResolvedMaterialTemplateCompiler.swift"
        ).read_text(encoding="utf-8")
        capability = (
            SCENE_ROOT / "RenderGraph/EffectExecution/SceneResolvedMaterialExecutionCapability+ProgramFirstStages.swift"
        ).read_text(encoding="utf-8")
        capability_report = (
            SCENE_ROOT / "RenderGraph/EffectExecution/SceneResolvedMaterialExecutionCapability.swift"
        ).read_text(encoding="utf-8")
        composition = (
            SCENE_ROOT / "Rendering/SceneResolvedMaterialGraphComposition.swift"
        ).read_text(encoding="utf-8")
        self.assertIn('caseInsensitiveCompare("_rt_FullFrameBuffer")', compiler)
        self.assertIn("sceneBackgroundCandidateIsOrdered", capability)
        self.assertIn("candidateNode.nodeIndex == nodes.last?.nodeIndex", capability)
        self.assertIn("!admitted.isGraphOutputProvider", capability)
        self.assertIn("case .none, .externalPrimary: true", capability)
        self.assertIn("scene-background-provider-ambiguous", capability)
        self.assertIn("scene-background-compose-shape", capability)
        self.assertIn("schema=scene-background-provider-v1", capability_report)
        self.assertNotIn("sceneBackground=same-frame-main-target", capability_report)
        self.assertIn("mainPass.withReadableTarget", composition)
        background_section = capability.split(
            "private static func sceneBackgroundRequirement", 1
        )[1].split("/// Only a launch-time", 1)[0]
        self.assertNotIn("sampleID", background_section)
        self.assertNotIn("descriptorID ==", background_section)


if __name__ == "__main__":
    unittest.main()
