import Foundation
import Metal
import simd

/// Load-time bridge: resolves a layer's puppet `.mdl`, parses the bind-pose
/// mesh, and creates either an animated or bind-pose GeometryProduct. The
/// atlas is retained only by that product as a sampling resource.
enum ScenePuppetLayerLoad {
    private enum MeshFileResolution {
        case ready(URL)
        case absent
        case rejected
    }

    /// Launch-time payload installed into any existing SceneScript owner for
    /// the same authored layer.  The rig reader remains the sole source of
    /// names, parent order, and bind-local matrices; no sample-specific
    /// routing is involved.
    struct BoneConfiguration {
        let names: [String]
        let parentIndices: [Int]
        let worldMatrices: [Double]
        let localMatrices: [Double]
    }

    static func boneConfiguration(
        for layer: SceneRenderDescriptor.Layer,
        cacheDirectory: URL
    ) -> BoneConfiguration? {
        guard let puppetMeshPath = layer.puppetMeshPath,
              case let .ready(meshURL) = meshFileResolution(
                  relativePath: puppetMeshPath,
                  cacheDirectory: cacheDirectory
              ),
              let data = try? Data(contentsOf: meshURL),
              let mesh = try? SceneMdlPuppetMeshReader.read(data: data),
              let rig = try? SceneMdlPuppetRigReader.read(data: data, mesh: mesh)
        else { return nil }
        for (index, bone) in rig.bones.enumerated() {
            if let diagnostic = bone.physicsDiagnostic {
                NSLog("MWX Puppet: layer=%d bone=%d fallback=authored-pose reason=%@",
                      layer.id, index, diagnostic)
            }
        }
        let localMatrices: [simd_float4x4] = rig.bones.map { bone in
            let values = bone.bindLocalMatrixColumnMajor
            return simd_float4x4(
                SIMD4(values[0], values[1], values[2], values[3]),
                SIMD4(values[4], values[5], values[6], values[7]),
                SIMD4(values[8], values[9], values[10], values[11]),
                SIMD4(values[12], values[13], values[14], values[15])
            )
        }
        guard let frame = try? ScenePuppetBoneTransformFrame(
            rig: rig, animatedLocalMatrices: localMatrices
        ) else { return nil }
        func flatten(_ matrix: simd_float4x4) -> [Double] {
            [matrix.columns.0, matrix.columns.1, matrix.columns.2, matrix.columns.3]
                .flatMap { [Double($0.x), Double($0.y), Double($0.z), Double($0.w)] }
        }
        return BoneConfiguration(
            names: rig.bones.map(\.name),
            parentIndices: rig.bones.map(\.parentIndex),
            worldMatrices: frame.worldMatrices.flatMap(flatten),
            localMatrices: frame.localMatrices.flatMap(flatten)
        )
    }

    struct Outcome {
        let geometryProduct: SceneGeometryProduct?
        let playback: ScenePuppetPlaybackState?
        /// True only when the authored package omits the referenced mesh. In
        /// that case the image payload is the sole available authored product.
        let allowsMissingMeshTextureProduct: Bool
        let message: String
    }

