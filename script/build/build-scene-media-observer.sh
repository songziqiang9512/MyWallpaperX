#!/bin/bash
# Experimental system-media transport. Build project-authored code against the
# SDK's public Perl XS headers; no reference binaries or private entitlements.
# Ships in Developer ID releases by release-owner decision (2026-10-07, user-
# verified); Mac App Store builds must not include this backend (D6).
set -euo pipefail
mwx_destination="$1"
mwx_source="$SRCROOT/MyWallpaperX/Core/SteamWorkshopScene/Systems/Media/Observer/SceneMediaObserver.m"
mwx_sdk="$(xcrun --sdk macosx --show-sdk-path)"
mwx_perl_core="$(/usr/bin/perl -MConfig -e 'print "$Config{archlib}/CORE"')"
if [[ ! -f "$mwx_sdk$mwx_perl_core/XSUB.h" ]]; then
  echo "Scene media observer: matching system Perl XS SDK headers unavailable" >&2
  exit 1
fi
mwx_arch_flags=()
for mwx_arch in ${ARCHS:-$(uname -m)}; do mwx_arch_flags+=(-arch "$mwx_arch"); done
mkdir -p "$mwx_destination"
xcrun --sdk macosx clang -dynamiclib -fobjc-arc \
  -Wno-compound-token-split-by-macro \
  -mmacosx-version-min="${MACOSX_DEPLOYMENT_TARGET:-14.0}" \
  "${mwx_arch_flags[@]}" -isystem "$mwx_sdk$mwx_perl_core" \
  -framework Foundation -framework AppKit -framework ImageIO \
  -undefined dynamic_lookup "$mwx_source" -o "$mwx_destination/SceneMediaObserver.dylib"
if [[ "${CODE_SIGNING_ALLOWED:-YES}" != NO ]]; then
  /usr/bin/codesign --force --options runtime --sign "${EXPANDED_CODE_SIGN_IDENTITY:--}" \
    "$mwx_destination/SceneMediaObserver.dylib"
fi
