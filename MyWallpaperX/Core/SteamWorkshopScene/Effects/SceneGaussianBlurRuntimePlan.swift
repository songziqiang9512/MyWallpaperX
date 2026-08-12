import Foundation

struct SceneGaussianBlurPlan {
    let horizontalStep: Float
    let verticalStep: Float
    let sampleResolutionScale: Float
    let isPrecise: Bool
    let kernel: SceneGaussianBlurKernel

    nonisolated init(
        horizontalStep: Float,
        verticalStep: Float,
        sampleResolutionScale: Float,
        isPrecise: Bool,
        kernel: SceneGaussianBlurKernel = .large
    ) {
        self.horizontalStep = horizontalStep
        self.verticalStep = verticalStep
        self.sampleResolutionScale = sampleResolutionScale
        self.isPrecise = isPrecise
        self.kernel = kernel
    }
}
