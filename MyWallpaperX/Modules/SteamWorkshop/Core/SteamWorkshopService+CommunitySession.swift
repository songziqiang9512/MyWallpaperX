import Foundation

extension SteamWorkshopService {
    func preparePersonalWorkshopFetchIfNeeded(
        source: SteamWorkshopSource,
        forceRefresh: Bool,
        navigationVersion: Int
    ) -> Bool {
        guard source.isPersonal, communityAccountID == nil else { return false }
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
                    self.browserState = .failed(error.localizedDescription)
                    self.statusMessage = "Steam 社区登录已失效，请重新登录。"
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
