// Page media traversal remains solely for playback controls, independent of system songs.
let webCompatibilityScriptMediaDiscovery = #"""
  const wallpaperMediaNodes = () => {
    const result = [];
    const visitedRoots = new WeakSet();
    const collectFromRoot = (root) => {
      if (!root || visitedRoots.has(root)) return;
      visitedRoots.add(root);
      try {
        if (root.querySelectorAll) {
          root.querySelectorAll('audio,video').forEach((node) => result.push(node));
          root.querySelectorAll('*').forEach((element) => {
            if (element && element.shadowRoot) {
              collectFromRoot(element.shadowRoot);
            }
            if (element && element.tagName && String(element.tagName).toLowerCase() === 'iframe') {
              try {
                const frameDocument = element.contentDocument;
                if (frameDocument) {
                  collectFromRoot(frameDocument);
                }
              } catch (_) {}
            }
          });
        }
      } catch (_) {}
    };
    collectFromRoot(document);
    return result;
  };
  const wallpaperImmediateMediaNodes = () => {
    try {
      return Array.from(document.querySelectorAll('audio,video'));
    } catch (_) {
      return [];
    }
  };
"""#
