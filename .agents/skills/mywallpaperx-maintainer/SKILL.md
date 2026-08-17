---
name: mywallpaperx-maintainer
description: >-
  Repository-specific guidance for maintaining and evolving the MyWallpaperX
  native macOS app without drifting its AppKit product, Video, Web, Scene, or
  shared lifecycle architecture. Use whenever Codex works in this repository
  on code, tests, reviews, diagnostics, architecture discussions, plans,
  documentation, builds, runtime evidence, signing, releases, repository
  governance, or generated-artifact growth. This skill replaces
  build-macos-apps for MyWallpaperX: when it
  applies, do not additionally load build-macos-apps or its sub-skills. Rebuild
  current facts from live code and canonical repository documents, and correct
  this skill when stronger evidence proves its routing or method wrong.
---

# MyWallpaperX Maintainer

Use this Skill as a compact method and routing layer, never as a snapshot of the current implementation. Do not store current capability counts, sample results, active route phases, dirty files, or temporary workarounds here.

## Start With Scope And Authority

1. Classify the request as discussion, read-only review, diagnosis, or implementation. Never let Skill activation expand the user's authorization.
2. Run `git status --short --branch --untracked-files=all` at task start, including read-only review or diagnosis. Assign this batch an explicit owned path set and preserve every unrelated modified, deleted, staged, or untracked path; repeat status before writing when concurrent work may have changed it.
3. Follow repository-root `AGENTS.md` for implementation, validation, commit, sample, and workspace safety rules.
4. Read `docs/README.md` when the task involves behavior, architecture, evidence, documentation, or owner selection. Use its current document-role routing instead of searching history broadly.

Resolve two different questions separately:

- **Current fact:** prefer current code/configuration and reproducible current-run evidence, then use the repository's document-role order to resolve remaining conflicts.
- **Target contract:** use applicable official author behavior, `AGENTS.md`, long-term architecture contracts, and the active route. Existing code, tests, directories, Skill text, memories, and third-party references cannot redefine the target merely because they exist.

Record any difference as deviation debt with the current owner, fallback/route, correction gate, and retirement condition. Never merge current fact and target contract into one precedence list.

Interpret instructions by strength:

| Strength | Meaning |
|---|---|
| Hard boundary | User/workspace safety, clean-room separation, single product output ownership, identity/lifecycle integrity, and evidence honesty. |
| Default method | Producer-to-consumer tracing, vertical slices, local failure radius, and risk-scaled verification. Deviate when stronger evidence justifies a better method and state the replacement gate. |
| Routing hint | Type, path, command, or current owner clue. Verify it live and correct this Skill when stale. |

## Load Only What The Task Needs

All references are one level from this file. Do not load a reference merely because it might become useful later.

| Task surface | Load |
|---|---|
| Local/online video import, library, cache, playback, helper IPC, per-display sessions | [Video method](references/video-engine.md) |
| Workshop Web model, WKWebView host, navigation, property/resource/media/input/audio lifecycle | [Web method](references/web-engine.md) |
| Scene format, shader, graph, Metal, VM, particles, inputs, providers, visual evidence | [Scene method](references/scene-engine.md) |
| Build, test triage, AppKit/window behavior, logs, signing, runtime evidence, Git handoff | [Verification and macOS method](references/verification-and-handoff.md) |
| Skill error, rule/document drift, authority routing, Skill publication | [Skill governance](references/skill-governance.md) |
| Build/runtime output, large reports, residue, writer attribution, cleanup candidates | [Artifact governance](references/artifact-governance.md) |

For cross-runtime work, load only the affected module references and trace the complete current switch chain. Do not assume `WallpaperEngine` owns all Video, Web, and Scene lifecycles. At the current routing level, separately verify:

- persisted product intent and active-runtime state;
- product switch sequencing and invalidation notifications;
- Video/Web request and per-display session ownership plus shared pause/system/audio policy;
- Scene launch, surface, frame, and teardown ownership;
- system-still/static-image apply, per-display publication, and dynamic-runtime teardown ownership;
- the output owner that actually publishes each desktop surface.

