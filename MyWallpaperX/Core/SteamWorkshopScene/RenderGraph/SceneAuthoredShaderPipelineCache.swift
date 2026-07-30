import Foundation
import Metal

final class SceneAuthoredShaderPipelineCache {
    struct Pipeline {
        let state: MTLRenderPipelineState
        let sampler: MTLSamplerState
    }

    private struct Key: Hashable {
        let contractKey: String
        let pixelFormatRawValue: UInt
        let renderState: SceneMaterialRenderState
    }

    private enum Entry {
        case ready(Pipeline)
        case failed
    }

    private let device: MTLDevice
    private let pixelFormat: MTLPixelFormat
    private let sampler: MTLSamplerState
    private let lock = NSLock()
    private var entries: [Key: Entry] = [:]
    private var compilationAttempts = 0
    private var failedEntries = 0

    var entryCount: Int { withLock { entries.count } }
    var compilationAttemptCount: Int { withLock { compilationAttempts } }
    var failedEntryCount: Int { withLock { failedEntries } }

    init?(
        device: MTLDevice,
        pixelFormat: MTLPixelFormat = .bgra8Unorm
    ) {
        guard pixelFormat == .bgra8Unorm else { return nil }
        let descriptor = MTLSamplerDescriptor()
        descriptor.normalizedCoordinates = true
        descriptor.minFilter = .linear
        descriptor.magFilter = .linear
        descriptor.mipFilter = .notMipmapped
        descriptor.sAddressMode = .clampToEdge
        descriptor.tAddressMode = .clampToEdge
        descriptor.rAddressMode = .clampToEdge
        guard let sampler = device.makeSamplerState(descriptor: descriptor) else {
            return nil
        }
        self.device = device
        self.pixelFormat = pixelFormat
        self.sampler = sampler
    }

    func pipeline(for plan: SceneAuthoredShaderExecutionPlan) -> Pipeline? {
        lock.lock()
        defer { lock.unlock() }
        let key = cacheKey(for: plan)
        if let entry = entries[key] {
            guard case .ready(let pipeline) = entry else { return nil }
            return pipeline
        }

        compilationAttempts += 1
        guard plan.renderState.matchesFullscreenOverwrite(
                  alphaWriting: .unspecified
              ),
              plan.program.uniformLayout.byteSize > 0,
              plan.program.uniformLayout.byteSize <= 4_096,
              let library = try? device.makeLibrary(
                  source: plan.program.metalSource,
                  options: nil
              ),
              let vertex = library.makeFunction(
                  name: plan.program.vertexFunctionName
              ),
              let fragment = library.makeFunction(
                  name: plan.program.fragmentFunctionName
              ) else {
            recordFailure(for: key)
            return nil
        }
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.label = "Scene authored shader \(plan.cacheKey.prefix(12))"
        descriptor.vertexFunction = vertex
        descriptor.fragmentFunction = fragment
        descriptor.colorAttachments[0].pixelFormat = pixelFormat
        descriptor.colorAttachments[0].isBlendingEnabled = false
        descriptor.colorAttachments[0].writeMask = .all
        guard let state = try? device.makeRenderPipelineState(descriptor: descriptor) else {
            recordFailure(for: key)
            return nil
        }
        let pipeline = Pipeline(state: state, sampler: sampler)
        entries[key] = .ready(pipeline)
        return pipeline
    }

    func reset() {
        lock.lock()
        defer { lock.unlock() }
        entries.removeAll(keepingCapacity: true)
        compilationAttempts = 0
        failedEntries = 0
    }

    private func recordFailure(for key: Key) {
        entries[key] = .failed
        failedEntries += 1
    }

    private func cacheKey(for plan: SceneAuthoredShaderExecutionPlan) -> Key {
        return Key(
            contractKey: plan.cacheKey,
            pixelFormatRawValue: pixelFormat.rawValue,
            renderState: plan.renderState
        )
    }

    private func withLock<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}
