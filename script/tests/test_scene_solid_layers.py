#!/usr/bin/env python3

from __future__ import annotations

from script.tests.source_family import read_source_family
import json
import re
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
SOURCE_ROOT = REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene"
SWIFT_SOURCES = [
    REPOSITORY_ROOT / "script/tests/fixtures/SceneUserPropertyResolutionStub.swift",
    REPOSITORY_ROOT / "script/tests/fixtures/SceneStaticModelMaterialBindingUnavailableStub.swift",
    SOURCE_ROOT / "Runtime/Frame/SceneStaticModelMaterialBindings.swift",
    Path(__file__).resolve().parents[2] / "MyWallpaperX/Core/SteamWorkshopScene/Resources/Textures/SceneResourceBudget.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Diagnostics/ScenePerformanceCounterHub.swift",
    SOURCE_ROOT / "Format/SceneCompatibilityContext.swift",
    SOURCE_ROOT / "Rendering/Composition/SceneBloomPostProcess.swift",
    SOURCE_ROOT / "Systems/Properties/SceneDynamicSnapshot.swift",
    SOURCE_ROOT / "Format/SceneDocument.swift",
    SOURCE_ROOT / "Format/SceneDocument+General.swift",
    SOURCE_ROOT / "Format/SceneDocument+ShaderValue.swift",
    SOURCE_ROOT / "Format/SceneDocument+Timeline.swift",
    SOURCE_ROOT / "Format/SceneDocumentObject.swift",
    SOURCE_ROOT / "Format/SceneObjectDependency.swift",
    SOURCE_ROOT / "Format/SceneDirectionalLightDefinition.swift",
    SOURCE_ROOT / "Format/ScenePointLightDefinition.swift",
    SOURCE_ROOT / "Format/SceneSpotLightDefinition.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Text/SceneTextScriptDefinition.swift",
    SOURCE_ROOT / "Format/SceneTimelineAnimation.swift",
    SOURCE_ROOT / "Format/SceneDocument+NumericParsing.swift",
    SOURCE_ROOT / "Format/ScenePuppetAnimationLayer.swift",
    SOURCE_ROOT / "Format/SceneJSONValue.swift",
    SOURCE_ROOT / "Format/SceneScriptBindingDefinition.swift",
    SOURCE_ROOT / "Systems/Properties/SceneScriptDynamicProviderHostContract.swift",
    SOURCE_ROOT / "Format/SceneScriptSourceEvidence.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Compilation/Material/SceneEffectDefinition.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Compilation/Material/SceneEffectTextureInput.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Composition/SceneUtilityLayer.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Runtime/Frame/SceneRenderDescriptor.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Runtime/Frame/SceneRenderDescriptor+Layer.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Runtime/Frame/SceneRenderDescriptor+AuthoredAssets.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Input/SceneLayerParallax.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Geometry/SceneMatrix.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Puppet/ScenePuppetAttachmentFrameSnapshot.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Geometry/SceneLayerWorldFrameResolver.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Particles/SceneParticleWorldSpacePlan.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Particles/SceneParticleWorldSpacePlan+Descriptor.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Metal/SceneMetalPipeline.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Resources/Textures/SceneSolidLayerTexture.swift",
    SOURCE_ROOT / "Resources/Assets/SceneResourceIndex.swift",
    SOURCE_ROOT / "Resources/Assets/SceneResourceView.swift",
    SOURCE_ROOT / "Resources/Textures/SceneTexturePathResolver.swift",
]


