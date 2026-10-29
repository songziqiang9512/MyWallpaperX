import Foundation
import AVFoundation
import Metal
import QuartzCore
import CryptoKit

// Standalone compilation shims for value envelopes outside the provider under test.
// AVPlayer, pixel decoding, Metal textures, lifecycle and command execution are production code.
struct SceneFrameTiming { let frameIndex: UInt64; let hostTime: Double; let sceneTime: Double }
enum ColorRepresentation { case opaque, premultipliedAlpha }
enum ColorResolution { case resolved(ColorRepresentation), unresolved }
enum SceneTextureContent { case color(ColorResolution) }
enum ResourceProvider { case video(layerID: Int, lifecycleEpoch: UInt64), videoAsset(asset: SceneAssetTextureIdentity, sourceIncarnation: UUID, lifecycleEpoch: UInt64), videoUserProperty(property: SceneUserPropertyTextureIdentity, sourceIncarnation: UUID, lifecycleEpoch: UInt64) }
enum ResourceIdentity { case provider(ResourceProvider) }
enum ResourceGeneration { case provider(contentGeneration: UInt64) }
enum TexturePurpose: Equatable { case premultipliedColor }
struct SceneAssetTextureIdentity { let purpose: TexturePurpose }
struct SceneUserPropertyTextureIdentity: Equatable { let propertyKey: String; let purpose: TexturePurpose }
enum SceneShaderTextureFormat { case rgba8888 }
enum SceneVideoTexturePlaybackOwner: Equatable { case ordinary, asset, userProperty(SceneUserPropertyTextureIdentity) }
enum TextureUV { case identity }
enum TextureSampling { case linearClamp }
struct SceneTextureCandidate { let texture: MTLTexture; let identity: ResourceIdentity; let generation: ResourceGeneration; let purpose: TexturePurpose; let content: SceneTextureContent; let physicalSize: CGSize; let mappedSize: CGSize; let uvTransform: TextureUV; let sampling: TextureSampling; var authoredFormat: SceneShaderTextureFormat? = nil }
enum FrameIdentity { case layerSource(Int), asset(SceneAssetTextureIdentity), materialUserProperty(SceneUserPropertyTextureIdentity) }
typealias SceneFrameTextureIdentity = FrameIdentity
typealias SceneTextureProviderIdentity = ResourceProvider
struct SceneTextureProviderPublication {
    let requestIdentity: FrameIdentity; let candidate: SceneTextureCandidate; let contentGeneration: UInt64
    var isComplete: Bool { contentGeneration > 0 }
    var generationIsCurrent: Bool { contentGeneration > 0 }
}

