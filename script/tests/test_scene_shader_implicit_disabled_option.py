from pathlib import Path
import subprocess
import tempfile
import unittest


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
SWIFT_SOURCES = [
    "MyWallpaperX/Core/SteamWorkshopScene/Format/SceneJSONValue.swift",
    "MyWallpaperX/Core/SteamWorkshopScene/Resources/Textures/SceneTextureSampling.swift",
    "MyWallpaperX/Core/SteamWorkshopScene/Compilation/ShaderContract/SceneShaderLegacyAnnotationJSON.swift",
    "MyWallpaperX/Core/SteamWorkshopScene/Compilation/ShaderContract/SceneShaderContract.swift",
    "MyWallpaperX/Core/SteamWorkshopScene/Compilation/ShaderContract/SceneShaderSourceGraph.swift",
    "MyWallpaperX/Core/SteamWorkshopScene/Compilation/ShaderPreparation/SceneShaderVariantEnvironment.swift",
    "MyWallpaperX/Core/SteamWorkshopScene/Compilation/ShaderPreparation/SceneShaderVariantEnvironment+HostFacts.swift",
    "MyWallpaperX/Core/SteamWorkshopScene/Compilation/ShaderPreparation/SceneShaderVariantEnvironment+ModuleResolution.swift",
    "MyWallpaperX/Core/SteamWorkshopScene/Compilation/ShaderPreparation/SceneShaderVariantResolver.swift",
    "MyWallpaperX/Core/SteamWorkshopScene/Compilation/ShaderPreparation/SceneShaderVariantResolver+Schema.swift",
    "MyWallpaperX/Core/SteamWorkshopScene/Compilation/ShaderPreparation/SceneShaderVariantResolver+SchemaSeed.swift",
    "MyWallpaperX/Core/SteamWorkshopScene/Compilation/ShaderPreparation/SceneShaderVariantResolver+DisabledCombo.swift",
    "MyWallpaperX/Core/SteamWorkshopScene/Compilation/ShaderPreparation/SceneShaderVariantResolver+TextureFormat.swift",
    "MyWallpaperX/Core/SteamWorkshopScene/Compilation/ShaderPreparation/SceneShaderVariantResolver+ImplicitDisabledOptionAdmission.swift",
    "MyWallpaperX/Core/SteamWorkshopScene/Compilation/ShaderPreparation/SceneShaderDirective.swift",
    "MyWallpaperX/Core/SteamWorkshopScene/Compilation/ShaderPreparation/SceneShaderMacroExpansion.swift",
    "MyWallpaperX/Core/SteamWorkshopScene/Compilation/ShaderPreparation/SceneShaderMalformedMetadataAdmission.swift",
    "MyWallpaperX/Core/SteamWorkshopScene/Compilation/ShaderPreparation/SceneShaderPreprocessor.swift",
    "MyWallpaperX/Core/SteamWorkshopScene/Compilation/ShaderPreparation/SceneShaderPreprocessor+Directive.swift",
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
