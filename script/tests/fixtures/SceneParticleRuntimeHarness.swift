
import CoreGraphics
import Foundation
import ImageIO
import Metal
import simd

struct SceneLayerDisplayScriptOwnership: Codable {
    let visible: Bool
    let alpha: Bool
    var fields: [String] {
        (visible ? ["visible"] : []) + (alpha ? ["alpha"] : [])
    }
    var isEmpty: Bool { !visible && !alpha }
}

struct SceneRenderDescriptor: Codable {
    struct ColorTargetFormat {
        let metalPixelFormat: MTLPixelFormat = .bgra8Unorm
    }
    var colorTargetFormat: ColorTargetFormat { .init() }

    struct Layer: Codable {
        let id: Int
        let name: String?
        let contentKind: String
        let particlePath: String?
        let particleInstanceOverride: SceneParticleInstanceOverride?
        var parentID: Int?
        let visible: Bool?
        var displayScriptOwnership: SceneLayerDisplayScriptOwnership? = nil
        let alpha: Double?
        var originXYZ: [Float]? = nil
        var scaleXYZ: [Float]? = nil
        var anglesXYZ: [Float]? = nil
        var originHasScript: Bool? = nil
        var scaleHasScript: Bool? = nil
        var anglesHasScript: Bool? = nil
        var attachmentName: String? = nil
        var parentAttachmentBindFrame: [Float]? = nil
        var childLayerIDs: [Int] = []
        var usesPerspective: Bool? = nil
        var timelines: [SceneDocument.SceneObjectTimeline] = []
        var timelineDiagnostics: [String] = []
        var parallaxDepthXY: [Float]? = nil
        var disablesParallaxPropagation = false
        var utilityLayer: Bool? = nil
        var hasPerspectiveGeometryConsumer: Bool { false }
        var hasFramebufferMaterialSource: Bool { false }
        var cameraPath: CameraPath? = nil
        struct CameraPath: Codable { let camera: String; let fov: Double? }
    }

    struct MaterialPassDescriptor: Codable {
        let materialPath: String
        let passIndex: Int
        let shaderPath: String?
        let texturePaths: [String]
        let textureSlots: [String?]
        let constantShaderValues: [String: SceneDocument.ShaderValue]
        let userTextureInputs: [SceneUserTextureInput?]
        let userShaderValues: [String: String]
        let blending: String?
        let combos: [String: Int]
        let depthTest: String?
        let depthWrite: String?
        let cullMode: String?
        let alphaWriting: String?

        init(
            materialPath: String,
            passIndex: Int = 0,
            shaderPath: String?,
            texturePaths: [String],
            textureSlots: [String?]? = nil,
            constantShaderValues: [String: SceneDocument.ShaderValue] = [:],
            userTextureInputs: [SceneUserTextureInput?] = [],
            userShaderValues: [String: String] = [:],
            blending: String?,
            combos: [String: Int] = [:],
            depthTest: String? = "disabled",
            depthWrite: String? = "disabled",
            cullMode: String? = "nocull",
            alphaWriting: String? = nil
        ) {
            self.materialPath = materialPath
            self.passIndex = passIndex
            self.shaderPath = shaderPath
            self.texturePaths = texturePaths
            self.textureSlots = textureSlots ?? texturePaths.map(Optional.some)
            self.constantShaderValues = constantShaderValues
            self.userTextureInputs = userTextureInputs
            self.userShaderValues = userShaderValues
            self.blending = blending
            self.combos = combos
            self.depthTest = depthTest
            self.depthWrite = depthWrite
            self.cullMode = cullMode
            self.alphaWriting = alphaWriting
        }
    }

    struct CameraDescriptor: Codable {
        var eye: [Float] = [0, 0, 0]
        var center: [Float] = [0, 0, -1]
        var up: [Float] = [0, 1, 0]
        var orthoWidth: Float? = nil
        var orthoHeight: Float? = nil
        let authoredOrthographicProjectionActive: Bool?
        init(authoredOrthographicProjectionActive: Bool? = nil) {
            self.authoredOrthographicProjectionActive = authoredOrthographicProjectionActive
        }
        var fovDegrees: Float? = nil
        var perspectiveOverrideFOVDegrees: Float? = nil
        var nearZ: Float = 0.01
        var farZ: Float = 10000
        var default2DOriginInputLayerID: Int? = nil
    }
    var camera = CameraDescriptor()
    var layers: [Layer]
    let renderOrderLayerIDs: [Int]
    let materialPasses: [MaterialPassDescriptor]


}

