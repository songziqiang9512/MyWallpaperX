import Foundation

/// §6 SteamService 线协议（SK1.1）的 Swift 侧消息与解码合同。
///
/// 帧为 UTF-8 NDJSON 单行；64 位 ID（steamId/workshopId/manifestId）一律十进制字符串；
/// 凭据只允许出现在 `private` 包装对象内，进入日志前必须先脱敏。
/// 错误码 taxonomy 与 `script/tests/fixtures/steam-protocol/error-codes.json` 保持一致
/// （C# 侧 `ProtocolErrorCodes.Codes` 与此数组同序）。
enum SteamServiceProtocol {
    static let version = 1
    static let maxFrameBytes = 1_048_576
    static let maxPendingRequests = 256
    static let requestTimeout: TimeInterval = 30

    static let errorCodes: [String] = [
        "network",
        "rateLimited",
        "authExpired",
        "invalidChallenge",
        "accessDenied",
        "unsupportedQuery",
        "unsupportedContent",
        "diskFull",
        "integrity",
        "cancelled",
        "protocolMismatch",
        "helperUnavailable",
    ]

    static func isValidErrorCode(_ code: String) -> Bool {
        errorCodes.contains(code)
    }
}

/// 出站帧构造（App → helper 的 request；Swift 侧不构造 result/event）。
enum SteamServiceRequestBuilder {
    static func ping(requestId: String, processEpoch: Int, accountEpoch: Int) -> Data? {
        encode([
            "v": .int(SteamServiceProtocol.version),
            "type": .string("request"),
            "requestId": .string(requestId),
            "command": .string("ping"),
            "processEpoch": .int(processEpoch),
            "accountEpoch": .int(accountEpoch),
        ])
    }

    static func shutdown(requestId: String, processEpoch: Int, accountEpoch: Int) -> Data? {
        encode([
            "v": .int(SteamServiceProtocol.version),
            "type": .string("request"),
            "requestId": .string(requestId),
            "command": .string("shutdown"),
            "processEpoch": .int(processEpoch),
            "accountEpoch": .int(accountEpoch),
        ])
    }

    /// 通用请求：payload 的字段名由各命令卡（SK2+）定义，此处只负责 envelope 合同。
    static func request(
        requestId: String,
        command: String,
        processEpoch: Int,
        accountEpoch: Int,
        authAttemptId: String? = nil,
        queryGeneration: Int? = nil,
        cursor: String? = nil,
        jobId: String? = nil,
        attempt: Int? = nil,
        payload: SteamServiceJSON? = nil
    ) -> Data? {
        var fields: [String: SteamServiceJSON] = [
            "v": .int(SteamServiceProtocol.version),
            "type": .string("request"),
            "requestId": .string(requestId),
            "command": .string(command),
            "processEpoch": .int(processEpoch),
            "accountEpoch": .int(accountEpoch),
        ]
        if let authAttemptId { fields["authAttemptId"] = .string(authAttemptId) }
        if let queryGeneration { fields["queryGeneration"] = .int(queryGeneration) }
        if let cursor { fields["cursor"] = .string(cursor) }
        if let jobId { fields["jobId"] = .string(jobId) }
        if let attempt { fields["attempt"] = .int(attempt) }
        if let payload { fields["payload"] = payload }
        return encode(fields)
    }

    private static func encode(_ frame: [String: SteamServiceJSON]) -> Data? {
        var data = try? JSONEncoder().encode(SteamServiceJSON.object(frame))
        data?.append(0x0A)
        return data
    }
}

/// 协议层错误（与 C# ProtocolDecode 的拒绝原因一一对应）。
enum SteamServiceFrameError: Error, Equatable {
    case badJSON
    case notAnObject
    case unsupportedVersion
    case missingType
    case requestWithoutRequestId
    case requestWithoutCommand
    case resultWithoutRequestId
    case resultWithoutOkFlag
    case resultWithoutTaxonomyCode
    case eventWithoutName
    case unknownType(String)
}

/// 入站帧（helper → App 的 result/event/ready）。
struct SteamServiceFrame: Equatable {
    var requestId: String?
    var command: String?
    var event: String?
    var sequence: Int?
    var processEpoch: Int?
    var accountEpoch: Int?
    var authAttemptId: String?
    var queryGeneration: Int?
    var cursor: String?
    var jobId: String?
    var attempt: Int?
    var ok: Bool?
    var error: ProtocolErrorPayload?
    var root: [String: SteamServiceJSON]
    var frameType: String

    struct ProtocolErrorPayload: Equatable {
        let code: String
        let message: String
    }

    /// 该帧是否为 requestId 的终态（type=result）；终态每 requestId 至多一个，由客户端去重。
    var isTerminal: Bool { frameType == "result" }
}

enum SteamServiceFrameDecoder {
    /// 解码单帧；失败返回协议层错误，调用方必须有界处理（不得锁死读取循环）。
    static func decode(_ line: String) -> Result<SteamServiceFrame, SteamServiceFrameError> {
        guard let data = line.data(using: .utf8) else { return .failure(.badJSON) }
        return decode(data)
    }

