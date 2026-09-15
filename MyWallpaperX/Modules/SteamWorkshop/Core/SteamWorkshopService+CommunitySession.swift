import Foundation

extension SteamWorkshopService {
    func preparePersonalWorkshopFetchIfNeeded(
        source: SteamWorkshopSource,
        forceRefresh: Bool,
        navigationVersion: Int
    ) -> Bool {
        guard source.isPersonal else { return false }
        // Personal data has one login owner. Never re-enter fetch after Cookie verification.
        browserState = .loaded
        browserItems = []
        hasMoreBrowserItems = false
        isRefreshingBrowserFeed = false
        statusMessage = steamAuth.isOnline
            ? "暂时无法加载 Steam 个人列表，请稍后重试。"
            : "查看「\(source.displayName)」需要登录 Steam。请使用工具栏的「登录 Steam」。"
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