// Default absent external metadata exactly as the carrier did before this gate.
extension SceneRenderDescriptor.Layer {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(id: try c.decode(Int.self, forKey: .id),
            name: try c.decodeIfPresent(String.self, forKey: .name),
            contentKind: try c.decode(String.self, forKey: .contentKind),
            particlePath: try c.decodeIfPresent(String.self, forKey: .particlePath),
            particleInstanceOverride: try c.decodeIfPresent(SceneParticleInstanceOverride.self, forKey: .particleInstanceOverride),
            parentID: try c.decodeIfPresent(Int.self, forKey: .parentID),
            visible: try c.decodeIfPresent(Bool.self, forKey: .visible),
            alpha: try c.decodeIfPresent(Double.self, forKey: .alpha))
        displayScriptOwnership = try c.decodeIfPresent(SceneLayerDisplayScriptOwnership.self, forKey: .displayScriptOwnership)
        originXYZ = try c.decodeIfPresent([Float].self, forKey: .originXYZ)
        scaleXYZ = try c.decodeIfPresent([Float].self, forKey: .scaleXYZ)
        anglesXYZ = try c.decodeIfPresent([Float].self, forKey: .anglesXYZ)
        originHasScript = try c.decodeIfPresent(Bool.self, forKey: .originHasScript)
        scaleHasScript = try c.decodeIfPresent(Bool.self, forKey: .scaleHasScript)
        anglesHasScript = try c.decodeIfPresent(Bool.self, forKey: .anglesHasScript)
        attachmentName = try c.decodeIfPresent(String.self, forKey: .attachmentName)
        parentAttachmentBindFrame = try c.decodeIfPresent([Float].self, forKey: .parentAttachmentBindFrame)
        childLayerIDs = try c.decodeIfPresent([Int].self, forKey: .childLayerIDs) ?? []
        timelines = try c.decodeIfPresent([SceneDocument.SceneObjectTimeline].self, forKey: .timelines) ?? []
        timelineDiagnostics = try c.decodeIfPresent([String].self, forKey: .timelineDiagnostics) ?? []
        usesPerspective = try c.decodeIfPresent(Bool.self, forKey: .usesPerspective)
        parallaxDepthXY = try c.decodeIfPresent([Float].self, forKey: .parallaxDepthXY)
        disablesParallaxPropagation = try c.decodeIfPresent(Bool.self, forKey: .disablesParallaxPropagation) ?? false
    }
}

// Carriers only: admission and all world/translation math below are product sources.
enum SceneShaderUserValueKind: String, Codable {
    case null, boolean, number, string, array, object
}

struct SceneDocument {
    struct SceneObjectTimeline: Codable {
        enum Host: String, Codable { case origin, angles, scale }
        let host: Host
    }
    struct ShaderValue: Codable {
        let rawValue: String
        let valueKind: String
        let components: [Double]?
        let userBinding: String?
        let timeline: SceneJSONPresence?
        let timelineDiagnostics: [String]
        var scriptSource: String? = nil
        var userValueKind: SceneShaderUserValueKind? = nil
        var bindingKeys: [String] = []
    }
}

struct SceneJSONPresence: Codable {
    init(from decoder: Decoder) throws {}
    func encode(to encoder: Encoder) throws {}
}

struct SceneUserTextureInput: Codable {
    init(from decoder: Decoder) throws {}
    func encode(to encoder: Encoder) throws {}
}

struct SceneLayerFragmentUniforms {
    var time: Float
    var alpha: Float
    var dependencyBlendMode: UInt32
    var usesDependencyBlend: UInt32
    var cursorUV: SIMD2<Float>
    var sourceSampling: SIMD2<Float>
    var tint: SIMD4<Float>
    var textureFrame0: SIMD4<Float>
    var textureFrame1: SIMD4<Float>
}

