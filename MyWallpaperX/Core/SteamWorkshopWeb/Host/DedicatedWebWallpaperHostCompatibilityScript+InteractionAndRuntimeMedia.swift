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
            // innerHTML/replaceChildren may attach a source created before it
            // had a media parent. Consume its current declaration, not stale
            // currentSrc (WebKit can retain the failed selection while loading).
            const declaredSource = String(this.src || '').trim();
            const hasReplacement = declaredSource ? declaredSource !== missingSource
              : Array.from(this.querySelectorAll('source')).some((source) => {
                  const value = String(source.src || source.getAttribute('src') || '').trim();
                  return value && value !== missingSource;
                });
            if (hasReplacement) delete this.__mwxMissingSource;
            else {
              hostLogger?.post('media.play.skipped', `${this.tagName ? String(this.tagName).toLowerCase() : 'media'} missing=${missingSource}`);
              return Promise.resolve();
            }
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
