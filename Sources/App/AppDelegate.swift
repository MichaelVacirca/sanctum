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
    private var theme: Theme = .cathedral
    private var themeIndex: Int = 0

    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            try setupModules()
        } catch {
            NSLog("Sanctum failed to initialize: \(error)")
            NSApp.terminate(nil)
            return
        }

        setupKeyboardHandling()

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
        // Development fallback: load from project Assets/ directory
        if assetLibrary.count == 0 {
            let devAssetsURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent("Assets")
            if FileManager.default.fileExists(atPath: devAssetsURL.path) {
                try? assetLibrary.loadAssets(from: devAssetsURL)
            }
        }
        // Select and apply the configured theme (creates color placeholders
        // for any panels whose art isn't present, so the arc is visible even
        // before real assets are generated).
        let configured = Theme.named(config.theme)
        themeIndex = Theme.all.firstIndex { $0.id == configured.id } ?? 0
        applyTheme(configured)

        // Display
        displayManager = DisplayManager(renderer: renderer)
        displayManager.setup()

        // Debug overlay
        if config.debugOverlay, let window = NSApp.windows.first {
            debugOverlay = DebugOverlay(parentView: window.contentView!)
        }
    }

    /// Switch the active visual theme: point the composition engine at the
    /// theme's panel order, ensure panels exist (placeholders if no art is
    /// loaded), and swap in the theme's drifting icons.
    private func applyTheme(_ newTheme: Theme) {
        theme = newTheme
        compositionEngine.panelOrder = newTheme.panelOrder

        let loaded = Set(assetLibrary.textureNames)
        if !newTheme.panelOrder.contains(where: loaded.contains) {
            for (i, name) in newTheme.panelOrder.enumerated() {
                let tint = newTheme.phases[min(i, newTheme.phases.count - 1)].tint
                assetLibrary.createSolidTexture(
                    width: 512, height: 512,
                    color: placeholderColor(from: tint), name: name
                )
            }
        }

        compositionEngine.setPanels(assetLibrary.textureNames)
        compositionEngine.setIcons(newTheme.icons.filter { loaded.contains($0) })
    }

    /// Cycle to the next built-in theme live (bound to the 'T' key) — handy for
    /// an operator switching the room's vibe mid-event.
    private func cycleTheme() {
        themeIndex = (themeIndex + 1) % Theme.all.count
        applyTheme(Theme.all[themeIndex])
        NSLog("Sanctum theme → \(theme.displayName)")
    }

    /// Map a phase color-grade tint (an RGB multiplier) to a representative
    /// solid color for placeholder panels.
    private func placeholderColor(from tint: SIMD3<Float>) -> (UInt8, UInt8, UInt8, UInt8) {
        func ch(_ v: Float) -> UInt8 { UInt8(max(30, min(235, v * 150))) }
        return (ch(tint.x), ch(tint.y), ch(tint.z), 255)
    }

    private func setupKeyboardHandling() {
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            switch event.keyCode {
            case 53: // Escape
                NSApp.terminate(nil)
                return nil
            case 2: // 'D' key — toggle debug overlay
                self?.debugOverlay?.toggle()
                return nil
            case 15: // 'R' key — reset energy arc
                self?.corruptionEngine.reset()
                return nil
            case 17: // 'T' key — cycle visual theme
                self?.cycleTheme()
                return nil
            default:
                return event
            }
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

        // Theme-driven look: interpolated color grade + effect profile
        let phaseTint = theme.interpolatedTint(at: audioState.corruptionIndex)
        uniforms.phaseTint = (phaseTint.x, phaseTint.y, phaseTint.z)
        let fx = theme.effects
        uniforms.refraction = fx.refraction
        uniforms.aberration = fx.aberration
        uniforms.crack = fx.crack
        uniforms.warp = fx.warp
        uniforms.fold = fx.fold
        uniforms.shimmer = fx.shimmer
        uniforms.saturation = fx.saturation
        uniforms.brightness = fx.brightness

        // 5. Render pipeline
        guard let commandBuffer = renderer.commandQueue.makeCommandBuffer() else { return }

        // Pass 1: Full-screen panel composition with crossfade.
        // Composite tint drifts from white toward the theme's energy tint —
        // cathedral drains toward dark, beach stays bright and warm.
        let et = theme.energyTint(at: audioState.corruptionIndex)
        let tint = SIMD4<Float>(et.x, et.y, et.z, 1.0)
        let currentPanelName = compositionEngine.currentPanelName
        let nextPanelName = compositionEngine.nextPanelName
        if let currentTex = assetLibrary.texture(named: currentPanelName),
           let nextTex = assetLibrary.texture(named: nextPanelName) {
            renderer.shaderPipeline.compositePanels(
                currentPanel: currentTex,
                nextPanel: nextTex,
                crossfade: compositionEngine.crossfade,
                tintColor: tint,
                commandBuffer: commandBuffer
            )
        }

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
        debugOverlay?.update(audioState: audioState, time: Double(time), theme: theme)

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