    static func decode(_ data: Data) -> Result<SteamServiceFrame, SteamServiceFrameError> {
        guard let json = try? JSONDecoder().decode(SteamServiceJSON.self, from: data) else {
            return .failure(.badJSON)
        }
        guard case .object(let root) = json else { return .failure(.notAnObject) }
        guard case .int(let version) = root["v"] ?? .null, version == SteamServiceProtocol.version else {
            return .failure(.unsupportedVersion)
        }
        guard case .string(let frameType)? = root["type"] else { return .failure(.missingType) }

        var frame = SteamServiceFrame(root: root, frameType: frameType)
        switch frameType {
        case "request":
            guard case .string(let requestId)? = root["requestId"], !requestId.isEmpty else {
                return .failure(.requestWithoutRequestId)
            }
            guard case .string(let command)? = root["command"], !command.isEmpty else {
                return .failure(.requestWithoutCommand)
            }
            frame.requestId = requestId
            frame.command = command
        case "result":
            guard case .string(let requestId)? = root["requestId"] else {
                return .failure(.resultWithoutRequestId)
            }
            guard case .bool(let ok)? = root["ok"] else {
                return .failure(.resultWithoutOkFlag)
            }
            if !ok {
                guard case .object(let error)? = root["error"],
                      case .string(let code)? = error["code"],
                      SteamServiceProtocol.isValidErrorCode(code) else {
                    return .failure(.resultWithoutTaxonomyCode)
                }
                let message: String
                if case .string(let text)? = error["message"] {
                    message = text
                } else {
                    message = ""
                }
                frame.error = SteamServiceFrame.ProtocolErrorPayload(code: code, message: message)
            }
            frame.requestId = requestId
            frame.ok = ok
        case "event":
            guard case .string(let event)? = root["event"], !event.isEmpty else {
                return .failure(.eventWithoutName)
            }
            frame.event = event
            if case .int(let sequence)? = root["sequence"] { frame.sequence = sequence }
        case "ready":
            break
        default:
            return .failure(.unknownType(frameType))
        }

        if case .int(let processEpoch)? = root["processEpoch"] { frame.processEpoch = processEpoch }
        if case .int(let accountEpoch)? = root["accountEpoch"] { frame.accountEpoch = accountEpoch }
        if case .string(let authAttemptId)? = root["authAttemptId"] { frame.authAttemptId = authAttemptId }
        if case .int(let queryGeneration)? = root["queryGeneration"] { frame.queryGeneration = queryGeneration }
        if case .string(let cursor)? = root["cursor"] { frame.cursor = cursor }
        if case .string(let jobId)? = root["jobId"] { frame.jobId = jobId }
        if case .int(let attempt)? = root["attempt"] { frame.attempt = attempt }
        return .success(frame)
    }
}

/// 有界 NDJSON 分帧读取：半包/多包正确；单帧超限即报错并由调用方有界终止。
final class SteamServiceFrameReader {
    enum Outcome: Equatable { case frame, eof, overlong }

    private(set) var lastOutcome: Outcome = .frame
    private var pending = Data()
    private let stream: ReadableStream

    protocol ReadableStream {
        func read(into buffer: UnsafeMutablePointer<UInt8>, count: Int) throws -> Int
    }

    init(stream: ReadableStream) {
        self.stream = stream
    }

    /// 读取一帧（不含换行）；返回 nil 表示 EOF 或超长（检查 lastOutcome）。
    func readFrame() throws -> String? {
        while true {
            if let newline = pending.firstIndex(of: 0x0A) {
                let frameData = pending.subdata(in: pending.startIndex..<newline)
                pending.removeSubrange(pending.startIndex...newline)
                if frameData.count > SteamServiceProtocol.maxFrameBytes {
                    lastOutcome = .overlong
                    return nil
                }
                lastOutcome = .frame
                return String(data: frameData, encoding: .utf8)
            }
            if pending.count > SteamServiceProtocol.maxFrameBytes {
                pending.removeAll()
                lastOutcome = .overlong
                return nil
            }
            var chunk = [UInt8](repeating: 0, count: 65_536)
            let read = try chunk.withUnsafeMutableBufferPointer { buffer in
                try stream.read(into: buffer.baseAddress!, count: buffer.count)
            }
            if read == 0 {
                let hadPartial = !pending.isEmpty
                pending.removeAll()
                lastOutcome = hadPartial ? .overlong : .eof
                return nil
            }
            pending.append(contentsOf: chunk[0..<read])
        }
    }
}

/// JSON 值容器：data/payload 等开放字段按合同原样保留，不做语义解释。
indirect enum SteamServiceJSON: Equatable {
    case null
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case array([SteamServiceJSON])
    case object([String: SteamServiceJSON])

    var stringValue: String? {
        if case .string(let value) = self { return value }
        return nil
    }

    var intValue: Int? {
        if case .int(let value) = self { return value }
        return nil
    }

    var boolValue: Bool? {
        if case .bool(let value) = self { return value }
        return nil
    }

    var objectValue: [String: SteamServiceJSON]? {
        if case .object(let value) = self { return value }
        return nil
    }
}

extension SteamServiceJSON: Decodable {
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int.self) {
            self = .int(value)
        } else if let value = try? container.decode(Double.self) {
            self = .double(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([SteamServiceJSON].self) {
            self = .array(value)
        } else if let value = try? container.decode([String: SteamServiceJSON].self) {
            self = .object(value)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "unsupported json value")
        }
    }
}

extension SteamServiceJSON: Encodable {
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let value): try container.encode(value)
        case .int(let value): try container.encode(value)
        case .double(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }
}
