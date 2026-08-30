#!/usr/bin/env python3

"""Shared compiler fixture for focused SceneScript vector-owner tests."""

from __future__ import annotations

from pathlib import Path
import shutil
import subprocess


ROOT = Path(__file__).resolve().parents[2]
SCENE = ROOT / "MyWallpaperX/Core/SteamWorkshopScene"
VM = SCENE / "Runtime/SceneScript"
QUICKJS = VM / "QuickJSNG"

SWIFT_SOURCES = [
    SCENE / "Format/SceneJSONValue.swift",
    SCENE / "Format/SceneScriptBindingDefinition.swift",
    SCENE / "Properties/SceneDynamicSnapshot.swift",
    SCENE / "Properties/SceneUserProperty.swift",
    SCENE / "Properties/SceneScriptDynamicProviderHostContract.swift",
    SCENE / "Properties/SceneUserPropertyBindings.swift",
    VM / "SceneScriptPropertyInput.swift",
    SCENE / "Runtime/SceneAudioSpectrum.swift",
    SCENE / "Resources/SceneNamedTextureReference.swift",
    SCENE
    / "RenderGraph/LayerDependencies/SceneNamedTextureDependencyReferenceAnalysis.swift",
    VM / "SceneScriptScalarRuntime.swift",
    VM / "SceneScriptOwnerLifecycleBridge.swift",
    VM / "SceneScriptAnimationHandleBridge.swift",
    VM / "SceneScriptAudioHost.swift",
    VM / "SceneScriptEffectHandleBridge.swift",
    VM / "SceneScriptFallbackCatalog.swift",
    VM / "SceneScriptLayerHandleBridge.swift",
    VM / "SceneScriptLayerRuntimeDescriptorBridge.swift",
    VM / "SceneScriptMediaEventBridge.swift",
    VM / "SceneScriptCursorProgram.swift",
    VM / "SceneScriptDynamicLayerRuntime.swift",
    VM / "SceneScriptScalarProgram.swift",
    VM / "SceneScriptStringProgram.swift",
    VM / "SceneScriptStringRuntime.swift",
    VM / "SceneScriptVectorCandidateCatalog.swift",
    VM / "SceneScriptVectorMediaRouteCandidate.swift",
    VM / "SceneScriptVectorProgram.swift",
    VM / "SceneScriptVectorRuntime.swift",
    VM / "SceneScriptQuickJSProgramCandidate.swift",
]

C_SOURCES = [
    VM / "SceneQuickJS.c",
    VM / "SceneQuickJSValueHost.c",
    VM / "SceneQuickJSAnimationHost.c",
    VM / "SceneQuickJSModuleHost.c",
    VM / "SceneQuickJSAudioHost.c",
    VM / "SceneQuickJSMediaEventHost.c",
    VM / "SceneQuickJSHandleHost.c",
    VM / "SceneQuickJSLayerHost.c",
    VM / "SceneQuickJSLayerSnapshotHost.c",
    VM / "SceneQuickJSJobHost.c",
    VM / "SceneQuickJSTimerHost.c",
    QUICKJS / "quickjs.c",
    QUICKJS / "dtoa.c",
    QUICKJS / "libregexp.c",
    QUICKJS / "libunicode.c",
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
            let title: String
            let artist: String
        }
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
    }
}

struct SceneTextScriptDefinition {
    let source: String
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

        init(
            scriptSource: String?,
            components: [Double]?,
            userValueKind: SceneShaderUserValueKind? = nil
        ) {
            self.scriptSource = scriptSource
            self.components = components
            self.userValueKind = userValueKind
        }
    }

    struct EffectDescriptor {
        struct PassDescriptor {
            let passIndex: Int
            let id: Int?
            let constantShaderValues: [String: ShaderValue]
            let textureSlots: [String?]
            let userTextureInputs: [Bool?]

            init(
                passIndex: Int,
                id: Int?,
                constantShaderValues: [String: ShaderValue],
                textureSlots: [String?] = [],
                userTextureInputs: [Bool?] = []
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
        let anglesXYZ: [Float]? = nil
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
        var utilityLayer: UtilityLayer? = nil
        var parentID: Int? = nil
        var childLayerIDs: [Int] = []
        var dependencyLayerIDs: [Int] = []
        var authoredDependencies: [Int] = []
        var effectFiles: [String] = []
        var parallaxDepthXY: [Float]? = nil
    }

    var layers: [Layer]
    var renderOrderLayerIDs: [Int] { layers.map(\.id) }
}

extension SceneRenderDescriptor.Layer {
    static func dynamicText(_ mutation: SceneScriptLayerMutation) -> Self? {
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
            str(VM / "SceneQuickJS.h"),
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
