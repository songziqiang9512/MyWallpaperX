#if DEBUG
import Foundation

struct SceneStartupReportBuffer {
    private var lines: [String]?

    init(enabled: Bool) {
        lines = enabled ? [] : nil
    }

    var isEnabled: Bool {
        lines != nil
    }

    mutating func append(_ line: @autoclosure () -> String) {
        guard lines != nil else { return }
        lines?.append(line())
    }

    mutating func append(contentsOf newLines: @autoclosure () -> [String]) {
        guard lines != nil else { return }
        lines?.append(contentsOf: newLines())
    }

    var layerEntryCount: Int {
        lines?.filter { $0.starts(with: "layer ") }.count ?? 0
    }

    func write(to url: URL?, appending: Bool = false) {
        guard let url, let lines else { return }
        if appending {
            guard let handle = try? FileHandle(forWritingTo: url) else { return }
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: Data(("\n" + lines.joined(separator: "\n") + "\n").utf8))
            return
        }
        try? lines.joined(separator: "\n").write(
            to: url, atomically: true, encoding: .utf8
        )
    }
}

extension SceneMetalView {
    func requestDebugSnapshot(reason: String, outputDirectory: URL,
                              kind: SceneDebugFrameCapture.RequestClass) -> SceneDebugFrameCapture.Admission {
        debugFrameCapture.request(reason: reason, outputDirectory: outputDirectory, kind: kind)
    }
}
#endif
