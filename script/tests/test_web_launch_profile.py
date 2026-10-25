"""The launch profile consumes descriptor facts without an inspector model."""
from pathlib import Path
import subprocess
import tempfile
import unittest

from script.tests.test_web_compat_parity import source_block

ROOT = Path(__file__).resolve().parents[2]

STORE_HARNESS = r'''
import Foundation
import CryptoKit
import Darwin
typealias CGDirectDisplayID = UInt32
enum WallpaperEngine {}
// PROFILE_DECLARATIONS
@MainActor enum DedicatedWebWallpaperHostPlaceholderAdapter {
    static var derivations = 0
    // STORE_DECLARATIONS
}
@MainActor final class WKWebsiteDataStore {
    static let instance = WKWebsiteDataStore()
    static var identifiers = Set<UUID>()
    static var removed = Set<UUID>()
    static var fetches = 0
    static var defersCompletion = false
    static var pending: [(Set<UUID>) -> Void] = []
    static func `default`() -> WKWebsiteDataStore { instance }
    static func fetchAllDataStoreIdentifiers(_ completion: @escaping (Set<UUID>) -> Void) {
        fetches += 1
        if defersCompletion { pending.append(completion) } else { completion(identifiers) }
    }
    static func remove(forIdentifier identifier: UUID, completionHandler: (Error?) -> Void) {
        removed.insert(identifier)
        completionHandler(nil)
    }
    static func finishNext() { pending.removeFirst()(identifiers) }
    static func reset() {
        identifiers = []; removed = []; fetches = 0
        defersCompletion = false; pending = []
    }
}
// REAL_RECLAIMER
@main enum StoreHarness {
    @MainActor static func main() {
        typealias Adapter = DedicatedWebWallpaperHostPlaceholderAdapter
        typealias Reclaimer = WebWallpaperDataStoreReclaimer
        typealias Store = WKWebsiteDataStore
        let a = Adapter.WebPersistentDataStoreRecord(recordID: "a", rootPaths: ["/first"])
        let b = Adapter.WebPersistentDataStoreRecord(recordID: "b", rootPaths: ["/second"])
        let changed = Adapter.WebPersistentDataStoreRecord(recordID: "a", rootPaths: ["/changed"])
        func identifiers(_ record: Adapter.WebPersistentDataStoreRecord, _ screens: [UInt32]) -> Set<UUID> {
            Adapter.persistentDataStoreIdentifiers(for: record, screenIDs: screens)
        }
        func update(_ owner: Reclaimer, _ records: [Adapter.WebPersistentDataStoreRecord],
                    screens: [UInt32] = [1], removal: Set<String> = []) {
            owner.updateLiveRecords(records, screenIDs: screens, removalIntent: removal,
                activeRecordIDs: [], inUsePersistentDataStoreIdentifiers: [])
        }
        func wait(_ condition: () -> Bool) {
            let deadline = Date().addingTimeInterval(2)
            while !condition(), Date() < deadline {
                RunLoop.main.run(until: Date().addingTimeInterval(0.002))
            }
            precondition(condition(), "scheduled reclaimer deadline")
        }
        func advance() { RunLoop.main.run(until: Date().addingTimeInterval(0.08)) }

        let changedIDs = identifiers(changed, [2, 3])
        let firstIDs = identifiers(a, [1])
        let liveIDs = identifiers(b, [3])
        Adapter.derivations = 0
        let owner = Reclaimer()
        update(owner, [a, b])
        for _ in 0..<50 { update(owner, [a, b]) }
        update(owner, [changed, b], screens: [2, 3])
        precondition(Adapter.derivations == 0 && Store.fetches == 0,
            "ordinary projections and root/screen changes must not hash store UUIDs")
        // The deleted record keeps the previous screen cohort; the remaining
        // live record is protected using the current one at actual reclamation.
        Store.identifiers = changedIDs.union(liveIDs).union(firstIDs)
        update(owner, [b], screens: [3], removal: ["a"])
        precondition(Adapter.derivations == 1, "only confirmed deletion expands the removed record")
        wait { Store.fetches == 1 }
        precondition(Adapter.derivations == 2 && changedIDs.isSubset(of: Store.removed)
            && Store.removed.isDisjoint(with: liveIDs),
            "latest live cohort is derived once and remains protected")

        Store.reset(); Adapter.derivations = 0
        let projection = Reclaimer()
        update(projection, [a, b])
        update(projection, []) // cache reset or incomplete projection
        advance()
        precondition(Adapter.derivations == 0 && Store.fetches == 0,
            "projection absence without removal intent cannot reclaim or hash")
        update(projection, [a, b])
        update(projection, [b], removal: ["a"])
        update(projection, [a, b]) // restore inside the grace period
        advance()
        precondition(Store.fetches == 0, "restoring a record cancels its delayed deletion")

        Store.reset()
        let usageOwner = Reclaimer()
        var usage = Reclaimer.LiveUsage(activeRecordIDs: [], inUsePersistentDataStoreIdentifiers: [])
        var usageReads = 0
        usageOwner.liveUsageProvider = { usageReads += 1; return usage }
        update(usageOwner, [a, b])
        update(usageOwner, [b], removal: ["a"])
        // A surface started after projection must be re-read by the work item.
        usage = .init(activeRecordIDs: [], inUsePersistentDataStoreIdentifiers: firstIDs)
        wait { usageReads > 0 }
        precondition(Store.fetches == 0, "live usage at grace-period expiry postpones deletion")
        usage = .init(activeRecordIDs: [], inUsePersistentDataStoreIdentifiers: [])
        wait { Store.fetches == 1 }
        precondition(Store.removed == firstIDs, "a later retry re-reads released surface usage")

        Store.reset()
        let retiring = Reclaimer()
        var retiringReads = 0
        retiring.liveUsageProvider = {
            retiringReads += 1
            return .init(activeRecordIDs: ["a"], inUsePersistentDataStoreIdentifiers: [])
        }
        update(retiring, [a, b])
        update(retiring, [b], removal: ["a"])
        wait { retiringReads == Reclaimer.maxRemovalAttempts }
        precondition(Store.fetches == 0 && Store.removed.isEmpty,
            "an active record remains protected through all bounded retries")

        Store.reset(); Adapter.derivations = 0
        let restoredDuringEnumeration = Reclaimer()
        Store.defersCompletion = true
        update(restoredDuringEnumeration, [a, b])
        update(restoredDuringEnumeration, [b], removal: ["a"])
        wait { Store.pending.count == 1 }
        update(restoredDuringEnumeration, [changed, b], screens: [2, 3])
        Store.finishNext()
        precondition(Store.removed.isEmpty && Adapter.derivations == 1,
            "restoration before asynchronous enumeration completion cancels deletion without live UUID expansion")

        Store.reset(); Adapter.derivations = 0
        let newSurfaceDuringEnumeration = Reclaimer()
        var asynchronousUsage = Reclaimer.LiveUsage(activeRecordIDs: [], inUsePersistentDataStoreIdentifiers: [])
        newSurfaceDuringEnumeration.liveUsageProvider = { asynchronousUsage }
        Store.defersCompletion = true
        update(newSurfaceDuringEnumeration, [a, b])
        update(newSurfaceDuringEnumeration, [b], removal: ["a"])
        wait { Store.pending.count == 1 }
        asynchronousUsage = .init(activeRecordIDs: ["a"], inUsePersistentDataStoreIdentifiers: firstIDs)
        Store.finishNext()
        precondition(Store.removed.isEmpty && Adapter.derivations == 1,
            "a new active surface before enumeration completion is protected by current usage")
        Store.defersCompletion = false
        asynchronousUsage = .init(activeRecordIDs: [], inUsePersistentDataStoreIdentifiers: [])
        wait { Store.fetches == 2 }
        precondition(Store.removed == firstIDs && Adapter.derivations == 2,
            "the existing retry rechecks usage and expands the current live projection only once")
        print("web-store-reclaimer-pass")
    }
}
'''


