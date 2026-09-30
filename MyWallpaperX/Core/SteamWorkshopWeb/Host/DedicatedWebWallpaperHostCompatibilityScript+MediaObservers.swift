//
//  DedicatedWebWallpaperHostCompatibilityScript+MediaObservers.swift
//  MyWallpaperX
//

let webCompatibilityScriptMediaObservers = #"""
  // document-start 顶层补丁区：attachShadow 包装器（F01）与
  // addEventListener/removeEventListener DOMContentLoaded 同一性补丁（F40）
  // 必须在 DCL 回调之外、页面解析期之前安装，才能覆盖解析期注册的监听器与
  // 解析期创建的 shadow root。两者的具体实现（installWallpaperShadowObserver、
  // wallpaperEnsureOptionalSliderControls）声明在下方 DCL 回调作用域内，这里
  // 经 window 级 holder（__mwxInstallWallpaperShadowObserver /
  // __mwxEnsureOptionalSliderControls）惰性桥接：包装器只读 window 属性，
  // 不直接引用回调作用域标识符，避免解析期调用命中 TDZ/未定义。
  try {
    const originalAttachShadow = window.Element && window.Element.prototype &&
      typeof window.Element.prototype.attachShadow === 'function'
      ? window.Element.prototype.attachShadow
      : null;
    if (originalAttachShadow && window.Element.prototype.__mwxAttachShadowWrapped !== true) {
      window.Element.prototype.attachShadow = function(init) {
        const shadowRoot = originalAttachShadow.call(this, init);
        try {
          if (typeof window.__mwxInstallWallpaperShadowObserver === 'function') {
            window.__mwxInstallWallpaperShadowObserver(shadowRoot);
          }
        } catch (_) {}
        try { wallpaperRefreshMediaState(); } catch (_) {}
        return shadowRoot;
      };
      window.Element.prototype.__mwxAttachShadowWrapped = true;
    }
  } catch (_) {}
  try {
    const originalAddEventListener = EventTarget.prototype.addEventListener;
    const originalRemoveEventListener = EventTarget.prototype.removeEventListener;
    if (
      typeof originalAddEventListener === 'function' &&
      typeof originalRemoveEventListener === 'function' &&
      EventTarget.prototype.__mwxDOMReadyGuardPatched !== true
    ) {
      const domReadyWrappedListeners = new WeakMap();
      const wrapDOMContentLoadedListener = (listener) => {
        const existingWrappedListener = domReadyWrappedListeners.get(listener);
        if (existingWrappedListener) return existingWrappedListener;
        const wrappedListener = function(event) {
          try {
            if (
              window.__mwxEnsureOptionalSliderControls &&
              typeof window.__mwxEnsureOptionalSliderControls.install === 'function'
            ) {
              window.__mwxEnsureOptionalSliderControls.install(document);
            }
          } catch (_) {}
          return listener.call(this, event);
        };
        try { Object.defineProperty(wrappedListener, 'name', { value: listener.name || 'mwxDOMContentLoadedListener' }); } catch (_) {}
        domReadyWrappedListeners.set(listener, wrappedListener);
        return wrappedListener;
      };
      EventTarget.prototype.addEventListener = function(type, listener, options) {
        if (
          String(type || '') === 'DOMContentLoaded' &&
          typeof listener === 'function' &&
          (this === document || this === window)
        ) {
          return originalAddEventListener.call(this, type, wrapDOMContentLoadedListener(listener), options);
        }
        return originalAddEventListener.call(this, type, listener, options);
      };
      EventTarget.prototype.removeEventListener = function(type, listener, options) {
        if (
          String(type || '') === 'DOMContentLoaded' &&
          typeof listener === 'function' &&
          (this === document || this === window)
        ) {
          const wrappedListener = domReadyWrappedListeners.get(listener);
          if (wrappedListener) {
            return originalRemoveEventListener.call(this, type, wrappedListener, options);
          }
        }
        return originalRemoveEventListener.call(this, type, listener, options);
      };
      EventTarget.prototype.__mwxDOMReadyGuardPatched = true;
    }
  } catch (_) {}
  document.addEventListener('DOMContentLoaded', () => {
    // 本脚本按 frame 注入：就绪信号是宿主屏幕级状态机（applyCompatibilityState、
    // markScreenReady）的触发条件，只由顶层 frame 发出。
    if (wallpaperIsTopFrame === true) {
      hostLogger.post('dom.ready', document.location.href);
    }
    try {
      document.documentElement.style.width = '100%';
      document.documentElement.style.height = '100%';
      document.body && (document.body.style.width = '100%');
      document.body && (document.body.style.height = '100%');
    } catch (_) {}
    const registeredMediaNodes = new WeakSet();
    let loggedFirstMediaNode = false;
    let loggedFirstVideoCanPlay = false;
    const mediaStateSummary = (node) => {
      const source = node.currentSrc || node.src || 'inline-media';
      const parts = [source];
      try { parts.push(`tag=${(node.tagName || 'media').toLowerCase()}`); } catch (_) {}
      try { parts.push(`readyState=${Number(node.readyState || 0)}`); } catch (_) {}
      try { parts.push(`networkState=${Number(node.networkState || 0)}`); } catch (_) {}
      try { parts.push(`paused=${node.paused ? 'true' : 'false'}`); } catch (_) {}
      try { parts.push(`ended=${node.ended ? 'true' : 'false'}`); } catch (_) {}
      try { parts.push(`muted=${node.muted ? 'true' : 'false'}`); } catch (_) {}
      try { parts.push(`currentTime=${Number(node.currentTime || 0).toFixed(3)}`); } catch (_) {}
      try { parts.push(`duration=${Number(node.duration || 0).toFixed(3)}`); } catch (_) {}
      try {
        if (typeof node.videoWidth === 'number' && typeof node.videoHeight === 'number') {
          parts.push(`videoSize=${node.videoWidth}x${node.videoHeight}`);
        }
      } catch (_) {}
      try {
        const rect = node.getBoundingClientRect();
        parts.push(`rect=${Math.round(rect.width)}x${Math.round(rect.height)}`);
      } catch (_) {}
      try { parts.push(`visibility=${document.visibilityState || 'unknown'}`); } catch (_) {}
      return parts.join(' ');
    };
    const postMediaState = (type, node) => hostLogger.post(type, mediaStateSummary(node));
    Array.from(document.querySelectorAll('source')).forEach((sourceNode) => {
      const src = (sourceNode.getAttribute('src') || '').trim();
      if (!src) {
        hostLogger.post('resource.sanitized', `empty-source ${sourceNode.outerHTML}`);
        sourceNode.remove();
      }
    });
    // 作者意图记录：页面自己调用 play()/pause() 才改写 __myWallpaperAuthorPaused。
    // 宿主暂停走 WebKit 原生媒体门（setAllMediaPlaybackSuspended）与兼容层的
    // 原始方法调用，都不经过这两个包装器，因此不会被误记为作者暂停。
    if (typeof HTMLMediaElement !== 'undefined' && typeof HTMLMediaElement.prototype.play === 'function') {
      const _originalPlay = HTMLMediaElement.prototype.play;
      HTMLMediaElement.prototype.play = function() {
        try { this.__myWallpaperAuthorPaused = false; } catch (_) {}
        const isInvalidMediaSource =
          typeof window.__myWallpaperIsInvalidMediaSourceValue === 'function'
            ? window.__myWallpaperIsInvalidMediaSourceValue
            : (value) => !String(value || '').trim();
        const mediaSrc = this.currentSrc || (this.getAttribute && this.getAttribute('src')) || this.src || '';
        let hasSrc = !!mediaSrc && !isInvalidMediaSource(mediaSrc);
        if (!hasSrc && typeof this.querySelectorAll === 'function') {
          try {
            hasSrc = Array.from(this.querySelectorAll('source')).some((sourceNode) => {
              const sourceValue = sourceNode.currentSrc || (sourceNode.getAttribute && sourceNode.getAttribute('src')) || sourceNode.src || '';
              return !!sourceValue && !isInvalidMediaSource(sourceValue);
            });
          } catch (_) {}
        }
        if (!hasSrc) {
          hostLogger.post('resource.sanitized', 'play() skipped: no src on media node');
          return Promise.resolve();
        }
        return _originalPlay.apply(this, arguments);
      };
    }
    // 原始 pause 交给 window 保存：宿主暂停分支必须绕过本包装器调用它，
    // 否则兼容层自己的暂停会被记成作者暂停，恢复时被错误地跳过播放。
    if (typeof HTMLMediaElement !== 'undefined' && typeof HTMLMediaElement.prototype.pause === 'function') {
      const _originalPause = HTMLMediaElement.prototype.pause;
      window.__mwxOriginalMediaPause = _originalPause;
      HTMLMediaElement.prototype.pause = function() {
        try { this.__myWallpaperAuthorPaused = true; } catch (_) {}
        return _originalPause.apply(this, arguments);
      };
    }
    const attachWallpaperMediaNode = (node) => {
      if (!node || registeredMediaNodes.has(node)) return;
      registeredMediaNodes.add(node);
      try {
        const hostVolume = Number(window.__myWallpaperLastHostVolume);
        if (Number.isFinite(hostVolume)) node.volume = hostVolume;
      } catch (_) {}
      try {
        const hostPlaybackRate = Number(window.__myWallpaperLastHostPlaybackRate);
        if (Number.isFinite(hostPlaybackRate)) node.playbackRate = hostPlaybackRate;
      } catch (_) {}
      if (!loggedFirstMediaNode) {
        loggedFirstMediaNode = true;
        hostLogger.post('first-media-node-found', mediaStateSummary(node));
      }
      postMediaState('media.initial', node);
      node.addEventListener('error', () => {
        const error = node.error;
        const details = error ? `code=${error.code}` : 'unknown';
        hostLogger.post('media.error', `${mediaStateSummary(node)} ${details}`.trim());
        wallpaperRefreshMediaState(node, true);
      });
      node.addEventListener('stalled', () => {
        postMediaState('media.stalled', node);
        wallpaperRefreshMediaState(node);
      });
      node.addEventListener('suspend', () => {
        postMediaState('media.suspend', node);
        wallpaperRefreshMediaState(node);
      });
      node.addEventListener('waiting', () => {
        postMediaState('media.waiting', node);
        wallpaperRefreshMediaState(node);
      });
      node.addEventListener('playing', () => {
        postMediaState('media.playing', node);
        wallpaperRefreshMediaState(node, false);
      });
      node.addEventListener('pause', () => {
        postMediaState('media.pause', node);
        wallpaperRefreshMediaState(node, true);
      });
      node.addEventListener('loadedmetadata', () => {
        postMediaState('media.loadedmetadata', node);
        wallpaperRefreshMediaState(node);
      });
      node.addEventListener('loadeddata', () => {
        postMediaState('media.loadeddata', node);
        wallpaperRefreshMediaState(node);
      });
      node.addEventListener('canplay', () => {
        if (!loggedFirstVideoCanPlay && String(node.tagName || '').toLowerCase() === 'video') {
          loggedFirstVideoCanPlay = true;
          hostLogger.post('first-video-canplay', mediaStateSummary(node));
        }
        postMediaState('media.canplay', node);
        wallpaperRefreshMediaState(node);
      });
      node.addEventListener('canplaythrough', () => {
        postMediaState('media.canplaythrough', node);
        wallpaperRefreshMediaState(node);
      });
      node.addEventListener('ended', () => {
        postMediaState('media.ended', node);
        wallpaperRefreshMediaState(node, true);
      });
      node.addEventListener('emptied', () => {
        postMediaState('media.emptied', node);
        wallpaperRefreshMediaState(node, true);
      });
      node.addEventListener('durationchange', () => wallpaperRefreshMediaState(node));
      node.addEventListener('timeupdate', () => wallpaperDispatchMediaTimeline(node));
      node.addEventListener('play', () => {
        wallpaperMarkPreferredMediaNode(node);
        wallpaperDispatchMediaPlayback(node, false);
      });
      node.addEventListener('playing', () => {
        wallpaperMarkPreferredMediaNode(node);
        wallpaperDispatchMediaPlayback(node, false);
      });
      node.addEventListener('pause', () => wallpaperDispatchMediaPlayback(node, true));
      node.addEventListener('ended', () => wallpaperDispatchMediaPlayback(node, true));
      node.addEventListener('emptied', () => wallpaperRefreshMediaState(node, true));
      node.addEventListener('volumechange', () => wallpaperRefreshMediaState(node));
      node.addEventListener('ratechange', () => wallpaperRefreshMediaState(node));
      node.addEventListener('seeking', () => wallpaperRefreshMediaState(node));
      node.addEventListener('seeked', () => wallpaperRefreshMediaState(node));
      node.addEventListener('progress', () => wallpaperRefreshMediaState(node));
      node.addEventListener('loadstart', () => wallpaperRefreshMediaState(node));
    };
    const attachWallpaperMediaNodesFromRoot = (rootNode) => {
      if (!rootNode) return;
      const rootType = rootNode.nodeType;
      if (rootType === Node.DOCUMENT_FRAGMENT_NODE || rootType === Node.DOCUMENT_NODE) {
        if (rootNode.querySelectorAll) {
          rootNode.querySelectorAll('audio,video').forEach(attachWallpaperMediaNode);
          rootNode.querySelectorAll('iframe').forEach((element) => {
            try {
              const frameDocument = element.contentDocument;
              if (frameDocument) {
                attachWallpaperMediaNodesFromRoot(frameDocument);
              }
            } catch (_) {}
          });
        }
        return;
      }
      if (rootType !== Node.ELEMENT_NODE) return;
      if (rootNode.matches && rootNode.matches('audio,video')) {
        attachWallpaperMediaNode(rootNode);
      }
      if (rootNode.shadowRoot) {
        attachWallpaperMediaNodesFromRoot(rootNode.shadowRoot);
      }
      if (rootNode.tagName && String(rootNode.tagName).toLowerCase() === 'iframe') {
        try {
          const frameDocument = rootNode.contentDocument;
          if (frameDocument) {
            attachWallpaperMediaNodesFromRoot(frameDocument);
          }
        } catch (_) {}
      }
      if (rootNode.querySelectorAll) {
        rootNode.querySelectorAll('audio,video').forEach(attachWallpaperMediaNode);
        rootNode.querySelectorAll('iframe').forEach((element) => {
          try {
            const frameDocument = element.contentDocument;
            if (frameDocument) {
              attachWallpaperMediaNodesFromRoot(frameDocument);
            }
          } catch (_) {}
        });
      }
    };
"""#
