import Foundation
import simd

#if canImport(Metal) && canImport(MetalKit) && canImport(UIKit)
import Metal
import MetalKit
import UIKit
import CarddexCore

/// MTKView-backed holofoil renderer. Mirrors the GLSL implementation in
/// `apps/web/src/render/shaders.js`; see `Shaders/Holofoil.metal` for the
/// per-pattern functions.
public final class HolofoilRenderer: NSObject, MTKViewDelegate {

    private let device: MTLDevice
    private let queue: MTLCommandQueue
    private var pipeline: MTLRenderPipelineState?

    private let frontTexture: MTLTexture
    private let depthTexture: MTLTexture
    private let foilMaskTexture: MTLTexture?
    private let expandedColorTexture: MTLTexture?

    /// Uniforms updated per-frame. Mirrors `frontFragmentShader`'s uniforms.
    public struct Uniforms {
        public var viewAngle: SIMD2<Float> = .zero      // x = pitch, y = yaw, radians
        public var lightDirection: SIMD3<Float> = SIMD3(0, 0, 1)
        public var depthScale: Float = 0.12
        public var foilStrength: Float = 1.0
        public var coverage: Float = 1.0                // 0…1, gated by HoloCoverage
        public var pattern: Int32 = 0                   // index into the MSL switch
        public var time: Float = 0
    }

    public var uniforms = Uniforms()

    public init?(view: MTKView,
                 card: HolofoilCatalogCard,
                 textureLoader: HolofoilTextureLoader) {
        guard let device = view.device ?? MTLCreateSystemDefaultDevice() else { return nil }
        guard let queue = device.makeCommandQueue() else { return nil }
        guard let front = try? textureLoader.load(card.image, on: device),
              let depth = try? textureLoader.load(card.depth, on: device) else {
            return nil
        }
        self.device = device
        self.queue = queue
        self.frontTexture = front
        self.depthTexture = depth
        // The bundled catalog only carries front colour + depth and an
        // *expanded* colour image (the holo region rendered at full extent).
        // We don't ship a dedicated foil mask asset yet, so we sample the
        // front texture's alpha as the mask in the shader's index-2 slot
        // and bind the expanded colour image — when present — into the
        // shader's index-3 slot, matching `holofoil_fragment`'s parameters.
        self.foilMaskTexture = nil
        self.expandedColorTexture = card.expandedImage.flatMap { try? textureLoader.load($0, on: device) }
        super.init()
        view.device = device
        view.colorPixelFormat = .bgra8Unorm
        view.delegate = self
        self.pipeline = makePipeline(view: view)
        self.uniforms.depthScale  = Float(card.depthScale ?? 0.12)
        self.uniforms.foilStrength = Float(card.foilStrength ?? 1.0)
        self.uniforms.pattern = Int32(Self.patternIndex(card.holoPattern))
    }

    public func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    public func draw(in view: MTKView) {
        guard let pipeline,
              let drawable = view.currentDrawable,
              let descriptor = view.currentRenderPassDescriptor,
              let commandBuffer = queue.makeCommandBuffer(),
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) else {
            return
        }
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentTexture(frontTexture, index: 0)
        encoder.setFragmentTexture(depthTexture, index: 1)
        encoder.setFragmentTexture(foilMaskTexture ?? frontTexture, index: 2)
        encoder.setFragmentTexture(expandedColorTexture ?? frontTexture, index: 3)
        var u = uniforms
        encoder.setVertexBytes(&u,   length: MemoryLayout<Uniforms>.stride, index: 1)
        encoder.setFragmentBytes(&u, length: MemoryLayout<Uniforms>.stride, index: 0)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        encoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    private func makePipeline(view: MTKView) -> MTLRenderPipelineState? {
        // Load the MSL bundled in this target's resource bundle.
        guard let library = try? device.makeDefaultLibrary(bundle: Bundle.module) else { return nil }
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction   = library.makeFunction(name: "holofoil_vertex")
        descriptor.fragmentFunction = library.makeFunction(name: "holofoil_fragment")
        descriptor.colorAttachments[0].pixelFormat = view.colorPixelFormat
        return try? device.makeRenderPipelineState(descriptor: descriptor)
    }

    private static func patternIndex(_ p: HoloPattern?) -> Int {
        switch p ?? .none {
        case .starlight:   return 1
        case .cosmos:      return 2
        case .tinsel:      return 3
        case .sheen:       return 4
        case .crackedIce:  return 5
        case .crosshatch:  return 6
        case .waterWeb:    return 7
        case .sequin:      return 8
        case .fireworks:   return 9
        case .plain:       return 10
        case .none:        return 0
        }
    }
}
#endif
