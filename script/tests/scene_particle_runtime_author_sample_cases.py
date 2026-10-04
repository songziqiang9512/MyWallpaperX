"""Isolated author-sample regressions for the shared particle harness."""

from scene_real_test_fixtures import sample_cache_root, sample_runtime_evidence_path

REAL_SAMPLE_CACHE = sample_cache_root("3742133044")
REAL_SAMPLE_EVIDENCE = sample_runtime_evidence_path("3742133044")
EVENTSPAWN_SAMPLE_CACHE = sample_cache_root("3768903841")
EVENTSPAWN_SAMPLE_EVIDENCE = sample_runtime_evidence_path("3768903841")
EVENTDEATH_SAMPLE_CACHE = sample_cache_root("2131872317")
EVENTDEATH_SAMPLE_EVIDENCE = sample_runtime_evidence_path("2131872317")
FLARE_PARTICLE_CACHE = (
    sample_cache_root("2998757800") / "particles/workshop/2105295491"
)
STATIC_ORIGIN_SAMPLE_CACHE = sample_cache_root("3088601835")
STATIC_ORIGIN_SAMPLE_EVIDENCE = sample_runtime_evidence_path("3088601835")
REFRACTION_SAMPLE_CACHE = sample_cache_root("3768229922")
REFRACTION_SAMPLE_EVIDENCE = sample_runtime_evidence_path("3768229922")
WATER_IMPACT_SAMPLE_CACHE = sample_cache_root("3770444459")
WATER_IMPACT_SAMPLE_EVIDENCE = sample_runtime_evidence_path("3770444459")
NESTED_SAMPLE_CACHE = sample_cache_root("2974757317")
NESTED_SAMPLE_EVIDENCE = sample_runtime_evidence_path("2974757317")
NESTED_AUTHOR_OFF_SAMPLE_CACHE = sample_cache_root("2938612768")
NESTED_AUTHOR_OFF_SAMPLE_EVIDENCE = sample_runtime_evidence_path("2938612768")


