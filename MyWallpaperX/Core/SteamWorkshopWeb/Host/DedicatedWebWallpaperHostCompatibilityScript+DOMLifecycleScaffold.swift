let webCompatibilityScriptDOMLifecycleScaffold = #"""
    const wallpaperEnsureHostScaffold = (() => {
      const generatedMarker = 'data-mwx-host-generated';
      const ensureWindowTopBarForElement = (element) => {
        if (!element || !element.classList || !element.classList.contains('wrapper')) return;
        if (element.querySelector(':scope > .windowTopBar')) return;
        const topBar = document.createElement('div');
        topBar.className = 'windowTopBar';
        topBar.setAttribute(generatedMarker, 'windowTopBar');
        topBar.style.display = 'none';
        topBar.style.pointerEvents = 'none';
        topBar.style.userSelect = 'none';
        topBar.style.webkitUserSelect = 'none';

        const buttons = document.createElement('div');
        buttons.className = 'windowTopBarButtons';
        buttons.setAttribute(generatedMarker, 'windowTopBarButtons');

        for (let index = 0; index < 3; index += 1) {
          const button = document.createElement('span');
          button.className = 'windowTopBarButton';
          button.setAttribute(generatedMarker, `windowTopBarButton-${index + 1}`);
          buttons.appendChild(button);
        }

        topBar.appendChild(buttons);
        element.insertBefore(topBar, element.firstChild || null);
        const spacer = document.createElement('br');
        spacer.className = 'windowTopBarBR';
        spacer.setAttribute(generatedMarker, 'windowTopBarBR');
        spacer.style.display = 'none';
        element.insertBefore(spacer, topBar.nextSibling || element.firstChild || null);
      };
      const install = (root) => {
        const scope = root && typeof root.querySelectorAll === 'function' ? root : document;
        try {
          if (scope === document && document.body && document.body.classList && document.body.classList.contains('wrapper')) {
            ensureWindowTopBarForElement(document.body);
          }
          Array.from(scope.querySelectorAll('.wrapper')).forEach(ensureWindowTopBarForElement);
        } catch (_) {}
      };
      return { install };
    })();
    const wallpaperEnsureOptionalSliderControls = (() => {
      const generatedMarker = 'data-mwx-host-generated';
      const makeButton = (className) => {
        const button = document.createElement('button');
        button.type = 'button';
        button.className = className;
        button.hidden = true;
        button.setAttribute(generatedMarker, className);
        button.style.display = 'none';
        button.style.pointerEvents = 'none';
        return button;
      };
      const ensureContainer = (container) => {
        if (!container || typeof container.querySelector !== 'function') return;
        if (!container.querySelector('.slider')) return;
        if (!container.querySelector('.prev-button')) {
          container.appendChild(makeButton('prev-button'));
        }
        if (!container.querySelector('.next-button')) {
          container.appendChild(makeButton('next-button'));
        }
      };
      const install = (root) => {
        const scope = root && typeof root.querySelectorAll === 'function' ? root : document;
        try {
          Array.from(scope.querySelectorAll('.slider-container')).forEach(ensureContainer);
        } catch (_) {}
      };
      return { install };
    })();
    // window 级 holder：DOMContentLoaded 同一性补丁已上移到 MediaObservers
    // 段顶部的 document-start 顶层补丁区（F40），wrapped 监听器触发时经它
    // 回调本作用域的安装器；补丁自身不引用 DCL 回调作用域标识符。
    window.__mwxEnsureOptionalSliderControls = wallpaperEnsureOptionalSliderControls;
    const wallpaperCrossOriginFrameFallbacks = (() => {
      const documentPropertyName = '__mwxCrossOriginFallbackDocument';
      const windowPropertyName = '__mwxCrossOriginFallbackWindow';
      const createFallbackDocument = (frame) => {
        try {
          if (frame && frame[documentPropertyName]) {
            return frame[documentPropertyName];
          }
        } catch (_) {}
        let fallbackDocument = null;
        try {
          fallbackDocument = document.implementation.createHTMLDocument('cross-origin iframe');
          fallbackDocument.documentElement.setAttribute('data-mwx-cross-origin-frame', 'true');
        } catch (_) {
          fallbackDocument = document;
        }
        try {
          Object.defineProperty(frame, documentPropertyName, {
            configurable: true,
            enumerable: false,
            value: fallbackDocument
          });
        } catch (_) {}
        return fallbackDocument;
      };
      const frameSourceIsLikelyCrossOrigin = (frame) => {
        try {
          if (!frame || typeof frame.getAttribute !== 'function') return false;
          const rawSource = String(frame.getAttribute('src') || '').trim();
          if (!rawSource || rawSource.toLowerCase() === 'about:blank') return false;
          const frameURL = new URL(rawSource, document.location.href);
          return frameURL.origin !== document.location.origin;
        } catch (_) {
          return false;
        }
      };
      const postAccessDiagnostic = (frame, propertyName) => {
        try {
          const src = frame && typeof frame.getAttribute === 'function'
            ? frame.getAttribute('src')
            : '';
          hostLogger.post('iframe.crossOriginAccess', `${propertyName} fallback ${String(src || '')}`);
        } catch (_) {}
      };
      const createFallbackWindow = (frame, frameWindow) => {
        try {
          if (frame && frame[windowPropertyName]) {
            return frame[windowPropertyName];
          }
        } catch (_) {}
        const fallbackDocument = createFallbackDocument(frame);
        const fallbackWindow = {
          document: fallbackDocument,
          postMessage(message, targetOrigin, transfer) {
            try {
              if (frameWindow && typeof frameWindow.postMessage === 'function') {
                return frameWindow.postMessage(message, targetOrigin, transfer);
              }
            } catch (_) {}
          },
          addEventListener(type, listener, options) {
            try {
              if (frameWindow && typeof frameWindow.addEventListener === 'function') {
                return frameWindow.addEventListener(type, listener, options);
              }
            } catch (_) {}
          },
          removeEventListener(type, listener, options) {
            try {
              if (frameWindow && typeof frameWindow.removeEventListener === 'function') {
                return frameWindow.removeEventListener(type, listener, options);
              }
            } catch (_) {}
          }
        };
        try {
          fallbackWindow.window = fallbackWindow;
          fallbackWindow.self = fallbackWindow;
          fallbackWindow.top = window.top;
          fallbackWindow.parent = window;
        } catch (_) {}
        try {
          Object.defineProperty(frame, windowPropertyName, {
            configurable: true,
            enumerable: false,
            value: fallbackWindow
          });
        } catch (_) {}
        return fallbackWindow;
      };
      const install = () => {
        const prototype = window.HTMLIFrameElement && window.HTMLIFrameElement.prototype;
        if (!prototype || prototype.__mwxCrossOriginAccessPatched === true) return;
        try {
          const contentDocumentDescriptor = Object.getOwnPropertyDescriptor(prototype, 'contentDocument');
          if (contentDocumentDescriptor && typeof contentDocumentDescriptor.get === 'function') {
            Object.defineProperty(prototype, 'contentDocument', {
              configurable: true,
              enumerable: contentDocumentDescriptor.enumerable === true,
              get: function() {
                try {
                  const frameDocument = contentDocumentDescriptor.get.call(this);
                  if (frameDocument) return frameDocument;
                  if (frameSourceIsLikelyCrossOrigin(this)) {
                    postAccessDiagnostic(this, 'contentDocument');
                    return createFallbackDocument(this);
                  }
                  return frameDocument;
                } catch (_) {
                  postAccessDiagnostic(this, 'contentDocument');
                  return createFallbackDocument(this);
                }
              }
            });
          }
        } catch (_) {}
        try {
          const contentWindowDescriptor = Object.getOwnPropertyDescriptor(prototype, 'contentWindow');
          if (contentWindowDescriptor && typeof contentWindowDescriptor.get === 'function') {
            Object.defineProperty(prototype, 'contentWindow', {
              configurable: true,
              enumerable: contentWindowDescriptor.enumerable === true,
              get: function() {
                try {
                  const frameWindow = contentWindowDescriptor.get.call(this);
                  if (frameSourceIsLikelyCrossOrigin(this)) {
                    postAccessDiagnostic(this, 'contentWindow');
                    return createFallbackWindow(this, frameWindow);
                  }
                  if (frameWindow && frameWindow.document) {
                    return frameWindow;
                  }
                  return frameWindow;
                } catch (_) {
                  postAccessDiagnostic(this, 'contentWindow');
                  try {
                    return createFallbackWindow(this, contentWindowDescriptor.get.call(this));
                  } catch (_) {
                    return createFallbackWindow(this, null);
                  }
                }
              }
            });
          }
        } catch (_) {}
        prototype.__mwxCrossOriginAccessPatched = true;
      };
      return { install };
    })();
    wallpaperCrossOriginFrameFallbacks.install();
    try {
      const originalQuerySelector = Element.prototype.querySelector;
      if (typeof originalQuerySelector === 'function' && Element.prototype.__mwxSliderQueryGuardPatched !== true) {
        Element.prototype.querySelector = function(selector) {
          const result = originalQuerySelector.call(this, selector);
          if (
            result == null &&
            (selector === '.prev-button' || selector === '.next-button') &&
            this &&
            this.classList &&
            this.classList.contains('slider-container') &&
            originalQuerySelector.call(this, '.slider')
          ) {
            const className = selector.slice(1);
            const button = document.createElement('button');
            button.type = 'button';
            button.className = className;
            button.hidden = true;
            button.setAttribute('data-mwx-host-generated', className);
            button.style.display = 'none';
            button.style.pointerEvents = 'none';
            this.appendChild(button);
            return button;
          }
          return result;
        };
        Element.prototype.__mwxSliderQueryGuardPatched = true;
      }
    } catch (_) {}
    // DOMContentLoaded addEventListener/removeEventListener 同一性补丁已上移
    // 至 MediaObservers 段顶部的 document-start 顶层补丁区（F40 收尾）：
    // 原位安装发生在宿主自身 DCL 回调体内，页面解析期注册的监听器不走
    // wrapped 路径，removeEventListener 同一性修复实际不可达。
    try {
      document.addEventListener('DOMContentLoaded', () => {
        wallpaperEnsureOptionalSliderControls.install(document);
      }, { once: true, capture: true });
    } catch (_) {}
    const wallpaperScheduleDeferredDOMBootstrap = (() => {
      let scheduled = false;
      return () => {
        if (scheduled) return;
        scheduled = true;
        const bootstrap = () => {
          const installFrameBindings = (element) => {
            if (!element || !element.tagName || String(element.tagName).toLowerCase() !== 'iframe') return;
            try {
              const frameWindow = element.contentWindow;
              if (frameWindow && frameWindow.__mwxLoadListenerInstalled !== true) {
                frameWindow.__mwxLoadListenerInstalled = true;
                frameWindow.addEventListener('load', () => {
                  try {
                    const nextFrameDocument = element.contentDocument;
                    if (nextFrameDocument) {
                      attachWallpaperMediaNodesFromRoot(nextFrameDocument);
                      wallpaperScheduleLifecycleRefresh();
                      wallpaperScheduleInteractiveRegionRefresh();
                    }
                  } catch (_) {}
                });
              }
            } catch (_) {}
          };
          const installShadowObserversFromDocument = () => {
            try {
              // 全量递归扫 shadow root（含嵌套）：解析期（DCL 之前）创建且
              // 宿主不在旧五类白名单（audio,video,iframe,[data-wallpaper],
              // canvas）内的自定义元素 shadow root，attachShadow 包装器的
              // window holder 尚未生效，旧白名单补扫永远接不到——其中的
              // <video> 拿不到媒体观察器/时间轴监听（退化为 8s 轮询粒度）。
              // WeakSet 防环；installWallpaperShadowObserver 自带幂等。
              const visitedRoots = new WeakSet();
              const collectAndInstall = (root) => {
                if (!root || visitedRoots.has(root)) return;
                visitedRoots.add(root);
                try {
                  if (!root.querySelectorAll) return;
                  root.querySelectorAll('*').forEach((element) => {
                    if (element && element.shadowRoot) {
                      installWallpaperShadowObserver(element.shadowRoot);
                      collectAndInstall(element.shadowRoot);
                    }
                  });
                } catch (_) {}
              };
              Array.from(document.querySelectorAll('audio,video,iframe,[data-wallpaper],canvas')).forEach((element) => {
                installFrameBindings(element);
              });
              collectAndInstall(document);
            } catch (_) {}
          };
          installShadowObserversFromDocument();
          wallpaperEnsureHostScaffold.install(document);
          wallpaperEnsureOptionalSliderControls.install(document);
          wallpaperRefreshMediaState();
          wallpaperScheduleInteractiveRegionRefresh();
        };
        if (typeof window.requestIdleCallback === 'function') {
          window.requestIdleCallback(bootstrap, { timeout: 1500 });
        } else {
          window.setTimeout(bootstrap, 1200);
        }
      };
    })();
"""#
