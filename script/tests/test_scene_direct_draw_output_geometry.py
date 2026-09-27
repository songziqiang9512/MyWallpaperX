#!/usr/bin/env python3
"""Production carrier transforms and real Metal spatial coverage.

Synthetic fixed textures isolate geometry from animation/noise and shader
four-point mapping; original authored effects are covered by App replays.
"""
import json
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
SCENE = ROOT / 'MyWallpaperX/Core/SteamWorkshopScene'
HARNESS = r'''
import Foundation
import CoreGraphics
import Metal
import simd
struct SceneTextureUVTransform {
    let origin: SIMD2<Float>, xAxis: SIMD2<Float>, yAxis: SIMD2<Float>
    static let identity = Self(origin:.zero,xAxis:SIMD2(1,0),yAxis:SIMD2(0,1))
}
@main enum Harness {
    static func main() throws {
        guard let device = MTLCreateSystemDefaultDevice(),
              let pipeline = SceneImageLayerPipeline(device: device, blendMode: .additive),
              let queue = device.makeCommandQueue() else { fatalError("Metal unavailable") }
        var result: [String: Any] = [:]
        func model(_ canvas: SIMD2<Float>, _ world: simd_float4x4 = matrix_identity_float4x4,
                   _ parallax: SIMD2<Float> = .zero) -> simd_float4x4? {
            SceneDirectDrawOutputGeometry.modelMatrix(worldFrame: world,
                parallaxOffset: parallax, canvasSize: canvas)
        }
        let parent = SceneMatrix.translation(SIMD3<Float>(51,72,3)) * SceneMatrix.rotationZ(0.3)
        let local = SceneMatrix.translation(SIMD3<Float>(-11,13,0)) * SceneMatrix.rotationZ(-0.5)
            * SceneMatrix.scale(SIMD3<Float>(2,3,1))
        let world = parent * local
        let actual = model(SIMD2(400,200), world, SIMD2(7,-9))!
        var transformed = true
        for point in [SIMD4<Float>(0,0,0,1), SIMD4(0.25,0.125,0,1), SIMD4(-0.5,0.5,0,1)] {
            // Independent expected local point in authored height units. No
            // shader-dependent top translation may move the authored origin.
            let expected = world * SIMD4(point.x*200, -point.y*200, point.z, 1)
                + SIMD4<Float>(7,-9,0,0)
            transformed = transformed && simd_distance(actual * point, expected) < 0.001
        }
        result["authoredTransform"] = transformed
        var invalid = world; invalid.columns.2.z = .infinity
        result["invalidRejected"] = model(SIMD2(.nan,200)) == nil
            && model(SIMD2(400,0)) == nil && model(SIMD2(-1,200)) == nil
            && model(SIMD2(400,200),invalid) == nil
            && model(SIMD2(400,200),world,SIMD2(.nan,0)) == nil
        let projection = SceneMatrix.ortho(left:-200,right:200,bottom:-100,top:100,near:-1,far:1)
        let hugeModel = model(SIMD2(400,200),SceneMatrix.scale(SIMD3(1,5e16,1)))!
        result["oversizedRejected"] = SceneCaptureGeometryResolver.projectedPixelSize(
            layerMVP:projection * hugeModel, viewportSize:CGSize(width:400,height:200)) == nil
        let normalSize = SceneCaptureGeometryResolver.projectedPixelSize(
            layerMVP:projection * model(SIMD2(400,200))!, viewportSize:CGSize(width:400,height:200))!
        result["normalPixelSize"] = [Int(normalSize.width),Int(normalSize.height)]
        func render(canvas: SIMD2<Float>, shape: Int) -> [Int] {
            let width=Int(canvas.x), height=Int(canvas.y), n=128
            var rgba=[UInt8](repeating:0,count:n*n*4)
            for y in 0..<n { for x in 0..<n {
                let u=(Float(x)+0.5)/Float(n), v=(Float(y)+0.5)/Float(n)
                let active: Bool
                switch shape {
                case 0: active = simd_length(SIMD2(u-0.5,v-0.5)) < 0.2
                case 1: active = u > 0.1 && u < 0.3 && v > 0.1 && v < 0.3
                default: active = u > 0.4 && u < 0.6 && v > 0.2 && v < 0.8
                }
                if active { for c in 0..<4 { rgba[(y*n+x)*4+c]=255 } }
            } }
            let srcDesc=MTLTextureDescriptor.texture2DDescriptor(pixelFormat:.rgba8Unorm,width:n,height:n,mipmapped:false)
            srcDesc.storageMode = .shared
            let src=device.makeTexture(descriptor:srcDesc)!
            rgba.withUnsafeBytes { src.replace(region:MTLRegionMake2D(0,0,n,n),mipmapLevel:0,withBytes:$0.baseAddress!,bytesPerRow:n*4) }
            let dstDesc=MTLTextureDescriptor.texture2DDescriptor(pixelFormat:.bgra8Unorm,width:width,height:height,mipmapped:false)
            dstDesc.usage = [.renderTarget]; dstDesc.storageMode = .shared
            let dst=device.makeTexture(descriptor:dstDesc)!
            let pass=MTLRenderPassDescriptor(); pass.colorAttachments[0].texture=dst
            pass.colorAttachments[0].loadAction = .clear; pass.colorAttachments[0].storeAction = .store
            pass.colorAttachments[0].clearColor=MTLClearColorMake(0,0,0,0)
            let cb=queue.makeCommandBuffer()!, encoder=cb.makeRenderCommandEncoder(descriptor:pass)!
            let projection=SceneMatrix.ortho(left:-canvas.x/2,right:canvas.x/2,bottom:-canvas.y/2,top:canvas.y/2,near:-1,far:1)
            let uniforms=SceneLayerFragmentUniforms(time:0,alpha:1,dependencyBlendMode:0,usesDependencyBlend:0,
                cursorUV:.zero,sourceSampling:SIMD2(2,0),tint:SIMD4(repeating:1),
                textureFrame0:SIMD4(0,0,1,0),textureFrame1:SIMD4(0,1,0,0))
            pipeline.bind(encoder:encoder)
            pipeline.drawLayer(texture:src,mvp:projection * model(canvas)!,uniforms:uniforms,encoder:encoder)
            encoder.endEncoding(); cb.commit(); cb.waitUntilCompleted()
            precondition(cb.status == .completed && cb.error == nil)
            var pixels=[UInt8](repeating:0,count:width*height*4)
            pixels.withUnsafeMutableBytes { dst.getBytes($0.baseAddress!,bytesPerRow:width*4,from:MTLRegionMake2D(0,0,width,height),mipmapLevel:0) }
            var xs=[Int](), ys=[Int]()
            for y in 0..<height { for x in 0..<width where pixels[(y*width+x)*4] > 127 { xs.append(x);ys.append(y) } }
            return [xs.min()!,ys.min()!,xs.max()!+1,ys.max()!+1]
        }
        for (name,canvas) in [("wide",SIMD2<Float>(400,200)),("square",SIMD2<Float>(200,200)),("portrait",SIMD2<Float>(200,400))] {
            result[name]=render(canvas:canvas,shape:0)
        }
        result["cornerMarker"]=render(canvas:SIMD2(400,200),shape:1)
        result["linearMarker"]=render(canvas:SIMD2(400,200),shape:2)
        print(String(data:try JSONSerialization.data(withJSONObject:result),encoding:.utf8)!)
    }
}
'''

class SceneDirectDrawOutputGeometryTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        with tempfile.TemporaryDirectory(prefix='mwx-square-gpu-') as directory:
            p=Path(directory); (p/'Main.swift').write_text(HARNESS)
            sources=['Rendering/Geometry/SceneMatrix.swift','Rendering/Geometry/SceneDirectDrawOutputGeometry.swift',
                     'Rendering/Metal/SceneMetalPipeline.swift','Diagnostics/ScenePerformanceCounterHub.swift',
                     'Rendering/Geometry/SceneCaptureGeometry.swift','Rendering/Composition/SceneUtilityLayer.swift']
            commands=[['xcrun','-sdk','macosx','metal','-c',str(SCENE/'Rendering/Composition/SceneImageLayer.metal'),'-o',str(p/'image.air')],
                      ['xcrun','-sdk','macosx','metallib',str(p/'image.air'),'-o',str(p/'default.metallib')],
                      ['swiftc',*[str(SCENE/s) for s in sources],str(p/'Main.swift'),'-o',str(p/'run')]]
            for command in commands:
                run=subprocess.run(command,capture_output=True,text=True,timeout=120)
                if run.returncode: raise RuntimeError(run.stderr)
            run=subprocess.run([str(p/'run')],capture_output=True,text=True,check=True,timeout=30)
            cls.result=json.loads(run.stdout)

    def test_circle_keeps_equal_units_and_height_based_diameter(self):
        for name,w,h in [('wide',400,200),('square',200,200),('portrait',200,400)]:
            x0,y0,x1,y1=self.result[name]
            self.assertAlmostEqual(x1-x0,y1-y0,delta=1)
            self.assertAlmostEqual(x1-x0,0.4*h,delta=3)
            self.assertAlmostEqual((x0+x1)/2,w/2,delta=1)
            self.assertAlmostEqual((y0+y1)/2,h/2,delta=1)

    def test_fixed_content_has_no_top_compensation(self):
        for name,expected in [('cornerMarker',[120,140,160,180]),('linearMarker',[180,40,220,160])]:
            for value,target in zip(self.result[name],expected):
                self.assertAlmostEqual(value,target,delta=2,msg=name)

    def test_authored_transforms_and_invalid_inputs(self):
        self.assertTrue(self.result['authoredTransform'])
        self.assertTrue(self.result['invalidRejected'])
        self.assertTrue(self.result['oversizedRejected'])
        self.assertEqual(self.result['normalPixelSize'],[200,200])

if __name__ == '__main__': unittest.main()
