import AppKit
import Foundation
import WebKit

/// 网络桥接桩：与 DedicatedWebWallpaperHostPlaceholderAdapter+RuntimeBridge 的
/// 成功回包同形状——响应体统一 base64 + bodyIsBase64 标志 + responseURL，且
/// 与宿主同形状按发送 frame 定向回包（D5）。
final class NetworkBridgeStub: NSObject, WKScriptMessageHandler {
    static let primaryBytes: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0xFF, 0xFE, 0x80, 0x7F]
    static let secondaryBytes: [UInt8] = [0x00, 0x10, 0x80, 0xFF, 0x41]
    weak var webView: WKWebView?
    /// 到达宿主网络桥的代理请求数。
    private(set) var receivedRequestCount = 0
    var holdReplies = false
    private(set) var heldRequests: [WKScriptMessage] = []

    var heldURLs: [String] { heldRequests.map { ($0.body as? [String: Any])?["url"] as? String ?? "" } }

    func reply(_ index: Int, body: String, error: String? = nil) async throws {
        let message = heldRequests[index]
        let request = message.body as! [String: Any]
        var payload: [String: Any] = ["requestID": request["requestID"]!, "ok": error == nil,
            "status": 200, "headers": ["content-type": "text/plain"],
            "body": Data(body.utf8).base64EncodedString(), "bodyIsBase64": true,
            "responseURL": request["url"]!]
        if let error { payload["error"] = error }
        let data = try JSONSerialization.data(withJSONObject: payload)
        let json = String(data: data, encoding: .utf8)!
        guard let webView else { throw NSError(domain: "WebCompatibilityParity", code: 3) }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            webView.evaluateJavaScript("window.__myWallpaperResolveNetworkRequest(\(json));",
                                      in: message.frameInfo, in: .page) { result in
                continuation.resume(with: result.map { _ in () })
            }
        }
    }

    static func hexadecimal(_ bytes: [UInt8]) -> String {
        bytes.map { String(format: "%02x", $0) }.joined()
    }

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard
            let body = message.body as? [String: Any],
            let requestID = body["requestID"] as? String,
            let url = body["url"] as? String
        else { return }
        receivedRequestCount += 1
        if holdReplies { heldRequests.append(message); return }
        let bytes = url.contains("secondary") ? Self.secondaryBytes : Self.primaryBytes
        let payload: [String: Any] = [
            "requestID": requestID,
            "ok": true,
            "status": 200,
            "headers": ["content-type": "application/octet-stream"],
            "body": Data(bytes).base64EncodedString(),
            "bodyIsBase64": true,
            "responseURL": url
        ]
        guard
            let data = try? JSONSerialization.data(withJSONObject: payload),
            let json = String(data: data, encoding: .utf8)
        else { return }
        // D5：回包只回发送请求的 frame，不改发主 frame。
        webView?.evaluateJavaScript(
            "window.__myWallpaperResolveNetworkRequest(\(json));",
            in: message.frameInfo,
            in: .page,
            completionHandler: nil
        )
    }
}

