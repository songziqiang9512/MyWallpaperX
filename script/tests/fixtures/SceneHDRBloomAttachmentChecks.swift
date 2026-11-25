import Foundation
import Metal

enum SceneHDRBloomAttachmentChecks {
    typealias MakeTexture = (Int, Int, [Float16]) -> (texture: MTLTexture, bytes: [Float16])
    typealias ReadTexture = (MTLTexture, Int, Int) -> [Float16]

    private struct Fixture {
        let name: String
        let size: SIMD2<Int>
        let levels: [[Int]]
        let hdr: SceneBloomConfiguration.HDR
        let uniform: Bool
        let phase: Int
        let edgeBlocks: Bool

        init(_ name: String, _ size: SIMD2<Int>, _ levels: [[Int]], iterations: Float = 8,
             strength: Float = 0.3, threshold: Float = 0.5, scatter: Float = 1.6,
             uniform: Bool = false, phase: Int = 0, edgeBlocks: Bool = false) {
            self.name = name
            self.size = size
            self.levels = levels
            self.hdr = .init(strength: strength, threshold: threshold, scatter: scatter,
                             feather: 0.75, iterations: iterations)
            self.uniform = uniform
            self.phase = phase
            self.edgeBlocks = edgeBlocks
        }

        var rgba: [Float16] {
            let (width, height) = (size.x, size.y)
            var values = [Float16](repeating: 0, count: width * height * 4)
            for y in 0..<height {
                for x in 0..<width {
                    let texel = pixel(x, y)
                    let offset = (y * width + x) * 4
                    values[offset] = texel.0
                    values[offset + 1] = texel.1
                    values[offset + 2] = texel.2
                    values[offset + 3] = texel.3
                }
            }
            return values
        }

        private func pixel(_ x: Int, _ y: Int) -> (Float16, Float16, Float16, Float16) {
            if uniform { return (0.25, 0.125, 0.5, 0.375) }
            if x == size.x - 1 && y == size.y - 1 { return (32, 4, 0.0625, 0.875) }
            if edgeBlocks {
                if x >= size.x / 2 + 1 && y < size.y / 2 - 1 { return (8, 2, 0.625, 0.875) }
                return (0, 0, 0, 0)
            }
            let onLine = size.x > 1 ? x == size.x / 2 + phase : y == size.y / 2 + phase
            if onLine { return (0.125, 3, 0.875, 0.625) }
            if (2 * x + y + phase) % 5 == 0 { return (0, 0, 0, 0) }
            return (Float16((x + 3 * y) % 7) / 32, 0.000002, 0.03125, 0.375)
        }
    }

    private struct Attachment {
        let width: Int
        let height: Int
        let format: Int
        let samples: Int
        let load: Int
        let token: UInt64

        init(_ record: [NSNumber]) {
            width = record[0].intValue
            height = record[1].intValue
            format = record[2].intValue
            samples = record[3].intValue
            load = record[4].intValue
            token = record[5].uint64Value
        }

        var size: [Int] { [width, height] }
    }

    private struct Rendered {
        var prepared = false
        var encoded = false
        var completed = false
        var bytes = 0
        var functionMisses = 0
        var attachments: [Attachment] = []
        var original: [Float16] = []
        var output: [Float16] = []

        var facts: [String: Any] {
            ["prepared": prepared, "encoded": encoded, "completed": completed,
             "bytes": bytes, "functionMisses": functionMisses,
             "extents": attachments.map(\.size), "loadActions": attachments.map(\.load)]
        }
    }

