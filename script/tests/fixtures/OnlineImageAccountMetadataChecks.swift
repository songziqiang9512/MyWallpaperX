import Foundation

/// Account display behavior runs through the real acquisition owner. The
/// existing harness supplies only controlled credential/network leaves.
extension OnlineImageLibraryHarness {
    static func wallhavenAccountMetadata() async throws {
        let previousReads = source.credentialReads
        source.credentialFailures = 2
        let unread = try await library("credential-read-retry")
        _ = await unread.prepareWallhaven(); _ = await unread.prepareWallhaven()
        check("failed-keychain-read-is-not-repeated-by-ordinary-source-preparation", unread.wallhavenAccount == .unread && source.credentialReads == previousReads + 1)
        unread.refreshWallhavenAccount()
        try await eventually("explicit failed keychain retry") { source.credentialReads == previousReads + 2 }
        try await settle()
        check("one-explicit-account-refresh-retries-one-failed-read-without-looping", unread.wallhavenAccount == .unread && source.credentialReads == previousReads + 2)
        unread.refreshWallhavenAccount()
        try await eventually("keychain recovered on later explicit action") { unread.wallhavenAccount == .unconfigured }
        check("keychain-recovery-uses-original-owner-with-no-account-network", source.credentialReads == previousReads + 3 && source.collectionCalls == 0)
        let value = try await library("account-metadata")
        _ = await value.prepareWallhaven()
        check("ordinary-key-preparation-does-not-fetch-account-metadata", value.wallhavenAccount == .unconfigured && source.collectionCalls == 0)
        source.holdCollections = true
        try await value.setWallhavenKey("fixture-A")
        try await eventually("saved key account request") { source.pendingCollections.count == 1 }
        check("saved-key-is-not-presented-as-verified-before-network", value.wallhavenAccount == .loading && value.wallhavenAccount.hasStoredKey == true)
        try await value.setWallhavenKey("fixture-B")
        try await eventually("replacement key account request") { source.pendingCollections.count == 2 }
        source.completeCollections(.success([.init(label: "Old account", count: 8)]))
        try await settle()
        check("late-old-key-collections-cannot-replace-new-key-state", value.wallhavenAccount == .loading)
        source.completeCollections(.failure(URLError(.cannotConnectToHost)))
        try await eventually("failed account metadata") { if case .unavailable = value.wallhavenAccount { return true }; return false }
        let savedKey = await value.wallhaven.key
        check("account-metadata-failure-retains-configured-key", value.wallhavenAccount.hasStoredKey == true && savedKey == "fixture-B")
        let sameAsset = OnlineImageAsset(id: .init(source: .wallhaven, artworkID: "same-key-transfer"), title: "same key",
            sourceURL: URL(string: "https://example.invalid/work/same-key-transfer")!, originalURL: URL(string: "https://example.invalid/same-key-transfer")!)
        let detailSeed = OnlineImageArtwork(source: .wallhaven, artworkID: "same-key-detail", title: "same key detail", sourceURL: sameAsset.sourceURL)
        value.download(sameAsset)
        let pendingDetail = Task { try await value.detail(detailSeed) }
        try await eventually("same-key download and detail in flight") { transfer.starts(sameAsset.id.artworkID) == 1 && source.starts[detailSeed.id] == 1 }
        let sameScope = value.requestScope(.wallhaven)
        try await value.setWallhavenKey(" fixture-B ")
        value.refreshWallhavenAccount(); value.refreshWallhavenAccount()
        try await eventually("explicit metadata retry") { source.pendingCollections.count == 1 }
        check("explicit-account-refresh-coalesces-without-a-second-owner", source.collectionCalls == 3)
        check("saving-the-same-normalized-key-preserves-inflight-generation-and-requests", value.requestScope(.wallhaven) == sameScope
            && transfer.cancels(sameAsset.id.artworkID) == 0 && source.cancellations[detailSeed.id, default: 0] == 0)
        source.resolve(detailSeed.id)
        let resolvedDetail = try await pendingDetail.value
        transfer.finish(sameAsset.id.artworkID, bytes: png)
        try await drained(value, "same-key acquisition")
        check("same-key-save-does-not-regress-real-detail-or-publication", resolvedDetail.artworkID == detailSeed.artworkID && value.record(for: sameAsset.id.reference) != nil)
        source.completeCollections(.success([]))
        try await eventually("empty account collection success") { value.wallhavenAccount == .ready([]) }
        check("empty-collections-is-a-successful-configured-account", value.wallhavenAccount.hasStoredKey == true)
        try await value.setWallhavenKey(nil)
        value.refreshWallhavenAccount(); try await settle()
        check("removing-key-restores-anonymous-state-without-account-network", value.wallhavenAccount == .unconfigured && source.collectionCalls == 3)
        source.holdCollections = false
    }

}