class WebLaunchProfileTests(unittest.TestCase):
    def test_descriptor_only_profile_preserves_compatibility_policy(self):
        source = ROOT / "MyWallpaperX/Modules/SteamWorkshop/Web/Core/SteamWorkshopWebResolvedRuntimeRiskFlags.swift"
        fixture = ROOT / "script/tests/fixtures/WebLaunchProfileChecks.swift"
        with tempfile.TemporaryDirectory(prefix="mwx-web-launch-profile-") as raw:
            directory = Path(raw)
            binary = directory / "check"
            compiled = subprocess.run(
                ["xcrun", "swiftc", "-parse-as-library", str(source), str(fixture),
                 "-module-cache-path", str(directory / "modules"), "-o", str(binary)],
                capture_output=True, text=True,
            )
            self.assertEqual(compiled.returncode, 0, compiled.stderr)
            run = subprocess.run([str(binary)], capture_output=True, text=True)
            self.assertEqual(run.returncode, 0, run.stdout + run.stderr)
            self.assertIn("web-launch-profile-pass", run.stdout)

    def test_reclaimer_expands_store_identities_only_for_real_deletion(self):
        host = ROOT / "MyWallpaperX/Core/SteamWorkshopWeb/Host"
        types = (host / "WebWallpaperHostTypes.swift").read_text()
        surface = (host / "DedicatedWebWallpaperHostPlaceholderAdapter+Surface.swift").read_text()
        profiles = "extension WallpaperEngine {\n" + "\n".join(
            source_block(types, marker) for marker in
            ("enum WebRuntimeOriginMode", "struct WebRuntimeProfile")) + "\n}"
        markers = ("struct WebPersistentDataStoreRecord", "static let persistableWebRuntimeProfiles:",
            "static func persistentDataStoreIdentifiers(", "static func persistentDataStoreIdentifier(for identity:",
            "static func workshopDataStoreIdentity(", "static func scopedDataStoreIdentity(")
        # The immutable profile array has no brace body; copy its exact statement.
        profile_start = surface.index(markers[1])
        profile_end = surface.index("    ]", profile_start) + len("    ]")
        declarations = "\n".join(surface[profile_start:profile_end] if marker == markers[1]
            else source_block(surface, marker) for marker in markers)
        declarations = declarations.replace("        var identifiers = Set<UUID>()",
            "        derivations += 1\n        var identifiers = Set<UUID>()", 1)
        # Shorten only the existing scheduling interval; run the real deletion,
        # restoration, usage-provider and orphan logic against a fake WebKit leaf.
        reclaimer = source_block(types, "final class WebWallpaperDataStoreReclaimer")
        reclaimer = reclaimer.replace("static let removalGracePeriod: TimeInterval = 30",
                                      "static let removalGracePeriod: TimeInterval = 0.015")
        source = STORE_HARNESS.replace("// PROFILE_DECLARATIONS", profiles).replace(
            "// STORE_DECLARATIONS", declarations).replace("// REAL_RECLAIMER", "@MainActor\n" + reclaimer)
        with tempfile.TemporaryDirectory(prefix="mwx-web-store-reclaimer-") as raw:
            directory = Path(raw)
            harness = directory / "Harness.swift"; harness.write_text(source)
            binary = directory / "check"
            compiled = subprocess.run(["xcrun", "swiftc", "-parse-as-library",
                "-default-isolation", "MainActor", str(harness),
                "-module-cache-path", str(directory / "modules"), "-o", str(binary)],
                capture_output=True, text=True)
            self.assertEqual(compiled.returncode, 0, compiled.stderr)
            run = subprocess.run([str(binary)], capture_output=True, text=True, timeout=10)
            self.assertEqual(run.returncode, 0, run.stdout + run.stderr)
            self.assertIn("web-store-reclaimer-pass", run.stdout)


if __name__ == "__main__":
    unittest.main()