    static func preparedGeometry(
        for layer: SceneRenderDescriptor.Layer,
        atlasTexture: MTLTexture,
        cacheDirectory: URL,
        device: MTLDevice,
        pipeline: SceneImageLayerPipeline
    ) -> Outcome? {
        guard let puppetMeshPath = layer.puppetMeshPath else { return nil }
        let meshURL: URL
        switch meshFileResolution(
            relativePath: puppetMeshPath,
            cacheDirectory: cacheDirectory
        ) {
        case let .ready(url):
            meshURL = url
        case .absent:
            return Outcome(
                geometryProduct: nil,
                playback: nil,
                allowsMissingMeshTextureProduct: true,
                message: "puppet mesh unavailable (\(puppetMeshPath))"
            )
        case .rejected:
            return Outcome(
                geometryProduct: nil,
                playback: nil,
                allowsMissingMeshTextureProduct: false,
                message: "puppet mesh path rejected (\(puppetMeshPath))"
            )
        }
        let data: Data
        do {
            data = try Data(contentsOf: meshURL)
        } catch {
            return Outcome(
                geometryProduct: nil,
                playback: nil,
                allowsMissingMeshTextureProduct: false,
                message: "puppet mesh read failed (\(puppetMeshPath))"
            )
        }
        let mesh: SceneMdlPuppetMesh
        do {
            mesh = try SceneMdlPuppetMeshReader.read(data: data)
        } catch let error as SceneMdlPuppetMeshReadError {
            return Outcome(
                geometryProduct: nil,
                playback: nil,
                allowsMissingMeshTextureProduct: false,
                message: "puppet mesh rejected: \(error.description) (\(puppetMeshPath))"
            )
        } catch {
            return Outcome(
                geometryProduct: nil,
                playback: nil,
                allowsMissingMeshTextureProduct: false,
                message: "puppet mesh rejected: unknown parse failure (\(puppetMeshPath))"
            )
        }
        let renderSize = layer.renderSizeWH ?? []
        let layerWidth = renderSize.count > 0 ? renderSize[0] : 0
        let layerHeight = renderSize.count > 1 ? renderSize[1] : 0
        var animationFallbackMessage: String?
        if layer.puppetAnimationLayers.isEmpty == false {
            do {
                let rig = try SceneMdlPuppetRigReader.read(data: data, mesh: mesh)
                guard let animationSet = try SceneMdlPuppetAnimationReader.read(data: data) else {
                    animationFallbackMessage = "animation rejected: version-matched MDLA is absent"
                    return staticOutcome(
                        layer: layer,
                        mesh: mesh,
                        layerWidth: layerWidth,
                        layerHeight: layerHeight,
                        device: device,
                        pipeline: pipeline,
                        animationFallbackMessage: animationFallbackMessage
                    )
                }
                switch ScenePuppetAnimationSelector.select(
                    layers: layer.puppetAnimationLayers,
                    animationSet: animationSet
                ) {
                case let .success(selection?):
                    switch ScenePuppetPlaybackState.make(
                        layerID: layer.id,
                        mesh: mesh,
                        rig: rig,
                        selection: selection,
                        atlasTexture: atlasTexture,
                        layerWidth: layerWidth,
                        layerHeight: layerHeight,
                        device: device,
                        pipeline: pipeline
                    ) {
                    case let .success(output):
                        return Outcome(
                            geometryProduct: output.product,
                            playback: output.state,
                            allowsMissingMeshTextureProduct: false,
                            message: String(
                                format: "puppet world geometry OK %@ mode=%@ ids=%@ clips=%d verts=%d tris=%d",
                                mesh.version,
                                selection.composition.rawValue,
                                selection.clips.map { String($0.animation.id) }.joined(separator: ","),
                                selection.clips.count,
                                mesh.vertices.count,
                                mesh.triangleCount
                            )
                        )
                    case let .failure(failure):
                        animationFallbackMessage = "animation geometry rejected: \(failure.description)"
                    }
                case .success(nil):
                    animationFallbackMessage = "animation inactive: no visible layer"
                case let .failure(failure):
                    animationFallbackMessage = "animation rejected: \(failure.description)"
                }
            } catch let failure as SceneMdlPuppetRigReadError {
                animationFallbackMessage = "animation rig rejected: \(failure.description)"
            } catch let failure as SceneMdlPuppetAnimationReadError {
                animationFallbackMessage = "animation data rejected: \(failure.description)"
            } catch {
                animationFallbackMessage = "animation rejected: unknown parse failure"
            }
        }
        // A script can deform a rig without an authored animation clip. Keep
        // it in the same playback/evaluator owner, seeded by the bind pose.
        if layer.puppetAnimationLayers.isEmpty, layer.hasInlineScript,
           let rig = try? SceneMdlPuppetRigReader.read(data: data, mesh: mesh) {
            switch ScenePuppetPlaybackState.make(
                layerID: layer.id, mesh: mesh, rig: rig,
                selection: .init(clips: [], composition: .layered),
                atlasTexture: atlasTexture, layerWidth: layerWidth,
                layerHeight: layerHeight,
                device: device, pipeline: pipeline
            ) {
            case let .success(output):
                return Outcome(geometryProduct: output.product, playback: output.state,
                    allowsMissingMeshTextureProduct: false,
                    message: "puppet script world geometry prepared")
            case let .failure(failure):
                animationFallbackMessage = "script pose rejected: \(failure.description)"
            }
        }
        return staticOutcome(
            layer: layer,
            mesh: mesh,
            layerWidth: layerWidth,
            layerHeight: layerHeight,
            device: device,
            pipeline: pipeline,
            animationFallbackMessage: animationFallbackMessage
        )
    }

    private static func staticOutcome(
        layer: SceneRenderDescriptor.Layer,
        mesh: SceneMdlPuppetMesh,
        layerWidth: Float,
        layerHeight: Float,
        device: MTLDevice,
        pipeline: SceneImageLayerPipeline,
        animationFallbackMessage: String?
    ) -> Outcome {
        switch ScenePuppetMeshGeometry.prepare(
            mesh: mesh,
            layerWidth: layerWidth,
            layerHeight: layerHeight,
            device: device,
            pipeline: pipeline
        ) {
        case let .success(output):
            return Outcome(
                geometryProduct: output.product,
                playback: nil,
                allowsMissingMeshTextureProduct: false,
                message: String(
                    format: "puppet bind-pose world geometry OK %@ stride=%d verts=%d tris=%d",
                    mesh.version,
                    mesh.vertexStride,
                    output.vertexCount,
                    output.triangleCount
                ) + (animationFallbackMessage.map { "; \($0)" } ?? "")
            )
        case let .failure(failure):
            return Outcome(
                geometryProduct: nil,
                playback: nil,
                allowsMissingMeshTextureProduct: false,
                message: "puppet geometry preparation failed: \(failure.description) (\(layer.puppetMeshPath ?? "unknown"))"
                    + (animationFallbackMessage.map { "; \($0)" } ?? "")
            )
        }
    }

    /// The mesh path comes from extracted pkg JSON; only accept it when the
    /// resolved file (symlinks included) stays inside the extraction cache.
    private static func meshFileResolution(
        relativePath: String,
        cacheDirectory: URL
    ) -> MeshFileResolution {
        guard relativePath.hasPrefix("/") == false,
              relativePath.contains("..") == false
        else {
            return .rejected
        }
        let candidate = cacheDirectory.appendingPathComponent(relativePath)
        guard FileManager.default.fileExists(atPath: candidate.path) else {
            return .absent
        }
        let resolvedFile = candidate.resolvingSymlinksInPath().standardizedFileURL
        let resolvedRoot = cacheDirectory.resolvingSymlinksInPath().standardizedFileURL
        let rootPath = resolvedRoot.path.hasSuffix("/")
            ? resolvedRoot.path
            : resolvedRoot.path + "/"
        guard resolvedFile.path.hasPrefix(rootPath) else { return .rejected }
        return .ready(candidate)
    }
}
