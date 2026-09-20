//
//  SteamWorkshopQueryClient.swift
//  MyWallpaperX
//

import Foundation

/// SK3.1：结构化查询的 Swift 侧模型（helper IPC 是唯一数据源；无 UI 缓存）。
struct SteamWorkshopQueryItem: Equatable {
    let publishedFileId: String
    let creatorSteamId: String?
    let title: String
    let description: String?
    let previewUrl: String?
    let fileSize: Int?
    let timeUpdated: Int?
    let timeCreated: Int?
    let timeSubscribed: Int?
    let consumerAppId: Int?
    let visibility: Int?
    let banned: Bool?
    let banReason: String?
    let subscriptions: Int?
    let favorited: Int?
    let lifetimeSubscriptions: Int?
    let lifetimeFavorited: Int?
    let views: Int?
    let dependencyIds: [String]
    let tags: [String]
    var creatorName: String? = nil
}

struct SteamWorkshopQueryPage: Equatable {
    let page: Int
    let total: Int
    let hasMore: Bool
    let items: [SteamWorkshopQueryItem]
    let wrongAppDropped: Int
    /// 单条目级错误（详情批中已删除/私有条目等）；页面级失败走 throws。
    let partialErrors: [SteamWorkshopPartialError]

    struct SteamWorkshopPartialError: Equatable {
        let publishedFileId: String
        let code: String
    }
}

enum SteamWorkshopQuerySort: String {
    case newest
    case updated // helper SortMap: query_type 21（2026-09-16 匿名链实测可用）
    case trend
    case subscriptions
    case votes
}

/// Stable filesystem identity for one helper-owned staging lease. A lexical
/// `job-*` name is not ownership: the name may be replaced before cleanup.
nonisolated struct SteamWorkshopStagingLeaseIdentity: Codable, Equatable, Sendable {
    let device: UInt64
    let inode: UInt64
}

/// helper 的下载完成凭证；只证明协议字段一致，不等于磁盘内容或入库成功。
/// 入库 owner 必须重新验收文件及项目内容，并在提交前复核账号/作业身份。
nonisolated struct SteamWorkshopStagedReceipt: Equatable, Codable, Sendable {
    let version: Int
    let contentDigest: String
    let jobId: String
    let workshopId: String
    let accountSteamId: String
    let accountEpoch: Int
    let manifestId: String
    let stagingURL: URL
    let verifiedBytes: Int
    /// Optional only for decoding pre-v4 durable jobs. New receipts always bind
    /// the helper lease path to its exact filesystem identity.
    let stagingLeaseIdentity: SteamWorkshopStagingLeaseIdentity?

    /// Validate the helper-owned lease name lexically. Filesystem canonicalization is
    /// deliberately excluded because it can rewrite `/private/tmp` and would also
    /// turn validation into an implicit path-adoption operation.
    nonisolated static func validatedStagingURL(path: String, stagingRoot: String) -> URL? {
        guard stagingRoot.hasPrefix("/"), path.hasPrefix("/"),
              !stagingRoot.utf8.contains(0), !path.utf8.contains(0) else { return nil }
        let base = stagingRoot.replacingOccurrences(of: #"/+$"#, with: "", options: .regularExpression)
        let components = base.dropFirst().split(separator: "/", omittingEmptySubsequences: false)
        guard !base.isEmpty, components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }),
              path.hasPrefix(base + "/") else { return nil }
        let name = String(path.dropFirst(base.count + 1))
        guard name.hasPrefix("job-"), name.utf8.count == 36,
              name.dropFirst(4).utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) })
        else { return nil }
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    @MainActor init(frame: SteamServiceFrame, jobId: String, workshopId: String,
         accountSteamId: String, accountEpoch: Int, stagingRoot: String) throws {
        func validID(_ value: String) -> Bool {
            !value.isEmpty && value.utf8.allSatisfy { (48...57).contains($0) }
                && (UInt64(value) ?? 0) > 0
        }
        let invalid = SteamServiceClient.RequestError.helperError(
            code: "integrity", message: "下载完成凭证不完整或与当前任务不一致。")
        guard frame.isTerminal, frame.ok == true, frame.accountEpoch == accountEpoch,
              let data = frame.root["data"]?.objectValue,
              data["receiptVersion"]?.intValue == 2,
              let digest = data["contentDigest"]?.stringValue, digest.utf8.count == 64,
              digest.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }),
              data["stagedComplete"]?.boolValue == true,
              !jobId.isEmpty, data["jobId"]?.stringValue == jobId,
              validID(workshopId), data["workshopId"]?.stringValue == workshopId,
              validID(accountSteamId), data["accountSteamId"]?.stringValue == accountSteamId,
              let manifestId = data["manifestId"]?.stringValue, validID(manifestId),
              data["projectJsonPresent"]?.boolValue == true,
              let stagingDeviceText = data["stagingDevice"]?.stringValue,
              let stagingDevice = UInt64(stagingDeviceText),
              let stagingInodeText = data["stagingInode"]?.stringValue,
              let stagingInode = UInt64(stagingInodeText), stagingInode > 0,
              let total = data["totalBytes"]?.intValue, total > 0, total <= 8 * 1024 * 1024 * 1024,
              data["verifiedBytes"]?.intValue == total,
              let path = data["stagingPath"]?.stringValue,
              let url = Self.validatedStagingURL(path: path, stagingRoot: stagingRoot) else { throw invalid }
        self.version = 2
        self.contentDigest = digest
        self.jobId = jobId
        self.workshopId = workshopId
        self.accountSteamId = accountSteamId
        self.accountEpoch = accountEpoch
        self.manifestId = manifestId
        self.stagingURL = url
        self.verifiedBytes = total
        self.stagingLeaseIdentity = SteamWorkshopStagingLeaseIdentity(
            device: stagingDevice,
            inode: stagingInode
        )
    }
}

