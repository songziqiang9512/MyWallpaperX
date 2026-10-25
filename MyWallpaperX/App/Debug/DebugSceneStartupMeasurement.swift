#if DEBUG
import Foundation

/// Evidence for one product selection. This value never drives playback.
struct DebugSceneStartupMeasurement {
    let index: Int
    let recordID: String
    let rootPath: String
    let entryUptimeMicros: UInt64
    private(set) var ticketID: UUID?
    private(set) var intentEpoch: UInt64?
    private(set) var requestID: UUID?
    private(set) var executionID: UUID?
    private(set) var daemonGeneration: UInt64?
    private(set) var daemonPID: Int32?
    private(set) var phaseUptimes: [String: UInt64] = [:]
    private(set) var preparedUptimeMicros: UInt64?
    private(set) var presentedUptimeMicros: UInt64?
    private(set) var presentedObservedUptimeMicros: UInt64?
    private(set) var parentFinalizedUptimeMicros: UInt64?
    private(set) var failures: [String] = []
    private struct PrefixObservation {
        let requestID: UUID?
        let generation: UInt64
        let pid: Int32?
        let uptimeMicros: UInt64
        let childStartupUptimes: [String: UInt64]?
    }
    private static let prefixPhases = ["preparationReceived", "processStartBegan",
        "processStartReturned", "helloObserved", "loadEnqueueAttempted"]
    private var prefixObservations: [String: PrefixObservation] = [:]
    private var prefixOrder: [String] = []
    private var prefixFailures: [String] = []

    init(index: Int, recordID: String, rootPath: String, entryUptimeMicros: UInt64) {
        self.index = index
        self.recordID = recordID
        self.rootPath = rootPath
        self.entryUptimeMicros = entryUptimeMicros
    }

    mutating func bindSelection(ticketID: UUID, intentEpoch: UInt64) {
        guard self.ticketID == nil else { fail("duplicate-selection"); return }
        self.ticketID = ticketID
        self.intentEpoch = intentEpoch
    }

    mutating func observePhase(
        _ phase: String, recordID: String?, ticketID: UUID, intentEpoch: UInt64,
        requestID: UUID, uptimeMicros: UInt64
    ) {
        guard admits(ticketID: ticketID, intentEpoch: intentEpoch),
              recordID == self.recordID, bindRequest(requestID) else { return }
        let phases = ["accepted", "preparingModel", "preparingPrograms",
            "preparingResources", "preparingSurfaces", "launched"]
        guard phases.contains(phase) else { return }
        if phaseUptimes[phase] == nil { phaseUptimes[phase] = uptimeMicros }
        else if phase == "accepted" { fail("duplicate-accepted") }
    }

    mutating func observeEndpoint(
        _ phase: String, ticketID: UUID, intentEpoch: UInt64, requestID: UUID,
        executionID: UUID, daemonGeneration: UInt64, daemonPID: Int32?,
        uptimeMicros: UInt64
    ) {
        guard admits(ticketID: ticketID, intentEpoch: intentEpoch),
              bindRequest(requestID) else { return }
        guard phase == "prepared" || phase == "parentFinalized" else { return }
        if let previous = self.executionID, previous != executionID {
            fail("execution-identity-changed"); return
        }
        if let previous = self.daemonGeneration, previous != daemonGeneration {
            fail("daemon-generation-changed"); return
        }
        if let previous = self.daemonPID, previous != daemonPID {
            fail("daemon-pid-changed"); return
        }
        self.executionID = executionID
        self.daemonGeneration = daemonGeneration
        self.daemonPID = daemonPID
        if phase == "prepared" {
            guard preparedUptimeMicros == nil else { fail("duplicate-prepared"); return }
            preparedUptimeMicros = uptimeMicros
        } else {
            guard parentFinalizedUptimeMicros == nil else { fail("duplicate-finalized"); return }
            parentFinalizedUptimeMicros = uptimeMicros
        }
    }