class SceneParticleAuthorSampleCases:
    def test_real_3742133044_only_assembles_visible_snow_layer(self) -> None:
        if not REAL_SAMPLE_EVIDENCE.is_file() or not REAL_SAMPLE_CACHE.is_dir():
            self.skipTest("isolated 3742133044 runtime evidence is unavailable")
        result = self.run_harness(
            "real", str(REAL_SAMPLE_EVIDENCE), str(REAL_SAMPLE_CACHE)
        )
        self.assertEqual(result["activeLayerIDs"], [196])
        self.assertEqual(result["batchLayerIDs"], [196])
        self.assertGreater(result["initialCount"], 0)
        self.assertTrue(result["stateChanged"])
        self.assertTrue(result["bufferMatchesData"])
        self.assertEqual(result["blend"], "additive")
        self.assertTrue(result["usesPerspective"])
        self.assertTrue(result["orientationScreen"])
        self.assertAlmostEqual(result["overrideCount"], 0.60000002, places=6)
        self.assertAlmostEqual(result["overrideLifetime"], 1.4, places=6)
        self.assertAlmostEqual(result["overrideSize"], 1.8, places=6)
        self.assertLessEqual(result["maximumLocalSize"], 72.001)
        self.assertGreater(result["maximumLocalSize"], 9)
        self.assertLess(result["meanLocalY"], 700)
        self.assertEqual(result["playbackLoadedLine"], "particle loaded: 1 / 1")
        self.assertEqual(result["missingBatchLoadedLine"], "particle loaded: 0 / 1")


    def test_real_2974757317_executes_nested_matrix_rain(self) -> None:
        if not NESTED_SAMPLE_EVIDENCE.is_file() or not NESTED_SAMPLE_CACHE.is_dir():
            self.skipTest("isolated 2974757317 runtime evidence is unavailable")
        result = self.run_harness(
            "nested-real", str(NESTED_SAMPLE_EVIDENCE), str(NESTED_SAMPLE_CACHE)
        )
        self.assertEqual(result["headCount"], 43)
        self.assertGreaterEqual(result["trailCount"], 43)
        self.assertEqual(result["trailBatchCount"], 1)
        self.assertEqual(result["headSizeRange"], [50, 50])
        self.assertEqual(result["trailSizeRange"], [50, 50])
        self.assertLess(result["headYRange"][1], -250)
        self.assertGreater(result["trailYRange"][0], result["headYRange"][1])
        self.assertGreaterEqual(
            result["trailYRange"][1] - result["trailYRange"][0], 240
        )
        self.assertEqual(result["trailVelocityYRange"], [100, 100])
        self.assertEqual(result["staticRejections"], 0)
        self.assertEqual(result["nestedBudgetDetails"], [])


    def test_real_2938612768_keeps_author_disabled_matrix_off(self) -> None:
        cache = NESTED_AUTHOR_OFF_SAMPLE_CACHE
        if not NESTED_AUTHOR_OFF_SAMPLE_EVIDENCE.is_file() or not cache.is_dir():
            self.skipTest("isolated 2938612768 runtime evidence is unavailable")
        result = self.run_harness(
            "nested-real", str(NESTED_AUTHOR_OFF_SAMPLE_EVIDENCE), str(cache)
        )
        self.assertEqual(result["headCount"], 0)
        self.assertEqual(result["trailCount"], 0)
        self.assertNotIn(85705, result["activeLayerIDs"])
        self.assertEqual(result["staticRejections"], 0)


    def test_real_flare_children_enter_continuous_emitter_profile(self) -> None:
        if not FLARE_PARTICLE_CACHE.is_dir():
            self.skipTest("isolated 2998757800 particle cache is unavailable")
        result = self.run_harness("continuous-profile-real", str(FLARE_PARTICLE_CACHE))
        self.assertEqual(result["supported"], {
            "Flare_Flame": True,
            "Flare_Smoke": True,
            "Flare_Sparks": True,
        })
        self.assertEqual(set(result["completed"].values()), {False})
        self.assertEqual(result["rates"]["Flare_Sparks"], 10)
        self.assertEqual(result["instantaneous"]["Flare_Sparks"], 1)


    def test_real_3088601835_applies_static_snowstorm_fog_origin(self) -> None:
        if not STATIC_ORIGIN_SAMPLE_EVIDENCE.is_file() or not STATIC_ORIGIN_SAMPLE_CACHE.is_dir():
            self.skipTest("isolated 3088601835 runtime evidence is unavailable")
        result = self.run_harness(
            "static-origin-real",
            str(STATIC_ORIGIN_SAMPLE_EVIDENCE),
            str(STATIC_ORIGIN_SAMPLE_CACHE),
        )
        self.assertEqual(result["childLayerIDs"], [513, 534])
        self.assertEqual(result["childInstanceCounts"], [1, 1])
        self.assertEqual(result["childTextureWidths"], [128, 128])
        self.assertEqual(result["unsupportedLayerIDs"], [])


    def test_real_3768903841_executes_strict_eventspawn_child(self) -> None:
        if not EVENTSPAWN_SAMPLE_EVIDENCE.is_file() or not EVENTSPAWN_SAMPLE_CACHE.is_dir():
            self.skipTest("isolated 3768903841 runtime evidence is unavailable")
        result = self.run_harness(
            "eventspawn-real",
            str(EVENTSPAWN_SAMPLE_EVIDENCE),
            str(EVENTSPAWN_SAMPLE_CACHE),
        )
        self.assertIn(264, result["activeLayerIDs"])
        self.assertGreater(result["childInstanceCount"], 0)
        self.assertEqual(result["childTextureWidth"], 128)
        self.assertFalse(result["layer264ChildUnsupported"])


    def test_real_2131872317_executes_eventdeath_firework_burst(self) -> None:
        if not EVENTDEATH_SAMPLE_EVIDENCE.is_file() or not EVENTDEATH_SAMPLE_CACHE.is_dir():
            self.skipTest("isolated 2131872317 runtime evidence is unavailable")
        result = self.run_harness(
            "eventdeath-real",
            str(EVENTDEATH_SAMPLE_EVIDENCE),
            str(EVENTDEATH_SAMPLE_CACHE),
        )
        self.assertGreater(result["firstHitFrame"], 0)
        self.assertEqual(result["hitInstanceCount"], 8_500)
        self.assertGreater(result["hitMaximumAlpha"], 0)
        self.assertGreater(result["hitMaximumSize"], 0)
        self.assertGreater(result["hitMaximumTrailStretch"], 1)
        self.assertGreater(result["renderedPixelCount"], 1_000)
        self.assertGreater(result["renderedPixelWidth"], 100)
        self.assertGreater(result["renderedPixelHeight"], 100)
        self.assertTrue(result["hitUsesTrail"])
        self.assertFalse(result["layer529ChildUnsupported"])


    def test_real_3768229922_loads_strict_refraction_without_duplicate_upload(self) -> None:
        if not REFRACTION_SAMPLE_EVIDENCE.is_file() or not REFRACTION_SAMPLE_CACHE.is_dir():
            self.skipTest("isolated 3768229922 runtime evidence is unavailable")
        result = self.run_harness(
            "refraction-real",
            str(REFRACTION_SAMPLE_EVIDENCE),
            str(REFRACTION_SAMPLE_CACHE),
        )
        self.assertEqual(
            sorted(result["refractionLayerIDs"]), [1103, 1144], result
        )
        self.assertTrue(result["sameTextureIdentity"])
        self.assertEqual(result["staticCandidateLayerIDs"], [])
        self.assertEqual(result["amounts"], [0.5, 0.5])
        self.assertNotIn("refractionUnsupported", result["diagnostics"])


    def test_real_2131872317_executes_refractive_eventdeath_child(self) -> None:
        if not EVENTDEATH_SAMPLE_EVIDENCE.is_file() or not EVENTDEATH_SAMPLE_CACHE.is_dir():
            self.skipTest("isolated 2131872317 runtime evidence is unavailable")
        result = self.run_harness(
            "refraction-child-real",
            str(EVENTDEATH_SAMPLE_EVIDENCE),
            str(EVENTDEATH_SAMPLE_CACHE),
        )
        self.assertGreater(result["firstFrame"], 0)
        self.assertIn(
            "particles/presets/fireworkshitdistort.json",
            result["paths"],
        )
        self.assertIn(
            "particles/presets/fireworkshitdistort.json",
            result["candidatePaths"],
        )
        self.assertEqual(result["refractionUnsupported"], [])


    def test_real_3770444459_sustains_refractive_water_impacts(self) -> None:
        if (
            not WATER_IMPACT_SAMPLE_EVIDENCE.is_file()
            or not WATER_IMPACT_SAMPLE_CACHE.is_dir()
        ):
            self.skipTest("isolated 3770444459 runtime evidence is unavailable")
        result = self.run_harness(
            "water-impact-real",
            str(WATER_IMPACT_SAMPLE_EVIDENCE),
            str(WATER_IMPACT_SAMPLE_CACHE),
        )
        for layer_id in ("239", "245", "248"):
            self.assertGreater(result["activeFrames"][layer_id], 0, result)
            self.assertGreater(result["maximumInstances"][layer_id], 0, result)
        self.assertEqual(result["refractionUnsupported"], [])
        self.assertIn(48, result["candidateLayers"], result)
        self.assertEqual(result["activeRopePaths"], [
            "particles/presets/dripping_water_refract.json",
            "particles/presets/dripping_water_splash.json",
        ], result)
        self.assertGreater(
            result["maximumRopeInstances"]["particles/presets/dripping_water_refract.json"],
            0,
        )
        self.assertGreater(
            result["maximumRopeInstances"]["particles/presets/dripping_water_splash.json"],
            0,
        )
        self.assertEqual(result["refractiveRopePaths"], [
            "particles/presets/dripping_water_refract.json",
        ])
        self.assertEqual(result["ropeUnsupported"], [])
        self.assertEqual(result["activeTrailChildLayers"], [239, 245, 248], result)
        for layer_id in ("239", "245", "248"):
            self.assertGreater(result["maximumTrailChildInstances"][layer_id], 0, result)
        self.assertGreaterEqual(result["minimumTrailStretch"], 1)
        self.assertLessEqual(result["maximumTrailStretch"], 2)
        self.assertEqual(result["trailChildUnsupported"], [])
        for layer_id in (239, 245, 248):
            self.assertIn(layer_id, result["legacyLayers"], result)
