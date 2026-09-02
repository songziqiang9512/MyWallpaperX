import Foundation
import CryptoKit
import Metal

/// Immutable launch-prepared resources for direct `objects[].model` layers.
/// Geometry production joins the existing renderer/main pass; this type owns
/// no command queue, frame target, compositor, or mutable playback state.
struct ScenePreparedStaticModelResources {
    struct Entry {
        let modelPath: String
        let materialPath: String
        let geometryIdentity: String
        let mesh: SceneStaticModelMesh
        let albedo: SceneTextureCandidate
        let emissiveMask: SceneTextureCandidate?
        let material: SceneStaticModelMaterial
        let writesDepth: Bool
    }

    let pipeline: SceneStaticModelPipeline?
    private let entriesByLayerID: [Int: Entry]

    static let empty = ScenePreparedStaticModelResources(
        pipeline: nil,
        entriesByLayerID: [:]
    )

    var isEmpty: Bool { entriesByLayerID.isEmpty }
    var preparedLayerIDs: [Int] { entriesByLayerID.keys.sorted() }

    subscript(layerID: Int) -> Entry? {
        entriesByLayerID[layerID]
    }

    static func prepare(
        descriptor: SceneRenderDescriptor,
        resourceView: SceneResourceView,
        device: MTLDevice,
        textureLoader: SceneTextureLoader,
        cancellationCheck: () throws -> Void
    ) throws -> ScenePreparedStaticModelResources {
        let layers = descriptor.layers.filter { $0.staticModelPath != nil }
        guard !layers.isEmpty,
              let pipeline = SceneStaticModelPipeline(device: device) else {
            return .empty
        }

        struct PreparedGeometry {
            let materialPath: String
            let geometryIdentity: String
            let mesh: SceneStaticModelMesh
        }

        let textureResolver = SceneTexturePathResolver(
            resourceView: resourceView,
            descriptor: descriptor
        )
        var geometryByPath: [String: PreparedGeometry] = [:]
        var rejectedModelPaths: Set<String> = []
        var entries: [Int: Entry] = [:]

        for layer in layers {
            try cancellationCheck()
            guard let modelPath = layer.staticModelPath else { continue }
            let modelIdentity = identity(modelPath)
            if rejectedModelPaths.contains(modelIdentity) { continue }

            let preparedGeometry: PreparedGeometry
            if let cached = geometryByPath[modelIdentity] {
                preparedGeometry = cached
            } else {
                guard let modelURL = resourceView.resource(
                    relativePath: modelPath
                )?.url,
                      let data = try? Data(
                          contentsOf: modelURL,
                          options: .mappedIfSafe
                      ),
                      let decoded = try? SceneMdlStaticModelReader.read(
                          data: data
                      ),
                      let mesh = pipeline.makeMesh(
                          vertices: decoded.vertices,
                          indices: decoded.indices
                      ) else {
                    rejectedModelPaths.insert(modelIdentity)
                    continue
                }
                preparedGeometry = PreparedGeometry(
                    materialPath: decoded.materialPath,
                    geometryIdentity: geometryIdentity(decoded),
                    mesh: mesh
                )
                geometryByPath[modelIdentity] = preparedGeometry
            }
            try cancellationCheck()

            guard let materialIdentity = SceneVFSAssetPath(
                preparedGeometry.materialPath
            ),
                  let pass = descriptor.materialPasses.first(where: {
                SceneVFSAssetPath($0.materialPath) == materialIdentity
                    && $0.passIndex == 0
            }),
                  let texturePath = pass.textureSlots.first.flatMap({ $0 }),
                  let textureURL = textureResolver.resolveTextureFile(
                      named: texturePath
                  ),
                  case let .loaded(albedo) = textureLoader.loadCandidate(
                      from: textureURL,
                      purpose: .straightAlbedo,
                      device: device
                  ) else {
                continue
            }
            let modelMaterial = material(pass)
            let emissiveMask = modelMaterial.emissiveBrightness > 0
                ? optionalTexture(
                    at: 2,
                    in: pass,
                    purpose: .mask,
                    resolver: textureResolver,
                    textureLoader: textureLoader,
                    device: device
                )
                : nil
            entries[layer.id] = Entry(
                modelPath: modelPath,
                materialPath: preparedGeometry.materialPath,
                geometryIdentity: preparedGeometry.geometryIdentity,
                mesh: preparedGeometry.mesh,
                albedo: albedo,
                emissiveMask: emissiveMask,
                material: modelMaterial,
                writesDepth: writesDepth(pass.depthWrite)
            )
            try cancellationCheck()
        }

        return ScenePreparedStaticModelResources(
            pipeline: entries.isEmpty ? nil : pipeline,
            entriesByLayerID: entries
        )
    }

    private static func identity(_ path: String) -> String {
        path.replacingOccurrences(of: "\\", with: "/")
            .localizedLowercase
    }

