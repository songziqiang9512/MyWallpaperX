import Foundation

extension Harness {
    static func vector(_ value: SceneDynamicValue?) -> [Double] {
        guard case let .vector3(x, y, z)? = value else { return [] }
        return [x, y, z]
    }

    static func vector2(_ value: SceneDynamicValue?) -> [Double] {
        guard case let .vector2(x, y)? = value else { return [] }
        return [x, y]
    }

    static func scalar(_ value: SceneDynamicValue?) -> Double {
        guard case let .scalar(number)? = value else { return -1 }
        return number
    }

    static func propertyProgram(
        bindings: [(String, SceneDynamicTarget)]
    ) -> ScenePropertyBindingProgram {
        ScenePropertyBindingProgram(
            definitions: bindings.map {
                .init(target: $0.1, valueType: .scalar, authoredValue: .scalar(0))
            },
            instructions: bindings.map {
                .init(
                    propertyKey: $0.0,
                    path: .init(components: [.key($0.0)]),
                    target: $0.1,
                    valueType: .scalar
                )
            }
        )
    }

    static func unchanged(
        _ state: ScenePropertyLiveUpdateState,
        from before: ScenePropertyLiveUpdateState
    ) -> Bool {
        state.effectiveValues == before.effectiveValues
            && state.userValues == before.userValues
    }

    static func string(_ value: SceneDynamicValue?) -> String {
        guard case let .string(text)? = value else { return "" }
        return text
    }

    static func textBinding(
        source: String,
        value: String,
        wrapperKeys: [String] = ["script", "value"],
        properties: [String: SceneJSONValue] = [:]
    ) -> SceneScriptBindingIR {
        .init(
            source: source,
            owner: .init(
                kind: .object,
                objectIndex: 2,
                objectID: 77,
                effectIndex: nil,
                effectID: nil,
                passIndex: nil,
                passID: nil
            ),
            targetPath: [.key("objects"), .index(2), .key("text")],
            properties: properties,
            authoredValue: .string(value),
            valueType: .string,
            wrapperKeys: wrapperKeys
        )
    }

    static func alphaBinding(
        source: String,
        value: Double,
        properties: [String: SceneJSONValue] = [:],
        wrapperKeys: [String] = ["animation", "script", "value"]
    ) -> SceneScriptBindingIR {
        .init(
            source: source,
            owner: .init(
                kind: .object, objectIndex: 0, objectID: 10,
                effectIndex: nil, effectID: nil, passIndex: nil, passID: nil
            ),
            targetPath: [.key("objects"), .index(0), .key("alpha")],
            properties: properties,
            authoredValue: .number(value),
            valueType: .number,
            wrapperKeys: wrapperKeys
        )
    }

    static func binding(
        key: String,
        source: String,
        value: String,
        properties: [String: SceneJSONValue],
        ownerKind: SceneScriptBindingOwner.Kind = .object,
        objectIndex: Int = 0,
        objectID: Int = 10,
        wrapperKeys: [String]? = nil
    ) -> SceneScriptBindingIR {
        .init(
            source: source,
            owner: .init(
                kind: ownerKind, objectIndex: objectIndex, objectID: objectID,
                effectIndex: nil, effectID: nil, passIndex: nil, passID: nil
            ),
            targetPath: [.key("objects"), .index(objectIndex), .key(key)],
            properties: properties,
            authoredValue: .string(value),
            valueType: .string,
            wrapperKeys: wrapperKeys ?? (properties.isEmpty
                ? ["script", "value"]
                : ["script", "scriptproperties", "value"])
        )
    }

    static func colorBinding(
        source: String,
        value: String = "0.2 0.3 0.4",
        objectIndex: Int = 4,
        objectID: Int = 500,
        properties: [String: SceneJSONValue] = [:]
    ) -> SceneScriptBindingIR {
        .init(
            source: source,
            owner: .init(
                kind: .object, objectIndex: objectIndex, objectID: objectID,
                effectIndex: nil, effectID: nil, passIndex: nil, passID: nil
            ),
            targetPath: [
                .key("objects"), .index(objectIndex), .key("color"),
            ],
            properties: properties,
            authoredValue: .string(value),
            valueType: .string,
            wrapperKeys: properties.isEmpty
                ? ["script", "value"]
                : ["script", "scriptproperties", "value"]
        )
    }

