import Foundation
import Metal

final class ShaderPipeline {
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue

    private var compositePanelsPipeline: MTLComputePipelineState!
    private var compositeIconsPipeline: MTLComputePipelineState!
    private var effectsRenderPipeline: MTLRenderPipelineState!

    private(set) var compositionOutput: MTLTexture!
    private(set) var effectsOutput: MTLTexture!

    let canvasWidth: Int
    let canvasHeight: Int

    init(device: MTLDevice, commandQueue: MTLCommandQueue,
         canvasWidth: Int = 3840, canvasHeight: Int = 2160) throws {
        self.device = device
        self.commandQueue = commandQueue
        self.canvasWidth = canvasWidth
        self.canvasHeight = canvasHeight

        try setupPipelines()
        setupTextures()
    }

    private func setupPipelines() throws {
        guard let library = device.makeDefaultLibrary() else {
            throw SanctumError.shaderCompilationFailed
        }

        if let panelsFunc = library.makeFunction(name: "compositePanels") {
            compositePanelsPipeline = try device.makeComputePipelineState(function: panelsFunc)
        }

        if let iconsFunc = library.makeFunction(name: "compositeIcons") {
            compositeIconsPipeline = try device.makeComputePipelineState(function: iconsFunc)
        }

        let effectsDesc = MTLRenderPipelineDescriptor()
        effectsDesc.vertexFunction = library.makeFunction(name: "fullscreenQuadVertex")
        effectsDesc.fragmentFunction = library.makeFunction(name: "effectsFragment")
        effectsDesc.colorAttachments[0].pixelFormat = .bgra8Unorm
        effectsRenderPipeline = try device.makeRenderPipelineState(descriptor: effectsDesc)
    }

    private func setupTextures() {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: canvasWidth, height: canvasHeight,
            mipmapped: false
        )
        descriptor.usage = [.shaderRead, .shaderWrite]
        descriptor.storageMode = .private
        compositionOutput = device.makeTexture(descriptor: descriptor)

        descriptor.usage = [.shaderRead, .shaderWrite, .renderTarget]
        effectsOutput = device.makeTexture(descriptor: descriptor)
    }

    func applyEffects(audioUniforms: AudioUniforms, commandBuffer: MTLCommandBuffer) {
        let passDescriptor = MTLRenderPassDescriptor()
        passDescriptor.colorAttachments[0].texture = effectsOutput
        passDescriptor.colorAttachments[0].loadAction = .dontCare
        passDescriptor.colorAttachments[0].storeAction = .store

        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: passDescriptor) else { return }
        encoder.setRenderPipelineState(effectsRenderPipeline)
        encoder.setFragmentTexture(compositionOutput, index: 0)
        var uniforms = audioUniforms
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<AudioUniforms>.size, index: 0)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        encoder.endEncoding()
    }

    func compositePanels(panelTextures: [MTLTexture],
                         tintColor: SIMD4<Float>,
                         commandBuffer: MTLCommandBuffer) {
        guard panelTextures.count >= 4 else { return }
        guard let encoder = commandBuffer.makeComputeCommandEncoder() else { return }
        encoder.setComputePipelineState(compositePanelsPipeline)
        encoder.setTexture(compositionOutput, index: 0)
        encoder.setTexture(panelTextures[0], index: 1)
        encoder.setTexture(panelTextures[1], index: 2)
        encoder.setTexture(panelTextures[2], index: 3)
        encoder.setTexture(panelTextures[3], index: 4)

        var tint = tintColor
        encoder.setBytes(&tint, length: MemoryLayout<SIMD4<Float>>.size, index: 0)

        let threadgroupSize = MTLSize(width: 16, height: 16, depth: 1)
        let gridSize = MTLSize(width: canvasWidth, height: canvasHeight, depth: 1)
        encoder.dispatchThreads(gridSize, threadsPerThreadgroup: threadgroupSize)
        encoder.endEncoding()
    }

    func compositeIcons(iconNodes: [SceneNode],
                        iconTexture: MTLTexture,
                        commandBuffer: MTLCommandBuffer) {
        guard !iconNodes.isEmpty else { return }
        guard let encoder = commandBuffer.makeComputeCommandEncoder() else { return }
        encoder.setComputePipelineState(compositeIconsPipeline)
        encoder.setTexture(compositionOutput, index: 0)
        encoder.setTexture(iconTexture, index: 1)

        struct IconInstance {
            var position: SIMD2<Float>
            var size: SIMD2<Float>
            var opacity: Float
            var rotation: Float
            var scale: Float
            var padding: Float = 0
        }
        var instances = iconNodes.map { node in
            IconInstance(
                position: SIMD2(node.position.x, node.position.y),
                size: SIMD2(256, 256),
                opacity: node.opacity,
                rotation: node.rotation,
                scale: node.scale
            )
        }
        var count = UInt32(instances.count)

        encoder.setBytes(&instances, length: MemoryLayout<IconInstance>.stride * instances.count, index: 0)
        encoder.setBytes(&count, length: MemoryLayout<UInt32>.size, index: 1)

        let threadgroupSize = MTLSize(width: 16, height: 16, depth: 1)
        let gridSize = MTLSize(width: canvasWidth, height: canvasHeight, depth: 1)
        encoder.dispatchThreads(gridSize, threadsPerThreadgroup: threadgroupSize)
        encoder.endEncoding()
    }
}
