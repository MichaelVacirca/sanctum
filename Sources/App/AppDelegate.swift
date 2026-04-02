import Cocoa
import Metal
import QuartzCore

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow!
    private var metalLayer: CAMetalLayer!
    private var renderer: MetalRenderer!
    private nonisolated(unsafe) var displayLink: CVDisplayLink?

    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            renderer = try MetalRenderer(canvasWidth: 3840, canvasHeight: 2160)
        } catch {
            NSLog("Failed to initialize Metal: \(error)")
            NSApp.terminate(nil)
            return
        }

        setupWindow()
        startDisplayLink()
        renderer.clearCanvas(color: MTLClearColor(red: 0.05, green: 0.02, blue: 0.15, alpha: 1.0))
    }

    private func setupWindow() {
        let screenFrame = NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 1920, height: 1080)

        window = NSWindow(
            contentRect: screenFrame,
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Sanctum"
        window.contentView = NSView(frame: screenFrame)

        metalLayer = CAMetalLayer()
        metalLayer.device = renderer.device
        metalLayer.pixelFormat = .bgra8Unorm
        metalLayer.framebufferOnly = true
        metalLayer.frame = window.contentView!.bounds
        metalLayer.contentsScale = window.backingScaleFactor
        metalLayer.drawableSize = CGSize(
            width: screenFrame.width * window.backingScaleFactor,
            height: screenFrame.height * window.backingScaleFactor
        )

        window.contentView!.layer = metalLayer
        window.contentView!.wantsLayer = true
        window.makeKeyAndOrderFront(nil)
    }

    private func startDisplayLink() {
        CVDisplayLinkCreateWithActiveCGDisplays(&displayLink)
        guard let displayLink else { return }

        let callback: CVDisplayLinkOutputCallback = { _, _, _, _, _, userInfo -> CVReturn in
            let appDelegate = Unmanaged<AppDelegate>.fromOpaque(userInfo!).takeUnretainedValue()
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    appDelegate.renderFrame()
                }
            }
            return kCVReturnSuccess
        }

        CVDisplayLinkSetOutputCallback(displayLink, callback,
            Unmanaged.passUnretained(self).toOpaque())
        CVDisplayLinkStart(displayLink)
    }

    private func renderFrame() {
        renderer.presentCanvas(to: metalLayer)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let displayLink {
            CVDisplayLinkStop(displayLink)
        }
    }
}