/// SK3.1：统一结构化查询消费 API。排序/筛选/分页合同见
/// 计划 §4.1 与 SK0.1 能力表（页码分页、hasMore=received==pageSize、days 缺口）。
@MainActor
final class SteamWorkshopQueryClient {
    private let client: SteamServiceClient

    init(client: SteamServiceClient) {
        self.client = client
    }

    /// tagGroups 语义（2026-09-16 SK0.1 探针实测）：组内任一 tag 命中即算
    /// 命中（组内 OR），组与组之间要求全部命中（跨组 AND）。
    func browse(
        sort: SteamWorkshopQuerySort,
        page: Int,
        tags: [String] = [],
        tagGroups: [[String]] = [],
        search: String? = nil
    ) async throws -> SteamWorkshopQueryPage {
        var fields: [String: SteamServiceJSON] = [
            "sort": .string(sort.rawValue),
            "page": .int(page),
        ]
        if !tags.isEmpty {
            fields["tags"] = .array(tags.map(SteamServiceJSON.string))
        }
        if !tagGroups.isEmpty {
            fields["tagGroups"] = .array(tagGroups.map { group in
                .array(group.map(SteamServiceJSON.string))
            })
        }
        if let search, !search.isEmpty {
            fields["search"] = .string(search)
        }
        let frame = try await client.request(
            command: "queryBrowse",
            payload: .object(fields)
        )
        return try decodePage(from: frame, expectedPage: page)
    }

    func details(ids: [String]) async throws -> SteamWorkshopQueryPage {
        let frame = try await client.request(
            command: "queryDetails",
            payload: .object(["ids": .array(ids.map(SteamServiceJSON.string))])
        )
        return try decodePage(from: frame, expectedPage: 0)
    }

    /// 作者工坊（GetUserFiles 以作者 steamid 查询）。
    func author(creatorSteamId: String, page: Int) async throws -> SteamWorkshopQueryPage {
        let frame = try await client.request(
            command: "queryAuthor",
            payload: .object([
                "creatorSteamId": .string(creatorSteamId),
                "page": SteamServiceJSON.int(page),
            ])
        )
        return try decodePage(from: frame, expectedPage: page)
    }

    /// 已订阅列表（需登录）。
    func subscriptions(page: Int) async throws -> SteamWorkshopQueryPage {
        let frame = try await client.request(
            command: "listSubscriptions",
            payload: .object(["page": SteamServiceJSON.int(page)])
        )
        return try decodePage(from: frame, expectedPage: page)
    }

    /// 收藏 ID 列表（需登录；ids_only）。
    func favoriteIds(page: Int) async throws -> (ids: [String], total: Int, hasMore: Bool) {
        let frame = try await client.request(
            command: "listFavorites",
            payload: .object(["page": SteamServiceJSON.int(page)])
        )
        let data = try resultData(frame)
        guard let values = data["ids"]?.arrayValue,
              data["page"]?.intValue == page,
              let total = data["total"]?.intValue, total >= 0,
              let hasMore = data["hasMore"]?.boolValue else { throw malformed }
        let ids = try values.map { value -> String in
            guard let id = value.stringValue, validID(id) else { throw malformed }
            return id
        }
        guard Set(ids).count == ids.count else { throw malformed }
        return (ids, total, hasMore)
    }

    /// 订阅写入（SK3.3）：desiredState 单次写；调用方随后用
    /// subscriptionStates 对账确认。
    func setSubscription(workshopId: String, subscribe: Bool) async throws {
        let frame = try await client.request(
            command: "setSubscription",
            payload: .object([
                "workshopId": .string(workshopId),
                "desiredState": .string(subscribe ? "subscribe" : "unsubscribe"),
            ])
        )
        let data = try resultData(frame)
        guard data["workshopId"]?.stringValue == workshopId,
              data["desiredState"]?.stringValue == (subscribe ? "subscribe" : "unsubscribe"),
              data["confirmed"]?.boolValue == true else { throw malformed }
    }

