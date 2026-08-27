#!/usr/bin/env python3

from __future__ import annotations

import json
import os
from pathlib import Path
import runpy
import shutil
import subprocess
import tempfile
import unittest


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
BASE_FIXTURE = runpy.run_path(
    str(Path(__file__).with_name("test_scene_xray_scalar_owner_admission.py"))
)
SCENE_ROOT = BASE_FIXTURE["SCENE_ROOT"]
STOCK_ROOT = BASE_FIXTURE["STOCK_ROOT"]
SWIFT_SOURCES = BASE_FIXTURE["SWIFT_SOURCES"]
X_RAY_SUPPORT_SOURCE = BASE_FIXTURE["X_RAY_SUPPORT_SOURCE"]
PRODUCT_COMPILER_SOURCE = BASE_FIXTURE["product_xray_compiler_source"]
BASE_HARNESS_PREFIX = BASE_FIXTURE["HARNESS"].split("@main", 1)[0]


PROVIDER_HARNESS = BASE_HARNESS_PREFIX + r'''
private let externalProviderLayerID = 41

private enum ProviderContract: Equatable {
    case primary
    case wrongPass
    case wrongSlot
    case secondary
}

private func providerDescriptor(
    _ providerContract: ProviderContract
) -> SceneRenderDescriptor {
    let providerPath: String
    switch providerContract {
    case .secondary:
        providerPath = "_rt_imageLayerComposite_\(externalProviderLayerID)_b"
    case .primary, .wrongPass, .wrongSlot:
        providerPath = "_rt_imageLayerComposite_\(externalProviderLayerID)_a"
    }
    let consumerPassIndex = providerContract == .wrongPass ? 1 : 0
    let consumerSlots: [String?] = providerContract == .wrongSlot
        ? [nil, "textures/blend.jpg", providerPath]
        : [nil, providerPath, "particle/halo_6"]
    let consumerPass = SceneRenderDescriptor.EffectDescriptor.PassDescriptor(
        passIndex: consumerPassIndex,
        texturePaths: consumerSlots.compactMap { $0 },
        textureSlots: consumerSlots,
        userTextureInputs: [],
        combos: ["BLENDMODE": 0],
        constantShaderValues: [
            "size": value(0.25),
            "multiply": value(1.5),
        ]
    )
    let providerPass = SceneRenderDescriptor.EffectDescriptor.PassDescriptor(
        passIndex: 0,
        texturePaths: ["textures/provider-source.jpg"],
        textureSlots: ["textures/provider-source.jpg"],
        userTextureInputs: [],
        combos: [:],
        constantShaderValues: [:]
    )
    let provider = SceneRenderDescriptor.Layer(
        id: externalProviderLayerID,
        contentKind: "image",
        effects: [.init(
            id: "provider-effect",
            file: "effects/tint/effect.json",
            visible: true,
            passes: [providerPass]
        )]
    )
    let consumer = SceneRenderDescriptor.Layer(
        id: layerID,
        contentKind: "image",
        dependencyLayerIDs: [externalProviderLayerID],
        effects: [.init(
            id: effectKey.descriptorID,
            file: "effects/xray/effect.json",
            visible: true,
            passes: [consumerPass]
        )]
    )
    return .init(
        layers: [provider, consumer],
        renderOrderLayerIDs: [externalProviderLayerID, layerID],
        materialPasses: [.init(
            id: "materials/effects/xray.json#0",
            materialPath: "materials/effects/xray.json",
            passIndex: 0,
            shaderPath: "effects/xray",
            texturePaths: [],
            textureSlots: [],
            userTextureInputs: [],
            combos: [:],
            constantShaderValues: [:],
            userShaderValues: [:],
            blending: "normal",
            depthTest: "disabled",
            depthWrite: "disabled",
            cullMode: "nocull",
            alphaWriting: nil
        )]
    )
}

private func providerCompileInput(
    root: URL,
    providerContract: ProviderContract
) -> SceneEffectStageCompileInput {
    SceneEffectStageCompileInput(
        stageGraph: graph(),
        effectKey: effectKey,
        definitionPath: "effects/xray/effect.json",
        inputRole: .layerSource,
        descriptor: providerDescriptor(providerContract),
        shaderContracts: [contract(root)],
        userPropertyProducers: [],
        activeEffectLocalDirectBoolVisibilityTargets: [],
        frameDrivenEffectVisibilityOwners: []
    )
}

private func providerResult(
    root: URL,
    providerContract: ProviderContract
) -> [String: Any] {
    let input = providerCompileInput(
        root: root,
        providerContract: providerContract
    )
    let product = productCompilerResult(input)
    return [
        "revoked": SceneEffectStageXRayScalarOwnerAdmission
            .acceptsDedicatedRevocation(effectKey: effectKey, input: input),
        "productOutcome": product.outcome,
        "productDetail": product.detail,
        "providerPassCount": input.descriptor.layers.first?.effects.first?
            .passes.count ?? 0,
    ]
}

@main
private enum XRayVisibleGraphOutputOwnerHarness {
    static func main() throws {
        let stock = URL(
            fileURLWithPath: CommandLine.arguments[1],
            isDirectory: true
        )
        let result: [String: Any] = [
            "primary": providerResult(root: stock, providerContract: .primary),
            "wrongPass": providerResult(
                root: stock,
                providerContract: .wrongPass
            ),
            "wrongSlot": providerResult(
                root: stock,
                providerContract: .wrongSlot
            ),
            "secondary": providerResult(
                root: stock,
                providerContract: .secondary
            ),
        ]
        let data = try JSONSerialization.data(
            withJSONObject: result,
            options: [.sortedKeys]
        )
        print(String(decoding: data, as: UTF8.self))
    }
}
'''


