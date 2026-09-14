# QuickJS-NG core snapshot

This directory contains the minimal QuickJS-NG core sources used by the
SceneScript runtime. The snapshot is pinned to upstream commit
`bbe0480a68c664d7737eecde260fd47224b2c0d6` (2026-08-16).

Only the core runtime is included. The QuickJS command-line shell and its
standard-library host modules are intentionally excluded: SceneScript gets a
project-owned allowlist and never receives filesystem, network, process, DOM,
or Node globals.

The upstream MIT license is preserved in `LICENSE`. Product code must use the
`SceneScript` wrapper rather than depending on QuickJS internals directly.
