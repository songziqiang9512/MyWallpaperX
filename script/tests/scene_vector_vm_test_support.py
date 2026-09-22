#!/usr/bin/env python3

"""Shared compiler fixture for focused SceneScript vector-owner tests."""

from __future__ import annotations

from pathlib import Path
import shutil
import subprocess


ROOT = Path(__file__).resolve().parents[2]
SCENE = ROOT / "MyWallpaperX/Core/SteamWorkshopScene"
VM = SCENE / "Systems/Script"
QUICKJS = VM / "QuickJSNG"

SWIFT_SOURCES = [
    SCENE / "Format/SceneJSONValue.swift",
    SCENE / "Format/SceneScriptBindingDefinition.swift",
    ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Properties/SceneDynamicSnapshot.swift",
    ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Properties/SceneScriptValueOwnership.swift",
    ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Properties/SceneUserProperty.swift",
    ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Properties/SceneScriptDynamicProviderHostContract.swift",
    ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Properties/SceneUserPropertyBindings.swift",
    ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Script/SceneScriptPropertyInput.swift",
    ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Media/SceneAudioSpectrum.swift",
    ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Animation/SceneTextureAnimationControl.swift",
    ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Geometry/SceneMatrix.swift",
    ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Puppet/ScenePuppetAttachmentFrameSnapshot.swift",
    ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Geometry/SceneLayerWorldFrameResolver.swift",
    ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Geometry/SceneLayerDynamicWorldFrameResolver.swift",
    ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Resources/Textures/SceneNamedTextureReference.swift",
    ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Dependencies/SceneNamedTextureDependencyReferenceAnalysis.swift",
    ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Script/SceneScriptScalarRuntime.swift",
    ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Script/SceneScriptQuickJSDomain+FrameTransaction.swift",
    ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Script/SceneScriptLocalStorage.swift",
    ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Script/SceneScriptOwnerLifecycleBridge.swift",
    ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Script/SceneScriptAnimationHandleBridge.swift",
    ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Script/SceneScriptAudioHost.swift",
    ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Script/SceneScriptEffectHandleBridge.swift",
    ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Script/SceneScriptFallbackCatalog.swift",
    ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Script/SceneScriptLayerHandleBridge.swift",
    ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Script/SceneScriptLayerRuntimeDescriptorBridge.swift",
    ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Script/SceneScriptLayerTopologyModels.swift",
    ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Script/SceneScriptLayerWorldTransformProjection.swift",
    ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Script/SceneScriptLayerWorldTransformPublication.swift",
    ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Script/SceneScriptMediaEventBridge.swift",
    ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Script/SceneScriptCursorProgramModels.swift",
    ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Script/SceneScriptCursorProgram.swift",
    ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Script/SceneScriptCursorHitAdmission.swift",
    ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Script/SceneScriptDynamicLayerRuntime.swift",
    ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Script/SceneScriptDynamicImageReferenceAnalysis.swift",
    ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Script/SceneScriptScalarProgram.swift",
    ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Script/SceneScriptScalarProgram+Projection.swift",
    ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Script/SceneScriptStringProgram.swift",
    ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Script/SceneScriptStringRuntime.swift",
    ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Script/SceneScriptVectorCandidateCatalog.swift",
    ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Script/SceneScriptVectorCandidateModels.swift",
    ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Script/SceneScriptVectorMediaRouteCandidate.swift",
    ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Script/SceneScriptVectorProgramModels.swift",
    ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Script/SceneScriptVectorProgram.swift",
    ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Script/SceneScriptVectorProgram+Registrations.swift",
    ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Script/SceneScriptBooleanVisibilityValidation.swift",
    ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Script/SceneScriptVectorRuntime.swift",
    ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Script/SceneScriptVectorOwner+Cursor.swift",
    ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Script/SceneScriptVectorOwner+PuppetBones.swift",
    ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Script/SceneScriptQuickJSProgramCandidateModels.swift",
    ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Script/SceneScriptQuickJSProgramCandidate.swift",
]

C_SOURCES = [
    ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Script/SceneQuickJS.c",
    ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Script/SceneQuickJSValueHost.c",
    ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Script/SceneQuickJSAnimationHost.c",
    ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Script/SceneQuickJSModuleHost.c",
    ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Script/SceneQuickJSAudioHost.c",
    ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Script/SceneQuickJSMediaEventHost.c",
    ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Script/SceneQuickJSHandleHost.c",
    ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Script/SceneQuickJSLayerHost.c",
    ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Script/SceneQuickJSLayerSnapshotHost.c",
    ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Script/SceneQuickJSStorageHost.c",
    ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Script/SceneQuickJSJobHost.c",
    ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Script/SceneQuickJSTimerHost.c",
    ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Script/QuickJSNG/quickjs.c",
    ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Script/QuickJSNG/dtoa.c",
    ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Script/QuickJSNG/libregexp.c",
    ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Script/QuickJSNG/libunicode.c",
]

