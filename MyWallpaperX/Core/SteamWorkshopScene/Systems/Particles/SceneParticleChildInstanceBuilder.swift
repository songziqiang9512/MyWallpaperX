import Foundation

/// Builds child instances from the current display-callback sample set. Rope
/// systems stay on persistent topology so particles from separate event/static
/// systems can never become adjacent rope nodes.
enum SceneParticleChildInstanceBuilder {
    /// Rebuild all templates in authored system order using the prepared index
    /// and reusable per-template instance storage.
    static func rebuildAll(
        templates: [SceneParticleChildTemplate],
        templatesByIndex: [Int: SceneParticleChildTemplate],
        systems: [SceneParticleChildSystem],
        renderOnlySystems: [SceneParticleChildSystem] = [],
        layerAlpha: Float,
        into scratch: inout [Int: [SceneParticleGPUInstance]]
    ) {
        for template in templates {
            scratch[template.index, default: []].removeAll(keepingCapacity: true)
        }
        if renderOnlySystems.isEmpty {
            for system in systems {
                append(system, lookup: templatesByIndex, layerAlpha: layerAlpha, into: &scratch)
            }
            return
        }

        // Both inputs are ordered by the monotonic child-system identity. Merge
        // without constructing a combined per-frame array so retirement does not
        // change authored instance order.
        var liveIndex = 0
        var renderOnlyIndex = 0
        while liveIndex < systems.count || renderOnlyIndex < renderOnlySystems.count {
            let useLive = renderOnlyIndex >= renderOnlySystems.count
                || (liveIndex < systems.count
                    && systems[liveIndex].id < renderOnlySystems[renderOnlyIndex].id)
            let system: SceneParticleChildSystem
            if useLive {
                system = systems[liveIndex]
                liveIndex += 1
            } else {
                system = renderOnlySystems[renderOnlyIndex]
                renderOnlyIndex += 1
            }
            append(system, lookup: templatesByIndex, layerAlpha: layerAlpha, into: &scratch)
        }
    }

    private static func append(
        _ system: SceneParticleChildSystem,
        lookup: [Int: SceneParticleChildTemplate],
        layerAlpha: Float,
        into scratch: inout [Int: [SceneParticleGPUInstance]]
    ) {
        guard let template = lookup[system.templateIndex] else { return }
        if let rope = template.rope {
            scratch[template.index, default: []].append(contentsOf: rope.instances(
                particles: system.simulator.particles,
                origin: system.origin,
                particleOrigins: system.isWorldSpace ? system.particleOrigins : [:],
                layerAlpha: layerAlpha,
                simulationTime: system.simulator.simulationTime
            ))
            return
        }
        for particle in system.simulator.renderParticlesForCurrentAdvance() {
            scratch[template.index, default: []].append(template.instance(
                origin: system.isWorldSpace
                    ? system.particleOrigins[particle.id] ?? system.origin
                    : system.origin,
                particle: particle,
                layerAlpha: layerAlpha
            ))
        }
    }

}
