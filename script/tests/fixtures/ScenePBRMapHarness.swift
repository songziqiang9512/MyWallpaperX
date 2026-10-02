import Foundation
import Metal
import simd

@main enum PBRMapHarness {
    typealias Capture = SceneBaseMaterialLitCapturePayload
    static func tex(_ rgba: [UInt8], flags: UInt32, format: UInt32 = 0,
                    width: UInt32 = 4, height: UInt32 = 4) -> Data {
        var data=Data("TEXV0005\0TEXI0001\0".utf8)
        func u(_ x:UInt32) { var v=x.littleEndian;withUnsafeBytes(of:&v){data.append(contentsOf:$0)} }
        for v in [format,flags,width,height,width,height,0] { u(v) }
        data.append(Data("TEXB0002\0".utf8))
        for v in [UInt32(1),1,width,height,0,0,UInt32(rgba.count)] { u(v) }
        data.append(contentsOf:rgba);return data
    }
    static func main() throws {
        let device=MTLCreateSystemDefaultDevice()!,queue=device.makeCommandQueue()!
        let library=try device.makeLibrary(URL:URL(fileURLWithPath:CommandLine.arguments[1]))
        let work=URL(fileURLWithPath:CommandLine.arguments[2])
        let base=SceneImageLayerPipeline(device:device,pixelFormat:.rgba16Float,library:library)!
        let lit=SceneLitImageLayerPipeline(device:device,pixelFormat:.rgba16Float,library:library)!
        let loader=SceneTextureLoader()
        func load(_ name:String,_ data:Data,purpose:SceneTextureLoadPurpose = .mask)->SceneTextureCandidate {
            let url=work.appendingPathComponent(name+".tex");try! data.write(to:url)
            guard case let .loaded(candidate)=loader.loadCandidate(from:url,purpose:purpose,device:device) else { fatalError(name) }
            return candidate
        }
        func target(_ value:[Float]? = nil)->MTLTexture {
            let d=MTLTextureDescriptor.texture2DDescriptor(pixelFormat:.rgba16Float,width:1,height:1,mipmapped:false)
            d.storageMode = .shared;d.usage=[.shaderRead,.renderTarget]
            let t=device.makeTexture(descriptor:d)!
            if let value { let raw=value.map(Float16.init);raw.withUnsafeBytes{t.replace(region:MTLRegionMake2D(0,0,1,1),mipmapLevel:0,withBytes:$0.baseAddress!,bytesPerRow:8)} }
            return t
        }
        func render(_ map:Capture.TextureInput,allowed:UInt32=11,material:SIMD2<Float> = SIMD2(0.2,0.8),
                    emission:SIMD4<Float>? = SIMD4(0.25,0.5,1,2),source:[Float] = [0.5,0.25,0.125,1],
                    intensity:Float=0,light:SIMD3<Float> = SIMD3(0,0,1),normal:SIMD3<Float> = SIMD3(0,0,1),
                    tint:SIMD3<Float> = SIMD3(repeating:1),opacity:Float=1)->[Float] {
            let normalMatrix=simd_float4x4(diagonal:SIMD4(1,1,normal.z,1))
            let packed=Capture.packLights(pointLights:[.init(position:light,color:SIMD3(repeating:1),intensity:intensity,radius:1000)],spotLights:[],ambient:.zero,material:material,view:SIMD4(0,0,1,0),layerModelMatrix:matrix_identity_float4x4,normalModelMatrix:normalMatrix)!
            let payload=Capture(pipeline:lit,lights:packed,normal:.disabled,materialMap:map,mapAllowedComponents:allowed,emission:emission)!
            let input=target(source),output=target(),command=queue.makeCommandBuffer()!
            let uniforms=SceneLayerFragmentUniforms(time:0,alpha:opacity,dependencyBlendMode:0,usesDependencyBlend:0,cursorUV:.zero,sourceSampling:.zero,tint:SIMD4(tint,1),textureFrame0:SIMD4(0,0,1,0),textureFrame1:SIMD4(0,1,0,0))
            precondition(SceneOffscreenEffectRenderer.captureSource(sourceTexture:input,target:output,sourceUniforms:uniforms,pipeline:base,commandBuffer:command,sourceLighting:payload))
            command.commit();command.waitUntilCompleted();precondition(command.status == .completed)
            var raw=[Float16](repeating:0,count:4)
            raw.withUnsafeMutableBytes{output.getBytes($0.baseAddress!,bytesPerRow:8,from:MTLRegionMake2D(0,0,1,1),mipmapLevel:0)}
            return raw.map(Float.init)
        }
        let vectors=try JSONSerialization.jsonObject(with:Data(contentsOf:work.appendingPathComponent("vectors.json"))) as! [[String:Any]]
        var records:[[String:Any]]=[]
        for v in vectors {
            func floats(_ key:String)->[Float] { (v[key] as! [NSNumber]).map(\.floatValue) }
            func f(_ key:String)->Float { (v[key] as! NSNumber).floatValue }
            let rgba=(v["rgba"] as! [Int]).map(UInt8.init),bits=UInt32(v["bits"] as! Int)
            let format=UInt32(v["format"] as? Int ?? 0)
            let block:[UInt8]=[0,248,0,248,0,0,0,0]
            let bytes:[UInt8]=format == 7 ? block : format == 6 ? Array(repeating:136,count:8)+block : format == 4 ? [128,128,0,0,0,0,0,0]+block : Array(repeating:rgba,count:16).flatMap{$0}
            let c=load(v["name"] as! String,tex(bytes,flags:bits<<20,format:format))
            let m=floats("material"),l=floats("light"),n=floats("normal"),t=floats("tint")
            let emission:SIMD4<Float>? = v["emission"] is NSNull ? nil : SIMD4<Float>(floats("emission"))
            let actual=render(.resolve(c,kind:.materialMap),allowed:UInt32(v["allowed"] as! Int),material:SIMD2(m),emission:emission,source:floats("source"),intensity:f("intensity"),light:SIMD3(l),normal:SIMD3(n),tint:SIMD3(t),opacity:f("opacity"))
            let expected=floats("expected")
            for channel in 0..<4 {
                let half=Float16(expected[channel]), tolerance=Float(half.ulp)
                precondition(actual[channel].isFinite && abs(actual[channel]-Float(half))<=tolerance,"\(v["name"]!) \(actual) != \(expected)")
            }
            records.append(["name":v["name"]!,"actual":actual,"expected":expected,"pixelFormat":c.pixelFormat.rawValue])
        }
        var contracts:[String:Bool]=[:]
        let flags=UInt32(11)<<20
        let rgba=[UInt8(255),128,77,128]
        let valid=load("valid",tex(Array(repeating:rgba,count:16).flatMap{$0},flags:flags))
        let slot=Capture.TextureInput.resolve(valid,kind:.materialMap)
        let fallback=render(.disabled,intensity:1)
        contracts["unavailableKeepsScalar"]=render(.resolve(nil,kind:.materialMap),intensity:1)==fallback
        let invalid=SceneTextureCandidate(texture:valid.texture,identity:valid.identity,generation:valid.generation,purpose:valid.purpose,content:valid.content,physicalSize:CGSize(width:999,height:4),mappedSize:valid.mappedSize,uvTransform:valid.uvTransform,sampling:valid.sampling)
        contracts["unsafeRangeRejectsMap"]=Capture.TextureInput.resolve(invalid,kind:.materialMap).status == "invalid"
        let packed=Capture.packLights(pointLights:[],spotLights:[],ambient:SIMD3(repeating:1),material:SIMD2(0.2,0.8),view:SIMD4(0,0,1,0),layerModelMatrix:matrix_identity_float4x4,normalModelMatrix:matrix_identity_float4x4)!
        let aliasPipeline=SceneLitImageLayerPipeline(device:device,pixelFormat:valid.pixelFormat,library:library)!
        let alias=Capture(pipeline:aliasPipeline,lights:packed,normal:.disabled,materialMap:slot,mapAllowedComponents:11,emission:SIMD4(repeating:1))!
        let safe=alias.validated(for:valid.texture)!
        contracts["aliasRejectsOnlyMap"]=safe.materialMap.status == "invalid" && safe.lights.material == alias.lights.material && safe.lights.mapSamplingComponents.y == 0
        contracts["unsafeTargetStillRejected"]=alias.validated(for:target()) == nil
        // Native compressed candidates are loaded through the same data path.
        let colorBlock:[UInt8]=[0,248,0,248,0,0,0,0]
        let formats:[(UInt32,[UInt8],Float)]=[(7,colorBlock,1),(6,Array(repeating:136,count:8)+colorBlock,8.0/15),(4,[128,128,0,0,0,0,0,0]+colorBlock,128.0/255)]
        for (format,bytes,alpha) in formats {
            let c=load("bc\(format)",tex(bytes,flags:flags,format:format))
            let pixel=render(.resolve(c,kind:.materialMap),allowed:8,emission:SIMD4(1,1,1,1),source:[0,0,0,1])
            contracts["texFormat\(format)PixelFormat\(c.pixelFormat.rawValue)Alpha"]=abs(pixel[0]-alpha)<0.002
        }
        // Full origin/axes applied once. Same atlas, independent map sampler.
        let atlasBytes=(0..<32).flatMap { i -> [UInt8] in [0,0,0,i%8<4 ? 0:255] }
        let atlas=load("atlas",tex(atlasBytes,flags:UInt32(8)<<20,width:8))
        func frame(_ uv:SceneTextureUVTransform,_ sampling:SceneTextureSampling?=nil)->SceneTextureCandidate {
            SceneTextureCandidate(texture:atlas.texture,identity:atlas.identity,generation:atlas.generation,purpose:atlas.purpose,content:atlas.content,physicalSize:atlas.physicalSize,mappedSize:atlas.mappedSize,uvTransform:uv,sampling:sampling ?? atlas.sampling,authoredFormat:atlas.authoredFormat)
        }
        let left=frame(.init(origin:.zero,xAxis:SIMD2(0.5,0),yAxis:SIMD2(0,1)))
        let right=frame(.init(origin:SIMD2(0.5,0),xAxis:SIMD2(0.5,0),yAxis:SIMD2(0,1)))
        func alpha(_ c:SceneTextureCandidate)->Float { render(.resolve(c,kind:.materialMap),allowed:8,emission:SIMD4(repeating:1),source:[0,0,0,1])[0] }
        contracts["exactOwnFrame"]=alpha(left)==0 && alpha(right)==1
        let linear=frame(.identity),nearest=frame(.identity,atlas.sampling.applying(clampUVs:true,noInterpolation:true))
        contracts["exactOwnSampler"]=abs(alpha(linear)-0.5)<0.002 && alpha(nearest)==1
        var gridBytes:[UInt8]=[]
        for i in 0..<64 { let a=UInt8(4*(i%8)+24*(i/8));gridBytes.append(contentsOf:[0,0,0,a]) }
        let grid=load("grid",tex(gridBytes,flags:UInt32(8)<<20,width:8,height:8))
        let gridFrame=SceneTextureCandidate(texture:grid.texture,identity:grid.identity,generation:grid.generation,purpose:grid.purpose,content:grid.content,physicalSize:grid.physicalSize,mappedSize:grid.mappedSize,uvTransform:.init(origin:SIMD2(0.5,0.25),xAxis:SIMD2(0.5,0),yAxis:SIMD2(0,0.25)),sampling:grid.sampling)
        let expectedGrid=Float(Float16(82.0/255))
        contracts["fullXYFrameExactlyOnce"]=abs(alpha(gridFrame)-expectedGrid)<=Float(Float16(expectedGrid).ulp)
        let registry=SceneFrameTextureRegistry(),request=SceneFrameTextureIdentity.asset(.init(virtualPath:"valid.tex",purpose:.mask)!)
        registry.set(.init(requestIdentity:request,candidate:valid,contentGeneration:1),for:request)
        contracts["mapPublicationReady"]=Capture.TextureInput.resolve(registry.lookup(request),kind:.materialMap).status == "ready"
        let normalCandidate=load("purpose-normal",tex(Array(repeating:rgba,count:16).flatMap{$0},flags:flags),purpose:.normal)
        registry.set(.init(requestIdentity:request,candidate:normalCandidate,contentGeneration:2),for:request)
        let wrongPurpose=Capture.TextureInput.resolve(registry.lookup(request),kind:.materialMap)
        contracts["wrongPurposePublicationInvalid"]=wrongPurpose.status == "invalid" && render(wrongPurpose,intensity:1)==fallback
        registry.set(.init(requestIdentity:request,candidate:valid,contentGeneration:3),for:request)
        registry.set(.init(requestIdentity:request,candidate:invalid,contentGeneration:2),for:request)
        contracts["stalePublicationKeepsCurrent"]=Capture.TextureInput.resolve(registry.lookup(request),kind:.materialMap).status == "ready"
        if case let .loaded(png)=loader.loadCandidate(from:work.appendingPathComponent("headerless.png"),purpose:.mask,device:device) {
            contracts["headerlessDoesNotInventPresence"]=Capture.TextureInput.resolve(png,kind:.materialMap).status == "unsupported"
        } else { contracts["headerlessDoesNotInventPresence"]=false }
        let rg=load("unsupported-rg",tex(Array(repeating:[UInt8(255),128],count:16).flatMap{$0},flags:flags,format:8))
        contracts["partialDataFormatUnsupported"]=Capture.TextureInput.resolve(rg,kind:.materialMap).status == "unsupported"
        guard case let .loaded(color)=loader.loadCandidate(from:work.appendingPathComponent("valid.tex"),purpose:.premultipliedColor,device:device) else { fatalError("color purpose") }
        contracts["samePathColorDataPurposeIsolation"]=valid.texture !== color.texture && valid.content != color.content
        var animated=tex(atlasBytes,flags:(UInt32(8)<<20)|4,width:8)
        animated.append(Data("TEXS0002\0".utf8));var count:UInt32=2;withUnsafeBytes(of:&count){animated.append(contentsOf:$0)}
        for x:Float in [0,4] { var index:UInt32=0;withUnsafeBytes(of:&index){animated.append(contentsOf:$0)};for value:Float in [0.1,x,0,4,0,0,4] { var f=value;withUnsafeBytes(of:&f){animated.append(contentsOf:$0)} } }
        try animated.write(to:work.appendingPathComponent("animated.tex"))
        let identity=SceneAssetTextureIdentity(virtualPath:"animated.tex",purpose:.mask)!
        let catalog=SceneMaterialAssetTextureCatalog(demands:[identity],resourceView:.init(projectRootURL:work,packageRootURL:nil),descriptor:.init(),device:device)
        let provider=catalog.makeFrameProvider()
        func at(_ t:Double)->SceneTextureProviderPublication { guard case let .ready(p)=provider.states(sceneTime:t)[identity] else { fatalError("frame") };return p }
        let a=at(0);provider.commitFrame();let b=at(0.15);provider.discardFrame();let retry=at(0.15);provider.commitFrame()
        contracts["actualFrameProvider"]=a.texture === b.texture && alpha(a.candidate)==0 && alpha(b.candidate)==1
        contracts["cancelRetryGeneration"]=b.contentGeneration == retry.contentGeneration
        contracts["metadataInAtom"]=a.candidate.sampling.rawFlags == (UInt32(8)<<20)|4 && a.contentGeneration != b.contentGeneration
        // Cache admission is optional; native GPU residency admission is not.
        let metadataOnly=SceneTextureCandidate(texture:a.texture,identity:a.candidate.identity,generation:a.candidate.generation,purpose:a.candidate.purpose,content:a.candidate.content,physicalSize:a.candidate.physicalSize,mappedSize:a.candidate.mappedSize,uvTransform:a.candidate.uvTransform,sampling:.init(texFlags:4))
        let changed=SceneTextureProviderPublication(requestIdentity:a.requestIdentity,candidate:metadataOnly,contentGeneration:a.contentGeneration)
        contracts["metadataChangesPublicationAtom"] = !a.isSameAtom(as:changed)
        let skew=frame(.init(origin:.zero,xAxis:SIMD2(0.5,0.1),yAxis:SIMD2(0,0.5)))
        contracts["skewRemainsUnsupported"]=Capture.TextureInput.resolve(skew,kind:.materialMap).status == "unsupported"
        let budget=SceneTextureDecodeCacheBudget(maximumBytes:1)
        var uncached:SceneTextureLoader?=SceneTextureLoader(decodeCacheBudget:budget)
        let url=work.appendingPathComponent("valid.tex")
        if case .loaded=uncached!.loadCandidate(from:url,purpose:.mask,device:device) {
            contracts["cacheDenialKeepsLoad"]=budget.rejectionCount > 0 && budget.residentBytes == 0
        } else { contracts["cacheDenialKeepsLoad"]=false }
        uncached=nil;contracts["cacheReleased"]=budget.residentBytes == 0
        let quota=SceneResourceBudget.shared,baseline=quota.snapshot
        let reservation=quota.maximumBytes-baseline.residentBytes
        precondition(quota.reserve(reservation,kind:.gpu))
        var failedInput:Capture.TextureInput = .disabled
        do {
            defer { quota.release(reservation,kind:.gpu) }
            let fresh=SceneTextureLoader(decodeCacheBudget:SceneTextureDecodeCacheBudget(maximumBytes:1))
            switch fresh.loadCandidate(from:url,purpose:.mask,device:device) {
            case let .loaded(candidate):failedInput = .resolve(candidate,kind:.materialMap);contracts["realBudgetDenial"]=false
            case .failed:failedInput = .unavailable;contracts["realBudgetDenial"]=quota.snapshot.rejectionCount > baseline.rejectionCount
            }
        }
        contracts["budgetReleased"]=quota.snapshot.residentBytes == baseline.residentBytes
        contracts["budgetFailureKeepsScalar"]=render(failedInput,intensity:1)==fallback
        let retryLoader=SceneTextureLoader(decodeCacheBudget:SceneTextureDecodeCacheBudget(maximumBytes:1))
        if case let .loaded(candidate)=retryLoader.loadCandidate(from:url,purpose:.mask,device:device) {
            contracts["budgetReleaseRetriesSource"]=render(.resolve(candidate,kind:.materialMap),intensity:1) != fallback
        } else { contracts["budgetReleaseRetriesSource"]=false }
        print(String(decoding:try JSONSerialization.data(withJSONObject:["vectors":records,"contracts":contracts],options:[.sortedKeys]),as:UTF8.self))
    }
}
