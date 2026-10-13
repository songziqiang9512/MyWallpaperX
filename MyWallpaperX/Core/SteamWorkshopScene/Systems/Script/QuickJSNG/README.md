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

The local `quickjs.c` patch implements only `RegExp.$1` through `RegExp.$9`
from the [TC39 legacy RegExp proposal](https://github.com/tc39/proposal-regexp-legacy-features/tree/e4257f8e83c4d4b648ef1b6150c01ba5938def37)
(Stage 3, checked 2026-10-13). It does not claim the entire proposal or current
ECMA-262 coverage. The nine configurable, non-enumerable native getters have
no setters and require the original intrinsic constructor as receiver.

The existing context owns the capture slots; the original RegExp object owns
its immutable creation-realm identity and legacy eligibility, using the
runtime's existing context-reference/low-bit-tag representation so the shared
JSObject header stays 72 bytes on the product's arm64 ABI.
Both follow the runtime's normal marking and finalization. Successful native
matches publish all nine slots; failed matches retain them, same-realm
subclass matches invalidate them, and foreign-realm matches do not update
either realm. The original matcher, native exec identity and empty replacement
fastpath remain in place. That fastpath prepares captures from native positions
after each match so a later output failure retains the last completed match.
Publication tracks the current capture range, replacing used slots and clearing
the previous tail once; repeated no-capture matches keep the other slots empty
without releasing nine empty values again. No input string or second cache is retained.
Long-lived slice captures detach their captured bytes through the existing
8/16-bit constructors, and context captures join the existing memory estimator.
Required lastIndex writes precede capture publication, including a receiver
frozen by the exec getter or lastIndex conversion; zero-length progress and the
final failed-match reset keep the original native exec contract.
It adds native capture preparation, without a JavaScript exec wrapper.
The fastpath retains the actual native exec realm even when exec is borrowed,
until both successful and exceptional matching paths have returned;
exceptions from its constructor/exec lookup propagate through replace.
An allocation failure in replace's initial output buffer also exits before
the fastpath, preserving the original exception instead of returning a
successful value with that exception still pending.

The existing SceneScript QuickJS host gate covers owned timer inputs, String
matching and replacement order, descriptors, mutable prototypes, construction,
two contexts, GC, interruption and allocation failure. The D4 decision is in
`docs/scene/roadmap/batch2/script-component-api-design.md`. On upstream refresh,
compare this surface and these regressions first; retire the local patch only
when the replacement intrinsic supplies the same tested contracts. The
upstream commit and MIT attribution above remain unchanged.
