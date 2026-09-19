import Foundation

/// Builds child instances from the current display-callback sample set. Rope
/// systems stay on persistent topology so particles from separate event/static
/// systems can never become adjacent rope nodes.
enum SceneParticleChildInstanceBuilder {
    /// Rebuild every template in one ordered pass over live and render-only systems.
    ///
    /// The previous per-template entry point filtered `systems` once for every
    /// template. Complex authored scenes can retain hundreds of child systems,
    /// so that turned an otherwise linear frame step into an avoidable
    /// `templates * systems` scan and allocated a short-lived matching array for
    /// each template. Templates and the index are launch-stable; only particle
    /// state and the reusable scratch buffers are frame-varying.
    static func rebuildAll(
        templates: [SceneParticleChildTemplate],
        templatesByIndex: [Int: SceneParticleChildTemplate]? = nil,
        systems: [SceneParticleChildSystem],
        renderOnlySystems: [SceneParticleChildSystem] = [],
        layerAlpha: Float,
        into scratch: inout [Int: [SceneParticleGPUInstance]]
    ) {
        let lookup = templatesByIndex ?? Dictionary(
            templates.map { ($0.index, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        for template in templates {
            scratch[template.index, default: []].removeAll(keepingCapacity: true)
        }
        if renderOnlySystems.isEmpty {
            for system in systems {
                append(system, lookup: lookup, layerAlpha: layerAlpha, into: &scratch)
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
            append(system, lookup: lookup, layerAlpha: layerAlpha, into: &scratch)
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

    /// Builds one child template at a time for focused callers and older
    /// validation harnesses. The realtime path uses `rebuildAll` above.
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
            $0 + $1.simulator.renderParticlesForCurrentAdvance().count
        })
        for system in matchingSystems {
            for particle in system.simulator.renderParticlesForCurrentAdvance() {
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
