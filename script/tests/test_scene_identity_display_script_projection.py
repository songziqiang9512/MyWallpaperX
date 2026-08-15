#!/usr/bin/env python3

from __future__ import annotations

import json
from pathlib import Path
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]
SCENE = ROOT / "MyWallpaperX/Core/SteamWorkshopScene"
SOURCES = [
    SCENE / "Properties/SceneLaunchOriginTransitionCompiler+SyntaxLexer.swift",
    SCENE / "Properties/SceneIdentityDisplayScriptProjection.swift",
]

HARNESS = r'''
import Foundation

enum SceneScriptBindingPathComponent: Equatable {
    case key(String)
    case index(Int)
}

struct SceneScriptBindingOwner: Equatable {
    enum Kind: Equatable { case scene, object, effect }
    let kind: Kind
    let objectIndex: Int?
    let objectID: Int?
}

struct SceneScriptSourceEvidenceIR {
    let source: String
    let owner: SceneScriptBindingOwner
    let targetPath: [SceneScriptBindingPathComponent]
    let wrapperKeys: [String]
}

struct SceneLayerDisplayScriptOwnership {
    let visible: Bool
    let alpha: Bool
}

struct SceneRenderDescriptor {
    struct Layer {
        let id: Int
        let layerIndex: Int
        let visible: Bool?
        var displayScriptOwnership: SceneLayerDisplayScriptOwnership?
    }
    var layers: [Layer]
}

@main
enum Harness {
    static func main() throws {
        let identity = """
        'use strict';
        /** The current property value is intentionally unchanged. */
        export function update(value) {
            return value;
        }
        """
        let base = SceneRenderDescriptor(layers: [
            .init(
                id: 187,
                layerIndex: 0,
                visible: true,
                displayScriptOwnership: .init(visible: true, alpha: true)
            ),
            .init(
                id: 188,
                layerIndex: 1,
                visible: false,
                displayScriptOwnership: .init(visible: true, alpha: false)
            ),
        ])
        func evidence(
            _ source: String = identity,
            kind: SceneScriptBindingOwner.Kind = .object,
            index: Int = 0,
            id: Int = 187,
            key: String = "visible",
            wrapper: [String] = ["script", "user", "value"]
        ) -> SceneScriptSourceEvidenceIR {
            .init(
                source: source,
                owner: .init(kind: kind, objectIndex: index, objectID: id),
                targetPath: [.key("objects"), .index(index), .key(key)],
                wrapperKeys: wrapper
            )
        }
        func ownership(_ item: SceneRenderDescriptor) -> [Bool] {
            let value = item.layers[0].displayScriptOwnership!
            return [value.visible, value.alpha]
        }
        let accepted = SceneIdentityDisplayScriptProjection.apply(
            to: base,
            sourceEvidence: [evidence()]
        )
        let renamed = SceneIdentityDisplayScriptProjection.apply(
            to: base,
            sourceEvidence: [evidence(identity.replacingOccurrences(of: "value", with: "current"))]
        )
        let cases: [String: SceneScriptSourceEvidenceIR] = [
            "mutated-return": evidence(identity.replacingOccurrences(of: "return value;", with: "return !value;")),
            "extra-statement": evidence(identity.replacingOccurrences(of: "return value;", with: "value = false; return value;")),
            "return-newline": evidence(identity.replacingOccurrences(of: "return value;", with: "return\nvalue;")),
            "wrong-owner": evidence(identity, kind: .effect),
            "wrong-index": evidence(identity, index: 1),
            "wrong-id": evidence(identity, id: 999),
            "wrong-target": evidence(identity, key: "alpha"),
            "extra-wrapper": evidence(identity, wrapper: ["extra", "script", "user", "value"]),
            "malformed-comment": evidence("/* unterminated"),
            "dynamic-code": evidence(identity + " Function('return false')();"),
        ]
        let rejected = cases.mapValues {
            ownership(SceneIdentityDisplayScriptProjection.apply(to: base, sourceEvidence: [$0]))
        }
        let payload: [String: Any] = [
            "accepted": ownership(accepted),
            "renamedArgumentAccepted": ownership(renamed),
            "authoredFalseAccepted": SceneIdentityDisplayScriptProjection.apply(
                to: base,
                sourceEvidence: [evidence(identity, index: 1, id: 188)]
            ).layers[1].displayScriptOwnership!.visible == false,
            "rejected": rejected,
        ]
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }
}
'''


class SceneIdentityDisplayScriptProjectionTests(unittest.TestCase):
    def test_exact_identity_only_releases_visible_ownership(self) -> None:
        with tempfile.TemporaryDirectory(prefix="mwx-identity-display-") as raw:
            directory = Path(raw)
            harness = directory / "Harness.swift"
            binary = directory / "identity-display"
            harness.write_text(HARNESS, encoding="utf-8")
            compile_result = subprocess.run(
                ["swiftc", *(str(path) for path in SOURCES), str(harness), "-o", str(binary)],
                capture_output=True,
                text=True,
            )
            self.assertEqual(compile_result.returncode, 0, compile_result.stderr)
            result = subprocess.run(
                [str(binary)], check=True, capture_output=True, text=True
            )
            payload = json.loads(result.stdout)

        self.assertEqual(payload["accepted"], [False, True])
        self.assertEqual(payload["renamedArgumentAccepted"], [False, True])
        self.assertTrue(payload["authoredFalseAccepted"])
        self.assertTrue(payload["rejected"])
        self.assertTrue(
            all(value == [True, True] for value in payload["rejected"].values())
        )


if __name__ == "__main__":
    unittest.main()
