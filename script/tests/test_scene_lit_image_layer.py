#!/usr/bin/env python3
"""Real Metal base-capture/composition behavior for bounded 2D material lighting."""
import json
from copy import deepcopy
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from script.tests import test_scene_texture_candidate as texture_fixture
from script.tests.fixtures import scene_reflection_oracle as reflection_oracle

ROOT = Path(__file__).resolve().parents[2]
SCENE = ROOT / 'MyWallpaperX/Core/SteamWorkshopScene'

def reflection_vectors():
    vectors = reflection_oracle.freeze()
    # Independent finite arithmetic counterexample: 4 * Float32(1e38)
    # overflows Float32, while multiplication by Float32(1e-37) yields ~40.
    # The zero environment isolates the original reflection-only base term.
    vector = deepcopy(vectors['gpu_numerical'][0]['input'])
    vector.update(name='finite-original-base-intermediate-overflow', source=[4,4,4,1],
                  environment=[0,0,0,1], tint=[1e38]*3, opacity=1e-37)
    expected = reflection_oracle.surface(vector)
    expected['radiance_tolerance'] = [2*reflection_oracle.half_ulp(x) for x in expected['half_rgba'][:3]]
    assert 39.9 < expected['half_rgba'][0] < 40.1
    vectors['gpu_numerical'].append(dict(input=vector, expected=expected))
    return vectors

