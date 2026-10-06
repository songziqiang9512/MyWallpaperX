import Foundation
import Metal
import simd

@main enum PBRScalarHarness {
    typealias Capture = SceneBaseMaterialLitCapturePayload
    static func main() throws {
        let device=MTLCreateSystemDefaultDevice()!, queue=device.makeCommandQueue()!
        let library=try device.makeLibrary(URL:URL(fileURLWithPath:CommandLine.arguments[1]))
        let base=SceneImageLayerPipeline(device:device,pixelFormat:.rgba16Float,library:library)!
        let lit=SceneLitImageLayerPipeline(device:device,pixelFormat:.rgba16Float,library:library)!
        func texture(_ source:SIMD4<Float>? = nil) -> MTLTexture {
            let d=MTLTextureDescriptor.texture2DDescriptor(pixelFormat:.rgba16Float,width:1,height:1,mipmapped:false)
            d.storageMode = .shared; d.usage=[.shaderRead,.renderTarget]
            let t=device.makeTexture(descriptor:d)!
            if let source { var values=(0..<4).map { Float16(source[$0]) }
                values.withUnsafeMutableBytes { t.replace(region:MTLRegionMake2D(0,0,1,1),mipmapLevel:0,withBytes:$0.baseAddress!,bytesPerRow:8) } }
            return t
        }
        var records:[[String:Any]]=[]
        func check(_ name:String,metal:Float,rough:Float,source:SIMD4<Float> = SIMD4(repeating:1),
            intensity:Float=1,count:Int=1,light:SIMD3<Float> = SIMD3(0,0,1),
            view:SIMD4<Float> = SIMD4(0,0,1,0),normal:SIMD3<Float> = SIMD3(0,0,1),
            tint:Float=1,opacity:Float=1,ambient:Float=0) {
            let n=simd_normalize(normal),right=simd_normalize(SIMD3(n.z,0,-n.x))
            let normalModel=simd_float4x4(SIMD4(right,0),SIMD4(0,1,0,0),SIMD4(n,0),SIMD4(0,0,0,1))
            let points=(0..<count).map { _ in Capture.PointLight(position:light,color:SIMD3(repeating:1),intensity:intensity,radius:1000) }
            let packed=Capture.packLights(pointLights:points,spotLights:[],ambient:SIMD3(repeating:ambient),
                material:SIMD2(metal,rough),view:view,layerModelMatrix:matrix_identity_float4x4,normalModelMatrix:normalModel)!
            let payload=Capture(pipeline:lit,lights:packed,normal:.disabled)!
            var uniforms=Harness.uniforms; uniforms.alpha=opacity; uniforms.tint=SIMD4(tint,tint,tint,1)
            let input=texture(source),output=texture(),command=queue.makeCommandBuffer()!
            precondition(SceneOffscreenEffectRenderer.captureSource(sourceTexture:input,target:output,
                sourceUniforms:uniforms,pipeline:base,commandBuffer:command,sourceLighting:payload))
            command.commit();command.waitUntilCompleted();precondition(command.status == .completed)
            var raw=[Float16](repeating:0,count:4)
            raw.withUnsafeMutableBytes { output.getBytes($0.baseAddress!,bytesPerRow:8,from:MTLRegionMake2D(0,0,1,1),mipmapLevel:0) }
            let actual=raw.map(Float.init)
            let represented=SIMD4<Float>((0..<4).map { Float(Float16(source[$0])) })
            let response=Harness.materialResponse(normal:n,light:light,view:SIMD3(view.x,view.y,view.z),
                source:represented,metallic:Double(metal),roughness:Double(rough))
            // Official 2D lit-image point contract: planar (X/Y) falloff with
            // k_2D=1.85 intensity scale; receiver under the light is maximum.
            let falloff=pow(max(0,1-Double(simd_length(SIMD2(light.x,light.y)))/1000),2)*1.85
            var expected=[Float]()
            for channel in 0..<3 {
                let value=(Double(response[channel])*falloff*Double(intensity)*Double(count)
                    + Double(represented[channel])*Double(ambient))*Double(tint)*Double(opacity)
                let half=Float16(min(65504,max(0,value)))
                expected.append(Float(half))
                let tolerance=max(Float(half.ulp),0.002)
                precondition(actual[channel].isFinite && abs(actual[channel]-Float(half))<=tolerance,
                    "\(name) channel\(channel): \(actual) != \(expected) tolerance\(tolerance)")
            }
            let expectedAlpha=Float(Float16(represented.w*opacity))
            precondition(actual[3] == expectedAlpha)
            var dimUniforms=Harness.uniforms; dimUniforms.tint=SIMD4(0.5,0.5,0.5,1)
            let dim=texture(), next=queue.makeCommandBuffer()!
            precondition(SceneOffscreenEffectRenderer.captureSource(sourceTexture:output,target:dim,
                sourceUniforms:dimUniforms,pipeline:base,commandBuffer:next))
            next.commit();next.waitUntilCompleted();precondition(next.status == .completed)
            var dimRaw=[Float16](repeating:0,count:4)
            dimRaw.withUnsafeMutableBytes { dim.getBytes($0.baseAddress!,bytesPerRow:8,from:MTLRegionMake2D(0,0,1,1),mipmapLevel:0) }
            for c in 0..<3 { precondition(Float(dimRaw[c]) == Float(Float16(actual[c]*0.5))) }
            records.append(["dimActual":dimRaw.map(Float.init),"name":name,"actual":actual,"expectedRGB":expected,
                "material":[metal,rough],"intensity":intensity,"lights":count,
                "normal":[normal.x,normal.y,normal.z],"view":[view.x,view.y,view.z,view.w],
                "light":[light.x,light.y,light.z],"source":[source.x,source.y,source.z,source.w],"opacity":opacity,"tint":tint])
        }
        for m:Float in [0,0.5,1] { for r:Float in [0,0.1,0.5,1] {
            check("material-\(m)-\(r)",metal:m,rough:r,source:SIMD4(0.5,0.25,0.125,1))
        }}
        for coverage:Float in [0,0.25,1] { for count in [1,4] {
            check("half-domain-\(coverage)-\(count)",metal:1,rough:0,source:SIMD4(repeating:coverage),intensity:30,count:count)
        }}
        check("extreme-finite-factors",metal:1,rough:0,intensity:1e38,tint:1e-20,opacity:1e-18)
        check("zero-opacity",metal:1,rough:0,intensity:Float.greatestFiniteMagnitude,opacity:0)
        check("zero-tint",metal:1,rough:0,intensity:Float.greatestFiniteMagnitude,tint:0)
        check("dielectric-black-specular",metal:0,rough:0.5,source:SIMD4(0,0,0,1))
        check("hdr-source-reflectance-bound",metal:0.5,rough:0.5,source:SIMD4(8,4,2,1))
        check("legacy-ambient-metal",metal:1,rough:0.5,source:SIMD4(8,4,2,1),intensity:0,ambient:0.5)
        check("nonaxis-aligned-peak",metal:1,rough:0,light:SIMD3(0.6,0,0.8),view:SIMD4(0.6,0,0.8,0),normal:SIMD3(0.6,0,0.8))
        check("coincident-light",metal:0,rough:0,light:.zero)
        check("tilted",metal:0.35,rough:0.42,light:SIMD3(0.3,0.2,1),view:SIMD4(-0.4,0.2,1,1),normal:SIMD3(0.6,0,0.8))
        check("perspective-eye",metal:0.35,rough:0.42,view:SIMD4(1,0,1,1))
        check("backside-view",metal:0,rough:0.1,view:SIMD4(0,0,-1,1))
        check("zero-view",metal:0,rough:0,view:.zero)
        check("grazing",metal:0.4,rough:0.3,light:SIMD3(1,0,0.001),view:SIMD4(-1,0,0.001,1))
        var timing:[String:Any]=[:]
        if ProcessInfo.processInfo.environment["MWX_PBR_TIMING"] != nil {
            let d=MTLTextureDescriptor.texture2DDescriptor(pixelFormat:.rgba16Float,width:256,height:256,mipmapped:false)
            d.usage=[.shaderRead,.renderTarget]; d.storageMode = .private
            let output=device.makeTexture(descriptor:d)!, input=texture(SIMD4(0.5,0.25,0.125,1))
            let lights=Capture.packLights(pointLights:(0..<4).map { i in
                Capture.PointLight(position:SIMD3(Float(i)*0.1,0,1),color:SIMD3(repeating:1),intensity:1,radius:1000)
            },spotLights:[],ambient:SIMD3(repeating:0.1),material:SIMD2(0.5,0.5),view:SIMD4(0,0,1,0),
                layerModelMatrix:matrix_identity_float4x4,normalModelMatrix:matrix_identity_float4x4)!
            func measure(_ pipeline:SceneLitImageLayerPipeline) -> [Double] {
                let payload=Capture(pipeline:pipeline,lights:lights,normal:.disabled)!
                var samples:[Double]=[]
                for iteration in 0..<13 {
                    let cb=queue.makeCommandBuffer()!
                    for _ in 0..<32 { precondition(SceneOffscreenEffectRenderer.captureSource(sourceTexture:input,target:output,
                        sourceUniforms:Harness.uniforms,pipeline:base,commandBuffer:cb,sourceLighting:payload)) }
                    cb.commit();cb.waitUntilCompleted();precondition(cb.status == .completed)
                    if iteration>=10 { samples.append((cb.gpuEndTime-cb.gpuStartTime)*1000) }
                }
                return samples
            }
            timing=["target":[256,256],"lights":4,"drawsPerCommand":32,"warmupCommands":10,"currentMilliseconds":measure(lit)]
            if CommandLine.arguments.count>2 {
                let oldLibrary=try device.makeLibrary(URL:URL(fileURLWithPath:CommandLine.arguments[2]))
                let old=SceneLitImageLayerPipeline(device:device,pixelFormat:.rgba16Float,library:oldLibrary)!
                timing["legacyDiffuseMilliseconds"]=measure(old)
            }
        }
        print(String(decoding:try JSONSerialization.data(withJSONObject:["cases":records,"count":records.count,"timing":timing],options:[.sortedKeys]),as:UTF8.self))
    }
}