    static func passBinding(
        key: String,
        source: String,
        value: Double,
        wrapperKeys: [String] = ["script", "value"],
        properties: [String: SceneJSONValue] = [:]
    ) -> SceneScriptBindingIR {
        .init(
            source: source,
            owner: .init(
                kind: .pass, objectIndex: 0, objectID: 10,
                effectIndex: 0, effectID: 100, passIndex: 0, passID: 200
            ),
            targetPath: [
                .key("objects"), .index(0), .key("effects"), .index(0),
                .key("passes"), .index(0), .key("constantshadervalues"),
                .key(key),
            ],
            properties: properties,
            authoredValue: .number(value),
            valueType: .number,
            wrapperKeys: wrapperKeys
        )
    }

    static func passVectorBinding(
        key: String = "scale",
        source: String,
        value: String,
        wrapperKeys: [String],
        properties: [String: SceneJSONValue] = [:]
    ) -> SceneScriptBindingIR {
        .init(
            source: source,
            owner: .init(
                kind: .pass, objectIndex: 0, objectID: 10,
                effectIndex: 0, effectID: 100, passIndex: 0, passID: 200
            ),
            targetPath: [
                .key("objects"), .index(0), .key("effects"), .index(0),
                .key("passes"), .index(0), .key("constantshadervalues"),
                .key(key),
            ],
            properties: properties,
            authoredValue: .string(value),
            valueType: .string,
            wrapperKeys: wrapperKeys
        )
    }

    static func particleRateBinding(
        source: String,
        value: Double,
        wrapperKeys: [String] = ["script", "scriptproperties", "value"],
        properties: [String: SceneJSONValue] = [
            "frequency": .number(0), "minvalue": .number(1),
        ]
    ) -> SceneScriptBindingIR {
        .init(
            source: source,
            owner: .init(
                kind: .object, objectIndex: 3, objectID: 139,
                effectIndex: nil, effectID: nil, passIndex: nil, passID: nil
            ),
            targetPath: [
                .key("objects"), .index(3),
                .key("instanceoverride"), .key("rate"),
            ],
            properties: properties,
            authoredValue: .number(value),
            valueType: .number,
            wrapperKeys: wrapperKeys
        )
    }

    static let originSource = """
    'use strict';
    export var scriptProperties = createScriptProperties()
      .addSlider({name:'x',label:'X',value:20,min:0,max:3800,integer:false})
      .addSlider({name:'y',label:'Y',value:2250,min:0,max:3800,integer:false})
      .finish();
    export function update(value) {
      thisLayer.getEffect('history').executeMaterialFunction('clearHistory');
      value.x = scriptProperties.x;
      value.y = scriptProperties.y - 0;
      return value;
    }
    """

    static let angleSource = """
    export function update(value) {
      value.y = 0.15;
      return value;
    }
    """

    static let propertyEventSource = """
    export var scriptProperties = createScriptProperties()
      .addSlider({name:'step',value:1}).finish();
    let applied = 0;
    let initialized = false;
    export function init(value) {
      initialized = true;
      return value;
    }
    export function applyUserProperties(changed) {
      if (!initialized) { throw new Error('properties before init'); }
      if (changed.hasOwnProperty('mode')) {
        applied = scriptProperties.step + engine.userProperties.mode;
      }
    }
    export function update(value) {
      value.x = applied;
      return value;
    }
    """

    static let scaleSource = """
    'use strict';
    export var scriptProperties = createScriptProperties()
      .addSlider({name:'size',label:'Size',value:1.5,min:1,max:3,integer:false})
      .finish();
    export function update(value) {
      if (scriptProperties.size < 0) { throw new Error('vector provider failure'); }
      return scriptProperties.size;
    }
    """

    static let layerSource = """
    export function update(value) {
      const day = 1;
      const destination = thisScene.getLayer(`C${day}`).origin;
      return destination.copy();
    }
    """

    static let layerColorSource = """
    let color = new Vec3(0.2, 0.3, 0.4);
    export function mediaThumbnailChanged(event) {
      color.x = event.primaryColor.x;
      color.y = event.primaryColor.y;
      color.z = event.primaryColor.z;
    }
    export function update(value) { return color.copy(); }
    """