@main enum Harness {
 static var completedSeekPixelRows:[[String:Any]]=[]
 static var seekPixelFailureContext:[String:Any]=[:]
 static func main() throws {
  let root=URL(fileURLWithPath:CommandLine.arguments[1])
  let isWebM=CommandLine.arguments.contains("--webm")
  let data=try Data(contentsOf:root.appendingPathComponent(isWebM ? "clip.webm" : "clip.mp4"))
  guard let device=MTLCreateSystemDefaultDevice() else {fatalError("device unavailable")}
  if isWebM {try scopedWebM(data:data,root:root,device:device);return}
  guard let source=SceneVideoTextureSource(owner:.ordinary,mp4PayloadData:data,isWebM:isWebM,cacheDirectory:root,device:device) else { fatalError("provider unavailable") }
  defer { source.stop() }
  // Observe the actual AVPlayer without changing product APIs or replacing its backend.
  let player=Mirror(reflecting:source).children.compactMap{$0.value as? AVPlayer}.first!
  if CommandLine.arguments.contains("--seek-pixels") {
   do {try seekPixels(source,player,device:device)}
   catch {
    // Observe only after the original failure, before stop clears its evidence.
    let observed=seekFailureFacts(source,player)
    source.stop()
    let failure:[String:Any]=["status":"STOP","failure":String(describing:error),
     "completedRows":completedSeekPixelRows,"stopPlayerItemAbsent":player.currentItem==nil,
     "failureFacts":observed]
    print(String(decoding:try JSONSerialization.data(withJSONObject:failure,options:[.sortedKeys]),as:UTF8.self))
    exit(1)
   }
   return
  }
  if CommandLine.arguments.contains("--eof-discard") { try eofDiscard(source, player, looping: !CommandLine.arguments.contains("--no-loop")); return }
  if CommandLine.arguments.contains("--paused-seek") { try pausedSeek(source); return }
  if CommandLine.arguments.contains("--loop-phase") { try loopPhase(source); return }
  let start=CACurrentMediaTime(); var frame:UInt64=0
  var decodedTimes:[Double]=[]; var requestedTimes:[Double]=[]
  func timing()->SceneFrameTiming {let now=CACurrentMediaTime();frame+=1;return .init(frameIndex:frame,hostTime:now,sceneTime:now-start)}
  func pump(_ duration:Double, repeatPlay:Bool=false)->[Double] {
   let end=CACurrentMediaTime()+duration; var times:[Double]=[];var generation:UInt64=0
   while CACurrentMediaTime()<end {
    let t=timing();if repeatPlay {source.apply(.play,timing:t)}
    if let f=source.currentFrame(for:t),f.contentGeneration != generation { times.append(f.requestedItemTime); if let decoded=f.decodedItemTime { decodedTimes.append(decoded); requestedTimes.append(f.requestedItemTime) };generation=f.contentGeneration }
    RunLoop.current.run(until:Date(timeIntervalSinceNow:1.0/60.0))
   };return times
  }
  source.apply(.play,timing:timing())
  let initial=pump(1.5);guard initial.count>5,player.rate>0 else {fatalError("decoder failed startup \(initial.count)")}
  let sharedFrame=source.currentFrame(for:timing())!
  let authored=sharedFrame.layerPublication(for:7)!,dynamic=sharedFrame.layerPublication(for:-8)!
  let projectedIdentity:Bool
  if case let .provider(.video(authoredID,authoredEpoch))=authored.candidate.identity,
     case let .provider(.video(dynamicID,dynamicEpoch))=dynamic.candidate.identity {
   projectedIdentity=authoredID==7 && dynamicID == -8 && authoredEpoch==dynamicEpoch
    && authored.candidate.texture === dynamic.candidate.texture && authored.contentGeneration==dynamic.contentGeneration
  } else {projectedIdentity=false}
  let beforeRate=player.rate
  source.apply(.play,timing:timing());let afterPlayRate=player.rate
  _=pump(0.2)
  source.apply(.setRate(1),timing:timing());let afterSameRate=player.rate
  let repeatStart=decodedTimes.count
  let repeated=pump(1.5,repeatPlay:true)
  let repeatedDecodedTimes=Array(decodedTimes[repeatStart...])
  let repeatedRequestedTimes=Array(requestedTimes[repeatStart...])
  source.apply(.pause,timing:timing());let pausedTime=source.playbackSnapshot(sceneTime:timing().sceneTime).currentTime
  _=pump(0.1);source.apply(.pause,timing:timing());_=pump(0.1)
  let held=source.playbackSnapshot(sceneTime:timing().sceneTime)
  source.apply(.play,timing:timing());let resumed=pump(0.5)
  source.apply(.setCurrentTime(0.5),timing:timing());let sought=pump(0.5)
  source.apply(.setRate(2),timing:timing());let faster=pump(0.4);let changedRate=player.rate
  player.pause() // Simulate a backend stall without changing authored playing state.
  source.apply(.play,timing:timing());let recovered=pump(0.3);let recoveredRate=player.rate
  let rejectedTiming=timing();_=source.prepareFrame(for:rejectedTiming);source.discardPreparedFrame()
  source.apply(.play,timing:rejectedTiming)
  _=source.currentFrame(for:rejectedTiming);let retried=pump(0.3);let retryRate=player.rate
  let result:[String:Any] = ["sharedFrameProjectsConsumerIdentity":projectedIdentity,"beforeRate":beforeRate,"afterRepeatedPlayRate":afterPlayRate,"afterUnchangedRate":afterSameRate,"initialFrames":initial.count,"repeatedPlayFrames":repeated.count,"repeatedPlayTimes":repeated,"decodedTimes":decodedTimes,"repeatedDecodedTimes":repeatedDecodedTimes,"repeatedRequestedTimes":repeatedRequestedTimes,"requestedTimes":requestedTimes,"pauseHeld":abs(held.currentTime-pausedTime)<0.000001 && !held.isPlaying,"resumedFrames":resumed.count,"seekFrames":sought.count,"seekFirst":sought.first ?? -1,"seekLast":sought.last ?? -1,"changedRate":changedRate,"fasterTimes":faster,"recoveredRate":recoveredRate,"recoveredFrames":recovered.count,"retryRate":retryRate,"retriedFrames":retried.count]
  let encoded=try JSONSerialization.data(withJSONObject:result,options:[.prettyPrinted,.sortedKeys]); print(String(decoding:encoded,as:UTF8.self))
 }
 static func textureWitness(_ texture:MTLTexture,device:MTLDevice)->[String:Any] {
  let width=texture.width,height=texture.height,rowBytes=width*4,length=rowBytes*height
  guard texture.pixelFormat == .bgra8Unorm,
        let queue=device.makeCommandQueue(),let command=queue.makeCommandBuffer(),
        let buffer=device.makeBuffer(length:length,options:.storageModeShared),
        let blit=command.makeBlitCommandEncoder() else {fatalError("texture readback unavailable")}
  blit.copy(from:texture,sourceSlice:0,sourceLevel:0,sourceOrigin:.init(x:0,y:0,z:0),sourceSize:.init(width:width,height:height,depth:1),to:buffer,destinationOffset:0,destinationBytesPerRow:rowBytes,destinationBytesPerImage:length)
  blit.endEncoding();command.commit();command.waitUntilCompleted()
  guard command.status == .completed else {fatalError("texture readback failed")}
  let bytes=Data(bytes:buffer.contents(),count:length)
  let rgb=bytes.enumerated().filter{$0.offset%4 != 3}.map{$0.element}
  var center=[Double](repeating:0,count:3);var count=0
  for y in (height/2-10)..<(height/2+10) {for x in (width/2-10)..<(width/2+10) {
   let offset=y*rowBytes+x*4
   for (channel,component) in [2,1,0].enumerated() {center[channel]+=Double(bytes[offset+component])}
   count+=1
  }}
  return ["sha256":SHA256.hash(data:bytes).map{String(format:"%02x",$0)}.joined(),
          "rgbRange":[rgb.min()!,rgb.max()!],"centerMeanRGB":center.map{$0/Double(count)}]
 }
 struct SeekPixelFailure: Error {let reason:String}
 static func reflected(_ value:Any,_ name:String)->Any? {
  Mirror(reflecting:value).children.first{$0.label==name}?.value
 }
 static func unwrapped(_ value:Any?)->Any? {
  guard let value else {return nil}
  let mirror=Mirror(reflecting:value)
  return mirror.displayStyle == .optional ? mirror.children.first?.value:value
 }
 static func finite(_ value:Double)->Any {value.isFinite ? value as Any:NSNull()}
 static func timeFacts(_ value:CMTime)->[String:Any] {
  ["value":value.value,"timescale":value.timescale,"epoch":value.epoch,
   "isNumeric":value.isNumeric,"seconds":finite(CMTimeGetSeconds(value))]
 }
 static func frameFacts(_ frame:SceneVideoTextureSource.Frame)->[String:Any] {
  ["generation":frame.contentGeneration,"epoch":frame.epoch,
   "texture":String(describing:ObjectIdentifier(frame.texture)),
   "size":[frame.texture.width,frame.texture.height],"requested":finite(frame.requestedItemTime),
   "decoded":frame.decodedItemTime.map{finite($0)} ?? NSNull()]
 }
 static func decodedFacts(_ value:Any?)->Any {
  guard let value=unwrapped(value),
        let texture=reflected(value,"texture") as? MTLTexture,
        let requested=reflected(value,"requestedItemTime") as? Double else {return NSNull()}
  return ["texture":String(describing:ObjectIdentifier(texture)),"requested":finite(requested),
          "decoded":(unwrapped(reflected(value,"decodedItemTime")) as? Double).map{finite($0)} ?? NSNull()]
 }
 static func seekFailureFacts(_ source:SceneVideoTextureSource,_ player:AVPlayer)->[String:Any] {
  // No prepare/currentFrame/copyPixelBuffer, command, run-loop pump or GPU readback here.
  var facts=seekPixelFailureContext
  facts["scope"]="failure-only observation before stop; no retry or post-deadline prepare"
  facts["playerTime"]=timeFacts(player.currentTime())
  facts["playerRate"]=finite(Double(player.rate))
  facts["playerStatus"]=player.status.rawValue
  facts["timeControlStatus"]=player.timeControlStatus.rawValue
  facts["waitingReason"]=player.reasonForWaitingToPlay.map{$0.rawValue as Any} ?? NSNull()
  facts["playerItemPresent"]=player.currentItem != nil
  facts["sourceItemIsCurrent"]=(unwrapped(reflected(source,"item")) as? AVPlayerItem).map{$0 === player.currentItem} ?? false
  if let item=player.currentItem {
   facts["itemStatus"]=item.status.rawValue;facts["itemDuration"]=timeFacts(item.duration)
   facts["itemBufferEmpty"]=item.isPlaybackBufferEmpty
   facts["itemLikelyToKeepUp"]=item.isPlaybackLikelyToKeepUp
  }
  for name in ["hasStarted","needsPlayerAnchor","payloadPreparationFailed"] {
   facts[name]=(reflected(source,name) as? Bool).map{$0 as Any} ?? NSNull()
  }
  facts["pendingFrameIndex"]=unwrapped(reflected(source,"pendingFrameIndex")) ?? NSNull()
  facts["publishedFrame"]=(unwrapped(reflected(source,"lastFrame")) as? SceneVideoTextureSource.Frame).map{frameFacts($0) as Any} ?? NSNull()
  facts["pendingFrame"]=(unwrapped(reflected(source,"pendingFrame")) as? SceneVideoTextureSource.Frame).map{frameFacts($0) as Any} ?? NSNull()
  facts["decodedCandidate"]=decodedFacts(reflected(source,"decodedFrameCandidate"))
  if let lifecycle=reflected(source,"lifecycle") as? SceneVideoProviderLifecycleState {
   facts["lifecycle"]=["epoch":lifecycle.epoch,"generation":lifecycle.contentGeneration,
    "isPlaying":lifecycle.isPlaying,"isAdvancing":lifecycle.isAdvancingPlayback,
    "rate":finite(lifecycle.rate),"loop":lifecycle.loop]
  }
  if let events=reflected(source,"playerEventState") as? SceneVideoPlayerEventState {
   facts["commandGeneration"]=events.commandGeneration
   facts["anchoredGeneration"]=events.anchoredGeneration.map{$0 as Any} ?? NSNull()
  }
  if let state=reflected(source,"playerPositionState") {
   let child=Mirror(reflecting:state).children.first
   var position:[String:Any]=["state":child?.label ?? "unchanged"]
   if let child {
    let values=Mirror(reflecting:child.value).children.map{$0.value}
    if child.label=="required" {
     position["rawTarget"]=(unwrapped(child.value) as? Double).map{finite($0)} ?? NSNull()
    }
    if let operation=values.first as? UUID {position["operationID"]=operation.uuidString}
    if let item=values.compactMap({$0 as? AVPlayerItem}).first {
     position["itemIsCurrent"]=item === player.currentItem
     position["itemIsSourceItem"]=(unwrapped(reflected(source,"item")) as? AVPlayerItem).map{$0 === item} ?? false
    }
    if let target=values.compactMap({$0 as? CMTime}).first {
     position["target"]=timeFacts(target)
     if let output=reflected(source,"videoOutput") as? AVPlayerItemVideoOutput {
      position["hasBufferAtTargetAfterFailure"]=output.hasNewPixelBuffer(forItemTime:target)
     }
    }
   }
   facts["positioning"]=position
  }
  return facts
 }
 static func seekPixels(_ source:SceneVideoTextureSource,_ player:AVPlayer,device:MTLDevice) throws {
  let scenario=CommandLine.arguments.last!
  let scenarios=["seek6","seek2","same-inflight6","repeat-until-ready6","latest6-2-6","discard-before","discard-after","ordinary-drop","paused-discard-after"]
  guard scenarios.contains(scenario) else {throw SeekPixelFailure(reason:"unknown pixel case")}
  var controls:[[Double]]=[]
  for value in [UInt8(0),255] {
   let descriptor=MTLTextureDescriptor.texture2DDescriptor(pixelFormat:.bgra8Unorm,width:320,height:180,mipmapped:false)
   descriptor.storageMode = .shared
   guard let texture=device.makeTexture(descriptor:descriptor) else {throw SeekPixelFailure(reason:"control allocation")}
   let bytes=(0..<(320*180)).flatMap{_ in [value,value,value,UInt8(255)]}
   bytes.withUnsafeBytes{texture.replace(region:MTLRegionMake2D(0,0,320,180),mipmapLevel:0,
                                        withBytes:$0.baseAddress!,bytesPerRow:1280)}
   controls.append(textureWitness(texture,device:device)["centerMeanRGB"] as! [Double])
  }
  let start=CACurrentMediaTime();var frame:UInt64=0;var repeatedSeekCommands=0
  func timing()->SceneFrameTiming {
   let now=CACurrentMediaTime();frame+=1
   return .init(frameIndex:frame,hostTime:now,sceneTime:now-start)
  }
  func published()->SceneVideoTextureSource.Frame? {
   Mirror(reflecting:source).children.first{$0.label=="lastFrame"}!.value as? SceneVideoTextureSource.Frame
  }
  func held(_ baseline:SceneVideoTextureSource.Frame)->Bool {
   guard let current=published() else {return false}
   return current.contentGeneration==baseline.contentGeneration && current.texture === baseline.texture
  }
  let firstDeadline=CACurrentMediaTime()+2
  while (published()==nil || player.rate==0) && CACurrentMediaTime()<firstDeadline {
   _=source.currentFrame(for:timing());RunLoop.current.run(until:Date(timeIntervalSinceNow:1.0/120))
  }
  guard let initial=published(),player.rate>0 else {throw SeekPixelFailure(reason:"playing source startup")}
  let initialRGB=textureWitness(initial.texture,device:device)["centerMeanRGB"]!
  func awaitCandidate(_ baseline:SceneVideoTextureSource.Frame,_ fixed:SceneFrameTiming?,
                      _ attempts:inout [UInt64],phase:String,progress:[String:Any],
                      firstCandidate:SceneVideoTextureSource.Frame?=nil,
                      repeatTarget:Double?=nil) throws -> SceneVideoTextureSource.Frame {
   let deadline=CACurrentMediaTime()+2
   let attemptsBefore=attempts.count
   func failed(_ reason:String,_ observedAttempts:[UInt64])->SeekPixelFailure {
    seekPixelFailureContext=["phase":phase,"scenario":scenario,"caseProgress":progress,
     "baseline":frameFacts(baseline),"awaitSeconds":2,
     "attemptCount":observedAttempts.count-attemptsBefore,"attemptFrameIndicesTail":Array(observedAttempts.suffix(8)),
     "elapsedSeconds":finite(CACurrentMediaTime()-deadline+2),
     "firstCandidate":firstCandidate.map{frameFacts($0) as Any} ?? NSNull(),
     "fixedTiming":fixed.map{["frameIndex":$0.frameIndex,"hostTime":finite($0.hostTime),
                               "sceneTime":finite($0.sceneTime)] as Any} ?? NSNull()]
    return SeekPixelFailure(reason:reason)
   }
   repeat {
    let t=fixed ?? timing();attempts.append(t.frameIndex)
    if let repeatTarget {
     source.apply(.setCurrentTime(repeatTarget),timing:t)
     repeatedSeekCommands+=1
    }
    let candidate=source.prepareFrame(for:t)
    guard held(baseline) else {throw failed(scenario+": prepare changed last-ready",attempts)}
    if let candidate,candidate.contentGeneration>baseline.contentGeneration {return candidate}
    source.discardPreparedFrame()
    guard held(baseline) else {throw failed(scenario+": empty discard changed last-ready",attempts)}
    RunLoop.current.run(until:Date(timeIntervalSinceNow:1.0/120))
   } while CACurrentMediaTime()<deadline
   throw failed(scenario+": no new target candidate",attempts)
  }
  func runCase(_ name:String,_ targets:[Double]) throws -> [String:Any] {
   let baseline=published()!
   var row:[String:Any]=["case":name,"commands":targets,
                         "baselineGeneration":baseline.contentGeneration]
   if let target=targets.last {row["target"]=target}
   var attempts:[UInt64]=[];var fixed:SceneFrameTiming?
   if name=="paused-discard-after" {source.apply(.pause,timing:timing())}
   for (index,target) in targets.enumerated() {
    let t=timing();source.apply(.setCurrentTime(target),timing:t)
    if targets.count>1 {
     _=source.prepareFrame(for:t);source.discardPreparedFrame()
     guard held(baseline) else {throw SeekPixelFailure(reason:name+": overwritten command published")}
     if index==targets.count-1 {fixed=t}
    }
   }
   if name=="ordinary-drop" {
    _=source.prepareFrame(for:timing());source.discardPreparedFrame()
    row["rateImmediatelyAfterDiscard"]=player.rate
    row["publishedAfterDiscard"]=published()!.contentGeneration
    row["heldTextureAfterDiscard"]=held(baseline)
    let idleStart=CACurrentMediaTime()
    row["backendBeforeIdle"]=CMTimeGetSeconds(player.currentTime())
    row["typedBeforeIdle"]=source.playbackSnapshot(sceneTime:idleStart-start).currentTime
    // No prepare/currentFrame/command occurs during this run-loop interval.
    RunLoop.current.run(until:Date(timeIntervalSinceNow:0.2))
    let idleEnd=CACurrentMediaTime()
    row["idleElapsed"]=idleEnd-idleStart
    row["backendAfterIdle"]=CMTimeGetSeconds(player.currentTime())
    row["typedAfterIdle"]=source.playbackSnapshot(sceneTime:idleEnd-start).currentTime
    row["publishedAfterIdle"]=published()!.contentGeneration
    row["heldTextureAfterIdle"]=held(baseline)
   } else if name=="same-inflight6" || name=="discard-before" {
    let t=timing();fixed=t;attempts.append(t.frameIndex)
    let early=source.prepareFrame(for:t)
    if let early,early.contentGeneration>baseline.contentGeneration {
     row["earlyCandidateTexture"]=textureWitness(early.texture,device:device)
    } else {row["earlyCandidateTexture"]=NSNull()}
    // No run-loop yield has occurred after the first prepare. Repeat the exact
    // authored target while its backend request can still be in flight.
    if name=="same-inflight6" {source.apply(.setCurrentTime(6),timing:t)}
    source.discardPreparedFrame()
    row["publishedAfterDiscard"]=published()!.contentGeneration
    row["heldTextureAfterDiscard"]=held(baseline)
   } else if name=="discard-after" || name=="paused-discard-after" {fixed=timing()}
   var candidate=try awaitCandidate(baseline,fixed,&attempts,phase:"first-target",progress:row,
                                   repeatTarget:name=="repeat-until-ready6" ? 6:nil)
   row["firstCandidateGeneration"]=candidate.contentGeneration
   row["firstTexture"]=textureWitness(candidate.texture,device:device)
   if name=="discard-after" || name=="paused-discard-after" {
    // This observes an actual prepared texture, not private seek-callback state.
    row["discardPhase"]="ready-candidate-not-callback"
    let firstTexture=candidate.texture
    row["heldTimeBeforeDiscard"]=source.playbackSnapshot(sceneTime:CACurrentMediaTime()-start).currentTime
    source.discardPreparedFrame()
    row["publishedAfterDiscard"]=published()!.contentGeneration
    row["heldTextureAfterDiscard"]=held(baseline)
    candidate=try awaitCandidate(baseline,fixed,&attempts,phase:"after-discard",progress:row,firstCandidate:candidate)
    row["retrySameTexture"]=candidate.texture === firstTexture
    row["retryTexture"]=textureWitness(candidate.texture,device:device)
    row["heldTimeAfterRetry"]=source.playbackSnapshot(sceneTime:CACurrentMediaTime()-start).currentTime
    row["playingAfterRetry"]=source.playbackSnapshot(sceneTime:CACurrentMediaTime()-start).isPlaying
    row["rateAfterRetry"]=player.rate
   }
   row["candidateGeneration"]=candidate.contentGeneration
   row["publishedBeforeCommit"]=published()!.contentGeneration
   row["heldTextureBeforeCommit"]=held(baseline)
   row["candidateSize"]=[candidate.texture.width,candidate.texture.height]
   row["requested"]=candidate.requestedItemTime
   row["itemTimeForDisplay"]=candidate.decodedItemTime.map{$0 as Any} ?? NSNull()
   row["actualPlayerTime"]=CMTimeGetSeconds(player.currentTime())
   row["typedTime"]=source.playbackSnapshot(sceneTime:CACurrentMediaTime()-start).currentTime
   row["retryFrameIndices"]=attempts;row["retryFrameIndex"]=fixed.map{$0.frameIndex as Any} ?? NSNull()
   row["repeatedSeekCommands"]=repeatedSeekCommands
   source.commitPreparedFrame()
   row["publishedAfterCommit"]=published()!.contentGeneration
   row["committedCandidateTexture"]=published()!.texture === candidate.texture
   completedSeekPixelRows.append(row)
   return row
  }
  var result:[String:Any]=["controls":controls,"initialRGB":initialRGB]
  if scenario=="seek2" {result["setupSeek6"]=try runCase("setupSeek6",[6])}
  result["row"]=try runCase(scenario,scenario=="ordinary-drop" ? [] : scenario=="latest6-2-6" ? [6,2,6] : [scenario=="seek2" ? 2:6])
  print(String(decoding:try JSONSerialization.data(withJSONObject:result,options:[.sortedKeys]),as:UTF8.self))
 }
 static func scopedWebM(data:Data,root:URL,device:MTLDevice) throws {
  // Drain temporary AV borrowers without destroying the stopped Source. A
  // surviving Source/player/output reference must not hide a retained item.
  var stoppedSource:SceneVideoTextureSource?
  weak var stoppedAsset:AVAsset?
  weak var stoppedFile:SceneVideoOwnedFile?
  var stoppedURL:URL?
  var result=try autoreleasepool { () throws -> [String:Any] in
   guard let source=SceneVideoTextureSource(owner:.ordinary,mp4PayloadData:data,isWebM:true,
           cacheDirectory:root,device:device) else {fatalError("provider unavailable")}
   stoppedSource=source
   let player=Mirror(reflecting:source).children.compactMap{$0.value as? AVPlayer}.first!
   return try webM(source,player,data:data,root:root,device:device) {asset,file in
    stoppedAsset=asset;stoppedFile=file;stoppedURL=file.url
   }
  }
  guard let source=stoppedSource,let url=stoppedURL else {fatalError("retirement observation unavailable")}
  let deadline=CACurrentMediaTime()+0.5
  while (stoppedAsset != nil || stoppedFile != nil || FileManager.default.fileExists(atPath:url.path))
          && CACurrentMediaTime()<deadline {
   autoreleasepool {RunLoop.current.run(until:Date(timeIntervalSinceNow:1.0/120))}
  }
  result["stoppedSourceAliveAtReleaseCheck"]=stoppedSource != nil
  result["stoppedAssetReleased"]=stoppedAsset == nil
  result["stoppedOwnedFileReleased"]=stoppedFile == nil
  result["stoppedPayloadAbsent"] = !FileManager.default.fileExists(atPath:url.path)
  result["filesAfterBorrowerRelease"]=payloadFiles(root)
  withExtendedLifetime(source) {}
  print(String(decoding:try JSONSerialization.data(withJSONObject:result,options:[.sortedKeys]),as:UTF8.self))
 }
 static func payloadFiles(_ directory:URL)->[String] {
  let payloads=directory.appendingPathComponent(".mywallpaperx-scene-video-payloads")
  return ((try? FileManager.default.contentsOfDirectory(atPath:payloads.path)) ?? []).sorted()
 }
 static func webM(_ source:SceneVideoTextureSource,_ player:AVPlayer,data:Data,root:URL,device:MTLDevice,
                  willStop:(AVAsset,SceneVideoOwnedFile)->Void) throws -> [String:Any] {
  let start=CACurrentMediaTime();var frame:UInt64=0;var generation:UInt64=0
  var last:SceneVideoTextureSource.Frame?
  func timing()->SceneFrameTiming {let now=CACurrentMediaTime();frame+=1;return .init(frameIndex:frame,hostTime:now,sceneTime:now-start)}
  func command(_ action:SceneScriptMediaPlaybackCommand.Action) {source.apply(action,timing:timing())}
  func pump(_ seconds:Double,untilFirst:Bool=false)->[[Any]] {
   let end=CACurrentMediaTime()+seconds;var rows:[[Any]]=[]
   while CACurrentMediaTime()<end {
    if let f=source.currentFrame(for:timing()),f.contentGeneration != generation {
     generation=f.contentGeneration;last=f
     let opaque:Bool
     if case .color(.resolved(.opaque))=f.content {opaque=true} else {opaque=false}
     rows.append([f.requestedItemTime,f.decodedItemTime ?? -1,f.contentGeneration,f.texture.width,f.texture.height,opaque])
     if untilFirst {break}
    }
    RunLoop.current.run(until:Date(timeIntervalSinceNow:1.0/120))
   };return rows
  }
  // No run-loop yield has occurred: the background preparation cannot yet
  // install its item. Commands must reach the original lifecycle while pending.
  let initialItemPending=player.currentItem == nil
  command(.pause);command(.setRate(2));command(.setCurrentTime(0.7))
  let pending=source.playbackSnapshot(sceneTime:timing().sceneTime)
  let pendingCommandsHeld = !pending.isPlaying && pending.rate == 2 && abs(pending.currentTime-0.7)<0.000001
  let initial=pump(4,untilFirst:true)
  guard let first=last else {fatalError("WebM did not publish a real frame")}
  let firstWitness=textureWitness(first.texture,device:device),preparedFilePresent = !payloadFiles(root).isEmpty
  let duration=source.playbackSnapshot(sceneTime:timing().sceneTime).duration
  command(.play);let playing=pump(0.5)
  let playingWitness=textureWitness(last!.texture,device:device)
  command(.pause);let pauseTime=source.playbackSnapshot(sceneTime:timing().sceneTime).currentTime
  let pausedRefresh=pump(0.2),held=source.playbackSnapshot(sceneTime:timing().sceneTime)
  let pauseHeld = !held.isPlaying && abs(held.currentTime-pauseTime)<0.000001
  command(.setCurrentTime(0.3));let seek=pump(0.4)
  command(.setCurrentTime(1.8));command(.setLoop(true));command(.play)
  let loopRows=pump(2.4),ends=source.playbackSnapshot(sceneTime:timing().sceneTime).endedGeneration
  let displayTimes=loopRows.compactMap{$0[1] as? Double}
  let displayWraps=zip(displayTimes,displayTimes.dropFirst()).filter{$0.1<$0.0}.count
  guard let asset=player.currentItem?.asset else {fatalError("prepared AV asset unavailable")}
  func observeOwnedFile() {
   let stored=Mirror(reflecting:source).children.first{$0.label=="ownedFile"}!.value
   guard let file=Mirror(reflecting:stored).children.compactMap({$0.value as? SceneVideoOwnedFile}).first
   else {fatalError("prepared owned-file lease unavailable")}
   willStop(asset,file)
  }
  observeOwnedFile()
  source.stop()
  let stoppedFrameAbsent=source.currentFrame(for:timing()) == nil
  let stoppedItemAbsent=player.currentItem == nil
  let filesAfterStop=withExtendedLifetime(asset) {payloadFiles(root)}

  // Cancel before preparation can install AVPlayerItem. Keep the cancelled
  // provider alive and pump its public frame API after the worker has settled.
  let cancelRoot=root.appendingPathComponent("cancelled",isDirectory:true)
  guard let cancelled=SceneVideoTextureSource(owner:.ordinary,mp4PayloadData:data,isWebM:true,cacheDirectory:cancelRoot,device:device) else {fatalError("cancel provider unavailable")}
  let cancelPlayer=Mirror(reflecting:cancelled).children.compactMap{$0.value as? AVPlayer}.first!
  let cancelStartedPending=cancelPlayer.currentItem == nil
  cancelled.apply(.play,timing:timing())
  cancelled.stop()
  var cancelLateFrameAbsent=true
  let settle=CACurrentMediaTime()+0.5
  while CACurrentMediaTime()<settle {
   if cancelled.currentFrame(for:timing()) != nil {cancelLateFrameAbsent=false}
   RunLoop.current.run(until:Date(timeIntervalSinceNow:1.0/120))
  }
  let result:[String:Any]=["initialItemPending":initialItemPending,"pendingCommandsHeld":pendingCommandsHeld,"preparedFilePresent":preparedFilePresent,"duration":duration,"initialRows":initial,"playingRows":playing,"pausedRefreshRows":pausedRefresh,"pauseHeld":pauseHeld,"seekRows":seek,"loopRows":loopRows,"ends":ends,"displayWraps":displayWraps,"firstTexture":firstWitness,"playingTexture":playingWitness,"stoppedFrameAbsent":stoppedFrameAbsent,"stoppedItemAbsent":stoppedItemAbsent,"filesAfterStop":filesAfterStop,"cancelStartedPending":cancelStartedPending,"cancelLateFrameAbsent":cancelLateFrameAbsent,"cancelLateItemAbsent":cancelPlayer.currentItem == nil,"cancelFilesAfterSettle":payloadFiles(cancelRoot)]
  return result
 }
 static func eofDiscard(_ source:SceneVideoTextureSource, _ player:AVPlayer, looping:Bool) throws {
  let start=CACurrentMediaTime();var frame:UInt64=0
  func timing()->SceneFrameTiming {let now=CACurrentMediaTime();frame+=1;return .init(frameIndex:frame,hostTime:now,sceneTime:now-start)}
  func published()->UInt64 {(Mirror(reflecting:source).children.first{$0.label=="lastFrame"}!.value as? SceneVideoTextureSource.Frame)?.contentGeneration ?? 0}
  source.apply(.setLoop(looping),timing:.init(frameIndex:0,hostTime:start,sceneTime:0))
  if CommandLine.arguments.contains("--drop-before-end") {
   while CACurrentMediaTime()-start < 1.65 {_=source.currentFrame(for:timing());RunLoop.current.run(until:Date(timeIntervalSinceNow:1.0/120))}
   var rawEnds=0
   let observer=NotificationCenter.default.addObserver(forName:.AVPlayerItemDidPlayToEndTime,
       object:player.currentItem,queue:.main){_ in rawEnds+=1}
   defer {NotificationCenter.default.removeObserver(observer)}
   let baseline=Mirror(reflecting:source).children.first{$0.label=="lastFrame"}!.value as? SceneVideoTextureSource.Frame
   let before=published(),timeAtDrop=CMTimeGetSeconds(player.currentTime())
   let endsBefore=source.playbackSnapshot(sceneTime:CACurrentMediaTime()-start).endedGeneration
   _=source.prepareFrame(for:timing());source.discardPreparedFrame()
   let immediateRate=player.rate,afterDiscard=published()
   // Deliver a real AVPlayer EOF without preparing another host frame.
   let deadline=CACurrentMediaTime()+2
   while rawEnds==0 && CACurrentMediaTime()<deadline {RunLoop.current.run(until:Date(timeIntervalSinceNow:1.0/120))}
   RunLoop.current.run(until:Date(timeIntervalSinceNow:0.15))
   let snapshot=source.playbackSnapshot(sceneTime:CACurrentMediaTime()-start)
   let after=Mirror(reflecting:source).children.first{$0.label=="lastFrame"}!.value as? SceneVideoTextureSource.Frame
   let heldTexture:Bool
   if let baseline,let after {heldTexture=baseline.texture === after.texture} else {heldTexture=false}
   let result:[String:Any]=["looping":looping,"before":before,"afterDiscard":afterDiscard,
       "afterIdle":published(),"heldTextureAfterIdle":heldTexture,"timeAtDrop":timeAtDrop,
       "rateImmediatelyAfterDiscard":immediateRate,"endsBefore":endsBefore,"rawEndCount":rawEnds,
       "endedAfterIdle":snapshot.endedGeneration,"playingAfterIdle":snapshot.isPlaying,
       "duration":snapshot.duration,"timeAfterIdle":snapshot.currentTime]
   print(String(decoding:try JSONSerialization.data(withJSONObject:result,options:[.sortedKeys]),as:UTF8.self))
   return
  }
  while CACurrentMediaTime()-start < 1.93 {_=source.currentFrame(for:timing());RunLoop.current.run(until:Date(timeIntervalSinceNow:1.0/120))}
  let before=published();let rejected=timing();_=source.prepareFrame(for:rejected)
  RunLoop.current.run(until:Date(timeIntervalSinceNow:0.35))
  let endsBefore=source.playbackSnapshot(sceneTime:CACurrentMediaTime()-start).endedGeneration
  source.discardPreparedFrame();let afterDiscard=published()
  let now=timing();source.apply(.setLoop(false),timing:now)
  let snapshot=source.playbackSnapshot(sceneTime:now.sceneTime)
  _=source.currentFrame(for:rejected);let afterRetry=published()
  var rows:[[Double]]=[];var generation=afterRetry;let until=CACurrentMediaTime()+0.5
  while CACurrentMediaTime()<until {
   let t=timing();if let f=source.currentFrame(for:t),f.contentGeneration != generation {rows.append([t.sceneTime,f.requestedItemTime,f.decodedItemTime ?? -1,Double(f.contentGeneration)]);generation=f.contentGeneration}
   RunLoop.current.run(until:Date(timeIntervalSinceNow:1.0/120))
  }
  let final=source.playbackSnapshot(sceneTime:timing().sceneTime)
  print(String(decoding:try JSONSerialization.data(withJSONObject:["looping":looping,"before":before,"afterDiscard":afterDiscard,"afterRetry":afterRetry,"endsBefore":endsBefore,"endsAfter":snapshot.endedGeneration,"scene":now.sceneTime,"time":snapshot.currentTime,"playing":snapshot.isPlaying,"finalEnds":final.endedGeneration,"finalPlaying":final.isPlaying,"finalTime":final.currentTime,"rows":rows]),as:UTF8.self))
 }
 static func pausedSeek(_ source:SceneVideoTextureSource) throws {
  let start=CACurrentMediaTime();var frame:UInt64=0;var last:SceneVideoTextureSource.Frame?
  func timing()->SceneFrameTiming {let now=CACurrentMediaTime();frame+=1;return .init(frameIndex:frame,hostTime:now,sceneTime:now-start)}
  func pump(_ seconds:Double)->[[Double]] {
   let end=CACurrentMediaTime()+seconds;var rows:[[Double]]=[]
   while CACurrentMediaTime()<end {
    if let f=source.currentFrame(for:timing()),f.contentGeneration != last?.contentGeneration {
     rows.append([f.requestedItemTime,f.decodedItemTime ?? -1]);last=f
    }
    RunLoop.current.run(until:Date(timeIntervalSinceNow:1.0/120))
   };return rows
  }
  _=pump(0.8);guard last != nil else {fatalError("startup failed")}
  source.apply(.pause,timing:timing())
  source.apply(.setCurrentTime(6),timing:timing())
  let paused=pump(0.5);let held=pump(0.2)
  source.apply(.setCurrentTime(4),timing:timing())
  _=source.prepareFrame(for:timing())
  // Reject the frame, then replace its in-flight seek before completion.
  source.discardPreparedFrame()
  source.apply(.setCurrentTime(2),timing:timing())
  let replaced=pump(0.5)
  source.apply(.stop,timing:timing())
  let stopped=pump(0.5)
  let duration=source.playbackSnapshot(sceneTime:timing().sceneTime).duration
  source.apply(.setCurrentTime(duration),timing:timing())
  _=source.currentFrame(for:timing())
  source.apply(.setLoop(false),timing:timing())
  let loopOff=pump(0.5)
  source.apply(.setCurrentTime(duration),timing:timing())
  _=source.currentFrame(for:timing())
  source.apply(.setLoop(true),timing:timing())
  let loopOn=pump(0.5)
  print(String(decoding:try JSONSerialization.data(withJSONObject:["paused":paused,"held":held,"replaced":replaced,"stopped":stopped,"loopOff":loopOff,"loopOn":loopOn,"duration":duration]),as:UTF8.self))
 }
 static func loopPhase(_ source: SceneVideoTextureSource) throws {
  let start=CACurrentMediaTime(); var frame:UInt64=0; var generation:UInt64=0
  source.apply(.play,timing:.init(frameIndex:0,hostTime:start,sceneTime:0))
  var rows:[[Double]]=[]
  while CACurrentMediaTime()-start < 8.5 {
   let now=CACurrentMediaTime();let scene=now-start;frame+=1
   if let candidate=source.currentFrame(for:.init(frameIndex:frame,hostTime:now,sceneTime:scene)),candidate.contentGeneration != generation {
    generation=candidate.contentGeneration
    rows.append([scene,candidate.requestedItemTime,candidate.decodedItemTime ?? -1])
   }
   RunLoop.current.run(until:Date(timeIntervalSinceNow:1.0/60.0))
  }
  let snapshot=source.playbackSnapshot(sceneTime:CACurrentMediaTime()-start)
  let player=Mirror(reflecting:source).children.compactMap{$0.value as? AVPlayer}.first!
  let timescale=player.currentItem!.duration.timescale
  print(String(decoding:try JSONSerialization.data(withJSONObject:["rows":rows,"ends":snapshot.endedGeneration,"duration":snapshot.duration,"requestTimescale":timescale]),as:UTF8.self))
 }

}
