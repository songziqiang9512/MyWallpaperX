import Foundation

// Thin external carriers only. The Python gate inserts the unmodified product
// join method, dynamic resource, lighting profile and template declarations.
// Reference objects stand in for prepared textures and video files; this
// harness neither prepares media nor allocates or validates GPU resources.
final class MTLTexture {
    let width: Int
    let height: Int
    init(width: Int = 96, height: Int = 48) {
        self.width = width
        self.height = height
    }
}
struct SceneTextureCandidate { let texture: MTLTexture }
enum SceneTextureLoader { struct SourceKey: Hashable { let token: String } }
final class SceneVideoOwnedFile {}
struct SceneMaterialRenderState: Equatable, Sendable {}
enum ScenePuppetLayerLoad { struct PreparedPose {} }
struct SceneAssetTextureIdentity: Equatable, Sendable { let token: String }
struct SceneDynamicTarget: Equatable, Sendable { let token: String }
struct ScenePreparedBaseImageResources {
    let dynamicImageResources: [String: ScenePreparedDynamicImageResource]
}
enum SceneAssetCatalog {
    struct ModelAsset {
        let relativePath: String
        let autosize: Bool?
    }
}
struct SceneRenderDescriptor {
    struct Camera { let orthoHeight: Float? }
    struct UtilityLayer {
        enum Kind { case composition, other }
        let kind: Kind
    }
    struct Layer {
        let imagePath: String?
        let utilityLayer: UtilityLayer?
    }
    let camera: Camera
    let layers: [Layer]
}