    static let spotColorSource = """
    import * as WEColor from 'WEColor';
    export var scriptProperties = createScriptProperties()
      .addCheckbox({name:'useColor2',value:false}).finish();
    export function update(value) {
      return scriptProperties.useColor2
        ? WEColor.normalizeColor(new Vec3(200, 200, 255))
        : value;
    }
    """

    static let modelTintSource = """
    import * as WEColor from 'WEColor';
    export var scriptProperties = createScriptProperties()
      .addCheckbox({name:'useBlue',value:false}).finish();
    export function update(value) {
      return scriptProperties.useBlue
        ? WEColor.normalizeColor(new Vec3(215, 235, 255))
        : value;
    }
    """

    static let scriptPropertyColorSource = """
    export var scriptProperties = createScriptProperties();
    export function update(value) {
      if (scriptProperties.dynamicTitle) { return value; }
      return new Vec3(scriptProperties.titleColor);
    }
    """

    static let thisLayerColorSource = """
    export function update(value) { return thisLayer.color; }
    """

    static let undefinedColorSource = """
    export function update(value) {}
    """

    static let failingColorSource = """
    let calls = { value: 0 };
    export function update(value) {
      calls.value += 1;
      if (calls.value == 1) { return value.multiply(2); }
      throw new Error('color failure');
    }
    """

    static let animationSource = """
    export function init(value) {
      thisObject.getAnimation().play();
      return value;
    }
    """

    static let mediaAnimationSource = """
    export function mediaThumbnailChanged(event) {
      if (event.hasThumbnail) {
        const animation = thisObject.getAnimation();
        animation.stop();
        animation.play();
      }
    }
    """

    static let mediaPlaybackSource = """
    'use strict'
    var secondsPerFade = 1
    var resultScale = 1
    var unusedPlaybackSlot = 0
    var scalarAccumulator = 0
    secondsPerFade = 1 / secondsPerFade
    var playbackBranch = MediaPlaybackEvent.PLAYBACK_STOPPED

    export function mediaPlaybackChanged(playbackEvent) {
        if (playbackEvent.state == MediaPlaybackEvent.PLAYBACK_STOPPED) {
            playbackBranch = 0
        } else if (playbackEvent.state == MediaPlaybackEvent.PLAYBACK_PLAYING) {
            playbackBranch = 1
        } else if (playbackEvent.state == MediaPlaybackEvent.PLAYBACK_PAUSED) {
            playbackBranch = 2
        } else {
            playbackBranch = 3
        }
    }

    export function update(authoredScalar) {
        if (playbackBranch == 0) {
            scalarAccumulator = scalarAccumulator - (secondsPerFade * engine.frametime * 2)
            if (scalarAccumulator < 0) { scalarAccumulator = 0 }
        } else if (playbackBranch == 1) {
            scalarAccumulator = scalarAccumulator + (secondsPerFade * engine.frametime * 2)
            if (scalarAccumulator > 1) { scalarAccumulator = 1 }
        } else if (playbackBranch == 2) {
            scalarAccumulator = scalarAccumulator + (secondsPerFade * engine.frametime * 2)
            if (scalarAccumulator > 1) { scalarAccumulator = 1 }
        }
        return scalarAccumulator * resultScale
    }
    """

    static let mediaPropertiesSource = """
    let mediaData = "";
    export function update(value) { return mediaData || value; }
    export function mediaPropertiesChanged(event) {
        mediaData = [event.title, event.artist, event.subTitle, event.albumTitle, event.albumArtist, event.genres, event.contentType].join(" / ");
    }
    """

    static let orderedScalarMediaSource = """
    function mark(value) { shared.mediaOrder = (shared.mediaOrder || "") + value; }
    let initialized = false;
    export function init(value) { initialized = true; mark("sI"); return value; }
    export function mediaPlaybackChanged() {
        if (!initialized) { throw new Error("scalar media before init"); }
        mark("sP");
    }
    export function mediaPropertiesChanged() { thisLayer.visible = false; mark("sR"); }
    export function mediaThumbnailChanged() { mark("sH"); }
    export function mediaTimelineChanged() { mark("sL"); }
    export function update(value) { mark("sU"); return value; }
    """

