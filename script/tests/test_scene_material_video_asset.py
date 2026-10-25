"""Authored video TEX assets through the real provider and image GPU pipeline."""

from __future__ import annotations

import json
import hashlib
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
from script.tests import test_scene_initial_video_resource_readiness as readiness
from script.tests.scene_pkg_fixture import make_package
from script.tests.scene_video_segment_delegate_fixture import (
    compile_segment_delegate, segment_delegate_sources,
)

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

func mediaTemplate(_ path: SceneVFSAssetPath, variant: Int,
                   propertyKey: String? = nil) -> SceneResolvedMaterialTemplate {
    let slot = variant == 0 ? 0 : 2
    let varying = variant == 0 ? "v_TexCoord" : "renamedUV"
    let name = variant == 0 ? "self/neutral" : "alternate/renamed-resource"
    let annotation = propertyKey == nil ? "" : #" // {"formatcombo":true}"#
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
        uniform sampler2D g_Texture\(slot);\(annotation)
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
    let reference: SceneResolvedMaterialTemplate.TextureReference = propertyKey.map {
        .userProperty(.init(key: $0))
    } ?? .asset(path)
    slots[slot] = .init(index: slot, candidates: [.init(reference: reference, provenance: .explicitBinding)])
    return .validated(textureSlots: slots, combos: [], uniformDeclarations: [],
        renderState: SceneMaterialRenderState.compile(blending: "normal", depthTest: "disabled",
            depthWrite: "disabled", cullMode: "nocull", alphaWriting: nil)!,
        graphRole: .init(effectInput: .layerSource, effectOutput: .effectOutput,
            nodeTarget: .effectOutput, bindings: []), shaderContract: contract,
        diagnosticProvenance: .init(nodeIndex: 0, authoredShaderPath: contract.identity,
            contractIdentity: contract.identity, contractCanonicalSHA256: hash,
            textureSources: [], uniformSources: []))!
}

func propertyFormatProfileChecks(path: SceneVFSAssetPath, variant: Int, device: MTLDevice) throws -> [String: Bool] {
    let slot = variant == 0 ? 0 : 2
    let key = variant == 0 ? "self-picture" : "arbitrary-renamed-picture"
    let property = SceneUserPropertyTextureIdentity(propertyKey: key, purpose: .premultipliedColor)!
    let template = mediaTemplate(path, variant: variant, propertyKey: key)
    let sampler = SceneResolvedMaterialShaderSchema.Sampler(name: "g_Texture\(slot)", slot: slot,
        mode: .regular, materialKey: nil, isHidden: false, defaultTexture: nil,
        readinessCombo: nil, sourceProvenPurpose: .premultipliedColor)
    let formatSlots = try SceneResolvedMaterialTextureResolver.launchTextureFormatSlots(template: template)
    let profiles = try SceneResolvedMaterialTextureResolver.launchTextureFormatProfiles(template: template,
        samplers: [slot: sampler], readinessMask: UInt8(1) << UInt8(slot), formatSlots: formatSlots,
        graphTextureFormatFacts: [:], assetFormatFacts: [:], assetStates: [:]).get()
    let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm,
        width: 2, height: 2, mipmapped: false)
    descriptor.usage = .shaderRead
    let texture = device.makeTexture(descriptor: descriptor)!
    let incarnation = UUID()
    func runtimeKey(format: SceneShaderTextureFormat?, generation: UInt64) throws -> SceneResolvedMaterialVariantKey {
        // Controlled provider metadata at the production resolver boundary.
        // The separate native Source gate proves which format the producer supplies.
        let candidate = SceneTextureCandidate(texture: texture,
            identity: .provider(.videoUserProperty(property: property, sourceIncarnation: incarnation,
                lifecycleEpoch: 3)), generation: .provider(contentGeneration: generation),
            purpose: .premultipliedColor, content: .color(.resolved(.opaque)),
            physicalSize: .init(width: 2, height: 2), mappedSize: .init(width: 2, height: 2),
            uvTransform: .identity, sampling: .linearClamp, authoredFormat: format)
        let publication = SceneTextureProviderPublication(requestIdentity: .materialUserProperty(property),
            candidate: candidate, contentGeneration: generation)
        let dynamic = SceneDynamicSnapshotResolver().resolve(frameIndex: 1, generation: 1,
            definitions: [], userValues: [:], timelineValues: [:], sceneScriptValues: [:]).snapshot
        let frameInputs = SceneAuthoredShaderFrameInputs(frameIndex: 1, screenSize: .init(width: 2, height: 2),
            sceneTime: 0, dayTime: 0, frameTime: 1 / 60, pointerCurrentNDC: .zero,
            pointerPreviousNDC: .zero, pointerPrimaryButtonDown: false,
            parallaxPositionNDC: .zero, audioSpectrum: .silent)
        let snapshot = SceneFrameTextureRegistrySnapshot(frameEpoch: 1, frameIndex: 1,
            entries: [.materialUserProperty(property): .ready(.init(publication: publication, resourceGeneration: generation))])
        let frame = try SceneResolvedMaterialFrameSnapshot.validated(textureSnapshot: snapshot,
            dynamicSnapshot: dynamic, frameInputs: frameInputs).get()
        let input = frame.finalizationInput(template: template, layerID: 17,
            renderSize: .init(width: 2, height: 2), modelViewProjection: matrix_identity_float4x4,
            layerModelMatrix: matrix_identity_float4x4, effectOutputModelViewProjection: matrix_identity_float4x4,
            effectTextureProjectionMatrixInverse: matrix_identity_float4x4, implicitFramebufferIdentity: nil)
        return try SceneResolvedMaterialTextureResolver.variantKey(input, samplers: [slot: sampler],
            reachableSamplers: [slot: [sampler]], formatSlots: formatSlots,
            allowPresenceIndependentDefaults: true)
    }
    let first = try runtimeKey(format: nil, generation: 1)
    let later = try runtimeKey(format: nil, generation: 7)
    let invented = try runtimeKey(format: .rgba8888, generation: 1)
    return ["formatComboAnnotationReachesOwner": formatSlots == [slot],
        "externalPropertyLaunchHasNoTEXFormat": profiles.count == 1 && profiles[0][slot] == nil,
        "externalPropertyRuntimeMatchesLaunchProfile": profiles.contains(first.textureFormats),
        "providerGenerationDoesNotChangeFormatKey": first == later,
        "inventedTEXFormatCannotMatchPropertyLaunch": !profiles.contains(invented.textureFormats)]
}