    mutating func observePresentation(
        requestID: UUID, recordID: String?, presentedUptimeMicros: UInt64,
        observedUptimeMicros: UInt64
    ) {
        guard self.requestID == requestID, self.recordID == recordID else { return }
        guard self.presentedUptimeMicros == nil else { fail("duplicate-presented"); return }
        self.presentedUptimeMicros = presentedUptimeMicros
        presentedObservedUptimeMicros = observedUptimeMicros
    }

    mutating func observePrefix(
        _ phase: String, ticketID: UUID, intentEpoch: UInt64, requestID: UUID?,
        daemonGeneration: UInt64, daemonPID: Int32?, uptimeMicros: UInt64,
        childStartupUptimes: [String: UInt64]? = nil
    ) {
        guard admits(ticketID: ticketID, intentEpoch: intentEpoch),
              Self.prefixPhases.contains(phase) else { return }
        guard prefixObservations[phase] == nil else {
            let reason = "duplicate-" + phase
            if !prefixFailures.contains(reason) { prefixFailures.append(reason) }
            return
        }
        prefixOrder.append(phase)
        prefixObservations[phase] = .init(requestID: requestID, generation: daemonGeneration,
            pid: daemonPID, uptimeMicros: uptimeMicros, childStartupUptimes: childStartupUptimes)
    }

    mutating func fail(_ reason: String) {
        if !failures.contains(reason) { failures.append(reason) }
    }

    var isComplete: Bool {
        phaseUptimes["accepted"] != nil && preparedUptimeMicros != nil
            && presentedUptimeMicros != nil && parentFinalizedUptimeMicros != nil
    }

    var report: [String: Any] {
        var reasons = failures
        func require(_ valid: Bool, _ reason: String) {
            if !valid && !reasons.contains(reason) { reasons.append(reason) }
        }
        require(ticketID != nil && intentEpoch != nil, "selection-identity-missing")
        require(requestID != nil && executionID != nil, "execution-identity-missing")
        require((daemonPID ?? 0) > 0 && (daemonGeneration ?? 0) > 0, "daemon-identity-missing")
        require(phaseUptimes["accepted"] != nil, "accepted-missing")
        require(preparedUptimeMicros != nil, "prepared-missing")
        require(presentedUptimeMicros != nil, "presented-missing")
        require(parentFinalizedUptimeMicros != nil, "parent-finalized-missing")
        if let accepted = phaseUptimes["accepted"], let prepared = preparedUptimeMicros,
           let presented = presentedUptimeMicros, let observed = presentedObservedUptimeMicros,
           let finalized = parentFinalizedUptimeMicros {
            require(entryUptimeMicros <= accepted && accepted <= prepared
                && prepared <= presented && presented <= finalized
                && presented <= observed, "event-clock-order-invalid")
        }
        func jsonValue<Value>(_ value: Value?) -> Any { value.map { $0 as Any } ?? NSNull() }
        func elapsed(_ end: UInt64?) -> Any {
            guard let end, end >= entryUptimeMicros else { return NSNull() }
            return Double(end - entryUptimeMicros) / 1_000
        }
        return [
            "index": index, "passed": reasons.isEmpty, "recordID": recordID,
            "rootPath": rootPath, "ticketID": jsonValue(ticketID?.uuidString),
            "intentEpoch": jsonValue(intentEpoch), "requestID": jsonValue(requestID?.uuidString),
            "executionID": jsonValue(executionID?.uuidString),
            "daemonPID": jsonValue(daemonPID), "daemonGeneration": jsonValue(daemonGeneration),
            "entryUptimeMicros": entryUptimeMicros,
            "presentedUptimeMicros": jsonValue(presentedUptimeMicros),
            "presentedObservedUptimeMicros": jsonValue(presentedObservedUptimeMicros),
            "parentFinalizedUptimeMicros": jsonValue(parentFinalizedUptimeMicros),
            "phaseObservedUptimeMicros": phaseUptimes,
            "entryToAcceptedObservedMs": elapsed(phaseUptimes["accepted"]),
            "entryToPreparedObservedMs": elapsed(preparedUptimeMicros),
            "entryToPresentedMs": elapsed(presentedUptimeMicros),
            "entryToPresentedObservedMs": elapsed(presentedObservedUptimeMicros),
            "entryToParentFinalizedMs": elapsed(parentFinalizedUptimeMicros),
            "parentPrefixObservation": prefixReport,
            "childStartupObservation": childStartupReport,
            "failures": reasons
        ]
    }