    private static func geometryIdentity(
        _ model: SceneMdlStaticModel
    ) -> String {
        var data = Data()
        data.reserveCapacity(
            model.vertices.count * 48
                + model.indices.count * MemoryLayout<UInt16>.size
        )
        for vertex in model.vertices {
            for value in [
                vertex.position.x, vertex.position.y, vertex.position.z,
                vertex.normal.x, vertex.normal.y, vertex.normal.z,
                vertex.tangent.x, vertex.tangent.y,
                vertex.tangent.z, vertex.tangent.w,
                vertex.uv.x, vertex.uv.y,
            ] {
                var bits = value.bitPattern.littleEndian
                withUnsafeBytes(of: &bits) { data.append(contentsOf: $0) }
            }
        }
        for index in model.indices {
            var value = index.littleEndian
            withUnsafeBytes(of: &value) { data.append(contentsOf: $0) }
        }
        return SHA256.hash(data: data).map {
            String(format: "%02x", $0)
        }.joined()
    }

    private static func writesDepth(_ value: String?) -> Bool {
        guard let normalized = value?.trimmingCharacters(
            in: .whitespacesAndNewlines
        ).localizedLowercase else {
            return true
        }
        return !["disabled", "false", "off", "0"].contains(normalized)
    }

    private static func material(
        _ pass: SceneRenderDescriptor.MaterialPassDescriptor
    ) -> SceneStaticModelMaterial {
        // Shader symbols are case-sensitive. Stock model materials commonly
        // carry both the editor's `Color`/`Alpha` defaults and the authored
        // `color`/`alpha` inputs, so a folded lookup can nondeterministically
        // replace the authored value with its neutral editor default.
        let color = components(named: "color", in: pass)
            ?? components(named: "Color", in: pass)
            ?? [1, 1, 1]
        let opacity = components(named: "alpha", in: pass)?.first
            ?? components(named: "Alpha", in: pass)?.first
            ?? 1
        let emissiveColor = components(named: "emissivecolor", in: pass)
            ?? [1, 1, 1]
        let emissiveBrightness = components(
            named: "emissivebrightness",
            in: pass
        )?.first ?? 0
        let tintFront = components(named: "tintfront", in: pass)
        let tintBack = components(named: "tintback", in: pass)
        let tintExponent = components(named: "tintwexponent", in: pass)?
            .first ?? 1.5
        let viewTint: SceneStaticModelViewTint? = if let tintFront, let tintBack {
            .init(
                front: SIMD3(
                    component(tintFront, at: 0, default: 1),
                    component(tintFront, at: 1, default: 1),
                    component(tintFront, at: 2, default: 1)
                ),
                back: SIMD3(
                    component(tintBack, at: 0, default: 1),
                    component(tintBack, at: 1, default: 1),
                    component(tintBack, at: 2, default: 1)
                ),
                exponent: Float(tintExponent),
                usesDynamicBackColor:
                    shaderValue(named: "tintback", in: pass)?.scriptSource != nil
            )
        } else {
            nil
        }
        return SceneStaticModelMaterial(
            color: SIMD3(
                component(color, at: 0, default: 1),
                component(color, at: 1, default: 1),
                component(color, at: 2, default: 1)
            ),
            opacity: Float(opacity),
            receivesLighting: pass.combos["LIGHTING"] != 0,
            textureAlphaIsOpacity: pass.combos["TINTMASKALPHA"] != 1,
            textureAlphaIsTintMask: pass.combos["TINTMASKALPHA"] == 1,
            emissiveColor: SIMD3(
                component(emissiveColor, at: 0, default: 1),
                component(emissiveColor, at: 1, default: 1),
                component(emissiveColor, at: 2, default: 1)
            ),
            emissiveBrightness: Float(emissiveBrightness),
            viewTint: viewTint
        )
    }

    /// Optional packed material data fails soft, leaving the ordinary lit
    /// albedo intact. It is loaded as a typed mask rather than color.
    private static func optionalTexture(
        at slotIndex: Int,
        in pass: SceneRenderDescriptor.MaterialPassDescriptor,
        purpose: SceneTextureLoadPurpose,
        resolver: SceneTexturePathResolver,
        textureLoader: SceneTextureLoader,
        device: MTLDevice
    ) -> SceneTextureCandidate? {
        guard pass.textureSlots.indices.contains(slotIndex),
              let path = pass.textureSlots[slotIndex],
              let url = resolver.resolveTextureFile(named: path),
              case let .loaded(candidate) = textureLoader.loadCandidate(
                  from: url,
                  purpose: purpose,
                  device: device
              ),
              candidate.sampling.isResolvedForMaterialProgram,
              !candidate.sampling.usesClampBorderFallback else {
            return nil
        }
        return candidate
    }

    private static func components(
        named name: String,
        in pass: SceneRenderDescriptor.MaterialPassDescriptor
    ) -> [Double]? {
        shaderValue(named: name, in: pass)?.components
    }

    private static func shaderValue(
        named name: String,
        in pass: SceneRenderDescriptor.MaterialPassDescriptor
    ) -> SceneDocument.ShaderValue? {
        pass.constantShaderValues[name]
    }

    private static func component(
        _ values: [Double],
        at index: Int,
        default defaultValue: Float
    ) -> Float {
        values.indices.contains(index) ? Float(values[index]) : defaultValue
    }
}
