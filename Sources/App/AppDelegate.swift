import Cocoa
import Metal
import QuartzCore

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    // Core modules
    private var renderer: MetalRenderer!
    private var audioCapture: AudioCapture!
    private var analysisEngine: AnalysisEngine!
    private var corruptionEngine: CorruptionEngine!
    private var compositionEngine: CompositionEngine!
    private var assetLibrary: AssetLibrary!
    private var displayManager: DisplayManager!
    private var debugOverlay: DebugOverlay?

    // State
    private nonisolated(unsafe) var displayLink: CVDisplayLink?
    private var startTime: Double = 0
    private var lastFrameTime: Double = 0
    private var config = SanctumConfig.load()
    private var currentAudioState = AudioState.silent

    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            try setupModules()
        } catch {
            NSLog("Sanctum failed to initialize: \(error)")
            NSApp.terminate(nil)
            return
        }

        startTime = CACurrentMediaTime()
        lastFrameTime = startTime
        startDisplayLink()

        // Start audio capture
        do {
            if config.audioSource == "line-in" {
                try audioCapture.start()
            } else {
                let fileURL = URL(fileURLWithPath: config.audioSource)
                try audioCapture.startFromFile(url: fileURL, loop: true)
            }
        } catch {
            NSLog("Audio capture failed: \(error). Running in visual-only mode.")
        }
    }

    private func setupModules() throws {
        // Renderer
        renderer = try MetalRenderer(canvasWidth: config.canvasWidth,
                                      canvasHeight: config.canvasHeight)

        // Audio
        audioCapture = AudioCapture(bufferSize: config.audioBufferSize)
        analysisEngine = AnalysisEngine(sampleRate: Float(audioCapture.sampleRate))
        corruptionEngine = CorruptionEngine(
            windowDuration: config.corruptionWindowHours * 3600
        )

        // Composition
        compositionEngine = CompositionEngine(
            canvasWidth: Float(config.canvasWidth),
            canvasHeight: Float(config.canvasHeight)
        )

        // Load assets
        assetLibrary = AssetLibrary(device: renderer.device)
        if let assetsURL = Bundle.main.url(forResource: "Assets", withExtension: nil) {
            try? assetLibrary.loadAssets(from: assetsURL)
        }
        // Create placeholder assets if none loaded
        if assetLibrary.count == 0 {
            let colors: [(UInt8, UInt8, UInt8, UInt8)] = [
                (15, 10, 60, 255),   // deep blue
                (140, 20, 30, 255),  // ruby red
                (80, 10, 80, 255),   // deep purple
                (20, 60, 30, 255),   // forest green
            ]
            for i in 0..<4 {
                assetLibrary.createSolidTexture(width: 512, height: 512,
                    color: colors[i], name: "panel-\(i)")
            }
        }
        compositionEngine.setPanels(assetLibrary.textureNames.filter { $0.contains("panel") })

        // Display
        displayManager = DisplayManager(renderer: renderer)
        displayManager.setup()

        // Debug overlay
        if config.debugOverlay, let window = NSApp.windows.first {
            debugOverlay = DebugOverlay(parentView: window.contentView!)
        }
    }

    private func startDisplayLink() {
        CVDisplayLinkCreateWithActiveCGDisplays(&displayLink)
        guard let displayLink else { return }

        let callback: CVDisplayLinkOutputCallback = { _, _, _, _, _, userInfo -> CVReturn in
            let delegate = Unmanaged<AppDelegate>.fromOpaque(userInfo!).takeUnretainedValue()
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    delegate.renderFrame()
                }
            }
            return kCVReturnSuccess
        }

        CVDisplayLinkSetOutputCallback(displayLink, callback,
            Unmanaged.passUnretained(self).toOpaque())
        CVDisplayLinkStart(displayLink)
    }

    private func renderFrame() {
        let now = CACurrentMediaTime()
        let deltaTime = Float(now - lastFrameTime)
        lastFrameTime = now
        let time = Float(now - startTime)

        // 1. Get audio samples and analyze
        let samples = audioCapture.getRecentSamples(count: config.audioBufferSize)
        var audioState = analysisEngine.analyze(samples: samples)

        // 2. Update corruption
        corruptionEngine.update(energy: audioState.overallEnergy, deltaTime: deltaTime)
        audioState.corruptionIndex = corruptionEngine.corruptionIndex

        // 3. Update composition (scene graph)
        compositionEngine.update(audioState: audioState, deltaTime: deltaTime)

        // 4. Build audio uniforms for shaders
        var uniforms = AudioUniforms()
        uniforms.bands = (audioState.subBass, audioState.bass, audioState.mids, audioState.highs)
        uniforms.bpm = audioState.bpm
        uniforms.beatPhase = audioState.beatPhase
        uniforms.corruptionIndex = audioState.corruptionIndex
        uniforms.time = time
        uniforms.isBeat = audioState.isBeat ? 1.0 : 0.0
        uniforms.isTransient = audioState.isTransient ? 1.0 : 0.0

        // 5. Render pipeline
        guard let commandBuffer = renderer.commandQueue.makeCommandBuffer() else { return }

        // Pass 1: Composition
        let corruption = audioState.corruptionIndex
        let tint = SIMD4<Float>(
            1.0 - corruption * 0.3,
            1.0 - corruption * 0.5,
            1.0 - corruption * 0.1,
            1.0
        )
        let panelNodes = compositionEngine.sceneGraph.allNodes(ofType: .panel)
        let panelTextures = panelNodes.prefix(4).compactMap { assetLibrary.texture(named: $0.textureName) }
        renderer.shaderPipeline.compositePanels(
            panelTextures: panelTextures,
            tintColor: tint,
            commandBuffer: commandBuffer
        )

        // Pass 1b: Overlay icons
        let iconNodes = compositionEngine.sceneGraph.allNodes(ofType: .icon)
        if let iconTex = assetLibrary.texture(named: iconNodes.first?.textureName ?? "") {
            renderer.shaderPipeline.compositeIcons(
                iconNodes: iconNodes,
                iconTexture: iconTex,
                commandBuffer: commandBuffer
            )
        }

        // Pass 2: Effects
        renderer.shaderPipeline.applyEffects(audioUniforms: uniforms, commandBuffer: commandBuffer)

        // Pass 3: Post-processing
        renderer.shaderPipeline.applyPostProcessing(audioUniforms: uniforms, commandBuffer: commandBuffer)

        // Copy final output to canvas
        if let blitEncoder = commandBuffer.makeBlitCommandEncoder() {
            blitEncoder.copy(from: renderer.shaderPipeline.finalOutput, to: renderer.canvasTexture)
            blitEncoder.endEncoding()
        }

        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()

        // 6. Present to displays
        displayManager.present()

        // 7. Update debug overlay
        debugOverlay?.update(audioState: audioState, time: Double(time))

        currentAudioState = audioState
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let displayLink {
            CVDisplayLinkStop(displayLink)
        }
        audioCapture?.stop()
        displayManager?.teardown()
    }
}
