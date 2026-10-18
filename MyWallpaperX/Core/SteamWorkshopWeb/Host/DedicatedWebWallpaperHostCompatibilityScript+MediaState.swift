//
//  DedicatedWebWallpaperHostCompatibilityScript+MediaState.swift
//  MyWallpaperX
//

let webCompatibilityScriptMediaState = #"""
  // The only writer of official media state: host-selected system songs. Page
  // audio/video events still control page playback, but cannot publish metadata.
  let wallpaperSystemMediaCursor = null;
  let wallpaperPendingSystemMediaState = null;
  const wallpaperCompareMediaCounter = (first, second) => {
    const a = String(first).replace(/^0+(?=\d)/, '');
    const b = String(second).replace(/^0+(?=\d)/, '');
    return a.length === b.length ? (a === b ? 0 : (a < b ? -1 : 1)) : (a.length < b.length ? -1 : 1);
  };
  const wallpaperPublishSystemMediaState = (next) => {
    const previous = window.__myWallpaperMediaState;
    // Replace the entire session before invoking any author callback. A callback
    // inspecting another channel never sees artwork/properties from two tracks.
    window.__myWallpaperMediaIntegrationEnabled = next.status.enabled;
    window.__myWallpaperMediaState = next;
    const channels = [
      ['status', 'updateMediaStatus', mediaStatusListeners],
      ['properties', 'updateMediaProperties', mediaPropertiesListeners],
      ['thumbnail', 'updateMediaThumbnail', mediaThumbnailListeners],
      ['timeline', 'updateMediaTimeline', mediaTimelineListeners],
      ['playback', 'updateMediaPlayback', mediaPlaybackListeners]
    ];
    for (const [key, callback, listeners] of channels) {
      // Thumbnail objects are reused when the host omits unchanged artwork, so
      // timeline updates never scan/base64-serialize the cover on the JS thread.
      const changed = key === 'thumbnail'
        ? previous[key] !== next[key]
        : JSON.stringify(previous[key]) !== JSON.stringify(next[key]);
      if (!changed) continue;
      const legacy = window.wallpaperPropertyListener;
      try {
        if (legacy && typeof legacy[callback] === 'function') legacy[callback](next[key]);
      } catch (error) {
        hostLogger?.post('media.' + key + '.error', error && error.message ? error.message : error);
      }
      for (const listener of listeners) {
        try { listener(next[key]); } catch (_) {}
      }
    }
  };
  window.__myWallpaperApplySystemMedia = (payload, expectedToken, expectedNonce) => {
    if (window.__myWallpaperHostFrameEndpointToken !== expectedToken
      || window.__myWallpaperHostFrameDocumentNonce !== expectedNonce) return false;
    if (!payload || !/^\d+$/.test(payload.epoch) || !/^\d+$/.test(payload.revision)
      || !/^\d+$/.test(payload.deliverySequence)) return false;
    if (wallpaperSystemMediaCursor && wallpaperSystemMediaCursor.token === expectedToken) {
      const epochOrder = wallpaperCompareMediaCounter(payload.epoch, wallpaperSystemMediaCursor.epoch);
      if (epochOrder < 0 || (epochOrder === 0
        && wallpaperCompareMediaCounter(payload.revision, wallpaperSystemMediaCursor.revision) < 0)
        || wallpaperCompareMediaCounter(payload.deliverySequence, wallpaperSystemMediaCursor.deliverySequence) <= 0) return false;
    }
    const previous = wallpaperPendingSystemMediaState || window.__myWallpaperMediaState;
    const next = Object.freeze({
      status: Object.freeze(payload.status),
      properties: Object.freeze(payload.properties),
      thumbnail: payload.thumbnail === undefined ? previous.thumbnail : Object.freeze(payload.thumbnail),
      timeline: Object.freeze(payload.timeline),
      playback: Object.freeze(payload.playback)
    });
    wallpaperSystemMediaCursor = { token: expectedToken, epoch: payload.epoch, revision: payload.revision, deliverySequence: payload.deliverySequence };
    if (window.wallpaperEngine_paused === true && next.status.enabled === true) {
      wallpaperPendingSystemMediaState = next;
    } else {
      wallpaperPendingSystemMediaState = null;
      wallpaperPublishSystemMediaState(next);
    }
    return true;
  };
  window.__myWallpaperFlushSystemMedia = () => {
    if (!wallpaperPendingSystemMediaState) return;
    const next = wallpaperPendingSystemMediaState;
    wallpaperPendingSystemMediaState = null;
    wallpaperPublishSystemMediaState(next);
  };
"""#
