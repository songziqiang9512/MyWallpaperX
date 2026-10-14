"""Display vocabulary, migrated language selection, and loss-preserving import."""
import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

from script.tests.test_scene_property_live_routing import method_body

ROOT = Path(__file__).resolve().parents[2]
RESOLVER = ROOT / 'MyWallpaperX/Shared/WorkshopPropertyDisplayResolver.swift'
RESOURCE = ROOT / 'MyWallpaperX/Resources/WorkshopPropertyDisplayStrings.json'
SCENE = ROOT / 'MyWallpaperX/Core/SteamWorkshopScene'
NORMALIZATION = ROOT / 'MyWallpaperX/Modules/SteamWorkshop/Web/Core/SteamWorkshopService+WebPropertyNormalizationSupport.swift'

PROBE = r'''
import Foundation
struct SteamWorkshopService { __WEB_METHODS__ }
@main enum Probe {
    static func main() throws {
        let vocabulary = try JSONDecoder().decode(WorkshopPropertyDisplayResolver.Vocabulary.self,
            from: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])))
        let token = "ui_browse_properties_scheme_color"
        let unknown = "ui_editor_author_private_name"
        var facts: [String: Bool] = [:]
        func resolver(_ keys: [String], _ author: WorkshopPropertyLocalization = .empty) -> WorkshopPropertyDisplayResolver {
            .init(localization: author, languageKeys: keys, vocabulary: vocabulary)
        }
        facts["english"] = resolver(["en-us"]).string(token) == "Scheme color"
        facts["simplified-alias"] = resolver(["zh-hans-cn"]).string(token) == "主题色"
        facts["traditional-alias"] = resolver(["zh-tw"]).string(token) == "主題色"
        facts["english-fallback"] = resolver(["ja-jp"]).string(token) == "Scheme color"
        facts["unknown-keeps-exact-author-text"] = resolver(["zh-cn"]).string(unknown) == unknown
        let root: [String: Any] = ["localization": [token: "Author theme"],
            "general": ["localization": [token: "ignored"]]]
        facts["root-flat-keeps-old-precedence"] = resolver(["zh-cn"], .init(projectRoot: root)).string(token) == "Author theme"
        let flat = WorkshopPropertyLocalization(projectRoot: ["general": ["localization": [token: "", unknown: "作者原文"]]])
        facts["explicit-empty-author-is-not-overwritten"] = resolver(["en-us"], flat).string(token).isEmpty
        facts["author-unknown-token-can-be-explicitly-localized"] = resolver(["en-us"], flat).string(unknown) == "作者原文"
        let languageTables: [String: Any] = ["zh-cht": [token: "作者繁體"], "zh-chs": [token: "作者简体"],
            "en-us": [token: "Author English"], "not-a-language": [token: "wrong"], "bad": [token: 1]]
        let author = WorkshopPropertyLocalization(projectRoot: ["general": ["localization": languageTables]])
        facts["author-simplified-is-deterministic"] = resolver(["zh-hans-cn", "zh"], author).string(token) == "作者简体"
        facts["author-traditional-is-deterministic"] = resolver(["zh-hant-hk", "zh"], author).string(token) == "作者繁體"
        facts["unknown-language-does-not-steal-english"] = resolver(["en-us"], author).string(token) == "Author English"
        facts["old-first-table-fallback-is-stable"] = WorkshopPropertyLocalization(flat: nil,
            tables: ["fr-fr": [token: "Français"], "de-de": [token: "Deutsch"]])
                .strings(languageKeys: ["en-us"])[token] == "Deutsch"
        let keys = WorkshopPropertyDisplayResolver.preferredLanguageKeys(preferredLanguages: ["zh_Hant_TW", "en-US"],
            currentIdentifier: "zh_Hant_TW", autoupdatingIdentifier: "en_US")
        facts["ordered-language-candidates-preserved"] = keys == ["zh-hant-tw", "zh", "en-us", "en"]
        facts["web-language-interface-delegates"] = SteamWorkshopService.wallpaperEngineLanguageCode(for: "zh-Hant-TW") == "zh-cht"
            && SteamWorkshopService.wallpaperEngineLanguageCode(for: "zh-Hans-CN") == "zh-chs"
            && SteamWorkshopService.wallpaperEngineLanguageCode(for: "pt_BR") == "pt-br"
        facts["web-author-table-interface-keeps-input-behavior"] = SteamWorkshopService.webProjectLocalization(from: root)[token] == "Author theme"
        facts["web-explicit-author-priority"] = SteamWorkshopService.localizedWebString(token, localization: [token: "Author visible"]) == "Author visible"
        facts["web-unknown-preserves-text"] = SteamWorkshopService.localizedWebString(unknown, localization: [:]) == unknown
        facts["fixture-loads-real-standard-vocabulary"] = WorkshopPropertyDisplayResolver().string("ui_close") != "ui_close"
        func webInputs(_ localization: [String: String]) -> SteamWorkshopService.WebDisplayConditionInputs {
            let options = SteamWorkshopService.webPropertyOptions(
                from: [["label": "ui_close", "value": 0]], localization: localization)
            let definition = SteamWorkshopWebPropertyDefinition(key: "mode", title: "Own mode", kind: .combo,
                runtimeType: "combo", order: 0, minimumValue: nil, maximumValue: nil,
                allowsFractionalValues: false, fractionalPrecision: nil, displayCondition: nil,
                directoryMode: nil, fileType: nil, defaultValue: .number(0), options: options)
            return .init(values: ["mode": .number(0)], definitions: [definition])
        }
        let rawWeb = webInputs([:])
        facts["web-standard-token-without-author-map-keeps-old-text-condition"] = rawWeb.comboTextValues["mode"] == "ui_close"
            && SteamWorkshopService.WebDisplayConditionProgram("mode.text == 'ui_close'").evaluate(inputs: rawWeb)
            && !SteamWorkshopService.WebDisplayConditionProgram("mode.text == 'Close'").evaluate(inputs: rawWeb)
        let authoredWeb = webInputs(["ui_close": "Author off"])
        facts["web-explicit-author-label-keeps-old-translated-text-condition"] = authoredWeb.comboTextValues["mode"] == "Author off"
            && SteamWorkshopService.WebDisplayConditionProgram("mode.text == 'Author off'").evaluate(inputs: authoredWeb)
            && !SteamWorkshopService.WebDisplayConditionProgram("mode.text == 'ui_close'").evaluate(inputs: authoredWeb)
        facts["web-hidden-value-condition-remains-numeric"] = rawWeb.values["mode"] == .number(0)
            && authoredWeb.values["mode"] == .number(0)
            && SteamWorkshopService.WebDisplayConditionProgram("mode.value == 0").evaluate(inputs: rawWeb)
            && SteamWorkshopService.WebDisplayConditionProgram("mode.value == 0").evaluate(inputs: authoredWeb)
        let work = URL(fileURLWithPath: CommandLine.arguments[2])
        let raw: [String: Any] = ["type": "scene", "general": ["localization": languageTables, "properties": [
            "renamed_key": ["type": "combo", "text": token, "value": "ui_hidden_original", "condition": "gate.value == true",
                "options": [["label": "ui_close", "value": "ui_hidden_original"]]],
            "gate": ["type": "bool", "text": token, "value": true]]]]
        try JSONSerialization.data(withJSONObject: raw).write(to: work.appendingPathComponent("project.json"))
        let project = try SceneProjectLoader().load(from: work)
        let definition = project.userProperties.definitions.first { $0.key == "renamed_key" }!
        let imported = resolver(["zh-hans-cn"], project.propertyDisplayLocalization)
        facts["project-captures-author-table-without-translating-catalog"] = imported.string(definition.title) == "作者简体"
            && definition.title == token && definition.key == "renamed_key"
        facts["condition-default-and-hidden-value-stay-raw"] = definition.displayCondition == "gate.value == true"
            && definition.defaultValue == .string("ui_hidden_original") && definition.options.first?.value == .string("ui_hidden_original")
            && definition.options.first?.label == "ui_close"
        facts["same-token-cross-type-is-display-only"] = project.userProperties.definitions.allSatisfy { imported.string($0.title) == "作者简体" }
            && Set(project.userProperties.definitions.map(\.kind)) == [.combo, .bool]
        facts["missing-vocabulary-is-local-raw-fallback"] = WorkshopPropertyDisplayResolver(languageKeys: ["en-us"], vocabulary: .empty).string(token) == token
        print(String(decoding: try JSONSerialization.data(withJSONObject: facts), as: UTF8.self))
    }
}
'''