    // MARK: - SK4.2 分级下载（staged；入库归 SK4.3）

    /// 发起 helper 下载：授权→manifest→有界 chunk→校验→stagedComplete。
    /// 进度经事件观察者（downloadProgress）；终态为本调用返回。
    /// timeout 为 nil：下载不受请求超时约束，取消走 cancelStagedDownload。
    func startStagedDownload(
        jobId: String,
        workshopId: String,
        accountSteamId: String,
        stagingRoot: String,
        resumeStagingPath: String? = nil,
        resumeManifestId: String? = nil,
        resumeStagingLeaseIdentity: SteamWorkshopStagingLeaseIdentity? = nil
    ) async throws -> SteamWorkshopStagedReceipt {
        let epoch = client.accountEpoch
        var payload: [String: SteamServiceJSON] = [
            "workshopId": .string(workshopId),
            "stagingRoot": .string(stagingRoot),
        ]
        let resumeFieldCount = [
            resumeStagingPath != nil,
            resumeManifestId != nil,
            resumeStagingLeaseIdentity != nil,
        ].filter { $0 }.count
        guard resumeFieldCount == 0 || resumeFieldCount == 3 else { throw malformed }
        if let resumeStagingPath, let resumeManifestId, let resumeStagingLeaseIdentity {
            payload["resumeStagingPath"] = .string(resumeStagingPath)
            payload["resumeManifestId"] = .string(resumeManifestId)
            payload["resumeStagingDevice"] = .string(String(resumeStagingLeaseIdentity.device))
            payload["resumeStagingInode"] = .string(String(resumeStagingLeaseIdentity.inode))
        }
        // Keep the start request alive after the caller is cancelled. The helper's
        // original terminal is the physical-drain acknowledgement; the separate
        // cancelDownload response only says that cancellation was accepted.
        let requestTask = Task { @MainActor [client] in
            try await client.request(
                command: "startDownload",
                jobId: jobId,
                payload: .object(payload),
                private: nil,
                timeout: nil,
                awaitRemoteTerminalAcrossAccountEpochChanges: true
            )
        }
        let frame = try await withTaskCancellationHandler {
            try await requestTask.value
        } onCancel: {
            Task { @MainActor [client] in
                _ = try? await client.request(command: "cancelDownload", jobId: jobId)
            }
        }
        try Task.checkCancellation()
        guard client.accountEpoch == epoch else { throw CancellationError() }
        return try SteamWorkshopStagedReceipt(frame: frame, jobId: jobId, workshopId: workshopId,
            accountSteamId: accountSteamId, accountEpoch: epoch, stagingRoot: stagingRoot)
    }

    /// 取消在途分级下载；helper 以 cancelled terminal 收口该请求。
    /// jobId 与 startDownload 一致放信封（helper 的 cancelDownload 只读信封字段）。
    func cancelStagedDownload(jobId: String) async throws {
        _ = try await client.request(command: "cancelDownload", jobId: jobId)
    }

    /// Release the helper's pre-write barrier only after the App has persisted
    /// the exact lease identity for this logical attempt.
    func acknowledgeStagedDownload(
        jobId: String,
        stagingPath: String,
        manifestId: String,
        stagingLeaseIdentity: SteamWorkshopStagingLeaseIdentity
    ) async throws {
        let frame = try await client.request(
            command: "acknowledgeDownloadStaging",
            jobId: jobId,
            payload: .object([
                "stagingPath": .string(stagingPath),
                "manifestId": .string(manifestId),
                "stagingDevice": .string(String(stagingLeaseIdentity.device)),
                "stagingInode": .string(String(stagingLeaseIdentity.inode)),
            ])
        )
        let data = try resultData(frame)
        guard data["acknowledged"]?.boolValue == true else { throw malformed }
    }

    /// 订阅状态批量核对（需登录）。
    func subscriptionStates(ids: [String]) async throws -> [String: Bool] {
        let frame = try await client.request(
            command: "querySubscriptionStates",
            payload: .object(["ids": .array(ids.map(SteamServiceJSON.string))])
        )
        let data = try resultData(frame)
        guard let states = data["states"]?.objectValue, Set(states.keys) == Set(ids) else { throw malformed }
        var result: [String: Bool] = [:]
        for (id, value) in states {
            guard validID(id), let state = value.boolValue else { throw malformed }
            result[id] = state
        }
        return result
    }

    // MARK: - 解码

    private var malformed: SteamServiceClient.RequestError {
        .helperError(code: "protocolMismatch", message: "Steam 查询结果不完整，原列表已保留，请重试。")
    }