final class SceneVideoTextureSource {
    init?(
        layerID: Int,
        mp4PayloadData: Data,
        isWebM: Bool = false,
        cacheDirectory: URL,
        device: MTLDevice
    ) { return nil }
}

private struct RuntimeEvidence: Decodable {
    struct RuntimeInput: Decodable {
        let renderDescriptor: SceneRenderDescriptor
    }

    let runtimeInput: RuntimeInput
}

@main
enum Harness {
    static func main() throws {
        guard CommandLine.arguments.count >= 2 else { throw HarnessError.missingMode }
        switch CommandLine.arguments[1] {
        case "configuration-storage":
            guard let device = MTLCreateSystemDefaultDevice() else { throw HarnessError.noMetal }
            let runtime = SceneParticleRuntime(descriptor: .init(
                layers: [], renderOrderLayerIDs: [], materialPasses: []),
                cacheDirectory: FileManager.default.temporaryDirectory, device: device)
            let fields = Set(Mirror(reflecting: runtime).children.compactMap(\.label))
            let snapshotFields = Set(Mirror(reflecting: runtime.frameSnapshot()).children.compactMap(\.label))
            let compilationFields = Set(Mirror(reflecting: SceneParticleLayerImageEmitterCompilation.empty)
                .children.compactMap(\.label))
            let definition = SceneParticleDefinitionParser().parse(root: [:])
            try printJSON([
                "runtimeDiagnostics": fields.contains("diagnostics"),
                "runtimeAdoptionReport": fields.contains("liveWorldSpaceAdoptedLayerIDs"),
                "snapshotAdoptionReport": snapshotFields.contains("adoptedWorldSpaceLayerIDs"),
                "compilationDiagnostics": compilationFields.contains("diagnostics"),
                "definitionDiagnostics": Mirror(reflecting: definition).children.contains { $0.label == "diagnostics" },
            ])
        case "playback-control":
            try printJSON(playbackControl())
        case "delayed-children":
            try printJSON(delayedChildren())
        case "delayed-child-edges":
            try printJSON(delayedChildren(edges: true))
        case "real":
            guard CommandLine.arguments.count == 4 else { throw HarnessError.missingPath }
            try printJSON(realSample(
                evidencePath: CommandLine.arguments[2],
                cachePath: CommandLine.arguments[3]
            ))
        case "eventspawn-real":
            guard CommandLine.arguments.count == 4 else { throw HarnessError.missingPath }
            try printJSON(realEventSpawnSample(
                evidencePath: CommandLine.arguments[2],
                cachePath: CommandLine.arguments[3]
            ))
        case "eventdeath-real":
            guard CommandLine.arguments.count == 4 else { throw HarnessError.missingPath }
            try printJSON(realEventDeathSample(
                evidencePath: CommandLine.arguments[2],
                cachePath: CommandLine.arguments[3]
            ))
        case "eventfollow-synthetic":
            try printJSON(syntheticEventFollow())
        case "nested-synthetic":
            try printJSON(syntheticNestedChildren())
        case "worldspace-translation":
            try printJSON(translationAnchoring())
        case "worldspace-translation-edges":
            try printJSON(translationEdges())
        case "worldspace-freeze":
            try printJSON(syntheticWorldSpaceFreeze())
        case "worldspace-freeze-recovery":
            try printJSON(syntheticWorldSpaceFreezeRecovery())
        case "instance-buffer-budget":
            try printJSON(instanceBufferBudget())
        case "worldspace-gravity-frame":
            try printJSON(syntheticWorldSpaceGravityFrame())
        case "worldspace-pointer-emitter":
            try printJSON(syntheticWorldSpacePointerEmitter())
        case "audio-bounds-gate":
            try printJSON(syntheticAudioBoundsGate())
        case "worldspace-rope-trail":
            try printJSON(syntheticWorldSpaceRopeTrail())
        case "worldspace-pointer-force":
            try printJSON(syntheticWorldSpacePointerForce())
        case "worldspace-pointer-positionaround":
            try printJSON(syntheticWorldSpacePointerPositionAround())
        case "pointer-demand-real":
            guard CommandLine.arguments.count == 7 else {
                throw HarnessError.missingMode
            }
            try printJSON(realPointerDemand(
                evidencePath: CommandLine.arguments[2],
                cachePath: CommandLine.arguments[3],
                layerID: Int(CommandLine.arguments[4]) ?? 0,
                pointer: SIMD3(
                    Double(CommandLine.arguments[5]) ?? 0,
                    Double(CommandLine.arguments[6]) ?? 0,
                    0
                )
            ))
        case "nested-real":
            guard CommandLine.arguments.count == 4 else { throw HarnessError.missingPath }
            try printJSON(realNestedMatrix(
                evidencePath: CommandLine.arguments[2],
                cachePath: CommandLine.arguments[3]
            ))
        case "continuous-profile-real":
            guard CommandLine.arguments.count == 3 else { throw HarnessError.missingPath }
            try printJSON(realContinuousProfiles(cachePath: CommandLine.arguments[2]))
        case "static-origin-real":
            guard CommandLine.arguments.count == 4 else { throw HarnessError.missingPath }
            try printJSON(realStaticOriginSample(
                evidencePath: CommandLine.arguments[2],
                cachePath: CommandLine.arguments[3]
            ))
        case "refraction-real":
            guard CommandLine.arguments.count == 4 else { throw HarnessError.missingPath }
            try printJSON(realRefractionSample(
                evidencePath: CommandLine.arguments[2],
                cachePath: CommandLine.arguments[3]
            ))
        case "refraction-child-real":
            guard CommandLine.arguments.count == 4 else { throw HarnessError.missingPath }
            try printJSON(realRefractionChildSample(
                evidencePath: CommandLine.arguments[2],
                cachePath: CommandLine.arguments[3]
            ))
        case "water-impact-real":
            guard CommandLine.arguments.count == 4 else { throw HarnessError.missingPath }
            try printJSON(realWaterImpactSample(
                evidencePath: CommandLine.arguments[2],
                cachePath: CommandLine.arguments[3]
            ))
        case "stock-synthetic":
            guard CommandLine.arguments.count == 3 else { throw HarnessError.missingPath }
            try printJSON(stockSynthetic(bundlePath: CommandLine.arguments[2]))
        case "rope-trail-synthetic":
            try printJSON(syntheticRopeTrail())
        case "rope-synthetic":
            try printJSON(syntheticRope())
        case "static-scaled-rope-synthetic":
            try printJSON(syntheticStaticScaledRope())
        case "dynamic-control-point-synthetic":
            try printJSON(syntheticDynamicControlPoint())
        case "child-float-safety":
            try printJSON(syntheticChildFloatSafety())
        case "child-instance-override-synthetic":
            try printJSON(syntheticChildInstanceOverride())
        case "layer-alpha-synthetic":
            try printJSON(syntheticLayerAlpha())
        case "dynamic-instance-override-synthetic":
            try printJSON(syntheticDynamicInstanceOverride())
        case "velocity-defaults-synthetic":
            try printJSON(syntheticVelocityDefaults())
        case "child-pointer-control-point-synthetic":
            try printJSON(syntheticChildPointerControlPoint())
        case "dynamic-control-point-angle-synthetic":
            try printJSON(syntheticDynamicControlPointAngle())
        case "batch-evidence-synthetic":
            try printJSON(syntheticBatchEvidence())
        case "lifecycle-synthetic":
            try printJSON(syntheticLifecycle())
        case "playback-delta-synthetic":
            try printJSON(playbackDeltaBounds())
        case "frame-transaction-synthetic":
            try printJSON(frameTransactionBounds())
        case "subframe-lifetime-synthetic":
            try printJSON(syntheticSubframeLifetime())
        case "subframe-child-lifecycle-synthetic":
            try printJSON(syntheticSubframeChildLifecycle())
        case "sprite-geometry-synthetic":
            try printJSON(syntheticSpriteGeometry())
        case "trail-direction-synthetic":
            try printJSON(syntheticTrailDirection())
        case "child-capacity-synthetic":
            try printJSON(syntheticChildCapacity())
        case "synthetic":
            try printJSON(synthetic())
        default:
            throw HarnessError.missingMode
        }
    }

