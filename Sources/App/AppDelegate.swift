import Cocoa
import Metal
import QuartzCore

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    // Core modules
    private var renderer: MetalRenderer!
    private var audioCapture: AudioCapture!
    private var analysisEngine: AnalysisEngine!
    private var arcController: ArcController!
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
    // Smoothed audio values fed to the shader (kills per-frame flicker)
    private var smoothBands: (Float, Float, Float, Float) = (0, 0, 0, 0)
    private var beatEnv: Float = 0
    private var transientEnv: Float = 0

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
        arcController = ArcController(
            mode: ArcController.Mode(rawValue: config.arcMode) ?? .energy,
            startHour: ArcController.parseHour(config.scheduleStart, fallback: 21),
            endHour: ArcController.parseHour(config.scheduleEnd, fallback: 2),
            energyWindow: config.corruptionWindowHours * 3600
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
            case 15: // 'R' — roll the arc all the way back to the start (sunset)
                self?.arcController.reset()
                return nil
            case 17: // 'T' key — cycle visual theme
                self?.cycleTheme()
                return nil
            case 124: // → advance the arc (manual)
                self?.arcController.advance(by: 0.05)
                return nil
            case 123: // ← roll the arc back (manual)
                self?.arcController.advance(by: -0.05)
                return nil
            case 126: // ↑ advance faster (manual)
                self?.arcController.advance(by: 0.2)
                return nil
            case 125: // ↓ roll back faster (manual)
                self?.arcController.advance(by: -0.2)
                return nil
            case 0: // 'A' — resume automatic advance (schedule / energy)
                self?.arcController.resumeAuto()
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

        // 2. Advance the arc (energy / clock schedule / manual scrub)
        arcController.update(energy: audioState.overallEnergy, deltaTime: deltaTime)
        audioState.corruptionIndex = arcController.index

        // 3. Update composition (scene graph)
        compositionEngine.update(audioState: audioState, deltaTime: deltaTime)

        // Smooth the audio values feeding the shader so jumpy FFT/beat data
        // doesn't make the image flicker: bands lerp toward their targets, and
        // beat/transient become short decaying pulses instead of 1-frame flashes.
        let bandLerp: Float = 0.30
        smoothBands.0 += (audioState.subBass - smoothBands.0) * bandLerp
        smoothBands.1 += (audioState.bass    - smoothBands.1) * bandLerp
        smoothBands.2 += (audioState.mids    - smoothBands.2) * bandLerp
        smoothBands.3 += (audioState.highs   - smoothBands.3) * bandLerp
        beatEnv = max(beatEnv * 0.82, audioState.isBeat ? 1.0 : 0.0)
        transientEnv = max(transientEnv * 0.88, audioState.isTransient ? 1.0 : 0.0)

        // 4. Build audio uniforms for shaders
        var uniforms = AudioUniforms()
        uniforms.bands = smoothBands
        uniforms.bpm = audioState.bpm
        uniforms.beatPhase = audioState.beatPhase
        uniforms.corruptionIndex = audioState.corruptionIndex
        uniforms.time = time
        uniforms.isBeat = beatEnv
        uniforms.isTransient = transientEnv

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
        uniforms.flash = fx.flash
        uniforms.sunPos = (theme.sunPosition.x, theme.sunPosition.y)

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

        // Pass 1b: Overlay icons — draw each group with its own texture so the
        // drifting icons show their real art (not all sharing the first one).
        let iconNodes = compositionEngine.sceneGraph.allNodes(ofType: .icon)
        for (name, nodes) in Dictionary(grouping: iconNodes, by: { $0.textureName }) {
            if let iconTex = assetLibrary.texture(named: name) {
                renderer.shaderPipeline.compositeIcons(
                    iconNodes: nodes,
                    iconTexture: iconTex,
                    commandBuffer: commandBuffer
                )
            }
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
        let arcStatus = arcController.isManual
            ? "MANUAL  (A = resume auto)"
            : (config.arcMode == "schedule"
               ? "AUTO \(config.scheduleStart)→\(config.scheduleEnd)"
               : "AUTO energy")
        debugOverlay?.update(audioState: audioState, time: Double(time),
                             theme: theme, arc: arcStatus)

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
