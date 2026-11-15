extension Harness {
    static func catalogFrameCases(device: MTLDevice, loader: SceneTextureLoader,
                                  directory: URL, library: MTLLibrary) throws -> [String:Any] {
        func write(_ name: String, _ data: Data) throws -> URL {
            let url=directory.appendingPathComponent(name+".tex");try data.write(to:url)
            if let evidence=ProcessInfo.processInfo.environment["MWX_TEXTURE_CANDIDATE_EVIDENCE"] {
                let saved=URL(fileURLWithPath:evidence).appendingPathComponent("catalog-frame-inputs")
                try FileManager.default.createDirectory(at:saved,withIntermediateDirectories:true)
                try FileManager.default.copyItem(at:url,to:saved.appendingPathComponent(url.lastPathComponent))
            }
            return url
        }
        func frames(_ data: Data, _ coordinates: [[Float]], duration: Float=0.25) -> Data {
            var result=data;result.removeLast(36);append(UInt32(coordinates.count),to:&result)
            for frame in coordinates { appendSpriteFrame(imageIndex:0,duration:duration,coordinates:frame,to:&result) }
            return result
        }
        let raw=try Data(contentsOf:directory.appendingPathComponent("single-frame.tex"))
        let embedded=try Data(contentsOf:directory.appendingPathComponent("single-frame-legacy-embedded.tex"))
        let rawFrames: [[Float]]=[[2,0,4,0,0,2],[0,2,4,0,0,2]]
        let embeddedFrames: [[Float]]=[[0,0,2,0,0,4],[2,0,2,0,0,4]]
        let rawURL=try write("catalog-raw",frames(raw,rawFrames))
        let embeddedData=frames(embedded,embeddedFrames)
        let embeddedURL=try write("catalog-embedded",embeddedData)
        let renamedURL=try write("renamed-catalog-region",embeddedData)
        let left=Array(repeating:[255,0,0,255,255,255,255,0] as [UInt8],count:4).flatMap{$0}
        let leftURL=try write("catalog-independent-left",embeddedImageTex(textureWidth:2,textureHeight:4,
            imageWidth:2,imageHeight:4,payload:Data(left),flags:3))
        let red=Array(repeating:[255,0,0,255] as [UInt8],count:8).flatMap{$0}
        let redURL=try write("catalog-independent-red",embeddedImageTex(textureWidth:4,textureHeight:2,
            imageWidth:4,imageHeight:2,payload:Data(red),flags:3))
        let row: [UInt8]=[255,0,255,255,255,0,0,255,0,255,0,255,0,0,255,255,255,255,0,255]
        let pixels=Data(Array(repeating:row,count:3).flatMap{$0})
        var non2=embeddedImageTex(textureWidth:8,textureHeight:4,imageWidth:5,imageHeight:3,
            payload:try encodedImageData(width:5,height:3,type:"public.png" as CFString,pixels:pixels),flags:7)
        non2.append(Data("TEXS0002\0".utf8));append(2,to:&non2)
        for frame: [Float] in [[1,0,2,0,0,3],[3,0,2,0,0,3]] { appendSpriteFrame(imageIndex:0,duration:0.25,coordinates:frame,to:&non2) }
        let non2URL=try write("catalog-non-two-ratio",non2)
        let non2Left=Data(Array(repeating:Array(row[4..<12]),count:3).flatMap{$0})
        let non2Right=Data(Array(repeating:Array(row[12..<20]),count:3).flatMap{$0})
        let non2LeftURL=try write("catalog-non-two-left",embeddedImageTex(textureWidth:2,textureHeight:3,imageWidth:2,imageHeight:3,payload:non2Left,flags:3))
        let non2RightURL=try write("catalog-non-two-right",embeddedImageTex(textureWidth:2,textureHeight:3,imageWidth:2,imageHeight:3,payload:non2Right,flags:3))
        let longURL=try write("catalog-long-duration",frames(raw,rawFrames,duration:.greatestFiniteMagnitude))
        let badSourceURL=try write("catalog-outside-decoded",frames(embedded,[embeddedFrames[0],[6,0,2,0,0,4]]))
        let zeroURL=try write("catalog-zero-axis",frames(raw,[rawFrames[0],[2,0,0,0,0,2]]))
        let invalidDurationURL=try write("catalog-negative-duration",frames(raw,rawFrames,duration:-1))
        let crossURL=try write("catalog-cross-image",crossImageSpriteBC3Tex())
        typealias Sample=(name:String,url:URL,purpose:SceneTextureLoadPurpose,references:[URL],uvs:[SceneTextureUVTransform],size:CGSize,mapped:CGSize)
        var samples: [Sample]=[]
        for purpose: SceneTextureLoadPurpose in [.straightAlbedo,.premultipliedColor,.normal,.mask] {
            samples.append(("raw-"+purpose.reportToken,rawURL,purpose,
                [directory.appendingPathComponent("single-frame-independent-crop.tex"),redURL],
                [.init(origin:SIMD2(0.25,0),xAxis:SIMD2(0.5,0),yAxis:SIMD2(0,0.5)),.init(origin:SIMD2(0,0.5),xAxis:SIMD2(0.5,0),yAxis:SIMD2(0,0.5))],
                CGSize(width:8,height:4),CGSize(width:6,height:4)))
        }
        for purpose: SceneTextureLoadPurpose in [.straightAlbedo,.premultipliedColor] {
            for url in [embeddedURL,renamedURL] {
                samples.append((url.deletingPathExtension().lastPathComponent+"-"+purpose.reportToken,url,purpose,
                    [leftURL,directory.appendingPathComponent("single-frame-embedded-independent-crop.tex")],
                    [.init(origin:.zero,xAxis:SIMD2(0.5,0),yAxis:SIMD2(0,1)),.init(origin:SIMD2(0.5,0),xAxis:SIMD2(0.5,0),yAxis:SIMD2(0,1))],
                    CGSize(width:4,height:4),CGSize(width:4,height:4)))
            }
            samples.append(("non-two-"+purpose.reportToken,non2URL,purpose,[non2LeftURL,non2RightURL],
                [.init(origin:SIMD2(0.2,0),xAxis:SIMD2(0.4,0),yAxis:SIMD2(0,1)),.init(origin:SIMD2(0.6,0),xAxis:SIMD2(0.4,0),yAxis:SIMD2(0,1))],
                CGSize(width:5,height:3),CGSize(width:5,height:3)))
        }
        let identities=samples.map{SceneAssetTextureIdentity(virtualPath:$0.url.lastPathComponent,purpose:$0.purpose)!}
        let long=SceneAssetTextureIdentity(virtualPath:longURL.lastPathComponent,purpose:.mask)!
        let bad=SceneAssetTextureIdentity(virtualPath:badSourceURL.lastPathComponent,purpose:.straightAlbedo)!
        let zero=SceneAssetTextureIdentity(virtualPath:zeroURL.lastPathComponent,purpose:.mask)!
        let negative=SceneAssetTextureIdentity(virtualPath:invalidDurationURL.lastPathComponent,purpose:.mask)!
        let cross=SceneAssetTextureIdentity(virtualPath:crossURL.lastPathComponent,purpose:.straightAlbedo)!
        let catalog=try SceneMaterialAssetTextureCatalog(demands:Set(identities+[long,bad,zero,negative,cross]),
            resourceView:.init(projectRootURL:directory,packageRootURL:nil),descriptor:.init(),device:device)
        let provider=catalog.makeFrameProvider();var contracts: [String:Bool]=[:];var rows: [[String:Any]]=[]
        for (phase,time) in [0.0,0.375,0.5].enumerated() {
            let states=provider.states(sceneTime:time);provider.commitFrame()
            for (index,sample) in samples.enumerated() {
                let expectedIndex=phase == 1 ? 1:0
                let reference=try candidate(loader.loadCandidate(from:sample.references[expectedIndex],purpose:sample.purpose,device:device))
                let expected=try renderCandidate(reference,library:library,device:device)
                var row: [String:Any]=["name":sample.name,"phase":phase,"time":time,"expected":expected]
                let key=sample.name+"-phase\(phase)"
                if case let .ready(publication)=states[identities[index]] {
                    let registry=SceneFrameTextureRegistry(),request=SceneFrameTextureIdentity.asset(identities[index])
                    registry.set(publication,for:request)
                    if case let .ready(resource)?=registry.lookup(request) {
                        let c=resource.publication.candidate,actual=try renderCandidate(c,library:library,device:device)
                        row["pixel"]=actual;row["generation"]=publication.contentGeneration
                        row["uv"]=[c.uvTransform.origin.x,c.uvTransform.origin.y,c.uvTransform.xAxis.x,c.uvTransform.xAxis.y,c.uvTransform.yAxis.x,c.uvTransform.yAxis.y]
                        contracts[key]=publication.isComplete && c.isSpriteSheet && c.purpose == sample.purpose
                            && c.physicalSize == sample.size && c.mappedSize == sample.mapped
                            && c.uvTransform == sample.uvs[expectedIndex] && c.sampling.rawFlags == 7 && actual == expected
                    } else { contracts[key]=false }
                } else { contracts[key]=false }
                rows.append(row)
            }
        }
        let first=provider.states(sceneTime:0.375);provider.discardFrame()
        let retry=provider.states(sceneTime:0.375);provider.commitFrame()
        contracts["discardRetryKeepsFrameGeneration"]=identities.allSatisfy { identity in
            guard case let .ready(a)=first[identity],case let .ready(b)=retry[identity] else { return false }
            return a.isSameAtom(as:b)
        }
        let maximum=Double(Float.greatestFiniteMagnitude);var longRows: [[String:Any]]=[]
        for (index,time) in [0,1.5*maximum,2*maximum].enumerated() {
            var row: [String:Any]=["time":time]
            let expected = index == 1 ? [255,0,0,255]:[32,64,128,255]
            if case let .ready(publication)=provider.states(sceneTime:time)[long] {
                let actual=try renderCandidate(publication.candidate,library:library,device:device)
                row["pixel"]=actual;row["generation"]=publication.contentGeneration
                contracts["longDurationPhase\(index)"]=actual == expected
            } else { contracts["longDurationPhase\(index)"]=false }
            provider.commitFrame();longRows.append(row)
        }
        contracts["decodedBoundsIsMetadataLocal"]=catalog.launchStates[bad] == .effectLocalUnavailable(.animatedFrameMetadataInvalid)
        contracts["zeroAxisIsMetadataLocal"]=catalog.launchStates[zero] == .effectLocalUnavailable(.animatedFrameMetadataInvalid)
        contracts["readerBadDurationRemainsHard"]=catalog.launchStates[negative] == .unavailable
        contracts["crossImageRemainsUnsupported"]=catalog.launchStates[cross] == .unavailable
        return ["contracts":contracts,"rows":rows,"longDuration":longRows]
    }

    static func singleFrameCases(device: MTLDevice, loader: SceneTextureLoader,
                                 directory: URL, library: MTLLibrary) throws -> [String: Any] {
        let crop: [UInt8] = [0,255,0,255, 255,255,255,0, 200,100,50,255, 255,255,0,255,
                             0,0,255,255, 255,0,255,255, 64,128,255,128, 0,255,255,255]
        var atlas = Array(repeating: [255,0,0,255] as [UInt8], count: 32).flatMap { $0 }
        for y in 0..<2 {
            atlas.replaceSubrange((y*8+2)*4..<(y*8+6)*4, with: crop[y*16..<(y+1)*16])
        }
        let frame: [Float] = [2,0,4,0,0,2]
        func sheet(_ frames: [[Float]], duration: Float = 0.25) -> Data {
            var data = embeddedImageTex(textureWidth: 8, textureHeight: 4,
                imageWidth: 6, imageHeight: 4, payload: Data(atlas), flags: 7)
            data.append(Data("TEXS0002\0".utf8)); append(UInt32(frames.count), to: &data)
            for coordinates in frames {
                appendSpriteFrame(imageIndex: 0, duration: duration,
                    coordinates: coordinates, to: &data)
            }
            return data
        }
        func write(_ name: String, _ data: Data) throws -> URL {
            let url = directory.appendingPathComponent(name + ".tex")
            try data.write(to: url)
            if let evidence = ProcessInfo.processInfo.environment["MWX_TEXTURE_CANDIDATE_EVIDENCE"] {
                let saved = URL(fileURLWithPath: evidence).appendingPathComponent("single-frame-inputs")
                try FileManager.default.createDirectory(at: saved, withIntermediateDirectories: true)
                try FileManager.default.copyItem(at: url, to: saved.appendingPathComponent(url.lastPathComponent))
            }
            return url
        }
        let referenceURL = try write("single-frame-independent-crop", embeddedImageTex(
            textureWidth: 4, textureHeight: 2, imageWidth: 4, imageHeight: 2,
            payload: Data(crop), flags: 3))
        let reference = try candidate(loader.loadCandidate(from: referenceURL,
            purpose: .straightAlbedo, device: device))
        let referencePixel = try renderCandidate(reference,library:library,device:device)
        var contracts = ["independentCropLiteralPixel": referencePixel == [32,64,128,255],
                         "independentCropRemainsStatic": !reference.isSpriteSheet
                            && reference.uvTransform == .identity]
        var rows: [[String: Any]] = []
        let positiveCases: [(String,Float)] = [("single-frame",0.25), ("renamed-constant-region",0.25), ("single-zero-duration",0)]
        for (name, duration) in positiveCases {
            let data = sheet([frame], duration: duration), url = try write(name, data)
            let outcome = try loader.loadCandidate(from: url, purpose: .straightAlbedo, device: device)
            var row: [String: Any] = ["path":url.lastPathComponent,"duration":duration,"frameCount":1]
            if case let .loaded(c) = outcome {
                let actual = try renderCandidate(c,library:library,device:device)
                row["status"] = "loaded"; row["pixel"] = actual
                row["physical"] = [c.physicalSize.width,c.physicalSize.height]
                row["mapped"] = [c.mappedSize.width,c.mappedSize.height]
                row["uv"] = [c.uvTransform.origin.x,c.uvTransform.origin.y,c.uvTransform.xAxis.x,c.uvTransform.xAxis.y,c.uvTransform.yAxis.x,c.uvTransform.yAxis.y]
                contracts[name + "Ready"] = true
                contracts[name + "Metadata"] = c.isSpriteSheet && c.purpose == .straightAlbedo
                    && c.content == .color(.resolved(.straightAlpha))
                    && c.physicalSize == CGSize(width:8,height:4) && c.mappedSize == CGSize(width:6,height:4)
                    && c.uvTransform == .init(origin:SIMD2(0.25,0),xAxis:SIMD2(0.5,0),yAxis:SIMD2(0,0.5))
                    && c.sampling.rawFlags == 7 && c.sampling.filter == .nearest
                    && c.sampling.addressMode == .clampToEdge && c.authoredFormat?.rawValue == 0
                    && filePath(c.identity) == url.resolvingSymlinksInPath().standardizedFileURL.path
                    && generationByteCount(c.generation) == UInt64(data.count)
                contracts[name + "PixelMatchesIndependent"] = actual == referencePixel
            } else {
                row["status"] = "failed"
                for suffix in ["Ready","Metadata","PixelMatchesIndependent"] { contracts[name + suffix] = false }
            }
            rows.append(row)
        }
        let singleURL = directory.appendingPathComponent("single-frame.tex")
        for purpose: SceneTextureLoadPurpose in [.normal,.mask,.noise] {
            let label = purpose.reportToken
            if case let .loaded(c) = try loader.loadCandidate(from:singleURL,purpose:purpose,device:device) {
                let actual = try renderCandidate(c,library:library,device:device)
                contracts[label + "SingleFrameData"] = c.purpose == purpose && c.content == .data
                    && c.isSpriteSheet && c.uvTransform == .init(origin:SIMD2(0.25,0),xAxis:SIMD2(0.5,0),yAxis:SIMD2(0,0.5))
                    && c.physicalSize == CGSize(width:8,height:4) && c.mappedSize == CGSize(width:6,height:4)
                    && c.sampling.rawFlags == 7 && actual == referencePixel
            } else { contracts[label + "SingleFrameData"] = false }
        }
        func png(_ pixels: [UInt8], width: Int, height: Int) throws -> Data {
            guard let provider = CGDataProvider(data: Data(pixels) as CFData),
                  let image = CGImage(width:width,height:height,bitsPerComponent:8,bitsPerPixel:32,
                    bytesPerRow:width*4,space:CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo:.init(rawValue:CGImageAlphaInfo.last.rawValue),provider:provider,
                    decode:nil,shouldInterpolate:false,intent:.defaultIntent) else { throw HarnessError.imageCreationFailed }
            return try encodeImage(image,type:"public.png" as CFString)
        }
        let embeddedRow: [UInt8] = [255,0,0,255, 255,255,255,0, 0,0,255,255, 255,255,0,255]
        let embeddedPixels = Array(repeating:embeddedRow,count:4).flatMap{$0}
        let embeddedCrop = Array(repeating:Array(embeddedRow[8..<16]),count:4).flatMap{$0}
        var embedded = embeddedImageTex(textureWidth:8,textureHeight:4,imageWidth:4,imageHeight:4,
            payload:try png(embeddedPixels,width:4,height:4),flags:7)
        embedded.append(Data("TEXS0002\0".utf8));append(1,to:&embedded)
        appendSpriteFrame(imageIndex:0,duration:0.25,coordinates:[2,0,2,0,0,4],to:&embedded)
        let embeddedURL = try write("single-frame-legacy-embedded",embedded)
        let embeddedReferenceURL = try write("single-frame-embedded-independent-crop",embeddedImageTex(
            textureWidth:2,textureHeight:4,imageWidth:2,imageHeight:4,
            payload:try png(embeddedCrop,width:2,height:4),flags:3))
        var embeddedRows: [[String:Any]] = []
        for purpose: SceneTextureLoadPurpose in [.straightAlbedo,.premultipliedColor] {
            let key = purpose.reportToken
            let reference = try candidate(loader.loadCandidate(from:embeddedReferenceURL,purpose:purpose,device:device))
            let expected = try renderCandidate(reference,library:library,device:device)
            var row: [String:Any] = ["purpose":key,"referencePixel":expected]
            if case let .loaded(c) = try loader.loadCandidate(from:embeddedURL,purpose:purpose,device:device) {
                let actual = try renderCandidate(c,library:library,device:device)
                row["status"] = "loaded";row["pixel"] = actual
                row["physical"] = [c.physicalSize.width,c.physicalSize.height]
                row["uv"] = [c.uvTransform.origin.x,c.uvTransform.origin.y,c.uvTransform.xAxis.x,c.uvTransform.xAxis.y,c.uvTransform.yAxis.x,c.uvTransform.yAxis.y]
                contracts[key + "EmbeddedFramePixels"] = actual == expected && expected == [255,255,0,255]
                contracts[key + "EmbeddedFrameMetadata"] = c.isSpriteSheet && c.purpose == purpose
                    && c.physicalSize == CGSize(width:4,height:4) && c.mappedSize == CGSize(width:4,height:4)
                    && c.uvTransform == .init(origin:SIMD2(0.5,0),xAxis:SIMD2(0.5,0),yAxis:SIMD2(0,1))
            } else {
                row["status"] = "failed"
                contracts[key + "EmbeddedFramePixels"] = false
                contracts[key + "EmbeddedFrameMetadata"] = false
            }
            embeddedRows.append(row)
        }
        var outOfSource = embedded
        outOfSource.removeLast(32)
        appendSpriteFrame(imageIndex:0,duration:0.25,coordinates:[6,0,2,0,0,4],to:&outOfSource)
        let outOfSourceURL = try write("single-frame-embedded-out-of-source",outOfSource)
        for purpose: SceneTextureLoadPurpose in [.straightAlbedo,.premultipliedColor] {
            let outcome = try loader.loadCandidate(from:outOfSourceURL,purpose:purpose,device:device)
            if case .failed(.decodeFailed) = outcome {
                contracts[purpose.reportToken + "EmbeddedActualSourceBounds"] = true
            } else { contracts[purpose.reportToken + "EmbeddedActualSourceBounds"] = false }
        }
        let negativeCases: [(String,[[Float]])] = [("multi-frame",[frame,frame]),
                               ("single-zero-area",[[Float(2),0,0,0,0,2]]),
                               ("single-nonfinite",[[Float.nan,0,4,0,0,2]]),
                               ("single-outbound",[[Float(7),0,4,0,0,2]])]
        for (name, frames) in negativeCases {
            let url = try write(name,sheet(frames))
            let rejected: Bool
            if case .failed(.decodeFailed) = try loader.loadCandidate(from:url,purpose:.straightAlbedo,device:device) {
                rejected = true
            } else { rejected = false }
            contracts[name + "Rejected"] = rejected
        }
        let affine = try affineFrameCases(device:device,loader:loader,directory:directory,library:library)
        return ["contracts":contracts,"rows":rows,"embeddedRows":embeddedRows,"referencePixel":referencePixel,"affine":affine,
                "scope":"Production Loader candidate and source shader frame sampling; no model or normal-lighting claim."]
    }

    static func affineFrameCases(device: MTLDevice, loader: SceneTextureLoader,
                                 directory: URL, library: MTLLibrary) throws -> [String:Any] {
        func write(_ name: String, _ data: Data) throws -> URL {
            let url=directory.appendingPathComponent(name+".tex");try data.write(to:url)
            if let evidence=ProcessInfo.processInfo.environment["MWX_TEXTURE_CANDIDATE_EVIDENCE"] {
                let saved=URL(fileURLWithPath:evidence).appendingPathComponent("single-frame-inputs")
                try FileManager.default.createDirectory(at:saved,withIntermediateDirectories:true)
                try FileManager.default.copyItem(at:url,to:saved.appendingPathComponent(url.lastPathComponent))
            }
            return url
        }
        var pixels:[UInt8]=[]
        for y in 0..<8 { for x in 0..<8 { pixels += [UInt8(20+3*x),UInt8(30+5*y),UInt8(40+x+7*y),255] } }
        let coordinates:[[Float]]=[[6.5,0.5,0,4,-4,0],[6.5,0.5,-4,0,0,4],[0.5,0.5,4,0,2,4]]
        let names=["rotate","mirror","skew"]
        let expectedUV:[[Float]]=[[0.8125,0.0625,0,0.5,-0.5,0],[0.8125,0.0625,-0.5,0,0,0.5],[0.0625,0.0625,0.5,0,0.25,0.5]]
        let expectedPixels=[[32,40,58,255],[32,40,58,255],[29,40,57,255]]
        func sheet(_ frames:[[Float]], embedded:Bool=false) throws -> Data {
            var data:Data
            if embedded {
                let image=try encodedImageData(width:4,height:4,type:"public.png" as CFString,
                    pixels:Data(Array(repeating:[UInt8(33),66,99,255],count:16).flatMap{$0}))
                data=embeddedImageTex(textureWidth:8,textureHeight:4,imageWidth:4,imageHeight:4,payload:image,flags:7)
            } else {
                data=embeddedImageTex(textureWidth:8,textureHeight:8,imageWidth:8,imageHeight:8,payload:Data(pixels),flags:7)
            }
            data.append(Data("TEXS0002\0".utf8));append(UInt32(frames.count),to:&data)
            for frame in frames { appendSpriteFrame(imageIndex:0,duration:0.25,coordinates:frame,to:&data) }
            return data
        }
        var contracts:[String:Bool]=[:],rows:[[String:Any]]=[]
        func observe(_ name:String,_ url:URL,_ expected:[Float],_ pixel:[Int],_ extent:Int) throws {
            var row:[String:Any]=["name":name,"path":url.lastPathComponent,"expectedUV":expected,"expectedPixel":pixel]
            if case let .loaded(c)=try loader.loadCandidate(from:url,purpose:.straightAlbedo,device:device) {
                let actual=try renderCandidate(c,library:library,device:device)
                let uv=[c.uvTransform.origin.x,c.uvTransform.origin.y,c.uvTransform.xAxis.x,c.uvTransform.xAxis.y,c.uvTransform.yAxis.x,c.uvTransform.yAxis.y]
                row["status"]="loaded";row["uv"]=uv;row["pixel"]=actual
                contracts[name]=uv == expected && actual == pixel && c.isSpriteSheet
                    && c.physicalSize == CGSize(width:extent,height:extent) && c.sampling.rawFlags == 7
            } else { row["status"]="failed";contracts[name]=false }
            rows.append(row)
        }
        for index in names.indices {
            let url=try write("affine-single-"+names[index],sheet([coordinates[index]]))
            try observe(names[index],url,expectedUV[index],expectedPixels[index],8)
        }
        let renamed=try write("independent-affine-resource",sheet([coordinates[1]]))
        try observe("renamed",renamed,expectedUV[1],expectedPixels[1],8)
        let legacyFrames:[[Float]]=[[3.5,0.5,0,2,-2,0],[3.5,0.5,-2,0,0,2],[0.5,0.5,2,0,1,2]]
        let legacyUV:[[Float]]=[[0.875,0.125,0,0.5,-0.5,0],[0.875,0.125,-0.5,0,0,0.5],[0.125,0.125,0.5,0,0.25,0.5]]
        let legacy=try write("affine-single-legacy",sheet([legacyFrames[0]],embedded:true))
        try observe("legacy",legacy,legacyUV[0],[33,66,99,255],4)
        let multi=try write("affine-catalog",sheet(coordinates))
        let multiRename=try write("renamed-affine-catalog",sheet(coordinates))
        let multiLegacy=try write("affine-catalog-legacy",sheet(legacyFrames,embedded:true))
        let badFrames:[(String,[Float])]=[("zero-det",[0,0,2,2,4,4]),
            ("nan",[Float.nan,0,2,0,0,2]),("fourth-corner",[1,1,6,2,2,6])]
        var negatives:[(String,URL)]=[]
        for (name,frame) in badFrames {
            let url=try write("affine-bad-"+name,sheet([frame]));negatives.append((name,url))
            if case .failed(.decodeFailed)=try loader.loadCandidate(from:url,purpose:.straightAlbedo,device:device) {
                contracts[name+"SingleRejected"]=true
            } else { contracts[name+"SingleRejected"]=false }
        }
        let outsideLegacy=try write("affine-bad-source",sheet([[4.5,0.5,0,2,-2,0]],embedded:true))
        negatives.append(("actual-source",outsideLegacy))
        if case .failed(.decodeFailed)=try loader.loadCandidate(from:outsideLegacy,purpose:.straightAlbedo,device:device) {
            contracts["actual-sourceSingleRejected"]=true
        } else { contracts["actual-sourceSingleRejected"]=false }
        let urls=[multi,multiRename,multiLegacy]+negatives.map{$0.1}
        let identities=urls.map{SceneAssetTextureIdentity(virtualPath:$0.lastPathComponent,purpose:.straightAlbedo)!}
        let catalog=try SceneMaterialAssetTextureCatalog(demands:Set(identities),
            resourceView:.init(projectRootURL:directory,packageRootURL:nil),descriptor:.init(),device:device)
        for (offset,bad) in negatives.enumerated() {
            let state=catalog.launchStates[identities[offset+3]]
            contracts[bad.0+"CatalogClassification"]=bad.0 == "nan"
                ? state == .unavailable : state == .effectLocalUnavailable(.animatedFrameMetadataInvalid)
        }
        let provider=catalog.makeFrameProvider();var catalogRows:[[String:Any]]=[]
        for (phase,time) in [0.0,0.375,0.625].enumerated() {
            let states=provider.states(sceneTime:time)
            for index in 0..<3 {
                let expected=index == 2 ? legacyUV[phase]:expectedUV[phase]
                let pixel=index == 2 ? [33,66,99,255]:expectedPixels[phase]
                var row:[String:Any]=["asset":urls[index].lastPathComponent,"phase":phase,"time":time,
                    "expectedUV":expected,"expectedPixel":pixel]
                let key="catalog\(index)-phase\(phase)"
                if case let .ready(publication)=states[identities[index]] {
                    let c=publication.candidate
                    let uv=[c.uvTransform.origin.x,c.uvTransform.origin.y,c.uvTransform.xAxis.x,c.uvTransform.xAxis.y,c.uvTransform.yAxis.x,c.uvTransform.yAxis.y]
                    let actual=try renderCandidate(c,library:library,device:device)
                    row["status"]="ready";row["uv"]=uv;row["pixel"]=actual;row["generation"]=publication.contentGeneration
                    contracts[key]=publication.isComplete && c.isSpriteSheet && uv == expected && actual == pixel
                } else { row["status"]="not-ready";contracts[key]=false }
                catalogRows.append(row)
            }
            provider.commitFrame()
        }
        return ["contracts":contracts,"singleRows":rows,"catalogRows":catalogRows,
            "scope":"Full UV and center samples only; center pixels do not distinguish orientation. NaN is a Reader failure."]
    }

    static func embeddedUploadCases(
        device: MTLDevice,
        loader: SceneTextureLoader,
        directory: URL,
        normalizedColorURL: URL,
        mappedEmbeddedURL: URL,
        mappedTexb3EmbeddedURL: URL,
        oversizedTexb3MipChainURL: URL,
        malformedTexb3EmbeddedURL: URL,
        decodedMismatchTexb3URL: URL,
        lowerMipMismatchTexb3URL: URL,
        freeFormatMismatchTexb3URL: URL,
        mappedTexb3JPEGURL: URL,
        normalizedStraightAlbedoJPEGURL: URL,
        normalizedStraightAlbedoPNGURL: URL,
        transparentStraightAlbedoPNGURL: URL,
        authoredStraightAlbedoMipsPNGURL: URL,
        paddedStraightAlbedoJPEGURL: URL,
        mislabeledTexb4StraightAlbedoPNGURL: URL,
        mappedTexb2MipURL: URL
    ) throws -> (directTransparent: SceneTextureCandidate, result: [String: Any]) {
        let mappedEmbeddedColor = try candidate((try loader.loadCandidate(
            from: mappedEmbeddedURL,
            purpose: .premultipliedColor,
            device: device
        )))
        let mappedEmbeddedNormalRejected = rejectedDimensions(
            (try loader.loadCandidate(
                from: mappedEmbeddedURL,
                purpose: .normal,
                device: device
            ))
        )
        let mappedTexb3EmbeddedColor = try candidate((try loader.loadCandidate(
            from: mappedTexb3EmbeddedURL,
            purpose: .premultipliedColor,
            device: device
        )))
        let oversizedTexb3MipChainColor = try candidate((try loader.loadCandidate(
            from: oversizedTexb3MipChainURL,
            purpose: .premultipliedColor,
            device: device
        )))
        let mappedTexb3EmbeddedNormal = try candidate((try loader.loadCandidate(
            from: mappedTexb3EmbeddedURL,
            purpose: .normal,
            device: device
        )))
        let malformedTexb3EmbeddedRejected = rejectedEmbeddedMetadata(
            (try loader.loadCandidate(
                from: malformedTexb3EmbeddedURL,
                purpose: .premultipliedColor,
                device: device
            ))
        )
        let decodedMismatchTexb3Rejected = rejectedEmbeddedMetadata(
            (try loader.loadCandidate(
                from: decodedMismatchTexb3URL,
                purpose: .premultipliedColor,
                device: device
            ))
        )
        let lowerMipMismatchTexb3Rejected = rejectedEmbeddedMetadata(
            (try loader.loadCandidate(
                from: lowerMipMismatchTexb3URL,
                purpose: .premultipliedColor,
                device: device
            ))
        )
        let freeFormatMismatchTexb3Rejected = rejectedEmbeddedMetadata(
            (try loader.loadCandidate(
                from: freeFormatMismatchTexb3URL,
                purpose: .premultipliedColor,
                device: device
            ))
        )
        let mappedTexb3JPEG = try candidate((try loader.loadCandidate(
            from: mappedTexb3JPEGURL,
            purpose: .premultipliedColor,
            device: device
        )))
        let normalizedStraightAlbedoJPEG = try candidate((try loader.loadCandidate(
            from: normalizedStraightAlbedoJPEGURL,
            purpose: .straightAlbedo,
            device: device
        )))
        let normalizedStraightAlbedoPNG = try candidate((try loader.loadCandidate(
            from: normalizedStraightAlbedoPNGURL,
            purpose: .straightAlbedo,
            device: device
        )))
        let transparentStraightAlbedoPNG = try candidate((try loader.loadCandidate(
            from: transparentStraightAlbedoPNGURL,
            purpose: .straightAlbedo,
            device: device
        )))
        let transparentStraightAlbedoPixel = try readFirstPixel(
            texture: transparentStraightAlbedoPNG.texture, device: device
        )
        let directTransparentURL = directory.appendingPathComponent("transparent-large.png")
        try pngData(width: 4097, height: 2).write(to: directTransparentURL)
        let directTransparent = try candidate((try loader.loadCandidate(
            from: directTransparentURL, purpose: .straightAlbedo, device: device
        )))
        let legacyMappedStraight = try candidate((try loader.loadCandidate(
            from: mappedEmbeddedURL, purpose: .straightAlbedo, device: device)))
        let normalizedLegacyStraight = try candidate((try loader.loadCandidate(
            from: normalizedColorURL, purpose: .straightAlbedo, device: device)))
        let paddedMipsURL = directory.appendingPathComponent("padded-straight-mips.tex")
        try embeddedImageTex(textureWidth: 8192, textureHeight: 8,
            imageWidth: 4096, imageHeight: 8, payload: try pngData(width: 8192, height: 8),
            containerVersion: "TEXB0003", freeImageFormat: 13, mipWidth: 8192, mipHeight: 8,
            additionalMips: [(4096, 4, try pngData(width: 4096, height: 4))]).write(to: paddedMipsURL)
        let paddedStraightMips = try candidate((try loader.loadCandidate(
            from: paddedMipsURL, purpose: .straightAlbedo, device: device)))
        let straightResize = try straightResizeProbe(device: device)
        let authoredStraightAlbedoMipsPNG = try candidate(
            (try loader.loadCandidate(
                from: authoredStraightAlbedoMipsPNGURL,
                purpose: .straightAlbedo,
                device: device
            ))
        )
        let authoredStraightAlbedoMipsPixel = try readFirstPixel(
            texture: authoredStraightAlbedoMipsPNG.texture,
            device: device
        )
        let paddedStraightAlbedoJPEGRejected = rejectedDimensions(
            (try loader.loadCandidate(
                from: paddedStraightAlbedoJPEGURL,
                purpose: .straightAlbedo,
                device: device
            ))
        )
        let mislabeledTexb4StraightAlbedoPNGRejected = rejectedDimensions(
            (try loader.loadCandidate(
                from: mislabeledTexb4StraightAlbedoPNGURL,
                purpose: .straightAlbedo,
                device: device
            ))
        )
        let mappedTexb2MipRejected = rejectedDimensions(
            (try loader.loadCandidate(
                from: mappedTexb2MipURL,
                purpose: .premultipliedColor,
                device: device
            ))
        )
        let result: [String: Any] = [
            "mappedEmbeddedColorIdentity":
                mappedEmbeddedColor.axisAlignedMappedUVScale(
                    expectedPurpose: .premultipliedColor
                ) == SIMD2(repeating: 1),
            "mappedEmbeddedNormalRejected": mappedEmbeddedNormalRejected,
            "mappedTexb3EmbeddedColorIdentity":
                mappedTexb3EmbeddedColor.axisAlignedMappedUVScale(
                    expectedPurpose: .premultipliedColor
                ) == SIMD2(repeating: 1),
            "mappedTexb3EmbeddedColorPreservesMipChain":
                mappedTexb3EmbeddedColor.texture.mipmapLevelCount == 2,
            "oversizedTexb3MipChainPreservesAuthoredBase":
                oversizedTexb3MipChainColor.texture.width == 4097
                    && oversizedTexb3MipChainColor.texture.height == 2
                    && oversizedTexb3MipChainColor.texture.mipmapLevelCount == 2
                    && oversizedTexb3MipChainColor.physicalSize
                        == CGSize(width: 4097, height: 2)
                    && oversizedTexb3MipChainColor.mappedSize
                        == CGSize(width: 4097, height: 2),
            "mappedTexb3EmbeddedNormalIdentity":
                mappedTexb3EmbeddedNormal.axisAlignedMappedUVScale(
                    expectedPurpose: .normal
                ) == SIMD2(repeating: 1),
            "malformedTexb3EmbeddedRejected": malformedTexb3EmbeddedRejected,
            "decodedMismatchTexb3Rejected": decodedMismatchTexb3Rejected,
            "lowerMipMismatchTexb3Rejected": lowerMipMismatchTexb3Rejected,
            "freeFormatMismatchTexb3Rejected":
                freeFormatMismatchTexb3Rejected,
            "mappedTexb3JPEGIdentity":
                mappedTexb3JPEG.axisAlignedMappedUVScale(
                    expectedPurpose: .premultipliedColor
                ) == SIMD2(repeating: 1),
            "mappedTexb3JPEGOpaque":
                mappedTexb3JPEG.content == .color(.resolved(.opaque)),
            "mappedTexb3PNGPreservesAlphaContract":
                mappedTexb3EmbeddedColor.content
                    == .color(.resolved(.premultipliedAlpha)),
            "normalizedStraightAlbedoJPEGIdentity":
                normalizedStraightAlbedoJPEG.axisAlignedMappedUVScale(
                    expectedPurpose: .straightAlbedo
                ) == SIMD2(repeating: 1)
                    && normalizedStraightAlbedoJPEG.texture.width == 4096
                    && normalizedStraightAlbedoJPEG.texture.height == 1,
            "normalizedStraightAlbedoPNGIdentity":
                normalizedStraightAlbedoPNG.axisAlignedMappedUVScale(
                    expectedPurpose: .straightAlbedo
                ) == SIMD2(repeating: 1)
                    && normalizedStraightAlbedoPNG.texture.width == 4096
                    && normalizedStraightAlbedoPNG.texture.height == 1,
            "transparentStraightAlbedoPNG":
                transparentStraightAlbedoPNG.axisAlignedMappedUVScale(
                    expectedPurpose: .straightAlbedo
                ) == SIMD2<Float>(repeating: 1)
                    && transparentStraightAlbedoPNG.texture.width == 4096
                    && transparentStraightAlbedoPNG.texture.height == 1
                    && transparentStraightAlbedoPNG.texture.mipmapLevelCount == 1,
            "transparentStraightAlbedoPixel": transparentStraightAlbedoPixel,
            "directTransparentPNG": directTransparent.texture.width == 4096
                && directTransparent.texture.height == 1
                && directTransparent.texture.mipmapLevelCount == 13
                && directTransparent.axisAlignedMappedUVScale(
                    expectedPurpose: .straightAlbedo) == SIMD2<Float>(repeating: 1),
            "normalizedLegacyStraight": normalizedLegacyStraight.texture.width == 4096
                && normalizedLegacyStraight.texture.height == 1
                && normalizedLegacyStraight.axisAlignedMappedUVScale(
                    expectedPurpose: .straightAlbedo) == SIMD2<Float>(repeating: 1),
            "paddedStraightMips": paddedStraightMips.texture.width == 8192
                && paddedStraightMips.texture.height == 8 && paddedStraightMips.texture.mipmapLevelCount == 2
                && paddedStraightMips.axisAlignedMappedUVScale(
                    expectedPurpose: .straightAlbedo) == SIMD2<Float>(0.5, 1),
            "legacyMappedStraight": legacyMappedStraight.axisAlignedMappedUVScale(
                expectedPurpose: .straightAlbedo) == SIMD2<Float>(repeating: 1),
            "straightResize": straightResize,
            "authoredStraightAlbedoMipsPNG":
                authoredStraightAlbedoMipsPNG.axisAlignedMappedUVScale(
                    expectedPurpose: .straightAlbedo
                ) == SIMD2(repeating: 1)
                    && authoredStraightAlbedoMipsPNG.texture.width == 8192
                    && authoredStraightAlbedoMipsPNG.texture.height == 2
                    && authoredStraightAlbedoMipsPNG.texture.mipmapLevelCount == 2
                    && authoredStraightAlbedoMipsPNG.content
                        == .color(.resolved(.straightAlpha)),
            "authoredStraightAlbedoMipsPixel":
                authoredStraightAlbedoMipsPixel,
            "paddedStraightAlbedoJPEGRejected":
                paddedStraightAlbedoJPEGRejected,
            "mislabeledTexb4StraightAlbedoPNGRejected":
                mislabeledTexb4StraightAlbedoPNGRejected,
            "mappedTexb2MipRejected": mappedTexb2MipRejected,
        ]
        return (directTransparent, result)
    }

    static func straightResizeProbe(device: MTLDevice) throws -> [String: Any] {
        func image(_ pixels: [UInt8], _ width: Int, _ height: Int,
                   alpha: CGImageAlphaInfo = .last) throws -> CGImage {
            guard let provider = CGDataProvider(data: Data(pixels) as CFData),
                  let image = CGImage(width: width, height: height,
                    bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGBitmapInfo(rawValue: alpha.rawValue),
                    provider: provider, decode: nil, shouldInterpolate: false,
                    intent: .defaultIntent) else { throw HarnessError.imageCreationFailed }
            return image
        }
        let colors: [UInt8] = [255,0,0,0, 0,0,255,255]
        let horizontal = try image(colors, 2, 1)
        let vertical = try image(colors, 1, 2)
        let nonInteger = try image([255,0,0,0, 0,0,255,255, 0,255,0,0], 3, 1)
        let zeroAlpha = try image([17,91,203,0, 17,91,203,0], 2, 1)
        let premultiplied = try image(colors, 2, 1, alpha: .premultipliedLast)
        func scaled(_ image: CGImage, width: Int = 1) -> [Int] {
            SceneImageTextureUploader.rgbaData(image: image, width: width, height: 1,
                purpose: .straightAlbedo)?.map(Int.init) ?? []
        }
        let encoded = try encodeImage(horizontal, type: "public.png" as CFString)
        guard let source = CGImageSourceCreateWithData(encoded as CFData, nil),
              let decoded = CGImageSourceCreateImageAtIndex(source, 0, nil),
              case let .loaded(texture) = SceneImageTextureUploader.upload(
                image: decoded, purpose: .straightAlbedo, maxDimension: 1,
                device: device) else { throw HarnessError.loadFailed }
        // A source beyond the previous full-RGBA scratch limit is now
        // sampled directly into the one-pixel output.
        let oversized = try image([UInt8](repeating: 127, count: 4097 * 4096 * 4),
                                  4097, 4096)
        let rows: [UInt8] = [0,0,255,0, 255,0,0,255, 9,9,9,9,
                              0,255,0,128, 255,255,255,64, 9,9,9,9]
        func strided(_ bytes: [UInt8], decode: UnsafePointer<CGFloat>? = nil,
                     order: CGBitmapInfo = .byteOrder32Little) -> CGImage? {
            CGImage(width: 2, height: 2, bitsPerComponent: 8, bitsPerPixel: 32,
                bytesPerRow: 12, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.first.rawValue | order.rawValue),
                provider: CGDataProvider(data: Data(bytes) as CFData)!, decode: decode,
                shouldInterpolate: false, intent: .defaultIntent)
        }
        let stridedImage = strided(rows)!
        let truncated = strided(Array(rows.dropLast()))
        let invalidOrder = strided(rows, order: .byteOrder16Big)
        let invalidDecode = [CGFloat](repeating: 1, count: 8).withUnsafeBufferPointer {
            strided(rows, decode: $0.baseAddress)
        }
        func converted(_ bits: Int, gray: Bool, little: Bool) throws -> [Int] {
            let values: [UInt16] = gray ? [200,0,64,255] : [255,0,0,0,0,0,255,255]
            var bytes: [UInt8] = []
            for (index, value) in values.enumerated() {
                if bits == 8 { bytes.append(UInt8(value)) }
                else {
                    let word: UInt16 = gray ? value * 257 : [65535,0x1234,0,0,0,0,0xABCD,0x8001][index]
                    bytes += little ? [UInt8(word & 255),UInt8(word >> 8)]
                        : [UInt8(word >> 8),UInt8(word & 255)]
                }
            }
            let order: CGBitmapInfo = bits == 16
                ? (little ? .byteOrder16Little : .byteOrder16Big) : .byteOrderDefault
            let space = gray ? CGColorSpaceCreateDeviceGray() : CGColorSpaceCreateDeviceRGB()
            let provider = CGDataProvider(data: Data(bytes) as CFData)!
            let value = CGImage(width: 2, height: 1, bitsPerComponent: bits,
                bitsPerPixel: (gray ? 2 : 4) * bits, bytesPerRow: bytes.count,
                space: space, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue | order.rawValue),
                provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
            let raw = scaled(value)
            let png = try encodeImage(value, type: "public.png" as CFString)
            let source = CGImageSourceCreateWithData(png as CFData, nil)!
            let decoded = CGImageSourceCreateImageAtIndex(source, 0, nil)!
            return raw + scaled(decoded)
        }
        return [
            "stridedFirst": SceneImageTextureUploader.rgbaData(image: stridedImage,
                width: 2, height: 2, purpose: .straightAlbedo)?.map(Int.init) ?? [],
            "stridedResize": scaled(stridedImage),
            "truncatedRejected": truncated.map { scaled($0).isEmpty } ?? true,
            "decodeRejected": invalidDecode.map { scaled($0).isEmpty } ?? true,
            "bitmapRejected": invalidOrder.map { scaled($0).isEmpty } ?? true,
            "gray8": try converted(8, gray: true, little: false),
            "gray16": try converted(16, gray: true, little: false),
            "rgba16Big": try converted(16, gray: false, little: false),
            "rgba16Little": try converted(16, gray: false, little: true),
            "horizontal": scaled(horizontal),
            "vertical": scaled(vertical),
            "nonInteger": scaled(nonInteger, width: 2),
            "zeroAlpha": scaled(zeroAlpha),
            "premultipliedRejected": scaled(premultiplied).isEmpty,
            "dataResizeRejected": SceneImageTextureUploader.rgbaData(
                image: horizontal, width: 1, height: 1, purpose: .normal) == nil,
            "largeSourcePreserved": scaled(oversized) == [127,127,127,127],
            "directPNG": try readFirstPixel(texture: texture, device: device),
        ]
    }
}
