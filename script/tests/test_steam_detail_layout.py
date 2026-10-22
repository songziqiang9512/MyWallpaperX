"""Actual shared footer controls and production detail action layout."""
import pathlib
import hashlib
import json
import os
import subprocess
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]

class SteamDetailLayoutTests(unittest.TestCase):
    def test_scene_property_notifications_preserve_actual_detail(self):
        """Execute the real detail/observer; external account/playback leaves are inert."""
        def declaration(source, prefix):
            start = source.index(prefix)
            opening = source.index('{', start)
            depth = 0
            for index in range(opening, len(source)):
                depth += (source[index] == '{') - (source[index] == '}')
                if depth == 0:
                    return source[start:index+1]
            raise AssertionError(prefix)

        ui = ROOT / 'MyWallpaperX/Modules/SteamWorkshop/UI'
        core = ROOT / 'MyWallpaperX/Modules/SteamWorkshop/Core'
        with tempfile.TemporaryDirectory(prefix='mwx-detail-invalidation-', dir='/private/tmp') as temporary:
            work = pathlib.Path(temporary)
            paths = [ui / 'SteamWorkshopItemDetailSheet.swift', ui / 'SteamWorkshopItemDetailSheet+Observation.swift',
                ui / 'SteamWorkshopDetailFooterView.swift', ui / 'SteamWorkshopPreviewPlaceholderView.swift',
                ui / 'SteamWorkshopPreviewState.swift', ui / 'SteamWorkshopItemDetailPreviewSupport.swift',
                core / 'SteamWorkshopDownloadProgress.swift', core / 'SteamWorkshopDetailRefreshSupport.swift',
                ROOT / 'MyWallpaperX/Shared/UI/InspectorFooterMetrics.swift',
                ROOT / 'MyWallpaperX/Shared/UI/InspectorFadingScrollView.swift',
                ROOT / 'MyWallpaperX/Core/SteamWorkshopScene/Systems/Properties/SceneUserProperty.swift']
            originals = {}
            def read(path):
                data = path.read_bytes()
                originals[str(path.relative_to(ROOT))] = hashlib.sha256(data).hexdigest()
                return data.decode()
            sources = []
            for path in paths:
                target = work / path.name
                target.write_text(read(path))
                sources.append(target)
            models = read(core / 'SteamWorkshopModels.swift')
            fragments = ['import AppKit\nimport Foundation'] + [declaration(models, prefix) for prefix in [
                'enum SteamWorkshopDownloadContentType', 'nonisolated enum SteamWorkshopPreviewAssetKind',
                'nonisolated struct SteamWorkshopDetailField', 'nonisolated struct SteamWorkshopBrowserItem',
                'struct SteamWorkshopDownloadRecord']]
            validation = read(ROOT / 'MyWallpaperX/Modules/SteamWorkshop/Web/Core/SteamWorkshopWebValidationModels.swift')
            fragments += [declaration(validation, prefix) for prefix in [
                'enum SteamWorkshopWebDependencyStatus']]
            fragments.append(declaration(read(ui / 'AppKitSteamWorkshopBrowserItemSupportViews.swift'), 'enum SteamWorkshopDownloadProgressPalette'))
            service = read(ROOT / 'MyWallpaperX/Modules/SteamWorkshop/Scene/SteamWorkshopSceneService+SceneProperties.swift')
            fragments.append('extension SteamWorkshopService {\n' + '\n\n'.join(declaration(service, prefix) for prefix in [
                'private enum ScenePropertyOverrideStore', '    func scenePropertyOverrides(',
                '    func updateScenePropertyValue(', '    func saveScenePropertyOverrides(']) + '\n}')
            actual = work / 'ActualFragments.swift'
            actual.write_text('\n\n'.join(fragments))
            sources.append(actual)
            for name in ['SteamDetailInvalidationSupport.swift', 'SteamDetailInvalidationHarness.swift']:
                path = ROOT / 'script/tests/fixtures' / name
                read(path)
                sources.append(path)
            binary = work / 'detail'
            command = ['xcrun', 'swiftc', '-O', '-parse-as-library', '-swift-version', '5', '-default-isolation', 'MainActor',
                *map(str, sources), '-module-cache-path', str(work/'module-cache'), '-o', str(binary)]
            build = subprocess.run(command, capture_output=True, text=True, timeout=90)
            self.assertEqual(build.returncode, 0, build.stdout + build.stderr)
            home = work/'home'
            home.mkdir()
            result = subprocess.run([str(binary)], env=dict(os.environ, HOME=str(home), CFFIXED_USER_HOME=str(home)),
                capture_output=True, text=True, timeout=30)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            facts = json.loads(result.stdout)
            for name, passed in facts['checks'].items():
                with self.subTest(name=name):
                    self.assertTrue(passed)
            self.assertTrue(facts['checks'])
            self.assertEqual(originals, {name: hashlib.sha256((ROOT/name).read_bytes()).hexdigest() for name in originals})
            proof = os.environ.get('MWX_DETAIL_INVALIDATION_PROOF_DIR')
            if proof:
                target = pathlib.Path(proof)
                target.mkdir(parents=True, exist_ok=True)
                (target/'facts.json').write_text(json.dumps(facts, indent=2)+'\n')
                (target/'source-inputs.json').write_text(json.dumps(originals, indent=2)+'\n')
                (target/'compile.log').write_text(build.stdout+build.stderr)
                (target/'runtime.log').write_text(result.stderr)

    def test_long_primary_actions_and_narrow_widths(self):
        with tempfile.TemporaryDirectory(prefix='mwx-steam-detail-layout-', dir='/private/tmp') as temporary:
            binary = pathlib.Path(temporary) / 'footer'
            support = (ROOT / 'MyWallpaperX/Modules/SteamWorkshop/UI/AppKitSteamWorkshopBrowserItemSupportViews.swift').read_text()
            bar = pathlib.Path(temporary) / 'ActualGlassBar.swift'
            bar.write_text('import AppKit\nimport QuartzCore\n' + support[support.index('enum SteamWorkshopDownloadProgressPalette'):])
            build = subprocess.run(['xcrun', 'swiftc', '-parse-as-library',
                str(ROOT / 'MyWallpaperX/Shared/UI/InspectorFooterMetrics.swift'),
                str(ROOT / 'MyWallpaperX/Modules/SteamWorkshop/UI/SteamWorkshopDetailFooterView.swift'),
                str(bar), str(ROOT / 'script/tests/fixtures/SteamDetailFooterHarness.swift'), '-o', str(binary)],
                capture_output=True, text=True, timeout=60)
            self.assertEqual(build.returncode, 0, build.stdout + build.stderr)
            result = subprocess.run([str(binary)], capture_output=True, text=True, timeout=30)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn('dispatch PASS', result.stdout)

if __name__ == '__main__':
    unittest.main()