Current type names such as `WallpaperManager`, `MainWindowCoordinator`, `WallpaperRuntimeSwitch`, `WallpaperEngine`, and `SceneDesktopWallpaperHost` are discovery hints, not a permanent target diagram. If a unified coordinator becomes the target, establish it first in the canonical architecture and migrate ownership explicitly.

Do not broadly load `docs/history/`, `.codex` reports, real Workshop content, or `Reference Project/`. Read history only for a named historical question. Read clean-room reference material only under the active research workflow and context-separation rules.

## Define The Decision Note

Keep a short decision note in the working context; do not create a document for a small change:

```yaml
mode: discussion | read-only-review | diagnosis | implementation
target_current_debt: target contract; current fact; deviation debt
owner_and_breakpoint: producer -> first wrong identity -> committing consumer
owned_scope_and_failure_radius: paths; smallest request/surface/session/effect affected
verification_boundary: positive case; counterexample; runtime/build gates; skipped claims
```

Add module-specific identity, route, source, or evidence fields only when the loaded reference requires them.

## Execute One Coherent Result

1. Trace the real producer-to-consumer chain and locate the first incorrect identity, state transition, or output. Do not infer ownership from a similar filename or a dated report.
2. Close one user-visible or executable vertical result. Cross directories when one responsibility requires it, but do not bundle independent behavior or opportunistic cleanup.
3. Extend the existing responsible owner. If the canonical target requires a missing or replacement owner or process boundary, add only that owner and define delegation, route, transfer, teardown, rollback, and retirement. Never create an unregistered, independent, or long-lived second coordinator, host, renderer, resource registry, state tree, clock, pause policy, graph, or final output path; migration coexistence is allowed only behind an explicit route with one product output decision and typed fallback.
4. Preserve identity across async boundaries: intent epoch, request, generation, display, session, surface, navigation, provider, target, and publication as applicable. Add stale/teardown counterexamples when these can change.
5. Keep integrity failures fail-closed at the smallest unsafe unit. Keep ordinary visual or optional-provider failures local and observable when the canonical contract permits it.
6. Run the smallest gate that can falsify the change, confirm the changed code actually loaded, then escalate by risk. Never use build, ready, route, non-black, matrix, or one sample as a stronger visible/parity/release claim.
7. Update each role-specific canonical authority whose owned fact changed, while recording each fact in only one owning document. Never copy a new current result into this Skill.
8. Freeze the owned diff, inspect untracked files explicitly, and classify generated artifacts. After the final build, runtime, or gate, repeat status and relevant process/output checks; stop exact owned processes or record explicit retention, then report all skipped or unresolved boundaries.

## Correct This Skill Without Following It Blindly

When current evidence conflicts with this Skill, classify the conflict as `skill-error`, `implementation-deviation`, `contract-change`, or `ambiguous`; see [Skill governance](references/skill-governance.md).

The user's standing maintenance request authorizes the smallest correction to a proven Skill error during a write-authorized implementation task only when that error directly affects the current objective; product-code write permission without both conditions is insufficient. Add the affected Skill paths to the owned scope, confirm no conflicting lane owns them, and replace or delete the wrong guidance. In read-only work, for future-only relevance, or on ownership conflict, report a correction candidate instead. Do not append layers of exceptions, and keep an independently scoped Skill correction in a separate commit.

Scale Skill validation to the correction: mechanical fixes need deterministic validation; owner or domain-method changes need a targeted fresh-context test; cross-cutting authority/trigger changes need all affected domains. The Skill remains subordinate to current code evidence and canonical target contracts.

## Replace Generic macOS Guidance

Do not load `build-macos-apps` or any namespaced sub-skill after this Skill triggers. The conditional [Verification and macOS method](references/verification-and-handoff.md) carries the useful shell-first build/debug, AppKit/window, test triage, telemetry, nested-code signing, packaging, and notarization methods, narrowed to this repository's multi-runtime architecture.

## Report Only Applicable Closure

Report the actual result and owner, verification commands and outcomes, skipped/blocked gates, remaining deviation or fallback, and staging/commit/push state. Report runtime identities, route state, signing, or artifact retention only when the task touched them. Mark non-applicable fields as such rather than executing unrelated work for checklist completeness.

Never treat "the Skill was followed" as validation. The final claim is bounded by the current code and evidence actually inspected or run.
