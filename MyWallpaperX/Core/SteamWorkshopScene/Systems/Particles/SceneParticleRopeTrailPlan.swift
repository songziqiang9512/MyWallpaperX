import Foundation
import simd

/// Bounded Rope Trail support for the shape shared by current stock and
/// Workshop samples. Public renderer semantics define a per-particle path;
/// UV animation, size fading, and non-screen orientation remain
/// closed until their geometry and sampling contracts are implemented.
nonisolated struct SceneParticleRopeTrailPlan: Equatable, Sendable {
    static let defaultSegmentCount = 4
    static let maximumHistorySampleCount = 262_144
    static let maximumSegmentInstanceCount = 65_536

    let length: TimeInterval
    let segmentCount: Int
    let subdivision: Int
    var renderSegmentCount: Int { segmentCount * (subdivision + 1) }
    /// Upper bound for the drawable segments of one particle. The authored
    /// segment/subdivision pair decides how densely the prepared history is
    /// sampled; a curved path still needs enough drawable nodes so that the
    /// polyline does not show its corners.
    let maximumSegmentsPerParticle: Int
    let fadesAlpha: Bool
    /// Whole-layer budget for live + retired tracks, derived from the same
    /// frozen constants as the admission guard: no more tracks than the
    /// history-sample budget admits at each track's per-track sample
    /// ceiling, and no more than the segment-instance budget admits at
    /// each track's drawable maximum. Retirement is a drain window, not a
    /// second unbounded population: under short-lived, high-rate churn the
    /// oldest retired ribbons are evicted early so the combined track
    /// count, emitted instances, and history memory stay bounded.
    var maximumTotalTrackCount: Int {
        min(
            Self.maximumHistorySampleCount / (renderSegmentCount * 4 + 4),
            Self.maximumSegmentInstanceCount / maximumSegmentsPerParticle
        )
    }
    var stepSnapshotPolicy: SceneParticleStepSnapshotPolicy? {
        SceneParticleStepSnapshotPolicy(
            interval: length / TimeInterval(renderSegmentCount * 4),
            maximumSnapshots: renderSegmentCount * 4 + 4
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
        guard let subdivision = Int(exactly: renderer.subdivision ?? 1),
              subdivision >= 0,
              subdivision < Self.maximumSegmentInstanceCount,
              segmentCount > 0,
              segmentCount <= Self.maximumSegmentInstanceCount / (subdivision + 1) else {
            return nil
        }
        let renderSegmentCount = segmentCount * (subdivision + 1)
        guard length.isFinite,
              length > 0,
              segmentCount > 0,
              renderSegmentCount <= (Self.maximumHistorySampleCount - 4) / 4,
              length / TimeInterval(renderSegmentCount * 4) > 0,
              maximumParticleCount > 0,
              maximumParticleCount
                <= Self.maximumHistorySampleCount / (renderSegmentCount * 4 + 4),
              maximumParticleCount
                <= Self.maximumSegmentInstanceCount / renderSegmentCount else {
            return nil
        }
        self.length = length
        self.segmentCount = segmentCount
        self.subdivision = subdivision
        maximumSegmentsPerParticle = min(
            renderSegmentCount * 4 + 4,
            max(renderSegmentCount, Self.maximumSegmentInstanceCount / maximumParticleCount)
        )
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
        var position: SIMD3<Float>
    }

    private struct Track {
        var committed: [TimedSample]
        var current: TimedSample
        var appearance: SceneParticleRopeTrailParticle
        /// Dead-particle retirement. Retired tracks stop appending samples
        /// and drain inside the authored retention window instead of
        /// disappearing at the frame the particle died.
        var isRetired: Bool = false
    }

    private let plan: SceneParticleRopeTrailPlan
    private var elapsed: TimeInterval = 0
    private var tracks: [UInt64: Track] = [:]
    /// Retired track ids in retirement order. Kept as an explicit sequence so
    /// ghost emission stays deterministic across replayed frames.
    private var retiredIDs: [UInt64] = []

    init(plan: SceneParticleRopeTrailPlan) {
        self.plan = plan
    }

    /// Bounded-state evidence: the combined live + retired track
    /// population and the retired drain depth.
    mutating func clear(keepingCapacity: Bool = true) {
        tracks.removeAll(keepingCapacity: keepingCapacity)
        retiredIDs.removeAll(keepingCapacity: keepingCapacity)
    }

    var totalTrackCount: Int { tracks.count }
    var retiredTrackCount: Int { retiredIDs.count }

    mutating func advance(
        by frameDelta: TimeInterval,
        particles: [SceneParticleRopeTrailParticle],
        layerAlpha: Float
    ) -> [SceneParticleGPUInstance] {
        let validParticles = update(by: frameDelta, particles: particles)
        let safeLayerAlpha = layerAlpha.isFinite ? min(max(layerAlpha, 0), 1) : 0
        let liveIDs = Set(validParticles.map(\.id))
        var result: [SceneParticleGPUInstance] = []
        result.reserveCapacity(validParticles.count + retiredIDs.count)
        for particle in validParticles {
            guard let track = tracks[particle.id] else { continue }
            result.append(contentsOf: instances(
                for: track, layerAlpha: safeLayerAlpha
            ))
        }
        // Retired ribbons keep emitting their draining remainder so a dead
        // particle's tail fades out along the retention window instead of
        // vanishing with the particle. Ids that are live again are skipped
        // defensively: update() un-retires revived tracks, so the same
        // geometry is emitted exactly once.
        for id in retiredIDs where !liveIDs.contains(id) {
            guard let track = tracks[id] else { continue }
            result.append(contentsOf: instances(
                for: track, layerAlpha: safeLayerAlpha
            ))
        }
        return result
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
        // Revival is an explicit transition recorded in the same value as
        // retirement, so a rolled-back frame restores both flags together: a
        // retired id that is live again this frame rejoins the appending path
        // and emits exactly once, instead of staying in the retired queue and
        // being double-emitted until the particle dies again.
        var stillRetiredIDs: [UInt64] = []
        stillRetiredIDs.reserveCapacity(retiredIDs.count)
        for id in retiredIDs {
            guard liveIDs.contains(id) else {
                stillRetiredIDs.append(id)
                continue
            }
            if var track = tracks[id] {
                track.isRetired = false
                tracks[id] = track
            }
        }
        retiredIDs = stillRetiredIDs
        // Death is a simulation result, so retirement is derived from the same
        // live-id set on every update: a rolled-back frame that revives the
        // particle restores this whole history value and the track resumes
        // appending, while replaying the death re-retires at the same elapsed
        // time. Retired tracks stop appending and age out tail-first under the
        // authored retention window; once the newest recorded sample has left
        // the window the track is fully drained and removed. Same-frame deaths
        // enter the queue in ascending id order so ghost drain order never
        // depends on dictionary iteration order.
        for id in tracks.keys.filter({ !liveIDs.contains($0) }).sorted() {
            guard var track = tracks[id], !track.isRetired else { continue }
            track.isRetired = true
            tracks[id] = track
            retiredIDs.append(id)
        }
        while let front = retiredIDs.first,
              let track = tracks[front],
              track.current.time + plan.length <= elapsed {
            retiredIDs.removeFirst()
            tracks.removeValue(forKey: front)
        }

        for particle in validParticles {
            let sample = TimedSample(time: elapsed, position: particle.position)
            if var track = tracks[particle.id] {
                commit(sample, to: &track)
                track.current = sample
                track.appearance = particle
                prune(&track)
                tracks[particle.id] = track
            } else {
                tracks[particle.id] = Track(committed: [sample], current: sample, appearance: particle)
            }
        }
        // Total-track budget, enforced at the end of the update so the
        // frame-exit population (including this frame's births) is what
        // stays bounded. Retirement under churn (short lifetimes, high
        // emission, long retention window) accumulates ghosts far beyond
        // the live-particle count the plan was admitted with, so the
        // oldest retired ribbons are evicted deterministically once the
        // combined population exceeds the whole-layer budget. Live tracks
        // are never evicted: the admission guard already bounds them by
        // maximumParticleCount, which is itself inside this budget.
        while tracks.count > plan.maximumTotalTrackCount,
              let oldest = retiredIDs.first {
            retiredIDs.removeFirst()
            tracks.removeValue(forKey: oldest)
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
        let maximumSamples = plan.renderSegmentCount * 4 + 4
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

        // Refine the actual simulated path instead of inventing a curve that
        // can overshoot it. Drawable nodes come from the prepared history
        // samples so a curved path keeps its curvature; the authored
        // segments/subdivision pair only decides how densely that history is
        // sampled. Shared endpoint joins below keep coverage continuous.
        var nodes: [TimedSample] = [track.current]
        let oldest = elapsed - plan.length
        for sample in samples.dropLast().reversed() {
            guard sample.time > oldest else { break }
            guard let previous = nodes.last, sample.time < previous.time else { continue }
            nodes.append(sample)
        }
        if let last = nodes.last, last.time > oldest {
            var upperSampleIndex = samples.count - 1
            if let value = Self.interpolate(samples, at: oldest, upperIndex: &upperSampleIndex) {
                nodes.append(value)
            } else if first.time < last.time {
                nodes.append(first)
            }
        }
        // Keep one drawable segment budget for the whole layer.
        let allowedNodes = plan.maximumSegmentsPerParticle + 1
        if nodes.count > allowedNodes {
            let stride = Int(
                (Double(nodes.count - 1) / Double(max(allowedNodes - 1, 1))).rounded(.up)
            )
            var thinned: [TimedSample] = []
            thinned.reserveCapacity(allowedNodes)
            var index = 0
            while index < nodes.count {
                thinned.append(nodes[index])
                index += max(stride, 1)
            }
            if let last = nodes.last, thinned.last?.time != last.time {
                thinned[thinned.count - 1] = last
            }
            nodes = thinned
        }
        // Stationary intervals have no drawable length. Merge their endpoint
        // before finding neighbours so resumed motion still has one join and
        // one width/UV value at the shared position. Keep the newest sample.
        var distinctNodes: [TimedSample] = []
        distinctNodes.reserveCapacity(nodes.count)
        for node in nodes {
            if let previous = distinctNodes.last,
               simd_distance(previous.position, node.position) <= 0.0001 {
                continue
            }
            distinctNodes.append(node)
        }
        nodes = distinctNodes
        guard nodes.count >= 2 else { return [] }
        // Stretch the texture across the available path, including a growing
        // trail. The retention window can exceed the particle's entire life.
        let textureDuration = track.current.time - nodes[nodes.count - 1].time

        var result: [SceneParticleGPUInstance] = []
        result.reserveCapacity(nodes.count - 1)
        for index in 0..<(nodes.count - 1) {
            let newer = nodes[index]
            let older = nodes[index + 1]
            let displacement = newer.position - older.position
            let segmentLength = simd_length(displacement)
            // Path history must not turn a lifetime opacity/size animation
            // into a second, unrequested fade along the ribbon. The current
            // particle owns appearance; renderer fade is applied separately.
            let size = track.appearance.size
            guard segmentLength.isFinite, segmentLength > 0.0001,
                  size.isFinite, size > 0.0001 else {
                continue
            }

            let newerU = Self.normalizedTrailPosition(
                sampleTime: newer.time,
                elapsed: elapsed,
                length: textureDuration
            )
            let olderU = Self.normalizedTrailPosition(
                sampleTime: older.time,
                elapsed: elapsed,
                length: textureDuration
            )
            let alphaFade = plan.fadesAlpha ? Self.normalizedTrailPosition(
                sampleTime: (newer.time + older.time) * 0.5,
                elapsed: elapsed,
                length: plan.length
            ) : 1
            let alpha = min(max(
                track.appearance.alpha * layerAlpha * alphaFade,
                0
            ), 1)
            let frame = SceneParticleFrameTransform.identity.verticalTrailSlice(
                tailPosition: olderU,
                headPosition: newerU
            )
            result.append(SceneParticleGPUInstance(
                position: (newer.position + older.position) * 0.5,
                size: size,
                rotation: .zero,
                color: simd_max(
                    track.appearance.color,
                    SIMD3(repeating: 0)
                ),
                alpha: alpha,
                velocity: displacement,
                trailStretch: segmentLength / size,
                trailUVRange: SIMD2(olderU, newerU),
                usesTrailDisplacement: true,
                trailHeadDirection: index > 0
                    ? nodes[index - 1].position - newer.position
                    : displacement,
                trailTailDirection: index + 2 < nodes.count
                    ? older.position - nodes[index + 2].position
                    : displacement,
                trailEndpointSizes: SIMD2(repeating: size),
                currentFrame: frame
            ))
        }
        return result
    }

    private static func interpolate(
        _ samples: [TimedSample],
        at target: TimeInterval,
        upperIndex: inout Int
    ) -> TimedSample? {
        guard let first = samples.first, let last = samples.last,
              target >= first.time else {
            return nil
        }
        if target >= last.time {
            return last
        }
        // Targets move backward along the trail, so each history sample is
        // visited at most once across all segments of this particle.
        while upperIndex > 1, samples[upperIndex - 1].time >= target {
            upperIndex -= 1
        }
        let lower = samples[upperIndex - 1]
        let upper = samples[upperIndex]
        let duration = upper.time - lower.time
        let mix = duration > 0 ? Float((target - lower.time) / duration) : 0
        return TimedSample(
            time: target,
            position: lower.position + (upper.position - lower.position) * mix
        )
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
