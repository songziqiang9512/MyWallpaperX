import CoreGraphics
import Foundation
import simd

// Only the GPU container and immutable context carrier are leaves. Camera,
// visibility, typed snapshot and both world resolvers are product code.
struct SceneFrameContext {
    let sceneTime: Double
    let screenSize: CGSize
    let dynamicValues: SceneDynamicSnapshot
}

struct SceneMetalRenderer {
    let renderDescriptor: SceneRenderDescriptor
    let layersByID: [Int: SceneRenderDescriptor.Layer]
    let worldFramesByLayerID: [Int: simd_float4x4]

    init(_ descriptor: SceneRenderDescriptor) {
        renderDescriptor = descriptor
        layersByID = Dictionary(uniqueKeysWithValues: descriptor.layers.map { ($0.id, $0) })
        worldFramesByLayerID = SceneLayerWorldFrameResolver.compute(
            descriptor: descriptor, byID: layersByID)
    }
}

@main enum SceneNativeCameraFrameTransformChecks {
    static let viewport = CGSize(width: 900, height: 600)
    static var serial = 0

    static func descriptor(cameraID: Int = 7, parentID: Int? = nil,
                           tag: String = "default", includeCamera: Bool = true,
                           orthographic: Bool = false, renamed: Bool = false) throws -> SceneRenderDescriptor {
        var objects: [[String: Any]] = []
        if let parentID {
            objects.append(["id": parentID, "origin": "0 0 0", "angles": "0 0 0"])
        }
        if includeCamera {
            var layer: [String: Any] = ["id": cameraID, "camera": tag, "fov": 60,
                "origin": "0 0 6", "angles": "0 0 0", "visible": true,
                "path": renamed ? "curves/another.json" : "paths/own.json"]
            if let parentID { layer["parent"] = parentID }
            objects.append(layer)
        }
        objects.append(["id": 90, "model": "models/unrelated.mdl", "origin": "0 0 0"])
        let root: [String: Any] = ["version": 3,
            "camera": ["eye": "0.7 3 6", "center": "0 0 0", "up": "0 1 0"],
            "general": ["orthogonalprojection": orthographic
                ? ["width": 900, "height": 600] as Any : NSNull(),
                "fov": 47, "nearz": 0.1, "farz": 100, "camerashake": false,
                "cameraparallax": false], "objects": objects]
        serial += 1
        let directory = URL(fileURLWithPath: CommandLine.arguments[1])
        let url = directory.appendingPathComponent("own-native-camera-\(serial).json")
        try JSONSerialization.data(withJSONObject: root).write(to: url)
        let properties = SceneUserPropertyDefinitionParser().parse(properties: [:])
        let document = try SceneDocumentLoader().load(from: url, propertyCatalog: properties)
        guard let result = SceneRenderDescriptorBuilder().build(
            project: SceneProject(rootURL: directory, entryPath: url.lastPathComponent,
                userProperties: properties), sceneDocument: document,
            assetCatalog: SceneAssetCatalog(models: [], materials: [], effectDefinitions: [],
                effectDefinitionDiagnostics: [], shaderReferences: [], textureReferences: []),
            resourceReferences: .init(missingReferences: [], builtInReferenceCount: 0,
                runtimeProvidedReferenceCount: 0), capabilityProfile: .init(firstStageRendererGaps: [])) else {
            throw NSError(domain: "own-native-camera-descriptor", code: 1)
        }
        return result
    }

    typealias Published = (SceneDynamicTarget, SceneDynamicValue, SceneDynamicValue)

    static func snapshot(_ values: [Published]) -> SceneDynamicSnapshot {
        SceneDynamicSnapshotResolver().resolve(frameIndex: 2, generation: 17,
            definitions: values.map { .init(target: $0.0,
                valueType: $0.1.valueType, authoredValue: $0.2) },
            sceneScriptValues: Dictionary(uniqueKeysWithValues: values.map { ($0.0, $0.1) })).snapshot
    }

