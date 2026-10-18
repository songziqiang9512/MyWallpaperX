import Foundation
import simd
import CryptoKit

// Inputs and expectations only. The real Loader, Descriptor and Parallax
// owners decide normalization, inheritance and pointer displacement.
func sceneParallaxDepthDefaultChecks(project: SceneProject) throws -> [String: Bool] {
    let general: [String: Any] = [
        "orthogonalprojection": ["width": 1000, "height": 500],
        "cameraparallax": true, "cameraparallaxamount": 0.1,
        "cameraparallaxmouseinfluence": 0.5,
    ]
    let catalog = SceneAssetCatalog(models: [], materials: [], effectDefinitions: [],
        effectDefinitionDiagnostics: [], shaderReferences: [], textureReferences: [])
    var results: [String: Bool] = [:]
    func object(_ id: Int, depth: Any? = nil, resource: String = "models/owned/ridge.json") -> [String: Any] {
        var value: [String: Any] = ["id": id, "image": resource,
            "name": "owned-\(id)", "origin": "500 250 0", "size": "80 60"]
        if let depth { value["parallaxDepth"] = depth }
        return value
    }
    func load(_ name: String, _ objects: [[String: Any]],
              general settings: [String: Any]? = nil) throws -> (SceneDocument, SceneRenderDescriptor) {
        let root: [String: Any] = ["general": settings ?? general, "objects": objects]
        let url = project.rootURL.appendingPathComponent("owned-parallax-\(name).json")
        let bytes = try JSONSerialization.data(withJSONObject: root, options: [.sortedKeys])
        try bytes.write(to: url)
        let document = try SceneDocumentLoader().load(from: url)
        guard let descriptor = SceneRenderDescriptorBuilder().build(project: project,
            sceneDocument: document, assetCatalog: catalog,
            resourceReferences: .init(missingReferences: [], builtInReferenceCount: 0,
                                      runtimeProvidedReferenceCount: 0),
            capabilityProfile: .init(firstStageRendererGaps: [])) else {
            throw NSError(domain: "OwnedParallaxFixture", code: 1)
        }
        results["\(name):authored-root-preserved"] = document.authoredRoot == SceneJSONValue(jsonObject: root)
        results["\(name):source-bytes-preserved"] = document.sourceWitness
            == SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        results["\(name):initial-configurations-preserved"] = zip(objects, descriptor.layers).allSatisfy {
            SceneJSONValue(jsonObject: $0.0) == $0.1.initialConfiguration
        }
        return (document, descriptor)
    }
    func layer(_ descriptor: SceneRenderDescriptor, _ id: Int) -> SceneRenderDescriptor.Layer {
        descriptor.layers.first { $0.id == id }!
    }
    func offset(_ descriptor: SceneRenderDescriptor, _ id: Int,
                _ pointer: SIMD2<Float>) -> SIMD2<Float> {
        let layers = Dictionary(uniqueKeysWithValues: descriptor.layers.map { ($0.id, $0) })
        let resolutions = SceneLayerParallax.resolveAll(layersByID: layers)
        let worldFrames = SceneLayerWorldFrameResolver.compute(descriptor: descriptor, byID: layers)
        let resolution = resolutions[id]
        let frame = resolution.flatMap { worldFrames[$0.sourceLayerID] }
        let camera = descriptor.camera
        return SceneLayerParallax.offset(resolution: resolution,
            configuration: .init(enabled: camera.parallaxEnabled, amount: camera.parallaxAmount,
                mouseInfluence: camera.parallaxMouseInfluence,
                orthoSize: SIMD2(camera.orthoWidth ?? 1000, camera.orthoHeight ?? 500),
                cameraPosition: SIMD2(500, 250), worldYDown: true),
            layerPosition: frame.map { SIMD2($0.columns.3.x, $0.columns.3.y) } ?? .zero,
            mouseNormalized: pointer)
    }
    func close(_ actual: SIMD2<Float>, _ wanted: SIMD2<Float>) -> Bool {
        abs(actual.x - wanted.x) < 0.00001 && abs(actual.y - wanted.y) < 0.00001
    }
    let original = [object(11), object(12, depth: "1 1"), object(13, depth: "0 0")]
    let (document, descriptor) = try load("omission", original)
    results["omission:typed-unit-depth"] = document.objects[0].parallaxDepth == "1 1"
        && layer(descriptor, 11).parallaxDepthXY == [1, 1]
    results["omission:matches-explicit-unit"] = layer(descriptor, 11).parallaxDepthXY
        == layer(descriptor, 12).parallaxDepthXY
    results["omission:center-neutral"] = offset(descriptor, 11, .zero) == .zero
    results["omission:diagonal-offset"] = close(offset(descriptor, 11, SIMD2(0.8, -0.6)), SIMD2(-20, -7.5))
    results["omission:explicit-unit-same-offset"] = offset(descriptor, 11, SIMD2(-0.8, 0.6))
        == offset(descriptor, 12, SIMD2(-0.8, 0.6))
    results["omission:explicit-zero-still-disabled"] = layer(descriptor, 13).parallaxDepthXY == [0, 0]
        && offset(descriptor, 13, SIMD2(0.8, -0.6)) == .zero

    // A different resource, IDs, names and object order cannot select the policy.
    let renamed = [object(903, depth: "0 0", resource: "models/other/static.json"),
        object(902, depth: "1 1", resource: "models/other/moving.json"),
        object(901, resource: "models/renamed/landscape.json")]
    let (_, variant) = try load("renamed-reordered", renamed)
    results["variant:same-unit-depth-and-offset"] = layer(variant, 901).parallaxDepthXY == [1, 1]
        && offset(variant, 901, SIMD2(0.8, -0.6)) == offset(descriptor, 11, SIMD2(0.8, -0.6))

    let declared: [(String, Any, String?, [Float]?)] = [
        ("zero", "0 0", "0 0", [0, 0]),
        ("per-axis", "0 -0.5", "0 -0.5", [0, -0.5]),
        ("short", "0.25", "0.25", [0.25, 0]),
        ("extra", "0.25 -0.5 7", "0.25 -0.5 7", [0.25, -0.5]),
        ("null", NSNull(), nil, nil), ("bool", true, nil, nil),
        ("number", 1, nil, nil), ("array", [1, 1], nil, nil),
        ("empty", "", "", nil), ("bad-token", "1 nope", "1 nope", nil),
        ("wrapper", ["value": "0.25 -0.5"], "0.25 -0.5", [0.25, -0.5]),
        ("bad-wrapper", ["value": 1], nil, nil),
        ("missing-wrapper-value", ["future": "1 1"], nil, nil),
    ]
    for (name, raw, expectedString, expectedDepth) in declared {
        let (parsed, result) = try load("declared-\(name)", [object(21, depth: raw)])
        results["declared-\(name):old-projection"] = parsed.objects[0].parallaxDepth == expectedString
            && layer(result, 21).parallaxDepthXY == expectedDepth
        if expectedDepth == nil || expectedDepth == [0, 0] {
            results["declared-\(name):not-replaced-by-unit"] = offset(result, 21, SIMD2(0.8, -0.6)) == .zero
        }
        if name == "per-axis" {
            results["declared-per-axis:axis-zero-preserved"] = close(offset(result, 21, SIMD2(0.8, -0.6)), SIMD2(0, 3.75))
        }
    }
    for raw in ["NaN 1", "Inf 1", "1e400 1"] {
        let (parsed, result) = try load("nonfinite-\(raw)", [object(22, depth: raw)])
        results["nonfinite-\(raw):preserved-local-zero"] = parsed.objects[0].parallaxDepth == raw
            && layer(result, 22).parallaxDepthXY?.first?.isFinite == false
            && offset(result, 22, SIMD2(0.8, -0.6)) == .zero
    }

    var parent = object(31); var child = object(32, depth: "0.25 -0.5")
    child["parent"] = 31; child["origin"] = "20 30 0"
    let (_, inherited) = try load("inherited", [child, parent])
    let inheritedLayers = Dictionary(uniqueKeysWithValues: inherited.layers.map { ($0.id, $0) })
    let inheritedSources = SceneLayerParallax.resolveAll(layersByID: inheritedLayers)
    results["parent:omitted-unit-propagates"] = inheritedSources[32]?.sourceLayerID == 31
        && inheritedSources[32]?.depth == SIMD2(1, 1)
        && offset(inherited, 32, SIMD2(0.8, -0.6)) == offset(inherited, 31, SIMD2(0.8, -0.6))
    parent["disablepropagation"] = true
    let (_, blocked) = try load("blocked", [parent, child])
    let blockedLayers = Dictionary(uniqueKeysWithValues: blocked.layers.map { ($0.id, $0) })
    let blockedSource = SceneLayerParallax.resolveAll(layersByID: blockedLayers)[32]
    results["parent:blocker-keeps-explicit-child"] = blockedSource?.sourceLayerID == 32
        && blockedSource?.depth == SIMD2(0.25, -0.5)
    parent["disablepropagation"] = false; parent["parallaxDepth"] = "0 0"
    let (_, zeroParent) = try load("zero-parent", [parent, child])
    results["parent:explicit-zero-propagates"] = offset(zeroParent, 32, SIMD2(0.8, -0.6)) == .zero

    for (name, key, value) in [("camera-off", "cameraparallax", false as Any),
                              ("amount-zero", "cameraparallaxamount", 0 as Any)] {
        var settings = general; settings[key] = value
        let (_, result) = try load(name, [object(41)], general: settings)
        results["\(name):unit-preserved-but-no-offset"] = layer(result, 41).parallaxDepthXY == [1, 1]
            && offset(result, 41, SIMD2(0.8, -0.6)) == .zero
    }
    let non2D: [(String, [String: Any])] = [
        ("missing-mode", [:]), ("perspective", ["fov": 60]),
        ("empty-ortho", ["orthogonalprojection": [:]]),
        ("zero-size", ["orthogonalprojection": ["width": 0, "height": 500]]),
        ("one-axis", ["orthogonalprojection": ["width": 1000]]),
        ("disabled-auto", ["orthogonalprojection": ["auto": false]]),
    ]
    for (name, settings) in non2D {
        let (parsed, result) = try load(name, [object(51)], general: settings)
        results["\(name):no-2d-default"] = parsed.general.authoredOrthographicProjectionActive == false
            && parsed.objects[0].parallaxDepth == nil && layer(result, 51).parallaxDepthXY == nil
            && offset(result, 51, SIMD2(0.8, -0.6)) == .zero
    }
    let (_, autoOrtho) = try load("authored-auto", [object(52)],
        general: ["orthogonalprojection": ["auto": true]])
    results["authored-auto:existing-general-owner-qualifies"] = layer(autoOrtho, 52).parallaxDepthXY == [1, 1]
    let (_, nativeModel) = try load("native-model", [["id": 53, "model": "models/owned/mesh.mdl"]],
        general: ["fov": 60])
    results["native-model:no-depth-default"] = layer(nativeModel, 53).contentKind == "model"
        && layer(nativeModel, 53).parallaxDepthXY == nil
    return results
}
