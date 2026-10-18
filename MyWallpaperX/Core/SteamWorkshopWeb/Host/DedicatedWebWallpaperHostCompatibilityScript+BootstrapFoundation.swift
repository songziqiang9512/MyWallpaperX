let webCompatibilityScriptBootstrapFoundation = #"""
  const audioStreams = [];
  const audioListeners = [];
  const failedAudioListeners = new WeakSet();
  let hasLoggedAudioSpectrumDelivery = false;
  let hasLoggedAudioSpectrumChange = false;
  let firstDeliveredAudioSpectrum = [];
  const volumeListeners = [];
  const mediaStatusListeners = [];
  const mediaPropertiesListeners = [];
  const mediaThumbnailListeners = [];
  const mediaTimelineListeners = [];
  const mediaPlaybackListeners = [];
  const playbackStateListeners = [];
  const audioContextInstances = new Set();
  const randomFileRequestTimeoutMS = 8000;
  const mediaPlaybackConstants = {
    PLAYBACK_STOPPED: 0,
    PLAYBACK_PLAYING: 1,
    PLAYBACK_PAUSED: 2
  };
  window.__myWallpaperIsMediaPlayAbortError = function(error) {
    const name = String((error && error.name) || '');
    const message = String((error && error.message) || error || '').toLowerCase();
    return name === 'AbortError' ||
      message.includes('operation was aborted') ||
      message.includes('interrupted by a call to pause') ||
      message.includes('interrupted by a new load request');
  };
  window.__myWallpaperIsOptionalAudioPlayError = function(error, node) {
    try {
      const tagName = String((node && node.tagName) || '').toLowerCase();
      if (tagName !== 'audio') return false;
      const name = String((error && error.name) || '');
      const message = String((error && error.message) || error || '').toLowerCase();
      const code = node && node.error ? Number(node.error.code || 0) : 0;
      return name === 'NotSupportedError' ||
        code === 4 ||
        message.includes('operation is not supported') ||
        message.includes('not supported');
    } catch (_) {
      return false;
    }
  };
  window.__myWallpaperWrapMediaPlayPromise = function(playResult, node) {
    if (!playResult || typeof playResult.catch !== 'function') return playResult;
    return playResult.catch((error) => {
      if (window.__myWallpaperIsMediaPlayAbortError(error)) {
        try {
          const tagName = node && node.tagName ? String(node.tagName).toLowerCase() : 'media';
          const source = node ? String(node.currentSrc || node.src || '').trim() : '';
          hostLogger.post('media.play.aborted', `${tagName} ${source}`.trim());
        } catch (_) {}
        return;
      }
      if (window.__myWallpaperIsOptionalAudioPlayError(error, node)) {
        try {
          const source = node ? String(node.currentSrc || node.src || '').trim() : '';
          hostLogger.post('media.play.unsupported', `audio ${source}`.trim());
        } catch (_) {}
        return;
      }
      throw error;
    });
  };
  // 系统歌曲状态只由宿主快照发布。首份快照之前关闭，不能把页面背景音冒充系统歌曲。
  const wallpaperMediaIntegrationEnabled = () => window.__myWallpaperMediaIntegrationEnabled === true;
  // 本脚本按 frame 注入（见 Host+Surface 的注入面），只有顶层 frame 具有
  // 屏幕级语义：就绪信号与自动交互区域登记都只由顶层 frame 发出。
  const wallpaperIsTopFrame = (() => {
    try { return window.top === window; } catch (_) { return false; }
  })();
  // 同源子 frame window 判定（仍服务指针转发等非推送路径）：按 src 先判同源，
  // 避免读跨源 contentWindow 污染 iframe.crossOriginAccess 诊断面。
  const wallpaperSameOriginFrameWindow = (frame) => {
    try {
      const rawSource = String(frame && frame.getAttribute ? frame.getAttribute('src') || '' : '').trim();
      if (rawSource && rawSource.toLowerCase() !== 'about:blank') {
        const frameURL = new URL(rawSource, document.location.href);
        if (frameURL.origin !== document.location.origin) return null;
      }
    } catch (_) {
      return null;
    }
    try { return frame.contentWindow || null; } catch (_) { return null; }
  };
  // 同源下行中继（退役中）：D5 已把宿主推送（属性/暂停/音量/频谱/目录）与
  // 回包迁到按 frame 定向投递，对应入口的调用点已同批移除；仅剩指针转发的
  // 同源子 frame 坐标换算派发（argsForChild 形式）仍需要它，待指针定向化
  // 时按同一退役条款移除。
  const wallpaperRelayHostPushToChildFrames = (methodName, args, argsForChild) => {
    if (window.__myWallpaperHostPushRelayDepth > 0) return;
    window.__myWallpaperHostPushRelayDepth = 1;
    try {
      document.querySelectorAll('iframe').forEach((frame) => {
        const childWindow = wallpaperSameOriginFrameWindow(frame);
        if (!childWindow) return;
        try {
          const relay = childWindow[methodName];
          if (typeof relay !== 'function') return;
          const childArgs = typeof argsForChild === 'function' ? argsForChild(frame) : args;
          if (!Array.isArray(childArgs)) return;
          relay.apply(childWindow, childArgs);
        } catch (_) {}
      });
    } catch (_) {
    } finally {
      window.__myWallpaperHostPushRelayDepth = 0;
    }
  };
  // D5 frame endpoint 登记：每个注入文档在脚本评估期向宿主上报文档 nonce；
  // 宿主校验真实 webView 后经「按 frame 定向 evaluateJavaScript」向本 frame
  // 回发 endpoint token。nonce/token 只做路由相关性与 challenge 续约，不是
  // 任何资源/网络/主 frame 特权的凭据。子导航产生的新文档会再次执行本段。
  try {
    if (!window.__myWallpaperHostFrameDocumentNonce) {
      window.__myWallpaperHostFrameDocumentNonce =
        'mwx-frame-' + Date.now().toString(36) + '-' + Math.random().toString(36).slice(2, 10);
      const helloHandler = window.webkit && window.webkit.messageHandlers
        && window.webkit.messageHandlers.wallpaperHostFrameEndpoint;
      if (helloHandler && typeof helloHandler.postMessage === 'function') {
        helloHandler.postMessage({ type: 'hello', nonce: window.__myWallpaperHostFrameDocumentNonce });
      }
    }
  } catch (_) {}
  // 宿主租约 challenge 的 receiver 侧校验：token 不匹配直接抛错，宿主据错误
  // 撤销该 endpoint（页面伪造/覆盖 token 只会让自己失去续约与推送）。
  window.__myWallpaperHostFrameEndpointChallenge = function(expectedToken) {
    if (window.__myWallpaperHostFrameEndpointToken !== expectedToken) {
      throw new Error('endpoint-token-mismatch');
    }
    // A legacy author can retain the original listener object and mutate/delete
    // callbacks later without touching window again. The existing host lease
    // heartbeat closes that observation gap; no page polling timer is added.
    if (typeof window.__myWallpaperReportMediaDemand === 'function') {
      window.__myWallpaperReportMediaDemand(false);
    }
    return true;
  };
  // 宿主回包可达性（D5 活判据）：主 frame 走宿主默认求值面，恒可达；子 frame
  // hello ack（endpoint token 写回）后定向可达。fetch/XHR 代理路径只在判据为真
  // 时进入宿主代理，否则保持原生请求行为，绝不悬挂在不可达的回包上。
  const wallpaperHostReplyReachable = () => {
    try {
      if (window.top === window) return true;
      return window.__myWallpaperHostFrameEndpointAck === true;
    } catch (_) {
      return false;
    }
  };
  try {
    Object.defineProperty(window, '__mwxHostReplyReachable', {
      configurable: true,
      get: wallpaperHostReplyReachable
    });
  } catch (_) {
    try { window.__mwxHostReplyReachable = wallpaperHostReplyReachable(); } catch (_) {}
  }
  window.wallpaperMediaIntegration = Object.assign(
    {},
    window.wallpaperMediaIntegration || {},
    mediaPlaybackConstants
  );
  window.__myWallpaperMediaState = {
    status: {
      enabled: wallpaperMediaIntegrationEnabled(),
      available: 'false',
      state: mediaPlaybackConstants.PLAYBACK_STOPPED
    },
    properties: {
      title: '',
      artist: '',
      subTitle: '',
      albumTitle: '',
      albumArtist: '',
      genres: '',
      contentType: '',
      position: 0,
      duration: 0
    },
    thumbnail: {
      thumbnail: '',
      primaryColor: '',
      secondaryColor: '',
      tertiaryColor: '',
      textColor: '',
      highContrastColor: ''
    },
    timeline: { position: 0, duration: 0 },
    playback: { state: mediaPlaybackConstants.PLAYBACK_STOPPED }
  };
  window.__myWallpaperDirectoryState = window.__myWallpaperDirectoryState || {};
  window.__myWallpaperLastUserProperties = window.__myWallpaperInitialUserProperties || window.__myWallpaperLastUserProperties || {};
  window.__myWallpaperLastGeneralProperties = window.__myWallpaperInitialGeneralProperties || window.__myWallpaperLastGeneralProperties || {};
  window.wallpaperEngine_paused = !!window.__myWallpaperInitialPaused;
  let wallpaperPropertyListenerValue = window.wallpaperPropertyListener && typeof window.wallpaperPropertyListener === 'object'
    ? window.wallpaperPropertyListener
    : {};
  const resumeAudioContexts = () => {
    const constructors = [window.AudioContext, window.webkitAudioContext].filter(Boolean);
    for (const Ctor of constructors) {
      try {
        if (!Ctor || !Ctor.prototype || typeof Ctor.prototype.resume !== 'function') continue;
        const originalResume = Ctor.prototype.resume;
        if (Ctor.prototype.__mwxResumeWrapped) continue;
        Ctor.prototype.__mwxResumeWrapped = true;
        Ctor.prototype.resume = function(...args) {
          try { audioContextInstances.add(this); } catch (_) {}
          return originalResume.apply(this, args).catch((error) => {
            hostLogger.post('audio.resume.error', error && error.message ? error.message : error);
            throw error;
          });
        };
      } catch (_) {}
    }
  };
  const wrapAudioContextConstructor = (name) => {
    try {
      const OriginalCtor = window[name];
      if (!OriginalCtor || OriginalCtor.__mwxConstructorWrapped) return;
      const WrappedCtor = function(...args) {
        const instance = new OriginalCtor(...args);
        try { audioContextInstances.add(instance); } catch (_) {}
        return instance;
      };
      WrappedCtor.prototype = OriginalCtor.prototype;
      Object.setPrototypeOf(WrappedCtor, OriginalCtor);
      WrappedCtor.__mwxConstructorWrapped = true;
      window[name] = WrappedCtor;
    } catch (_) {}
  };
  const defineVisibilityProperty = (target, name, getter) => {
    if (!target) return false;
    try {
      Object.defineProperty(target, name, {
        configurable: true,
        enumerable: true,
        get: getter
      });
      return true;
    } catch (_) {
      return false;
    }
  };
  const hostLogger = (() => {
    const handler = window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.wallpaperHostLog;
    const lastLogTimes = new Map();
    const noisyTypeIntervals = {
      'console.warn': 2000,
      'console.error': 500,
      'window.error': 500,
      'promise.rejection': 500,
      'resource.error': 2000,
      'resource.ignored': 5000,
      'fetch.error': 5000,
      'fetch.ignored': 5000,
      'xhr.error': 5000,
      'xhr.status': 5000,
      'media.error': 2000,
      'media.waiting': 2000,
      'media.stalled': 2000,
      'media.suspend': 2000,
      'media.playing': 1000,
      'media.pause': 1000,
      'media.loadedmetadata': 1000,
      'media.loadeddata': 1000,
      'media.canplay': 1000,
      'media.canplaythrough': 1000,
      'media.initial': 1000,
      'media.play.unsupported': 5000,
      'media.resume.skipped': 5000,
      'audio.resume.skipped': 5000,
      'host-reply.unsupported': 5000,
      'interactive-regions.subframe-ignored': 5000,
      'loader.pending': 1000,
      'iframe.crossOriginAccess': 5000,
      'backstretch.noop': 1000,
      'pointer.defer': 1000,
      'runtime.randomFile': 1000,
      'directory.access': 2000
    };
    return {
      post(type, message) {
        if (!handler || typeof handler.postMessage !== 'function') return;
        try {
          const normalizedType = String(type || '');
          const normalizedMessage = String(message ?? '').slice(0, 600);
          const interval = noisyTypeIntervals[normalizedType];
          if (interval) {
            const key = `${normalizedType}|${normalizedMessage}`;
            const now = Date.now();
            const lastTime = lastLogTimes.get(key) || 0;
            if ((now - lastTime) < interval) {
              return;
            }
            lastLogTimes.set(key, now);
            if (lastLogTimes.size > 300) {
              const staleBefore = now - 60000;
              for (const [entryKey, entryTime] of lastLogTimes.entries()) {
                if (entryTime < staleBefore) {
                  lastLogTimes.delete(entryKey);
                }
              }
            }
          }
          handler.postMessage({ type: normalizedType, message: normalizedMessage });
        } catch (_) {}
      }
    };
  })();
  resumeAudioContexts();
  wrapAudioContextConstructor('AudioContext');
  wrapAudioContextConstructor('webkitAudioContext');
  window.wallpaperEngine_mouseover = false;
  window.wallpaperEngine_cursor = { x: 0, y: 0, normalizedX: 0, normalizedY: 0, buttons: 0 };
  if (typeof window.updateCircleSize !== 'function') {
    window.updateCircleSize = function() {};
  }
  window.__myWallpaperInteractiveRegionState = {
    lastSignature: '',
    lastAutoRegisterAt: 0
  };
  window.wallpaperRegisterAudioStream = function(audio) {
    if (audio) {
      audioStreams.push(audio);
    }
  };
  window.wallpaperRegisterAudio = window.wallpaperRegisterAudioStream;
  window.wallpaperRegisterAudioListener = function(listener) {
    if (typeof listener !== 'function') return;
    audioListeners.push(listener);
    if (audioListeners.length === 1) { try { window.webkit.messageHandlers.wallpaperHostAudioDemand.postMessage({ active: true }); } catch (_) {} }
    hostLogger.post('audio.listener.registered', `count=${audioListeners.length}`);
  };
  window.wallpaperRegisterVolumeListener = function(listener) {
    if (typeof listener === 'function') {
      volumeListeners.push(listener);
    }
  };
  let wallpaperLastMediaDemand = '';
  const wallpaperLegacyMediaChannels = {
    updateMediaStatus: 'status', updateMediaProperties: 'properties',
    updateMediaThumbnail: 'thumbnail', updateMediaTimeline: 'timeline', updateMediaPlayback: 'playback'
  };
  const wallpaperLegacyMediaHooks = new WeakMap();
  const wallpaperLastLegacyMediaCallbacks = new Map();
  let wallpaperLastLegacyMediaObject = null;
  const wallpaperObserveLegacyMediaObject = (legacy) => {
    if (!legacy || typeof legacy !== 'object') return;
    let hooks = wallpaperLegacyMediaHooks.get(legacy);
    if (!hooks) { hooks = new Map(); wallpaperLegacyMediaHooks.set(legacy, hooks); }
    for (const name of Object.keys(wallpaperLegacyMediaChannels)) {
      try {
        const descriptor = Object.getOwnPropertyDescriptor(legacy, name);
        const installed = hooks.get(name);
        if (descriptor && installed && descriptor.get === installed.get && descriptor.set === installed.set) continue;
        if (descriptor && descriptor.configurable === false) continue;
        // Keep inherited accessors/properties untouched; the lease challenge
        // handles changes which cannot be intercepted on this object safely.
        if (!descriptor && name in legacy) continue;
        const isAccessor = descriptor && ('get' in descriptor || 'set' in descriptor);
        let storedValue = descriptor ? descriptor.value : undefined;
        const get = isAccessor ? descriptor.get : function() { return storedValue; };
        let set;
        if (isAccessor ? descriptor.set : (!descriptor || descriptor.writable !== false)) {
          set = function(value) {
            if (isAccessor) descriptor.set.call(this, value);
            else storedValue = value;
            if (!descriptor) {
              // A formerly absent callback becomes enumerable on its first
              // assignment, as an ordinary author-created property would.
              Object.defineProperty(legacy, name, { configurable: true, enumerable: true, get, set });
            }
            wallpaperRefreshMediaDemand();
          };
        }
        Object.defineProperty(legacy, name, {
          configurable: true, enumerable: descriptor ? descriptor.enumerable : false, get, set
        });
        hooks.set(name, { get, set });
      } catch (_) {}
    }
  };
  const wallpaperRefreshMediaDemand = (force) => {
    const legacy = wallpaperPropertyListenerValue || {};
    wallpaperObserveLegacyMediaObject(legacy);
    const callbacks = new Map(Object.keys(wallpaperLegacyMediaChannels).map((name) => {
      try { return [name, typeof legacy[name] === 'function' ? legacy[name] : null]; }
      catch (_) { return [name, null]; }
    }));
    const needsMedia = mediaPropertiesListeners.length > 0 || mediaThumbnailListeners.length > 0
      || mediaTimelineListeners.length > 0 || mediaPlaybackListeners.length > 0
      || Array.from(callbacks).some(([name, callback]) => name !== 'updateMediaStatus' && callback);
    const active = needsMedia || mediaStatusListeners.length > 0 || !!callbacks.get('updateMediaStatus');
    const newlyRegistered = [];
    for (const [name, callback] of callbacks) {
      if (callback && (wallpaperLastLegacyMediaObject !== legacy || wallpaperLastLegacyMediaCallbacks.get(name) !== callback)) {
        newlyRegistered.push([name, callback]);
      }
      wallpaperLastLegacyMediaCallbacks.set(name, callback);
    }
    wallpaperLastLegacyMediaObject = legacy;
    const token = window.__myWallpaperHostFrameEndpointToken;
    if (token) {
      const signature = token + ':' + active + ':' + needsMedia;
      if (force || signature !== wallpaperLastMediaDemand) {
        try {
          window.webkit.messageHandlers.wallpaperHostFrameEndpoint.postMessage({
            type: 'mediaDemand', nonce: window.__myWallpaperHostFrameDocumentNonce,
            token, active, needsMedia
          });
          wallpaperLastMediaDemand = signature;
        } catch (_) {}
      }
    }
    // A late legacy callback needs the current value even when the provider's
    // track/generation has not changed. Commit identities/demand before invoking
    // author code: a callback can synchronously remove or replace its own object.
    for (const [name, callback] of newlyRegistered) {
      try { callback.call(legacy, window.__myWallpaperMediaState[wallpaperLegacyMediaChannels[name]]); } catch (_) {}
    }
  };
  let wallpaperMediaDemandRefreshQueued = false;
  const wallpaperScheduleMediaDemandRefresh = () => {
    if (wallpaperMediaDemandRefreshQueued) return;
    wallpaperMediaDemandRefreshQueued = true;
    Promise.resolve().then(() => {
      wallpaperMediaDemandRefreshQueued = false;
      wallpaperRefreshMediaDemand();
    });
  };
  window.__myWallpaperReportMediaDemand = (force = true) => wallpaperRefreshMediaDemand(force);
  wallpaperObserveLegacyMediaObject(wallpaperPropertyListenerValue);
  window.addEventListener('pagehide', () => {
    try {
      window.webkit.messageHandlers.wallpaperHostFrameEndpoint.postMessage({
        type: 'goodbye', nonce: window.__myWallpaperHostFrameDocumentNonce,
        token: window.__myWallpaperHostFrameEndpointToken
      });
    } catch (_) {}
  });
  window.addEventListener('pageshow', (event) => {
    if (!event.persisted) return;
    // Back/forward-cache documents keep their JS state but their old host lease
    // was revoked on pagehide. Re-register before reporting listener demand.
    wallpaperLastMediaDemand = '';
    window.__myWallpaperHostFrameEndpointAck = false;
    window.__myWallpaperHostFrameEndpointToken = null;
    try {
      window.webkit.messageHandlers.wallpaperHostFrameEndpoint.postMessage({
        type: 'hello', nonce: window.__myWallpaperHostFrameDocumentNonce
      });
    } catch (_) {}
  });
  window.wallpaperRegisterMediaStatusListener = function(listener) {
    if (typeof listener === 'function') {
      mediaStatusListeners.push(listener);
      wallpaperRefreshMediaDemand();
      try {
        listener(window.__myWallpaperMediaState.status);
      } catch (_) {}
    }
  };
  window.wallpaperRegisterMediaPropertiesListener = function(listener) {
    if (typeof listener === 'function') {
      mediaPropertiesListeners.push(listener);
      wallpaperRefreshMediaDemand();
      try { listener(window.__myWallpaperMediaState.properties); } catch (_) {}
    }
  };
  window.wallpaperRegisterMediaThumbnailListener = function(listener) {
    if (typeof listener === 'function') {
      mediaThumbnailListeners.push(listener);
      wallpaperRefreshMediaDemand();
      const thumbnail = window.__myWallpaperMediaState.thumbnail;
      try { listener(thumbnail); } catch (_) {}
    }
  };
  window.wallpaperRegisterMediaTimelineListener = function(listener) {
    if (typeof listener === 'function') {
      mediaTimelineListeners.push(listener);
      wallpaperRefreshMediaDemand();
      try { listener(window.__myWallpaperMediaState.timeline); } catch (_) {}
    }
  };
  const replayWallpaperPropertyListenerState = function(options) {
    const replayOptions = options || {};
    wallpaperRefreshMediaDemand();
    try {
      // user 属性应用门是 DOMContentLoaded（interactive），不是 window.load：
      // 官方文档明确属性事件在壁纸加载时触发、且要求页面不要用 window.onload
      // 承载 WE 专用代码（"it's unreliable and can lead to Wallpaper Engine
      // missing certain events"）。无关子资源挂起会让 load 永不触发，因此
      // load 只保留为二次重放兜底。
      if (document.readyState !== 'interactive' && document.readyState !== 'complete') {
        if (window.__myWallpaperDeferredPropertyReplayScheduled !== true) {
          window.__myWallpaperDeferredPropertyReplayScheduled = true;
          // DCL 与 load 是同一重放的互斥兜底，不是两次重放：`once` 只保证各自
          // 的监听器被消费，先到者不撤销另一侧，两者都会触发。重复重放会重复
          // 应用暂停状态等一次性状态，因此先到者取走一次性标志并撤销另一侧。
          const replayAfterReady = () => {
            if (window.__myWallpaperDeferredPropertyReplayScheduled !== true) return;
            window.__myWallpaperDeferredPropertyReplayScheduled = false;
            document.removeEventListener('DOMContentLoaded', replayAfterReady);
            window.removeEventListener('load', replayAfterReady);
            replayWallpaperPropertyListenerState(replayOptions);
          };
          document.addEventListener('DOMContentLoaded', replayAfterReady, { once: true });
          window.addEventListener('load', replayAfterReady, { once: true });
        }
        return;
      }
    } catch (_) {}
    if (replayOptions.includeUserProperties === true) {
      try {
        if (typeof window.__myWallpaperApplyProperties === 'function') {
          window.__myWallpaperApplyProperties(window.__myWallpaperLastUserProperties || {});
        } else if (typeof window.wallpaperPropertyListener.applyUserProperties === 'function') {
          window.wallpaperPropertyListener.applyUserProperties(window.__myWallpaperLastUserProperties || {});
        }
      } catch (_) {}
    }
    try {
      if (typeof window.__myWallpaperApplyGeneralProperties === 'function') {
        window.__myWallpaperApplyGeneralProperties(window.__myWallpaperLastGeneralProperties || {});
      } else if (typeof window.wallpaperPropertyListener.applyGeneralProperties === 'function') {
        window.wallpaperPropertyListener.applyGeneralProperties(window.__myWallpaperLastGeneralProperties || {});
      }
    } catch (_) {}
    try {
      if (typeof window.__myWallpaperApplyInitialPausedState === 'function') {
        window.__myWallpaperApplyInitialPausedState(!!window.wallpaperEngine_paused);
      } else if (window.wallpaperEngine_paused === true) {
        if (typeof window.wallpaperPropertyListener.setPaused === 'function') {
          window.wallpaperPropertyListener.setPaused(true);
        }
        if (typeof window.wallpaperPropertyListener.setPlaybackState === 'function') {
          window.wallpaperPropertyListener.setPlaybackState('paused');
        }
      }
    } catch (_) {}
    try {
      if (typeof window.wallpaperPropertyListener.updateMediaStatus === 'function') {
        window.wallpaperPropertyListener.updateMediaStatus(window.__myWallpaperMediaState.status);
      }
    } catch (_) {}
    try {
      if (typeof window.wallpaperPropertyListener.updateMediaProperties === 'function') {
        window.wallpaperPropertyListener.updateMediaProperties(window.__myWallpaperMediaState.properties);
      }
    } catch (_) {}
    try {
      const thumbnail = window.__myWallpaperMediaState.thumbnail;
      if (
        typeof window.wallpaperPropertyListener.updateMediaThumbnail === 'function'
      ) {
        window.wallpaperPropertyListener.updateMediaThumbnail(thumbnail);
      }
    } catch (_) {}
    try {
      if (typeof window.wallpaperPropertyListener.updateMediaTimeline === 'function') {
        window.wallpaperPropertyListener.updateMediaTimeline(window.__myWallpaperMediaState.timeline);
      }
    } catch (_) {}
    try {
      if (typeof window.wallpaperPropertyListener.updateMediaPlayback === 'function') {
        window.wallpaperPropertyListener.updateMediaPlayback(window.__myWallpaperMediaState.playback);
      }
    } catch (_) {}
    try {
      const directoryState = window.__myWallpaperDirectoryState || {};
      if (typeof window.wallpaperPropertyListener.userDirectoryFilesAddedOrChanged === 'function') {
        for (const [propertyName, files] of Object.entries(directoryState)) {
          const safeFiles = Array.isArray(files) ? files.map((value) => String(value || '')) : [];
          if (safeFiles.length > 0) {
            window.wallpaperPropertyListener.userDirectoryFilesAddedOrChanged(propertyName, safeFiles);
          }
        }
      }
    } catch (_) {}
  };
  const scheduleWallpaperPropertyListenerReplay = function() {
    try {
      if (window.__myWallpaperPropertyReplayQueued === true) return;
      window.__myWallpaperPropertyReplayQueued = true;
      window.__myWallpaperRunAfterSettledFrames(() => {
        window.__myWallpaperPropertyReplayQueued = false;
        replayWallpaperPropertyListenerState({ includeUserProperties: true });
      });
    } catch (_) {
      window.__myWallpaperPropertyReplayQueued = false;
      try { replayWallpaperPropertyListenerState({ includeUserProperties: true }); } catch (_) {}
    }
  };
  try {
    Object.defineProperty(window, 'wallpaperPropertyListener', {
      configurable: true,
      enumerable: true,
      get() {
        // Legacy pages may assign/delete a callback on the existing listener
        // object instead of replacing it. Observe after that synchronous write.
        wallpaperScheduleMediaDemandRefresh();
        return wallpaperPropertyListenerValue;
      },
      set(value) {
        if (!value || typeof value !== 'object') return;
        wallpaperPropertyListenerValue = value;
        wallpaperRefreshMediaDemand();
        scheduleWallpaperPropertyListenerReplay();
      }
    });
  } catch (_) {
    window.wallpaperPropertyListener = wallpaperPropertyListenerValue;
  }
  window.wallpaperRegisterPropertyListener = function(listener) {
    if (!listener || typeof listener !== 'object') return;
    window.wallpaperPropertyListener = listener;
    scheduleWallpaperPropertyListenerReplay();
  };
  window.wallpaperSetPlaybackStateListener = function(listener) {
    if (typeof listener === 'function') {
      playbackStateListeners.push(listener);
      try {
        listener(!!window.wallpaperEngine_paused);
      } catch (_) {}
    }
  };
  window.wallpaperRegisterPlaybackListener = window.wallpaperSetPlaybackStateListener;
  window.wallpaperRegisterMediaPlaybackListener = function(listener) {
    if (typeof listener === 'function') {
      mediaPlaybackListeners.push(listener);
      wallpaperRefreshMediaDemand();
      try { listener(window.__myWallpaperMediaState.playback); } catch (_) {}
    }
  };
"""#