    static func worlds(_ renderer: SceneMetalRenderer, _ values: SceneDynamicSnapshot)
        -> [Int: simd_float4x4] {
        SceneLayerDynamicWorldFrameResolver.resolve(descriptor: renderer.renderDescriptor,
            byID: renderer.layersByID, snapshot: values,
            staticFrames: renderer.worldFramesByLayerID)
    }

    static func frame(_ renderer: SceneMetalRenderer, _ values: SceneDynamicSnapshot,
                      _ current: [Int: simd_float4x4]) -> SceneParticleCameraFrame {
        renderer.makeCameraFrame(frameContext: .init(sceneTime: 1,
            screenSize: viewport, dynamicValues: values), worldFrames: current)
    }

    static func near(_ actual: SIMD3<Float>, _ expected: [Double]) -> Bool {
        zip([actual.x, actual.y, actual.z], expected).allSatisfy { pair in
            abs(Double(pair.0)-pair.1) < 0.00002
        }
    }

    static func xy(_ frame: SceneParticleCameraFrame) -> [Double] {
        let clip = frame.perspectiveViewProjection * SIMD4<Float>(0, 0, 0, 1)
        return [Double(clip.x / clip.w), Double(clip.y / clip.w)]
    }

    static func array(_ value: SIMD3<Float>) -> [Double] {
        [Double(value.x), Double(value.y), Double(value.z)]
    }

    static func inputFacts(_ values: [Published], _ snapshot: SceneDynamicSnapshot) -> Bool {
        values.allSatisfy { snapshot[$0.0]?.source == .sceneScript && snapshot[$0.0]?.value == $0.1 }
    }

    static func positive(_ name: String, renamed: Bool) throws -> [String: Any] {
        let id = renamed ? 937 : 7, parent = renamed ? 412 : 2
        let renderer = SceneMetalRenderer(try descriptor(cameraID: id,
            parentID: name == "parent" ? parent : nil, renamed: renamed))
        let a = renamed ? 1.0 / 5 : 0.2, b = renamed ? 3.0 / 10 : 0.3
        let values: [Published]
        let eye, forward, right, up, point: [Double]
        switch name {
        case "origin":
            values = [(.layer(layerID: id, field: .origin), .vector3(1, 2, 7), .vector3(0, 0, 6))]
            eye = [1, 2, 7]; forward = [0, 0, -1]; right = [1, 0, 0]; up = [0, 1, 0]
            point = [-0.16495721976846453, -0.4948716593053936]
        case "angles":
            values = [(.layer(layerID: id, field: .angles), .vector3(a, b, 0), .vector3(0, 0, 0))]
            eye = [0, 0, 6]; forward = [-0.28962947762551555, 0.19866933079506122, -0.9362933635841992]
            right = [0.955336489125606, 0, -0.29552020666133955]
            up = [0.05871080169382652, 0.9800665778412416, 0.18979606097868743]
            point = [0.36445558091698427, -0.35110408070511206]
        default:
            values = [(.layer(layerID: parent, field: .origin), .vector3(0.7, -0.3, 0.5), .vector3(0, 0, 0)),
                (.layer(layerID: parent, field: .angles), .vector3(0, renamed ? 1.0 / 4 : 0.25, 0), .vector3(0, 0, 0))]
            eye = [2.1844237555271375, -0.3, 6.313474530263869]
            forward = [-0.24740395925452294, 0, -0.9689124217106447]
            right = [0.9689124217106447, 0, -0.24740395925452294]; up = [0, 1, 0]
            point = [-0.09617881740345254, 0.07804797521305959]
        }
        let snapshot = snapshot(values), current = worlds(renderer, snapshot)
        let camera = frame(renderer, snapshot, current), actualXY = xy(camera)
        // Frozen independent double point-rotation/ray oracles; no expected
        // value is obtained from SceneMatrix, CameraFrame or a baseline frame.
        let facts = ["published": inputFacts(values, snapshot),
            "typedTransformLane": values.allSatisfy { value in
                if case let .layer(layerID, _) = value.0 {
                    return snapshot.dynamicTransformLayerIDsForFrame.contains(layerID)
                }; return false
            },
            "currentWorldDiffersFromSeed": current[id] != renderer.worldFramesByLayerID[id],
            "ordinaryModelWorldUnchanged": current[90] == renderer.worldFramesByLayerID[90],
            "nativeSelected": camera.defaultsToPerspective,
            "eye": near(camera.perspectiveEyePosition, eye),
            "forward": near(camera.cameraForward, forward), "right": near(camera.cameraRight, right),
            "up": near(camera.cameraUp, up),
            "pointNDC": zip(actualXY, point).allSatisfy { abs($0.0-$0.1) < 0.00003 }]
        return ["name": name, "renamed": renamed, "facts": facts,
            "actualEye": array(camera.perspectiveEyePosition), "expectedEye": eye,
            "actualForward": array(camera.cameraForward), "expectedForward": forward,
            "actualNDCXY": actualXY, "expectedNDCXY": point]
    }

