#if DEBUG
import AppKit
@preconcurrency import Metal

/// Diagnostic requests and exports own their buffers independently of surfaces.
nonisolated final class SceneDebugFrameCapture: @unchecked Sendable {
    enum RequestClass: Sendable { case required, periodic }
    enum Admission: Equatable { case accepted(UInt64), rejected(String) }
    struct Terminal: Sendable {
        let id: UInt64
        let reason: String
        let failure: String?
    }
    private struct Request: Sendable {
        let id: UInt64
        let reason: String
        let outputDirectory: URL
        let kind: RequestClass
    }
    /// One process-wide export lane. Counts work, never owns a capture registry.
    private final class WorkLane: @unchecked Sendable {
        let queue = DispatchQueue(label: "Scene diagnostic PNG export", qos: .utility)
        private let lock = NSLock()
        private var count = 0
        private var bytes = 0
        func acquire(_ size: Int) -> Bool {
            lock.lock(); defer { lock.unlock() }
            guard count < 2, size <= SceneResourceBudget.shared.maximumBytes / 4 - bytes else { return false }
            count += 1; bytes += size
            return true
        }
        func release(_ size: Int) {
            lock.lock(); defer { lock.unlock() }
            count -= 1; bytes -= size
        }
    }
    private static let lane = WorkLane()
    private let lock = NSLock()
    private let isEnabled = ProcessInfo.processInfo.arguments.contains("--mwx-debug-scene-evidence-dir")
    private var pendingRequests: [Request] = []
    private var nextID: UInt64 = 0
    private var outstanding = 0
    private var closed = false
    private var drainCallbacks: [@Sendable () -> Void] = []
    // Scheduling observation permits deterministic completion/drain race tests.
    private let beforeExport: (@Sendable () -> Void)?
    private let observeTerminal: (@Sendable (Terminal) -> Void)?

    init(beforeExport: (@Sendable () -> Void)? = nil,
         observeTerminal: (@Sendable (Terminal) -> Void)? = nil) {
        self.beforeExport = beforeExport
        self.observeTerminal = observeTerminal
    }

    func configure(_ layer: CAMetalLayer) {
        if isEnabled { layer.framebufferOnly = false }
    }

    @discardableResult
    func request(reason: String, outputDirectory: URL, kind: RequestClass = .required) -> Admission {
        lock.lock()
        let rejection: String?
        if !isEnabled { rejection = "disabled" }
        else if closed { rejection = "closed" }
        else if kind == .required && pendingRequests.filter({ $0.kind == .required }).count >= 2 {
            rejection = "required-pending-full"
        } else { rejection = nil }
        if let rejection {
            lock.unlock()
            Self.reportRejected(reason: reason, stage: rejection)
            return .rejected(rejection)
        }
        var superseded: Request?
        if kind == .periodic, let index = pendingRequests.firstIndex(where: { $0.kind == .periodic }) {
            superseded = pendingRequests.remove(at: index)
            outstanding += 1
        }
        nextID += 1
        let request = Request(id: nextID, reason: reason, outputDirectory: outputDirectory, kind: kind)
        pendingRequests.append(request)
        lock.unlock()
        if let superseded {
            report(superseded, failure: "superseded")
            finishOutstanding()
        }
        return .accepted(request.id)
    }

    func closeAndDrain(_ completion: @escaping @Sendable () -> Void) {
        lock.lock()
        closed = true
        let pending = pendingRequests
        pendingRequests.removeAll()
        // Include pending terminal delivery before exposing drain completion.
        outstanding += pending.count
        drainCallbacks.append(completion)
        lock.unlock()
        for request in pending {
            report(request, failure: "teardown")
            finishOutstanding()
        }
        finishIfDrained()
    }

    func encodeIfRequested(texture: MTLTexture, commandBuffer: MTLCommandBuffer) {
        lock.lock()
        guard !closed, !pendingRequests.isEmpty else { lock.unlock(); return }
        let width = texture.width, height = texture.height
        let isFloat = texture.pixelFormat == .rgba16Float
        let (rowBytes, rowOverflow) = width.multipliedReportingOverflow(by: isFloat ? 8 : 4)
        let (byteCount, sizeOverflow) = rowBytes.multipliedReportingOverflow(by: height)
        let supported = texture.pixelFormat == .bgra8Unorm || isFloat
        let size = supported && !rowOverflow && !sizeOverflow
            ? texture.device.heapBufferSizeAndAlign(length: byteCount, options: .storageModeShared).size : 0
        let invalid = !supported || rowOverflow || sizeOverflow
            || size > SceneResourceBudget.shared.maximumBytes / 4
        if !invalid && !Self.lane.acquire(size) { lock.unlock(); return }
        let request = pendingRequests.removeFirst()
        outstanding += 1
        lock.unlock()
        if invalid {
            report(request, failure: "readback-format-or-size")
            finishOutstanding()
            return
        }
        guard let buffer = texture.device.makeSceneBuffer(length: byteCount, options: .storageModeShared),
              let encoder = commandBuffer.makeBlitCommandEncoder() else {
            finish(request, bytes: size, failure: "metal-readback-setup")
            return
        }
        encoder.copy(from: texture, sourceSlice: 0, sourceLevel: 0,
                     sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
                     sourceSize: MTLSize(width: width, height: height, depth: 1),
                     to: buffer, destinationOffset: 0,
                     destinationBytesPerRow: rowBytes, destinationBytesPerImage: byteCount)
        encoder.endEncoding()
        // Outstanding was registered before commit, including the GPU/callback gap.
        commandBuffer.addCompletedHandler { [self] completed in
            guard completed.status == .completed else {
                finish(request, bytes: size, failure: "metal-command-\(completed.status.rawValue)")
                return
            }
            Self.lane.queue.async { [self] in
                beforeExport?()
                let failure = withExtendedLifetime(buffer) {
                    autoreleasepool {
                        Self.persist(buffer: buffer, width: width, height: height,
                                     rowBytes: rowBytes, isFloat: isFloat, request: request)
                    }
                }
                finish(request, bytes: size, failure: failure)
            }
        }
    }

    private func finish(_ request: Request, bytes: Int, failure: String?) {
        report(request, failure: failure)
        Self.lane.release(bytes)
        finishOutstanding()
    }
    private func finishOutstanding() {
        lock.lock(); outstanding -= 1; lock.unlock()
        finishIfDrained()
    }
    private func finishIfDrained() {
        lock.lock()
        let callbacks = closed && outstanding == 0 ? drainCallbacks : []
        if closed && outstanding == 0 { drainCallbacks.removeAll() }
        lock.unlock()
        callbacks.forEach { $0() }
    }
    private func report(_ request: Request, failure: String?) {
        if let failure {
            NSLog("MWX DEBUG SCENE: phase=snapshot-failed reason=%@ request=%llu stage=%@", request.reason, request.id, failure)
        }
        observeTerminal?(Terminal(id: request.id, reason: request.reason, failure: failure))
    }
    static func reportRejected(reason: String, stage: String) {
        NSLog("MWX DEBUG SCENE: phase=snapshot-rejected reason=%@ stage=%@", reason, stage)
    }

    private static func persist(buffer: MTLBuffer, width: Int, height: Int,
                                rowBytes: Int, isFloat: Bool, request: Request) -> String? {
        if isFloat {
            // GPU is terminal; this independent buffer now belongs only to this
            // CPU export. Convert in place, without full-frame CPU copies.
            let count = rowBytes * height / 2
            let words = buffer.contents().bindMemory(to: UInt16.self, capacity: count)
            for index in 0..<count {
                let value = Float(Float16(bitPattern: words[index]))
                let normalized = value.isFinite ? min(1, max(0, value)) : 0
                words[index] = UInt16((normalized * 65_535).rounded())
            }
        }
        let bitmapInfo: CGBitmapInfo = isFloat
            ? [.byteOrder16Little, CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)]
            : [.byteOrder32Little, CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue)]
        // persist is synchronous inside withExtendedLifetime(buffer) and an
        // autoreleasepool: the provider cannot outlive its exclusively owned data.
        guard let provider = CGDataProvider(dataInfo: nil, data: buffer.contents(),
                                          size: rowBytes * height, releaseData: { _, _, _ in }),
              let source = CGImage(width: width, height: height, bitsPerComponent: isFloat ? 16 : 8,
                bitsPerPixel: isFloat ? 64 : 32, bytesPerRow: rowBytes,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: bitmapInfo,
                provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent),
              let png = NSBitmapImageRep(cgImage: source).representation(using: .png, properties: [:])
        else { return "png-encode" }
        let outputURL = request.outputDirectory.appendingPathComponent("scene-\(request.reason)-window.png")
        do {
            try png.write(to: outputURL, options: [.atomic])
            NSLog("MWX DEBUG SCENE: phase=snapshot reason=%@ request=%llu source=metal path=%@", request.reason, request.id, outputURL.path)
            return nil
        } catch { return "write" }
    }
}
#endif
