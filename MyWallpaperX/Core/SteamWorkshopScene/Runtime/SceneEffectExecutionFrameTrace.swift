import CryptoKit
import Foundation

nonisolated enum SceneEffectExecutionOrigin: String, Sendable {
    case image
    case solid
    case text
    case quad
    case utilityComposition = "utility-composition"
    case utilityProject = "utility-project"
    case utilityFullscreen = "utility-fullscreen"
}

nonisolated struct SceneEffectExecutionIdentity: Hashable, Sendable {
    let layerID: Int
    let effectIndex: Int
    let descriptorID: String
}

nonisolated enum SceneEffectCPUInvocationOutcome: Hashable, Sendable {
    case encodedOutput
    case failed(reasonCode: String)

    var details: (fact: SceneEffectOutcomeFact, value: String, reason: String?) {
        switch self {
        case .encodedOutput:
            (.encoded, "encoded-output", nil)
        case let .failed(reasonCode):
            (.failed, "failed", reasonCode)
        }
    }
}

nonisolated enum SceneEffectRouteOperationOutcome: Hashable, Sendable {
    case encoded
    case failed(reasonCode: String)

    var details: (fact: SceneEffectOutcomeFact, value: String, reason: String?) {
        switch self {
        case .encoded:
            (.encoded, "encoded", nil)
        case let .failed(reasonCode):
            (.failed, "failed", reasonCode)
        }
    }
}

nonisolated enum SceneFrameCommandBufferStatus: String, Hashable, Sendable {
    case completed
    case failed
}

nonisolated struct SceneEffectExecutionFrameCohort: Sendable {
    let frameIndex: UInt64
    let attemptedEffects: Int
    let returnedOutputs: Int
    let failedInvocations: Int
    let routeOperations: Int
    let cohortSHA256: String
}

nonisolated enum SceneEffectSubjectKind: String, Hashable, Sendable {
    case effect
    case aggregate
}

nonisolated enum SceneEffectOutcomeFact: Hashable, Sendable {
    case encoded
    case failed
}

nonisolated struct SceneEffectInvocationSubject: Hashable, Sendable {
    let kind: SceneEffectSubjectKind
    let origin: SceneEffectExecutionOrigin
    let layerID: Int
    let effectIndex: Int?
    let descriptorID: String?
    let family: String
    let backend: String

    var logFields: [String] {
        [
            "origin=\(origin.rawValue)",
            "subject=\(kind.rawValue)",
            "layer=\(layerID)",
            "effect=\(effectIndex.map(String.init) ?? "-")",
            "descriptor=\(SceneEffectExecutionLogToken.encode(descriptorID))",
            "family=\(SceneEffectExecutionLogToken.encode(family))",
            "backend=\(SceneEffectExecutionLogToken.encode(backend))",
        ]
    }
}

nonisolated struct SceneEffectInvocationEvent: Hashable, Sendable {
    let subject: SceneEffectInvocationSubject
    let outcome: SceneEffectCPUInvocationOutcome

    var logFields: [String] {
        subject.logFields + [
            "outcome=\(outcome.details.value)",
            "reason=\(SceneEffectExecutionLogToken.encode(outcome.details.reason))",
        ]
    }

    var canonicalLine: String {
        (["effect"] + logFields).joined(separator: "|")
    }
}

nonisolated struct SceneEffectRouteSubject: Hashable, Sendable {
    let origin: SceneEffectExecutionOrigin
    let layerID: Int
    let operation: String

    var logFields: [String] {
        [
            "origin=\(origin.rawValue)",
            "layer=\(layerID)",
            "operation=\(SceneEffectExecutionLogToken.encode(operation))",
        ]
    }
}

nonisolated struct SceneEffectRouteEvent: Hashable, Sendable {
    let subject: SceneEffectRouteSubject
    let outcome: SceneEffectRouteOperationOutcome

    var logFields: [String] {
        subject.logFields + [
            "outcome=\(outcome.details.value)",
            "reason=\(SceneEffectExecutionLogToken.encode(outcome.details.reason))",
        ]
    }

    var canonicalLine: String {
        (["route"] + logFields).joined(separator: "|")
    }
}