    static func renderDescriptor(evidencePath: String) throws -> SceneRenderDescriptor {
        let evidenceURL = URL(fileURLWithPath: evidencePath)
        return try JSONDecoder().decode(
            RuntimeEvidence.self,
            from: Data(contentsOf: evidenceURL)
        ).runtimeInput.renderDescriptor
    }

    static func layer(
        _ id: Int,
        _ path: String,
        visible: Bool = true,
        particleAlpha: Double? = nil,
        layerAlpha: Double = 1,
        particleSize: Double? = nil,
        particleLifetime: Double? = nil,
        particleRate: Double? = nil,
        particleCount: Double? = nil,
        particleNormalizedColor: SIMD3<Double>? = nil,
        alphaHasUser: Bool = false,
        alphaHasScript: Bool = false,
        controlPoint: SIMD3<Double>? = nil,
        controlPointHasAnimation: Bool = false
    ) -> SceneRenderDescriptor.Layer {
        .init(
            id: id, name: nil, contentKind: "particle", particlePath: path,
            particleInstanceOverride: (particleAlpha != nil || particleSize != nil
                || particleLifetime != nil || particleRate != nil
                || particleCount != nil || particleNormalizedColor != nil
                || controlPoint != nil) ?
                SceneParticleInstanceOverride(
                    id: nil,
                    alpha: particleAlpha.map { value in SceneParticleBoundValue(
                        value: .scalar(value),
                        userPropertyKey: alphaHasUser ? "foreground" : nil,
                        hasScript: alphaHasScript,
                        hasAnimation: false
                    ) },
                    size: particleSize.map { SceneParticleBoundValue(
                        value: .scalar($0), userPropertyKey: "size",
                        hasScript: false, hasAnimation: false
                    ) },
                    lifetime: particleLifetime.map { SceneParticleBoundValue(
                        value: .scalar($0), userPropertyKey: nil,
                        hasScript: false, hasAnimation: false
                    ) },
                    rate: particleRate.map { SceneParticleBoundValue(
                        value: .scalar($0), userPropertyKey: nil,
                        hasScript: false, hasAnimation: false
                    ) },
                    speed: nil,
                    count: particleCount.map { SceneParticleBoundValue(
                        value: .scalar($0), userPropertyKey: "count",
                        hasScript: false, hasAnimation: false
                    ) },
                    brightness: nil,
                    color: nil,
                    normalizedColor: particleNormalizedColor.map { SceneParticleBoundValue(
                        value: .vector([$0.x, $0.y, $0.z]), userPropertyKey: "color",
                        hasScript: false, hasAnimation: false
                    ) },
                    controlPoints: controlPoint.map { value in [
                        1: SceneParticleBoundValue(
                            value: .vector([value.x, value.y, value.z]),
                            userPropertyKey: nil,
                            hasScript: false,
                            hasAnimation: controlPointHasAnimation
                        )
                    ] } ?? [:],
                    controlPointAngles: [:]
                )
                : nil,
            parentID: nil, visible: visible, alpha: layerAlpha
        )
    }

