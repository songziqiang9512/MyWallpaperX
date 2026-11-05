import Foundation
import WebKit

extension Scenarios {
    static func audioOutputVolume() async throws {
        let observation = #"""
        (() => {
          const probe = { gains: new WeakMap(), writes: new WeakMap(), edges: [],
            connect: AudioNode.prototype.connect, disconnect: AudioNode.prototype.disconnect,
            volume: window.__mwxNativeMediaVolume,
            destination: Object.getOwnPropertyDescriptor(BaseAudioContext.prototype, 'destination').get,
            Audio: window.Audio, Context: window.AudioContext,
            createSource: AudioContext.prototype.createMediaElementSource,
            createProcessor: AudioContext.prototype.createScriptProcessor,
            resume: AudioContext.prototype.resume, play: HTMLMediaElement.prototype.play };
          const createGain = AudioContext.prototype.createGain;
          AudioContext.prototype.createGain = function(...args) {
            const gain = createGain.apply(this, args);
            if (!probe.gains.has(this)) probe.gains.set(this, gain);
            return gain;
          };
          AudioNode.prototype.connect = function(...args) {
            probe.edges.push({ source: this, target: args[0] });
            return probe.connect.apply(this, args);
          };
          Object.defineProperty(HTMLMediaElement.prototype, 'volume', { ...probe.volume,
            set(value) {
              probe.volume.set.call(this, value);
              probe.writes.set(this, (probe.writes.get(this) || 0) + 1);
            }
          });
          window.__audioOutputProbe = probe;
        })();
        """#
        let documentURL = URL(string: CommandLine.arguments[2])!
        let host = PageHost(html: "", beforeCompatibilityScript: observation, initialVolume: 0, documentURL: documentURL)
        defer { host.close() }
        try await host.open()
        _ = try await host.script(#"""
        window.__audioOutputResult = null;
        (async () => {
          const checks = {}, facts = {}, contexts = [], playing = [], silentSinks = [];
          let outcome;
          const probe = window.__audioOutputProbe;
          const check = (name, value) => { checks[name] = !!value; };
          const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));
          const nativeVolume = media => probe.volume.get.call(media);
          const writes = media => probe.writes.get(media) || 0;
          const mediaFacts = (media, context) => ({ time: media.currentTime, duration: media.duration,
            ready: media.readyState, network: media.networkState, paused: media.paused, muted: media.muted,
            volume: nativeVolume(media), source: media.currentSrc.split(':', 1)[0], error: media.error?.code ?? null,
            context: context.state, contextTime: context.currentTime });
          const errorName = action => { try { action(); return 'none'; } catch (error) { return error.name; } };
          const wait = async condition => {
            for (let i = 0; i < 150; i++) { if (condition()) return true; await sleep(10); }
            return condition();
          };
          const tone = new URL('tone.wav', location.href).href;
          facts.origin = location.origin; facts.audioOrigin = new URL(tone).origin;
          check('media-fixture-has-a-real-same-origin-document', location.protocol === 'http:' && facts.origin === facts.audioOrigin);
          const setVolume = value => window.__myWallpaperSetGlobalVolume(value);
          const makeContext = () => { const context = new AudioContext(); contexts.push(context); return context; };
          const silentlyPull = (context, input) => {
            const sink = probe.createProcessor.call(context, 2048, 1, 1), pull = { callbacks: 0, rms: 0 };
            silentSinks.push(sink);
            sink.onaudioprocess = event => {
              const values = event.inputBuffer.getChannelData(0);
              pull.rms = Math.sqrt(values.reduce((sum, value) => sum + value * value, 0) / values.length);
              pull.callbacks++;
              for (let channel = 0; channel < event.outputBuffer.numberOfChannels; channel++) {
                event.outputBuffer.getChannelData(channel).fill(0);
              }
            };
            probe.connect.call(input, sink);
            probe.connect.call(sink, probe.destination.call(context));
            return pull;
          };
          const silenceAndObserve = context => {
            const gain = probe.gains.get(context), destination = probe.destination.call(context);
            check('native-destination-object-is-preserved', context.destination === destination);
            check('real-context-creates-one-terminal-gain', !!gain);
            if (!gain || context.destination !== destination) throw Error('missing native output boundary before source starts');
            probe.disconnect.call(gain, destination);
            const analyser = context.createAnalyser(); analyser.fftSize = 2048;
            probe.connect.call(gain, analyser);
            return { gain, analyser, pull: silentlyPull(context, analyser) };
          };
          const requireRouting = (source, gain) => {
            const edge = probe.edges.filter(edge => edge.source === source).at(-1);
            if (!edge || edge.target !== gain) throw Error('source bypassed terminal gain; refusing to start audible test source');
          };
          const rms = analyser => {
            const values = new Float32Array(analyser.fftSize); analyser.getFloatTimeDomainData(values);
            return Math.sqrt(values.reduce((sum, value) => sum + value * value, 0) / values.length);
          };
          try {
            setVolume(1);
            const context = makeContext(), output = silenceAndObserve(context);
            const source = context.createConstantSource(); source.offset.value = 0.5;
            check('connect-returns-authored-destination', source.connect(context.destination) === context.destination);
            check('duplicate-connect-retains-authored-destination', source.connect(context.destination) === context.destination);
            requireRouting(source, output.gain);
            await context.resume(); source.start();
            check('native-pcm-unity-output', await wait(() => Math.abs(rms(output.analyser) - 0.5) < 0.025));
            facts.constantUnity = rms(output.analyser);
            setVolume(0.5);
            check('native-pcm-half-output', await wait(() => Math.abs(rms(output.analyser) - 0.25) < 0.02));
            facts.constantHalf = rms(output.analyser);
            setVolume(0);
            check('native-pcm-muted-output', await wait(() => rms(output.analyser) < 0.0001));
            facts.constantMuted = rms(output.analyser);
            setVolume(1);
            check('native-pcm-unmute-restores-output', await wait(() => Math.abs(rms(output.analyser) - 0.5) < 0.025));
            source.stop();

            const node = context.createGain(), parameter = context.createGain().gain;
            check('audio-param-connect-retains-native-return', node.connect(parameter) === undefined);
            check('audio-param-disconnect-retains-overload', node.disconnect(parameter, 0) === undefined);
            for (const argumentsList of [[], [0], [context.destination], [context.destination, 0], [context.destination, 0, 0]]) {
              node.connect(context.destination);
              check('native-disconnect-' + argumentsList.length + '-' + typeof argumentsList[0], node.disconnect(...argumentsList) === undefined);
            }
            check('disconnect-missing-edge-keeps-native-error',
              errorName(() => node.disconnect(context.destination)) === errorName(() => probe.disconnect.call(node, context.destination)));
            check('connect-invalid-input-keeps-native-error',
              errorName(() => node.connect(context.destination, 0, 99)) === errorName(() => probe.connect.call(node, context.destination, 0, 99)));
            check('connect-invalid-this-keeps-native-error',
              errorName(() => AudioNode.prototype.connect.call({}, context.destination)) === errorName(() => probe.connect.call({}, context.destination)));
            const offline = new OfflineAudioContext(1, 128, 8000), offlineSource = offline.createConstantSource();
            offlineSource.offset.value = 0.4;
            check('offline-connect-retains-native-destination', offlineSource.connect(offline.destination) === offline.destination);
            setVolume(0); offlineSource.start();
            const rendered = await offline.startRendering();
            check('offline-rendering-is-not-host-scaled', Math.abs(rendered.getChannelData(0)[64] - 0.4) < 0.001);

            const late = makeContext(), lateOutput = silenceAndObserve(late), lateSource = late.createConstantSource();
            lateSource.connect(late.destination); requireRouting(lateSource, lateOutput.gain);
            await late.resume(); lateSource.start();
            check('muted-late-context-and-node-start-at-zero', lateOutput.gain.gain.value === 0
              && await wait(() => rms(lateOutput.analyser) < 0.0001));
            lateSource.stop();
            class AuthoredContext extends AudioContext {}
            const subclass = new AuthoredContext(); contexts.push(subclass);
            check('audio-context-subclass-keeps-native-prototype', subclass instanceof AuthoredContext && subclass instanceof AudioContext
              && probe.gains.get(subclass)?.gain.value === 0);
            if (window.webkitAudioContext) {
              const alias = new webkitAudioContext(); contexts.push(alias);
              check('webkit-context-alias-initializes-muted-master', probe.gains.get(alias)?.gain.value === 0);
            }

            setVolume(0.5);
            const audio = new Audio(); audio.volume = 0.4;
            check('html-author-volume-and-effective-native-volume-are-distinct', audio.volume === 0.4 && nativeVolume(audio) === 0.2);
            const beforeInvalid = writes(audio), nativeLeaf = document.createElement('audio');
            for (const [name, value] of [['nan', NaN], ['infinity', Infinity], ['negative', -0.1], ['large', 1.1], ['bigint', 1n], ['symbol', Symbol()]]) {
              check('native-volume-error-' + name, errorName(() => { audio.volume = value; })
                === errorName(() => probe.volume.set.call(nativeLeaf, value)));
            }
            check('invalid-volume-does-not-write-real-source', writes(audio) === beforeInvalid && audio.volume === 0.4 && nativeVolume(audio) === 0.2);
            let conversions = 0; const beforeCoercion = writes(audio);
            audio.volume = { valueOf() { conversions++; return 0.6; } };
            check('native-volume-converts-once-and-writes-real-source-once', conversions === 1 && writes(audio) === beforeCoercion + 1
              && audio.volume === 0.6 && nativeVolume(audio) === 0.3);
            const descriptor = Object.getOwnPropertyDescriptor(HTMLMediaElement.prototype, 'volume');
            check('volume-getter-keeps-native-brand-check', errorName(() => descriptor.get.call({})) === errorName(() => probe.volume.get.call({})));
            check('volume-setter-keeps-native-brand-check', errorName(() => descriptor.set.call({}, 0.4)) === errorName(() => probe.volume.set.call({}, 0.4)));
            audio.muted = true; setVolume(0); setVolume(0.5);
            check('host-unmute-keeps-authored-muted', audio.muted && audio.volume === 0.6 && nativeVolume(audio) === 0.3);
            probe.volume.set.call(audio, 0.8);
            check('native-controls-settle-through-volumechange', await wait(() => audio.volume === 0.8 && nativeVolume(audio) === 0.4));
            setVolume(0.5); setVolume(0.5); await sleep(30);
            check('repeated-host-projection-does-not-become-author-volume', audio.volume === 0.8 && nativeVolume(audio) === 0.4);

            const nativeContext = new probe.Context(); contexts.push(nativeContext);
            const nativeAudio = new probe.Audio(tone); playing.push(nativeAudio); nativeAudio.loop = true;
            probe.volume.set.call(nativeAudio, 0.4);
            const nativeAnalyser = nativeContext.createAnalyser();
            const nativePull = silentlyPull(nativeContext, nativeAnalyser);
            const nativeSource = probe.createSource.call(nativeContext, nativeAudio);
            probe.connect.call(nativeSource, nativeAnalyser);
            await probe.resume.call(nativeContext); await probe.play.call(nativeAudio);
            check('native-media-control-produces-real-pcm', await wait(() => rms(nativeAnalyser) > 0.08));
            check('native-media-control-has-active-silent-pull', await wait(() => nativePull.callbacks > 0 && nativePull.rms > 0.08));
            facts.nativeMedia = { rms: rms(nativeAnalyser), pull: { ...nativePull }, ...mediaFacts(nativeAudio, nativeContext) };
            nativeAudio.pause();

            for (const mode of ['factory', 'constructor']) {
              setVolume(1);
              const mixedContext = makeContext(), mixedOutput = silenceAndObserve(mixedContext);
              const media = new Audio(tone); playing.push(media); media.loop = true; media.volume = 0.4;
              let reads = 0;
              const mixedSource = mode === 'factory' ? mixedContext.createMediaElementSource(media)
                : new MediaElementAudioSourceNode(mixedContext, { get mediaElement() { reads++; return media; } });
              mixedSource.connect(mixedContext.destination); requireRouting(mixedSource, mixedOutput.gain);
              const beforeGain = mixedContext.createAnalyser();
              probe.disconnect.call(mixedSource, mixedOutput.gain);
              probe.connect.call(mixedSource, beforeGain); probe.connect.call(beforeGain, mixedOutput.gain);
              await mixedContext.resume(); await media.play();
              check('mixed-' + mode + '-real-pcm-starts', await wait(() => rms(mixedOutput.analyser) > 0.08));
              check('mixed-' + mode + '-has-active-silent-pull', await wait(() => mixedOutput.pull.callbacks > 0 && mixedOutput.pull.rms > 0.08));
              const baseline = rms(mixedOutput.analyser);
              setVolume(0.5);
              check('mixed-' + mode + '-master-applies-once', await wait(() => rms(beforeGain) > 0.08
                && Math.abs(rms(mixedOutput.analyser) / rms(beforeGain) - 0.5) < 0.02)
                && nativeVolume(media) === 0.4 && media.volume === 0.4 && (mode !== 'constructor' || reads === 1));
              facts['mixed-' + mode] = { baseline, half: rms(mixedOutput.analyser), beforeGain: rms(beforeGain),
                pull: { ...mixedOutput.pull }, masterGain: mixedOutput.gain.gain.value, ...mediaFacts(media, mixedContext) };
              setVolume(0); media.volume = 0.7;
              check('mixed-' + mode + '-author-edit-cannot-bypass-muted-master', await wait(() => rms(mixedOutput.analyser) < 0.0001)
                && nativeVolume(media) === 0.7);
              media.pause();
            }
            setVolume(0.5);
            const orphan = new Audio(); orphan.volume = 0.4;
            const rejected = errorName(() => new MediaElementAudioSourceNode({}, { mediaElement: orphan }));
            const rejectedFactory = errorName(() => AudioContext.prototype.createMediaElementSource.call({}, orphan));
            setVolume(0.5);
            check('failed-media-source-construction-does-not-reclassify-element', rejected !== 'none' && rejectedFactory !== 'none'
              && nativeVolume(orphan) === 0.2);

            setVolume(0);
            check('Audio-without-new-keeps-native-call-semantics', errorName(() => Audio()) === errorName(() => Reflect.apply(probe.Audio, window, [])));
            const detached = new Audio(tone); playing.push(detached); detached.loop = true;
            check('detached-Audio-initializes-current-muted-output', nativeVolume(detached) === 0 && !detached.isConnected);
            await detached.play(); detached.volume = 0.9; setVolume(0);
            check('active-detached-media-keeps-current-master', detached.volume === 0.9 && nativeVolume(detached) === 0 && !detached.paused);
            detached.pause(); await sleep(30);
            const pausedWrites = writes(detached); setVolume(0);
            check('paused-detached-media-retires-active-demand', writes(detached) === pausedWrites);
            detached.loop = false; detached.currentTime = 0.98; await detached.play();
            check('detached-media-reaches-real-ended', await wait(() => detached.ended));
            const endedWrites = writes(detached); setVolume(0);
            check('ended-detached-media-retires-active-demand', writes(detached) === endedWrites);
            const autoplay = new Audio(tone); playing.push(autoplay); autoplay.autoplay = true;
            check('late-Audio-autoplay-is-initialized-muted', nativeVolume(autoplay) === 0);
            check('late-Audio-autoplay-really-starts', await wait(() => !autoplay.paused));
            autoplay.pause();

            const frame = document.createElement('iframe'); frame.srcdoc = '<html><body></body></html>'; document.body.appendChild(frame);
            check('same-origin-child-receives-real-bootstrap', await wait(() => typeof frame.contentWindow.__myWallpaperSetGlobalVolume === 'function'));
            const child = frame.contentWindow, childAudio = new child.Audio(); childAudio.volume = 0.4; child.document.body.appendChild(childAudio);
            setVolume(0.5); await sleep(30); child.__myWallpaperSetGlobalVolume(0.5); await sleep(30);
            check('parent-child-repeated-apply-keeps-one-author-coefficient', childAudio.volume === 0.4 && nativeVolume(childAudio) === 0.2);
            setVolume(0); child.__myWallpaperSetGlobalVolume(0);
            frame.srcdoc = '<html><body><script>window.lateAudio = new Audio();<\/script></body></html>';
            check('child-navigation-restores-current-muted-seed', await wait(() => !!frame.contentWindow.lateAudio)
              && nativeVolume(frame.contentWindow.lateAudio) === 0);
            frame.remove();
            let listeners = 0, events = 0;
            window.wallpaperRegisterVolumeListener(() => listeners++);
            window.addEventListener('wallpaper-volume-changed', () => events++);
            setVolume(0); setVolume(0);
            check('same-value-host-notifications-remain-once-per-call', listeners === 2 && events === 2);
            outcome = { checks, facts };
          } catch (error) {
            outcome = { checks, facts, error: String(error && error.stack || error) };
          } finally {
            for (const media of playing) media.pause();
            for (const context of contexts) {
              try { await context.close(); } catch (error) { facts.closeError = String(error); }
            }
          }
          check('native-contexts-close-before-completion-receipt', contexts.every(context => context.state === 'closed') && !facts.closeError);
          window.__audioOutputResult = outcome;
        })(); true;
        """#)
        try await host.waitUntil("window.__audioOutputResult !== null", seconds: 30, label: "real audio output checks")
        let json = try await host.script("JSON.stringify(window.__audioOutputResult)") as! String
        print("web-audio-output-facts: \(json)")
        let value = try JSONSerialization.jsonObject(with: Data(json.utf8)) as! [String: Any]
        expect(value["error"] == nil, "real audio output scenario error: \(json)")
        let checks = value["checks"] as! [String: Bool]
        expect(checks.count >= 40, "real audio output scenario did not reach all boundaries")
        for (name, passed) in checks.sorted(by: { $0.key < $1.key }) { expect(passed, name) }
    }
}