@MainActor
extension Scenarios {
    static func nativeXHRAbort() async throws {
        let cases = ["new-abort", "opened-abort-send", "active-abort-success", "active-abort-failure",
                     "active-abort-arraybuffer", "active-abort-resend", "opened-abort-send-abort", "rs2-abort", "abort-rs4-open", "abort-rs4-open-send",
                     "abort-rs4-nested", "abort-event-open", "abort-event-open-send", "abort-end-open", "abort-end-open-send",
                     "done-abort", "done-double-abort", "done-abort-arraybuffer", "success-done-abort", "error-done-abort"]
        var checks: [String: Bool] = [:]
        let success = ["property:load", "listener:load", "property:loadend", "listener:loadend"]
        let failure = ["property:error", "listener:error", "property:loadend", "listener:loadend"]
        let cancelled = ["property:abort", "listener:abort", "property:loadend", "listener:loadend"]
        for phase in ["native", "proxy"] {
            for name in cases {
                let stub = NetworkBridgeStub()
                stub.holdReplies = true
                let host = PageHost(html: "<meta http-equiv=\"Content-Security-Policy\" content=\"connect-src data: blob:\"><body>R50 abort facts</body>", networkStub: stub)
                defer { host.close() }
                var observations: [[String: Any]] = []
                var probeError: String?
                var replies = 0
                do {
                    try await host.open()
                    try await host.waitUntil("window.__mwxHostReplyReachable === true", label: "abort fact reply channel")
                    _ = try await host.script(#"""
                    window.__mwxAbortXHRStart = function(phase, name) {
                      const original = window.__mwxNativeXHR;
                      const xhr = new original.Constructor();
                      const facts = window.__mwxAbortXHRFacts = {phase, name, events: [], operations: []};
                      const native = phase === 'native';
                      let stage = 'A', order = 0, aborting = false, reopened = false, hookAborted = false;
                      function attempt(body) { try { return body(); } catch (error) { return {error: error.name, message: String(error.message)}; } }
                      function response() {
                        return attempt(() => {
                          const value = xhr.response;
                          if (value === null) return {type: 'null'};
                          if (value instanceof ArrayBuffer) return {type: 'ArrayBuffer', byteLength: value.byteLength};
                          return {type: typeof value, length: typeof value === 'string' ? value.length : null};
                        });
                      }
                      function state() {
                        return {stage, readyState: attempt(() => xhr.readyState), status: attempt(() => xhr.status),
                          text: attempt(() => xhr.responseText), url: attempt(() => xhr.responseURL), response: response(),
                          contentType: attempt(() => xhr.getResponseHeader('content-type')),
                          allHeaders: attempt(() => xhr.getAllResponseHeaders())};
                      }
                      function op(operation, body) {
                        const row = {operation, orderBefore: ++order, before: state()};
                        facts.operations.push(row);
                        row.eventsBefore = facts.events.length;
                        try { body(); row.ok = true; }
                        catch (error) { row.ok = false; row.error = error.name; row.message = String(error.message); }
                        row.orderAfter = ++order; row.after = state(); row.eventsAfter = facts.events.length;
                      }
                      function url(label) {
                        return !native || name === 'error-done-abort' ? 'https://assets.example.com/r50/' + label : 'data:text/plain;charset=utf-8,R50_' + label;
                      }
                      function open(label) { return native ? original.open.call(xhr, 'GET', url(label), true) : xhr.open('GET', url(label), true); }
                      function send() { return native ? original.send.call(xhr) : xhr.send(); }
                      function runAbort(operation) {
                        op(operation, () => {
                          const previouslyAborting = aborting;
                          aborting = true;
                          try { return native ? original.abort.call(xhr) : xhr.abort(); }
                          finally { aborting = previouslyAborting; }
                        });
                      }
                      function hook(type) {
                        if (name === 'abort-rs4-nested' && !hookAborted && aborting && type === 'readystatechange' && xhr.readyState === 4) {
                          hookAborted = true; runAbort('nested-abort-at-RS4');
                        }
                        const reopen = aborting && ((name.startsWith('abort-rs4-open') && type === 'readystatechange' && xhr.readyState === 4)
                          || (name.startsWith('abort-event-') && type === 'abort') || (name.startsWith('abort-end-') && type === 'loadend'));
                        if (reopen && !reopened) {
                          reopened = true; stage = 'B';
                          op('abort-callback-open-B', () => open('B'));
                          if (name.endsWith('-send')) op('abort-callback-send-B', send);
                        }
                        const abortAtState = name === 'rs2-abort' ? 2 : ['success-done-abort', 'error-done-abort'].includes(name) ? 4 : null;
                        if (!hookAborted && type === 'readystatechange' && xhr.readyState === abortAtState) {
                          hookAborted = true;
                          runAbort('readystatechange-' + abortAtState + '-abort');
                        }
                      }
                      for (const type of ['readystatechange', 'loadstart', 'progress', 'load', 'error', 'abort', 'timeout', 'loadend']) {
                        xhr['on' + type] = function(event) {
                          facts.events.push({order: ++order, source: 'property', type, duringAbort: aborting,
                            eventType: event ? event.type : null, targetIsXHR: !!event && event.target === xhr,
                            currentTargetIsXHR: !!event && event.currentTarget === xhr, thisIsXHR: this === xhr, ...state()});
                          hook(type);
                        };
                        xhr.addEventListener(type, function(event) {
                          facts.events.push({order: ++order, source: 'listener', type, duringAbort: aborting,
                            eventType: event.type, targetIsXHR: event.target === xhr,
                            currentTargetIsXHR: event.currentTarget === xhr, thisIsXHR: this === xhr, ...state()});
                        });
                      }
                      facts.capture = {constructorType: typeof original.Constructor, openType: typeof original.open, sendType: typeof original.send, abortType: typeof original.abort, openIsPatched: original.open !== XMLHttpRequest.prototype.open,
                        sendIsPatched: original.send !== XMLHttpRequest.prototype.send,
                        abortIsPatched: original.abort !== XMLHttpRequest.prototype.abort};
                      window.__mwxAbortXHRState = state;
                      window.__mwxAbortXHRSnapshot = () => ({...facts, state: state(), reopened, hookAborted,
                        targetsValid: facts.events.every(event => event.targetIsXHR && event.currentTargetIsXHR && event.thisIsXHR),
                        terminalOrder: facts.events.filter(event => ['abort', 'load', 'error', 'loadend'].includes(event.type)).map(event => event.source + ':' + event.type),
                        counts: facts.events.reduce((counts, event) => { const key = event.source + ':' + event.type; counts[key] = (counts[key] || 0) + 1; return counts; }, {})});
                      window.__mwxAbortXHRAfterDone = () => {
                        runAbort('abort-after-DONE');
                        if (name === 'done-double-abort') runAbort('second-abort-after-DONE');
                      };
                      if (name === 'new-abort') { runAbort('new-object-abort'); return; }
                      op('open-A', () => open('A'));
                      if (name.endsWith('arraybuffer')) op('set-arraybuffer', () => { xhr.responseType = 'arraybuffer'; });
                      if (name.startsWith('opened-abort-send')) {
                        runAbort('opened-unsent-abort'); op('send-after-unsent-abort', send);
                        if (name === 'opened-abort-send-abort') runAbort('active-abort-after-unsent-abort');
                        return;
                      }
                      op('send-A', send);
                      if (name.startsWith('active-') || name.startsWith('abort-')) runAbort('active-abort');
                      if (name === 'active-abort-resend') op('send-after-active-abort', send);
                    };
                    true;
                    """#)
                    let arguments = try JSONSerialization.data(withJSONObject: [phase, name])
                    _ = try await host.script("window.__mwxAbortXHRStart(...\(String(data: arguments, encoding: .utf8)!)); true;")
                    if phase == "proxy" {
                        let pending = try await host.script("Object.keys(window.__myWallpaperNetworkRequests).length") as! Int
                        for _ in 0..<50 where stub.heldRequests.count < pending { try await host.wait(0.02) }
                    }
                    try await host.wait(0.15)
                    observations.append(["point": "after-initial-operations", "bridgeRequests": stub.receivedRequestCount,
                                         "bridgeReplies": replies, "facts": try await host.script("window.__mwxAbortXHRSnapshot()")])
                    if phase == "proxy" {
                        for index in stub.heldRequests.indices.reversed() {
                            let fails = name == "error-done-abort" || (name == "active-abort-failure" && index == 0)
                            try await stub.reply(index, body: "reply-\(index)", error: fails ? "controlled-old-error" : nil)
                            replies += 1
                            try await host.wait(0.05)
                            observations.append(["point": "reply-\(index)", "bridgeRequests": stub.receivedRequestCount,
                                                 "bridgeReplies": replies, "facts": try await host.script("window.__mwxAbortXHRSnapshot()")])
                        }
                    }
                    if name.hasPrefix("done-") {
                        try await host.waitUntil("window.__mwxAbortXHRState().readyState === 4", seconds: 3, label: "DONE abort premise")
                        _ = try await host.script("window.__mwxAbortXHRAfterDone(); true;")
                        observations.append(["point": "after-DONE-abort", "bridgeRequests": stub.receivedRequestCount,
                                             "bridgeReplies": replies, "facts": try await host.script("window.__mwxAbortXHRSnapshot()")])
                    }
                    try await host.wait(0.15)
                } catch { probeError = String(describing: error) }
                let final = (try? await host.script("window.__mwxAbortXHRSnapshot ? window.__mwxAbortXHRSnapshot() : null")) as? [String: Any] ?? [:]
                var row: [String: Any] = ["phase": phase, "case": name, "bridgeRequests": stub.receivedRequestCount,
                    "bridgeReplies": replies, "heldURLs": stub.heldURLs, "observations": observations, "final": final]
                if let probeError { row["probeError"] = probeError }
                let data = try JSONSerialization.data(withJSONObject: row, options: [.sortedKeys])
                print("WK_XHR_ABORT_FACT=" + String(decoding: data, as: UTF8.self))
                let key = phase + "/" + name
                let state = final["state"] as? [String: Any] ?? [:]
                let capture = final["capture"] as? [String: Any] ?? [:]
                let response = state["response"] as? [String: Any] ?? [:]
                let events = final["events"] as? [[String: Any]] ?? []
                let operations = final["operations"] as? [[String: Any]] ?? []
                let terminal = final["terminalOrder"] as? [String] ?? []
                let counts = final["counts"] as? [String: Int] ?? [:]
                let reopens = name.hasPrefix("abort-") && name.contains("-open")
                let sendsB = reopens && name.hasSuffix("-send")
                let remainsOpen = name == "opened-abort-send" || reopens
                let doneCallback = name == "success-done-abort" || name == "error-done-abort"
                checks[key + "/collected"] = probeError == nil && !final.isEmpty
                checks[key + "/native-capture"] = ["constructorType", "openType", "sendType", "abortType"].allSatisfy { capture[$0] as? String == "function" }
                    && capture["openIsPatched"] as? Bool == true && capture["sendIsPatched"] as? Bool == true
                checks[key + "/targets"] = final["targetsValid"] as? Bool == true
                if phase == "native" { checks[key + "/no-bridge"] = stub.receivedRequestCount == 0 }
                if !remainsOpen {
                    checks[key + "/reset-state"] = state["readyState"] as? Int == 0 && state["status"] as? Int == 0
                        && state["contentType"] is NSNull && state["allHeaders"] as? String == ""
                    if name.hasSuffix("arraybuffer") {
                        checks[key + "/empty-response"] = response["type"] as? String == "null"
                    } else if !(phase == "native" && name == "rs2-abort") {
                        checks[key + "/empty-response"] = state["text"] as? String == "" && response["length"] as? Int == 0
                    }
                }
                if name == "new-abort" {
                    checks[key + "/no-events"] = events.isEmpty
                } else if name == "opened-abort-send" || name == "opened-abort-send-abort" {
                    let unsent = operations.first { $0["operation"] as? String == "opened-unsent-abort" }
                    let after = unsent?["after"] as? [String: Any] ?? [:]
                    checks[key + "/unsent-remains-open"] = unsent?["ok"] as? Bool == true && after["readyState"] as? Int == 1
                    checks[key + "/send-after-unsent-abort"] = operations.first { $0["operation"] as? String == "send-after-unsent-abort" }?["ok"] as? Bool == true
                    if name == "opened-abort-send" {
                        checks[key + "/completes"] = state["readyState"] as? Int == 4 && state["status"] as? Int == 200 && terminal == success
                    }
                }
                if reopens {
                    checks[key + "/keeps-new-request"] = final["reopened"] as? Bool == true && state["stage"] as? String == "B"
                        && state["readyState"] as? Int == (sendsB ? 4 : 1) && state["status"] as? Int == (sendsB ? 200 : 0)
                    checks[key + "/abort-chain-and-new-terminal"] = terminal == cancelled + (sendsB ? success : [])
                    if phase == "proxy" { checks[key + "/new-body"] = state["text"] as? String == (sendsB ? "reply-1" : "") }
                } else if name.hasPrefix("done-") || doneCallback {
                    checks[key + "/keeps-original-terminal"] = terminal == (name == "error-done-abort" ? failure : success)
                    checks[key + "/no-extra-abort"] = (counts["property:abort"] ?? 0) == 0 && (counts["listener:abort"] ?? 0) == 0
                    for operation in operations where (operation["operation"] as? String)?.contains("abort") == true {
                        checks[key + "/no-event-in-" + (operation["operation"] as! String)] = operation["eventsBefore"] as? Int == operation["eventsAfter"] as? Int
                        let before = operation["before"] as? [String: Any] ?? [:], after = operation["after"] as? [String: Any] ?? [:]
                        checks[key + "/keeps-url-in-" + (operation["operation"] as! String)] = before["url"] as? String != nil && before["url"] as? String == after["url"] as? String
                    }
                    if name == "done-abort-arraybuffer" {
                        let before = operations.first { $0["operation"] as? String == "abort-after-DONE" }?["before"] as? [String: Any] ?? [:]
                        let loaded = before["response"] as? [String: Any] ?? [:]
                        checks[key + "/loaded-before-reset"] = loaded["type"] as? String == "ArrayBuffer" && (loaded["byteLength"] as? Int ?? 0) > 0
                            && before["contentType"] as? String != nil
                    }
                } else if name != "new-abort" && name != "opened-abort-send" {
                    checks[key + "/one-abort-chain"] = terminal == cancelled
                }
                if (counts["property:abort"] ?? 0) > 0 {
                    let ready = events.first { $0["source"] as? String == "property" && $0["type"] as? String == "readystatechange" && $0["duringAbort"] as? Bool == true && $0["readyState"] as? Int == 4 }
                    let abort = events.first { $0["source"] as? String == "property" && $0["type"] as? String == "abort" }
                    checks[key + "/RS4-before-abort"] = ready != nil && (ready?["order"] as? Int ?? 0) < (abort?["order"] as? Int ?? 0)
                }
                if name == "active-abort-resend" {
                    let rejected = operations.first { $0["operation"] as? String == "send-after-active-abort" }
                    checks[key + "/send-requires-new-open"] = rejected?["ok"] as? Bool == false && rejected?["error"] as? String == "InvalidStateError"
                }
                if name == "abort-rs4-nested" {
                    checks[key + "/nested-abort-ran"] = operations.first { $0["operation"] as? String == "nested-abort-at-RS4" }?["ok"] as? Bool == true
                }
                if phase == "proxy" {
                    checks[key + "/bridge-count"] = stub.receivedRequestCount == (name == "new-abort" || name == "rs2-abort" ? 0 : sendsB ? 2 : 1)
                    if !(name.hasPrefix("done-") || doneCallback || name == "opened-abort-send" || name == "new-abort") {
                        let point = sendsB ? "reply-1" : "after-initial-operations"
                        let settled = observations.first { $0["point"] as? String == point }?["facts"] as? [String: Any] ?? [:]
                        checks[key + "/old-reply-no-events"] = !settled.isEmpty && (settled["events"] as? [[String: Any]])?.count == events.count
                    }
                }
            }
        }
        let data = try JSONSerialization.data(withJSONObject: checks, options: [.sortedKeys])
        print("WK_XHR_ABORT_CHECKS=" + String(decoding: data, as: UTF8.self))
        expect(checks.values.allSatisfy { $0 }, "native XHR abort mismatches: \(checks.filter { !$0.value }.keys.sorted())")
    }

    static func nativeXHRLifecycle() async throws {
        let cases = ["single", "reuse-success", "reuse-failure", "reuse-abort-success", "opened-reopen-send",
                     "headers-reopen", "done-reopen", "load-reopen", "failed-open", "second-send",
                     "current-error", "error-done-reopen"]
        var checks: [String: Bool] = [:]
        for phase in ["native", "proxy"] {
            for name in cases {
                let stub = NetworkBridgeStub()
                stub.holdReplies = true
                let host = PageHost(html: "<meta http-equiv=\"Content-Security-Policy\" content=\"connect-src data: blob:\"><body>XHR identity and events</body>", networkStub: stub)
                defer { host.close() }
                var observations: [[String: Any]] = []
                var probeError: String?
                do {
                    try await host.open()
                    try await host.waitUntil("window.__mwxHostReplyReachable === true", label: "XHR reply channel")
                    _ = try await host.script(#"""
                    window.__mwxStartXHRCase = function(phase, name) {
                      const original = window.__mwxNativeXHR;
                      const xhr = new original.Constructor();
                      const facts = window.__mwxXHRFacts = {phase, name, events: [], operations: [], done: false};
                      const native = phase === 'native';
                      let stage = 'A', reentered = false, order = 0;
                      function read(key) { try { return xhr[key]; } catch (error) { return {error: error.name}; } }
                      function state() { return {stage, readyState: read('readyState'), status: read('status'), text: read('responseText'), url: read('responseURL')}; }
                      function op(operation, body) {
                        try { body(); facts.operations.push({order: ++order, operation, ok: true, state: state()}); }
                        catch (error) { facts.operations.push({order: ++order, operation, ok: false, error: error.name, state: state()}); }
                      }
                      function url(label) {
                        if (!native || name === 'current-error' || name === 'error-done-reopen') return 'https://assets.example.com/xhr/' + label;
                        return 'data:text/plain;charset=utf-8,XHR_' + label;
                      }
                      function open(method, value) { return native ? original.open.call(xhr, method, value, true) : xhr.open(method, value, true); }
                      function send() { return native ? original.send.call(xhr) : xhr.send(); }
                      function abort() { return native ? original.abort.call(xhr) : xhr.abort(); }
                      function record(source, type, event, receiver) {
                        facts.events.push({order: ++order, source, type, eventType: event ? event.type : null,
                          targetIsXHR: !!event && event.target === xhr, targetIsNull: !!event && event.target === null,
                          currentTargetIsXHR: !!event && event.currentTarget === xhr, thisIsXHR: receiver === xhr, ...state()});
                      }
                      function reenter(type) {
                        if (!reentered && name === 'opened-reopen-send' && type === 'readystatechange' && xhr.readyState === 1) {
                          reentered = true;
                          op('opened-send-A', send);
                          stage = 'B';
                          op('opened-open-B', () => open('GET', url('B')));
                          op('opened-send-B', send);
                          return;
                        }
                        const matches = (name === 'headers-reopen' && type === 'readystatechange' && xhr.readyState === 2)
                          || (['done-reopen', 'error-done-reopen'].includes(name) && type === 'readystatechange' && xhr.readyState === 4)
                          || (name === 'load-reopen' && type === 'load');
                        if (!matches || reentered) return;
                        reentered = true;
                        stage = 'B';
                        op('reentrant-open-B', () => open('GET', url('B')));
                        if (name === 'headers-reopen') op('reentrant-send-B', send);
                      }
                      for (const type of ['readystatechange', 'loadstart', 'progress', 'load', 'error', 'abort', 'timeout', 'loadend']) {
                        xhr['on' + type] = function(event) { record('property', type, event, this); reenter(type); };
                        xhr.addEventListener(type, function(event) {
                          record('listener', type, event, this);
                          if (type === 'loadend') setTimeout(() => { facts.done = true; }, 100);
                        });
                      }
                      facts.capture = {openIsPatched: original.open !== XMLHttpRequest.prototype.open,
                        sendIsPatched: original.send !== XMLHttpRequest.prototype.send};
                      window.__mwxXHRSnapshot = () => ({...facts, state: state(), reentered,
                        counts: facts.events.reduce((counts, event) => { const key = event.source + ':' + event.type; counts[key] = (counts[key] || 0) + 1; return counts; }, {}),
                        targetsValid: facts.events.every(event => event.targetIsXHR && event.currentTargetIsXHR && event.thisIsXHR),
                        terminalOrder: facts.events.filter(event => ['load', 'error', 'loadend'].includes(event.type)).map(event => event.source + ':' + event.type),
                        completionOrder: facts.events.filter(event => (event.type === 'readystatechange' && event.readyState === 4) || ['load', 'error', 'loadend'].includes(event.type)).map(event => event.source + ':' + event.type)});
                      op('open-A', () => open('GET', url('A')));
                      if (name !== 'opened-reopen-send') op('send-A', send);
                      if (name.startsWith('reuse-')) {
                        if (name === 'reuse-abort-success') op('abort-A', abort);
                        stage = 'B';
                        op('open-B-same-URL', () => open('GET', url('A')));
                        op('send-B', send);
                      } else if (name === 'failed-open') {
                        op('forbidden-open-TRACE', () => open('TRACE', url('B')));
                      } else if (name === 'second-send') op('second-send-A', send);
                    };
                    true;
                    """#)
                    let arguments = try JSONSerialization.data(withJSONObject: [phase, name])
                    _ = try await host.script("window.__mwxStartXHRCase(...\(String(data: arguments, encoding: .utf8)!)); true;")
                    if phase == "proxy" {
                        let pending = try await host.script("Object.keys(window.__myWallpaperNetworkRequests).length") as! Int
                        for _ in 0..<50 where stub.heldRequests.count < pending { try await host.wait(0.02) }
                        observations.append(["point": "queued", "facts": try await host.script("window.__mwxXHRSnapshot()")])
                        let reverse = name.hasPrefix("reuse-") || name == "opened-reopen-send"
                        let indices = reverse ? Array(stub.heldRequests.indices.reversed()) : Array(stub.heldRequests.indices)
                        for index in indices {
                            let fails = name == "current-error" || name == "error-done-reopen" || (name == "reuse-failure" && index == 0)
                            try await stub.reply(index, body: "reply-\(index)", error: fails ? "controlled-XHR-error" : nil)
                            try await host.wait(0.05)
                            observations.append(["point": "reply-\(index)", "facts": try await host.script("window.__mwxXHRSnapshot()")])
                        }
                    } else {
                        try await host.waitUntil("window.__mwxXHRFacts.done === true", seconds: 3, label: "native XHR terminal event")
                    }
                } catch { probeError = String(describing: error) }
                let final = (try? await host.script("window.__mwxXHRSnapshot ? window.__mwxXHRSnapshot() : null")) as? [String: Any] ?? [:]
                var row: [String: Any] = ["phase": phase, "case": name, "bridgeRequests": stub.receivedRequestCount,
                    "heldURLs": stub.heldURLs, "observations": observations, "final": final]
                if let probeError { row["probeError"] = probeError }
                let data = try JSONSerialization.data(withJSONObject: row, options: [.sortedKeys])
                print("WK_XHR_FACT=" + String(decoding: data, as: UTF8.self))
                let key = phase + "/" + name
                let state = final["state"] as? [String: Any] ?? [:]
                let operations = final["operations"] as? [[String: Any]] ?? []
                let terminal = final["terminalOrder"] as? [String] ?? []
                let success = ["property:load", "listener:load", "property:loadend", "listener:loadend"]
                let failure = ["property:error", "listener:error", "property:loadend", "listener:loadend"]
                checks[key + "/evaluated"] = probeError == nil && !final.isEmpty
                checks[key + "/targets"] = final["targetsValid"] as? Bool == true
                if phase == "native" { checks[key + "/no-bridge"] = stub.receivedRequestCount == 0 }
                switch name {
                case "single", "current-error":
                    let expected = name == "current-error" ? failure : success
                    checks[key + "/completion"] = final["completionOrder"] as? [String] == ["property:readystatechange", "listener:readystatechange"] + expected
                    checks[key + "/state"] = state["readyState"] as? Int == 4 && state["status"] as? Int == (name == "current-error" ? 0 : 200)
                case "done-reopen", "load-reopen", "error-done-reopen":
                    checks[key + "/terminal-after-reopen"] = terminal == (name == "error-done-reopen" ? failure : success)
                        && final["reentered"] as? Bool == true && state["readyState"] as? Int == 1 && state["stage"] as? String == "B"
                case "headers-reopen":
                    checks[key + "/reentered"] = final["reentered"] as? Bool == true && state["status"] as? Int == 200
                    if phase == "proxy" {
                        checks[key + "/only-new-request"] = stub.heldURLs == ["https://assets.example.com/xhr/B"]
                            && state["text"] as? String == "reply-0" && terminal == success
                    }
                case "failed-open", "second-send":
                    let operation = name == "failed-open" ? "forbidden-open-TRACE" : "second-send-A"
                    let rejected = operations.first { $0["operation"] as? String == operation }
                    checks[key + "/throws"] = rejected?["ok"] as? Bool == false && rejected?["error"] as? String == (name == "failed-open" ? "SecurityError" : "InvalidStateError")
                    checks[key + "/original-completes"] = state["readyState"] as? Int == 4 && state["status"] as? Int == 200 && terminal == success
                    if phase == "proxy" { checks[key + "/one-request"] = stub.receivedRequestCount == 1 && state["text"] as? String == "reply-0" }
                default:
                    checks[key + "/new-completes"] = state["readyState"] as? Int == 4 && state["status"] as? Int == 200 && state["stage"] as? String == "B"
                    if phase == "proxy" {
                        let beforeOld = observations.first { $0["point"] as? String == "reply-1" }?["facts"] as? [String: Any] ?? [:]
                        checks[key + "/old-response-ignored"] = stub.receivedRequestCount == 2 && state["text"] as? String == "reply-1"
                            && terminal == (name == "reuse-abort-success" ? ["property:loadend", "listener:loadend"] + success : success)
                            && (beforeOld["events"] as? [[String: Any]])?.count == (final["events"] as? [[String: Any]])?.count
                    }
                }
            }
        }
        let data = try JSONSerialization.data(withJSONObject: checks, options: [.sortedKeys])
        print("WK_XHR_CHECKS=" + String(decoding: data, as: UTF8.self))
        expect(checks.values.allSatisfy { $0 }, "native XHR mismatches: \(checks.filter { !$0.value }.keys.sorted())")
    }

    static func nativeAbortMatrix() async throws {
        let stub = NetworkBridgeStub()
        let host = PageHost(html: "<meta http-equiv=\"Content-Security-Policy\" content=\"connect-src 'none'\"><body>abort probe</body>",
                            stubNativeFetch: false, networkStub: stub)
        defer { host.close() }
        try await host.open()
        try await host.waitUntil("window.__mwxHostReplyReachable === true", label: "native abort probe reply channel")
        _ = try await host.script(#"""
        window.__mwxAbortProbeResults = [];
        window.__mwxAbortProbeCases = [
          {name:'url-default', input:'url', reason:'default', override:'aborted', method:'GET'},
          {name:'url-custom', input:'url', reason:'object', override:'aborted', method:'GET'},
          {name:'url-null-reason', input:'url', reason:'null', override:'aborted', method:'HEAD'},
          {name:'request-inherit', input:'request', reason:'default', override:'missing', method:'GET'},
          {name:'request-undefined', input:'request', reason:'object', override:'undefined', method:'HEAD'},
          {name:'request-null', input:'request', reason:'object', override:'null', method:'GET'},
          {name:'request-active', input:'request', reason:'object', override:'active', method:'HEAD'},
          {name:'url-active', input:'url', reason:'object', override:'active', method:'GET'},
          {name:'replace-custom-with-active', input:'url', reason:'object', override:'aborted', replace:'active', method:'GET'},
          {name:'replace-active-with-aborted', input:'url', reason:'object', override:'active', replace:'aborted', method:'HEAD'}
        ];
        window.__mwxAbortProbeRun = async (index, phase) => {
          const spec = window.__mwxAbortProbeCases[index];
          const aborted = new AbortController(), active = new AbortController();
          if (spec.reason === 'default') aborted.abort();
          else aborted.abort(spec.reason === 'null' ? null : {probe:spec.name});
          const url = 'https://mwx-r48.invalid/abort-probe/' + spec.method;
          const input = spec.input === 'request' ? new Request(url, {signal:aborted.signal, method:spec.method}) : url;
          const init = {method:spec.method};
          if (spec.override === 'undefined') init.signal = undefined;
          if (spec.override === 'null') init.signal = null;
          if (spec.override === 'active') init.signal = active.signal;
          if (spec.override === 'aborted') init.signal = aborted.signal;
          const constructed = new Request(input, init);
          const row = {phase, name:spec.name, input:spec.input, method:spec.method, reasonKind:spec.reason,
            override:spec.override, replace:spec.replace || null,
            constructedSignalAborted:constructed.signal.aborted,
            constructedReasonMatches:Object.is(constructed.signal.reason, aborted.signal.reason)};
          const fetcher = phase === 'native' ? window.__mwxNativeFetch : window.fetch.bind(window);
          try {
            const pending = fetcher(input, init);
            if (spec.replace) init.signal = spec.replace === 'active' ? active.signal : aborted.signal;
            const response = await pending;
            row.outcome = 'fulfilled'; row.status = response.status;
            row.errorName = null; row.reasonMatches = false;
          } catch (error) {
            row.outcome = 'rejected'; row.errorName = error?.name || null;
            row.reasonMatches = Object.is(error, aborted.signal.reason);
          }
          window.__mwxAbortProbeResults.push(row);
        };
        true;
        """#)
        let count = try await host.script("window.__mwxAbortProbeCases.length") as! Int
        var ordinal = 0
        var facts: [[String: Any]] = []
        for phase in ["native", "product"] {
            for index in 0..<count {
                let before = stub.receivedRequestCount
                _ = try await host.script("window.__mwxAbortProbeRun(\(index), '\(phase)'); true")
                ordinal += 1
                try await host.waitUntil("window.__mwxAbortProbeResults.length === \(ordinal)", label: "abort matrix \(phase) \(index)")
                let json = try await host.script("JSON.stringify(window.__mwxAbortProbeResults[\(ordinal - 1)])") as! String
                var row = try JSONSerialization.jsonObject(with: Data(json.utf8)) as! [String: Any]
                row["bridgeRequests"] = stub.receivedRequestCount - before
                let data = try JSONSerialization.data(withJSONObject: row, options: [.sortedKeys])
                print("WK_ABORT_FACT=" + String(decoding: data, as: UTF8.self))
                facts.append(row)
            }
        }
        var failures: [String] = []
        for index in 0..<count {
            let native = facts[index], product = facts[index + count]
            let cancelled = native["constructedSignalAborted"] as? Bool == true
            let nativeValid = native["bridgeRequests"] as? Int == 0 && native["outcome"] as? String == "rejected"
                && (cancelled ? native["reasonMatches"] as? Bool == true : native["errorName"] as? String == "TypeError")
            let expectedOutcome = cancelled ? native["outcome"] as? String : "fulfilled"
            let expectedReason = cancelled ? native["reasonMatches"] as? Bool : false
            let productValid = product["outcome"] as? String == expectedOutcome
                && product["reasonMatches"] as? Bool == expectedReason
                && product["bridgeRequests"] as? Int == (cancelled ? 0 : 1)
                && (cancelled || product["status"] as? Int == 200)
            if !nativeValid || !productValid { failures.append(native["name"] as! String) }
        }
        expect(failures.isEmpty, "native abort matrix mismatches: \(failures)")
    }

    /// F19：桥接回包的 base64 响应体必须按 bodyIsBase64 还原成字节——fetch 的
    /// arrayBuffer 与 XHR 的 responseType='arraybuffer' 都要逐字节一致。
    static func networkBridgeBinaryRestore() async throws {
        let page = """
        <html><body>
        <script>
        window.__f19 = { fetch: null, xhr: null };
        const toHex = (bytes) => Array.from(bytes).map(byte => byte.toString(16).padStart(2, '0')).join('');
        (async () => {
          try {
            const response = await fetch('https://assets.example.com/mwx/primary.bin');
            window.__f19.fetch = {
              status: response.status,
              url: response.url,
              contentType: response.headers.get('content-type'),
              hex: toHex(new Uint8Array(await response.arrayBuffer()))
            };
          } catch (error) {
            window.__f19.fetch = { error: String((error && error.message) || error) };
          }
        })();
        const xhr = new XMLHttpRequest();
        xhr.open('GET', 'https://assets.example.com/mwx/secondary.bin');
        xhr.responseType = 'arraybuffer';
        xhr.onload = () => {
          window.__f19.xhr = {
            status: xhr.status,
            responseURL: xhr.responseURL,
            contentType: xhr.getResponseHeader('Content-Type'),
            hex: toHex(new Uint8Array(xhr.response))
          };
        };
        xhr.onerror = () => { window.__f19.xhr = { error: 'xhr_error' }; };
        xhr.send();
        </script>
        </body></html>
        """
        let stub = NetworkBridgeStub()
        let host = PageHost(html: page, stubNativeFetch: true, networkStub: stub)
        defer { host.close() }
        try await host.open()
        try await host.waitUntil(
            "window.__f19.fetch !== null && window.__f19.xhr !== null",
            label: "proxied fetch and xhr"
        )
        let fetchError = try await host.script("window.__f19.fetch.error ? String(window.__f19.fetch.error) : ''") as? String
        let xhrError = try await host.script("window.__f19.xhr.error ? String(window.__f19.xhr.error) : ''") as? String
        expect(fetchError == "", "fetch 代理失败: \(fetchError ?? "nil")")
        expect(xhrError == "", "XHR 代理失败: \(xhrError ?? "nil")")
        let fetchHex = try await host.script("String(window.__f19.fetch.hex)") as? String
        let xhrHex = try await host.script("String(window.__f19.xhr.hex)") as? String
        expect(
            fetchHex == NetworkBridgeStub.hexadecimal(NetworkBridgeStub.primaryBytes),
            "fetch arrayBuffer 未按 base64 还原字节: \(fetchHex ?? "nil")"
        )
        expect(
            xhrHex == NetworkBridgeStub.hexadecimal(NetworkBridgeStub.secondaryBytes),
            "XHR arrayBuffer 未按 base64 还原字节: \(xhrHex ?? "nil")"
        )
        let fetchURL = try await host.script("String(window.__f19.fetch.url)") as? String
        expect(
            fetchURL == "https://assets.example.com/mwx/primary.bin",
            "fetch Response.url 未回填作者可见 URL: \(fetchURL ?? "nil")"
        )
        let fetchStatus = try await host.script("window.__f19.fetch.status") as? Int
        let xhrStatus = try await host.script("window.__f19.xhr.status") as? Int
        expect(
            fetchStatus == 200 && xhrStatus == 200,
            "代理回包状态码未透传: fetch=\(String(describing: fetchStatus)) xhr=\(String(describing: xhrStatus))"
        )
        let xhrContentType = try await host.script("String(window.__f19.xhr.contentType)") as? String
        expect(
            xhrContentType == "application/octet-stream",
            "XHR getResponseHeader 未透传代理响应头: \(xhrContentType ?? "nil")"
        )
    }
}
