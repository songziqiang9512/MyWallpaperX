//
//  DedicatedWebWallpaperHostCompatibilityScript+BootstrapPlugins.swift
//  MyWallpaperX
//

let webCompatibilityScriptBootstrapPlugins = #"""
  const loadedPluginNames = new Set();
  const pluginListeners = [];
  const myWallpaperBackstretchCommands = new Set(['destroy', 'pause', 'resume', 'next', 'prev', 'show']);
  const myWallpaperNormalizeBackstretchCommand = (value) => {
    if (typeof value !== 'string') return '';
    const command = value.trim();
    return myWallpaperBackstretchCommands.has(command) ? command : '';
  };
  const myWallpaperCopyFunctionProperties = (source, target) => {
    try {
      for (const propertyName of Object.getOwnPropertyNames(source)) {
        if (propertyName === 'length' || propertyName === 'name' || propertyName === 'prototype') continue;
        try {
          const descriptor = Object.getOwnPropertyDescriptor(source, propertyName);
          if (descriptor) Object.defineProperty(target, propertyName, descriptor);
        } catch (_) {}
      }
    } catch (_) {}
  };
  const myWallpaperHasBackstretchInstance = ($, element) => {
    try {
      return !!($(element).data('backstretch'));
    } catch (_) {
      return false;
    }
  };
  const myWallpaperLogBackstretchNoop = (command, scope) => {
    try {
      hostLogger?.post('backstretch.noop', `${scope} ${command} before init`);
    } catch (_) {}
  };
  const myWallpaperWrapBackstretchMethod = ($, original) => {
    if (typeof original !== 'function') return original;
    if (original.__mwxBackstretchMethodWrapped === true) return original;
    const wrapped = function(commandValue, ...args) {
      const command = myWallpaperNormalizeBackstretchCommand(commandValue);
      if (!command) {
        return original.apply(this, [commandValue, ...args]);
      }
      const elementsWithInstance = [];
      try {
        this.each(function() {
          if (myWallpaperHasBackstretchInstance($, this)) {
            elementsWithInstance.push(this);
          }
        });
      } catch (_) {}
      if (elementsWithInstance.length === 0) {
        myWallpaperLogBackstretchNoop(command, 'method');
        return this;
      }
      if (Number(this && this.length) === elementsWithInstance.length) {
        return original.apply(this, [commandValue, ...args]);
      }
      try {
        original.apply($(elementsWithInstance), [commandValue, ...args]);
      } catch (_) {}
      return this;
    };
    myWallpaperCopyFunctionProperties(original, wrapped);
    try { wrapped.__mwxBackstretchMethodWrapped = true; } catch (_) {}
    return wrapped;
  };
  const myWallpaperWrapBackstretchStatic = ($, original) => {
    if (typeof original !== 'function') return original;
    if (original.__mwxBackstretchStaticWrapped === true) return original;
    const wrapped = function(commandValue, ...args) {
      const command = myWallpaperNormalizeBackstretchCommand(commandValue);
      if (command) {
        try {
          const body = $('body');
          if (!body || !body.length || !body.data('backstretch')) {
            myWallpaperLogBackstretchNoop(command, 'static');
            return undefined;
          }
        } catch (_) {
          myWallpaperLogBackstretchNoop(command, 'static');
          return undefined;
        }
      }
      return original.apply(this, [commandValue, ...args]);
    };
    myWallpaperCopyFunctionProperties(original, wrapped);
    try { wrapped.__mwxBackstretchStaticWrapped = true; } catch (_) {}
    return wrapped;
  };
  const myWallpaperInstallBackstretchSlotHook = ($, target, propertyName, wrapValue, stateKey) => {
    if (!target || target[stateKey] === true) return;
    try {
      const existingDescriptor = Object.getOwnPropertyDescriptor(target, propertyName);
      if (existingDescriptor && existingDescriptor.configurable === false) {
        const existingValue = typeof existingDescriptor.get === 'function'
          ? existingDescriptor.get.call(target)
          : existingDescriptor.value;
        const wrappedValue = wrapValue(existingValue);
        if (typeof wrappedValue === 'function' && wrappedValue !== existingValue && existingDescriptor.writable !== false) {
          target[propertyName] = wrappedValue;
        }
        return;
      }
      let storedValue = wrapValue(target[propertyName]);
      Object.defineProperty(target, propertyName, {
        configurable: true,
        enumerable: existingDescriptor ? existingDescriptor.enumerable === true : true,
        get() {
          return storedValue;
        },
        set(nextValue) {
          storedValue = wrapValue(nextValue);
        }
      });
      Object.defineProperty(target, stateKey, {
        configurable: true,
        enumerable: false,
        value: true
      });
    } catch (_) {}
  };
  const myWallpaperInstallBackstretchCompat = ($) => {
    try {
      if (!$ || !$.fn) return;
      myWallpaperInstallBackstretchSlotHook(
        $,
        $.fn,
        'backstretch',
        (value) => myWallpaperWrapBackstretchMethod($, value),
        '__mwxBackstretchMethodHooked'
      );
      myWallpaperInstallBackstretchSlotHook(
        $,
        $,
        'backstretch',
        (value) => myWallpaperWrapBackstretchStatic($, value),
        '__mwxBackstretchStaticHooked'
      );
    } catch (_) {}
  };
  const myWallpaperWatchJQueryGlobal = (name) => {
    try {
      const existingDescriptor = Object.getOwnPropertyDescriptor(window, name);
      if (existingDescriptor && existingDescriptor.configurable === false) {
        const existingValue = typeof existingDescriptor.get === 'function'
          ? existingDescriptor.get.call(window)
          : existingDescriptor.value;
        myWallpaperInstallBackstretchCompat(existingValue);
        return;
      }
      const originalGetter = existingDescriptor && typeof existingDescriptor.get === 'function'
        ? existingDescriptor.get.bind(window)
        : null;
      const originalSetter = existingDescriptor && typeof existingDescriptor.set === 'function'
        ? existingDescriptor.set.bind(window)
        : null;
      let storedValue = originalGetter ? originalGetter() : window[name];
      Object.defineProperty(window, name, {
        configurable: true,
        enumerable: existingDescriptor ? existingDescriptor.enumerable === true : true,
        get() {
          return originalGetter ? originalGetter() : storedValue;
        },
        set(nextValue) {
          if (originalSetter) {
            originalSetter(nextValue);
          } else {
            storedValue = nextValue;
          }
          myWallpaperInstallBackstretchCompat(originalGetter ? originalGetter() : nextValue);
        }
      });
      myWallpaperInstallBackstretchCompat(storedValue);
    } catch (_) {
      try { myWallpaperInstallBackstretchCompat(window[name]); } catch (_) {}
    }
  };
  myWallpaperWatchJQueryGlobal('jQuery');
  myWallpaperWatchJQueryGlobal('$');
  const wallpaperPluginStub = {
    supported: false,
    version: '0',
    isAvailable: () => false
  };
  const wallpaperCueStub = {
    supported: false,
    version: '0',
    isAvailable: () => false,
    getDeviceCount(callback) {
      try { if (typeof callback === 'function') callback(0); } catch (_) {}
      return 0;
    },
    getDeviceInfo(deviceIndex, callback) {
      const payload = {
        id: Number(deviceIndex || 0),
        index: Number(deviceIndex || 0),
        type: 'stub',
        model: 'unsupported',
        serial: '',
        ledCount: 0,
        leds: []
      };
      try {
        if (typeof callback === 'function') {
          callback(payload);
        }
      } catch (_) {}
      return payload;
    },
    getLedPositionsByDeviceIndex(deviceIndex, callback) {
      try { if (typeof callback === 'function') callback([]); } catch (_) {}
      return [];
    },
    getLedPositions(callback) {
      try { if (typeof callback === 'function') callback([]); } catch (_) {}
      return [];
    },
    setLedColorsByImageData() { return false; },
    setLedColorsByDeviceIndex() { return false; },
    setAllLedsColorsAsync() { return false; },
    setSync() { return false; }
  };
  window.cue = Object.assign({}, wallpaperCueStub, window.cue || {});
  window.wpPlugins = Object.assign(
    {},
    window.wpPlugins || {},
    {
      led: Object.assign({}, wallpaperPluginStub, window.wpPlugins && window.wpPlugins.led ? window.wpPlugins.led : {}),
      rgb: Object.assign({}, wallpaperPluginStub, window.wpPlugins && window.wpPlugins.rgb ? window.wpPlugins.rgb : {}),
      cue: Object.assign({}, wallpaperPluginStub, window.wpPlugins && window.wpPlugins.cue ? window.wpPlugins.cue : {})
    }
  );
  window.wallpaperPluginListener = window.wallpaperPluginListener || {
    onPluginLoaded() {}
  };
  window.wallpaperRegisterPluginListener = function(listener) {
    if (!listener || typeof listener.onPluginLoaded !== 'function') return;
    pluginListeners.push(listener);
    window.wallpaperPluginListener = listener;
    for (const pluginName of loadedPluginNames) {
      try { listener.onPluginLoaded(pluginName, '1'); } catch (_) {}
    }
  };
  window.__myWallpaperNotifyPluginLoaded = function(pluginName) {
    const safePluginName = String(pluginName || '').trim();
    if (!safePluginName) return;
    const notifyNames = new Set([safePluginName]);
    if (safePluginName === 'led' || safePluginName === 'rgb') {
      notifyNames.add('cue');
    }
    for (const loadedName of notifyNames) {
      loadedPluginNames.add(loadedName);
      if (loadedName === 'cue' || loadedName === 'led' || loadedName === 'rgb') {
        window.wpPlugins[loadedName] = Object.assign({}, wallpaperPluginStub, window.wpPlugins[loadedName] || {}, {
          supported: true,
          version: '1',
          isAvailable: () => true
        });
      }
    }
    const previousCue = window.cue || {};
    const previousCueIsAvailable = typeof previousCue.isAvailable === 'function' ? previousCue.isAvailable.bind(previousCue) : null;
    window.cue = Object.assign({}, wallpaperCueStub, previousCue, {
      supported: notifyNames.has('cue'),
      version: notifyNames.has('cue') ? '1' : String(previousCue.version || '0'),
      isAvailable: () => notifyNames.has('cue') || (previousCueIsAvailable ? previousCueIsAvailable() : false)
    });
    try {
      const allListeners = [];
      if (window.wallpaperPluginListener && typeof window.wallpaperPluginListener.onPluginLoaded === 'function') {
        allListeners.push(window.wallpaperPluginListener);
      }
      for (const listener of pluginListeners) {
        if (listener && typeof listener.onPluginLoaded === 'function' && allListeners.includes(listener) === false) {
          allListeners.push(listener);
        }
      }
      for (const loadedName of notifyNames) {
        for (const listener of allListeners) {
          try { listener.onPluginLoaded(loadedName, '1'); } catch (_) {}
        }
        window.dispatchEvent(new CustomEvent('wallpaper-plugin-loaded', { detail: loadedName }));
      }
    } catch (error) {
      hostLogger?.post('plugin.listener.error', error && error.message ? error.message : error);
    }
  };
  window.wallpaperPropertyListener = window.wallpaperPropertyListener || {
    applyUserProperties() {},
    applyGeneralProperties() {},
    userDirectoryFilesAddedOrChanged() {},
    userDirectoryFilesRemoved() {},
    setPaused() {},
    setPlaybackState() {},
    updateMediaStatus() {},
    updateMediaProperties() {},
    updateMediaThumbnail() {},
    updateMediaTimeline() {},
    updateMediaPlayback() {}
  };
  window.wallpaperApplyUserProperties = function(properties) {
    window.__myWallpaperApplyProperties(properties || {});
  };
  window.wallpaperSetPaused = function(isPaused) {
    window.__myWallpaperSetPaused(!!isPaused);
  };
  window.wallpaperSetVolume = function(value) {
    window.__myWallpaperSetGlobalVolume(value);
  };
"""#