SCENE_FIXTURE = {
    "version": 3,
    "general": {
        "orthogonalprojection": {"width": 1920, "height": 1080},
        "cameraparallax": True,
        "cameraparallaxamount": 0.125,
        "cameraparallaxmouseinfluence": 1,
    },
    "objects": [
        {
            "id": 10,
            "name": "Plain solid",
            "image": "models/util/solidlayer.json",
            "alignment": "topleft",
            "color": "0.1 0.2 0.3",
            "size": "1920 1080",
            "alpha": 0.75,
        },
        {
            "id": 160,
            "name": "Value-script solid",
            "image": "models/util/solidlayer.json",
            "size": "100 100",
            "visible": {"script": "export function update(v) { return v; }", "value": True},
        },
        {
            "id": 161,
            "name": "Origin-script solid",
            "image": "models/util/solidlayer.json",
            "size": "100 100",
            "origin": {"script": "export function update(v) { return v; }", "value": "0 0 0"},
        },
        {
            "id": 162,
            "name": "Origin-script parent",
            "image": "models/util/solidlayer.json",
            "size": "100 100",
            "origin": {"script": "export function update(v) { return v; }", "value": "0 0 0"},
        },
        {
            "id": 163,
            "name": "Static child of scripted parent",
            "image": "models/util/solidlayer.json",
            "size": "100 100",
            "parent": 162,
        },
        {
            "id": 164,
            "name": "Static parent",
            "image": "models/util/solidlayer.json",
            "size": "100 100",
        },
        {
            "id": 165,
            "name": "Static child",
            "image": "models/util/solidlayer.json",
            "size": "100 100",
            "parent": 164,
        },
        {
            "id": 170,
            "image": "models/util/solidlayer.json",
            "size": "100 100",
            "origin": "120 240 3",
            "angles": "0 0 1.5707963267948966",
            "scale": "2 4 -1",
            "parallaxDepth": "0.25 -0.5",
        },
        {
            "id": 171,
            "particle": "particles/owned.json",
            "parent": 170,
            "origin": "10 20 7",
            "scale": "0.5 2 1",
        },
        {
            "id": 180,
            "image": "models/util/solidlayer.json",
            "size": "100 100",
            "origin": "120 240 3",
            "angles": "0 0 1.5707963267948966",
            "scale": "2 4 -1",
            "parallaxDepth": "0 0",
        },
        {
            "id": 181,
            "particle": "particles/owned.json",
            "parent": 180,
            "origin": "10 20 7",
            "scale": "0.5 2 1",
        },
        {
            "id": 190,
            "image": "models/util/solidlayer.json",
            "size": "100 100",
            "origin": {"value": "120 240 3", "script": "export function update(v) { return v; }"},
            "parallaxDepth": "0.25 -0.5",
        },
        {"id": 191, "particle": "particles/owned.json", "parent": 190},
        {
            "id": 20,
            "name": "Wrapped solid",
            "image": "models/util/solidlayer.json",
            "color": {"value": "0.4 0.5 0.6"},
            "size": "640 480",
            "alpha": {"script": "export function update() {}", "value": 0},
        },
        {
            "id": 30,
            "name": "Default white solid",
            "image": "models/util/solidlayer.json",
            "size": "320 200",
            "alpha": {"user": "opacity", "value": 0.25},
            "instance": {
                "id": 31,
                "textures": ["util\\white", None],
                "usertextures": [
                    {"type": "system", "name": "$mediaThumbnail"},
                    42,
                    {
                        "type": "system",
                        "name": "$mediaThumbnail",
                        "future": True,
                    },
                ],
                "combos": {"version": 2},
                "futurekey": {"preserve": True},
            },
        },
        {
            "id": 33,
            "image": "models/util/solidlayer.json",
            "size": "2560 1440",
            "color": "0.2 0.4 0.6",
            "instance": {"textures": ["custom/carrier"], "combos": {"version": 2}},
        },
        {
            "id": 34,
            "image": "models/util/solidlayer.json",
            "size": "640 480",
            "instance": {"textures": ["custom/missing"], "combos": {"version": 2}},
        },
        {
            "id": 40,
            "name": "Regular image",
            "image": "models/user/photo.json",
            "alignment": {"value": "bottomleft"},
            "size": "100 100",
            "brightness": 3.0,
            "effects": [
                {
                    "file": "effects/blend/effect.json",
                    "passes": [
                        {
                            "textures": [
                                None,
                                "_rt_imageLayerComposite_42_a",
                            ],
                            "constantshadervalues": {
                                "Opacity": {"user": "opacity", "value": 0.75},
                            },
                            "usertextures": [
                                None,
                                {"type": "system", "name": "$mediaThumbnail"},
                                "newproperty25",
                            ],
                        }
                    ],
                }
            ],
        },
        {
            "id": 45,
            "name": "Model-declared size image",
            "image": "models/user/declared.json",
        },
        {
            "id": 50,
            "name": "Composition without parallax",
            "image": "models/util/composelayer.json",
        },
        {
            "id": 60,
            "name": "Composition with authored parallax",
            "image": "models/util/composelayer.json",
            "parallaxDepth": "0.25 -0.5",
        },
        {
            "id": 70,
            "name": "Puppet",
            "image": "models/puppet.json",
            "animationlayers": [
                {
                    "id": 701,
                    "animation": 702,
                    "name": "Idle",
                    "additive": False,
                    "blend": 1.0,
                    "blendin": False,
                    "blendout": False,
                    "blendtime": 0.5,
                    "rate": 1.0,
                    "visible": {"user": "animate", "value": True},
                }
            ],
        },
        # text 通道在 CoreText 栅格化阶段消费同一个 brightness key，descriptor 仍要保留原始声明。
        {
            "id": 80,
            "name": "Text with brightness",
            "text": "Hi",
            "brightness": 4.0,
            "size": "100 40",
        },
    ],
}