@main enum Harness {
    static func main() throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[1])
        let variant = Int(CommandLine.arguments[3])!
        let slot = variant == 0 ? 0 : 2
        let identity = SceneAssetTextureIdentity(virtualPath: CommandLine.arguments[2], purpose: .premultipliedColor)!
        let catalog = try SceneMaterialAssetTextureCatalog(demands: [identity],
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
        checks.merge(try propertyFormatProfileChecks(path: identity.path, variant: variant,
            device: MTLCreateSystemDefaultDevice()!)) { _, new in new }
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
        cls.evidence = Path(os.environ["MWX_SCENE_MATERIAL_VIDEO_EVIDENCE"]) if os.environ.get(
            "MWX_SCENE_MATERIAL_VIDEO_EVIDENCE") else None
        if cls.evidence:
            cls.evidence.mkdir(parents=True, exist_ok=True)
        product_override = os.environ.get("MWX_SCENE_VIDEO_PRODUCT_SOURCE_ROOT")
        cls.product_root = Path(product_override or os.environ.get("MWX_D7_PRODUCT_SOURCE_ROOT", ROOT)).resolve()
        cls.legacy_storage = not product_override and cls.product_root != ROOT.resolve()
        io_expectation = os.environ.get("MWX_SCENE_VIDEO_INPUT_IO_EXPECTATION", "current")
        if io_expectation not in ("before", "current"):
            raise RuntimeError("Input IO expectation must be before or current")
        cls.input_io_before = io_expectation == "before"
        if cls.input_io_before and not product_override:
            raise RuntimeError("before expectation requires an explicit actual product source root")
        extras = [
            "Resources/Assets/SceneResourceIndex.swift", "Resources/Assets/SceneResourceView.swift",
            "Resources/Assets/SceneStockTextureSemanticRegistry.swift",
            "Resources/Textures/SceneTexturePathResolver.swift", "Resources/Textures/SceneMaterialAssetTextureCatalog.swift",
            "Resources/Textures/SceneBaseImageTextureCandidateSupport.swift", "Resources/Textures/SceneBaseMaterialTextureResolver.swift",
            "Compilation/Material/SceneBaseMaterialProviderBindingProgram.swift", "Compilation/Material/SceneEffectTextureInput.swift",
            "Compilation/Material/SceneRenderTargetVocabulary.swift",
            "Systems/Properties/SceneDynamicSnapshot.swift", "Rendering/Frame/SceneMetalRenderer+BaseMaterialColor.swift",
            "Rendering/Metal/SceneMetalPipeline.swift", "Runtime/Frame/SceneMaterialRenderState.swift", "Format/SceneWebMContainer.swift",
            "Rendering/Composition/SceneImageLayerDrawRequest.swift", "Rendering/Composition/SceneImageLayerCompositor+Uniforms.swift",
            "Rendering/Composition/SceneBlendModeShaderSource.swift",
            "Resources/Providers/SceneVideoPayloadPreparation.swift", "Resources/Providers/SceneVideoProviderLifecycleState.swift",
            "Resources/Providers/SceneVideoTextureSource.swift", "Resources/Providers/SceneVideoTextureSourceRegistry.swift",
            "Format/ScenePkgReader.swift",
        ]
        sources = list(dict.fromkeys(textures.SWIFT_SOURCES + [SCENE / path for path in extras]))
        sources = [cls.product_root / path.relative_to(ROOT) for path in sources]
        if cls.legacy_storage:
            # The retained D7 source has its original directory Root. These
            # three D8 dependencies did not exist; never substitute current
            # product text into an actual-before compilation.
            d8_only = {"ScenePlaybackSource.swift", "SceneResourceIdentity.swift", "SceneResourceView+Backing.swift"}
            sources = [path for path in sources if path.name not in d8_only]
        readiness_input = cls.product_root / "MyWallpaperX/Core/SteamWorkshopScene/Resources/Textures/SceneBaseImageTextureLoad.swift"
        readiness_source = cls.work / "SceneOrdinaryVideoFrameReadiness.swift"
        readiness_source.write_text(readiness.declaration(readiness_input.read_text(),
            "enum SceneOrdinaryVideoFrameReadiness:") + "\n")
        harness = ROOT / "script/tests/fixtures/SceneMaterialVideoAssetHarness.swift"
        shader = cls.product_root / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Composition/SceneImageLayer.metal"
        delegate_sources = segment_delegate_sources(cls.product_root / "MyWallpaperX/Core/SteamWorkshopScene")
        if cls.legacy_storage and not any(path.exists() for path in delegate_sources):
            delegate_sources = ()
        cls.source_inputs = list(dict.fromkeys(sources + list(delegate_sources) + [
            Path(compile_segment_delegate.__code__.co_filename), readiness_input, harness, Path(__file__),
            Path(textures.__file__), Path(readiness.__file__), Path(make_package.__code__.co_filename),
            shader, shader.with_name("SceneDistanceFog.metalh")]))
        cls.io_fixture = ROOT / "script/tests/fixtures/SceneVideoPackageReadObserver.c"
        if not cls.legacy_storage:
            cls.source_inputs.append(cls.io_fixture)
        cls.before_hashes = {str(path): hashlib.sha256(path.read_bytes()).hexdigest() for path in cls.source_inputs}
        cls.environment = os.environ.copy()
        cls.environment["CLANG_MODULE_CACHE_PATH"] = str(cls.work / "clang-cache")
        cls.environment["HOME"] = str(cls.work / "home")
        cls.environment["CFFIXED_USER_HOME"] = str(cls.work / "home")
        (cls.work / "home").mkdir()
        delegate_arguments = compile_segment_delegate(cls.work,
            scene_root=cls.product_root / "MyWallpaperX/Core/SteamWorkshopScene",
            environment=cls.environment, evidence_directory=cls.evidence,
            allow_legacy=cls.legacy_storage)
        cls.io_library = cls.work / "entry-read-observer.dylib"
        if not cls.legacy_storage:
            io_command = ["xcrun", "clang", "-dynamiclib", "-std=c11", "-Wall", "-Wextra", "-Werror",
                          str(cls.io_fixture), "-o", str(cls.io_library)]
            io_compile = subprocess.run(io_command, cwd=ROOT, env=cls.environment,
                capture_output=True, text=True, timeout=60)
            if cls.evidence:
                (cls.evidence / "entry-read-observer-compile.json").write_text(json.dumps({
                    "argv": io_command, "exitCode": io_compile.returncode,
                    "stdout": io_compile.stdout, "stderr": io_compile.stderr,
                    "sourceSHA256": hashlib.sha256(cls.io_fixture.read_bytes()).hexdigest(),
                }, indent=2) + "\n")
            if io_compile.returncode:
                raise RuntimeError(io_compile.stderr)
        compiled = subprocess.run(["swiftc", "-parse-as-library", "-D", "DEBUG", "-default-isolation", "MainActor",
            *([] if cls.legacy_storage else ["-D", "MWX_COMPLETED_WEBM_REUSE", "-D", "MWX_REGISTRY_INPUT_IO"]),
            *delegate_arguments, *map(str, sources), str(readiness_source), str(harness),
            "-module-cache-path", str(cls.work / "swift-cache"), "-o", str(cls.work / "probe")],
            cwd=ROOT, env=cls.environment, capture_output=True, text=True)
        if cls.evidence:
            (cls.evidence / "compile.stdout.log").write_text(compiled.stdout)
            (cls.evidence / "compile.stderr.log").write_text(compiled.stderr)
            (cls.evidence / "compile.json").write_text(json.dumps({"exitCode": compiled.returncode,
                "productSourceRoot": str(cls.product_root), "sourceSHA256Before": cls.before_hashes,
                "generatedReadinessSHA256": hashlib.sha256(readiness_source.read_bytes()).hexdigest()}, indent=2) + "\n")
        if compiled.returncode:
            cls.temporary.cleanup()
            raise RuntimeError(compiled.stderr)
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
        after = {str(path): hashlib.sha256(path.read_bytes()).hexdigest() for path in cls.source_inputs}
        changed = [path for path, sha in cls.before_hashes.items() if after[path] != sha]
        if cls.evidence:
            (cls.evidence / "source-identity.json").write_text(json.dumps({
                "productSourceRoot": str(cls.product_root), "legacyHostStorageMapping": cls.legacy_storage,
                "sourceSHA256Before": cls.before_hashes, "sourceSHA256After": after,
                "changedPaths": changed, "sourceUnchanged": not changed}, indent=2) + "\n")
        cls.temporary.cleanup()
        if changed:
            raise RuntimeError("material video gate input changed: " + ", ".join(changed))

    def test_package_remount_video_private_storage_and_actual_av_borrowers(self):
        if self.legacy_storage:
            self.skipTest("current package Root regression; historical D7 storage needs its original frozen gate")
        root = self.work / "storage-scene"
        root.mkdir()
        (root / "scene.pkg").write_bytes(make_package([
            ("textures/renamed-card.tex", video_tex((self.work / "clip.mp4").read_bytes())),
        ]))
        run = subprocess.run([str(self.work / "probe"), str(root), str(self.shader), "--storage",
            str(self.work / "clip.mp4")],
            cwd=ROOT, env=self.environment, capture_output=True, text=True, timeout=90)
        if self.evidence:
            (self.evidence / "storage.stdout.log").write_text(run.stdout)
            (self.evidence / "storage.stderr.log").write_text(run.stderr)
        self.assertEqual(run.returncode, 0, run.stderr)
        result = json.loads(run.stdout)
        if self.evidence:
            (self.evidence / "storage.json").write_text(json.dumps(result, indent=2, sort_keys=True) + "\n")
        print(json.dumps(result, sort_keys=True), flush=True)
        required = {"embeddedActualFrameKeepsRedPixels", "embeddedBorrowsActualSourceAVAsset",
            "ordinarySurfaceRebuildReusesActualSource", "independentPackageMountKeepsActualSource",
            "retiredCachePollutionDoesNotChangePackageBytes", "retiredCachePollutionKeepsBorrowedEmbeddedBytes",
            "retiredCachePollutionKeepsCurrentDeclaration", "embeddedAVBorrowerAlonePinsFile",
            "embeddedFinalAVBorrowerUnlinksFile", "externalCandidatePrimesActualDecoder",
            "externalCandidateAdopts", "externalActualFrameKeepsRedPixels",
            "packageRemountKeepsExternalPrivateBytes", "cancelledReplacementKeepsOldProvider",
            "liveReplacementUsesNewActualPrivateSource", "externalAVBorrowerAlonePinsFile",
            "externalFinalAVBorrowerUnlinksFile"}
        required.update(kind + suffix for kind in ("failed", "missing") for suffix in (
            "PackageUnavailableKeepsLooseSelection", "LoosePrivateOutsideAuthor", "LooseAuthorNamespaceUnchanged"))
        self.assertTrue(required.issubset(result["checks"]), result)
        self.assertEqual(len(result["pixels"]), 2, result)
        self.assertEqual(result["storageMapping"], "actual package Root with explicit App-private media domain")
        for name, passed in result["checks"].items():
            with self.subTest(check=name):
                self.assertTrue(passed, result)

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
                if self.evidence:
                    (self.evidence / f"original-gpu-{index}.stdout.log").write_text(run.stdout)
                    (self.evidence / f"original-gpu-{index}.stderr.log").write_text(run.stderr)
                self.assertEqual(run.returncode, 0, run.stderr)
                result = json.loads(run.stdout)
                for name, passed in result["checks"].items():
                    self.assertTrue(passed, (name, result))
                self.assertGreater(len(result["generations"]), 10)
                self.assertTrue(all(b == a + 1 for a, b in zip(result["generations"], result["generations"][1:])))
                print(json.dumps({"variant": index, "resource": resource, "property": property_name,
                    "layerID": layer_id, "videoLayerID": video_layer_id,
                    "checks": result["checks"], "frames": len(result["pixels"]),
                    "red": result["pixels"][0], "tinted": result["tinted"], "still": result["still"],
                    "afterStopInsideAVScope": result.get("afterStopInsideAVScope"),
                    "afterAVScopeRelease": result.get("afterAVScopeRelease")}, sort_keys=True))

    def test_completed_package_webm_reuses_file_with_independent_players_and_last_borrow(self):
        if self.legacy_storage:
            self.skipTest('completed package reuse requires the current package Root API')
        root = self.work / 'completed-webm-scene'
        root.mkdir()
        webm = root / 'source.webm'
        # A supported-size, explicit pixel-format real VP9 input, independent of D34's large mechanism clip.
        encode = subprocess.run(['ffmpeg', '-v', 'error', '-f', 'lavfi', '-i',
            'color=red:size=320x180:rate=30:duration=2', '-c:v', 'libvpx-vp9',
            '-pix_fmt', 'yuv420p', '-g', '30', '-auto-alt-ref', '0', str(webm)],
            check=True, capture_output=True, text=True, timeout=60)
        package = make_package([
            ('textures/first.tex', video_tex(webm.read_bytes())),
            ('textures/peer.tex', video_tex(webm.read_bytes())),
        ])
        for name in ('scene.pkg', 'peer.pkg'):
            (root / name).write_bytes(package)
        run = subprocess.run([str(self.work / 'probe'), str(root), str(self.shader), '--completed-webm-reuse'],
            cwd=ROOT, env=self.environment, capture_output=True, text=True, timeout=90)
        if self.evidence:
            (self.evidence / 'completed-webm-inputs.json').write_text(json.dumps({
                'webmSHA256': hashlib.sha256(webm.read_bytes()).hexdigest(),
                'packageSHA256': hashlib.sha256(package).hexdigest(),
                'webmBytes': webm.stat().st_size, 'packageBytes': len(package),
                'encodeStdout': encode.stdout, 'encodeStderr': encode.stderr,
                'scope': 'generated real VP9 input; Reader package facts with controlled managed binding; no library admission claim',
            }, indent=2) + '\n')
            (self.evidence / 'completed-webm.stdout.log').write_text(run.stdout)
            (self.evidence / 'completed-webm.stderr.log').write_text(run.stderr)
        self.assertEqual(run.returncode, 0, run.stderr)
        result = json.loads(run.stdout)
        if self.evidence:
            (self.evidence / 'completed-webm.json').write_text(json.dumps(result, indent=2, sort_keys=True) + '\n')
        expected = {
            'startsWithNoPrivateReservation', 'actualFileOutsideAuthorRoot', 'completedFileHasOneActualReservation',
            'independentSourcesAndPlayers', 'secondSourceUsesCompletedFileSynchronously',
            'bothActualPlayersPublishRedPixels', 'firstStopDoesNotStopSecondPublication',
            'lastActualAssetAloneKeepsFileAndCharge', 'lastAssetReleaseUnlinksAndReturnsReservation',
            'stoppedSourcesRemainAliveAfterFinalBorrow', 'sourceSnapshotCannotServeRemuxPurpose',
            'closedWriterPublishesExactFile', 'remuxCannotReplaceSourceSnapshotPurpose',
            'actualPrivateDomainPartitionsBorrow', 'budgetInstancePartitionsBorrow',
            'partialWriterNeverRegistersSuccess', 'cancelledPublicationEscapes',
            'cancelledPublicationDoesNotRegister', 'cancelledHitCannotBorrow',
            'replacedOutputCannotHitOldSuccess', 'changedAuthorInputEscapesAtRegistryEntry',
            'changedAuthorDeclarationEscapesAtRegistryEntry', 'completedFileRemainsUsableAfterAuthorChange',
            'freshRootUsesNewRevisionAndPrivateFile',
        }
        expected.update(name + 'CannotBorrowOtherCompletedIdentity' for name in
                        ('packagePath', 'rawEntry'))
        self.assertEqual(set(result['checks']), expected, result)
        for name in expected:
            with self.subTest(check=name):
                self.assertIs(result['checks'][name], True, result)
        print(json.dumps(result, sort_keys=True), flush=True)

    def test_package_registry_hits_avoid_payload_io_after_eviction(self):
        if self.legacy_storage:
            self.skipTest('package Input IO requires the current managed Root API')
        root = self.work / 'registry-input-io'
        root.mkdir()
        external = os.environ.get('MWX_SCENE_VIDEO_IO_WEBM')
        webm = Path(external) if external else root / 'source.webm'
        if not external:
            if self.input_io_before:
                self.fail('the actual-before comparison requires one shared frozen WebM input')
            subprocess.run(['ffmpeg', '-v', 'error', '-f', 'lavfi', '-i',
                'color=red:size=320x180:rate=30:duration=2', '-c:v', 'libvpx-vp9',
                '-pix_fmt', 'yuv420p', '-g', '30', '-auto-alt-ref', '0', str(webm)],
                check=True, capture_output=True, timeout=60)
        media = webm.read_bytes()
        package = make_package([
            ('textures/first.tex', video_tex(media)),
            ('textures/not-tex.bin', video_tex(media)),
            ('textures/not-video.tex', video_tex(bytes(16))),
            ('textures/malformed.tex', b'not a TEX'),
        ])
        for name in ('scene.pkg', 'changed.pkg'):
            (root / name).write_bytes(package)
        environment = dict(self.environment, DYLD_INSERT_LIBRARIES=str(self.io_library))
        mode = 'before' if self.input_io_before else 'current'
        command = [str(self.work / 'probe'), str(root), str(self.shader), '--registry-input-io', mode]
        run = subprocess.run(command, cwd=ROOT, env=environment, capture_output=True, text=True, timeout=90)
        if self.evidence:
            (self.evidence / 'input-io.stdout.log').write_text(run.stdout)
            (self.evidence / 'input-io.stderr.log').write_text(run.stderr)
            (self.evidence / 'input-io-inputs.json').write_text(json.dumps({
                'argv': command, 'mode': mode, 'productSourceRoot': str(self.product_root),
                'sharedWebMInput': str(webm), 'webmSHA256': hashlib.sha256(media).hexdigest(),
                'packageSHA256': hashlib.sha256(package).hexdigest(),
                'observerSHA256': hashlib.sha256(self.io_fixture.read_bytes()).hexdigest(),
                'sourceSHA256': self.before_hashes,
            }, indent=2) + '\n')
        self.assertEqual(run.returncode, 0, run.stderr)
        result = json.loads(run.stdout)
        expected = {'coldPositiveControl', 'sameLiveSourceAndExpectedIO', 'completedHitExpectedIO',
            'differentIdentityReadsOriginalPayload', 'not-tex.binKeepsOriginalResult',
            'not-video.texKeepsOriginalResult', 'malformed.texKeepsOriginalResult',
            'cancelledRequestIsRejected', 'cancelledRequestExpectedIO', 'sourceChangedEscapesBeforePayload',
            'actualAssetKeepsCompletedFile', 'lastBorrowActuallyReleased', 'lastBorrowMissReadsOriginalPayload'}
        self.assertEqual(set(result['checks']), expected)
        for name in expected:
            with self.subTest(check=name):
                self.assertIs(result['checks'][name], True, result)
        self.assertGreater(result['entryBytes'], 0)
        self.assertEqual(result['expectedHitBytes'], result['entryBytes'] if self.input_io_before else 0)
        if self.evidence:
            (self.evidence / 'input-io.json').write_text(json.dumps(result, indent=2, sort_keys=True) + '\n')
        print(json.dumps(result, sort_keys=True), flush=True)
