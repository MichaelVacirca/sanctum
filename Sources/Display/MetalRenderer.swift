import Foundation
import Metal
import MetalKit
import QuartzCore

final class MetalRenderer: NSObject {
    let device: MTLDevice
    let commandQueue: MTLCommandQueue
    private var passthroughPipeline: MTLRenderPipelineState!
    private(set) var shaderPipeline: ShaderPipeline!

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
        shaderPipeline = try ShaderPipeline(device: device, commandQueue: commandQueue,
                                            canvasWidth: canvasWidth, canvasHeight: canvasHeight)
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
        descriptor.usage = [.renderTarget, .shaderRead, .shaderWrite]
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

    func renderFrame(panelTextures: [MTLTexture], tintColor: SIMD4<Float>) {
        guard let commandBuffer = commandQueue.makeCommandBuffer() else { return }

        shaderPipeline.compositePanels(panelTextures: panelTextures,
                                        tintColor: tintColor,
                                        commandBuffer: commandBuffer)

        guard let blitEncoder = commandBuffer.makeBlitCommandEncoder() else { return }
        blitEncoder.copy(from: shaderPipeline.compositionOutput,
                         sourceSlice: 0, sourceLevel: 0,
                         sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
                         sourceSize: MTLSize(width: canvasWidth, height: canvasHeight, depth: 1),
                         to: canvasTexture,
                         destinationSlice: 0, destinationLevel: 0,
                         destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0))
        blitEncoder.endEncoding()

        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
    }

    /// Present a sub-region of the canvas to a metal layer (for multi-display)
    func presentCanvasRegion(to layer: CAMetalLayer, region: MTLRegion) {
        guard let drawable = layer.nextDrawable() else { return }
        guard let commandBuffer = commandQueue.makeCommandBuffer() else { return }

        let quadDesc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: region.size.width, height: region.size.height,
            mipmapped: false
        )
        quadDesc.usage = [.shaderRead, .renderTarget]
        quadDesc.storageMode = .private
        guard let quadTexture = device.makeTexture(descriptor: quadDesc) else { return }

        guard let blitEncoder = commandBuffer.makeBlitCommandEncoder() else { return }
        blitEncoder.copy(
            from: canvasTexture,
            sourceSlice: 0, sourceLevel: 0,
            sourceOrigin: region.origin,
            sourceSize: region.size,
            to: quadTexture,
            destinationSlice: 0, destinationLevel: 0,
            destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0)
        )
        blitEncoder.endEncoding()

        let passDescriptor = MTLRenderPassDescriptor()
        passDescriptor.colorAttachments[0].texture = drawable.texture
        passDescriptor.colorAttachments[0].loadAction = .dontCare
        passDescriptor.colorAttachments[0].storeAction = .store

        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: passDescriptor) else { return }
        encoder.setRenderPipelineState(passthroughPipeline)
        encoder.setFragmentTexture(quadTexture, index: 0)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        encoder.endEncoding()

        commandBuffer.present(drawable)
        commandBuffer.commit()
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
