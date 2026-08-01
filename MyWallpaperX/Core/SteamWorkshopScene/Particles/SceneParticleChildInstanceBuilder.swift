import Foundation

/// Builds one child template at a time. Rope systems stay isolated so particles
/// from separate event/static systems can never become adjacent rope nodes.
enum SceneParticleChildInstanceBuilder {
    static func rebuild(
        template: SceneParticleChildTemplate,
        systems: [SceneParticleChildSystem],
        layerAlpha: Float,
        into instances: inout [SceneParticleGPUInstance]
    ) {
        instances.removeAll(keepingCapacity: true)
        let matchingSystems = systems.filter { $0.templateIndex == template.index }
        if let rope = template.rope {
            instances.reserveCapacity(matchingSystems.reduce(0) { count, system in
                count + max(system.simulator.particles.count - 1, 0)
                    * (rope.subdivisionCount + 1)
            })
            for system in matchingSystems {
                instances.append(contentsOf: rope.instances(
                    particles: system.simulator.particles,
                    origin: system.origin,
                    particleOrigins: system.isWorldSpace ? system.particleOrigins : [:],
                    layerAlpha: layerAlpha,
                    simulationTime: system.simulator.simulationTime
                ))
            }
            return
        }

        instances.reserveCapacity(matchingSystems.reduce(0) {
            $0 + $1.simulator.particles.count
        })
        for system in matchingSystems {
            for particle in system.simulator.particles {
                instances.append(template.instance(
                    origin: system.isWorldSpace
                        ? system.particleOrigins[particle.id] ?? system.origin
                        : system.origin,
                    particle: particle,
                    layerAlpha: layerAlpha
                ))
            }
        }
    }
}
