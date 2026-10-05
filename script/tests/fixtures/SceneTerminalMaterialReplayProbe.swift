// Included in the material-pass harness to share its authored input builders.
private func terminalReplayProbe(device: MTLDevice, queue: MTLCommandQueue) -> [String: Bool] {
    let vertex = """
    attribute vec3 a_Position;
    attribute vec2 a_TexCoord;
    varying vec2 v_TexCoord;
    uniform mat4 g_ModelViewProjectionMatrix;
    uniform mat4 g_ModelViewProjectionMatrixInverse;
    void main() {
        v_TexCoord = a_TexCoord;
        gl_Position = mul(vec4(a_Position, 1.0), g_ModelViewProjectionMatrix);
        gl_Position += mul(vec4(0.0), g_ModelViewProjectionMatrixInverse);
    }
    """
    let vertexWithoutInverse = vertex
        .replacingOccurrences(of: "uniform mat4 g_ModelViewProjectionMatrixInverse;", with: "")
        .replacingOccurrences(of: "gl_Position += mul(vec4(0.0), g_ModelViewProjectionMatrixInverse);", with: "")
    let noInverse = program(device: device, marker: 8799, outputSlot: 0,
        uniformValues: ["g_ModelViewProjectionMatrix": bytes(matrix_identity_float4x4)],
        replayVertexSource: vertexWithoutInverse)!
    let zeroScale = simd_float4x4(diagonal: SIMD4<Float>(0, 0, 1, 1))
    let input = texture(device: device, usage: [.shaderRead, .renderTarget], fill: [128,0,0,128, 128,0,0,128,
                                               128,0,0,128, 128,0,0,128])
    let material = program(device: device, marker: 8800, outputSlot: 0,
        slot0Texture: input, uniformValues: [
            "g_ModelViewProjectionMatrix": bytes(matrix_identity_float4x4),
            "g_ModelViewProjectionMatrixInverse": bytes(matrix_identity_float4x4),
        ], replayVertexSource: vertex)!
    let replay = material.terminalReplay(unitModelViewProjection: matrix_identity_float4x4)!
    let mvp = replay.resolvedUniforms.first { $0.field.authoredName == "g_ModelViewProjectionMatrix" }!
        .encodedValue.withUnsafeBytes { $0.loadUnaligned(as: simd_float4x4.self) }
    let inverse = replay.resolvedUniforms.first { $0.field.authoredName == "g_ModelViewProjectionMatrixInverse" }!
        .encodedValue.withUnsafeBytes { $0.loadUnaligned(as: simd_float4x4.self) }
    let size = replay.resolvedUniforms.first { $0.field.authoredName == "mwxRenderSize" }!
        .encodedValue.withUnsafeBytes { $0.loadUnaligned(as: SIMD2<Float>.self) }
    let target = texture(device: device, format: .bgra8Unorm, width: 16, height: 16,
                         usage: [.shaderRead, .renderTarget])
    let encoder = SceneResolvedMaterialPassEncoder(device: device)!
    let cold = encoder.prepareTerminalReplay(program: material, target: target,
        unitModelViewProjection: matrix_identity_float4x4)
    let coldRejected: Bool
    if case .failure(.compileStateKeyRejected) = cold { coldRejected = true }
    else { coldRejected = false }
    func plan(_ format: MTLPixelFormat, _ role: Program.PassRole)
        -> SceneResolvedMaterialPassEncoder.WarmupPlan {
        .init(identity: "terminal-fixture", preparedKey: material.preparedShader.cacheKey,
              frontend: material.frontendProgram, renderState: material.renderState,
              frontendSchemaVersion: material.semanticIdentity.shader.frontendSchemaVersion,
              pixelFormat: format, writeMask: .all, passRole: role, device: device)!
    }
    let coldAttempts = encoder.pipelineCompilationAttemptCount
    let report = encoder.warmup([plan(.bgra8Unorm, .offscreenOverwrite),
                                plan(.bgra8Unorm, .terminalSourceOver),
                                plan(.rgba16Float, .terminalSourceOver)])
    let attempts = encoder.pipelineCompilationAttemptCount
    let pass = try! encoder.prepareTerminalReplay(program: material, target: target,
        unitModelViewProjection: matrix_identity_float4x4).get()
    let command = queue.makeCommandBuffer()!
    let main = SceneMainPassEncoder(commandBuffer: command, target: target,
        clearColor: MTLClearColor(red: 0, green: 0, blue: 1, alpha: 1), clearEnabled: true)
    let wrongTarget = texture(device: device, format: .bgra8Unorm, width: 16, height: 16,
                              usage: [.shaderRead, .renderTarget])
    let wrongMain = SceneMainPassEncoder(commandBuffer: command, target: wrongTarget,
        clearColor: MTLClearColor(), clearEnabled: true)
    let targetRejected = !wrongMain.encodePreparedDraw { encoder.terminalDraw(pass, target: $0, commandBuffer: $1) }
    let wrongCommand = queue.makeCommandBuffer()!
    let commandRejected = !main.belongs(to: wrongCommand)
    let roleRejected = !encoder.encode(pass, commandBuffer: command)
    let success = main.encodePreparedDraw { encoder.terminalDraw(pass, target: $0, commandBuffer: $1) }
    let sharedEncoderRemainsOpen = main.encoder() != nil
    let finished = main.finishEnsuringClear()
    command.commit(); command.waitUntilCompleted()
    let rgba = pixels(target)
    let center = pixel(rgba, at: 8 * 16 + 8)!
    let outside = pixel(rgba, at: 0)!
    let sourceOver = abs(Int(center[0]) - 127) <= 1
        && center[1] == 0 && abs(Int(center[2]) - 128) <= 1 && center[3] == 255
        && outside == [255, 0, 0, 255]
    let resized = texture(device: device, format: .rgba16Float, width: 32, height: 32,
                          usage: [.shaderRead, .renderTarget])
    let resizedPass = try? encoder.prepareTerminalReplay(program: material, target: resized,
        unitModelViewProjection: matrix_identity_float4x4).get()
    let alias = encoder.prepareTerminalReplay(program: material, target: input,
        unitModelViewProjection: matrix_identity_float4x4)
    let aliasRejected: Bool
    if case .failure(.bindingsRejected) = alias { aliasRejected = true } else { aliasRejected = false }
    let clip = program(device: device, marker: 8801, outputSlot: 0)!
    let straight = program(device: device, marker: 8802, outputSlot: 0,
        slot0Content: .color(.resolved(.straightAlpha)), slot0Purpose: .straightAlbedo,
        uniformValues: ["g_ModelViewProjectionMatrix": bytes(matrix_identity_float4x4),
                        "g_ModelViewProjectionMatrixInverse": bytes(matrix_identity_float4x4)],
        replayVertexSource: vertex)!
    let straightResult = encoder.prepareTerminalReplay(program: straight, target: target,
        unitModelViewProjection: matrix_identity_float4x4)
    let straightRejected: Bool
    if case .failure(.fragmentOutputRejected) = straightResult { straightRejected = true }
    else { straightRejected = false }
    encoder.reset()
    let staleCommand = queue.makeCommandBuffer()!
    let staleMain = SceneMainPassEncoder(commandBuffer: staleCommand, target: target,
        clearColor: MTLClearColor(), clearEnabled: true)
    let staleRejected = !staleMain.encodePreparedDraw { encoder.terminalDraw(pass, target: $0, commandBuffer: $1) }
    let encodedModel = try! JSONEncoder().encode(material.frontendProgram)
    var oldObject = try! JSONSerialization.jsonObject(with: encodedModel) as! [String: Any]
    oldObject.removeValue(forKey: "vertexPositionInput")
    let oldModel = try! JSONDecoder().decode(SceneAuthoredShaderProgram.self,
        from: JSONSerialization.data(withJSONObject: oldObject))
    let archiveOriginal = SceneResolvedMaterialPipelineBinaryArchive.keyDigest(
        frontend: material.frontendProgram, renderState: material.renderState,
        pixelFormat: .bgra8Unorm, sampleCount: 1, writeMask: .all, device: device)
    let archiveTerminal = SceneResolvedMaterialPipelineBinaryArchive.keyDigest(
        frontend: material.frontendProgram, renderState: material.renderState,
        pixelFormat: .bgra8Unorm, sampleCount: 1, writeMask: .all,
        passRole: .terminalSourceOver, device: device)
    return [
        "terminalColdCacheRejectsWithoutFrameCompilation": coldRejected && coldAttempts == 0,
        "terminalRolesAndFormatsWarmSeparately": report.uniqueKeyCount == 3 && report.readyKeyCount == 3,
        "terminalNoFrameCompilation": encoder.pipelineCompilationAttemptCount == attempts,
        "terminalPreservesFrozenProgram": replay.semanticIdentity == material.semanticIdentity
            && replay.exactIdentity != material.exactIdentity
            && replay.exactIdentity.uniformBytes == replay.uniformBytes
            && replay.exactIdentity.textureSlots == material.exactIdentity.textureSlots
            && replay.preparedShader == material.preparedShader && input.width == 2 && size == SIMD2<Float>(2, 2),
        "terminalZeroScaleOnlyRequiresConsumedInverse":
            noInverse.terminalReplay(unitModelViewProjection: zeroScale) != nil
            && material.terminalReplay(unitModelViewProjection: zeroScale) == nil,
        "terminalMatrixAndInverse": mvp[0][0] == 0.5 && mvp[1][1] == 0.5
            && inverse[0][0] == 2 && inverse[1][1] == 2,
        "terminalClipAndSingularRejected": clip.terminalReplay(unitModelViewProjection: matrix_identity_float4x4) == nil
            && material.terminalReplay(unitModelViewProjection: simd_float4x4()) == nil,
        "terminalSourceOverAndPlacement": success && sharedEncoderRemainsOpen && finished
            && command.status == .completed && sourceOver,
        "terminalResizeUsesPreparedFormat": resizedPass != nil,
        "terminalTargetAndCommandIdentity": targetRejected && commandRejected && roleRejected,
        "terminalBindingsAndColorRejected": aliasRejected && straightRejected,
        "terminalStaleRejected": staleRejected,
        "terminalLegacyModelNotAdmitted": !oldModel.supportsTerminalMaterialReplay,
        "terminalPersistentRoleIdentity": archiveOriginal != nil && archiveTerminal != archiveOriginal,
    ]
}
