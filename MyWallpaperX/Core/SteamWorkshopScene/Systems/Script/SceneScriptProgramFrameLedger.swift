import Foundation

/// Shared per-frame observation ledger for the QuickJS program families.
///
/// The scalar, string and vector programs observe the same media event
/// streams and user-property acknowledgement state; the watermark,
/// consumed-generation and applied-property members used to be declared and
/// snapshotted/restored identically in all three. One ledger instance per
/// program now owns that state; the programs expose single-line delegating
/// surface methods instead of duplicating the snapshot/restore bodies.
nonisolated final class SceneScriptProgramFrameLedger {
    var observedMediaThumbnailEvent =
        SceneScriptObservedEvent<SceneScriptMediaThumbnailEventInput>()
    var observedMediaPlaybackEvent =
        SceneScriptObservedEvent<SceneScriptMediaPlaybackEventInput>()
    var observedMediaPropertiesEvent =
        SceneScriptObservedEvent<SceneScriptMediaPropertiesEventInput>()
    var observedMediaTimelineEvent =
        SceneScriptObservedEvent<SceneScriptMediaTimelineEventInput>()
    var consumedMediaThumbnailGenerations: [SceneDynamicTarget: UInt64] = [:]
    var consumedMediaPlaybackGenerations: [SceneDynamicTarget: UInt64] = [:]
    var consumedMediaPropertiesGenerations: [SceneDynamicTarget: UInt64] = [:]
    var consumedMediaTimelineGenerations: [SceneDynamicTarget: UInt64] = [:]
    var appliedUserProperties = SceneScriptAppliedUserPropertyState()

    func remove(targets: Set<SceneDynamicTarget>) {
        for target in targets {
            consumedMediaThumbnailGenerations.removeValue(forKey: target)
            consumedMediaPlaybackGenerations.removeValue(forKey: target)
            consumedMediaPropertiesGenerations.removeValue(forKey: target)
            consumedMediaTimelineGenerations.removeValue(forKey: target)
        }
        appliedUserProperties.remove(targets: targets)
    }

    /// A held frame may predate permanent String-owner retirement. Restoring
    /// its acknowledgement must not recreate per-owner records after release.
    func retain(targets: Set<SceneDynamicTarget>) {
        consumedMediaThumbnailGenerations = consumedMediaThumbnailGenerations.filter { targets.contains($0.key) }
        consumedMediaPlaybackGenerations = consumedMediaPlaybackGenerations.filter { targets.contains($0.key) }
        consumedMediaPropertiesGenerations = consumedMediaPropertiesGenerations.filter { targets.contains($0.key) }
        consumedMediaTimelineGenerations = consumedMediaTimelineGenerations.filter { targets.contains($0.key) }
        appliedUserProperties.retain(targets: targets)
    }

    func observeMediaEvents(_ events: SceneScriptMediaFrameEvents) -> SceneScriptObservedMediaFrameEvents {
        .init(
            playback: observedMediaPlaybackEvent.observe(events.playback),
            properties: observedMediaPropertiesEvent.observe(events.properties),
            thumbnail: observedMediaThumbnailEvent.observe(events.thumbnail),
            timeline: observedMediaTimelineEvent.observe(events.timeline)
        )
    }

    func snapshot() -> SceneScriptProgramFrameState {
        .init(
            observedMediaThumbnailEvent: observedMediaThumbnailEvent.snapshot(),
            observedMediaPlaybackEvent: observedMediaPlaybackEvent.snapshot(),
            observedMediaPropertiesEvent: observedMediaPropertiesEvent.snapshot(),
            observedMediaTimelineEvent: observedMediaTimelineEvent.snapshot(),
            consumedMediaThumbnailGenerations: consumedMediaThumbnailGenerations,
            consumedMediaPlaybackGenerations: consumedMediaPlaybackGenerations,
            consumedMediaPropertiesGenerations: consumedMediaPropertiesGenerations,
            consumedMediaTimelineGenerations: consumedMediaTimelineGenerations,
            appliedUserProperties: appliedUserProperties
        )
    }

    func restore(
        _ state: SceneScriptProgramFrameState,
        rejectedOwnerTargets: Set<SceneDynamicTarget>? = nil
    ) {
        if let rejectedOwnerTargets {
            // Keep the observed input watermark and accepted peers. Only the
            // rejected target's acknowledgement belongs to the failed result.
            for target in rejectedOwnerTargets {
                consumedMediaThumbnailGenerations[target] = state.consumedMediaThumbnailGenerations[target]
                consumedMediaPlaybackGenerations[target] = state.consumedMediaPlaybackGenerations[target]
                consumedMediaPropertiesGenerations[target] = state.consumedMediaPropertiesGenerations[target]
                consumedMediaTimelineGenerations[target] = state.consumedMediaTimelineGenerations[target]
            }
            appliedUserProperties.restore(state.appliedUserProperties, for: rejectedOwnerTargets)
            return
        }
        observedMediaThumbnailEvent.restore(state.observedMediaThumbnailEvent)
        observedMediaPlaybackEvent.restore(state.observedMediaPlaybackEvent)
        observedMediaPropertiesEvent.restore(state.observedMediaPropertiesEvent)
        observedMediaTimelineEvent.restore(state.observedMediaTimelineEvent)
        consumedMediaThumbnailGenerations = state.consumedMediaThumbnailGenerations
        consumedMediaPlaybackGenerations = state.consumedMediaPlaybackGenerations
        consumedMediaPropertiesGenerations = state.consumedMediaPropertiesGenerations
        consumedMediaTimelineGenerations = state.consumedMediaTimelineGenerations
        appliedUserProperties = state.appliedUserProperties
    }
}