SWIFT_PREAMBLE = r'''
import Foundation

struct SceneFrameTiming {
    let wallDate: Date
    let simulationFrameTime: TimeInterval
    let sceneTime: TimeInterval
}

final class SceneMediaThumbnailInbox {
    struct Snapshot {
        struct Properties {
            let title, artist, subTitle, albumTitle, albumArtist, genres, contentType: String
        }
        struct Timeline { let position, duration: Double }
        let current: Data?
        let primaryColor: SIMD3<Double>?
        let secondaryColor: SIMD3<Double>?
        let tertiaryColor: SIMD3<Double>?
        let textColor: SIMD3<Double>?
        let highContrastColor: SIMD3<Double>?
        let generation: UInt64
        let playbackState: Int?
        let playbackGeneration: UInt64
        let properties: Properties?
        let propertiesGeneration: UInt64
        let timeline: Timeline?
        let timelineGeneration: UInt64
    }
}

struct SceneTextScriptDefinition {
    let source: String
}

struct SceneShaderContract {}

enum SceneBaseMaterialColorModulationCompiler {
    struct Binding {
        let modelPath: String
        let sourceLayerID: Int
        let scriptSource: String
        let scriptProperties: [String: SceneJSONValue]
        let authoredColor: SIMD3<Double>
    }

    static func compile(
        descriptor: SceneRenderDescriptor,
        shaderContracts: [SceneShaderContract],
        dynamicImageModelPaths: Set<String>,
        admittedLayerColorConsumerIDs: Set<Int>
    ) -> [Binding] { [] }
}

struct SceneScriptMaterialFunctionMutation: Equatable, Sendable {
    let layerID: Int
    let effectIndex: Int
    let functionName: String
}

enum SceneTimelinePlaybackCommand: String, Equatable, Sendable {
    case play
    case pause
    case stop
}

struct SceneTimelinePlaybackMutation: Equatable, Sendable {
    let target: SceneDynamicTarget
    let command: SceneTimelinePlaybackCommand
}

enum SceneParticleNumericValue: Equatable, Sendable {
    case scalar(Double)
    case vector([Double])

    var scalarValue: Double? {
        guard case let .scalar(value) = self else { return nil }
        return value
    }
}

struct SceneParticleBoundValue: Equatable, Sendable {
    let value: SceneParticleNumericValue?
    let userPropertyKey: String?
    let hasScript: Bool
    let hasAnimation: Bool
}

struct SceneParticleInstanceOverride: Equatable, Sendable {
    let alpha: SceneParticleBoundValue?
    let size: SceneParticleBoundValue?
    let lifetime: SceneParticleBoundValue?
    let rate: SceneParticleBoundValue?
    let speed: SceneParticleBoundValue?
    let count: SceneParticleBoundValue?
    let brightness: SceneParticleBoundValue?
    let color: SceneParticleBoundValue?
    let normalizedColor: SceneParticleBoundValue?
    let controlPoints: [Int: SceneParticleBoundValue]
    let controlPointAngles: [Int: SceneParticleBoundValue]
}

struct SceneRenderDescriptor {
    struct Camera {
        var parallaxEnabled = false
        var orthoHeight: Float? = nil
    }
    var camera = Camera()
    struct ModelMaterialLink {
        let modelPath: String
        let materialPath: String? = nil
    }
    enum SceneShaderUserValueKind {
        case null
        case string
    }

    struct TextStyle {
        let fontPath: String?
        let colorRGB: [Float]?
        let pointSize: Float?
    }

    struct ShaderValue {
        let scriptSource: String?
        let components: [Double]?
        let userValueKind: SceneShaderUserValueKind?
        var userBinding: String? = nil
        let bindingKeys: [String]
        let timeline: Bool?
        let timelineDiagnostics: [String]
        let scriptProperties: [String: SceneJSONValue]?

        init(
            scriptSource: String?,
            components: [Double]?,
            userValueKind: SceneShaderUserValueKind? = nil,
            bindingKeys: [String] = [],
            timeline: Bool? = nil,
            timelineDiagnostics: [String] = [],
            scriptProperties: [String: SceneJSONValue]? = nil
        ) {
            self.scriptSource = scriptSource
            self.components = components
            self.userValueKind = userValueKind
            self.bindingKeys = bindingKeys
            self.timeline = timeline
            self.timelineDiagnostics = timelineDiagnostics
            self.scriptProperties = scriptProperties
        }
    }

    struct MaterialPassDescriptor {
        let materialPath: String
        let passIndex: Int
        let constantShaderValues: [String: ShaderValue]
    }

    struct SceneEffectTextureInput: ExpressibleByBooleanLiteral {
        enum Kind: Equatable { case path, system, property, unknown }
        let kind: Kind
        let value: String

        init(booleanLiteral value: Bool) {
            kind = .path
            self.value = value ? "fixture-user-texture" : ""
        }
    }

    struct EffectDescriptor {
        struct PassDescriptor {
            let passIndex: Int
            let id: Int?
            let constantShaderValues: [String: ShaderValue]
            let textureSlots: [String?]
            let userTextureInputs: [SceneEffectTextureInput?]

            init(
                passIndex: Int,
                id: Int?,
                constantShaderValues: [String: ShaderValue],
                textureSlots: [String?] = [],
                userTextureInputs: [SceneEffectTextureInput?] = []
            ) {
                self.passIndex = passIndex
                self.id = id
                self.constantShaderValues = constantShaderValues
                self.textureSlots = textureSlots
                self.userTextureInputs = userTextureInputs
            }
        }

        let name: String?
        let effectID: Int?
        let passes: [PassDescriptor]
        let id: String
        let visible: Bool?

        init(
            name: String?,
            effectID: Int? = nil,
            passes: [PassDescriptor] = [],
            id: String = "effect",
            visible: Bool? = true
        ) {
            self.name = name
            self.effectID = effectID
            self.passes = passes
            self.id = id
            self.visible = visible
        }
    }

    struct UtilityLayer {
        enum Kind {
            case composition
        }

        let kind: Kind
        let copyBackground: Bool
        let passthrough: Bool
    }

    struct Layer {
        let id: Int
        let layerIndex: Int
        let name: String?
        var visible: Bool?
        let originXYZ: [Float]?
        let scaleXYZ: [Float]?
        var anglesXYZ: [Float]? = nil
        var colorRGB: [Float]? = nil
        let scaleHasScript: Bool?
        let alpha: Double?
        let effects: [EffectDescriptor]
        var contentKind: String = "image"
        var particleInstanceOverride: SceneParticleInstanceOverride? = nil
        var textScript: SceneTextScriptDefinition? = nil
        var text: String? = nil
        var textStyle: TextStyle? = nil
        var sizeWH: [Float]? = nil
        var imagePath: String? = nil
        var staticModelPath: String? = nil
        var spotLight: Int? = nil
        var directionalLight: Int? = nil
        var authoredLightIntensity: Float? { nil }
        var utilityLayer: UtilityLayer? = nil
        var parentID: Int? = nil
        var childLayerIDs: [Int] = []
        var dependencyLayerIDs: [Int] = []
        var authoredDependencies: [Int] = []
        var effectFiles: [String] = []
        var parallaxDepthXY: [Float]? = nil
        var attachmentName: String? = nil
        var parentAttachmentBindFrame: [Float]? = nil
    }

    var layers: [Layer]
    var modelMaterialLinks: [ModelMaterialLink] = []
    var materialPasses: [MaterialPassDescriptor] = []
    var renderOrderLayerIDs: [Int] { layers.map(\.id) }
}

extension SceneRenderDescriptor.Layer {
    static func dynamicText(_ mutation: SceneScriptLayerMutation) -> Self? {
        nil
    }

    static func dynamicImage(
        _ mutation: SceneScriptLayerMutation,
        template: SceneScriptDynamicImageLayerTemplate
    ) -> Self? {
        nil
    }
}
'''


