//
//  DedicatedWebWallpaperHostCompatibilityScript+MediaState.swift
//  MyWallpaperX
//

let webCompatibilityScriptMediaState = #"""
  const wallpaperMediaContentType = (node) => {
    try {
      const tagName = String(node && node.tagName ? node.tagName : '').toLowerCase();
      if (tagName === 'audio') return 'music';
      if (tagName === 'video') return 'video';
    } catch (_) {}
    return '';
  };
  const wallpaperMediaPropertiesPayload = (node) => {
    const fallbackTitle = wallpaperDocumentTitle();
    const mediaSource = node ? (node.currentSrc || node.src || '') : '';
    const sourceTitle = wallpaperFileStem(mediaSource);
    const mediaSession = wallpaperMediaSessionMetadata();
    const title = (mediaSession && mediaSession.title) || sourceTitle || fallbackTitle || '';
    const artist = (mediaSession && mediaSession.artist) || wallpaperDocumentMetaContent('meta[name="author"]') || '';
    const albumTitle =
      (mediaSession && mediaSession.album) ||
      (fallbackTitle && fallbackTitle !== title ? fallbackTitle : '');
    const position = node && Number.isFinite(Number(node.currentTime)) ? Number(node.currentTime) : 0;
    const duration = node && Number.isFinite(Number(node.duration)) ? Number(node.duration) : 0;
    // 官方契约字段：title / artist / subTitle / albumTitle / albumArtist /
    // genres / contentType。本实现的数据源是页面媒体节点而非系统级媒体会话，
    // 没有来源的字段按空串补齐。
    return {
      title,
      artist,
      subTitle: '',
      albumTitle,
      albumArtist: '',
      genres: '',
      contentType: wallpaperMediaContentType(node),
      position,
      duration
    };
  };
  const wallpaperMediaThumbnailColorFields = {
    primaryColor: '',
    secondaryColor: '',
    tertiaryColor: '',
    textColor: '',
    highContrastColor: ''
  };
  // 缩略图取色结果按 URL 缓存：null 表示不可取色（跨源污染 canvas 或加载失败），
  // 不再重复取色。
  const wallpaperMediaThumbnailColorCache = new Map();
  const wallpaperMediaThumbnailColorRequests = new Set();
  const wallpaperMediaColorHex = (red, green, blue) => '#' + [red, green, blue]
    .map((value) => Math.max(0, Math.min(255, Math.round(value))).toString(16).padStart(2, '0'))
    .join('');
  const wallpaperMediaRelativeLuminance = (rgb) => {
    const linear = (value) => {
      const normalized = Math.max(0, Math.min(255, value)) / 255;
      return normalized <= 0.03928 ? normalized / 12.92 : ((normalized + 0.055) / 1.055) ** 2.4;
    };
    return 0.2126 * linear(rgb[0]) + 0.7152 * linear(rgb[1]) + 0.0722 * linear(rgb[2]);
  };
  const wallpaperMediaContrastRatio = (first, second) => {
    const lighter = Math.max(first, second);
    const darker = Math.min(first, second);
    return (lighter + 0.05) / (darker + 0.05);
  };
  const wallpaperMediaThumbnailColorFieldsFromPixels = (pixels) => {
    const buckets = new Map();
    for (let index = 0; index + 3 < pixels.length; index += 4) {
      if (pixels[index + 3] < 128) continue;
      const red = pixels[index];
      const green = pixels[index + 1];
      const blue = pixels[index + 2];
      const key = ((red >> 4) << 8) | ((green >> 4) << 4) | (blue >> 4);
      const entry = buckets.get(key);
      if (entry) {
        entry.count += 1;
        entry.red += red;
        entry.green += green;
        entry.blue += blue;
      } else {
        buckets.set(key, { count: 1, red, green, blue });
      }
    }
    const dominant = Array.from(buckets.values()).sort((first, second) => second.count - first.count).slice(0, 3);
    if (dominant.length === 0) return null;
    const channelAverage = (entry, channel) => entry[channel] / entry.count;
    const dominantRGB = [channelAverage(dominant[0], 'red'), channelAverage(dominant[0], 'green'), channelAverage(dominant[0], 'blue')];
    const asHex = (entry) => entry
      ? wallpaperMediaColorHex(channelAverage(entry, 'red'), channelAverage(entry, 'green'), channelAverage(entry, 'blue'))
      : '';
    const luminance = wallpaperMediaRelativeLuminance(dominantRGB);
    const whiteContrast = wallpaperMediaContrastRatio(luminance, 1);
    const blackContrast = wallpaperMediaContrastRatio(luminance, 0);
    const sufficientContrast = whiteContrast >= 4.5 ? '#ffffff' : (blackContrast >= 4.5 ? '#000000' : null);
    return {
      primaryColor: asHex(dominant[0]),
      secondaryColor: asHex(dominant[1]),
      tertiaryColor: asHex(dominant[2]),
      // textColor 取与主色对比足够（>= 4.5:1）的黑白；都不足时取对比更高者。
      textColor: sufficientContrast || (whiteContrast >= blackContrast ? '#ffffff' : '#000000'),
      // highContrastColor 是黑白中对主色对比更高者。
      highContrastColor: whiteContrast >= blackContrast ? '#ffffff' : '#000000'
    };
  };
  const wallpaperAnalyzeMediaThumbnail = (url) => {
    if (!url || wallpaperMediaThumbnailColorCache.has(url) || wallpaperMediaThumbnailColorRequests.has(url)) return;
    wallpaperMediaThumbnailColorRequests.add(url);
    const finish = (fields) => {
      wallpaperMediaThumbnailColorRequests.delete(url);
      wallpaperMediaThumbnailColorCache.set(url, fields);
      // Map 保插入序：超限时逐出最旧条目，当前 URL 刚写入不会被误逐。
      if (wallpaperMediaThumbnailColorCache.size > 64) {
        wallpaperMediaThumbnailColorCache.delete(wallpaperMediaThumbnailColorCache.keys().next().value);
      }
      // 取色结果到达后重放一次媒体状态，让已注册的监听器拿到颜色字段。
      wallpaperRefreshMediaState();
    };
    try {
      const image = new Image();
      image.onload = () => {
        try {
          const size = 32;
          const canvas = document.createElement('canvas');
          canvas.width = size;
          canvas.height = size;
          const context = canvas.getContext('2d');
          if (!context) {
            finish(null);
            return;
          }
          context.drawImage(image, 0, 0, size, size);
          finish(wallpaperMediaThumbnailColorFieldsFromPixels(context.getImageData(0, 0, size, size).data));
        } catch (_) {
          // 跨源图片会污染 canvas，getImageData 抛错即视为无源。
          finish(null);
        }
      };
      image.onerror = () => finish(null);
      image.src = url;
    } catch (_) {
      finish(null);
    }
  };
  const wallpaperMediaThumbnailPayload = (node) => {
    const thumbnail = wallpaperMediaThumbnailURL(node);
    wallpaperAnalyzeMediaThumbnail(thumbnail);
    const source = node ? String(node.currentSrc || node.src || '') : '';
    const title = wallpaperFileStem(source) || wallpaperDocumentTitle() || '';
    return Object.assign(
      {
        thumbnail,
        source,
        title,
        available: thumbnail ? 'true' : 'false'
      },
      wallpaperMediaThumbnailColorFields,
      wallpaperMediaThumbnailColorCache.get(thumbnail) || {}
    );
  };
  const wallpaperMediaTimelinePayload = (node) => {
    const mediaSessionPosition = wallpaperMediaSessionPositionState();
    const position =
      mediaSessionPosition && Number.isFinite(Number(mediaSessionPosition.position))
        ? Number(mediaSessionPosition.position)
        : (node && Number.isFinite(Number(node.currentTime)) ? Number(node.currentTime) : 0);
    const duration =
      mediaSessionPosition && Number.isFinite(Number(mediaSessionPosition.duration))
        ? Number(mediaSessionPosition.duration)
        : (node && Number.isFinite(Number(node.duration)) ? Number(node.duration) : 0);
    const playbackRate =
      mediaSessionPosition && Number.isFinite(Number(mediaSessionPosition.playbackRate))
        ? Number(mediaSessionPosition.playbackRate)
        : (node && Number.isFinite(Number(node.playbackRate)) ? Number(node.playbackRate) : 1);
    return {
      position,
      duration,
      playbackRate,
      progress:
        Number.isFinite(duration) && duration > 0
          ? Math.max(0, Math.min(1, position / duration))
          : 0,
      available: Number.isFinite(duration) && duration > 0 ? 'true' : 'false'
    };
  };
  const wallpaperMediaSessionActionHandlers = () => {
    try {
      return navigator.mediaSession && navigator.mediaSession.__mwxActionHandlers
        ? navigator.mediaSession.__mwxActionHandlers
        : {};
    } catch (_) {
      return {};
    }
  };
  const wallpaperMediaPlaybackPayload = (node, pausedOverride) => {
    const mediaSession = wallpaperMediaSessionMetadata();
    const actionHandlers = wallpaperMediaSessionActionHandlers();
    const paused = typeof pausedOverride === 'boolean' ? pausedOverride : (node ? !!node.paused : true);
    const ended = node ? !!node.ended : false;
    const muted = node ? !!node.muted : false;
    const position = node && Number.isFinite(Number(node.currentTime)) ? Number(node.currentTime) : 0;
    const duration = node && Number.isFinite(Number(node.duration)) ? Number(node.duration) : 0;
    const rate = node && Number.isFinite(Number(node.playbackRate)) ? Number(node.playbackRate) : 1;
    let state = mediaPlaybackConstants.PLAYBACK_STOPPED;
    if (ended) {
      state = mediaPlaybackConstants.PLAYBACK_STOPPED;
    } else if (mediaSession && mediaSession.playbackState === 'playing') {
      state = mediaPlaybackConstants.PLAYBACK_PLAYING;
    } else if (mediaSession && mediaSession.playbackState === 'paused') {
      state = mediaPlaybackConstants.PLAYBACK_PAUSED;
    } else if (paused) {
      state = mediaPlaybackConstants.PLAYBACK_PAUSED;
    } else if (node) {
      state = mediaPlaybackConstants.PLAYBACK_PLAYING;
    }
    return {
      state,
      position,
      duration,
      rate,
      muted: muted ? 'true' : 'false',
      available: node ? 'true' : 'false',
      canPlay: actionHandlers.play ? 'true' : 'false',
      canPause: actionHandlers.pause ? 'true' : 'false',
      canSeekForward: actionHandlers.seekforward ? 'true' : 'false',
      canSeekBackward: actionHandlers.seekbackward ? 'true' : 'false'
    };
  };
  const wallpaperMediaSessionPositionState = () => {
    try {
      if (!navigator.mediaSession || typeof navigator.mediaSession.setPositionState !== 'function') {
        return null;
      }
      return navigator.mediaSession.__mwxPositionState || null;
    } catch (_) {
      return null;
    }
  };
  const wallpaperMediaStatusPayload = (node) => {
    const available = !!node;
    const playback = window.__myWallpaperMediaState && window.__myWallpaperMediaState.playback
      ? window.__myWallpaperMediaState.playback
      : null;
    const state = playback && playback.state ? playback.state : mediaPlaybackConstants.PLAYBACK_STOPPED;
    return {
      // 官方语义：enabled 表示用户是否启用媒体集成选项（宿主设置），
      // available 才表示当前是否有可用的媒体会话。
      enabled: wallpaperMediaIntegrationEnabled(),
      available: available ? 'true' : 'false',
      state
    };
  };
  const wallpaperDispatchMediaProperties = (node) => {
    const payload = wallpaperMediaPropertiesPayload(node);
    window.__myWallpaperMediaState.properties = payload;
    try {
      if (window.wallpaperPropertyListener && typeof window.wallpaperPropertyListener.updateMediaProperties === 'function') {
        window.wallpaperPropertyListener.updateMediaProperties(payload);
      }
    } catch (error) {
      hostLogger.post('media.properties.error', error && error.message ? error.message : error);
    }
    for (const listener of mediaPropertiesListeners) {
      try { listener(payload); } catch (_) {}
    }
  };
  const wallpaperDispatchMediaStatus = (node) => {
    const payload = wallpaperMediaStatusPayload(node);
    window.__myWallpaperMediaState.status = payload;
    try {
      if (window.wallpaperPropertyListener && typeof window.wallpaperPropertyListener.updateMediaStatus === 'function') {
        window.wallpaperPropertyListener.updateMediaStatus(payload);
      }
    } catch (error) {
      hostLogger.post('media.status.error', error && error.message ? error.message : error);
    }
    for (const listener of mediaStatusListeners) {
      try { listener(payload); } catch (_) {}
    }
  };
  const wallpaperDispatchMediaThumbnail = (node) => {
    const payload = wallpaperMediaThumbnailPayload(node);
    const hadThumbnail = wallpaperHasMediaThumbnail(window.__myWallpaperMediaState.thumbnail);
    const hasThumbnail = wallpaperHasMediaThumbnail(payload);
    window.__myWallpaperMediaState.thumbnail = payload;
    if (!hasThumbnail && !hadThumbnail) return;
    try {
      if (window.wallpaperPropertyListener && typeof window.wallpaperPropertyListener.updateMediaThumbnail === 'function') {
        window.wallpaperPropertyListener.updateMediaThumbnail(payload);
      }
    } catch (error) {
      hostLogger.post('media.thumbnail.error', error && error.message ? error.message : error);
    }
    for (const listener of mediaThumbnailListeners) {
      try { listener(payload); } catch (_) {}
    }
  };
  const wallpaperDispatchMediaTimeline = (node) => {
    const payload = wallpaperMediaTimelinePayload(node);
    window.__myWallpaperMediaState.timeline = payload;
    try {
      if (window.wallpaperPropertyListener && typeof window.wallpaperPropertyListener.updateMediaTimeline === 'function') {
        window.wallpaperPropertyListener.updateMediaTimeline(payload);
      }
    } catch (error) {
      hostLogger.post('media.timeline.error', error && error.message ? error.message : error);
    }
    for (const listener of mediaTimelineListeners) {
      try { listener(payload); } catch (_) {}
    }
  };
  const wallpaperDispatchMediaPlayback = (node, pausedOverride) => {
    const payload = wallpaperMediaPlaybackPayload(node, pausedOverride);
    window.__myWallpaperMediaState.playback = payload;
    try {
      if (window.wallpaperPropertyListener && typeof window.wallpaperPropertyListener.updateMediaPlayback === 'function') {
        window.wallpaperPropertyListener.updateMediaPlayback(payload);
      }
    } catch (error) {
      hostLogger.post('media.playback.error', error && error.message ? error.message : error);
    }
    for (const listener of mediaPlaybackListeners) {
      try { listener(payload); } catch (_) {}
    }
  };
  const wallpaperNotifyFullMediaState = (preferredNode, pausedOverride) => {
    const node = preferredNode || wallpaperPreferredMediaNode();
    wallpaperDispatchMediaStatus(node);
    wallpaperDispatchMediaProperties(node);
    wallpaperDispatchMediaThumbnail(node);
    wallpaperDispatchMediaTimeline(node);
    wallpaperDispatchMediaPlayback(node, pausedOverride);
  };
  const wallpaperQueueMediaRefresh = (() => {
    let scheduled = false;
    let pendingNode = null;
    let pendingPausedOverride = undefined;
    return (preferredNode, pausedOverride) => {
      if (preferredNode) {
        pendingNode = preferredNode;
      }
      if (typeof pausedOverride === 'boolean') {
        pendingPausedOverride = pausedOverride;
      }
      if (scheduled) return;
      scheduled = true;
      const flush = () => {
        scheduled = false;
        const nextNode = pendingNode;
        const nextPausedOverride = pendingPausedOverride;
        pendingNode = null;
        pendingPausedOverride = undefined;
        wallpaperNotifyFullMediaState(nextNode, nextPausedOverride);
      };
      if (typeof window.requestAnimationFrame === 'function') {
        window.requestAnimationFrame(flush);
      } else {
        window.setTimeout(flush, 0);
      }
    };
  })();
  const wallpaperRefreshMediaState = (preferredNode, pausedOverride) => {
    wallpaperQueueMediaRefresh(preferredNode, pausedOverride);
  };
"""#
