import Foundation
import Metal

/// Executes a test kernel appended to the actual frontend-generated source.
@main
private enum SceneShaderExpressionProbe {
    static func main() throws {
        guard CommandLine.arguments.count == 3,
              let count = Int(CommandLine.arguments[2]), count > 0,
              let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue() else {
            throw NSError(domain: "expression-probe-input-or-device", code: 1)
        }
        let source = try String(contentsOfFile: CommandLine.arguments[1], encoding: .utf8)
        let library = try device.makeLibrary(source: source, options: nil)
        guard let function = library.makeFunction(name: "mwxTestEvaluate"),
              let buffer = device.makeBuffer(length: count * MemoryLayout<SIMD4<Float>>.stride,
                                             options: .storageModeShared),
              let command = queue.makeCommandBuffer(),
              let encoder = command.makeComputeCommandEncoder() else {
            throw NSError(domain: "expression-probe-resource", code: 1)
        }
        let pipeline = try device.makeComputePipelineState(function: function)
        encoder.setComputePipelineState(pipeline)
        encoder.setBuffer(buffer, offset: 0, index: 0)
        encoder.dispatchThreads(MTLSize(width: count, height: 1, depth: 1),
            threadsPerThreadgroup: MTLSize(width: 1, height: 1, depth: 1))
        encoder.endEncoding()
        command.commit()
        command.waitUntilCompleted()
        guard command.status == .completed, command.error == nil else {
            throw command.error ?? NSError(domain: "expression-probe-completion", code: 1)
        }
        let values = buffer.contents().bindMemory(to: Float.self, capacity: count * 4)
        let output = Array(UnsafeBufferPointer(start: values, count: count * 4))
        FileHandle.standardOutput.write(try JSONEncoder().encode(output))
    }
}
