import Foundation
import Metal
import simd

@main enum AuthoredNormalHarness {
    typealias Capture = SceneBaseMaterialLitCapturePayload
    static func tex(format: UInt32, width: UInt32 = 4, height: UInt32 = 4,
                    flags: UInt32 = 0, bytes: [UInt8]) -> Data {
        var data = Data("TEXV0005\0TEXI0001\0".utf8)
        func append(_ value: UInt32) { var v = value.littleEndian; withUnsafeBytes(of: &v) { data.append(contentsOf: $0) } }
        for v in [format,flags,width,height,width,height,0] { append(v) }
        data.append(Data("TEXB0002\0".utf8))
        for v in [UInt32(1),1,width,height,0,0,UInt32(bytes.count)] { append(v) }
        data.append(contentsOf: bytes)
        return data
    }
    static func bc5(_ x: Int8, _ y: Int8) -> [UInt8] {
        [UInt8(bitPattern:x),UInt8(bitPattern:x),0,0,0,0,0,0,
         UInt8(bitPattern:y),UInt8(bitPattern:y),0,0,0,0,0,0]
    }
    static func copy(_ c: SceneTextureCandidate, uv: SceneTextureUVTransform? = nil,
                     sampling: SceneTextureSampling? = nil, purpose: SceneTextureLoadPurpose? = nil,
                     generation: SceneTextureResourceGeneration? = nil,
                     size: CGSize? = nil) -> SceneTextureCandidate {
        SceneTextureCandidate(texture:c.texture, identity:c.identity, generation:generation ?? c.generation,
            purpose:purpose ?? c.purpose,content:c.content,physicalSize:size ?? c.physicalSize,
            mappedSize:c.mappedSize,uvTransform:uv ?? c.uvTransform,sampling:sampling ?? c.sampling,
            authoredFormat:c.authoredFormat)
    }
    static func main() throws {
        let device=MTLCreateSystemDefaultDevice()!, queue=device.makeCommandQueue()!
        let library=try device.makeLibrary(URL:URL(fileURLWithPath:CommandLine.arguments[1]))
        let directory=URL(fileURLWithPath:CommandLine.arguments[2])
        let loader=SceneTextureLoader()
        func load(_ name:String,_ data:Data, purpose:SceneTextureLoadPurpose = .normal) throws -> SceneTextureCandidate {
            let url=directory.appendingPathComponent(name+".tex");try data.write(to:url)
            guard case let .loaded(value)=loader.loadCandidate(from:url,purpose:purpose,device:device) else { fatalError("load \(name)") }
            return value
        }
        let pipeline=SceneImageLayerPipeline(device:device,pixelFormat:.rgba16Float,library:library)!
        let lit=SceneLitImageLayerPipeline(device:device,pixelFormat:.rgba16Float,library:library)!
        let model=matrix_identity_float4x4
        let position=SIMD3<Float>(4,3,5)
        let point=Capture.PointLight(position:position,color:SIMD3(repeating:1),intensity:1,radius:100)
        let lights=Capture.packLights(pointLights:[point],spotLights:[],ambient:.zero,material:SIMD2(0.5,0.5),view:SIMD4(0,0,1,0),layerModelMatrix:model,normalModelMatrix:model)!
        func render(_ normal:Capture.TextureInput) -> [Float] {
            Harness.render(device,queue,pipeline:pipeline,lit:lit,payload:lights,normalInput:normal)
        }
        var cases=0, maxError:Float=0
        var candidates:[SceneTextureCandidate]=[]
        for (i,xy) in [(Int8(0),Int8(0)),(90,0),(-90,0),(0,90),(0,-90)].enumerated() {
            let c=try load("signed\(i)",tex(format:5,bytes:bc5(xy.0,xy.1)))
            precondition(c.pixelFormat == .bc5_rgSnorm)
            let x=Float(xy.0)/127, y=Float(xy.1)/127
            candidates.append(c)
            let n=simd_normalize(SIMD3(x,y,sqrt(max(0,1-x*x-y*y))))
            check(render(.resolve(c)),n)
        }
        for (i,xy) in [(UInt8(128),UInt8(128)),(230,128),(25,128),(128,230),(128,25),(255,255)].enumerated() {
            let c=try load("unsigned\(i)",tex(format:8,bytes:Array(repeating:[xy.0,xy.1],count:16).flatMap{$0}))
            precondition(c.pixelFormat == .rg8Unorm)
            let x=Float(xy.0)/255*2-1,y=Float(xy.1)/255*2-1
            check(render(.resolve(c)),simd_normalize(SIMD3(x,y,sqrt(max(0,1-x*x-y*y)))))
        }
        for (i,rgb) in [[UInt8(230),128,204],[25,128,204],[128,230,204],[128,25,204],[128,128,0]].enumerated() {
            let c=try load("rgb\(i)",tex(format:0,bytes:Array(repeating:rgb+[255],count:16).flatMap{$0}))
            precondition(c.pixelFormat == .rgba8Unorm)
            check(render(.resolve(c)),simd_normalize(SIMD3(Float(rgb[0]),Float(rgb[1]),Float(rgb[2]))/255*2-1))
        }
        func check(_ pixels:[Float],_ normal:SIMD3<Float>) {
            for y in 0..<Harness.height { for x in 0..<Harness.width {
                let world=SIMD3<Float>((Float(x)+0.5)/Float(Harness.width)-0.5,0.5-(Float(y)+0.5)/Float(Harness.height),0)
                let delta=position-world,distance=simd_length(delta)
                let attenuation=pow(max(0,1-distance/100),2)
                let response=Harness.materialResponse(normal:normal,light:delta/distance)
                for channel in 0..<3 { maxError=max(maxError,abs(pixels[(y*Harness.width+x)*4+channel]-response[channel]*attenuation)) }
            }}
            cases += 1
        }
        let sampleLibrary=try device.makeLibrary(source:"""
        #include <metal_stdlib>
        using namespace metal;
        kernel void readNormal(texture2d<float> tex [[texture(0)]], device float4 *output [[buffer(0)]]) {
            constexpr sampler state(filter::nearest,address::clamp_to_edge);
            output[0]=tex.sample(state,float2(0.5));
        }
        """,options:nil)
        let sampleState=try device.makeComputePipelineState(function:sampleLibrary.makeFunction(name:"readNormal")!)
        func sample(_ texture:MTLTexture) -> SIMD4<Float> {
            let buffer=device.makeBuffer(length:16,options:.storageModeShared)!
            let command=queue.makeCommandBuffer()!,encoder=command.makeComputeCommandEncoder()!
            encoder.setComputePipelineState(sampleState);encoder.setTexture(texture,index:0);encoder.setBuffer(buffer,offset:0,index:0)
            encoder.dispatchThreads(MTLSize(width:1,height:1,depth:1),threadsPerThreadgroup:MTLSize(width:1,height:1,depth:1));encoder.endEncoding()
            command.commit();command.waitUntilCompleted();precondition(command.status == .completed)
            return buffer.contents().load(as:SIMD4<Float>.self)
        }
        let signedSamples=candidates.map { sample($0.texture) }
        let signedExact=zip(signedSamples,[(Float(0),Float(0)),(90,0),(-90,0),(0,90),(0,-90)])
            .allSatisfy { actual,xy in abs(actual.x-xy.0/127)<0.00001 && abs(actual.y-xy.1/127)<0.00001 }
        let dataTex=tex(format:0,bytes:Array(repeating:[UInt8(230),128,204,128],count:16).flatMap{$0})
        let normalPurpose=try load("dual-purpose",dataTex)
        let colorPurpose=try load("dual-purpose",dataTex,purpose:.premultipliedColor)
        let srgbDescriptor=MTLTextureDescriptor.texture2DDescriptor(pixelFormat:.rgba8Unorm_srgb,width:4,height:4,mipmapped:false)
        srgbDescriptor.storageMode = .shared;srgbDescriptor.usage = .shaderRead
        let srgb=device.makeTexture(descriptor:srgbDescriptor)!
        let srgbBytes=Array(repeating:[UInt8(230),128,204,255],count:16).flatMap{$0}
        srgbBytes.withUnsafeBytes { srgb.replace(region:MTLRegionMake2D(0,0,4,4),mipmapLevel:0,withBytes:$0.baseAddress!,bytesPerRow:16) }
        let srgbInput=Capture.TextureInput.resolve(Harness.candidate(srgb))
        // Small BC1/2/3 files exercise the actual loader's RGBA decode route.
        // The same parsed blocks also exercise its native uploader contract.
        var nativeBCResults:[Bool]=[]
        for (format,pixelFormat,alpha) in [(UInt32(7),MTLPixelFormat.bc1_rgba,[UInt8]()),
            (6,.bc2_rgba,Array(repeating:UInt8(255),count:8)),
            (4,.bc3_rgba,[UInt8(255),255,0,0,0,0,0,0])] {
            let block=alpha+[UInt8(0),132,0,132,0,0,0,0]
            let candidate=try load("bc\(format)",tex(format:format,bytes:block))
            precondition(candidate.pixelFormat == .rgba8Unorm)
            check(render(.resolve(candidate)),simd_normalize(SIMD3<Float>(132.0/255*2-1,130.0/255*2-1,-1)))
            let container=loader.texContainer(from:directory.appendingPathComponent("bc\(format).tex"))!
            guard case let .loaded(native)=SceneCompressedTextureUploader.uploadNativeImage(container.images[0],pixelFormat:pixelFormat,device:device) else { fatalError("native BC upload") }
            let value=sample(native),input=Capture.TextureInput.resolve(Harness.candidate(native))
            let pixels=render(input)
            nativeBCResults.append(input.status == "ready" && abs(value.x-0.52)<0.02
                && abs(value.y-0.51)<0.02 && value.z == 0
                && stride(from:0,to:pixels.count,by:4).allSatisfy { pixels[$0] == 0 })
        }
        let flat=render(.disabled)
        let neutral=render(.resolve(candidates[0]))
        let registry=SceneFrameTextureRegistry()
        let identity=SceneFrameTextureIdentity.asset(.init(virtualPath:"normal.tex",purpose:.normal)!)
        let c=candidates[1]
        let publication=SceneTextureProviderPublication(requestIdentity:identity,candidate:c,contentGeneration:1)
        registry.set(publication,for:identity)
        let ready=Capture.TextureInput.resolve(registry.lookup(identity))
        let bad=SceneTextureProviderPublication(requestIdentity:identity,candidate:copy(c,size:CGSize(width:8,height:4)),contentGeneration:2)
        registry.set(bad,for:identity)
        let invalid=Capture.TextureInput.resolve(registry.lookup(identity))
        let missing=Capture.TextureInput.resolve(Optional<SceneFrameTextureLookupStatus>.none)
        registry.set(.init(requestIdentity:identity,candidate:copy(c,purpose:.flow),contentGeneration:3),for:identity)
        let wrongPurpose=Capture.TextureInput.resolve(registry.lookup(identity))
        // Two frames share one physical atlas, but publish a different full UV atom.
        let atlas=try load("atlas",tex(format:0,width:8,height:4,bytes:(0..<32).flatMap { index in
            index % 8 < 4 ? [UInt8(230),128,204,255] : [25,128,204,255]
        }))
        let first=copy(atlas,uv:.init(origin:.zero,xAxis:SIMD2(0.5,0),yAxis:SIMD2(0,1)))
        let second=copy(atlas,uv:.init(origin:SIMD2(0.5,0),xAxis:SIMD2(0.5,0),yAxis:SIMD2(0,1)))
        func publish(_ candidate:SceneTextureCandidate,_ generation:UInt64) -> [Float] {
            registry.set(.init(requestIdentity:identity,candidate:candidate,contentGeneration:generation),for:identity)
            return render(.resolve(registry.lookup(identity)))
        }
        let frameA=publish(first,1),frameB=publish(second,2),frameARestored=publish(first,3)
        // Linear interpolation between exact opposite RGB encodings cancels.
        let cancellation=try load("cancellation",tex(format:0,width:2,height:1,bytes:[255,255,255,255,0,0,0,255]))
        let line=copy(cancellation,uv:.init(origin:SIMD2(0.5-0.000001,0),xAxis:SIMD2(0.000002,0),yAxis:SIMD2(0,1)))
        let cancellationPixels=render(.resolve(line))
        let nearest=copy(atlas,sampling:.init(texFlags:3))
        let sampledLinear=render(.resolve(atlas)),sampledNearest=render(.resolve(nearest))
        let unsupported=try load("scalar",tex(format:9,bytes:Array(repeating:128,count:16)))
        // The real catalog owns sprite timing and publishes a new atom while
        // the physical atlas remains the same. No second clock exists here.
        var animated = tex(format:0,width:8,height:4,flags:4,bytes:(0..<32).flatMap { index in
            index % 8 < 4 ? [UInt8(230),128,204,255] : [25,128,204,255]
        })
        animated.append(Data("TEXS0002\0".utf8))
        func append(_ v:UInt32) { var value=v.littleEndian; withUnsafeBytes(of:&value) { animated.append(contentsOf:$0) } }
        append(2)
        for origin:Float in [0,4] {
            append(0);append(Float(0.1).bitPattern)
            for value:Float in [origin,0,4,0,0,4] { append(value.bitPattern) }
        }
        try animated.write(to:directory.appendingPathComponent("animation.tex"))
        let animatedIdentity=SceneAssetTextureIdentity(virtualPath:"animation.tex",purpose:.normal)!
        let catalog=SceneMaterialAssetTextureCatalog(demands:[animatedIdentity],resourceView:
            SceneResourceView(projectRootURL:directory,packageRootURL:nil,stockAssetsRootURL:directory),
            descriptor:SceneRenderDescriptor(),device:device)
        let provider=catalog.makeFrameProvider()
        func frame(_ time:Double) -> SceneTextureProviderPublication {
            guard case let .ready(value)?=provider.states(sceneTime:time)[animatedIdentity] else { fatalError("animated publication") }
            return value
        }
        let animationA=frame(0);provider.commitFrame()
        let animationB=frame(0.15);provider.discardFrame()
        let animationRetry=frame(0.15);provider.commitFrame()
        registry.set(animationA,for:.asset(animatedIdentity))
        let animationPixelsA=render(.resolve(registry.lookup(.asset(animatedIdentity))))
        registry.set(animationB,for:.asset(animatedIdentity))
        let animationPixelsB=render(.resolve(registry.lookup(.asset(animatedIdentity))))
        let layerPipeline=SceneLitImageLayerPipeline(device:device,pixelFormat:.rgba8Unorm,library:library)!
        let aliasDescriptor=MTLTextureDescriptor.texture2DDescriptor(pixelFormat:.rgba8Unorm,width:4,height:4,mipmapped:false)
        aliasDescriptor.usage=[.shaderRead,.renderTarget]
        let alias=device.makeTexture(descriptor:aliasDescriptor)!
        let aliasPayload=Capture(pipeline:layerPipeline,lights:lights,normal:.resolve(Harness.candidate(alias)))!
        let safeAlias=aliasPayload.validated(for:alias)
        let wrongTarget=Harness.texture(device)
        let aliasBase=SceneImageLayerPipeline(device:device,pixelFormat:.rgba8Unorm,library:library)!
        let aliasSource=Harness.texture(device,fill:Harness.albedo)
        func aliasCapture(_ payload:Capture) -> [UInt8] {
            let command=queue.makeCommandBuffer()!
            precondition(SceneOffscreenEffectRenderer.captureSource(sourceTexture:aliasSource,target:alias,
                sourceUniforms:Harness.uniforms,pipeline:aliasBase,commandBuffer:command,sourceLighting:payload))
            command.commit();command.waitUntilCompleted();precondition(command.status == .completed)
            var pixels=[UInt8](repeating:0,count:64)
            pixels.withUnsafeMutableBytes { alias.getBytes($0.baseAddress!,bytesPerRow:16,from:MTLRegionMake2D(0,0,4,4),mipmapLevel:0) }
            return pixels
        }
        let aliasPixels=aliasCapture(aliasPayload)
        let safeFlatPixels=aliasCapture(Capture(pipeline:layerPipeline,lights:lights,normal:.disabled)!)

        // Independent per-pixel oracle for this authored eight-column atlas.
        // It resolves repeat/clamp and bilinear weights in physical texels;
        // it does not call a product UV/sampler or normal-decoding helper.
        func atlasOracle(_ pixels:[Float],origin:Float,axis:Float,nearest:Bool,repeatUV:Bool) -> Float {
            var error:Float=0
            func red(_ raw:Int) -> Float {
                let column=repeatUV ? (raw % 8 + 8) % 8 : min(7,max(0,raw))
                return Float(column<4 ? 230 : 25)/255
            }
            for y in 0..<Harness.height { for x in 0..<Harness.width {
                let u=(Float(x)+0.5)/Float(Harness.width)
                let texel=(origin+u*axis)*8-0.5
                let index=Int(floor(texel)),fraction=texel-Float(index)
                let r=nearest ? red(Int(floor(texel+0.5))) : red(index)*(1-fraction)+red(index+1)*fraction
                let n=simd_normalize(SIMD3<Float>(r*2-1,128.0/255*2-1,204.0/255*2-1))
                let world=SIMD3<Float>(u-0.5,0.5-(Float(y)+0.5)/Float(Harness.height),0)
                let delta=position-world,distance=simd_length(delta)
                let attenuation=pow(1-distance/100,2)
                let response=Harness.materialResponse(normal:n,light:delta/distance)
                for channel in 0..<3 { error=max(error,abs(pixels[(y*Harness.width+x)*4+channel]-response[channel]*attenuation)) }
            }}
            return error
        }
        let uvOracleErrors=[
            atlasOracle(frameA,origin:0,axis:0.5,nearest:false,repeatUV:true),
            atlasOracle(frameB,origin:0.5,axis:0.5,nearest:false,repeatUV:true),
            atlasOracle(sampledLinear,origin:0,axis:1,nearest:false,repeatUV:true),
            atlasOracle(sampledNearest,origin:0,axis:1,nearest:true,repeatUV:false),
            atlasOracle(animationPixelsA,origin:0,axis:0.5,nearest:false,repeatUV:true),
            atlasOracle(animationPixelsB,origin:0.5,axis:0.5,nearest:false,repeatUV:true),
        ]
        let contracts:[String:Bool]=[
            "bc5NeutralEqualsFlat":flat == neutral,
            "bc5ActualSignedSamples":signedExact,
            "nativeBCFullRGBNegativeZ":nativeBCResults == [true,true,true],
            "samePathPurposeIsolated":normalPurpose.texture !== colorPurpose.texture
                && abs(sample(normalPurpose.texture).x-230.0/255)<0.0001
                && abs(sample(colorPurpose.texture).x-sample(normalPurpose.texture).x)>0.1,
            "wrongSRGBDiscriminated":abs(sample(srgb).y-128.0/255)>0.2
                && srgbInput.status == "unsupported" && render(srgbInput) == flat,
            "readyPublication":ready.status == "ready",
            "badPhysicalRangeRejected":invalid.status == "invalid" && render(invalid) == flat,
            "wrongPurposeRejected":wrongPurpose.status == "invalid" && render(wrongPurpose) == flat,
            "missingIsFlatLit":missing.status == "unavailable" && render(missing) == flat,
            "unsupportedIsFlatLit":Capture.TextureInput.resolve(unsupported).status == "unsupported" && render(.resolve(unsupported)) == flat,
            "sameTextureDifferentFrame":first.texture === second.texture && frameA != frameB && frameA == frameARestored,
            "ownSampler":sampledLinear != sampledNearest,
            "exactUVAndSamplerOracle":uvOracleErrors.allSatisfy { $0 < 0.002 },
            "rgbCancellationFlat":cancellationPixels == flat,
            "actualAssetFrameProvider":animationA.texture === animationB.texture
                && animationA.candidate.uvTransform != animationB.candidate.uvTransform
                && animationPixelsA != animationPixelsB,
            "discardRetrySameGeneration":animationB.contentGeneration == animationRetry.contentGeneration,
            "normalAliasFlatLit":safeAlias?.normal.status == "invalid" && safeAlias?.lights.ambientHasNormal.w == 0
                && aliasPixels == safeFlatPixels && aliasPixels[0] > 0,
            "targetFormatStillRejected":aliasPayload.validated(for:wrongTarget) == nil,
            "gpuCompletionAndTerminal":true,
        ]
        precondition(maxError < 0.002)
        print(String(decoding:try JSONSerialization.data(withJSONObject:["formatCases":cases,"uvOracleErrors":uvOracleErrors,"signedSamples":signedSamples.map { [$0.x,$0.y,$0.z,$0.w] },"maxOracleError":maxError,"contracts":contracts],options:[.sortedKeys]),as:UTF8.self))
    }
}
