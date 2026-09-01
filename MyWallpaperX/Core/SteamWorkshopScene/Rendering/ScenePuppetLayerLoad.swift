import Foundation
import Metal

// Load-time bridge: resolves a layer's puppet `.mdl`, parses the bind-pose
// mesh, and creates either a bounded playback state or a static
// bind-pose image. Failure
// keeps the existing atlas texture (current behavior) and reports why, so
// unsupported puppets stay visible in diagnostics instead of silently
// pretending to be supported.
enum ScenePuppetLayerLoad {
    struct StaticRecomposeIdentity: Hashable {
        fileprivate let puppetMeshSource: SceneTextureLoader.SourceKey
        fileprivate let atlasTexture: ObjectIdentifier
        fileprivate let layerWidthBits: UInt32
        fileprivate let layerHeightBits: UInt32
    }

    struct Outcome {
        let texture: MTLTexture?
        let playback: ScenePuppetPlaybackState?
        let byteCost: Int
        let message: String
    }

    static func staticRecomposeIdentity(
        for layer: SceneRenderDescriptor.Layer,
        atlasTexture: MTLTexture,
        atlasIsAnimated: Bool,
        cacheDirectory: URL,
        loader: SceneTextureLoader
    ) -> StaticRecomposeIdentity? {
        guard atlasIsAnimated == false,
              layer.puppetAnimationLayers.isEmpty,
              let puppetMeshPath = layer.puppetMeshPath,
              let renderSize = layer.renderSizeWH,
              renderSize.count >= 2,
              let puppetMeshURL = containedFileURL(
                  relativePath: puppetMeshPath,
                  cacheDirectory: cacheDirectory
              ),
              let puppetMeshSource = loader.sourceKey(for: puppetMeshURL) else {
            return nil
        }
        return StaticRecomposeIdentity(
            puppetMeshSource: puppetMeshSource,
            atlasTexture: ObjectIdentifier(atlasTexture),
            layerWidthBits: renderSize[0].bitPattern,
            layerHeightBits: renderSize[1].bitPattern
        )
    }

