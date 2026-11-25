import Foundation
import Metal

enum SceneStandardBloomResizeChecks {
    private struct Input {
        let width: Int
        let height: Int
        let levels: [[Int]]
        let bgra: [UInt8]

        init(_ width: Int, _ height: Int, _ levels: [[Int]]) {
            self.width = width
            self.height = height
            self.levels = levels
            var pixels = [UInt8](repeating: 0, count: width * height * 4)
            for y in 0..<height {
                for x in 0..<width {
                    let index = (y * width + x) * 4
                    if (width / 2 - 12..<width / 2 + 12).contains(x)
                        && (height / 2 - 10..<height / 2 + 10).contains(y) {
                        pixels[index] = 255
                        pixels[index + 1] = 255
                        pixels[index + 2] = 255
                    }
                    pixels[index + 3] = UInt8(100 + (3 * x + 5 * y) % 156)
                }
            }
            bgra = pixels
        }

        var extents: [[Int]] { levels + [levels[0], [width, height]] }

        func halo(_ pixels: [UInt8]) -> [UInt8] {
            [1, 4, 8, 16, 24].map { distance in
                pixels[(height / 2 * width + width / 2 + 11 + distance) * 4 + 2]
            }
        }
    }

    private struct Encoded {
        let source: MTLTexture
        let prepared: Bool
        let encoded: Bool
        let attachments: [[NSNumber]]

        var tokens: [UInt64] { attachments.map { $0[5].uint64Value } }
        var extents: [[Int]] { attachments.map { [$0[0].intValue, $0[1].intValue] } }
    }

    private struct Drawn {
        let work: Encoded
        let completed: Bool
        let output: [UInt8]

        func facts(_ input: Input) -> [String: Any] {
            ["prepared": work.prepared, "encoded": work.encoded, "completed": completed,
             "extents": work.extents, "halo": input.halo(output).map(Int.init),
             "intermediateTokens": Array(work.tokens.dropLast())]
        }
    }

    static func run(device: MTLDevice, queue: MTLCommandQueue) -> [String: Any] {
        let large = Input(640, 384, [[160, 96], [80, 48]])
        let small = Input(128, 84, [[32, 21], [16, 10]])
        let sameTargets = Input(131, 87, [[32, 21], [16, 10]])
        let budget = SceneResourceBudget.shared
        let cfg = SceneBloomConfiguration(enabled: true, strength: 1, threshold: 0.1,
                                          tint: SIMD3(repeating: 1))
        var failures: [String] = []
        func check(_ condition: Bool, _ why: String) {
            if !condition { failures.append(why) }
        }

        func encode(_ input: Input, bloom: SceneBloomPostProcess, command: MTLCommandBuffer) -> Encoded {
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm,
                width: input.width, height: input.height, mipmapped: false)
            descriptor.usage = [.renderTarget, .shaderRead]
            descriptor.storageMode = .shared
            let source = device.makeTexture(descriptor: descriptor)!
            input.bgra.withUnsafeBytes {
                source.replace(region: MTLRegionMake2D(0, 0, input.width, input.height), mipmapLevel: 0,
                    withBytes: $0.baseAddress!, bytesPerRow: input.width * 4)
            }
            let prepared = bloom.prepareCapacity(configuration: cfg, source: source)
            MWXArmEncoderFault(command, 0)
            let encoded = bloom.encode(configuration: cfg, source: source, commandBuffer: command)
            return .init(source: source, prepared: prepared, encoded: encoded,
                         attachments: MWXEncoderAttachmentTrace())
        }

        func readback(_ work: Encoded, command: MTLCommandBuffer) -> Drawn {
            command.waitUntilCompleted()
            let source = work.source
            var bytes = [UInt8](repeating: 0, count: source.width * source.height * 4)
            bytes.withUnsafeMutableBytes {
                source.getBytes($0.baseAddress!, bytesPerRow: source.width * 4,
                    from: MTLRegionMake2D(0, 0, source.width, source.height), mipmapLevel: 0)
            }
            return .init(work: work, completed: command.status == .completed && command.error == nil, output: bytes)
        }

        func draw(_ input: Input, bloom: SceneBloomPostProcess) -> Drawn {
            autoreleasepool {
                let command = queue.makeCommandBuffer()!
                let work = encode(input, bloom: bloom, command: command)
                command.commit()
                return readback(work, command: command)
            }
        }

        func confirm(_ drawn: Drawn, _ input: Input, _ label: String) {
            check(drawn.work.prepared && drawn.work.encoded && drawn.completed, "\(label) command")
            check(drawn.work.extents == input.extents, "\(label) real render extents")
            check(drawn.work.attachments.map { $0[4].uintValue } == [
                MTLLoadAction.dontCare.rawValue, MTLLoadAction.dontCare.rawValue,
                MTLLoadAction.dontCare.rawValue, MTLLoadAction.load.rawValue], "\(label) render load actions")
            check(input.halo(drawn.output)[1] > 0, "\(label) original black pixels received halo")
            check(drawn.output.indices.allSatisfy {
                $0 % 4 == 3 ? drawn.output[$0] == input.bgra[$0] : drawn.output[$0] >= input.bgra[$0]
            }, "\(label) source alpha and base RGB")
        }

        func fresh(_ input: Input) -> Drawn {
            autoreleasepool { draw(input, bloom: SceneBloomPostProcess(device: device)!) }
        }