nonisolated final class SceneEffectExecutionFrameTrace: @unchecked Sendable {
    let frameIndex: UInt64

    private let telemetry: SceneEffectExecutionTelemetry
    private let lock = NSLock()
    private var invocationEvents: Set<SceneEffectInvocationEvent> = []
    private var routeEvents: Set<SceneEffectRouteEvent> = []
    private var isFrozen = false
    private var frozenCohort: SceneEffectExecutionFrameCohort?

    init(frameIndex: UInt64, telemetry: SceneEffectExecutionTelemetry) {
        self.frameIndex = frameIndex
        self.telemetry = telemetry
    }

    @discardableResult
    func recordExact(
        identity: SceneEffectExecutionIdentity,
        origin: SceneEffectExecutionOrigin,
        family: String,
        backend: String,
        outcome: SceneEffectCPUInvocationOutcome
    ) -> Bool {
        recordInvocation(
            subject: SceneEffectInvocationSubject(
                kind: .effect,
                origin: origin,
                layerID: identity.layerID,
                effectIndex: identity.effectIndex,
                descriptorID: identity.descriptorID,
                family: family,
                backend: backend
            ),
            outcome: outcome
        )
    }

    @discardableResult
    func recordAggregate(
        layerID: Int,
        family: String,
        origin: SceneEffectExecutionOrigin,
        backend: String,
        outcome: SceneEffectCPUInvocationOutcome
    ) -> Bool {
        recordInvocation(
            subject: SceneEffectInvocationSubject(
                kind: .aggregate,
                origin: origin,
                layerID: layerID,
                effectIndex: nil,
                descriptorID: nil,
                family: family,
                backend: backend
            ),
            outcome: outcome
        )
    }

    @discardableResult
    func recordRouteOperation(
        layerID: Int,
        origin: SceneEffectExecutionOrigin,
        operation: String,
        outcome: SceneEffectRouteOperationOutcome
    ) -> Bool {
        let event = SceneEffectRouteEvent(
            subject: SceneEffectRouteSubject(
                origin: origin,
                layerID: layerID,
                operation: operation
            ),
            outcome: outcome
        )
        let inserted = withLock {
            guard !isFrozen else { return false }
            return routeEvents.insert(event).inserted
        }
        if inserted { telemetry.recordRouteTransition(event, frameIndex: frameIndex) }
        return inserted
    }

    func freeze() -> SceneEffectExecutionFrameCohort? {
        withLock {
            if isFrozen { return frozenCohort }
            isFrozen = true
            guard !invocationEvents.isEmpty || !routeEvents.isEmpty else { return nil }

            let subjects = Set(invocationEvents.map(\.subject))
            let returned = Set(invocationEvents.lazy.filter {
                $0.outcome.details.fact == .encoded
            }.map(\.subject))
            let failed = Set(invocationEvents.lazy.filter {
                $0.outcome.details.fact == .failed
            }.map(\.subject))
            let operations = Set(routeEvents.map(\.subject))
            let lines = (
                invocationEvents.map(\.canonicalLine) + routeEvents.map(\.canonicalLine)
            ).sorted()
            let digest = SHA256.hash(data: Data(lines.joined(separator: "\n").utf8))
                .map { String(format: "%02x", $0) }
                .joined()
            let cohort = SceneEffectExecutionFrameCohort(
                frameIndex: frameIndex,
                attemptedEffects: subjects.count,
                returnedOutputs: returned.count,
                failedInvocations: failed.count,
                routeOperations: operations.count,
                cohortSHA256: digest
            )
            frozenCohort = cohort
            return cohort
        }
    }

    private func recordInvocation(
        subject: SceneEffectInvocationSubject,
        outcome: SceneEffectCPUInvocationOutcome
    ) -> Bool {
        let event = SceneEffectInvocationEvent(subject: subject, outcome: outcome)
        let inserted = withLock {
            guard !isFrozen else { return false }
            return invocationEvents.insert(event).inserted
        }
        if inserted { telemetry.recordInvocationTransition(event, frameIndex: frameIndex) }
        return inserted
    }

    private func withLock<Result>(_ operation: () -> Result) -> Result {
        lock.lock()
        defer { lock.unlock() }
        return operation()
    }
}

nonisolated private enum SceneEffectExecutionLogToken {
    static func encode(_ value: String?) -> String {
        guard let value, !value.isEmpty else { return "-" }
        return value.utf8.map { byte in
            let isAllowed = (48...57).contains(byte)
                || (65...90).contains(byte)
                || (97...122).contains(byte)
                || [43, 45, 46, 47, 58, 95].contains(byte)
            return isAllowed
                ? String(UnicodeScalar(byte))
                : String(format: "%%%02X", byte)
        }.joined()
    }
}
