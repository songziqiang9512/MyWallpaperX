let webCompatibilityScriptInteractionAndRuntimeMedia = #"""
  if (window.HTMLMediaElement && window.HTMLMediaElement.prototype) {
    try {
      const mediaProto = window.HTMLMediaElement.prototype;
      const originalPlay = mediaProto.play;
      if (typeof originalPlay === 'function' && !mediaProto.__mwxPlayWrapped) {
        mediaProto.__mwxPlayWrapped = true;
        mediaProto.play = function(...args) {
          const missingSource = String(this.__mwxMissingSource || '').trim();
          if (missingSource) {
            hostLogger?.post('media.play.skipped', `${this.tagName ? String(this.tagName).toLowerCase() : 'media'} missing=${missingSource}`);
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
            hostLogger?.post('media.play.skipped', `${this.tagName ? String(this.tagName).toLowerCase() : 'media'} src=${resolvedSource || 'none'}`);
            return Promise.resolve();
          }
          const playResult = originalPlay.apply(this, args);
          if (typeof window.__myWallpaperWrapMediaPlayPromise === 'function') {
            return window.__myWallpaperWrapMediaPlayPromise(playResult, this);
          }
          return playResult;
        };
      }
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