    static let orderedVectorMediaSource = """
    function mark(value) { shared.mediaOrder = (shared.mediaOrder || "") + value; }
    let initialized = false;
    export function init(value) { initialized = true; mark("vI"); return value; }
    export function mediaPlaybackChanged() {
        if (!initialized) { throw new Error("vector media before init"); }
        mark("vP");
    }
    export function mediaPropertiesChanged() { thisLayer.visible = false; mark("vR"); }
    export function mediaThumbnailChanged() { mark("vH"); }
    export function mediaTimelineChanged() { mark("vL"); }
    export function update(value) { mark("vU"); return value; }
    """

    static let orderedStringMediaSource = """
    function mark(value) { shared.mediaOrder = (shared.mediaOrder || "") + value; }
    let initialized = false;
    export function init(value) { initialized = true; mark("tI"); return value; }
    export function mediaPlaybackChanged() {
        if (!initialized) { throw new Error("string media before init"); }
        mark("tP");
    }
    export function mediaPropertiesChanged() { thisLayer.visible = false; mark("tR"); }
    export function mediaThumbnailChanged() { mark("tH"); }
    export function mediaTimelineChanged() { mark("tL"); }
    export function update() { mark("tU"); return shared.mediaOrder; }
    """


    static let audioScaleSource = """
    export var scriptProperties = createScriptProperties()
        .addSlider({name: "frequency", value: 0})
        .addSlider({name: "minvalue", value: 1})
        .finish();
    const audioBuffer = engine.registerAudioBuffers(engine.AUDIO_RESOLUTION_16);
    let initialValue;
    export function init(value) { initialValue = value; }
    export function update() {
        return initialValue.multiply(
            scriptProperties.minvalue + audioBuffer.average[scriptProperties.frequency]
        );
    }
    """

    static let passVectorSource = """
    export function update(value) { return value.multiply(2); }
    """

    static let passColorSource = """
    import * as WEColor from 'WEColor';
    export let scriptProperties = createScriptProperties()
        .addSlider({name: 'speed', value: 0.25})
        .addSlider({name: 'saturation', value: 1})
        .addSlider({name: 'brightness', value: 1})
        .finish();
    export function update(value) {
        return WEColor.hsv2rgb({
            x: engine.runtime * scriptProperties.speed,
            y: scriptProperties.saturation,
            z: scriptProperties.brightness
        });
    }
    """

    static let passAudioScalarSource = """
    export var scriptProperties = createScriptProperties()
        .addSlider({name: "frequency", value: 0})
        .addSlider({name: "minvalue", value: 1})
        .addSlider({name: "maxvalue", value: 2})
        .addSlider({name: "smoothing", value: 20})
        .finish();
    const audioBuffer = engine.registerAudioBuffers(engine.AUDIO_RESOLUTION_16);
    let initialValue = 0;
    export function init(value) { initialValue = value; return value; }
    export function update() {
        return initialValue * (
            scriptProperties.minvalue
            + audioBuffer.average[scriptProperties.frequency]
        );
    }
    """

    static let dynamicScalarSource = """
    export var scriptProperties = createScriptProperties()
        .addSlider({name: "newSlider", value: 50})
        .finish();
    let initialized = false;
    export function init(value) {
        initialized = true;
        return value;
    }
    export function applyUserProperties() {
        if (!initialized) { throw new Error("properties before scalar init"); }
    }
    export function update(value) {
        if (scriptProperties.newSlider < 0) {
            throw new Error("scalar provider failure");
        }
        return -scriptProperties.newSlider;
    }
    """

    static let currentPropertyEventSource = """
    'use strict';
    export function applyUserProperties(userProperties) {
      if (userProperties.hasOwnProperty('ui_editor_properties_mode')) {
        const mode = parseInt(userProperties.ui_editor_properties_mode);
        thisObject.colormode = mode;
        if (mode === 3) {
          engine.setTimeout(() => { thisObject.colormode = 9; }, 20);
        }
      }
    }
    """

    static let particleAudioSource = """
    export var scriptProperties = createScriptProperties()
        .addSlider({name: "frequency", value: 0})
        .addSlider({name: "minvalue", value: 1})
        .finish();
    const audioBuffer = engine.registerAudioBuffers(engine.AUDIO_RESOLUTION_16);
    let initialValue = 0;
    export function init(value) { initialValue = value; return value; }
    export function update() {
        return initialValue * (
            scriptProperties.minvalue
            + audioBuffer.average[scriptProperties.frequency]
        );
    }
    """
}
