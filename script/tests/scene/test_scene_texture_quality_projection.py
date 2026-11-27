"""Native CPU checks for the ordinary authored-mip quality decision."""

from pathlib import Path
import platform
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[3]
SOURCE = ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Resources/Textures/SceneOrdinaryImageMipSelection.swift"

CAPTURE_POLICY = SOURCE.parents[2] / "Rendering/Targets/SceneOffscreenResolutionPolicy.swift"

HARNESS = r'''
import Foundation

@main
enum Harness {
    static func main() {
        let world = SceneAutomaticTextureProjection.worldExtent(size: [6528, 4420], scale: nil)!
        let authored = [(6528, 4420), (3264, 2210), (1632, 1105), (816, 552), (408, 276)]
        let cover = 3024.0 / 6528
        let minimum = SceneAutomaticTextureProjection.minimumExtent(worldExtent: world, coverScale: cover)!
        precondition(minimum == SIMD2(3024, 2048))
        precondition(SceneOrdinaryImageMipSelection.minimumExtent(minimum)
            .baseIndex(in: authored, maximumSingleLevelDimension: 4096) == 1)
        precondition(SceneOrdinaryImageMipSelection.maximumLongEdge(2048)
            .baseIndex(in: authored, maximumSingleLevelDimension: 4096) == 2)

        let source = SceneAutomaticTextureProjection.Source(worldExtent: world, layerIDs: [54])
        let coverage = source.maximumCoverScale(forMappedSize: CGSize(width: 3264, height: 2210))
        precondition(cover < coverage)
        precondition(coverage == 0.5)
        let larger = 3265.0 / 6528
        precondition(larger > coverage)
        let grown = SceneAutomaticTextureProjection.minimumExtent(worldExtent: world, coverScale: larger)!
        precondition(SceneOrdinaryImageMipSelection.minimumExtent(grown)
            .baseIndex(in: authored, maximumSingleLevelDimension: 4096) == 0)

        let odd = [(4031, 2035), (2015, 1017), (1007, 508), (503, 254)]
        let wide = SceneAutomaticTextureProjection.worldExtent(size: [1000, 910], scale: [-2, 1, 1])!
        let tall = SceneAutomaticTextureProjection.worldExtent(size: [900, 1018], scale: nil)!
        var aliases = SceneAutomaticTextureProjection.Source(worldExtent: wide, layerIDs: [71])
        aliases.include(layerID: 901, worldExtent: tall)
        let sharedMinimum = SceneAutomaticTextureProjection.minimumExtent(worldExtent: aliases.worldExtent, coverScale: 1)!
        precondition(aliases.layerIDs == [71, 901] && sharedMinimum == SIMD2(2000, 1018))
        precondition(SceneOrdinaryImageMipSelection.minimumExtent(sharedMinimum)
            .baseIndex(in: odd, maximumSingleLevelDimension: 4096) == 0)
        precondition(SceneOrdinaryImageMipSelection.minimumExtent(SIMD2(2000, 1017))
            .baseIndex(in: odd, maximumSingleLevelDimension: 4096) == 1)
        var local = SceneAutomaticTextureProjection.Source(worldExtent: wide, layerIDs: [71])
        local.include(layerID: 901, worldExtent: tall, capture: SIMD2(2015, 1017))
        local.include(layerID: 902, worldExtent: wide, capture: SIMD2(1900, 1016))
        let smallWindow = local.minimumExtent(for: 0.5)!
        precondition(smallWindow == SIMD2(2015, 1017))
        precondition(SceneOrdinaryImageMipSelection.minimumExtent(smallWindow)
            .baseIndex(in: odd, maximumSingleLevelDimension: 4096) == 1)
        let enlarged = local.minimumExtent(for: 1)!
        precondition(enlarged == SIMD2(2015, 1018))
        precondition(SceneOrdinaryImageMipSelection.minimumExtent(enlarged)
            .baseIndex(in: odd, maximumSingleLevelDimension: 4096) == 0)
        let smallDrawable = SceneOrdinaryImageMipSelection.minimumExtent(SIMD2(1000, 500))
        precondition(smallDrawable.baseIndex(in: [(5000, 2500)], maximumSingleLevelDimension: 4096) == 0)
        precondition(smallDrawable.baseIndex(in: [(10000, 5000), (5000, 2500)],
                                            maximumSingleLevelDimension: 4096) == 0)
        precondition(SceneOrdinaryImageMipSelection.maximumLongEdge(5000)
            .baseIndex(in: [(10000, 5000), (5000, 2500)], maximumSingleLevelDimension: 4096) == 0)
        precondition(smallDrawable.baseIndex(in: [(8192, 4096), (4096, 2048)],
                                            maximumSingleLevelDimension: 4096) == 1)

        let maximumHeaderDimension = CGFloat(Float(UInt32.max))
        precondition(SceneOffscreenResolutionPolicy.preferredImageCaptureExtent(
            CGSize(width: maximumHeaderDimension, height: maximumHeaderDimension)) == nil)
        precondition(SceneOffscreenResolutionPolicy.preferredImageCaptureExtent(
            CGSize(width: 2560, height: 1465)) == SIMD2(2560, 1465))
        precondition(SceneAutomaticTextureProjection.worldExtent(size: [100, 0], scale: nil) == nil)
        precondition(SceneAutomaticTextureProjection.minimumExtent(worldExtent: world, coverScale: .infinity) == nil)
    }
}
'''


@unittest.skipUnless(platform.system() == "Darwin", "requires the native Swift toolchain")
class SceneTextureQualityProjectionTests(unittest.TestCase):
    def test_author_mip_follows_drawable_and_shared_axis_requirement(self):
        with tempfile.TemporaryDirectory(prefix="mwx-scene-texture-projection-") as directory:
            temporary = Path(directory)
            harness = temporary / "Harness.swift"
            harness.write_text(HARNESS)
            binary = temporary / "checks"
            build = subprocess.run(
                ["xcrun", "swiftc", str(SOURCE), str(CAPTURE_POLICY), str(harness), "-module-cache-path",
                 str(temporary / "modules"), "-o", str(binary)],
                capture_output=True, text=True, timeout=45,
            )
            self.assertEqual(build.returncode, 0, build.stderr)
            result = subprocess.run([str(binary)], capture_output=True, text=True, timeout=10)
            self.assertEqual(result.returncode, 0, result.stderr)


if __name__ == "__main__":
    unittest.main()
