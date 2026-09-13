import json
import subprocess
import tempfile
import unittest
from pathlib import Path


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
SOURCE = (
    REPOSITORY_ROOT
    / "MyWallpaperX/Core/SteamWorkshopScene/RenderGraph/ShaderPreparation"
    / "SceneGenericShaderLoopGuardLowering.swift"
)

HARNESS = r'''
import Foundation

struct Output: Codable {
    let vertexNamespaced: Bool
    let fragmentNamespaced: Bool
    let symbolsDisjoint: Bool
    let pairCount: Int
    let standalonePreserved: Bool
    let authoredCollisionRejected: Bool
}

@main
enum Main {
    static func main() throws {
        let vertex = """
        #version 450
        void main() {
            for (int i = 0; i < 8; ++i) {}
        }
        """
        let fragment = """
        #version 450
        void main() {
            int i = 0;
            while (i < 8) { ++i; }
        }
        """
        let pair = SceneGenericShaderLoopGuardLowering.lowerPair(
            vertex: vertex,
            fragment: fragment
        )
        let standalone = SceneGenericShaderLoopGuardLowering.lower(vertex)
        let collision = SceneGenericShaderLoopGuardLowering.lowerPair(
            vertex: vertex.replacingOccurrences(
                of: "void main()",
                with: "bool mwxVertexGuardLoop(bool value) { return value; }\nvoid main()"
            ),
            fragment: fragment
        )
        let output = Output(
            vertexNamespaced: pair?.vertex.contains("mwxVertexGuardLoop") == true
                && pair?.vertex.contains("mwxFragmentGuardLoop") == false,
            fragmentNamespaced: pair?.fragment.contains("mwxFragmentGuardLoop") == true
                && pair?.fragment.contains("mwxVertexGuardLoop") == false,
            symbolsDisjoint: pair?.vertex.contains("mwxVertexLoopGuardCount") == true
                && pair?.fragment.contains("mwxFragmentLoopGuardCount") == true,
            pairCount: pair?.guardedLoopCount ?? -1,
            standalonePreserved: standalone?.source.contains("mwxGuardLoop") == true,
            authoredCollisionRejected: collision == nil
        )
        FileHandle.standardOutput.write(try JSONEncoder().encode(output))
    }
}
'''


class SceneGenericShaderLoopGuardLoweringTests(unittest.TestCase):
    def test_stage_symbols_do_not_collide_when_msl_is_linked(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            harness = root / "Harness.swift"
            binary = root / "loop-guard"
            harness.write_text(HARNESS, encoding="utf-8")
            subprocess.run(
                ["swiftc", str(SOURCE), str(harness), "-o", str(binary)],
                cwd=REPOSITORY_ROOT,
                check=True,
                capture_output=True,
                text=True,
            )
            completed = subprocess.run(
                [str(binary)],
                cwd=REPOSITORY_ROOT,
                check=True,
                capture_output=True,
                text=True,
            )
        self.assertEqual(
            json.loads(completed.stdout),
            {
                "vertexNamespaced": True,
                "fragmentNamespaced": True,
                "symbolsDisjoint": True,
                "pairCount": 2,
                "standalonePreserved": True,
                "authoredCollisionRejected": True,
            },
        )


if __name__ == "__main__":
    unittest.main()
