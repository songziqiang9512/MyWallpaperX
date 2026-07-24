import Foundation
import Metal

// Load-time bridge: resolves a layer's puppet `.mdl`, parses the bind-pose
// mesh, and recomposes the atlas texture into the layer-space image. Failure
// keeps the existing atlas texture (current behavior) and reports why, so
// unsupported puppets stay visible in diagnostics instead of silently
// pretending to be supported.
enum ScenePuppetLayerLoad {
    struct Outcome {
        let texture: MTLTexture?
        let byteCost: Int
        let message: String
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
                byteCost: 0,
                message: "puppet mesh rejected: \(error.description) (\(puppetMeshPath))"
            )
        } catch {
            return Outcome(
                texture: nil,
                byteCost: 0,
                message: "puppet mesh rejected: unknown parse failure (\(puppetMeshPath))"
            )
        }
        let renderSize = layer.renderSizeWH ?? []
        let layerWidth = renderSize.count > 0 ? renderSize[0] : 0
        let layerHeight = renderSize.count > 1 ? renderSize[1] : 0
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
                byteCost: output.byteCost,
                message: String(
                    format: "puppet bind-pose mesh OK %@ stride=%d verts=%d tris=%d → %d×%d",
                    mesh.version,
                    mesh.vertexStride,
                    output.vertexCount,
                    output.triangleCount,
                    output.texture.width,
                    output.texture.height
                )
            )
        case .failure(let failure):
            return Outcome(
                texture: nil,
                byteCost: 0,
                message: "puppet mesh recompose failed: \(failure.description) (\(puppetMeshPath))"
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
