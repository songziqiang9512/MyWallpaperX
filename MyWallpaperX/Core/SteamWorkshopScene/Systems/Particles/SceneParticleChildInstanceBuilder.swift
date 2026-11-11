import Foundation

/// Builds child instances from the current display-callback sample set. Rope
/// systems stay on persistent topology so particles from separate event/static
/// systems can never become adjacent rope nodes.
enum SceneParticleChildInstanceBuilder {
    /// Rebuild all templates in authored system order using the prepared index
    /// and reusable per-renderer instance storage.
    static func rebuildAll(
        templates: [SceneParticleChildTemplate],
        templatesByIndex: [Int: SceneParticleChildTemplate],
        systems: [SceneParticleChildSystem],
        renderOnlySystems: [SceneParticleChildSystem] = [],
        layerAlpha: Float,
        rootTranslationOffset: SIMD3<Double> = .zero,
        into scratch: inout [SceneParticleChildRendererKey: [SceneParticleGPUInstance]]
    ) {
        for template in templates {
            for renderer in template.renderers {
                let key = SceneParticleChildRendererKey(
                    templateIndex: template.index, rendererIndex: renderer.index
                )
                scratch[key, default: []].removeAll(keepingCapacity: true)
            }
        }
        if renderOnlySystems.isEmpty {
            for system in systems {
                append(system, lookup: templatesByIndex, layerAlpha: layerAlpha, rootTranslationOffset: rootTranslationOffset, into: &scratch)
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
            append(system, lookup: templatesByIndex, layerAlpha: layerAlpha, rootTranslationOffset: rootTranslationOffset, into: &scratch)
        }
    }

    static func batches(
        templates: [SceneParticleChildTemplate],
        layerID: Int,
        scratch: [SceneParticleChildRendererKey: [SceneParticleGPUInstance]]
    ) -> [SceneParticleDrawBatch] {
        var batches: [SceneParticleDrawBatch] = []
        batches.reserveCapacity(scratch.count)
        for template in templates {
            for renderer in template.renderers {
                let key = SceneParticleChildRendererKey(
                    templateIndex: template.index, rendererIndex: renderer.index
                )
                guard let instances = scratch[key], !instances.isEmpty else { continue }
                batches.append(renderer.drawBatch(
                    layerID: layerID, particlePath: template.path,
                    childTemplateIndex: template.index, instances: instances,
                    sizeIsWorldSpace: template.definition.flags.isWorldSpace
                ))
            }
        }
        return batches
    }

    private static func append(
        _ system: SceneParticleChildSystem,
        lookup: [Int: SceneParticleChildTemplate],
        layerAlpha: Float,
        rootTranslationOffset: SIMD3<Double>,
        into scratch: inout [SceneParticleChildRendererKey: [SceneParticleGPUInstance]]
    ) {
        guard let template = lookup[system.templateIndex] else { return }
        let origin = system.origin + (system.isWorldSpace ? .zero : rootTranslationOffset)
        let currentParticles = template.renderers.contains { $0.rope != nil }
            ? system.simulator.particles.liveArray : []
        let particles = template.renderers.contains { $0.rope == nil }
            ? system.simulator.renderParticlesForCurrentAdvance() : []
        for renderer in template.renderers {
            let key = SceneParticleChildRendererKey(
                templateIndex: template.index, rendererIndex: renderer.index
            )
            if let rope = renderer.rope {
                scratch[key, default: []].append(contentsOf: rope.instances(
                    particles: currentParticles,
                    origin: origin,
                    particleOrigins: system.isWorldSpace ? system.particleOrigins : [:],
                    scale: template.transform.scale,
                    layerAlpha: layerAlpha,
                    simulationTime: system.simulator.simulationTime
                ))
                continue
            }
            for particle in particles {
                scratch[key, default: []].append(template.instance(
                    renderer: renderer,
                    origin: system.isWorldSpace
                        ? system.particleOrigins[particle.id] ?? origin
                        : origin,
                    particle: particle,
                    layerAlpha: layerAlpha
                ))
            }
        }
    }

}
