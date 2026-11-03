private func appendReadback(
    _ texture: MTLTexture,
    commandBuffer: MTLCommandBuffer
) -> Readback? {
    let (rowBytes, rowOverflow) = texture.width.multipliedReportingOverflow(by: 4)
    let (paddedRowBytes, paddingOverflow) = rowBytes.addingReportingOverflow(255)
    guard !rowOverflow, !paddingOverflow else { return nil }
    let bytesPerRow = (paddedRowBytes / 256) * 256
    let (imageBytes, imageOverflow) = bytesPerRow.multipliedReportingOverflow(by: texture.height)
    guard !imageOverflow else { return nil }
    guard let destination = texture.device.makeBuffer(
        length: imageBytes,
        options: .storageModeShared
    ), let encoder = commandBuffer.makeBlitCommandEncoder() else {
        return nil
    }
    encoder.copy(
        from: texture,
        sourceSlice: 0,
        sourceLevel: 0,
        sourceOrigin: .init(x: 0, y: 0, z: 0),
        sourceSize: .init(
            width: texture.width,
            height: texture.height,
            depth: 1
        ),
        to: destination,
        destinationOffset: 0,
        destinationBytesPerRow: bytesPerRow,
        destinationBytesPerImage: imageBytes
    )
    encoder.endEncoding()
    return .init(
        buffer: destination,
        bytesPerRow: bytesPerRow,
        width: texture.width,
        height: texture.height
    )
}

private struct ScalarReadback {
    let buffer: MTLBuffer
    let bytesPerRow: Int
    let width: Int
    let height: Int

    var first: UInt8 {
        buffer.contents().assumingMemoryBound(to: UInt8.self).pointee
    }

    var last: UInt8 {
        let offset = (height - 1) * bytesPerRow + width - 1
        return buffer.contents().advanced(by: offset)
            .assumingMemoryBound(to: UInt8.self).pointee
    }
}

private func appendScalarReadback(
    _ texture: MTLTexture,
    commandBuffer: MTLCommandBuffer
) -> ScalarReadback? {
    guard texture.pixelFormat == .r8Unorm else { return nil }
    let bytesPerRow = 256
    guard let destination = texture.device.makeBuffer(
        length: bytesPerRow * texture.height,
        options: .storageModeShared
    ), let encoder = commandBuffer.makeBlitCommandEncoder() else { return nil }
    encoder.copy(
        from: texture,
        sourceSlice: 0,
        sourceLevel: 0,
        sourceOrigin: .init(x: 0, y: 0, z: 0),
        sourceSize: .init(width: texture.width, height: texture.height, depth: 1),
        to: destination,
        destinationOffset: 0,
        destinationBytesPerRow: bytesPerRow,
        destinationBytesPerImage: bytesPerRow * texture.height
    )
    encoder.endEncoding()
    return .init(
        buffer: destination,
        bytesPerRow: bytesPerRow,
        width: texture.width,
        height: texture.height
    )
}

private struct RedGreenReadback {
    let buffer: MTLBuffer
    let bytesPerRow: Int
    let width: Int
    let height: Int

    var first: [UInt8] {
        let pointer = buffer.contents().assumingMemoryBound(to: UInt8.self)
        return Array(UnsafeBufferPointer(start: pointer, count: 2))
    }

    var last: [UInt8] {
        let offset = (height - 1) * bytesPerRow + (width - 1) * 2
        let pointer = buffer.contents().advanced(by: offset)
            .assumingMemoryBound(to: UInt8.self)
        return Array(UnsafeBufferPointer(start: pointer, count: 2))
    }
}

private func appendRedGreenReadback(
    _ texture: MTLTexture,
    commandBuffer: MTLCommandBuffer
) -> RedGreenReadback? {
    guard texture.pixelFormat == .rg8Unorm else { return nil }
    let bytesPerRow = 256
    guard let destination = texture.device.makeBuffer(
        length: bytesPerRow * texture.height,
        options: .storageModeShared
    ), let encoder = commandBuffer.makeBlitCommandEncoder() else { return nil }
    encoder.copy(
        from: texture,
        sourceSlice: 0,
        sourceLevel: 0,
        sourceOrigin: .init(x: 0, y: 0, z: 0),
        sourceSize: .init(
            width: texture.width,
            height: texture.height,
            depth: 1
        ),
        to: destination,
        destinationOffset: 0,
        destinationBytesPerRow: bytesPerRow,
        destinationBytesPerImage: bytesPerRow * texture.height
    )
    encoder.endEncoding()
    return .init(
        buffer: destination,
        bytesPerRow: bytesPerRow,
        width: texture.width,
        height: texture.height
    )
}

private func matches(_ pixel: [UInt8], _ expected: [UInt8]) -> Bool {
    pixel.count == expected.count && zip(pixel, expected).allSatisfy {
        abs(Int($0) - Int($1)) <= 2
    }
}

private func isPremultiplied(_ pixel: [UInt8]) -> Bool {
    guard pixel.count == 4 else { return false }
    let alpha = Int(pixel[3])
    return Int(pixel[0]) <= alpha + 1
        && Int(pixel[1]) <= alpha + 1
        && Int(pixel[2]) <= alpha + 1
        && (alpha != 0 || pixel[0 ... 2].allSatisfy { $0 == 0 })
}

private func fill(
    _ texture: MTLTexture,
    color: MTLClearColor,
    queue: MTLCommandQueue
) -> Bool {
    guard let buffer = queue.makeCommandBuffer() else { return false }
    let descriptor = MTLRenderPassDescriptor()
    descriptor.colorAttachments[0].texture = texture
    descriptor.colorAttachments[0].loadAction = .clear
    descriptor.colorAttachments[0].storeAction = .store
    descriptor.colorAttachments[0].clearColor = color
    guard let encoder = buffer.makeRenderCommandEncoder(
        descriptor: descriptor
    ) else { return false }
    encoder.endEncoding()
    buffer.commit()
    buffer.waitUntilCompleted()
    return buffer.status == .completed && buffer.error == nil
}