        let smallControl = fresh(small)
        let sameTargetsControl = fresh(sameTargets)
        confirm(smallControl, small, "small control")
        confirm(sameTargetsControl, sameTargets, "same-target extent control")
        let expectedSmallCharge = small.levels.reduce(0) { count, level in
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm,
                width: level[0], height: level[1], mipmapped: false)
            descriptor.storageMode = .private
            descriptor.usage = [.renderTarget, .shaderRead]
            return count + device.heapTextureSizeAndAlign(descriptor: descriptor).size
        }

        let (largeReference, resize) = autoreleasepool {
            let originalBytes = budget.snapshot.residentBytes
            let owner = SceneBloomPostProcess(device: device)!
            let old = draw(large, bloom: owner)
            let largeCharge = budget.snapshot.residentBytes - originalBytes
            let held = budget.maximumBytes - budget.snapshot.residentBytes
            precondition(budget.reserve(held, kind: .gpu))
            defer { budget.release(held, kind: .gpu) }
            let changed = draw(small, bloom: owner)
            let resident = withExtendedLifetime(owner) { budget.snapshot.residentBytes - originalBytes - held }
            confirm(old, large, "completed large")
            confirm(changed, small, "completed resize under pressure")
            check(largeCharge > expectedSmallCharge && resident == expectedSmallCharge,
                  "completed resize released large targets to admit small pair")
            check(changed.output == smallControl.output, "tight small full BGRA equals roomy small")
            return (old, ["large": old.facts(large), "small": changed.facts(small),
                          "oldCharge": largeCharge, "newCharge": resident] as [String: Any])
        }

        let reused = autoreleasepool {
            let owner = SceneBloomPostProcess(device: device)!
            let event = device.makeSharedEvent()!
            let firstCommand = queue.makeCommandBuffer()!, nextCommand = queue.makeCommandBuffer()!
            firstCommand.encodeWaitForEvent(event, value: 1)
            let firstWork = encode(small, bloom: owner, command: firstCommand)
            firstCommand.commit()
            let firstCharge = budget.snapshot.residentBytes
            let nextWork = encode(sameTargets, bloom: owner, command: nextCommand)
            nextCommand.commit()
            let reusedCharge = budget.snapshot.residentBytes == firstCharge
            event.signaledValue = 1
            let first = readback(firstWork, command: firstCommand)
            let next = readback(nextWork, command: nextCommand)
            confirm(first, small, "first same-target extent")
            confirm(next, sameTargets, "same-target extent reuse")
            check(reusedCharge, "changing the physical source within the target bucket must not reserve a second pair")
            check(first.work.tokens.count == 4 && next.work.tokens.count == 4
                && first.work.tokens.dropLast() == next.work.tokens.dropLast(),
                "physical source extent changed but the intermediate identities must match")
            check(first.output == smallControl.output && next.output == sameTargetsControl.output,
                  "each reused target uses its current physical source sampling distance")
            return ["first": first.facts(small), "second": next.facts(sameTargets), "sameCharge": reusedCharge]
                as [String: Any]
        }

        let inFlight = autoreleasepool {
            let originalBytes = budget.snapshot.residentBytes
            let owner = SceneBloomPostProcess(device: device)!
            let event = device.makeSharedEvent()!
            let (old, blocked, held, residentWhileQueued, oldCharge, queued, deniedByBudget) = autoreleasepool {
                let oldCommand = queue.makeCommandBuffer()!
                let refusedCommand = queue.makeCommandBuffer()!
                oldCommand.encodeWaitForEvent(event, value: 1)
                let oldWork = encode(large, bloom: owner, command: oldCommand)
                oldCommand.commit()
                let oldCharge = budget.snapshot.residentBytes - originalBytes
                let held = budget.maximumBytes - budget.snapshot.residentBytes
                precondition(budget.reserve(held, kind: .gpu))
                let rejections = budget.snapshot.rejectionCount
                let refused = encode(small, bloom: owner, command: refusedCommand)
                refusedCommand.commit()
                let queued = oldCommand.status == .committed || oldCommand.status == .scheduled
                let residentWhileQueued = budget.snapshot.residentBytes - originalBytes - held
                let deniedByBudget = budget.snapshot.rejectionCount > rejections
                event.signaledValue = 1
                return (readback(oldWork, command: oldCommand), readback(refused, command: refusedCommand),
                        held, residentWhileQueued, oldCharge, queued, deniedByBudget)
            }
            defer { budget.release(held, kind: .gpu) }
            let retired = budget.snapshot.residentBytes - originalBytes - held
            let resumed = draw(small, bloom: owner)
            let resident = withExtendedLifetime(owner) { budget.snapshot.residentBytes - originalBytes - held }
            check(queued && oldCharge > expectedSmallCharge && residentWhileQueued == oldCharge,
                  "GPU submission retains the real old texture leases while blocked")
            check(deniedByBudget && !blocked.work.prepared && !blocked.work.encoded
                && blocked.completed && blocked.work.attachments.isEmpty && blocked.output == small.bgra,
                  "new pass cannot take in-flight capacity or alter its source")
            confirm(old, large, "previous in-flight submission")
            confirm(resumed, small, "recovered after in-flight resize")
            check(retired == 0 && resident == expectedSmallCharge, "after GPU completion the old lease returns")
            check(old.output == largeReference.output && resumed.output == smallControl.output,
                  "queued old and recovered new frames match real controls")
            return ["queued": queued, "deniedByBudget": deniedByBudget, "oldCharge": oldCharge,
                    "heldOldCharge": residentWhileQueued, "afterCompletion": retired, "newCharge": resident,
                    "old": old.facts(large), "blocked": blocked.facts(small), "resumed": resumed.facts(small)]
                as [String: Any]
        }

        return ["failures": failures, "completedResize": resize, "sameTargets": reused,
                "inFlight": inFlight, "smallControl": smallControl.facts(small),
                "sameTargetsControl": sameTargetsControl.facts(sameTargets)]
    }
}
