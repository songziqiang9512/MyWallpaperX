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
  // 请求 ID 加 per-frame 随机段：主 frame 与子 frame 的计数器各自从 0 起，
  // 只靠毫秒时间戳会在同一毫秒碰撞，导致回包中继扇出时两个 frame 认领彼此的
  // 响应（随机文件路径已带随机段，不受影响）。
  const networkRequestNonce = Math.random().toString(36).slice(2, 10);
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
  // 代理请求头只回传原生放行的三个名字（与 RuntimeBridge 侧白名单一致）。
  // Authorization 等鉴权头本批不放行（显式产品决策，owner：网络桥接；退役条件：
  // 出现官方行为证据要求跨域携带凭据时单独立项）。Headers 实例 / 二元数组 /
  // 普通对象统一归一化成普通字典再 postMessage，避免直接克隆 Headers 丢字段。
  const PROXIED_REQUEST_HEADER_NAMES = ['accept', 'accept-language', 'content-type'];
  const normalizedProxiedRequestHeaders = (rawHeaders) => {
    const headers = {};
    const assign = (name, value) => {
      if (name === undefined || name === null || value === undefined || value === null) return;
      const normalizedName = String(name).toLowerCase();
      if (!PROXIED_REQUEST_HEADER_NAMES.includes(normalizedName)) return;
      headers[normalizedName] = String(value);
    };
    try {
      if (!rawHeaders) return headers;
      if (typeof rawHeaders.forEach === 'function' && typeof rawHeaders.get === 'function') {
        rawHeaders.forEach((value, name) => assign(name, value));
      } else if (Array.isArray(rawHeaders)) {
        for (const pair of rawHeaders) {
          if (pair && pair.length >= 2) assign(pair[0], pair[1]);
        }
      } else if (typeof rawHeaders === 'object') {
        for (const name of Object.keys(rawHeaders)) assign(name, rawHeaders[name]);
      }
    } catch (_) {}
    return headers;
  };
  // 204/205/304 按规范是无正文状态：用非空 Uint8Array 构造 Response 会抛 TypeError
  // 并落进代理失败分支，从而把真实响应替换成原始 CORS 错误。
  const PROXIED_NULL_BODY_STATUSES = [204, 205, 304];
  const proxiedResponseHasNullBody = (status) => PROXIED_NULL_BODY_STATUSES.includes(Number(status));
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
    const requestID = `network-${Date.now()}-${networkRequestNonce}-${++networkRequestCounter}`;
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
          const proxyCapable = canProxyNetworkRequest(method, url.href);
          if (proxyCapable && wallpaperHostReplyReachable() !== true) {
            // hello 未 ack（回包通道未建立）的 frame 不进入只会等桥超时的代理
            // 路径，保持原生结果（下面按 fetch.error 记录并重抛原生错误）。
            hostLogger.post('host-reply.unsupported', `${method} ${url.href}`);
          } else if (proxyCapable) {
            const proxiedRequestHeaders = normalizedProxiedRequestHeaders(init && init.headers);
            return hostNetworkRequest(url.href, method, proxiedRequestHeaders).then(payload => {
              hostLogger.post('fetch.proxy', `${method} ${url.href} status=${payload.status}`);
              const status = payload.status || 200;
              const body = method === 'HEAD' || proxiedResponseHasNullBody(status)
                ? null
                : proxiedResponseBody(payload);
              const response = new Response(body, {
                status,
                headers: payload.headers || {}
              });
              // 构造出的 Response 没有 url：用原生 HTTPURLResponse.url（已还原成
              // 作者可见 URL）回填 response.url 语义；缺失时退回请求 URL。
              try {
                const responseURL = String(payload.responseURL || url.href);
                Object.defineProperty(response, 'url', { configurable: true, get: () => responseURL });
              } catch (_) {}
              return response;
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
    this.__mwx_requestHeaders = {};
    // 代理路径会在实例上定义 readyState/status/... 访问器（configurable），
    // open() 复用同一对象（XHR 规范允许）再走原生路径时必须摘除，否则
    // 实例属性持续遮蔽原型访问器，页面永远读到上一次代理响应；__mwx_proxied
    // 同理，残留会让 getResponseHeader 走空 __mwx_responseHeaders 而非原生头。
    for (const proxiedKey of ['readyState', 'status', 'statusText', 'responseURL', 'responseText', 'response', '__mwx_proxied']) {
      try { delete this[proxiedKey]; } catch (_) {}
    }
    this.addEventListener('error', () => {
      if (canProxyNetworkRequest(method, url) && wallpaperHostReplyReachable() === true) {
        hostLogger.post('xhr.proxy.pending', `${method} ${String(url)}`);
        return;
      }
      hostLogger.post('xhr.error', `${method} ${String(url)}`);
    });
    this.addEventListener('loadend', () => {
      if (this.status >= 400 || this.status === 0) {
        if (this.status === 0 && canProxyNetworkRequest(method, url) && wallpaperHostReplyReachable() === true) {
          return;
        }
        hostLogger.post('xhr.status', `${method} ${String(url)} status=${this.status}`);
      }
    });
    return originalOpen.call(this, method, url, ...rest);
  };
  // 代理路径下 send 被拦截、真实请求不再发出，但页面显式设置的请求头仍然要
  // 在代理调用里透传（否则 accept / accept-language / content-type 静默丢失）。
  const originalSetRequestHeader = XMLHttpRequest.prototype.setRequestHeader;
  XMLHttpRequest.prototype.setRequestHeader = function(name, value) {
    try {
      if (this.__mwx_requestHeaders && name !== undefined && name !== null) {
        this.__mwx_requestHeaders[String(name)] = String(value);
      }
    } catch (_) {}
    return originalSetRequestHeader.call(this, name, value);
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
      const proxyCapable = canProxyNetworkRequest(method, url.href);
      shouldProxy = proxyCapable && wallpaperHostReplyReachable() === true;
      if (proxyCapable && shouldProxy !== true) {
        // hello 未 ack（回包通道未建立）的 frame 不进入只会等桥超时的代理路径，
        // 保持原生 XHR（否则请求既不发原生也拿不到回包）。
        hostLogger.post('host-reply.unsupported', `${method} ${url.href}`);
      }
    } catch (_) {}
    if (shouldProxy && networkRequestHandler && typeof networkRequestHandler.postMessage === 'function') {
      xhr.__mwx_proxied = true;
      try { Object.defineProperty(xhr, 'readyState', { configurable: true, get: () => 2 }); } catch (_) {}
      try { xhr.onreadystatechange && xhr.onreadystatechange.call(xhr); } catch (_) {}
      try { xhr.dispatchEvent(new Event('readystatechange')); } catch (_) {}
      hostNetworkRequest(proxyURL, method, normalizedProxiedRequestHeaders(xhr.__mwx_requestHeaders)).then(payload => {
        try {
          xhr.__mwx_responseHeaders = payload.headers || {};
          const responseStatus = payload.status || 200;
          // 204/205/304 无正文：与真实 XHR 一致地还原为空响应体。
          const responseBytes = proxiedResponseHasNullBody(responseStatus)
            ? new Uint8Array(0)
            : proxiedResponseBody(payload);
          const responseURL = String(payload.responseURL || proxyURL || '');
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
          Object.defineProperty(xhr, 'status', { configurable: true, get: () => responseStatus });
          Object.defineProperty(xhr, 'statusText', { configurable: true, get: () => String(responseStatus) });
          Object.defineProperty(xhr, 'responseURL', { configurable: true, get: () => responseURL });
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
