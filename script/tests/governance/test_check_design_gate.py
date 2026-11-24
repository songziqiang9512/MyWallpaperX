import unittest
from script.governance import check_design_gate as gate


class DesignGateEvidenceTests(unittest.TestCase):
    def area(self, status):
        return {"id": "capability", "title": "Capability", "owner": "existing-owner",
                "status": status, "designDoc": "docs/design.md",
                "matchPatterns": ["App/*"], "contentPatterns": []}

    def test_approved_match_reports_authority_without_blocking(self):
        violations, advisory = gate.evaluate(["App/a.swift"], {"areas": [self.area("approved")]})
        self.assertEqual(violations, [])
        self.assertEqual(len(advisory), 1)
        self.assertIn("approved owner=existing-owner design=docs/design.md paths=App/a.swift", advisory[0])

    def test_blocked_match_still_rejects_and_unrelated_path_does_not_claim_approval(self):
        violations, _ = gate.evaluate(["App/a.swift"], {"areas": [self.area("blocked-pending-design")]})
        self.assertEqual(len(violations), 1)
        self.assertEqual(gate.evaluate(["Other/a.swift"], {"areas": [self.area("approved")]}), ([], []))

    def test_existing_settings_fields_and_immersive_window_have_distinct_designs(self):
        registry = gate.load_registry()
        violations, advisory = gate.evaluate(["MyWallpaperX/Shared/Settings/AppKitSettingsView+Layout.swift"], registry)
        self.assertEqual(violations, [])
        self.assertTrue(any(entry.startswith("wallpaper-quality-settings:") for entry in advisory))
        violations, _ = gate.evaluate(["MyWallpaperX/App/SettingsWindowController.swift"], registry)
        self.assertTrue(any(entry.startswith("immersive-main-window-ui:") for entry in violations))


if __name__ == "__main__":
    unittest.main()