@unittest.skipUnless(shutil.which("swiftc"), "swiftc is required")
class SceneXRayVisibleGraphOutputOwnerTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.temporary_directory = tempfile.TemporaryDirectory(
            prefix="mwx-xray-visible-graph-owner-"
        )
        root = Path(cls.temporary_directory.name)
        support = root / "Support.swift"
        compiler = root / "ProductXRayCompiler.swift"
        harness = root / "Harness.swift"
        support.write_text(BASE_FIXTURE["SUPPORT"], encoding="utf-8")
        compiler.write_text(PRODUCT_COMPILER_SOURCE(), encoding="utf-8")
        harness.write_text(PROVIDER_HARNESS, encoding="utf-8")

        cls.stock = root / "stock"
        (cls.stock / "shaders/effects").mkdir(parents=True)
        shutil.copy2(
            STOCK_ROOT / "effects/xray/shaders/effects/xray.vert",
            cls.stock / "shaders/effects/xray.vert",
        )
        shutil.copy2(
            STOCK_ROOT / "effects/xray/shaders/effects/xray.frag",
            cls.stock / "shaders/effects/xray.frag",
        )
        shutil.copy2(
            STOCK_ROOT / "shaders/common_blending.h",
            cls.stock / "shaders/common_blending.h",
        )

        cls.binary = root / "xray-visible-graph-owner"
        environment = os.environ.copy()
        environment["CLANG_MODULE_CACHE_PATH"] = str(root / "clang-cache")
        environment["SWIFT_MODULECACHE_PATH"] = str(root / "swift-cache")
        compilation = subprocess.run(
            [
                "xcrun",
                "--sdk",
                "macosx",
                "swiftc",
                "-parse-as-library",
                str(support),
                str(X_RAY_SUPPORT_SOURCE),
                *(str(path) for path in SWIFT_SOURCES),
                str(compiler),
                str(harness),
                "-framework",
                "Metal",
                "-framework",
                "CoreGraphics",
                "-framework",
                "ImageIO",
                "-module-cache-path",
                str(root / "module-cache"),
                "-o",
                str(cls.binary),
            ],
            cwd=REPOSITORY_ROOT,
            env=environment,
            capture_output=True,
            text=True,
        )
        if compilation.returncode != 0:
            raise RuntimeError(compilation.stderr)

    @classmethod
    def tearDownClass(cls) -> None:
        cls.temporary_directory.cleanup()

    def run_harness(self, *, route_disabled: bool = False) -> dict:
        environment = os.environ.copy()
        if route_disabled:
            environment["MWX_SCENE_NAMED_PROVIDER_ROUTE"] = "disable-generic"
        else:
            environment.pop("MWX_SCENE_NAMED_PROVIDER_ROUTE", None)
        completed = subprocess.run(
            [str(self.binary), str(self.stock)],
            cwd=REPOSITORY_ROOT,
            env=environment,
            check=True,
            capture_output=True,
            text=True,
        )
        return json.loads(completed.stdout)

    def test_primary_pass_zero_slot_one_revokes_the_incumbent(self) -> None:
        result = self.run_harness()["primary"]
        self.assertEqual(
            result,
            {
                "revoked": True,
                "productOutcome": "rejected",
                "productDetail": (
                    "current-stock-scalar-owner-revoked-to-material-program"
                ),
                "providerPassCount": 1,
            },
        )

    def test_wrong_pass_slot_and_secondary_retain_the_incumbent(self) -> None:
        result = self.run_harness()
        expected_outcomes = {
            "wrongPass": "rejected",
            "wrongSlot": "accepted",
            "secondary": "accepted",
        }
        for key, outcome in expected_outcomes.items():
            with self.subTest(key=key):
                self.assertFalse(result[key]["revoked"], result)
                self.assertEqual(result[key]["productOutcome"], outcome, result)

    def test_legacy_named_provider_disable_cannot_restore_incumbent(self) -> None:
        result = self.run_harness(route_disabled=True)["primary"]
        self.assertTrue(result["revoked"], result)
        self.assertEqual(result["productOutcome"], "rejected", result)
        self.assertEqual(
            result["productDetail"],
            "current-stock-scalar-owner-revoked-to-material-program",
            result,
        )


if __name__ == "__main__":
    unittest.main()
