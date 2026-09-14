import Foundation
import AppKit
import AVFoundation
import CoreGraphics
import QuartzCore
import WebKit
import Darwin
import UniformTypeIdentifiers

final class CommandReader {
    var frames = DaemonNewlineFrameBuffer()
    let decoder = JSONDecoder()
    let daemon: WallpaperDaemon

    init(daemon: WallpaperDaemon) {
        self.daemon = daemon
    }

    func start() {
        FileHandle.standardInput.readabilityHandler = { [weak self] handle in
            guard let self else { return }
            let data = handle.availableData
            if data.isEmpty {
                DispatchQueue.main.async {
                    self.daemon.shutdown()
                }
                return
            }

            self.consume(data)
        }
    }

    func consume(_ data: Data) {
        for line in frames.append(data) {
            do {
                let command = try decoder.decode(DaemonCommand.self, from: line)
                DispatchQueue.main.async {
                    self.daemon.handle(command)
                }
            } catch {
                daemonLog("failed to decode command \(error.localizedDescription)")
            }
        }
    }
}