    /// Diagnostic qualification is independent from the original presented metric.
    private var prefixReport: [String: Any] {
        var reasons = prefixFailures
        func require(_ valid: Bool, _ reason: String) {
            if !valid && !reasons.contains(reason) { reasons.append(reason) }
        }
        for phase in ["preparationReceived", "loadEnqueueAttempted"] {
            require(prefixObservations[phase] != nil, phase + "-missing")
        }
        let startsProcess = prefixObservations["processStartBegan"] != nil
            || prefixObservations["processStartReturned"] != nil
        if startsProcess {
            for phase in ["processStartBegan", "processStartReturned", "helloObserved"] {
                require(prefixObservations[phase] != nil, phase + "-missing")
            }
        }
        require(phaseUptimes["accepted"] != nil, "accepted-observation-missing")
        require(requestID != nil && daemonGeneration != nil && daemonPID != nil,
            "final-execution-identity-missing")
        require(prefixOrder == Self.prefixPhases.filter { prefixObservations[$0] != nil },
            "prefix-arrival-order-invalid")
        var previous = entryUptimeMicros
        var events: [String: [String: Any]] = [:]
        for phase in Self.prefixPhases {
            guard let value = prefixObservations[phase] else { continue }
            require(previous <= value.uptimeMicros, "prefix-clock-order-invalid")
            previous = value.uptimeMicros
            // Preparation arrives before a fresh transport generation exists.
            if phase != "preparationReceived" {
                require(value.generation == daemonGeneration, "prefix-generation-mismatch")
                if phase != "processStartBegan" {
                    require(value.pid == daemonPID && (value.pid ?? 0) > 0, "prefix-pid-mismatch")
                }
            }
            if phase == "loadEnqueueAttempted" {
                require(value.requestID != nil && value.requestID == requestID, "prefix-request-mismatch")
            }
            events[phase] = ["uptimeMicros": value.uptimeMicros, "generation": value.generation,
                "daemonPID": value.pid.map { $0 as Any } ?? NSNull(),
                "requestID": value.requestID.map { $0.uuidString as Any } ?? NSNull()]
        }
        if let accepted = phaseUptimes["accepted"] {
            require(previous <= accepted, "prefix-clock-order-invalid")
        }
        func time(_ phase: String) -> UInt64? { prefixObservations[phase]?.uptimeMicros }
        func interval(_ start: UInt64?, _ end: UInt64?) -> Any {
            guard let start, let end, start <= end else { return NSNull() }
            return Double(end - start) / 1_000
        }
        return ["schemaVersion": 1, "passed": reasons.isEmpty,
            "clock": "parent-process-system-uptime", "events": events,
            "notObservedAfterSelection": Self.prefixPhases.filter { prefixObservations[$0] == nil },
            "intervalsMs": [
                "entryToPreparationReceived": interval(entryUptimeMicros, time("preparationReceived")),
                "preparationReceivedToProcessStartBegan": interval(time("preparationReceived"), time("processStartBegan")),
                "processStartCall": interval(time("processStartBegan"), time("processStartReturned")),
                "processStartReturnedToHelloObserved": interval(time("processStartReturned"), time("helloObserved")),
                "helloObservedToLoadEnqueueAttempted": interval(time("helloObserved"), time("loadEnqueueAttempted")),
                "preparationReceivedToLoadEnqueueAttempted": interval(time("preparationReceived"), time("loadEnqueueAttempted")),
                "loadEnqueueAttemptedToAcceptedObserved": interval(time("loadEnqueueAttempted"), phaseUptimes["accepted"])
            ], "failures": reasons]
    }