    static func run(device: MTLDevice, queue: MTLCommandQueue, makeTexture: MakeTexture,
                    readTexture: ReadTexture) -> [String: Any] {
        guard device.supportsFamily(.apple2) else { return ["supported": false] }
        let budget = SceneResourceBudget.shared
        let library = device.makeDefaultLibrary()!
        let entry = "sceneBloomHDRUpsampleAttachmentFragment"
        var failures: [String] = []
        var evidence: [String: Any] = [:]
        func check(_ condition: Bool, _ why: String) {
            if !condition { failures.append(why) }
        }

        typealias Source = (texture: MTLTexture, bytes: [Float16])
        func encode(_ fixture: Fixture, source: Source, bloom: SceneBloomPostProcess?,
                    command: MTLCommandBuffer) -> Rendered {
            let configuration = SceneBloomConfiguration(enabled: true, strength: 0, threshold: 9,
                tint: SIMD3(0.8, 1, 0.4), hdr: fixture.hdr)
            var result = Rendered()
            result.original = source.bytes
            let resident = budget.snapshot.residentBytes
            result.prepared = bloom?.prepareCapacity(configuration: configuration, source: source.texture) ?? false
            result.bytes = budget.snapshot.residentBytes - resident
            MWXArmEncoderFault(command, 0)
            result.encoded = bloom?.encode(configuration: configuration, source: source.texture,
                                           commandBuffer: command) ?? false
            result.attachments = MWXEncoderAttachmentTrace().map(Attachment.init)
            return result
        }

        func readback(_ result: inout Rendered, source: Source, command: MTLCommandBuffer) {
            command.waitUntilCompleted()
            result.completed = command.status == .completed && command.error == nil
            result.output = readTexture(source.texture, source.texture.width, source.texture.height)
        }

        func render(_ fixture: Fixture, rgba: [Float16], sampled: Bool) -> Rendered {
            autoreleasepool {
                MWXArmNamedMissingAttachmentFunction(library, sampled ? entry : nil)
                let bloom = SceneBloomPostProcess(device: device, pixelFormat: .rgba16Float,
                                                  hdrEnabled: true)
                let misses = Int(MWXMissingFunctionAttempts())
                MWXArmNamedMissingAttachmentFunction(library, nil)
                let source = makeTexture(fixture.size.x, fixture.size.y, rgba)
                let command = queue.makeCommandBuffer()!
                var result = encode(fixture, source: source, bloom: bloom, command: command)
                result.functionMisses = misses
                command.commit()
                readback(&result, source: source, command: command)
                return result
            }
        }

        func capacity(_ levels: [[Int]]) -> Int {
            levels.reduce(0) { bytes, size in
                let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba16Float,
                    width: size[0], height: size[1], mipmapped: false)
                descriptor.storageMode = .private
                descriptor.usage = [.renderTarget, .shaderRead]
                return bytes + device.heapTextureSizeAndAlign(descriptor: descriptor).size
            }
        }

        func checkAttachments(_ actual: Rendered, _ fixture: Fixture, sampled: Bool) {
            let levels = fixture.levels
            let reconstruct = Array(levels.dropLast().reversed())
            let expected = levels.isEmpty ? [] : levels + reconstruct + [[fixture.size.x, fixture.size.y]]
            let label = "\(fixture.name): \(sampled ? "sampled" : "attachment")"
            check(actual.attachments.map(\.size) == expected, "\(label) render extents")
            check(actual.attachments.allSatisfy { $0.format == Int(MTLPixelFormat.rgba16Float.rawValue) && $0.samples == 1 },
                  "\(label) format/sample count")
            guard !levels.isEmpty, actual.attachments.count == expected.count else { return }
            let clear = Int(MTLLoadAction.dontCare.rawValue)
            let load = Int(MTLLoadAction.load.rawValue)
            let expectedLoads = Array(repeating: clear, count: levels.count)
                + Array(repeating: sampled ? clear : load, count: reconstruct.count) + [load]
            check(actual.attachments.map(\.load) == expectedLoads, "\(label) load actions")
            let fine = actual.attachments.prefix(levels.count).dropLast().reversed().map(\.token)
            let writes = actual.attachments.dropFirst(levels.count).dropLast().map(\.token)
            let distinct = Set(actual.attachments.map(\.token)).count
            check(sampled ? distinct == expected.count : writes == fine && distinct == levels.count + 1,
                  "\(label) texture identities")
        }

