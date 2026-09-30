let webCompatibilityScriptBootstrapFoundation = #"""
  const audioStreams = [];
  const audioListeners = [];
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
  // 官方语义：media status 的 enabled 表示"用户是否启用媒体集成选项"（宿主
  // 设置），与页面是否存在媒体节点无关；宿主当前没有该开关，缺省恒 true。
  const wallpaperMediaIntegrationEnabled = () => window.__myWallpaperMediaIntegrationEnabled !== false;
  // 本脚本按 frame 注入（见 Host+Surface 的注入面），只有顶层 frame 具有
  // 屏幕级语义：就绪信号与自动交互区域登记都只由顶层 frame 发出。
  const wallpaperIsTopFrame = (() => {
    try { return window.top === window; } catch (_) { return false; }
  })();
  // 宿主 evaluateJavaScript 只送达主 frame。主 frame 收到推送后向直接子
  // frame 调用同名兼容函数，由子 frame 再向下传递；跨源子 frame 取不到
  // contentWindow 属性，只保留其自身注入的 API 面（拿不到运行时推送）。
  // 退役条件：宿主改为按 frame 定向推送（WKWebView frame 定向求值）后，
  // 本中继与各入口的调用点同批移除。
  // 子 frame 可达性判定放在 contentWindow 读取之前：DOMLifecycleScaffold 的
  // contentWindow 补丁对跨源 frame 会记 iframe.crossOriginAccess 诊断并造
  // fallback window，按 src 先判同源可避免中继自己污染该诊断面。
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
  // 宿主回包（网络响应 / 随机文件路径）只经 webView.evaluateJavaScript 送达主
  // frame，中继也只能沿同源父链下行：因此「本 frame 是否收得到宿主回包」等价于
  // 「本 frame 与顶层同源」。用 window.top.document 可访问性判定，可覆盖
  // 「父同源但祖父跨源」的嵌套情形（只看 window.parent 会漏判这一档）。
  // 收不到回包的 frame 不进入只会等超时的代理路径，保持原生请求行为。
  // window.__mwxHostReplyReachable 是同一判据的观测探针（供诊断与回归门读取）。
  const wallpaperHostReplyReachable = (() => {
    try {
      if (window.top === window) return true;
      void window.top.document;
      return true;
    } catch (_) {
      return false;
    }
  })();
  try { window.__mwxHostReplyReachable = wallpaperHostReplyReachable; } catch (_) {}
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
  const wallpaperHasMediaThumbnail = (payload) => (
    payload &&
    typeof payload.thumbnail === 'string' &&
    payload.thumbnail.trim().length > 0
  );
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
  window.wallpaperRegisterMediaStatusListener = function(listener) {
    if (typeof listener === 'function') {
      mediaStatusListeners.push(listener);
      try {
        listener(window.__myWallpaperMediaState.status);
      } catch (_) {}
    }
  };
  window.wallpaperRegisterMediaPropertiesListener = function(listener) {
    if (typeof listener === 'function') {
      mediaPropertiesListeners.push(listener);
      try { listener(window.__myWallpaperMediaState.properties); } catch (_) {}
    }
  };
  window.wallpaperRegisterMediaThumbnailListener = function(listener) {
    if (typeof listener === 'function') {
      mediaThumbnailListeners.push(listener);
      const thumbnail = window.__myWallpaperMediaState.thumbnail;
      if (wallpaperHasMediaThumbnail(thumbnail)) {
        try { listener(thumbnail); } catch (_) {}
      }
    }
  };
  window.wallpaperRegisterMediaTimelineListener = function(listener) {
    if (typeof listener === 'function') {
      mediaTimelineListeners.push(listener);
      try { listener(window.__myWallpaperMediaState.timeline); } catch (_) {}
    }
  };
  const replayWallpaperPropertyListenerState = function(options) {
    const replayOptions = options || {};
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
        wallpaperHasMediaThumbnail(thumbnail) &&
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
        return wallpaperPropertyListenerValue;
      },
      set(value) {
        if (!value || typeof value !== 'object') return;
        wallpaperPropertyListenerValue = value;
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
      try { listener(window.__myWallpaperMediaState.playback); } catch (_) {}
    }
  };
"""#
