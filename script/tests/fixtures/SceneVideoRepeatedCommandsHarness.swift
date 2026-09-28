import Foundation
import AVFoundation
import Metal
import QuartzCore

// Standalone compilation shims for value envelopes outside the provider under test.
// AVPlayer, pixel decoding, Metal textures, lifecycle and command execution are production code.
struct SceneFrameTiming { let frameIndex: UInt64; let hostTime: Double; let sceneTime: Double }
struct SceneScriptVideoPlaybackSnapshot { let layerID: Int; let duration: Double; let rate: Double; let loop: Bool; let currentTime: Double; let isPlaying: Bool; let endedGeneration: UInt64 }
struct SceneScriptVideoCommand { enum Action { case play, pause, stop, setCurrentTime(Double), setRate(Double), setLoop(Bool) }; let layerID: Int; let action: Action }
enum ColorRepresentation { case opaque, premultipliedAlpha }
enum ColorResolution { case resolved(ColorRepresentation), unresolved }
enum SceneTextureContent { case color(ColorResolution) }
enum ResourceProvider { case video(layerID: Int, lifecycleEpoch: UInt64) }
enum ResourceIdentity { case provider(ResourceProvider) }
enum ResourceGeneration { case provider(contentGeneration: UInt64) }
enum TexturePurpose { case premultipliedColor }
enum TextureUV { case identity }
enum TextureSampling { case linearClamp }
struct SceneTextureCandidate { let texture: MTLTexture; let identity: ResourceIdentity; let generation: ResourceGeneration; let purpose: TexturePurpose; let content: SceneTextureContent; let physicalSize: CGSize; let mappedSize: CGSize; let uvTransform: TextureUV; let sampling: TextureSampling }
enum FrameIdentity { case layerSource(Int) }
struct SceneTextureProviderPublication { let requestIdentity: FrameIdentity; let candidate: SceneTextureCandidate; let contentGeneration: UInt64 }