    static func controls() throws -> [String: Bool] {
        let origin: Published = (.layer(layerID: 7, field: .origin), .vector3(1, 2, 7), .vector3(0, 0, 6))
        let visibility: Published = (.layer(layerID: 7, field: .visibility), .bool(false), .bool(true))
        let empty = snapshot([])
        let general = SceneMetalRenderer(try descriptor(includeCamera: false))
        let fallback = frame(general, empty, worlds(general, empty))
        let renderer = SceneMetalRenderer(try descriptor())
        let seed = frame(renderer, empty, renderer.worldFramesByLayerID)
        let hiddenValues = snapshot([origin, visibility])
        let hidden = frame(renderer, hiddenValues, worlds(renderer, hiddenValues))
        let other = SceneMetalRenderer(try descriptor(tag: "side"))
        let changed = snapshot([origin])
        let nondefault = frame(other, changed, worlds(other, changed))
        let missing = frame(renderer, changed, [:])
        let ortho = SceneMetalRenderer(try descriptor(orthographic: true))
        let flatSeed = frame(ortho, empty, ortho.worldFramesByLayerID)
        let flatCurrent = frame(ortho, changed, worlds(ortho, changed))
        let unrelatedValues = snapshot([(.layer(layerID: 90, field: .origin),
            .vector3(0.3, 0.2, 0), .vector3(0, 0, 0))])
        let unrelatedWorld = worlds(renderer, unrelatedValues)
        let unrelated = frame(renderer, unrelatedValues, unrelatedWorld)
        let fallbackMatches: (SceneParticleCameraFrame) -> Bool = {
            near($0.perspectiveEyePosition, [0.7, 3, 6])
                && $0.perspectiveViewProjection == fallback.perspectiveViewProjection
        }
        return [
            "staticNative": near(seed.perspectiveEyePosition, [0, 0, 6])
                && near(seed.cameraForward, [0, 0, -1]) && xy(seed).allSatisfy { abs($0) < 0.00003 },
            "staticGeneralMissingCamera": near(fallback.perspectiveEyePosition, [0.7, 3, 6])
                && xy(fallback).allSatisfy { abs($0) < 0.00003 },
            "hiddenDefault": inputFacts([origin, visibility], hiddenValues) && fallbackMatches(hidden),
            "nondefault": other.layersByID[7]?.cameraPath?.camera == "side" && fallbackMatches(nondefault),
            "missingWorld": fallbackMatches(missing),
            "orthographic2D": !flatCurrent.defaultsToPerspective
                && flatCurrent.orthographicViewProjection == flatSeed.orthographicViewProjection,
            "unrelatedModel": inputFacts([(.layer(layerID: 90, field: .origin),
                    .vector3(0.3, 0.2, 0), .vector3(0, 0, 0))], unrelatedValues)
                && unrelatedWorld[90] != renderer.worldFramesByLayerID[90]
                && unrelated.perspectiveViewProjection == seed.perspectiveViewProjection,
        ]
    }

    static func main() throws {
        var rows: [[String: Any]] = []
        for renamed in [false, true] {
            for name in ["origin", "angles", "parent"] {
                rows.append(try positive(name, renamed: renamed))
            }
        }
        print(String(decoding: try JSONSerialization.data(withJSONObject:
            ["rows": rows, "controls": try controls()], options: [.sortedKeys]), as: UTF8.self))
    }
}