    static func writeParticle(
        _ path: String,
        material: String,
        flags: Int = 0,
        renderer: String = "sprite",
        rendererFlags: Int = 0,
        rendererLength: Any? = nil,
        rendererMinimumLength: Double? = nil,
        rendererMaximumLength: Double? = nil,
        additionalRenderers: [Any] = [],
        velocityX: Double? = nil,
        lifetime: Double = 10,
        startTime: Double? = nil,
        moves: Bool = false,
        movementFlags: Int = 0,
        rate: Double = 60,
        emitterDuration: Double? = nil,
        audioProcessingMode: Int? = nil,
        operatorAudioProcessingMode: Int? = nil,
        instantaneous: Int? = nil,
        emitterControlPoint: Int? = nil,
        controlPointOffset: [Double]? = nil,
        children: [[String: Any]] = [],
        under root: URL
    ) throws {
        var initializers: [[String: Any]] = [
            ["name": "lifetimerandom", "min": lifetime, "max": lifetime],
            ["name": "sizerandom", "min": 8, "max": 8],
        ]
        if let velocityX {
            initializers.append([
                "name": "velocityrandom",
                "min": [velocityX, 0, 0],
                "max": [velocityX, 0, 0],
            ])
        }
        var rendererDefinition: [String: Any] = [
            "name": renderer,
            "flags": rendererFlags,
        ]
        if let rendererLength { rendererDefinition["length"] = rendererLength }
        if let rendererMinimumLength { rendererDefinition["minlength"] = rendererMinimumLength }
        if let rendererMaximumLength { rendererDefinition["maxlength"] = rendererMaximumLength }
        var emitter: [String: Any] = [
            "name": "sphererandom", "rate": rate, "distancemin": 0, "distancemax": 0,
        ]
        if let emitterDuration { emitter["duration"] = emitterDuration }
        if let audioProcessingMode { emitter["audioprocessingmode"] = audioProcessingMode }
        if let instantaneous { emitter["instantaneous"] = instantaneous }
        if let emitterControlPoint { emitter["controlpoint"] = emitterControlPoint }
        var operators: [[String: Any]] = []
        if moves {
            operators.append([
                "name": "movement",
                "flags": movementFlags,
            ])
        }
        if let operatorAudioProcessingMode {
            operators.append([
                "name": "turbulence",
                "audioprocessingmode": operatorAudioProcessingMode,
            ])
        }
        var definition: [String: Any] = [
            "material": material,
            "maxcount": 100,
            "flags": flags,
            "emitter": [emitter],
            "initializer": initializers,
            "operator": operators,
            "renderer": ([rendererDefinition] as [Any]) + additionalRenderers,
            "children": children,
        ]
        if let startTime { definition["starttime"] = startTime }
        if let emitterControlPoint, let controlPointOffset {
            definition["controlpoint"] = [[
                "id": emitterControlPoint,
                "offset": controlPointOffset,
            ]]
        }
        try writeJSON(definition, to: root.appendingPathComponent(path))
    }