HARNESS_SOURCE = r'''
// Unused target-format shell; this harness exercises solid parsing and textures.
enum SceneGraphRenderTargetPlan { enum TextureFormat { case rgba16f, rgbaBackbuffer } }
import Foundation
import Metal

struct SceneParticleInstanceOverride: Codable {}

struct SceneParticleDefinitionParser {
    func parseInstanceOverride(_ raw: Any?) -> SceneParticleInstanceOverride? { nil }
}

struct SceneTextDescriptor: Codable {
    let padding: Float

    init(padding: Float = 0) {
        self.padding = padding
    }

    static func parse(_ root: [String: Any]) -> SceneTextDescriptor { .init() }
}

enum SceneTextGeometry {
    static func expandedSize(authoredSize: [Float]?, padding: Float) -> [Float]? {
        authoredSize
    }
}

enum SceneUserPropertyValue {}

enum SceneUserPropertyKind {
    case sceneTexture
}

struct SceneUserPropertyDefinition {
    let key: String
    let kind: SceneUserPropertyKind
}

struct SceneUserPropertyCatalog {
    let definitions: [SceneUserPropertyDefinition]

    static let empty = SceneUserPropertyCatalog(definitions: [])
}



struct SceneUserPropertyDocumentResolver {
    func resolve(
        root: [String: Any],
        catalog: SceneUserPropertyCatalog,
        overrides: [String: SceneUserPropertyValue]
    ) -> SceneUserPropertyResolution {
        SceneUserPropertyResolution(root: root)
    }
}

struct ScenePkgExtractionReport {
    let outputURL: URL?
}

struct SceneProject {
    let rootURL: URL
    let entryPath: String
    let userProperties: SceneUserPropertyCatalog

    var entryURL: URL { rootURL.appendingPathComponent(entryPath) }
}

struct SceneMdlPuppetAttachment {
    let name: String
    let sceneBindFrameColumnMajor: [Float]
}

struct SceneAssetCatalog {
    struct ModelAsset {
        let relativePath: String
        let materialPath: String?
        let cropOffsetXY: [Float]?
        let isSolidLayer: Bool
        let declaredSizeWH: [Float]?
        let puppetPath: String?
        let puppetAttachments: [SceneMdlPuppetAttachment]
    }

    struct MaterialAsset {
        struct Pass {
            let shader: String?
            let textures: [String]
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

        let relativePath: String
        let rawSHA256: String
        let shaderPathIndependentSHA256: String
        let passes: [Pass]
    }

    let models: [ModelAsset]
    let materials: [MaterialAsset]
    let effectDefinitions: [SceneEffectDefinition]
    let effectDefinitionDiagnostics: [SceneEffectDefinitionDiagnostic]
    let shaderReferences: [String]
    var shaderContracts: [Never] { [] }
    let textureReferences: [String]
}

struct SceneResourceReferenceIndex {
    let missingReferences: [String]
    let builtInReferenceCount: Int
    let runtimeProvidedReferenceCount: Int
}

struct SceneCapabilityProfile {
    let firstStageRendererGaps: [String]
}

struct SceneDiagnosticsReport {
    let project: SceneProject?
    let sceneDocument: SceneDocument?
    let assetCatalog: SceneAssetCatalog?
    let resourceReferences: SceneResourceReferenceIndex?
    let capabilityProfile: SceneCapabilityProfile?
}

@main
enum Harness {
    static func main() throws {
        guard CommandLine.arguments.count == 3 else { throw HarnessError.missingFixture }
        let sceneURL = URL(fileURLWithPath: CommandLine.arguments[1])
        let duplicateSceneURL = URL(fileURLWithPath: CommandLine.arguments[2])
        let document = try SceneDocumentLoader().load(from: sceneURL)
        let project = SceneProject(
            rootURL: sceneURL.deletingLastPathComponent(),
            entryPath: sceneURL.lastPathComponent,
            userProperties: .empty
        )
        let assetCatalog = SceneAssetCatalog(
            models: [
                .init(
                    relativePath: "models/user/declared.json",
                    materialPath: nil,
                    cropOffsetXY: nil,
                    isSolidLayer: false,
                    declaredSizeWH: [1920, 1080],
                    puppetPath: nil,
                    puppetAttachments: []
                ),
                .init(
                    relativePath: "models/user/photo.json",
                    materialPath: nil,
                    cropOffsetXY: nil,
                    isSolidLayer: false,
                    declaredSizeWH: [4000, 3000],
                    puppetPath: nil,
                    puppetAttachments: []
                ),
            ],
            materials: [],
            effectDefinitions: [],
            effectDefinitionDiagnostics: [],
            shaderReferences: [],
            textureReferences: []
        )
        let resourceReferences = SceneResourceReferenceIndex(
            missingReferences: [], builtInReferenceCount: 3,
            runtimeProvidedReferenceCount: 0
        )
        let capabilityProfile = SceneCapabilityProfile(firstStageRendererGaps: [])
        let duplicateIdentityError: String
        var duplicateDescriptorReached = false
        do {
            let duplicateDocument = try SceneDocumentLoader().load(from: duplicateSceneURL)
            _ = SceneRenderDescriptorBuilder().build(
                project: project,
                sceneDocument: duplicateDocument,
                assetCatalog: assetCatalog,
                resourceReferences: resourceReferences,
                capabilityProfile: capabilityProfile
            )
            duplicateDescriptorReached = true
            duplicateIdentityError = ""
        } catch {
            duplicateIdentityError = error.localizedDescription
        }
        guard let descriptor = SceneRenderDescriptorBuilder().build(
            project: project,
            sceneDocument: document,
            assetCatalog: assetCatalog,
            resourceReferences: resourceReferences,
            capabilityProfile: capabilityProfile
        ) else {
            throw HarnessError.descriptorRejected
        }

        func bloomDescriptor(_ general: [String: Any]) throws -> SceneBloomConfiguration {
            let url = sceneURL.deletingLastPathComponent().appendingPathComponent("bloom.json")
            try JSONSerialization.data(withJSONObject: ["general": general, "objects": []]).write(to: url)
            let parsed = try SceneDocumentLoader().load(from: url)
            let result = SceneRenderDescriptorBuilder().build(project: project, sceneDocument: parsed,
                assetCatalog: assetCatalog, resourceReferences: resourceReferences,
                capabilityProfile: capabilityProfile)!.camera.bloom
            let decoded = try JSONDecoder().decode(SceneBloomConfiguration.self,
                from: JSONEncoder().encode(result))
            precondition(decoded == result)
            return decoded
        }
        let defaultHDR = try bloomDescriptor(["hdr": true, "bloom": true])
        let explicitHDR = try bloomDescriptor(["hdr": true, "bloom": true, "bloomstrength": 7,
            "bloomhdrstrength": ["user": "power", "value": 0.5], "bloomhdrthreshold": 0.75,
            "bloomhdrscatter": 2, "bloomhdrfeather": 0.9, "bloomhdriterations": 3])
        let standardBloom = try bloomDescriptor(["hdr": false, "bloom": true, "bloomhdrstrength": 9])
        let bloomProfiles = defaultHDR.hdr == .init(strength: 2, threshold: 1, scatter: 1.619,
                feather: 0.1, iterations: 8)
            && explicitHDR.hdr == .init(strength: 0.5, threshold: 0.75, scatter: 2,
                feather: 0.9, iterations: 3)
            && explicitHDR.strength == 7 && standardBloom.hdr == nil

        guard let device = MTLCreateSystemDefaultDevice(),
              let solidTexture = SceneSolidLayerTexture.make(device: device) else {
            throw HarnessError.noMetal
        }
        var pixel = [UInt8](repeating: 0, count: 4)
        solidTexture.getBytes(
            &pixel,
            bytesPerRow: 4,
            from: MTLRegionMake2D(0, 0, 1, 1),
            mipmapLevel: 0
        )

        let uniform = SceneLayerFragmentUniforms(
            time: 0,
            alpha: 0.75,
            dependencyBlendMode: 0,
            usesDependencyBlend: 0,
            cursorUV: .zero,
            sourceSampling: .zero,
            tint: SIMD4(0.1, 0.2, 0.3, 1),
            textureFrame0: SIMD4(0, 0, 1, 0),
            textureFrame1: SIMD4(0, 1, 0, 0)
        )

        let objects = Dictionary(uniqueKeysWithValues: document.objects.map { ($0.id, $0) })
        let layers = Dictionary(uniqueKeysWithValues: descriptor.layers.map { ($0.id, $0) })
        let sourceResolver = SceneTexturePathResolver(
            resourceView: SceneResourceView(projectRootURL: project.rootURL,
                packageRootURL: nil, stockAssetsRootURL: nil),
            descriptor: descriptor
        )
        let solidSourceInputs = [10, 30, 33, 34].map { id -> [String: Any] in
            let layer = layers[id]!
            return ["staticPath": layer.staticBaseTexturePath ?? "",
                "resolvedFile": sourceResolver.resolvePrimaryTexture(for: layer)?.lastPathComponent ?? "",
                "size": layer.sizeWH ?? [], "color": layer.colorRGB ?? []]
        }
        let splitMaterialInstance = SceneDocument.SceneLayerMaterialInstance.parse(
            [
                "textures": ["resolved/cover"],
                "usertextures": [["user": "cover", "value": "resolved/cover"]],
            ],
            authoredRaw: [
                "textures": ["authored/cover"],
                "usertextures": [["user": "cover", "value": "authored/cover"]],
            ]
        )
        let authoredRawTexture: String?
        if case let .object(root)? = splitMaterialInstance?.rawValue,
           case let .array(textures)? = root["textures"],
           let first = textures.first,
           case let .string(value) = first {
            authoredRawTexture = value
        } else {
            authoredRawTexture = nil
        }
        let frames = descriptor.staticParticleWorldSpaceFrames
        let chains = descriptor.staticParticleWorldSpaceChains
        let worldFrames = SceneLayerWorldFrameResolver.compute(descriptor: descriptor, byID: layers)
        let parallax = SceneLayerParallax.resolveAll(layersByID: layers)
        let staticWorldSpaceTRS = Dictionary(uniqueKeysWithValues: [170, 171, 180, 181, 190, 191].map { id in
            var result: [String: Any] = [
                "chain": chains[id]?.sorted() ?? [], "admitted": frames[id] != nil,
                "parallaxSource": parallax[id]?.sourceLayerID ?? -1,
                "parallaxDepth": parallax[id].map { [$0.depth.x, $0.depth.y] } ?? [],
            ]
            if let frame = frames[id] {
                let direction = frame.localParticleDirection(SIMD3(8, 1, -2))
                result["localParticleDirection"] = [direction.x, direction.y, direction.z]
                let basis = frame.worldToLocalDirection
                result["worldToLocalDirection"] = [basis.columns.0.x, basis.columns.0.y, basis.columns.0.z,
                    basis.columns.1.x, basis.columns.1.y, basis.columns.1.z,
                    basis.columns.2.x, basis.columns.2.y, basis.columns.2.z]
            }
            if let world = worldFrames[id] {
                result["worldTranslation"] = [world.columns.3.x, world.columns.3.y, world.columns.3.z]
            }
            return (String(id), result)
        })
        let result: [String: Any] = [
            "bloomProfiles": bloomProfiles,
            "solidSourceInputs": solidSourceInputs,
            "staticWorldSpaceTRS": staticWorldSpaceTRS,
            "cameraParallaxEnabled": descriptor.camera.parallaxEnabled,
            "worldSpaceFrameLayerIDs": descriptor.staticParticleWorldSpaceFrames.keys.sorted(),
            "documentColors": [10, 20, 30].map { objects[$0]?.colorRGB ?? [] },
            "contentKinds": [10, 20, 30, 40].map { layers[$0]?.contentKind ?? "" },
            "modelDeclaredSizeWH": [45, 40].map { layers[$0]?.sizeWH ?? [] },
            "descriptorColors": [10, 20, 30].map { layers[$0]?.colorRGB ?? [] },
            "documentAlphas": [10, 20, 30, 40].map { objects[$0]?.alpha ?? -1 },
            "descriptorAlphas": [10, 20, 30, 40].map { layers[$0]?.alpha ?? -1 },
            "descriptorBrightness": [10, 40, 80].map { layers[$0]?.brightness ?? -1 },
            "imageAlignments": [10, 20, 40, 80].map {
                layers[$0]?.imageAlignment ?? "nil"
            },
            "brightnessContentKinds": [40, 80].map { layers[$0]?.contentKind ?? "" },
            "materialInstance": [
                "id": objects[30]?.materialInstance?.id ?? -1,
                "textureSlots": objects[30]?.materialInstance?.textureSlots.map {
                    $0 ?? "nil"
                } ?? [],
                "userTextureKinds": objects[30]?.materialInstance?.userTextureInputs.map {
                    $0?.kind.rawValue ?? "nil"
                } ?? [],
                "hasUserTextureOverride": objects[30]?.materialInstance?
                    .hasUserTextureOverride ?? false,
                "hasRawValue": objects[30]?.materialInstance?.rawValue != nil,
                "combos": objects[30]?.materialInstance?.combos ?? [:],
                "unknownKeys": objects[30]?.materialInstance?.unknownKeys ?? [],
                "isMalformed": objects[30]?.materialInstance?.isMalformed ?? true,
            ] as [String: Any],
            "splitMaterialInstance": [
                "effectiveTexture": splitMaterialInstance?.textureSlots.compactMap {
                    $0
                }.first ?? "",
                "authoredRawTexture": authoredRawTexture ?? "",
                "effectiveProperty": splitMaterialInstance?.userTextureInputs.compactMap {
                    $0
                }.first?.value ?? "",
            ],
            "userTextureInputKinds": layers[40]?.effects.first?.passes.first?.userTextureInputs.map {
                $0?.kind.rawValue ?? "nil"
            } ?? [],
            "wrappedShaderComponents": layers[40]?.effects.first?.passes.first?
                .constantShaderValues["Opacity"]?.components ?? [],
            "compositionParallaxDepths": [50, 60].map {
                layers[$0]?.parallaxDepthXY ?? []
            },
            "imageRenderable": [10, 20, 30, 40].map {
                layers[$0]?.isImageRenderable ?? false
            },
            "puppetAnimationLayers": layers[70]?.puppetAnimationLayers.map {
                [
                    "id": $0.id ?? -1,
                    "animationID": $0.animationID ?? -1,
                    "additive": $0.additive ?? true,
                    "blend": $0.blend ?? -1,
                    "blendIn": $0.blendIn ?? true,
                    "blendOut": $0.blendOut ?? true,
                    "blendTime": $0.blendTime ?? -1,
                    "rate": $0.rate ?? -1,
                    "visible": $0.visible ?? false,
                    "visibilityBinding": $0.visibilityBinding ?? "",
                ] as [String: Any]
            } ?? [],
            "uniformTint": [uniform.tint.x, uniform.tint.y, uniform.tint.z, uniform.tint.w],
            "textureSize": [solidTexture.width, solidTexture.height],
            "texturePixel": pixel,
            "duplicateIdentityError": duplicateIdentityError,
            "duplicateDescriptorReached": duplicateDescriptorReached,
        ]
        let data = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }

    enum HarnessError: Error {
        case missingFixture
        case noMetal
        case descriptorRejected
    }
}
'''


class SceneSolidLayerTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        swiftc = shutil.which("swiftc")
        if swiftc is None:
            raise unittest.SkipTest("swiftc is unavailable")
        missing_sources = [path for path in SWIFT_SOURCES if not path.is_file()]
        if missing_sources:
            raise RuntimeError(
                "Scene solid production contract is missing: "
                + ", ".join(path.name for path in missing_sources)
            )

        cls.temporary_directory = tempfile.TemporaryDirectory(prefix="mwx-scene-solid-")
        directory = Path(cls.temporary_directory.name)
        fixture = directory / "scene.json"
        fixture.write_text(json.dumps(SCENE_FIXTURE), encoding="utf-8")
        carrier = directory / "materials/custom/carrier.tex"
        carrier.parent.mkdir(parents=True)
        carrier.write_bytes(b"owned resolver fixture")
        duplicate_fixture = directory / "duplicate-scene.json"
        duplicate_scene = {
            "objects": [
                {"id": 10, "image": "models/user/first.json"},
                {"id": 10, "image": "models/user/second.json"},
                {"id": 20, "image": "models/user/third.json"},
                {"id": 20, "image": "models/user/fourth.json"},
            ]
        }
        duplicate_fixture.write_text(json.dumps(duplicate_scene), encoding="utf-8")
        harness = directory / "Harness.swift"
        harness.write_text(HARNESS_SOURCE, encoding="utf-8")
        cls.binary = directory / "scene-solid-layers"
        compilation = subprocess.run(
            [
                "xcrun",
                "--sdk",
                "macosx",
                "swiftc",
                *(str(path) for path in SWIFT_SOURCES),
                str(harness),
                "-framework",
                "Metal",
                "-o",
                str(cls.binary),
            ],
            capture_output=True,
            text=True,
        )
        if compilation.returncode != 0:
            raise RuntimeError(compilation.stderr)
        completed = subprocess.run(
            [str(cls.binary), str(fixture), str(duplicate_fixture)],
            check=True,
            capture_output=True,
            text=True,
        )
        cls.result = json.loads(completed.stdout)

    @classmethod
    def tearDownClass(cls) -> None:
        if hasattr(cls, "temporary_directory"):
            cls.temporary_directory.cleanup()

    def test_hdr_bloom_document_descriptor_and_codable_preserve_profile(self):
        self.assertTrue(self.result["bloomProfiles"])

    def test_world_space_gate_admits_value_scripts_and_rejects_transform_writers(self) -> None:
        eligible = self.result["worldSpaceFrameLayerIDs"]
        # A visibility value script is not a transform writer: the chain stays
        # authored-static and the world-space frame admits it.
        self.assertIn(160, eligible)
        # Declared transform writers keep the hard rejection.
        self.assertNotIn(161, eligible)
        # A static child under a scripted parent is chain-dynamic.
        self.assertNotIn(163, eligible)
        # A fully static chain remains eligible.
        self.assertIn(165, eligible)
        self.assertIn(164, eligible)

    def test_solid_layer_classification_and_renderability(self) -> None:
        self.assertEqual(self.result["contentKinds"], ["solid", "solid", "solid", "image"])
        self.assertEqual(self.result["imageRenderable"], [True, True, True, True])

    def test_static_world_space_trs_inherits_parallax_without_changing_direction(self) -> None:
        self.assertTrue(self.result["cameraParallaxEnabled"])
        facts = self.result["staticWorldSpaceTRS"]
        for layer_id in [170, 171, 180, 181]:
            with self.subTest(layer=layer_id):
                self.assertTrue(facts[str(layer_id)]["admitted"])
        self.assertEqual(facts["171"]["chain"], [170, 171])
        self.assertEqual(facts["181"]["chain"], [180, 181])
        self.assertEqual(facts["171"]["parallaxSource"], 170)
        self.assertEqual(facts["171"]["parallaxDepth"], [0.25, -0.5])
        self.assertEqual(facts["181"]["parallaxDepth"], [0, 0])
        self.assertEqual(facts["171"]["worldToLocalDirection"], facts["181"]["worldToLocalDirection"])
        # Parent rotation and nonuniform/mirrored scale, then child scale:
        # scene basis columns are (0,-1,0), (8,0,0), (0,0,-1).
        for actual, expected in zip(facts["171"]["localParticleDirection"], [1, -1, 2]):
            self.assertAlmostEqual(actual, expected, places=6)
        for actual, expected in zip(facts["171"]["worldTranslation"], [40, 820, -4]):
            self.assertAlmostEqual(actual, expected, places=5)
        for layer_id in [190, 191]:
            with self.subTest(transform_writer_chain=layer_id):
                self.assertFalse(facts[str(layer_id)]["admitted"])
                self.assertEqual(facts[str(layer_id)]["chain"], [])

    def test_model_declared_size_inherits_only_without_explicit_size(self) -> None:
        # 缺口 1：model 引用层无显式 size 时继承模型声明的 width/height；
        # 显式 size 仍逐字优先（40 的 "100 100" 压过 photo.json 的 4000×3000）。
        self.assertEqual(
            self.result["modelDeclaredSizeWH"],
            [[1920.0, 1080.0], [100.0, 100.0]],
        )

    def test_duplicate_object_ids_fail_before_descriptor_construction(self) -> None:
        error = self.result["duplicateIdentityError"]
        self.assertIn("重复对象 ID（10, 20）", error)
        self.assertIn("duplicate-scene.json", error)
        self.assertFalse(self.result["duplicateDescriptorReached"])

    def test_plain_wrapped_and_missing_colors_resolve_to_rgb(self) -> None:
        document_expected = [[0.1, 0.2, 0.3], [0.4, 0.5, 0.6], []]
        descriptor_expected = [[0.1, 0.2, 0.3], [0.4, 0.5, 0.6], []]
        for actual_colors, expected_colors in (
            (self.result["documentColors"], document_expected),
            (self.result["descriptorColors"], descriptor_expected),
        ):
            for actual, wanted in zip(actual_colors, expected_colors):
                self.assertEqual(len(actual), len(wanted))
                for component, expected_component in zip(actual, wanted):
                    self.assertAlmostEqual(component, expected_component, places=6)

    def test_plain_script_and_user_wrapped_alpha_preserve_authored_value(self) -> None:
        expected = [0.75, 0, 0.25, -1]
        self.assertEqual(self.result["documentAlphas"], expected)
        self.assertEqual(self.result["descriptorAlphas"], expected)

    def test_image_alignment_round_trips_without_leaking_into_text(self) -> None:
        self.assertEqual(
            self.result["imageAlignments"],
            ["topleft", "nil", "bottomleft", "nil"],
        )

    def test_effect_texture_inputs_keep_system_property_and_path_slots_typed(self) -> None:
        self.assertEqual(
            self.result["userTextureInputKinds"],
            ["nil", "system", "property"],
        )

    def test_layer_material_instance_preserves_slots_unknown_input_and_keys(self) -> None:
        self.assertEqual(
            self.result["materialInstance"],
            {
                "id": 31,
                "textureSlots": ["util/white", "nil"],
                "userTextureKinds": ["system", "unknown", "unknown"],
                "hasUserTextureOverride": True,
                "hasRawValue": True,
                "combos": {"version": 2},
                "unknownKeys": ["futurekey"],
                "isMalformed": False,
            },
        )

    def test_layer_material_instance_keeps_authored_raw_separate_from_effective_projection(
        self,
    ) -> None:
        self.assertEqual(
            self.result["splitMaterialInstance"],
            {
                "effectiveTexture": "resolved/cover",
                "authoredRawTexture": "authored/cover",
                "effectiveProperty": "cover",
            },
        )

    def test_numeric_shader_wrapper_preserves_components(self) -> None:
        self.assertEqual(self.result["wrappedShaderComponents"], [0.75])

    def test_composition_parallax_requires_an_authored_depth(self) -> None:
        self.assertEqual(self.result["compositionParallaxDepths"], [[], [0.25, -0.5]])

    def test_fragment_uniform_carries_layer_tint(self) -> None:
        for actual, expected in zip(self.result["uniformTint"], [0.1, 0.2, 0.3, 1]):
            self.assertAlmostEqual(actual, expected, places=6)

        compositor = (REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Composition/SceneImageLayerCompositor.swift").read_text(
            encoding="utf-8"
        )
        compositor_uniforms = (
            REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Composition/SceneImageLayerCompositor+Uniforms.swift"
        ).read_text(encoding="utf-8")
        shader = (REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Composition/SceneImageLayer.metal").read_text(
            encoding="utf-8"
        )
        self.assertRegex(
            compositor_uniforms,
            re.compile(
                r"usesAuthoredColor[^=]{0,40}=\s*layer\.contentKind\s*==\s*\"image\""
                r'[\s\S]{0,120}layer\.contentKind\s*==\s*"solid"'
                r"[\s\S]{0,160}values\.tint"
            ),
        )
        renderer = read_source_family(REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Frame/SceneMetalRenderer.swift")
        self.assertIn("tint: baseSource.usesAuthoredLayerColor", renderer)
        self.assertRegex(
            compositor_uniforms,
            re.compile(r"SceneLayerFragmentUniforms\([\s\S]{0,900}\btint\s*:\s*SIMD4\(tint\.x"),
        )
        self.assertRegex(shader, re.compile(r"\buniforms\.tint\b"))

    def test_authored_brightness_multiplies_layer_tint_but_not_text(self) -> None:
        # 官方随包 razer_bedroom 的 wave layer 用 brightness 3.0/4.0 过曝发光；未声明的 layer
        # 保持 nil（harness 用 -1 表示），text layer 的声明也照原样进 descriptor，但因为
        # contentKind 为 text，compositor 必须跳过乘法，交给 CoreText 栅格化消费。
        self.assertEqual(self.result["descriptorBrightness"], [-1, 3, 4])
        self.assertEqual(self.result["brightnessContentKinds"], ["image", "text"])

        compositor_uniforms = (
            REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Composition/SceneImageLayerCompositor+Uniforms.swift"
        ).read_text(encoding="utf-8")
        self.assertRegex(
            compositor_uniforms,
            re.compile(
                r'layer\.contentKind == "text"'
                r"[\s\S]{0,160}layer\.brightness \?\? 1"
            ),
        )
        self.assertRegex(
            compositor_uniforms,
            re.compile(r"tint\s*:\s*tint(?:\s*\*\s*sourceMaterialColor)?\s*\*\s*brightness"),
        )

    def test_puppet_animation_layer_round_trips_into_descriptor(self) -> None:
        self.assertEqual(
            self.result["puppetAnimationLayers"],
            [
                {
                    "id": 701,
                    "animationID": 702,
                    "additive": False,
                    "blend": 1,
                    "blendIn": False,
                    "blendOut": False,
                    "blendTime": 0.5,
                    "rate": 1,
                    "visible": True,
                    "visibilityBinding": "animate",
                }
            ],
        )

    def test_explicit_static_solid_source_uses_resolver_without_changing_author_values(self) -> None:
        expected = [
            ("", "", [1920, 1080], [0.1, 0.2, 0.3]),
            ("", "", [320, 200], []),
            ("custom/carrier", "carrier.tex", [2560, 1440], [0.2, 0.4, 0.6]),
            ("custom/missing", "", [640, 480], []),
        ]
        self.assertEqual(len(self.result["solidSourceInputs"]), len(expected))
        for actual, (path, filename, size, color) in zip(self.result["solidSourceInputs"], expected):
            self.assertEqual((actual["staticPath"], actual["resolvedFile"], actual["size"]), (path, filename, size))
            self.assertEqual(len(actual["color"]), len(color))
            for channel, expected_channel in zip(actual["color"], color):
                self.assertAlmostEqual(channel, expected_channel, places=6)

    def test_procedural_solid_fallback_reuses_white_texture(self) -> None:
        self.assertEqual(self.result["textureSize"], [1, 1])
        self.assertEqual(self.result["texturePixel"], [255, 255, 255, 255])


if __name__ == "__main__":
    unittest.main()
