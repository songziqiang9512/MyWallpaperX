"""Actual page interaction JS: auto-region projection and hover-style discovery.

Run the production registration and projection functions verbatim in Node; only
DOM geometry and the outbound message sink are controlled. Real WKWebView frame
routing/click forwarding remain covered by the existing compatibility/input gates.
"""
from pathlib import Path
import json
import subprocess
import unittest

from script.tests.test_web_compat_parity import source_block

ROOT = Path(__file__).resolve().parents[2]
HOST = ROOT / 'MyWallpaperX/Core/SteamWorkshopWeb/Host'


class WebInteractiveRegionProjectionTests(unittest.TestCase):
    def test_real_projection_deduplicates_and_skips_subframe_work(self):
        register = source_block((HOST / 'DedicatedWebWallpaperHostCompatibilityScript+HostBridge.swift').read_text(),
                                'window.__myWallpaperRegisterInteractiveRegions = function(payload)')
        mutation = (HOST / 'DedicatedWebWallpaperHostCompatibilityScript+DOMLifecycleMutation.swift').read_text()
        project = source_block(mutation, 'const wallpaperAutoRegisterInteractiveRegions = () =>')
        schedule = source_block(mutation, 'const wallpaperScheduleInteractiveRegionRefresh = (() =>') + ')();'
        lifecycle = source_block(mutation, 'const wallpaperScheduleLifecycleRefresh = (() =>') + ')();'
        script = r'''
const vm = require('node:vm');
const assert = require('node:assert/strict');
function fixture(topFrame, hasRAF = true) {
  const messages = [], frames = [], timers = [];
  let queries = 0, rafCalls = 0, timerCalls = 0, mediaDemand = 0;
  let rect = { left: 100, top: 160, right: 300, bottom: 240, width: 200, height: 80 };
  let draggable = false;
  const element = {
    tagName: 'BUTTON',
    getBoundingClientRect() { return rect; },
    getAttribute(name) { return name === 'draggable' ? String(draggable) : ''; }
  };
  const context = {
    wallpaperIsTopFrame: topFrame, hostLogger: null,
    document: { querySelectorAll() { queries++; return [element]; } },
    innerWidth: 1000, innerHeight: 800,
    getComputedStyle() { return { display: 'block', visibility: 'visible', pointerEvents: 'auto' }; },
    __myWallpaperInteractiveRegionState: { lastSignature: '', lastAutoRegisterAt: 0 },
    webkit: { messageHandlers: { wallpaperHostInteractiveRegions: { postMessage(payload) { messages.push(payload); } } } },
    CustomEvent: class { constructor(name, options) { this.name = name; this.detail = options.detail; } },
    dispatchEvent() {},
    wallpaperRefreshMediaDemand() { mediaDemand++; },
    setTimeout(callback, delay) { timerCalls++; timers.push({callback, delay}); }
  };
  if (hasRAF) context.requestAnimationFrame = callback => { rafCalls++; frames.push(callback); };
  context.window = context;
  vm.createContext(context);
  vm.runInContext(PRODUCTION, context);
  const schedule = () => vm.runInContext('wallpaperScheduleInteractiveRegionRefresh()', context);
  const flush = () => {
    while (frames.length) frames.shift()();
    while (timers.length) {
      const timer = timers.shift(); assert.equal(timer.delay, 16); timer.callback();
    }
  };
  return { context, messages, queries: () => queries,
    frames, timers, schedule, flush, rafCalls: () => rafCalls, timerCalls: () => timerCalls,
    mediaDemand: () => mediaDemand,
    lifecycle: () => vm.runInContext('wallpaperScheduleLifecycleRefresh()', context),
    project: () => { schedule(); flush(); },
    move: () => { rect = { ...rect, left: 100.00005, right: 300.00005 }; },
    drag: () => { draggable = true; }
  };
}
const main = fixture(true);
for (let i = 0; i < 20; i++) main.schedule();
assert.equal(main.frames.length, 1, 'main frame event bursts retain one scheduled projection');
assert.equal(main.queries(), 0, 'main frame projection remains deferred');
main.flush();
assert.equal(main.messages.length, 1);
const initial = JSON.parse(JSON.stringify(main.messages[0].regions[0]));
assert.deepEqual(initial, { id: 'button-default-1', x: 0.1, y: 0.2, width: 0.2, height: 0.1,
  allowsClick: true, allowsDrag: false });
for (let i = 0; i < 20; i++) main.project();
assert.equal(main.messages.length, 1, 'unchanged real geometry does not register repeatedly');
main.move(); main.project();
assert.equal(main.messages.length, 2, 'real sub-rounding geometry changes are retained');
assert.equal(main.messages[1].regions[0].x, 100.00005 / 1000);
main.drag(); main.project();
assert.equal(main.messages.length, 3);
assert.equal(main.messages[2].regions[0].allowsDrag, true, 'drag permission participates in the projection');
main.context.__myWallpaperRegisterInteractiveRegions({ source: 'page-script',
  regions: [{ ...main.messages[2].regions[0], allowsClick: false }] });
assert.equal(main.messages.length, 4);
main.project();
assert.equal(main.messages.length, 5, 'click permission is part of the shared complete signature');
assert.equal(main.messages[4].regions[0].allowsClick, true);
main.project();
assert.equal(main.messages.length, 5);
const child = fixture(false);
for (let i = 0; i < 20; i++) child.project();
assert.equal(child.queries(), 0, 'subframe auto projection exits before the DOM scan');
assert.equal(child.messages.length, 0, 'subframe auto regions have no host consumer');
assert.equal(child.rafCalls(), 0, 'subframe registration creates no empty RAF');
assert.equal(child.timerCalls(), 0);
child.context.__myWallpaperRegisterInteractiveRegions({ source: 'page-script', regions: [initial] });
assert.equal(child.messages.length, 0, 'public subframe registration keeps its existing coordinate boundary');
child.lifecycle(); child.schedule(); child.flush();
assert.equal(child.mediaDemand(), 1, 'actual child-frame media demand still schedules and executes');
assert.equal(child.rafCalls(), 1, 'only the actual media consumer schedules work in a child frame');

const fallback = fixture(true, false);
for (let i = 0; i < 20; i++) fallback.schedule();
assert.equal(fallback.timers.length, 1, 'main frame still coalesces without author RAF');
fallback.flush();
assert.equal(fallback.messages.length, 1);
const childFallback = fixture(false, false);
for (let i = 0; i < 20; i++) childFallback.schedule();
assert.equal(childFallback.timerCalls(), 0, 'subframe registration creates no empty fallback timer');
childFallback.lifecycle(); childFallback.flush();
assert.equal(childFallback.mediaDemand(), 1, 'child media retains the timer fallback');
console.log('web-interactive-region-projection-pass');
'''.replace('PRODUCTION', json.dumps(register + ';\n' + project + ';\n' + schedule + '\n' + lifecycle))
        result = subprocess.run(['node', '-e', script], capture_output=True, text=True, timeout=15)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn('web-interactive-region-projection-pass', result.stdout)


    def test_real_hover_cssom_avoids_duplicate_fetch_and_finds_late_rules(self):
        pointer = (HOST / 'DedicatedWebWallpaperHostCompatibilityScript+InteractionAndRuntimePointer.swift').read_text()
        discover = pointer[pointer.index('  window.__myWallpaperEnsureSyntheticHoverStyles ='):
                           pointer.index('  window.__myWallpaperSetSyntheticHoverChain =')]
        script = r"""
const vm = require('node:vm'), assert = require('node:assert/strict');
function page(styleSheets, links, responseText) {
  const styles = [], fetches = [];
  let currentResponse = responseText;
  const context = {
    hostLogger: null,
    document: {
      styleSheets,
      getElementById(id) { return styles.find(style => style.id === id) || null; },
      createElement(name) { assert.equal(name, 'style'); return {}; },
      head: { appendChild(style) { styles.push(style); } },
      querySelectorAll(selector) { assert.equal(selector, 'link[rel~="stylesheet"][href]'); return links; }
    },
    fetch(href) {
      fetches.push(href);
      return Promise.resolve({ ok: true, text: () => Promise.resolve(currentResponse) });
    }
  };
  context.window = context; vm.createContext(context); vm.runInContext(PRODUCTION, context);
  return { context, styles, fetches,
    discover: () => context.__myWallpaperEnsureSyntheticHoverStyles(),
    response: text => { currentResponse = text; },
    settled: () => new Promise(resolve => setImmediate(resolve)) };
}
(async () => {
  const rules = [{ selectorText: 'body', style: { cssText: 'color: red' } }];
  let reads = 0;
  const readable = { get cssRules() { reads++; return rules; } };
  const local = page([readable], [{ href: 'local.css', sheet: readable }], '');
  local.discover(); local.discover();
  assert.equal(local.fetches.length, 0, 'readable CSSOM never refetches the same link');
  assert.equal(local.styles.length, 0);
  rules.push({ selectorText: '.late-choice:hover', style: { cssText: 'opacity: 0.5' } });
  local.discover();
  assert.equal(local.styles.length, 1, 'a prior no-hover result cannot hide later insertRule content');
  assert.match(local.styles[0].textContent, /\.late-choice\.__mwx-hover/);
  const installedReads = reads; local.discover();
  assert.equal(reads, installedReads, 'the installed synthetic style retains its existing fast return');

  const blocked = { get cssRules() { throw new Error('SecurityError'); } };
  const unreadableLink = { href: 'cross-origin.css', sheet: blocked };
  const noSheetLink = { href: 'not-ready.css', sheet: null };
  const throwingLink = { href: 'throwing-sheet.css', get sheet() { throw new Error('unavailable'); } };
  const mixed = page([readable, blocked], [
    { href: 'already-readable.css', sheet: readable }, unreadableLink, noSheetLink, throwingLink
  ], '.remote-choice:hover { visibility: visible; }');
  // Use an empty readable sheet so successful local hover discovery cannot
  // legitimately bypass the fallback branch being exercised here.
  rules.length = 0;
  mixed.discover(); mixed.discover();
  assert.deepEqual(mixed.fetches, ['cross-origin.css', 'not-ready.css', 'throwing-sheet.css'],
    'only unreadable/missing sheets fetch, and the existing in-flight flag coalesces repeats');
  await mixed.settled();
  assert.equal(mixed.styles.length, 1);
  assert.match(mixed.styles[0].textContent, /\.remote-choice\.__mwx-hover/);

  const retry = page([blocked], [unreadableLink], 'body { color: blue; }');
  retry.discover(); await retry.settled();
  assert.equal(retry.styles.length, 0);
  retry.response('.fetched-later:hover { display: block; }');
  retry.discover(); await retry.settled();
  assert.equal(retry.fetches.length, 2, 'no-hover fallback result is not cached permanently');
  assert.equal(retry.styles.length, 1);

  let delayedRules = null;
  const delayedSheet = { get cssRules() { return delayedRules; } };
  const delayed = page([delayedSheet], [{ href: 'late-load.css', sheet: delayedSheet }], '');
  delayed.discover(); await delayed.settled();
  assert.equal(delayed.fetches.length, 1, 'unavailable rule list still has the original fetch fallback');
  delayedRules = [{ selectorText: '.loaded-later:hover', style: { cssText: 'display: flex' } }];
  delayed.discover();
  assert.equal(delayed.styles.length, 1, 'late stylesheet load is rescanned without a global CSSOM hook');
  assert.equal(delayed.fetches.length, 1);
  console.log('web-hover-cssom-discovery-pass');
})().catch(error => { console.error(error); process.exitCode = 1; });
""".replace('PRODUCTION', json.dumps(discover))
        result = subprocess.run(['node', '-e', script], capture_output=True, text=True, timeout=15)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn('web-hover-cssom-discovery-pass', result.stdout)



if __name__ == '__main__':
    unittest.main()