def compile_vector_harness(
    temporary_directory: Path,
    harness_source: str,
    binary_name: str,
) -> Path:
    clang = shutil.which("clang")
    if clang is None:
        raise RuntimeError("clang is required")

    objects: list[Path] = []
    for source in C_SOURCES:
        output = temporary_directory / f"{source.stem}.o"
        subprocess.run(
            [
                clang,
                "-std=c11",
                "-O0",
                "-c",
                str(source),
                "-o",
                str(output),
                "-I",
                str(VM),
                "-I",
                str(QUICKJS),
            ],
            check=True,
            capture_output=True,
            text=True,
        )
        objects.append(output)

    harness = temporary_directory / f"{binary_name}.swift"
    harness.write_text(SWIFT_PREAMBLE + harness_source, encoding="utf-8")
    binary = temporary_directory / binary_name
    compilation = subprocess.run(
        [
            "xcrun",
            "swiftc",
            "-parse-as-library",
            "-O",
            "-import-objc-header",
            str(ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Script/SceneQuickJS.h"),
            "-Xcc",
            f"-I{VM}",
            "-o",
            str(binary),
            *map(str, SWIFT_SOURCES),
            str(harness),
            *map(str, objects),
            "-Xlinker",
            "-lm",
        ],
        capture_output=True,
        text=True,
    )
    if compilation.returncode != 0:
        raise AssertionError(compilation.stdout + compilation.stderr)
    return binary
