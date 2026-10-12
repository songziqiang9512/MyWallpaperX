"""Authored video TEX assets through the real provider and image GPU pipeline."""

from __future__ import annotations

import json
import os
from pathlib import Path
import shutil
import struct
import subprocess
import tempfile
import unittest
import zlib

from script.tests import test_scene_sampler_default_purpose as sampler
from script.tests import test_scene_user_property_textures as textures

ROOT = Path(__file__).resolve().parents[2]
SCENE = ROOT / "MyWallpaperX/Core/SteamWorkshopScene"


def video_tex(payload: bytes, *, flags: int = 2) -> bytes:
    return (b"TEXV0005\0TEXI0001\0"
            + struct.pack("<7I", 0, flags, 32, 24, 32, 24, 0)
            + b"TEXB0003\0" + struct.pack("<Ii6I", 1, -1, 1, 32, 24, 0, 0, len(payload))
            + payload)


BASELINE = r'''
import Foundation
import Metal
import simd

func mediaTemplate(_ path: SceneVFSAssetPath, variant: Int) -> SceneResolvedMaterialTemplate {
    let slot = variant == 0 ? 0 : 2
    let varying = variant == 0 ? "v_TexCoord" : "renamedUV"
    let name = variant == 0 ? "self/neutral" : "alternate/renamed-resource"
    let result = variant == 0
        ? "gl_FragColor = texSample2D(g_Texture0, v_TexCoord);"
        : "vec2 copiedUV = renamedUV; vec4 sampledColor = texSample2D(g_Texture2, copiedUV); gl_FragColor = sampledColor;"
    let sources: [(SceneShaderContract.StageKind, String, String)] = [
        (.vertex, name + ".vert", """
        attribute vec3 a_Position;
        attribute vec2 a_TexCoord;
        varying vec2 \(varying);
        void main() { \(varying) = a_TexCoord; gl_Position = vec4(a_Position, 1.0); }
        """),
        (.fragment, name + ".frag", """
        varying vec2 \(varying);
        uniform sampler2D g_Texture\(slot);
        void main() { \(result) }
        """),
    ]
    let stages: [SceneShaderContract.Stage] = sources.map { kind, name, source in
        let parsed = SceneShaderContractSourceParser().parse(source, stageRelativePath: name)
        return .init(kind: kind, relativePath: name, source: source,
            rawSHA256: SceneShaderStableDigest.hash(Data(source.utf8)), includes: parsed.includes,
            annotations: parsed.annotations, declarations: parsed.declarations)
    }
    let hash = SceneShaderStableDigest.hash(Data(sources.map { $0.2 }.joined().utf8))
    let contract = SceneShaderContract(identity: name, sourceKind: .authoredSource,
        stages: stages, diagnostics: [], canonicalSHA256: hash, sourceGraph: .init(
            roots: stages.map { .init(label: $0.kind.rawValue, virtualPath: $0.relativePath) },
            nodes: stages.map { .init(virtualPath: $0.relativePath, provenance: .package, source: $0.source,
                rawSHA256: $0.rawSHA256, byteCount: $0.source.utf8.count) },
            edges: [], diagnostics: [], dependencySHA256: hash))
    var slots = Array<SceneResolvedMaterialTemplate.TextureSlot?>(repeating: nil, count: 8)
    slots[slot] = .init(index: slot, candidates: [.init(reference: .asset(path), provenance: .explicitBinding)])
    return .validated(textureSlots: slots, combos: [], uniformDeclarations: [],
        renderState: SceneMaterialRenderState.compile(blending: "normal", depthTest: "disabled",
            depthWrite: "disabled", cullMode: "nocull", alphaWriting: nil)!,
        graphRole: .init(effectInput: .layerSource, effectOutput: .effectOutput,
            nodeTarget: .effectOutput, bindings: []), shaderContract: contract,
        diagnosticProvenance: .init(nodeIndex: 0, authoredShaderPath: contract.identity,
            contractIdentity: contract.identity, contractCanonicalSHA256: hash,
            textureSources: [], uniformSources: []))!
}

@main enum Harness {
    static func main() throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[1])
        let variant = Int(CommandLine.arguments[3])!
        let slot = variant == 0 ? 0 : 2
        let identity = SceneAssetTextureIdentity(virtualPath: CommandLine.arguments[2], purpose: .premultipliedColor)!
        let catalog = SceneMaterialAssetTextureCatalog(demands: [identity],
            resourceView: SceneResourceView(projectRootURL: root, packageRootURL: nil,
                stockAssetsRootURL: nil), descriptor: .init(), device: MTLCreateSystemDefaultDevice()!)
        let active = SceneResolvedMaterialShaderSchema.Sampler(name: "g_Texture\(slot)", slot: slot,
            mode: .regular, materialKey: nil, isHidden: false, defaultTexture: .asset(identity.path),
            readinessCombo: nil, sourceProvenPurpose: .premultipliedColor)
        var checks: [String: Bool] = [:]
        let value = mediaTemplate(identity.path, variant: variant)
        func envelope(_ state: SceneAssetTextureLaunchState) -> Bool {
            guard case let .success(cache) = SceneResolvedMaterialVariantCache.launchValidated(template: value,
                maximumVariantCount: 8, assetFormatFacts: catalog.launchFormatFacts) else { return false }
            let capture = SceneAuthoredEffectRenderPlan.TextureIdentity(kind: .layerSource,
                layerID: variant == 0 ? 91 : 3083, effect: nil, name: nil)
            if case .success = cache.precompileLaunchEnvelope(implicitFramebufferIdentity: capture,
                assetStates: [identity: state]) {
                let capability = cache.launchEnvelopeCapabilitySnapshot()
                return capability.allEntriesReady && !capability.variants.isEmpty
            }
            return false
        }
        checks["preparedProviderColorEnvelope"] = envelope(.preparedVideoColor)
        let selected = try SceneResolvedMaterialTextureResolver.launchDefaultReference(sampler: active,
            slot: slot, assetStates: catalog.launchStates, systemProviderStates: [:])
        if case let .selected(reference, purpose) = selected {
            checks["preparedVideoCanPrepareSampler"] = reference == .asset(identity.path) && purpose == .premultipliedColor
        } else { checks["preparedVideoCanPrepareSampler"] = false }
        for state in [SceneAssetTextureLaunchState.pending, .unavailable] {
            do {
                _ = try SceneResolvedMaterialTextureResolver.launchDefaultReference(sampler: active,
                    slot: slot, assetStates: [identity: state], systemProviderStates: [:])
                checks[String(describing: state) + "DoesNotAcquirePreparedAuthority"] = false
            } catch { checks[String(describing: state) + "DoesNotAcquirePreparedAuthority"] = true }
        }
        print(String(decoding: try JSONSerialization.data(withJSONObject: [
            "mediaAdmitted": catalog.launchStates[identity] != .unavailable,
            "report": catalog.reportLines, "checks": checks, "variant": variant,
            "contractIdentity": value.shaderContract.identity
        ]), as: UTF8.self))
    }
}
'''