    /// Inclusive call windows on the same host, not exclusive subsystem CPU time.
    private var childStartupReport: [String: Any] {
        let phases = ["entryObserved", "appKitBegin", "appKitReturned", "runtimeBegin",
            "runtimeReturned", "helloSnapshotCaptured"]
        let hello = prefixObservations["helloObserved"]
        let start = prefixObservations["processStartBegan"]
        let applicable = hello != nil || start != nil
            || prefixObservations["processStartReturned"] != nil
        var reasons: [String] = []
        func require(_ valid: Bool, _ reason: String) {
            if !valid && !reasons.contains(reason) { reasons.append(reason) }
        }
        require(prefixReport["passed"] as? Bool == true, "parent-prefix-invalid")
        var events: [String: UInt64]?
        var reportedPID: UInt64?
        if applicable {
            require(hello != nil, "hello-observation-missing")
            if let values = hello?.childStartupUptimes {
                require(Set(values.keys) == Set(phases + ["schemaVersion", "pid"]),
                    "child-startup-keys-invalid")
                require(values["schemaVersion"] == 1, "child-startup-schema-invalid")
                reportedPID = values["pid"]
                let expectedPID = daemonPID.map { UInt64(max(0, $0)) }
                require(reportedPID != nil && reportedPID == expectedPID
                    && (reportedPID ?? 0) > 0, "child-startup-pid-mismatch")
                events = values.filter { phases.contains($0.key) }
                var previous: UInt64 = 0
                for phase in phases {
                    guard let value = values[phase] else {
                        require(false, phase + "-missing"); continue
                    }
                    require(value > 0 && previous <= value, "child-startup-clock-order-invalid")
                    previous = value
                }
                if let first = values["entryObserved"], let start {
                    require(start.uptimeMicros <= first, "child-entry-before-process-start")
                }
                if let last = values["helloSnapshotCaptured"], let hello {
                    require(last <= hello.uptimeMicros, "child-snapshot-after-parent-hello")
                }
            } else {
                require(false, "child-startup-values-missing-or-invalid")
            }
        }
        func jsonValue<Value>(_ value: Value?) -> Any { value.map { $0 as Any } ?? NSNull() }
        func time(_ phase: String) -> UInt64? { events?[phase] }
        func interval(_ first: UInt64?, _ last: UInt64?) -> Any {
            guard let first, let last, first <= last else { return NSNull() }
            return Double(last - first) / 1_000
        }
        return ["schemaVersion": 1, "passed": reasons.isEmpty, "applicable": applicable,
            "status": reasons.isEmpty ? (applicable ? "observed" : "notApplicable") : "invalid",
            "clock": "same-host-system-uptime",
            "identity": ["ticketID": jsonValue(ticketID?.uuidString),
                "intentEpoch": jsonValue(intentEpoch), "requestID": jsonValue(requestID?.uuidString),
                "executionID": jsonValue(executionID?.uuidString),
                "transportGeneration": jsonValue(daemonGeneration), "daemonPID": jsonValue(daemonPID),
                "reportedPID": jsonValue(reportedPID)],
            "events": jsonValue(events), "intervalsMs": [
                "processStartBeganToEntryObserved": interval(start?.uptimeMicros, time("entryObserved")),
                "entryObservedToAppKitBegin": interval(time("entryObserved"), time("appKitBegin")),
                "appKitCall": interval(time("appKitBegin"), time("appKitReturned")),
                "appKitReturnedToRuntimeBegin": interval(time("appKitReturned"), time("runtimeBegin")),
                "runtimeConstruction": interval(time("runtimeBegin"), time("runtimeReturned")),
                "runtimeReturnedToHelloSnapshotCaptured": interval(time("runtimeReturned"), time("helloSnapshotCaptured")),
                "helloSnapshotCapturedToParentHelloObserved": interval(time("helloSnapshotCaptured"), hello?.uptimeMicros),
                "entryObservedToParentHelloObserved": interval(time("entryObserved"), hello?.uptimeMicros)
            ], "failures": reasons]
    }

    private func admits(ticketID: UUID, intentEpoch: UInt64) -> Bool {
        self.ticketID == ticketID && self.intentEpoch == intentEpoch
    }

    private mutating func bindRequest(_ requestID: UUID) -> Bool {
        if let previous = self.requestID { return previous == requestID }
        self.requestID = requestID
        return true
    }
}
#endif