    private func validID(_ id: String) -> Bool {
        !id.isEmpty && id.utf8.allSatisfy { (48...57).contains($0) } && (UInt64(id) ?? 0) > 0
    }

    private func resultData(_ frame: SteamServiceFrame) throws -> [String: SteamServiceJSON] {
        guard frame.isTerminal, frame.ok == true, let data = frame.root["data"]?.objectValue else { throw malformed }
        return data
    }

    private func decodePage(from frame: SteamServiceFrame, expectedPage: Int) throws -> SteamWorkshopQueryPage {
        let data = try resultData(frame)
        guard let values = data["items"]?.arrayValue,
              data["page"]?.intValue == expectedPage,
              let total = data["total"]?.intValue, total >= 0,
              let hasMore = data["hasMore"]?.boolValue,
              let wrongApp = data["wrongAppDropped"]?.intValue, wrongApp >= 0 else { throw malformed }
        let items = try values.map { value -> SteamWorkshopQueryItem in
            guard let object = value.objectValue,
                  let id = object["publishedfileid"]?.stringValue, validID(id),
                  let title = object["title"]?.stringValue,
                  object["consumerAppid"]?.intValue == 431960,
                  let dependencyValues = object["dependencyIds"]?.arrayValue,
                  let tagValues = object["tags"]?.arrayValue else { throw malformed }
            for key in ["fileSize", "timeUpdated", "timeCreated", "timeSubscribed", "visibility",
                        "subscriptions", "favorited", "lifetimeSubscriptions", "lifetimeFavorited", "views"] {
                if let value = object[key], value != .null {
                    guard let number = value.intValue, number >= 0 else { throw malformed }
                }
            }
            if let preview = object["previewUrl"], preview != .null, preview.stringValue == nil { throw malformed }
            for key in ["description", "banReason"] {
                if let value = object[key], value != .null, value.stringValue == nil { throw malformed }
            }
            if let banned = object["banned"], banned != .null, banned.boolValue == nil { throw malformed }
            if let creator = object["creatorSteamId"], creator != .null, creator.stringValue == nil {
                throw malformed
            }
            if let name = object["creatorName"], name != .null, name.stringValue == nil { throw malformed }
            let creatorName = object["creatorName"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines)
            let creatorSteamId = object["creatorSteamId"]?.stringValue
            if let creatorSteamId, !validID(creatorSteamId) { throw malformed }
            let tags = try tagValues.map { tag -> String in
                guard let text = tag.stringValue else { throw malformed }; return text
            }
            let dependencyIds = try dependencyValues.map { dependency -> String in
                guard let id = dependency.stringValue, validID(id) else { throw malformed }
                return id
            }
            guard Set(dependencyIds).count == dependencyIds.count else { throw malformed }
            return SteamWorkshopQueryItem(publishedFileId: id, creatorSteamId: creatorSteamId, title: title,
                description: object["description"]?.stringValue,
                previewUrl: object["previewUrl"]?.stringValue, fileSize: object["fileSize"]?.intValue,
                timeUpdated: object["timeUpdated"]?.intValue, timeCreated: object["timeCreated"]?.intValue,
                timeSubscribed: object["timeSubscribed"]?.intValue,
                consumerAppId: 431960, visibility: object["visibility"]?.intValue,
                banned: object["banned"]?.boolValue, banReason: object["banReason"]?.stringValue,
                subscriptions: object["subscriptions"]?.intValue,
                favorited: object["favorited"]?.intValue,
                lifetimeSubscriptions: object["lifetimeSubscriptions"]?.intValue,
                lifetimeFavorited: object["lifetimeFavorited"]?.intValue,
                views: object["views"]?.intValue, dependencyIds: dependencyIds, tags: tags, creatorName: creatorName?.isEmpty == false ? creatorName : nil)
        }
        guard Set(items.map(\.publishedFileId)).count == items.count else { throw malformed }
        let partial: [SteamServiceJSON]
        if let value = data["partial"], value != .null {
            guard let array = value.arrayValue else { throw malformed }; partial = array
        } else { partial = [] }
        let errors = try partial.map { value -> SteamWorkshopQueryPage.SteamWorkshopPartialError in
            guard let object = value.objectValue,
                  let id = object["publishedfileid"]?.stringValue, validID(id),
                  let code = object["code"]?.stringValue, !code.isEmpty else { throw malformed }
            return .init(publishedFileId: id, code: code)
        }
        return SteamWorkshopQueryPage(page: expectedPage, total: total, hasMore: hasMore,
            items: items, wrongAppDropped: wrongApp, partialErrors: errors)
    }
}

private extension SteamServiceJSON {
    var arrayValue: [SteamServiceJSON]? {
        if case .array(let value) = self { return value }
        return nil
    }
}
