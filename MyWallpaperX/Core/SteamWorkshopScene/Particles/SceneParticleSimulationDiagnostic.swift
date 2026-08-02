import Foundation

nonisolated enum SceneParticleSimulationDiagnosticKind: String, Hashable, Sendable {
    case unsupportedEmitter
    case unsupportedInitializer
    case unsupportedOperator
    case boidsBounded
    case boidsUnsupported
    case vortexBounded
    case vortexUnsupported
    case capVelocityBounded
    case capVelocityUnsupported
    case controlPointForceBounded
    case controlPointForceUnsupported
    case unsupportedRenderer
    case trailRendererIgnored
    case childSystemsIgnored
    case dynamicOverrideIgnored
    case audioResponseIgnored
    case periodicEmissionBounded
    case periodicEmissionUnsupported
    case emitterDelayBounded
    case emitterDelayUnsupported
    case controlPointEmitterBounded
    case controlPointEmitterUnsupported
    case controlPointEmitterAnglesBounded
    case controlPointEmitterAnglesUnsupported
    case emitterSpeedBounded
    case emitterSpeedUnsupported
    case emitterShapeBounded
    case emitterShapeUnsupported
    case pointerControlPointBounded
    case pointerControlPointUnsupported
}

nonisolated struct SceneParticleSimulationDiagnostic: Hashable, Sendable {
    let kind: SceneParticleSimulationDiagnosticKind
    let componentName: String?
}
