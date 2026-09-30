let webCompatibilityScriptInteractionAndRuntimeLogging = #"""
  const serializedConsoleArgs = (args) => args.map(arg => {
    if (typeof arg === 'string') return arg;
    if (arg && typeof arg === 'object') {
      const message = typeof arg.message === 'string' ? arg.message : '';
      const stack = typeof arg.stack === 'string' ? arg.stack : '';
      if (message || stack) {
        return [message, stack].filter(Boolean).join(' ');
      }
    }
    try { return JSON.stringify(arg); } catch (_) { return String(arg); }
  }).join(' ');
  const isTransientLoaderReferenceError = (message) => {
    const normalized = String(message || '').toLowerCase();
    return normalized.includes("can't find variable:") &&
      normalized.includes('setupdate@') &&
      normalized.includes('/js/loader.js') &&
      (
        normalized.includes("can't find variable: weather") ||
        normalized.includes("can't find variable: date") ||
        normalized.includes("can't find variable: note")
      );
  };
  const isLocalStylesheetLink = (target, source) => {
    try {
      const tagName = String(target && target.tagName ? target.tagName : '').toUpperCase();
      if (tagName !== 'LINK') return false;
      const rel = String(target.getAttribute ? target.getAttribute('rel') || '' : '').toLowerCase();
      if (!rel.split(/\s+/).includes('stylesheet')) return false;
      if (!target.sheet) return false;
      const sourceURL = new URL(String(source || ''), document.location.href);
      const documentURL = new URL(document.location.href);
      return sourceURL.protocol === 'mwx-local:' ||
        sourceURL.origin === documentURL.origin;
    } catch (_) {
      return false;
    }
  };
  const wrapConsole = (name) => {
    const original = console[name];
    console[name] = function(...args) {
      try {
        const message = serializedConsoleArgs(args);
        hostLogger.post(
          name === 'error' && isTransientLoaderReferenceError(message) ? 'loader.pending' : `console.${name}`,
          message
        );
      } catch (_) {}
      if (typeof original === 'function') {
        return original.apply(this, args);
      }
    };
  };
  ['warn', 'error'].forEach(wrapConsole);
  window.addEventListener('error', (event) => {
    const target = event.target;
    if (target && target !== window) {
      const tagName = target.tagName || 'resource';
      const source = target.currentSrc || target.src || target.href || '';
      try {
        const normalizedTagName = String(tagName || '').toUpperCase();
        const sourceURL = source ? new URL(String(source), document.location.href) : null;
        if (normalizedTagName === 'LINK' && target.hasAttribute &&
            (target.hasAttribute('data-mwx-deferred-stylesheet') ||
             target.hasAttribute('data-mwx-remote-stylesheet-probe'))) {
          return;
        }
        const rawSource =
          target.getAttribute && ['IMG', 'SOURCE', 'AUDIO', 'VIDEO'].includes(normalizedTagName)
            ? String(target.getAttribute('src') || '').trim()
            : '';
        if (normalizedTagName === 'IMG' && (!rawSource || (sourceURL && sourceURL.href === document.location.href))) {
          hostLogger.post('resource.ignored', `${tagName} empty-src`);
          return;
        }
        const invalidMediaSource =
          ['SOURCE', 'AUDIO', 'VIDEO'].includes(normalizedTagName) &&
          (
            !rawSource && !String(source || '').trim() ||
            (typeof window.__myWallpaperIsInvalidMediaSourceValue === 'function' &&
              window.__myWallpaperIsInvalidMediaSourceValue(rawSource || source))
          );
        if (invalidMediaSource) {
          hostLogger.post('resource.ignored', `${tagName} empty-src`);
          return;
        }
      } catch (_) {}
      if (isLocalStylesheetLink(target, source)) {
        hostLogger.post('resource.stylesheet.partial', `${tagName} ${source}`.trim());
        return;
      }
      hostLogger.post('resource.error', `${tagName} ${source}`.trim());
      return;
    }
    hostLogger.post('window.error', `${event.message || 'unknown'} @ ${event.filename || 'inline'}:${event.lineno || 0}:${event.colno || 0}`);
  }, true);
  window.addEventListener('unhandledrejection', (event) => {
    const reason = event.reason && event.reason.stack ? event.reason.stack : event.reason;
    hostLogger.post('promise.rejection', reason || 'unknown');
  });
  const networkRequestHandler = window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.wallpaperHostNetworkRequest;
  let networkRequestCounter = 0;
  const base64ToUint8Array = (base64) => {
    const binary = atob(String(base64 || ''));
    const bytes = new Uint8Array(binary.length);
    for (let index = 0; index < binary.length; index++) {
      bytes[index] = binary.charCodeAt(index);
    }
    return bytes;
  };
  const responseHeaderValue = (headers, name) => {
    const normalized = String(name || '').toLowerCase();
    for (const key of Object.keys(headers || {})) {
      if (String(key).toLowerCase() === normalized) {
        return String(headers[key]);
      }
    }
    return '';
  };
  const proxiedResponseBody = (payload) => {
    if (payload && payload.bodyIsBase64 === true) {
      return base64ToUint8Array(payload.body);
    }
    return (payload && payload.body) || '';
  };
  const hostNetworkRequest = (url, method, headers) => new Promise((resolve, reject) => {
    if (!networkRequestHandler || typeof networkRequestHandler.postMessage !== 'function') {
      reject(new Error('network_bridge_unavailable'));
      return;
    }
    let normalizedURL;
    try {
      normalizedURL = new URL(String(url || ''), document.location.href);
    } catch (error) {
      reject(error);
      return;
    }
    if (!['http:', 'https:'].includes(normalizedURL.protocol)) {
      reject(new Error('network_bridge_unsupported_scheme'));
      return;
    }
    const normalizedMethod = String(method || 'GET').toUpperCase();
    if (!['GET', 'HEAD'].includes(normalizedMethod)) {
      reject(new Error('network_bridge_unsupported_method'));
      return;
    }
    const requestID = `network-${Date.now()}-${++networkRequestCounter}`;
    const timeoutID = setTimeout(() => {
      delete window.__myWallpaperNetworkRequests[requestID];
      reject(new Error('network_bridge_timeout'));
    }, 15000);
    window.__myWallpaperNetworkRequests[requestID] = (payload) => {
      clearTimeout(timeoutID);
      if (!payload || payload.ok !== true) {
        reject(new Error((payload && payload.error) || 'network_bridge_failed'));
        return;
      }
      resolve(payload);
    };
    try {
      networkRequestHandler.postMessage({
        requestID,
        url: normalizedURL.href,
        method: normalizedMethod,
        headers: headers || {}
      });
    } catch (error) {
      clearTimeout(timeoutID);
      delete window.__myWallpaperNetworkRequests[requestID];
      reject(error);
    }
  });
  window.__myWallpaperNetworkRequests = window.__myWallpaperNetworkRequests || {};
  window.__myWallpaperResolveNetworkRequest = function(payload) {
    try {
      const requestID = payload && payload.requestID;
      const callback = requestID && window.__myWallpaperNetworkRequests[requestID];
      if (typeof callback !== 'function') return;
      delete window.__myWallpaperNetworkRequests[requestID];
      callback(payload);
    } catch (_) {}
  };
  const canProxyNetworkRequest = (method, url) => {
    try {
      const normalizedURL = new URL(String(url || ''), document.location.href);
      const documentURL = new URL(document.location.href);
      if (normalizedURL.origin === documentURL.origin) return false;
      if (normalizedURL.hostname === '127.0.0.1' || normalizedURL.hostname === 'localhost') return false;
      return ['http:', 'https:'].includes(normalizedURL.protocol) &&
        ['GET', 'HEAD'].includes(String(method || 'GET').toUpperCase());
    } catch (_) {
      return false;
    }
  };
  if (typeof window.fetch === 'function') {
    const originalFetch = window.fetch.bind(window);
    const localCompanionResponse = (resource) => {
      try {
        const rawURL = resource && typeof resource === 'object' && 'url' in resource ? resource.url : resource;
        const url = new URL(String(rawURL || ''), document.location.href);
        const isLocalCompanion =
          (url.hostname === '127.0.0.1' || url.hostname === 'localhost') &&
          url.port === '5000';
        if (!isLocalCompanion) return null;
        const path = url.pathname.replace(/\/+$/, '') || '/';
        if (path === '/usage') {
          return new Response(JSON.stringify([0, 0, -1, 0, 0, 0]), {
            status: 200,
            headers: { 'Content-Type': 'application/json' }
          });
        }
        if (path === '/performance') {
          return new Response(JSON.stringify({ hwinfo: [], psutil: {} }), {
            status: 200,
            headers: { 'Content-Type': 'application/json' }
          });
        }
        if (path === '/notes' || path === '/shortcuts') {
          return new Response(JSON.stringify([]), {
            status: 200,
            headers: { 'Content-Type': 'application/json' }
          });
        }
        if (path === '/logs') {
          return new Response('', {
            status: 200,
            headers: { 'Content-Type': 'text/plain' }
          });
        }
      } catch (_) {}
      return null;
    };
    window.fetch = function(resource, init) {
      const method = String((init && init.method) || (resource && resource.method) || 'GET').toUpperCase();
      const rawURL = resource && typeof resource === 'object' && 'url' in resource ? resource.url : resource;
      const companionResponse = localCompanionResponse(resource);
      if (companionResponse) {
        hostLogger.post('fetch.compat', String(rawURL));
        return Promise.resolve(companionResponse);
      }
      return originalFetch(resource, init).catch(error => {
        try {
          const url = new URL(String(rawURL || ''), document.location.href);
          const localPath = url.pathname.replace(/^\/+/, '');
          if (method === 'HEAD' && localPath === 'performance.layout.user.js') {
            hostLogger.post('fetch.ignored', `${method} ${localPath} optional`);
            throw error;
          }
          if (canProxyNetworkRequest(method, url.href)) {
            return hostNetworkRequest(url.href, method, {}).then(payload => {
              hostLogger.post('fetch.proxy', `${method} ${url.href} status=${payload.status}`);
              const body = method === 'HEAD' ? null : proxiedResponseBody(payload);
              return new Response(body, {
                status: payload.status || 200,
                headers: payload.headers || {}
              });
            }).catch(proxyError => {
              hostLogger.post('fetch.proxy.error', `${method} ${url.href} ${proxyError && proxyError.message ? proxyError.message : proxyError}`);
              throw error;
            });
          }
        } catch (urlError) {
          if (urlError !== error) {
            // Fall through to regular error logging when URL normalization fails.
          } else {
            throw error;
          }
        }
        hostLogger.post('fetch.error', `${String(rawURL)} ${error && error.message ? error.message : error}`);
        throw error;
      });
    };
  }
  const originalOpen = XMLHttpRequest.prototype.open;
  const originalSend = XMLHttpRequest.prototype.send;
  XMLHttpRequest.prototype.open = function(method, url, ...rest) {
    this.__mwx_method = method;
    this.__mwx_url = url;
    this.__mwx_responseHeaders = {};
    this.addEventListener('error', () => {
      if (canProxyNetworkRequest(method, url)) {
        hostLogger.post('xhr.proxy.pending', `${method} ${String(url)}`);
        return;
      }
      hostLogger.post('xhr.error', `${method} ${String(url)}`);
    });
    this.addEventListener('loadend', () => {
      if (this.status >= 400 || this.status === 0) {
        if (this.status === 0 && canProxyNetworkRequest(method, url)) {
          return;
        }
        hostLogger.post('xhr.status', `${method} ${String(url)} status=${this.status}`);
      }
    });
    return originalOpen.call(this, method, url, ...rest);
  };
  const originalGetResponseHeader = XMLHttpRequest.prototype.getResponseHeader;
  XMLHttpRequest.prototype.getResponseHeader = function(name) {
    try {
      if (this.__mwx_proxied === true && this.__mwx_responseHeaders) {
        const target = String(name || '').toLowerCase();
        for (const key of Object.keys(this.__mwx_responseHeaders)) {
          if (key.toLowerCase() === target) {
            return this.__mwx_responseHeaders[key];
          }
        }
        return null;
      }
    } catch (_) {}
    return originalGetResponseHeader.call(this, name);
  };
  const originalGetAllResponseHeaders = XMLHttpRequest.prototype.getAllResponseHeaders;
  XMLHttpRequest.prototype.getAllResponseHeaders = function() {
    try {
      if (this.__mwx_proxied === true && this.__mwx_responseHeaders) {
        return Object.keys(this.__mwx_responseHeaders)
          .map(key => `${key}: ${this.__mwx_responseHeaders[key]}`)
          .join('\r\n');
      }
    } catch (_) {}
    return originalGetAllResponseHeaders.call(this);
  };
  XMLHttpRequest.prototype.send = function(body) {
    const xhr = this;
    const method = String(xhr.__mwx_method || 'GET').toUpperCase();
    const rawURL = xhr.__mwx_url;
    let shouldProxy = false;
    let proxyURL = null;
    try {
      const url = new URL(String(rawURL || ''), document.location.href);
      proxyURL = url.href;
      shouldProxy = canProxyNetworkRequest(method, url.href);
    } catch (_) {}
    if (shouldProxy && networkRequestHandler && typeof networkRequestHandler.postMessage === 'function') {
      xhr.__mwx_proxied = true;
      try { Object.defineProperty(xhr, 'readyState', { configurable: true, get: () => 2 }); } catch (_) {}
      try { xhr.onreadystatechange && xhr.onreadystatechange.call(xhr); } catch (_) {}
      try { xhr.dispatchEvent(new Event('readystatechange')); } catch (_) {}
      hostNetworkRequest(proxyURL, method, {}).then(payload => {
        try {
          xhr.__mwx_responseHeaders = payload.headers || {};
          const responseBytes = proxiedResponseBody(payload);
          const decodeResponseText = () => {
            if (responseBytes instanceof Uint8Array) {
              try { return new TextDecoder('utf-8').decode(responseBytes); } catch (_) { return ''; }
            }
            return String(responseBytes || '');
          };
          const responseType = String(xhr.responseType || '');
          let responseValue;
          if (responseType === 'arraybuffer') {
            responseValue = responseBytes instanceof Uint8Array ? responseBytes.buffer : new ArrayBuffer(0);
          } else if (responseType === 'blob') {
            responseValue = new Blob([responseBytes], { type: responseHeaderValue(payload.headers, 'content-type') });
          } else if (responseType === 'json') {
            try { responseValue = JSON.parse(decodeResponseText()); } catch (_) { responseValue = null; }
          } else {
            responseValue = decodeResponseText();
          }
          Object.defineProperty(xhr, 'readyState', { configurable: true, get: () => 4 });
          Object.defineProperty(xhr, 'status', { configurable: true, get: () => payload.status || 200 });
          Object.defineProperty(xhr, 'statusText', { configurable: true, get: () => String(payload.status || 200) });
          Object.defineProperty(xhr, 'responseText', { configurable: true, get: () => decodeResponseText() });
          Object.defineProperty(xhr, 'response', { configurable: true, get: () => responseValue });
        } catch (_) {}
        try { xhr.onreadystatechange && xhr.onreadystatechange.call(xhr); } catch (_) {}
        try { xhr.onload && xhr.onload.call(xhr, new Event('load')); } catch (_) {}
        try { xhr.onloadend && xhr.onloadend.call(xhr, new Event('loadend')); } catch (_) {}
        try { xhr.dispatchEvent(new Event('readystatechange')); } catch (_) {}
        try { xhr.dispatchEvent(new Event('load')); } catch (_) {}
        try { xhr.dispatchEvent(new Event('loadend')); } catch (_) {}
        hostLogger.post('xhr.proxy', `${method} ${proxyURL} status=${payload.status}`);
      }).catch(error => {
        try {
          Object.defineProperty(xhr, 'readyState', { configurable: true, get: () => 4 });
          Object.defineProperty(xhr, 'status', { configurable: true, get: () => 0 });
        } catch (_) {}
        try { xhr.onerror && xhr.onerror.call(xhr, new Event('error')); } catch (_) {}
        try { xhr.onloadend && xhr.onloadend.call(xhr, new Event('loadend')); } catch (_) {}
        try { xhr.dispatchEvent(new Event('error')); } catch (_) {}
        try { xhr.dispatchEvent(new Event('loadend')); } catch (_) {}
        hostLogger.post('xhr.proxy.error', `${method} ${proxyURL} ${error && error.message ? error.message : error}`);
      });
      return;
    }
    return originalSend.call(this, body);
  };
"""#