@main enum Harness {
 static func main() throws {
  let root=URL(fileURLWithPath:CommandLine.arguments[1]);let data=try Data(contentsOf:root.appendingPathComponent("clip.mp4"))
  guard let device=MTLCreateSystemDefaultDevice(), let source=SceneVideoTextureSource(layerID:7,mp4PayloadData:data,cacheDirectory:root,device:device) else { fatalError("provider unavailable") }
  defer { source.stop() }
  // Observe the actual AVPlayer without changing product APIs or replacing its backend.
  let player=Mirror(reflecting:source).children.compactMap{$0.value as? AVPlayer}.first!
  if CommandLine.arguments.contains("--eof-discard") { try eofDiscard(source, player, looping: !CommandLine.arguments.contains("--no-loop")); return }
  if CommandLine.arguments.contains("--paused-seek") { try pausedSeek(source); return }
  if CommandLine.arguments.contains("--loop-phase") { try loopPhase(source); return }
  let start=CACurrentMediaTime(); var frame:UInt64=0
  var decodedTimes:[Double]=[]; var requestedTimes:[Double]=[]
  func timing()->SceneFrameTiming {let now=CACurrentMediaTime();frame+=1;return .init(frameIndex:frame,hostTime:now,sceneTime:now-start)}
  func pump(_ duration:Double, repeatPlay:Bool=false)->[Double] {
   let end=CACurrentMediaTime()+duration; var times:[Double]=[];var generation:UInt64=0
   while CACurrentMediaTime()<end {
    let t=timing();if repeatPlay {source.apply(.init(layerID:7,action:.play),timing:t)}
    if let f=source.currentFrame(for:t),f.contentGeneration != generation { times.append(f.requestedItemTime); if let decoded=f.decodedItemTime { decodedTimes.append(decoded); requestedTimes.append(f.requestedItemTime) };generation=f.contentGeneration }
    RunLoop.current.run(until:Date(timeIntervalSinceNow:1.0/60.0))
   };return times
  }
  source.apply(.init(layerID:7,action:.play),timing:timing())
  let initial=pump(1.5);guard initial.count>5,player.rate>0 else {fatalError("decoder failed startup \(initial.count)")}
  let beforeRate=player.rate
  source.apply(.init(layerID:7,action:.play),timing:timing());let afterPlayRate=player.rate
  _=pump(0.2)
  source.apply(.init(layerID:7,action:.setRate(1)),timing:timing());let afterSameRate=player.rate
  let repeatStart=decodedTimes.count
  let repeated=pump(1.5,repeatPlay:true)
  let repeatedDecodedTimes=Array(decodedTimes[repeatStart...])
  let repeatedRequestedTimes=Array(requestedTimes[repeatStart...])
  source.apply(.init(layerID:7,action:.pause),timing:timing());let pausedTime=source.playbackSnapshot(sceneTime:timing().sceneTime).currentTime
  _=pump(0.1);source.apply(.init(layerID:7,action:.pause),timing:timing());_=pump(0.1)
  let held=source.playbackSnapshot(sceneTime:timing().sceneTime)
  source.apply(.init(layerID:7,action:.play),timing:timing());let resumed=pump(0.5)
  source.apply(.init(layerID:7,action:.setCurrentTime(0.5)),timing:timing());let sought=pump(0.5)
  source.apply(.init(layerID:7,action:.setRate(2)),timing:timing());let faster=pump(0.4);let changedRate=player.rate
  source.apply(.init(layerID:7,action:.setRate(-1)),timing:timing());let invalidRateIgnored=player.rate==changedRate
  let beforeWrong=player.rate;source.apply(.init(layerID:99,action:.pause),timing:timing());let wrongIgnored=player.rate==beforeWrong
  player.pause() // Simulate a backend stall without changing authored playing state.
  source.apply(.init(layerID:7,action:.play),timing:timing());let recovered=pump(0.3);let recoveredRate=player.rate
  let rejectedTiming=timing();_=source.prepareFrame(for:rejectedTiming);source.discardPreparedFrame()
  source.apply(.init(layerID:7,action:.play),timing:rejectedTiming)
  _=source.currentFrame(for:rejectedTiming);let retried=pump(0.3);let retryRate=player.rate
  let result:[String:Any] = ["beforeRate":beforeRate,"afterRepeatedPlayRate":afterPlayRate,"afterUnchangedRate":afterSameRate,"initialFrames":initial.count,"repeatedPlayFrames":repeated.count,"repeatedPlayTimes":repeated,"decodedTimes":decodedTimes,"repeatedDecodedTimes":repeatedDecodedTimes,"repeatedRequestedTimes":repeatedRequestedTimes,"requestedTimes":requestedTimes,"pauseHeld":abs(held.currentTime-pausedTime)<0.000001 && !held.isPlaying,"resumedFrames":resumed.count,"seekFrames":sought.count,"seekFirst":sought.first ?? -1,"seekLast":sought.last ?? -1,"wrongLayerIgnored":wrongIgnored,"changedRate":changedRate,"fasterTimes":faster,"invalidRateIgnored":invalidRateIgnored,"recoveredRate":recoveredRate,"recoveredFrames":recovered.count,"retryRate":retryRate,"retriedFrames":retried.count]
  let encoded=try JSONSerialization.data(withJSONObject:result,options:[.prettyPrinted,.sortedKeys]); print(String(decoding:encoded,as:UTF8.self))
 }
 static func eofDiscard(_ source:SceneVideoTextureSource, _ player:AVPlayer, looping:Bool) throws {
  let start=CACurrentMediaTime();var frame:UInt64=0
  func timing()->SceneFrameTiming {let now=CACurrentMediaTime();frame+=1;return .init(frameIndex:frame,hostTime:now,sceneTime:now-start)}
  func published()->UInt64 {(Mirror(reflecting:source).children.first{$0.label=="lastFrame"}!.value as? SceneVideoTextureSource.Frame)?.contentGeneration ?? 0}
  source.apply(.init(layerID:7,action:.setLoop(looping)),timing:.init(frameIndex:0,hostTime:start,sceneTime:0))
  while CACurrentMediaTime()-start < 1.93 {_=source.currentFrame(for:timing());RunLoop.current.run(until:Date(timeIntervalSinceNow:1.0/120))}
  let before=published();let rejected=timing();_=source.prepareFrame(for:rejected)
  RunLoop.current.run(until:Date(timeIntervalSinceNow:0.35))
  let endsBefore=source.playbackSnapshot(sceneTime:CACurrentMediaTime()-start).endedGeneration
  source.discardPreparedFrame();let afterDiscard=published()
  let now=timing();source.apply(.init(layerID:7,action:.setLoop(false)),timing:now)
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
  source.apply(.init(layerID:7,action:.pause),timing:timing())
  source.apply(.init(layerID:7,action:.setCurrentTime(6)),timing:timing())
  let paused=pump(0.5);let held=pump(0.2)
  source.apply(.init(layerID:7,action:.setCurrentTime(4)),timing:timing())
  _=source.prepareFrame(for:timing())
  // Reject the frame, then replace its in-flight seek before completion.
  source.discardPreparedFrame()
  source.apply(.init(layerID:7,action:.setCurrentTime(2)),timing:timing())
  let replaced=pump(0.5)
  source.apply(.init(layerID:7,action:.stop),timing:timing())
  let stopped=pump(0.5)
  let duration=source.playbackSnapshot(sceneTime:timing().sceneTime).duration
  source.apply(.init(layerID:7,action:.setCurrentTime(duration)),timing:timing())
  _=source.currentFrame(for:timing())
  source.apply(.init(layerID:7,action:.setLoop(false)),timing:timing())
  let loopOff=pump(0.5)
  source.apply(.init(layerID:7,action:.setCurrentTime(duration)),timing:timing())
  _=source.currentFrame(for:timing())
  source.apply(.init(layerID:7,action:.setLoop(true)),timing:timing())
  let loopOn=pump(0.5)
  print(String(decoding:try JSONSerialization.data(withJSONObject:["paused":paused,"held":held,"replaced":replaced,"stopped":stopped,"loopOff":loopOff,"loopOn":loopOn,"duration":duration]),as:UTF8.self))
 }
 static func loopPhase(_ source: SceneVideoTextureSource) throws {
  let start=CACurrentMediaTime(); var frame:UInt64=0; var generation:UInt64=0
  source.apply(.init(layerID:7,action:.play),timing:.init(frameIndex:0,hostTime:start,sceneTime:0))
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