class WorkshopPropertyDisplayLocalizationTests(unittest.TestCase):
    def test_curated_resource_contract(self):
        def unique_object(pairs):
            result = {}
            for key, value in pairs:
                self.assertNotIn(key, result, f'duplicate resource key: {key}')
                result[key] = value
            return result
        resource = json.loads(RESOURCE.read_text(), object_pairs_hook=unique_object)
        self.assertEqual(resource['schemaVersion'], 1)
        self.assertEqual(set(resource['languages']), {'en-us', 'zh-chs', 'zh-cht'})
        english = resource['languages']['en-us']
        self.assertEqual(len(english), 15)
        for language, entries in resource['languages'].items():
            self.assertEqual(set(entries), set(english), language)
            for token, text in entries.items():
                self.assertTrue(token.startswith('ui_'))
                self.assertIsInstance(text, str)
                self.assertTrue(text.strip())
                self.assertNotIn('<', text)
        # Resource keys name display tokens; never wallpaper/property identity.
        self.assertEqual(set(resource), {'schemaVersion', 'languages'})

    @unittest.skipUnless(shutil.which('swiftc'), 'Swift compiler required')
    def test_resolver_web_interfaces_and_real_project_import(self):
        normalization = NORMALIZATION.read_text()
        signatures = ['    nonisolated static func webProjectLocalization(',
            '    nonisolated static func localizedWebString(', '    nonisolated static func wallpaperEngineLanguageCode(',
            '    nonisolated static func normalizedWebDisplayText(', '    private nonisolated static func normalizedWebDisplaySegments(',
            '    private nonisolated static func collapseRepeatedWebDisplaySegments(',
            '    nonisolated static func normalizedWebPropertyTitleText(']
        source = PROBE.replace('__WEB_METHODS__', '\n'.join(method_body(normalization, s) for s in signatures))
        with tempfile.TemporaryDirectory(prefix='mwx-property-display-') as directory:
            work = Path(directory)
            (work / RESOURCE.name).write_bytes(RESOURCE.read_bytes())
            probe = work / 'Probe.swift'
            probe.write_text(source)
            binary = work / 'probe'
            inputs = [RESOLVER, SCENE / 'Format/SceneProject.swift', SCENE / 'Format/SceneCompatibilityContext.swift',
                SCENE / 'Systems/Properties/SceneUserProperty.swift', SCENE / 'Systems/Properties/SceneUserPropertyDefinitionParser.swift',
                NORMALIZATION.with_name('SteamWorkshopService+WebPropertyParsing.swift'),
                NORMALIZATION.with_name('SteamWorkshopWebPropertyModels.swift'),
                NORMALIZATION.with_name('SteamWorkshopService+WebDisplayConditionSupport.swift'),
                NORMALIZATION.with_name('SteamWorkshopService+WebDisplayConditionParsing.swift')]
            build = subprocess.run(['swiftc', '-parse-as-library', *map(str, inputs), str(probe),
                '-module-cache-path', str(work / 'cache'), '-o', str(binary)], capture_output=True, text=True, timeout=90)
            self.assertEqual(build.returncode, 0, build.stderr)
            run = subprocess.run([str(binary), str(RESOURCE), str(work)], capture_output=True, text=True, timeout=30)
            self.assertEqual(run.returncode, 0, run.stderr)
            for name, passed in json.loads(run.stdout).items():
                with self.subTest(name=name):
                    self.assertTrue(passed)
