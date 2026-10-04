"""World-frame, transform recovery and pointer behavior for the shared particle harness."""


class SceneParticleWorldSpaceCases:
    def test_world_space_system_freezes_on_runtime_transform_write(self) -> None:
        result = self.run_harness("worldspace-freeze")
        self.assertTrue(result["movingLayerActive"])
        # The system simulates normally while no chain transform lane exists.
        self.assertTrue(result["movingPositions"])
        self.assertTrue(any(abs(x) > 0.01 for x, _, _ in result["movingPositions"]))
        # Without a current world frame the runtime transform write freezes
        # the system at its last committed state (previous-current) instead of
        # silently misconverting world forces through the stale launch frame.
        self.assertEqual(result["frozenPositions"], result["movingPositions"])
        self.assertEqual(result["frozenAgainPositions"], result["movingPositions"])
        self.assertTrue(result["freezeDiagnostic"])


    def test_frozen_world_space_layer_recovers_after_transform_restores(self) -> None:
        result = self.run_harness("worldspace-freeze-recovery")
        # The degenerate (zero-scale) frame itself still holds the last
        # committed state: the freeze stays a previous-current fail-soft.
        self.assertTrue(result["degenerateHoldsPrevious"])
        self.assertTrue(result["chainedFrozenHoldsPrevious"])
        # Once a valid current world frame is available again the system
        # resumes simulation instead of staying frozen forever, both for a
        # self-chain system and for one under a two-level ancestor chain
        # with a static child sharing the same layer delta.
        self.assertTrue(result["recoveryResumes"])
        self.assertTrue(result["chainedRecoveryResumes"])
        self.assertTrue(result["chainedRootAndChildBatches"])
        self.assertTrue(result["resumeDiagnostic"])


    def test_frozen_world_space_layer_recovers_when_the_write_vanishes(self) -> None:
        result = self.run_harness("worldspace-freeze-recovery")
        # A one-shot undeclared script write (or a finished timeline)
        # produces no transform lane on later frames: the snapshot falls
        # back to the authored transform and the resolver serves a valid
        # frame again. The freeze must be re-evaluated on those lane-less
        # frames — the degenerate frame itself still holds previous-current.
        self.assertTrue(result["vanishingWriteHoldsDuringDegenerate"])
        self.assertTrue(result["vanishingWriteResumes"])
        self.assertTrue(result["vanishingWriteStaysUnfrozen"])
        self.assertTrue(result["vanishingWriteResumeDiagnostic"])
        # A lane-less frame that still cannot construct a current frame
        # keeps the previous-current freeze instead of guessing recovery.
        self.assertTrue(result["conservativeHoldKeepsPrevious"])


    def test_vanished_write_recovers_while_another_chain_keeps_writing(self) -> None:
        result = self.run_harness("worldspace-freeze-recovery")
        for key in ("unrelatedWriteKeepsInvalidFrozen", "unrelatedWriteResumes",
                    "unrelatedWriteStaysUnfrozen", "recoveryRollbackKeepsFrozen",
                    "recoveryReplayMatches"):
            with self.subTest(key=key):
                self.assertTrue(result[key])


    def test_freeze_rollback_via_frame_snapshot_restores_simulation(self) -> None:
        result = self.run_harness("worldspace-freeze-recovery")
        # A degenerate frame that the host discards rolls the freeze back
        # with the simulation values: the next valid frame simulates again.
        self.assertTrue(result["rollbackResumes"])


    def test_non_world_space_layer_not_frozen_on_ancestor_transform_write(self) -> None:
        result = self.run_harness("worldspace-freeze-recovery")
        # A local-space particle system never consumes the world frame, so
        # a scripted transform write on its ancestor chain must not stop
        # its simulation and must not report a world-space freeze for it.
        self.assertTrue(result["localKeepsMoving"])
        self.assertTrue(result["localFreezeDiagnosticAbsent"])


    def test_world_space_system_follows_current_world_frame_over_transform_lane(self) -> None:
        result = self.run_harness("worldspace-freeze")
        # With the renderer's current world frame supplied, the same transform
        # lane no longer freezes the system: birth velocities and gravity run
        # through the live frame each advance.
        identity = result["liveIdentityPositions"]
        rotated = result["liveRotatedPositions"]
        self.assertTrue(identity)
        self.assertTrue(any(abs(x) > 0.01 for x, _, _ in identity))
        self.assertTrue(result["liveIdentityFollowsCurrent"])
        self.assertFalse(result["liveIdentityFrozen"])
        self.assertTrue(result["liveRotatedFollowsCurrent"])
        self.assertFalse(result["liveRotatedFrozen"])
        # A +90 degree Z world frame redirects the world +X birth velocity
        # into the local Y axis, so the rotated run moves on Y while the
        # identity run keeps moving on X.
        identityX = sum(abs(p[0]) for p in identity)
        identityY = sum(abs(p[1]) for p in identity)
        rotatedX = sum(abs(p[0]) for p in rotated)
        rotatedY = sum(abs(p[1]) for p in rotated)
        self.assertGreater(identityX, identityY * 4)
        self.assertGreater(rotatedY, rotatedX * 4)
        self.assertTrue(any(abs(y) > 0.01 for _, y, _ in rotated))


    def test_world_space_pointer_positionaround_births_around_pointer(self) -> None:
        result = self.run_harness("worldspace-pointer-positionaround")
        # The positionAround initializer's pointer demand is registered for
        # the world system and births distribute around the pointer position.
        self.assertIn(131, result["demandedLayerIDs"])
        self.assertTrue(result["positions"])
        for x, y, _ in result["positions"]:
            self.assertLess(abs(x - 60), 60)
            self.assertLess(abs(y - 40), 60)
        # Not all at the exact pointer point: the distance spread is real.
        distinct = len({(round(x), round(y)) for x, y, _ in result["positions"]})
        self.assertGreater(distinct, 1)


    def test_world_space_pointer_force_repels_from_pointer(self) -> None:
        result = self.run_harness("worldspace-pointer-force")
        # The pointer control point's demand is registered for the world
        # system, and the negative-scale attract accelerates particles away
        # from the pointer instead of staying inert at the origin.
        self.assertIn(121, result["demandedLayerIDs"])
        without = result["withoutPointerPositions"]
        with_pointer = result["withPointerPositions"]
        self.assertTrue(without)
        self.assertTrue(with_pointer)
        # Without the pointer the force is fail-closed: no acceleration.
        for x, _, _ in without:
            self.assertLess(abs(x), 0.5)
        # With the pointer at +X the repulsion drives particles to -X.
        moved = [x for x, _, _ in with_pointer if x < -0.5]
        self.assertGreater(len(moved), len(with_pointer) // 2)


    def test_world_space_rope_pointer_trail_renders(self) -> None:
        result = self.run_harness("worldspace-rope-trail")
        # The pointer-trail rope family profile (world system + pointer CP0 +
        # rope renderer flags=1/subdivision=100/maxcount=256) is admitted and
        # produces rope geometry following the pointer birth history.
        self.assertIn(111, result["activeLayerIDs"])
        self.assertIn(111, result["demandedLayerIDs"])
        self.assertFalse(result["ropeDiagnostic"])
        self.assertGreater(result["instanceCount"], 0)
        self.assertTrue(result["firstPositions"])


    def test_audio_bounds_without_mode_gates_emission(self) -> None:
        result = self.run_harness("audio-bounds-gate")
        # Authored bounds without a channel mode still gate the emitter: the
        # mode only selects left/right/center (bounds-only corpus shape comes
        # from the same editor flow as the mode-bearing copies).
        self.assertEqual(result["boundsOnlySilentCount"], 0)
        self.assertGreater(result["boundsOnlyLoudCount"], 0)
        # The explicit-mode shape keeps its existing gate.
        self.assertEqual(result["modeCenterSilentCount"], 0)


    def test_world_space_pointer_emitter_follows_pointer(self) -> None:
        result = self.run_harness("worldspace-pointer-emitter")
        # The emitter's pointer control-point demand must not be excluded for
        # world-space systems: the supplied pointer value is the layer-local
        # unprojection through the layer's current model matrix, the same
        # space every control-point consumer composes in.
        self.assertIn(91, result["pointerDemandLayerIDs"])
        self.assertTrue(result["positions"])
        # Births cluster at the pointer position, not at the static offset.
        for x, y, _ in result["positions"]:
            self.assertLess(abs(x - 40), 2.0)
            self.assertLess(abs(y - 60), 2.0)
        self.assertNotIn("pointerControlPointUnsupported", result["diagnosticKinds"])


    def test_world_space_prewarm_converts_gravity_through_launch_frame(self) -> None:
        result = self.run_harness("worldspace-gravity-frame")
        # The init-time warm-up must convert world gravity through the
        # injected +90 degree Z launch frame: world +X gravity moves the
        # prewarmed particles along the local Y axis, not raw +X.
        self.assertTrue(result["prewarmPositions"])
        self.assertGreater(result["prewarmY"], result["prewarmX"] * 4)


    def test_world_space_live_gravity_follows_current_frame(self) -> None:
        result = self.run_harness("worldspace-gravity-frame")
        # With a transform lane and a -90 degree Z current frame, world +X
        # gravity integrates into local +Y during live advances.
        self.assertTrue(result["livePositions"])
        self.assertGreater(result["liveY"], result["liveX"] * 4)
