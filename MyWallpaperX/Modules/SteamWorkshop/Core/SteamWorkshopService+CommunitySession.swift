import Foundation

extension SteamWorkshopService {
    func preparePersonalWorkshopFetchIfNeeded(
        source: SteamWorkshopSource,
        forceRefresh: Bool,
        navigationVersion: Int
    ) -> Bool {
        guard source.isPersonal else { return false }
        // SK2.2 合同（§3.1）：进入个人列表不得自动弹任何登录窗口。
        // 已有社区 Cookie 会话时沿用既有抓取；否则只给工具栏指引的空态。
        guard communityAccountID != nil else {
            browserState = .loaded
            browserItems = []
            hasMoreBrowserItems = false
            statusMessage = "查看「\(source.displayName)」需要登录 Steam。请使用工具栏的「登录 Steam」。"
            return true
        }
        browserState = .loading
        browserItems = []
        statusMessage = "正在验证 Steam 社区登录状态…"
        browserFetchTask = Task(priority: .userInitiated) { [weak self] in
            do {
                let account = try await SteamCommunitySessionController.shared.ensureAuthenticated()
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    guard let self, self.navigationVersion == navigationVersion, self.source == source else { return }
                    self.communityAccountID = account.id
                    self.communityAccountName = account.displayName
                    self.browserFetchTask = nil
                    self.fetchBrowserItems(forceRefresh: forceRefresh)
                }
            } catch {
                await MainActor.run {
                    guard let self, self.navigationVersion == navigationVersion else { return }
                    self.isRefreshingBrowserFeed = false
                    // SK2.2：Cookie 失效不再自动弹网页登录，给工具栏指引空态。
                    self.communityAccountID = nil
                    self.browserState = .loaded
                    self.browserItems = []
                    self.hasMoreBrowserItems = false
                    self.statusMessage = "Steam 社区登录已失效。查看「\(source.displayName)」请使用工具栏的「登录 Steam」。"
                }
            }
        }
        return true
    }

    func presentCommunityLogin() {
        Task { [weak self] in
            do {
                guard let self else { return }
                let account = try await self.communitySession.presentLogin()
                self.communityAccountID = account.id
                self.communityAccountName = account.displayName
                if self.source.isPersonal { self.refresh() }
            } catch {
                self?.statusMessage = "Steam 社区登录未完成。"
            }
        }
    }

    func switchCommunityAccount() {
        Task { [weak self] in
            guard let self else { return }
            await self.communitySession.clearSession()
            self.communityAccountID = nil
            self.communityAccountName = nil
            do {
                let account = try await self.communitySession.presentLogin()
                self.communityAccountID = account.id
                self.communityAccountName = account.displayName
                if self.source.isPersonal { self.refresh() }
            } catch {
                self.statusMessage = "Steam 社区账号切换未完成。"
            }
        }
    }

    func clearCommunitySession() {
        communityAccountID = nil
        communityAccountName = nil
        clearPersonalSubscriptionCaches()
        Task { await communitySession.clearSession() }
    }

    nonisolated static func fetchHTMLForBrowseSource(
        url: URL,
        context: SteamWorkshopBrowseContext,
        source: SteamWorkshopSource
    ) async throws -> String {
        if source.isPersonal {
            switch context {
            case .discovery:
                return try await SteamCommunitySessionController.shared.renderedHTML(for: url)
            case .authorWorkshop:
                break
            }
        }
        return try await fetchHTML(url: url)
    }
}
