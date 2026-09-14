"""Execute the production synchronous launch entry with preparation boundary doubles."""
from pathlib import Path
import json
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / 'MyWallpaperX/Core/SteamWorkshopScene/Runtime/SceneDesktopWallpaperHost+Launch.swift'


class SceneSyncLaunchGenerationTests(unittest.TestCase):
    def test_attempts_receive_distinct_generations_even_after_failure(self):
        source = SOURCE.read_text()
        begin = source.index('    @discardableResult\n    func launch(')
        end = source.index('    private static func prepareLaunch(', begin)
        method = source[begin:end]
        support = r'''
import Foundation
struct SceneUserPropertyValue {}
struct SceneRuntimeModel {}
struct SceneTextureDecodeCacheBudget {}
enum Phase { case accepted, launched }
enum Expected: Error { case preparation }
final class SceneDesktopWallpaperHost {
    var nextSceneScriptGeneration: UInt64 = 0
    let textureDecodeCacheBudget = SceneTextureDecodeCacheBudget()
    static var observed: [UInt64] = []
    static var failNext = false
    static func recordLaunchPhase(_ phase: Phase) {}
    static func prepareLaunch(rootURL: URL,
        propertyOverrides: [String: SceneUserPropertyValue],
        userPropertyTextureURLs: [String: URL], logURL: URL?, recordID: String?,
        sceneScriptGeneration: UInt64,
        textureDecodeCacheBudget: SceneTextureDecodeCacheBudget, cancellation: Int?,
        progress: (Phase, String) -> Void
    ) throws -> (context: Int, model: SceneRuntimeModel) {
        observed.append(sceneScriptGeneration)
        if failNext { failNext = false; throw Expected.preparation }
        return (0, SceneRuntimeModel())
    }
    func activate(_ context: Int) throws {}
'''
        tail = r'''
}
@main enum Harness {
    static func main() throws {
        let host = SceneDesktopWallpaperHost()
        let root = URL(fileURLWithPath: "/unused")
        try host.launch(rootURL: root)
        SceneDesktopWallpaperHost.failNext = true
        do { try host.launch(rootURL: root) } catch Expected.preparation {}
        try host.launch(rootURL: root)
        print(String(data: try JSONEncoder().encode(SceneDesktopWallpaperHost.observed), encoding: .utf8)!)
    }
}
'''
        with tempfile.TemporaryDirectory(prefix='mwx-launch-generation-') as directory:
            path = Path(directory)
            harness = path / 'Harness.swift'
            harness.write_text(support + method + tail)
            binary = path / 'harness'
            compilation = subprocess.run(['xcrun', 'swiftc', '-swift-version', '5', '-parse-as-library', str(harness), '-o', str(binary)], capture_output=True, text=True, timeout=60)
            self.assertEqual(compilation.returncode, 0, compilation.stderr)
            result = subprocess.run([str(binary)], capture_output=True, text=True, check=True, timeout=10)
            self.assertEqual(json.loads(result.stdout), [1, 2, 3])
