import AVFoundation

nonisolated struct WallpaperVideoTrackDetails: Sendable {
    let displaySize: CGSize?
    let codecText: String?
    let nominalFrameRateText: String?

    var resolutionText: String? {
        displaySize.map(Self.resolutionText(for:))
    }

    static func resolutionText(for displaySize: CGSize) -> String {
        "\(Int(displaySize.width)) × \(Int(displaySize.height))"
    }

    static func load(from asset: AVAsset, includesCodec: Bool = true) async -> Self? {
        guard !Task.isCancelled, let track = try? await asset.loadTracks(withMediaType: .video).first,
              !Task.isCancelled else { return nil }
        let size = await displaySize(for: track)
        guard !Task.isCancelled else { return nil }
        let format = includesCodec ? try? await track.load(.formatDescriptions).first : nil
        guard !Task.isCancelled else { return nil }
        let frameRate = try? await track.load(.nominalFrameRate)
        let fpsText = frameRate.flatMap { fps -> String? in
            guard fps.isFinite, fps > 0 else { return nil }
            return String(localized: "\(fps.formatted(.number.precision(.fractionLength(0...2)))) FPS")
        }
        return Self(displaySize: size, codecText: format.map(codecText(for:)), nominalFrameRateText: fpsText)
    }

    static func displaySize(for track: AVAssetTrack) async -> CGSize? {
        guard let (naturalSize, transform) = try? await track.load(.naturalSize, .preferredTransform) else { return nil }
        let size = CGRect(origin: .zero, size: naturalSize).applying(transform).size
        let width = size.width.rounded()
        let height = size.height.rounded()
        guard width > 0, height > 0, width < Double(Int.max), height < Double(Int.max) else { return nil }
        return CGSize(width: width, height: height)
    }

    private static func codecText(for format: CMFormatDescription) -> String {
        let codec = CMFormatDescriptionGetMediaSubType(format)
        switch codec {
        case kCMVideoCodecType_H264: return "H.264"
        case kCMVideoCodecType_HEVC: return "HEVC"
        case kCMVideoCodecType_HEVCWithAlpha: return "HEVC with Alpha"
        case kCMVideoCodecType_MPEG4Video: return "MPEG-4 Part 2"
        case kCMVideoCodecType_H263: return "H.263"
        default: return String(format: "0x%08X", codec)
        }
    }
}
