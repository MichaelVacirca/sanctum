import Cocoa
import Metal
import QuartzCore

@MainActor
final class DisplayManager {
    private let renderer: MetalRenderer
    private let gridConfig: GridConfig
    private var windows: [NSWindow] = []
    private var metalLayers: [CAMetalLayer] = []
    private var singleDisplayMode = false

    init(renderer: MetalRenderer, gridConfig: GridConfig = .defaultConfig) {
        self.renderer = renderer
        self.gridConfig = gridConfig
    }

    func setup() {
        let screens = NSScreen.screens

        if screens.count < gridConfig.columns * gridConfig.rows {
            setupSingleDisplay(screen: screens[0])
            singleDisplayMode = true
        } else {
            setupMultiDisplay(screens: screens)
            singleDisplayMode = false
        }
    }

    private func setupSingleDisplay(screen: NSScreen) {
        let window = createFullscreenWindow(on: screen)
        window.level = .floating // Not .screenSaver — allows Cmd+Tab and escape
        window.isMovableByWindowBackground = true
        let layer = createMetalLayer(size: screen.frame.size, scale: screen.backingScaleFactor)
        window.contentView!.layer = layer
        window.contentView!.wantsLayer = true
        window.makeKeyAndOrderFront(nil)
        windows.append(window)
        metalLayers.append(layer)
    }

    private func setupMultiDisplay(screens: [NSScreen]) {
        let externalScreens = screens.count > 1 ? Array(screens[1...]) : screens

        for (i, _) in gridConfig.displays.enumerated() {
            guard i < externalScreens.count else { break }
            let screen = externalScreens[i]
            let window = createFullscreenWindow(on: screen)
            let layer = createMetalLayer(size: screen.frame.size, scale: screen.backingScaleFactor)
            window.contentView!.layer = layer
            window.contentView!.wantsLayer = true
            window.makeKeyAndOrderFront(nil)
            windows.append(window)
            metalLayers.append(layer)
        }
    }

    func present() {
        if singleDisplayMode {
            renderer.presentCanvas(to: metalLayers[0])
        } else {
            let quadWidth = renderer.canvasWidth / gridConfig.columns
            let quadHeight = renderer.canvasHeight / gridConfig.rows

            for (i, slot) in gridConfig.displays.enumerated() {
                guard i < metalLayers.count else { break }
                let originX = slot.column * quadWidth
                let originY = slot.row * quadHeight
                renderer.presentCanvasRegion(
                    to: metalLayers[i],
                    region: MTLRegionMake2D(originX, originY, quadWidth, quadHeight)
                )
            }
        }
    }

    private func createFullscreenWindow(on screen: NSScreen) -> NSWindow {
        let window = NSWindow(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false,
            screen: screen
        )
        window.level = .screenSaver
        window.contentView = NSView(frame: screen.frame)
        window.collectionBehavior = [.fullScreenPrimary, .canJoinAllSpaces]
        return window
    }

    private func createMetalLayer(size: CGSize, scale: CGFloat) -> CAMetalLayer {
        let layer = CAMetalLayer()
        layer.device = renderer.device
        layer.pixelFormat = .bgra8Unorm
        layer.framebufferOnly = true
        layer.frame = CGRect(origin: .zero, size: size)
        layer.contentsScale = scale
        layer.drawableSize = CGSize(width: size.width * scale, height: size.height * scale)
        return layer
    }

    func teardown() {
        windows.forEach { $0.close() }
        windows.removeAll()
        metalLayers.removeAll()
    }
}
