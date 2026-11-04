import Foundation
import Metal

@main
enum Harness {
    static func main() throws {
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue() else {
            print("{\"metalAvailable\":false}")
            return
        }
        var results: [String: Bool] = [:]

        try SceneSubmissionAdmissionChecks.dependencyBindings(
            device: device, queue: queue, results: &results
        )
        try SceneSubmissionLifecycleChecks.invalidationHistoryAndObservation(
            device: device, queue: queue, results: &results
        )
        try SceneSubmissionAdmissionChecks.capabilityAndTargetAdmission(
            device: device, queue: queue, results: &results
        )
        try SceneSubmissionPublicationChecks.lateNamedInputAvailability(
            device: device, queue: queue, results: &results
        )
        try SceneSubmissionPublicationChecks.lateProviderContentPropagation(
            device: device, queue: queue, results: &results
        )
        try SceneSubmissionAtomicPreparationChecks.atomicPreparationRollback(
            device: device, queue: queue, results: &results
        )
        try SceneSubmissionAtomicPreparationChecks.lateHistoryRollback(
            device: device, queue: queue, results: &results
        )
        try SceneSubmissionPublicationChecks.preparedProviderAndNamedSuffix(
            device: device, queue: queue, results: &results
        )
        try SceneSubmissionPublicationChecks.repeatedTerminalPublication(
            device: device, queue: queue, results: &results
        )
        try SceneSubmissionAtomicPreparationChecks.twoCandidateSubmission(
            device: device, queue: queue, results: &results
        )
        try SceneSubmissionRuntimeBridgeChecks.claimsProvidersAndEvidence(
            device: device, queue: queue, results: &results
        )
        try SceneSubmissionAdmissionChecks.fallbackAndFrameConsumption(
            device: device, queue: queue, results: &results
        )
        try SceneSubmissionLifecycleChecks.ticketsPinsAndCompletionOrder(
            device: device, queue: queue, results: &results
        )

        let payload: [String: Any] = [
            "metalAvailable": true,
            "results": results,
        ]
        let data = try JSONSerialization.data(
            withJSONObject: payload,
            options: [.sortedKeys]
        )
        print(String(decoding: data, as: UTF8.self))
    }
}