REFLECTION_HARNESS = r'''
import Foundation
import Metal
import simd
@main enum ReflectionHarness {
    typealias Capture = SceneBaseMaterialLitCapturePayload
    // A typed publication-unit fixture. These numerical tests deliberately do
    // not assert that this identity came from the runtime completion owner.
    static let sourceReceipt = SceneCompletedColorSourceIdentity(frameIndex: 41,
        frameEpoch: 5, executionEpoch: 2,
        commandBufferObservationID: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
        allocationGeneration: 9,
        resetEpoch: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!)
    static func texture(_ device:MTLDevice, width:Int=1,height:Int=1,
                        format:MTLPixelFormat = .rgba16Float,mips:Bool=false,values:[Float]?=nil)->MTLTexture {
        let d=MTLTextureDescriptor.texture2DDescriptor(pixelFormat:format,width:width,height:height,mipmapped:mips)
        d.storageMode = .shared;d.usage=[.renderTarget,.shaderRead]
        let t=device.makeTexture(descriptor:d)!
        if let values {
            let data=values.map(Float16.init)
            data.withUnsafeBytes{t.replace(region:MTLRegionMake2D(0,0,width,height),mipmapLevel:0,withBytes:$0.baseAddress!,bytesPerRow:width*8)}
        }
        return t
    }
    static func normal(_ device:MTLDevice,_ spec:[String:Any])->Capture.TextureInput {
        let isBC=spec["format"] as! String == "bc5-rg-snorm"
        let d=MTLTextureDescriptor.texture2DDescriptor(pixelFormat:isBC ? .bc5_rgSnorm : .rgba8Unorm,width:4,height:4,mipmapped:false)
        d.storageMode = .shared;d.usage = .shaderRead
        let t=device.makeTexture(descriptor:d)!
        let bytes:[UInt8]
        if isBC {
            let xy=spec["endpoints"] as! [Int]
            bytes=xy.flatMap { [UInt8(bitPattern:Int8($0)),UInt8(bitPattern:Int8($0)),0,0,0,0,0,0] }
        } else { bytes=Array(repeating:(spec["texel"] as! [Int]).map(UInt8.init),count:16).flatMap{$0} }
        bytes.withUnsafeBytes{t.replace(region:MTLRegionMake2D(0,0,4,4),mipmapLevel:0,withBytes:$0.baseAddress!,bytesPerRow:16)}
        let size=CGSize(width:4,height:4)
        let c=SceneTextureCandidate(texture:t,identity:.builtIn(name:"self-authored-f5-normal"),generation:.immutable(revision:1),
            purpose:.normal,content:.data,physicalSize:size,mappedSize:size,uvTransform:.identity,sampling:.directImageFallback)
        let input=Capture.TextureInput.resolve(c)
        precondition(input.status == "ready")
        return input
    }
    static func map(_ device:MTLDevice,_ rgba:[Int])->Capture.TextureInput {
        let d=MTLTextureDescriptor.texture2DDescriptor(pixelFormat:.rgba8Unorm,width:1,height:1,mipmapped:false)
        d.storageMode = .shared;d.usage = .shaderRead
        let t=device.makeTexture(descriptor:d)!,bytes=rgba.map(UInt8.init)
        bytes.withUnsafeBytes{t.replace(region:MTLRegionMake2D(0,0,1,1),mipmapLevel:0,withBytes:$0.baseAddress!,bytesPerRow:4)}
        let size=CGSize(width:1,height:1)
        let c=SceneTextureCandidate(texture:t,identity:.builtIn(name:"self-authored-f5-map"),generation:.immutable(revision:1),
            purpose:.mask,content:.data,physicalSize:size,mappedSize:size,uvTransform:.identity,sampling:.init(texFlags:4<<20))
        let input=Capture.TextureInput.resolve(c,kind:.materialMap)
        precondition(input.status == "ready")
        return input
    }
    static func floats(_ v:[String:Any],_ key:String)->[Float] { (v[key] as! [NSNumber]).map(\.floatValue) }
    static func number(_ v:[String:Any],_ key:String)->Float { (v[key] as! NSNumber).floatValue }
    static func pixels(_ t:MTLTexture)->[Float] {
        if t.pixelFormat == .rgba32Float {
            var data=[Float](repeating:0,count:4)
            data.withUnsafeMutableBytes{t.getBytes($0.baseAddress!,bytesPerRow:16,from:MTLRegionMake2D(0,0,1,1),mipmapLevel:0)}
            return data
        }
        var data=[Float16](repeating:0,count:4)
        data.withUnsafeMutableBytes{t.getBytes($0.baseAddress!,bytesPerRow:8,from:MTLRegionMake2D(0,0,1,1),mipmapLevel:0)}
        return data.map(Float.init)
    }

    // Measurement control: independent hardware filtering at the frozen
    // oracle coordinate. This contains no product projection/normal formula.
    static func sampleControl(_ device: MTLDevice, _ queue: MTLCommandQueue,
                              texture: MTLTexture, uv: [Float]) throws -> [Float] {
        let code = """
        #include <metal_stdlib>
        using namespace metal;
        kernel void sampleControl(texture2d<float> t [[texture(0)]],
                                  constant float2& uv [[buffer(0)]],
                                  device float4* output [[buffer(1)]]) {
            constexpr sampler s(coord::normalized,address::clamp_to_edge,
                                filter::linear,mip_filter::linear);
            output[0] = t.sample(s,uv,level(0));
        }
        """
        let library = try device.makeLibrary(source: code, options: nil)
        let pipeline = try device.makeComputePipelineState(function: library.makeFunction(name: "sampleControl")!)
        var coordinate = SIMD2<Float>(uv)
        let output = device.makeBuffer(length: 16)!, cb = queue.makeCommandBuffer()!
        let encoder = cb.makeComputeCommandEncoder()!
        encoder.setComputePipelineState(pipeline); encoder.setTexture(texture, index: 0)
        encoder.setBytes(&coordinate, length: 8, index: 0); encoder.setBuffer(output, offset: 0, index: 1)
        encoder.dispatchThreads(MTLSizeMake(1,1,1), threadsPerThreadgroup: MTLSizeMake(1,1,1))
        encoder.endEncoding(); cb.commit(); cb.waitUntilCompleted()
        precondition(cb.status == .completed && cb.error == nil)
        let value = output.contents().bindMemory(to: SIMD4<Float>.self, capacity: 1).pointee
        return [value.x,value.y,value.z,value.w]
    }

    static func main() throws {
        let device=MTLCreateSystemDefaultDevice()!,queue=device.makeCommandQueue()!
        let library=try device.makeLibrary(URL:URL(fileURLWithPath:CommandLine.arguments[1]))
        let report=try JSONSerialization.jsonObject(with:Data(contentsOf:URL(fileURLWithPath:CommandLine.arguments[2]))) as! [String:Any]
        let base=SceneImageLayerPipeline(device:device,pixelFormat:.rgba16Float,library:library)!
        let lit=SceneLitImageLayerPipeline(device:device,pixelFormat:.rgba16Float,library:library)!
        var rows:[[String:Any]]=[]
        for row in report["gpu_numerical"] as! [[String:Any]] {
            let v=row["input"] as! [String:Any]
            let source=texture(device,values:floats(v,"source")),target=texture(device)
            let envValues=Array(repeating:floats(v,"environment"),count:13*7).flatMap{$0}
            let environment=texture(device,width:13,height:7,mips:true,values:envValues)
            let cb=queue.makeCommandBuffer()!
            let blit=cb.makeBlitCommandEncoder()!;blit.generateMipmaps(for:environment);blit.endEncoding()
            var packed=Capture.packLights(pointLights:[],spotLights:[],ambient:.zero,material:SIMD2(number(v,"metallic"),0),
                view:SIMD4(SIMD3(floats(v,"view")),0),layerModelMatrix:matrix_identity_float4x4,normalModelMatrix:matrix_identity_float4x4)!
            packed.reflection=SIMD4(number(v,"strength"),4,0,0)
            if let original=v["original_radiance"] as? [NSNumber] {
                let stored=floats(v,"source").map(Float16.init).map(Float.init)
                packed.ambientHasNormal=SIMD4(original[0].floatValue/stored[0],original[1].floatValue/stored[1],original[2].floatValue/stored[2],0)
                packed.reflection.w=1
            }
            var attempts=0
            let payload=Capture(pipeline:lit,lights:packed,normal:normal(device,v["normal_texel"] as! [String:Any]),
                materialMap:map(device,v["map_texel"] as! [Int]),mapAllowedComponents:4,
                environmentSource:{ _ in attempts+=1;return v["environment_ready"] as! Bool ?
                    .sameFrameEnvironment(frameEpoch:1,allocationGeneration:1,texture:environment,source:sourceReceipt) : nil })!
            let uniform=SceneLayerFragmentUniforms(time:0,alpha:number(v,"opacity"),dependencyBlendMode:0,usesDependencyBlend:0,cursorUV:.zero,
                sourceSampling:.zero,tint:SIMD4(SIMD3(floats(v,"tint")),(v["tint_alpha"] as? NSNumber)?.floatValue ?? 1),
                textureFrame0:SIMD4(0,0,1,0),textureFrame1:SIMD4(0,1,0,0))
            let accepted=SceneOffscreenEffectRenderer.captureSource(sourceTexture:source,target:target,sourceUniforms:uniform,
                pipeline:base,commandBuffer:cb,sourceLighting:v["enabled"] as! Bool ? payload : nil)
            cb.commit();cb.waitUntilCompleted()
            let actual=pixels(target)
            let baselineTarget=texture(device),baselineCB=queue.makeCommandBuffer()!
            precondition(SceneOffscreenEffectRenderer.captureSource(sourceTexture:source,target:baselineTarget,sourceUniforms:uniform,pipeline:base,commandBuffer:baselineCB))
            baselineCB.commit();baselineCB.waitUntilCompleted()
            let graphTarget=texture(device),graphCB=queue.makeCommandBuffer()!
            let graphEncoder=SceneGraphResourcePassEncoder(commandQueue:queue)
            let beforePrepare=attempts
            let prepared=graphEncoder.prepareSourceCapture(source:source,target:graphTarget,uniforms:uniform,
                pipeline:base,sourceLighting:v["enabled"] as! Bool ? payload : nil)!
            let prepareIsLazy=attempts == beforePrepare
            let aliasRejected=graphEncoder.prepareSourceCapture(source:source,target:source,uniforms:uniform,
                pipeline:base,sourceLighting:payload) == nil && attempts == beforePrepare
            let commonAlias=SceneOffscreenEffectRenderer.captureSource(sourceTexture:source,target:source,
                sourceUniforms:uniform,pipeline:base,commandBuffer:graphCB,sourceLighting:payload)
                && attempts == beforePrepare
            let graphBlit=graphCB.makeBlitCommandEncoder()!;graphBlit.generateMipmaps(for:environment);graphBlit.endEncoding()
            let graphAccepted=graphEncoder.encode(prepared,commandBuffer:graphCB)
            graphCB.commit();graphCB.waitUntilCompleted()
            rows.append(["graphActual":pixels(graphTarget),"graphCompleted":graphCB.status == .completed && graphCB.error == nil,
                         "graphAccepted":graphAccepted,"prepareIsLazy":prepareIsLazy,"aliasRejected":aliasRejected,"commonAliasSkipped":commonAlias,
                         "name":v["name"]!,"actual":actual,"original":pixels(baselineTarget),"accepted":accepted,
                         "normalReady":payload.normal.status == "ready","mapReady":payload.materialMap.status == "ready",
                         "attempts":attempts,"completed":cb.status == .completed && cb.error == nil])
        }
        // rgba32f is only a test readback surface: it preserves enough precision
        // to compare sampled-value equivalence within 2e-6 while the real
        // environment storage remains rgba16f; internal UV precision is not measured.
        let base32=SceneImageLayerPipeline(device:device,pixelFormat:.rgba32Float,library:library)!
        let lit32=SceneLitImageLayerPipeline(device:device,pixelFormat:.rgba32Float,library:library)!

        // Independent constant-per-mip inputs expose trilinear LOD selection.
        // The frozen oracle supplies only roughness, mip count, and expected LOD.
        var lodRows:[[String:Any]]=[]
        for row in report["roughness_lod"] as! [[String:Any]] {
            let count=(row["mip_count"] as! NSNumber).intValue
            let size=1 << (count-1),env=texture(device,width:size,height:size,mips:true)
            for level in 0..<count {
                let extent=max(1,size >> level)
                let value=Float(level+1)/8
                let data:[Float16]=Array(repeating:[Float16(value),Float16(value),Float16(value),Float16(1)],count:extent*extent).flatMap{$0}
                data.withUnsafeBytes {env.replace(region:MTLRegionMake2D(0,0,extent,extent),mipmapLevel:level,
                    withBytes:$0.baseAddress!,bytesPerRow:extent*8)}
            }
            let source=texture(device,values:[0,0,0,1]),target=texture(device,format:.rgba32Float),cb=queue.makeCommandBuffer()!
            var p=Capture.packLights(pointLights:[],spotLights:[],ambient:.zero,material:SIMD2(0,number(row,"roughness")),
                view:SIMD4(0,0,1,0),layerModelMatrix:matrix_identity_float4x4,normalModelMatrix:matrix_identity_float4x4)!
            p.reflection=SIMD4(1,0,0,0)
            let payload=Capture(pipeline:lit32,lights:p,normal:normal(device,["format":"bc5-rg-snorm","endpoints":[0,0]]),
                environmentSource:{ _ in .sameFrameEnvironment(frameEpoch:1,allocationGeneration:1,texture:env,source:sourceReceipt) })!
            let accepted=SceneOffscreenEffectRenderer.captureSource(sourceTexture:source,target:target,
                sourceUniforms:Harness.uniforms,pipeline:base32,commandBuffer:cb,sourceLighting:payload)
            cb.commit();cb.waitUntilCompleted()
            lodRows.append(["mipCount":count,"roughness":row["roughness"]!,"actual":pixels(target),
                            "completed":accepted && cb.status == .completed && cb.error == nil])
        }

        let width=256,height=128
        var gradient:[Float]=[]
        for y in 0..<height { for x in 0..<width { gradient.append(contentsOf:[(Float(x)+0.5)/Float(width),(Float(y)+0.5)/Float(height),1,1]) } }
        var spatial:[[String:Any]]=[]
        for row in report["gpu_spatial"] as! [[String:Any]] {
            let v=row["input"] as! [String:Any]
            let source=texture(device,values:[0,0,0,1]),target=texture(device,format:.rgba32Float)
            let env=texture(device,width:width,height:height,mips:true,values:gradient),cb=queue.makeCommandBuffer()!
            let blit=cb.makeBlitCommandEncoder()!;blit.generateMipmaps(for:env);blit.endEncoding()
            let position=SIMD3(floats(v,"position"))
            var model=matrix_identity_float4x4;model.columns.3=SIMD4(position,1)
            let view:SIMD4<Float>
            if let eye=v["eye"] as? [NSNumber] { view=SIMD4(eye[0].floatValue,eye[1].floatValue,eye[2].floatValue,1) }
            else { view=SIMD4(SIMD3(floats(v,"view")),0) }
            var p=Capture.packLights(pointLights:[],spotLights:[],ambient:.zero,material:SIMD2(0,0),view:view,layerModelMatrix:model,normalModelMatrix:matrix_identity_float4x4)!
            p.reflection=SIMD4(1,number(v,"distance"),0,0)
            let matrix=(v["vp"] as! [[NSNumber]]).map { SIMD4<Float>($0.map(\.floatValue)) }
            p.sceneViewProjection=simd_float4x4(rows:matrix)
            let payload=Capture(pipeline:lit32,lights:p,normal:normal(device,v["normal_texel"] as! [String:Any]),
                environmentSource:{ _ in .sameFrameEnvironment(frameEpoch:1,allocationGeneration:1,texture:env,source:sourceReceipt) })!
            precondition(SceneOffscreenEffectRenderer.captureSource(sourceTexture:source,target:target,sourceUniforms:Harness.uniforms,
                pipeline:base32,commandBuffer:cb,sourceLighting:payload))
            cb.commit();cb.waitUntilCompleted()
            let expected=row["expected"] as! [String:Any]
            let filtered: [Float]
            if expected["valid"] as! Bool { filtered = try sampleControl(device,queue,texture:env,uv:floats(expected,"uv")) }
            else { filtered = [0,0,0,0] }
            spatial.append(["name":v["name"]!,"actual":pixels(target),"independentFilteredOracle":filtered,
                            "completed":cb.status == .completed && cb.error == nil])
        }
        print(String(data:try JSONSerialization.data(withJSONObject:["numeric":rows,"spatial":spatial,"roughnessLOD":lodRows],options:.sortedKeys),encoding:.utf8)!)
    }
}
'''