        func compareOutputs(_ attachment: Rendered, _ sampled: Rendered, name: String) -> [String: Any] {
            var maxError = 0.0
            var maxULPs = 0
            var firstDifference: [String: Any]?
            var rgbTotals = [SIMD3<Double>(repeating: 0), SIMD3<Double>(repeating: 0)]
            for index in attachment.output.indices {
                let candidate = attachment.output[index]
                let reference = sampled.output[index]
                let channel = index % 4
                if channel == 3 {
                    let alpha = attachment.original[index].bitPattern
                    if candidate.bitPattern != alpha || reference.bitPattern != alpha {
                        firstDifference = firstDifference ?? ["index": index, "alpha": true]
                    }
                    continue
                }
                guard candidate.isFinite, reference.isFinite, candidate >= 0, reference >= 0 else {
                    firstDifference = firstDifference ?? ["index": index, "nonfiniteOrNegative": true]
                    continue
                }
                let ulps = abs(Int(candidate.bitPattern) - Int(reference.bitPattern))
                let absolute = abs(Double(candidate) - Double(reference))
                maxError = max(maxError, absolute)
                maxULPs = max(maxULPs, ulps)
                rgbTotals[0][channel] += Double(candidate)
                rgbTotals[1][channel] += Double(reference)
                let nearZero = max(candidate, reference) <= 0.00001
                if ulps > 2 && !(nearZero && absolute <= 0.00001) {
                    firstDifference = firstDifference ?? ["index": index, "channel": channel,
                        "attachment": Double(candidate), "sampled": Double(reference), "ulps": ulps]
                }
            }
            check(firstDifference == nil, "\(name) RGB/alpha parity")
            var row: [String: Any] = ["attachment": attachment.facts, "sampled": sampled.facts,
                "maxAbsoluteError": maxError, "maxULPs": maxULPs,
                "rgbTotals": rgbTotals.map { [$0.x, $0.y, $0.z] }]
            row["firstDifference"] = firstDifference
            return row
        }

        let even = Fixture("even-line", SIMD2(64, 32), [[32, 16], [16, 8], [8, 4]], iterations: 3.75)
        let odd = Fixture("odd-phase-peak", SIMD2(65, 33), [[32, 16], [16, 8], [8, 4], [4, 2], [2, 1], [1, 1]],
                          phase: 1)
        let cases = [
            even,
            odd,
            Fixture("large-odd-fine-edge", SIMD2(3022, 1962),
                    [[1511, 981], [755, 490], [377, 245]], iterations: 3.75, edgeBlocks: true),
            Fixture("one-column", SIMD2(1, 13), [[1, 6], [1, 3], [1, 1]]),
            Fixture("one-row", SIMD2(13, 1), [[6, 1], [3, 1], [1, 1]]),
            Fixture("uniform-DC", SIMD2(32, 16), [[16, 8], [8, 4], [4, 2]], iterations: 3,
                    threshold: 0, uniform: true),
            Fixture("large-finite", SIMD2(17, 9), [[8, 4], [4, 2], [2, 1], [1, 1]],
                    iterations: .greatestFiniteMagnitude, strength: 0.000001, threshold: 0,
                    scatter: 100_000_000),
            Fixture("zero-strength", SIMD2(17, 9), [], strength: 0),
        ]
        var controls: [String: Rendered] = [:]
        for fixture in cases {
            let rgba = fixture.rgba
            let attachment = render(fixture, rgba: rgba, sampled: false)
            let sampled = render(fixture, rgba: rgba, sampled: true)
            if fixture.name == even.name || fixture.name == odd.name { controls[fixture.name] = sampled }
            let active = !fixture.levels.isEmpty
            for (actual, isSampled) in [(attachment, false), (sampled, true)] {
                let label = "\(fixture.name): \(isSampled ? "sampled" : "attachment")"
                check(actual.prepared && actual.encoded == active && actual.completed, "\(label) command")
                check(actual.functionMisses == (isSampled ? 1 : 0), "\(label) function selection")
                check((actual.output != actual.original) == active, "\(label) actual contribution")
                checkAttachments(actual, fixture, sampled: isSampled)
            }
            let downBytes = capacity(fixture.levels)
            let savedBytes = capacity(Array(fixture.levels.dropLast()))
            check(attachment.bytes == downBytes && sampled.bytes == downBytes + savedBytes,
                  "\(fixture.name) aligned GPU quota")
            var row = compareOutputs(attachment, sampled, name: fixture.name)
            row["expectedSavedBytes"] = savedBytes
            evidence[fixture.name] = row
        }

