#if DEBUG
//
//  WebRuntimeDiagnosticsStore.swift
//  MyWallpaperX
//

import Foundation
import CoreGraphics

struct WebRuntimeDiagnosticEvent: Identifiable, Equatable {
    enum Severity: String {
        case info
        case warning
        case error
    }

    let id = UUID()
    let timestamp: Date
    let recordID: String?
    let screenID: CGDirectDisplayID?
    let type: String
    let severity: Severity
    let message: String
    let url: String?
}
@MainActor
final class WebRuntimeDiagnosticsStore {
    static let shared = WebRuntimeDiagnosticsStore()
    static let didChangeNotification = Notification.Name("WebRuntimeDiagnosticsStore.didChange")

    private let capacity = 500
    private var events: [WebRuntimeDiagnosticEvent] = []
    private let shouldLogToConsole = ProcessInfo.processInfo.arguments.contains("--mwx-log-web-diagnostics")

    func record(
        type: String,
        severity: WebRuntimeDiagnosticEvent.Severity,
        message: String,
        recordID: String?,
        screenID: CGDirectDisplayID?,
        url: String? = nil
    ) {
        let event = WebRuntimeDiagnosticEvent(
            timestamp: Date(),
            recordID: recordID,
            screenID: screenID,
            type: type,
            severity: severity,
            message: String(message.prefix(800)),
            url: url.map { String($0.prefix(800)) }
        )
        events.append(event)
        if events.count > capacity {
            events.removeFirst(events.count - capacity)
        }
        NotificationCenter.default.post(name: Self.didChangeNotification, object: recordID)
        guard shouldLogToConsole else { return }
        NSLog(
            "MWX WEB DIAG record=%@ screen=%@ severity=%@ type=%@ url=%@ message=%@",
            recordID ?? "-",
            screenID.map(String.init) ?? "-",
            severity.rawValue,
            type,
            event.url ?? "-",
            event.message
        )
    }

    func recentEvents(recordID: String?, limit: Int = 50) -> [WebRuntimeDiagnosticEvent] {
        events
            .reversed()
            .filter { recordID == nil || $0.recordID == recordID }
            .prefix(limit)
            .reversed()
    }

    func clear(recordID: String?) {
        guard let recordID else {
            events.removeAll()
            NotificationCenter.default.post(name: Self.didChangeNotification, object: nil)
            return
        }
        events.removeAll { $0.recordID == recordID }
        NotificationCenter.default.post(name: Self.didChangeNotification, object: recordID)
    }
}
typealias WebRuntimeDiagnosticHandler = (String, WebRuntimeDiagnosticEvent.Severity, String, URL?) -> Void
#else
typealias WebRuntimeDiagnosticHandler = Never
#endif
