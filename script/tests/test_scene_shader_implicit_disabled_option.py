from pathlib import Path
import subprocess
import tempfile
import unittest


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
SWIFT_SOURCES = [
    "MyWallpaperX/Core/SteamWorkshopScene/Format/SceneJSONValue.swift",
    "MyWallpaperX/Core/SteamWorkshopScene/Resources/SceneTextureSampling.swift",
    "MyWallpaperX/Core/SteamWorkshopScene/RenderGraph/ShaderContract/SceneShaderLegacyAnnotationJSON.swift",
    "MyWallpaperX/Core/SteamWorkshopScene/RenderGraph/ShaderContract/SceneShaderContract.swift",
    "MyWallpaperX/Core/SteamWorkshopScene/RenderGraph/ShaderContract/SceneShaderSourceGraph.swift",
    "MyWallpaperX/Core/SteamWorkshopScene/RenderGraph/ShaderPreparation/SceneShaderVariantEnvironment.swift",
    "MyWallpaperX/Core/SteamWorkshopScene/RenderGraph/ShaderPreparation/SceneShaderVariantEnvironment+HostFacts.swift",
    "MyWallpaperX/Core/SteamWorkshopScene/RenderGraph/ShaderPreparation/SceneShaderVariantEnvironment+ModuleResolution.swift",
    "MyWallpaperX/Core/SteamWorkshopScene/RenderGraph/ShaderPreparation/SceneShaderVariantResolver.swift",
    "MyWallpaperX/Core/SteamWorkshopScene/RenderGraph/ShaderPreparation/SceneShaderVariantResolver+Schema.swift",
    "MyWallpaperX/Core/SteamWorkshopScene/RenderGraph/ShaderPreparation/SceneShaderVariantResolver+SchemaSeed.swift",
    "MyWallpaperX/Core/SteamWorkshopScene/RenderGraph/ShaderPreparation/SceneShaderVariantResolver+DisabledCombo.swift",
    "MyWallpaperX/Core/SteamWorkshopScene/RenderGraph/ShaderPreparation/SceneShaderVariantResolver+TextureFormat.swift",
    "MyWallpaperX/Core/SteamWorkshopScene/RenderGraph/ShaderPreparation/SceneShaderVariantResolver+ImplicitDisabledOptionAdmission.swift",
    "MyWallpaperX/Core/SteamWorkshopScene/RenderGraph/ShaderPreparation/SceneShaderDirective.swift",
    "MyWallpaperX/Core/SteamWorkshopScene/RenderGraph/ShaderPreparation/SceneShaderMacroExpansion.swift",
    "MyWallpaperX/Core/SteamWorkshopScene/RenderGraph/ShaderPreparation/SceneShaderMalformedMetadataAdmission.swift",
    "MyWallpaperX/Core/SteamWorkshopScene/RenderGraph/ShaderPreparation/SceneShaderPreprocessor.swift",
    "MyWallpaperX/Core/SteamWorkshopScene/RenderGraph/ShaderPreparation/SceneShaderPreprocessor+Directive.swift",
    "script/tests/fixtures/SceneShaderImplicitDisabledOptionHarness.swift",
]


class SceneShaderImplicitDisabledOptionTests(unittest.TestCase):
    def test_focused_swift_harness(self) -> None:
        with tempfile.TemporaryDirectory(
            prefix="mwx-implicit-disabled-option-"
        ) as temporary_directory:
            executable = Path(temporary_directory) / "harness"
            compilation = subprocess.run(
                [
                    "swiftc",
                    "-o",
                    str(executable),
                    *[str(REPOSITORY_ROOT / path) for path in SWIFT_SOURCES],
                ],
                cwd=REPOSITORY_ROOT,
                capture_output=True,
                text=True,
                check=False,
            )
            self.assertEqual(
                compilation.returncode,
                0,
                compilation.stdout + compilation.stderr,
            )
            execution = subprocess.run(
                [str(executable)],
                cwd=REPOSITORY_ROOT,
                capture_output=True,
                text=True,
                check=False,
            )
            self.assertEqual(
                execution.returncode,
                0,
                execution.stdout + execution.stderr,
            )
            self.assertIn(
                "scene_shader_implicit_disabled_option_harness: PASS",
                execution.stdout,
            )


if __name__ == "__main__":
    unittest.main()
