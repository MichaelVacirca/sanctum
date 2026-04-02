import Foundation
import Metal
import MetalKit
import QuartzCore

final class MetalRenderer: NSObject {
    let device: MTLDevice
    let commandQueue: MTLCommandQueue
    private var passthroughPipeline: MTLRenderPipelineState!

    private(set) var canvasTexture: MTLTexture!
    let canvasWidth: Int
    let canvasHeight: Int

    init(canvasWidth: Int = 3840, canvasHeight: Int = 2160) throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw SanctumError.noMetalDevice
        }
        guard let commandQueue = device.makeCommandQueue() else {
            throw SanctumError.commandQueueFailed
        }
        self.device = device
        self.commandQueue = commandQueue
        self.canvasWidth = canvasWidth
        self.canvasHeight = canvasHeight
        super.init()
        try setupPipelines()
        setupCanvasTexture()
    }

    private func setupPipelines() throws {
        guard let library = device.makeDefaultLibrary() else {
            throw SanctumError.shaderCompilationFailed
        }

        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = library.makeFunction(name: "fullscreenQuadVertex")
        descriptor.fragmentFunction = library.makeFunction(name: "passthroughFragment")
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        passthroughPipeline = try device.makeRenderPipelineState(descriptor: descriptor)
    }

    private func setupCanvasTexture() {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: canvasWidth,
            height: canvasHeight,
            mipmapped: false
        )
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .private
        canvasTexture = device.makeTexture(descriptor: descriptor)
    }

    func presentCanvas(to layer: CAMetalLayer) {
        guard let drawable = layer.nextDrawable() else { return }
        guard let commandBuffer = commandQueue.makeCommandBuffer() else { return }

        let passDescriptor = MTLRenderPassDescriptor()
        passDescriptor.colorAttachments[0].texture = drawable.texture
        passDescriptor.colorAttachments[0].loadAction = .clear
        passDescriptor.colorAttachments[0].storeAction = .store
        passDescriptor.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)

        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: passDescriptor) else { return }
        encoder.setRenderPipelineState(passthroughPipeline)
        encoder.setFragmentTexture(canvasTexture, index: 0)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        encoder.endEncoding()

        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    func renderTextureToCanvas(_ texture: MTLTexture) {
        guard let commandBuffer = commandQueue.makeCommandBuffer() else { return }
        let passDescriptor = MTLRenderPassDescriptor()
        passDescriptor.colorAttachments[0].texture = canvasTexture
        passDescriptor.colorAttachments[0].loadAction = .clear
        passDescriptor.colorAttachments[0].storeAction = .store
        passDescriptor.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: passDescriptor) else { return }
        encoder.setRenderPipelineState(passthroughPipeline)
        encoder.setFragmentTexture(texture, index: 0)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        encoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
    }

    func clearCanvas(color: MTLClearColor) {
        guard let commandBuffer = commandQueue.makeCommandBuffer() else { return }
        let passDescriptor = MTLRenderPassDescriptor()
        passDescriptor.colorAttachments[0].texture = canvasTexture
        passDescriptor.colorAttachments[0].loadAction = .clear
        passDescriptor.colorAttachments[0].storeAction = .store
        passDescriptor.colorAttachments[0].clearColor = color
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: passDescriptor) else { return }
        encoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
    }
}

enum SanctumError: Error {
    case noMetalDevice
    case commandQueueFailed
    case shaderCompilationFailed
    case audioDeviceNotFound
    case assetLoadFailed(String)
}
