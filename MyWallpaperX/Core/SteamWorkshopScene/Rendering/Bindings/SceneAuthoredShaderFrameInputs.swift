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
    /// Producer generation carried through the authored frame snapshot so
    /// evidence can join a consumed uniform to the exact published input.
    let generation: UInt64

    init(
        left16: [Float],
        right16: [Float],
        left32: [Float],
        right32: [Float],
        left64: [Float],
        right64: [Float],
        generation: UInt64 = 0
    ) {
        self.left16 = left16
        self.right16 = right16
        self.left32 = left32
        self.right32 = right32
        self.left64 = left64
        self.right64 = right64
        self.generation = generation
    }

    static let silent = Self(
        left16: Array(repeating: 0, count: 16),
        right16: Array(repeating: 0, count: 16),
        left32: Array(repeating: 0, count: 32),
        right32: Array(repeating: 0, count: 32),
        left64: Array(repeating: 0, count: 64),
        right64: Array(repeating: 0, count: 64),
        generation: 0
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
    let lighting: SceneAuthoredShaderLightingInputs

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
        audioSpectrum: SceneAuthoredShaderAudioSpectrumInputs = .silent,
        lighting: SceneAuthoredShaderLightingInputs = .unavailable
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
        self.lighting = lighting
    }
}

/// Public quad attributes before the authored vertex body runs. Geometry
/// preparation supplies author UVs; every ordinary card shares the unit default.
nonisolated struct SceneShaderQuadCoordinates: Equatable, Hashable, Sendable {
    let p0: SIMD2<Float>
    let p1: SIMD2<Float>
    let p2: SIMD2<Float>
    let p3: SIMD2<Float>

    static let unit = Self(p0: .init(0, 0), p1: .init(1, 0),
                           p2: .init(1, 1), p3: .init(0, 1))

    /// Keep the established triangle-strip order in both shader backends.
    var packed01: SIMD4<Float> { .init(p3.x, p3.y, p2.x, p2.y) }
    var packed23: SIMD4<Float> { .init(p0.x, p0.y, p1.x, p1.y) }
}

nonisolated struct SceneAuthoredShaderUniformInputs {
    let frameIndex: UInt64
    let renderSize: CGSize
    let screenSize: CGSize
    let modelViewProjection: simd_float4x4
    let layerModelMatrix: simd_float4x4
    let effectUnitModelMatrix: simd_float4x4?
    let effectOutputModelViewProjection: simd_float4x4
    let effectTextureProjectionMatrixInverse: simd_float4x4
    let effectDrawAlpha: Float
    let effectDrawColor: SIMD3<Float>
    let sceneTime: Float
    let dayTime: Float
    let frameTime: Float
    let pointerCurrentNDC: SIMD2<Float>
    let pointerPreviousNDC: SIMD2<Float>
    let pointerPrimaryButtonDown: Bool
    let parallaxPositionNDC: SIMD2<Float>
    let audioSpectrum: SceneAuthoredShaderAudioSpectrumInputs
    let lighting: SceneAuthoredShaderLightingInputs
    let vertexCoordinates: SceneShaderQuadCoordinates
    let vertexInputSize: CGSize?

    init(
        frameIndex: UInt64,
        renderSize: CGSize,
        screenSize: CGSize,
        modelViewProjection: simd_float4x4,
        layerModelMatrix: simd_float4x4,
        effectUnitModelMatrix: simd_float4x4? = nil,
        effectOutputModelViewProjection: simd_float4x4,
        effectTextureProjectionMatrixInverse: simd_float4x4,
        effectDrawAlpha: Float = 1,
        effectDrawColor: SIMD3<Float> = .init(repeating: 1),
        sceneTime: Float,
        dayTime: Float,
        frameTime: Float,
        pointerCurrentNDC: SIMD2<Float>,
        pointerPreviousNDC: SIMD2<Float>,
        pointerPrimaryButtonDown: Bool = false,
        parallaxPositionNDC: SIMD2<Float> = .zero,
        audioSpectrum: SceneAuthoredShaderAudioSpectrumInputs = .silent,
        lighting: SceneAuthoredShaderLightingInputs = .unavailable,
        vertexCoordinates: SceneShaderQuadCoordinates = .unit,
        vertexInputSize: CGSize? = nil
    ) {
        self.frameIndex = frameIndex
        self.renderSize = renderSize
        self.vertexCoordinates = vertexCoordinates
        self.vertexInputSize = vertexInputSize
        self.screenSize = screenSize
        self.modelViewProjection = modelViewProjection
        self.layerModelMatrix = layerModelMatrix
        self.effectUnitModelMatrix = effectUnitModelMatrix
        self.effectOutputModelViewProjection =
            effectOutputModelViewProjection
        self.effectTextureProjectionMatrixInverse = effectTextureProjectionMatrixInverse
        self.effectDrawAlpha = effectDrawAlpha
        self.effectDrawColor = effectDrawColor
        self.sceneTime = sceneTime
        self.dayTime = dayTime
        self.frameTime = frameTime
        self.pointerCurrentNDC = pointerCurrentNDC
        self.pointerPreviousNDC = pointerPreviousNDC
        self.pointerPrimaryButtonDown = pointerPrimaryButtonDown
        self.parallaxPositionNDC = parallaxPositionNDC
        self.audioSpectrum = audioSpectrum
        self.lighting = lighting
    }
}