@main
enum ScenePreparedScriptResourceCatalogHarness {
    static func main() throws {
        typealias Resource = ScenePreparedDynamicImageResource
        typealias Profile = SceneBaseMaterialLightingProfile
        let lit = Profile(lightingEnabled: true, scalarMaterial: SIMD2(0.21, 0.79), normalSource: .disabled)
        func resource(_ path: String, profile: Profile? = nil,
                      natural: [Float]? = nil, mesh: String? = nil) -> Resource {
            .init(modelPath: path, product: .image(.init(texture: MTLTexture())),
                naturalSizeWH: natural, puppetMeshPath: mesh, lightingProfile: profile)
        }
        let videoSource = SceneTextureLoader.SourceKey(token: "prepared-video")
        let videoFile = SceneVideoOwnedFile()
        func video(_ path: String, profile: Profile? = .disabled) -> Resource {
            .init(modelPath: path, product: .video(source: videoSource, file: videoFile, sizeWH: [3750, 2250]),
                naturalSizeWH: [3750, 2250], lightingProfile: profile)
        }
        let sourcePaths: Set<String> = ["models/full-source.json", "models/lowered.json",
            "models/video-source.json"]
        let resources: [String: Resource] = [
            "models/plain.json": resource("models/plain.json", profile: .disabled),
            "models/lit.json": resource("models/lit.json", profile: lit),
            "models/full-source.json": resource("MODELS\\FULL-SOURCE.JSON"),
            "models/lowered.json": resource("models/lowered.json"),
            "models/unknown.json": resource("models/unknown.json"),
            "models/autosize.json": resource("models/autosize.json", profile: lit, natural: [800, 600]),
            "models/autosize-missing.json": resource("models/autosize-missing.json", profile: lit),
            "models/video.json": video("models/video.json"),
            "models/video-autosize.json": video("MODELS\\VIDEO-AUTOSIZE.JSON"),
            "models/video-source.json": video("models/video-source.json", profile: nil),
            "models/video-unknown.json": video("models/video-unknown.json", profile: nil),
            "models/puppet.json": resource("models/puppet.json", profile: .disabled,
                natural: [512, 256], mesh: "models/unseen-puppet.mdl")
        ]
        let models: [SceneAssetCatalog.ModelAsset] = [
            .init(relativePath: "MODELS/AUTOSIZE.JSON", autosize: true),
            .init(relativePath: "MODELS/AUTOSIZE-MISSING.JSON", autosize: true),
            .init(relativePath: "MODELS/VIDEO-AUTOSIZE.JSON", autosize: true),
            .init(relativePath: "models/puppet.json", autosize: false),
            .init(relativePath: "models/plain.json", autosize: nil)
        ]
        let composition = SceneRenderDescriptor.Layer(imagePath: "models/composition.json",
            utilityLayer: .init(kind: .composition))
        let otherUtility = SceneRenderDescriptor.Layer(imagePath: "models/not-composition.json",
            utilityLayer: .init(kind: .other))
        let noPath = SceneRenderDescriptor.Layer(imagePath: nil, utilityLayer: .init(kind: .composition))
        let descriptor = SceneRenderDescriptor(camera: .init(orthoHeight: 1080),
            layers: [composition, otherUtility, noPath])
        let joined = SceneDesktopWallpaperLaunchFrameSchema.preparedResourceCatalog(
            descriptor: descriptor, baseImages: .init(dynamicImageResources: resources),
            models: models, sourceMaterialModelPaths: sourcePaths)
        let sourceResources = resources.filter { sourcePaths.contains(SceneModelResourceIdentity($0.value.modelPath).value) }
        let unprovedSources = SceneDesktopWallpaperLaunchFrameSchema.preparedResourceCatalog(
            descriptor: .init(camera: .init(orthoHeight: nil), layers: []),
            baseImages: .init(dynamicImageResources: sourceResources), models: [], sourceMaterialModelPaths: [])
        let compositionOnly = SceneDesktopWallpaperLaunchFrameSchema.preparedResourceCatalog(
            descriptor: descriptor, baseImages: .init(dynamicImageResources: [:]),
            models: [], sourceMaterialModelPaths: [])
        let noOrthoComposition = [Float?.none, 0, -1].allSatisfy { height in
            let catalog = SceneDesktopWallpaperLaunchFrameSchema.preparedResourceCatalog(
                descriptor: .init(camera: .init(orthoHeight: height), layers: [composition]),
                baseImages: .init(dynamicImageResources: [:]), models: [], sourceMaterialModelPaths: [])
            return catalog.templates.isEmpty && catalog.lightingProfiles.isEmpty
        }
        let rejectedPaths = [
            "models/unknown.json", "models/autosize-missing.json",
            "models/video-unknown.json",
            "models/not-composition.json"
        ]
        let payload: [String: Any] = [
            "templates": joined.templates.mapValues { template in
                ["modelPath": template.modelPath, "renderSizeWH": template.renderSizeWH,
                 "autosize": template.autosize, "puppetMeshPath": template.puppetMeshPath.map { $0 as Any } ?? NSNull(),
                 "kind": template.kind == .composition ? "composition" : "image",
                 "defaultRenderSizeWH": template.defaultRenderSizeWH] as [String: Any]
            },
            "profiles": joined.lightingProfiles.mapValues { profile in
                ["lighting": profile.lightingEnabled,
                 "scalar": profile.scalarMaterial.map { [$0.x, $0.y] } ?? []] as [String: Any]
            },
            "rejected": Dictionary(uniqueKeysWithValues: rejectedPaths.map { path in
                (path, joined.templates[path] == nil && joined.lightingProfiles[path] == nil)
            }),
            "unprovedSourceTemplates": unprovedSources.templates.keys.sorted(),
            "compositionOnlyProfiles": compositionOnly.lightingProfiles.keys.sorted(),
            "compositionRequiresOrthographicHeight": noOrthoComposition,
            "inputProfilesPreserved": joined.lightingProfiles["models/plain.json"] == .disabled
                && joined.lightingProfiles["models/lit.json"] == lit
                && joined.lightingProfiles["models/autosize.json"] == lit
        ]
        let json = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        print(String(decoding: json, as: UTF8.self))
    }
}
