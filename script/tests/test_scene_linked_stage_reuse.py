#!/usr/bin/env python3
"""Compiler orchestration failures with a deterministic helper boundary.

Real helper/MSL/Metal equivalence is covered by the generic coordinate compiler
and actual cold/warm product-entry gates; these doubles inject missing/stale files.
"""
import json
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / 'MyWallpaperX/Core/SteamWorkshopScene/Compilation/ShaderPreparation/SceneGenericShaderCompiler.swift'
SUPPORT = r'''
import Foundation

enum SceneGenericShaderOutputSemantics { case color }
enum SceneGenericShaderExpectedColorTransfer {}
struct SceneShaderColorBoundary {}
enum SceneGenericShaderCompilerBundle {
    struct Limits {
        let maximumStageSourceBytes = 4096
        let maximumArtifactBytes = 4096
        let maximumDiagnosticBytes = 4096
        let maximumResidentBytes = 1048576
        let timeoutMilliseconds = 100
    }
    struct Configuration {
        let backendID = "test"
        let glslang = URL(fileURLWithPath: "/test/glslang")
        let spirvCross = URL(fileURLWithPath: "/test/cross")
        let glslangVersionProbe = "test-version"
        let spirvCrossVersionProbe = "test-version"
        let glslangVersionProbeExitCode: Int32 = 0
        let spirvCrossVersionProbeExitCode: Int32 = 0
        let limits = Limits()
    }
    enum Failure: Error { case unavailable }
    static func resolve(bundle: Bundle) -> Result<Configuration, Failure> { .success(.init()) }
}
enum SceneGenericShaderSourceNormalizer {
    struct Pair { let vertex: String; let fragment: String; let vertexPositionInput = 0 }
    enum Failure: Error { case invalid }
    static func normalize(vertexSource: String, fragmentSource: String,
                          maximumStageSourceBytes: Int) -> Result<Pair, Failure> {
        .success(.init(vertex: vertexSource, fragment: fragmentSource))
    }
}
struct SceneGenericShaderProgramArtifact: Encodable { let stages: [String]; let guardCap: Int? }
enum SceneGenericShaderArtifactBuilder {
    struct Stage {
        let name: String; let source: String; let authoredSource: String
        let msl: String; let reflection: Data
    }
    enum Failure: Error { case loopUnbounded, loopBudget, invalid }
    static func build(requestKey: String, backendID: String,
        outputSemantics: SceneGenericShaderOutputSemantics,
        expectedColorTransfer: SceneGenericShaderExpectedColorTransfer?,
        premultipliedColorInputSlots: Set<Int>, defaultBoundaryColorSlots: Set<Int>,
        colorBoundary: SceneShaderColorBoundary?, boundTextureSlots: Set<Int>,
        stages: [Stage], vertexPositionInput: Int, loopGuardCap: Int?,
        maximumArtifactBytes: Int) -> Result<SceneGenericShaderProgramArtifact, Failure> {
        if loopGuardCap == nil && stages.contains(where: { $0.source.contains("needs_guard") }) {
            return .failure(.loopUnbounded)
        }
        return .success(.init(stages: stages.map(\.msl), guardCap: loopGuardCap))
    }
}
enum SceneGenericShaderLoopGuardLowering {
    static let iterationCap = 100
    static func lowerPair(vertex: String, fragment: String) -> SceneGenericShaderSourceNormalizer.Pair? {
        .init(vertex: vertex + " guarded", fragment: fragment + " guarded")
    }
}
enum SceneGenericShaderCompilerProcess {
    struct Output { let stdout: Data; let stderr = Data() }
    enum Failure: Error { case rejected }
    static var calls: [[String]] = []
    static var links = 0
    static var mode = ""
    static func run(executable: URL, arguments: [String], workingDirectory: URL,
                    timeoutMilliseconds: Int, maximumDiagnosticBytes: Int,
                    maximumResidentBytes: Int, expectedExitCode: Int32 = 0) -> Result<Output, Failure> {
        calls.append(arguments)
        if arguments == ["--version"] { return .success(.init(stdout: Data("test-version".utf8))) }
        do {
            if arguments.contains("-l") {
                links += 1
                if mode == "link-failure" { return .failure(.rejected) }
                for (suffix, name) in [("vert", "author.vert"), ("frag", "author.frag")] {
                    if suffix == "frag" && (mode == "missing-fragment" || mode == "stale-retry" && links == 2) { continue }
                    let data = try Data(contentsOf: workingDirectory.appendingPathComponent(name))
                    let output = workingDirectory.appendingPathComponent(suffix + ".spv")
                    if mode == "symlink" && suffix == "frag" {
                        try FileManager.default.createSymbolicLink(at: output,
                            withDestinationURL: workingDirectory.appendingPathComponent(name))
                    } else { try (mode == "empty" && suffix == "frag" ? Data() : data).write(to: output) }
                }
            } else if let index = arguments.firstIndex(of: "--output") {
                let input = URL(fileURLWithPath: arguments[0])
                try Data(contentsOf: input).write(to: URL(fileURLWithPath: arguments[index + 1]))
            } else { return .failure(.rejected) }
            return .success(.init(stdout: Data()))
        } catch { return .failure(.rejected) }
    }
}
@main enum Harness {
    static func main() throws {
        SceneGenericShaderCompilerProcess.mode = CommandLine.arguments[1]
        let cache = URL(fileURLWithPath: CommandLine.arguments[2])
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        let guarded = ["guarded", "stale-retry"].contains(CommandLine.arguments[1])
        let vertex = guarded ? "vertex needs_guard" : "renamed_vertex"
        let result = SceneGenericShaderCompiler.compile(requestKey: "fixture", vertexSource: vertex,
            fragmentSource: "renamed_fragment", cacheRoot: cache)
        var output: [String: Any] = ["links": SceneGenericShaderCompilerProcess.links,
                                    "calls": SceneGenericShaderCompilerProcess.calls]
        switch result {
        case let .success(url): output["artifact"] = try JSONSerialization.jsonObject(with: Data(contentsOf: url))
        case let .failure(failure): output["failure"] = String(describing: failure)
        }
        output["published"] = FileManager.default.fileExists(atPath: cache.appendingPathComponent("fixture.json").path)
        FileHandle.standardOutput.write(try JSONSerialization.data(withJSONObject: output))
    }
}
'''

class SceneLinkedStageReuseTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temporary = tempfile.TemporaryDirectory(prefix='mwx-linked-stage-')
        cls.addClassCleanup(cls.temporary.cleanup)
        root = Path(cls.temporary.name)
        support = root / 'Harness.swift'
        support.write_text(SUPPORT)
        cls.binary = root / 'probe'
        subprocess.run(['xcrun', 'swiftc', '-parse-as-library', str(SOURCE),
                        str(support), '-module-cache-path', str(root/'modules'),
                        '-o', str(cls.binary)], capture_output=True, text=True, check=True)

    def run_case(self, mode):
        with tempfile.TemporaryDirectory(dir=self.temporary.name) as cache:
            result = subprocess.run([str(self.binary), mode, cache], capture_output=True,
                                    text=True, check=True)
            return json.loads(result.stdout)

    def test_exact_linked_stages_are_published_without_duplicate_compile(self):
        row = self.run_case('ordinary')
        self.assertEqual(row['artifact']['stages'], ['renamed_vertex', 'renamed_fragment'])
        self.assertEqual(row['links'], 1)
        self.assertEqual(len(row['calls']), 7)  # two version probes, one link, four cross calls

    def test_guarded_retry_publishes_only_the_replacement_stages(self):
        row = self.run_case('guarded')
        self.assertEqual(row['links'], 2)
        self.assertEqual(row['artifact'], {'guardCap': 100,
            'stages': ['vertex needs_guard guarded', 'renamed_fragment guarded']})

    def test_missing_or_unsafe_linked_output_does_not_publish(self):
        for mode in ['missing-fragment', 'empty', 'symlink', 'stale-retry']:
            with self.subTest(mode=mode):
                row = self.run_case(mode)
                self.assertEqual(row['failure'], 'artifact("fragment-spirv")')
                self.assertFalse(row['published'])

    def test_failed_link_stops_before_lowering_or_publication(self):
        row = self.run_case('link-failure')
        self.assertIn('stage-link', row['failure'])
        self.assertFalse(row['published'])
        self.assertEqual(len(row['calls']), 3)

if __name__ == '__main__':
    unittest.main()