@unittest.skipUnless(shutil.which("swiftc") and shutil.which("ffmpeg"), "Swift and ffmpeg required")
class SceneMaterialVideoAssetTests(unittest.TestCase):
    def test_media_asset_is_admitted_without_fabricating_a_static_frame(self):
        with tempfile.TemporaryDirectory(prefix="mwx-material-video-") as directory:
            work = Path(directory)
            (work / "cards").mkdir()
            subprocess.run(["ffmpeg", "-v", "error", "-f", "lavfi", "-i",
                "color=red:size=32x24:rate=10:duration=1", "-f", "lavfi", "-i",
                "color=blue:size=32x24:rate=10:duration=1", "-filter_complex",
                "[0:v][1:v]concat=n=2:v=1:a=0", "-c:v", "libx264", "-pix_fmt", "yuv420p",
                str(work / "clip.mp4")], check=True, capture_output=True)
            for resource in ["cards/first", "renamed/new-card"]:
                (work / resource).parent.mkdir(parents=True, exist_ok=True)
                (work / f"{resource}.tex").write_bytes(video_tex((work / "clip.mp4").read_bytes()))
            support = work / "Support.swift"
            support.write_text(sampler.SUPPORT)
            harness = work / "Harness.swift"
            harness.write_text(BASELINE)
            environment = os.environ.copy()
            environment["CLANG_MODULE_CACHE_PATH"] = str(work / "clang-cache")
            compiled = subprocess.run(["swiftc", "-parse-as-library", str(support),
                *map(str, sampler.SWIFT_SOURCES), str(harness),
                "-module-cache-path", str(work / "swift-cache"), "-o", str(work / "probe")],
                cwd=ROOT, env=environment, capture_output=True, text=True)
            self.assertEqual(compiled.returncode, 0, compiled.stderr)
            for index, resource in enumerate(["cards/first", "renamed/new-card"]):
                with self.subTest(resource=resource):
                    run = subprocess.run([str(work / "probe"), str(work), resource, str(index)], check=True,
                        capture_output=True, text=True, env=environment)
                    result = json.loads(run.stdout)
                    self.assertTrue(result["mediaAdmitted"], result)
                    for name, passed in result["checks"].items():
                        self.assertTrue(passed, (name, result))
                    print(json.dumps(result, sort_keys=True))


def solid_png() -> bytes:
    def chunk(kind, payload):
        return struct.pack(">I", len(payload)) + kind + payload + struct.pack(">I", zlib.crc32(kind + payload))
    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">2I5B", 1, 1, 8, 6, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(bytes([0, 0, 255, 0, 255]))) + chunk(b"IEND", b""))