    static func recomposedTexture(
        for layer: SceneRenderDescriptor.Layer,
        atlasTexture: MTLTexture,
        cacheDirectory: URL,
        remainingByteBudget: Int,
        device: MTLDevice,
        commandQueue: MTLCommandQueue,
        pipeline: SceneImageLayerPipeline
    ) -> Outcome? {
        guard let puppetMeshPath = layer.puppetMeshPath else { return nil }
        guard let meshURL = containedFileURL(
            relativePath: puppetMeshPath,
            cacheDirectory: cacheDirectory
        ) else {
            return Outcome(
                texture: nil,
                playback: nil,
                byteCost: 0,
                message: "puppet mesh unavailable (\(puppetMeshPath))"
            )
        }
        let data: Data
        do {
            data = try Data(contentsOf: meshURL)
        } catch {
            return Outcome(
                texture: nil,
                playback: nil,
                byteCost: 0,
                message: "puppet mesh read failed (\(puppetMeshPath))"
            )
        }
        let mesh: SceneMdlPuppetMesh
        do {
            mesh = try SceneMdlPuppetMeshReader.read(data: data)
        } catch let error as SceneMdlPuppetMeshReadError {
            return Outcome(
                texture: nil,
                playback: nil,
                byteCost: 0,
                message: "puppet mesh rejected: \(error.description) (\(puppetMeshPath))"
            )
        } catch {
            return Outcome(
                texture: nil,
                playback: nil,
                byteCost: 0,
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
                        atlasTexture: atlasTexture,
                        layerWidth: layerWidth,
                        layerHeight: layerHeight,
                        remainingByteBudget: remainingByteBudget,
                        device: device,
                        commandQueue: commandQueue,
                        pipeline: pipeline,
                        animationFallbackMessage: animationFallbackMessage
                    )
                }
                switch ScenePuppetAnimationSelector.select(
                    layers: layer.puppetAnimationLayers,
                    animationSet: animationSet
                ) {
                case .success(let selection?):
                    switch ScenePuppetPlaybackState.make(
                        layerID: layer.id,
                        mesh: mesh,
                        rig: rig,
                        selection: selection,
                        atlasTexture: atlasTexture,
                        layerWidth: layerWidth,
                        layerHeight: layerHeight,
                        remainingByteBudget: remainingByteBudget,
                        device: device,
                        pipeline: pipeline
                    ) {
                    case .success(let output):
                        return Outcome(
                            texture: output.texture,
                            playback: output.state,
                            byteCost: output.byteCost,
                            message: String(
                                format: "puppet animation OK %@ mode=%@ ids=%@ clips=%d verts=%d tris=%d → %d×%d",
                                mesh.version,
                                selection.composition.rawValue,
                                selection.clips.map { String($0.animation.id) }.joined(separator: ","),
                                selection.clips.count,
                                mesh.vertices.count,
                                mesh.triangleCount,
                                output.texture.width,
                                output.texture.height
                            )
                        )
                    case .failure(let failure):
                        animationFallbackMessage = "animation target rejected: \(failure.description)"
                    }
                case .success(nil):
                    animationFallbackMessage = "animation inactive: no visible layer"
                case .failure(let failure):
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
        return staticOutcome(
            layer: layer,
            mesh: mesh,
            atlasTexture: atlasTexture,
            layerWidth: layerWidth,
            layerHeight: layerHeight,
            remainingByteBudget: remainingByteBudget,
            device: device,
            commandQueue: commandQueue,
            pipeline: pipeline,
            animationFallbackMessage: animationFallbackMessage
        )
    }

    private static func staticOutcome(
        layer: SceneRenderDescriptor.Layer,
        mesh: SceneMdlPuppetMesh,
        atlasTexture: MTLTexture,
        layerWidth: Float,
        layerHeight: Float,
        remainingByteBudget: Int,
        device: MTLDevice,
        commandQueue: MTLCommandQueue,
        pipeline: SceneImageLayerPipeline,
        animationFallbackMessage: String?
    ) -> Outcome {
        switch ScenePuppetMeshRecomposer.recompose(
            mesh: mesh,
            atlasTexture: atlasTexture,
            layerWidth: layerWidth,
            layerHeight: layerHeight,
            remainingByteBudget: remainingByteBudget,
            device: device,
            commandQueue: commandQueue,
            pipeline: pipeline
        ) {
        case .success(let output):
            return Outcome(
                texture: output.texture,
                playback: nil,
                byteCost: output.byteCost,
                message: String(
                    format: "puppet bind-pose mesh OK %@ stride=%d verts=%d tris=%d → %d×%d",
                    mesh.version,
                    mesh.vertexStride,
                    output.vertexCount,
                    output.triangleCount,
                    output.texture.width,
                    output.texture.height
                ) + (animationFallbackMessage.map { "; \($0)" } ?? "")
            )
        case .failure(let failure):
            return Outcome(
                texture: nil,
                playback: nil,
                byteCost: 0,
                message: "puppet mesh recompose failed: \(failure.description) (\(layer.puppetMeshPath ?? "unknown"))"
                    + (animationFallbackMessage.map { "; \($0)" } ?? "")
            )
        }
    }

    // The mesh path comes from extracted pkg JSON; only accept it when the
    // resolved file (symlinks included) stays inside the extraction cache.
    private static func containedFileURL(relativePath: String, cacheDirectory: URL) -> URL? {
        guard relativePath.hasPrefix("/") == false,
              relativePath.contains("..") == false else {
            return nil
        }
        let candidate = cacheDirectory.appendingPathComponent(relativePath)
        guard FileManager.default.fileExists(atPath: candidate.path) else { return nil }
        let resolvedFile = candidate.resolvingSymlinksInPath().standardizedFileURL
        let resolvedRoot = cacheDirectory.resolvingSymlinksInPath().standardizedFileURL
        let rootPath = resolvedRoot.path.hasSuffix("/")
            ? resolvedRoot.path
            : resolvedRoot.path + "/"
        guard resolvedFile.path.hasPrefix(rootPath) else { return nil }
        return candidate
    }
}
