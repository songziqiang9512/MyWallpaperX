import Foundation
import Metal
import simd

// Captures the production vertex results on Metal. Only the entry return type
// and output publication are instrumented; position/tangent calculations are
// the production shader body. Fixtures use explicit local axes and models,
// not a claim about official camera/renderer-axis uniform production.
enum SceneParticleFixedGeometryHarness {
 struct Case: Codable { let name:String;let scale:[Float];let axis:[Float];let rotation:[Float];let columns:[[Float]] }
 static func run() throws -> [[String:Any]] {
  guard let device=MTLCreateSystemDefaultDevice(),let queue=device.makeCommandQueue() else { return [] }
  let input = #"[{"name":"identity","scale":[1,1,1],"axis":[0,0,1],"rotation":[0.2,-0.4,0.7],"columns":[[1,0,0],[0,1,0],[0,0,1]]},{"name":"uniform3","scale":[3,3,3],"axis":[0,0,1],"rotation":[0.2,-0.4,0.7],"columns":[[3,0,0],[0,3,0],[0,0,3]]},{"name":"axisY","scale":[2,3,5],"axis":[0,1,0],"rotation":[0,0,0],"columns":[[2,0,0],[0,3,0],[0,0,5]]},{"name":"axisYrotated","scale":[2,3,5],"axis":[0,1,0],"rotation":[0.2,-0.4,0.7],"columns":[[2,0,0],[0,3,0],[0,0,5]]},{"name":"oblique","scale":[2,3,5],"axis":[1,1,1],"rotation":[0.2,-0.4,0.7],"columns":[[2,0,0],[0,3,0],[0,0,5]]},{"name":"flipY","scale":[1,-1,1],"axis":[0,0,1],"rotation":[0.2,-0.4,0.7],"columns":[[1,0,0],[0,-1,0],[0,0,1]]},{"name":"mirrorScale","scale":[-2,3,5],"axis":[1,1,1],"rotation":[0.2,-0.4,0.7],"columns":[[-2,0,0],[0,3,0],[0,0,5]]},{"name":"zeroScale","scale":[0,3,5],"axis":[0,0,1],"rotation":[0.2,-0.4,0.7],"columns":[[0,0,0],[0,3,0],[0,0,5]]},{"name":"rotatedScale","scale":[1,1,1],"columns":[[0,2,0],[-3,0,0],[0,0,5]],"axis":[1,1,1],"rotation":[0.2,-0.4,0.7]},{"name":"parentShear","scale":[1,1,1],"columns":[[2,1,0],[1,3,1],[0,1,5]],"axis":[1,1,1],"rotation":[0.2,-0.4,0.7]},{"name":"zero","scale":[1,1,1],"columns":[[0,0,0],[0,0,0],[0,0,0]],"axis":[1,1,1],"rotation":[0.2,-0.4,0.7]},{"name":"rankOne","scale":[1,1,1],"columns":[[0,0,0],[0,0,0],[1,2,5]],"axis":[1,1,1],"rotation":[0.2,-0.4,0.7]}]"#
  let cases=try JSONDecoder().decode([Case].self,from:Data(input.utf8))
  // Instrument only the production entry signature and final result publication.
  // The entire vertex body is compiled unchanged, including uniforms and branch selection.
  let source=sceneParticleShaderSource
   .replacingOccurrences(of:"vertex Varyings sceneParticleVert",with:"vertex void sceneParticleVert")
   .replacingOccurrences(of:"constant LayerUniforms &uniforms [[buffer(2)]])",with:"constant LayerUniforms &uniforms [[buffer(2)]], device float4 *probe [[buffer(3)]])")
   .replacingOccurrences(of:"    return out;",with:"    probe[vertexID] = out.position;\n    probe[vertexID + 4] = float4(out.screenTangentX, out.screenTangentY);\n    return;")
  let command=queue.makeCommandBuffer()!
  let lib=try device.makeLibrary(source:source,options:nil);let np=MTLRenderPipelineDescriptor();np.vertexFunction=lib.makeFunction(name:"sceneParticleVert");np.isRasterizationEnabled=false;let pipeline=try device.makeRenderPipelineState(descriptor:np)
  let camera=SceneParticleCameraFrame(camera:.init(eye:[0,0,0],center:[0,0,-1],up:[0,1,0],orthoWidth:640,orthoHeight:480,fovDegrees:nil,perspectiveOverrideFOVDegrees:nil,nearZ:0.1,farZ:1000),viewportSize:CGSize(width:640,height:480))
  var quad:[SIMD4<Float>]=[SIMD4(-0.5,-0.5,0,1),SIMD4(0.5,-0.5,1,1),SIMD4(-0.5,0.5,0,0),SIMD4(0.5,0.5,1,0)]
  var results:[[String:Any]]=[];var buffers:[MTLBuffer]=[]
  let modes: [(String, SceneParticleOrientation, Bool)] = [("fixed", .fixed, false), ("fixedWorldSize", .fixed, true), ("worldFixed", .worldFixed, false), ("worldFixedWorldSize", .worldFixed, true), ("worldScreen", .worldScreen, false), ("upright", .upright, false), ("localScreen", .screen, false), ("localScreenWorldSize", .screen, true)]
  var draws = modes.flatMap { mode in cases.enumerated().map { (index: $0.offset, c: $0.element, mode: mode) } }
  let singular = Case(name: "parallelXY", scale: [1,1,1], axis: [0,0,1],
      rotation: [0.2,-0.4,0.7], columns: [[0,1,0],[0,1,0],[0,0,1]])
  for mode in modes where mode.1 == .screen {
   draws.append((index: cases.count, c: singular, mode: mode))
  }
  for draw in draws {
   let c = draw.c
   var model=matrix_identity_float4x4;for j in 0..<3 {model[j]=SIMD4(c.columns[j][0],c.columns[j][1],c.columns[j][2],0)};model.columns.3=SIMD4(0.1,0.2,0.3,1)
   let basis=camera.basis(for:draw.mode.1,layerModel:model,orientationAxis:SIMD3(c.axis[0],c.axis[1],c.axis[2]))
   var uniforms=SceneParticleLayerUniforms(viewProjection:matrix_identity_float4x4,layerModel:model,basis:basis,sizeIsWorldSpace:draw.mode.2)
   var instance=SceneParticleGPUInstance(position:SIMD3(0.3,-0.2,0.1),size:4,rotation:SIMD3(c.rotation[0],c.rotation[1],c.rotation[2]),color:SIMD3(repeating:1),alpha:1,currentFrameAspect:2)
   let output=device.makeBuffer(length:8*16,options:.storageModeShared)!;buffers.append(output)
   let capturePass=MTLRenderPassDescriptor();capturePass.renderTargetWidth=1;capturePass.renderTargetHeight=1;capturePass.defaultRasterSampleCount=1;let enc=command.makeRenderCommandEncoder(descriptor:capturePass)!;enc.setRenderPipelineState(pipeline);enc.setVertexBytes(&quad,length:64,index:0);enc.setVertexBytes(&instance,length:MemoryLayout<SceneParticleGPUInstance>.stride,index:1);enc.setVertexBytes(&uniforms,length:MemoryLayout<SceneParticleLayerUniforms>.stride,index:2);enc.setVertexBuffer(output,offset:0,index:3);enc.drawPrimitives(type:.point,vertexStart:0,vertexCount:4);enc.endEncoding()
  }
  command.commit();command.waitUntilCompleted()
  guard command.status == .completed else {throw command.error ?? NSError(domain:"fixed-geometry-gpu",code:1)}
  for i in draws.indices {
   let p=buffers[i].contents().bindMemory(to:Float.self,capacity:32)
   results.append(["name":draws[i].c.name,"mode":draws[i].mode.0,
    "positions":(0..<4).map{Array(UnsafeBufferPointer(start:p+$0*4,count:4))},
    "tangents":(0..<4).map{Array(UnsafeBufferPointer(start:p+16+$0*4,count:4))}])
  }
  return results
 }
}