        let held = budget.maximumBytes - budget.snapshot.residentBytes - capacity(even.levels)
        if held >= 0, budget.reserve(held, kind: .gpu) {
            let rgba = even.rgba
            let attachment = render(even, rgba: rgba, sampled: false)
            let rejections = budget.snapshot.rejectionCount
            let sampled = render(even, rgba: rgba, sampled: true)
            budget.release(held, kind: .gpu)
            check(attachment.prepared && attachment.encoded && attachment.completed,
                  "tight quota must admit attachment path")
            check(!sampled.prepared && !sampled.encoded && sampled.completed && sampled.attachments.isEmpty
                && sampled.output == sampled.original && budget.snapshot.rejectionCount > rejections,
                  "tight quota must decline sampled path without writing the source")
            evidence["tightQuota"] = ["attachment": attachment.facts, "sampled": sampled.facts]
        } else {
            failures.append("tight quota could not be established")
        }

        func checkQueuedResize() -> [String: Any] {
            let originalBytes = budget.snapshot.residentBytes
            let oldBytes = capacity(even.levels), newBytes = capacity(odd.levels)
            let bloom = SceneBloomPostProcess(device: device, pixelFormat: .rgba16Float, hdrEnabled: true)!
            let event = device.makeSharedEvent()!
            let (older, newer, heldBytes, waiting) = autoreleasepool {
                let oldSource = makeTexture(even.size.x, even.size.y, even.rgba)
                let newSource = makeTexture(odd.size.x, odd.size.y, odd.rgba)
                let oldCommand = queue.makeCommandBuffer()!
                let newCommand = queue.makeCommandBuffer()!
                oldCommand.encodeWaitForEvent(event, value: 1)
                var older = encode(even, source: oldSource, bloom: bloom, command: oldCommand)
                oldCommand.commit()
                var newer = encode(odd, source: newSource, bloom: bloom, command: newCommand)
                newCommand.commit()
                let heldBytes = budget.snapshot.residentBytes - originalBytes
                let waiting = (oldCommand.status == .committed || oldCommand.status == .scheduled)
                    && (newCommand.status == .committed || newCommand.status == .scheduled)
                event.signaledValue = 1
                readback(&older, source: oldSource, command: oldCommand)
                readback(&newer, source: newSource, command: newCommand)
                return (older, newer, heldBytes, waiting)
            }
            let completedBytes = withExtendedLifetime(bloom) { budget.snapshot.residentBytes - originalBytes }
            check(waiting && older.bytes == oldBytes && newer.bytes == newBytes && heldBytes == oldBytes + newBytes,
                  "queued resize retained both actual chains before event release")
            check(completedBytes == newBytes, "queued resize retired old capacity at GPU completion")
            let before = Set(older.attachments.map(\.token)), after = Set(newer.attachments.map(\.token))
            check(before.isDisjoint(with: after), "queued resize reused an in-flight texture for new dimensions")
            for (fixture, output) in [(even, older), (odd, newer)] {
                let label = "queued resize \(fixture.name)"
                check(output.prepared && output.encoded && output.completed, "\(label) command")
                checkAttachments(output, fixture, sampled: false)
            }
            return ["bothQueued": waiting, "oldBytes": oldBytes, "newBytes": newBytes,
                    "heldBytes": heldBytes, "completedBytes": completedBytes,
                    "oldOutput": compareOutputs(older, controls[even.name]!, name: "queued old extent"),
                    "newOutput": compareOutputs(newer, controls[odd.name]!, name: "queued new extent")]
        }

        evidence["queuedResize"] = checkQueuedResize()

        MWXArmNamedMissingAttachmentFunction(library, entry)
        let ordinary = SceneBloomPostProcess(device: device)
        check(ordinary != nil && MWXMissingFunctionAttempts() == 0, "ordinary Bloom must not look up HDR attachment")
        MWXArmNamedMissingAttachmentFunction(library, nil)
        return ["supported": true, "failures": failures, "cases": evidence]
    }
}