class SceneLitImageLayerTests(unittest.TestCase):
    def test_independent_reflection_numbers_and_scene_projection(self):
        with tempfile.TemporaryDirectory(prefix='mwx-f5-numeric-') as temporary:
            work=Path(temporary);vectors=reflection_vectors()
            (work/'vectors.json').write_text(json.dumps(vectors,indent=2))
            air=[]
            for name in ['SceneImageLayer','SceneLitImageLayer']:
                output=work/(name+'.air')
                compilation=subprocess.run(['xcrun','-sdk','macosx','metal','-c',str(Path(os.environ['MWX_REFLECTION_SHADER']) if name=='SceneLitImageLayer' and 'MWX_REFLECTION_SHADER' in os.environ else SCENE/'Rendering/Composition'/(name+'.metal')),'-o',str(output)],capture_output=True,text=True)
                self.assertEqual(compilation.returncode,0,compilation.stderr);air.append(str(output))
            library=work/'fixture.metallib'
            subprocess.run(['xcrun','-sdk','macosx','metallib',*air,'-o',str(library)],check=True,capture_output=True,text=True)
            sources=['Rendering/Metal/SceneMetalPipeline.swift','Rendering/Metal/SceneLitImageLayerPipeline.swift',
                     'Rendering/Composition/SceneOffscreenEffectRenderer+Capture.swift','Diagnostics/ScenePerformanceCounterHub.swift','Diagnostics/SceneGPUCensus.swift','Rendering/Graph/SceneGraphResourcePassEncoder.swift']
            (work/'Support.swift').write_text(texture_fixture.HARNESS.split('@main',1)[0]+'struct SceneGraphRenderTargetPlan { struct ClearColor { let red:Double; let green:Double; let blue:Double; let alpha:Double } }\nimport simd\nenum SceneMatrix { static func scale(_ v:SIMD3<Float>)->simd_float4x4 { simd_float4x4(diagonal:SIMD4(v,1)) } }\n')
            (work/'ReflectionHarness.swift').write_text(REFLECTION_HARNESS);binary=work/'fixture'
            compiled=subprocess.run(['xcrun','swiftc','-D','SCENE_AUTHORED_NORMAL','-parse-as-library',
                *map(str,dict.fromkeys(texture_fixture.SWIFT_SOURCES+[SCENE/s for s in sources])),str(work/'Support.swift'),
                str(ROOT/'script/tests/fixtures/SceneLitImageLayerHarness.swift'),str(work/'ReflectionHarness.swift'),
                '-module-cache-path',str(work/'cache'),'-o',str(binary)],capture_output=True,text=True)
            self.assertEqual(compiled.returncode,0,compiled.stderr)
            run=subprocess.run([str(binary),str(library),str(work/'vectors.json')],capture_output=True,text=True)
            self.assertEqual(run.returncode,0,run.stderr);report=json.loads(run.stdout)
            if destination:=os.environ.get('MWX_REFLECTION_EVIDENCE'):
                Path(destination).mkdir(parents=True,exist_ok=True)
                (Path(destination)/'numeric-projection-gpu.json').write_text(json.dumps(report,indent=2))
            self.assertEqual(len(report['numeric']),len(vectors['gpu_numerical']))
            for actual,vector in zip(report['numeric'],vectors['gpu_numerical']):
                v,e=vector['input'],vector['expected'];name=v['name']
                self.assertTrue(actual['accepted'] and actual['completed'] and actual['normalReady'] and actual['mapReady'],actual)
                self.assertEqual(actual['actual'][3],e['half_rgba'][3],actual)
                self.assertEqual(actual['graphActual'],actual['actual'],actual)
                for key in ['graphCompleted','graphAccepted','prepareIsLazy','aliasRejected','commonAliasSkipped']:self.assertTrue(actual[key],actual)
                if name=='coverage-zero':self.assertEqual(actual['actual'],[0,0,0,0],actual)
                if name in {'strength-zero','B-zero','disabled-original','unavailable-original'}:
                    self.assertEqual(actual['actual'],actual['original'],actual)
                else:
                    for channel in range(3):self.assertLessEqual(abs(actual['actual'][channel]-e['half_rgba'][channel]),e['radiance_tolerance'][channel],(actual,e))
                if name in {'strength-zero','disabled-original'}:self.assertEqual(actual['attempts'],0,actual)
            self.assertEqual(len(report['roughnessLOD']),len(vectors['roughness_lod']))
            for actual,vector in zip(report['roughnessLOD'],vectors['roughness_lod']):
                self.assertTrue(actual['completed'],actual)
                expected=(vector['lod']+1)/8*.04
                for channel in range(3):self.assertLessEqual(abs(actual['actual'][channel]-expected),2e-6,(actual,vector))
                self.assertEqual(actual['actual'][3],1,actual)
            self.assertEqual(len(report['spatial']),len(vectors['gpu_spatial']))
            for actual,vector in zip(report['spatial'],vectors['gpu_spatial']):
                e=vector['expected'];v=vector['input'];self.assertTrue(actual['completed'],actual)
                if not e['valid']:self.assertEqual(actual['actual'],[0,0,0,1],actual);continue
                n=reflection_oracle.unit(v['normal']);view=reflection_oracle.unit(tuple(v['eye'][i]-v['position'][i] for i in range(3))) if 'eye' in v else reflection_oracle.unit(v['view'])
                fresnel=.04+.96*(1-min(1,abs(reflection_oracle.dot(n,view))))**5
                recovered=[actual['actual'][c]/fresnel for c in range(2)]
                # Compare sampled-pixel equivalence at the frozen oracle UV.
                # RGBA16F hardware filtering quantizes interpolated values;
                # this does not claim a direct measurement of internal UV.
                expected=actual['independentFilteredOracle'][:2]
                for channel in range(2):self.assertLessEqual(abs(recovered[channel]-expected[channel]),2e-6,(actual,e,recovered,expected))
            print(json.dumps(report,sort_keys=True))

    def test_world_space_capture_and_terminal_composition(self):
        with tempfile.TemporaryDirectory(prefix='scene-lit-image-') as temporary:
            work = Path(temporary)
            air = []
            for name in ['SceneImageLayer', 'SceneLitImageLayer']:
                output = work / (name + '.air')
                subprocess.run(['xcrun','-sdk','macosx','metal','-c',str(SCENE / 'Rendering/Composition' / (name+'.metal')),'-o',str(output)],check=True,capture_output=True,text=True)
                air.append(str(output))
            library = work / 'fixture.metallib'
            subprocess.run(['xcrun','-sdk','macosx','metallib',*air,'-o',str(library)],check=True,capture_output=True,text=True)
            sources = ['Rendering/Metal/SceneMetalPipeline.swift','Rendering/Metal/SceneLitImageLayerPipeline.swift',
                'Rendering/Composition/SceneOffscreenEffectRenderer+Capture.swift',
                'Diagnostics/ScenePerformanceCounterHub.swift','Diagnostics/SceneGPUCensus.swift']
            support = work / 'Support.swift'
            support.write_text(texture_fixture.HARNESS.split('@main', 1)[0] + 'import simd\nenum SceneMatrix { static func scale(_ v: SIMD3<Float>) -> simd_float4x4 { simd_float4x4(diagonal: SIMD4(v,1)) } }\n')
            binary = work / 'fixture'
            compiled = subprocess.run(['xcrun','swiftc','-parse-as-library',*[str(p) for p in dict.fromkeys(texture_fixture.SWIFT_SOURCES + [SCENE / s for s in sources])],str(support),str(ROOT/'script/tests/fixtures/SceneLitImageLayerHarness.swift'),'-module-cache-path',str(work/'module-cache'),'-o',str(binary)],capture_output=True,text=True)
            self.assertEqual(compiled.returncode,0,compiled.stderr)
            result = subprocess.run([str(binary),str(library)],capture_output=True,text=True)
            self.assertEqual(result.returncode,0,result.stderr)
            report = json.loads(result.stdout)
            self.assertEqual(report['rectangleRotationNormalCases'],12)
            self.assertLess(report['maxOracleError'],0.002)
            self.assertEqual(report['flatNormalError'],0)
            self.assertTrue(report['mixedOverflowTruncates'])
            self.assertTrue(report['pointsOverflowKeepsAuthoredOrder'])
            print(json.dumps(report,sort_keys=True))

if __name__ == '__main__': unittest.main()
