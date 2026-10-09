import Foundation

/// Preparation-only, lossless VP9 demux. Public format authorities:
/// https://www.webmproject.org/docs/container/
/// https://www.webmproject.org/vp9/mp4/ and VP9 bitstream specification §6.2.
/// Packet ranges refer to zero-based offsets in the caller's original Data;
/// this type owns neither a file, a decoder, nor a playback clock.
nonisolated enum SceneWebMContainer {
    struct Limits: Sendable {
        var maximumPayloadBytes = 256 * 1024 * 1024
        var maximumPacketBytes = 32 * 1024 * 1024
        var maximumPackets = 60_000
        var maximumElements = 500_000
        var maximumClusters = 16_384
        var maximumDimension = 16_384
        var maximumDurationNanoseconds: Int64 = 86_400_000_000_000
    }

    struct Track: Sendable {
        let number: UInt64
        let width: Int
        let height: Int
        let timecodeScaleNanoseconds: Int64
        let defaultDurationNanoseconds: Int64?
        let durationNanoseconds: Int64?
        /// FullBox version/flags followed by VPCodecConfigurationRecord.
        /// Does not include the MP4 box size or the four-character box type.
        let vpCodecConfiguration: Data
    }

    struct Packet: Sendable {
        let dataRange: Range<Int>
        let presentationTimeNanoseconds: Int64
        let durationNanoseconds: Int64
        let isKeyframe: Bool
    }

    struct Video: Sendable {
        let track: Track
        let packets: [Packet]
    }

    enum ParseError: Error, Equatable, CustomStringConvertible {
        case malformed(String)
        case unsupported(String)
        case budgetExceeded(String)

        var description: String {
            switch self {
            case let .malformed(reason): "webm-malformed: \(reason)"
            case let .unsupported(reason): "webm-unsupported: \(reason)"
            case let .budgetExceeded(reason): "webm-budget: \(reason)"
            }
        }
    }

    static func parse(
        _ data: Data,
        limits: Limits = .init(),
        cancellationCheck: @escaping @Sendable () throws -> Void = {}
    ) throws -> Video {
        guard limits.maximumPayloadBytes > 0, limits.maximumPacketBytes > 0,
              limits.maximumPackets > 0, limits.maximumElements > 0,
              limits.maximumClusters > 0, limits.maximumDimension > 0,
              limits.maximumDurationNanoseconds > 0 else {
            throw ParseError.budgetExceeded("invalid limits")
        }
        guard data.count <= limits.maximumPayloadBytes else {
            throw ParseError.budgetExceeded("payload bytes")
        }
        var parser = Parser(data: data, limits: limits, cancellationCheck: cancellationCheck)
        return try parser.parse()
    }

    private struct Element {
        let id: UInt64
        let range: Range<Int>
        let unknownSize: Bool
    }

    private struct RawPacket {
        let track: UInt64
        let range: Range<Int>
        let timecode: Int64
        let duration: UInt64?
        let keyframe: Bool
    }

    private struct VideoMetadata {
        var width: UInt64?
        var height: UInt64?
        var displayWidth: UInt64?
        var displayHeight: UInt64?
        var colour: [UInt64: UInt64] = [:]
    }

    private struct TrackMetadata {
        var number: UInt64?
        var type: UInt64?
        var codec: String?
        var defaultDuration: UInt64?
        var codecFeatures: [UInt8: UInt8] = [:]
        var video: VideoMetadata?
    }

    private struct VP9Header: Equatable {
        let profile: UInt8
        let bitDepth: UInt8
        let chroma: UInt8
        let fullRange: Bool
        let colorSpace: UInt8
        let width: Int
        let height: Int
    }

    private struct Parser {
        let data: Data
        let limits: Limits
        let cancellationCheck: @Sendable () throws -> Void
        var elementCount = 0
        var clusters = 0
        var maximumIDLength = 4
        var maximumSizeLength = 8
        var timeScale: UInt64 = 1_000_000
        var durationTicks: Double?
        var metadata: TrackMetadata?
        var rawPackets: [RawPacket] = []

        mutating func parse() throws -> Video {
            try cancellationCheck()
            var cursor = 0
            let header = try element(at: &cursor, end: data.count)
            guard header.id == 0x1A45DFA3 else { throw ParseError.malformed("missing EBML header") }
            try parseHeader(header)
            var hasSegment = false
            while cursor < data.count {
                let child = try element(at: &cursor, end: data.count, unknownIDs: [0x18538067])
                switch child.id {
                case 0x18538067:
                    guard !hasSegment else { throw ParseError.unsupported("multiple segments") }
                    hasSegment = true
                    try parseSegment(child)
                case 0xEC, 0xBF: break // Void and CRC do not change the media representation.
                default: throw ParseError.unsupported("top-level element")
                }
            }
            guard hasSegment else { throw ParseError.malformed("missing segment") }
            return try finish()
        }

        mutating func parseHeader(_ parent: Element) throws {
            var cursor = parent.range.lowerBound
            var seen = Set<UInt64>()
            var docType: String?
            while cursor < parent.range.upperBound {
                let child = try element(at: &cursor, end: parent.range.upperBound)
                try unique(child.id, seen: &seen)
                switch child.id {
                case 0x4282: docType = try string(child)
                case 0x4286, 0x42F7:
                    guard try uint(child) == 1 else { throw ParseError.unsupported("EBML version") }
                case 0x42F2:
                    let value = try uint(child)
                    guard (1...4).contains(value) else { throw ParseError.unsupported("EBML ID length") }
                    maximumIDLength = Int(value)
                case 0x42F3:
                    let value = try uint(child)
                    guard (1...8).contains(value) else { throw ParseError.unsupported("EBML size length") }
                    maximumSizeLength = Int(value)
                case 0x4287, 0x4285:
                    let version = try uint(child)
                    guard version > 0, version <= 4 else { throw ParseError.unsupported("WebM version") }
                case 0xEC, 0xBF: break
                default: throw ParseError.unsupported("EBML header field")
                }
            }
            guard docType == "webm" else { throw ParseError.unsupported("DocType must be webm") }
        }

        mutating func parseSegment(_ parent: Element) throws {
            var cursor = parent.range.lowerBound
            var seen = Set<UInt64>()
            while cursor < parent.range.upperBound {
                let child = try element(at: &cursor, end: parent.range.upperBound, unknownIDs: [0x1F43B675])
                switch child.id {
                case 0x1549A966:
                    try unique(child.id, seen: &seen)
                    try parseInfo(child)
                case 0x1654AE6B:
                    try unique(child.id, seen: &seen)
                    try parseTracks(child)
                case 0x1F43B675:
                    clusters += 1
                    guard clusters <= limits.maximumClusters else { throw ParseError.budgetExceeded("clusters") }
                    cursor = try parseCluster(child)
                case 0x114D9B74, 0x1C53BB6B, 0x1254C367, 0xEC, 0xBF:
                    break // SeekHead, Cues and Tags are not needed for this sequential demux.
                default: throw ParseError.unsupported("segment media extension")
                }
            }
        }

        mutating func parseInfo(_ parent: Element) throws {
            var cursor = parent.range.lowerBound
            var seen = Set<UInt64>()
            while cursor < parent.range.upperBound {
                let child = try element(at: &cursor, end: parent.range.upperBound)
                try unique(child.id, seen: &seen)
                switch child.id {
                case 0x2AD7B1: timeScale = try uint(child)
                case 0x4489: durationTicks = try floating(child)
                case 0x4D80, 0x5741, 0x7BA9, 0x4461, 0x73A4, 0x7384, 0xEC, 0xBF: break
                default: throw ParseError.unsupported("segment timing/link field")
                }
            }
            guard timeScale > 0, timeScale <= UInt64(Int64.max) else {
                throw ParseError.malformed("invalid timecode scale")
            }
        }

        mutating func parseTracks(_ parent: Element) throws {
            var cursor = parent.range.lowerBound
            while cursor < parent.range.upperBound {
                let child = try element(at: &cursor, end: parent.range.upperBound)
                switch child.id {
                case 0xAE:
                    guard metadata == nil else { throw ParseError.unsupported("multiple tracks, including audio") }
                    metadata = try parseTrack(child)
                case 0xEC, 0xBF: break
                default: throw ParseError.unsupported("track collection extension")
                }
            }
        }

        mutating func parseTrack(_ parent: Element) throws -> TrackMetadata {
            var track = TrackMetadata()
            var seen = Set<UInt64>()
            var cursor = parent.range.lowerBound
            while cursor < parent.range.upperBound {
                let child = try element(at: &cursor, end: parent.range.upperBound)
                try unique(child.id, seen: &seen)
                switch child.id {
                case 0xD7: track.number = try uint(child)
                case 0x83: track.type = try uint(child)
                case 0x86: track.codec = try string(child)
                case 0x23E383: track.defaultDuration = try uint(child)
                case 0x63A2: track.codecFeatures = try codecFeatures(child)
                case 0xE0: track.video = try parseVideo(child)
                case 0xB9:
                    guard try uint(child) == 1 else { throw ParseError.unsupported("disabled video track") }
                case 0x56AA, 0x56BB, 0x55EE:
                    guard try uint(child) == 0 else { throw ParseError.unsupported("codec delay/preroll/additions") }
                case 0x73C5, 0x88, 0x55AA, 0x9C, 0x536E, 0x22B59C, 0x22B59D, 0x258688,
                     0xEC, 0xBF: break
                default: throw ParseError.unsupported("track encoding/operation extension")
                }
            }
            guard track.type == 1, track.codec == "V_VP9" else {
                throw ParseError.unsupported("only a single VP9 video track is supported")
            }
            guard let number = track.number, number > 0, track.video != nil else {
                throw ParseError.malformed("incomplete video track")
            }
            return track
        }

        mutating func parseVideo(_ parent: Element) throws -> VideoMetadata {
            var video = VideoMetadata()
            var seen = Set<UInt64>()
            var cursor = parent.range.lowerBound
            while cursor < parent.range.upperBound {
                let child = try element(at: &cursor, end: parent.range.upperBound)
                try unique(child.id, seen: &seen)
                switch child.id {
                case 0xB0: video.width = try uint(child)
                case 0xBA: video.height = try uint(child)
                case 0x54B0: video.displayWidth = try uint(child)
                case 0x54BA: video.displayHeight = try uint(child)
                case 0x55B0: video.colour = try parseColour(child)
                case 0x9A:
                    guard [0, 2].contains(try uint(child)) else { throw ParseError.unsupported("interlaced video") }
                case 0x53C0, 0x53B8, 0x54AA, 0x54BB, 0x54CC, 0x54DD, 0x54B2:
                    guard try uint(child) == 0 else { throw ParseError.unsupported("alpha/stereo/crop/display units") }
                case 0xEC, 0xBF: break
                default: throw ParseError.unsupported("video display extension")
                }
            }
            guard let width = video.width, let height = video.height, width > 0, height > 0 else {
                throw ParseError.malformed("missing pixel dimensions")
            }
            guard width <= UInt64(max(0, limits.maximumDimension)),
                  height <= UInt64(max(0, limits.maximumDimension)) else {
                throw ParseError.budgetExceeded("pixel dimensions")
            }
            guard (video.displayWidth ?? width) == width, (video.displayHeight ?? height) == height else {
                throw ParseError.unsupported("non-square display pixels")
            }
            return video
        }

        mutating func parseColour(_ parent: Element) throws -> [UInt64: UInt64] {
            var values: [UInt64: UInt64] = [:]
            var cursor = parent.range.lowerBound
            while cursor < parent.range.upperBound {
                let child = try element(at: &cursor, end: parent.range.upperBound)
                guard values[child.id] == nil else { throw ParseError.malformed("duplicate Colour field") }
                switch child.id {
                case 0x55B1...0x55BB: values[child.id] = try uint(child)
                case 0xEC, 0xBF: break
                default: throw ParseError.unsupported("HDR/Colour extension not preserved by remux")
                }
            }
            return values
        }

        mutating func parseCluster(_ parent: Element) throws -> Int {
            var cursor = parent.range.lowerBound
            var timecode: UInt64?
            var blocks: [(Element, UInt64?, Bool?)] = []
            while cursor < parent.range.upperBound {
                let start = cursor
                let child = try element(at: &cursor, end: parent.range.upperBound, unknownIDs: [0x1F43B675])
                // An unknown-size Cluster ends at the next Segment child. No
                // byte search is used, so compressed payload cannot impersonate it.
                if parent.unknownSize, Self.segmentChildIDs.contains(child.id) { cursor = start; break }
                switch child.id {
                case 0xE7:
                    guard timecode == nil else { throw ParseError.malformed("duplicate cluster timecode") }
                    timecode = try uint(child)
                case 0xA3: blocks.append((child, nil, nil))
                case 0xA0: blocks.append(try parseBlockGroup(child))
                case 0xA7, 0xAB, 0xEC, 0xBF: break
                default: throw ParseError.unsupported("cluster encrypted/extra block")
                }
                guard blocks.count <= limits.maximumPackets - rawPackets.count else {
                    throw ParseError.budgetExceeded("packets")
                }
            }
            guard let timecode, timecode <= UInt64(Int64.max) else {
                throw ParseError.malformed("missing or overflowing cluster timecode")
            }
            for (block, duration, keyframe) in blocks {
                try cancellationCheck()
                rawPackets.append(try parseBlock(block, clusterTime: Int64(timecode), duration: duration, keyframe: keyframe))
            }
            return cursor
        }

        static let segmentChildIDs: Set<UInt64> = [
            0x1F43B675, 0x1549A966, 0x1654AE6B, 0x114D9B74, 0x1C53BB6B,
            0x1254C367, 0x1043A770, 0x1941A469, 0x18538067, 0x1A45DFA3
        ]

        mutating func parseBlockGroup(_ parent: Element) throws -> (Element, UInt64?, Bool?) {
            var cursor = parent.range.lowerBound
            var block: Element?
            var duration: UInt64?
            var hasReference = false
            while cursor < parent.range.upperBound {
                let child = try element(at: &cursor, end: parent.range.upperBound)
                switch child.id {
                case 0xA1:
                    guard block == nil else { throw ParseError.malformed("multiple Blocks in BlockGroup") }
                    block = child
                case 0x9B:
                    guard duration == nil else { throw ParseError.malformed("duplicate BlockDuration") }
                    duration = try uint(child)
                case 0xFB:
                    guard (1...8).contains(child.range.count) else { throw ParseError.malformed("ReferenceBlock integer") }
                    hasReference = true
                case 0xEC, 0xBF: break
                default: throw ParseError.unsupported("BlockGroup additions/state/padding")
                }
            }
            guard let block else { throw ParseError.malformed("BlockGroup missing Block") }
            return (block, duration, !hasReference)
        }

        func parseBlock(_ block: Element, clusterTime: Int64, duration: UInt64?, keyframe: Bool?) throws -> RawPacket {
            var cursor = block.range.lowerBound
            let (track, _) = try vint(at: &cursor, end: block.range.upperBound, isID: false)
            guard track > 0, cursor <= block.range.upperBound - 4 else {
                throw ParseError.malformed("truncated block header/payload")
            }
            let relative = Int64(Int16(bitPattern: UInt16(byte(cursor)) << 8 | UInt16(byte(cursor + 1))))
            let flags = byte(cursor + 2)
            cursor += 3
            guard flags & 0x06 == 0 else { throw ParseError.unsupported("block lacing") }
            guard flags & 0x08 == 0 else { throw ParseError.unsupported("invisible alternate-reference block") }
            guard flags & 0x70 == 0, keyframe == nil || flags & 0x81 == 0 else {
                throw ParseError.malformed("reserved block flags")
            }
            let range = cursor..<block.range.upperBound
            guard range.count <= limits.maximumPacketBytes else { throw ParseError.budgetExceeded("packet bytes") }
            let (timecode, overflow) = clusterTime.addingReportingOverflow(relative)
            guard !overflow, timecode >= 0 else { throw ParseError.malformed("negative/overflowing block timecode") }
            return RawPacket(track: track, range: range, timecode: timecode,
                             duration: duration, keyframe: keyframe ?? (flags & 0x80 != 0))
        }

        mutating func finish() throws -> Video {
            guard let metadata, let number = metadata.number, let video = metadata.video,
                  let width = video.width, let height = video.height, !rawPackets.isEmpty else {
                throw ParseError.malformed("missing track or packets")
            }
            let scale = Int64(timeScale)
            let defaultDuration = try metadata.defaultDuration.map { try boundedNanoseconds($0, scale: 1) }
            let declaredDuration: Int64?
            if let durationTicks {
                let nanoseconds = durationTicks * Double(scale)
                guard nanoseconds.isFinite, nanoseconds > 0,
                      nanoseconds <= Double(limits.maximumDurationNanoseconds),
                      nanoseconds.rounded() < Double(Int64.max) else {
                    throw ParseError.malformed("invalid segment duration")
                }
                declaredDuration = Int64(nanoseconds.rounded())
            } else { declaredDuration = nil }
            var firstHeader: VP9Header?
            var packets: [Packet] = []
            for (index, raw) in rawPackets.enumerated() {
                try cancellationCheck()
                guard raw.track == number else { throw ParseError.malformed("block references another track") }
                let header = try vp9Header(raw.range, isKeyframe: raw.keyframe, expectedProfile: firstHeader?.profile)
                if let header {
                    if let firstHeader, header != firstHeader { throw ParseError.unsupported("VP9 configuration changes") }
                    firstHeader = header
                }
                guard firstHeader != nil, index > 0 || raw.keyframe else {
                    throw ParseError.unsupported("stream does not begin with a VP9 keyframe")
                }
                let pts = try boundedNanoseconds(UInt64(raw.timecode), scale: scale, permitsZero: true)
                guard packets.last.map({ pts > $0.presentationTimeNanoseconds }) ?? true else {
                    throw ParseError.unsupported("non-increasing presentation timestamps")
                }
                let packetDuration: Int64
                if let duration = raw.duration { packetDuration = try boundedNanoseconds(duration, scale: scale) }
                else if let defaultDuration { packetDuration = defaultDuration }
                else if index + 1 < rawPackets.count {
                    let next = rawPackets[index + 1].timecode
                    guard next > raw.timecode else { throw ParseError.unsupported("non-increasing presentation timestamps") }
                    packetDuration = try boundedNanoseconds(UInt64(next - raw.timecode), scale: scale)
                } else if let declaredDuration, declaredDuration > pts { packetDuration = declaredDuration - pts }
                else { throw ParseError.unsupported("last packet duration unavailable") }
                let (end, overflow) = pts.addingReportingOverflow(packetDuration)
                guard !overflow, end <= limits.maximumDurationNanoseconds else {
                    throw ParseError.budgetExceeded("timeline")
                }
                packets.append(Packet(dataRange: raw.range, presentationTimeNanoseconds: pts,
                                      durationNanoseconds: packetDuration, isKeyframe: raw.keyframe))
            }
            guard let firstHeader, firstHeader.width == Int(width), firstHeader.height == Int(height) else {
                throw ParseError.malformed("VP9 dimensions disagree with track")
            }
            let configuration = try configuration(firstHeader, metadata: metadata, colour: video.colour)
            let track = Track(number: number, width: Int(width), height: Int(height),
                              timecodeScaleNanoseconds: scale, defaultDurationNanoseconds: defaultDuration,
                              durationNanoseconds: declaredDuration, vpCodecConfiguration: configuration)
            return Video(track: track, packets: packets)
        }

        func codecFeatures(_ element: Element) throws -> [UInt8: UInt8] {
            var cursor = element.range.lowerBound
            var features: [UInt8: UInt8] = [:]
            while cursor < element.range.upperBound {
                guard cursor <= element.range.upperBound - 3 else { throw ParseError.malformed("CodecPrivate feature") }
                let id = byte(cursor)
                guard (1...4).contains(id), byte(cursor + 1) == 1, features[id] == nil else {
                    throw ParseError.unsupported("CodecPrivate feature encoding")
                }
                features[id] = byte(cursor + 2)
                cursor += 3
            }
            return features
        }

        func configuration(_ header: VP9Header, metadata: TrackMetadata, colour: [UInt64: UInt64]) throws -> Data {
            let features = metadata.codecFeatures
            guard features[1].map({ $0 == header.profile }) ?? true,
                  features[3].map({ $0 == header.bitDepth }) ?? true,
                  features[4].map({ $0 == header.chroma || (header.chroma == 1 && $0 == 0) }) ?? true else {
                throw ParseError.malformed("CodecPrivate contradicts VP9 header")
            }
            let level = features[2] ?? 0 // Level is not in the keyframe header. Zero explicitly means undefined.
            guard [0, 10, 11, 20, 21, 30, 31, 40, 41, 50, 51, 52, 60, 61, 62].contains(level) else {
                throw ParseError.unsupported("VP9 level")
            }
            guard colour[0x55B2].map({ $0 == 0 || $0 == UInt64(header.bitDepth) }) ?? true,
                  colour[0x55B3].map({ $0 == (header.chroma <= 2 ? 1 : 0) }) ?? true,
                  colour[0x55B4].map({ $0 == (header.chroma <= 1 ? 1 : 0) }) ?? true,
                  colour[0x55B5, default: 0] == 0, colour[0x55B6, default: 0] == 0 else {
                throw ParseError.malformed("Colour contradicts VP9 bit depth/subsampling")
            }
            let range = colour[0x55B9, default: 0]
            guard range <= 2, range == 0 || (range == 2) == header.fullRange else {
                throw ParseError.malformed("Colour contradicts VP9 range")
            }
            var chroma = features[4] ?? header.chroma
            let horizontal = colour[0x55B7, default: 0], vertical = colour[0x55B8, default: 0]
            guard horizontal <= 2, vertical <= 2 else { throw ParseError.malformed("invalid chroma siting") }
            if header.chroma == 1, horizontal != 0 || vertical != 0 {
                guard horizontal == 1, [1, 2].contains(vertical) else { throw ParseError.unsupported("chroma siting") }
                chroma = vertical == 1 ? 1 : 0
                guard features[4].map({ $0 == chroma }) ?? true else {
                    throw ParseError.malformed("CodecPrivate contradicts chroma siting")
                }
            }
            // Unspecified fields remain CICP 2, including BT.601's ambiguous
            // PAL/NTSC primaries and BT.2020's transfer. Container colour has
            // independent transfer/primaries (e.g. PQ), unlike the VP9 enum.
            let matrixByColorSpace: [UInt8] = [2, 6, 1, 6, 7, 9, 2, 0]
            let primariesByColorSpace: [UInt8] = [2, 2, 1, 6, 7, 9, 2, 1]
            let transferByColorSpace: [UInt8] = [2, 2, 1, 6, 7, 2, 2, 13]
            let matrix = specifiedColour(colour[0x55B1]) ?? UInt64(matrixByColorSpace[Int(header.colorSpace)])
            let primaries = specifiedColour(colour[0x55BB]) ?? UInt64(primariesByColorSpace[Int(header.colorSpace)])
            let transfer = specifiedColour(colour[0x55BA]) ?? UInt64(transferByColorSpace[Int(header.colorSpace)])
            let compatibleMatrices: [[UInt64]] = [[0, 1, 2, 4, 5, 6, 7, 8, 9, 10], [2, 5, 6],
                                                 [1, 2], [2, 6], [2, 7], [2, 9, 10], [], [0]]
            guard matrix <= 255, primaries <= 255, transfer <= 255,
                  compatibleMatrices[Int(header.colorSpace)].contains(matrix),
                  matrix != 0 || (chroma == 3 && header.fullRange) else {
                throw ParseError.malformed("invalid CICP configuration")
            }
            return Data([1, 0, 0, 0, header.profile, level,
                         header.bitDepth << 4 | chroma << 1 | (header.fullRange ? 1 : 0),
                         UInt8(primaries), UInt8(transfer), UInt8(matrix), 0, 0])
        }

        func specifiedColour(_ value: UInt64?) -> UInt64? { value == 2 ? nil : value }

        func vp9Header(_ range: Range<Int>, isKeyframe: Bool, expectedProfile: UInt8?) throws -> VP9Header? {
            // A superframe can have multiple displayed or invisible frames;
            // this bounded path refuses that timing ambiguity rather than split it.
            let marker = byte(range.upperBound - 1)
            if marker & 0xE0 == 0xC0 {
                let indexSize = 2 + (Int(marker & 7) + 1) * (Int((marker >> 3) & 3) + 1)
                if indexSize <= range.count, byte(range.upperBound - indexSize) == marker {
                    throw ParseError.unsupported("VP9 superframe")
                }
            }
            var bits = Bits(data: data, range: range)
            guard try bits.read(2) == 2 else { throw ParseError.malformed("VP9 frame marker") }
            let low = try bits.read(1), high = try bits.read(1)
            let profile = UInt8(low | high << 1)
            if profile == 3, try bits.read(1) != 0 { throw ParseError.malformed("VP9 reserved profile bit") }
            guard try bits.read(1) == 0 else { throw ParseError.unsupported("VP9 show-existing frame") }
            let keyframe = try bits.read(1) == 0
            guard try bits.read(1) == 1 else { throw ParseError.unsupported("VP9 hidden frame") }
            _ = try bits.read(1) // error_resilient_mode does not change packet/time identity.
            guard keyframe == isKeyframe else { throw ParseError.malformed("block/VP9 keyframe disagreement") }
            if !keyframe {
                guard expectedProfile == nil || expectedProfile == profile else {
                    throw ParseError.unsupported("VP9 profile changes")
                }
                return nil
            }
            guard try bits.read(24) == 0x498342 else { throw ParseError.malformed("VP9 sync code") }
            let depth: UInt8 = profile >= 2 ? (try bits.read(1) == 0 ? 10 : 12) : 8
            let colorSpace = UInt8(try bits.read(3))
            guard colorSpace != 6 else { throw ParseError.malformed("VP9 reserved color space") }
            let fullRange: Bool
            var x: UInt32 = 1, y: UInt32 = 1
            if colorSpace != 7 {
                fullRange = try bits.read(1) != 0
                if profile & 1 != 0 {
                    x = try bits.read(1); y = try bits.read(1)
                    guard try bits.read(1) == 0, !(x == 1 && y == 1) else {
                        throw ParseError.malformed("VP9 profile subsampling/reserved bit")
                    }
                }
            } else {
                guard profile & 1 != 0, try bits.read(1) == 0 else { throw ParseError.malformed("VP9 RGB profile") }
                x = 0; y = 0; fullRange = true
            }
            guard !(x == 0 && y == 1) else { throw ParseError.unsupported("VP9 4:4:0 chroma") }
            let chroma: UInt8 = x == 1 ? (y == 1 ? 1 : 2) : 3
            let width = Int(try bits.read(16)) + 1, height = Int(try bits.read(16)) + 1
            if try bits.read(1) != 0 {
                let renderWidth = Int(try bits.read(16)) + 1, renderHeight = Int(try bits.read(16)) + 1
                guard renderWidth == width, renderHeight == height else { throw ParseError.unsupported("VP9 render dimensions") }
            }
            return VP9Header(profile: profile, bitDepth: depth, chroma: chroma, fullRange: fullRange,
                             colorSpace: colorSpace, width: width, height: height)
        }

        func boundedNanoseconds(_ value: UInt64, scale: Int64, permitsZero: Bool = false) throws -> Int64 {
            guard value <= UInt64(Int64.max), scale > 0 else { throw ParseError.malformed("timestamp integer overflow") }
            let (result, overflow) = Int64(value).multipliedReportingOverflow(by: scale)
            guard !overflow, result >= (permitsZero ? 0 : 1) else { throw ParseError.malformed("timestamp/duration overflow") }
            guard result <= limits.maximumDurationNanoseconds else { throw ParseError.budgetExceeded("timeline") }
            return result
        }

        mutating func element(at cursor: inout Int, end: Int, unknownIDs: Set<UInt64> = []) throws -> Element {
            try cancellationCheck()
            elementCount += 1
            guard elementCount <= limits.maximumElements else { throw ParseError.budgetExceeded("elements") }
            let (id, _) = try vint(at: &cursor, end: end, isID: true)
            let (size, unknown) = try vint(at: &cursor, end: end, isID: false)
            if unknown {
                guard unknownIDs.contains(id) else { throw ParseError.unsupported("unknown size on non-Segment/Cluster") }
                let result = Element(id: id, range: cursor..<end, unknownSize: true)
                cursor = end
                return result
            }
            guard size <= UInt64(end - cursor) else { throw ParseError.malformed("element exceeds parent range") }
            let range = cursor..<(cursor + Int(size))
            cursor = range.upperBound
            return Element(id: id, range: range, unknownSize: false)
        }

        func vint(at cursor: inout Int, end: Int, isID: Bool) throws -> (UInt64, Bool) {
            guard cursor < end else { throw ParseError.malformed("truncated VINT") }
            let first = byte(cursor)
            guard first != 0 else { throw ParseError.malformed("zero VINT marker") }
            let length = first.leadingZeroBitCount + 1
            guard length <= (isID ? maximumIDLength : maximumSizeLength),
                  length <= end - cursor else { throw ParseError.malformed("VINT length") }
            let marker = UInt8(0x80 >> (length - 1))
            var value = UInt64(isID ? first : first & (marker - 1))
            for offset in 1..<length { value = value << 8 | UInt64(byte(cursor + offset)) }
            cursor += length
            let maximum = (UInt64(1) << (7 * length)) - 1
            return (value, !isID && value == maximum)
        }

        func uint(_ element: Element) throws -> UInt64 {
            guard element.range.count <= 8 else { throw ParseError.malformed("unsigned integer width") }
            return element.range.reduce(UInt64(0)) { $0 << 8 | UInt64(byte($1)) }
        }

        func floating(_ element: Element) throws -> Double {
            switch element.range.count {
            case 4: return Double(Float(bitPattern: UInt32(try uint(element))))
            case 8: return Double(bitPattern: try uint(element))
            default: throw ParseError.malformed("float width")
            }
        }

        func string(_ element: Element) throws -> String {
            guard element.range.count <= 256,
                  let string = String(data: data.subdata(in: shifted(element.range)), encoding: .utf8) else {
                throw ParseError.malformed("string encoding/length")
            }
            return string
        }

        func unique(_ id: UInt64, seen: inout Set<UInt64>) throws {
            guard id == 0xEC || id == 0xBF || seen.insert(id).inserted else {
                throw ParseError.malformed("duplicate metadata field")
            }
        }

        func shifted(_ range: Range<Int>) -> Range<Int> {
            (data.startIndex + range.lowerBound)..<(data.startIndex + range.upperBound)
        }

        func byte(_ offset: Int) -> UInt8 { data[data.startIndex + offset] }
    }

    private struct Bits {
        let data: Data
        let range: Range<Int>
        var position = 0

        mutating func read(_ count: Int) throws -> UInt32 {
            guard count <= 32, position <= range.count * 8 - count else {
                throw ParseError.malformed("truncated VP9 uncompressed header")
            }
            var result: UInt32 = 0
            for _ in 0..<count {
                let value = data[data.startIndex + range.lowerBound + position / 8]
                result = result << 1 | UInt32(value >> (7 - position % 8) & 1)
                position += 1
            }
            return result
        }
    }
}