    static func writeJSON(_ value: [String: Any], to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]).write(to: url)
    }

    static func writePNG(_ url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil, width: 2, height: 2, bitsPerComponent: 8, bytesPerRow: 8,
            space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ), let image = context.makeImage(),
           let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)
        else { throw HarnessError.imageWrite }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw HarnessError.imageWrite }
    }

    static func writeAnimatedTEX(_ url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        var data = Data("TEXV0005\0TEXI0001\0".utf8)
        appendUInt32(0, to: &data)
        appendUInt32(4, to: &data)
        appendUInt32(2, to: &data)
        appendUInt32(2, to: &data)
        appendUInt32(2, to: &data)
        appendUInt32(2, to: &data)
        appendUInt32(0, to: &data)
        data.append(Data("TEXB0002\0".utf8))
        appendUInt32(1, to: &data)
        appendUInt32(1, to: &data)
        appendUInt32(2, to: &data)
        appendUInt32(2, to: &data)
        appendUInt32(0, to: &data)
        appendUInt32(0, to: &data)
        appendUInt32(16, to: &data)
        data.append(Data(repeating: 255, count: 16))
        data.append(Data("TEXS0002\0".utf8))
        appendUInt32(2, to: &data)
        for _ in 0..<2 {
            appendUInt32(0, to: &data)
            appendFloat32(0.1, to: &data)
            for value: Float in [0, 0, 2, 0, 0, 2] {
                appendFloat32(value, to: &data)
            }
        }
        try data.write(to: url)
    }

    static func appendUInt32(_ value: UInt32, to data: inout Data) {
        var littleEndian = value.littleEndian
        withUnsafeBytes(of: &littleEndian) { data.append(contentsOf: $0) }
    }

    static func appendFloat32(_ value: Float, to data: inout Data) {
        var bits = value.bitPattern.littleEndian
        withUnsafeBytes(of: &bits) { data.append(contentsOf: $0) }
    }

    static func scalar(_ value: SceneParticleBoundValue?) -> Double {
        value?.value?.scalarValue ?? -1
    }

    static func sampling(
        _ value: SceneParticleTextureSampling
    ) -> [String: Any] {
        [
            "filter": value.filter.rawValue,
            "address": value.addressMode.rawValue,
            "clampBorderFallback": value.usesClampBorderFallback,
        ]
    }

    static func vector(_ value: SIMD4<Float>) -> [Float] {
        [value.x, value.y, value.z, value.w]
    }

    static func printJSON(_ value: [String: Any]) throws {
        let data = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }

    enum HarnessError: Error {
        case missingMode
        case missingPath
        case noMetal
        case noParticlePipeline
        case imageWrite
    }
}

