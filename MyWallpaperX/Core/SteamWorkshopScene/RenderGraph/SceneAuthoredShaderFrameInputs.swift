import CoreGraphics
import Foundation
import simd

nonisolated struct SceneAuthoredShaderAudioSpectrumInputs: Equatable, Sendable {
    let left16: [Float]
    let right16: [Float]
    let left32: [Float]
    let right32: [Float]
    let left64: [Float]
    let right64: [Float]

    static let silent = Self(
        left16: Array(repeating: 0, count: 16),
        right16: Array(repeating: 0, count: 16),
        left32: Array(repeating: 0, count: 32),
        right32: Array(repeating: 0, count: 32),
        left64: Array(repeating: 0, count: 64),
        right64: Array(repeating: 0, count: 64)
    )
}

nonisolated struct SceneAuthoredShaderFrameInputs {
    let frameIndex: UInt64
    let screenSize: CGSize
    let sceneTime: Float
    let dayTime: Float
    let frameTime: Float
    let pointerCurrentNDC: SIMD2<Float>
    let pointerPreviousNDC: SIMD2<Float>
    let pointerPrimaryButtonDown: Bool
    let parallaxPositionNDC: SIMD2<Float>
    let audioSpectrum: SceneAuthoredShaderAudioSpectrumInputs

    init(
        frameIndex: UInt64,
        screenSize: CGSize,
        sceneTime: Float,
        dayTime: Float,
        frameTime: Float,
        pointerCurrentNDC: SIMD2<Float>,
        pointerPreviousNDC: SIMD2<Float>,
        pointerPrimaryButtonDown: Bool = false,
        parallaxPositionNDC: SIMD2<Float> = .zero,
        audioSpectrum: SceneAuthoredShaderAudioSpectrumInputs = .silent
    ) {
        self.frameIndex = frameIndex
        self.screenSize = screenSize
        self.sceneTime = sceneTime
        self.dayTime = dayTime
        self.frameTime = frameTime
        self.pointerCurrentNDC = pointerCurrentNDC
        self.pointerPreviousNDC = pointerPreviousNDC
        self.pointerPrimaryButtonDown = pointerPrimaryButtonDown
        self.parallaxPositionNDC = parallaxPositionNDC
        self.audioSpectrum = audioSpectrum
    }
}

nonisolated struct SceneAuthoredShaderUniformInputs {
    let frameIndex: UInt64
    let renderSize: CGSize
    let screenSize: CGSize
    let modelViewProjection: simd_float4x4
    let layerModelMatrix: simd_float4x4
    let effectTextureProjectionMatrix: simd_float4x4
    let effectTextureProjectionMatrixInverse: simd_float4x4
    let sceneTime: Float
    let dayTime: Float
    let frameTime: Float
    let pointerCurrentNDC: SIMD2<Float>
    let pointerPreviousNDC: SIMD2<Float>
    let pointerPrimaryButtonDown: Bool
    let parallaxPositionNDC: SIMD2<Float>
    let texturePhysicalSizes: [Int: CGSize]
    let audioSpectrum: SceneAuthoredShaderAudioSpectrumInputs

    init(
        frameIndex: UInt64,
        renderSize: CGSize,
        screenSize: CGSize,
        modelViewProjection: simd_float4x4,
        layerModelMatrix: simd_float4x4,
        effectTextureProjectionMatrix: simd_float4x4 = matrix_identity_float4x4,
        effectTextureProjectionMatrixInverse: simd_float4x4,
        sceneTime: Float,
        dayTime: Float,
        frameTime: Float,
        pointerCurrentNDC: SIMD2<Float>,
        pointerPreviousNDC: SIMD2<Float>,
        pointerPrimaryButtonDown: Bool = false,
        parallaxPositionNDC: SIMD2<Float> = .zero,
        texturePhysicalSizes: [Int: CGSize],
        audioSpectrum: SceneAuthoredShaderAudioSpectrumInputs = .silent
    ) {
        self.frameIndex = frameIndex
        self.renderSize = renderSize
        self.screenSize = screenSize
        self.modelViewProjection = modelViewProjection
        self.layerModelMatrix = layerModelMatrix
        self.effectTextureProjectionMatrix = effectTextureProjectionMatrix
        self.effectTextureProjectionMatrixInverse = effectTextureProjectionMatrixInverse
        self.sceneTime = sceneTime
        self.dayTime = dayTime
        self.frameTime = frameTime
        self.pointerCurrentNDC = pointerCurrentNDC
        self.pointerPreviousNDC = pointerPreviousNDC
        self.pointerPrimaryButtonDown = pointerPrimaryButtonDown
        self.parallaxPositionNDC = parallaxPositionNDC
        self.texturePhysicalSizes = texturePhysicalSizes
        self.audioSpectrum = audioSpectrum
    }
}