@unittest.skipUnless(shutil.which("swiftc") and shutil.which("ffmpeg"), "Swift and ffmpeg required")
class SceneMaterialVideoAssetGPUTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temporary = tempfile.TemporaryDirectory(prefix="mwx-material-video-gpu-")
        cls.work = Path(cls.temporary.name)
        extras = [
            "Resources/Assets/SceneResourceIndex.swift", "Resources/Assets/SceneResourceView.swift",
            "Resources/Assets/SceneStockTextureSemanticRegistry.swift",
            "Resources/Textures/SceneTexturePathResolver.swift", "Resources/Textures/SceneMaterialAssetTextureCatalog.swift",
            "Resources/Textures/SceneBaseImageTextureCandidateSupport.swift", "Resources/Textures/SceneBaseMaterialTextureResolver.swift",
            "Compilation/Material/SceneBaseMaterialProviderBindingProgram.swift", "Compilation/Material/SceneEffectTextureInput.swift",
            "Systems/Properties/SceneDynamicSnapshot.swift", "Rendering/Frame/SceneMetalRenderer+BaseMaterialColor.swift",
            "Rendering/Metal/SceneMetalPipeline.swift", "Format/SceneWebMContainer.swift",
            "Rendering/Composition/SceneImageLayerDrawRequest.swift", "Rendering/Composition/SceneImageLayerCompositor+Uniforms.swift",
            "Rendering/Composition/SceneBlendModeShaderSource.swift",
            "Resources/Providers/SceneVideoPayloadPreparation.swift", "Resources/Providers/SceneVideoProviderLifecycleState.swift",
            "Resources/Providers/SceneVideoTextureSource.swift", "Resources/Providers/SceneVideoTextureSourceRegistry.swift",
        ]
        sources = list(dict.fromkeys(textures.SWIFT_SOURCES + [SCENE / path for path in extras]))
        cls.environment = os.environ.copy()
        cls.environment["CLANG_MODULE_CACHE_PATH"] = str(cls.work / "clang-cache")
        compiled = subprocess.run(["swiftc", "-parse-as-library", "-D", "DEBUG", "-default-isolation", "MainActor",
            *map(str, sources), str(ROOT / "script/tests/fixtures/SceneMaterialVideoAssetHarness.swift"),
            "-module-cache-path", str(cls.work / "swift-cache"), "-o", str(cls.work / "probe")],
            cwd=ROOT, env=cls.environment, capture_output=True, text=True)
        if compiled.returncode:
            cls.temporary.cleanup()
            raise RuntimeError(compiled.stderr)
        shader = SCENE / "Rendering/Composition/SceneImageLayer.metal"
        cls.shader = cls.work / "SceneImageLayer.metal"
        cls.shader.write_text(shader.read_text().replace('#include "SceneDistanceFog.metalh"',
            shader.with_name("SceneDistanceFog.metalh").read_text()))
        subprocess.run(["ffmpeg", "-v", "error", "-f", "lavfi", "-i",
            "color=red:size=32x24:rate=10:duration=1", "-f", "lavfi", "-i",
            "color=blue:size=32x24:rate=10:duration=1", "-filter_complex",
            "[0:v][1:v]concat=n=2:v=1:a=0", "-c:v", "libx264", "-pix_fmt", "yuv420p",
            str(cls.work / "clip.mp4")], check=True, capture_output=True)

    @classmethod
    def tearDownClass(cls):
        cls.temporary.cleanup()

    def test_real_frames_publication_fallback_selection_and_float_gpu(self):
        for index, (resource, property_name, flags) in enumerate([
            ("cards/first", "background", 2), ("renamed/new-card", "arbitrary-picture", 34),
        ]):
            with self.subTest(resource=resource, property=property_name):
                root = self.work / f"scene{index}"
                (root / resource).parent.mkdir(parents=True)
                (root / f"{resource}.tex").write_bytes(video_tex((self.work / "clip.mp4").read_bytes(), flags=flags))
                (root / "bad").mkdir()
                (root / "bad/truncated.tex").write_bytes(b"TEXV0005\0")
                (root / "still.png").write_bytes(solid_png())
                layer_id, video_layer_id = (91, 7) if index == 0 else (3083, 551)
                run = subprocess.run([str(self.work / "probe"), str(root), str(self.shader), resource, property_name,
                    str(layer_id), str(video_layer_id)],
                    cwd=ROOT, env=self.environment, capture_output=True, text=True, timeout=20)
                self.assertEqual(run.returncode, 0, run.stderr)
                result = json.loads(run.stdout)
                for name, passed in result["checks"].items():
                    self.assertTrue(passed, (name, result))
                self.assertGreater(len(result["generations"]), 10)
                self.assertTrue(all(b == a + 1 for a, b in zip(result["generations"], result["generations"][1:])))
                print(json.dumps({"variant": index, "resource": resource, "property": property_name,
                    "layerID": layer_id, "videoLayerID": video_layer_id,
                    "checks": result["checks"], "frames": len(result["pixels"]),
                    "red": result["pixels"][0], "tinted": result["tinted"], "still": result["still"]}, sort_keys=True))
