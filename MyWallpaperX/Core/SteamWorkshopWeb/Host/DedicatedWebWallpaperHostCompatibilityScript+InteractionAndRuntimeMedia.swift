let webCompatibilityScriptInteractionAndRuntimeMedia = #"""
  if (navigator.mediaSession) {
    try {
      const mediaSession = navigator.mediaSession;
      if (!mediaSession.__mwxActionHandlerWrapped && typeof mediaSession.setActionHandler === 'function') {
        mediaSession.__mwxActionHandlerWrapped = true;
        mediaSession.__mwxActionHandlers = mediaSession.__mwxActionHandlers || {};
        const originalSetActionHandler = mediaSession.setActionHandler.bind(mediaSession);
        mediaSession.setActionHandler = function(action, handler) {
          const normalizedAction = String(action || '').toLowerCase();
          if (normalizedAction) {
            mediaSession.__mwxActionHandlers[normalizedAction] = typeof handler === 'function';
          }
          wallpaperRefreshMediaState();
          return originalSetActionHandler(action, handler);
        };
      }
      if (!mediaSession.__mwxPlaybackStateWrapped) {
        mediaSession.__mwxPlaybackStateWrapped = true;
        let playbackStateValue = typeof mediaSession.playbackState === 'string' ? mediaSession.playbackState : 'none';
        Object.defineProperty(mediaSession, 'playbackState', {
          configurable: true,
          enumerable: true,
          get() {
            return playbackStateValue;
          },
          set(value) {
            playbackStateValue = value;
            wallpaperRefreshMediaState();
          }
        });
      }
    } catch (_) {}
  }
  if (navigator.mediaSession && typeof navigator.mediaSession.setPositionState === 'function') {
    try {
      const originalSetPositionState = navigator.mediaSession.setPositionState.bind(navigator.mediaSession);
      if (!navigator.mediaSession.__mwxPositionStateWrapped) {
        navigator.mediaSession.__mwxPositionStateWrapped = true;
        navigator.mediaSession.__mwxPositionState = null;
        navigator.mediaSession.setPositionState = function(state) {
          navigator.mediaSession.__mwxPositionState = state || null;
          wallpaperRefreshMediaState();
          return originalSetPositionState(state);
        };
      }
    } catch (_) {}
  }
  if (window.HTMLMediaElement && window.HTMLMediaElement.prototype) {
    try {
      const mediaProto = window.HTMLMediaElement.prototype;
      const originalPlay = mediaProto.play;
      if (typeof originalPlay === 'function' && !mediaProto.__mwxPlayWrapped) {
        mediaProto.__mwxPlayWrapped = true;
        mediaProto.play = function(...args) {
          const missingSource = String(this.__mwxMissingSource || '').trim();
          if (missingSource) {
            hostLogger.post('media.play.skipped', `${this.tagName ? String(this.tagName).toLowerCase() : 'media'} missing=${missingSource}`);
            return Promise.resolve();
          }
          const resolvedSource = String(this.currentSrc || this.src || '').trim();
          const normalizedSource = resolvedSource.toLowerCase();
          if (
            !resolvedSource ||
            normalizedSource === 'null' ||
            normalizedSource === 'undefined' ||
            normalizedSource === '(null)' ||
            normalizedSource === 'about:blank' ||
            normalizedSource.endsWith('/null')
          ) {
            hostLogger.post('media.play.skipped', `${this.tagName ? String(this.tagName).toLowerCase() : 'media'} src=${resolvedSource || 'none'}`);
            return Promise.resolve();
          }
          const playResult = originalPlay.apply(this, args);
          if (typeof window.__myWallpaperWrapMediaPlayPromise === 'function') {
            return window.__myWallpaperWrapMediaPlayPromise(playResult, this);
          }
          return playResult;
        };
      }
      const originalSetAttribute = mediaProto.setAttribute;
      if (typeof originalSetAttribute === 'function' && !mediaProto.__mwxSetAttributeWrapped) {
        mediaProto.__mwxSetAttributeWrapped = true;
        mediaProto.setAttribute = function(name, value) {
          const result = originalSetAttribute.call(this, name, value);
          if (String(name || '').toLowerCase() === 'src') {
            wallpaperRefreshMediaState(this);
          }
          return result;
        };
      }
      const defineMediaPropertyHook = (propertyName) => {
        const descriptor = Object.getOwnPropertyDescriptor(mediaProto, propertyName);
        if (!descriptor || typeof descriptor.set !== 'function' || mediaProto[`__mwx_${propertyName}_wrapped`]) return;
        mediaProto[`__mwx_${propertyName}_wrapped`] = true;
        Object.defineProperty(mediaProto, propertyName, {
          configurable: true,
          enumerable: descriptor.enumerable,
          get: descriptor.get,
          set(value) {
            descriptor.set.call(this, value);
            wallpaperRefreshMediaState(this);
          }
        });
      };
      defineMediaPropertyHook('src');
      defineMediaPropertyHook('currentTime');
    } catch (_) {}
  }
  const installWallpaperMediaRuntimeLogging = (() => {
    const installedMediaNodes = new WeakSet();
    const mediaEvents = ['loadedmetadata', 'loadeddata', 'canplay', 'canplaythrough', 'play', 'playing', 'pause', 'waiting', 'stalled', 'suspend', 'emptied', 'ended', 'error'];
    const describeMediaNode = (node, eventName) => {
      try {
        const readyState = Number(node && node.readyState);
        const networkState = Number(node && node.networkState);
        const currentSrc = String((node && (node.currentSrc || node.src)) || '');
        const duration = Number(node && node.duration);
        const currentTime = Number(node && node.currentTime);
        const errorCode = node && node.error ? Number(node.error.code || 0) : 0;
        return [
          eventName,
          node && node.tagName ? String(node.tagName).toLowerCase() : 'media',
          `src=${currentSrc || 'none'}`,
          `readyState=${Number.isFinite(readyState) ? readyState : -1}`,
          `networkState=${Number.isFinite(networkState) ? networkState : -1}`,
          `currentTime=${Number.isFinite(currentTime) ? currentTime.toFixed(3) : 'nan'}`,
          `duration=${Number.isFinite(duration) ? duration.toFixed(3) : 'nan'}`,
          `paused=${node ? !!node.paused : true}`,
          `ended=${node ? !!node.ended : false}`,
          `error=${errorCode}`
        ].join(' ');
      } catch (_) {
        return eventName;
      }
    };
    const installOnNode = (node) => {
      if (!(node instanceof HTMLMediaElement) || installedMediaNodes.has(node)) return;
      installedMediaNodes.add(node);
      for (const eventName of mediaEvents) {
        node.addEventListener(eventName, () => {
          hostLogger.post('media.event', describeMediaNode(node, eventName));
          wallpaperRefreshMediaState(node);
        });
      }
      hostLogger.post('media.observe', describeMediaNode(node, 'attached'));
    };
    const installInRoot = (root) => {
      try {
        if (!root || typeof root.querySelectorAll !== 'function') return;
        root.querySelectorAll('audio,video').forEach(installOnNode);
      } catch (_) {}
    };
    return {
      installOnNode,
      installInRoot
    };
  })();
  installWallpaperMediaRuntimeLogging.installInRoot(document);
  if (typeof MutationObserver === 'function') {
    try {
      const mediaObserver = new MutationObserver((mutations) => {
        for (const mutation of mutations) {
          for (const node of mutation.addedNodes || []) {
            if (node instanceof HTMLMediaElement) {
              installWallpaperMediaRuntimeLogging.installOnNode(node);
              continue;
            }
            if (node && typeof node.querySelectorAll === 'function') {
              installWallpaperMediaRuntimeLogging.installInRoot(node);
            }
          }
        }
      });
      mediaObserver.observe(document.documentElement || document, { childList: true, subtree: true });
    } catch (_) {}
  }
  const visibilityOverrideResults = [
    defineVisibilityProperty(document, 'hidden', () => false),
    defineVisibilityProperty(Document.prototype, 'hidden', () => false),
    defineVisibilityProperty(document, 'visibilityState', () => 'visible'),
    defineVisibilityProperty(Document.prototype, 'visibilityState', () => 'visible'),
    defineVisibilityProperty(document, 'webkitVisibilityState', () => 'visible'),
    defineVisibilityProperty(Document.prototype, 'webkitVisibilityState', () => 'visible')
  ];
"""#
