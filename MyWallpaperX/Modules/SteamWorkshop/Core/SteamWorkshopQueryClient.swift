//
//  SteamWorkshopQueryClient.swift
//  MyWallpaperX
//

import Foundation

/// SK3.1：结构化查询的 Swift 侧模型（helper IPC 是唯一数据源；无 UI 缓存）。
struct SteamWorkshopQueryItem: Equatable {
    let publishedFileId: String
    let title: String
    let previewUrl: String?
    let fileSize: Int?
    let timeUpdated: Int?
    let timeCreated: Int?
    let timeSubscribed: Int?
    let consumerAppId: Int?
    let tags: [String]
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
    case trend
    case subscriptions
    case votes
}

/// SK3.1：统一结构化查询消费 API。排序/筛选/分页合同见
/// 计划 §4.1 与 SK0.1 能力表（页码分页、hasMore=received==pageSize、days 缺口）。
@MainActor
final class SteamWorkshopQueryClient {
    private let client: SteamServiceClient

    init(client: SteamServiceClient) {
        self.client = client
    }

    func browse(
        sort: SteamWorkshopQuerySort,
        page: Int,
        tags: [String] = [],
        search: String? = nil
    ) async throws -> SteamWorkshopQueryPage {
        var fields: [String: SteamServiceJSON] = [
            "sort": .string(sort.rawValue),
            "page": .int(page),
        ]
        if !tags.isEmpty {
            fields["tags"] = .array(tags.map(SteamServiceJSON.string))
        }
        if let search, !search.isEmpty {
            fields["search"] = .string(search)
        }
        let frame = try await client.request(
            command: "queryBrowse",
            payload: .object(fields)
        )
        return try decodePage(from: frame)
    }

    func details(ids: [String]) async throws -> SteamWorkshopQueryPage {
        let frame = try await client.request(
            command: "queryDetails",
            payload: .object(["ids": .array(ids.map(SteamServiceJSON.string))])
        )
        return try decodePage(from: frame)
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
        return try decodePage(from: frame)
    }

    /// 已订阅列表（需登录）。
    func subscriptions(page: Int) async throws -> SteamWorkshopQueryPage {
        let frame = try await client.request(
            command: "listSubscriptions",
            payload: .object(["page": SteamServiceJSON.int(page)])
        )
        return try decodePage(from: frame)
    }

    /// 收藏 ID 列表（需登录；ids_only）。
    func favoriteIds(page: Int) async throws -> (ids: [String], total: Int, hasMore: Bool) {
        let frame = try await client.request(
            command: "listFavorites",
            payload: .object(["page": SteamServiceJSON.int(page)])
        )
        guard case .object(let data)? = frame.root["data"],
              case .array(let ids)? = data["ids"] else { return ([], 0, false) }
        return (
            ids.compactMap(\.stringValue),
            data["total"]?.intValue ?? 0,
            data["hasMore"]?.boolValue ?? false
        )
    }

    /// 订阅写入（SK3.3）：desiredState 单次写；调用方随后用
    /// subscriptionStates 对账确认。
    func setSubscription(workshopId: String, subscribe: Bool) async throws {
        _ = try await client.request(
            command: "setSubscription",
            payload: .object([
                "workshopId": .string(workshopId),
                "desiredState": .string(subscribe ? "subscribe" : "unsubscribe"),
            ])
        )
    }

    // MARK: - SK4.2 分级下载（staged；入库归 SK4.3）

    /// 发起 helper 下载：授权→manifest→有界 chunk→校验→stagedComplete。
    /// 进度经事件观察者（downloadProgress）；终态为本调用返回。
    /// timeout 为 nil：下载不受请求超时约束，取消走 cancelStagedDownload。
    func startStagedDownload(
        jobId: String,
        workshopId: String,
        stagingRoot: String
    ) async throws {
        _ = try await client.request(
            command: "startDownload",
            jobId: jobId,
            payload: .object([
                "workshopId": .string(workshopId),
                "stagingRoot": .string(stagingRoot),
            ]),
            private: nil,
            timeout: nil
        )
    }

    /// 取消在途分级下载；helper 以 cancelled terminal 收口该请求。
    func cancelStagedDownload(jobId: String) async throws {
        _ = try await client.request(
            command: "cancelDownload",
            jobId: jobId,
            payload: .object(["jobId": .string(jobId)])
        )
    }

    /// 订阅状态批量核对（需登录）。
    func subscriptionStates(ids: [String]) async throws -> [String: Bool] {
        let frame = try await client.request(
            command: "querySubscriptionStates",
            payload: .object(["ids": .array(ids.map(SteamServiceJSON.string))])
        )
        guard case .object(let data)? = frame.root["data"],
              case .object(let states)? = data["states"] else { return [:] }
        var result: [String: Bool] = [:]
        for (id, value) in states {
            result[id] = value.boolValue ?? false
        }
        return result
    }

    // MARK: - 解码

    private func decodePage(from frame: SteamServiceFrame) throws -> SteamWorkshopQueryPage {
        guard case .object(let data)? = frame.root["data"] else {
            throw SteamServiceClient.RequestError.connectionLost
        }
        let items: [SteamWorkshopQueryItem] = (data["items"]?.arrayValue ?? []).compactMap { value in
            guard let object = value.objectValue else { return nil }
            return SteamWorkshopQueryItem(
                publishedFileId: object["publishedfileid"]?.stringValue ?? "",
                title: object["title"]?.stringValue ?? "",
                previewUrl: object["previewUrl"]?.stringValue,
                fileSize: object["fileSize"]?.intValue,
                timeUpdated: object["timeUpdated"]?.intValue,
                timeCreated: object["timeCreated"]?.intValue,
                timeSubscribed: object["timeSubscribed"]?.intValue,
                consumerAppId: object["consumerAppid"]?.intValue,
                tags: object["tags"]?.arrayValue?.compactMap(\.stringValue) ?? []
            )
        }
        let partialErrors: [SteamWorkshopQueryPage.SteamWorkshopPartialError] =
            (data["partial"]?.arrayValue ?? []).compactMap { value in
                guard let object = value.objectValue else { return nil }
                return SteamWorkshopQueryPage.SteamWorkshopPartialError(
                    publishedFileId: object["publishedfileid"]?.stringValue ?? "",
                    code: object["code"]?.stringValue ?? "unsupportedContent"
                )
            }
        return SteamWorkshopQueryPage(
            page: data["page"]?.intValue ?? 0,
            total: data["total"]?.intValue ?? 0,
            hasMore: data["hasMore"]?.boolValue ?? false,
            items: items,
            wrongAppDropped: data["wrongAppDropped"]?.intValue ?? 0,
            partialErrors: partialErrors
        )
    }
}

private extension SteamServiceJSON {
    var arrayValue: [SteamServiceJSON]? {
        if case .array(let value) = self { return value }
        return nil
    }
}
