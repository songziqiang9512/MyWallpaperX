import Foundation
import simd

/// Bounded Rope Trail support for the shape shared by current stock and
/// Workshop samples. Public renderer semantics define a per-particle path;
/// subdivision, UV animation, size fading, and non-screen orientation remain
/// closed until their geometry and sampling contracts are implemented.
nonisolated struct SceneParticleRopeTrailPlan: Equatable, Sendable {
    static let defaultSegmentCount = 4
    static let maximumSegmentCount = 8
    static let maximumLength: TimeInterval = 4
    static let maximumParticleCount = 512
    static let maximumSegmentInstanceCount = 4_096

    let length: TimeInterval
    let segmentCount: Int
    let fadesAlpha: Bool
    var stepSnapshotPolicy: SceneParticleStepSnapshotPolicy? {
        SceneParticleStepSnapshotPolicy(
            interval: length / TimeInterval(segmentCount * 4),
            maximumSnapshots: segmentCount * 4 + 4
        )
    }

    nonisolated init?(
        renderer: SceneParticleRenderer,
        rendererCount: Int,
        maximumParticleCount: Int
    ) {
        guard rendererCount == 1,
              renderer.kind == .ropeTrail,
              renderer.orientation == nil || renderer.orientation == "screen",
              renderer.axis == nil,
              renderer.rawFlags == 0,
              renderer.minimumLength == nil,
              renderer.maximumLength == nil,
              renderer.subdivision == nil,
              renderer.uvScale == nil,
              renderer.smoothsUV == nil,
              renderer.scrollsUV == nil,
              renderer.fadesSize != true,
              !renderer.hasMalformedFields,
              renderer.unsupportedFieldNames.isEmpty else {
            return nil
        }
        guard let length = renderer.length else { return nil }
        let segmentCount = renderer.segments ?? Self.defaultSegmentCount
        guard length.isFinite,
              length > 0,
              length <= Self.maximumLength,
              (1...Self.maximumSegmentCount).contains(segmentCount),
              (1...Self.maximumParticleCount).contains(maximumParticleCount),
              maximumParticleCount
                <= Self.maximumSegmentInstanceCount / segmentCount else {
            return nil
        }
        self.length = length
        self.segmentCount = segmentCount
        fadesAlpha = renderer.fadesAlpha == true
    }
}

nonisolated struct SceneParticleRopeTrailParticle: Equatable, Sendable {
    let id: UInt64
    let position: SIMD3<Float>
    let size: Float
    let color: SIMD3<Float>
    let alpha: Float

    nonisolated init(
        id: UInt64,
        position: SIMD3<Float>,
        size: Float,
        color: SIMD3<Float>,
        alpha: Float
    ) {
        self.id = id
        self.position = position
        self.size = size
        self.color = color
        self.alpha = alpha
    }
}

