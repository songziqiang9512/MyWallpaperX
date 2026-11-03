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
  let command=queue.makeCommandBuffer()!
  let pipeline = try probePipeline(device: device)
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

 static func rasterProfiles() throws -> [[String: Any]] {
  guard let device = MTLCreateSystemDefaultDevice(),
        let queue = device.makeCommandQueue(),
        let command = queue.makeCommandBuffer() else { return [] }
  let pipeline = try probePipeline(device: device)
  let viewport = SIMD2<Float>(640, 360)
  let projection = SceneMatrix.perspectiveRHMetal(
      fovYRadians: 0.9, aspect: viewport.x / viewport.y, near: 1, far: 30)
  let camera = SceneParticleCameraFrame(camera: .init(
      eye: [0,0,0], center: [0,0,-1], up: [0,1,0],
      orthoWidth: nil, orthoHeight: nil, fovDegrees: 50,
      perspectiveOverrideFOVDegrees: nil, nearZ: 1, farZ: 30),
      viewportSize: CGSize(width: 640, height: 360))
  let rows: [(String, SIMD4<Float>, SIMD4<Float>)] = [
      ("identity", SIMD4(1,0,0,0), SIMD4(0,1,0,0)),
      ("quarter-turn", SIMD4(0,-1.5,0,0.125), SIMD4(0.5,0,0,-0.0625)),
      ("shear", SIMD4(1.25,0.375,0,0.1), SIMD4(-0.25,0.75,0,-0.08)),
      ("mirror", SIMD4(-0.75,0.25,0,-0.04), SIMD4(0.5,1.5,0,0.03)),
  ]
  let model = SceneMatrix.translation(SIMD3<Float>(0.2,-0.15,-6))
      * SceneMatrix.rotationZ(0.3) * SceneMatrix.scale(SIMD3<Float>(1.7,0.55,1.2))
  var geometries: [(String, SceneParticleGPUInstance, simd_float4x4)] = [
      ("sprite", .init(position: SIMD3(0.15,-0.2,0.3), size: 3,
          rotation: SIMD3(0.2,-0.4,0.7), color: SIMD3(repeating: 1), alpha: 1,
          currentFrameAspect: 1.7), model),
      ("affine-trail", .init(position: SIMD3(0.15,-0.2,0.3), size: 3,
          rotation: .zero, color: SIMD3(repeating: 1), alpha: 1,
          velocity: SIMD3(0.9,0.4,0.2), trailStretch: 1.8), model),
      ("displacement-trail", .init(position: SIMD3(0.15,-0.2,0.3), size: 3,
          rotation: .zero, color: SIMD3(repeating: 1), alpha: 1,
          velocity: SIMD3(0.9,0.4,0.2), trailStretch: 1,
          usesTrailDisplacement: true, trailHeadDirection: SIMD3(-0.2,1,0.1),
          trailTailDirection: SIMD3(1,-0.3,0.2), trailEndpointSizes: SIMD2(2.2,1.4)), model),
  ]
  for (name, z): (String, Float) in [
      ("near", -1), ("far", -30), ("before-near", -0.5),
      ("beyond-far", -31), ("behind-eye", 2),
  ] {
   geometries.append((name, .init(position: SIMD3(0,0,z), size: 0.1,
       rotation: .zero, color: SIMD3(repeating: 1), alpha: 1), matrix_identity_float4x4))
  }
  var records: [(String, String, SIMD2<Int>, SIMD4<Float>, SIMD4<Float>, MTLBuffer)] = []
  for (geometry, instance, layerModel) in geometries {
   let basis = camera.basis(for: .screen, layerModel: layerModel)
   let canonical = SceneParticleLayerUniforms(viewProjection: projection,
       layerModel: layerModel, basis: basis, viewportSize: viewport,
       viewBasis: .init(right: SIMD3(1,0,0), up: SIMD3(0,1,0)))
   for physical in [SIMD2(64,32), SIMD2(128,96)] {
    for (name, x, y) in rows {
     var uniforms = canonical
     uniforms.rasterClipX = x; uniforms.rasterClipY = y
     let buffer = encodeProbe(instance: instance, uniforms: uniforms,
         physicalExtent: physical, pipeline: pipeline, device: device, command: command)
     records.append((geometry, name, physical, x, y, buffer))
    }
   }
  }
  command.commit(); command.waitUntilCompleted()
  guard command.status == .completed else {
   throw command.error ?? NSError(domain: "particle-raster-probe", code: 1)
  }
  return records.map { geometry, name, physical, x, y, buffer in
   let p = buffer.contents().bindMemory(to: Float.self, capacity: 32)
   return ["geometry": geometry, "map": name,
       "physicalExtent": [physical.x, physical.y], "canonicalViewport": [viewport.x, viewport.y],
       "rasterClipX": [x.x,x.y,x.z,x.w], "rasterClipY": [y.x,y.y,y.z,y.w],
       "positions": (0..<4).map { Array(UnsafeBufferPointer(start: p + $0 * 4, count: 4)) },
       "tangents": (0..<4).map { Array(UnsafeBufferPointer(start: p + 16 + $0 * 4, count: 4)) }]
  }
 }

 private static func probePipeline(device: MTLDevice) throws -> MTLRenderPipelineState {
  let source = sceneParticleShaderSource + """
  vertex void sceneParticleProbe(
      uint vertexID [[vertex_id]], uint instanceID [[instance_id]],
      constant QuadVertex *quad [[buffer(0)]],
      device const ParticleInstance *instances [[buffer(1)]],
      constant LayerUniforms &uniforms [[buffer(2)]],
      device float4 *probe [[buffer(3)]]) {
      Varyings out = particleVertex(vertexID, instanceID, quad, instances, uniforms, false);
      probe[vertexID] = out.position;
      probe[vertexID + 4] = float4(out.screenTangentX, out.screenTangentY);
  }
  """
  let library = try device.makeLibrary(source: source, options: nil)
  let descriptor = MTLRenderPipelineDescriptor()
  descriptor.vertexFunction = library.makeFunction(name: "sceneParticleProbe")
  descriptor.isRasterizationEnabled = false
  return try device.makeRenderPipelineState(descriptor: descriptor)
 }

 private static func encodeProbe(instance: SceneParticleGPUInstance,
     uniforms: SceneParticleLayerUniforms, physicalExtent: SIMD2<Int>,
     pipeline: MTLRenderPipelineState, device: MTLDevice,
     command: MTLCommandBuffer) -> MTLBuffer {
  var quad: [SIMD4<Float>] = [SIMD4(-0.5,-0.5,0,1), SIMD4(0.5,-0.5,1,1),
      SIMD4(-0.5,0.5,0,0), SIMD4(0.5,0.5,1,0)]
  var instance = instance; var uniforms = uniforms
  let output = device.makeBuffer(length: 8 * 16, options: .storageModeShared)!
  let pass = MTLRenderPassDescriptor()
  pass.renderTargetWidth = physicalExtent.x; pass.renderTargetHeight = physicalExtent.y
  pass.defaultRasterSampleCount = 1
  let encoder = command.makeRenderCommandEncoder(descriptor: pass)!
  encoder.setRenderPipelineState(pipeline)
  encoder.setVertexBytes(&quad, length: 64, index: 0)
  encoder.setVertexBytes(&instance, length: MemoryLayout<SceneParticleGPUInstance>.stride, index: 1)
  encoder.setVertexBytes(&uniforms, length: MemoryLayout<SceneParticleLayerUniforms>.stride, index: 2)
  encoder.setVertexBuffer(output, offset: 0, index: 3)
  encoder.drawPrimitives(type: .point, vertexStart: 0, vertexCount: 4)
  encoder.endEncoding()
  return output
 }
}
