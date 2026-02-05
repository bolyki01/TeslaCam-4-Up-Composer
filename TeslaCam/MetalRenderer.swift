import Foundation
import Metal
import MetalKit
import AVFoundation

final class MetalRenderer: NSObject, MTKViewDelegate {
  private let device: MTLDevice
  private let commandQueue: MTLCommandQueue
  private let pipeline: MTLRenderPipelineState
  private let sampler: MTLSamplerState
  private let vertexBuffer: MTLBuffer
  private let textureCache: CVMetalTextureCache
  private let blackTexture: MTLTexture

  var cameraOrder: [Camera] = []
  var outputsProvider: (() -> [Camera: AVPlayerItemVideoOutput])?

  private var lastTextures: [Camera: MTLTexture] = [:]

  init?(mtkView: MTKView) {
    guard let device = MTLCreateSystemDefaultDevice() else { return nil }
    self.device = device
    guard let queue = device.makeCommandQueue() else { return nil }
    self.commandQueue = queue

    mtkView.device = device
    mtkView.colorPixelFormat = .bgra8Unorm
    mtkView.framebufferOnly = false

    guard let lib = MetalRenderer.loadLibrary(device: device),
          let vertexFunc = lib.makeFunction(name: "vertex_main"),
          let fragFunc = lib.makeFunction(name: "fragment_main") else { return nil }

    let pipelineDesc = MTLRenderPipelineDescriptor()
    pipelineDesc.vertexFunction = vertexFunc
    pipelineDesc.fragmentFunction = fragFunc
    pipelineDesc.colorAttachments[0].pixelFormat = mtkView.colorPixelFormat

    do {
      pipeline = try device.makeRenderPipelineState(descriptor: pipelineDesc)
    } catch {
      return nil
    }

    let samplerDesc = MTLSamplerDescriptor()
    samplerDesc.minFilter = .linear
    samplerDesc.magFilter = .linear
    samplerDesc.sAddressMode = .clampToEdge
    samplerDesc.tAddressMode = .clampToEdge
    sampler = device.makeSamplerState(descriptor: samplerDesc)!

    let quad: [Float] = [
      -1, -1, 0, 1,
       1, -1, 1, 1,
      -1,  1, 0, 0,
       1, -1, 1, 1,
       1,  1, 1, 0,
      -1,  1, 0, 0
    ]
    vertexBuffer = device.makeBuffer(bytes: quad, length: quad.count * MemoryLayout<Float>.size, options: [])!

    var cache: CVMetalTextureCache?
    CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, device, nil, &cache)
    textureCache = cache!

    let blackDesc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: 1, height: 1, mipmapped: false)
    blackDesc.usage = [.shaderRead]
    blackTexture = device.makeTexture(descriptor: blackDesc)!
    var blackPixel: [UInt8] = [0, 0, 0, 255]
    blackTexture.replace(region: MTLRegionMake2D(0, 0, 1, 1), mipmapLevel: 0, withBytes: &blackPixel, bytesPerRow: 4)

    super.init()
  }

  private static func loadLibrary(device: MTLDevice) -> MTLLibrary? {
    #if SWIFT_PACKAGE
    let bundle = Bundle.module
    #else
    let bundle = Bundle.main
    #endif
    guard let url = bundle.url(forResource: "MetalShaders", withExtension: "metal") else {
      return device.makeDefaultLibrary()
    }
    do {
      let source = try String(contentsOf: url, encoding: .utf8)
      return try device.makeLibrary(source: source, options: nil)
    } catch {
      return device.makeDefaultLibrary()
    }
  }

  func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

  func draw(in view: MTKView) {
    guard let drawable = view.currentDrawable,
          let pass = view.currentRenderPassDescriptor,
          let outputs = outputsProvider?() else { return }

    for (camera, output) in outputs {
      let hostTime = CACurrentMediaTime()
      let itemTime = output.itemTime(forHostTime: hostTime)
      if output.hasNewPixelBuffer(forItemTime: itemTime) {
        if let pixelBuffer = output.copyPixelBuffer(forItemTime: itemTime, itemTimeForDisplay: nil) {
          if let texture = makeTexture(from: pixelBuffer) {
            lastTextures[camera] = texture
          }
        }
      }
    }

    guard let commandBuffer = commandQueue.makeCommandBuffer(),
          let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else { return }

    encoder.setRenderPipelineState(pipeline)
    encoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
    encoder.setFragmentSamplerState(sampler, index: 0)

    let cams = cameraOrder
    let count = cams.count
    let columns = count > 4 ? 3 : 2
    let rows = count > 4 ? 2 : 2

    let w = Double(view.drawableSize.width)
    let h = Double(view.drawableSize.height)
    let tileW = w / Double(columns)
    let tileH = h / Double(rows)

    for (idx, camera) in cams.enumerated() {
      let col = idx % columns
      let row = idx / columns
      let viewport = MTLViewport(
        originX: Double(col) * tileW,
        originY: Double(rows - 1 - row) * tileH,
        width: tileW,
        height: tileH,
        znear: 0,
        zfar: 1
      )
      encoder.setViewport(viewport)
      let texture = lastTextures[camera] ?? blackTexture
      encoder.setFragmentTexture(texture, index: 0)
      encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
    }

    encoder.endEncoding()
    commandBuffer.present(drawable)
    commandBuffer.commit()
  }

  private func makeTexture(from pixelBuffer: CVPixelBuffer) -> MTLTexture? {
    let width = CVPixelBufferGetWidth(pixelBuffer)
    let height = CVPixelBufferGetHeight(pixelBuffer)
    var cvTextureOut: CVMetalTexture?
    let status = CVMetalTextureCacheCreateTextureFromImage(
      kCFAllocatorDefault,
      textureCache,
      pixelBuffer,
      nil,
      .bgra8Unorm,
      width,
      height,
      0,
      &cvTextureOut
    )
    if status != kCVReturnSuccess { return nil }
    guard let cvTexture = cvTextureOut else { return nil }
    return CVMetalTextureGetTexture(cvTexture)
  }
}
