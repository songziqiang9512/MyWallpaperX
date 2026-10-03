import Foundation

// Deterministic lifecycle collaborators; the compiled renderer stage,
// PreparedFrame ownership and source transaction are production sources.
final class Events {
    var values: [String] = []
    func add(_ value: String) { values.append(value) }
}
final class MTLTexture {}
final class CAMetalDrawable {
    let texture = MTLTexture()
}
final class MTLCommandBuffer {
    enum Status { case notEnqueued, committed, completed }
    var status: Status = .notEnqueued
    var error: Error? = nil
    let events: Events
    var completions: [(MTLCommandBuffer) -> Void] = []
    init(_ events: Events) { self.events = events }
    func present(_ drawable: CAMetalDrawable) { events.add("present") }
    func addCompletedHandler(_ handler: @escaping (MTLCommandBuffer) -> Void) {
        precondition(status == .notEnqueued)
        completions.append(handler)
    }
    func commit() { events.add("commit"); status = .committed }
    func complete() {
        status = .completed
        events.add("completed")
        completions.forEach { $0(self) }
    }
}
struct SceneResolvedMaterialFrameTargetPlan {}
// Admission/resource preparation is outside this submission-stage probe.
// Uninhabited opaque leaves satisfy FrameOutcome's carried signature without
// recreating either owner or allowing a fixture admission-success path.
enum SceneResolvedMaterialRuntimeBridge {
    enum FramePreparationRequest {}
}
enum SceneResolvedMaterialFrameResourceBundle {}
struct SceneEffectExecutionFrameTrace {}
struct SceneParticlePerformanceObservation {}
final class SceneEffectExecutionTelemetry {
    let events: Events
    init(_ events: Events) { self.events = events }
    func observeSharedCommandBuffer(for trace: SceneEffectExecutionFrameTrace, on buffer: MTLCommandBuffer) {
        events.add("effect.observe")
    }
}
final class SceneFramePerformanceTelemetry {
    let events: Events
    init(_ events: Events) { self.events = events }
    func recordParticleSubmission(_ values: [SceneParticlePerformanceObservation], on buffer: MTLCommandBuffer) {
        events.add("particle.observe")
    }
    func recordSubmitted(on buffer: MTLCommandBuffer) { events.add("frame.observe") }
}
final class SceneCompositionGroupFrameRuntime {
    let events: Events
    init(_ events: Events) { self.events = events }
    func arm() { events.add("group.arm") }
    func cancel() { events.add("group.cancel") }
}
final class SceneParticleDepthTargetLease {
    let events: Events
    init(_ events: Events) { self.events = events }
    func arm(on buffer: MTLCommandBuffer) { events.add("depth.arm") }
    func cancel() { events.add("depth.cancel") }
}
final class SceneMainPassEncoder {
    let events: Events
    init(_ events: Events) { self.events = events }
    func armCompositionPins() { events.add("pins.arm") }
    func cancelCompositionPins() { events.add("pins.cancel") }
}
final class InstanceBuffer {
    let events: Events
    init(_ events: Events) { self.events = events }
    func cancelUncommittedSubmission(on buffer: MTLCommandBuffer) -> Bool {
        events.add("particle.uncommitted.cancel"); return true
    }
    func cancelPending() -> Bool { events.add("particle.pending.cancel"); return true }
}
struct SceneParticleDrawBatch { let instanceBuffer: InstanceBuffer }
final class Compositor {
    let events: Events
    init(_ events: Events) { self.events = events }
    func cancelUnsubmittedResolvedMaterialFrame(on buffer: MTLCommandBuffer) {
        events.add("compositor.cancel")
    }
}
struct SceneMetalRenderer {
    let imageCompositor: Compositor
    let effectExecutionTelemetry: SceneEffectExecutionTelemetry
    let events: Events
    init(_ events: Events) {
        self.events = events
        imageCompositor = Compositor(events)
        effectExecutionTelemetry = SceneEffectExecutionTelemetry(events)
    }
    func discardUnsubmittedFrameResources() { events.add("registry.discard") }
    final class ReflectionFrame {
        let events: Events
        init(_ events: Events) { self.events = events }
        func arm() { events.add("reflection.arm") }
        func cancel() { events.add("reflection.cancel") }
    }
    final class StaticModelFrame {
        let events: Events
        init(_ events: Events) { self.events = events }
        func arm(on buffer: MTLCommandBuffer) { events.add("model.arm") }
        func cancel() { events.add("model.cancel") }
    }
}