// Only the two complete production methods are inserted by the Python compiler
// fixture. The image/geometry encoder responsibilities are outside this gate.
struct SceneMetalRenderer {
    let parallaxByLayerID: [Int: SceneLayerParallax.Resolution]
}
// PRODUCTION_PARTICLE_MODEL_METHODS

// Fixture-only adapters preserve existing simulation inputs while preparing
// through the real throwing product kernel. Product runtime initializers
// require the already prepared per-launch graph and perform no definition IO.
extension SceneParticleRuntime {
    convenience init(
        descriptor: SceneRenderDescriptor,
        cacheDirectory: URL,
        device: MTLDevice,
        resourceView: SceneResourceView? = nil,
        stockTextureBundleURL: URL? = SceneStockTextureResolver.defaultBundleRoot(),
        textureLoader: SceneTextureLoader = SceneTextureLoader(),
        layerImage: SceneParticleLayerImageEmitterCompilation = .empty,
        staticWorldSpaceFrames: [Int: SceneParticleWorldSpaceFrame]? = nil,
        staticWorldSpaceChains: [Int: Set<Int>]? = nil,
        preparedParticleVisibilityLayerIDs: Set<Int> = [],
        initialDynamicValues: SceneDynamicSnapshot = .empty(frameIndex: 0),
        initialPlayback: [Int: SceneParticlePlaybackSnapshot] = [:]
    ) {
        let view = resourceView ?? SceneResourceView(
            projectRootURL: cacheDirectory, packageRootURL: nil)
        let assets = try! Self.prepareAssets(descriptor: descriptor,
            resourceView: view,
            preparedParticleVisibilityLayerIDs: preparedParticleVisibilityLayerIDs,
            stockTextureBundleURL: stockTextureBundleURL)
        self.init(descriptor: descriptor, preparedAssets: assets, device: device,
            textureLoader: textureLoader, layerImage: layerImage,
            staticWorldSpaceFrames: staticWorldSpaceFrames,
            staticWorldSpaceChains: staticWorldSpaceChains,
            preparedParticleVisibilityLayerIDs: preparedParticleVisibilityLayerIDs,
            initialDynamicValues: initialDynamicValues, initialPlayback: initialPlayback)
    }
}

extension SceneParticlePlaybackState {
    convenience init?(
        descriptor: SceneRenderDescriptor,
        cacheDirectory: URL,
        device: MTLDevice,
        resourceView: SceneResourceView? = nil,
        textureLoader: SceneTextureLoader = SceneTextureLoader(),
        layerImage: SceneParticleLayerImageEmitterCompilation = .empty,
        preparedParticleVisibilityLayerIDs: Set<Int> = [],
        initialDynamicValues: SceneDynamicSnapshot = .empty(frameIndex: 0),
        initialPlayback: [Int: SceneParticlePlaybackSnapshot] = [:]
    ) {
        let view = resourceView ?? SceneResourceView(
            projectRootURL: cacheDirectory, packageRootURL: nil)
        let assets = try! SceneParticleRuntime.prepareAssets(descriptor: descriptor,
            resourceView: view,
            preparedParticleVisibilityLayerIDs: preparedParticleVisibilityLayerIDs)
        self.init(descriptor: descriptor, preparedAssets: assets, device: device,
            textureLoader: textureLoader, layerImage: layerImage,
            preparedParticleVisibilityLayerIDs: preparedParticleVisibilityLayerIDs,
            initialDynamicValues: initialDynamicValues, initialPlayback: initialPlayback)
    }
}
