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

    func write(to url: URL?) {
        guard let url, let lines else { return }
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