@main
struct SceneRendererSubmissionStageHarness {
    static func candidate(_ events: Events, buffer: MTLCommandBuffer) -> SceneMetalRenderer.PreparedFrame {
        let source = SceneSourceUpdateTransaction()
        source.registerResolution(completed: { events.add("source.completed") },
                                  rollback: { events.add("source.rollback") })
        return SceneMetalRenderer(events).makePreparedFrame(
            commandBuffer: buffer, drawable: CAMetalDrawable(),
            encodeFrameReadback: { _, _ in events.add("readback") },
            onDrawableWillPresent: { _ in events.add("willPresent") },
            effectExecutionTrace: .init(), particlePerformanceObservations: [],
            performanceTelemetry: .init(events), compositionGroupRuntime: .init(events),
            sourceUpdateTransaction: source, frameDepthLeases: [.init(events)],
            reflectionFrame: .init(events), modelFrame: .init(events),
            mainPassForSubmission: .init(events),
            particleBatches: [.init(instanceBuffer: .init(events))])
    }
    static func main() throws {
        var checks: [String: Bool] = [:]
        let submitted = Events(), buffer = MTLCommandBuffer(submitted)
        let prepared = candidate(submitted, buffer: buffer)
        checks["preparationDoesNotSubmitOrCancel"] = submitted.values.isEmpty && prepared.isReady
        prepared.whenCompleted { submitted.add("observer.\($0)") }
        checks["submittedOutcome"] = SceneMetalRenderer.submitPreparedFrame(.prepared(prepared)) == .submitted
        checks["submissionOrder"] = submitted.values == ["readback", "willPresent", "present", "effect.observe",
            "particle.observe", "frame.observe", "group.arm", "depth.arm", "reflection.arm", "model.arm", "pins.arm", "commit"]
        prepared.cancel()
        let repeated = SceneMetalRenderer.submitPreparedFrame(.prepared(prepared))
        checks["resolvedCandidateCannotCancelOrResubmit"] = repeated == .dropped(reasonCode: "prepared-frame-already-resolved")
            && submitted.values.last == "commit" && !submitted.values.contains("source.rollback")
        buffer.complete()
        checks["completionOwnsSourceAndObserver"] = submitted.values.suffix(3) == ["completed", "observer.true", "source.completed"]
        let cancelled = Events(), cancelledBuffer = MTLCommandBuffer(cancelled)
        let pending = candidate(cancelled, buffer: cancelledBuffer)
        pending.whenCompleted { _ in cancelled.add("unexpected.observer") }
        pending.cancel(); pending.cancel()
        let expectedCancel = ["compositor.cancel", "source.rollback", "group.cancel", "reflection.cancel", "model.cancel",
            "pins.cancel", "depth.cancel", "particle.uncommitted.cancel", "particle.pending.cancel", "registry.discard"]
        checks["cancellationOrderAndExactlyOnce"] = cancelled.values == expectedCancel && cancelledBuffer.status == .notEnqueued
        let dropped = Events(), droppedBuffer = MTLCommandBuffer(dropped)
        do { _ = candidate(dropped, buffer: droppedBuffer) }
        checks["deinitCancelsUnsubmittedResources"] = dropped.values == expectedCancel
        print(String(decoding: try JSONSerialization.data(withJSONObject: checks, options: [.sortedKeys]), as: UTF8.self))
    }
}
