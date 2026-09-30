//
//  DedicatedWebWallpaperHostCompatibilityScript+BootstrapResourceRewriting.swift
//  MyWallpaperX
//

let webCompatibilityScriptBootstrapResourceRewriting = #"""
  window.__myWallpaperRewriteLocalFileURL = function(rawValue) {
    const value = String(rawValue || '').trim();
    const normalizedValue = value.toLowerCase();
    if (
      !value ||
      normalizedValue === 'null' ||
      normalizedValue === 'undefined' ||
      normalizedValue === '(null)' ||
      normalizedValue === 'about:blank' ||
      normalizedValue === 'file:///'
    ) {
      return '';
    }
    if (value.startsWith('mwx-local://')) return value;
    if (value.startsWith('/') && !value.startsWith('//')) {
      const normalizedPath = value.replace(/\/+/g, '/');
      if (/^\/(Users|Volumes|private|tmp|var)\//.test(normalizedPath)) {
        const segments = normalizedPath
          .split('/')
          .filter(Boolean)
          .map((segment) => encodeURIComponent(segment));
        return `mwx-local://wallpaper/__absolute__/${segments.join('/')}`;
      }
    }
    if (!normalizedValue.startsWith('file:///')) return value;
    try {
      const parsed = new URL(value);
      const decodedPath = decodeURIComponent(parsed.pathname || '');
      const normalizedPath = decodedPath.startsWith('/') ? decodedPath : `/${decodedPath}`;
      const segments = normalizedPath
        .split('/')
        .filter(Boolean)
        .map((segment) => encodeURIComponent(segment));
      return `mwx-local://wallpaper/__absolute__/${segments.join('/')}`;
    } catch (_) {
      return value;
    }
  };
  const myWallpaperIsMediaOrSourceElement = (node) => {
    if (!node) return false;
    try {
      const tagName = String(node.tagName || '').toLowerCase();
      if (tagName === 'audio' || tagName === 'video' || tagName === 'source') return true;
    } catch (_) {}
    try {
      if (typeof HTMLMediaElement !== 'undefined' && node instanceof HTMLMediaElement) return true;
    } catch (_) {}
    try {
      if (typeof HTMLSourceElement !== 'undefined' && node instanceof HTMLSourceElement) return true;
    } catch (_) {}
    return false;
  };
  window.__myWallpaperIsInvalidMediaSourceValue = function(rawValue) {
    const value = String(rawValue || '').trim();
    const normalizedValue = value.toLowerCase();
    if (
      !value ||
      normalizedValue === 'null' ||
      normalizedValue === 'undefined' ||
      normalizedValue === '(null)' ||
      normalizedValue === 'about:blank' ||
      normalizedValue === 'file:///' ||
      normalizedValue === 'index.html'
    ) {
      return true;
    }
    try {
      const sourceURL = new URL(value, document.location.href);
      const documentURL = new URL(document.location.href);
      const sourceHref = sourceURL.href.toLowerCase();
      const documentHref = documentURL.href.toLowerCase();
      const sourcePath = String(sourceURL.pathname || '').replace(/\/+$/, '').toLowerCase();
      if (sourceHref === documentHref) return true;
      if (
        sourcePath.endsWith('/null') ||
        sourcePath.endsWith('/undefined') ||
        sourcePath.endsWith('/(null)') ||
        sourcePath.endsWith('/about:blank') ||
        sourcePath.endsWith('/index.html')
      ) {
        return true;
      }
    } catch (_) {}
    return false;
  };
  const myWallpaperClearInvalidMediaSource = (node, attributeName, rawValue) => {
    try {
      const normalizedAttributeName = String(attributeName || 'src');
      if (typeof node.removeAttribute === 'function') {
        node.removeAttribute(normalizedAttributeName);
      }
      try { node.__mwxInvalidMediaSource = String(rawValue || ''); } catch (_) {}
      try {
        if (typeof HTMLMediaElement !== 'undefined' && node instanceof HTMLMediaElement && typeof node.load === 'function') {
          node.load();
        }
      } catch (_) {}
      try {
        const parent = node.parentElement;
        if (
          parent &&
          typeof HTMLMediaElement !== 'undefined' &&
          parent instanceof HTMLMediaElement &&
          typeof parent.load === 'function'
        ) {
          parent.load();
        }
      } catch (_) {}
      try {
        const tagName = String(node.tagName || 'media').toLowerCase();
        hostLogger.post('resource.sanitized', `${tagName}.${normalizedAttributeName} skipped invalid media source ${String(rawValue || '')}`);
      } catch (_) {}
    } catch (_) {}
  };
  const rewriteStyleValue = (value) => {
    const normalized = String(value || '');
    if (!normalized || normalized.toLowerCase().includes('file:///') === false) {
      return normalized;
    }
    const rewrittenURLFunctions = normalized.replace(
      /url\(\s*(?:(["'])(.*?)\1|([^)]*))\s*\)/gi,
      (match, quote, quotedValue, unquotedValue) => {
        const rawURL = String(quotedValue !== undefined ? quotedValue : unquotedValue || '').trim();
        if (rawURL.toLowerCase().startsWith('file:///') === false) return match;
        const rewritten = window.__myWallpaperRewriteLocalFileURL(rawURL);
        if (!rewritten) return 'none';
        const outputQuote = quote || '"';
        return `url(${outputQuote}${rewritten}${outputQuote})`;
      }
    );
    return rewrittenURLFunctions.replace(
      /file:\/\/\/[^\s"'()]+/gi,
      (match) => window.__myWallpaperRewriteLocalFileURL(match)
    );
  };
  const patchURLBackedProperty = (prototype, propertyName) => {
    if (!prototype) return;
    try {
      const descriptor = Object.getOwnPropertyDescriptor(prototype, propertyName);
      if (!descriptor || typeof descriptor.set !== 'function' || prototype[`__mwxPatched_${propertyName}`]) return;
      Object.defineProperty(prototype, propertyName, {
        configurable: true,
        enumerable: descriptor.enumerable === true,
        get: descriptor.get ? function() { return descriptor.get.call(this); } : undefined,
        set: function(value) {
          if (
            propertyName === 'src' &&
            myWallpaperIsMediaOrSourceElement(this) &&
            window.__myWallpaperIsInvalidMediaSourceValue(value)
          ) {
            myWallpaperClearInvalidMediaSource(this, propertyName, value);
            return;
          }
          descriptor.set.call(this, window.__myWallpaperRewriteLocalFileURL(value));
        }
      });
      prototype[`__mwxPatched_${propertyName}`] = true;
    } catch (_) {}
  };
  const patchStyleProperty = (propertyName) => {
    try {
      const prototype = window.CSSStyleDeclaration && window.CSSStyleDeclaration.prototype;
      if (!prototype) return;
      if (prototype[`__mwxPatched_${propertyName}`]) return;
      let descriptorOwner = prototype;
      let descriptor = null;
      while (descriptorOwner && !descriptor) {
        descriptor = Object.getOwnPropertyDescriptor(descriptorOwner, propertyName);
        descriptorOwner = Object.getPrototypeOf(descriptorOwner);
      }
      const cssPropertyName = propertyName.replace(/[A-Z]/g, (match) => `-${match.toLowerCase()}`);
      const originalGetPropertyValue = prototype.getPropertyValue;
      const originalSetProperty = prototype.setProperty;
      Object.defineProperty(prototype, propertyName, {
        configurable: true,
        enumerable: descriptor ? descriptor.enumerable === true : true,
        get: descriptor && typeof descriptor.get === 'function'
          ? function() { return descriptor.get.call(this); }
          : function() {
              return typeof originalGetPropertyValue === 'function'
                ? originalGetPropertyValue.call(this, cssPropertyName)
                : '';
            },
        set: function(value) {
          const rewritten = rewriteStyleValue(value);
          if (descriptor && typeof descriptor.set === 'function') {
            descriptor.set.call(this, rewritten);
            return;
          }
          if (typeof originalSetProperty === 'function') {
            originalSetProperty.call(this, cssPropertyName, rewritten, '');
          }
        }
      });
      prototype[`__mwxPatched_${propertyName}`] = true;
    } catch (_) {}
  };
  patchURLBackedProperty(window.HTMLImageElement && window.HTMLImageElement.prototype, 'src');
  patchURLBackedProperty(window.HTMLMediaElement && window.HTMLMediaElement.prototype, 'src');
  patchURLBackedProperty(window.HTMLSourceElement && window.HTMLSourceElement.prototype, 'src');
  patchURLBackedProperty(window.HTMLAnchorElement && window.HTMLAnchorElement.prototype, 'href');
  patchURLBackedProperty(window.HTMLLinkElement && window.HTMLLinkElement.prototype, 'href');
  patchURLBackedProperty(window.HTMLVideoElement && window.HTMLVideoElement.prototype, 'poster');
  patchStyleProperty('background');
  patchStyleProperty('backgroundImage');
  try {
    const originalSetAttribute = Element.prototype.setAttribute;
    if (typeof originalSetAttribute === 'function' && Element.prototype.__mwxSetAttributePatched !== true) {
      Element.prototype.setAttribute = function(name, value) {
        const normalizedName = String(name || '').toLowerCase();
        if (
          normalizedName === 'src' &&
          myWallpaperIsMediaOrSourceElement(this) &&
          window.__myWallpaperIsInvalidMediaSourceValue(value)
        ) {
          myWallpaperClearInvalidMediaSource(this, normalizedName, value);
          return;
        }
        if (['src', 'href', 'poster'].includes(normalizedName)) {
          return originalSetAttribute.call(this, name, window.__myWallpaperRewriteLocalFileURL(value));
        }
        if (normalizedName === 'style') {
          return originalSetAttribute.call(this, name, rewriteStyleValue(value));
        }
        return originalSetAttribute.call(this, name, value);
      };
      Element.prototype.__mwxSetAttributePatched = true;
    }
    if (typeof MutationObserver === 'function' && window.__mwxInlineStyleURLObserverInstalled !== true) {
      const rewriteInlineStyleURLs = (node) => {
        if (!node || typeof node.getAttribute !== 'function') return;
        const currentStyle = node.getAttribute('style');
        if (!currentStyle || currentStyle.toLowerCase().includes('file:///') === false) return;
        const rewrittenStyle = rewriteStyleValue(currentStyle);
        if (rewrittenStyle !== currentStyle) {
          originalSetAttribute.call(node, 'style', rewrittenStyle);
        }
      };
      const styleObserver = new MutationObserver((records) => {
        records.forEach((record) => rewriteInlineStyleURLs(record.target));
      });
      styleObserver.observe(document, {
        attributes: true,
        attributeFilter: ['style'],
        subtree: true
      });
      window.__mwxInlineStyleURLObserverInstalled = true;
    }
  } catch (_) {}
  try {
    const sanitizePlaceholderMediaSources = () => {
      const nodes = Array.from(document.querySelectorAll('audio,video,source,link'));
      nodes.forEach((node) => {
        try {
          const attributesToNormalize = [];
          if (typeof node.getAttribute === 'function') {
            if (node.hasAttribute && node.hasAttribute('src')) {
              attributesToNormalize.push('src');
            }
            if (node.hasAttribute && node.hasAttribute('poster')) {
              attributesToNormalize.push('poster');
            }
          }
          attributesToNormalize.forEach((attributeName) => {
            const current = node.getAttribute(attributeName);
            if (current == null) return;
            if (
              attributeName === 'src' &&
              myWallpaperIsMediaOrSourceElement(node) &&
              window.__myWallpaperIsInvalidMediaSourceValue(current)
            ) {
              myWallpaperClearInvalidMediaSource(node, attributeName, current);
              return;
            }
            const rewritten = window.__myWallpaperRewriteLocalFileURL(current);
            if (rewritten === current) return;
            if (!rewritten) {
              node.removeAttribute(attributeName);
              return;
            }
            if (typeof node.setAttribute === 'function') {
              node.setAttribute(attributeName, rewritten);
            }
          });
        } catch (_) {}
      });
    };
    sanitizePlaceholderMediaSources();
    document.addEventListener('DOMContentLoaded', sanitizePlaceholderMediaSources, { once: true });
  } catch (_) {}
  try {
    const prototype = window.CSSStyleDeclaration && window.CSSStyleDeclaration.prototype;
    const originalSetProperty = prototype && prototype.setProperty;
    if (typeof originalSetProperty === 'function' && prototype.__mwxSetPropertyPatched !== true) {
      prototype.setProperty = function(name, value, priority) {
        return originalSetProperty.call(this, name, rewriteStyleValue(value), priority);
      };
      prototype.__mwxSetPropertyPatched = true;
    }
  } catch (_) {}
  const normalizeLegacyBodyBackgrounds = () => {
    try {
      if (!document.body || !document.body.style) return;
      const currentBackground = String(document.body.style.background || '');
      const currentBackgroundImage = String(document.body.style.backgroundImage || '');
      const normalizedBackground = rewriteStyleValue(currentBackground);
      const normalizedBackgroundImage = rewriteStyleValue(currentBackgroundImage);
      if (normalizedBackground !== currentBackground) {
        document.body.style.background = normalizedBackground;
      }
      if (normalizedBackgroundImage !== currentBackgroundImage) {
        document.body.style.backgroundImage = normalizedBackgroundImage;
      }
    } catch (_) {}
  };
  const installLegacyBackgroundFunctionWrappers = () => {
    try {
      const wrapNamedFunction = (name) => {
        const original = window[name];
        if (typeof original !== 'function' || original.__mwxBackgroundWrapped) {
          return;
        }
        const wrapped = function(...args) {
          const result = original.apply(this, args);
          normalizeLegacyBodyBackgrounds();
          return result;
        };
        wrapped.__mwxBackgroundWrapped = true;
        window[name] = wrapped;
      };
      wrapNamedFunction('shouldShow');
      wrapNamedFunction('changeBackground');
      wrapNamedFunction('TransitionSwith');
    } catch (_) {}
  };
  installLegacyBackgroundFunctionWrappers();
  try { window.addEventListener('DOMContentLoaded', installLegacyBackgroundFunctionWrappers, { once: true }); } catch (_) {}
  try { window.addEventListener('load', installLegacyBackgroundFunctionWrappers, { once: true }); } catch (_) {}
  try { setTimeout(installLegacyBackgroundFunctionWrappers, 0); } catch (_) {}
  try { setTimeout(installLegacyBackgroundFunctionWrappers, 250); } catch (_) {}
  const randomFileCallbacks = new Map();
  const randomFileTimeouts = new Map();
  window.__myWallpaperResolveRandomFile = function(requestID, value) {
    try {
      const normalizedRequestID = String(requestID);
      const callback = randomFileCallbacks.get(normalizedRequestID);
      const timeoutID = randomFileTimeouts.get(normalizedRequestID);
      if (timeoutID) {
        try { window.clearTimeout(timeoutID); } catch (_) {}
        randomFileTimeouts.delete(normalizedRequestID);
      }
      if (typeof callback === 'function') {
        callback(String(value || ''));
      }
      randomFileCallbacks.delete(normalizedRequestID);
    } catch (_) {}
  };
  window.wallpaperRequestRandomFileForProperty = function(propertyName, callback) {
    let requestID = '';
    try {
      requestID = `req_${Date.now()}_${Math.random().toString(36).slice(2)}`;
      if (typeof callback === 'function') {
        randomFileCallbacks.set(requestID, callback);
        const timeoutID = window.setTimeout(() => {
          const pendingCallback = randomFileCallbacks.get(requestID);
          randomFileCallbacks.delete(requestID);
          randomFileTimeouts.delete(requestID);
          if (typeof pendingCallback === 'function') {
            try { pendingCallback(''); } catch (_) {}
          }
        }, randomFileRequestTimeoutMS);
        randomFileTimeouts.set(requestID, timeoutID);
      }
      // 宿主回包（__myWallpaperResolveRandomFile）只送达主 frame，中继也只沿
      // 同源父链下行：与顶层不同源的 frame 拿不到回包，直接走下面的即时回调
      // 分支，避免 8s 空等。
      if (wallpaperHostReplyReachable !== true) {
        hostLogger.post('host-reply.unsupported', `randomFile ${String(propertyName || 'unknown')}`);
      }
      const handler = wallpaperHostReplyReachable === true
        ? window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.wallpaperHostRandomFile
        : null;
      if (handler && typeof handler.postMessage === 'function') {
        handler.postMessage({
          requestID,
          propertyName: String(propertyName || '')
        });
      } else if (typeof callback === 'function') {
        randomFileCallbacks.delete(requestID);
        const timeoutID = randomFileTimeouts.get(requestID);
        if (timeoutID) {
          try { window.clearTimeout(timeoutID); } catch (_) {}
          randomFileTimeouts.delete(requestID);
        }
        callback('');
      }
      hostLogger.post('runtime.randomFile', String(propertyName || 'unknown'));
    } catch (_) {
      if (requestID) {
        randomFileCallbacks.delete(requestID);
        const timeoutID = randomFileTimeouts.get(requestID);
        if (timeoutID) {
          try { window.clearTimeout(timeoutID); } catch (_) {}
          randomFileTimeouts.delete(requestID);
        }
      }
      if (typeof callback === 'function') {
        callback('');
      }
    }
  };
  const updateCursorState = (event) => {
    try {
      const width = Math.max(window.innerWidth || 0, 1);
      const height = Math.max(window.innerHeight || 0, 1);
      const x = Number(event && typeof event.clientX === 'number' ? event.clientX : 0);
      const y = Number(event && typeof event.clientY === 'number' ? event.clientY : 0);
      window.wallpaperEngine_cursor = {
        x,
        y,
        normalizedX: x / width,
        normalizedY: y / height,
        buttons: Number(event && typeof event.buttons === 'number' ? event.buttons : 0)
      };
      window.wallpaperEngine_mouseover = true;
    } catch (_) {}
  };
"""#