/// Keeps a bounded, oversampled history per live particle and converts each
/// path segment into an existing particle quad instance. Reusing that pipeline
/// preserves TEX sampling, mip selection, blend, and refraction behavior.
nonisolated struct SceneParticleRopeTrailHistory {
    private struct TimedSample {
        var time: TimeInterval
        var particle: SceneParticleRopeTrailParticle
    }

    private struct Track {
        var committed: [TimedSample]
        var current: TimedSample
    }

    private let plan: SceneParticleRopeTrailPlan
    private var elapsed: TimeInterval = 0
    private var tracks: [UInt64: Track] = [:]

    init(plan: SceneParticleRopeTrailPlan) {
        self.plan = plan
    }

    mutating func advance(
        by frameDelta: TimeInterval,
        particles: [SceneParticleRopeTrailParticle],
        layerAlpha: Float
    ) -> [SceneParticleGPUInstance] {
        let validParticles = update(by: frameDelta, particles: particles)
        let safeLayerAlpha = layerAlpha.isFinite ? min(max(layerAlpha, 0), 1) : 0
        return validParticles.flatMap { particle -> [SceneParticleGPUInstance] in
            guard let track = tracks[particle.id] else { return [] }
            return instances(for: track, layerAlpha: safeLayerAlpha)
        }
    }

    mutating func ingest(
        by frameDelta: TimeInterval,
        particles: [SceneParticleRopeTrailParticle]
    ) {
        _ = update(by: frameDelta, particles: particles)
    }

    private mutating func update(
        by frameDelta: TimeInterval,
        particles: [SceneParticleRopeTrailParticle]
    ) -> [SceneParticleRopeTrailParticle] {
        let delta = frameDelta.isFinite ? max(frameDelta, 0) : 0
        elapsed += delta
        let validParticles = particles.filter(Self.valid)
        let liveIDs = Set(validParticles.map(\.id))
        for id in tracks.keys.filter({ !liveIDs.contains($0) }) {
            tracks.removeValue(forKey: id)
        }

        for particle in validParticles {
            let sample = TimedSample(time: elapsed, particle: particle)
            if var track = tracks[particle.id] {
                commit(sample, to: &track)
                track.current = sample
                prune(&track)
                tracks[particle.id] = track
            } else {
                tracks[particle.id] = Track(committed: [sample], current: sample)
            }
        }
        return validParticles
    }

    private func commit(_ sample: TimedSample, to track: inout Track) {
        guard let latest = track.committed.last else {
            track.committed = [sample]
            return
        }
        if sample.time - latest.time >= historySampleInterval {
            track.committed.append(sample)
        } else if sample.time == latest.time {
            track.committed[track.committed.count - 1] = sample
        }
    }

    private func prune(_ track: inout Track) {
        let cutoff = elapsed - plan.length
        while track.committed.count > 2,
              track.committed[1].time < cutoff {
            track.committed.removeFirst()
        }
        let maximumSamples = plan.segmentCount * 4 + 4
        if track.committed.count > maximumSamples {
            track.committed.removeFirst(track.committed.count - maximumSamples)
        }
    }

    private var historySampleInterval: TimeInterval {
        plan.stepSnapshotPolicy?.interval ?? plan.length
    }

    private func instances(
        for track: Track,
        layerAlpha: Float
    ) -> [SceneParticleGPUInstance] {
        var samples = track.committed
        if let latest = samples.last, latest.time == track.current.time {
            samples[samples.count - 1] = track.current
        } else {
            samples.append(track.current)
        }
        guard let first = samples.first, samples.count >= 2 else { return [] }

        var nodes: [TimedSample] = [track.current]
        for index in 1...plan.segmentCount {
            let target = elapsed
                - plan.length * TimeInterval(index) / TimeInterval(plan.segmentCount)
            if target < first.time {
                if let latest = nodes.last, first.time < latest.time {
                    nodes.append(first)
                }
                break
            }
            guard let value = Self.interpolate(samples, at: target) else { break }
            nodes.append(value)
        }
        guard nodes.count >= 2 else { return [] }

        var result: [SceneParticleGPUInstance] = []
        result.reserveCapacity(nodes.count - 1)
        for index in 0..<(nodes.count - 1) {
            let newer = nodes[index]
            let older = nodes[index + 1]
            let displacement = newer.particle.position - older.particle.position
            let segmentLength = simd_length(displacement)
            let size = (newer.particle.size + older.particle.size) * 0.5
            guard segmentLength.isFinite, segmentLength > 0.0001,
                  size.isFinite, size > 0.0001 else {
                continue
            }

            let newerU = Self.normalizedTrailPosition(
                sampleTime: newer.time,
                elapsed: elapsed,
                length: plan.length
            )
            let olderU = Self.normalizedTrailPosition(
                sampleTime: older.time,
                elapsed: elapsed,
                length: plan.length
            )
            let alphaFade = plan.fadesAlpha ? (newerU + olderU) * 0.5 : 1
            let alpha = min(max(
                (newer.particle.alpha + older.particle.alpha) * 0.5
                    * layerAlpha * alphaFade,
                0
            ), 1)
            let frame = SceneParticleFrameTransform.identity.verticalTrailSlice(
                tailPosition: olderU,
                headPosition: newerU
            )
            result.append(SceneParticleGPUInstance(
                position: (newer.particle.position + older.particle.position) * 0.5,
                size: size,
                rotation: .zero,
                color: simd_max(
                    (newer.particle.color + older.particle.color) * 0.5,
                    SIMD3(repeating: 0)
                ),
                alpha: alpha,
                velocity: displacement,
                trailStretch: segmentLength / size,
                trailUVRange: SIMD2(olderU, newerU),
                usesTrailDisplacement: true,
                currentFrame: frame
            ))
        }
        return result
    }

    private static func interpolate(
        _ samples: [TimedSample],
        at target: TimeInterval
    ) -> TimedSample? {
        guard let first = samples.first, let last = samples.last,
              target >= first.time else {
            return nil
        }
        if target >= last.time {
            return last
        }
        for index in 1..<samples.count where samples[index].time >= target {
            let lower = samples[index - 1]
            let upper = samples[index]
            let duration = upper.time - lower.time
            let mix = duration > 0 ? Float((target - lower.time) / duration) : 0
            return TimedSample(
                time: target,
                particle: SceneParticleRopeTrailParticle(
                    id: upper.particle.id,
                    position: lower.particle.position
                        + (upper.particle.position - lower.particle.position) * mix,
                    size: lower.particle.size
                        + (upper.particle.size - lower.particle.size) * mix,
                    color: lower.particle.color
                        + (upper.particle.color - lower.particle.color) * mix,
                    alpha: lower.particle.alpha
                        + (upper.particle.alpha - lower.particle.alpha) * mix
                )
            )
        }
        return nil
    }

    private static func normalizedTrailPosition(
        sampleTime: TimeInterval,
        elapsed: TimeInterval,
        length: TimeInterval
    ) -> Float {
        Float(min(max(1 - (elapsed - sampleTime) / length, 0), 1))
    }

    private static func valid(_ particle: SceneParticleRopeTrailParticle) -> Bool {
        particle.position.x.isFinite
            && particle.position.y.isFinite
            && particle.position.z.isFinite
            && particle.size.isFinite && particle.size >= 0
            && particle.color.x.isFinite
            && particle.color.y.isFinite
            && particle.color.z.isFinite
            && particle.alpha.isFinite
    }
}
