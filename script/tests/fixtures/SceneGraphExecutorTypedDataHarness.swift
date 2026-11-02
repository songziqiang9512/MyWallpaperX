
@main private enum TypedDataProducerHarness {
    static func main() throws {
        setenv("MWX_SCENE_GENERIC_SHADER_ROUTE", "disable-generic", 1)
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else {
            print("{\"metalAvailable\":false}"); return
        }
        var reports: [String: Any] = [:]
        for format in ["r8", "rg88", "r16f", "rg1616f"] {
            let paired = format.hasPrefix("rg"), floating = format.hasSuffix("f")
            let content: SceneTextureContent = paired
                ? (floating ? .redGreenFloat16 : .redGreenUnorm)
                : (floating ? .scalarRedFloat16 : .scalarRedUnorm)
            let dataGraph = graph(targets: [rawTarget(first, format: format)], nodes: [
                material(0, ordinal: 0, target: first, read: input),
                material(1, ordinal: 1, target: output, read: first),
            ])
            let chain = admittedGraph(dataGraph)
            let owners = capabilities(chain, catalog: catalog(for: dataGraph,
                scalarConsumerNodes: [1: paired ? "rg" : "red"]))
            guard let claim = owners.claim(chain), let capability = owners.resolve(claim.token, for: chain),
                  let executor = Executor(device: device, capabilities: owners),
                  let producer = capability.material(for: dataGraph.nodes[0]),
                  let consumer = capability.material(for: dataGraph.nodes[1]) else {
                reports[format] = ["failure": "admission", "reports": owners.reportLines]; continue
            }
            let lease = makeLease(requirePlan(dataGraph), device: device)
            let command = queue.makeCommandBuffer()!
            let preparation = executor.prepare(token: claim.token, leases: [lease],
                historyRehydrateCopiesByEffect: [:], frame: frame(1),
                sourceTexture: makeSource(device, bgra: [191, 128, 64, 255]),
                sourceUniforms: .neutral(), sourcePipeline: makeSourcePipeline(device), frameInputs: .init(),
                commandBuffer: command, previousStates: [:], previousGraphResources: [:],
                effectGeneration: 1, resetGeneration: 1)
            guard case let .success(prepared) = preparation,
                  let publication = prepared.stages.first?.frameResources[first],
                  let stored = lease.texture(for: first),
                  executor.encode(prepared, commandBuffer: command),
                  let finalRead = appendReadback(prepared.finalTexture, commandBuffer: command),
                  let buffer = device.makeBuffer(length: 256 * stored.height, options: .storageModeShared),
                  let blit = command.makeBlitCommandEncoder() else {
                reports[format] = ["failure": failureCode(preparation)]; continue
            }
            blit.copy(from: stored, sourceSlice: 0, sourceLevel: 0, sourceOrigin: .init(x: 0, y: 0, z: 0),
                sourceSize: .init(width: stored.width, height: stored.height, depth: 1), to: buffer,
                destinationOffset: 0, destinationBytesPerRow: 256, destinationBytesPerImage: 256 * stored.height)
            blit.endEncoding(); command.commit(); command.waitUntilCompleted()
            let channels = paired ? 2 : 1, bytesPerPixel = channels * (floating ? 2 : 1)
            func pixel(_ offset: Int) -> [Float] {
                if floating {
                    let words = buffer.contents().advanced(by: offset).assumingMemoryBound(to: UInt16.self)
                    return (0..<channels).map { Float(Float16(bitPattern: words[$0])) }
                }
                let bytes = buffer.contents().advanced(by: offset).assumingMemoryBound(to: UInt8.self)
                return (0..<channels).map { Float(bytes[$0]) / 255 }
            }
            let expectedStored: [Float] = paired ? [64 / 255, 128 / 255] : [64 / 255]
            let expectedFinal: [UInt8] = paired ? [0, 128, 64, 255] : [0, 0, 64, 255]
            let consumerVariants = consumer.variants.launchEnvelopeCapabilitySnapshot().variants
            reports[format] = [
                "completed": command.status == .completed && command.error == nil,
                "producerContentAdmitted": producer.variants.launchEnvelopeOutputContent == content,
                "actualPublication": publication.publication.candidate.content == content
                    && publication.publication.candidate.purpose == .preservedChannels,
                "rawStorage": [pixel(0), pixel((stored.height - 1) * 256 + (stored.width - 1) * bytesPerPixel)]
                    .allSatisfy { zip($0, expectedStored).allSatisfy { abs($0 - $1) < 0.002 } },
                "consumerExcludesDataFromColorMask": !consumerVariants.isEmpty
                    && consumerVariants.allSatisfy { $0.frontendProgram.colorBoundary?.colorInputSlots == [] },
                "authoredFinalPixels": matches(finalRead.firstPixel, expectedFinal)
                    && matches(finalRead.lastPixel, expectedFinal),
                "noVisualFallback": prepared.stages.allSatisfy { $0.effectLocalFailureReasonCode == nil },
                "twoMaterialDraws": prepared.stages.count == 1 && prepared.stages[0].programCacheKeys.count == 2
                    && intentKinds(prepared) == ["material", "material"],
                "storedPixel": pixel(0), "finalPixel": finalRead.firstPixel,
            ]
        }
        print(String(decoding: try JSONSerialization.data(withJSONObject:
            ["metalAvailable": true, "reports": reports], options: [.sortedKeys]), as: UTF8.self))
    }
}
